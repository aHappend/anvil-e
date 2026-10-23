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
        DIV_START=4'd5, DIV_WAIT=4'd6, GELU_APPLY=4'd7,
        REDUCE_START=4'd8, REDUCE_WAIT=4'd9,
        GELU_1=4'd10, GELU_2=4'd11, GELU_3=4'd12, GELU_4=4'd13,
        GELU_5=4'd14, GELU_DONE=4'd15;
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
    reg signed [95:0] tanh_value, gelu_work, gelu_prod_reg;
    reg signed [95:0] exponent_shift;
    reg [6:0] iteration;
    reg [127:0] radicand;
    reg [129:0] remainder;
    reg [63:0] root_value;
    reg signed [47:0] result;
    reg error;
    wire signed [63:0] series_term, series_total;
    wire [6:0] series_iteration;
    wire series_finished, series_valid, series_error;
    anvil_e2_series series (
        .clk(clk), .rst_n(rst_n),
        .enable(state==SERIES), .operation(operation),
        .reduced(reduced[63:0]), .term(term[63:0]), .total(total[63:0]),
        .iteration(iteration), .next_term(series_term), .next_total(series_total),
        .next_iteration(series_iteration), .finished(series_finished),
        .step_valid(series_valid), .step_error(series_error)
    );
    reg signed [127:0] divide_numerator;
    reg [127:0] divide_denominator;
    wire divide_ready, divide_valid, divide_error;
    wire signed [127:0] divide_data;
    wire signed [127:0] divide_quotient, divide_remainder;
    anvil_e2_divide divider (
        .clk(clk), .rst_n(rst_n),
        .in_valid(state==DIV_START || state==REDUCE_START),
        .in_ready(divide_ready), .in_numerator(divide_numerator),
        .in_denominator(divide_denominator), .out_valid(divide_valid),
        .out_ready(state==DIV_WAIT || state==REDUCE_WAIT), .out_data(divide_data),
        .out_error(divide_error), .out_quotient(divide_quotient),
        .out_remainder(divide_remainder)
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
    wire signed [95:0] input_value={{48{in_data[47]}},in_data};
    wire signed [95:0] exp_only_bounded=input_value< -96'sd17592186044416 ?
        -96'sd17592186044416:input_value;
    wire signed [95:0] gelu_exp_arg=gelu_work<0 ? gelu_work*96'sd2:-gelu_work*96'sd2;
    wire signed [95:0] gelu_bounded=gelu_exp_arg< -96'sd17592186044416 ?
        -96'sd17592186044416:gelu_exp_arg;
    wire signed [95:0] trig_remainder=divide_remainder[95:0];
    wire signed [95:0] trig_reduced=trig_remainder>PI ? trig_remainder-TWO_PI:
        trig_remainder< -PI ? trig_remainder+TWO_PI:trig_remainder;
    wire signed [95:0] floor_quotient=divide_remainder<0 ?
        divide_quotient[95:0]-96'sd1:divide_quotient[95:0];
    wire [129:0] shifted_remainder=(remainder<<2)|{128'd0,radicand[127:126]};
    wire [129:0] trial=({66'd0,root_value}<<2)|130'd1;
    wire signed [95:0] exponential=total>>>-exponent_shift;
    wire signed [95:0] signed_tanh=argument<0 ? -tanh_value:tanh_value;
    wire signed [95:0] gelu_product=multiply_q40(argument,ONE+signed_tanh);
    wire signed [95:0] gelu_half=(gelu_prod_reg>>>1)+
        (gelu_prod_reg[0] && gelu_prod_reg[1] ? 96'sd1:96'sd0);

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
            gelu_work <= 0;
            gelu_prod_reg <= 0;
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
                        divide_numerator <= {{80{in_data[47]}},in_data};
                        divide_denominator <= 128'd6908435304715;
                        state <= REDUCE_START;
                    end else if (in_op == EXP) begin
                        if (in_data > 0) begin
                            error <= 1;
                            state <= HOLD;
                        end else begin
                            divide_numerator <= {{32{exp_only_bounded[95]}},exp_only_bounded};
                            divide_denominator <= 128'd762123384786;
                            state <= REDUCE_START;
                        end
                    end else if (in_op == GELU) begin
                        if (in_data >= 48'sd8796093022208) begin
                            result <= in_data;
                            state <= HOLD;
                        end else if (in_data <= -48'sd8796093022208) begin
                            result <= 0;
                            state <= HOLD;
                        end else begin
                            gelu_work <= {{48{in_data[47]}}, in_data};
                            state <= GELU_1;
                        end
                    end else begin
                        error <= 1;
                        state <= HOLD;
                    end
                end
                GELU_1: begin
                    gelu_work <= multiply_q40(argument, argument);
                    state <= GELU_2;
                end
                GELU_2: begin
                    gelu_work <= multiply_q40(gelu_work, argument);
                    state <= GELU_3;
                end
                GELU_3: begin
                    gelu_work <= argument + multiply_q40(GELU_K, gelu_work);
                    state <= GELU_4;
                end
                GELU_4: begin
                    gelu_work <= multiply_q40(GELU_C, gelu_work);
                    state <= GELU_5;
                end
                GELU_5: begin
                    divide_numerator <= {{32{gelu_bounded[95]}},gelu_bounded};
                    divide_denominator <= 128'd762123384786;
                    state <= REDUCE_START;
                end
                REDUCE_START: if (divide_ready) state <= REDUCE_WAIT;
                REDUCE_WAIT: if (divide_valid) begin
                    if (divide_error) begin error<=1; result<=0; state<=HOLD; end
                    else begin
                        if (operation==SIN || operation==COS) begin
                            reduced<=trig_reduced;
                            term<=operation==SIN ? trig_reduced:ONE;
                            total<=operation==SIN ? trig_reduced:ONE;
                        end else begin
                            exponent_shift<=floor_quotient;
                            reduced<=divide_remainder<0 ?
                                divide_remainder[95:0]+LN2:divide_remainder[95:0];
                            term<=ONE; total<=ONE;
                        end
                        state<=SERIES;
                    end
                end
                SERIES: if (series_valid) begin
                    term <= series_term;
                    total <= series_total;
                    iteration <= series_iteration;
                    if (series_error) begin error<=1; result<=0; state<=HOLD; end
                    else if (series_finished) state <= FINISH;
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
                    gelu_prod_reg <= gelu_product;
                    state <= GELU_DONE;
                end
                GELU_DONE: begin
                    result <= saturate(gelu_half);
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
