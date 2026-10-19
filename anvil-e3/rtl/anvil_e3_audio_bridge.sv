module anvil_e3_audio_bridge #(
    parameter integer AUDIO_LAYERS=12, AUDIO_HIDDEN=1024, AUDIO_FFN=4096,
    AUDIO_HEAD_DIM=128, AUDIO_OUT_DIM=1536, AUDIO_CONV_KERNEL=5,
    AUDIO_SUBSAMPLE_C0=128, AUDIO_SUBSAMPLE_C1=32, AUDIO_FREQ_BINS=128,
    TEXT_HIDDEN=512
) (
    input wire clk, rst_n, start_valid,
    output wire start_ready,
    input wire [31:0] tokens,
    input wire [63:0] weights, input_base, work_base, output_base,
    output wire cmd_valid, cmd_write,
    input wire cmd_ready,
    output wire [63:0] cmd_addr,
    output wire [31:0] cmd_wdata,
    input wire result_valid,
    output wire result_ready,
    input wire [31:0] result_data,
    input wire result_error,
    output wire done_valid,
    input wire done_ready,
    output wire [3:0] done_error
);
    localparam IDLE=0, LAUNCH=1, WAIT=2, DONE=3;
    localparam integer WIDTH=AUDIO_HIDDEN>AUDIO_OUT_DIM ? AUDIO_HIDDEN:AUDIO_OUT_DIM;
    reg [1:0] state;
    reg second_projection;
    reg [31:0] count;
    reg [63:0] w, src, tmp, dst;
    reg [3:0] error_hold;
    wire [63:0] weight_addr;
    wire layout_error;
    wire ready, done;
    wire [3:0] error;
    anvil_e3_audio_layout #(
        .AUDIO_LAYERS(AUDIO_LAYERS), .AUDIO_HIDDEN(AUDIO_HIDDEN),
        .AUDIO_FFN(AUDIO_FFN), .AUDIO_HEAD_DIM(AUDIO_HEAD_DIM),
        .AUDIO_OUT_DIM(AUDIO_OUT_DIM), .AUDIO_CONV_KERNEL(AUDIO_CONV_KERNEL),
        .AUDIO_SUBSAMPLE_C0(AUDIO_SUBSAMPLE_C0), .AUDIO_SUBSAMPLE_C1(AUDIO_SUBSAMPLE_C1),
        .AUDIO_FREQ_BINS(AUDIO_FREQ_BINS), .TEXT_HIDDEN(TEXT_HIDDEN)
    ) layout (
        .weights_base(w), .layer_index(32'd0),
        .tensor_group(second_projection ? 6'd29:6'd27),
        .tensor_addr(weight_addr), .weights_bytes(), .address_error(layout_error)
    );
    anvil_e3_audio_vector #(.MAX_WIDTH(WIDTH)) projections (
        .clk(clk), .rst_n(rst_n), .start_valid(state==LAUNCH && !layout_error),
        .start_ready(ready), .start_op(3'd0), .start_tokens({32'd0,count}),
        .start_rows(second_projection ? TEXT_HIDDEN:AUDIO_OUT_DIM),
        .start_cols(second_projection ? AUDIO_OUT_DIM:AUDIO_HIDDEN),
        .start_weights(weight_addr), .start_input(second_projection ? tmp:src),
        .start_aux(weight_addr+64'(AUDIO_OUT_DIM)*AUDIO_HIDDEN*4),
        .start_output(second_projection ? dst:tmp),
        .start_clipped(1'b0), .start_bias(!second_projection), .start_half(1'b0),
        .cmd_valid(cmd_valid), .cmd_write(cmd_write), .cmd_ready(cmd_ready),
        .cmd_addr(cmd_addr), .cmd_wdata(cmd_wdata), .result_valid(result_valid),
        .result_ready(result_ready), .result_data(result_data), .result_error(result_error),
        .done_valid(done), .done_ready(state==WAIT), .done_error(error)
    );
    assign start_ready=rst_n && state==IDLE;
    assign done_valid=rst_n && state==DONE;
    assign done_error=rst_n ? error_hold:4'd0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=IDLE; second_projection<=0; count<=0; w<=0;
            src<=0; tmp<=0; dst<=0; error_hold<=0;
        end else case (state)
            IDLE: if (start_valid) begin
                count<=tokens; w<=weights; src<=input_base; tmp<=work_base;
                dst<=output_base; second_projection<=0; error_hold<=0; state<=LAUNCH;
            end
            LAUNCH: begin
                if (layout_error) begin error_hold<=5; state<=DONE; end
                else if (ready) state<=WAIT;
            end
            WAIT: if (done) begin
                if (error!=0) begin error_hold<=error; state<=DONE; end
                else if (second_projection) state<=DONE;
                else begin second_projection<=1; state<=LAUNCH; end
            end
            DONE: if (done_ready) state<=IDLE;
            default: begin error_hold<=6; state<=DONE; end
        endcase
    end
endmodule
