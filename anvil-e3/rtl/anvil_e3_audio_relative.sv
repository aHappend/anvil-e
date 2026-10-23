module anvil_e3_audio_relative #(
    parameter integer AUDIO_HIDDEN=1024
) (
    input wire clk, rst_n, start_valid,
    output wire start_ready,
    input wire [31:0] start_query, start_key, start_channel,
    output wire out_valid,
    input wire out_ready,
    output wire signed [47:0] out_data,
    output wire out_error
);
    localparam IDLE=0, FREQUENCY_START=1, FREQUENCY_WAIT=2, ANGLE=3,
        TRIG_START=4, TRIG_WAIT=5, HOLD=6,
        FREQ_DIV_START=7, FREQ_DIV_WAIT=8, FREQ_ROUND=9,
        ANGLE_MUL=10, ANGLE_ABS=11, ANGLE_DIV_START=12,
        ANGLE_DIV_WAIT=13, ANGLE_SUB=14;
    localparam signed [127:0] LN10000=128'sd10126876334763;
    localparam signed [127:0] TWO_PI=128'sd6908435304715;
    localparam signed [127:0] PI=128'sd3454217652358;
    reg [3:0] state;
    reg signed [32:0] delta;
    reg odd_channel;
    reg signed [47:0] argument, frequency, result;
    reg [63:0] freq_num_reg, freq_q_reg, freq_r_reg;
    reg signed [95:0] angle_prod_reg;
    reg [95:0] angle_mag_reg, angle_r_reg;
    reg signed [127:0] work_reg;
    reg error_hold;
    wire [63:0] magnitude=64'(LN10000)*2*64'(start_channel>>1);
    wire div_ready, div_valid, div_error;
    wire [95:0] div_q, div_r;
    wire div_in_valid=(state==FREQ_DIV_START || state==ANGLE_DIV_START);
    wire [95:0] div_in_num=(state==FREQ_DIV_START) ?
        {32'd0,freq_num_reg} : angle_mag_reg;
    wire [95:0] div_in_den=(state==FREQ_DIV_START) ?
        96'(AUDIO_HIDDEN) : 96'd6908435304715;
    anvil_e3_unsigned_divide #(.WIDTH(96)) shared_divider (
        .clk(clk), .rst_n(rst_n), .in_valid(div_in_valid),
        .in_ready(div_ready), .in_numerator(div_in_num),
        .in_denominator(div_in_den), .out_valid(div_valid),
        .out_ready(state==FREQ_DIV_WAIT || state==ANGLE_DIV_WAIT),
        .out_quotient(div_q), .out_remainder(div_r), .out_error(div_error)
    );
    wire [63:0] quotient=freq_q_reg+64'(
        ({freq_r_reg,1'b0}>{1'b0,64'(AUDIO_HIDDEN)}) ||
        (({freq_r_reg,1'b0}=={1'b0,64'(AUDIO_HIDDEN)}) && freq_q_reg[0]));
    wire signed [127:0] angle_base=angle_prod_reg<0 ?
        -$signed({32'd0,angle_r_reg}):$signed({32'd0,angle_r_reg});
    wire signed [127:0] work=angle_base>PI ? angle_base-TWO_PI:
        angle_base< -PI ? angle_base+TWO_PI:angle_base;
    wire ready, valid, error;
    wire signed [47:0] value;
    anvil_e2_nonlinear nonlinear (
        .clk(clk), .rst_n(rst_n),
        .in_valid(state==FREQUENCY_START || state==TRIG_START),
        .in_ready(ready),
        .in_op(state==FREQUENCY_START ? 3'd0:odd_channel ? 3'd2:3'd1),
        .in_data(argument), .out_valid(valid),
        .out_ready(state==FREQUENCY_WAIT || state==TRIG_WAIT),
        .out_data(value), .out_error(error)
    );
    assign start_ready=rst_n && state==IDLE;
    assign out_valid=rst_n && state==HOLD;
    assign out_data=rst_n ? result:48'sd0;
    assign out_error=rst_n && error_hold;
    initial begin
        if (AUDIO_HIDDEN<=0 || AUDIO_HIDDEN>65535)
            $fatal(1,"PARAMETER ERROR: audio relative dimension");
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=IDLE; delta<=0; odd_channel<=0; argument<=0; frequency<=0;
            result<=0; error_hold<=0; freq_num_reg<=0; freq_q_reg<=0;
            freq_r_reg<=0; angle_prod_reg<=0; angle_mag_reg<=0;
            angle_r_reg<=0; work_reg<=0;
        end else case (state)
            IDLE: if (start_valid) begin
                delta<=$signed({1'b0,start_query})-$signed({1'b0,start_key});
                odd_channel<=start_channel[0]; error_hold<=0; result<=0;
                if (start_channel>=AUDIO_HIDDEN) begin error_hold<=1; state<=HOLD; end
                else if (start_channel<2) begin
                    frequency<=48'sd1099511627776; state<=ANGLE_MUL;
                end else begin
                    freq_num_reg<=magnitude; state<=FREQ_DIV_START;
                end
            end
            FREQ_DIV_START: if (div_ready) state<=FREQ_DIV_WAIT;
            FREQ_DIV_WAIT: if (div_valid) begin
                if (div_error) begin error_hold<=1; state<=HOLD; end
                else begin
                    freq_q_reg<=div_q[63:0]; freq_r_reg<=div_r[63:0];
                    state<=FREQ_ROUND;
                end
            end
            FREQ_ROUND: begin
                argument<=-quotient[47:0]; state<=FREQUENCY_START;
            end
            FREQUENCY_START: if (ready) state<=FREQUENCY_WAIT;
            FREQUENCY_WAIT: if (valid) begin
                if (error) begin error_hold<=1; state<=HOLD; end
                else begin frequency<=value; state<=ANGLE_MUL; end
            end
            ANGLE_MUL: begin
                angle_prod_reg<=$signed(frequency)*$signed(delta);
                state<=ANGLE_ABS;
            end
            ANGLE_ABS: begin
                angle_mag_reg<=angle_prod_reg<0 ?
                    -$unsigned(angle_prod_reg):$unsigned(angle_prod_reg);
                state<=ANGLE_DIV_START;
            end
            ANGLE_DIV_START: if (div_ready) state<=ANGLE_DIV_WAIT;
            ANGLE_DIV_WAIT: if (div_valid) begin
                if (div_error) begin error_hold<=1; state<=HOLD; end
                else begin
                    angle_r_reg<=div_r;
                    state<=ANGLE_SUB;
                end
            end
            ANGLE_SUB: begin
                work_reg<=work;
                state<=ANGLE;
            end
            ANGLE: begin
                argument<=work_reg[47:0]; state<=TRIG_START;
            end
            TRIG_START: if (ready) state<=TRIG_WAIT;
            TRIG_WAIT: if (valid) begin
                result<=value; error_hold<=error; state<=HOLD;
            end
            HOLD: if (out_ready) state<=IDLE;
            default: begin error_hold<=1; result<=0; state<=HOLD; end
        endcase
    end
endmodule
