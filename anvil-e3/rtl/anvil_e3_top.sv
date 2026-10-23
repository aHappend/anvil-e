module anvil_e3_top #(
    parameter integer AUDIO_LAYERS=12, AUDIO_HIDDEN=1024, AUDIO_FFN=4096,
    AUDIO_HEADS=8, AUDIO_HEAD_DIM=128, AUDIO_OUT_DIM=1536, AUDIO_CONV_KERNEL=5,
    AUDIO_SUBSAMPLE_C0=128, AUDIO_SUBSAMPLE_C1=32, AUDIO_FREQ_BINS=128,
    AUDIO_CHUNK_SIZE=12, AUDIO_CONTEXT_LEFT=13, AUDIO_CONTEXT_RIGHT=0,
    VISION_LAYERS=16, VISION_HIDDEN=768, VISION_FFN=3072,
    VISION_HEADS=12, VISION_HEAD_DIM=64, PATCH_SIZE=16, POOL_KERNEL=3,
    VISION_SOFT_TOKENS=280, TEXT_LAYERS=24, TEXT_HIDDEN=512, PLE_DIM=512,
    TEXT_FFN=2048, EMBED_DIM=768, VOCAB_SIZE=262144,
    POSITION_EMBEDDING_SIZE=10240, TEXT_Q_HEADS=4, LOCAL_KV_HEADS=2,
    FULL_KV_HEADS=1, LOCAL_HEAD_DIM=256, FULL_HEAD_DIM=512,
    SLIDING_WINDOW=512, MAX_SEQ_LEN=262144
) (
    input wire clk, rst_n, job_valid,
    input wire [2:0] job_mode,
    input wire [31:0] job_tokens, job_patch_rows, job_patch_cols, job_audio_frames,
    input wire [15:0] job_output_dim,
    input wire [63:0] weights_base, vision_weights_base, audio_weights_base,
    input wire [63:0] image_base, audio_base, tokens_base, positions_base, mask_base, scratch_base,
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
    localparam LEGAL=AUDIO_LAYERS>0 && AUDIO_LAYERS<=65535 &&
        AUDIO_HIDDEN>0 && 64'(AUDIO_HIDDEN)*2<=65535 &&
        AUDIO_FFN>0 && AUDIO_FFN<=65535 &&
        AUDIO_HEADS>0 && AUDIO_HEADS<=65535 &&
        AUDIO_HEAD_DIM>0 && AUDIO_HEAD_DIM<=65535 &&
        64'(AUDIO_HEADS)*AUDIO_HEAD_DIM==AUDIO_HIDDEN &&
        AUDIO_OUT_DIM>0 && AUDIO_OUT_DIM<=65535 &&
        AUDIO_CONV_KERNEL>0 && AUDIO_CONV_KERNEL<=65535 && AUDIO_CONV_KERNEL%2==1 &&
        AUDIO_SUBSAMPLE_C0>0 && AUDIO_SUBSAMPLE_C0<=65535 &&
        AUDIO_SUBSAMPLE_C1>0 && AUDIO_SUBSAMPLE_C1<=65535 &&
        AUDIO_FREQ_BINS>0 && AUDIO_FREQ_BINS<=65535 &&
        64'(AUDIO_SUBSAMPLE_C1)*((64'(AUDIO_FREQ_BINS)+3)/4)<=65535 &&
        AUDIO_CHUNK_SIZE>0 && AUDIO_CONTEXT_LEFT>=0 && AUDIO_CONTEXT_RIGHT>=0 &&
        VISION_LAYERS>0 && VISION_LAYERS<=65535 &&
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
        localparam integer AW=AUDIO_FFN>2*AUDIO_HIDDEN ? AUDIO_FFN:2*AUDIO_HIDDEN;
        localparam [127:0] VH=VISION_HIDDEN, VF=VISION_FFN;
        localparam [127:0] VL_WORDS=4*VH+4*VH*VH+2*VISION_HEAD_DIM+3*VH*VF;
        localparam [127:0] BRIDGE_WORD=VH*3*PATCH_SIZE*PATCH_SIZE+
            2*POSITION_EMBEDDING_SIZE*VH+VISION_LAYERS*VL_WORDS;
        localparam [127:0] VWEIGHT_BYTES=(BRIDGE_WORD+128'(TEXT_HIDDEN)*VISION_HIDDEN)*4;
        localparam [127:0] AF1=(128'(AUDIO_FREQ_BINS)+1)/2;
        localparam [127:0] AF2=(128'(AUDIO_FREQ_BINS)+3)/4;
        reg [2:0] state;
        reg [3:0] owner;
        reg [2:0] mode;
        reg [31:0] text_tokens, rows, cols, frames, audio_layer, vision_layer, text_layer;
        reg [15:0] output_dim;
        reg [63:0] weights, vision_weights, audio_weights, image, audio;
        reg [63:0] ids, positions, masks, scratch;
        reg [63:0] p_reg, pooled_rows_reg, pooled_cols_reg, at1_reg, at2_reg, n_reg;
        reg [63:0] v0, v1, vq, vk, vv, soft_tokens_base, fid, fpos, fmask;
        reg [63:0] x0, x1, ple, tq, tk, tv, asub, ax0, ax1, aw0, aw1;
        reg [63:0] aq, ak, av, aa, aout, asoft;
        reg audio_x, vision_x, text_x;
        reg [3:0] error_hold;
        wire job_audio_mode=job_mode>=3 && job_mode<=6;
        wire job_image_mode=job_mode==1 || job_mode==2 || job_mode==5 || job_mode==6;
        wire [32:0] job_pooled_rows, job_pooled_cols, pooled_row_remainder, pooled_col_remainder;
        anvil_e3_constant_divide #(.WIDTH(33), .DIVISOR(33'(POOL_KERNEL)))
            row_extent (.numerator(33'(job_patch_rows)+POOL_KERNEL-1),
                .quotient(job_pooled_rows), .remainder(pooled_row_remainder));
        anvil_e3_constant_divide #(.WIDTH(33), .DIVISOR(33'(POOL_KERNEL)))
            column_extent (.numerator(33'(job_patch_cols)+POOL_KERNEL-1),
                .quotient(job_pooled_cols), .remainder(pooled_col_remainder));
        wire audio_mode=mode>=3 && mode<=6;
        wire image_mode=mode==1 || mode==2 || mode==5 || mode==6;
        wire text_mode=mode==0 || mode==2 || mode==4 || mode==6;
        wire [127:0] p={64'd0,p_reg};
        wire [127:0] s=image_mode ? VISION_SOFT_TOKENS:0;
        wire [127:0] at1={64'd0,at1_reg};
        wire [127:0] at2={64'd0,at2_reg};
        wire [63:0] pooled_rows=pooled_rows_reg;
        wire [63:0] pooled_cols=pooled_cols_reg;
        wire [127:0] n={64'd0,n_reg};
        localparam [127:0] VA_STRIDE=128'(VISION_HEADS)*VISION_HEAD_DIM;
        localparam [127:0] P_SOFT_STRIDE=2*128'(VISION_HIDDEN)+3*VA_STRIDE;
        localparam [127:0] PLE_STRIDE=128'(TEXT_LAYERS)*PLE_DIM;
        localparam [127:0] QW_STRIDE=128'(TEXT_Q_HEADS)*DM;
        localparam [127:0] KW_STRIDE=128'(KM)*DM;
        localparam [127:0] N_SUB_STRIDE=128'd3+2*128'(TEXT_HIDDEN)+PLE_STRIDE+QW_STRIDE+2*KW_STRIDE;
        localparam [127:0] AC0_STRIDE=AF1*AUDIO_SUBSAMPLE_C0;
        localparam [127:0] AC1_STRIDE=AF2*AUDIO_SUBSAMPLE_C1;
        localparam [127:0] AT2_TOTAL_STRIDE=3*AC1_STRIDE+6*128'(AUDIO_HIDDEN)+
            2*128'(AW)+128'(AUDIO_OUT_DIM)+128'(TEXT_HIDDEN);
        wire [127:0] vw=p*VISION_HIDDEN, va=p*VA_STRIDE;
        wire [127:0] sw=s*TEXT_HIDDEN;
        wire [127:0] o_v0=0, o_v1=vw, o_vq=2*vw, o_vk=2*vw+va, o_vv=2*vw+2*va;
        wire [127:0] o_soft=p*P_SOFT_STRIDE, o_ids=o_soft+sw, o_pos=o_ids+n;
        wire [127:0] o_mask=o_ids+2*n, o_x0=o_ids+3*n;
        wire [127:0] o_x1=o_ids+n*(3+TEXT_HIDDEN);
        wire [127:0] o_ple=o_ids+n*(3+2*TEXT_HIDDEN);
        wire [127:0] o_q=o_ids+n*(3+2*TEXT_HIDDEN+PLE_STRIDE);
        wire [127:0] o_k=o_ids+n*(3+2*TEXT_HIDDEN+PLE_STRIDE+QW_STRIDE);
        wire [127:0] o_v=o_ids+n*(3+2*TEXT_HIDDEN+PLE_STRIDE+QW_STRIDE+KW_STRIDE);
        wire [127:0] o_sub=o_ids+n*N_SUB_STRIDE;
        wire [127:0] o_ax0=o_sub+2*at1*AC0_STRIDE+3*at2*AC1_STRIDE;
        wire [127:0] o_ax1=o_ax0+at2*AUDIO_HIDDEN;
        wire [127:0] o_aw0=o_ax0+at2*(2*AUDIO_HIDDEN);
        wire [127:0] o_aw1=o_ax0+at2*(2*AUDIO_HIDDEN+AW);
        wire [127:0] o_aq=o_ax0+at2*(2*AUDIO_HIDDEN+2*AW);
        wire [127:0] o_ak=o_ax0+at2*(3*AUDIO_HIDDEN+2*AW);
        wire [127:0] o_av=o_ax0+at2*(4*AUDIO_HIDDEN+2*AW);
        wire [127:0] o_att=o_ax0+at2*(5*AUDIO_HIDDEN+2*AW);
        wire [127:0] o_aout=o_ax0+at2*(6*AUDIO_HIDDEN+2*AW);
        wire [127:0] o_asoft=o_ax0+at2*(6*AUDIO_HIDDEN+2*AW+AUDIO_OUT_DIM);
        wire [127:0] scratch_bytes=(o_sub+2*at1*AC0_STRIDE+at2*AT2_TOTAL_STRIDE)*4;
        wire [127:0] weight_bytes, audio_weight_bytes;
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
            .scratch_bytes(), .tensor_error(), .scratch_error()
        );
`define E3_AUDIO_PARAMETERS \
            .AUDIO_LAYERS(AUDIO_LAYERS), .AUDIO_HIDDEN(AUDIO_HIDDEN), .AUDIO_FFN(AUDIO_FFN), \
            .AUDIO_HEAD_DIM(AUDIO_HEAD_DIM), .AUDIO_OUT_DIM(AUDIO_OUT_DIM), \
            .AUDIO_CONV_KERNEL(AUDIO_CONV_KERNEL), .AUDIO_SUBSAMPLE_C0(AUDIO_SUBSAMPLE_C0), \
            .AUDIO_SUBSAMPLE_C1(AUDIO_SUBSAMPLE_C1), .AUDIO_FREQ_BINS(AUDIO_FREQ_BINS), \
            .TEXT_HIDDEN(TEXT_HIDDEN)
        anvil_e3_audio_layout #(`E3_AUDIO_PARAMETERS) audio_extent (
            .weights_base(audio_weights), .layer_index(32'd0), .tensor_group(6'd0),
            .tensor_addr(), .weights_bytes(audio_weight_bytes), .address_error()
        );
        function automatic overflow(input [63:0] base, input [127:0] bytes);
            overflow=({64'd0,base}+bytes)>128'hffffffffffffffff;
        endfunction
        wire descriptor_bad=mode==7 || n==0 || n>MAX_SEQ_LEN || n>32'hffffffff ||
            !(output_dim==EMBED_DIM || output_dim==2*EMBED_DIM/3 ||
              output_dim==EMBED_DIM/3 || output_dim==EMBED_DIM/6) ||
            (text_mode && text_tokens==0) || (!text_mode && text_tokens!=0) ||
            |weights[1:0] || |scratch[1:0] ||
            (text_mode && (|ids[1:0] || |positions[1:0] || |masks[1:0])) ||
            (audio_mode && (frames==0 || |audio_weights[1:0] ||
                |audio[1:0] || VOCAB_SIZE<=258883)) ||
            (image_mode && (rows==0 || cols==0 || rows>POSITION_EMBEDDING_SIZE ||
                cols>POSITION_EMBEDDING_SIZE || p>32'hffffffff ||
                128'(pooled_rows)*pooled_cols!=s ||
                |vision_weights[1:0] || |image[1:0] || VOCAB_SIZE<=258882));
        wire extent_bad=overflow(weights,weight_bytes) || overflow(scratch,scratch_bytes) ||
            (text_mode && (overflow(ids,128'(text_tokens)*4) ||
                overflow(positions,128'(text_tokens)*4) || overflow(masks,128'(text_tokens)*4))) ||
            (audio_mode && (overflow(audio_weights,audio_weight_bytes) ||
                overflow(audio,128'(frames)*AUDIO_FREQ_BINS*4))) ||
            (image_mode && (overflow(vision_weights,VWEIGHT_BYTES) ||
                overflow(image,p*3*PATCH_SIZE*PATCH_SIZE*4)));
        wire [9:0] start_valids, start_readys, stage_valids, stage_writes;
        wire [9:0] stage_readys, result_valids, result_readys, stage_dones, done_readys;
        wire [63:0] stage_addrs [0:9];
        wire [31:0] stage_data [0:9];
        wire [3:0] stage_errors [0:9];
        wire bridge_ready, bridge_result_valid, bridge_result_error;
        wire [31:0] bridge_data;
        genvar g;
        for (g=0;g<10;g=g+1) begin : stage_channels
            assign start_valids[g]=rst_n && state==START && owner==g;
            assign stage_readys[g]=rst_n && state==WAIT && owner==g && bridge_ready;
            assign result_valids[g]=rst_n && state==WAIT && owner==g && bridge_result_valid;
            assign done_readys[g]=rst_n && state==WAIT && owner==g;
        end
        anvil_e2_memory memory_bridge (
            .clk(clk), .rst_n(rst_n), .cmd_valid(state==WAIT && stage_valids[owner]),
            .cmd_ready(bridge_ready), .cmd_write(stage_writes[owner]),
            .cmd_addr(stage_addrs[owner]), .cmd_wdata(stage_data[owner]),
            .result_valid(bridge_result_valid), .result_ready(state==WAIT && result_readys[owner]),
            .result_data(bridge_data), .result_error(bridge_result_error),
            .mem_req_valid(mem_req_valid), .mem_req_ready(mem_req_ready),
            .mem_req_write(mem_req_write), .mem_req_addr(mem_req_addr),
            .mem_req_wdata(mem_req_wdata), .mem_rsp_valid(mem_rsp_valid),
            .mem_rsp_ready(mem_rsp_ready), .mem_rsp_rdata(mem_rsp_rdata), .mem_rsp_error(mem_rsp_error)
        );
`define E3_MEMORY(I) \
        .clk(clk), .rst_n(rst_n), .start_valid(start_valids[I]), .start_ready(start_readys[I]), \
        .cmd_valid(stage_valids[I]), .cmd_ready(stage_readys[I]), .cmd_write(stage_writes[I]), \
        .cmd_addr(stage_addrs[I]), .cmd_wdata(stage_data[I]), .result_valid(result_valids[I]), \
        .result_ready(result_readys[I]), .result_data(bridge_data), .result_error(bridge_result_error), \
        .done_valid(stage_dones[I]), .done_ready(done_readys[I]), .done_error(stage_errors[I])
        anvil_e3_audio_subsample #(
            .AUDIO_HIDDEN(AUDIO_HIDDEN), .AUDIO_SUBSAMPLE_C0(AUDIO_SUBSAMPLE_C0),
            .AUDIO_SUBSAMPLE_C1(AUDIO_SUBSAMPLE_C1), .AUDIO_FREQ_BINS(AUDIO_FREQ_BINS)
        ) audio_subsample (
            `E3_MEMORY(0), .frames(frames), .weights(audio_weights), .input_base(audio),
            .work_base(asub), .output_base(ax0)
        );
        anvil_e3_audio_conformer_layer #(
            `E3_AUDIO_PARAMETERS, .AUDIO_HEADS(AUDIO_HEADS),
            .AUDIO_CHUNK_SIZE(AUDIO_CHUNK_SIZE), .AUDIO_CONTEXT_LEFT(AUDIO_CONTEXT_LEFT),
            .AUDIO_CONTEXT_RIGHT(AUDIO_CONTEXT_RIGHT)
        ) audio_conformer (
            `E3_MEMORY(1), .tokens(32'(at2)), .layer_index(audio_layer),
            .weights(audio_weights), .x0_base(ax0), .x1_base(ax1),
            .work0_base(aw0), .work1_base(aw1), .q_base(aq), .k_base(ak),
            .v_base(av), .attention_base(aa), .start_current_x(audio_x)
        );
        anvil_e3_audio_bridge #(`E3_AUDIO_PARAMETERS) audio_bridge (
            `E3_MEMORY(2), .tokens(32'(at2)), .weights(audio_weights),
            .input_base(audio_x ? ax1:ax0), .work_base(aout), .output_base(asoft)
        );
        anvil_e2_vision_patch_embed #(
            .VISION_HIDDEN(VISION_HIDDEN), .PATCH_SIZE(PATCH_SIZE),
            .POSITION_EMBEDDING_SIZE(POSITION_EMBEDDING_SIZE)
        ) vision_patch_embed (
            `E3_MEMORY(3), .patch_rows(rows), .patch_cols(cols),
            .weights(vision_weights), .image(image), .output_base(v0)
        );
        anvil_e2_vision_encoder_layer #(
            .VISION_LAYERS(VISION_LAYERS), .VISION_HIDDEN(VISION_HIDDEN),
            .VISION_FFN(VISION_FFN), .VISION_HEADS(VISION_HEADS),
            .VISION_HEAD_DIM(VISION_HEAD_DIM), .PATCH_SIZE(PATCH_SIZE),
            .POSITION_EMBEDDING_SIZE(POSITION_EMBEDDING_SIZE)
        ) vision_encoder (
            `E3_MEMORY(4), .tokens(32'(p)), .layer_index(vision_layer), .patch_cols(cols),
            .weights(vision_weights), .x0_base(v0), .x1_base(v1), .q_base(vq),
            .k_base(vk), .v_base(vv), .start_current_x(vision_x)
        );
        anvil_e2_vision_pool_proj #(
            .VISION_HIDDEN(VISION_HIDDEN), .TEXT_HIDDEN(TEXT_HIDDEN),
            .POOL_KERNEL(POOL_KERNEL), .VISION_SOFT_TOKENS(VISION_SOFT_TOKENS)
        ) vision_pool (
            `E3_MEMORY(5), .patch_rows(rows), .patch_cols(cols),
            .weights(vision_weights+64'(BRIDGE_WORD*4)),
            .input_base(vision_x ? v1:v0), .output_base(soft_tokens_base)
        );
        wire [31:0] valid_tokens;
        anvil_e3_trimodal_fusion #(
            .TEXT_HIDDEN(TEXT_HIDDEN), .VISION_SOFT_TOKENS(VISION_SOFT_TOKENS),
            .VOCAB_SIZE(VOCAB_SIZE), .MAX_SEQ_LEN(MAX_SEQ_LEN)
        ) trimodal_fusion (
            `E3_MEMORY(6), .mode(mode), .text_tokens(text_tokens), .audio_tokens(32'(at2)),
            .weights(weights), .token_ids(ids), .positions(positions), .masks(masks),
            .soft_base(soft_tokens_base), .audio_soft_base(asoft),
            .fused_ids(fid), .fused_positions(fpos), .fused_masks(fmask),
            .x0_base(x0), .valid_tokens(valid_tokens)
        );
`define E3_TEXT_PARAMETERS \
            .VOCAB_SIZE(VOCAB_SIZE), .HIDDEN_SIZE(TEXT_HIDDEN), .PER_LAYER_INPUT_SIZE(PLE_DIM), \
            .INTERMEDIATE_SIZE(TEXT_FFN), .EMBEDDING_DIM(EMBED_DIM), .NUM_LAYERS(TEXT_LAYERS), \
            .NUM_Q_HEADS(TEXT_Q_HEADS), .LOCAL_KV_HEADS(LOCAL_KV_HEADS), \
            .FULL_KV_HEADS(FULL_KV_HEADS), .LOCAL_HEAD_DIM(LOCAL_HEAD_DIM), \
            .FULL_HEAD_DIM(FULL_HEAD_DIM), .SLIDING_WINDOW(SLIDING_WINDOW)
`define E3_TEXT_PORTS(I) \
            `E3_MEMORY(I), .tokens(32'(n)), .valid_tokens(valid_tokens), .output_dim(output_dim), \
            .weights(weights), .token_ids(fid), .positions(fpos), .masks(fmask), .scratch(scratch), \
            .x0_base(x0), .x1_base(x1), .ple_base(ple), .q_base(tq), .k_base(tk), .v_base(tv), \
            .layer_index(text_layer), .patch_cols(cols), .start_current_x(text_x)
        anvil_e2_text_frontend_ple #(`E3_TEXT_PARAMETERS) text_frontend (
            `E3_TEXT_PORTS(7), .emb_valid(), .emb_ready(1'b0), .emb_data(), .emb_index(), .emb_last()
        );
        anvil_e2_hybrid_layer #(`E3_TEXT_PARAMETERS) hybrid_layer (
            `E3_TEXT_PORTS(8), .emb_valid(), .emb_ready(1'b0), .emb_data(), .emb_index(), .emb_last()
        );
        wire out_valid, out_last;
        wire signed [31:0] out_data;
        wire [15:0] out_index;
        anvil_e2_pool_norm #(`E3_TEXT_PARAMETERS) pool_norm (
            `E3_TEXT_PORTS(9), .emb_valid(out_valid),
            .emb_ready(emb_ready && state==WAIT && owner==9),
            .emb_data(out_data), .emb_index(out_index), .emb_last(out_last)
        );
`undef E3_AUDIO_PARAMETERS
`undef E3_MEMORY
`undef E3_TEXT_PARAMETERS
`undef E3_TEXT_PORTS
        assign job_ready=rst_n && state==IDLE;
        assign busy=rst_n && state!=IDLE;
        assign done_valid=rst_n && state==DONE;
        assign done_error=rst_n ? error_hold:4'd0;
        assign emb_valid=rst_n && state==WAIT && owner==9 && out_valid;
        assign emb_data=rst_n ? out_data:32'sd0;
        assign emb_index=rst_n ? out_index:16'd0;
        assign emb_last=rst_n && state==WAIT && owner==9 && out_last;
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                state<=IDLE; owner<=0; mode<=0; text_tokens<=0; rows<=0; cols<=0; frames<=0;
                output_dim<=0; weights<=0; vision_weights<=0; audio_weights<=0;
                image<=0; audio<=0; ids<=0; positions<=0; masks<=0; scratch<=0;
                p_reg<=0; pooled_rows_reg<=0; pooled_cols_reg<=0;
                at1_reg<=0; at2_reg<=0; n_reg<=0;
                v0<=0; v1<=0; vq<=0; vk<=0; vv<=0; soft_tokens_base<=0;
                fid<=0; fpos<=0; fmask<=0; x0<=0; x1<=0; ple<=0; tq<=0; tk<=0; tv<=0;
                asub<=0; ax0<=0; ax1<=0; aw0<=0; aw1<=0; aq<=0; ak<=0; av<=0;
                aa<=0; aout<=0; asoft<=0;
                audio_layer<=0; vision_layer<=0; text_layer<=0;
                audio_x<=0; vision_x<=0; text_x<=0; error_hold<=0;
            end else case (state)
                IDLE: if (job_valid) begin
                    mode<=job_mode; text_tokens<=job_tokens; rows<=job_patch_rows;
                    cols<=job_patch_cols; frames<=job_audio_frames; output_dim<=job_output_dim;
                    weights<=weights_base; vision_weights<=vision_weights_base;
                    audio_weights<=audio_weights_base; image<=image_base; audio<=audio_base;
                    ids<=tokens_base; positions<=positions_base; masks<=mask_base; scratch<=scratch_base;
                    p_reg<=job_image_mode ? (64'(job_patch_rows)*64'(job_patch_cols)):64'd0;
                    pooled_rows_reg<={31'd0,job_pooled_rows};
                    pooled_cols_reg<={31'd0,job_pooled_cols};
                    at1_reg<=job_audio_mode ? ((64'(job_audio_frames)+64'd1)>>1):64'd0;
                    at2_reg<=job_audio_mode ? ((64'(job_audio_frames)+64'd3)>>2):64'd0;
                    n_reg<=64'(job_tokens)+
                        (job_image_mode ? (64'(VISION_SOFT_TOKENS)+64'd2):64'd0)+
                        (job_audio_mode ? (((64'(job_audio_frames)+64'd3)>>2)+64'd2):64'd0);
                    audio_layer<=0; vision_layer<=0; text_layer<=0;
                    audio_x<=0; vision_x<=0; text_x<=0; error_hold<=0; state<=VALIDATE;
                end
                VALIDATE: begin
                    v0<=scratch+64'(o_v0*4); v1<=scratch+64'(o_v1*4);
                    vq<=scratch+64'(o_vq*4); vk<=scratch+64'(o_vk*4); vv<=scratch+64'(o_vv*4);
                    soft_tokens_base<=scratch+64'(o_soft*4); fid<=scratch+64'(o_ids*4);
                    fpos<=scratch+64'(o_pos*4); fmask<=scratch+64'(o_mask*4);
                    x0<=scratch+64'(o_x0*4); x1<=scratch+64'(o_x1*4);
                    ple<=scratch+64'(o_ple*4); tq<=scratch+64'(o_q*4);
                    tk<=scratch+64'(o_k*4); tv<=scratch+64'(o_v*4);
                    asub<=scratch+64'(o_sub*4); ax0<=scratch+64'(o_ax0*4);
                    ax1<=scratch+64'(o_ax1*4); aw0<=scratch+64'(o_aw0*4);
                    aw1<=scratch+64'(o_aw1*4); aq<=scratch+64'(o_aq*4);
                    ak<=scratch+64'(o_ak*4); av<=scratch+64'(o_av*4);
                    aa<=scratch+64'(o_att*4); aout<=scratch+64'(o_aout*4);
                    asoft<=scratch+64'(o_asoft*4);
                    if (descriptor_bad) begin error_hold<=1; state<=DONE; end
                    else if (extent_bad) begin error_hold<=5; state<=DONE; end
                    else begin
                        if (audio_mode) owner<=0;
                        else if (image_mode) owner<=3;
                        else owner<=6;
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
                                audio_x<=!audio_x;
                                if (audio_layer==AUDIO_LAYERS-1) owner<=2;
                                else audio_layer<=audio_layer+1'b1;
                            end
                            2: begin if (image_mode) owner<=3; else owner<=6; end
                            3: owner<=4;
                            4: begin
                                vision_x<=!vision_x;
                                if (vision_layer==VISION_LAYERS-1) owner<=5;
                                else vision_layer<=vision_layer+1'b1;
                            end
                            5: owner<=6;
                            6: owner<=7;
                            7: owner<=8;
                            8: begin
                                text_x<=!text_x;
                                if (text_layer==TEXT_LAYERS-1) owner<=9;
                                else text_layer<=text_layer+1'b1;
                            end
                            9: state<=DONE;
                            default: begin error_hold<=6; state<=DONE; end
                        endcase
                    end
                end
                DONE: if (done_ready) state<=IDLE;
                default: begin error_hold<=6; state<=DONE; end
            endcase
        end
    end else begin : invalid_parameters
        initial $fatal(1,"PARAMETER ERROR: unsupported Anvil-E3 geometry");
        assign job_ready=0; assign busy=0; assign mem_req_valid=0;
        assign mem_req_write=0; assign mem_req_addr=0; assign mem_req_wdata=0;
        assign mem_rsp_ready=0; assign emb_valid=0; assign emb_data=0;
        assign emb_index=0; assign emb_last=0; assign done_valid=0; assign done_error=0;
    end endgenerate
endmodule
