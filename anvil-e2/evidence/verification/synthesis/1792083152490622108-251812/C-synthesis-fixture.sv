module synthesis_fixture (

    input wire clk, rst_n, job_valid,
    input wire [1:0] job_mode,
    input wire [31:0] job_tokens, job_patch_rows, job_patch_cols,
    input wire [15:0] job_output_dim,
    input wire [63:0] weights_base, vision_weights_base, image_base, tokens_base,
    positions_base, mask_base, scratch_base,
    input wire mem_req_ready, mem_rsp_valid,
    input wire [31:0] mem_rsp_rdata,
    input wire mem_rsp_error, emb_ready, done_ready,
    output wire job_ready, mem_req_valid, mem_req_write,
    output wire [63:0] mem_req_addr,
    output wire [31:0] mem_req_wdata,
    output wire mem_rsp_ready, emb_valid,
    output wire signed [31:0] emb_data,
    output wire [15:0] emb_index,
    output wire emb_last, done_valid,
    output wire [3:0] done_error,
    output wire busy
);
anvil_e2_top #(.VISION_LAYERS(16),.VISION_HIDDEN(4),.VISION_FFN(3),.VISION_HEADS(1),.VISION_HEAD_DIM(4),.PATCH_SIZE(1),.POOL_KERNEL(1),.VISION_SOFT_TOKENS(1),.TEXT_LAYERS(24),.TEXT_HIDDEN(2),.PLE_DIM(2),.TEXT_FFN(3),.EMBED_DIM(12),.VOCAB_SIZE(262144),.POSITION_EMBEDDING_SIZE(10240),.TEXT_Q_HEADS(4),.LOCAL_KV_HEADS(2),.FULL_KV_HEADS(1),.LOCAL_HEAD_DIM(2),.FULL_HEAD_DIM(4),.SLIDING_WINDOW(2),.MAX_SEQ_LEN(262144),.RMS_EPSILON_Q80(128'd1208925819614629175)) implementation (.*);
endmodule
