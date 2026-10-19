module anvil_e2_vision_encoder_layer #(
    parameter integer VISION_LAYERS=16, VISION_HIDDEN=768, VISION_FFN=3072,
    VISION_HEADS=12, VISION_HEAD_DIM=64, PATCH_SIZE=16,
    POSITION_EMBEDDING_SIZE=10240,
    parameter logic [127:0] RMS_EPSILON_Q80 = (128'd17 << 56)
) (
    input wire clk, rst_n, start_valid,
    output wire start_ready,
    input wire [31:0] tokens, layer_index, patch_cols,
    input wire [63:0] weights, x0_base, x1_base, q_base, k_base, v_base,
    input wire start_current_x,
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
    anvil_e2_hybrid_layer #(
        .HIDDEN_SIZE(VISION_HIDDEN), .PER_LAYER_INPUT_SIZE(1),
        .INTERMEDIATE_SIZE(VISION_FFN), .EMBEDDING_DIM(6),
        .NUM_LAYERS(VISION_LAYERS), .NUM_Q_HEADS(VISION_HEADS),
        .LOCAL_KV_HEADS(VISION_HEADS), .FULL_KV_HEADS(VISION_HEADS),
        .LOCAL_HEAD_DIM(VISION_HEAD_DIM), .FULL_HEAD_DIM(VISION_HEAD_DIM),
        .STAGE(1), .VISION(1), .PATCH_SIZE(PATCH_SIZE),
        .POSITION_EMBEDDING_SIZE(POSITION_EMBEDDING_SIZE),
        .RMS_EPSILON_Q80(RMS_EPSILON_Q80)
    ) engine (
        .clk(clk), .rst_n(rst_n), .start_valid(start_valid), .start_ready(start_ready),
        .tokens(tokens), .valid_tokens(tokens), .output_dim(16'd6),
        .weights(weights), .token_ids(64'd0), .positions(64'd0),
        .masks(64'd0), .scratch(64'd0), .ple_base(64'd0),
        .x0_base(x0_base), .x1_base(x1_base), .q_base(q_base),
        .k_base(k_base), .v_base(v_base), .layer_index(layer_index),
        .patch_cols(patch_cols), .start_current_x(start_current_x),
        .cmd_valid(cmd_valid), .cmd_ready(cmd_ready), .cmd_write(cmd_write),
        .cmd_addr(cmd_addr), .cmd_wdata(cmd_wdata), .result_valid(result_valid),
        .result_ready(result_ready), .result_data(result_data), .result_error(result_error),
        .emb_valid(), .emb_ready(1'b0), .emb_data(), .emb_index(), .emb_last(),
        .done_valid(done_valid), .done_ready(done_ready), .done_error(done_error)
    );
endmodule
