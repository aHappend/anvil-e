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
    localparam IDLE=6'd0, SERIES=6'd1, ROOT=6'd2, FINISH=6'd3, HOLD=6'd4,
        DIV_START=6'd5, DIV_WAIT=6'd6, GELU_APPLY=6'd7,
        SERIES_WAIT=6'd8, DISPATCH=6'd9, GELU_SQUARE=6'd10,
        GELU_SQUARE_ROUND=6'd11, GELU_CUBE=6'd12,
        GELU_CUBE_ROUND=6'd13, GELU_SCALE=6'd14,
        GELU_SCALE_ROUND=6'd15, GELU_ADD=6'd16,
        GELU_COEFFICIENT=6'd17, GELU_COEFFICIENT_ROUND=6'd18,
        GELU_EXP_ARGUMENT=6'd19, EXP_CLAMP=6'd20,
        RANGE_PREPARE=6'd21, RANGE_START=6'd22, RANGE_WAIT=6'd23,
        RANGE_APPLY=6'd24, TRIG_WRAP=6'd25, TRIG_INIT=6'd26,
        GELU_FINAL_PRODUCT=6'd27, GELU_FINAL_ROUND=6'd28,
        GELU_FINAL_HALF=6'd29;
    localparam EXP=3'd0, SIN=3'd1, COS=3'd2, RECIP=3'd3,
               RSQRT=3'd4, GELU=3'd5;
    localparam signed [95:0] ONE=96'sd1099511627776;
    localparam signed [95:0] LN2=96'sd762123384786;
    localparam signed [95:0] PI=96'sd3454217652358;
    localparam signed [95:0] TWO_PI=96'sd6908435304715;
    localparam signed [95:0] GELU_C=96'sd877283352226;
    localparam signed [95:0] GELU_K=96'sd49164662436;
    reg [5:0] state;
    reg [2:0] operation;
    reg signed [95:0] argument, reduced, term, total;
    reg signed [95:0] temporary, gelu_factor;
    reg signed [127:0] product;
    wire signed [95:0] exponential=total >>> -exponent_shift;
    reg signed [95:0] tanh_value;
    reg signed [95:0] exponent_shift;
    reg [6:0] iteration;
    reg [127:0] radicand;
    reg [129:0] remainder;
    wire [129:0] shifted_remainder=(remainder<<2)|{128'd0,radicand[127:126]};
    wire [129:0] trial=({66'd0,root_value}<<2)|130'd1;
    reg [63:0] root_value;
    reg signed [47:0] result;
    reg error;
    wire signed [63:0] series_term, series_total;
    wire [6:0] series_iteration;
    wire series_ready, series_valid, series_finished, series_error;
    anvil_e2_series series (
        .clk(clk), .rst_n(rst_n),
        .enable(state==SERIES), .operation(operation),
        .in_ready(series_ready), .out_valid(series_valid),
        .out_ready(state==SERIES_WAIT), .out_error(series_error),
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

    function automatic signed [95:0] round_product;
        input signed [127:0] value;
        reg signed [127:0] floor_value;
        begin
            floor_value = value >>> 40;
            if ((value[39:0] > 40'h8000000000) ||
                (value[39:0] == 40'h8000000000 && floor_value[0]))
                floor_value = floor_value + 128'sd1;
            round_product = floor_value[95:0];
        end
    endfunction

    function automatic signed [95:0] half_even(input signed [95:0] x);
        reg signed [95:0] q;
        begin
            q=x>>>1;
            half_even=q+96'(x[0] && q[0]);
        end
    endfunction

    reg [63:0] range_numerator, range_denominator;
    reg [63:0] range_quotient, range_remainder;
    wire [63:0] range_q, range_r;
    wire range_ready, range_valid, range_error;
    wire trig_operation=operation==SIN || operation==COS;
    anvil_e3_unsigned_divide #(.WIDTH(64)) range_divider (
        .clk(clk), .rst_n(rst_n), .in_valid(state==RANGE_START),
        .in_ready(range_ready), .in_numerator(range_numerator),
        .in_denominator(range_denominator), .out_valid(range_valid),
        .out_ready(state==RANGE_WAIT), .out_quotient(range_q),
        .out_remainder(range_r), .out_error(range_error)
    );

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
            tanh_value <= 0;
            divide_numerator <= 0;
            divide_denominator <= 0;
            temporary <= 0;
            gelu_factor <= 0;
            product <= 0;
            range_numerator <= 0;
            range_denominator <= 0;
            range_quotient <= 0;
            range_remainder <= 0;
        end else begin
            case (state)
                IDLE: if (in_valid) begin
                    operation <= in_op;
                    argument <= {{48{in_data[47]}}, in_data};
                    error <= 0;
                    result <= 0;
                    iteration <= 1;
                    state <= DISPATCH;
                end
                DISPATCH: begin
                    if (operation == RECIP) begin
                        if (argument == 0) begin
                            error <= 1;
                            state <= HOLD;
                        end else begin
                            divide_numerator <= argument[95] ?
                                -128'sd1208925819614629174706176:
                                128'sd1208925819614629174706176;
                            divide_denominator <= argument[95] ?
                                -$signed({{32{argument[95]}},argument}):
                                $signed({{32{argument[95]}},argument});
                            state <= DIV_START;
                        end
                    end else if (operation == RSQRT) begin
                        if (argument <= 0) begin
                            error <= 1;
                            state <= HOLD;
                        end else begin
                            radicand <= {80'd0, argument[47:0]} << 56;
                            root_value <= 0;
                            remainder <= 0;
                            iteration <= 0;
                            state <= ROOT;
                        end
                    end else if ((operation == SIN || operation == COS ||
                                  operation == EXP || operation == GELU) &&
                                 argument == 0) begin
                        result <= (operation == COS || operation == EXP) ?
                            48'sd1099511627776 : 48'sd0;
                        state <= HOLD;
                    end else if (trig_operation) begin
                        temporary <= argument;
                        state <= RANGE_PREPARE;
                    end else if (operation == EXP || operation == GELU) begin
                        if (operation == GELU) begin
                            if (argument >= 96'sd8796093022208) begin
                                result <= argument[47:0];
                                state <= HOLD;
                            end else if (argument <= -96'sd8796093022208) begin
                                result <= 0;
                                state <= HOLD;
                            end else begin
                                state <= GELU_SQUARE;
                            end
                        end else if (argument > 0) begin
                            error <= 1;
                            state <= HOLD;
                        end else begin
                            temporary <= argument;
                            state <= EXP_CLAMP;
                        end
                    end else begin
                        error <= 1;
                        state <= HOLD;
                    end
                end
                GELU_SQUARE: begin
                    product <= $signed(argument[63:0])*$signed(argument[63:0]);
                    state <= GELU_SQUARE_ROUND;
                end
                GELU_SQUARE_ROUND: begin
                    gelu_factor <= round_product(product);
                    state <= GELU_CUBE;
                end
                GELU_CUBE: begin
                    product <= $signed(gelu_factor[63:0])*$signed(argument[63:0]);
                    state <= GELU_CUBE_ROUND;
                end
                GELU_CUBE_ROUND: begin
                    gelu_factor <= round_product(product);
                    state <= GELU_SCALE;
                end
                GELU_SCALE: begin
                    product <= $signed(GELU_K[63:0])*$signed(gelu_factor[63:0]);
                    state <= GELU_SCALE_ROUND;
                end
                GELU_SCALE_ROUND: begin
                    gelu_factor <= round_product(product);
                    state <= GELU_ADD;
                end
                GELU_ADD: begin
                    gelu_factor <= argument+gelu_factor;
                    state <= GELU_COEFFICIENT;
                end
                GELU_COEFFICIENT: begin
                    product <= $signed(GELU_C[63:0])*$signed(gelu_factor[63:0]);
                    state <= GELU_COEFFICIENT_ROUND;
                end
                GELU_COEFFICIENT_ROUND: begin
                    gelu_factor <= round_product(product);
                    state <= GELU_EXP_ARGUMENT;
                end
                GELU_EXP_ARGUMENT: begin
                    temporary <= gelu_factor<0 ? gelu_factor<<<1:-(gelu_factor<<<1);
                    state <= EXP_CLAMP;
                end
                EXP_CLAMP: begin
                    if (temporary < -96'sd17592186044416)
                        temporary <= -96'sd17592186044416;
                    state <= RANGE_PREPARE;
                end
                RANGE_PREPARE: begin
                    range_numerator <= temporary[63] ?
                        -$unsigned(temporary[63:0]):$unsigned(temporary[63:0]);
                    range_denominator <= trig_operation ?
                        64'd6908435304715:64'd762123384786;
                    state <= RANGE_START;
                end
                RANGE_START: if (range_ready) state <= RANGE_WAIT;
                RANGE_WAIT: if (range_valid) begin
                    if (range_error) begin
                        error <= 1;
                        result <= 0;
                        state <= HOLD;
                    end else begin
                        range_quotient <= range_q;
                        range_remainder <= range_r;
                        state <= RANGE_APPLY;
                    end
                end
                RANGE_APPLY: begin
                    if (trig_operation) begin
                        reduced <= temporary[63] ?
                            -$signed({32'd0,range_remainder}):
                            $signed({32'd0,range_remainder});
                        state <= TRIG_WRAP;
                    end else begin
                        // Negative exponential reduction floors, not truncates.
                        exponent_shift <= temporary[63] ?
                            -$signed({32'd0,range_quotient})-
                                96'(range_remainder!=0):
                            $signed({32'd0,range_quotient});
                        reduced <= temporary[63] && range_remainder!=0 ?
                            LN2-$signed({32'd0,range_remainder}):
                            $signed({32'd0,range_remainder});
                        term <= ONE;
                        total <= ONE;
                        state <= SERIES;
                    end
                end
                TRIG_WRAP: begin
                    if (reduced>PI) reduced <= reduced-TWO_PI;
                    else if (reduced< -PI) reduced <= reduced+TWO_PI;
                    state <= TRIG_INIT;
                end
                TRIG_INIT: begin
                    term <= operation==SIN ? reduced:ONE;
                    total <= operation==SIN ? reduced:ONE;
                    state <= SERIES;
                end
                SERIES: if (series_ready) state <= SERIES_WAIT;
                SERIES_WAIT: if (series_valid) begin
                    if (series_error) begin
                        error <= 1;
                        result <= 0;
                        state <= HOLD;
                    end else begin
                        term <= series_term;
                        total <= series_total;
                        iteration <= series_iteration;
                        if (series_finished) state <= FINISH;
                        else state <= SERIES;
                    end
                end
                ROOT: begin
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
                    gelu_factor <= ONE+(argument<0 ? -tanh_value:tanh_value);
                    state <= GELU_FINAL_PRODUCT;
                end
                GELU_FINAL_PRODUCT: begin
                    product <= $signed(argument[63:0])*$signed(gelu_factor[63:0]);
                    state <= GELU_FINAL_ROUND;
                end
                GELU_FINAL_ROUND: begin
                    gelu_factor <= round_product(product);
                    state <= GELU_FINAL_HALF;
                end
                GELU_FINAL_HALF: begin
                    result <= saturate(half_even(gelu_factor));
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
