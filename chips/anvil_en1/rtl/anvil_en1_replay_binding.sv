module anvil_en1_replay_binding #(
    parameter integer COMPACT = 0,
    parameter integer EXTERNAL_VECTOR_RAM = 0
) (
    input wire clk, rst_n,
    input wire control_valid,
    output wire control_ready,
    input wire control_invalidate, control_fallback,
    input wire [1:0] control_model, control_precision, control_modality,
    input wire [31:0] control_generation, control_tokens,
    input wire [63:0] control_tokens_base, control_weights_base,
    input wire [63:0] control_image_base, control_vision_weights_base,
    input wire [31:0] control_patches, control_patch_rows, control_patch_columns,
    input wire [63:0] control_audio_base, control_audio_weights_base,
    input wire [31:0] control_audio_frames,
    output wire control_rsp_valid,
    input wire control_rsp_ready,
    output wire [3:0] control_error,
    input wire regen_valid,
    output wire regen_ready,
    input wire [1:0] regen_model,
    input wire [7:0] regen_owner,
    input wire [31:0] regen_token,
    input wire regen_is_value,
    input wire [1:0] regen_kv_head,
    input wire [9:0] regen_component,
    output wire regen_rsp_valid,
    input wire regen_rsp_ready,
    output wire [31:0] regen_rsp_data,
    output wire [3:0] regen_rsp_error,
    output wire frontier_read_valid,
    input wire frontier_read_ready,
    output wire [31:0] frontier_read_generation, frontier_read_token,
    output wire [7:0] frontier_read_layer,
    output wire [11:0] frontier_read_component,
    input wire frontier_read_rsp_valid,
    output wire frontier_read_rsp_ready,
    input wire [31:0] frontier_read_rsp_data,
    input wire [3:0] frontier_read_rsp_error,
    output wire ring_read_valid,
    input wire ring_read_ready,
    output wire [1:0] ring_read_model,
    output wire [31:0] ring_read_generation, ring_read_token,
    output wire [7:0] ring_read_owner,
    output wire ring_read_is_value,
    output wire [1:0] ring_read_kv_head,
    output wire [9:0] ring_read_component,
    input wire ring_read_rsp_valid,
    output wire ring_read_rsp_ready,
    input wire ring_read_rsp_hit,
    input wire [31:0] ring_read_rsp_data,
    input wire [3:0] ring_read_rsp_error,
    input wire eval_start_valid,
    output wire eval_start_ready,
    input wire [1:0] eval_model, eval_precision, eval_modality, eval_domain,
    input wire [31:0] eval_generation, eval_tokens, eval_token,
    input wire [7:0] eval_layer,
    input wire [63:0] eval_tokens_base, eval_weights_base,
    output wire eval_output_valid,
    input wire eval_output_ready,
    output wire [31:0] eval_output_index,
    output wire [15:0] eval_output_data,
    output wire eval_output_last,
    output wire eval_done_valid,
    input wire eval_done_ready,
    output wire [3:0] eval_done_error,
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
    output wire cmd_valid,
    input wire cmd_ready,
    output wire cmd_write,
    output wire [63:0] cmd_addr,
    output wire [31:0] cmd_wdata,
    output wire [2:0] cmd_owner,
    output wire cmd_input,
    input wire result_valid,
    output wire result_ready,
    input wire [31:0] result_data,
    input wire result_error,
    output wire [6:0] frame_depth,
    output wire [63:0] workspace_live_bytes, workspace_shadow_bytes,
    output wire [63:0] native_workspace_bytes, native_workspace_shadow_bytes,
    output wire [63:0] workspace_reserved_bytes, workspace_metadata_bytes,
    output wire [63:0] owner_source_live_bytes, owner_source_physical_bytes,
    output wire [63:0] owner_tile_live_bytes, owner_tile_physical_bytes,
    output wire [63:0] text_tile_live_bytes, text_tile_physical_bytes,
    output wire [63:0] ple_live_bytes, ple_physical_bytes,
    output wire [63:0] embedding_live_bytes, embedding_physical_bytes,
    output wire [63:0] post_live_bytes, post_physical_bytes,
    output wire [63:0] text_tile_shadow_bytes, embedding_shadow_bytes, post_shadow_bytes,
    output wire [3:0] vector_ram_write, vector_ram_read,
    output wire [47:0] vector_ram_waddr, vector_ram_raddr,
    output wire [63:0] vector_ram_wdata,
    input wire [63:0] vector_ram_rdata,
    output wire [63:0] vision_live_bytes, vision_physical_bytes,
    output wire [63:0] audio_live_bytes, audio_physical_bytes,
    output wire [63:0] audio_feature_live_bytes, audio_feature_physical_bytes,
    output wire [63:0] image_feature_live_bytes, image_feature_physical_bytes,
    output wire [63:0] binding_state_bytes,
    output wire [63:0] reported_controller_bytes,
    output wire [63:0] native_reconstruction_controller_bytes,
    output wire memo_hit_event, memo_eviction_event, ring_hit_event,
    output wire owner_reprojection_event, replay_owner_reprojection_event,
    output wire [31:0] owner_reprojection_bytes, replay_owner_reprojection_bytes,
    output wire replay_input_event, replay_projection_event, replay_intermediate_event,
    output wire [31:0] replay_input_bytes, replay_projection_bytes, replay_intermediate_bytes,
    output wire [3:0] attention_activity,
    output wire avoided_projection_event,
    output wire [31:0] avoided_projection_bytes,
    output wire protocol_error,
    output wire busy
);
    localparam [2:0] CONTROL_IDLE = 0, CONTROL_VALIDATE = 1,
        CONTROL_SEND = 2, CONTROL_WAIT = 3, CONTROL_PUBLISH = 4,
        CONTROL_RESPONSE = 5;
    localparam [2:0] ROOT_IDLE = 0, ROOT_VALIDATE = 1, ROOT_SEND = 2,
        ROOT_WAIT = 3, ROOT_ERROR_PUBLISH = 4, ROOT_ERROR_RESPONSE = 5;
    reg [2:0] control_state, root_state;
    reg active, invalidate_hold, fallback_hold, root_owner;
    reg [1:0] model_hold, precision_hold, modality_hold;
    reg [31:0] generation_hold, tokens_hold;
    reg [63:0] tokens_base_hold, weights_base_hold;
    reg [63:0] image_base_hold, vision_weights_hold;
    reg [31:0] patches_hold, rows_hold, columns_hold;
    reg [63:0] audio_base_hold, audio_weights_hold;
    reg [31:0] audio_frames_hold;
    reg [1:0] root_model, root_precision, root_modality, root_domain;
    reg [31:0] root_generation, root_tokens, root_token;
    reg [7:0] root_layer;
    reg [63:0] root_tokens_base, root_weights_base;
    reg [3:0] control_error_hold, root_error_hold;

    initial begin
        if (COMPACT != 0 && COMPACT != 1)
            $fatal(1, "PARAMETER ERROR: COMPACT must be 0 or 1");
    end

    wire owner_control_ready, owner_control_valid;
    wire [3:0] owner_control_error;
    wire owner_busy, replay_busy, owner_regen_ready;
    wire owner_eval_valid, owner_eval_ready, owner_eval_output_ready, owner_eval_done_ready;
    wire [1:0] owner_eval_model, owner_eval_precision, owner_eval_domain;
    wire [31:0] owner_eval_generation, owner_eval_tokens, owner_eval_token;
    wire [7:0] owner_eval_layer;
    wire engine_ready, engine_output_valid, engine_output_last, engine_done_valid;
    wire [31:0] engine_output_index;
    wire [15:0] engine_output_data;
    wire [3:0] engine_done_error;
    wire [1:0] client_cmd_valid, client_cmd_ready, client_cmd_write;
    wire [127:0] client_cmd_addr;
    wire [63:0] client_cmd_wdata, client_result_data;
    wire [1:0] client_result_valid, client_result_ready, client_result_error;
    wire control_open = rst_n && control_state == CONTROL_IDLE &&
        root_state == ROOT_IDLE && !owner_busy && !replay_busy;
    wire root_open = rst_n && active && control_state == CONTROL_IDLE &&
        root_state == ROOT_IDLE;
    wire owner_route = rst_n && root_owner && root_state == ROOT_WAIT;
    wire frontier_route = rst_n && !root_owner && root_state == ROOT_WAIT;
    wire root_error_valid = rst_n && root_state == ROOT_ERROR_RESPONSE;
    wire selected_output_ready = root_owner ? owner_eval_output_ready : eval_output_ready;
    wire selected_done_ready = root_owner ? owner_eval_done_ready : eval_done_ready;
    wire root_descriptor_good = root_model == model_hold &&
        root_precision == precision_hold && root_modality == modality_hold &&
        root_generation == generation_hold && root_tokens == tokens_hold &&
        root_tokens_base == tokens_base_hold && root_weights_base == weights_base_hold;

    assign control_ready = control_open;
    assign control_rsp_valid = rst_n && control_state == CONTROL_RESPONSE;
    assign control_error = rst_n ? control_error_hold : 4'd0;
    assign regen_ready = rst_n && active && control_state == CONTROL_IDLE &&
        !control_valid && owner_regen_ready;
    assign owner_eval_ready = root_open;
    assign eval_start_ready = root_open && !control_valid && !owner_eval_valid;
    assign eval_output_valid = frontier_route && engine_output_valid;
    assign eval_output_index = rst_n ? engine_output_index : 32'd0;
    assign eval_output_data = rst_n ? engine_output_data : 16'd0;
    assign eval_output_last = frontier_route && engine_output_last;
    assign eval_done_valid = (frontier_route && engine_done_valid) ||
        (root_error_valid && !root_owner);
    assign eval_done_error = !rst_n ? 4'd0 :
        (root_error_valid ? root_error_hold : engine_done_error);
    assign busy = rst_n && (control_state != CONTROL_IDLE ||
        root_state != ROOT_IDLE || owner_busy || replay_busy);
    localparam integer BINDING_BITS = $bits(control_state) + $bits(root_state) +
        $bits(active) + $bits(invalidate_hold) + $bits(fallback_hold) + $bits(root_owner) +
        $bits(model_hold) + $bits(precision_hold) + $bits(modality_hold) +
        $bits(generation_hold) + $bits(tokens_hold) + $bits(tokens_base_hold) +
        $bits(weights_base_hold) + $bits(image_base_hold) + $bits(vision_weights_hold) +
        $bits(patches_hold) + $bits(rows_hold) + $bits(columns_hold) +
        $bits(audio_base_hold) + $bits(audio_weights_hold) + $bits(audio_frames_hold) +
        $bits(root_model) + $bits(root_precision) + $bits(root_modality) + $bits(root_domain) +
        $bits(root_generation) + $bits(root_tokens) + $bits(root_token) +
        $bits(root_layer) + $bits(root_tokens_base) + $bits(root_weights_base) +
        $bits(control_error_hold) + $bits(root_error_hold);
    assign binding_state_bytes = rst_n ? 64'((BINDING_BITS + 7) >> 3) : 64'd0;
    wire [63:0] owner_controller_bytes, replay_controller_bytes, memory_controller_bytes;
    assign reported_controller_bytes = !rst_n ? 64'd0 :
        owner_controller_bytes + replay_controller_bytes + memory_controller_bytes;

    anvil_en1_owner_replay #(.COMPACT(COMPACT)) owner_replay (
        .clk(clk), .rst_n(rst_n),
        .control_valid(rst_n && control_state == CONTROL_SEND),
        .control_ready(owner_control_ready), .control_invalidate(invalidate_hold),
        .control_fallback(fallback_hold), .control_model(model_hold),
        .control_precision(precision_hold), .control_generation(generation_hold),
        .control_tokens(tokens_hold), .control_weights_base(weights_base_hold),
        .control_rsp_valid(owner_control_valid),
        .control_rsp_ready(rst_n && control_state == CONTROL_WAIT),
        .control_error(owner_control_error),
        .regen_valid(rst_n && active && control_state == CONTROL_IDLE &&
            !control_valid && regen_valid),
        .regen_ready(owner_regen_ready), .regen_model(regen_model), .regen_owner(regen_owner),
        .regen_token(regen_token), .regen_is_value(regen_is_value),
        .regen_kv_head(regen_kv_head), .regen_component(regen_component),
        .regen_rsp_valid(regen_rsp_valid), .regen_rsp_ready(regen_rsp_ready),
        .regen_rsp_data(regen_rsp_data), .regen_rsp_error(regen_rsp_error),
        .frontier_read_valid(frontier_read_valid), .frontier_read_ready(frontier_read_ready),
        .frontier_read_generation(frontier_read_generation),
        .frontier_read_token(frontier_read_token), .frontier_read_layer(frontier_read_layer),
        .frontier_read_component(frontier_read_component),
        .frontier_read_rsp_valid(frontier_read_rsp_valid),
        .frontier_read_rsp_ready(frontier_read_rsp_ready),
        .frontier_read_rsp_data(frontier_read_rsp_data),
        .frontier_read_rsp_error(frontier_read_rsp_error),
        .ring_read_valid(ring_read_valid), .ring_read_ready(ring_read_ready),
        .ring_read_model(ring_read_model), .ring_read_generation(ring_read_generation),
        .ring_read_token(ring_read_token), .ring_read_owner(ring_read_owner),
        .ring_read_is_value(ring_read_is_value), .ring_read_kv_head(ring_read_kv_head),
        .ring_read_component(ring_read_component), .ring_read_rsp_valid(ring_read_rsp_valid),
        .ring_read_rsp_ready(ring_read_rsp_ready), .ring_read_rsp_hit(ring_read_rsp_hit),
        .ring_read_rsp_data(ring_read_rsp_data), .ring_read_rsp_error(ring_read_rsp_error),
        .eval_start_valid(owner_eval_valid), .eval_start_ready(owner_eval_ready),
        .eval_model(owner_eval_model), .eval_precision(owner_eval_precision),
        .eval_domain(owner_eval_domain), .eval_generation(owner_eval_generation),
        .eval_token(owner_eval_token), .eval_tokens(owner_eval_tokens),
        .eval_layer(owner_eval_layer),
        .eval_output_valid(owner_route && engine_output_valid),
        .eval_output_ready(owner_eval_output_ready),
        .eval_output_index(engine_output_index), .eval_output_data(engine_output_data),
        .eval_output_last(owner_route && engine_output_last),
        .eval_done_valid((owner_route && engine_done_valid) ||
            (root_error_valid && root_owner)),
        .eval_done_ready(owner_eval_done_ready),
        .eval_done_error(root_error_valid ? root_error_hold : engine_done_error),
        .cmd_valid(client_cmd_valid[0]), .cmd_ready(client_cmd_ready[0]),
        .cmd_write(client_cmd_write[0]), .cmd_addr(client_cmd_addr[0+:64]),
        .cmd_wdata(client_cmd_wdata[0+:32]),
        .result_valid(client_result_valid[0]), .result_ready(client_result_ready[0]),
        .result_data(client_result_data[0+:32]), .result_error(client_result_error[0]),
        .raw_source_live_bytes(owner_source_live_bytes),
        .raw_source_physical_bytes(owner_source_physical_bytes),
        .tile_live_bytes(owner_tile_live_bytes), .tile_physical_bytes(owner_tile_physical_bytes),
        .controller_bytes(owner_controller_bytes),
        .owner_reprojection_event(owner_reprojection_event),
        .owner_reprojection_bytes(owner_reprojection_bytes),
        .ring_hit_event(ring_hit_event), .busy(owner_busy)
    );

    anvil_en1_replay_execute #(
        .COMPACT(COMPACT), .EXTERNAL_VECTOR_RAM(EXTERNAL_VECTOR_RAM)
    ) replay (
        .vector_ram_write(vector_ram_write), .vector_ram_read(vector_ram_read),
        .vector_ram_waddr(vector_ram_waddr), .vector_ram_raddr(vector_ram_raddr),
        .vector_ram_wdata(vector_ram_wdata), .vector_ram_rdata(vector_ram_rdata),
        .clk(clk), .rst_n(rst_n),
        .attention_activity(attention_activity),
        .avoided_projection_event(avoided_projection_event),
        .avoided_projection_bytes(avoided_projection_bytes),
        .start_valid(rst_n && root_state == ROOT_SEND), .start_ready(engine_ready),
        .model(root_model), .precision(root_precision), .modality(root_modality),
        .eval_domain(root_domain), .generation(root_generation),
        .tokens(root_tokens), .token(root_token), .layer(root_layer),
        .tokens_base(root_tokens_base), .weights_base(root_weights_base),
        .native_image_base(image_base_hold), .native_vision_weights_base(vision_weights_hold),
        .native_patches(patches_hold), .native_patch_rows(rows_hold),
        .native_patch_columns(columns_hold), .native_audio_base(audio_base_hold),
        .native_audio_weights_base(audio_weights_hold), .native_audio_frames(audio_frames_hold),
        .modality_ready(1'b0), .modality_rsp_valid(1'b0),
        .modality_rsp_data(16'd0), .modality_rsp_error(1'b1),
        .mask_valid(mask_valid), .mask_ready(mask_ready), .mask_token(mask_token),
        .mask_rsp_valid(mask_rsp_valid), .mask_rsp_ready(mask_rsp_ready),
        .mask_rsp_data(mask_rsp_data), .mask_rsp_error(mask_rsp_error),
        .req_valid(req_valid), .req_ready(req_ready), .req_op(req_op),
        .req_model(req_model), .req_layer(req_layer), .req_token(req_token),
        .req_is_value(req_is_value), .req_kv_head(req_kv_head),
        .req_component(req_component), .req_base(req_base),
        .rsp_valid(rsp_valid), .rsp_ready(rsp_ready), .rsp_addr(rsp_addr),
        .rsp_owner(rsp_owner), .rsp_alias(rsp_alias), .rsp_error(rsp_error),
        .rsp_space(rsp_space),
        .cmd_valid(client_cmd_valid[1]), .cmd_ready(client_cmd_ready[1]),
        .cmd_write(client_cmd_write[1]), .cmd_addr(client_cmd_addr[64+:64]),
        .cmd_wdata(client_cmd_wdata[32+:32]),
        .result_valid(client_result_valid[1]), .result_ready(client_result_ready[1]),
        .result_data(client_result_data[32+:32]), .result_error(client_result_error[1]),
        .output_valid(engine_output_valid),
        .output_ready(rst_n && root_state == ROOT_WAIT && selected_output_ready),
        .output_index(engine_output_index), .output_data(engine_output_data),
        .output_last(engine_output_last), .done_valid(engine_done_valid),
        .done_ready(rst_n && root_state == ROOT_WAIT && selected_done_ready),
        .done_error(engine_done_error),
        .backing_valid(backing_valid), .backing_ready(backing_ready),
        .backing_generation(backing_generation), .backing_write(backing_write),
        .backing_addr(backing_addr), .backing_wdata(backing_wdata),
        .backing_rsp_valid(backing_rsp_valid), .backing_rsp_ready(backing_rsp_ready),
        .backing_rsp_data(backing_rsp_data), .backing_rsp_error(backing_rsp_error),
        .frame_depth(frame_depth), .live_payload_bytes(workspace_live_bytes),
        .production_shadow_bytes(workspace_shadow_bytes),
        .native_payload_bytes(native_workspace_bytes),
        .native_production_shadow_bytes(native_workspace_shadow_bytes),
        .backing_reserved_bytes(workspace_reserved_bytes),
        .visibility_metadata_bytes(workspace_metadata_bytes),
        .tile_live_bytes(text_tile_live_bytes), .tile_physical_bytes(text_tile_physical_bytes),
        .tile_shadow_bytes(text_tile_shadow_bytes),
        .ple_live_bytes(ple_live_bytes), .ple_physical_bytes(ple_physical_bytes),
        .embedding_live_bytes(embedding_live_bytes),
        .embedding_shadow_bytes(embedding_shadow_bytes),
        .embedding_physical_bytes(embedding_physical_bytes),
        .post_vector_live_bytes(post_live_bytes), .post_vector_physical_bytes(post_physical_bytes),
        .post_vector_shadow_bytes(post_shadow_bytes),
        .vision_vector_live_bytes(vision_live_bytes),
        .vision_vector_physical_bytes(vision_physical_bytes),
        .audio_vector_live_bytes(audio_live_bytes),
        .audio_vector_physical_bytes(audio_physical_bytes),
        .audio_feature_vector_live_bytes(audio_feature_live_bytes),
        .audio_feature_vector_physical_bytes(audio_feature_physical_bytes),
        .image_feature_vector_live_bytes(image_feature_live_bytes),
        .image_feature_vector_physical_bytes(image_feature_physical_bytes),
        .memo_hit_event(memo_hit_event), .memo_eviction_event(memo_eviction_event),
        .owner_reprojection_event(replay_owner_reprojection_event),
        .owner_reprojection_bytes(replay_owner_reprojection_bytes),
        .native_input_read_event(replay_input_event),
        .native_input_read_bytes(replay_input_bytes),
        .native_projection_event(replay_projection_event),
        .native_projection_bytes(replay_projection_bytes),
        .native_intermediate_event(replay_intermediate_event),
        .native_intermediate_bytes(replay_intermediate_bytes),
        .reported_controller_bytes(replay_controller_bytes),
        .native_reconstruction_controller_bytes(native_reconstruction_controller_bytes),
        .busy(replay_busy)
    );

    anvil_en1_memory_arbiter #(.CLIENTS(2), .READ_ONLY(1)) memory (
        .clk(clk), .rst_n(rst_n),
        .client_cmd_valid(client_cmd_valid), .client_cmd_ready(client_cmd_ready),
        .client_cmd_write(client_cmd_write), .client_cmd_addr(client_cmd_addr),
        .client_cmd_wdata(client_cmd_wdata), .client_result_valid(client_result_valid),
        .client_input_read_event({replay_input_event, 1'b0}),
        .client_cmd_replay(2'b11),
        .client_result_ready(client_result_ready), .client_result_data(client_result_data),
        .client_result_error(client_result_error),
        .cmd_valid(cmd_valid), .cmd_ready(cmd_ready), .cmd_write(cmd_write),
        .cmd_addr(cmd_addr), .cmd_wdata(cmd_wdata), .cmd_owner(cmd_owner),
        .cmd_input(cmd_input), .cmd_replay(),
        .result_valid(result_valid), .result_ready(result_ready),
        .result_data(result_data), .result_error(result_error),
        .drain_valid(1'b0), .drain_done_ready(1'b1), .protocol_error(protocol_error),
        .controller_bytes(memory_controller_bytes)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            control_state <= CONTROL_IDLE;
            active <= 0;
            invalidate_hold <= 0;
            fallback_hold <= 0;
            model_hold <= 0;
            precision_hold <= 0;
            modality_hold <= 0;
            generation_hold <= 0;
            tokens_hold <= 0;
            tokens_base_hold <= 0;
            weights_base_hold <= 0;
            image_base_hold <= 0;
            vision_weights_hold <= 0;
            patches_hold <= 0;
            rows_hold <= 0;
            columns_hold <= 0;
            audio_base_hold <= 0;
            audio_weights_hold <= 0;
            audio_frames_hold <= 0;
            control_error_hold <= 0;
        end else begin
            case (control_state)
                CONTROL_IDLE: if (control_valid && control_ready) begin
                    active <= 0;
                    invalidate_hold <= control_invalidate;
                    fallback_hold <= control_fallback;
                    model_hold <= control_model;
                    precision_hold <= control_precision;
                    modality_hold <= control_modality;
                    generation_hold <= control_generation;
                    tokens_hold <= control_tokens;
                    tokens_base_hold <= control_tokens_base;
                    weights_base_hold <= control_weights_base;
                    image_base_hold <= control_image_base;
                    vision_weights_hold <= control_vision_weights_base;
                    patches_hold <= control_patches;
                    rows_hold <= control_patch_rows;
                    columns_hold <= control_patch_columns;
                    audio_base_hold <= control_audio_base;
                    audio_weights_hold <= control_audio_weights_base;
                    audio_frames_hold <= control_audio_frames;
                    control_error_hold <= 0;
                    control_state <= CONTROL_VALIDATE;
                end
                CONTROL_VALIDATE: begin
                    if (!invalidate_hold && ((model_hold != 1 && model_hold != 2) ||
                        precision_hold > 1)) begin
                        control_error_hold <= 6;
                        control_state <= CONTROL_PUBLISH;
                    end else if (!invalidate_hold && (tokens_hold == 0 ||
                        tokens_hold > 131072 || tokens_base_hold[1:0] ||
                        weights_base_hold[1:0])) begin
                        control_error_hold <= 5;
                        control_state <= CONTROL_PUBLISH;
                    end else
                        control_state <= CONTROL_SEND;
                end
                CONTROL_SEND: if (owner_control_ready)
                    control_state <= CONTROL_WAIT;
                CONTROL_WAIT: if (owner_control_valid) begin
                    control_error_hold <= owner_control_error;
                    active <= !invalidate_hold && owner_control_error == 0;
                    control_state <= CONTROL_PUBLISH;
                end
                CONTROL_PUBLISH: control_state <= CONTROL_RESPONSE;
                CONTROL_RESPONSE: if (control_rsp_ready)
                    control_state <= CONTROL_IDLE;
                default: begin
                    active <= 0;
                    control_error_hold <= 7;
                    control_state <= CONTROL_PUBLISH;
                end
            endcase
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            root_state <= ROOT_IDLE;
            root_owner <= 0;
            root_model <= 0;
            root_precision <= 0;
            root_modality <= 0;
            root_domain <= 0;
            root_generation <= 0;
            root_tokens <= 0;
            root_token <= 0;
            root_layer <= 0;
            root_tokens_base <= 0;
            root_weights_base <= 0;
            root_error_hold <= 0;
        end else begin
            case (root_state)
                ROOT_IDLE: if (owner_eval_valid && owner_eval_ready) begin
                    root_owner <= 1;
                    root_model <= owner_eval_model;
                    root_precision <= owner_eval_precision;
                    root_modality <= modality_hold;
                    root_domain <= owner_eval_domain;
                    root_generation <= owner_eval_generation;
                    root_tokens <= owner_eval_tokens;
                    root_token <= owner_eval_token;
                    root_layer <= owner_eval_layer;
                    root_tokens_base <= tokens_base_hold;
                    root_weights_base <= weights_base_hold;
                    root_error_hold <= 0;
                    root_state <= ROOT_VALIDATE;
                end else if (eval_start_valid && eval_start_ready) begin
                    root_owner <= 0;
                    root_model <= eval_model;
                    root_precision <= eval_precision;
                    root_modality <= eval_modality;
                    root_domain <= eval_domain;
                    root_generation <= eval_generation;
                    root_tokens <= eval_tokens;
                    root_token <= eval_token;
                    root_layer <= eval_layer;
                    root_tokens_base <= eval_tokens_base;
                    root_weights_base <= eval_weights_base;
                    root_error_hold <= 0;
                    root_state <= ROOT_VALIDATE;
                end
                ROOT_VALIDATE: begin
                    if ((root_model != 1 && root_model != 2) || root_precision > 1) begin
                        root_error_hold <= 6;
                        root_state <= ROOT_ERROR_PUBLISH;
                    end else if (!root_descriptor_good) begin
                        root_error_hold <= 7;
                        root_state <= ROOT_ERROR_PUBLISH;
                    end else
                        root_state <= ROOT_SEND;
                end
                ROOT_SEND: if (engine_ready)
                    root_state <= ROOT_WAIT;
                ROOT_WAIT: if (engine_done_valid && selected_done_ready)
                    root_state <= ROOT_IDLE;
                ROOT_ERROR_PUBLISH: root_state <= ROOT_ERROR_RESPONSE;
                ROOT_ERROR_RESPONSE: if (selected_done_ready)
                    root_state <= ROOT_IDLE;
                default: begin
                    root_error_hold <= 7;
                    root_state <= ROOT_ERROR_PUBLISH;
                end
            endcase
        end
    end
endmodule
