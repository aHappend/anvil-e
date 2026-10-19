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
        TRIG_START=4, TRIG_WAIT=5, HOLD=6;
    localparam signed [127:0] LN10000=128'sd10126876334763;
    localparam signed [127:0] TWO_PI=128'sd6908435304715;
    localparam signed [127:0] PI=128'sd3454217652358;
    reg [2:0] state;
    reg signed [32:0] delta;
    reg odd_channel;
    reg signed [47:0] argument, frequency, result;
    reg error_hold;
    reg signed [127:0] work, magnitude, quotient, residue;
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
            result<=0; error_hold<=0; work=0; magnitude=0; quotient=0; residue=0;
        end else case (state)
            IDLE: if (start_valid) begin
                delta<=$signed({1'b0,start_query})-$signed({1'b0,start_key});
                odd_channel<=start_channel[0]; error_hold<=0; result<=0;
                if (start_channel>=AUDIO_HIDDEN) begin error_hold<=1; state<=HOLD; end
                else if (start_channel<2) begin
                    frequency<=48'sd1099511627776; state<=ANGLE;
                end else begin
                    magnitude=LN10000*2*128'(start_channel/2);
                    quotient=magnitude/AUDIO_HIDDEN;
                    residue=magnitude-quotient*AUDIO_HIDDEN;
                    if (residue>AUDIO_HIDDEN-residue ||
                        (residue==AUDIO_HIDDEN-residue && quotient[0])) quotient=quotient+1;
                    argument<=-quotient[47:0]; state<=FREQUENCY_START;
                end
            end
            FREQUENCY_START: if (ready) state<=FREQUENCY_WAIT;
            FREQUENCY_WAIT: if (valid) begin
                if (error) begin error_hold<=1; state<=HOLD; end
                else begin frequency<=value; state<=ANGLE; end
            end
            ANGLE: begin
                work=$signed(frequency)*$signed(delta);
                work=work%TWO_PI;
                if (work>PI) work=work-TWO_PI;
                else if (work< -PI) work=work+TWO_PI;
                argument<=work[47:0]; state<=TRIG_START;
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
