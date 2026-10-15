module anvil_e2_top #(
    parameter integer VISION_LAYERS=16, VISION_HIDDEN=768, VISION_FFN=3072,
    VISION_HEADS=12, VISION_HEAD_DIM=64, PATCH_SIZE=16, POOL_KERNEL=3,
    VISION_SOFT_TOKENS=280, TEXT_LAYERS=24, TEXT_HIDDEN=512, PLE_DIM=512,
    TEXT_FFN=2048, EMBED_DIM=768, VOCAB_SIZE=262144,
    POSITION_EMBEDDING_SIZE=10240, TEXT_Q_HEADS=4, LOCAL_KV_HEADS=2,
    FULL_KV_HEADS=1, LOCAL_HEAD_DIM=256, FULL_HEAD_DIM=512,
    SLIDING_WINDOW=512, MAX_SEQ_LEN=262144
) (
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
    localparam LEGAL=VISION_LAYERS>0 && VISION_LAYERS<=65535 &&
        TEXT_LAYERS>0 && TEXT_LAYERS<=65535 &&
        VISION_HIDDEN>0 && VISION_HIDDEN<=65535 &&
        VISION_FFN>0 && VISION_FFN<=65535 &&
        VISION_HEADS>0 && VISION_HEADS<=65535 &&
        VISION_HEAD_DIM>0 && VISION_HEAD_DIM%4==0 &&
        64'(VISION_HEADS)*VISION_HEAD_DIM==VISION_HIDDEN &&
        PATCH_SIZE>0 && 64'd3*PATCH_SIZE*PATCH_SIZE<=65535 &&
        POOL_KERNEL>0 && VISION_SOFT_TOKENS>0 &&
        TEXT_HIDDEN>0 && TEXT_HIDDEN<=65535 &&
        PLE_DIM>0 && PLE_DIM<=65535 && TEXT_FFN>0 && TEXT_FFN<=65535 &&
        EMBED_DIM>=6 && EMBED_DIM<=65535 && EMBED_DIM%6==0 &&
        VOCAB_SIZE>0 && POSITION_EMBEDDING_SIZE>0 && TEXT_Q_HEADS>0 &&
        LOCAL_KV_HEADS>0 && FULL_KV_HEADS>0 &&
        TEXT_Q_HEADS%LOCAL_KV_HEADS==0 && TEXT_Q_HEADS%FULL_KV_HEADS==0 &&
        LOCAL_HEAD_DIM>0 && FULL_HEAD_DIM>0 &&
        LOCAL_HEAD_DIM%2==0 && FULL_HEAD_DIM%2==0 &&
        64'(TEXT_Q_HEADS)*LOCAL_HEAD_DIM<=65535 &&
        64'(TEXT_Q_HEADS)*FULL_HEAD_DIM<=65535 &&
        SLIDING_WINDOW>0 && MAX_SEQ_LEN>0;
    generate if (LEGAL) begin : legal_datapath
        localparam IDLE=0, VALIDATE=1, START=2, WAIT=3, DONE=4;
        localparam integer DM=LOCAL_HEAD_DIM>FULL_HEAD_DIM ? LOCAL_HEAD_DIM:FULL_HEAD_DIM;
        localparam integer KM=LOCAL_KV_HEADS>FULL_KV_HEADS ? LOCAL_KV_HEADS:FULL_KV_HEADS;
        localparam [127:0] VH=VISION_HIDDEN, VF=VISION_FFN;
        localparam [127:0] VL_WORDS=4*VH+4*VH*VH+2*VISION_HEAD_DIM+3*VH*VF;
        localparam [127:0] BRIDGE_WORD=VH*3*PATCH_SIZE*PATCH_SIZE+
            2*POSITION_EMBEDDING_SIZE*VH+VISION_LAYERS*VL_WORDS;
        localparam [127:0] VWEIGHT_BYTES=(BRIDGE_WORD+128'(TEXT_HIDDEN)*VISION_HIDDEN)*4;
        reg [2:0] state, owner;
        reg [1:0] mode;
        reg [31:0] text_tokens, rows, cols, vision_layer, text_layer;
        reg [15:0] output_dim;
        reg [63:0] weights, vision_weights, image, ids, positions, masks, scratch;
        reg vision_x, text_x;
        reg [3:0] error_hold;
        wire image_mode=mode!=0;
        wire [127:0] p=image_mode ? 128'(rows)*cols:0;
        wire [127:0] s=image_mode ? VISION_SOFT_TOKENS:0;
        wire [127:0] n=128'(text_tokens)+(image_mode ? s+2:0);
        wire [127:0] vw=p*VISION_HIDDEN, va=p*VISION_HEADS*VISION_HEAD_DIM;
        wire [127:0] sw=s*TEXT_HIDDEN, tw=n*TEXT_HIDDEN;
        wire [127:0] pw=n*TEXT_LAYERS*PLE_DIM, qw=n*TEXT_Q_HEADS*DM, kw=n*KM*DM;
        wire [127:0] o_v0=0, o_v1=vw, o_vq=2*vw, o_vk=2*vw+va, o_vv=2*vw+2*va;
        wire [127:0] o_soft=2*vw+3*va, o_ids=o_soft+sw, o_pos=o_ids+n;
        wire [127:0] o_mask=o_pos+n, o_x0=o_mask+n, o_x1=o_x0+tw;
        wire [127:0] o_ple=o_x1+tw, o_q=o_ple+pw, o_k=o_q+qw, o_v=o_k+kw;
        wire [127:0] scratch_bytes=(o_v+kw)*4;
        wire [63:0] v0=scratch+64'(o_v0*4), v1=scratch+64'(o_v1*4);
        wire [63:0] vq=scratch+64'(o_vq*4), vk=scratch+64'(o_vk*4), vv=scratch+64'(o_vv*4);
        wire [63:0] soft_tokens_base=scratch+64'(o_soft*4), fid=scratch+64'(o_ids*4);
        wire [63:0] fpos=scratch+64'(o_pos*4), fmask=scratch+64'(o_mask*4);
        wire [63:0] x0=scratch+64'(o_x0*4), x1=scratch+64'(o_x1*4);
        wire [63:0] ple=scratch+64'(o_ple*4), tq=scratch+64'(o_q*4);
        wire [63:0] tk=scratch+64'(o_k*4), tv=scratch+64'(o_v*4);
        wire [127:0] weight_bytes, unused_scratch;
        anvil_e2_address #(
            .VOCAB_SIZE(VOCAB_SIZE), .HIDDEN_SIZE(TEXT_HIDDEN),
            .PER_LAYER_INPUT_SIZE(PLE_DIM), .INTERMEDIATE_SIZE(TEXT_FFN),
            .EMBEDDING_DIM(EMBED_DIM), .NUM_LAYERS(TEXT_LAYERS),
            .NUM_Q_HEADS(TEXT_Q_HEADS), .LOCAL_KV_HEADS(LOCAL_KV_HEADS),
            .FULL_KV_HEADS(FULL_KV_HEADS), .LOCAL_HEAD_DIM(LOCAL_HEAD_DIM),
            .FULL_HEAD_DIM(FULL_HEAD_DIM)
        ) text_extent (
            .weights_base(weights), .scratch_base(scratch), .job_tokens(32'(n)),
            .tensor_id(5'd0), .layer_index(32'd0), .element_index(64'd0),
            .scratch_region(3'd0), .scratch_word(64'd0), .tensor_addr(), .scratch_addr(),
            .tensor_rows(), .tensor_cols(), .weights_bytes(weight_bytes),
            .scratch_bytes(unused_scratch), .tensor_error(), .scratch_error()
        );
        function automatic overflow(input [63:0] base, input [127:0] bytes);
            overflow=({64'd0,base}+bytes)>128'hffffffffffffffff;
        endfunction
        wire descriptor_bad=mode==3 || n==0 || n>MAX_SEQ_LEN || n>32'hffffffff ||
            !(output_dim==EMBED_DIM || output_dim==2*EMBED_DIM/3 ||
              output_dim==EMBED_DIM/3 || output_dim==EMBED_DIM/6) ||
            (mode==1 && text_tokens!=0) || (mode==2 && text_tokens==0) ||
            |weights[1:0] || |scratch[1:0] ||
            (text_tokens!=0 && (|ids[1:0] || |positions[1:0] || |masks[1:0])) ||
            (image_mode && (rows==0 || cols==0 || rows>POSITION_EMBEDDING_SIZE ||
                cols>POSITION_EMBEDDING_SIZE || p>32'hffffffff ||
                ((128'(rows)+POOL_KERNEL-1)/POOL_KERNEL)*
                ((128'(cols)+POOL_KERNEL-1)/POOL_KERNEL)!=s ||
                |vision_weights[1:0] || |image[1:0] || VOCAB_SIZE<=258882));
        wire extent_bad=overflow(weights,weight_bytes) || overflow(scratch,scratch_bytes) ||
            (text_tokens!=0 && (overflow(ids,128'(text_tokens)*4) ||
                overflow(positions,128'(text_tokens)*4) || overflow(masks,128'(text_tokens)*4))) ||
            (image_mode && (overflow(vision_weights,VWEIGHT_BYTES) ||
                overflow(image,p*3*PATCH_SIZE*PATCH_SIZE*4)));
        wire [6:0] start_valids, start_readys, stage_valids, stage_writes;
        wire [6:0] stage_readys, result_valids, result_readys, stage_dones, done_readys;
        wire [63:0] stage_addrs [0:6];
        wire [31:0] stage_data [0:6];
        wire [3:0] stage_errors [0:6];
        wire bridge_ready, bridge_result_valid, bridge_result_error;
        wire [31:0] bridge_data;
        genvar g;
        for (g=0;g<7;g=g+1) begin : stage_channels
            assign start_valids[g]=rst_n && state==START && owner==g;
            assign stage_readys[g]=rst_n && state==WAIT && owner==g && bridge_ready;
            assign result_valids[g]=rst_n && state==WAIT && owner==g && bridge_result_valid;
            assign done_readys[g]=rst_n && state==WAIT && owner==g;
        end
        anvil_e2_memory memory_bridge (
            .clk(clk), .rst_n(rst_n), .cmd_valid(state==WAIT && stage_valids[owner]),
            .cmd_ready(bridge_ready), .cmd_write(stage_writes[owner]),
            .cmd_addr(stage_addrs[owner]), .cmd_wdata(stage_data[owner]),
            .result_valid(bridge_result_valid),
            .result_ready(state==WAIT && result_readys[owner]), .result_data(bridge_data),
            .result_error(bridge_result_error), .mem_req_valid(mem_req_valid),
            .mem_req_ready(mem_req_ready), .mem_req_write(mem_req_write),
            .mem_req_addr(mem_req_addr), .mem_req_wdata(mem_req_wdata),
            .mem_rsp_valid(mem_rsp_valid), .mem_rsp_ready(mem_rsp_ready),
            .mem_rsp_rdata(mem_rsp_rdata), .mem_rsp_error(mem_rsp_error)
        );
`define E2_MEMORY(I) \
        .clk(clk), .rst_n(rst_n), .start_valid(start_valids[I]), .start_ready(start_readys[I]), \
        .cmd_valid(stage_valids[I]), .cmd_ready(stage_readys[I]), .cmd_write(stage_writes[I]), \
        .cmd_addr(stage_addrs[I]), .cmd_wdata(stage_data[I]), .result_valid(result_valids[I]), \
        .result_ready(result_readys[I]), .result_data(bridge_data), .result_error(bridge_result_error), \
        .done_valid(stage_dones[I]), .done_ready(done_readys[I]), .done_error(stage_errors[I])
        anvil_e2_vision_patch_embed #(
            .VISION_HIDDEN(VISION_HIDDEN), .PATCH_SIZE(PATCH_SIZE),
            .POSITION_EMBEDDING_SIZE(POSITION_EMBEDDING_SIZE)
        ) patch_embed (
            `E2_MEMORY(0), .patch_rows(rows), .patch_cols(cols),
            .weights(vision_weights), .image(image), .output_base(v0)
        );
        anvil_e2_vision_encoder_layer #(
            .VISION_LAYERS(VISION_LAYERS), .VISION_HIDDEN(VISION_HIDDEN),
            .VISION_FFN(VISION_FFN), .VISION_HEADS(VISION_HEADS),
            .VISION_HEAD_DIM(VISION_HEAD_DIM), .PATCH_SIZE(PATCH_SIZE),
            .POSITION_EMBEDDING_SIZE(POSITION_EMBEDDING_SIZE)
        ) vision_encoder (
            `E2_MEMORY(1), .tokens(32'(p)), .layer_index(vision_layer), .patch_cols(cols),
            .weights(vision_weights), .x0_base(v0), .x1_base(v1), .q_base(vq),
            .k_base(vk), .v_base(vv), .start_current_x(vision_x)
        );
        anvil_e2_vision_pool_proj #(
            .VISION_HIDDEN(VISION_HIDDEN), .TEXT_HIDDEN(TEXT_HIDDEN),
            .POOL_KERNEL(POOL_KERNEL), .VISION_SOFT_TOKENS(VISION_SOFT_TOKENS)
        ) vision_pool (
            `E2_MEMORY(2), .patch_rows(rows), .patch_cols(cols),
            .weights(vision_weights+64'(BRIDGE_WORD*4)),
            .input_base(vision_x ? v1:v0), .output_base(soft_tokens_base)
        );
        wire [31:0] valid_tokens;
        anvil_e2_multimodal_fusion #(
            .TEXT_HIDDEN(TEXT_HIDDEN), .VISION_SOFT_TOKENS(VISION_SOFT_TOKENS),
            .VOCAB_SIZE(VOCAB_SIZE), .MAX_SEQ_LEN(MAX_SEQ_LEN)
        ) fusion (
            `E2_MEMORY(3), .mode(mode), .text_tokens(text_tokens), .weights(weights),
            .token_ids(ids), .positions(positions), .masks(masks), .soft_base(soft_tokens_base),
            .fused_ids(fid), .fused_positions(fpos), .fused_masks(fmask),
            .x0_base(x0), .valid_tokens(valid_tokens)
        );
`define E2_TEXT_PARAMETERS \
            .VOCAB_SIZE(VOCAB_SIZE), .HIDDEN_SIZE(TEXT_HIDDEN), .PER_LAYER_INPUT_SIZE(PLE_DIM), \
            .INTERMEDIATE_SIZE(TEXT_FFN), .EMBEDDING_DIM(EMBED_DIM), .NUM_LAYERS(TEXT_LAYERS), \
            .NUM_Q_HEADS(TEXT_Q_HEADS), .LOCAL_KV_HEADS(LOCAL_KV_HEADS), \
            .FULL_KV_HEADS(FULL_KV_HEADS), .LOCAL_HEAD_DIM(LOCAL_HEAD_DIM), \
            .FULL_HEAD_DIM(FULL_HEAD_DIM), .SLIDING_WINDOW(SLIDING_WINDOW)
`define E2_TEXT_PORTS(I) \
            `E2_MEMORY(I), .tokens(32'(n)), .valid_tokens(valid_tokens), .output_dim(output_dim), \
            .weights(weights), .token_ids(fid), .positions(fpos), .masks(fmask), .scratch(scratch), \
            .x0_base(x0), .x1_base(x1), .ple_base(ple), .q_base(tq), .k_base(tk), .v_base(tv), \
            .layer_index(text_layer), .patch_cols(cols), .start_current_x(text_x)
        anvil_e2_text_frontend_ple #(`E2_TEXT_PARAMETERS) text_frontend (
            `E2_TEXT_PORTS(4), .emb_valid(), .emb_ready(1'b0), .emb_data(), .emb_index(), .emb_last()
        );
        anvil_e2_hybrid_layer #(`E2_TEXT_PARAMETERS) hybrid_layer (
            `E2_TEXT_PORTS(5), .emb_valid(), .emb_ready(1'b0), .emb_data(), .emb_index(), .emb_last()
        );
        wire out_valid, out_last;
        wire signed [31:0] out_data;
        wire [15:0] out_index;
        anvil_e2_pool_norm #(`E2_TEXT_PARAMETERS) pool_norm (
            `E2_TEXT_PORTS(6), .emb_valid(out_valid),
            .emb_ready(emb_ready && state==WAIT && owner==6),
            .emb_data(out_data), .emb_index(out_index), .emb_last(out_last)
        );
`undef E2_MEMORY
`undef E2_TEXT_PARAMETERS
`undef E2_TEXT_PORTS
        assign job_ready=rst_n && state==IDLE;
        assign busy=rst_n && state!=IDLE;
        assign done_valid=rst_n && state==DONE;
        assign done_error=rst_n ? error_hold:4'd0;
        assign emb_valid=rst_n && state==WAIT && owner==6 && out_valid;
        assign emb_data=rst_n ? out_data:32'sd0;
        assign emb_index=rst_n ? out_index:16'd0;
        assign emb_last=rst_n && state==WAIT && owner==6 && out_last;
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                state<=IDLE; owner<=0; mode<=0; text_tokens<=0; rows<=0; cols<=0;
                output_dim<=0; weights<=0; vision_weights<=0; image<=0; ids<=0;
                positions<=0; masks<=0; scratch<=0; vision_layer<=0; text_layer<=0;
                vision_x<=0; text_x<=0; error_hold<=0;
            end else case (state)
                IDLE: if (job_valid) begin
                    mode<=job_mode; text_tokens<=job_tokens; rows<=job_patch_rows;
                    cols<=job_patch_cols; output_dim<=job_output_dim; weights<=weights_base;
                    vision_weights<=vision_weights_base; image<=image_base; ids<=tokens_base;
                    positions<=positions_base; masks<=mask_base; scratch<=scratch_base;
                    vision_layer<=0; text_layer<=0; vision_x<=0; text_x<=0;
                    error_hold<=0; state<=VALIDATE;
                end
                VALIDATE: begin
                    if (descriptor_bad) begin error_hold<=1; state<=DONE; end
                    else if (extent_bad) begin error_hold<=5; state<=DONE; end
                    else begin
                        if (image_mode) owner<=0; else owner<=3;
                        state<=START;
                    end
                end
                START: if (start_readys[owner]) state<=WAIT;
                WAIT: if (stage_dones[owner]) begin
                    if (stage_errors[owner]!=0) begin error_hold<=stage_errors[owner]; state<=DONE; end
                    else begin
                        state<=START;
                        case (owner)
                            0: owner<=1;
                            1: begin
                                vision_x<=!vision_x;
                                if (vision_layer==VISION_LAYERS-1) owner<=2;
                                else vision_layer<=vision_layer+1;
                            end
                            2: owner<=3;
                            3: owner<=4;
                            4: owner<=5;
                            5: begin
                                text_x<=!text_x;
                                if (text_layer==TEXT_LAYERS-1) owner<=6;
                                else text_layer<=text_layer+1;
                            end
                            6: state<=DONE;
                            default: begin error_hold<=6; state<=DONE; end
                        endcase
                    end
                end
                DONE: if (done_ready) state<=IDLE;
                default: begin error_hold<=6; state<=DONE; end
            endcase
        end
    end else begin : invalid_parameters
        initial $fatal(1,"PARAMETER ERROR: unsupported Anvil-E2 geometry");
        assign job_ready=0; assign busy=0; assign mem_req_valid=0;
        assign mem_req_write=0; assign mem_req_addr=0; assign mem_req_wdata=0;
        assign mem_rsp_ready=0; assign emb_valid=0; assign emb_data=0;
        assign emb_index=0; assign emb_last=0; assign done_valid=0; assign done_error=0;
    end endgenerate
endmodule
