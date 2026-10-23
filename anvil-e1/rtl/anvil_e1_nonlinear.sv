module anvil_e1_nonlinear (
    input wire clk,
    input wire rst_n,
    input wire in_valid,
    output wire in_ready,
    input wire [2:0] in_op,
    input wire signed [31:0] in_data,
    output wire out_valid,
    input wire out_ready,
    output wire signed [31:0] out_data,
    output wire out_error
);
    localparam IDLE=0, SERIES=1, ROOT=2, FINISH=3, HOLD=4,
        DIVIDE=5, RANGE_SAVE=6, ANGLE_SAVE=7, SERIES_SAVE=8,
        RECIP_SAVE=9, RSQRT_SAVE=10, TANH_SAVE=11,
        DIV_DONE=12, GELU_1=13, GELU_2=14, GELU_3=15, GELU_4=16,
        GELU_5=17, EXP_START=18, SERIES_2=19, SERIES_DIV=20,
        FINISH_EXP=21, TANH_DONE=22;
    localparam EXP=3'd0, SIN=3'd1, COS=3'd2, RECIP=3'd3,
               RSQRT=3'd4, GELU=3'd5;
    localparam signed [95:0] ONE=96'sd1099511627776;
    localparam signed [95:0] LN2=96'sd762123384786;
    localparam signed [95:0] PI=96'sd3454217652358;
    localparam signed [95:0] TWO_PI=96'sd6908435304715;
    localparam signed [95:0] GELU_C=96'sd877283352226;
    localparam signed [95:0] GELU_K=96'sd49164662436;
    reg [4:0] state;
    reg [2:0] operation;
    reg signed [95:0] argument, reduced, term, total, exponent_shift;
    reg signed [95:0] gelu_tmp, series_num_reg, series_div_reg, exp_reg, tanh_prod_reg;
    reg signed [95:0] div_result_reg, div_floor_reg, div_rem_reg;
    reg [5:0] iteration;
    reg [95:0] radicand;
    reg [97:0] remainder;
    reg [47:0] root_value;
    reg signed [31:0] result;
    reg error;

    reg [95:0] div_quotient, div_divisor;
    reg [96:0] div_remainder;
    reg div_negative, div_dividend_negative;
    reg [5:0] div_iteration;
    reg [4:0] div_return;
    reg [95:0] div_next_quotient;
    reg [96:0] div_next_remainder;
    integer div_bit;
    always @* begin
        div_next_quotient=div_quotient;
        div_next_remainder=div_remainder;
        if (state==DIVIDE) begin
            for (div_bit=0; div_bit<3; div_bit=div_bit+1) begin
                div_next_remainder={div_next_remainder[95:0],div_next_quotient[95]};
                div_next_quotient=div_next_quotient<<1;
                if (div_next_remainder>={1'b0,div_divisor}) begin
                    div_next_remainder=div_next_remainder-{1'b0,div_divisor};
                    div_next_quotient[0]=1'b1;
                end
            end
        end
    end
    wire [95:0] div_rounded_magnitude=div_quotient+
        ((div_remainder>{1'b0,div_divisor}-div_remainder ||
          (div_remainder=={1'b0,div_divisor}-div_remainder && div_quotient[0]))
         ? 96'd1:96'd0);
    wire signed [95:0] div_result=div_negative ?
        -$signed(div_rounded_magnitude):$signed(div_rounded_magnitude);
    wire signed [95:0] div_floor=div_negative ?
        -$signed(div_quotient)-(div_remainder!=0 ? 96'sd1:96'sd0):
        $signed(div_quotient);
    wire signed [95:0] div_signed_remainder=div_dividend_negative ?
        -$signed(div_remainder[95:0]):$signed(div_remainder[95:0]);
    task automatic begin_divide;
        input signed [95:0] numerator, denominator;
        input [4:0] next_state;
        begin
            div_quotient<=numerator<0 ? -numerator:numerator;
            div_divisor<=denominator<0 ? -denominator:denominator;
            div_remainder<=0; div_iteration<=0;
            div_negative<=(numerator<0)!=(denominator<0);
            div_dividend_negative<=numerator<0;
            div_return<=next_state; state<=DIVIDE;
        end
    endtask

    function automatic signed [95:0] multiply_q40;
        input signed [95:0] a, b;
        reg signed [191:0] product, floor_value;
        begin
            product=a*b;
            floor_value=product>>>40;
            if (product[39:0]>40'h8000000000 ||
                (product[39:0]==40'h8000000000 && floor_value[0]))
                floor_value=floor_value+192'sd1;
            multiply_q40=floor_value[95:0];
        end
    endfunction
    function automatic signed [95:0] half_round;
        input signed [95:0] value;
        reg signed [95:0] q;
        begin
            q=value>>>1;
            if (value[0] && q[0]) q=q+96'sd1;
            half_round=q;
        end
    endfunction
    function automatic signed [31:0] saturate;
        input signed [95:0] x;
        begin
            if (x>96'sd2147483647) saturate=32'sh7fffffff;
            else if (x< -96'sd2147483648) saturate=32'sh80000000;
            else saturate=x[31:0];
        end
    endfunction
    function automatic signed [31:0] to_q24;
        input signed [95:0] x;
        reg signed [95:0] q;
        begin
            q=x>>>16;
            if (x[15:0]>16'h8000 || (x[15:0]==16'h8000 && q[0]))
                q=q+96'sd1;
            to_q24=saturate(q);
        end
    endfunction
    function automatic signed [95:0] exp_argument;
        input signed [31:0] value;
        input gelu;
        reg signed [95:0] x;
        begin
            x=$signed({{64{value[31]}},value})<<<16;
            if (gelu) begin
                x=multiply_q40(GELU_C,x+multiply_q40(GELU_K,
                    multiply_q40(multiply_q40(x,x),x)));
                x=x<0 ? x*96'sd2:-x*96'sd2;
            end
            if (x< -96'sd17592186044416) x=-96'sd17592186044416;
            exp_argument=x;
        end
    endfunction
    wire signed [95:0] input_q40=$signed({{64{in_data[31]}},in_data})<<<16;
    wire signed [95:0] angle_remainder=div_rem_reg>PI ?
        div_rem_reg-TWO_PI:div_rem_reg< -PI ?
        div_rem_reg+TWO_PI:div_rem_reg;
    wire signed [95:0] series_divisor=operation==SIN ?
        96'sd2*iteration*(96'sd2*iteration+96'sd1):operation==COS ?
        (96'sd2*iteration-96'sd1)*(96'sd2*iteration):{90'd0,iteration};
    wire [97:0] shifted_remainder=(remainder<<2)|{96'd0,radicand[95:94]};
    wire [97:0] trial=({50'd0,root_value}<<2)|98'd1;
    wire signed [95:0] exponential=total>>>-exponent_shift;
    wire signed [95:0] tanh_value=argument<0 ? -div_result_reg:div_result_reg;
    wire signed [95:0] gelu_scaled=gelu_tmp<0 ? gelu_tmp*96'sd2:-gelu_tmp*96'sd2;

    assign in_ready=rst_n && state==IDLE;
    assign out_valid=rst_n && state==HOLD;
    assign out_data=rst_n ? result:32'sd0;
    assign out_error=rst_n && error;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=IDLE; operation<=EXP; argument<=0; reduced<=0; term<=0; total<=0;
            exponent_shift<=0; iteration<=0; radicand<=0; remainder<=0;
            root_value<=0; result<=0; error<=0;
            gelu_tmp<=0; series_num_reg<=0; series_div_reg<=0; exp_reg<=0; tanh_prod_reg<=0;
            div_result_reg<=0; div_floor_reg<=0; div_rem_reg<=0;
            div_quotient<=0; div_divisor<=0; div_remainder<=0;
            div_negative<=0; div_dividend_negative<=0; div_iteration<=0; div_return<=IDLE;
        end else begin
            case (state)
                IDLE: if (in_valid) begin
                    operation<=in_op; argument<=input_q40;
                    error<=0; result<=0; iteration<=1;
                    if (in_op==RECIP) begin
                        if (in_data==0) begin error<=1; state<=HOLD; end
                        else begin_divide(96'sd281474976710656,
                            {{64{in_data[31]}},in_data},RECIP_SAVE);
                    end else if (in_op==RSQRT) begin
                        if (in_data<=0) begin error<=1; state<=HOLD; end
                        else begin
                            radicand<={64'd0,in_data}<<56; root_value<=0;
                            remainder<=0; iteration<=0; state<=ROOT;
                        end
                    end else if (in_op==SIN || in_op==COS)
                        begin_divide(input_q40,TWO_PI,ANGLE_SAVE);
                    else if (in_op==EXP || in_op==GELU) begin
                        if (in_op==GELU && in_data>=32'sd134217728) begin
                            result<=in_data; state<=HOLD;
                        end else if (in_op==GELU && in_data<= -32'sd134217728) begin
                            result<=0; state<=HOLD;
                        end else if (in_op==EXP && in_data>0) begin
                            error<=1; state<=HOLD;
                        end else if (in_op==EXP) begin
                            gelu_tmp<=input_q40< -96'sd17592186044416 ? -96'sd17592186044416:input_q40;
                            state<=EXP_START;
                        end else begin
                            state<=GELU_1;
                        end
                    end else begin error<=1; state<=HOLD; end
                end
                GELU_1: begin gelu_tmp<=multiply_q40(argument,argument); state<=GELU_2; end
                GELU_2: begin gelu_tmp<=multiply_q40(gelu_tmp,argument); state<=GELU_3; end
                GELU_3: begin gelu_tmp<=argument+multiply_q40(GELU_K,gelu_tmp); state<=GELU_4; end
                GELU_4: begin gelu_tmp<=multiply_q40(GELU_C,gelu_tmp); state<=GELU_5; end
                GELU_5: begin
                    gelu_tmp<=gelu_scaled< -96'sd17592186044416 ? -96'sd17592186044416:gelu_scaled;
                    state<=EXP_START;
                end
                EXP_START: begin_divide(gelu_tmp,LN2,RANGE_SAVE);
                DIVIDE: begin
                    div_quotient<=div_next_quotient; div_remainder<=div_next_remainder;
                    if (div_iteration==31) state<=DIV_DONE;
                    else div_iteration<=div_iteration+1'b1;
                end
                DIV_DONE: begin
                    div_result_reg<=div_result;
                    div_floor_reg<=div_floor;
                    div_rem_reg<=div_signed_remainder;
                    state<=div_return;
                end
                RANGE_SAVE: begin
                    exponent_shift<=div_floor_reg;
                    reduced<=div_rem_reg<0 ? div_rem_reg+LN2:div_rem_reg;
                    term<=ONE; total<=ONE; state<=SERIES;
                end
                ANGLE_SAVE: begin
                    reduced<=angle_remainder;
                    term<=operation==SIN ? angle_remainder:ONE;
                    total<=operation==SIN ? angle_remainder:ONE;
                    state<=SERIES;
                end
                SERIES: begin
                    series_num_reg<=multiply_q40(term,reduced);
                    series_div_reg<=series_divisor;
                    state<=(operation==SIN || operation==COS) ? SERIES_2:SERIES_DIV;
                end
                SERIES_2: begin
                    series_num_reg<= -multiply_q40(series_num_reg,reduced);
                    state<=SERIES_DIV;
                end
                SERIES_DIV: begin_divide(series_num_reg,series_div_reg,SERIES_SAVE);
                SERIES_SAVE: begin
                    term<=div_result_reg; total<=total+div_result_reg;
                    if (iteration==18) state<=FINISH;
                    else begin iteration<=iteration+1'b1; state<=SERIES; end
                end
                ROOT: begin
                    if (shifted_remainder>=trial) begin
                        remainder<=shifted_remainder-trial;
                        root_value<=(root_value<<1)|48'd1;
                    end else begin
                        remainder<=shifted_remainder; root_value<=root_value<<1;
                    end
                    radicand<=radicand<<2;
                    if (iteration==47) state<=FINISH;
                    else iteration<=iteration+1'b1;
                end
                FINISH: begin
                    if (operation==RSQRT)
                        begin_divide(96'sd18446744073709551616,{48'd0,root_value},RSQRT_SAVE);
                    else if (operation==SIN || operation==COS) begin
                        result<=to_q24(total); state<=HOLD;
                    end else begin
                        exp_reg<=exponential; state<=FINISH_EXP;
                    end
                end
                FINISH_EXP: begin
                    if (operation==EXP) begin
                        result<=to_q24(exp_reg); state<=HOLD;
                    end else begin_divide((ONE-exp_reg)<<<40,ONE+exp_reg,TANH_SAVE);
                end
                RECIP_SAVE, RSQRT_SAVE: begin result<=saturate(div_result_reg); state<=HOLD; end
                TANH_SAVE: begin
                    tanh_prod_reg<=multiply_q40(argument,ONE+tanh_value);
                    state<=TANH_DONE;
                end
                TANH_DONE: begin
                    result<=to_q24(half_round(tanh_prod_reg));
                    state<=HOLD;
                end
                HOLD: if (out_ready) state<=IDLE;
                default: begin error<=1; result<=0; state<=HOLD; end
            endcase
        end
    end
endmodule
