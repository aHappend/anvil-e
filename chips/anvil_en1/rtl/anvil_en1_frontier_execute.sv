module anvil_en1_frontier_execute #(
    parameter integer COMPACT = 0,
    parameter integer EXTERNAL_VECTOR_RAM = 0,
    parameter integer EXTERNAL_EMBEDDING_RAM = 0,
    parameter integer EXTERNAL_HIDDEN_RAM = 0,
    parameter integer SHARED_PLE = 0
) (
    input wire image_immutable, image_invalidate,
    input wire clk, rst_n,
    input wire control_valid,
    output wire control_ready,
    input wire control_invalidate,
    input wire [1:0] control_model, control_precision, control_modality,
    input wire [31:0] control_generation, control_tokens,
    input wire [63:0] control_tokens_base, control_weights_base,
    output wire control_rsp_valid,
    input wire control_rsp_ready,
    output wire [3:0] control_error,
    input wire task_valid,
    output wire task_ready,
    input wire [2:0] task_op,
    input wire [1:0] task_model, task_precision,
    input wire [31:0] task_generation, task_tokens, task_token,
    input wire [7:0] task_layer,
    input wire task_source_frontier,
    output wire task_done_valid,
    input wire task_done_ready,
    output wire [3:0] task_done_error,
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
    output wire fetch_valid,
    input wire fetch_ready,
    output wire [1:0] fetch_model,
    output wire [7:0] fetch_owner,
    output wire [31:0] fetch_token,
    output wire fetch_is_value,
    output wire [1:0] fetch_kv_head,
    output wire [9:0] fetch_component,
    input wire fetch_rsp_valid,
    output wire fetch_rsp_ready,
    input wire [15:0] fetch_rsp_data,
    input wire [3:0] fetch_rsp_error,
    input wire owner_read_valid,
    output wire owner_read_ready,
    input wire [31:0] owner_read_generation, owner_read_token,
    input wire [7:0] owner_read_layer,
    input wire [11:0] owner_read_component,
    output wire owner_read_rsp_valid,
    input wire owner_read_rsp_ready,
    output wire [31:0] owner_read_rsp_data,
    output wire [3:0] owner_read_rsp_error,
    input wire ring_read_valid,
    output wire ring_read_ready,
    input wire [1:0] ring_read_model,
    input wire [31:0] ring_read_generation, ring_read_token,
    input wire [7:0] ring_read_owner,
    input wire ring_read_is_value,
    input wire [1:0] ring_read_kv_head,
    input wire [9:0] ring_read_component,
    output wire ring_read_rsp_valid,
    input wire ring_read_rsp_ready,
    output wire ring_read_rsp_hit,
    output wire [31:0] ring_read_rsp_data,
    output wire [3:0] ring_read_rsp_error,
    output wire eval_start_valid,
    input wire eval_start_ready,
    output wire [1:0] eval_model, eval_precision, eval_modality, eval_domain,
    output wire [31:0] eval_generation, eval_tokens, eval_token,
    output wire [7:0] eval_layer,
    output wire [63:0] eval_tokens_base, eval_weights_base,
    input wire eval_output_valid,
    output wire eval_output_ready,
    input wire [31:0] eval_output_index,
    input wire [15:0] eval_output_data,
    input wire eval_output_last,
    input wire eval_done_valid,
    output wire eval_done_ready,
    input wire [3:0] eval_done_error,
    input wire backing_valid,
    output wire backing_ready,
    input wire [31:0] backing_generation,
    input wire backing_write,
    input wire [17:0] backing_addr,
    input wire [31:0] backing_wdata,
    output wire backing_rsp_valid,
    input wire backing_rsp_ready,
    output wire [31:0] backing_rsp_data,
    output wire [3:0] backing_rsp_error,
    output wire cmd_valid,
    input wire cmd_ready,
    output wire cmd_write,
    output wire input_read_event,
    output wire [63:0] cmd_addr,
    output wire [31:0] cmd_wdata,
    input wire result_valid,
    output wire result_ready,
    input wire [31:0] result_data,
    input wire result_error,
    output wire logit_valid,
    input wire logit_ready,
    output wire [15:0] logit_data,
    output wire [17:0] logit_index,
    output wire logit_last,
    output wire [63:0] vector_live_bytes, vector_physical_bytes,
    output wire [63:0] vector_shadow_bytes,
    output wire [63:0] feature_live_bytes, feature_physical_bytes,
    output wire [63:0] frontier_live_bytes, frontier_physical_bytes,
    output wire [63:0] frontier_shadow_bytes,
    output wire [63:0] frontier_metadata_bytes,
    output wire [63:0] ring_live_bytes, ring_physical_bytes, ring_metadata_bytes,
    output wire [63:0] ring_shadow_bytes,
    output wire [63:0] anchor_live_bytes, anchor_physical_bytes,
    output wire grant_valid,
    input wire grant_ready,
    output wire [4:0] grant_component,
    output wire [63:0] grant_payload_bytes, grant_shadow_bytes,
    input wire grant_rsp_valid,
    output wire grant_rsp_ready,
    input wire grant_allowed,
    output wire [191:0] execution_live_bytes, execution_physical_bytes,
    output wire [191:0] execution_shadow_bytes,
    output wire [3:0] vector_ram_write, vector_ram_read,
    output wire [47:0] vector_ram_waddr, vector_ram_raddr,
    output wire [63:0] vector_ram_wdata,
    input wire [63:0] vector_ram_rdata,
    output wire [1:0] embedding_ram_write, embedding_ram_read,
    output wire [63:0] embedding_ram_waddr, embedding_ram_raddr,
    output wire [31:0] embedding_ram_wdata,
    input wire [31:0] embedding_ram_rdata,
    output wire hidden_ram_write, hidden_ram_read,
    output wire [31:0] hidden_ram_waddr, hidden_ram_raddr,
    output wire [15:0] hidden_ram_wdata,
    input wire [15:0] hidden_ram_rdata,
    output wire [63:0] reported_controller_bytes,
    output wire [3:0] attention_activity,
    output wire avoided_projection_event,
    output wire [31:0] avoided_projection_bytes,
    output wire backing_bound,
    output wire busy
);
    localparam integer MAX_H = COMPACT ? 8 : 2560;
    localparam integer P = COMPACT ? 4 : 256;
    localparam integer H_BITS = $clog2(MAX_H);
    localparam [5:0] IDLE = 0, CONTROL_VALIDATE = 1, VALIDATE = 2,
        FRONTIER_CONTROL = 3, FRONTIER_CONTROL_WAIT = 4,
        FRONTIER_RELEASED = 5, RING_CONTROL = 6, RING_CONTROL_WAIT = 7,
        BOTH_RELEASED = 8, CONFIG_FRONTIER_DONE = 9,
        EMBED_START = 10, EMBED_WAIT = 11, EMBED_COMMIT = 12,
        LAYER_START = 13, LAYER_WAIT = 14, VECTOR_COMMIT = 15,
        WRITE_START = 16, WRITE_LOW_READ = 17, WRITE_LOW_CAPTURE = 18,
        WRITE_HIGH_READ = 19, WRITE_HIGH_CAPTURE = 20,
        WRITE_SEND = 21, WRITE_WAIT = 22, ANCHOR_START = 23,
        ANCHOR_WAIT = 24, EVAL_START = 25, EVAL_WAIT = 26,
        LOGITS_START = 27, LOGITS_WAIT = 28, PUBLISH = 29, RESPONSE = 30,
        TOKEN_ADDRESS = 31, TOKEN_SEND = 32, TOKEN_WAIT = 33, TOKEN_CLASSIFY = 34,
        FEATURE_START = 35, FEATURE_WAIT = 36, FEATURE_COMMIT = 37,
        ALLOCATION_SEND = 38, ALLOCATION_WAIT = 39,
        EMBED_PRIVATE_GRANT = 40, EVAL_OUTPUT_DRAIN = 41, FEATURE_DRAIN = 42;
    localparam [2:0] S_IDLE = 0, S_VALIDATE = 1, S_LOCAL_READ = 2,
        S_LOCAL_CAPTURE = 3, S_FRONTIER_SEND = 4, S_FRONTIER_WAIT = 5,
        S_RESPONSE = 6;
    localparam [1:0] READ_IDLE = 0, READ_SEND = 1, READ_WAIT = 2,
        READ_RESPONSE = 3;
    localparam [2:0] FEATURE_IDLE = 0, FEATURE_VALIDATE = 1,
        FEATURE_READ = 2, FEATURE_CAPTURE = 3, FEATURE_RESPONSE = 4;
    localparam [2:0] M_NONE = 0, M_EMBED = 1, M_LAYER = 2, M_LOGITS = 3, M_TOKEN = 4;
    reg [5:0] state, frontier_return, ring_return;
    reg [4:0] allocation_component;
    reg [5:0] allocation_return;
    reg frontier_reserved, ring_reserved, vector_reserved, feature_reserved;
    reg anchor_reserved, embedding_reserved, layer_reserved;
    reg admission_fault;
    reg [63:0] frontier_reservation_hold, frontier_shadow_hold;
    reg [63:0] ring_reservation_hold, ring_shadow_hold;
    reg [2:0] operation, source_state;
    reg [1:0] model_hold, precision_hold, modality_hold, frontier_operation;
    reg [1:0] read_state;
    reg [2:0] feature_state;
    reg [31:0] generation_hold, tokens_hold, token_hold, hidden_hold;
    reg [63:0] tokens_base_hold, weights_base_hold;
    reg [63:0] token_address_hold;
    reg [31:0] token_id_hold;
    reg token_error_hold;
    reg [1:0] token_modality;
    reg [7:0] layer_hold;
    reg active, is_control, invalidate_hold, source_frontier;
    reg ordinary_configured, fallback_configured, frontier_frozen, ring_invalidate;
    reg h_allocated, h_committed, p_allocated, p_committed;
    reg [7:0] vector_layer;
    reg [31:0] vector_token, vector_generation;
    reg [31:0] h_count, p_count, input_count, write_component;
    reg h_bad, h_complete, p_bad, p_complete, input_bad, input_complete;
    reg [3:0] error_hold, child_error;
    reg [31:0] write_pair;
    reg source_is_ple_hold, source_is_logits, source_is_normalized_hold, source_error_hold;
    reg [31:0] logits_normalized_count;
    reg logits_normalized_bad;
    reg [31:0] source_index_hold;
    reg [15:0] source_data_hold, ple_q;
    wire [15:0] hidden_q;
    reg read_owner;
    reg [31:0] read_generation_hold, read_token_hold, read_data_hold;
    reg [7:0] read_layer_hold;
    reg [11:0] read_component_hold;
    reg [3:0] read_error_hold;
    reg feature_allocated, feature_committed, feature_bad, feature_complete;
    reg [31:0] feature_count, feature_generation, feature_token;
    reg [1:0] feature_kind, feature_request_model, feature_request_kind;
    reg [31:0] feature_request_token, feature_request_index;
    reg [15:0] feature_q, feature_data_hold;
    reg feature_error_hold;
    (* ramstyle = "M20K", nomem2reg *)
    reg [15:0] feature_payload [0:MAX_H-1];
    wire [31:0] CONTROLLER_BITS =
        $bits(state) + $bits(frontier_return) + $bits(ring_return) +
        $bits(allocation_component) + $bits(allocation_return) +
        $bits(frontier_reserved) + $bits(ring_reserved) +
        $bits(vector_reserved) + $bits(feature_reserved) + $bits(anchor_reserved) +
        $bits(embedding_reserved) + $bits(layer_reserved) +
        $bits(admission_fault) +
        $bits(frontier_reservation_hold) + $bits(frontier_shadow_hold) +
        $bits(ring_reservation_hold) + $bits(ring_shadow_hold) +
        $bits(operation) + $bits(source_state) + $bits(model_hold) +
        $bits(precision_hold) + $bits(modality_hold) + $bits(frontier_operation) +
        $bits(read_state) + $bits(feature_state) + $bits(generation_hold) +
        $bits(tokens_hold) + $bits(token_hold) + $bits(hidden_hold) +
        $bits(tokens_base_hold) + $bits(weights_base_hold) + $bits(token_address_hold) +
        $bits(token_id_hold) + $bits(token_error_hold) + $bits(token_modality) +
        $bits(layer_hold) + $bits(active) + $bits(is_control) +
        $bits(invalidate_hold) + $bits(source_frontier) + $bits(ordinary_configured) +
        $bits(fallback_configured) + $bits(frontier_frozen) + $bits(ring_invalidate) +
        $bits(h_allocated) + $bits(h_committed) + $bits(p_allocated) +
        $bits(p_committed) + $bits(vector_layer) + $bits(vector_token) +
        $bits(vector_generation) + $bits(h_count) + $bits(p_count) +
        $bits(input_count) + $bits(write_component) + $bits(h_bad) +
        $bits(h_complete) + $bits(p_bad) + $bits(p_complete) + $bits(input_bad) +
        $bits(input_complete) + $bits(error_hold) + $bits(child_error) +
        $bits(write_pair) + $bits(source_is_ple_hold) + $bits(source_is_logits) +
        $bits(source_is_normalized_hold) + $bits(logits_normalized_count) +
        $bits(logits_normalized_bad) +
        $bits(source_error_hold) + $bits(source_index_hold) +
        $bits(source_data_hold) + $bits(hidden_q) + $bits(ple_q) +
        $bits(read_owner) + $bits(read_generation_hold) + $bits(read_token_hold) +
        $bits(read_data_hold) + $bits(read_layer_hold) + $bits(read_component_hold) +
        $bits(read_error_hold) + $bits(feature_allocated) + $bits(feature_committed) +
        $bits(feature_bad) + $bits(feature_complete) + $bits(feature_count) +
        $bits(feature_generation) + $bits(feature_token) + $bits(feature_kind) +
        $bits(feature_request_model) + $bits(feature_request_kind) +
        $bits(feature_request_token) + $bits(feature_request_index) +
        $bits(feature_q) + $bits(feature_data_hold) + $bits(feature_error_hold);
    wire [63:0] frontier_controller_bytes, ring_controller_bytes;
    wire [63:0] embed_controller_bytes, layer_controller_bytes;
    wire [63:0] anchor_controller_bytes, logits_controller_bytes;
    assign reported_controller_bytes = !rst_n ? 64'd0 :
        64'((CONTROLLER_BITS+7) >> 3) + frontier_controller_bytes + ring_controller_bytes +
        embed_controller_bytes + layer_controller_bytes +
        anchor_controller_bytes + logits_controller_bytes;

    initial begin
        if (COMPACT != 0 && COMPACT != 1)
            $fatal(1, "PARAMETER ERROR: COMPACT must be 0 or 1");
        if (EXTERNAL_EMBEDDING_RAM != 0 && EXTERNAL_EMBEDDING_RAM != 1)
            $fatal(1, "PARAMETER ERROR: EXTERNAL_EMBEDDING_RAM must be 0 or 1");
        if ((EXTERNAL_HIDDEN_RAM != 0 && EXTERNAL_HIDDEN_RAM != 1) ||
            (EXTERNAL_HIDDEN_RAM == 1 && EXTERNAL_VECTOR_RAM != 1))
            $fatal(1, "PARAMETER ERROR: EXTERNAL_HIDDEN_RAM must be 0 or 1; external hidden storage requires external vectors");
        if ((SHARED_PLE != 0 && SHARED_PLE != 1) ||
            (SHARED_PLE == 1 && EXTERNAL_VECTOR_RAM != 1))
            $fatal(1, "PARAMETER ERROR: SHARED_PLE must be 0 or 1; shared PLE requires external vectors");
    end

    wire native_model;
    wire [31:0] padded_count = (tokens_hold + 32'd15) & 32'hfffffff0;
    wire [31:0] ring_tokens = padded_count > (COMPACT ? 4 : 512) ?
        (COMPACT ? 32'd4 : 32'd512) : padded_count;
    wire [31:0] shadow_ring_tokens = padded_count > 512 ? 32'd512 : padded_count;
    wire [63:0] shadow_frontier_bytes = model_hold == 1 ?
        ({32'd0, padded_count} << 11) + ({32'd0, padded_count} << 10) :
        ({32'd0, padded_count} << 12) + ({32'd0, padded_count} << 10);
    wire [63:0] reserved_frontier_bytes = COMPACT ?
        {32'd0, padded_count} << 4 : shadow_frontier_bytes;
    wire [63:0] reserved_ring_bytes = {32'd0, ring_tokens} <<
        (COMPACT ? 4 : (model_hold == 1 ? 10 : 11));
    wire [63:0] shadow_ring_bytes = {32'd0, shadow_ring_tokens} <<
        (model_hold == 1 ? 10 : 11);
    wire [63:0] actual_frontier_bytes, actual_ring_bytes, actual_anchor_bytes;
    wire [191:0] child_execution_bytes;
    wire [127:0] child_execution_shadow;
    wire [63:0] hidden_bytes = {32'd0, hidden_hold} << 1;
    wire [63:0] shadow_hidden_bytes = model_hold == 1 ? 64'd3072 : 64'd5120;
    wire [63:0] embedding_bytes = hidden_bytes + 64'(2*P);
    wire [63:0] embedding_shadow = shadow_hidden_bytes + 64'd512;
    wire [63:0] vector_reservation_bytes = operation == 7 ?
        hidden_bytes : embedding_bytes;
    wire [63:0] vector_reservation_shadow = operation == 7 ?
        shadow_hidden_bytes : embedding_shadow;
    wire selected_global;
    wire [63:0] head_bytes = COMPACT ?
        (selected_global ? 64'd16 : 64'd8) :
        (selected_global ? 64'd1024 : 64'd512);
    wire [63:0] shadow_head_bytes = selected_global ? 64'd1024 : 64'd512;
    wire [63:0] layer_attention_bytes = (hidden_bytes << 1) +
        hidden_bytes + 64'(2*P) + head_bytes;
    wire [63:0] layer_feedforward_bytes = (hidden_bytes << 1) +
        hidden_bytes + 64'(2*P);
    wire [63:0] layer_phase_bytes = layer_attention_bytes > layer_feedforward_bytes ?
        layer_attention_bytes : layer_feedforward_bytes;
    wire [63:0] layer_bytes = layer_phase_bytes -
        (EXTERNAL_HIDDEN_RAM ? hidden_bytes : 64'd0) -
        (SHARED_PLE ? 64'(2*P) : 64'd0);
    wire [63:0] layer_attention_shadow = (shadow_hidden_bytes << 1) +
        shadow_hidden_bytes + 64'd512 + shadow_head_bytes;
    wire [63:0] layer_feedforward_shadow = (shadow_hidden_bytes << 1) +
        shadow_hidden_bytes + 64'd512;
    wire [63:0] layer_phase_shadow = layer_attention_shadow > layer_feedforward_shadow ?
        layer_attention_shadow : layer_feedforward_shadow;
    wire [63:0] layer_shadow = layer_phase_shadow -
        (EXTERNAL_HIDDEN_RAM ? shadow_hidden_bytes : 64'd0) -
        (SHARED_PLE ? 64'd512 : 64'd0);
    wire [63:0] candidate_bytes = allocation_component == 0 ? reserved_frontier_bytes :
        (allocation_component == 1 ? reserved_ring_bytes :
        (allocation_component == 2 ? vector_reservation_bytes :
        (allocation_component == 3 ? hidden_bytes :
        (allocation_component == 4 ? 64'(COMPACT ? 8 : 512) :
        (allocation_component == 19 ? embedding_bytes : layer_bytes)))));
    wire [63:0] candidate_shadow = allocation_component == 0 ? shadow_frontier_bytes :
        (allocation_component == 1 ? shadow_ring_bytes :
        (allocation_component == 2 ? vector_reservation_shadow :
        (allocation_component == 3 ? shadow_hidden_bytes :
        (allocation_component == 4 ? 64'd512 :
        (allocation_component == 19 ? embedding_shadow : layer_shadow)))));
    assign frontier_live_bytes = !rst_n ? 64'd0 :
        (frontier_reserved && frontier_reservation_hold > actual_frontier_bytes ?
            frontier_reservation_hold : actual_frontier_bytes);
    assign frontier_shadow_bytes = rst_n && frontier_reserved ?
        frontier_shadow_hold : 64'd0;
    assign ring_live_bytes = !rst_n ? 64'd0 :
        (ring_reserved && ring_reservation_hold > actual_ring_bytes ?
            ring_reservation_hold : actual_ring_bytes);
    assign ring_shadow_bytes = rst_n && ring_reserved ? ring_shadow_hold : 64'd0;
    assign anchor_live_bytes = !rst_n ? 64'd0 :
        (anchor_reserved && 64'(COMPACT ? 8 : 512) > actual_anchor_bytes ?
            64'(COMPACT ? 8 : 512) : actual_anchor_bytes);
    assign execution_live_bytes[0+:64] = !rst_n ? 64'd0 :
        (embedding_reserved && embedding_bytes > child_execution_bytes[0+:64] ?
            embedding_bytes : child_execution_bytes[0+:64]);
    assign execution_shadow_bytes[0+:64] = !rst_n ? 64'd0 :
        (embedding_reserved && embedding_shadow > child_execution_shadow[0+:64] ?
            embedding_shadow : child_execution_shadow[0+:64]);
    assign execution_live_bytes[64+:64] = !rst_n ? 64'd0 :
        (layer_reserved && layer_bytes > child_execution_bytes[64+:64] ?
            layer_bytes : child_execution_bytes[64+:64]);
    assign execution_shadow_bytes[64+:64] = !rst_n ? 64'd0 :
        (layer_reserved && layer_shadow > child_execution_shadow[64+:64] ?
            layer_shadow : child_execution_shadow[64+:64]);
    assign execution_live_bytes[128+:64] = child_execution_bytes[128+:64];
    assign grant_valid = rst_n && state == ALLOCATION_SEND;
    assign grant_component = rst_n ? allocation_component : 5'd0;
    assign grant_payload_bytes = rst_n ? candidate_bytes : 64'd0;
    assign grant_shadow_bytes = rst_n ? candidate_shadow : 64'd0;
    assign grant_rsp_ready = rst_n && state == ALLOCATION_WAIT;
    wire [7:0] selected_layers, selected_owners;
    wire [11:0] selected_hidden;
    anvil_en1_geometry geometry (
        .rst_n(rst_n), .model(model_hold), .layer(layer_hold),
        .is_native(native_model), .layers(selected_layers), .owners(selected_owners),
        .owner(), .is_global(selected_global), .hidden(selected_hidden), .intermediate()
    );
    wire session_matches = task_model == model_hold &&
        task_precision == precision_hold && task_generation == generation_hold &&
        task_tokens == tokens_hold;
    wire expected_frontier = operation == 2 || operation == 3 ||
        (operation == 5 && layer_hold == selected_owners - 8'd1);
    wire retained_source_valid = h_committed &&
        vector_generation == generation_hold && vector_token == token_hold &&
        vector_layer == layer_hold;
    wire final_vector_valid = h_committed &&
        vector_generation == generation_hold && vector_token == tokens_hold - 1'b1 &&
        vector_layer == selected_layers;
    wire [64:0] token_address_sum = {1'b0, tokens_base_hold} +
        {31'd0, token_hold, 2'd0};
    wire [64:0] token_address_end = token_address_sum + 65'd3;
    wire token_image = token_id_hold == (COMPACT ? 32'd28 : 32'd258880);
    wire token_audio = token_id_hold == (COMPACT ? 32'd29 : 32'd258881);
    wire image_allowed = modality_hold == 1 || modality_hold == 3;
    wire audio_allowed = modality_hold == 2 || modality_hold == 3;
    wire feature_eval = state == FEATURE_START || state == FEATURE_WAIT ||
        state == FEATURE_COMMIT || state == FEATURE_DRAIN;

    wire frontier_control_ready, frontier_control_valid;
    wire [3:0] frontier_control_error;
    wire frontier_capacity_fallback;
    wire f_write_start_ready, f_write_ready, f_write_done_valid;
    wire [3:0] f_write_done_error;
    wire f_read_ready, f_read_valid;
    wire [31:0] f_read_data;
    wire [3:0] f_read_error;
    wire layer_frontier_valid = rst_n && source_state == S_FRONTIER_SEND;
    wire layer_frontier_ready = rst_n && read_state == READ_IDLE && !owner_read_valid;
    wire layer_frontier_rsp_valid = rst_n && read_state == READ_RESPONSE && !read_owner;
    wire layer_frontier_rsp_ready = rst_n && source_state == S_FRONTIER_WAIT;
    wire control_ingress = rst_n && state == FRONTIER_CONTROL && read_state == READ_IDLE;
    anvil_en1_frontier #(.COMPACT(COMPACT)) frontier (
        .clk(clk), .rst_n(rst_n),
        .control_valid(control_ingress), .control_ready(frontier_control_ready),
        .control_op(frontier_operation), .control_model(model_hold),
        .control_generation(generation_hold), .control_tokens(tokens_hold),
        .control_rsp_valid(frontier_control_valid),
        .control_rsp_ready(rst_n && state == FRONTIER_CONTROL_WAIT),
        .control_error(frontier_control_error), .fallback_needed(frontier_capacity_fallback),
        .padded_tokens(), .live_bytes(actual_frontier_bytes),
        .physical_payload_bytes(frontier_physical_bytes),
        .controller_bytes(frontier_controller_bytes),
        .token_metadata_bytes(frontier_metadata_bytes),
        .write_start_valid(rst_n && state == WRITE_START && read_state == READ_IDLE),
        .write_start_ready(f_write_start_ready),
        .write_generation(generation_hold), .write_token(token_hold),
        .write_layer(operation == 1 ? 8'd0 : layer_hold + 8'd1),
        .write_valid(rst_n && state == WRITE_SEND), .write_ready(f_write_ready),
        .write_data(write_pair), .write_first(write_component == 0),
        .write_last(write_component == hidden_hold - 32'd2),
        .write_done_valid(f_write_done_valid),
        .write_done_ready(rst_n && (state == WRITE_WAIT || state == WRITE_SEND)),
        .write_done_error(f_write_done_error),
        .read_valid(rst_n && read_state == READ_SEND), .read_ready(f_read_ready),
        .read_generation(read_generation_hold), .read_token(read_token_hold),
        .read_layer(read_layer_hold), .read_component(read_component_hold),
        .read_rsp_valid(f_read_valid),
        .read_rsp_ready(rst_n && read_state == READ_WAIT),
        .read_rsp_data(f_read_data), .read_rsp_error(f_read_error),
        .backing_bound(backing_bound),
        .backing_valid(backing_valid), .backing_ready(backing_ready),
        .backing_generation(backing_generation), .backing_write(backing_write),
        .backing_addr(backing_addr), .backing_wdata(backing_wdata),
        .backing_rsp_valid(backing_rsp_valid), .backing_rsp_ready(backing_rsp_ready),
        .backing_rsp_data(backing_rsp_data), .backing_rsp_error(backing_rsp_error)
    );
    wire ring_control_ready, ring_control_valid;
    wire [3:0] ring_control_error;
    wire anchor_write_start_valid, anchor_write_start_ready;
    wire [1:0] anchor_write_model, anchor_write_head;
    wire [31:0] anchor_write_generation, anchor_write_token, anchor_write_data;
    wire [7:0] anchor_write_owner;
    wire anchor_write_value, anchor_write_valid, anchor_write_ready;
    wire anchor_write_first, anchor_write_last, anchor_write_done_valid;
    wire anchor_write_done_ready;
    wire [3:0] anchor_write_done_error;
    anvil_en1_local_ring #(.COMPACT(COMPACT)) ring (
        .clk(clk), .rst_n(rst_n),
        .control_valid(rst_n && state == RING_CONTROL), .control_ready(ring_control_ready),
        .control_invalidate(ring_invalidate), .control_model(model_hold),
        .control_generation(generation_hold), .control_tokens(tokens_hold),
        .control_rsp_valid(ring_control_valid),
        .control_rsp_ready(rst_n && state == RING_CONTROL_WAIT),
        .control_error(ring_control_error), .live_bytes(actual_ring_bytes),
        .physical_payload_bytes(ring_physical_bytes), .token_metadata_bytes(ring_metadata_bytes),
        .controller_bytes(ring_controller_bytes),
        .write_start_valid(anchor_write_start_valid), .write_start_ready(anchor_write_start_ready),
        .write_model(anchor_write_model), .write_generation(anchor_write_generation),
        .write_token(anchor_write_token), .write_owner(anchor_write_owner),
        .write_is_value(anchor_write_value), .write_kv_head(anchor_write_head),
        .write_valid(anchor_write_valid), .write_ready(anchor_write_ready),
        .write_data(anchor_write_data), .write_first(anchor_write_first),
        .write_last(anchor_write_last), .write_done_valid(anchor_write_done_valid),
        .write_done_ready(anchor_write_done_ready), .write_done_error(anchor_write_done_error),
        .read_valid(ring_read_valid), .read_ready(ring_read_ready),
        .read_model(ring_read_model), .read_generation(ring_read_generation),
        .read_token(ring_read_token), .read_owner(ring_read_owner),
        .read_is_value(ring_read_is_value), .read_kv_head(ring_read_kv_head),
        .read_component(ring_read_component), .read_rsp_valid(ring_read_rsp_valid),
        .read_rsp_ready(ring_read_rsp_ready), .read_rsp_hit(ring_read_rsp_hit),
        .read_rsp_data(ring_read_rsp_data), .read_rsp_error(ring_read_rsp_error)
    );

    wire embed_ready, embed_done, embed_input_valid, embed_input_last;
    wire embed_ple_valid, embed_ple_last, embed_cmd_valid, embed_result_ready;
    wire [31:0] embed_input_index, embed_ple_index, embed_cmd_wdata;
    wire [15:0] embed_input_data, embed_ple_data;
    wire [63:0] embed_cmd_addr;
    wire embed_cmd_write;
    wire embed_input_event;
    wire [3:0] embed_error;
    wire layer_ready, layer_done, layer_output_valid, layer_output_last;
    wire layer_cmd_valid, layer_cmd_write, layer_result_ready;
    wire [31:0] layer_output_index, layer_cmd_wdata;
    wire [15:0] layer_output_data;
    wire [63:0] layer_cmd_addr;
    wire [3:0] layer_error;
    wire layer_source_valid, layer_source_rsp_ready, layer_source_ple;
    wire [1:0] layer_source_model;
    wire [7:0] layer_source_layer;
    wire [31:0] layer_source_token, layer_source_index;
    wire logits_ready, logits_done, logits_cmd_valid, logits_cmd_write;
    wire logits_result_ready, logits_source_valid, logits_source_rsp_ready;
    wire logits_source_normalized, logits_store_valid, logits_store_last;
    wire [31:0] logits_store_index;
    wire [15:0] logits_store_data;
    wire [31:0] logits_source_index, logits_cmd_wdata;
    wire [63:0] logits_cmd_addr;
    wire [3:0] logits_error;
    wire [2:0] memory_owner = state == EMBED_START || state == EMBED_WAIT ||
        state == EMBED_COMMIT ? M_EMBED :
        (state == LAYER_START || state == LAYER_WAIT ||
        (state == VECTOR_COMMIT && operation != 7) ? M_LAYER :
        (state == LOGITS_START || state == LOGITS_WAIT ? M_LOGITS :
        (state == TOKEN_SEND || state == TOKEN_WAIT ? M_TOKEN : M_NONE)));
    wire embed_modality_valid, embed_modality_rsp_ready;
    wire [1:0] embed_modality_model, embed_modality_kind;
    wire [31:0] embed_modality_token, embed_modality_index;
    anvil_en1_embedding_ple #(
        .COMPACT(COMPACT), .EXTERNAL_VECTOR_RAM(EXTERNAL_EMBEDDING_RAM)
    ) embedding (
        .image_immutable(image_immutable === 1'b1),
        .image_invalidate((image_invalidate === 1'b1) || (control_valid && control_ready)),
        .vector_ram_write(embedding_ram_write), .vector_ram_read(embedding_ram_read),
        .vector_ram_waddr(embedding_ram_waddr), .vector_ram_raddr(embedding_ram_raddr),
        .vector_ram_wdata(embedding_ram_wdata), .vector_ram_rdata(embedding_ram_rdata),
        .controller_bytes(embed_controller_bytes),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == EMBED_START), .start_ready(embed_ready),
        .model(model_hold), .precision(precision_hold), .modality(token_modality),
        .layer(layer_hold), .token(token_hold),
        .tokens_base(tokens_base_hold), .weights_base(weights_base_hold),
        .modality_valid(embed_modality_valid),
        .modality_ready(rst_n && state == EMBED_WAIT && feature_state == FEATURE_IDLE),
        .modality_model(embed_modality_model), .modality_kind(embed_modality_kind),
        .modality_token(embed_modality_token), .modality_index(embed_modality_index),
        .modality_rsp_valid(rst_n && feature_state == FEATURE_RESPONSE),
        .modality_rsp_ready(embed_modality_rsp_ready),
        .modality_rsp_data(feature_data_hold), .modality_rsp_error(feature_error_hold),
        .input_valid(embed_input_valid), .input_ready(rst_n && state == EMBED_WAIT),
        .input_index(embed_input_index), .input_data(embed_input_data),
        .input_last(embed_input_last), .ple_valid(embed_ple_valid),
        .ple_ready(rst_n && state == EMBED_WAIT), .ple_index(embed_ple_index),
        .ple_data(embed_ple_data), .ple_last(embed_ple_last),
        .cmd_valid(embed_cmd_valid), .cmd_ready(memory_owner == M_EMBED && cmd_ready),
        .cmd_write(embed_cmd_write), .cmd_addr(embed_cmd_addr), .cmd_wdata(embed_cmd_wdata),
        .input_read_event(embed_input_event),
        .result_valid(memory_owner == M_EMBED && result_valid),
        .result_ready(embed_result_ready), .result_data(result_data), .result_error(result_error),
        .done_valid(embed_done), .done_ready(rst_n && state == EMBED_WAIT),
        .done_error(embed_error),
        .live_payload_bytes(child_execution_bytes[0+:64]),
        .production_shadow_bytes(child_execution_shadow[0+:64]),
        .physical_payload_bytes(execution_physical_bytes[0+:64])
    );
    wire layer_req_valid, layer_req_value, layer_rsp_ready;
    wire [2:0] layer_req_op;
    wire [1:0] layer_req_model, layer_req_head;
    wire [7:0] layer_req_layer;
    wire [31:0] layer_req_token;
    wire [9:0] layer_req_component;
    wire [63:0] layer_req_base;
    wire layer_fetch_valid, layer_fetch_value, layer_fetch_rsp_ready;
    wire [1:0] layer_fetch_model, layer_fetch_head;
    wire [7:0] layer_fetch_owner;
    wire [31:0] layer_fetch_token;
    wire [9:0] layer_fetch_component;
    wire anchor_selected = operation == 2 &&
        (state == ANCHOR_START || state == ANCHOR_WAIT);
    wire layer_selected = state == LAYER_START || state == LAYER_WAIT;
    wire [3:0] layer_vector_write, layer_vector_read;
    wire [47:0] layer_vector_waddr, layer_vector_raddr;
    wire [63:0] layer_vector_wdata;
    wire [63:0] layer_vector_rdata = SHARED_PLE ?
        {ple_q, vector_ram_rdata[47:0]} : vector_ram_rdata;
    assign vector_ram_write = SHARED_PLE ?
        {1'b0, layer_vector_write[2:0]} : layer_vector_write;
    assign vector_ram_read = SHARED_PLE ?
        {1'b0, layer_vector_read[2:0]} : layer_vector_read;
    assign vector_ram_waddr = SHARED_PLE ?
        {12'd0, layer_vector_waddr[35:0]} : layer_vector_waddr;
    assign vector_ram_raddr = SHARED_PLE ?
        {12'd0, layer_vector_raddr[35:0]} : layer_vector_raddr;
    assign vector_ram_wdata = SHARED_PLE ?
        {16'd0, layer_vector_wdata[47:0]} : layer_vector_wdata;
    anvil_en1_asym_attn_ple #(
        .COMPACT(COMPACT), .EXTERNAL_VECTOR_RAM(EXTERNAL_VECTOR_RAM),
        .SHARED_RESIDUAL(EXTERNAL_HIDDEN_RAM), .SHARED_PLE(SHARED_PLE)
    ) text_layer (
        .image_immutable(image_immutable === 1'b1),
        .image_invalidate((image_invalidate === 1'b1) || (control_valid && control_ready)),
        .vector_ram_write(layer_vector_write), .vector_ram_read(layer_vector_read),
        .vector_ram_waddr(layer_vector_waddr), .vector_ram_raddr(layer_vector_raddr),
        .vector_ram_wdata(layer_vector_wdata), .vector_ram_rdata(layer_vector_rdata),
        .controller_bytes(layer_controller_bytes),
        .clk(clk), .rst_n(rst_n),
        .attention_activity(attention_activity),
        .avoided_projection_event(avoided_projection_event),
        .avoided_projection_bytes(avoided_projection_bytes),
        .start_valid(rst_n && state == LAYER_START), .start_ready(layer_ready),
        .model(model_hold), .precision(precision_hold), .layer(layer_hold),
        .token(token_hold), .weights_base(weights_base_hold),
        .source_valid(layer_source_valid),
        .source_ready(rst_n && source_state == S_IDLE && state == LAYER_WAIT),
        .source_model(layer_source_model), .source_layer(layer_source_layer),
        .source_token(layer_source_token), .source_index(layer_source_index),
        .source_is_ple(layer_source_ple),
        .source_is_branch(),
        .source_rsp_valid(rst_n && source_state == S_RESPONSE && !source_is_logits),
        .source_rsp_ready(layer_source_rsp_ready), .source_rsp_data(source_data_hold),
        .source_rsp_error(source_error_hold),
        .mask_valid(mask_valid), .mask_ready(mask_ready), .mask_token(mask_token),
        .mask_rsp_valid(mask_rsp_valid), .mask_rsp_ready(mask_rsp_ready),
        .mask_rsp_data(mask_rsp_data), .mask_rsp_error(mask_rsp_error),
        .req_valid(layer_req_valid), .req_ready(layer_selected && req_ready),
        .req_op(layer_req_op), .req_model(layer_req_model), .req_layer(layer_req_layer),
        .req_token(layer_req_token), .req_is_value(layer_req_value),
        .req_kv_head(layer_req_head), .req_component(layer_req_component),
        .req_base(layer_req_base), .rsp_valid(layer_selected && rsp_valid),
        .rsp_ready(layer_rsp_ready), .rsp_addr(rsp_addr), .rsp_owner(rsp_owner),
        .rsp_alias(rsp_alias), .rsp_error(rsp_error), .rsp_space(rsp_space),
        .fetch_valid(layer_fetch_valid), .fetch_ready(layer_selected && fetch_ready),
        .fetch_model(layer_fetch_model), .fetch_owner(layer_fetch_owner),
        .fetch_token(layer_fetch_token), .fetch_is_value(layer_fetch_value),
        .fetch_kv_head(layer_fetch_head), .fetch_component(layer_fetch_component),
        .fetch_rsp_valid(layer_selected && fetch_rsp_valid),
        .fetch_rsp_ready(layer_fetch_rsp_ready), .fetch_rsp_data(fetch_rsp_data),
        .fetch_rsp_error(fetch_rsp_error),
        .cmd_valid(layer_cmd_valid), .cmd_ready(memory_owner == M_LAYER && cmd_ready),
        .cmd_write(layer_cmd_write), .cmd_addr(layer_cmd_addr), .cmd_wdata(layer_cmd_wdata),
        .result_valid(memory_owner == M_LAYER && result_valid),
        .result_ready(layer_result_ready), .result_data(result_data), .result_error(result_error),
        .output_valid(layer_output_valid), .output_ready(rst_n && state == LAYER_WAIT),
        .output_index(layer_output_index), .output_data(layer_output_data),
        .output_last(layer_output_last), .done_valid(layer_done),
        .done_ready(rst_n && state == LAYER_WAIT), .done_error(layer_error),
        .live_payload_bytes(child_execution_bytes[64+:64]),
        .production_shadow_bytes(child_execution_shadow[64+:64]),
        .physical_payload_bytes(execution_physical_bytes[64+:64])
    );
    wire anchor_ready, anchor_done, anchor_req_valid, anchor_req_value, anchor_rsp_ready;
    wire [2:0] anchor_req_op;
    wire [1:0] anchor_req_model, anchor_req_head;
    wire [7:0] anchor_req_layer;
    wire [31:0] anchor_req_token;
    wire [9:0] anchor_req_component;
    wire [63:0] anchor_req_base;
    wire anchor_fetch_valid, anchor_fetch_value, anchor_fetch_rsp_ready;
    wire [1:0] anchor_fetch_model, anchor_fetch_head;
    wire [7:0] anchor_fetch_owner;
    wire [31:0] anchor_fetch_token;
    wire [9:0] anchor_fetch_component;
    wire [3:0] anchor_error;
    anvil_en1_anchor_materialize #(.COMPACT(COMPACT)) anchor (
        .controller_bytes(anchor_controller_bytes),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == ANCHOR_START), .start_ready(anchor_ready),
        .model(model_hold), .owner(layer_hold), .generation(generation_hold), .token(token_hold),
        .req_valid(anchor_req_valid), .req_ready(anchor_selected && req_ready),
        .req_op(anchor_req_op), .req_model(anchor_req_model), .req_layer(anchor_req_layer),
        .req_token(anchor_req_token), .req_is_value(anchor_req_value),
        .req_kv_head(anchor_req_head), .req_component(anchor_req_component),
        .req_base(anchor_req_base), .rsp_valid(anchor_selected && rsp_valid),
        .rsp_ready(anchor_rsp_ready), .rsp_owner(rsp_owner), .rsp_alias(rsp_alias),
        .rsp_error(rsp_error), .rsp_space(rsp_space),
        .fetch_valid(anchor_fetch_valid), .fetch_ready(anchor_selected && fetch_ready),
        .fetch_model(anchor_fetch_model), .fetch_owner(anchor_fetch_owner),
        .fetch_token(anchor_fetch_token), .fetch_is_value(anchor_fetch_value),
        .fetch_kv_head(anchor_fetch_head), .fetch_component(anchor_fetch_component),
        .fetch_rsp_valid(anchor_selected && fetch_rsp_valid),
        .fetch_rsp_ready(anchor_fetch_rsp_ready), .fetch_rsp_data(fetch_rsp_data),
        .fetch_rsp_error(fetch_rsp_error),
        .write_start_valid(anchor_write_start_valid), .write_start_ready(anchor_write_start_ready),
        .write_model(anchor_write_model), .write_generation(anchor_write_generation),
        .write_token(anchor_write_token), .write_owner(anchor_write_owner),
        .write_is_value(anchor_write_value), .write_kv_head(anchor_write_head),
        .write_valid(anchor_write_valid), .write_ready(anchor_write_ready),
        .write_data(anchor_write_data), .write_first(anchor_write_first),
        .write_last(anchor_write_last), .write_done_valid(anchor_write_done_valid),
        .write_done_ready(anchor_write_done_ready), .write_done_error(anchor_write_done_error),
        .done_valid(anchor_done), .done_ready(rst_n && state == ANCHOR_WAIT),
        .done_error(anchor_error), .live_payload_bytes(actual_anchor_bytes),
        .physical_payload_bytes(anchor_physical_bytes)
    );
    anvil_en1_final_logits #(.COMPACT(COMPACT), .EXTERNAL_PAYLOAD_RAM(1)) logits (
        .image_immutable(image_immutable === 1'b1),
        .image_invalidate((image_invalidate === 1'b1) || (control_valid && control_ready)),
        .controller_bytes(logits_controller_bytes),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == LOGITS_START), .start_ready(logits_ready),
        .model(model_hold), .precision(precision_hold), .weights_base(weights_base_hold),
        .source_valid(logits_source_valid),
        .source_ready(rst_n && source_state == S_IDLE && state == LOGITS_WAIT),
        .source_index(logits_source_index),
        .source_is_normalized(logits_source_normalized),
        .source_rsp_valid(rst_n && source_state == S_RESPONSE && source_is_logits),
        .source_rsp_ready(logits_source_rsp_ready), .source_rsp_data(source_data_hold),
        .source_rsp_error(source_error_hold),
        .normalized_store_valid(logits_store_valid),
        .normalized_store_ready(rst_n && state == LOGITS_WAIT),
        .normalized_store_index(logits_store_index),
        .normalized_store_data(logits_store_data), .normalized_store_last(logits_store_last),
        .cmd_valid(logits_cmd_valid), .cmd_ready(memory_owner == M_LOGITS && cmd_ready),
        .cmd_write(logits_cmd_write), .cmd_addr(logits_cmd_addr), .cmd_wdata(logits_cmd_wdata),
        .result_valid(memory_owner == M_LOGITS && result_valid),
        .result_ready(logits_result_ready), .result_data(result_data), .result_error(result_error),
        .logit_valid(logit_valid), .logit_ready(logit_ready), .logit_data(logit_data),
        .logit_index(logit_index), .logit_last(logit_last),
        .done_valid(logits_done), .done_ready(rst_n && state == LOGITS_WAIT),
        .done_error(logits_error),
        .live_payload_bytes(child_execution_bytes[128+:64]),
        .physical_payload_bytes(execution_physical_bytes[128+:64])
    );

    assign control_ready = rst_n && state == IDLE && read_state == READ_IDLE &&
        source_state == S_IDLE && feature_state == FEATURE_IDLE;
    assign control_rsp_valid = rst_n && state == RESPONSE && is_control;
    assign control_error = rst_n ? error_hold : 4'd0;
    assign task_ready = rst_n && state == IDLE && read_state == READ_IDLE &&
        source_state == S_IDLE && feature_state == FEATURE_IDLE && !control_valid;
    assign task_done_valid = rst_n && state == RESPONSE && !is_control;
    assign task_done_error = rst_n ? error_hold : 4'd0;
    assign busy = rst_n && (state != IDLE || read_state != READ_IDLE || source_state != S_IDLE);
    assign owner_read_ready = rst_n && read_state == READ_IDLE &&
        (!control_valid || state != IDLE) &&
        state != FRONTIER_CONTROL && state != FRONTIER_CONTROL_WAIT &&
        state != WRITE_START && state != WRITE_LOW_READ && state != WRITE_LOW_CAPTURE &&
        state != WRITE_HIGH_READ && state != WRITE_HIGH_CAPTURE &&
        state != WRITE_SEND && state != WRITE_WAIT;
    assign owner_read_rsp_valid = rst_n && read_state == READ_RESPONSE && read_owner;
    assign owner_read_rsp_data = rst_n ? read_data_hold : 32'd0;
    assign owner_read_rsp_error = rst_n ? read_error_hold : 4'd0;
    wire [63:0] actual_vector_bytes =
        (h_allocated ? {32'd0, hidden_hold} << 1 : 64'd0) +
        (p_allocated ? 64'(2*P) : 64'd0);
    wire [63:0] actual_vector_shadow =
        (h_allocated ? (model_hold == 1 ? 64'd3072 : 64'd5120) : 64'd0) +
        (p_allocated ? 64'd512 : 64'd0);
    assign vector_live_bytes = !rst_n ? 64'd0 :
        (vector_reserved && vector_reservation_bytes > actual_vector_bytes ?
            vector_reservation_bytes : actual_vector_bytes);
    assign vector_shadow_bytes = !rst_n ? 64'd0 :
        (vector_reserved && vector_reservation_shadow > actual_vector_shadow ?
            vector_reservation_shadow : actual_vector_shadow);
    wire shared_ple_fault;
    wire reservation_overrun = shared_ple_fault ||
        (frontier_reserved && actual_frontier_bytes > frontier_reservation_hold) ||
        (ring_reserved && actual_ring_bytes > ring_reservation_hold) ||
        (anchor_reserved && actual_anchor_bytes > 64'(COMPACT ? 8 : 512)) ||
        (vector_reserved && (actual_vector_bytes > vector_reservation_bytes ||
            actual_vector_shadow > vector_reservation_shadow)) ||
        (embedding_reserved && (child_execution_bytes[0+:64] > embedding_bytes ||
            child_execution_shadow[0+:64] > embedding_shadow)) ||
        (layer_reserved && (child_execution_bytes[64+:64] > layer_bytes ||
            child_execution_shadow[64+:64] > layer_shadow));
    assign execution_shadow_bytes[128+:64] = execution_live_bytes[128+:64];
    assign vector_physical_bytes = rst_n && !EXTERNAL_HIDDEN_RAM ?
        64'(2*MAX_H) : 64'd0;
    assign feature_live_bytes = rst_n && (feature_allocated || feature_reserved) ?
        {32'd0, hidden_hold} << 1 : 64'd0;
    assign feature_physical_bytes = rst_n ? 64'(2*MAX_H) : 64'd0;
    assign modality_valid = 1'b0;
    assign modality_model = 2'd0;
    assign modality_kind = 2'd0;
    assign modality_token = 32'd0;
    assign modality_index = 32'd0;
    assign modality_rsp_ready = 1'b0;
    assign eval_start_valid = rst_n && (state == EVAL_START || state == FEATURE_START);
    assign eval_model = rst_n ? model_hold : 2'd0;
    assign eval_precision = rst_n ? precision_hold : 2'd0;
    assign eval_modality = rst_n ? modality_hold : 2'd0;
    assign eval_domain = rst_n && feature_eval ? 2'd3 : 2'd0;
    assign eval_generation = rst_n ? generation_hold : 32'd0;
    assign eval_tokens = rst_n ? tokens_hold : 32'd0;
    assign eval_token = rst_n ? token_hold : 32'd0;
    assign eval_layer = !rst_n ? 8'd0 :
        (feature_eval ? {6'd0, token_modality} : layer_hold);
    assign eval_tokens_base = rst_n ? tokens_base_hold : 64'd0;
    assign eval_weights_base = rst_n ? weights_base_hold : 64'd0;
    assign eval_output_ready = rst_n &&
        (state == FEATURE_DRAIN || state == EVAL_OUTPUT_DRAIN ||
            (state == EVAL_WAIT && vector_reserved) ||
            (state == FEATURE_WAIT && feature_reserved));
    assign eval_done_ready = rst_n &&
        (state == EVAL_WAIT || state == FEATURE_WAIT ||
            state == FEATURE_DRAIN || state == EVAL_OUTPUT_DRAIN);
    assign cmd_valid = rst_n && (memory_owner == M_TOKEN ? state == TOKEN_SEND :
        (memory_owner == M_EMBED ? embed_cmd_valid :
        (memory_owner == M_LAYER ? layer_cmd_valid :
        (memory_owner == M_LOGITS ? logits_cmd_valid : 1'b0))));
    assign input_read_event = (rst_n && memory_owner == M_TOKEN &&
        state == TOKEN_SEND && cmd_ready) || embed_input_event;
    assign cmd_write = rst_n && (memory_owner == M_EMBED ? embed_cmd_write :
        (memory_owner == M_LAYER ? layer_cmd_write :
        (memory_owner == M_LOGITS ? logits_cmd_write : 1'b0)));
    assign cmd_addr = !rst_n ? 64'd0 : (memory_owner == M_TOKEN ? token_address_hold :
        (memory_owner == M_EMBED ? embed_cmd_addr :
        (memory_owner == M_LAYER ? layer_cmd_addr :
        (memory_owner == M_LOGITS ? logits_cmd_addr : 64'd0))));
    assign cmd_wdata = !rst_n ? 32'd0 : (memory_owner == M_EMBED ? embed_cmd_wdata :
        (memory_owner == M_LAYER ? layer_cmd_wdata :
        (memory_owner == M_LOGITS ? logits_cmd_wdata : 32'd0)));
    assign result_ready = rst_n && (memory_owner == M_TOKEN ? state == TOKEN_WAIT :
        (memory_owner == M_EMBED ? embed_result_ready :
        (memory_owner == M_LAYER ? layer_result_ready :
        (memory_owner == M_LOGITS ? logits_result_ready : 1'b0))));
    assign req_valid = rst_n && (anchor_selected ? anchor_req_valid :
        (layer_selected && layer_req_valid));
    assign req_op = !rst_n ? 3'd0 : (anchor_selected ? anchor_req_op :
        (layer_selected ? layer_req_op : 3'd0));
    assign req_model = !rst_n ? 2'd0 : (anchor_selected ? anchor_req_model :
        (layer_selected ? layer_req_model : 2'd0));
    assign req_layer = !rst_n ? 8'd0 : (anchor_selected ? anchor_req_layer :
        (layer_selected ? layer_req_layer : 8'd0));
    assign req_token = !rst_n ? 32'd0 : (anchor_selected ? anchor_req_token :
        (layer_selected ? layer_req_token : 32'd0));
    assign req_is_value = rst_n && (anchor_selected ? anchor_req_value :
        (layer_selected && layer_req_value));
    assign req_kv_head = !rst_n ? 2'd0 : (anchor_selected ? anchor_req_head :
        (layer_selected ? layer_req_head : 2'd0));
    assign req_component = !rst_n ? 10'd0 : (anchor_selected ? anchor_req_component :
        (layer_selected ? layer_req_component : 10'd0));
    assign req_base = !rst_n ? 64'd0 : (anchor_selected ? anchor_req_base :
        (layer_selected ? layer_req_base : 64'd0));
    assign rsp_ready = rst_n && (anchor_selected ? anchor_rsp_ready :
        (layer_selected && layer_rsp_ready));
    assign fetch_valid = rst_n && (anchor_selected ? anchor_fetch_valid :
        (layer_selected && layer_fetch_valid));
    assign fetch_model = !rst_n ? 2'd0 : (anchor_selected ? anchor_fetch_model :
        (layer_selected ? layer_fetch_model : 2'd0));
    assign fetch_owner = !rst_n ? 8'd0 : (anchor_selected ? anchor_fetch_owner :
        (layer_selected ? layer_fetch_owner : 8'd0));
    assign fetch_token = !rst_n ? 32'd0 : (anchor_selected ? anchor_fetch_token :
        (layer_selected ? layer_fetch_token : 32'd0));
    assign fetch_is_value = rst_n && (anchor_selected ? anchor_fetch_value :
        (layer_selected && layer_fetch_value));
    assign fetch_kv_head = !rst_n ? 2'd0 : (anchor_selected ? anchor_fetch_head :
        (layer_selected ? layer_fetch_head : 2'd0));
    assign fetch_component = !rst_n ? 10'd0 : (anchor_selected ? anchor_fetch_component :
        (layer_selected ? layer_fetch_component : 10'd0));
    assign fetch_rsp_ready = rst_n && (anchor_selected ? anchor_fetch_rsp_ready :
        (layer_selected && layer_fetch_rsp_ready));

    wire input_beat_ok = !input_bad && !input_complete && input_count < hidden_hold &&
        embed_input_index == input_count &&
        embed_input_last == (input_count == hidden_hold - 1'b1);
    wire ple_beat_ok = !p_bad && !p_complete && p_count < P &&
        embed_ple_index == p_count && embed_ple_last == (p_count == P-1);
    wire receive_layer = state == LAYER_WAIT;
    wire received_valid = receive_layer ? layer_output_valid :
        eval_output_valid && eval_output_ready;
    wire [31:0] received_index = receive_layer ? layer_output_index : eval_output_index;
    wire [15:0] received_data = receive_layer ? layer_output_data : eval_output_data;
    wire received_last = receive_layer ? layer_output_last : eval_output_last;
    wire h_beat_ok = !h_bad && !h_complete && h_count < hidden_hold &&
        received_index == h_count && received_last == (h_count == hidden_hold - 1'b1);
    wire feature_beat_ok = !feature_bad && !feature_complete &&
        feature_count < hidden_hold && eval_output_index == feature_count &&
        eval_output_last == (feature_count == hidden_hold - 1'b1);
    wire logits_store_ok = h_allocated && final_vector_valid &&
        !logits_normalized_bad && logits_store_index == logits_normalized_count &&
        logits_normalized_count < hidden_hold &&
        logits_store_last == (logits_normalized_count == hidden_hold - 1'b1);

    wire hidden_embedding_write = rst_n && state == EMBED_WAIT &&
        operation == 1 && embed_input_valid && input_beat_ok;
    wire hidden_result_write = rst_n && (state == LAYER_WAIT || state == EVAL_WAIT) &&
        received_valid && h_beat_ok;
    wire hidden_logits_write = rst_n && state == LOGITS_WAIT &&
        logits_store_valid && logits_store_ok;
    wire hidden_write = hidden_embedding_write || hidden_result_write || hidden_logits_write;
    wire [31:0] hidden_waddr = hidden_embedding_write ? embed_input_index :
        (hidden_result_write ? received_index : logits_store_index);
    wire [15:0] hidden_wdata = hidden_embedding_write ? embed_input_data :
        (hidden_result_write ? received_data : logits_store_data);
    wire hidden_read = rst_n &&
        ((source_state == S_LOCAL_READ && !source_is_ple_hold) ||
            state == WRITE_LOW_READ || state == WRITE_HIGH_READ);
    wire [31:0] hidden_raddr = source_state == S_LOCAL_READ ? source_index_hold :
        (state == WRITE_LOW_READ ? write_component : write_component + 32'd1);
    assign hidden_ram_write = EXTERNAL_HIDDEN_RAM == 1 && hidden_write;
    assign hidden_ram_read = EXTERNAL_HIDDEN_RAM == 1 && hidden_read;
    assign hidden_ram_waddr = rst_n && EXTERNAL_HIDDEN_RAM == 1 ? hidden_waddr : 32'd0;
    assign hidden_ram_raddr = rst_n && EXTERNAL_HIDDEN_RAM == 1 ? hidden_raddr : 32'd0;
    assign hidden_ram_wdata = rst_n && EXTERNAL_HIDDEN_RAM == 1 ? hidden_wdata : 16'd0;
    generate if (EXTERNAL_HIDDEN_RAM == 1) begin : external_hidden
        assign hidden_q = hidden_ram_rdata;
    end else begin : internal_hidden
        (* ramstyle = "M20K", nomem2reg *)
        reg [15:0] payload [0:MAX_H-1];
        reg [15:0] read_q;
        assign hidden_q = read_q;
        always @(posedge clk) begin
            if (hidden_write)
                payload[hidden_waddr[H_BITS-1:0]] <= hidden_wdata;
            if (hidden_read)
                read_q <= payload[hidden_raddr[H_BITS-1:0]];
        end
    end endgenerate

    wire feature_write = rst_n && state == FEATURE_WAIT &&
        eval_output_valid && eval_output_ready && feature_beat_ok;
    wire retained_ple_write = rst_n && state == EMBED_WAIT &&
        embed_ple_valid && ple_beat_ok && p_allocated && !feature_allocated;
    wire feature_read = rst_n && feature_state == FEATURE_READ;
    wire retained_ple_read = rst_n && source_state == S_LOCAL_READ &&
        source_is_ple_hold;
    wire shared_ple_write = rst_n && SHARED_PLE == 1 && layer_vector_write[3];
    wire shared_ple_read = rst_n && SHARED_PLE == 1 && layer_vector_read[3];
    wire [31:0] feature_write_index = shared_ple_write ?
        {20'd0, layer_vector_waddr[36+:12]} :
        (feature_write ? eval_output_index : embed_ple_index);
    wire [15:0] feature_write_data = shared_ple_write ?
        layer_vector_wdata[48+:16] :
        (feature_write ? eval_output_data : embed_ple_data);
    wire [31:0] ple_read_index = shared_ple_read ?
        {20'd0, layer_vector_raddr[36+:12]} : source_index_hold;
    assign shared_ple_fault = rst_n && SHARED_PLE == 1 &&
        (((shared_ple_write || shared_ple_read) &&
            (!layer_selected || !layer_reserved || !p_allocated ||
                !p_committed || feature_allocated)) ||
         (shared_ple_write && (feature_write || retained_ple_write ||
            layer_vector_waddr[36+:12] >= P)) ||
         (shared_ple_read && (feature_read || retained_ple_read ||
            layer_vector_raddr[36+:12] >= P)));
    always @(posedge clk) begin
        if (rst_n && !shared_ple_fault) begin
            if (feature_write || retained_ple_write || shared_ple_write)
                feature_payload[feature_write_index[H_BITS-1:0]] <= feature_write_data;
            if (feature_read)
                feature_q <= feature_payload[feature_request_index[H_BITS-1:0]];
            else if (retained_ple_read || shared_ple_read)
                ple_q <= feature_payload[ple_read_index[H_BITS-1:0]];
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            feature_state <= FEATURE_IDLE;
            feature_request_model <= 0;
            feature_request_kind <= 0;
            feature_request_token <= 0;
            feature_request_index <= 0;
            feature_data_hold <= 0;
            feature_error_hold <= 0;
        end else if (state == EMBED_COMMIT) begin
            feature_state <= FEATURE_IDLE;
            feature_data_hold <= 0;
            feature_error_hold <= 0;
        end else begin
            case (feature_state)
                FEATURE_IDLE: if (state == EMBED_WAIT && embed_modality_valid) begin
                    feature_request_model <= embed_modality_model;
                    feature_request_kind <= embed_modality_kind;
                    feature_request_token <= embed_modality_token;
                    feature_request_index <= embed_modality_index;
                    feature_data_hold <= 0;
                    feature_error_hold <= 0;
                    feature_state <= FEATURE_VALIDATE;
                end
                FEATURE_VALIDATE: begin
                    if (!feature_committed || feature_generation != generation_hold ||
                        feature_request_model != model_hold ||
                        feature_request_kind != feature_kind ||
                        feature_request_token != feature_token ||
                        feature_request_index >= hidden_hold) begin
                        feature_error_hold <= 1;
                        feature_state <= FEATURE_RESPONSE;
                    end else
                        feature_state <= FEATURE_READ;
                end
                FEATURE_READ: feature_state <= FEATURE_CAPTURE;
                FEATURE_CAPTURE: begin
                    feature_data_hold <= feature_q;
                    feature_state <= FEATURE_RESPONSE;
                end
                FEATURE_RESPONSE: if (embed_modality_rsp_ready)
                    feature_state <= FEATURE_IDLE;
                default: begin
                    feature_error_hold <= 1;
                    feature_data_hold <= 0;
                    feature_state <= FEATURE_RESPONSE;
                end
            endcase
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            read_state <= READ_IDLE;
            read_owner <= 0;
            read_generation_hold <= 0;
            read_token_hold <= 0;
            read_layer_hold <= 0;
            read_component_hold <= 0;
            read_data_hold <= 0;
            read_error_hold <= 0;
        end else begin
            case (read_state)
                READ_IDLE: begin
                    if (owner_read_valid && owner_read_ready) begin
                        read_owner <= 1;
                        read_generation_hold <= owner_read_generation;
                        read_token_hold <= owner_read_token;
                        read_layer_hold <= owner_read_layer;
                        read_component_hold <= owner_read_component;
                        read_data_hold <= 0;
                        read_error_hold <= 0;
                        read_state <= READ_SEND;
                    end else if (layer_frontier_valid && layer_frontier_ready) begin
                        read_owner <= 0;
                        read_generation_hold <= generation_hold;
                        read_token_hold <= token_hold;
                        read_layer_hold <= layer_hold;
                        read_component_hold <= {source_index_hold[11:1], 1'b0};
                        read_data_hold <= 0;
                        read_error_hold <= 0;
                        read_state <= READ_SEND;
                    end
                end
                READ_SEND: if (f_read_ready)
                    read_state <= READ_WAIT;
                READ_WAIT: if (f_read_valid) begin
                    read_data_hold <= f_read_data;
                    read_error_hold <= f_read_error;
                    read_state <= READ_RESPONSE;
                end
                READ_RESPONSE: if (read_owner ? owner_read_rsp_ready : layer_frontier_rsp_ready)
                    read_state <= READ_IDLE;
                default: begin
                    read_data_hold <= 0;
                    read_error_hold <= 7;
                    read_state <= READ_RESPONSE;
                end
            endcase
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            source_state <= S_IDLE;
            source_is_ple_hold <= 0;
            source_is_logits <= 0;
            source_is_normalized_hold <= 0;
            source_index_hold <= 0;
            source_data_hold <= 0;
            source_error_hold <= 0;
        end else begin
            case (source_state)
                S_IDLE: begin
                    if (state == LAYER_WAIT && layer_source_valid) begin
                        source_is_logits <= 0;
                        source_is_normalized_hold <= 0;
                        source_is_ple_hold <= layer_source_ple;
                        source_index_hold <= layer_source_index;
                        source_data_hold <= 0;
                        source_error_hold <= layer_source_model != model_hold ||
                            layer_source_layer != layer_hold || layer_source_token != token_hold;
                        source_state <= S_VALIDATE;
                    end else if (state == LOGITS_WAIT && logits_source_valid) begin
                        source_is_logits <= 1;
                        source_is_normalized_hold <= logits_source_normalized;
                        source_is_ple_hold <= 0;
                        source_index_hold <= logits_source_index;
                        source_data_hold <= 0;
                        source_error_hold <= !final_vector_valid;
                        source_state <= S_VALIDATE;
                    end
                end
                S_VALIDATE: begin
                    if (source_error_hold ||
                        (source_is_logits && (logits_normalized_bad ||
                            (source_is_normalized_hold ?
                                logits_normalized_count != hidden_hold :
                                source_index_hold < logits_normalized_count))) ||
                        (source_is_ple_hold ?
                        (!p_committed || source_index_hold >= P) :
                        (source_index_hold >= hidden_hold ||
                        (!source_frontier && !source_is_logits && !retained_source_valid)))) begin
                        source_error_hold <= 1;
                        source_state <= S_RESPONSE;
                    end else if (source_is_ple_hold || source_is_logits || !source_frontier)
                        source_state <= S_LOCAL_READ;
                    else
                        source_state <= S_FRONTIER_SEND;
                end
                S_LOCAL_READ: source_state <= S_LOCAL_CAPTURE;
                S_LOCAL_CAPTURE: begin
                    source_data_hold <= source_is_ple_hold ? ple_q : hidden_q;
                    source_state <= S_RESPONSE;
                end
                S_FRONTIER_SEND: if (layer_frontier_ready)
                    source_state <= S_FRONTIER_WAIT;
                S_FRONTIER_WAIT: if (layer_frontier_rsp_valid) begin
                    source_data_hold <= source_index_hold[0] ?
                        read_data_hold[31:16] : read_data_hold[15:0];
                    source_error_hold <= read_error_hold != 0;
                    source_state <= S_RESPONSE;
                end
                S_RESPONSE: if (source_is_logits ? logits_source_rsp_ready : layer_source_rsp_ready)
                    source_state <= S_IDLE;
                default: begin
                    source_data_hold <= 0;
                    source_error_hold <= 1;
                    source_state <= S_RESPONSE;
                end
            endcase
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            frontier_return <= 0;
            ring_return <= 0;
            allocation_component <= 0;
            allocation_return <= 0;
            frontier_reserved <= 0;
            ring_reserved <= 0;
            vector_reserved <= 0;
            feature_reserved <= 0;
            anchor_reserved <= 0;
            embedding_reserved <= 0;
            layer_reserved <= 0;
            admission_fault <= 0;
            frontier_reservation_hold <= 0;
            frontier_shadow_hold <= 0;
            ring_reservation_hold <= 0;
            ring_shadow_hold <= 0;
            operation <= 0;
            model_hold <= 0;
            precision_hold <= 0;
            modality_hold <= 0;
            frontier_operation <= 0;
            generation_hold <= 0;
            tokens_hold <= 0;
            token_hold <= 0;
            hidden_hold <= 0;
            tokens_base_hold <= 0;
            weights_base_hold <= 0;
            token_address_hold <= 0;
            token_id_hold <= 0;
            token_error_hold <= 0;
            token_modality <= 0;
            layer_hold <= 0;
            active <= 0;
            is_control <= 0;
            invalidate_hold <= 0;
            source_frontier <= 0;
            ordinary_configured <= 0;
            fallback_configured <= 0;
            frontier_frozen <= 0;
            ring_invalidate <= 0;
            h_allocated <= 0;
            h_committed <= 0;
            p_allocated <= 0;
            p_committed <= 0;
            feature_allocated <= 0;
            feature_committed <= 0;
            feature_bad <= 0;
            feature_complete <= 0;
            feature_count <= 0;
            feature_generation <= 0;
            feature_token <= 0;
            feature_kind <= 0;
            vector_layer <= 0;
            vector_token <= 0;
            vector_generation <= 0;
            h_count <= 0;
            p_count <= 0;
            input_count <= 0;
            write_component <= 0;
            h_bad <= 0;
            h_complete <= 0;
            p_bad <= 0;
            p_complete <= 0;
            input_bad <= 0;
            input_complete <= 0;
            error_hold <= 0;
            child_error <= 0;
            write_pair <= 0;
            logits_normalized_count <= 0;
            logits_normalized_bad <= 0;
        end else begin
            if (reservation_overrun)
                admission_fault <= 1;
            case (state)
                IDLE: begin
                    if (control_valid && control_ready) begin
                        admission_fault <= 0;
                        h_allocated <= 0;
                        h_committed <= 0;
                        p_allocated <= 0;
                        p_committed <= 0;
                        feature_allocated <= 0;
                        feature_committed <= 0;
                        is_control <= 1;
                        invalidate_hold <= control_invalidate;
                        model_hold <= control_model;
                        precision_hold <= control_precision;
                        modality_hold <= control_modality;
                        generation_hold <= control_generation;
                        tokens_hold <= control_tokens;
                        tokens_base_hold <= control_tokens_base;
                        weights_base_hold <= control_weights_base;
                        error_hold <= 0;
                        state <= CONTROL_VALIDATE;
                    end else if (task_valid && task_ready) begin
                        admission_fault <= 0;
                        is_control <= 0;
                        operation <= task_op;
                        token_hold <= task_token;
                        layer_hold <= task_layer;
                        source_frontier <= task_source_frontier;
                        error_hold <= !session_matches ? 4'd7 : 4'd0;
                        if ((task_model != 1 && task_model != 2) || task_precision > 1)
                            error_hold <= 6;
                        state <= VALIDATE;
                    end
                end
                CONTROL_VALIDATE: begin
                    if (!invalidate_hold && (!native_model || precision_hold > 1)) begin
                        active <= 0;
                        error_hold <= 6;
                        state <= PUBLISH;
                    end else if (!invalidate_hold && (tokens_hold == 0 ||
                        tokens_hold > 131072 || tokens_base_hold[1:0] ||
                        weights_base_hold[1:0])) begin
                        active <= 0;
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else begin
                        active <= 0;
                        h_allocated <= 0;
                        h_committed <= 0;
                        p_allocated <= 0;
                        p_committed <= 0;
                        feature_allocated <= 0;
                        feature_committed <= 0;
                        ordinary_configured <= 0;
                        fallback_configured <= 0;
                        frontier_frozen <= 0;
                        hidden_hold <= COMPACT ? 32'd8 : {20'd0, selected_hidden};
                        frontier_operation <= 1;
                        frontier_return <= FRONTIER_RELEASED;
                        state <= FRONTIER_CONTROL;
                    end
                end
                VALIDATE: begin
                    if (error_hold != 0)
                        state <= PUBLISH;
                    else if (!active) begin
                        error_hold <= 7;
                        state <= PUBLISH;
                    end else if (token_hold >= tokens_hold || token_hold > 131071 ||
                        (operation == 0 && (layer_hold != 0 || token_hold != 0)) ||
                        (operation == 1 && layer_hold != 0) ||
                        (operation == 2 && layer_hold != selected_owners - 8'd2) ||
                        (operation == 3 && layer_hold >= selected_owners - 8'd1) ||
                        (operation == 4 && (layer_hold != selected_owners - 8'd1 ||
                            token_hold != tokens_hold - 1'b1)) ||
                        (operation == 5 && (layer_hold < selected_owners - 8'd1 ||
                            layer_hold >= selected_layers || token_hold != tokens_hold - 1'b1)) ||
                        (operation == 6 && token_hold != tokens_hold - 1'b1) ||
                        (operation == 7 && (layer_hold != selected_layers ||
                            token_hold != tokens_hold - 1'b1))) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else if (source_frontier != expected_frontier ||
                        (operation == 0 && (ordinary_configured || fallback_configured)) ||
                        (operation != 0 && operation != 7 && operation != 6 &&
                            !ordinary_configured) ||
                        (operation == 5 && !frontier_frozen) ||
                        (operation == 5 && !source_frontier && !retained_source_valid) ||
                        (operation == 6 && !final_vector_valid)) begin
                        error_hold <= 7;
                        state <= PUBLISH;
                    end else begin
                        case (operation)
                            0: begin
                                frontier_operation <= 0;
                                frontier_return <= CONFIG_FRONTIER_DONE;
                                allocation_component <= 0;
                                allocation_return <= FRONTIER_CONTROL;
                                state <= ALLOCATION_SEND;
                            end
                            1, 3, 5: begin
                                input_count <= 0;
                                input_bad <= 0;
                                input_complete <= 0;
                                p_count <= 0;
                                p_bad <= 0;
                                p_complete <= 0;
                                p_allocated <= 0;
                                p_committed <= 0;
                                feature_allocated <= 0;
                                feature_committed <= 0;
                                if (operation == 1) begin
                                    h_allocated <= 0;
                                    h_committed <= 0;
                                end
                                state <= TOKEN_ADDRESS;
                            end
                            2: begin
                                allocation_component <= 4;
                                allocation_return <= ANCHOR_START;
                                state <= ALLOCATION_SEND;
                            end
                            4: begin
                                frontier_operation <= 2;
                                frontier_return <= PUBLISH;
                                state <= FRONTIER_CONTROL;
                            end
                            6: begin
                                logits_normalized_count <= 0;
                                logits_normalized_bad <= 0;
                                state <= LOGITS_START;
                            end
                            7: begin
                                ordinary_configured <= 0;
                                fallback_configured <= 0;
                                frontier_frozen <= 0;
                                h_allocated <= 0;
                                h_committed <= 0;
                                p_allocated <= 0;
                                p_committed <= 0;
                                feature_allocated <= 0;
                                feature_committed <= 0;
                                frontier_operation <= 1;
                                frontier_return <= FRONTIER_RELEASED;
                                state <= FRONTIER_CONTROL;
                            end
                        endcase
                    end
                end
                FRONTIER_CONTROL: if (control_ingress && frontier_control_ready)
                    state <= FRONTIER_CONTROL_WAIT;
                FRONTIER_CONTROL_WAIT: if (frontier_control_valid) begin
                    if (frontier_control_error == 0 && frontier_operation == 1)
                        frontier_reserved <= 0;
                    if (frontier_control_error != 0 ||
                        (frontier_operation == 0 && frontier_capacity_fallback)) begin
                        error_hold <= frontier_control_error != 0 ? frontier_control_error : 4'd7;
                        state <= PUBLISH;
                    end else
                        state <= frontier_return;
                    if (frontier_control_error == 0 && frontier_operation == 2)
                        frontier_frozen <= 1;
                end
                FRONTIER_RELEASED: begin
                    ring_invalidate <= 1;
                    ring_return <= BOTH_RELEASED;
                    state <= RING_CONTROL;
                end
                RING_CONTROL: if (ring_control_ready)
                    state <= RING_CONTROL_WAIT;
                RING_CONTROL_WAIT: if (ring_control_valid) begin
                    if (ring_control_error == 0 && ring_invalidate)
                        ring_reserved <= 0;
                    if (ring_control_error != 0) begin
                        error_hold <= ring_control_error;
                        state <= PUBLISH;
                    end else begin
                        if (!ring_invalidate)
                            ordinary_configured <= 1;
                        state <= ring_return;
                    end
                end
                BOTH_RELEASED: begin
                    if (is_control) begin
                        active <= !invalidate_hold;
                        state <= PUBLISH;
                    end else begin
                        frontier_operation <= 3;
                        frontier_return <= EVAL_START;
                        state <= FRONTIER_CONTROL;
                    end
                end
                CONFIG_FRONTIER_DONE: begin
                    ring_invalidate <= 0;
                    ring_return <= PUBLISH;
                    allocation_component <= 1;
                    allocation_return <= RING_CONTROL;
                    state <= ALLOCATION_SEND;
                end
                ALLOCATION_SEND: if (grant_valid && grant_ready)
                    state <= ALLOCATION_WAIT;
                ALLOCATION_WAIT: if (grant_rsp_valid && grant_rsp_ready) begin
                    if (!grant_allowed) begin
                        error_hold <= 7;
                        if (allocation_component == 3 && allocation_return == FEATURE_WAIT)
                            state <= FEATURE_DRAIN;
                        else if (allocation_component == 2 && allocation_return == EVAL_WAIT)
                            state <= EVAL_OUTPUT_DRAIN;
                        else
                            state <= PUBLISH;
                    end else begin
                        case (allocation_component)
                            0: begin
                                frontier_reserved <= 1;
                                frontier_reservation_hold <= candidate_bytes;
                                frontier_shadow_hold <= candidate_shadow;
                            end
                            1: begin
                                ring_reserved <= 1;
                                ring_reservation_hold <= candidate_bytes;
                                ring_shadow_hold <= candidate_shadow;
                            end
                            2: vector_reserved <= 1;
                            3: feature_reserved <= 1;
                            4: anchor_reserved <= 1;
                            19: embedding_reserved <= 1;
                            20: layer_reserved <= 1;
                            default: error_hold <= 7;
                        endcase
                        if (allocation_component == 0 || allocation_component == 1 ||
                            allocation_component == 2 || allocation_component == 3 ||
                            allocation_component == 4 || allocation_component == 19 ||
                            allocation_component == 20)
                            state <= allocation_return;
                        else
                            state <= PUBLISH;
                    end
                end
                EMBED_PRIVATE_GRANT: begin
                    allocation_component <= 19;
                    allocation_return <= EMBED_START;
                    state <= ALLOCATION_SEND;
                end
                TOKEN_ADDRESS: begin
                    if (token_address_sum[64] || token_address_end[64]) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else begin
                        token_address_hold <= token_address_sum[63:0];
                        state <= TOKEN_SEND;
                    end
                end
                TOKEN_SEND: if (cmd_ready)
                    state <= TOKEN_WAIT;
                TOKEN_WAIT: if (result_valid && result_ready) begin
                    token_id_hold <= result_data;
                    token_error_hold <= result_error;
                    state <= TOKEN_CLASSIFY;
                end
                TOKEN_CLASSIFY: begin
                    if (token_error_hold) begin
                        error_hold <= 2;
                        state <= PUBLISH;
                    end else if (token_id_hold >= (COMPACT ? 32'd32 : 32'd262144)) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else if ((token_image && !image_allowed) ||
                        (token_audio && !audio_allowed)) begin
                        error_hold <= 7;
                        state <= PUBLISH;
                    end else begin
                        token_modality <= token_image ? 2'd1 : (token_audio ? 2'd2 : 2'd0);
                        if (token_image || token_audio) begin
                            feature_count <= 0;
                            feature_bad <= 0;
                            feature_complete <= 0;
                            state <= FEATURE_START;
                        end else begin
                            allocation_component <= 2;
                            allocation_return <= EMBED_PRIVATE_GRANT;
                            state <= ALLOCATION_SEND;
                        end
                    end
                end
                FEATURE_START: if (eval_start_ready) begin
                    feature_committed <= 0;
                    feature_generation <= generation_hold;
                    feature_token <= token_hold;
                    feature_kind <= token_modality;
                    state <= FEATURE_WAIT;
                end
                FEATURE_WAIT: begin
                    if (eval_output_valid && !feature_reserved) begin
                        allocation_component <= 3;
                        allocation_return <= FEATURE_WAIT;
                        state <= ALLOCATION_SEND;
                    end else if (eval_output_valid && eval_output_ready) begin
                        feature_allocated <= 1;
                        if (!feature_beat_ok)
                            feature_bad <= 1;
                        else begin
                            feature_count <= feature_count + 1'b1;
                            if (eval_output_last)
                                feature_complete <= 1;
                        end
                    end
                    if (eval_done_valid && eval_done_ready) begin
                        child_error <= eval_done_error;
                        state <= FEATURE_COMMIT;
                    end
                end
                FEATURE_COMMIT: begin
                    if (child_error != 0 || feature_bad || !feature_complete ||
                        feature_count != hidden_hold) begin
                        error_hold <= child_error != 0 ? child_error : 4'd7;
                        feature_allocated <= 0;
                        feature_reserved <= 0;
                        feature_committed <= 0;
                        state <= PUBLISH;
                    end else begin
                        feature_committed <= 1;
                        allocation_component <= 2;
                        allocation_return <= EMBED_PRIVATE_GRANT;
                        state <= ALLOCATION_SEND;
                    end
                end
                FEATURE_DRAIN: if (eval_done_valid && eval_done_ready)
                    state <= PUBLISH;
                EVAL_OUTPUT_DRAIN: if (eval_done_valid && eval_done_ready)
                    state <= PUBLISH;
                EMBED_START: if (embed_ready) begin
                    p_allocated <= token_modality == 0;
                    if (operation == 1)
                        h_allocated <= 1;
                    state <= EMBED_WAIT;
                end
                EMBED_WAIT: begin
                    if (feature_state == FEATURE_RESPONSE && embed_modality_rsp_ready &&
                        !feature_error_hold && feature_request_index == hidden_hold - 1'b1) begin
                        feature_allocated <= 0;
                        feature_reserved <= 0;
                        feature_committed <= 0;
                        p_allocated <= 1;
                    end
                    if (embed_input_valid) begin
                        if (!input_beat_ok)
                            input_bad <= 1;
                        else begin
                            input_count <= input_count + 1'b1;
                            if (embed_input_last)
                                input_complete <= 1;
                        end
                    end
                    if (embed_ple_valid) begin
                        if (!ple_beat_ok || !p_allocated || feature_allocated)
                            p_bad <= 1;
                        else begin
                            p_count <= p_count + 1'b1;
                            if (embed_ple_last)
                                p_complete <= 1;
                        end
                    end
                    if (embed_done) begin
                        embedding_reserved <= 0;
                        child_error <= embed_error;
                        state <= EMBED_COMMIT;
                    end
                end
                EMBED_COMMIT: begin
                    feature_allocated <= 0;
                    feature_reserved <= 0;
                    feature_committed <= 0;
                    if (child_error != 0 || input_bad || !input_complete ||
                        input_count != hidden_hold || p_bad || !p_complete || p_count != P) begin
                        error_hold <= child_error != 0 ? child_error : 4'd7;
                        p_committed <= 0;
                        if (operation == 1)
                            h_committed <= 0;
                        state <= PUBLISH;
                    end else begin
                        p_committed <= 1;
                        if (operation == 1) begin
                            p_allocated <= 0;
                            p_committed <= 0;
                            h_committed <= 1;
                            vector_generation <= generation_hold;
                            vector_token <= token_hold;
                            vector_layer <= 0;
                            write_component <= 0;
                            state <= WRITE_START;
                        end else begin
                            h_count <= 0;
                            h_bad <= 0;
                            h_complete <= 0;
                            allocation_component <= 20;
                            allocation_return <= LAYER_START;
                            state <= ALLOCATION_SEND;
                        end
                    end
                end
                LAYER_START: if (layer_ready) begin
                    h_allocated <= 1;
                    state <= LAYER_WAIT;
                end
                LAYER_WAIT, EVAL_WAIT: begin
                    if (state == EVAL_WAIT && eval_output_valid && !vector_reserved) begin
                        allocation_component <= 2;
                        allocation_return <= EVAL_WAIT;
                        state <= ALLOCATION_SEND;
                    end else if (received_valid) begin
                        if (state == EVAL_WAIT)
                            h_allocated <= 1;
                        h_committed <= 0;
                        if (!h_beat_ok)
                            h_bad <= 1;
                        else begin
                            h_count <= h_count + 1'b1;
                            if (received_last)
                                h_complete <= 1;
                        end
                    end
                    if (state == LAYER_WAIT ? layer_done : eval_done_valid) begin
                        if (state == LAYER_WAIT)
                            layer_reserved <= 0;
                        child_error <= state == LAYER_WAIT ? layer_error : eval_done_error;
                        state <= VECTOR_COMMIT;
                    end
                end
                VECTOR_COMMIT: begin
                    p_allocated <= 0;
                    p_committed <= 0;
                    if (child_error != 0 || h_bad || !h_complete || h_count != hidden_hold) begin
                        h_committed <= 0;
                        error_hold <= child_error != 0 ? child_error : 4'd7;
                        state <= PUBLISH;
                    end else begin
                        h_committed <= 1;
                        vector_generation <= generation_hold;
                        vector_token <= token_hold;
                        vector_layer <= operation == 7 ? layer_hold : layer_hold + 8'd1;
                        if (operation == 3) begin
                            write_component <= 0;
                            state <= WRITE_START;
                        end else
                            state <= PUBLISH;
                    end
                end
                WRITE_START: if (read_state == READ_IDLE && f_write_start_ready)
                    state <= WRITE_LOW_READ;
                WRITE_LOW_READ: state <= WRITE_LOW_CAPTURE;
                WRITE_LOW_CAPTURE: begin
                    write_pair[15:0] <= hidden_q;
                    state <= WRITE_HIGH_READ;
                end
                WRITE_HIGH_READ: state <= WRITE_HIGH_CAPTURE;
                WRITE_HIGH_CAPTURE: begin
                    write_pair[31:16] <= hidden_q;
                    state <= WRITE_SEND;
                end
                WRITE_SEND: begin
                    if (f_write_done_valid) begin
                        error_hold <= f_write_done_error;
                        state <= PUBLISH;
                    end else if (f_write_ready) begin
                        if (write_component == hidden_hold - 32'd2)
                            state <= WRITE_WAIT;
                        else begin
                            write_component <= write_component + 32'd2;
                            state <= WRITE_LOW_READ;
                        end
                    end
                end
                WRITE_WAIT: if (f_write_done_valid) begin
                    error_hold <= f_write_done_error;
                    h_allocated <= 0;
                    h_committed <= 0;
                    p_allocated <= 0;
                    p_committed <= 0;
                    state <= PUBLISH;
                end
                ANCHOR_START: if (anchor_ready)
                    state <= ANCHOR_WAIT;
                ANCHOR_WAIT: if (anchor_done) begin
                    anchor_reserved <= 0;
                    error_hold <= anchor_error;
                    state <= PUBLISH;
                end
                EVAL_START: if (eval_start_ready) begin
                    fallback_configured <= 1;
                    h_allocated <= 0;
                    h_committed <= 0;
                    h_count <= 0;
                    h_bad <= 0;
                    h_complete <= 0;
                    state <= EVAL_WAIT;
                end
                LOGITS_START: if (logits_ready)
                    state <= LOGITS_WAIT;
                LOGITS_WAIT: begin
                    if (logits_store_valid) begin
                        if (!logits_store_ok)
                            logits_normalized_bad <= 1;
                        else
                            logits_normalized_count <= logits_normalized_count + 32'd1;
                    end
                    if (logits_done) begin
                        error_hold <= logits_error != 0 ? logits_error :
                            (logits_normalized_bad || logits_normalized_count != hidden_hold ?
                                4'd7 : 4'd0);
                        h_allocated <= 0;
                        h_committed <= 0;
                        state <= PUBLISH;
                    end
                end
                PUBLISH: begin
                    if (admission_fault || reservation_overrun)
                        error_hold <= 7;
                    if (error_hold != 0 || admission_fault || reservation_overrun) begin
                        h_allocated <= 0;
                        h_committed <= 0;
                        p_allocated <= 0;
                        p_committed <= 0;
                        feature_allocated <= 0;
                        feature_committed <= 0;
                    end
                    state <= RESPONSE;
                end
                RESPONSE: if (is_control ? control_rsp_ready : task_done_ready) begin
                    vector_reserved <= 0;
                    feature_reserved <= 0;
                    anchor_reserved <= 0;
                    embedding_reserved <= 0;
                    layer_reserved <= 0;
                    state <= IDLE;
                end
                default: begin
                    active <= 0;
                    h_committed <= 0;
                    p_committed <= 0;
                    error_hold <= 7;
                    state <= PUBLISH;
                end
            endcase
            if (!SHARED_PLE && state == LAYER_WAIT && source_state == S_RESPONSE &&
                layer_source_rsp_ready && source_is_ple_hold &&
                !source_error_hold && source_index_hold == P-1) begin
                p_allocated <= 0;
                p_committed <= 0;
            end
        end
    end
endmodule
