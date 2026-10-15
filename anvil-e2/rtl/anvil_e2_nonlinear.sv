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
    localparam IDLE=3'd0, SERIES=3'd1, ROOT=3'd2, FINISH=3'd3, HOLD=3'd4;
    localparam EXP=3'd0, SIN=3'd1, COS=3'd2, RECIP=3'd3,
               RSQRT=3'd4, GELU=3'd5;
    localparam signed [95:0] ONE=96'sd1099511627776;
    localparam signed [95:0] LN2=96'sd762123384786;
    localparam signed [95:0] PI=96'sd3454217652358;
    localparam signed [95:0] TWO_PI=96'sd6908435304715;
    localparam signed [95:0] GELU_C=96'sd877283352226;
    localparam signed [95:0] GELU_K=96'sd49164662436;
    reg [2:0] state, operation;
    reg signed [95:0] argument, reduced, term, total;
    reg signed [95:0] temporary, quotient, exponential, tanh_value;
    reg signed [95:0] exponent_shift;
    reg [6:0] iteration;
    reg [127:0] radicand;
    reg [129:0] remainder, shifted_remainder, trial;
    reg [63:0] root_value;
    reg signed [47:0] result;
    reg error;

    function automatic signed [95:0] multiply_q40;
        input signed [95:0] a, b;
        reg signed [191:0] product, floor_value;
        begin
            product = a * b;
            floor_value = product >>> 40;
            if ((product[39:0] > 40'h8000000000) ||
                (product[39:0] == 40'h8000000000 && floor_value[0]))
                floor_value = floor_value + 192'sd1;
            multiply_q40 = floor_value[95:0];
        end
    endfunction

    function automatic signed [95:0] divide_round;
        input signed [95:0] numerator, denominator;
        reg signed [95:0] magnitude, divisor, q, r;
        begin
            magnitude = numerator < 0 ? -numerator : numerator;
            divisor = denominator < 0 ? -denominator : denominator;
            q = magnitude / divisor;
            r = magnitude % divisor;
            if (r > divisor-r || (r == divisor-r && q[0]))
                q = q + 96'sd1;
            divide_round = (numerator < 0) != (denominator < 0) ? -q : q;
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
                        end else begin
                            result <= saturate(divide_round(96'sd1208925819614629174706176,
                                        {{48{in_data[47]}}, in_data}));
                        end
                        state <= HOLD;
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
                    end else if (in_op == SIN || in_op == COS) begin
                        temporary = $signed({{48{in_data[47]}}, in_data}) % TWO_PI;
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
                            quotient = temporary / LN2;
                            if (temporary % LN2 < 0) quotient = quotient - 96'sd1;
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
                    if (operation == SIN) begin
                        temporary = -multiply_q40(multiply_q40(term,reduced),reduced);
                        temporary = divide_round(temporary,
                            96'sd2*iteration*(96'sd2*iteration+96'sd1));
                    end else if (operation == COS) begin
                        temporary = -multiply_q40(multiply_q40(term,reduced),reduced);
                        temporary = divide_round(temporary,
                            (96'sd2*iteration-96'sd1)*(96'sd2*iteration));
                    end else begin
                        temporary = divide_round(multiply_q40(term,reduced),
                            {89'd0,iteration});
                    end
                    term <= temporary;
                    total <= total + temporary;
                    if (iteration == 18)
                        state <= FINISH;
                    else
                        iteration <= iteration + 1'b1;
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
                        result <= saturate(divide_round(96'sd309485009821345068724781056,
                            {32'd0,root_value}));
                    end else if (operation == SIN || operation == COS) begin
                        result <= saturate(total);
                    end else begin
                        exponential = total >>> -exponent_shift;
                        if (operation == EXP) begin
                            result <= saturate(exponential);
                        end else begin
                            tanh_value = divide_round((ONE-exponential) <<< 40,
                                                     ONE+exponential);
                            if (argument < 0) tanh_value = -tanh_value;
                            result <= saturate(divide_round(
                                multiply_q40(argument,ONE+tanh_value),96'sd2));
                        end
                    end
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
