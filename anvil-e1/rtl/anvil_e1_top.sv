module anvil_e1_top #(
    parameter integer VOCAB_SIZE=262144,
    parameter integer HIDDEN_SIZE=512,
    parameter integer PER_LAYER_INPUT_SIZE=512,
    parameter integer INTERMEDIATE_SIZE=2048,
    parameter integer EMBEDDING_DIM=768,
    parameter integer NUM_LAYERS=24,
    parameter integer NUM_Q_HEADS=4,
    parameter integer LOCAL_KV_HEADS=2,
    parameter integer FULL_KV_HEADS=1,
    parameter integer LOCAL_HEAD_DIM=256,
    parameter integer FULL_HEAD_DIM=512,
    parameter integer SLIDING_WINDOW=512,
    parameter integer MAX_SEQ_LEN=262144
) (
    input wire clk, rst_n,
    input wire job_valid,
    output wire job_ready,
    input wire [31:0] job_tokens,
    input wire [15:0] job_output_dim,
    input wire [63:0] weights_base, tokens_base, positions_base, mask_base, scratch_base,
    output wire mem_req_valid,
    input wire mem_req_ready,
    output wire mem_req_write,
    output wire [63:0] mem_req_addr,
    output wire [31:0] mem_req_wdata,
    input wire mem_rsp_valid,
    output wire mem_rsp_ready,
    input wire [31:0] mem_rsp_rdata,
    input wire mem_rsp_error,
    output wire emb_valid,
    input wire emb_ready,
    output wire signed [31:0] emb_data,
    output wire [15:0] emb_index,
    output wire emb_last,
    output wire done_valid,
    input wire done_ready,
    output wire [3:0] done_error,
    output wire busy
);
    localparam LEGAL=VOCAB_SIZE>0 && HIDDEN_SIZE>0 && HIDDEN_SIZE<=65535 &&
        PER_LAYER_INPUT_SIZE>0 && PER_LAYER_INPUT_SIZE<=65535 &&
        INTERMEDIATE_SIZE>0 && INTERMEDIATE_SIZE<=65535 &&
        EMBEDDING_DIM>=6 && EMBEDDING_DIM<=65535 && EMBEDDING_DIM%6==0 &&
        NUM_LAYERS>0 && NUM_LAYERS<=65535 && MAX_SEQ_LEN>0 &&
        NUM_Q_HEADS>0 && NUM_Q_HEADS<=65535 &&
        LOCAL_KV_HEADS>0 && FULL_KV_HEADS>0 &&
        NUM_Q_HEADS%LOCAL_KV_HEADS==0 && NUM_Q_HEADS%FULL_KV_HEADS==0 &&
        LOCAL_HEAD_DIM>0 && FULL_HEAD_DIM>0 &&
        LOCAL_HEAD_DIM%2==0 && FULL_HEAD_DIM%2==0 &&
        64'(NUM_Q_HEADS)*LOCAL_HEAD_DIM<=65535 &&
        64'(NUM_Q_HEADS)*FULL_HEAD_DIM<=65535 && SLIDING_WINDOW>0;
    generate if (LEGAL) begin : legal_datapath
        wire ctrl_cmd_valid, ctrl_result_ready;
        wire [63:0] ctrl_cmd_addr;
        wire engine_cmd_valid, engine_cmd_write, engine_result_ready;
        wire [63:0] engine_cmd_addr;
        wire [31:0] engine_cmd_wdata;
        wire memory_cmd_ready, memory_result_valid, memory_result_error;
        wire [31:0] memory_result_data;
        wire engine_start_valid, engine_start_ready;
        wire engine_emb_valid, engine_emb_ready, engine_emb_last;
        wire signed [31:0] engine_emb_data;
        wire [15:0] engine_emb_index;
        wire engine_done_valid, engine_done_ready;
        wire [3:0] engine_done_error;
        wire [31:0] tokens, valid_tokens;
        wire [15:0] output_dim;
        wire [63:0] weights, token_ids, positions, masks, scratch;
        reg engine_owner;
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) engine_owner<=0;
            else if (engine_start_valid && engine_start_ready) engine_owner<=1;
            else if (engine_done_valid && engine_done_ready) engine_owner<=0;
        end
        anvil_e1_controller #(
            .VOCAB_SIZE(VOCAB_SIZE), .HIDDEN_SIZE(HIDDEN_SIZE),
            .PER_LAYER_INPUT_SIZE(PER_LAYER_INPUT_SIZE), .INTERMEDIATE_SIZE(INTERMEDIATE_SIZE),
            .EMBEDDING_DIM(EMBEDDING_DIM), .NUM_LAYERS(NUM_LAYERS),
            .NUM_Q_HEADS(NUM_Q_HEADS), .LOCAL_KV_HEADS(LOCAL_KV_HEADS),
            .FULL_KV_HEADS(FULL_KV_HEADS), .LOCAL_HEAD_DIM(LOCAL_HEAD_DIM),
            .FULL_HEAD_DIM(FULL_HEAD_DIM), .MAX_SEQ_LEN(MAX_SEQ_LEN)
        ) controller (
            .clk(clk), .rst_n(rst_n), .job_valid(job_valid), .job_ready(job_ready),
            .job_tokens(job_tokens), .job_output_dim(job_output_dim),
            .weights_base(weights_base), .tokens_base(tokens_base),
            .positions_base(positions_base), .mask_base(mask_base), .scratch_base(scratch_base),
            .busy(busy), .cmd_valid(ctrl_cmd_valid),
            .cmd_ready(memory_cmd_ready && !engine_owner), .cmd_addr(ctrl_cmd_addr),
            .result_valid(memory_result_valid && !engine_owner),
            .result_ready(ctrl_result_ready), .result_data(memory_result_data),
            .result_error(memory_result_error),
            .engine_start_valid(engine_start_valid), .engine_start_ready(engine_start_ready),
            .tokens(tokens), .valid_tokens(valid_tokens), .output_dim(output_dim),
            .weights(weights), .token_ids(token_ids), .positions(positions),
            .masks(masks), .scratch(scratch), .engine_emb_valid(engine_emb_valid),
            .engine_emb_ready(engine_emb_ready), .engine_emb_data(engine_emb_data),
            .engine_emb_index(engine_emb_index), .engine_emb_last(engine_emb_last),
            .engine_done_valid(engine_done_valid), .engine_done_ready(engine_done_ready),
            .engine_done_error(engine_done_error), .emb_valid(emb_valid), .emb_ready(emb_ready),
            .emb_data(emb_data), .emb_index(emb_index), .emb_last(emb_last),
            .done_valid(done_valid), .done_ready(done_ready), .done_error(done_error)
        );
        anvil_e1_memory memory_bridge (
            .clk(clk), .rst_n(rst_n),
            .cmd_valid(engine_owner ? engine_cmd_valid:ctrl_cmd_valid),
            .cmd_ready(memory_cmd_ready),
            .cmd_write(engine_owner && engine_cmd_write),
            .cmd_addr(engine_owner ? engine_cmd_addr:ctrl_cmd_addr),
            .cmd_wdata(engine_owner ? engine_cmd_wdata:32'd0),
            .result_valid(memory_result_valid),
            .result_ready(engine_owner ? engine_result_ready:ctrl_result_ready),
            .result_data(memory_result_data), .result_error(memory_result_error),
            .mem_req_valid(mem_req_valid), .mem_req_ready(mem_req_ready),
            .mem_req_write(mem_req_write), .mem_req_addr(mem_req_addr),
            .mem_req_wdata(mem_req_wdata), .mem_rsp_valid(mem_rsp_valid),
            .mem_rsp_ready(mem_rsp_ready), .mem_rsp_rdata(mem_rsp_rdata),
            .mem_rsp_error(mem_rsp_error)
        );
        anvil_e1_sequencer #(
            .VOCAB_SIZE(VOCAB_SIZE), .HIDDEN_SIZE(HIDDEN_SIZE),
            .PER_LAYER_INPUT_SIZE(PER_LAYER_INPUT_SIZE), .INTERMEDIATE_SIZE(INTERMEDIATE_SIZE),
            .EMBEDDING_DIM(EMBEDDING_DIM), .NUM_LAYERS(NUM_LAYERS),
            .NUM_Q_HEADS(NUM_Q_HEADS), .LOCAL_KV_HEADS(LOCAL_KV_HEADS),
            .FULL_KV_HEADS(FULL_KV_HEADS), .LOCAL_HEAD_DIM(LOCAL_HEAD_DIM),
            .FULL_HEAD_DIM(FULL_HEAD_DIM), .SLIDING_WINDOW(SLIDING_WINDOW)
        ) sequencer (
            .clk(clk), .rst_n(rst_n), .start_valid(engine_start_valid),
            .start_ready(engine_start_ready), .tokens(tokens), .valid_tokens(valid_tokens),
            .output_dim(output_dim), .weights(weights), .token_ids(token_ids),
            .positions(positions), .masks(masks), .scratch(scratch),
            .cmd_valid(engine_cmd_valid), .cmd_ready(memory_cmd_ready && engine_owner),
            .cmd_write(engine_cmd_write), .cmd_addr(engine_cmd_addr),
            .cmd_wdata(engine_cmd_wdata), .result_valid(memory_result_valid && engine_owner),
            .result_ready(engine_result_ready), .result_data(memory_result_data),
            .result_error(memory_result_error), .emb_valid(engine_emb_valid),
            .emb_ready(engine_emb_ready), .emb_data(engine_emb_data),
            .emb_index(engine_emb_index), .emb_last(engine_emb_last),
            .done_valid(engine_done_valid), .done_ready(engine_done_ready),
            .done_error(engine_done_error)
        );
    end else begin : invalid_parameters
        initial $fatal(1,"PARAMETER ERROR: unsupported Anvil-E1 geometry");
        assign job_ready=0;
        assign mem_req_valid=0;
        assign mem_req_write=0;
        assign mem_req_addr=0;
        assign mem_req_wdata=0;
        assign mem_rsp_ready=0;
        assign emb_valid=0;
        assign emb_data=0;
        assign emb_index=0;
        assign emb_last=0;
        assign done_valid=0;
        assign done_error=0;
        assign busy=0;
    end endgenerate
endmodule
