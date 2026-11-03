module anvil_en1_top #(
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
    SLIDING_WINDOW=512, MAX_SEQ_LEN=262144,
    COMPACT=0, RESIDENT_ENTRIES=3, FORCE_FALLBACK=0
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
    output wire busy,
    input wire [1:0] job_model, job_precision,
    input wire job_decode,
    input wire [31:0] job_position,
    input wire [63:0] kv_base,
    output wire logit_valid,
    input wire logit_ready,
    output wire [15:0] logit_data,
    output wire [17:0] logit_index,
    output wire logit_last,
    input wire csr_valid, csr_write,
    input wire [11:0] csr_addr,
    input wire [31:0] csr_wdata,
    output wire csr_ready, csr_rsp_valid,
    input wire csr_rsp_ready,
    output wire [31:0] csr_rdata,
    output wire csr_error
);
    localparam [4:0] IDLE=0, VALIDATE=1, PARENT_START=2, PARENT_WAIT=3,
        POSITION_SEND=4, POSITION_WAIT=5, POSITION_CHECK=6,
        NATIVE_START=7, NATIVE_WAIT=8, PUBLISH=9, RESPONSE=10,
        ALLOCATION_DRAIN=11, ALLOCATION_CHECK=12,
        MASK_SCAN_SEND=13, MASK_SCAN_WAIT=14, MASK_SCAN_CHECK=15,
        BASELINE_COUNTS=16, BASELINE_SCALE=17, BASELINE_SUM=18,
        SCAN_ADVANCE=19;
    reg [4:0] state;
    reg [3:0] error_hold;
    reg [1:0] model_hold, precision_hold;
    reg [2:0] mode_hold;
    reg decode_hold;
    reg [31:0] tokens_hold, rows_hold, columns_hold, frames_hold, position_hold;
    reg [15:0] output_hold;
    reg [63:0] weights_hold, vision_weights_hold, audio_weights_hold;
    reg [63:0] image_hold, audio_hold, ids_hold, positions_hold, masks_hold;
    reg [63:0] scratch_hold, kv_hold;
    reg [31:0] scan_index, scan_data, generation;
    reg scan_error;
    reg session_valid;
    reg [31:0] session_tokens;
    reg [1:0] session_model, session_precision;
    reg [2:0] session_mode;
    reg [63:0] session_weights, session_vision_weights, session_audio_weights;
    reg [63:0] session_image, session_audio, session_ids, session_positions, session_masks;
    reg [31:0] session_rows, session_columns, session_frames;
    reg [14:0] baseline_local_units;
    reg [20:0] baseline_global_units;
    reg [31:0] baseline_payload;
    reg [14:0] production_local_units;
    reg [31:0] production_baseline_payload;
    reg [3:0] allocation_wait;
    reg [31:0] traffic_local_write_units, traffic_global_write_units;
    reg [31:0] traffic_local_span, traffic_global_span;
    reg [31:0] traffic_local_read_units, traffic_global_read_units;
    reg [63:0] traffic_local_read_bytes, traffic_global_read_bytes;
    reg [63:0] traffic_read_step, matched_traffic_bytes;

    initial begin
        if (COMPACT != 0 && COMPACT != 1)
            $fatal(1, "PARAMETER ERROR: COMPACT must be 0 or 1");
        if (FORCE_FALLBACK != 0 && FORCE_FALLBACK != 1)
            $fatal(1, "PARAMETER ERROR: FORCE_FALLBACK must be 0 or 1");
    end

    wire image_enabled = mode_hold == 1 || mode_hold == 2 ||
        mode_hold == 5 || mode_hold == 6;
    wire audio_enabled = mode_hold >= 3 && mode_hold <= 6;
    wire [1:0] modality_hold = {audio_enabled, image_enabled};
    wire [63:0] patch_count = {32'd0, rows_hold} * {32'd0, columns_hold};
    wire [64:0] ids_end = {1'b0, ids_hold} + {31'd0, tokens_hold, 2'd0} - 65'd1;
    wire [64:0] positions_end = {1'b0, positions_hold} +
        {31'd0, tokens_hold, 2'd0} - 65'd1;
    wire [64:0] masks_end = {1'b0, masks_hold} +
        {31'd0, tokens_hold, 2'd0} - 65'd1;
    wire [64:0] scan_address = {1'b0, positions_hold} + {31'd0, scan_index, 2'd0};
    wire [64:0] scan_mask_address = {1'b0, masks_hold} +
        {31'd0, scan_index, 2'd0};
    wire [31:0] remaining_queries = tokens_hold - scan_index;
    wire [31:0] local_query_span =
        remaining_queries > (COMPACT ? 32'd4 : 32'd512) ?
            (COMPACT ? 32'd4 : 32'd512) : remaining_queries;
    wire [63:0] traffic_local_writes = {32'd0, traffic_local_write_units} <<
        (COMPACT ? 4 : (model_hold == 1 ? 10 : 11));
    wire [63:0] traffic_global_writes = {32'd0, traffic_global_write_units} <<
        (COMPACT ? 5 : (model_hold == 1 ? 11 : 12));
    wire session_matches = session_valid && session_model == model_hold &&
        session_precision == precision_hold && session_mode == mode_hold &&
        session_weights == weights_hold && session_vision_weights == vision_weights_hold &&
        session_audio_weights == audio_weights_hold && session_image == image_hold &&
        session_audio == audio_hold && session_ids == ids_hold &&
        session_positions == positions_hold && session_masks == masks_hold &&
        session_rows == rows_hold && session_columns == columns_hold &&
        session_frames == frames_hold;
    wire native_descriptor_bad = mode_hold == 7 || tokens_hold == 0 ||
        tokens_hold > 131072 || position_hold > 131071 ||
        |ids_hold[1:0] || |positions_hold[1:0] || |masks_hold[1:0] ||
        |weights_hold[1:0] || ids_end[64] || positions_end[64] || masks_end[64] ||
        (image_enabled && (rows_hold == 0 || columns_hold == 0 ||
            patch_count > 64'hffffffff || |image_hold[1:0] ||
            |vision_weights_hold[1:0])) ||
        (audio_enabled && (frames_hold == 0 || |audio_hold[1:0] ||
            |audio_weights_hold[1:0]));
    wire native_session_bad = decode_hold ?
        (!session_matches || position_hold != session_tokens ||
            tokens_hold != session_tokens + 32'd1) : position_hold != 0;
    wire [31:0] padded_context = (tokens_hold + 32'd15) & 32'hfffffff0;
    wire [9:0] baseline_window = padded_context > (COMPACT ? 32'd4 : 32'd512) ?
        (COMPACT ? 10'd4 : 10'd512) : padded_context[9:0];
    wire [21:0] baseline_units = {7'd0, baseline_local_units} +
        {1'b0, baseline_global_units};
    wire [31:0] baseline_units_wide = {10'd0, baseline_units};
    wire [9:0] production_window = padded_context > 32'd512 ?
        10'd512 : padded_context[9:0];
    wire [21:0] production_units = {7'd0, production_local_units} +
        {1'b0, baseline_global_units};
    wire [31:0] production_units_wide = {10'd0, production_units};
    assign job_ready = rst_n && state == IDLE;
    assign busy = rst_n && state != IDLE;
    assign done_valid = rst_n && state == RESPONSE;
    assign done_error = rst_n ? error_hold : 4'd0;

    wire parent_ready, parent_req_valid, parent_req_write, parent_rsp_ready;
    wire [63:0] parent_req_addr;
    wire [31:0] parent_req_data;
    wire parent_emb_valid, parent_emb_last, parent_done;
    wire signed [31:0] parent_emb_data;
    wire [15:0] parent_emb_index;
    wire [3:0] parent_error;
    wire parent_selected = rst_n && state == PARENT_WAIT;
    anvil_e3_top #(
        .AUDIO_LAYERS(AUDIO_LAYERS), .AUDIO_HIDDEN(AUDIO_HIDDEN), .AUDIO_FFN(AUDIO_FFN),
        .AUDIO_HEADS(AUDIO_HEADS), .AUDIO_HEAD_DIM(AUDIO_HEAD_DIM),
        .AUDIO_OUT_DIM(AUDIO_OUT_DIM), .AUDIO_CONV_KERNEL(AUDIO_CONV_KERNEL),
        .AUDIO_SUBSAMPLE_C0(AUDIO_SUBSAMPLE_C0), .AUDIO_SUBSAMPLE_C1(AUDIO_SUBSAMPLE_C1),
        .AUDIO_FREQ_BINS(AUDIO_FREQ_BINS), .AUDIO_CHUNK_SIZE(AUDIO_CHUNK_SIZE),
        .AUDIO_CONTEXT_LEFT(AUDIO_CONTEXT_LEFT), .AUDIO_CONTEXT_RIGHT(AUDIO_CONTEXT_RIGHT),
        .VISION_LAYERS(VISION_LAYERS), .VISION_HIDDEN(VISION_HIDDEN),
        .VISION_FFN(VISION_FFN), .VISION_HEADS(VISION_HEADS),
        .VISION_HEAD_DIM(VISION_HEAD_DIM), .PATCH_SIZE(PATCH_SIZE), .POOL_KERNEL(POOL_KERNEL),
        .VISION_SOFT_TOKENS(VISION_SOFT_TOKENS), .TEXT_LAYERS(TEXT_LAYERS),
        .TEXT_HIDDEN(TEXT_HIDDEN), .PLE_DIM(PLE_DIM), .TEXT_FFN(TEXT_FFN),
        .EMBED_DIM(EMBED_DIM), .VOCAB_SIZE(VOCAB_SIZE),
        .POSITION_EMBEDDING_SIZE(POSITION_EMBEDDING_SIZE), .TEXT_Q_HEADS(TEXT_Q_HEADS),
        .LOCAL_KV_HEADS(LOCAL_KV_HEADS), .FULL_KV_HEADS(FULL_KV_HEADS),
        .LOCAL_HEAD_DIM(LOCAL_HEAD_DIM), .FULL_HEAD_DIM(FULL_HEAD_DIM),
        .SLIDING_WINDOW(SLIDING_WINDOW), .MAX_SEQ_LEN(MAX_SEQ_LEN)
    ) parent (
        .clk(clk), .rst_n(rst_n), .job_valid(rst_n && state == PARENT_START),
        .job_ready(parent_ready), .job_mode(mode_hold), .job_tokens(tokens_hold),
        .job_patch_rows(rows_hold), .job_patch_cols(columns_hold),
        .job_audio_frames(frames_hold), .job_output_dim(output_hold),
        .weights_base(weights_hold), .vision_weights_base(vision_weights_hold),
        .audio_weights_base(audio_weights_hold), .image_base(image_hold),
        .audio_base(audio_hold), .tokens_base(ids_hold), .positions_base(positions_hold),
        .mask_base(masks_hold), .scratch_base(scratch_hold),
        .mem_req_ready(parent_selected && mem_req_ready),
        .mem_rsp_valid(parent_selected && mem_rsp_valid), .mem_rsp_rdata(mem_rsp_rdata),
        .mem_rsp_error(mem_rsp_error), .mem_req_valid(parent_req_valid),
        .mem_req_write(parent_req_write), .mem_req_addr(parent_req_addr),
        .mem_req_wdata(parent_req_data), .mem_rsp_ready(parent_rsp_ready),
        .emb_ready(parent_selected && emb_ready), .emb_valid(parent_emb_valid),
        .emb_data(parent_emb_data), .emb_index(parent_emb_index), .emb_last(parent_emb_last),
        .done_valid(parent_done), .done_ready(parent_selected), .done_error(parent_error),
        .busy()
    );
    assign emb_valid = parent_selected && parent_emb_valid;
    assign emb_data = parent_selected ? parent_emb_data : 32'sd0;
    assign emb_index = parent_selected ? parent_emb_index : 16'd0;
    assign emb_last = parent_selected && parent_emb_last;

    wire native_ready, native_done;
    wire [3:0] native_error;
    wire native_cmd_valid, native_cmd_ready, native_cmd_write, native_result_ready;
    wire [63:0] native_cmd_addr;
    wire [31:0] native_cmd_data;
    wire [2:0] native_cmd_owner;
    wire native_cmd_input, native_cmd_replay;
    reg bridge_input, bridge_replay;
    wire native_logit_valid, native_logit_last;
    wire [15:0] native_logit_data;
    wire [17:0] native_logit_index;
    wire native_selected = rst_n && state == NATIVE_WAIT;
    wire fallback_active;
    wire [6:0] frame_depth;
    wire [1599:0] live_bytes, physical_bytes;
    wire [1599:0] production_shadow_bytes;
    wire [255:0] metadata_bytes;
    wire [255:0] production_shadow_metadata_bytes = !rst_n ? 256'd0 :
        {metadata_bytes[255:128], 64'd768, 64'd768};
    wire [63:0] shadow_bytes, reserved_bytes;
    wire [63:0] native_workspace_bytes, native_workspace_shadow_bytes;
    wire [63:0] native_reconstruction_controller_bytes;
    wire native_allocation_check_valid, native_allocation_fallback;
    wire resident_hit, resident_miss, alias_hit, memo_hit, memo_eviction, ring_hit;
    wire owner_event, replay_owner_event, replay_input_event, replay_projection_event;
    wire replay_intermediate_event, native_fault;
    wire [31:0] owner_bytes, replay_owner_bytes, replay_input_bytes;
    wire [31:0] replay_projection_bytes, replay_intermediate_bytes;
    wire [7:0] attention_activity;
    wire avoided_projection_event;
    wire [63:0] avoided_projection_bytes;
    wire bridge_ready, bridge_valid, bridge_error;
    wire [31:0] bridge_data;
    wire [63:0] csr_controller_bytes, ledger_controller_bytes, guard_controller_bytes;
    wire allocation_report_valid;
    wire allocation_report_check_valid, allocation_report_fallback, allocation_report_overlap;
    wire allocation_report_partition_error;
    wire allocation_failed;
    wire [1:0] allocation_report_model;
    wire [63:0] allocation_payload_bytes, allocation_replay_bytes, allocation_equivalent_bytes;
    wire [63:0] native_scratch_bytes;
    wire [63:0] allocation_shadow_bytes, native_scratch_shadow_bytes;
    wire [63:0] text_workspace_bytes, text_workspace_shadow_bytes;
    wire [63:0] fallback_working_bytes, fallback_working_shadow_bytes;
    wire [31:0] TOP_CONTROLLER_BITS = $bits({
        state, error_hold, model_hold, precision_hold, mode_hold, decode_hold,
        tokens_hold, rows_hold, columns_hold, frames_hold, position_hold, output_hold,
        weights_hold, vision_weights_hold, audio_weights_hold, image_hold, audio_hold,
        ids_hold, positions_hold, masks_hold, scratch_hold, kv_hold, scan_index,
        scan_data, generation, scan_error, session_valid, session_tokens, session_model,
        session_precision, session_mode, session_weights, session_vision_weights,
        session_audio_weights, session_image, session_audio, session_ids, session_positions,
        session_masks, session_rows, session_columns, session_frames, baseline_local_units,
        baseline_global_units, baseline_payload, bridge_input, bridge_replay,
        production_local_units, production_baseline_payload, allocation_wait,
        traffic_local_write_units, traffic_global_write_units,
        traffic_local_span, traffic_global_span,
        traffic_local_read_units, traffic_global_read_units,
        traffic_local_read_bytes, traffic_global_read_bytes,
        traffic_read_step, matched_traffic_bytes
    });
    // Immutable anvil_e2_memory: state, write, address, write/read data, error.
    localparam integer NATIVE_BRIDGE_BITS = 2+1+64+32+32+1;
    wire [63:0] integration_bytes = !rst_n ? 64'd0 :
        64'((TOP_CONTROLLER_BITS+7) >> 3) + 64'((NATIVE_BRIDGE_BITS+7) >> 3) +
        csr_controller_bytes + ledger_controller_bytes + guard_controller_bytes;
    anvil_en1_allocation_ledger allocations (
        .clk(clk), .rst_n(rst_n), .observation_valid(native_selected),
        .observation_model(model_hold), .component_live_bytes(live_bytes),
        .component_shadow_bytes(production_shadow_bytes),
        .metadata_bytes(metadata_bytes), .integration_bytes(integration_bytes),
        .shadow_metadata_bytes(production_shadow_metadata_bytes),
        .native_workspace_bytes(native_workspace_bytes),
        .native_workspace_shadow_bytes(native_workspace_shadow_bytes),
        .native_controller_bytes(native_reconstruction_controller_bytes),
        .observation_check_valid(native_allocation_check_valid),
        .observation_fallback(native_allocation_fallback),
        .report_valid(allocation_report_valid), .report_model(allocation_report_model),
        .report_check_valid(allocation_report_check_valid),
        .report_fallback(allocation_report_fallback), .report_overlap(allocation_report_overlap),
        .payload_bytes(allocation_payload_bytes), .replay_bytes(allocation_replay_bytes),
        .native_scratch_bytes(native_scratch_bytes),
        .equivalent_shadow_bytes(allocation_shadow_bytes),
        .native_scratch_shadow_bytes(native_scratch_shadow_bytes),
        .text_workspace_bytes(text_workspace_bytes),
        .text_workspace_shadow_bytes(text_workspace_shadow_bytes),
        .fallback_working_bytes(fallback_working_bytes),
        .fallback_working_shadow_bytes(fallback_working_shadow_bytes),
        .report_partition_error(allocation_report_partition_error),
        .equivalent_bytes(allocation_equivalent_bytes), .controller_bytes(ledger_controller_bytes)
    );
    anvil_en1_allocation_guard allocation_limits (
        .clk(clk), .rst_n(rst_n), .clear(job_valid && job_ready),
        .report_valid(allocation_report_check_valid),
        .report_fallback(allocation_report_fallback), .report_overlap(allocation_report_overlap),
        .report_model(allocation_report_model),
        .report_partition_error(allocation_report_partition_error),
        .equivalent_bytes(allocation_equivalent_bytes), .native_scratch_bytes(native_scratch_bytes),
        .equivalent_shadow_bytes(allocation_shadow_bytes),
        .native_scratch_shadow_bytes(native_scratch_shadow_bytes),
        .text_workspace_bytes(text_workspace_bytes),
        .text_workspace_shadow_bytes(text_workspace_shadow_bytes),
        .fallback_working_bytes(fallback_working_bytes),
        .fallback_working_shadow_bytes(fallback_working_shadow_bytes),
        .matched_payload_bytes({32'd0, production_baseline_payload}),
        .failed(allocation_failed), .controller_bytes(guard_controller_bytes)
    );
    anvil_en1_native #(.COMPACT(COMPACT), .RESIDENT_ENTRIES(RESIDENT_ENTRIES)) native (
        .image_invalidate(job_valid && job_ready),
        .clk(clk), .rst_n(rst_n),
        .integration_bytes(integration_bytes),
        .matched_payload_bytes({32'd0, production_baseline_payload}),
        .attention_activity(attention_activity),
        .avoided_projection_event(avoided_projection_event),
        .avoided_projection_bytes(avoided_projection_bytes),
        .start_valid(rst_n && state == NATIVE_START), .start_ready(native_ready),
        .model(model_hold), .precision(precision_hold), .modality(modality_hold),
        .generation(generation), .tokens(tokens_hold), .force_fallback(FORCE_FALLBACK != 0),
        .tokens_base(ids_hold), .weights_base(weights_hold), .mask_base(masks_hold),
        .image_base(image_hold), .vision_weights_base(vision_weights_hold),
        .patches(patch_count[31:0]), .patch_rows(rows_hold), .patch_columns(columns_hold),
        .audio_base(audio_hold), .audio_weights_base(audio_weights_hold),
        .audio_frames(frames_hold),
        .cmd_valid(native_cmd_valid), .cmd_ready(native_cmd_ready),
        .cmd_write(native_cmd_write), .cmd_addr(native_cmd_addr),
        .cmd_wdata(native_cmd_data), .cmd_owner(native_cmd_owner),
        .cmd_input(native_cmd_input), .cmd_replay(native_cmd_replay),
        .result_valid(native_selected && bridge_valid), .result_ready(native_result_ready),
        .result_data(bridge_data), .result_error(bridge_error),
        .logit_valid(native_logit_valid), .logit_ready(native_selected && logit_ready),
        .logit_data(native_logit_data), .logit_index(native_logit_index),
        .logit_last(native_logit_last), .done_valid(native_done),
        .done_ready(native_selected), .done_error(native_error),
        .fallback_active(fallback_active), .frame_depth(frame_depth),
        .allocation_live_bytes(live_bytes), .allocation_physical_bytes(physical_bytes),
        .allocation_shadow_bytes(production_shadow_bytes),
        .allocation_metadata_bytes(metadata_bytes), .workspace_shadow_bytes(shadow_bytes),
        .native_workspace_bytes(native_workspace_bytes),
        .native_workspace_shadow_bytes(native_workspace_shadow_bytes),
        .native_reconstruction_controller_bytes(native_reconstruction_controller_bytes),
        .allocation_check_valid(native_allocation_check_valid),
        .allocation_fallback(native_allocation_fallback),
        .workspace_reserved_bytes(reserved_bytes), .resident_hit_event(resident_hit),
        .resident_miss_event(resident_miss), .alias_event(alias_hit),
        .memo_hit_event(memo_hit), .memo_eviction_event(memo_eviction),
        .ring_hit_event(ring_hit), .owner_reprojection_event(owner_event),
        .replay_owner_reprojection_event(replay_owner_event),
        .owner_reprojection_bytes(owner_bytes), .replay_owner_reprojection_bytes(replay_owner_bytes),
        .replay_input_event(replay_input_event), .replay_projection_event(replay_projection_event),
        .replay_intermediate_event(replay_intermediate_event),
        .replay_input_bytes(replay_input_bytes), .replay_projection_bytes(replay_projection_bytes),
        .replay_intermediate_bytes(replay_intermediate_bytes),
        .protocol_error(native_fault), .busy()
    );
    assign logit_valid = native_selected && native_logit_valid;
    assign logit_data = native_selected ? native_logit_data : 16'd0;
    assign logit_index = native_selected ? native_logit_index : 18'd0;
    assign logit_last = native_selected && native_logit_last;

    wire native_req_valid, native_req_write, native_rsp_ready;
    wire [63:0] native_req_addr;
    wire [31:0] native_req_data;
    wire scan_send = rst_n && (state == POSITION_SEND || state == MASK_SCAN_SEND);
    wire scan_wait = rst_n && (state == POSITION_WAIT || state == MASK_SCAN_WAIT);
    wire bridge_command = scan_send || (native_selected && native_cmd_valid);
    assign native_cmd_ready = native_selected && bridge_ready;
    anvil_e2_memory native_memory (
        .clk(clk), .rst_n(rst_n),
        .cmd_valid(bridge_command), .cmd_ready(bridge_ready),
        .cmd_write(native_selected && native_cmd_write),
        .cmd_addr(state == MASK_SCAN_SEND ? scan_mask_address[63:0] :
            (scan_send ? scan_address[63:0] : native_cmd_addr)),
        .cmd_wdata(native_selected ? native_cmd_data : 32'd0),
        .result_valid(bridge_valid),
        .result_ready(scan_wait || (native_selected && native_result_ready)),
        .result_data(bridge_data), .result_error(bridge_error),
        .mem_req_valid(native_req_valid), .mem_req_ready(!parent_selected && mem_req_ready),
        .mem_req_write(native_req_write), .mem_req_addr(native_req_addr),
        .mem_req_wdata(native_req_data), .mem_rsp_valid(!parent_selected && mem_rsp_valid),
        .mem_rsp_ready(native_rsp_ready), .mem_rsp_rdata(mem_rsp_rdata),
        .mem_rsp_error(mem_rsp_error)
    );
    assign mem_req_valid = rst_n && (parent_selected ? parent_req_valid : native_req_valid);
    assign mem_req_write = rst_n && (parent_selected ? parent_req_write : native_req_write);
    assign mem_req_addr = !rst_n ? 64'd0 :
        (parent_selected ? parent_req_addr : native_req_addr);
    assign mem_req_wdata = !rst_n ? 32'd0 :
        (parent_selected ? parent_req_data : native_req_data);
    assign mem_rsp_ready = rst_n && (parent_selected ? parent_rsp_ready : native_rsp_ready);

    wire accepted_memory = mem_req_valid && mem_req_ready;
    wire completed_job = state == RESPONSE && done_ready;
    wire [24:0] perf_mask;
    wire [1599:0] perf_values;
    genvar metric;
    generate for (metric=0; metric<25; metric=metric+1) begin : telemetry
        if (metric == 0) begin
            assign perf_mask[metric] = busy;
            assign perf_values[64*metric+:64] = 64'd1;
        end else if (metric == 1) begin
            assign perf_mask[metric] = completed_job && error_hold == 0;
            assign perf_values[64*metric+:64] = 64'd1;
        end else if (metric == 2 || metric == 3) begin
            assign perf_mask[metric] = accepted_memory &&
                (metric == 3 ? mem_req_write : !mem_req_write);
            assign perf_values[64*metric+:64] = 64'd4;
        end else if (metric == 6) begin
            assign perf_mask[metric] = completed_job && error_hold == 0 &&
                (model_hold == 1 || model_hold == 2);
            assign perf_values[64*metric+:64] = matched_traffic_bytes;
        end else if (metric == 7) begin
            assign perf_mask[metric] = native_selected && avoided_projection_event;
            assign perf_values[64*metric+:64] = avoided_projection_bytes;
        end else if (metric == 8 || metric == 9) begin
            assign perf_mask[metric] = native_selected &&
                (metric == 8 ? alias_hit : resident_hit);
            assign perf_values[64*metric+:64] = 64'd1;
        end else if (metric >= 10 && metric <= 13) begin
            assign perf_mask[metric] = native_selected &&
                |attention_activity[2*(metric-10)+:2];
            assign perf_values[64*metric+:64] =
                {62'd0, attention_activity[2*(metric-10)+:2]};
        end else if (metric == 14) begin
            assign perf_mask[metric] = completed_job && error_hold != 0;
            assign perf_values[64*metric+:64] = 64'd1;
        end else if (metric == 16) begin
            assign perf_mask[metric] = rst_n && state == NATIVE_START && native_ready;
            assign perf_values[64*metric+:64] = {32'd0, baseline_payload};
        end else if (metric == 17) begin
            assign perf_mask[metric] = native_selected && (owner_event || replay_owner_event);
            assign perf_values[64*metric+:64] =
                (owner_event ? {32'd0,owner_bytes} : 64'd0) +
                (replay_owner_event ? {32'd0,replay_owner_bytes} : 64'd0);
        end else if (metric == 18 || metric == 19) begin
            assign perf_mask[metric] = native_selected && accepted_memory &&
                !mem_req_write && bridge_replay &&
                (metric == 18 ? bridge_input : !bridge_input);
            assign perf_values[64*metric+:64] = 64'd4;
        end else if (metric == 21 || metric == 22) begin
            assign perf_mask[metric] = native_selected &&
                (metric == 21 ? memo_hit : memo_eviction);
            assign perf_values[64*metric+:64] = 64'd1;
        end else if (metric == 23) begin
            assign perf_mask[metric] = native_selected && native_done && fallback_active;
            assign perf_values[64*metric+:64] = 64'd1;
        end else begin
            assign perf_mask[metric] = 1'b0;
            assign perf_values[64*metric+:64] = 64'd0;
        end
    end endgenerate
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            baseline_local_units <= 0;
            baseline_global_units <= 0;
            baseline_payload <= 0;
            production_local_units <= 0;
            production_baseline_payload <= 0;
        end else if (job_valid && job_ready) begin
            baseline_local_units <= 0;
            baseline_global_units <= 0;
            baseline_payload <= 0;
            production_local_units <= 0;
            production_baseline_payload <= 0;
        end else if (state == VALIDATE && model_hold != 0 &&
            model_hold != 3 && precision_hold <= 1 &&
            !native_descriptor_bad && !native_session_bad) begin
            baseline_local_units <= {5'd0, baseline_window} *
                (model_hold == 1 ? 15'd28 : 15'd35);
            baseline_global_units <= {3'd0, padded_context[17:0]} * 21'd14;
            production_local_units <= {5'd0, production_window} *
                (model_hold == 1 ? 15'd28 : 15'd35);
        end else if (state == POSITION_SEND) begin
            if (COMPACT)
                baseline_payload <= baseline_units_wide << 4;
            else if (model_hold == 1)
                baseline_payload <= baseline_units_wide << 10;
            else
                baseline_payload <= baseline_units_wide << 11;
            production_baseline_payload <= model_hold == 1 ?
                production_units_wide << 10 : production_units_wide << 11;
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            traffic_local_write_units <= 0;
            traffic_global_write_units <= 0;
            traffic_local_span <= 0;
            traffic_global_span <= 0;
            traffic_local_read_units <= 0;
            traffic_global_read_units <= 0;
            traffic_local_read_bytes <= 0;
            traffic_global_read_bytes <= 0;
            traffic_read_step <= 0;
            matched_traffic_bytes <= 0;
        end else if (job_valid && job_ready) begin
            traffic_local_write_units <= 0;
            traffic_global_write_units <= 0;
            traffic_local_span <= 0;
            traffic_global_span <= 0;
            traffic_local_read_units <= 0;
            traffic_global_read_units <= 0;
            traffic_local_read_bytes <= 0;
            traffic_global_read_bytes <= 0;
            traffic_read_step <= 0;
            matched_traffic_bytes <= 0;
        end else begin
            case (state)
                VALIDATE: if (model_hold == 1 || model_hold == 2) begin
                    traffic_local_write_units <= model_hold == 1 ?
                        (padded_context << 5) - (padded_context << 2) :
                        (padded_context << 5) + (padded_context << 1) + padded_context;
                    traffic_global_write_units <= (padded_context << 3) - padded_context;
                end
                POSITION_SEND: if (scan_index == 0)
                    matched_traffic_bytes <= traffic_local_writes + traffic_global_writes;
                MASK_SCAN_CHECK: begin
                    traffic_local_span <= scan_data[0] ? local_query_span : 32'd0;
                    traffic_global_span <= scan_data[0] ? remaining_queries : 32'd0;
                end
                BASELINE_COUNTS: begin
                    traffic_local_read_units <= model_hold == 1 ?
                        (traffic_local_span << 5) - (traffic_local_span << 2) :
                        (traffic_local_span << 5) + (traffic_local_span << 1) +
                            traffic_local_span;
                    traffic_global_read_units <=
                        (traffic_global_span << 3) - traffic_global_span;
                end
                BASELINE_SCALE: begin
                    traffic_local_read_bytes <= {32'd0, traffic_local_read_units} <<
                        (COMPACT ? 4 : (model_hold == 1 ? 10 : 11));
                    traffic_global_read_bytes <= {32'd0, traffic_global_read_units} <<
                        (COMPACT ? 5 : (model_hold == 1 ? 11 : 12));
                end
                BASELINE_SUM:
                    traffic_read_step <= traffic_local_read_bytes + traffic_global_read_bytes;
                SCAN_ADVANCE:
                    matched_traffic_bytes <= matched_traffic_bytes + traffic_read_step;
                default: begin end
            endcase
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bridge_input <= 0;
            bridge_replay <= 0;
        end else if (bridge_command && bridge_ready) begin
            bridge_input <= scan_send || native_cmd_input;
            bridge_replay <= !scan_send && native_cmd_replay;
        end
    end
    anvil_en1_csr_perf performance (
        .clk(clk), .rst_n(rst_n), .csr_valid(csr_valid), .csr_write(csr_write),
        .csr_addr(csr_addr), .csr_wdata(csr_wdata), .csr_ready(csr_ready),
        .csr_rsp_valid(csr_rsp_valid), .csr_rsp_ready(csr_rsp_ready),
        .csr_rdata(csr_rdata), .csr_error(csr_error), .status_model(model_hold),
        .status_busy(busy), .status_error(error_hold),
        .event_valid(rst_n && |perf_mask), .event_model(model_hold),
        .event_mask(perf_mask), .event_values(perf_values),
        .allocation_valid(allocation_report_valid), .allocation_model(allocation_report_model),
        .allocation_payload_bytes(allocation_payload_bytes),
        .allocation_replay_bytes(allocation_replay_bytes),
        .allocation_equivalent_bytes(allocation_equivalent_bytes),
        .traffic_valid(accepted_memory), .traffic_model(model_hold),
        .traffic_write(mem_req_write),
        .traffic_input(!parent_selected && bridge_input),
        .traffic_cache(!parent_selected && mem_req_write),
        .controller_bytes(csr_controller_bytes)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            error_hold <= 0;
            model_hold <= 0;
            precision_hold <= 0;
            mode_hold <= 0;
            decode_hold <= 0;
            tokens_hold <= 0;
            rows_hold <= 0;
            columns_hold <= 0;
            frames_hold <= 0;
            position_hold <= 0;
            output_hold <= 0;
            weights_hold <= 0;
            vision_weights_hold <= 0;
            audio_weights_hold <= 0;
            image_hold <= 0;
            audio_hold <= 0;
            ids_hold <= 0;
            positions_hold <= 0;
            masks_hold <= 0;
            scratch_hold <= 0;
            kv_hold <= 0;
            scan_index <= 0;
            scan_data <= 0;
            scan_error <= 0;
            generation <= 0;
            session_valid <= 0;
            session_tokens <= 0;
            session_model <= 0;
            session_precision <= 0;
            session_mode <= 0;
            session_weights <= 0;
            session_vision_weights <= 0;
            session_audio_weights <= 0;
            session_image <= 0;
            session_audio <= 0;
            session_ids <= 0;
            session_positions <= 0;
            session_masks <= 0;
            session_rows <= 0;
            session_columns <= 0;
            session_frames <= 0;
            allocation_wait <= 0;
        end else begin
            case (state)
                IDLE: if (job_valid && job_ready) begin
                    model_hold <= job_model;
                    precision_hold <= job_precision;
                    mode_hold <= job_mode;
                    decode_hold <= job_decode;
                    tokens_hold <= job_tokens;
                    rows_hold <= job_patch_rows;
                    columns_hold <= job_patch_cols;
                    frames_hold <= job_audio_frames;
                    position_hold <= job_position;
                    output_hold <= job_output_dim;
                    weights_hold <= weights_base;
                    vision_weights_hold <= vision_weights_base;
                    audio_weights_hold <= audio_weights_base;
                    image_hold <= image_base;
                    audio_hold <= audio_base;
                    ids_hold <= tokens_base;
                    positions_hold <= positions_base;
                    masks_hold <= mask_base;
                    scratch_hold <= scratch_base;
                    kv_hold <= kv_base;
                    error_hold <= 0;
                    scan_index <= 0;
                    if (job_model == 0 || !job_decode)
                        session_valid <= 0;
                    state <= VALIDATE;
                end
                VALIDATE: begin
                    if (model_hold == 0)
                        state <= PARENT_START;
                    else if (model_hold == 3 || precision_hold > 1) begin
                        error_hold <= 6;
                        state <= PUBLISH;
                    end else if (native_descriptor_bad) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else if (native_session_bad) begin
                        error_hold <= 7;
                        state <= PUBLISH;
                    end else
                        state <= POSITION_SEND;
                end
                PARENT_START: if (parent_ready)
                    state <= PARENT_WAIT;
                PARENT_WAIT: if (parent_done) begin
                    error_hold <= parent_error;
                    state <= PUBLISH;
                end
                POSITION_SEND: if (bridge_ready)
                    state <= POSITION_WAIT;
                POSITION_WAIT: if (bridge_valid) begin
                    scan_data <= bridge_data;
                    scan_error <= bridge_error;
                    state <= POSITION_CHECK;
                end
                POSITION_CHECK: begin
                    if (scan_error || scan_data != scan_index) begin
                        error_hold <= scan_error ? 4'd2 : 4'd5;
                        state <= PUBLISH;
                    end else
                        state <= MASK_SCAN_SEND;
                end
                MASK_SCAN_SEND: if (bridge_ready)
                    state <= MASK_SCAN_WAIT;
                MASK_SCAN_WAIT: if (bridge_valid) begin
                    scan_data <= bridge_data;
                    scan_error <= bridge_error;
                    state <= MASK_SCAN_CHECK;
                end
                MASK_SCAN_CHECK: begin
                    if (scan_error || |scan_data[31:1]) begin
                        error_hold <= scan_error ? 4'd2 : 4'd5;
                        state <= PUBLISH;
                    end else
                        state <= BASELINE_COUNTS;
                end
                BASELINE_COUNTS: state <= BASELINE_SCALE;
                BASELINE_SCALE: state <= BASELINE_SUM;
                BASELINE_SUM: state <= SCAN_ADVANCE;
                SCAN_ADVANCE: begin
                    if (scan_index + 32'd1 == tokens_hold) begin
                        if (generation == 32'hffffffff)
                            generation <= 1;
                        else
                            generation <= generation + 32'd1;
                        session_valid <= 0;
                        state <= NATIVE_START;
                    end else begin
                        scan_index <= scan_index + 32'd1;
                        state <= POSITION_SEND;
                    end
                end
                NATIVE_START: if (native_ready)
                    state <= NATIVE_WAIT;
                NATIVE_WAIT: if (native_done) begin
                    error_hold <= native_error != 0 ? native_error :
                        (native_fault ? 4'd7 : 4'd0);
                    allocation_wait <= 0;
                    state <= ALLOCATION_DRAIN;
                end
                ALLOCATION_DRAIN: begin
                    if (allocation_wait == 7)
                        state <= ALLOCATION_CHECK;
                    else
                        allocation_wait <= allocation_wait + 1'b1;
                end
                ALLOCATION_CHECK: begin
                    if (error_hold == 0 && !allocation_failed) begin
                        session_valid <= 1;
                        session_tokens <= tokens_hold;
                        session_model <= model_hold;
                        session_precision <= precision_hold;
                        session_mode <= mode_hold;
                        session_weights <= weights_hold;
                        session_vision_weights <= vision_weights_hold;
                        session_audio_weights <= audio_weights_hold;
                        session_image <= image_hold;
                        session_audio <= audio_hold;
                        session_ids <= ids_hold;
                        session_positions <= positions_hold;
                        session_masks <= masks_hold;
                        session_rows <= rows_hold;
                        session_columns <= columns_hold;
                        session_frames <= frames_hold;
                    end else begin
                        session_valid <= 0;
                        if (error_hold == 0)
                            error_hold <= 7;
                    end
                    state <= PUBLISH;
                end
                PUBLISH: state <= RESPONSE;
                RESPONSE: if (done_ready)
                    state <= IDLE;
                default: begin
                    session_valid <= 0;
                    error_hold <= 7;
                    state <= PUBLISH;
                end
            endcase
        end
    end
endmodule
