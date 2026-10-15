module anvil_e2_pool_norm #(
    parameter integer VOCAB_SIZE=262144, HIDDEN_SIZE=512,
    PER_LAYER_INPUT_SIZE=512, INTERMEDIATE_SIZE=2048, EMBEDDING_DIM=768,
    NUM_LAYERS=24, NUM_Q_HEADS=4, LOCAL_KV_HEADS=2, FULL_KV_HEADS=1,
    LOCAL_HEAD_DIM=256, FULL_HEAD_DIM=512, SLIDING_WINDOW=512,
    parameter logic [127:0] RMS_EPSILON_Q80 = (128'd17 << 56)
) (
    input wire clk, rst_n, start_valid,
    output wire start_ready,
    input wire [31:0] tokens, valid_tokens,
    input wire [15:0] output_dim,
    input wire [63:0] weights, token_ids, positions, masks, scratch,
    input wire [63:0] x0_base, x1_base, ple_base, q_base, k_base, v_base,
    input wire [31:0] layer_index, patch_cols,
    input wire start_current_x,
    output wire cmd_valid, cmd_write,
    input wire cmd_ready,
    output wire [63:0] cmd_addr,
    output wire [31:0] cmd_wdata,
    input wire result_valid,
    output wire result_ready,
    input wire [31:0] result_data,
    input wire result_error,
    output wire emb_valid,
    input wire emb_ready,
    output wire signed [31:0] emb_data,
    output wire [15:0] emb_index,
    output wire emb_last, done_valid,
    input wire done_ready,
    output wire [3:0] done_error
);
    anvil_e2_hybrid_layer #(
        .VOCAB_SIZE(VOCAB_SIZE), .HIDDEN_SIZE(HIDDEN_SIZE),
        .PER_LAYER_INPUT_SIZE(PER_LAYER_INPUT_SIZE), .INTERMEDIATE_SIZE(INTERMEDIATE_SIZE),
        .EMBEDDING_DIM(EMBEDDING_DIM), .NUM_LAYERS(NUM_LAYERS),
        .NUM_Q_HEADS(NUM_Q_HEADS), .LOCAL_KV_HEADS(LOCAL_KV_HEADS),
        .FULL_KV_HEADS(FULL_KV_HEADS), .LOCAL_HEAD_DIM(LOCAL_HEAD_DIM),
        .FULL_HEAD_DIM(FULL_HEAD_DIM), .SLIDING_WINDOW(SLIDING_WINDOW), .STAGE(2),
        .RMS_EPSILON_Q80(RMS_EPSILON_Q80)
    ) engine (.*);
endmodule
