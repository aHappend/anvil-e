module anvil_en1_replay_attention_execute #(
    parameter integer COMPACT = 0,
    parameter integer PAUSABLE = 0
) (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] model, precision,
    input wire [7:0] layer,
    input wire [3:0] query_head,
    input wire [31:0] query_position, tokens,
    input wire [63:0] weights_base,
    input wire [7:0] frame_layer,
    input wire [5:0] frame_slot,
    input wire input_bank,
    input wire resume_valid,
    input wire [159:0] continuation,
    input wire dependency_valid,
    input wire [1:0] dependency_domain,
    input wire [7:0] dependency_layer,
    input wire [31:0] dependency_token,
    input wire [11:0] dependency_length,
    input wire [5:0] dependency_slot,
    input wire pause, cancel,
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
    output wire [63:0] cmd_addr,
    output wire [31:0] cmd_wdata,
    input wire result_valid,
    output wire result_ready,
    input wire [31:0] result_data,
    input wire result_error,
    output wire output_valid,
    input wire output_ready,
    output wire [9:0] output_index,
    output wire [15:0] output_data,
    output wire output_last,
    output wire done_valid,
    input wire done_ready,
    output wire [3:0] done_error,
    output wire done_yield,
    output wire [159:0] done_continuation,
    output wire [7:0] done_owner,
    output wire [31:0] done_token,
    output wire done_is_value,
    output wire [1:0] done_kv_head,
    output wire [9:0] done_component,
    output wire owner_reprojection_event,
    output wire [31:0] owner_reprojection_bytes,
    output wire query_projection_event,
    output wire [31:0] query_projection_bytes,
    output wire source_read_event,
    output wire [31:0] source_read_bytes,
    output wire [63:0] controller_state_bytes,
    output wire [63:0] checkpoint_controller_bytes, tile_controller_bytes,
    output wire [63:0] tile_live_bytes, tile_physical_bytes,
    output wire [63:0] pair_live_bytes,
    output wire [3:0] attention_activity,
    output wire busy
);
    localparam [2:0] IDLE = 0, VALIDATE = 1, ATTENTION_START = 2,
        ATTENTION_RUN = 3, PUBLISH = 4, RESPONSE = 5;
    localparam [3:0] SERVICE_IDLE = 0, QUERY_VALIDATE = 1,
        QUERY_START = 2, QUERY_RUN = 3, QUERY_PUBLISH = 4, QUERY_RESPONSE = 5,
        FETCH_VALIDATE = 6, FETCH_START = 7, FETCH_RUN = 8,
        FETCH_PUBLISH = 9, FETCH_RESPONSE = 10;
    reg [2:0] state;
    reg [3:0] service_state;
    reg [1:0] model_hold, precision_hold, dependency_domain_hold;
    reg [7:0] layer_hold, frame_layer_hold, dependency_layer_hold;
    reg [3:0] query_head_hold;
    reg [31:0] position_hold, tokens_hold, dependency_token_hold;
    reg [63:0] weights_hold;
    reg [5:0] frame_slot_hold, dependency_slot_hold;
    reg input_bank_hold, resume_hold, dependency_valid_hold;
    reg [11:0] dependency_length_hold;
    reg [159:0] continuation_hold, done_continuation_hold;
    reg [3:0] error_hold;
    reg yield_hold;
    reg [7:0] done_owner_hold;
    reg [31:0] done_token_hold;
    reg done_selector_hold;
    reg [1:0] done_head_hold;
    reg [9:0] done_component_hold;
    reg authorized, authorized_memo;
    reg [7:0] authorized_owner;
    reg [31:0] authorized_token;
    reg authorized_selector;
    reg [1:0] authorized_head;
    reg [9:0] authorized_component;
    reg [1:0] service_model, service_head;
    reg [7:0] service_owner;
    reg [31:0] service_token;
    reg service_selector, service_memo;
    reg [9:0] service_component;
    reg [31:0] query_pair, service_pair;
    reg query_pair_valid;
    reg [9:0] query_pair_component;
    reg [3:0] service_error;

    initial begin
        if (COMPACT != 0 && COMPACT != 1)
            $fatal(1, "PARAMETER ERROR: COMPACT must be 0 or 1");
        if (PAUSABLE != 0 && PAUSABLE != 1)
            $fatal(1, "PARAMETER ERROR: PAUSABLE must be 0 or 1");
    end

    wire native_model, global_layer;
    wire [7:0] layer_count, owner_count;
    wire [11:0] selected_hidden;
    anvil_en1_geometry geometry (
        .rst_n(rst_n), .model(model_hold), .layer(layer_hold),
        .is_native(native_model), .layers(layer_count), .owners(owner_count),
        .owner(), .is_global(global_layer), .hidden(selected_hidden), .intermediate()
    );
    wire [9:0] dimension = COMPACT ?
        (global_layer ? 10'd8 : 10'd4) : (global_layer ? 10'd512 : 10'd256);
    wire [11:0] vector_length = COMPACT ? 12'd8 : selected_hidden;
    wire descriptor_valid = layer_hold < layer_count &&
        tokens_hold != 0 && tokens_hold <= 131072 && position_hold < tokens_hold &&
        query_head_hold < (COMPACT ? 4'd2 : 4'd8) && weights_hold[1:0] == 0;
    wire frame_valid = frame_layer_hold != 0 &&
        {1'b0, frame_layer_hold} == {1'b0, layer_hold} + 9'd1;
    wire dependency_descriptor_valid = dependency_domain_hold == 0 &&
        dependency_layer_hold < frame_layer_hold &&
        dependency_token_hold < tokens_hold &&
        dependency_length_hold == vector_length && dependency_slot_hold < 16;
    wire run = rst_n && state == ATTENTION_RUN && !(PAUSABLE && pause);
    wire cancel_service = PAUSABLE && cancel;
    wire tile_selected = service_state == QUERY_START || service_state == QUERY_RUN ||
        service_state == FETCH_START || service_state == FETCH_RUN;
    wire tile_query = service_state == QUERY_START || service_state == QUERY_RUN;

    wire attention_ready, attention_valid, attention_yield;
    wire [3:0] attention_error;
    wire [159:0] attention_continuation;
    wire [7:0] attention_owner;
    wire [31:0] attention_token;
    wire attention_selector;
    wire [1:0] attention_head;
    wire [9:0] attention_component;
    wire query_valid, query_rsp_ready;
    wire [9:0] query_component;
    wire fetch_valid, fetch_rsp_ready;
    wire [1:0] fetch_model, fetch_head;
    wire [7:0] fetch_owner;
    wire [31:0] fetch_token;
    wire fetch_selector;
    wire [9:0] fetch_component;
    wire need_valid;
    wire [1:0] need_model, need_head;
    wire [7:0] need_owner;
    wire [31:0] need_token;
    wire need_selector;
    wire [9:0] need_component;
    wire need_descriptor_valid = need_model == model_hold &&
        need_owner < owner_count && need_owner <= layer_hold &&
        need_token <= position_hold && need_token < tokens_hold &&
        need_head < (COMPACT || model_hold == 1 ? 2'd1 : 2'd2) &&
        need_component < dimension;
    wire direct_source = need_owner == layer_hold && need_token == position_hold;
    wire memo_source = dependency_valid_hold && dependency_descriptor_valid &&
        need_owner == dependency_layer_hold && need_token == dependency_token_hold;
    wire [1:0] need_action = cancel_service || !need_descriptor_valid ? 2'd2 :
        (direct_source || memo_source ? 2'd0 : 2'd1);
    wire need_ready = run && service_state == SERVICE_IDLE && !authorized;
    wire attention_work_valid, attention_work_rsp_ready;
    wire [2:0] attention_work_op;
    wire [1:0] attention_work_domain, attention_work_target;
    wire [31:0] attention_work_token, attention_work_data;
    wire [7:0] attention_work_layer, attention_work_scalar_index;
    wire [11:0] attention_work_length, attention_work_component;
    wire [5:0] attention_work_slot;
    wire attention_work_bank;
    wire attention_mask_valid, attention_mask_rsp_ready;
    wire attention_req_valid, attention_rsp_ready, attention_output_valid;
    wire tile_cmd_valid, tile_result_ready;

    anvil_en1_replay_attention #(.COMPACT(COMPACT)) attention (
        .clk(clk), .rst_n(rst_n),
        .attention_activity(attention_activity),
        .start_valid(rst_n && state == ATTENTION_START), .start_ready(attention_ready),
        .model(model_hold), .layer(layer_hold), .query_head(query_head_hold),
        .query_position(position_hold), .tokens(tokens_hold),
        .frame_layer(frame_layer_hold), .frame_slot(frame_slot_hold),
        .resume_valid(resume_hold), .continuation(continuation_hold),
        .query_valid(query_valid), .query_ready(run && service_state == SERVICE_IDLE),
        .query_component(query_component),
        .query_rsp_valid(run && service_state == QUERY_RESPONSE),
        .query_rsp_ready(query_rsp_ready),
        .query_rsp_data(service_component[0] ? service_pair[31:16] : service_pair[15:0]),
        .query_rsp_error(service_error != 0),
        .mask_valid(attention_mask_valid), .mask_ready(run && mask_ready), .mask_token(mask_token),
        .mask_rsp_valid(run && mask_rsp_valid), .mask_rsp_ready(attention_mask_rsp_ready),
        .mask_rsp_data(mask_rsp_data), .mask_rsp_error(mask_rsp_error),
        .req_valid(attention_req_valid), .req_ready(run && req_ready),
        .req_op(req_op), .req_model(req_model), .req_layer(req_layer),
        .req_token(req_token), .req_is_value(req_is_value), .req_kv_head(req_kv_head),
        .req_component(req_component), .req_base(req_base),
        .rsp_valid(run && rsp_valid), .rsp_ready(attention_rsp_ready),
        .rsp_addr(rsp_addr), .rsp_owner(rsp_owner), .rsp_alias(rsp_alias),
        .rsp_error(rsp_error), .rsp_space(rsp_space),
        .fetch_valid(fetch_valid), .fetch_ready(run && service_state == SERVICE_IDLE),
        .fetch_model(fetch_model), .fetch_owner(fetch_owner), .fetch_token(fetch_token),
        .fetch_is_value(fetch_selector), .fetch_kv_head(fetch_head),
        .fetch_component(fetch_component),
        .fetch_rsp_valid(run && service_state == FETCH_RESPONSE),
        .fetch_rsp_ready(fetch_rsp_ready),
        .fetch_rsp_data(service_component[0] ? service_pair[31:16] : service_pair[15:0]),
        .fetch_rsp_error(service_error),
        .need_valid(need_valid), .need_ready(need_ready), .need_action(need_action),
        .need_model(need_model), .need_owner(need_owner), .need_token(need_token),
        .need_is_value(need_selector), .need_kv_head(need_head),
        .need_component(need_component),
        .work_req_valid(attention_work_valid), .work_req_ready(run && !tile_selected && work_req_ready),
        .work_req_op(attention_work_op), .work_req_domain(attention_work_domain),
        .work_req_target(attention_work_target), .work_req_token(attention_work_token),
        .work_req_layer(attention_work_layer), .work_req_length(attention_work_length),
        .work_req_component(attention_work_component), .work_req_slot(attention_work_slot),
        .work_req_bank(attention_work_bank),
        .work_req_scalar_index(attention_work_scalar_index), .work_req_data(attention_work_data),
        .work_rsp_valid(run && !tile_selected && work_rsp_valid),
        .work_rsp_ready(attention_work_rsp_ready),
        .work_rsp_data(work_rsp_data), .work_rsp_error(work_rsp_error),
        .output_valid(attention_output_valid), .output_ready(run && output_ready),
        .output_index(output_index), .output_data(output_data), .output_last(output_last),
        .done_valid(attention_valid), .done_ready(run && service_state == SERVICE_IDLE && !authorized),
        .done_error(attention_error), .done_yield(attention_yield),
        .done_continuation(attention_continuation), .done_owner(attention_owner),
        .done_token(attention_token), .done_is_value(attention_selector),
        .done_kv_head(attention_head), .done_component(attention_component),
        .controller_state_bytes(checkpoint_controller_bytes), .busy()
    );

    wire tile_ready, tile_valid, tile_work_valid, tile_work_rsp_ready;
    wire [2:0] tile_work_op;
    wire [1:0] tile_work_domain, tile_work_target;
    wire [31:0] tile_work_token, tile_work_data, tile_data;
    wire [7:0] tile_work_layer, tile_work_scalar_index;
    wire [11:0] tile_work_length, tile_work_component;
    wire [5:0] tile_work_slot;
    wire tile_work_bank;
    wire [3:0] tile_error;
    anvil_en1_replay_kv_tile #(.COMPACT(COMPACT), .ALLOW_QUERY(1)) tile (
        .clk(clk), .rst_n(rst_n),
        .start_valid(run && (service_state == QUERY_START || service_state == FETCH_START)),
        .start_ready(tile_ready), .model(model_hold), .precision(precision_hold),
        .owner(tile_query ? layer_hold : service_owner),
        .token(tile_query ? position_hold : service_token), .tokens(tokens_hold),
        .is_value(!tile_query && service_selector),
        .kv_head(tile_query ? 2'd0 : service_head),
        .is_query(tile_query), .query_head(query_head_hold),
        .component({service_component[9:1], 1'b0}), .weights_base(weights_hold),
        .source_is_memo(!tile_query && service_memo),
        .source_layer(!tile_query && service_memo ? dependency_layer_hold : frame_layer_hold),
        .source_token(!tile_query && service_memo ? dependency_token_hold : position_hold),
        .source_slot(!tile_query && service_memo ? dependency_slot_hold : frame_slot_hold),
        .source_bank(!tile_query && service_memo ? 1'b0 : input_bank_hold),
        .work_req_valid(tile_work_valid), .work_req_ready(run && tile_selected && work_req_ready),
        .work_req_op(tile_work_op), .work_req_domain(tile_work_domain),
        .work_req_target(tile_work_target), .work_req_token(tile_work_token),
        .work_req_layer(tile_work_layer), .work_req_length(tile_work_length),
        .work_req_component(tile_work_component), .work_req_slot(tile_work_slot),
        .work_req_bank(tile_work_bank), .work_req_scalar_index(tile_work_scalar_index),
        .work_req_data(tile_work_data),
        .work_rsp_valid(run && tile_selected && work_rsp_valid),
        .work_rsp_ready(tile_work_rsp_ready),
        .work_rsp_data(work_rsp_data), .work_rsp_error(work_rsp_error),
        .cmd_valid(tile_cmd_valid), .cmd_ready(run && tile_selected && cmd_ready),
        .cmd_write(cmd_write), .cmd_addr(cmd_addr), .cmd_wdata(cmd_wdata),
        .result_valid(run && tile_selected && result_valid), .result_ready(tile_result_ready),
        .result_data(result_data), .result_error(result_error),
        .done_valid(tile_valid), .done_ready(run &&
            (service_state == QUERY_RUN || service_state == FETCH_RUN)),
        .done_data(tile_data), .done_error(tile_error),
        .owner_reprojection_event(owner_reprojection_event),
        .owner_reprojection_bytes(owner_reprojection_bytes),
        .query_projection_event(query_projection_event),
        .query_projection_bytes(query_projection_bytes),
        .source_read_event(source_read_event), .source_read_bytes(source_read_bytes),
        .controller_state_bytes(tile_controller_bytes),
        .tile_live_bytes(tile_live_bytes), .tile_physical_bytes(tile_physical_bytes), .busy()
    );

    assign start_ready = rst_n && state == IDLE;
    assign mask_valid = run && attention_mask_valid;
    assign mask_rsp_ready = run && attention_mask_rsp_ready;
    assign req_valid = run && attention_req_valid;
    assign rsp_ready = run && attention_rsp_ready;
    assign output_valid = run && attention_output_valid;
    assign cmd_valid = run && tile_selected && tile_cmd_valid;
    assign result_ready = run && tile_selected && tile_result_ready;
    assign work_req_valid = run && (tile_selected ? tile_work_valid : attention_work_valid);
    assign work_req_op = !rst_n ? 3'd0 : (tile_selected ? tile_work_op : attention_work_op);
    assign work_req_domain = !rst_n ? 2'd0 :
        (tile_selected ? tile_work_domain : attention_work_domain);
    assign work_req_target = !rst_n ? 2'd0 :
        (tile_selected ? tile_work_target : attention_work_target);
    assign work_req_token = !rst_n ? 32'd0 :
        (tile_selected ? tile_work_token : attention_work_token);
    assign work_req_layer = !rst_n ? 8'd0 :
        (tile_selected ? tile_work_layer : attention_work_layer);
    assign work_req_length = !rst_n ? 12'd0 :
        (tile_selected ? tile_work_length : attention_work_length);
    assign work_req_component = !rst_n ? 12'd0 :
        (tile_selected ? tile_work_component : attention_work_component);
    assign work_req_slot = !rst_n ? 6'd0 :
        (tile_selected ? tile_work_slot : attention_work_slot);
    assign work_req_bank = rst_n && (tile_selected ? tile_work_bank : attention_work_bank);
    assign work_req_scalar_index = !rst_n ? 8'd0 :
        (tile_selected ? tile_work_scalar_index : attention_work_scalar_index);
    assign work_req_data = !rst_n ? 32'd0 :
        (tile_selected ? tile_work_data : attention_work_data);
    assign work_rsp_ready = run && (tile_selected ? tile_work_rsp_ready : attention_work_rsp_ready);
    assign done_valid = rst_n && state == RESPONSE;
    assign done_error = rst_n ? error_hold : 4'd0;
    assign done_yield = rst_n && yield_hold && error_hold == 0;
    assign done_continuation = rst_n && yield_hold ? done_continuation_hold : 160'd0;
    assign done_owner = rst_n && yield_hold ? done_owner_hold : 8'd0;
    assign done_token = rst_n && yield_hold ? done_token_hold : 32'd0;
    assign done_is_value = rst_n && yield_hold && done_selector_hold;
    assign done_kv_head = rst_n && yield_hold ? done_head_hold : 2'd0;
    assign done_component = rst_n && yield_hold ? done_component_hold : 10'd0;
    assign controller_state_bytes = rst_n ? 64'd100 : 64'd0;
    assign pair_live_bytes = !rst_n ? 64'd0 :
        (query_pair_valid ? 64'd4 : 64'd0) +
        (service_state != SERVICE_IDLE ? 64'd4 : 64'd0);
    assign busy = rst_n && state != IDLE;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            service_state <= SERVICE_IDLE;
            model_hold <= 0;
            precision_hold <= 0;
            dependency_domain_hold <= 0;
            layer_hold <= 0;
            frame_layer_hold <= 0;
            dependency_layer_hold <= 0;
            query_head_hold <= 0;
            position_hold <= 0;
            tokens_hold <= 0;
            dependency_token_hold <= 0;
            weights_hold <= 0;
            frame_slot_hold <= 0;
            dependency_slot_hold <= 0;
            input_bank_hold <= 0;
            resume_hold <= 0;
            dependency_valid_hold <= 0;
            dependency_length_hold <= 0;
            continuation_hold <= 0;
            done_continuation_hold <= 0;
            error_hold <= 0;
            yield_hold <= 0;
            done_owner_hold <= 0;
            done_token_hold <= 0;
            done_selector_hold <= 0;
            done_head_hold <= 0;
            done_component_hold <= 0;
            authorized <= 0;
            authorized_memo <= 0;
            authorized_owner <= 0;
            authorized_token <= 0;
            authorized_selector <= 0;
            authorized_head <= 0;
            authorized_component <= 0;
            service_model <= 0;
            service_head <= 0;
            service_owner <= 0;
            service_token <= 0;
            service_selector <= 0;
            service_memo <= 0;
            service_component <= 0;
            query_pair <= 0;
            service_pair <= 0;
            query_pair_valid <= 0;
            query_pair_component <= 0;
            service_error <= 0;
        end else begin
            if (need_valid && need_ready && need_action == 0) begin
                authorized <= 1;
                authorized_memo <= !direct_source;
                authorized_owner <= need_owner;
                authorized_token <= need_token;
                authorized_selector <= need_selector;
                authorized_head <= need_head;
                authorized_component <= need_component;
            end
            case (state)
                IDLE: if (start_valid && start_ready) begin
                    model_hold <= model;
                    precision_hold <= precision;
                    layer_hold <= layer;
                    query_head_hold <= query_head;
                    position_hold <= query_position;
                    tokens_hold <= tokens;
                    weights_hold <= weights_base;
                    frame_layer_hold <= frame_layer;
                    frame_slot_hold <= frame_slot;
                    input_bank_hold <= input_bank;
                    resume_hold <= resume_valid;
                    continuation_hold <= continuation;
                    dependency_valid_hold <= dependency_valid;
                    dependency_domain_hold <= dependency_domain;
                    dependency_layer_hold <= dependency_layer;
                    dependency_token_hold <= dependency_token;
                    dependency_length_hold <= dependency_length;
                    dependency_slot_hold <= dependency_slot;
                    authorized <= 0;
                    query_pair_valid <= 0;
                    query_pair <= 0;
                    service_pair <= 0;
                    service_error <= 0;
                    error_hold <= 0;
                    yield_hold <= 0;
                    done_continuation_hold <= 0;
                    done_owner_hold <= 0;
                    done_token_hold <= 0;
                    done_selector_hold <= 0;
                    done_head_hold <= 0;
                    done_component_hold <= 0;
                    state <= VALIDATE;
                end
                VALIDATE: begin
                    if (!native_model || precision_hold > 1) begin
                        error_hold <= 6;
                        state <= PUBLISH;
                    end else if (!descriptor_valid) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else if (!frame_valid ||
                        (dependency_valid_hold && !dependency_descriptor_valid)) begin
                        error_hold <= 7;
                        state <= PUBLISH;
                    end else
                        state <= ATTENTION_START;
                end
                ATTENTION_START: if (attention_ready)
                    state <= ATTENTION_RUN;
                ATTENTION_RUN: if (run && attention_valid &&
                    service_state == SERVICE_IDLE && !authorized) begin
                    if (error_hold == 0)
                        error_hold <= attention_error;
                    yield_hold <= attention_yield && attention_error == 0 && error_hold == 0;
                    done_continuation_hold <= attention_continuation;
                    done_owner_hold <= attention_owner;
                    done_token_hold <= attention_token;
                    done_selector_hold <= attention_selector;
                    done_head_hold <= attention_head;
                    done_component_hold <= attention_component;
                    query_pair_valid <= 0;
                    state <= PUBLISH;
                end
                PUBLISH: state <= RESPONSE;
                RESPONSE: if (done_ready)
                    state <= IDLE;
                default: begin
                    error_hold <= 7;
                    yield_hold <= 0;
                    state <= PUBLISH;
                end
            endcase

            case (service_state)
                SERVICE_IDLE: begin
                    if (run && query_valid) begin
                        service_component <= query_component;
                        service_pair <= 0;
                        service_error <= 0;
                        service_state <= QUERY_VALIDATE;
                    end else if (run && fetch_valid) begin
                        service_model <= fetch_model;
                        service_owner <= fetch_owner;
                        service_token <= fetch_token;
                        service_selector <= fetch_selector;
                        service_head <= fetch_head;
                        service_component <= fetch_component;
                        service_memo <= authorized_memo;
                        service_pair <= 0;
                        service_error <= 0;
                        service_state <= FETCH_VALIDATE;
                    end
                end
                QUERY_VALIDATE: begin
                    if (cancel_service) begin
                        service_error <= 7;
                        service_state <= QUERY_PUBLISH;
                    end else if (service_component >= dimension) begin
                        service_error <= 5;
                        error_hold <= 5;
                        service_state <= QUERY_PUBLISH;
                    end else if (query_pair_valid &&
                        query_pair_component == {service_component[9:1], 1'b0}) begin
                        service_pair <= query_pair;
                        service_state <= QUERY_PUBLISH;
                    end else
                        service_state <= QUERY_START;
                end
                QUERY_START: if (tile_ready)
                    service_state <= QUERY_RUN;
                QUERY_RUN: if (tile_valid) begin
                    service_pair <= tile_data;
                    service_error <= tile_error;
                    if (tile_error != 0)
                        error_hold <= tile_error;
                    query_pair_valid <= tile_error == 0;
                    if (tile_error == 0) begin
                        query_pair <= tile_data;
                        query_pair_component <= {service_component[9:1], 1'b0};
                    end
                    service_state <= QUERY_PUBLISH;
                end
                QUERY_PUBLISH: service_state <= QUERY_RESPONSE;
                QUERY_RESPONSE: if (run && query_rsp_ready)
                    service_state <= SERVICE_IDLE;
                FETCH_VALIDATE: begin
                    if (cancel_service || !authorized || service_model != model_hold ||
                        service_owner != authorized_owner || service_token != authorized_token ||
                        service_selector != authorized_selector || service_head != authorized_head ||
                        service_component != authorized_component) begin
                        service_error <= 7;
                        service_state <= FETCH_PUBLISH;
                    end else
                        service_state <= FETCH_START;
                end
                FETCH_START: if (tile_ready)
                    service_state <= FETCH_RUN;
                FETCH_RUN: if (tile_valid) begin
                    service_pair <= tile_data;
                    service_error <= tile_error;
                    service_state <= FETCH_PUBLISH;
                end
                FETCH_PUBLISH: service_state <= FETCH_RESPONSE;
                FETCH_RESPONSE: if (run && fetch_rsp_ready) begin
                    authorized <= 0;
                    service_state <= SERVICE_IDLE;
                end
                default: begin
                    service_error <= 7;
                    service_state <= FETCH_PUBLISH;
                end
            endcase
        end
    end
endmodule
