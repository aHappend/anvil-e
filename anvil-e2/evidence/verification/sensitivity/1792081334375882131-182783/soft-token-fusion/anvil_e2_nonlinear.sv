module anvil_e2_nonlinear (
    input wire clk,
    input wire rst_n,
    input wire in_valid,
    output wire in_ready,
    input wire [2:0] in_op,
    input wire signed [47:0] in_data,
    output wire out_valid,
    input wire out_ready,
    output wire signed [47:0] out_data,
    output wire out_error
);
    localparam IDLE=4'd0, SERIES=4'd1, ROOT=4'd2, FINISH=4'd3, HOLD=4'd4,
        DIV_START=4'd5, DIV_WAIT=4'd6, GELU_APPLY=4'd7;
    localparam EXP=3'd0, SIN=3'd1, COS=3'd2, RECIP=3'd3,
               RSQRT=3'd4, GELU=3'd5;
    localparam signed [95:0] ONE=96'sd1099511627776;
    localparam signed [95:0] LN2=96'sd762123384786;
    localparam signed [95:0] PI=96'sd3454217652358;
    localparam signed [95:0] TWO_PI=96'sd6908435304715;
    localparam signed [95:0] GELU_C=96'sd877283352226;
    localparam signed [95:0] GELU_K=96'sd49164662436;
    reg [3:0] state;
    reg [2:0] operation;
    reg signed [95:0] argument, reduced, term, total;
    reg signed [95:0] temporary, quotient, exponential, tanh_value;
    reg signed [95:0] exponent_shift;
    reg signed [63:0] reduction_quotient, reduction_remainder;
    reg [6:0] iteration;
    reg [127:0] radicand;
    reg [129:0] remainder, shifted_remainder, trial;
    reg [63:0] root_value;
    reg signed [47:0] result;
    reg error;
    wire signed [63:0] series_term, series_total;
    wire [6:0] series_iteration;
    wire series_finished;
    anvil_e2_series series (
        .enable(state==SERIES), .operation(operation),
        .reduced(reduced[63:0]), .term(term[63:0]), .total(total[63:0]),
        .iteration(iteration), .next_term(series_term), .next_total(series_total),
        .next_iteration(series_iteration), .finished(series_finished)
    );
    reg signed [127:0] divide_numerator;
    reg [127:0] divide_denominator;
    wire divide_ready, divide_valid, divide_error;
    wire signed [127:0] divide_data;
    anvil_e2_divide divider (
        .clk(clk), .rst_n(rst_n), .in_valid(state==DIV_START),
        .in_ready(divide_ready), .in_numerator(divide_numerator),
        .in_denominator(divide_denominator), .out_valid(divide_valid),
        .out_ready(state==DIV_WAIT), .out_data(divide_data),
        .out_error(divide_error)
    );

    function automatic signed [95:0] multiply_q40;
        input signed [95:0] a, b;
        reg signed [63:0] narrow_a, narrow_b;
        reg signed [127:0] product, floor_value;
        begin
            // All call sites are bounded below 1024*G, including GELU's cube.
            narrow_a = a[63:0];
            narrow_b = b[63:0];
            product = narrow_a * narrow_b;
            floor_value = product >>> 40;
            if ((product[39:0] > 40'h8000000000) ||
                (product[39:0] == 40'h8000000000 && floor_value[0]))
                floor_value = floor_value + 128'sd1;
            multiply_q40 = floor_value[95:0];
        end
    endfunction

    function automatic signed [95:0] series_divide;
        input signed [95:0] numerator;
        input [11:0] denominator;
        reg [63:0] magnitude, divisor, q, r;
        begin
            // Series numerators are bounded by 64*G, well below 2^64.
            magnitude = numerator < 0 ? -numerator : numerator;
            divisor = {52'd0,denominator};
            q = magnitude / divisor;
            r = magnitude - q*divisor;
            if (r > divisor-r || (r == divisor-r && q[0]))
                q = q + 64'd1;
            series_divide = numerator < 0 ? -$signed({32'd0,q}):$signed({32'd0,q});
        end
    endfunction

    function automatic signed [47:0] saturate;
        input signed [95:0] x;
        begin
            if (x > 96'sd140737488289792) saturate = 48'sh7fffffff0000;
            else if (x < -96'sd140737488355328) saturate = 48'sh800000000000;
            else saturate = x[47:0];
        end
    endfunction

    assign in_ready = rst_n && state == IDLE;
    assign out_valid = rst_n && state == HOLD;
    assign out_data = rst_n ? result : 48'sd0;
    assign out_error = rst_n && error;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            operation <= EXP;
            argument <= 0;
            reduced <= 0;
            term <= 0;
            total <= 0;
            exponent_shift <= 0;
            iteration <= 0;
            radicand <= 0;
            remainder <= 0;
            root_value <= 0;
            result <= 0;
            error <= 0;
            temporary = 0;
            quotient = 0;
            exponential = 0;
            tanh_value = 0;
            shifted_remainder = 0;
            trial = 0;
            reduction_quotient = 0;
            reduction_remainder = 0;
            divide_numerator <= 0;
            divide_denominator <= 0;
        end else begin
            case (state)
                IDLE: if (in_valid) begin
                    operation <= in_op;
                    argument <= {{48{in_data[47]}}, in_data};
                    error <= 0;
                    result <= 0;
                    iteration <= 1;
                    if (in_op == RECIP) begin
                        if (in_data == 0) begin
                            error <= 1;
                            state <= HOLD;
                        end else begin
                            divide_numerator <= in_data[47] ?
                                -128'sd1208925819614629174706176:
                                128'sd1208925819614629174706176;
                            divide_denominator <= in_data[47] ?
                                -$signed({{80{in_data[47]}},in_data}):
                                $signed({{80{in_data[47]}},in_data});
                            state <= DIV_START;
                        end
                    end else if (in_op == RSQRT) begin
                        if (in_data <= 0) begin
                            error <= 1;
                            state <= HOLD;
                        end else begin
                            radicand <= {80'd0, in_data} << 56;
                            root_value <= 0;
                            remainder <= 0;
                            iteration <= 0;
                            state <= ROOT;
                        end
                    end else if ((in_op == SIN || in_op == COS || in_op == EXP ||
                                  in_op == GELU) && in_data == 0) begin
                        result <= (in_op == COS || in_op == EXP) ?
                            48'sd1099511627776 : 48'sd0;
                        state <= HOLD;
                    end else if (in_op == SIN || in_op == COS) begin
                        reduction_remainder = $signed(in_data) % 64'sd6908435304715;
                        temporary = reduction_remainder;
                        if (temporary > PI) temporary = temporary - TWO_PI;
                        if (temporary < -PI) temporary = temporary + TWO_PI;
                        reduced <= temporary;
                        term <= in_op == SIN ? temporary : ONE;
                        total <= in_op == SIN ? temporary : ONE;
                        state <= SERIES;
                    end else if (in_op == EXP || in_op == GELU) begin
                        temporary = {{48{in_data[47]}}, in_data};
                        if (in_op == GELU) begin
                            if (in_data >= 48'sd8796093022208) begin
                                result <= in_data;
                                state <= HOLD;
                            end else if (in_data <= -48'sd8796093022208) begin
                                result <= 0;
                                state <= HOLD;
                            end else begin
                                temporary = multiply_q40(GELU_C,
                                    temporary + multiply_q40(GELU_K,
                                    multiply_q40(multiply_q40(temporary,temporary),temporary)));
                                temporary = temporary < 0 ? temporary*96'sd2 : -temporary*96'sd2;
                                state <= SERIES;
                            end
                        end else if (in_data > 0) begin
                            error <= 1;
                            state <= HOLD;
                        end else begin
                            state <= SERIES;
                        end
                        if ((in_op == EXP && in_data <= 0) ||
                            (in_op == GELU && in_data > -48'sd8796093022208 &&
                             in_data < 48'sd8796093022208)) begin
                            if (temporary < -96'sd17592186044416)
                                temporary = -96'sd17592186044416;
                            reduction_quotient = $signed(temporary[63:0]) /
                                64'sd762123384786;
                            reduction_remainder = $signed(temporary[63:0]) -
                                reduction_quotient*64'sd762123384786;
                            quotient = reduction_quotient;
                            if (reduction_remainder < 0) quotient = quotient - 96'sd1;
                            exponent_shift <= quotient;
                            reduced <= temporary - quotient*LN2;
                            term <= ONE;
                            total <= ONE;
                        end
                    end else begin
                        error <= 1;
                        state <= HOLD;
                    end
                end
                SERIES: begin
                    term <= series_term;
                    total <= series_total;
                    iteration <= series_iteration;
                    if (series_finished) state <= FINISH;
                end
                ROOT: begin
                    shifted_remainder = (remainder << 2) | {128'd0,radicand[127:126]};
                    trial = ({66'd0,root_value} << 2) | 130'd1;
                    if (shifted_remainder >= trial) begin
                        remainder <= shifted_remainder - trial;
                        root_value <= (root_value << 1) | 64'd1;
                    end else begin
                        remainder <= shifted_remainder;
                        root_value <= root_value << 1;
                    end
                    radicand <= radicand << 2;
                    if (iteration == 63) state <= FINISH;
                    else iteration <= iteration + 1'b1;
                end
                FINISH: begin
                    if (operation == RSQRT) begin
                        divide_numerator <= 128'sd309485009821345068724781056;
                        divide_denominator <= {64'd0,root_value};
                        state <= DIV_START;
                    end else if (operation == SIN || operation == COS) begin
                        result <= saturate(total);
                        state <= HOLD;
                    end else begin
                        exponential = total >>> -exponent_shift;
                        if (operation == EXP) begin
                            result <= saturate(exponential);
                            state <= HOLD;
                        end else begin
                            divide_numerator <= $signed(ONE-exponential) <<< 40;
                            divide_denominator <= ONE+exponential;
                            state <= DIV_START;
                        end
                    end
                end
                DIV_START: if (divide_ready) state <= DIV_WAIT;
                DIV_WAIT: if (divide_valid) begin
                    if (divide_error) begin
                        error <= 1;
                        result <= 0;
                        state <= HOLD;
                    end else if (operation == GELU) begin
                        tanh_value <= divide_data[95:0];
                        state <= GELU_APPLY;
                    end else begin
                        result <= saturate(divide_data[95:0]);
                        state <= HOLD;
                    end
                end
                GELU_APPLY: begin
                    temporary = argument < 0 ? -tanh_value:tanh_value;
                    result <= saturate(series_divide(
                        multiply_q40(argument,ONE+temporary),12'd2));
                    state <= HOLD;
                end
                HOLD: if (out_ready) state <= IDLE;
                default: begin
                    error <= 1;
                    result <= 0;
                    state <= HOLD;
                end
            endcase
        end
    end
endmodule
