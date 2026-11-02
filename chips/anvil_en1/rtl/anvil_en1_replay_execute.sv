module anvil_en1_replay_execute #(
    parameter integer COMPACT = 0,
    parameter integer EXTERNAL_VECTOR_RAM = 0,
    parameter integer EXTERNAL_EMBEDDING_RAM = 0
) (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] model, precision, modality, eval_domain,
    input wire [31:0] generation, tokens, token,
    input wire [7:0] layer,
    input wire [63:0] tokens_base, weights_base,
    input wire [63:0] native_image_base, native_vision_weights_base,
    input wire [31:0] native_patches, native_patch_rows, native_patch_columns,
    input wire [63:0] native_audio_base, native_audio_weights_base,
    input wire [31:0] native_audio_frames,
    output wire modality_valid,
    input wire modality_ready,
    output wire [1:0] modality_model, modality_kind,
    output wire [31:0] modality_token, modality_index,
    input wire modality_rsp_valid,
    output wire modality_rsp_ready,
    input wire [15:0] modality_rsp_data,
    input wire modality_rsp_error,
    output wire mask_valid,
    input wire mask_ready,
    output wire [31:0] mask_token,
    input wire mask_rsp_valid,
    output wire mask_rsp_ready,
    input wire mask_rsp_data, mask_rsp_error,
    output wire req_valid,
    input wire req_ready,
    output wire [2:0] req_op,
    output wire [1:0] req_model,
    output wire [7:0] req_layer,
    output wire [31:0] req_token,
    output wire req_is_value,
    output wire [1:0] req_kv_head,
    output wire [9:0] req_component,
    output wire [63:0] req_base,
    input wire rsp_valid,
    output wire rsp_ready,
    input wire [63:0] rsp_addr,
    input wire [7:0] rsp_owner,
    input wire rsp_alias,
    input wire [3:0] rsp_error,
    input wire [1:0] rsp_space,
    output wire cmd_valid,
    input wire cmd_ready,
    output wire cmd_write,
    output wire [63:0] cmd_addr,
    output wire [31:0] cmd_wdata,
    input wire result_valid,
    output wire result_ready,
    input wire [31:0] result_data,
    input wire result_error,
    output wire output_valid,
    input wire output_ready,
    output wire [31:0] output_index,
    output wire [15:0] output_data,
    output wire output_last,
    output wire done_valid,
    input wire done_ready,
    output wire [3:0] done_error,
    output wire backing_valid,
    input wire backing_ready,
    output wire [31:0] backing_generation,
    output wire backing_write,
    output wire [17:0] backing_addr,
    output wire [31:0] backing_wdata,
    input wire backing_rsp_valid,
    output wire backing_rsp_ready,
    input wire [31:0] backing_rsp_data,
    input wire [3:0] backing_rsp_error,
    output wire [6:0] frame_depth,
    output wire [63:0] live_payload_bytes, production_shadow_bytes,
    output wire [63:0] native_payload_bytes, native_production_shadow_bytes,
    output wire [63:0] backing_reserved_bytes, visibility_metadata_bytes,
    output wire grant_valid,
    input wire grant_ready,
    output wire [63:0] grant_payload_bytes, grant_shadow_bytes,
    output wire [63:0] grant_native_bytes, grant_native_shadow_bytes,
    input wire grant_rsp_valid,
    output wire grant_rsp_ready,
    input wire grant_allowed,
    output wire [63:0] scheduler_state_bytes, dispatcher_state_bytes,
    output wire [63:0] selected_worker_state_bytes,
    output wire [63:0] binding_controller_bytes, projection_controller_bytes,
    output wire [63:0] executor_controller_bytes, checkpoint_controller_bytes,
    output wire [63:0] tile_controller_bytes, tile_live_bytes, tile_physical_bytes,
    output wire [63:0] ple_live_bytes, ple_physical_bytes,
    output wire [63:0] embedding_live_bytes, embedding_physical_bytes,
    output wire [63:0] post_vector_live_bytes, post_vector_physical_bytes,
    output wire [63:0] tile_shadow_bytes, embedding_shadow_bytes, post_vector_shadow_bytes,
    output wire [3:0] vector_ram_write, vector_ram_read,
    output wire [47:0] vector_ram_waddr, vector_ram_raddr,
    output wire [63:0] vector_ram_wdata,
    input wire [63:0] vector_ram_rdata,
    output wire [1:0] embedding_ram_write, embedding_ram_read,
    output wire [63:0] embedding_ram_waddr, embedding_ram_raddr,
    output wire [31:0] embedding_ram_wdata,
    input wire [31:0] embedding_ram_rdata,
    output wire [63:0] vision_vector_live_bytes, vision_vector_physical_bytes,
    output wire [63:0] vision_binding_controller_bytes, vision_patch_controller_bytes,
    output wire [63:0] vision_replay_controller_bytes, vision_executor_controller_bytes,
    output wire [63:0] vision_head_controller_bytes, vision_tile_controller_bytes,
    output wire [63:0] vision_clipped_controller_bytes, vision_clamp_controller_bytes,
    output wire [63:0] vision_output_controller_bytes, vision_output_clamp_controller_bytes,
    output wire [63:0] vision_post_controller_bytes, vision_norm_controller_bytes,
    output wire [63:0] vision_mlp_controller_bytes, vision_down_controller_bytes,
    output wire [63:0] vision_down_clamp_controller_bytes,
    output wire [63:0] vision_inner_controller_bytes, vision_inner_clamp_controller_bytes,
    output wire [63:0] audio_vector_live_bytes, audio_vector_physical_bytes,
    output wire [63:0] audio_input_controller_bytes, audio_nested_controller_bytes,
    output wire [63:0] audio_layer_controller_bytes,
    output wire [63:0] audio_feature_vector_live_bytes, audio_feature_vector_physical_bytes,
    output wire [63:0] audio_feature_controller_bytes, audio_feature_nested_controller_bytes,
    output wire [63:0] image_feature_vector_live_bytes, image_feature_vector_physical_bytes,
    output wire [63:0] image_feature_controller_bytes, image_feature_nested_controller_bytes,
    output wire native_audio_point_replay_event,
    output wire [31:0] native_audio_point_replay_bytes,
    output wire native_audio_history_replay_event, native_audio_glu_replay_event,
    output wire [31:0] native_audio_history_replay_bytes, native_audio_glu_replay_bytes,
    output wire native_input_read_event, native_projection_event, native_intermediate_event,
    output wire [31:0] native_input_read_bytes, native_projection_bytes, native_intermediate_bytes,
    output wire memo_hit_event, memo_eviction_event,
    output wire owner_reprojection_event,
    output wire [31:0] owner_reprojection_bytes,
    output wire query_projection_event,
    output wire [31:0] query_projection_bytes,
    output wire source_read_event,
    output wire [31:0] source_read_bytes,
    output wire [63:0] reported_controller_bytes,
    output wire [63:0] native_reconstruction_controller_bytes,
    output wire [3:0] attention_activity,
    output wire avoided_projection_event,
    output wire [31:0] avoided_projection_bytes,
    output wire busy
);
    localparam [2:0] IDLE = 0, VALIDATE = 1, WORKER_START = 2,
        WORKER_WAIT = 3, PUBLISH = 4, RESPONSE = 5;
    reg [2:0] state;
    reg [1:0] model_hold, precision_hold, modality_hold, mode_hold, domain_hold;
    reg [31:0] token_hold, tokens_hold, dependency_token_hold, generation_hold;
    reg [63:0] native_image_hold, native_vision_weights_hold;
    reg [31:0] native_patches_hold, native_rows_hold, native_columns_hold;
    reg [63:0] native_audio_hold, native_audio_weights_hold;
    reg [31:0] native_audio_frames_hold;
    reg [7:0] layer_hold, dependency_layer_hold;
    reg [11:0] length_hold, dependency_length_hold;
    reg [5:0] frame_hold, dependency_slot_hold;
    reg [63:0] tokens_base_hold, weights_base_hold;
    reg [159:0] continuation_hold, done_continuation_hold;
    reg dependency_valid_hold, input_worker, done_dependency_hold, done_bank_hold;
    reg [1:0] dependency_domain_hold, done_domain_hold;
    reg [7:0] done_layer_hold;
    reg [31:0] done_token_hold;
    reg [11:0] done_length_hold;
    reg [3:0] error_hold;
    reg [1:0] native_vector_owner;
    reg native_vector_fault;
    wire vision_branch_write, vision_branch_read;
    wire [31:0] vision_branch_waddr, vision_branch_raddr;
    wire [15:0] vision_branch_wdata;
    wire [2:0] audio_vector_write, audio_vector_read;
    wire [95:0] audio_vector_waddr, audio_vector_raddr;
    wire [47:0] audio_vector_wdata, native_vector_rdata;
    localparam integer NATIVE_VECTOR_BITS = $bits(native_vector_owner) +
        $bits(native_vector_fault) + $bits(native_vector_rdata);

    initial begin
        if (COMPACT != 0 && COMPACT != 1)
            $fatal(1, "PARAMETER ERROR: COMPACT must be 0 or 1");
        if (EXTERNAL_EMBEDDING_RAM != 0 && EXTERNAL_EMBEDDING_RAM != 1)
            $fatal(1, "PARAMETER ERROR: EXTERNAL_EMBEDDING_RAM must be 0 or 1");
    end

    wire task_valid, task_ready;
    wire [1:0] task_model, task_precision, task_modality, task_domain, task_mode;
    wire [31:0] task_generation, task_tokens, task_token;
    wire [7:0] task_layer;
    wire [11:0] task_length;
    wire [5:0] task_frame;
    wire [63:0] task_tokens_base, task_weights_base;
    wire [159:0] task_continuation;
    wire task_dependency_valid;
    wire [1:0] task_dependency_domain;
    wire [7:0] task_dependency_layer;
    wire [31:0] task_dependency_token;
    wire [11:0] task_dependency_length;
    wire [5:0] task_dependency_slot;
    wire task_done_ready;
    wire work_valid, work_ready, work_rsp_valid, work_rsp_ready;
    wire [2:0] work_op;
    wire [1:0] work_domain, work_target;
    wire [31:0] work_token, work_data, work_rsp_data;
    wire [7:0] work_layer, work_scalar_index;
    wire [11:0] work_length, work_component;
    wire [5:0] work_slot;
    wire work_bank, write_valid, write_ready, write_first, write_last, write_abort;
    wire [31:0] write_data;
    wire [3:0] work_rsp_error;
    wire [63:0] workspace_controller_bytes;
    anvil_en1_eval_schedule #(.COMPACT(COMPACT)) scheduler (
        .clk(clk), .rst_n(rst_n),
        .grant_valid(grant_valid), .grant_ready(grant_ready),
        .grant_payload_bytes(grant_payload_bytes), .grant_shadow_bytes(grant_shadow_bytes),
        .grant_native_bytes(grant_native_bytes),
        .grant_native_shadow_bytes(grant_native_shadow_bytes),
        .grant_rsp_valid(grant_rsp_valid), .grant_rsp_ready(grant_rsp_ready),
        .grant_allowed(grant_allowed),
        .start_valid(start_valid), .start_ready(start_ready),
        .model(model), .precision(precision), .modality(modality), .domain(eval_domain),
        .generation(generation), .tokens(tokens), .token(token), .layer(layer),
        .tokens_base(tokens_base), .weights_base(weights_base),
        .task_valid(task_valid), .task_ready(task_ready),
        .task_model(task_model), .task_precision(task_precision),
        .task_modality(task_modality), .task_domain(task_domain),
        .task_mode(task_mode), .task_generation(task_generation),
        .task_tokens(task_tokens), .task_token(task_token), .task_layer(task_layer),
        .task_length(task_length), .task_frame(task_frame),
        .task_tokens_base(task_tokens_base), .task_weights_base(task_weights_base),
        .task_continuation(task_continuation),
        .task_dependency_valid(task_dependency_valid),
        .task_dependency_domain(task_dependency_domain),
        .task_dependency_layer(task_dependency_layer),
        .task_dependency_token(task_dependency_token),
        .task_dependency_length(task_dependency_length),
        .task_dependency_slot(task_dependency_slot),
        .task_done_valid(rst_n && state == RESPONSE),
        .task_done_ready(task_done_ready), .task_done_error(error_hold),
        .task_done_dependency(done_dependency_hold), .task_done_bank(done_bank_hold),
        .task_done_dependency_domain(done_domain_hold),
        .task_done_dependency_layer(done_layer_hold),
        .task_done_dependency_token(done_token_hold),
        .task_done_dependency_length(done_length_hold),
        .task_done_continuation(done_continuation_hold),
        .work_req_valid(work_valid), .work_req_ready(work_ready),
        .work_req_op(work_op), .work_req_domain(work_domain),
        .work_req_target(work_target), .work_req_token(work_token),
        .work_req_layer(work_layer), .work_req_length(work_length),
        .work_req_component(work_component), .work_req_slot(work_slot),
        .work_req_bank(work_bank), .work_req_scalar_index(work_scalar_index),
        .work_req_data(work_data),
        .work_write_valid(write_valid), .work_write_ready(write_ready),
        .work_write_data(write_data), .work_write_first(write_first),
        .work_write_last(write_last), .work_write_abort(write_abort),
        .work_rsp_valid(work_rsp_valid), .work_rsp_ready(work_rsp_ready),
        .work_rsp_error(work_rsp_error), .work_rsp_data(work_rsp_data),
        .output_valid(output_valid), .output_ready(output_ready),
        .output_index(output_index), .output_data(output_data), .output_last(output_last),
        .done_valid(done_valid), .done_ready(done_ready), .done_error(done_error),
        .frame_depth(frame_depth), .scheduler_state_bytes(scheduler_state_bytes),
        .workspace_controller_bytes(workspace_controller_bytes),
        .live_payload_bytes(live_payload_bytes), .production_shadow_bytes(production_shadow_bytes),
        .native_payload_bytes(native_payload_bytes),
        .native_production_shadow_bytes(native_production_shadow_bytes),
        .backing_reserved_bytes(backing_reserved_bytes),
        .visibility_metadata_bytes(visibility_metadata_bytes),
        .memo_hit_event(memo_hit_event), .memo_eviction_event(memo_eviction_event),
        .backing_valid(backing_valid), .backing_ready(backing_ready),
        .backing_generation(backing_generation), .backing_write(backing_write),
        .backing_addr(backing_addr), .backing_wdata(backing_wdata),
        .backing_rsp_valid(backing_rsp_valid), .backing_rsp_ready(backing_rsp_ready),
        .backing_rsp_data(backing_rsp_data), .backing_rsp_error(backing_rsp_error),
        .busy(busy)
    );

    wire input_selected = rst_n && domain_hold == 0 && input_worker &&
        (state == WORKER_START || state == WORKER_WAIT);
    wire text_selected = rst_n && domain_hold == 0 && !input_worker &&
        (state == WORKER_START || state == WORKER_WAIT);
    wire input_ready, input_valid;
    wire [3:0] input_error;
    wire input_bank_result, input_yield;
    wire [159:0] input_continuation;
    wire [1:0] input_dependency_domain;
    wire [7:0] input_dependency_layer;
    wire [31:0] input_dependency_token;
    wire [11:0] input_dependency_length;
    wire input_modality_valid, input_modality_rsp_ready;
    wire [1:0] input_modality_model, input_modality_kind;
    wire [31:0] input_modality_token, input_modality_index;
    wire input_work_valid, input_work_rsp_ready;
    wire [2:0] input_work_op;
    wire [1:0] input_work_domain, input_work_target;
    wire [31:0] input_work_token, input_work_data;
    wire [7:0] input_work_layer, input_work_scalar_index;
    wire [11:0] input_work_length, input_work_component;
    wire [5:0] input_work_slot;
    wire input_work_bank;
    wire input_write_valid, input_write_first, input_write_last, input_write_abort;
    wire [31:0] input_write_data;
    wire input_cmd_valid, input_result_ready, input_token_event, text_token_event;
    wire [63:0] input_cmd_addr;
    wire [63:0] input_state_bytes, input_embedding_live, input_embedding_physical;
    wire [63:0] input_embedding_shadow, text_embedding_shadow;
    wire [63:0] text_embedding_live;
    wire [1:0] input_embedding_write, input_embedding_read;
    wire [1:0] text_embedding_write, text_embedding_read, embedding_access_fault;
    wire [63:0] input_embedding_waddr, input_embedding_raddr;
    wire [63:0] text_embedding_waddr, text_embedding_raddr;
    wire [31:0] input_embedding_wdata, text_embedding_wdata, embedding_rdata;
    reg embedding_ram_fault;
    genvar embedding_bank;
    generate for (embedding_bank=0; embedding_bank<2; embedding_bank=embedding_bank+1) begin : embedding_banks
        localparam integer BANK_WORDS = embedding_bank == 0 ?
            (COMPACT ? 8 : 2560) : (COMPACT ? 4 : 256);
        localparam integer BANK_BITS = $clog2(BANK_WORDS);
        wire input_access = input_embedding_write[embedding_bank] ||
            input_embedding_read[embedding_bank];
        wire text_access = text_embedding_write[embedding_bank] ||
            text_embedding_read[embedding_bank];
        wire write_enable = text_access ? text_embedding_write[embedding_bank] :
            input_embedding_write[embedding_bank];
        wire read_enable = text_access ? text_embedding_read[embedding_bank] :
            input_embedding_read[embedding_bank];
        wire [31:0] waddr = text_access ?
            text_embedding_waddr[32*embedding_bank+:32] :
            input_embedding_waddr[32*embedding_bank+:32];
        wire [31:0] raddr = text_access ?
            text_embedding_raddr[32*embedding_bank+:32] :
            input_embedding_raddr[32*embedding_bank+:32];
        wire [15:0] wdata = text_access ?
            text_embedding_wdata[16*embedding_bank+:16] :
            input_embedding_wdata[16*embedding_bank+:16];
        assign embedding_access_fault[embedding_bank] = rst_n &&
            ((input_access && text_access) ||
                (write_enable && waddr >= BANK_WORDS) ||
                (read_enable && raddr >= BANK_WORDS));
        assign embedding_ram_write[embedding_bank] = rst_n && EXTERNAL_EMBEDDING_RAM &&
            !embedding_access_fault[embedding_bank] && write_enable;
        assign embedding_ram_read[embedding_bank] = rst_n && EXTERNAL_EMBEDDING_RAM &&
            !embedding_access_fault[embedding_bank] && read_enable;
        assign embedding_ram_waddr[32*embedding_bank+:32] =
            rst_n && EXTERNAL_EMBEDDING_RAM ? waddr : 32'd0;
        assign embedding_ram_raddr[32*embedding_bank+:32] =
            rst_n && EXTERNAL_EMBEDDING_RAM ? raddr : 32'd0;
        assign embedding_ram_wdata[16*embedding_bank+:16] =
            rst_n && EXTERNAL_EMBEDDING_RAM ? wdata : 16'd0;
        if (EXTERNAL_EMBEDDING_RAM == 1) begin : external_bank
            assign embedding_rdata[16*embedding_bank+:16] =
                embedding_ram_rdata[16*embedding_bank+:16];
        end else begin : local_bank
            (* ramstyle = "M20K", nomem2reg *)
            reg [15:0] payload [0:BANK_WORDS-1];
            reg [15:0] read_q;
            assign embedding_rdata[16*embedding_bank+:16] = read_q;
            always @(posedge clk) begin
                if (rst_n && !embedding_access_fault[embedding_bank]) begin
                    if (write_enable)
                        payload[waddr[BANK_BITS-1:0]] <= wdata;
                    if (read_enable)
                        read_q <= payload[raddr[BANK_BITS-1:0]];
                end
            end
        end
    end endgenerate
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            embedding_ram_fault <= 0;
        else if (state == IDLE && task_valid && task_ready)
            embedding_ram_fault <= 0;
        else if (|embedding_access_fault ||
            (|input_embedding_live && |text_embedding_live))
            embedding_ram_fault <= 1;
    end
    anvil_en1_replay_input #(
        .COMPACT(COMPACT), .EXTERNAL_EMBEDDING_RAM(1)
    ) original_input (
        .embedding_ram_write(input_embedding_write), .embedding_ram_read(input_embedding_read),
        .embedding_ram_waddr(input_embedding_waddr), .embedding_ram_raddr(input_embedding_raddr),
        .embedding_ram_wdata(input_embedding_wdata), .embedding_ram_rdata(embedding_rdata),
        .clk(clk), .rst_n(rst_n),
        .start_valid(input_selected && state == WORKER_START), .start_ready(input_ready),
        .model(model_hold), .precision(precision_hold), .modality(modality_hold), .mode(mode_hold),
        .tokens(tokens_hold), .token(token_hold), .frame_layer(layer_hold),
        .frame_slot(frame_hold), .tokens_base(tokens_base_hold), .weights_base(weights_base_hold),
        .continuation(continuation_hold), .dependency_valid(dependency_valid_hold),
        .dependency_domain(dependency_domain_hold), .dependency_layer(dependency_layer_hold),
        .dependency_token(dependency_token_hold), .dependency_length(dependency_length_hold),
        .dependency_slot(dependency_slot_hold),
        .modality_valid(input_modality_valid), .modality_ready(input_selected && modality_ready),
        .modality_model(input_modality_model), .modality_kind(input_modality_kind),
        .modality_token(input_modality_token), .modality_index(input_modality_index),
        .modality_rsp_valid(input_selected && modality_rsp_valid),
        .modality_rsp_ready(input_modality_rsp_ready), .modality_rsp_data(modality_rsp_data),
        .modality_rsp_error(modality_rsp_error),
        .work_req_valid(input_work_valid), .work_req_ready(input_selected && work_ready),
        .work_req_op(input_work_op), .work_req_domain(input_work_domain),
        .work_req_target(input_work_target), .work_req_token(input_work_token),
        .work_req_layer(input_work_layer), .work_req_length(input_work_length),
        .work_req_component(input_work_component), .work_req_slot(input_work_slot),
        .work_req_bank(input_work_bank), .work_req_scalar_index(input_work_scalar_index),
        .work_req_data(input_work_data),
        .work_write_valid(input_write_valid), .work_write_ready(input_selected && write_ready),
        .work_write_data(input_write_data), .work_write_first(input_write_first),
        .work_write_last(input_write_last), .work_write_abort(input_write_abort),
        .work_rsp_valid(input_selected && work_rsp_valid),
        .work_rsp_ready(input_work_rsp_ready), .work_rsp_error(work_rsp_error),
        .work_rsp_data(work_rsp_data),
        .cmd_valid(input_cmd_valid), .cmd_ready(input_selected && cmd_ready),
        .cmd_write(), .cmd_addr(input_cmd_addr), .cmd_wdata(),
        .input_read_event(input_token_event),
        .result_valid(input_selected && result_valid), .result_ready(input_result_ready),
        .result_data(result_data), .result_error(result_error),
        .done_valid(input_valid), .done_ready(input_selected && state == WORKER_WAIT),
        .done_error(input_error), .done_bank(input_bank_result),
        .done_yield(input_yield), .done_continuation(input_continuation),
        .done_dependency_domain(input_dependency_domain),
        .done_dependency_layer(input_dependency_layer), .done_dependency_token(input_dependency_token),
        .done_dependency_length(input_dependency_length),
        .embedding_live_bytes(input_embedding_live),
        .embedding_shadow_bytes(input_embedding_shadow),
        .embedding_physical_bytes(input_embedding_physical),
        .controller_state_bytes(input_state_bytes), .busy()
    );

    wire text_ready, text_valid, text_yield, text_bank_result;
    wire [3:0] text_error;
    wire [159:0] text_continuation;
    wire [1:0] text_dependency_domain;
    wire [7:0] text_dependency_layer;
    wire [31:0] text_dependency_token;
    wire [11:0] text_dependency_length;
    wire text_modality_valid, text_modality_rsp_ready;
    wire [1:0] text_modality_model, text_modality_kind;
    wire [31:0] text_modality_token, text_modality_index;
    wire text_work_valid, text_work_rsp_ready;
    wire [2:0] text_work_op;
    wire [1:0] text_work_domain, text_work_target;
    wire [31:0] text_work_token, text_work_data;
    wire [7:0] text_work_layer, text_work_scalar_index;
    wire [11:0] text_work_length, text_work_component;
    wire [5:0] text_work_slot;
    wire text_work_bank, text_cmd_valid, text_result_ready;
    wire [63:0] text_cmd_addr, text_state_bytes, text_embedding_physical;
    wire text_owner_event, text_query_event, text_source_event;
    wire [31:0] text_owner_bytes, text_query_bytes, text_source_bytes;
    anvil_en1_replay_text_layer #(
        .COMPACT(COMPACT), .EXTERNAL_VECTOR_RAM(EXTERNAL_VECTOR_RAM),
        .EXTERNAL_EMBEDDING_RAM(1)
    ) text_layer (
        .embedding_ram_write(text_embedding_write), .embedding_ram_read(text_embedding_read),
        .embedding_ram_waddr(text_embedding_waddr), .embedding_ram_raddr(text_embedding_raddr),
        .embedding_ram_wdata(text_embedding_wdata), .embedding_ram_rdata(embedding_rdata),
        .vector_ram_write(vector_ram_write), .vector_ram_read(vector_ram_read),
        .vector_ram_waddr(vector_ram_waddr), .vector_ram_raddr(vector_ram_raddr),
        .vector_ram_wdata(vector_ram_wdata), .vector_ram_rdata(vector_ram_rdata),
        .clk(clk), .rst_n(rst_n),
        .attention_activity(attention_activity),
        .avoided_projection_event(avoided_projection_event),
        .avoided_projection_bytes(avoided_projection_bytes),
        .start_valid(text_selected && state == WORKER_START), .start_ready(text_ready),
        .model(model_hold), .precision(precision_hold), .modality(modality_hold), .mode(mode_hold),
        .frame_layer(layer_hold), .token(token_hold), .tokens(tokens_hold),
        .tokens_base(tokens_base_hold), .weights_base(weights_base_hold), .frame_slot(frame_hold),
        .continuation(continuation_hold), .dependency_valid(dependency_valid_hold),
        .dependency_domain(dependency_domain_hold), .dependency_layer(dependency_layer_hold),
        .dependency_token(dependency_token_hold), .dependency_length(dependency_length_hold),
        .dependency_slot(dependency_slot_hold),
        .modality_valid(text_modality_valid), .modality_ready(text_selected && modality_ready),
        .modality_model(text_modality_model), .modality_kind(text_modality_kind),
        .modality_token(text_modality_token), .modality_index(text_modality_index),
        .modality_rsp_valid(text_selected && modality_rsp_valid),
        .modality_rsp_ready(text_modality_rsp_ready), .modality_rsp_data(modality_rsp_data),
        .modality_rsp_error(modality_rsp_error),
        .mask_valid(mask_valid), .mask_ready(text_selected && mask_ready), .mask_token(mask_token),
        .mask_rsp_valid(text_selected && mask_rsp_valid), .mask_rsp_ready(mask_rsp_ready),
        .mask_rsp_data(mask_rsp_data), .mask_rsp_error(mask_rsp_error),
        .req_valid(req_valid), .req_ready(text_selected && req_ready), .req_op(req_op),
        .req_model(req_model), .req_layer(req_layer), .req_token(req_token),
        .req_is_value(req_is_value), .req_kv_head(req_kv_head), .req_component(req_component),
        .req_base(req_base), .rsp_valid(text_selected && rsp_valid), .rsp_ready(rsp_ready),
        .rsp_addr(rsp_addr), .rsp_owner(rsp_owner), .rsp_alias(rsp_alias),
        .rsp_error(rsp_error), .rsp_space(rsp_space),
        .work_req_valid(text_work_valid), .work_req_ready(text_selected && work_ready),
        .work_req_op(text_work_op), .work_req_domain(text_work_domain),
        .work_req_target(text_work_target), .work_req_token(text_work_token),
        .work_req_layer(text_work_layer), .work_req_length(text_work_length),
        .work_req_component(text_work_component), .work_req_slot(text_work_slot),
        .work_req_bank(text_work_bank), .work_req_scalar_index(text_work_scalar_index),
        .work_req_data(text_work_data), .work_rsp_valid(text_selected && work_rsp_valid),
        .work_rsp_ready(text_work_rsp_ready), .work_rsp_data(work_rsp_data),
        .work_rsp_error(work_rsp_error),
        .cmd_valid(text_cmd_valid), .cmd_ready(text_selected && cmd_ready),
        .cmd_write(), .cmd_addr(text_cmd_addr), .cmd_wdata(),
        .input_read_event(text_token_event),
        .result_valid(text_selected && result_valid), .result_ready(text_result_ready),
        .result_data(result_data), .result_error(result_error),
        .done_valid(text_valid), .done_ready(text_selected && state == WORKER_WAIT),
        .done_error(text_error), .done_yield(text_yield), .done_bank(text_bank_result),
        .done_continuation(text_continuation), .done_dependency_domain(text_dependency_domain),
        .done_dependency_layer(text_dependency_layer), .done_dependency_token(text_dependency_token),
        .done_dependency_length(text_dependency_length),
        .owner_reprojection_event(text_owner_event),
        .owner_reprojection_bytes(text_owner_bytes),
        .query_projection_event(text_query_event), .query_projection_bytes(text_query_bytes),
        .source_read_event(text_source_event), .source_read_bytes(text_source_bytes),
        .controller_state_bytes(text_state_bytes), .binding_controller_bytes(binding_controller_bytes),
        .projection_controller_bytes(projection_controller_bytes),
        .executor_controller_bytes(executor_controller_bytes),
        .checkpoint_controller_bytes(checkpoint_controller_bytes),
        .tile_controller_bytes(tile_controller_bytes), .tile_live_bytes(tile_live_bytes),
        .tile_shadow_bytes(tile_shadow_bytes),
        .tile_physical_bytes(tile_physical_bytes), .ple_live_bytes(ple_live_bytes),
        .ple_physical_bytes(ple_physical_bytes), .embedding_live_bytes(text_embedding_live),
        .embedding_shadow_bytes(text_embedding_shadow),
        .embedding_physical_bytes(text_embedding_physical),
        .post_vector_live_bytes(post_vector_live_bytes),
        .post_vector_shadow_bytes(post_vector_shadow_bytes),
        .post_vector_physical_bytes(post_vector_physical_bytes), .busy()
    );

    wire vision_selected = rst_n && domain_hold == 1 &&
        (state == WORKER_START || state == WORKER_WAIT);
    wire vision_ready, vision_valid, vision_yield, vision_bank_result;
    wire [3:0] vision_error;
    wire [159:0] vision_continuation;
    wire [1:0] vision_dependency_domain;
    wire [7:0] vision_dependency_layer;
    wire [31:0] vision_dependency_token;
    wire [11:0] vision_dependency_length;
    wire vision_work_valid, vision_work_rsp_ready;
    wire [2:0] vision_work_op;
    wire [1:0] vision_work_domain, vision_work_target;
    wire [31:0] vision_work_token, vision_work_data;
    wire [7:0] vision_work_layer, vision_work_scalar_index;
    wire [11:0] vision_work_length, vision_work_component;
    wire [5:0] vision_work_slot;
    wire vision_work_bank, vision_cmd_valid, vision_result_ready, vision_source_event;
    wire [31:0] vision_source_bytes;
    wire [63:0] vision_cmd_addr, vision_state_bytes;
    wire vision_input_event, vision_projection_event, vision_intermediate_event;
    wire [31:0] vision_input_bytes, vision_projection_bytes, vision_intermediate_bytes;
    wire vision_start = vision_selected && state == WORKER_START &&
        native_vector_owner == 0;
    anvil_en1_replay_vision_layer #(
        .COMPACT(COMPACT), .EXTERNAL_BRANCH_RAM(1)
    ) vision_layer (
        .clk(clk), .rst_n(rst_n),
        .start_valid(vision_start), .start_ready(vision_ready),
        .model(model_hold), .precision(precision_hold), .mode(mode_hold),
        .generation(generation_hold), .patches(native_patches_hold),
        .patch_rows(native_rows_hold), .patch_columns(native_columns_hold), .query_patch(token_hold),
        .frame_layer(layer_hold), .frame_slot(frame_hold), .image_base(native_image_hold),
        .vision_weights_base(native_vision_weights_hold), .continuation(continuation_hold),
        .dependency_valid(dependency_valid_hold), .dependency_domain(dependency_domain_hold),
        .dependency_layer(dependency_layer_hold), .dependency_token(dependency_token_hold),
        .dependency_length(dependency_length_hold), .dependency_slot(dependency_slot_hold),
        .work_req_valid(vision_work_valid), .work_req_ready(vision_selected && work_ready),
        .work_req_op(vision_work_op), .work_req_domain(vision_work_domain),
        .work_req_target(vision_work_target), .work_req_token(vision_work_token),
        .work_req_layer(vision_work_layer), .work_req_length(vision_work_length),
        .work_req_component(vision_work_component), .work_req_slot(vision_work_slot),
        .work_req_bank(vision_work_bank), .work_req_scalar_index(vision_work_scalar_index),
        .work_req_data(vision_work_data), .work_rsp_valid(vision_selected && work_rsp_valid),
        .work_rsp_ready(vision_work_rsp_ready), .work_rsp_data(work_rsp_data),
        .work_rsp_error(work_rsp_error), .cmd_valid(vision_cmd_valid),
        .cmd_ready(vision_selected && cmd_ready), .cmd_write(), .cmd_addr(vision_cmd_addr),
        .cmd_wdata(), .result_valid(vision_selected && result_valid),
        .result_ready(vision_result_ready), .result_data(result_data), .result_error(result_error),
        .done_valid(vision_valid), .done_ready(vision_selected && state == WORKER_WAIT),
        .done_error(vision_error), .done_yield(vision_yield), .done_bank(vision_bank_result),
        .done_continuation(vision_continuation),
        .done_dependency_domain(vision_dependency_domain),
        .done_dependency_layer(vision_dependency_layer), .done_dependency_token(vision_dependency_token),
        .done_dependency_length(vision_dependency_length),
        .input_read_event(vision_input_event), .input_read_bytes(vision_input_bytes),
        .projection_event(vision_projection_event), .projection_bytes(vision_projection_bytes),
        .intermediate_event(vision_intermediate_event), .intermediate_bytes(vision_intermediate_bytes),
        .source_read_event(vision_source_event), .source_read_bytes(vision_source_bytes),
        .vector_live_bytes(vision_vector_live_bytes), .vector_physical_bytes(vision_vector_physical_bytes),
        .branch_ram_write(vision_branch_write), .branch_ram_read(vision_branch_read),
        .branch_ram_waddr(vision_branch_waddr), .branch_ram_raddr(vision_branch_raddr),
        .branch_ram_wdata(vision_branch_wdata), .branch_ram_rdata(native_vector_rdata[15:0]),
        .controller_bytes(vision_state_bytes), .binding_controller_bytes(vision_binding_controller_bytes),
        .patch_controller_bytes(vision_patch_controller_bytes),
        .replay_controller_bytes(vision_replay_controller_bytes),
        .executor_controller_bytes(vision_executor_controller_bytes),
        .head_controller_bytes(vision_head_controller_bytes), .tile_controller_bytes(vision_tile_controller_bytes),
        .clipped_controller_bytes(vision_clipped_controller_bytes),
        .clamp_controller_bytes(vision_clamp_controller_bytes),
        .output_controller_bytes(vision_output_controller_bytes),
        .output_clamp_controller_bytes(vision_output_clamp_controller_bytes),
        .post_controller_bytes(vision_post_controller_bytes), .norm_controller_bytes(vision_norm_controller_bytes),
        .mlp_controller_bytes(vision_mlp_controller_bytes), .down_controller_bytes(vision_down_controller_bytes),
        .down_clamp_controller_bytes(vision_down_clamp_controller_bytes),
        .inner_controller_bytes(vision_inner_controller_bytes),
        .inner_clamp_controller_bytes(vision_inner_clamp_controller_bytes)
    );

    wire audio_selected = rst_n && domain_hold == 2 && layer_hold == 0 &&
        (state == WORKER_START || state == WORKER_WAIT);
    wire audio_ready, audio_valid, audio_bank_result, audio_work_valid, audio_work_rsp_ready;
    wire [3:0] audio_error;
    wire [2:0] audio_work_op;
    wire [1:0] audio_work_domain, audio_work_target;
    wire [31:0] audio_work_token, audio_work_data;
    wire [7:0] audio_work_layer, audio_work_scalar_index;
    wire [11:0] audio_work_length, audio_work_component;
    wire [5:0] audio_work_slot;
    wire audio_work_bank, audio_cmd_valid, audio_result_ready;
    wire [63:0] audio_cmd_addr;
    wire audio_input_event, audio_projection_event;
    wire [31:0] audio_input_bytes, audio_projection_bytes;
    wire audio_zero_ready, audio_zero_valid, audio_zero_bank, audio_zero_work_valid;
    wire audio_zero_work_rsp_ready, audio_zero_cmd_valid, audio_zero_result_ready;
    wire [3:0] audio_zero_error;
    wire [2:0] audio_zero_op;
    wire [1:0] audio_zero_domain, audio_zero_target;
    wire [31:0] audio_zero_token, audio_zero_data;
    wire [7:0] audio_zero_layer, audio_zero_scalar;
    wire [11:0] audio_zero_length, audio_zero_component;
    wire [5:0] audio_zero_slot;
    wire audio_zero_work_bank;
    wire [63:0] audio_zero_addr, audio_zero_live, audio_zero_physical, audio_zero_nested;
    wire audio_zero_input_event, audio_zero_projection_event;
    wire [31:0] audio_zero_input_bytes, audio_zero_projection_bytes;
    anvil_en1_replay_audio_input audio_input (
        .clk(clk), .rst_n(rst_n),
        .start_valid(audio_selected && state == WORKER_START), .start_ready(audio_zero_ready),
        .model(model_hold), .precision(precision_hold), .generation(generation_hold),
        .frames(native_audio_frames_hold), .token(token_hold),
        .frame_layer(layer_hold), .frame_slot(frame_hold),
        .audio_base(native_audio_hold), .audio_weights_base(native_audio_weights_hold),
        .work_req_valid(audio_zero_work_valid), .work_req_ready(audio_selected && work_ready),
        .work_req_op(audio_zero_op), .work_req_domain(audio_zero_domain),
        .work_req_target(audio_zero_target), .work_req_token(audio_zero_token),
        .work_req_layer(audio_zero_layer), .work_req_length(audio_zero_length),
        .work_req_component(audio_zero_component), .work_req_slot(audio_zero_slot),
        .work_req_bank(audio_zero_work_bank), .work_req_scalar_index(audio_zero_scalar),
        .work_req_data(audio_zero_data), .work_rsp_valid(audio_selected && work_rsp_valid),
        .work_rsp_ready(audio_zero_work_rsp_ready), .work_rsp_error(work_rsp_error),
        .cmd_valid(audio_zero_cmd_valid), .cmd_ready(audio_selected && cmd_ready),
        .cmd_write(), .cmd_addr(audio_zero_addr), .cmd_wdata(),
        .result_valid(audio_selected && result_valid), .result_ready(audio_zero_result_ready),
        .result_data(result_data), .result_error(result_error),
        .done_valid(audio_zero_valid), .done_ready(audio_selected && state == WORKER_WAIT),
        .done_error(audio_zero_error), .done_bank(audio_zero_bank),
        .input_read_event(audio_zero_input_event), .input_read_bytes(audio_zero_input_bytes),
        .projection_event(audio_zero_projection_event), .projection_bytes(audio_zero_projection_bytes),
        .point_replay_event(native_audio_point_replay_event),
        .point_replay_bytes(native_audio_point_replay_bytes),
        .vector_live_bytes(audio_zero_live),
        .vector_physical_bytes(audio_zero_physical),
        .controller_bytes(audio_input_controller_bytes),
        .nested_controller_bytes(audio_zero_nested)
    );

    wire audio_layer_selected = rst_n && domain_hold == 2 && layer_hold != 0 &&
        (state == WORKER_START || state == WORKER_WAIT);
    wire audio_layer_ready, audio_layer_valid, audio_layer_bank, audio_layer_yield;
    wire audio_layer_work_valid, audio_layer_work_rsp_ready, audio_layer_cmd_valid;
    wire audio_layer_result_ready;
    wire [3:0] audio_layer_error;
    wire [2:0] audio_layer_op;
    wire [1:0] audio_layer_domain, audio_layer_target, audio_layer_dependency_domain;
    wire [31:0] audio_layer_token, audio_layer_data, audio_layer_dependency_token;
    wire [7:0] audio_layer_layer, audio_layer_scalar, audio_layer_dependency_layer;
    wire [11:0] audio_layer_length, audio_layer_component, audio_layer_dependency_length;
    wire [5:0] audio_layer_slot;
    wire audio_layer_work_bank;
    wire [159:0] audio_layer_continuation;
    wire [63:0] audio_layer_addr, audio_layer_live, audio_layer_physical, audio_layer_nested;
    wire audio_layer_input_event, audio_layer_projection_event, audio_layer_intermediate_event;
    wire audio_layer_source_event;
    wire [31:0] audio_layer_input_bytes, audio_layer_projection_bytes;
    wire [31:0] audio_layer_intermediate_bytes, audio_layer_source_bytes;
    wire audio_layer_start = audio_layer_selected && state == WORKER_START &&
        native_vector_owner == 0;
    anvil_en1_replay_audio_layer #(
        .COMPACT(COMPACT), .EXTERNAL_VECTOR_RAM(1)
    ) audio_layer (
        .clk(clk), .rst_n(rst_n),
        .start_valid(audio_layer_start),
        .start_ready(audio_layer_ready),
        .model(model_hold), .precision(precision_hold), .mode(mode_hold),
        .generation(generation_hold), .frames(native_audio_frames_hold), .query_token(token_hold),
        .frame_layer(layer_hold), .frame_slot(frame_hold),
        .audio_base(native_audio_hold), .audio_weights_base(native_audio_weights_hold),
        .continuation(continuation_hold),
        .dependency_valid(dependency_valid_hold), .dependency_domain(dependency_domain_hold),
        .dependency_layer(dependency_layer_hold), .dependency_token(dependency_token_hold),
        .dependency_length(dependency_length_hold), .dependency_slot(dependency_slot_hold),
        .work_req_valid(audio_layer_work_valid),
        .work_req_ready(audio_layer_selected && work_ready),
        .work_req_op(audio_layer_op), .work_req_domain(audio_layer_domain),
        .work_req_target(audio_layer_target), .work_req_token(audio_layer_token),
        .work_req_layer(audio_layer_layer), .work_req_length(audio_layer_length),
        .work_req_component(audio_layer_component), .work_req_slot(audio_layer_slot),
        .work_req_bank(audio_layer_work_bank), .work_req_scalar_index(audio_layer_scalar),
        .work_req_data(audio_layer_data),
        .work_rsp_valid(audio_layer_selected && work_rsp_valid),
        .work_rsp_ready(audio_layer_work_rsp_ready), .work_rsp_data(work_rsp_data),
        .work_rsp_error(work_rsp_error),
        .cmd_valid(audio_layer_cmd_valid), .cmd_ready(audio_layer_selected && cmd_ready),
        .cmd_write(), .cmd_addr(audio_layer_addr), .cmd_wdata(),
        .result_valid(audio_layer_selected && result_valid), .result_ready(audio_layer_result_ready),
        .result_data(result_data), .result_error(result_error),
        .done_valid(audio_layer_valid), .done_ready(audio_layer_selected && state == WORKER_WAIT),
        .done_error(audio_layer_error), .done_yield(audio_layer_yield), .done_bank(audio_layer_bank),
        .done_continuation(audio_layer_continuation),
        .done_dependency_domain(audio_layer_dependency_domain),
        .done_dependency_layer(audio_layer_dependency_layer),
        .done_dependency_token(audio_layer_dependency_token),
        .done_dependency_length(audio_layer_dependency_length),
        .input_read_event(audio_layer_input_event), .input_read_bytes(audio_layer_input_bytes),
        .projection_event(audio_layer_projection_event), .projection_bytes(audio_layer_projection_bytes),
        .intermediate_event(audio_layer_intermediate_event),
        .intermediate_bytes(audio_layer_intermediate_bytes),
        .source_read_event(audio_layer_source_event), .source_read_bytes(audio_layer_source_bytes),
        .weight_read_event(), .weight_read_bytes(),
        .history_replay_event(native_audio_history_replay_event),
        .history_replay_bytes(native_audio_history_replay_bytes),
        .glu_replay_event(native_audio_glu_replay_event),
        .glu_replay_bytes(native_audio_glu_replay_bytes),
        .vector_live_bytes(audio_layer_live), .vector_physical_bytes(audio_layer_physical),
        .vector_ram_write(audio_vector_write), .vector_ram_read(audio_vector_read),
        .vector_ram_waddr(audio_vector_waddr), .vector_ram_raddr(audio_vector_raddr),
        .vector_ram_wdata(audio_vector_wdata), .vector_ram_rdata(native_vector_rdata),
        .controller_bytes(audio_layer_controller_bytes), .nested_controller_bytes(audio_layer_nested)
    );
    wire audio_active = audio_selected || audio_layer_selected;
    assign audio_ready = input_worker ? audio_zero_ready : audio_layer_ready;
    assign audio_valid = input_worker ? audio_zero_valid : audio_layer_valid;
    assign audio_error = input_worker ? audio_zero_error : audio_layer_error;
    assign audio_bank_result = input_worker ? audio_zero_bank : audio_layer_bank;
    assign audio_work_valid = input_worker ? audio_zero_work_valid : audio_layer_work_valid;
    assign audio_work_rsp_ready = input_worker ? audio_zero_work_rsp_ready : audio_layer_work_rsp_ready;
    assign audio_work_op = input_worker ? audio_zero_op : audio_layer_op;
    assign audio_work_domain = input_worker ? audio_zero_domain : audio_layer_domain;
    assign audio_work_target = input_worker ? audio_zero_target : audio_layer_target;
    assign audio_work_token = input_worker ? audio_zero_token : audio_layer_token;
    assign audio_work_layer = input_worker ? audio_zero_layer : audio_layer_layer;
    assign audio_work_length = input_worker ? audio_zero_length : audio_layer_length;
    assign audio_work_component = input_worker ? audio_zero_component : audio_layer_component;
    assign audio_work_slot = input_worker ? audio_zero_slot : audio_layer_slot;
    assign audio_work_bank = input_worker ? audio_zero_work_bank : audio_layer_work_bank;
    assign audio_work_scalar_index = input_worker ? audio_zero_scalar : audio_layer_scalar;
    assign audio_work_data = input_worker ? audio_zero_data : audio_layer_data;
    assign audio_cmd_valid = input_worker ? audio_zero_cmd_valid : audio_layer_cmd_valid;
    assign audio_cmd_addr = input_worker ? audio_zero_addr : audio_layer_addr;
    assign audio_result_ready = input_worker ? audio_zero_result_ready : audio_layer_result_ready;
    assign audio_input_event = audio_zero_input_event || audio_layer_input_event;
    assign audio_input_bytes = audio_zero_input_bytes + audio_layer_input_bytes;
    assign audio_projection_event = audio_zero_projection_event || audio_layer_projection_event;
    assign audio_projection_bytes = audio_zero_projection_bytes + audio_layer_projection_bytes;
    assign audio_vector_live_bytes = !rst_n ? 64'd0 : audio_zero_live + audio_layer_live;
    assign audio_vector_physical_bytes = !rst_n ? 64'd0 :
        audio_zero_physical + audio_layer_physical + 64'd6144;
    assign audio_nested_controller_bytes = !rst_n ? 64'd0 : audio_zero_nested + audio_layer_nested;

    wire vision_branch_access = vision_branch_write || vision_branch_read;
    wire audio_vector_access = |audio_vector_write || |audio_vector_read;
    wire native_vector_owner_fault = rst_n &&
        ((vision_branch_access && audio_vector_access) ||
         (vision_branch_access && (native_vector_owner != 1 || !vision_selected)) ||
         (audio_vector_access && (native_vector_owner != 2 || !audio_layer_selected)) ||
         (|vision_vector_live_bytes && |audio_layer_live));
    wire [2:0] native_vector_range_fault;
    wire native_vector_access_fault = native_vector_owner_fault ||
        |native_vector_range_fault;
    genvar native_bank;
    generate for (native_bank=0; native_bank<3; native_bank=native_bank+1) begin : native_vectors
        (* ramstyle = "M20K", nomem2reg *) reg [15:0] payload [0:1023];
        reg [15:0] read_q;
        wire vision_write = native_bank == 0 && vision_branch_write;
        wire vision_read = native_bank == 0 && vision_branch_read;
        wire [31:0] audio_waddr = audio_vector_waddr[32*native_bank+:32];
        wire [31:0] audio_raddr = audio_vector_raddr[32*native_bank+:32];
        wire [31:0] waddr = vision_write ? vision_branch_waddr : audio_waddr;
        wire [31:0] raddr = vision_read ? vision_branch_raddr : audio_raddr;
        wire [15:0] wdata = vision_write ? vision_branch_wdata :
            audio_vector_wdata[16*native_bank+:16];
        assign native_vector_range_fault[native_bank] = rst_n &&
            ((vision_write && vision_branch_waddr >= 768) ||
             (vision_read && vision_branch_raddr >= 768) ||
             (audio_vector_write[native_bank] && audio_waddr >= 1024) ||
             (audio_vector_read[native_bank] && audio_raddr >= 1024));
        assign native_vector_rdata[16*native_bank+:16] = read_q;
        always @(posedge clk) begin
            if (rst_n && !native_vector_access_fault) begin
                if (vision_write || audio_vector_write[native_bank])
                    payload[waddr[9:0]] <= wdata;
                if (vision_read || audio_vector_read[native_bank])
                    read_q <= payload[raddr[9:0]];
            end
        end
    end endgenerate
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            native_vector_owner <= 0;
        else if (vision_start && vision_ready)
            native_vector_owner <= 1;
        else if (audio_layer_start && audio_layer_ready)
            native_vector_owner <= 2;
        else if ((vision_selected && state == WORKER_WAIT && vision_valid) ||
            (audio_layer_selected && state == WORKER_WAIT && audio_layer_valid))
            native_vector_owner <= 0;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            native_vector_fault <= 0;
        else if (state == IDLE && task_valid && task_ready)
            native_vector_fault <= 0;
        else if (native_vector_access_fault)
            native_vector_fault <= 1;
    end

    wire feature_selected = rst_n && domain_hold == 3 && layer_hold == 2 &&
        (state == WORKER_START || state == WORKER_WAIT);
    wire feature_ready, feature_valid, feature_yield, feature_bank_result;
    wire [3:0] feature_error;
    wire [159:0] feature_continuation;
    wire [1:0] feature_dependency_domain;
    wire [7:0] feature_dependency_layer;
    wire [31:0] feature_dependency_token;
    wire [11:0] feature_dependency_length;
    wire feature_work_valid, feature_work_rsp_ready;
    wire [2:0] feature_work_op;
    wire [1:0] feature_work_domain, feature_work_target;
    wire [31:0] feature_work_token, feature_work_data;
    wire [7:0] feature_work_layer, feature_work_scalar_index;
    wire [11:0] feature_work_length, feature_work_component;
    wire [5:0] feature_work_slot;
    wire feature_work_bank, feature_cmd_valid, feature_result_ready;
    wire feature_projection_event, feature_source_event;
    wire feature_input_event;
    wire [31:0] feature_projection_bytes, feature_source_bytes, feature_input_bytes;
    wire [63:0] feature_cmd_addr;
    anvil_en1_replay_audio_feature #(.COMPACT(COMPACT)) audio_feature (
        .clk(clk), .rst_n(rst_n),
        .start_valid(feature_selected && state == WORKER_START), .start_ready(feature_ready),
        .model(model_hold), .precision(precision_hold), .mode(mode_hold), .modality(modality_hold),
        .generation(generation_hold), .frames(native_audio_frames_hold), .tokens(tokens_hold), .token(token_hold),
        .frame_layer(layer_hold), .frame_slot(frame_hold),
        .audio_weights_base(native_audio_weights_hold), .audio_base(native_audio_hold),
        .tokens_base(tokens_base_hold), .continuation(continuation_hold),
        .dependency_valid(dependency_valid_hold), .dependency_domain(dependency_domain_hold),
        .dependency_layer(dependency_layer_hold), .dependency_token(dependency_token_hold),
        .dependency_length(dependency_length_hold), .dependency_slot(dependency_slot_hold),
        .work_req_valid(feature_work_valid), .work_req_ready(feature_selected && work_ready),
        .work_req_op(feature_work_op), .work_req_domain(feature_work_domain),
        .work_req_target(feature_work_target), .work_req_token(feature_work_token),
        .work_req_layer(feature_work_layer), .work_req_length(feature_work_length),
        .work_req_component(feature_work_component), .work_req_slot(feature_work_slot),
        .work_req_bank(feature_work_bank), .work_req_scalar_index(feature_work_scalar_index),
        .work_req_data(feature_work_data), .work_rsp_valid(feature_selected && work_rsp_valid),
        .work_rsp_ready(feature_work_rsp_ready), .work_rsp_data(work_rsp_data),
        .work_rsp_error(work_rsp_error),
        .cmd_valid(feature_cmd_valid), .cmd_ready(feature_selected && cmd_ready),
        .cmd_write(), .cmd_addr(feature_cmd_addr), .cmd_wdata(),
        .result_valid(feature_selected && result_valid), .result_ready(feature_result_ready),
        .result_data(result_data), .result_error(result_error),
        .done_valid(feature_valid), .done_ready(feature_selected && state == WORKER_WAIT),
        .done_error(feature_error), .done_yield(feature_yield), .done_bank(feature_bank_result),
        .done_continuation(feature_continuation), .done_dependency_domain(feature_dependency_domain),
        .done_dependency_layer(feature_dependency_layer), .done_dependency_token(feature_dependency_token),
        .done_dependency_length(feature_dependency_length),
        .projection_event(feature_projection_event), .projection_bytes(feature_projection_bytes),
        .input_read_event(feature_input_event), .input_read_bytes(feature_input_bytes),
        .source_read_event(feature_source_event), .source_read_bytes(feature_source_bytes),
        .vector_live_bytes(audio_feature_vector_live_bytes),
        .vector_physical_bytes(audio_feature_vector_physical_bytes),
        .controller_bytes(audio_feature_controller_bytes),
        .nested_controller_bytes(audio_feature_nested_controller_bytes)
    );

    wire image_feature_selected = rst_n && domain_hold == 3 && layer_hold == 1 &&
        (state == WORKER_START || state == WORKER_WAIT);
    wire image_feature_ready, image_feature_valid, image_feature_yield, image_feature_bank_result;
    wire [3:0] image_feature_error;
    wire [159:0] image_feature_continuation;
    wire [1:0] image_feature_dependency_domain;
    wire [7:0] image_feature_dependency_layer;
    wire [31:0] image_feature_dependency_token;
    wire [11:0] image_feature_dependency_length;
    wire image_feature_work_valid, image_feature_work_rsp_ready;
    wire [2:0] image_feature_work_op;
    wire [1:0] image_feature_work_domain, image_feature_work_target;
    wire [31:0] image_feature_work_token, image_feature_work_data;
    wire [7:0] image_feature_work_layer, image_feature_work_scalar_index;
    wire [11:0] image_feature_work_length, image_feature_work_component;
    wire [5:0] image_feature_work_slot;
    wire image_feature_work_bank, image_feature_cmd_valid, image_feature_result_ready;
    wire image_feature_projection_event, image_feature_source_event, image_feature_input_event;
    wire [31:0] image_feature_projection_bytes, image_feature_source_bytes, image_feature_input_bytes;
    wire [63:0] image_feature_cmd_addr;
    anvil_en1_replay_image_feature #(.COMPACT(COMPACT)) image_feature (
        .clk(clk), .rst_n(rst_n),
        .cancel((start_valid && start_ready) || (done_valid && done_ready)),
        .start_valid(image_feature_selected && state == WORKER_START),
        .start_ready(image_feature_ready),
        .model(model_hold), .precision(precision_hold), .mode(mode_hold), .modality(modality_hold),
        .generation(generation_hold), .tokens(tokens_hold), .token(token_hold),
        .patches(native_patches_hold), .patch_rows(native_rows_hold), .patch_columns(native_columns_hold),
        .frame_layer(layer_hold), .frame_slot(frame_hold),
        .image_base(native_image_hold), .vision_weights_base(native_vision_weights_hold),
        .tokens_base(tokens_base_hold), .continuation(continuation_hold),
        .dependency_valid(dependency_valid_hold), .dependency_domain(dependency_domain_hold),
        .dependency_layer(dependency_layer_hold), .dependency_token(dependency_token_hold),
        .dependency_length(dependency_length_hold), .dependency_slot(dependency_slot_hold),
        .work_req_valid(image_feature_work_valid),
        .work_req_ready(image_feature_selected && work_ready),
        .work_req_op(image_feature_work_op), .work_req_domain(image_feature_work_domain),
        .work_req_target(image_feature_work_target), .work_req_token(image_feature_work_token),
        .work_req_layer(image_feature_work_layer), .work_req_length(image_feature_work_length),
        .work_req_component(image_feature_work_component), .work_req_slot(image_feature_work_slot),
        .work_req_bank(image_feature_work_bank), .work_req_scalar_index(image_feature_work_scalar_index),
        .work_req_data(image_feature_work_data),
        .work_rsp_valid(image_feature_selected && work_rsp_valid),
        .work_rsp_ready(image_feature_work_rsp_ready), .work_rsp_data(work_rsp_data),
        .work_rsp_error(work_rsp_error),
        .cmd_valid(image_feature_cmd_valid), .cmd_ready(image_feature_selected && cmd_ready),
        .cmd_write(), .cmd_addr(image_feature_cmd_addr), .cmd_wdata(),
        .result_valid(image_feature_selected && result_valid), .result_ready(image_feature_result_ready),
        .result_data(result_data), .result_error(result_error),
        .done_valid(image_feature_valid), .done_ready(image_feature_selected && state == WORKER_WAIT),
        .done_error(image_feature_error), .done_yield(image_feature_yield),
        .done_bank(image_feature_bank_result), .done_continuation(image_feature_continuation),
        .done_dependency_domain(image_feature_dependency_domain),
        .done_dependency_layer(image_feature_dependency_layer),
        .done_dependency_token(image_feature_dependency_token),
        .done_dependency_length(image_feature_dependency_length),
        .projection_event(image_feature_projection_event), .projection_bytes(image_feature_projection_bytes),
        .input_read_event(image_feature_input_event), .input_read_bytes(image_feature_input_bytes),
        .source_read_event(image_feature_source_event), .source_read_bytes(image_feature_source_bytes),
        .vector_live_bytes(image_feature_vector_live_bytes),
        .vector_physical_bytes(image_feature_vector_physical_bytes),
        .controller_bytes(image_feature_controller_bytes),
        .nested_controller_bytes(image_feature_nested_controller_bytes)
    );

    assign task_ready = rst_n && state == IDLE;
    assign work_valid = (input_selected && input_work_valid) ||
        (text_selected && text_work_valid) || (vision_selected && vision_work_valid) ||
        (audio_active && audio_work_valid) || (feature_selected && feature_work_valid) ||
        (image_feature_selected && image_feature_work_valid);
    assign work_op = domain_hold == 3 ? (layer_hold == 1 ? image_feature_work_op : feature_work_op) : (domain_hold == 2 ? audio_work_op :
        (domain_hold == 1 ? vision_work_op : (input_worker ? input_work_op : text_work_op)));
    assign work_domain = domain_hold == 3 ? (layer_hold == 1 ? image_feature_work_domain : feature_work_domain) : (domain_hold == 2 ? audio_work_domain :
        (domain_hold == 1 ? vision_work_domain : (input_worker ? input_work_domain : text_work_domain)));
    assign work_target = domain_hold == 3 ? (layer_hold == 1 ? image_feature_work_target : feature_work_target) : (domain_hold == 2 ? audio_work_target :
        (domain_hold == 1 ? vision_work_target : (input_worker ? input_work_target : text_work_target)));
    assign work_token = domain_hold == 3 ? (layer_hold == 1 ? image_feature_work_token : feature_work_token) : (domain_hold == 2 ? audio_work_token :
        (domain_hold == 1 ? vision_work_token : (input_worker ? input_work_token : text_work_token)));
    assign work_layer = domain_hold == 3 ? (layer_hold == 1 ? image_feature_work_layer : feature_work_layer) : (domain_hold == 2 ? audio_work_layer :
        (domain_hold == 1 ? vision_work_layer : (input_worker ? input_work_layer : text_work_layer)));
    assign work_length = domain_hold == 3 ? (layer_hold == 1 ? image_feature_work_length : feature_work_length) : (domain_hold == 2 ? audio_work_length :
        (domain_hold == 1 ? vision_work_length : (input_worker ? input_work_length : text_work_length)));
    assign work_component = domain_hold == 3 ? (layer_hold == 1 ? image_feature_work_component : feature_work_component) : (domain_hold == 2 ? audio_work_component :
        (domain_hold == 1 ? vision_work_component : (input_worker ? input_work_component : text_work_component)));
    assign work_slot = domain_hold == 3 ? (layer_hold == 1 ? image_feature_work_slot : feature_work_slot) : (domain_hold == 2 ? audio_work_slot :
        (domain_hold == 1 ? vision_work_slot : (input_worker ? input_work_slot : text_work_slot)));
    assign work_bank = domain_hold == 3 ? (layer_hold == 1 ? image_feature_work_bank : feature_work_bank) : (domain_hold == 2 ? audio_work_bank :
        (domain_hold == 1 ? vision_work_bank : (input_worker ? input_work_bank : text_work_bank)));
    assign work_scalar_index = domain_hold == 3 ?
        (layer_hold == 1 ? image_feature_work_scalar_index : feature_work_scalar_index) :
        (domain_hold == 2 ? audio_work_scalar_index : (domain_hold == 1 ? vision_work_scalar_index :
        (input_worker ? input_work_scalar_index : text_work_scalar_index)));
    assign work_data = domain_hold == 3 ? (layer_hold == 1 ? image_feature_work_data : feature_work_data) : (domain_hold == 2 ? audio_work_data :
        (domain_hold == 1 ? vision_work_data : (input_worker ? input_work_data : text_work_data)));
    assign write_valid = input_selected && input_write_valid;
    assign write_data = input_write_data;
    assign write_first = input_selected && input_write_first;
    assign write_last = input_selected && input_write_last;
    assign write_abort = input_selected && input_write_abort;
    assign work_rsp_ready = (input_selected && input_work_rsp_ready) ||
        (text_selected && text_work_rsp_ready) || (vision_selected && vision_work_rsp_ready) ||
        (audio_active && audio_work_rsp_ready) || (feature_selected && feature_work_rsp_ready) ||
        (image_feature_selected && image_feature_work_rsp_ready);
    assign modality_valid = (input_selected && input_modality_valid) ||
        (text_selected && text_modality_valid);
    assign modality_model = !rst_n ? 2'd0 :
        (input_worker ? input_modality_model : text_modality_model);
    assign modality_kind = !rst_n ? 2'd0 :
        (input_worker ? input_modality_kind : text_modality_kind);
    assign modality_token = !rst_n ? 32'd0 :
        (input_worker ? input_modality_token : text_modality_token);
    assign modality_index = !rst_n ? 32'd0 :
        (input_worker ? input_modality_index : text_modality_index);
    assign modality_rsp_ready = (input_selected && input_modality_rsp_ready) ||
        (text_selected && text_modality_rsp_ready);
    assign cmd_valid = (input_selected && input_cmd_valid) || (text_selected && text_cmd_valid) ||
        (vision_selected && vision_cmd_valid) || (audio_active && audio_cmd_valid) ||
        (feature_selected && feature_cmd_valid) || (image_feature_selected && image_feature_cmd_valid);
    assign cmd_write = 0;
    assign cmd_addr = !rst_n ? 64'd0 :
        (domain_hold == 3 ? (layer_hold == 1 ? image_feature_cmd_addr : feature_cmd_addr) :
        (domain_hold == 2 ? audio_cmd_addr :
        (domain_hold == 1 ? vision_cmd_addr : (input_worker ? input_cmd_addr : text_cmd_addr))));
    assign cmd_wdata = 0;
    assign result_ready = (input_selected && input_result_ready) || (text_selected && text_result_ready) ||
        (vision_selected && vision_result_ready) || (audio_active && audio_result_ready) ||
        (feature_selected && feature_result_ready) || (image_feature_selected && image_feature_result_ready);
    assign native_input_read_event = vision_input_event || audio_input_event ||
        feature_input_event || image_feature_input_event || input_token_event || text_token_event;
    assign native_input_read_bytes = vision_input_bytes + audio_input_bytes +
        feature_input_bytes + image_feature_input_bytes +
        (input_token_event ? 32'd4 : 32'd0) + (text_token_event ? 32'd4 : 32'd0);
    assign native_projection_event = vision_projection_event || audio_projection_event ||
        feature_projection_event || image_feature_projection_event;
    assign native_projection_bytes = vision_projection_bytes + audio_projection_bytes +
        feature_projection_bytes + image_feature_projection_bytes;
    assign native_intermediate_event = vision_intermediate_event || audio_layer_intermediate_event;
    assign native_intermediate_bytes = vision_intermediate_bytes + audio_layer_intermediate_bytes;
    assign owner_reprojection_event = text_owner_event;
    assign owner_reprojection_bytes = text_owner_bytes;
    assign query_projection_event = text_query_event;
    assign query_projection_bytes = text_query_bytes;
    assign source_read_event = text_source_event || vision_source_event ||
        audio_layer_source_event || feature_source_event || image_feature_source_event;
    assign source_read_bytes = text_source_bytes + vision_source_bytes +
        audio_layer_source_bytes + feature_source_bytes + image_feature_source_bytes;
    assign embedding_live_bytes = input_embedding_live + text_embedding_live;
    assign embedding_shadow_bytes = input_embedding_shadow + text_embedding_shadow;
    assign embedding_physical_bytes = rst_n ?
        input_embedding_physical + text_embedding_physical +
            (EXTERNAL_EMBEDDING_RAM ? 64'd0 :
                (COMPACT ? 64'd24 : 64'd5632)) : 64'd0;
    assign selected_worker_state_bytes = !rst_n ? 64'd0 :
        (domain_hold == 3 ? (layer_hold == 1 ? image_feature_controller_bytes : audio_feature_controller_bytes) :
        (domain_hold == 2 ? (input_worker ? audio_input_controller_bytes : audio_layer_controller_bytes) :
        (domain_hold == 1 ? vision_state_bytes : (input_worker ? input_state_bytes : text_state_bytes))));
    localparam integer DISPATCHER_BITS =
        $bits(state) + $bits(model_hold) + $bits(precision_hold) + $bits(modality_hold) +
        $bits(mode_hold) + $bits(domain_hold) + $bits(token_hold) + $bits(tokens_hold) +
        $bits(generation_hold) + $bits(native_image_hold) + $bits(native_vision_weights_hold) +
        $bits(native_patches_hold) + $bits(native_rows_hold) + $bits(native_columns_hold) +
        $bits(native_audio_hold) + $bits(native_audio_weights_hold) + $bits(native_audio_frames_hold) +
        $bits(dependency_token_hold) + $bits(layer_hold) + $bits(dependency_layer_hold) +
        $bits(length_hold) + $bits(dependency_length_hold) + $bits(frame_hold) +
        $bits(dependency_slot_hold) + $bits(tokens_base_hold) + $bits(weights_base_hold) +
        $bits(continuation_hold) + $bits(done_continuation_hold) + $bits(dependency_valid_hold) +
        $bits(input_worker) + $bits(done_dependency_hold) + $bits(done_bank_hold) +
        $bits(dependency_domain_hold) + $bits(done_domain_hold) + $bits(done_layer_hold) +
        $bits(done_token_hold) + $bits(done_length_hold) + $bits(error_hold) +
        $bits(embedding_ram_fault) + (EXTERNAL_EMBEDDING_RAM ? 0 : 32) +
        NATIVE_VECTOR_BITS;
    assign dispatcher_state_bytes = rst_n ? 64'((DISPATCHER_BITS + 7) >> 3) : 64'd0;
    wire [63:0] text_reported_controllers = input_state_bytes + text_state_bytes +
        binding_controller_bytes + projection_controller_bytes +
        executor_controller_bytes + checkpoint_controller_bytes + tile_controller_bytes;
    wire [63:0] vision_reported_controllers = vision_state_bytes +
        vision_binding_controller_bytes + vision_patch_controller_bytes +
        vision_replay_controller_bytes + vision_executor_controller_bytes +
        vision_head_controller_bytes + vision_tile_controller_bytes +
        vision_clipped_controller_bytes + vision_clamp_controller_bytes +
        vision_output_controller_bytes + vision_output_clamp_controller_bytes +
        vision_post_controller_bytes + vision_norm_controller_bytes +
        vision_mlp_controller_bytes + vision_down_controller_bytes +
        vision_down_clamp_controller_bytes + vision_inner_controller_bytes +
        vision_inner_clamp_controller_bytes;
    wire [63:0] audio_reported_controllers = audio_input_controller_bytes +
        audio_layer_controller_bytes + audio_nested_controller_bytes +
        audio_feature_controller_bytes + audio_feature_nested_controller_bytes;
    assign native_reconstruction_controller_bytes = !rst_n ? 64'd0 :
        input_state_bytes + vision_reported_controllers + audio_reported_controllers +
        image_feature_controller_bytes + image_feature_nested_controller_bytes +
        64'((NATIVE_VECTOR_BITS + 7) >> 3);
    assign reported_controller_bytes = !rst_n ? 64'd0 :
        scheduler_state_bytes + dispatcher_state_bytes + workspace_controller_bytes +
        text_reported_controllers + vision_reported_controllers +
        audio_reported_controllers + image_feature_controller_bytes +
        image_feature_nested_controller_bytes;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            native_image_hold <= 0;
            native_vision_weights_hold <= 0;
            native_patches_hold <= 0;
            native_rows_hold <= 0;
            native_columns_hold <= 0;
            native_audio_hold <= 0;
            native_audio_weights_hold <= 0;
            native_audio_frames_hold <= 0;
        end else if (start_valid && start_ready) begin
            native_image_hold <= native_image_base;
            native_vision_weights_hold <= native_vision_weights_base;
            native_patches_hold <= native_patches;
            native_rows_hold <= native_patch_rows;
            native_columns_hold <= native_patch_columns;
            native_audio_hold <= native_audio_base;
            native_audio_weights_hold <= native_audio_weights_base;
            native_audio_frames_hold <= native_audio_frames;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            model_hold <= 0;
            precision_hold <= 0;
            modality_hold <= 0;
            mode_hold <= 0;
            domain_hold <= 0;
            token_hold <= 0;
            tokens_hold <= 0;
            generation_hold <= 0;
            dependency_token_hold <= 0;
            layer_hold <= 0;
            dependency_layer_hold <= 0;
            length_hold <= 0;
            dependency_length_hold <= 0;
            frame_hold <= 0;
            dependency_slot_hold <= 0;
            tokens_base_hold <= 0;
            weights_base_hold <= 0;
            continuation_hold <= 0;
            done_continuation_hold <= 0;
            dependency_valid_hold <= 0;
            input_worker <= 0;
            done_dependency_hold <= 0;
            done_bank_hold <= 0;
            dependency_domain_hold <= 0;
            done_domain_hold <= 0;
            done_layer_hold <= 0;
            done_token_hold <= 0;
            done_length_hold <= 0;
            error_hold <= 0;
        end else begin
            case (state)
                IDLE: if (task_valid && task_ready) begin
                    model_hold <= task_model;
                    precision_hold <= task_precision;
                    modality_hold <= task_modality;
                    mode_hold <= task_mode;
                    domain_hold <= task_domain;
                    token_hold <= task_token;
                    tokens_hold <= task_tokens;
                    generation_hold <= task_generation;
                    layer_hold <= task_layer;
                    length_hold <= task_length;
                    frame_hold <= task_frame;
                    tokens_base_hold <= task_tokens_base;
                    weights_base_hold <= task_weights_base;
                    continuation_hold <= task_continuation;
                    dependency_valid_hold <= task_dependency_valid;
                    dependency_domain_hold <= task_dependency_domain;
                    dependency_layer_hold <= task_dependency_layer;
                    dependency_token_hold <= task_dependency_token;
                    dependency_length_hold <= task_dependency_length;
                    dependency_slot_hold <= task_dependency_slot;
                    input_worker <= task_layer == 0;
                    error_hold <= 0;
                    done_dependency_hold <= 0;
                    done_bank_hold <= 0;
                    done_continuation_hold <= 0;
                    done_domain_hold <= 0;
                    done_layer_hold <= 0;
                    done_token_hold <= 0;
                    done_length_hold <= 0;
                    state <= VALIDATE;
                end
                VALIDATE: begin
                    if ((domain_hold == 3 && layer_hold != 1 && layer_hold != 2) ||
                        length_hold != (domain_hold == 2 ? 12'd1024 :
                        (domain_hold == 1 ? 12'd768 :
                        (COMPACT ? 12'd8 : (model_hold == 1 ? 12'd1536 : 12'd2560)))) ||
                        (domain_hold == 1 && (native_patches_hold == 0 ||
                            token_hold >= native_patches_hold)) ||
                        (domain_hold == 2 && (layer_hold > 12 || native_audio_frames_hold == 0 ||
                            native_audio_frames_hold > 131072 ||
                            token_hold >= ((native_audio_frames_hold + 32'd3) >> 2))) ||
                        (domain_hold == 3 && (token_hold >= tokens_hold ||
                            (layer_hold == 1 && native_patches_hold == 0) ||
                            (layer_hold == 2 && (native_audio_frames_hold == 0 ||
                                native_audio_frames_hold > 131072)))) ||
                        (input_worker && (domain_hold == 0 ? mode_hold > 1 : mode_hold != 0))) begin
                        error_hold <= 7;
                        state <= PUBLISH;
                    end else
                        state <= WORKER_START;
                end
                WORKER_START: if (((domain_hold != 1 &&
                    !(domain_hold == 2 && !input_worker)) || native_vector_owner == 0) &&
                    (domain_hold == 3 ?
                    (layer_hold == 1 ? image_feature_ready : feature_ready) : (domain_hold == 2 ? audio_ready :
                    (domain_hold == 1 ? vision_ready : (input_worker ? input_ready : text_ready)))))
                    state <= WORKER_WAIT;
                WORKER_WAIT: begin
                    if (domain_hold == 3 && layer_hold == 1 && image_feature_valid) begin
                        error_hold <= image_feature_error;
                        done_bank_hold <= image_feature_bank_result;
                        done_dependency_hold <= image_feature_yield;
                        done_continuation_hold <= image_feature_continuation;
                        done_domain_hold <= image_feature_dependency_domain;
                        done_layer_hold <= image_feature_dependency_layer;
                        done_token_hold <= image_feature_dependency_token;
                        done_length_hold <= image_feature_dependency_length;
                        state <= PUBLISH;
                    end else if (domain_hold == 3 && layer_hold == 2 && feature_valid) begin
                        error_hold <= feature_error;
                        done_bank_hold <= feature_bank_result;
                        done_dependency_hold <= feature_yield;
                        done_continuation_hold <= feature_continuation;
                        done_domain_hold <= feature_dependency_domain;
                        done_layer_hold <= feature_dependency_layer;
                        done_token_hold <= feature_dependency_token;
                        done_length_hold <= feature_dependency_length;
                        state <= PUBLISH;
                    end else if (domain_hold == 2 && audio_valid) begin
                        error_hold <= audio_error;
                        done_bank_hold <= audio_bank_result;
                        if (!input_worker) begin
                            done_dependency_hold <= audio_layer_yield;
                            done_continuation_hold <= audio_layer_continuation;
                            done_domain_hold <= audio_layer_dependency_domain;
                            done_layer_hold <= audio_layer_dependency_layer;
                            done_token_hold <= audio_layer_dependency_token;
                            done_length_hold <= audio_layer_dependency_length;
                        end
                        state <= PUBLISH;
                    end else if (domain_hold == 1 && vision_valid) begin
                        error_hold <= vision_error;
                        done_bank_hold <= vision_bank_result;
                        done_dependency_hold <= vision_yield;
                        done_continuation_hold <= vision_continuation;
                        done_domain_hold <= vision_dependency_domain;
                        done_layer_hold <= vision_dependency_layer;
                        done_token_hold <= vision_dependency_token;
                        done_length_hold <= vision_dependency_length;
                        state <= PUBLISH;
                    end else if (domain_hold == 0 && input_worker && input_valid) begin
                        error_hold <= input_error;
                        done_bank_hold <= input_bank_result;
                        done_dependency_hold <= input_yield;
                        done_continuation_hold <= input_continuation;
                        done_domain_hold <= input_dependency_domain;
                        done_layer_hold <= input_dependency_layer;
                        done_token_hold <= input_dependency_token;
                        done_length_hold <= input_dependency_length;
                        state <= PUBLISH;
                    end else if (domain_hold == 0 && !input_worker && text_valid) begin
                        error_hold <= text_error;
                        done_bank_hold <= text_bank_result;
                        done_dependency_hold <= text_yield;
                        done_continuation_hold <= text_continuation;
                        done_domain_hold <= text_dependency_domain;
                        done_layer_hold <= text_dependency_layer;
                        done_token_hold <= text_dependency_token;
                        done_length_hold <= text_dependency_length;
                        state <= PUBLISH;
                    end
                end
                PUBLISH: begin
                    if (error_hold == 0 && (embedding_ram_fault || native_vector_fault)) begin
                        error_hold <= 7;
                        done_dependency_hold <= 0;
                    end
                    state <= RESPONSE;
                end
                RESPONSE: if (task_done_ready)
                    state <= IDLE;
                default: begin
                    error_hold <= 7;
                    done_dependency_hold <= 0;
                    state <= PUBLISH;
                end
            endcase
        end
    end
endmodule
