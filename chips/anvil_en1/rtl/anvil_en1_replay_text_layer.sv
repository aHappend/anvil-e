module anvil_en1_replay_text_layer #(
    parameter integer COMPACT = 0
) (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] model, precision, modality, mode,
    input wire [7:0] frame_layer,
    input wire [31:0] token, tokens,
    input wire [63:0] tokens_base, weights_base,
    input wire [5:0] frame_slot,
    input wire [159:0] continuation,
    input wire dependency_valid,
    input wire [1:0] dependency_domain,
    input wire [7:0] dependency_layer,
    input wire [31:0] dependency_token,
    input wire [11:0] dependency_length,
    input wire [5:0] dependency_slot,
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
    output wire work_req_valid,
    input wire work_req_ready,
    output wire [2:0] work_req_op,
    output wire [1:0] work_req_domain, work_req_target,
    output wire [31:0] work_req_token,
    output wire [7:0] work_req_layer,
    output wire [11:0] work_req_length, work_req_component,
    output wire [5:0] work_req_slot,
    output wire work_req_bank,
    output wire [7:0] work_req_scalar_index,
    output wire [31:0] work_req_data,
    input wire work_rsp_valid,
    output wire work_rsp_ready,
    input wire [31:0] work_rsp_data,
    input wire [3:0] work_rsp_error,
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
    output wire done_valid,
    input wire done_ready,
    output wire [3:0] done_error,
    output wire done_yield, done_bank,
    output wire [159:0] done_continuation,
    output wire [1:0] done_dependency_domain,
    output wire [7:0] done_dependency_layer,
    output wire [31:0] done_dependency_token,
    output wire [11:0] done_dependency_length,
    output wire owner_reprojection_event,
    output wire [31:0] owner_reprojection_bytes,
    output wire query_projection_event,
    output wire [31:0] query_projection_bytes,
    output wire source_read_event,
    output wire [31:0] source_read_bytes,
    output wire [63:0] controller_state_bytes,
    output wire [63:0] binding_controller_bytes, projection_controller_bytes,
    output wire [63:0] executor_controller_bytes, checkpoint_controller_bytes,
    output wire [63:0] tile_controller_bytes, tile_live_bytes, tile_physical_bytes,
    output wire [63:0] ple_live_bytes, ple_physical_bytes,
    output wire [63:0] embedding_live_bytes, embedding_physical_bytes,
    output wire [63:0] post_vector_live_bytes, post_vector_physical_bytes,
    output wire [3:0] attention_activity,
    output wire avoided_projection_event,
    output wire [31:0] avoided_projection_bytes,
    output wire busy
);
    localparam integer P = COMPACT ? 4 : 256;
    localparam integer P_BITS = $clog2(P);
    localparam integer MAX_H = COMPACT ? 8 : 2560;
    localparam integer MAX_D = COMPACT ? 8 : 512;
    localparam integer Q = COMPACT ? 2 : 8;
    localparam [4:0] IDLE = 0, VALIDATE = 1, BIND_START = 2,
        BIND_WAIT = 3, ATTENTION_START = 4, ATTENTION_WAIT = 5,
        TOKEN_ADDRESS = 6, TOKEN_SEND = 7, TOKEN_WAIT = 8,
        TOKEN_REGISTER = 9, EMBED_START = 10, EMBED_WAIT = 11,
        EMBED_REGISTER = 12, POST_START = 13, POST_WAIT = 14,
        PAIR_SEND = 15, PAIR_WAIT = 16, PAIR_REGISTER = 17,
        PUBLISH = 18, RESPONSE = 19, MODALITY_BIND = 20;
    localparam [2:0] SOURCE_IDLE = 0, SOURCE_VALIDATE = 1,
        SOURCE_LOCAL = 2, SOURCE_LOCAL_CAPTURE = 3, SOURCE_SEND = 4,
        SOURCE_WAIT = 5, SOURCE_REGISTER = 6, SOURCE_RESPONSE = 7;
    localparam [31:0] INPUT_MAGIC = 32'h454e3149;
    localparam [31:0] ATTENTION_MAGIC = 32'h454e3150;
    localparam [31:0] PLE_MAGIC = 32'h454e314c;
    reg [4:0] state;
    reg [2:0] source_state;
    reg [1:0] model_hold, precision_hold, modality_hold, mode_hold;
    reg [1:0] dependency_domain_hold, selected_modality, yielded_domain;
    reg [7:0] frame_layer_hold, dependency_layer_hold, yielded_layer;
    reg [31:0] token_hold, tokens_hold, dependency_token_hold, yielded_token;
    reg [63:0] tokens_base_hold, weights_base_hold, token_address_hold;
    reg [5:0] slot_hold, dependency_slot_hold;
    reg [11:0] length_hold, dependency_length_hold;
    reg dependency_valid_hold, attention_resume, yield_hold, ple_committed;
    reg [159:0] continuation_hold, yielded_continuation;
    reg [31:0] token_id_hold, input_count, ple_count, output_count, pair_hold;
    reg token_error_hold;
    reg [15:0] low_hold, ple_q;
    reg [3:0] error_hold, pair_error_hold, source_failure_hold;
    reg source_ple_hold, source_branch_hold, source_feature_hold, source_error_hold;
    reg [31:0] source_index_hold, source_pair_hold;
    reg [15:0] source_data_hold;
    reg [3:0] source_work_error;
    reg source_tag_error;
    (* ramstyle = "M20K", nomem2reg *)
    reg [15:0] ple_payload [0:P-1];

    initial begin
        if (COMPACT != 0 && COMPACT != 1)
            $fatal(1, "PARAMETER ERROR: COMPACT must be 0 or 1");
    end

    wire native_model = model_hold == 1 || model_hold == 2;
    wire [7:0] layer_count = model_hold == 1 ? 8'd35 : 8'd42;
    wire [7:0] logical_layer = frame_layer_hold - 8'd1;
    wire [11:0] selected_length = COMPACT ? 12'd8 :
        (model_hold == 1 ? 12'd1536 : 12'd2560);
    wire descriptor_valid = frame_layer_hold != 0 && frame_layer_hold <= layer_count &&
        tokens_hold != 0 && tokens_hold <= 131072 && token_hold < tokens_hold &&
        tokens_base_hold[1:0] == 0 && weights_base_hold[1:0] == 0;
    wire input_continuation = continuation_hold[159:128] == INPUT_MAGIC &&
        continuation_hold[127:0] == 0;
    wire projection_continuation = continuation_hold[159:128] == ATTENTION_MAGIC;
    wire ple_continuation = continuation_hold == {PLE_MAGIC, 128'd0};
    wire feature_tag_good = dependency_valid_hold && dependency_domain_hold == 3 &&
        (dependency_layer_hold == 1 || dependency_layer_hold == 2) &&
        dependency_token_hold == token_hold &&
        dependency_length_hold == selected_length && dependency_slot_hold < 16;
    wire [64:0] token_address_sum = {1'b0, tokens_base_hold} +
        {31'd0, token_hold, 2'd0};
    wire [64:0] token_address_end = token_address_sum + 65'd3;
    wire image_token = token_id_hold == (COMPACT ? 32'd28 : 32'd258880);
    wire audio_token = token_id_hold == (COMPACT ? 32'd29 : 32'd258881);
    wire image_allowed = modality_hold == 1 || modality_hold == 3;
    wire audio_allowed = modality_hold == 2 || modality_hold == 3;
    wire native_feature = selected_modality == 1 || selected_modality == 2;
    wire binding_selected = rst_n && (state == BIND_START || state == BIND_WAIT);
    wire attention_selected = rst_n &&
        (state == ATTENTION_START || state == ATTENTION_WAIT);
    wire embedding_selected = rst_n && (state == EMBED_START || state == EMBED_WAIT);
    wire post_selected = rst_n && (state == POST_START || state == POST_WAIT ||
        state == PAIR_SEND || state == PAIR_WAIT || state == PAIR_REGISTER);
    wire pair_selected = rst_n &&
        (state == PAIR_SEND || state == PAIR_WAIT || state == PAIR_REGISTER);

    wire binding_ready, binding_valid, binding_dependency;
    wire [3:0] binding_error;
    wire binding_work_valid, binding_work_rsp_ready;
    wire [2:0] binding_work_op;
    wire [1:0] binding_work_domain, binding_work_target;
    wire [31:0] binding_work_token, binding_work_data;
    wire [7:0] binding_work_layer, binding_work_scalar_index;
    wire [11:0] binding_work_length, binding_work_component;
    wire [5:0] binding_work_slot;
    wire binding_work_bank;
    anvil_en1_replay_frame_input #(.COMPACT(COMPACT)) predecessor (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == BIND_START), .start_ready(binding_ready),
        .model(model_hold), .token(token_hold), .tokens(tokens_hold),
        .frame_layer(frame_layer_hold), .frame_slot(slot_hold), .input_bank(1'b0),
        .dependency_valid(dependency_valid_hold),
        .dependency_domain(dependency_domain_hold),
        .dependency_layer(dependency_layer_hold), .dependency_token(dependency_token_hold),
        .dependency_length(dependency_length_hold), .dependency_slot(dependency_slot_hold),
        .work_req_valid(binding_work_valid),
        .work_req_ready(binding_selected && work_req_ready),
        .work_req_op(binding_work_op), .work_req_domain(binding_work_domain),
        .work_req_target(binding_work_target), .work_req_token(binding_work_token),
        .work_req_layer(binding_work_layer), .work_req_length(binding_work_length),
        .work_req_component(binding_work_component), .work_req_slot(binding_work_slot),
        .work_req_bank(binding_work_bank), .work_req_scalar_index(binding_work_scalar_index),
        .work_req_data(binding_work_data),
        .work_rsp_valid(binding_selected && work_rsp_valid),
        .work_rsp_ready(binding_work_rsp_ready), .work_rsp_error(work_rsp_error),
        .done_valid(binding_valid), .done_ready(rst_n && state == BIND_WAIT),
        .done_error(binding_error), .done_dependency(binding_dependency),
        .done_dependency_domain(), .done_dependency_layer(), .done_dependency_token(),
        .done_dependency_length(), .controller_state_bytes(binding_controller_bytes), .busy()
    );

    wire attention_ready, attention_valid, attention_yield;
    wire [3:0] attention_error;
    wire [159:0] attention_continuation;
    wire [7:0] attention_dependency_layer;
    wire [31:0] attention_dependency_token;
    wire attention_work_valid, attention_work_rsp_ready;
    wire [2:0] attention_work_op;
    wire [1:0] attention_work_domain, attention_work_target;
    wire [31:0] attention_work_token, attention_work_data;
    wire [7:0] attention_work_layer, attention_work_scalar_index;
    wire [11:0] attention_work_length, attention_work_component;
    wire [5:0] attention_work_slot;
    wire attention_work_bank, attention_cmd_valid, attention_result_ready;
    wire attention_source_event;
    wire [31:0] attention_source_bytes;
    wire [63:0] attention_cmd_addr;
    anvil_en1_replay_attention_projection #(.COMPACT(COMPACT)) attention_branch (
        .clk(clk), .rst_n(rst_n),
        .attention_activity(attention_activity),
        .start_valid(rst_n && state == ATTENTION_START), .start_ready(attention_ready),
        .model(model_hold), .precision(precision_hold), .layer(logical_layer),
        .frame_layer(frame_layer_hold), .token(token_hold), .tokens(tokens_hold),
        .weights_base(weights_base_hold), .frame_slot(slot_hold),
        .input_bank(1'b0), .output_bank(1'b1),
        .resume_valid(attention_resume), .continuation(continuation_hold),
        .dependency_valid(dependency_valid_hold),
        .dependency_domain(dependency_domain_hold),
        .dependency_layer(dependency_layer_hold), .dependency_token(dependency_token_hold),
        .dependency_length(dependency_length_hold), .dependency_slot(dependency_slot_hold),
        .mask_valid(mask_valid), .mask_ready(attention_selected && mask_ready),
        .mask_token(mask_token), .mask_rsp_valid(attention_selected && mask_rsp_valid),
        .mask_rsp_ready(mask_rsp_ready), .mask_rsp_data(mask_rsp_data),
        .mask_rsp_error(mask_rsp_error), .req_valid(req_valid),
        .req_ready(attention_selected && req_ready), .req_op(req_op),
        .req_model(req_model), .req_layer(req_layer), .req_token(req_token),
        .req_is_value(req_is_value), .req_kv_head(req_kv_head), .req_component(req_component),
        .req_base(req_base), .rsp_valid(attention_selected && rsp_valid),
        .rsp_ready(rsp_ready), .rsp_addr(rsp_addr), .rsp_owner(rsp_owner),
        .rsp_alias(rsp_alias), .rsp_error(rsp_error), .rsp_space(rsp_space),
        .work_req_valid(attention_work_valid),
        .work_req_ready(attention_selected && work_req_ready),
        .work_req_op(attention_work_op), .work_req_domain(attention_work_domain),
        .work_req_target(attention_work_target), .work_req_token(attention_work_token),
        .work_req_layer(attention_work_layer), .work_req_length(attention_work_length),
        .work_req_component(attention_work_component), .work_req_slot(attention_work_slot),
        .work_req_bank(attention_work_bank),
        .work_req_scalar_index(attention_work_scalar_index), .work_req_data(attention_work_data),
        .work_rsp_valid(attention_selected && work_rsp_valid),
        .work_rsp_ready(attention_work_rsp_ready), .work_rsp_data(work_rsp_data),
        .work_rsp_error(work_rsp_error),
        .cmd_valid(attention_cmd_valid), .cmd_ready(attention_selected && cmd_ready),
        .cmd_write(), .cmd_addr(attention_cmd_addr), .cmd_wdata(),
        .result_valid(attention_selected && result_valid),
        .result_ready(attention_result_ready), .result_data(result_data),
        .result_error(result_error), .done_valid(attention_valid),
        .done_ready(rst_n && state == ATTENTION_WAIT),
        .done_error(attention_error), .done_yield(attention_yield), .done_bank(),
        .done_continuation(attention_continuation),
        .done_dependency_layer(attention_dependency_layer),
        .done_dependency_token(attention_dependency_token),
        .owner_reprojection_event(owner_reprojection_event),
        .owner_reprojection_bytes(owner_reprojection_bytes),
        .query_projection_event(query_projection_event),
        .query_projection_bytes(query_projection_bytes),
        .source_read_event(attention_source_event), .source_read_bytes(attention_source_bytes),
        .controller_state_bytes(projection_controller_bytes),
        .executor_controller_bytes(executor_controller_bytes),
        .checkpoint_controller_bytes(checkpoint_controller_bytes),
        .tile_controller_bytes(tile_controller_bytes), .tile_live_bytes(tile_live_bytes),
        .tile_physical_bytes(tile_physical_bytes), .busy()
    );

    wire embed_ready, embed_valid, embed_input_valid, embed_input_last;
    wire embed_ple_valid, embed_ple_last, embed_cmd_valid, embed_result_ready;
    wire embed_input_event;
    wire [31:0] embed_input_index, embed_ple_index;
    wire [15:0] embed_ple_data;
    wire [63:0] embed_cmd_addr;
    wire [3:0] embed_error;
    wire embed_modality_valid, embed_modality_rsp_ready;
    wire [1:0] embed_modality_model, embed_modality_kind;
    wire [31:0] embed_modality_token, embed_modality_index;
    wire embed_input_correct = embed_input_index == input_count &&
        input_count < {20'd0, length_hold} &&
        embed_input_last == (input_count + 1'b1 == {20'd0, length_hold});
    wire embed_ple_correct = embed_ple_index == ple_count && ple_count < P &&
        embed_ple_last == (ple_count + 1'b1 == P);
    anvil_en1_embedding_ple #(.COMPACT(COMPACT)) layer_embedding (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == EMBED_START), .start_ready(embed_ready),
        .model(model_hold), .precision(precision_hold), .modality(selected_modality),
        .layer(logical_layer), .token(token_hold), .tokens_base(tokens_base_hold),
        .weights_base(weights_base_hold),
        .modality_valid(embed_modality_valid),
        .modality_ready(embedding_selected && (native_feature ?
            source_state == SOURCE_IDLE : modality_ready)),
        .modality_model(embed_modality_model), .modality_kind(embed_modality_kind),
        .modality_token(embed_modality_token), .modality_index(embed_modality_index),
        .modality_rsp_valid(embedding_selected && (native_feature ?
            source_state == SOURCE_RESPONSE : modality_rsp_valid)),
        .modality_rsp_ready(embed_modality_rsp_ready),
        .modality_rsp_data(native_feature ? source_data_hold : modality_rsp_data),
        .modality_rsp_error(native_feature ? source_error_hold : modality_rsp_error),
        .input_valid(embed_input_valid), .input_ready(rst_n && state == EMBED_WAIT),
        .input_index(embed_input_index), .input_data(), .input_last(embed_input_last),
        .ple_valid(embed_ple_valid), .ple_ready(rst_n && state == EMBED_WAIT),
        .ple_index(embed_ple_index), .ple_data(embed_ple_data), .ple_last(embed_ple_last),
        .cmd_valid(embed_cmd_valid), .cmd_ready(embedding_selected && cmd_ready),
        .cmd_write(), .cmd_addr(embed_cmd_addr), .cmd_wdata(),
        .input_read_event(embed_input_event),
        .result_valid(embedding_selected && result_valid),
        .result_ready(embed_result_ready), .result_data(result_data), .result_error(result_error),
        .done_valid(embed_valid), .done_ready(rst_n && state == EMBED_WAIT),
        .done_error(embed_error), .live_payload_bytes(embedding_live_bytes),
        .physical_payload_bytes(embedding_physical_bytes)
    );

    wire post_ready, post_valid, post_source_valid, post_source_rsp_ready;
    wire post_source_ple, post_source_branch;
    wire [1:0] post_source_model;
    wire [7:0] post_source_layer;
    wire [31:0] post_source_token, post_source_index;
    wire post_cmd_valid, post_result_ready, post_output_valid, post_output_last;
    wire [63:0] post_cmd_addr;
    wire [31:0] post_output_index;
    wire [15:0] post_output_data;
    wire [3:0] post_error;
    wire post_output_ready = rst_n && state == POST_WAIT && source_state == SOURCE_IDLE;
    wire post_output_correct = post_output_index == output_count &&
        output_count < {20'd0, length_hold} &&
        post_output_last == (output_count + 1'b1 == {20'd0, length_hold});
    anvil_en1_asym_attn_ple #(.COMPACT(COMPACT), .POST_ONLY(1)) post_attention (
        .clk(clk), .rst_n(rst_n),
        .attention_activity(),
        .avoided_projection_event(avoided_projection_event),
        .avoided_projection_bytes(avoided_projection_bytes),
        .start_valid(rst_n && state == POST_START), .start_ready(post_ready),
        .model(model_hold), .precision(precision_hold), .layer(logical_layer),
        .token(token_hold), .weights_base(weights_base_hold),
        .source_valid(post_source_valid),
        .source_ready(rst_n && state == POST_WAIT && source_state == SOURCE_IDLE),
        .source_model(post_source_model), .source_layer(post_source_layer),
        .source_token(post_source_token), .source_index(post_source_index),
        .source_is_ple(post_source_ple), .source_is_branch(post_source_branch),
        .source_rsp_valid(rst_n && source_state == SOURCE_RESPONSE),
        .source_rsp_ready(post_source_rsp_ready), .source_rsp_data(source_data_hold),
        .source_rsp_error(source_error_hold),
        .mask_valid(), .mask_ready(1'b0), .mask_token(), .mask_rsp_valid(1'b0),
        .mask_rsp_ready(), .mask_rsp_data(1'b0), .mask_rsp_error(1'b0),
        .req_valid(), .req_ready(1'b0), .req_op(), .req_model(), .req_layer(),
        .req_token(), .req_is_value(), .req_kv_head(), .req_component(), .req_base(),
        .rsp_valid(1'b0), .rsp_ready(), .rsp_addr(64'd0), .rsp_owner(8'd0),
        .rsp_alias(1'b0), .rsp_error(4'd0), .rsp_space(2'd0),
        .fetch_valid(), .fetch_ready(1'b0), .fetch_model(), .fetch_owner(),
        .fetch_token(), .fetch_is_value(), .fetch_kv_head(), .fetch_component(),
        .fetch_rsp_valid(1'b0), .fetch_rsp_ready(), .fetch_rsp_data(16'd0),
        .fetch_rsp_error(4'd0),
        .cmd_valid(post_cmd_valid), .cmd_ready(post_selected && cmd_ready),
        .cmd_write(), .cmd_addr(post_cmd_addr), .cmd_wdata(),
        .result_valid(post_selected && result_valid), .result_ready(post_result_ready),
        .result_data(result_data), .result_error(result_error),
        .output_valid(post_output_valid), .output_ready(post_output_ready),
        .output_index(post_output_index), .output_data(post_output_data),
        .output_last(post_output_last), .done_valid(post_valid),
        .done_ready(rst_n && state == POST_WAIT && !post_output_valid &&
            source_state == SOURCE_IDLE), .done_error(post_error),
        .live_payload_bytes(post_vector_live_bytes),
        .physical_payload_bytes(post_vector_physical_bytes)
    );

    always @(posedge clk) begin
        if (rst_n && state == EMBED_WAIT && embed_ple_valid && embed_ple_correct)
            ple_payload[embed_ple_index[P_BITS-1:0]] <= embed_ple_data;
        if (rst_n && source_state == SOURCE_LOCAL)
            ple_q <= ple_payload[source_index_hold[P_BITS-1:0]];
    end

    assign start_ready = rst_n && state == IDLE;
    assign modality_valid = embedding_selected && !native_feature && embed_modality_valid;
    assign modality_model = rst_n ? embed_modality_model : 2'd0;
    assign modality_kind = rst_n ? embed_modality_kind : 2'd0;
    assign modality_token = rst_n ? embed_modality_token : 32'd0;
    assign modality_index = rst_n ? embed_modality_index : 32'd0;
    assign modality_rsp_ready = embedding_selected && !native_feature && embed_modality_rsp_ready;
    assign work_req_valid = rst_n && (binding_selected ? binding_work_valid :
        (attention_selected ? attention_work_valid :
         (pair_selected ? state == PAIR_SEND :
            ((post_selected || (embedding_selected && native_feature)) &&
                source_state == SOURCE_SEND))));
    assign work_req_op = !rst_n ? 3'd0 : (binding_selected ? binding_work_op :
        (attention_selected ? attention_work_op : (pair_selected ? 3'd6 : 3'd4)));
    assign work_req_domain = !rst_n ? 2'd0 : (binding_selected ? binding_work_domain :
        (attention_selected ? attention_work_domain :
            (source_feature_hold && !pair_selected ? 2'd3 : 2'd0)));
    assign work_req_target = !rst_n ? 2'd0 : (binding_selected ? binding_work_target :
        (attention_selected ? attention_work_target : (pair_selected ? 2'd2 :
            (source_feature_hold ? 2'd1 : 2'd0))));
    assign work_req_token = !rst_n ? 32'd0 : (binding_selected ? binding_work_token :
        (attention_selected ? attention_work_token : token_hold));
    assign work_req_layer = !rst_n ? 8'd0 : (binding_selected ? binding_work_layer :
        (attention_selected ? attention_work_layer :
            (source_feature_hold && !pair_selected ? {6'd0, selected_modality} : frame_layer_hold)));
    assign work_req_length = !rst_n ? 12'd0 : (binding_selected ? binding_work_length :
        (attention_selected ? attention_work_length : length_hold));
    assign work_req_component = !rst_n ? 12'd0 :
        (binding_selected ? binding_work_component : (attention_selected ?
            attention_work_component : (pair_selected ?
                output_count[11:0] - 12'd2 : {source_index_hold[11:1], 1'b0})));
    assign work_req_slot = !rst_n ? 6'd0 : (binding_selected ? binding_work_slot :
        (attention_selected ? attention_work_slot :
            (source_feature_hold && !pair_selected ? dependency_slot_hold : slot_hold)));
    assign work_req_bank = rst_n && (binding_selected ? binding_work_bank :
        (attention_selected ? attention_work_bank : (pair_selected || source_branch_hold)));
    assign work_req_scalar_index = !rst_n ? 8'd0 :
        (binding_selected ? binding_work_scalar_index :
            (attention_selected ? attention_work_scalar_index : 8'd0));
    assign work_req_data = !rst_n ? 32'd0 : (binding_selected ? binding_work_data :
        (attention_selected ? attention_work_data : (pair_selected ? pair_hold : 32'd0)));
    assign work_rsp_ready = rst_n && (binding_selected ? binding_work_rsp_ready :
        (attention_selected ? attention_work_rsp_ready :
            (pair_selected ? state == PAIR_WAIT : source_state == SOURCE_WAIT)));
    assign cmd_valid = rst_n && (state == TOKEN_SEND ||
        (attention_selected && attention_cmd_valid) ||
        (embedding_selected && embed_cmd_valid) || (post_selected && post_cmd_valid));
    assign cmd_write = 0;
    assign input_read_event = (rst_n && state == TOKEN_SEND && cmd_ready) ||
        embed_input_event;
    assign cmd_addr = !rst_n ? 64'd0 : (attention_selected ? attention_cmd_addr :
        (embedding_selected ? embed_cmd_addr : (post_selected ? post_cmd_addr :
            token_address_hold)));
    assign cmd_wdata = 0;
    assign result_ready = rst_n && (state == TOKEN_WAIT ||
        (attention_selected && attention_result_ready) ||
        (embedding_selected && embed_result_ready) || (post_selected && post_result_ready));
    assign done_valid = rst_n && state == RESPONSE;
    assign done_error = rst_n ? error_hold : 4'd0;
    assign done_yield = rst_n && yield_hold && error_hold == 0;
    assign done_bank = rst_n;
    assign done_continuation = rst_n && yield_hold ? yielded_continuation : 160'd0;
    assign done_dependency_domain = rst_n && yield_hold ? yielded_domain : 2'd0;
    assign done_dependency_layer = rst_n && yield_hold ? yielded_layer : 8'd0;
    assign done_dependency_token = rst_n && yield_hold ? yielded_token : 32'd0;
    assign done_dependency_length = rst_n && yield_hold ? length_hold : 12'd0;
    assign ple_live_bytes = rst_n && (embedding_selected || ple_committed) ? 64'(2*P) : 64'd0;
    assign ple_physical_bytes = rst_n ? 64'(2*P) : 64'd0;
    assign busy = rst_n && state != IDLE;
    wire feature_source_event = rst_n && embedding_selected && source_feature_hold &&
        source_state == SOURCE_SEND && work_req_ready;
    assign source_read_event = attention_source_event || feature_source_event;
    assign source_read_bytes = attention_source_bytes + (feature_source_event ? 32'd4 : 32'd0);
    localparam integer CONTROLLER_BITS =
        $bits(state) + $bits(source_state) +
        $bits(model_hold) + $bits(precision_hold) + $bits(modality_hold) + $bits(mode_hold) +
        $bits(dependency_domain_hold) + $bits(selected_modality) + $bits(yielded_domain) +
        $bits(frame_layer_hold) + $bits(dependency_layer_hold) + $bits(yielded_layer) +
        $bits(token_hold) + $bits(tokens_hold) + $bits(dependency_token_hold) + $bits(yielded_token) +
        $bits(tokens_base_hold) + $bits(weights_base_hold) + $bits(token_address_hold) +
        $bits(slot_hold) + $bits(dependency_slot_hold) +
        $bits(length_hold) + $bits(dependency_length_hold) +
        $bits(dependency_valid_hold) + $bits(attention_resume) + $bits(yield_hold) +
        $bits(ple_committed) + $bits(continuation_hold) + $bits(yielded_continuation) +
        $bits(token_id_hold) + $bits(input_count) + $bits(ple_count) + $bits(output_count) +
        $bits(pair_hold) + $bits(token_error_hold) + $bits(low_hold) + $bits(ple_q) +
        $bits(error_hold) + $bits(pair_error_hold) + $bits(source_failure_hold) +
        $bits(source_ple_hold) + $bits(source_branch_hold) + $bits(source_feature_hold) +
        $bits(source_error_hold) +
        $bits(source_index_hold) + $bits(source_pair_hold) + $bits(source_data_hold) +
        $bits(source_work_error) + $bits(source_tag_error);
    assign controller_state_bytes = rst_n ? 64'((CONTROLLER_BITS + 7) >> 3) : 64'd0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            source_state <= SOURCE_IDLE;
            source_ple_hold <= 0;
            source_branch_hold <= 0;
            source_feature_hold <= 0;
            source_error_hold <= 0;
            source_index_hold <= 0;
            source_pair_hold <= 0;
            source_data_hold <= 0;
            source_work_error <= 0;
            source_tag_error <= 0;
            source_failure_hold <= 0;
        end else begin
            if (start_valid && start_ready)
                source_failure_hold <= 0;
            case (source_state)
                SOURCE_IDLE: begin
                    if (state == EMBED_WAIT && native_feature && embed_modality_valid) begin
                        source_feature_hold <= 1;
                        source_ple_hold <= 0;
                        source_branch_hold <= 0;
                        source_index_hold <= embed_modality_index;
                        source_tag_error <= !feature_tag_good ||
                            dependency_layer_hold != {6'd0, selected_modality} ||
                            embed_modality_model != model_hold ||
                            embed_modality_kind != selected_modality ||
                            embed_modality_token != token_hold;
                        source_error_hold <= 0;
                        source_work_error <= 0;
                        source_data_hold <= 0;
                        source_state <= SOURCE_VALIDATE;
                    end else if (state == POST_WAIT && post_source_valid) begin
                        source_feature_hold <= 0;
                        source_ple_hold <= post_source_ple;
                        source_branch_hold <= post_source_branch;
                        source_index_hold <= post_source_index;
                        source_tag_error <= post_source_model != model_hold ||
                            post_source_layer != logical_layer || post_source_token != token_hold;
                        source_error_hold <= 0;
                        source_work_error <= 0;
                        source_data_hold <= 0;
                        source_state <= SOURCE_VALIDATE;
                    end
                end
                SOURCE_VALIDATE: begin
                    if (source_tag_error || (source_ple_hold && source_branch_hold) ||
                        (source_ple_hold ? (!ple_committed || source_index_hold >= P) :
                            source_index_hold >= {20'd0, length_hold})) begin
                        source_error_hold <= 1;
                        source_failure_hold <= 7;
                        source_state <= SOURCE_RESPONSE;
                    end else if (source_ple_hold)
                        source_state <= SOURCE_LOCAL;
                    else
                        source_state <= SOURCE_SEND;
                end
                SOURCE_LOCAL: source_state <= SOURCE_LOCAL_CAPTURE;
                SOURCE_LOCAL_CAPTURE: begin
                    source_data_hold <= ple_q;
                    source_state <= SOURCE_RESPONSE;
                end
                SOURCE_SEND: if (work_req_valid && work_req_ready)
                    source_state <= SOURCE_WAIT;
                SOURCE_WAIT: if (work_rsp_valid && work_rsp_ready) begin
                    source_pair_hold <= work_rsp_data;
                    source_work_error <= work_rsp_error;
                    source_state <= SOURCE_REGISTER;
                end
                SOURCE_REGISTER: begin
                    source_error_hold <= source_work_error != 0;
                    if (source_work_error != 0) begin
                        source_failure_hold <= source_work_error;
                        source_data_hold <= 0;
                    end else
                        source_data_hold <= source_index_hold[0] ?
                            source_pair_hold[31:16] : source_pair_hold[15:0];
                    source_state <= SOURCE_RESPONSE;
                end
                SOURCE_RESPONSE: if (source_feature_hold ? embed_modality_rsp_ready : post_source_rsp_ready)
                    source_state <= SOURCE_IDLE;
                default: begin
                    source_error_hold <= 1;
                    source_failure_hold <= 7;
                    source_state <= SOURCE_RESPONSE;
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
            mode_hold <= 0;
            dependency_domain_hold <= 0;
            selected_modality <= 0;
            yielded_domain <= 0;
            frame_layer_hold <= 0;
            dependency_layer_hold <= 0;
            yielded_layer <= 0;
            token_hold <= 0;
            tokens_hold <= 0;
            dependency_token_hold <= 0;
            yielded_token <= 0;
            tokens_base_hold <= 0;
            weights_base_hold <= 0;
            token_address_hold <= 0;
            slot_hold <= 0;
            dependency_slot_hold <= 0;
            length_hold <= 0;
            dependency_length_hold <= 0;
            dependency_valid_hold <= 0;
            attention_resume <= 0;
            yield_hold <= 0;
            ple_committed <= 0;
            continuation_hold <= 0;
            yielded_continuation <= 0;
            token_id_hold <= 0;
            input_count <= 0;
            ple_count <= 0;
            output_count <= 0;
            pair_hold <= 0;
            token_error_hold <= 0;
            low_hold <= 0;
            error_hold <= 0;
            pair_error_hold <= 0;
        end else begin
            case (state)
                IDLE: if (start_valid && start_ready) begin
                    model_hold <= model;
                    precision_hold <= precision;
                    modality_hold <= modality;
                    mode_hold <= mode;
                    frame_layer_hold <= frame_layer;
                    token_hold <= token;
                    tokens_hold <= tokens;
                    tokens_base_hold <= tokens_base;
                    weights_base_hold <= weights_base;
                    slot_hold <= frame_slot;
                    continuation_hold <= continuation;
                    dependency_valid_hold <= dependency_valid;
                    dependency_domain_hold <= dependency_domain;
                    dependency_layer_hold <= dependency_layer;
                    dependency_token_hold <= dependency_token;
                    dependency_length_hold <= dependency_length;
                    dependency_slot_hold <= dependency_slot;
                    attention_resume <= 0;
                    yield_hold <= 0;
                    ple_committed <= 0;
                    error_hold <= 0;
                    pair_error_hold <= 0;
                    input_count <= 0;
                    ple_count <= 0;
                    output_count <= 0;
                    selected_modality <= 0;
                    yielded_domain <= 0;
                    yielded_layer <= 0;
                    yielded_token <= 0;
                    yielded_continuation <= 0;
                    state <= VALIDATE;
                end
                VALIDATE: begin
                    length_hold <= selected_length;
                    if (!native_model || precision_hold > 1) begin
                        error_hold <= 6;
                        state <= PUBLISH;
                    end else if (!descriptor_valid) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else if (mode_hold == 3 || (mode_hold == 1 &&
                        (!dependency_valid_hold || (!input_continuation &&
                            !projection_continuation && !ple_continuation)))) begin
                        error_hold <= 7;
                        state <= PUBLISH;
                    end else if (mode_hold == 1 && ple_continuation) begin
                        if (!feature_tag_good) begin
                            error_hold <= 7;
                            state <= PUBLISH;
                        end else
                            state <= TOKEN_ADDRESS;
                    end else if (mode_hold == 1 && projection_continuation) begin
                        attention_resume <= 1;
                        state <= ATTENTION_START;
                    end else
                        state <= BIND_START;
                end
                BIND_START: if (binding_ready)
                    state <= BIND_WAIT;
                BIND_WAIT: if (binding_valid) begin
                    if (binding_error != 0) begin
                        error_hold <= binding_error;
                        state <= PUBLISH;
                    end else if (binding_dependency) begin
                        yield_hold <= 1;
                        yielded_layer <= logical_layer;
                        yielded_token <= token_hold;
                        yielded_continuation <= {INPUT_MAGIC, 128'd0};
                        state <= PUBLISH;
                    end else begin
                        dependency_valid_hold <= 0;
                        attention_resume <= 0;
                        state <= ATTENTION_START;
                    end
                end
                ATTENTION_START: if (attention_ready)
                    state <= ATTENTION_WAIT;
                ATTENTION_WAIT: if (attention_valid) begin
                    if (attention_error != 0) begin
                        error_hold <= attention_error;
                        state <= PUBLISH;
                    end else if (attention_yield) begin
                        yield_hold <= 1;
                        yielded_layer <= attention_dependency_layer;
                        yielded_token <= attention_dependency_token;
                        yielded_continuation <= attention_continuation;
                        state <= PUBLISH;
                    end else
                        state <= TOKEN_ADDRESS;
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
                TOKEN_WAIT: if (result_valid) begin
                    token_id_hold <= result_data;
                    token_error_hold <= result_error;
                    state <= TOKEN_REGISTER;
                end
                TOKEN_REGISTER: begin
                    if (token_error_hold) begin
                        error_hold <= 2;
                        state <= PUBLISH;
                    end else if (token_id_hold >= (COMPACT ? 32'd32 : 32'd262144) ||
                        (image_token && !image_allowed) || (audio_token && !audio_allowed)) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else begin
                        if (image_token)
                            selected_modality <= 1;
                        else if (audio_token)
                            selected_modality <= 2;
                        else
                            selected_modality <= 0;
                        state <= MODALITY_BIND;
                    end
                end
                MODALITY_BIND: begin
                    if (mode_hold == 1 && ple_continuation) begin
                        if (!native_feature || !feature_tag_good ||
                            dependency_layer_hold != {6'd0, selected_modality}) begin
                            error_hold <= 7;
                            state <= PUBLISH;
                        end else
                            state <= EMBED_START;
                    end else if (native_feature) begin
                        yield_hold <= 1;
                        yielded_domain <= 3;
                        yielded_layer <= {6'd0, selected_modality};
                        yielded_token <= token_hold;
                        yielded_continuation <= {PLE_MAGIC, 128'd0};
                        state <= PUBLISH;
                    end else
                        state <= EMBED_START;
                end
                EMBED_START: if (embed_ready)
                    state <= EMBED_WAIT;
                EMBED_WAIT: begin
                    if (embed_input_valid) begin
                        if (!embed_input_correct)
                            error_hold <= 7;
                        input_count <= input_count + 1'b1;
                    end
                    if (embed_ple_valid) begin
                        if (!embed_ple_correct)
                            error_hold <= 7;
                        ple_count <= ple_count + 1'b1;
                    end
                    if (embed_valid) begin
                        if (embed_error != 0)
                            error_hold <= embed_error;
                        state <= EMBED_REGISTER;
                    end
                end
                EMBED_REGISTER: begin
                    if (error_hold != 0 || source_failure_hold != 0) begin
                        if (error_hold == 0)
                            error_hold <= source_failure_hold;
                        state <= PUBLISH;
                    end else if (input_count != {20'd0, length_hold} || ple_count != P) begin
                        error_hold <= 7;
                        state <= PUBLISH;
                    end else begin
                        ple_committed <= 1;
                        output_count <= 0;
                        state <= POST_START;
                    end
                end
                POST_START: if (post_ready)
                    state <= POST_WAIT;
                POST_WAIT: begin
                    if (post_output_valid && post_output_ready) begin
                        output_count <= output_count + 1'b1;
                        if (!post_output_correct)
                            error_hold <= 7;
                        else if (error_hold == 0) begin
                            if (!output_count[0])
                                low_hold <= post_output_data;
                            else begin
                                pair_hold <= {post_output_data, low_hold};
                                state <= PAIR_SEND;
                            end
                        end
                    end else if (post_valid && source_state == SOURCE_IDLE &&
                        !post_output_valid) begin
                        if (error_hold == 0) begin
                            if (source_failure_hold != 0)
                                error_hold <= source_failure_hold;
                            else if (post_error != 0)
                                error_hold <= post_error;
                            else if (output_count != {20'd0, length_hold})
                                error_hold <= 7;
                        end
                        ple_committed <= 0;
                        state <= PUBLISH;
                    end
                end
                PAIR_SEND: if (work_req_ready)
                    state <= PAIR_WAIT;
                PAIR_WAIT: if (work_rsp_valid) begin
                    pair_error_hold <= work_rsp_error;
                    state <= PAIR_REGISTER;
                end
                PAIR_REGISTER: begin
                    if (pair_error_hold != 0)
                        error_hold <= pair_error_hold;
                    state <= POST_WAIT;
                end
                PUBLISH: begin
                    ple_committed <= 0;
                    state <= RESPONSE;
                end
                RESPONSE: if (done_ready)
                    state <= IDLE;
                default: begin
                    error_hold <= 7;
                    yield_hold <= 0;
                    state <= PUBLISH;
                end
            endcase
        end
    end
endmodule
