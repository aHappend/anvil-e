module anvil_en1_native #(
    parameter integer COMPACT = 0,
    parameter integer RESIDENT_ENTRIES = 3
) (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] model, precision, modality,
    input wire [31:0] generation, tokens,
    input wire force_fallback,
    input wire [63:0] tokens_base, weights_base, mask_base,
    input wire [63:0] image_base, vision_weights_base,
    input wire [31:0] patches, patch_rows, patch_columns,
    input wire [63:0] audio_base, audio_weights_base,
    input wire [31:0] audio_frames,
    output wire cmd_valid,
    input wire cmd_ready,
    output wire cmd_write,
    output wire [63:0] cmd_addr,
    output wire [31:0] cmd_wdata,
    output wire [2:0] cmd_owner,
    output wire cmd_input, cmd_replay,
    input wire result_valid,
    output wire result_ready,
    input wire [31:0] result_data,
    input wire result_error,
    output wire logit_valid,
    input wire logit_ready,
    output wire [15:0] logit_data,
    output wire [17:0] logit_index,
    output wire logit_last,
    output wire done_valid,
    input wire done_ready,
    output wire [3:0] done_error,
    output wire fallback_active,
    output wire [6:0] frame_depth,
    output wire [1599:0] allocation_live_bytes, allocation_physical_bytes,
    output wire [255:0] allocation_metadata_bytes,
    output wire [63:0] workspace_shadow_bytes, workspace_reserved_bytes,
    output wire resident_hit_event, resident_miss_event, alias_event,
    output wire memo_hit_event, memo_eviction_event, ring_hit_event,
    output wire owner_reprojection_event, replay_owner_reprojection_event,
    output wire [31:0] owner_reprojection_bytes, replay_owner_reprojection_bytes,
    output wire replay_input_event, replay_projection_event, replay_intermediate_event,
    output wire [31:0] replay_input_bytes, replay_projection_bytes, replay_intermediate_bytes,
    output wire [7:0] attention_activity,
    output wire avoided_projection_event,
    output wire [63:0] avoided_projection_bytes,
    output wire protocol_error,
    output wire busy
);
    localparam [3:0] IDLE = 0, VALIDATE = 1, CACHE_SEND = 2,
        CACHE_WAIT = 3, FRONTIER_SEND = 4, FRONTIER_WAIT = 5,
        BIND_SEND = 6, BIND_WAIT = 7, SCHEDULE_SEND = 8,
        SCHEDULE_WAIT = 9, DRAIN_SEND = 10, DRAIN_WAIT = 11,
        PUBLISH = 12, RESPONSE = 13;
    localparam [2:0] META_IDLE = 0, META_SEND = 1, META_WAIT = 2,
        META_RESPONSE = 3;
    localparam [2:0] MASK_IDLE = 0, MASK_VALIDATE = 1, MASK_SEND = 2,
        MASK_WAIT = 3, MASK_PUBLISH = 4, MASK_RESPONSE = 5;
    reg [3:0] state;
    reg [1:0] model_hold, precision_hold, modality_hold;
    reg [31:0] generation_hold, tokens_hold;
    reg forced_hold;
    reg [63:0] tokens_base_hold, weights_base_hold, mask_base_hold;
    reg [63:0] image_base_hold, vision_weights_hold;
    reg [31:0] patches_hold, rows_hold, columns_hold;
    reg [63:0] audio_base_hold, audio_weights_hold;
    reg [31:0] audio_frames_hold;
    reg [3:0] error_hold;
    reg [2:0] meta_state, mask_state;
    reg [1:0] meta_owner;
    reg [121:0] meta_request;
    reg [78:0] meta_response;
    reg mask_owner, mask_value, mask_error;
    reg [31:0] mask_token_hold;
    reg [63:0] mask_address;

    initial begin
        if (COMPACT != 0 && COMPACT != 1)
            $fatal(1, "PARAMETER ERROR: COMPACT must be 0 or 1");
    end

    wire [31:0] padded = (tokens_hold + 32'd15) & 32'hfffffff0;
    wire [63:0] frontier_required = COMPACT ? {32'd0, padded} << 4 :
        (model_hold == 1 ?
            ({32'd0, padded} << 11) + ({32'd0, padded} << 10) :
            ({32'd0, padded} << 12) + ({32'd0, padded} << 10));
    wire selected_fallback = forced_hold ||
        frontier_required > (COMPACT ? 64'd8192 : 64'd3145728);
    wire [64:0] tokens_end = {1'b0, tokens_base_hold} +
        {31'd0, tokens_hold, 2'd0} - 65'd1;
    wire [64:0] masks_end = {1'b0, mask_base_hold} +
        {31'd0, tokens_hold, 2'd0} - 65'd1;
    wire [64:0] mask_sum = {1'b0, mask_base_hold} +
        {31'd0, mask_token_hold, 2'd0};
    wire [64:0] mask_end = mask_sum + 65'd3;
    wire executor_busy, binding_busy, schedule_busy;
    wire [3:0] executor_attention_activity, binding_attention_activity;
    wire executor_avoided_event, binding_avoided_event;
    wire [31:0] executor_avoided_bytes, binding_avoided_bytes;
    genvar activity;
    generate for (activity=0; activity<4; activity=activity+1) begin : attention_events
        assign attention_activity[2*activity+:2] =
            {1'b0, executor_attention_activity[activity]} +
            {1'b0, binding_attention_activity[activity]};
    end endgenerate
    assign avoided_projection_event = executor_avoided_event || binding_avoided_event;
    assign avoided_projection_bytes = {32'd0, executor_avoided_bytes} +
        {32'd0, binding_avoided_bytes};
    wire memory_fault, binding_fault;
    wire drain_ready, drain_done;
    wire core_idle = state == IDLE && meta_state == META_IDLE &&
        mask_state == MASK_IDLE && !executor_busy && !binding_busy && !schedule_busy;
    wire workers_drained = !executor_busy && !binding_busy &&
        meta_state == META_IDLE && mask_state == MASK_IDLE;
    assign start_ready = rst_n && core_idle && !protocol_error;
    assign done_valid = rst_n && state == RESPONSE;
    assign done_error = rst_n ? error_hold : 4'd0;
    assign busy = rst_n && !core_idle;
    assign protocol_error = rst_n && (memory_fault || binding_fault);

    wire [1:0] meta_valid, meta_ready, meta_rsp_valid, meta_rsp_ready;
    wire [243:0] meta_payload;
    wire [78:0] cache_response;
    wire cache_ready, cache_valid;
    wire cache_control_ready = rst_n && meta_state == META_IDLE;
    wire cache_control_valid = rst_n && meta_state == META_RESPONSE && meta_owner == 2;
    wire cache_control_accept = state == CACHE_SEND && cache_control_ready;
    wire meta_accept = rst_n && meta_state == META_IDLE && state != CACHE_SEND;
    assign meta_ready[1] = meta_accept;
    assign meta_ready[0] = meta_accept && !meta_valid[1];
    assign meta_rsp_valid[0] = rst_n && meta_state == META_RESPONSE && meta_owner == 0;
    assign meta_rsp_valid[1] = rst_n && meta_state == META_RESPONSE && meta_owner == 1;
    wire meta_retire = meta_owner == 2 ? state == CACHE_WAIT :
        (meta_owner == 1 ? meta_rsp_ready[1] : meta_rsp_ready[0]);

    wire fetch_valid, fetch_ready, fetch_value, fetch_rsp_valid, fetch_rsp_ready;
    wire [1:0] fetch_model, fetch_head;
    wire [7:0] fetch_owner;
    wire [31:0] fetch_token;
    wire [9:0] fetch_component;
    wire [15:0] fetch_data;
    wire [3:0] fetch_error;
    wire regen_valid, regen_ready, regen_value, regen_rsp_valid, regen_rsp_ready;
    wire [1:0] regen_model, regen_head;
    wire [7:0] regen_owner;
    wire [31:0] regen_token, regen_data;
    wire [9:0] regen_component;
    wire [3:0] regen_error;
    wire [63:0] cache_controller_bytes;
    anvil_en1_kv_shared_cache #(
        .COMPACT(COMPACT), .RESIDENT_ENTRIES(RESIDENT_ENTRIES)
    ) cache (
        .clk(clk), .rst_n(rst_n),
        .req_valid(rst_n && meta_state == META_SEND), .req_ready(cache_ready),
        .req_op(meta_request[121:119]), .req_model(meta_request[118:117]),
        .req_layer(meta_request[116:109]), .req_token(meta_request[108:77]),
        .req_is_value(meta_request[76]), .req_kv_head(meta_request[75:74]),
        .req_component(meta_request[73:64]), .req_base(meta_request[63:0]),
        .rsp_valid(cache_valid), .rsp_ready(rst_n && meta_state == META_WAIT),
        .rsp_addr(cache_response[78:15]), .rsp_owner(cache_response[14:7]),
        .rsp_alias(cache_response[6]), .rsp_error(cache_response[5:2]),
        .rsp_space(cache_response[1:0]),
        .fetch_valid(fetch_valid), .fetch_ready(fetch_ready),
        .fetch_model(fetch_model), .fetch_owner(fetch_owner), .fetch_token(fetch_token),
        .fetch_is_value(fetch_value), .fetch_kv_head(fetch_head),
        .fetch_component(fetch_component),
        .fetch_rsp_valid(fetch_rsp_valid), .fetch_rsp_ready(fetch_rsp_ready),
        .fetch_rsp_data(fetch_data), .fetch_rsp_error(fetch_error),
        .regen_valid(regen_valid), .regen_ready(regen_ready),
        .regen_model(regen_model), .regen_owner(regen_owner), .regen_token(regen_token),
        .regen_is_value(regen_value), .regen_kv_head(regen_head),
        .regen_component(regen_component),
        .regen_rsp_valid(regen_rsp_valid), .regen_rsp_ready(regen_rsp_ready),
        .regen_rsp_data(regen_data), .regen_rsp_error(regen_error),
        .resident_live_bytes(allocation_live_bytes[64*18+:64]),
        .resident_physical_bytes(allocation_physical_bytes[64*18+:64]),
        .metadata_bytes(allocation_metadata_bytes[64*3+:64]),
        .controller_bytes(cache_controller_bytes),
        .resident_hit_event(resident_hit_event), .resident_miss_event(resident_miss_event),
        .alias_event(alias_event)
    );

    wire task_valid, task_ready, task_source, task_done, task_done_ready;
    wire [2:0] task_op;
    wire [1:0] task_model, task_precision;
    wire [31:0] task_generation, task_tokens, task_token;
    wire [7:0] task_layer;
    wire [3:0] task_error;
    wire schedule_ready, schedule_done;
    wire [3:0] schedule_error;
    wire [63:0] schedule_controller_bytes, memory_controller_bytes;
    anvil_en1_frontier_schedule #(.COMPACT(COMPACT)) schedule (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == SCHEDULE_SEND), .start_ready(schedule_ready),
        .model(model_hold), .precision(precision_hold),
        .generation(generation_hold), .tokens(tokens_hold), .force_fallback(forced_hold),
        .task_valid(task_valid), .task_ready(task_ready), .task_op(task_op),
        .task_model(task_model), .task_precision(task_precision),
        .task_generation(task_generation), .task_tokens(task_tokens),
        .task_token(task_token), .task_layer(task_layer), .task_source_frontier(task_source),
        .task_done_valid(task_done), .task_done_ready(task_done_ready),
        .task_done_error(task_error), .done_valid(schedule_done),
        .done_ready(rst_n && state == SCHEDULE_WAIT), .done_error(schedule_error),
        .fallback_active(fallback_active), .busy(schedule_busy),
        .controller_bytes(schedule_controller_bytes)
    );

    wire executor_control_ready, executor_control_valid;
    wire [3:0] executor_control_error;
    wire binding_control_ready, binding_control_valid;
    wire [3:0] binding_control_error;
    wire owner_read_valid, owner_read_ready, owner_read_rsp_valid, owner_read_rsp_ready;
    wire [31:0] owner_read_generation, owner_read_token, owner_read_data;
    wire [7:0] owner_read_layer;
    wire [11:0] owner_read_component;
    wire [3:0] owner_read_error;
    wire ring_read_valid, ring_read_ready, ring_read_rsp_valid, ring_read_rsp_ready, ring_hit;
    wire [1:0] ring_model, ring_head;
    wire [31:0] ring_generation, ring_token, ring_data;
    wire [7:0] ring_owner;
    wire ring_value;
    wire [9:0] ring_component;
    wire [3:0] ring_error;
    wire eval_valid, eval_ready, eval_output_valid, eval_output_ready, eval_output_last;
    wire eval_done, eval_done_ready;
    wire [1:0] eval_model, eval_precision, eval_modality, eval_domain;
    wire [31:0] eval_generation, eval_tokens, eval_token, eval_output_index;
    wire [7:0] eval_layer;
    wire [63:0] eval_tokens_base, eval_weights_base;
    wire [15:0] eval_output_data;
    wire [3:0] eval_error;
    wire backing_valid, backing_ready, backing_write, backing_rsp_valid, backing_rsp_ready;
    wire [31:0] backing_generation, backing_wdata, backing_data;
    wire [17:0] backing_addr;
    wire [3:0] backing_error;
    wire [1:0] masks_valid, masks_ready, masks_rsp_valid, masks_rsp_ready;
    wire [63:0] masks_token;
    wire masks_accept = rst_n && mask_state == MASK_IDLE;
    assign masks_ready[1] = masks_accept;
    assign masks_ready[0] = masks_accept && !masks_valid[1];
    assign masks_rsp_valid[0] = rst_n && mask_state == MASK_RESPONSE && !mask_owner;
    assign masks_rsp_valid[1] = rst_n && mask_state == MASK_RESPONSE && mask_owner;
    wire [2:0] memory_valid, memory_ready, memory_write;
    wire [191:0] memory_addr;
    wire [95:0] memory_wdata, memory_rdata;
    wire [2:0] memory_rsp_valid, memory_rsp_ready, memory_error;
    wire [2:0] binding_memory_owner;
    wire executor_input_event, binding_memory_input;

    anvil_en1_frontier_execute #(.COMPACT(COMPACT)) frontier (
        .clk(clk), .rst_n(rst_n),
        .attention_activity(executor_attention_activity),
        .avoided_projection_event(executor_avoided_event),
        .avoided_projection_bytes(executor_avoided_bytes),
        .control_valid(rst_n && state == FRONTIER_SEND),
        .control_ready(executor_control_ready), .control_invalidate(1'b0),
        .control_model(model_hold), .control_precision(precision_hold),
        .control_modality(modality_hold), .control_generation(generation_hold),
        .control_tokens(tokens_hold), .control_tokens_base(tokens_base_hold),
        .control_weights_base(weights_base_hold),
        .control_rsp_valid(executor_control_valid),
        .control_rsp_ready(rst_n && state == FRONTIER_WAIT),
        .control_error(executor_control_error),
        .task_valid(task_valid), .task_ready(task_ready), .task_op(task_op),
        .task_model(task_model), .task_precision(task_precision),
        .task_generation(task_generation), .task_tokens(task_tokens),
        .task_token(task_token), .task_layer(task_layer), .task_source_frontier(task_source),
        .task_done_valid(task_done), .task_done_ready(task_done_ready), .task_done_error(task_error),
        .modality_ready(1'b0), .modality_rsp_valid(1'b0),
        .modality_rsp_data(16'd0), .modality_rsp_error(1'b1),
        .mask_valid(masks_valid[0]), .mask_ready(masks_ready[0]),
        .mask_token(masks_token[0+:32]), .mask_rsp_valid(masks_rsp_valid[0]),
        .mask_rsp_ready(masks_rsp_ready[0]), .mask_rsp_data(mask_value),
        .mask_rsp_error(mask_error),
        .req_valid(meta_valid[0]), .req_ready(meta_ready[0]),
        .req_op(meta_payload[119+:3]), .req_model(meta_payload[117+:2]),
        .req_layer(meta_payload[109+:8]), .req_token(meta_payload[77+:32]),
        .req_is_value(meta_payload[76]), .req_kv_head(meta_payload[74+:2]),
        .req_component(meta_payload[64+:10]), .req_base(meta_payload[0+:64]),
        .rsp_valid(meta_rsp_valid[0]), .rsp_ready(meta_rsp_ready[0]),
        .rsp_addr(meta_response[78:15]), .rsp_owner(meta_response[14:7]),
        .rsp_alias(meta_response[6]), .rsp_error(meta_response[5:2]),
        .rsp_space(meta_response[1:0]),
        .fetch_valid(fetch_valid), .fetch_ready(fetch_ready),
        .fetch_model(fetch_model), .fetch_owner(fetch_owner), .fetch_token(fetch_token),
        .fetch_is_value(fetch_value), .fetch_kv_head(fetch_head),
        .fetch_component(fetch_component),
        .fetch_rsp_valid(fetch_rsp_valid), .fetch_rsp_ready(fetch_rsp_ready),
        .fetch_rsp_data(fetch_data), .fetch_rsp_error(fetch_error),
        .owner_read_valid(owner_read_valid), .owner_read_ready(owner_read_ready),
        .owner_read_generation(owner_read_generation), .owner_read_token(owner_read_token),
        .owner_read_layer(owner_read_layer), .owner_read_component(owner_read_component),
        .owner_read_rsp_valid(owner_read_rsp_valid), .owner_read_rsp_ready(owner_read_rsp_ready),
        .owner_read_rsp_data(owner_read_data), .owner_read_rsp_error(owner_read_error),
        .ring_read_valid(ring_read_valid), .ring_read_ready(ring_read_ready),
        .ring_read_model(ring_model), .ring_read_generation(ring_generation),
        .ring_read_token(ring_token), .ring_read_owner(ring_owner),
        .ring_read_is_value(ring_value), .ring_read_kv_head(ring_head),
        .ring_read_component(ring_component),
        .ring_read_rsp_valid(ring_read_rsp_valid), .ring_read_rsp_ready(ring_read_rsp_ready),
        .ring_read_rsp_hit(ring_hit), .ring_read_rsp_data(ring_data),
        .ring_read_rsp_error(ring_error),
        .eval_start_valid(eval_valid), .eval_start_ready(eval_ready),
        .eval_model(eval_model), .eval_precision(eval_precision), .eval_modality(eval_modality),
        .eval_domain(eval_domain), .eval_generation(eval_generation),
        .eval_tokens(eval_tokens), .eval_token(eval_token), .eval_layer(eval_layer),
        .eval_tokens_base(eval_tokens_base), .eval_weights_base(eval_weights_base),
        .eval_output_valid(eval_output_valid), .eval_output_ready(eval_output_ready),
        .eval_output_index(eval_output_index), .eval_output_data(eval_output_data),
        .eval_output_last(eval_output_last), .eval_done_valid(eval_done),
        .eval_done_ready(eval_done_ready), .eval_done_error(eval_error),
        .backing_valid(backing_valid), .backing_ready(backing_ready),
        .backing_generation(backing_generation), .backing_write(backing_write),
        .backing_addr(backing_addr), .backing_wdata(backing_wdata),
        .backing_rsp_valid(backing_rsp_valid), .backing_rsp_ready(backing_rsp_ready),
        .backing_rsp_data(backing_data), .backing_rsp_error(backing_error),
        .cmd_valid(memory_valid[0]), .cmd_ready(memory_ready[0]),
        .cmd_write(memory_write[0]), .cmd_addr(memory_addr[0+:64]),
        .input_read_event(executor_input_event),
        .cmd_wdata(memory_wdata[0+:32]), .result_valid(memory_rsp_valid[0]),
        .result_ready(memory_rsp_ready[0]), .result_data(memory_rdata[0+:32]),
        .result_error(memory_error[0]),
        .logit_valid(logit_valid), .logit_ready(logit_ready), .logit_data(logit_data),
        .logit_index(logit_index), .logit_last(logit_last),
        .vector_live_bytes(allocation_live_bytes[64*2+:64]),
        .vector_physical_bytes(allocation_physical_bytes[64*2+:64]),
        .feature_live_bytes(allocation_live_bytes[64*3+:64]),
        .feature_physical_bytes(allocation_physical_bytes[64*3+:64]),
        .frontier_live_bytes(allocation_live_bytes[64*0+:64]),
        .frontier_physical_bytes(allocation_physical_bytes[64*0+:64]),
        .frontier_metadata_bytes(allocation_metadata_bytes[64*0+:64]),
        .ring_live_bytes(allocation_live_bytes[64*1+:64]),
        .ring_physical_bytes(allocation_physical_bytes[64*1+:64]),
        .ring_metadata_bytes(allocation_metadata_bytes[64*1+:64]),
        .anchor_live_bytes(allocation_live_bytes[64*4+:64]),
        .anchor_physical_bytes(allocation_physical_bytes[64*4+:64]),
        .execution_live_bytes(allocation_live_bytes[64*19+:192]),
        .execution_physical_bytes(allocation_physical_bytes[64*19+:192]),
        .reported_controller_bytes(allocation_live_bytes[64*24+:64]),
        .busy(executor_busy)
    );

    anvil_en1_replay_binding #(.COMPACT(COMPACT)) binding (
        .clk(clk), .rst_n(rst_n),
        .attention_activity(binding_attention_activity),
        .avoided_projection_event(binding_avoided_event),
        .avoided_projection_bytes(binding_avoided_bytes),
        .control_valid(rst_n && state == BIND_SEND), .control_ready(binding_control_ready),
        .control_invalidate(1'b0), .control_fallback(selected_fallback),
        .control_model(model_hold), .control_precision(precision_hold),
        .control_modality(modality_hold), .control_generation(generation_hold),
        .control_tokens(tokens_hold), .control_tokens_base(tokens_base_hold),
        .control_weights_base(weights_base_hold), .control_image_base(image_base_hold),
        .control_vision_weights_base(vision_weights_hold), .control_patches(patches_hold),
        .control_patch_rows(rows_hold), .control_patch_columns(columns_hold),
        .control_audio_base(audio_base_hold), .control_audio_weights_base(audio_weights_hold),
        .control_audio_frames(audio_frames_hold), .control_rsp_valid(binding_control_valid),
        .control_rsp_ready(rst_n && state == BIND_WAIT), .control_error(binding_control_error),
        .regen_valid(regen_valid), .regen_ready(regen_ready),
        .regen_model(regen_model), .regen_owner(regen_owner), .regen_token(regen_token),
        .regen_is_value(regen_value), .regen_kv_head(regen_head),
        .regen_component(regen_component),
        .regen_rsp_valid(regen_rsp_valid), .regen_rsp_ready(regen_rsp_ready),
        .regen_rsp_data(regen_data), .regen_rsp_error(regen_error),
        .frontier_read_valid(owner_read_valid), .frontier_read_ready(owner_read_ready),
        .frontier_read_generation(owner_read_generation), .frontier_read_token(owner_read_token),
        .frontier_read_layer(owner_read_layer), .frontier_read_component(owner_read_component),
        .frontier_read_rsp_valid(owner_read_rsp_valid),
        .frontier_read_rsp_ready(owner_read_rsp_ready),
        .frontier_read_rsp_data(owner_read_data), .frontier_read_rsp_error(owner_read_error),
        .ring_read_valid(ring_read_valid), .ring_read_ready(ring_read_ready),
        .ring_read_model(ring_model), .ring_read_generation(ring_generation),
        .ring_read_token(ring_token), .ring_read_owner(ring_owner),
        .ring_read_is_value(ring_value), .ring_read_kv_head(ring_head),
        .ring_read_component(ring_component),
        .ring_read_rsp_valid(ring_read_rsp_valid), .ring_read_rsp_ready(ring_read_rsp_ready),
        .ring_read_rsp_hit(ring_hit), .ring_read_rsp_data(ring_data), .ring_read_rsp_error(ring_error),
        .eval_start_valid(eval_valid), .eval_start_ready(eval_ready),
        .eval_model(eval_model), .eval_precision(eval_precision), .eval_modality(eval_modality),
        .eval_domain(eval_domain), .eval_generation(eval_generation),
        .eval_tokens(eval_tokens), .eval_token(eval_token), .eval_layer(eval_layer),
        .eval_tokens_base(eval_tokens_base), .eval_weights_base(eval_weights_base),
        .eval_output_valid(eval_output_valid), .eval_output_ready(eval_output_ready),
        .eval_output_index(eval_output_index), .eval_output_data(eval_output_data),
        .eval_output_last(eval_output_last), .eval_done_valid(eval_done),
        .eval_done_ready(eval_done_ready), .eval_done_error(eval_error),
        .mask_valid(masks_valid[1]), .mask_ready(masks_ready[1]),
        .mask_token(masks_token[32+:32]), .mask_rsp_valid(masks_rsp_valid[1]),
        .mask_rsp_ready(masks_rsp_ready[1]), .mask_rsp_data(mask_value),
        .mask_rsp_error(mask_error),
        .req_valid(meta_valid[1]), .req_ready(meta_ready[1]),
        .req_op(meta_payload[122+119+:3]), .req_model(meta_payload[122+117+:2]),
        .req_layer(meta_payload[122+109+:8]), .req_token(meta_payload[122+77+:32]),
        .req_is_value(meta_payload[122+76]), .req_kv_head(meta_payload[122+74+:2]),
        .req_component(meta_payload[122+64+:10]), .req_base(meta_payload[122+:64]),
        .rsp_valid(meta_rsp_valid[1]), .rsp_ready(meta_rsp_ready[1]),
        .rsp_addr(meta_response[78:15]), .rsp_owner(meta_response[14:7]),
        .rsp_alias(meta_response[6]), .rsp_error(meta_response[5:2]),
        .rsp_space(meta_response[1:0]),
        .backing_valid(backing_valid), .backing_ready(backing_ready),
        .backing_generation(backing_generation), .backing_write(backing_write),
        .backing_addr(backing_addr), .backing_wdata(backing_wdata),
        .backing_rsp_valid(backing_rsp_valid), .backing_rsp_ready(backing_rsp_ready),
        .backing_rsp_data(backing_data), .backing_rsp_error(backing_error),
        .cmd_valid(memory_valid[1]), .cmd_ready(memory_ready[1]),
        .cmd_write(memory_write[1]), .cmd_addr(memory_addr[64+:64]),
        .cmd_wdata(memory_wdata[32+:32]), .cmd_owner(binding_memory_owner),
        .cmd_input(binding_memory_input),
        .result_valid(memory_rsp_valid[1]), .result_ready(memory_rsp_ready[1]),
        .result_data(memory_rdata[32+:32]), .result_error(memory_error[1]),
        .frame_depth(frame_depth),
        .workspace_live_bytes(allocation_live_bytes[64*5+:64]),
        .workspace_shadow_bytes(workspace_shadow_bytes),
        .workspace_reserved_bytes(workspace_reserved_bytes),
        .workspace_metadata_bytes(allocation_metadata_bytes[64*2+:64]),
        .owner_source_live_bytes(allocation_live_bytes[64*6+:64]),
        .owner_source_physical_bytes(allocation_physical_bytes[64*6+:64]),
        .owner_tile_live_bytes(allocation_live_bytes[64*7+:64]),
        .owner_tile_physical_bytes(allocation_physical_bytes[64*7+:64]),
        .text_tile_live_bytes(allocation_live_bytes[64*8+:64]),
        .text_tile_physical_bytes(allocation_physical_bytes[64*8+:64]),
        .ple_live_bytes(allocation_live_bytes[64*9+:64]),
        .ple_physical_bytes(allocation_physical_bytes[64*9+:64]),
        .embedding_live_bytes(allocation_live_bytes[64*10+:64]),
        .embedding_physical_bytes(allocation_physical_bytes[64*10+:64]),
        .post_live_bytes(allocation_live_bytes[64*11+:64]),
        .post_physical_bytes(allocation_physical_bytes[64*11+:64]),
        .vision_live_bytes(allocation_live_bytes[64*12+:64]),
        .vision_physical_bytes(allocation_physical_bytes[64*12+:64]),
        .audio_live_bytes(allocation_live_bytes[64*13+:64]),
        .audio_physical_bytes(allocation_physical_bytes[64*13+:64]),
        .audio_feature_live_bytes(allocation_live_bytes[64*14+:64]),
        .audio_feature_physical_bytes(allocation_physical_bytes[64*14+:64]),
        .image_feature_live_bytes(allocation_live_bytes[64*15+:64]),
        .image_feature_physical_bytes(allocation_physical_bytes[64*15+:64]),
        .binding_state_bytes(allocation_live_bytes[64*16+:64]),
        .reported_controller_bytes(allocation_live_bytes[64*22+:64]),
        .memo_hit_event(memo_hit_event), .memo_eviction_event(memo_eviction_event),
        .ring_hit_event(ring_hit_event), .owner_reprojection_event(owner_reprojection_event),
        .replay_owner_reprojection_event(replay_owner_reprojection_event),
        .owner_reprojection_bytes(owner_reprojection_bytes),
        .replay_owner_reprojection_bytes(replay_owner_reprojection_bytes),
        .replay_input_event(replay_input_event), .replay_projection_event(replay_projection_event),
        .replay_intermediate_event(replay_intermediate_event),
        .replay_input_bytes(replay_input_bytes), .replay_projection_bytes(replay_projection_bytes),
        .replay_intermediate_bytes(replay_intermediate_bytes),
        .protocol_error(binding_fault), .busy(binding_busy)
    );

    assign memory_valid[2] = rst_n && mask_state == MASK_SEND;
    assign memory_write[2] = 1'b0;
    assign memory_addr[128+:64] = rst_n ? mask_address : 64'd0;
    assign memory_wdata[64+:32] = 32'd0;
    assign memory_rsp_ready[2] = rst_n && mask_state == MASK_WAIT;
    anvil_en1_memory_arbiter #(.CLIENTS(3), .READ_ONLY(1)) memory (
        .clk(clk), .rst_n(rst_n),
        .client_cmd_valid(memory_valid), .client_cmd_ready(memory_ready),
        .client_cmd_write(memory_write), .client_cmd_addr(memory_addr),
        .client_cmd_wdata(memory_wdata), .client_result_valid(memory_rsp_valid),
        .client_input_read_event({
            memory_valid[2] && memory_ready[2],
            memory_valid[1] && memory_ready[1] && binding_memory_input,
            executor_input_event}),
        .client_cmd_replay({mask_owner, 1'b1, 1'b0}),
        .client_result_ready(memory_rsp_ready), .client_result_data(memory_rdata),
        .client_result_error(memory_error),
        .cmd_valid(cmd_valid), .cmd_ready(cmd_ready), .cmd_write(cmd_write),
        .cmd_addr(cmd_addr), .cmd_wdata(cmd_wdata), .cmd_owner(cmd_owner),
        .cmd_input(cmd_input), .cmd_replay(cmd_replay),
        .result_valid(result_valid), .result_ready(result_ready),
        .result_data(result_data), .result_error(result_error),
        .drain_valid(rst_n && state == DRAIN_SEND && workers_drained),
        .drain_ready(drain_ready),
        .drain_done_valid(drain_done), .drain_done_ready(rst_n && state == DRAIN_WAIT),
        .protocol_error(memory_fault), .controller_bytes(memory_controller_bytes)
    );

    localparam integer STATE_BITS = $bits(state) + $bits(model_hold) +
        $bits(precision_hold) + $bits(modality_hold) + $bits(generation_hold) +
        $bits(tokens_hold) + $bits(forced_hold) + $bits(tokens_base_hold) +
        $bits(weights_base_hold) + $bits(mask_base_hold) + $bits(image_base_hold) +
        $bits(vision_weights_hold) + $bits(patches_hold) + $bits(rows_hold) +
        $bits(columns_hold) + $bits(audio_base_hold) + $bits(audio_weights_hold) +
        $bits(audio_frames_hold) + $bits(error_hold) + $bits(meta_state) +
        $bits(mask_state) + $bits(meta_owner) + $bits(meta_request) +
        $bits(meta_response) + $bits(mask_owner) + $bits(mask_value) +
        $bits(mask_error) + $bits(mask_token_hold) + $bits(mask_address);
    assign allocation_live_bytes[64*17+:64] = rst_n ?
        64'((STATE_BITS+7) >> 3) : 64'd0;
    assign allocation_physical_bytes[64*5+:64] = 64'd0;
    assign allocation_physical_bytes[64*16+:64] = allocation_live_bytes[64*16+:64];
    assign allocation_physical_bytes[64*17+:64] = allocation_live_bytes[64*17+:64];
    assign allocation_physical_bytes[64*22+:64] = allocation_live_bytes[64*22+:64];
    assign allocation_live_bytes[64*23+:64] = rst_n ?
        schedule_controller_bytes + memory_controller_bytes + cache_controller_bytes : 64'd0;
    assign allocation_physical_bytes[64*23+:64] = allocation_live_bytes[64*23+:64];
    assign allocation_physical_bytes[64*24+:64] = allocation_live_bytes[64*24+:64];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            meta_state <= META_IDLE;
            meta_owner <= 0;
            meta_request <= 0;
            meta_response <= 0;
        end else begin
            case (meta_state)
                META_IDLE: begin
                    if (cache_control_accept) begin
                        meta_owner <= 2;
                        meta_request <= {3'd2, model_hold, 8'd0, 32'd0,
                            1'b0, 2'd0, 10'd0, 64'd0};
                        meta_state <= META_SEND;
                    end else if (meta_valid[1] && meta_ready[1]) begin
                        meta_owner <= 1;
                        meta_request <= meta_payload[122+:122];
                        meta_state <= META_SEND;
                    end else if (meta_valid[0] && meta_ready[0]) begin
                        meta_owner <= 0;
                        meta_request <= meta_payload[0+:122];
                        meta_state <= META_SEND;
                    end
                end
                META_SEND: if (cache_ready)
                    meta_state <= META_WAIT;
                META_WAIT: if (cache_valid) begin
                    meta_response <= cache_response;
                    meta_state <= META_RESPONSE;
                end
                META_RESPONSE: if (meta_retire)
                    meta_state <= META_IDLE;
                default: begin
                    meta_response <= {64'd0, 8'd0, 1'b0, 4'd7, 2'd3};
                    meta_state <= META_RESPONSE;
                end
            endcase
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mask_state <= MASK_IDLE;
            mask_owner <= 0;
            mask_value <= 0;
            mask_error <= 0;
            mask_token_hold <= 0;
            mask_address <= 0;
        end else begin
            case (mask_state)
                MASK_IDLE: begin
                    if (masks_valid[1] && masks_ready[1]) begin
                        mask_owner <= 1;
                        mask_token_hold <= masks_token[32+:32];
                        mask_state <= MASK_VALIDATE;
                    end else if (masks_valid[0] && masks_ready[0]) begin
                        mask_owner <= 0;
                        mask_token_hold <= masks_token[0+:32];
                        mask_state <= MASK_VALIDATE;
                    end
                end
                MASK_VALIDATE: begin
                    mask_value <= 0;
                    mask_error <= 0;
                    if (mask_token_hold >= tokens_hold || mask_sum[64] || mask_end[64]) begin
                        mask_error <= 1;
                        mask_state <= MASK_PUBLISH;
                    end else begin
                        mask_address <= mask_sum[63:0];
                        mask_state <= MASK_SEND;
                    end
                end
                MASK_SEND: if (memory_ready[2])
                    mask_state <= MASK_WAIT;
                MASK_WAIT: if (memory_rsp_valid[2]) begin
                    mask_value <= memory_rdata[64];
                    mask_error <= memory_error[2] || memory_rdata[95:65] != 0;
                    mask_state <= MASK_PUBLISH;
                end
                MASK_PUBLISH: mask_state <= MASK_RESPONSE;
                MASK_RESPONSE: if (masks_rsp_ready[mask_owner])
                    mask_state <= MASK_IDLE;
                default: begin
                    mask_value <= 0;
                    mask_error <= 1;
                    mask_state <= MASK_PUBLISH;
                end
            endcase
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            model_hold <= 0;
            precision_hold <= 0;
            modality_hold <= 0;
            generation_hold <= 0;
            tokens_hold <= 0;
            forced_hold <= 0;
            tokens_base_hold <= 0;
            weights_base_hold <= 0;
            mask_base_hold <= 0;
            image_base_hold <= 0;
            vision_weights_hold <= 0;
            patches_hold <= 0;
            rows_hold <= 0;
            columns_hold <= 0;
            audio_base_hold <= 0;
            audio_weights_hold <= 0;
            audio_frames_hold <= 0;
            error_hold <= 0;
        end else begin
            case (state)
                IDLE: if (start_valid && start_ready) begin
                    model_hold <= model;
                    precision_hold <= precision;
                    modality_hold <= modality;
                    generation_hold <= generation;
                    tokens_hold <= tokens;
                    forced_hold <= force_fallback;
                    tokens_base_hold <= tokens_base;
                    weights_base_hold <= weights_base;
                    mask_base_hold <= mask_base;
                    image_base_hold <= image_base;
                    vision_weights_hold <= vision_weights_base;
                    patches_hold <= patches;
                    rows_hold <= patch_rows;
                    columns_hold <= patch_columns;
                    audio_base_hold <= audio_base;
                    audio_weights_hold <= audio_weights_base;
                    audio_frames_hold <= audio_frames;
                    error_hold <= 0;
                    state <= VALIDATE;
                end
                VALIDATE: begin
                    if ((model_hold != 1 && model_hold != 2) || precision_hold > 1) begin
                        error_hold <= 6;
                        state <= PUBLISH;
                    end else if (tokens_hold == 0 || tokens_hold > 131072 ||
                        tokens_base_hold[1:0] || weights_base_hold[1:0] ||
                        mask_base_hold[1:0] || tokens_end[64] || masks_end[64] ||
                        ((modality_hold == 1 || modality_hold == 3) &&
                            (patches_hold == 0 || rows_hold == 0 || columns_hold == 0 ||
                            image_base_hold[1:0] || vision_weights_hold[1:0])) ||
                        ((modality_hold == 2 || modality_hold == 3) &&
                            (audio_frames_hold == 0 || audio_base_hold[1:0] ||
                            audio_weights_hold[1:0]))) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else
                        state <= CACHE_SEND;
                end
                CACHE_SEND: if (cache_control_ready)
                    state <= CACHE_WAIT;
                CACHE_WAIT: if (cache_control_valid) begin
                    if (meta_response[5:2] != 0) begin
                        error_hold <= meta_response[5:2];
                        state <= DRAIN_SEND;
                    end else
                        state <= FRONTIER_SEND;
                end
                FRONTIER_SEND: if (executor_control_ready)
                    state <= FRONTIER_WAIT;
                FRONTIER_WAIT: if (executor_control_valid) begin
                    if (executor_control_error != 0) begin
                        error_hold <= executor_control_error;
                        state <= DRAIN_SEND;
                    end else
                        state <= BIND_SEND;
                end
                BIND_SEND: if (binding_control_ready)
                    state <= BIND_WAIT;
                BIND_WAIT: if (binding_control_valid) begin
                    if (binding_control_error != 0) begin
                        error_hold <= binding_control_error;
                        state <= DRAIN_SEND;
                    end else
                        state <= SCHEDULE_SEND;
                end
                SCHEDULE_SEND: if (schedule_ready)
                    state <= SCHEDULE_WAIT;
                SCHEDULE_WAIT: if (schedule_done) begin
                    error_hold <= schedule_error;
                    state <= DRAIN_SEND;
                end
                DRAIN_SEND: if (workers_drained && drain_ready)
                    state <= DRAIN_WAIT;
                DRAIN_WAIT: if (drain_done)
                    state <= PUBLISH;
                PUBLISH: state <= RESPONSE;
                RESPONSE: if (done_ready)
                    state <= IDLE;
                default: begin
                    error_hold <= 7;
                    state <= DRAIN_SEND;
                end
            endcase
        end
    end
endmodule
