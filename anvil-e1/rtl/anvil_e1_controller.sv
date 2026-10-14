module anvil_e1_controller #(
    parameter integer VOCAB_SIZE=262144, HIDDEN_SIZE=512,
    PER_LAYER_INPUT_SIZE=512, INTERMEDIATE_SIZE=2048, EMBEDDING_DIM=768,
    NUM_LAYERS=24, NUM_Q_HEADS=4, LOCAL_KV_HEADS=2, FULL_KV_HEADS=1,
    LOCAL_HEAD_DIM=256, FULL_HEAD_DIM=512, MAX_SEQ_LEN=262144
) (
    input wire clk, rst_n,
    input wire job_valid,
    output wire job_ready,
    input wire [31:0] job_tokens,
    input wire [15:0] job_output_dim,
    input wire [63:0] weights_base, tokens_base, positions_base, mask_base, scratch_base,
    output wire busy,
    output wire cmd_valid,
    input wire cmd_ready,
    output wire [63:0] cmd_addr,
    input wire result_valid,
    output wire result_ready,
    input wire [31:0] result_data,
    input wire result_error,
    output wire engine_start_valid,
    input wire engine_start_ready,
    output reg [31:0] tokens, valid_tokens,
    output reg [15:0] output_dim,
    output reg [63:0] weights, token_ids, positions, masks, scratch,
    input wire engine_emb_valid,
    output wire engine_emb_ready,
    input wire signed [31:0] engine_emb_data,
    input wire [15:0] engine_emb_index,
    input wire engine_emb_last,
    input wire engine_done_valid,
    output wire engine_done_ready,
    input wire [3:0] engine_done_error,
    output wire emb_valid,
    input wire emb_ready,
    output wire signed [31:0] emb_data,
    output wire [15:0] emb_index,
    output wire emb_last,
    output wire done_valid,
    input wire done_ready,
    output wire [3:0] done_error
);
    localparam IDLE=0, CHECK=1, REQUEST=2, RESPONSE=3, START=4, RUN=5, DONE=6;
    reg [2:0] state;
    reg [31:0] index;
    reg [1:0] field;
    reg [3:0] error_hold;
    reg emb_hold, last_hold;
    reg signed [31:0] data_hold;
    reg [15:0] index_hold;
    wire [127:0] weight_size, scratch_size;
    wire [63:0] unused_tensor_addr, unused_scratch_addr;
    wire [31:0] unused_rows, unused_cols;
    wire unused_tensor_error, unused_scratch_error;
    wire [127:0] input_size={96'd0,tokens}*128'd4;
    wire overflow=({64'd0,weights}+weight_size>128'hffffffffffffffff) ||
                  ({64'd0,scratch}+scratch_size>128'hffffffffffffffff) ||
                  ({64'd0,token_ids}+input_size>128'hffffffffffffffff) ||
                  ({64'd0,positions}+input_size>128'hffffffffffffffff) ||
                  ({64'd0,masks}+input_size>128'hffffffffffffffff);

    initial begin
        if (VOCAB_SIZE<=0 || MAX_SEQ_LEN<=0 || NUM_LAYERS<=0 || NUM_LAYERS>65535 ||
            HIDDEN_SIZE<=0 || HIDDEN_SIZE>65535 ||
            PER_LAYER_INPUT_SIZE<=0 || PER_LAYER_INPUT_SIZE>65535 ||
            INTERMEDIATE_SIZE<=0 || INTERMEDIATE_SIZE>65535 ||
            EMBEDDING_DIM<6 || EMBEDDING_DIM>65535 || EMBEDDING_DIM%6!=0 ||
            NUM_Q_HEADS<=0 || NUM_Q_HEADS>65535 ||
            LOCAL_KV_HEADS<=0 || FULL_KV_HEADS<=0 ||
            LOCAL_HEAD_DIM<=0 || FULL_HEAD_DIM<=0 ||
            LOCAL_HEAD_DIM>65535 || FULL_HEAD_DIM>65535 ||
            LOCAL_HEAD_DIM%2!=0 || FULL_HEAD_DIM%2!=0 ||
            64'(NUM_Q_HEADS)*LOCAL_HEAD_DIM>65535 ||
            64'(NUM_Q_HEADS)*FULL_HEAD_DIM>65535)
            $fatal(1,"PARAMETER ERROR: unsupported Anvil-E1 geometry or vector width");
        if (LOCAL_KV_HEADS>0 && FULL_KV_HEADS>0)
            if (NUM_Q_HEADS%LOCAL_KV_HEADS!=0 || NUM_Q_HEADS%FULL_KV_HEADS!=0)
                $fatal(1,"PARAMETER ERROR: Q heads must divide into KV groups");
    end

    anvil_e1_address #(
        .VOCAB_SIZE(VOCAB_SIZE), .HIDDEN_SIZE(HIDDEN_SIZE),
        .PER_LAYER_INPUT_SIZE(PER_LAYER_INPUT_SIZE), .INTERMEDIATE_SIZE(INTERMEDIATE_SIZE),
        .EMBEDDING_DIM(EMBEDDING_DIM), .NUM_LAYERS(NUM_LAYERS),
        .NUM_Q_HEADS(NUM_Q_HEADS), .LOCAL_KV_HEADS(LOCAL_KV_HEADS),
        .FULL_KV_HEADS(FULL_KV_HEADS), .LOCAL_HEAD_DIM(LOCAL_HEAD_DIM),
        .FULL_HEAD_DIM(FULL_HEAD_DIM)
    ) sizes (
        .weights_base(weights), .scratch_base(scratch), .job_tokens(tokens),
        .tensor_id(5'd0), .layer_index(32'd0), .element_index(64'd0),
        .scratch_region(3'd0), .scratch_word(64'd0),
        .tensor_addr(unused_tensor_addr), .scratch_addr(unused_scratch_addr),
        .tensor_rows(unused_rows), .tensor_cols(unused_cols),
        .weights_bytes(weight_size), .scratch_bytes(scratch_size),
        .tensor_error(unused_tensor_error), .scratch_error(unused_scratch_error)
    );

    assign job_ready=rst_n && state==IDLE;
    assign busy=rst_n && state!=IDLE;
    assign cmd_valid=rst_n && state==REQUEST;
    assign cmd_addr=!rst_n ? 64'd0 :
        (field==0 ? token_ids:field==1 ? positions:masks)+{30'd0,index,2'b00};
    assign result_ready=rst_n && state==RESPONSE;
    assign engine_start_valid=rst_n && state==START;
    assign engine_emb_ready=rst_n && state==RUN && !emb_hold;
    assign engine_done_ready=rst_n && state==RUN && !emb_hold && !engine_emb_valid;
    assign emb_valid=rst_n && emb_hold;
    assign emb_data=rst_n ? data_hold:32'sd0;
    assign emb_index=rst_n ? index_hold:16'd0;
    assign emb_last=rst_n && last_hold;
    assign done_valid=rst_n && state==DONE;
    assign done_error=rst_n ? error_hold:4'd0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=IDLE; index<=0; field<=0; error_hold<=0;
            tokens<=0; valid_tokens<=0; output_dim<=0;
            weights<=0; token_ids<=0; positions<=0; masks<=0; scratch<=0;
            emb_hold<=0; last_hold<=0; data_hold<=0; index_hold<=0;
        end else begin
            if (emb_hold && emb_ready) emb_hold<=0;
            case (state)
                IDLE: if (job_valid) begin
                    tokens<=job_tokens; output_dim<=job_output_dim;
                    weights<=weights_base; token_ids<=tokens_base;
                    positions<=positions_base; masks<=mask_base; scratch<=scratch_base;
                    valid_tokens<=0; index<=0; field<=0; error_hold<=0;
                    data_hold<=0; index_hold<=0; last_hold<=0;
                    state<=CHECK;
                end
                CHECK: begin
                    if (tokens==0 || tokens>MAX_SEQ_LEN ||
                        !(output_dim==EMBEDDING_DIM || output_dim==2*EMBEDDING_DIM/3 ||
                          output_dim==EMBEDDING_DIM/3 || output_dim==EMBEDDING_DIM/6) ||
                        |weights[1:0] || |token_ids[1:0] || |positions[1:0] ||
                        |masks[1:0] || |scratch[1:0]) begin
                        error_hold<=1; state<=DONE;
                    end else if (overflow) begin
                        error_hold<=5; state<=DONE;
                    end else state<=REQUEST;
                end
                REQUEST: if (cmd_ready) state<=RESPONSE;
                RESPONSE: if (result_valid) begin
                    if (result_error) begin
                        error_hold<=3; state<=DONE;
                    end else if ((field==0 && result_data>=VOCAB_SIZE) ||
                                 (field==1 && result_data>=MAX_SEQ_LEN) ||
                                 (field==2 && result_data>1)) begin
                        error_hold<=2; state<=DONE;
                    end else if (field==2) begin
                        if (result_data==1) valid_tokens<=valid_tokens+1'b1;
                        field<=0;
                        if (index==tokens-1) begin
                            if (valid_tokens==0 && result_data==0) begin
                                error_hold<=4; state<=DONE;
                            end else state<=START;
                        end else begin
                            index<=index+1'b1; state<=REQUEST;
                        end
                    end else begin
                        field<=field+1'b1; state<=REQUEST;
                    end
                end
                START: if (engine_start_ready) state<=RUN;
                RUN: begin
                    if (engine_emb_valid && engine_emb_ready) begin
                        emb_hold<=1; data_hold<=engine_emb_data;
                        index_hold<=engine_emb_index; last_hold<=engine_emb_last;
                    end
                    if (engine_done_valid && engine_done_ready) begin
                        error_hold<=engine_done_error; state<=DONE;
                    end
                end
                DONE: if (done_ready) state<=IDLE;
                default: begin error_hold<=1; state<=DONE; end
            endcase
        end
    end
endmodule
