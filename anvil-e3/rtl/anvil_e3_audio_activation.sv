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
        APPLY=5, LOG_TERM=6, HOLD=7;
    localparam signed [127:0] ONE=128'sd1099511627776;
    reg [2:0] state;
    reg [1:0] operation;
    reg signed [63:0] argument;
    reg signed [47:0] exponential, result;
    reg signed [127:0] ratio, log_power, log_sum, log_square;
    reg signed [127:0] numerator;
    reg [127:0] denominator;
    reg [5:0] iteration;
    reg error_hold;
    wire exp_ready, exp_valid, exp_error, div_ready, div_valid, div_error;
    wire signed [47:0] exp_data;
    wire signed [127:0] div_data;
    reg signed [127:0] work, next_power, next_sum;
    wire signed [127:0] abs_argument=argument<0 ?
        -$signed({{64{argument[63]}},argument}):
         $signed({{64{argument[63]}},argument});
    function automatic signed [127:0] divide_nearest(
        input signed [127:0] n, input [127:0] d);
        reg [127:0] m,q,r;
        begin
            m=n<0 ? -n:n; q=m/d; r=m-q*d;
            if (r>d-r || (r==d-r && q[0])) q=q+1;
            divide_nearest=n<0 ? -$signed(q):$signed(q);
        end
    endfunction
    function automatic signed [127:0] multiply_q40(
        input signed [127:0] a,b);
        reg signed [63:0] narrow_a, narrow_b;
        reg signed [127:0] p,q;
        begin
            narrow_a=a[63:0]; narrow_b=b[63:0];
            p=narrow_a*narrow_b; q=p>>>40;
            if (p[39:0]>40'h8000000000 ||
                (p[39:0]==40'h8000000000 && q[0])) q=q+1;
            multiply_q40=q[127:0];
        end
    endfunction
    function automatic signed [47:0] saturate(input signed [127:0] x);
        begin
            if (x>128'sd140737488289792) saturate=48'sh7fffffff0000;
            else if (x< -128'sd140737488355328) saturate=48'sh800000000000;
            else saturate=x[47:0];
        end
    endfunction
    wire signed [127:0] exp_argument=operation==3 ?
        -divide_nearest(abs_argument*2,128'd50):-abs_argument;
    anvil_e2_nonlinear exponential_unit (
        .clk(clk), .rst_n(rst_n), .in_valid(state==EXP_START),
        .in_ready(exp_ready), .in_op(3'd0),
        .in_data(saturate(exp_argument)), .out_valid(exp_valid),
        .out_ready(state==EXP_WAIT), .out_data(exp_data), .out_error(exp_error)
    );
    anvil_e2_divide divider (
        .clk(clk), .rst_n(rst_n), .in_valid(state==DIV_START),
        .in_ready(div_ready), .in_numerator(numerator), .in_denominator(denominator),
        .out_valid(div_valid), .out_ready(state==DIV_WAIT),
        .out_data(div_data), .out_error(div_error)
    );
    assign in_ready=rst_n && state==IDLE;
    assign out_valid=rst_n && state==HOLD;
    assign out_data=rst_n ? result:48'sd0;
    assign out_error=rst_n && error_hold;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=IDLE; operation<=0; argument<=0; exponential<=0; result<=0;
            ratio<=0; log_power<=0; log_sum<=0; log_square<=0;
            numerator<=0; denominator<=1; iteration<=0; error_hold<=0;
            work=0; next_power=0; next_sum=0;
        end else case (state)
            IDLE: if (in_valid) begin
                operation<=in_op; argument<=in_data; result<=0; error_hold<=0;
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
                        log_square<=multiply_q40(div_data,div_data);
                        iteration<=1; state<=LOG_TERM;
                    end else state<=APPLY;
                end
            end
            APPLY: begin
                case (operation)
                    0: result<=saturate(multiply_q40(
                        $signed({{64{argument[63]}},argument}),ratio));
                    1: result<=saturate(ratio);
                    3: result<=saturate(argument<0 ? -50*ratio:50*ratio);
                    default: begin result<=0; error_hold<=1; end
                endcase
                state<=HOLD;
            end
            LOG_TERM: begin
                next_power=multiply_q40(log_power,log_square);
                next_sum=log_sum+divide_nearest(next_power,128'(2*iteration+1));
                log_power<=next_power; log_sum<=next_sum;
                if (iteration==15) begin
                    work=argument>0 ? $signed({{64{argument[63]}},argument}):128'sd0;
                    result<=saturate(work+2*next_sum); state<=HOLD;
                end else iteration<=iteration+1'b1;
            end
            HOLD: if (out_ready) state<=IDLE;
            default: begin error_hold<=1; result<=0; state<=HOLD; end
        endcase
    end
endmodule
