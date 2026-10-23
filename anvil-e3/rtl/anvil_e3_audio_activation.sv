module anvil_e3_audio_activation (
    input wire clk, rst_n, in_valid,
    output wire in_ready,
    input wire [1:0] in_op,
    input wire signed [63:0] in_data,
    output wire out_valid,
    input wire out_ready,
    output wire signed [47:0] out_data,
    output wire out_error
);
    localparam IDLE=0, EXP_START=1, EXP_WAIT=2, DIV_START=3, DIV_WAIT=4,
        APPLY=5, LOG_TERM=6, HOLD=7, LOG_DIV_START=8, LOG_DIV_WAIT=9,
        CAP_DIV_START=10, CAP_DIV_WAIT=11, CAP_ROUND=12,
        LOG_SQ_ROUND=13, APPLY_ROUND=14;
    localparam signed [127:0] ONE=128'sd1099511627776;
    reg [3:0] state;
    reg [1:0] operation;
    reg signed [63:0] argument;
    reg signed [47:0] exp_arg_reg, exponential, result;
    reg signed [127:0] ratio, log_power, log_sum, log_square, mul_prod_reg;
    reg signed [127:0] numerator;
    reg [127:0] denominator;
    reg [64:0] cap_num_reg, cap_q_reg, cap_r_reg;
    reg [5:0] iteration;
    reg error_hold;
    wire exp_ready, exp_valid, exp_error, div_ready, div_valid, div_error;
    wire signed [47:0] exp_data;
    wire signed [127:0] div_data;
    wire signed [127:0] abs_in_data=in_data<0 ?
        -$signed({{64{in_data[63]}},in_data}):
         $signed({{64{in_data[63]}},in_data});
    function automatic signed [127:0] round_q40(input signed [127:0] p);
        reg signed [127:0] q;
        begin
            q=p>>>40;
            if (p[39:0]>40'h8000000000 ||
                (p[39:0]==40'h8000000000 && q[0])) q=q+1;
            round_q40=q[127:0];
        end
    endfunction
    function automatic signed [47:0] saturate(input signed [127:0] x);
        begin
            if (x>128'sd140737488289792) saturate=48'sh7fffffff0000;
            else if (x< -128'sd140737488355328) saturate=48'sh800000000000;
            else saturate=x[47:0];
        end
    endfunction
    wire cap_div_ready, cap_div_valid, cap_div_error;
    wire [64:0] cap_q, cap_r;
    anvil_e3_unsigned_divide #(.WIDTH(65)) cap_reduction (
        .clk(clk), .rst_n(rst_n), .in_valid(state==CAP_DIV_START),
        .in_ready(cap_div_ready), .in_numerator(cap_num_reg),
        .in_denominator(65'd50), .out_valid(cap_div_valid),
        .out_ready(state==CAP_DIV_WAIT),
        .out_quotient(cap_q), .out_remainder(cap_r),
        .out_error(cap_div_error)
    );
    wire [127:0] cap_rounded={63'd0,cap_q_reg}+
        128'(cap_r_reg>65'd25 || (cap_r_reg==65'd25 && cap_q_reg[0]));
    wire signed [127:0] mul_rounded=round_q40(mul_prod_reg);
    wire signed [127:0] next_sum=log_sum+div_data;
    wire signed [127:0] positive_argument=argument>0 ?
        $signed({{64{argument[63]}},argument}):128'sd0;
    anvil_e2_nonlinear exponential_unit (
        .clk(clk), .rst_n(rst_n), .in_valid(state==EXP_START),
        .in_ready(exp_ready), .in_op(3'd0),
        .in_data(exp_arg_reg), .out_valid(exp_valid),
        .out_ready(state==EXP_WAIT), .out_data(exp_data), .out_error(exp_error)
    );
    anvil_e2_divide divider (
        .clk(clk), .rst_n(rst_n),
        .in_valid(state==DIV_START || state==LOG_DIV_START),
        .in_ready(div_ready), .in_numerator(numerator), .in_denominator(denominator),
        .out_valid(div_valid), .out_ready(state==DIV_WAIT || state==LOG_DIV_WAIT),
        .out_data(div_data), .out_error(div_error)
    );
    assign in_ready=rst_n && state==IDLE;
    assign out_valid=rst_n && state==HOLD;
    assign out_data=rst_n ? result:48'sd0;
    assign out_error=rst_n && error_hold;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=IDLE; operation<=0; argument<=0; exp_arg_reg<=0;
            exponential<=0; result<=0; ratio<=0; log_power<=0; log_sum<=0;
            log_square<=0; mul_prod_reg<=0; numerator<=0; denominator<=1;
            cap_num_reg<=0; cap_q_reg<=0; cap_r_reg<=0;
            iteration<=0; error_hold<=0;
        end else case (state)
            IDLE: if (in_valid) begin
                operation<=in_op; argument<=in_data; result<=0; error_hold<=0;
                if (in_op==2'd3) begin
                    cap_num_reg<={abs_in_data[63:0],1'b0};
                    state<=CAP_DIV_START;
                end else begin
                    exp_arg_reg<=saturate(-abs_in_data);
                    state<=EXP_START;
                end
            end
            CAP_DIV_START: if (cap_div_ready) state<=CAP_DIV_WAIT;
            CAP_DIV_WAIT: if (cap_div_valid) begin
                if (cap_div_error) begin error_hold<=1; state<=HOLD; end
                else begin
                    cap_q_reg<=cap_q; cap_r_reg<=cap_r;
                    state<=CAP_ROUND;
                end
            end
            CAP_ROUND: begin
                exp_arg_reg<=saturate(-$signed(cap_rounded));
                state<=EXP_START;
            end
            EXP_START: if (exp_ready) state<=EXP_WAIT;
            EXP_WAIT: if (exp_valid) begin
                if (exp_error) begin error_hold<=1; state<=HOLD; end
                else begin
                    exponential<=exp_data;
                    if (operation==2) begin
                        numerator<=$signed({{80{exp_data[47]}},exp_data})<<<40;
                        denominator<=2*ONE+$signed({{80{exp_data[47]}},exp_data});
                    end else if (operation==3) begin
                        numerator<=(ONE-$signed({{80{exp_data[47]}},exp_data}))<<<40;
                        denominator<=ONE+$signed({{80{exp_data[47]}},exp_data});
                    end else begin
                        numerator<=(argument<0 ?
                            $signed({{80{exp_data[47]}},exp_data}):ONE)<<<40;
                        denominator<=ONE+$signed({{80{exp_data[47]}},exp_data});
                    end
                    state<=DIV_START;
                end
            end
            DIV_START: if (div_ready) state<=DIV_WAIT;
            DIV_WAIT: if (div_valid) begin
                if (div_error) begin error_hold<=1; state<=HOLD; end
                else begin
                    ratio<=div_data;
                    if (operation==2) begin
                        log_power<=div_data; log_sum<=div_data;
                        mul_prod_reg<=$signed(div_data[63:0])*$signed(div_data[63:0]);
                        iteration<=1; state<=LOG_SQ_ROUND;
                    end else state<=APPLY;
                end
            end
            LOG_SQ_ROUND: begin
                log_square<=mul_rounded;
                mul_prod_reg<=$signed(log_power[63:0])*$signed(mul_rounded[63:0]);
                state<=LOG_TERM;
            end
            APPLY: begin
                case (operation)
                    0: begin
                        mul_prod_reg<=argument*$signed(ratio[63:0]);
                        state<=APPLY_ROUND;
                    end
                    1: begin result<=saturate(ratio); state<=HOLD; end
                    3: begin result<=saturate(argument<0 ? -50*ratio:50*ratio); state<=HOLD; end
                    default: begin result<=0; error_hold<=1; state<=HOLD; end
                endcase
            end
            APPLY_ROUND: begin
                result<=saturate(mul_rounded);
                state<=HOLD;
            end
            LOG_TERM: begin
                log_power<=mul_rounded;
                numerator<=mul_rounded; denominator<=128'(2*iteration+1);
                state<=LOG_DIV_START;
            end
            LOG_DIV_START: if (div_ready) state<=LOG_DIV_WAIT;
            LOG_DIV_WAIT: if (div_valid) begin
                if (div_error) begin error_hold<=1; result<=0; state<=HOLD; end
                else begin
                    log_sum<=next_sum;
                    if (iteration==15) begin
                        result<=saturate(positive_argument+2*next_sum); state<=HOLD;
                    end else begin
                        iteration<=iteration+1'b1;
                        mul_prod_reg<=$signed(log_power[63:0])*$signed(log_square[63:0]);
                        state<=LOG_TERM;
                    end
                end
            end
            HOLD: if (out_ready) state<=IDLE;
            default: begin error_hold<=1; result<=0; state<=HOLD; end
        endcase
    end
endmodule
