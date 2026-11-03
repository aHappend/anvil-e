module anvil_en1_replay_audio_history #(
    parameter integer COMPACT = 0
) (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] model, precision, mode,
    input wire [31:0] generation, frames, query_token,
    input wire [7:0] frame_layer,
    input wire [5:0] frame_slot,
    input wire [63:0] audio_base, audio_weights_base,
    input wire [159:0] continuation,
    input wire dependency_valid,
    input wire [1:0] dependency_domain,
    input wire [7:0] dependency_layer,
    input wire [31:0] dependency_token,
    input wire [11:0] dependency_length,
    input wire [5:0] dependency_slot,
    output wire work_req_valid,
    input wire work_req_ready,
    output reg [2:0] work_req_op,
    output reg [1:0] work_req_domain, work_req_target,
    output reg [31:0] work_req_token,
    output reg [7:0] work_req_layer,
    output reg [11:0] work_req_length, work_req_component,
    output reg [5:0] work_req_slot,
    output reg work_req_bank,
    output reg [7:0] work_req_scalar_index,
    output reg [31:0] work_req_data,
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
    output wire done_valid,
    input wire done_ready,
    output wire [3:0] done_error,
    output wire done_yield,
    output wire [2:0] done_history_count,
    output wire [159:0] done_continuation,
    output wire [1:0] done_dependency_domain,
    output wire [7:0] done_dependency_layer,
    output wire [31:0] done_dependency_token,
    output wire [11:0] done_dependency_length,
    output wire input_read_event, projection_event, intermediate_event,
    output wire source_read_event, weight_read_event, history_replay_event, glu_replay_event,
    output wire [31:0] input_read_bytes, projection_bytes, intermediate_bytes,
    output wire [31:0] source_read_bytes, weight_read_bytes, history_replay_bytes, glu_replay_bytes,
    output wire [63:0] vector_live_bytes, vector_physical_bytes,
    output wire [63:0] controller_bytes, nested_controller_bytes
);
    localparam [4:0] IDLE = 0, VALIDATE = 1, CHILD_START = 2,
        CHILD_WAIT = 3, CHILD_CHECK = 4, FOLD_START = 5, FOLD_WAIT = 6,
        FOLD_CHECK = 7, ADVANCE = 8, PUBLISH = 9, RESPONSE = 10,
        RELEASE_SEND = 11, RELEASE_WAIT = 12, RELEASE_REGISTER = 13,
        TAP_SETUP = 14, SNAPSHOT_SEND = 15, SNAPSHOT_WAIT = 16,
        SNAPSHOT_REGISTER = 17, RESTORE_CHECK = 18, OUTPUT_SEND = 19,
        OUTPUT_WAIT = 20, OUTPUT_REGISTER = 21;
    localparam [31:0] HISTORY_MAGIC = 32'h454e314c;
    localparam [31:0] INPUT_MAGIC = 32'h454e3148;
    localparam [31:0] HEAD_MAGIC = 32'h454e3141;
    localparam [31:0] FINAL_BIND_MAGIC = 32'h454e3150;
    reg [4:0] state;
    reg [1:0] model_hold, precision_hold, mode_hold, child_mode;
    reg [1:0] dependency_domain_hold, yielded_domain;
    reg [31:0] generation_hold, frames_hold, query_hold, dependency_token_hold;
    reg [31:0] yielded_token;
    reg [7:0] layer_hold, dependency_layer_hold, yielded_layer;
    reg [5:0] slot_hold, dependency_slot_hold;
    reg [11:0] dependency_length_hold, yielded_length;
    reg [2:0] distance_hold;
    reg [63:0] audio_hold, weights_hold;
    reg [159:0] continuation_hold, child_continuation, yielded_continuation;
    reg dependency_valid_hold, child_yield_hold, child_bank_hold, yield_hold;
    reg [1:0] release_kind;
    reg [3:0] error_hold, child_error_hold, work_error_hold;
    reg [9:0] channel_hold;
    reg [15:0] low_hold;
    reg [31:0] accumulator_hold, fold_data_hold, output_pair, snapshot_data;
    reg snapshot_restore, snapshot_word;

    initial begin
        if (COMPACT != 0 && COMPACT != 1)
            $fatal(1, "PARAMETER ERROR: COMPACT must be 0 or 1");
    end

    wire [7:0] logical_layer = layer_hold - 1'b1;
    wire [31:0] tokens_hold = (frames_hold + 32'd3) >> 2;
    wire [2:0] last_distance = query_hold < 4 ? query_hold[2:0] : 3'd4;
    wire [31:0] historical_token = query_hold - {29'd0, distance_hold};
    wire common_continuation_tag = continuation_hold[127:96] == generation_hold &&
        continuation_hold[63:56] == layer_hold &&
        continuation_hold[55:50] == slot_hold &&
        continuation_hold[49:48] == model_hold &&
        continuation_hold[47:46] == precision_hold &&
        continuation_hold[45:38] == logical_layer &&
        continuation_hold[34:0] == 0;
    wire input_continuation_tag = common_continuation_tag &&
        continuation_hold[159:128] == HISTORY_MAGIC &&
        continuation_hold[95:64] == query_hold &&
        continuation_hold[37:35] <= last_distance;
    wire head_continuation_tag = common_continuation_tag &&
        (continuation_hold[159:128] == HEAD_MAGIC ||
            (continuation_hold[159:128] == FINAL_BIND_MAGIC &&
                continuation_hold[37:35] == 0)) &&
        continuation_hold[95:64] <= query_hold &&
        query_hold - continuation_hold[95:64] <= {29'd0, last_distance};
    wire [31:0] resumed_distance = query_hold - continuation_hold[95:64];
    wire [159:0] input_yield_descriptor = {HISTORY_MAGIC, generation_hold,
        query_hold, layer_hold, slot_hold, model_hold, precision_hold,
        logical_layer, distance_hold, 35'd0};
    wire child_selected = rst_n && (state == CHILD_START || state == CHILD_WAIT);
    wire fold_selected = rst_n && (state == FOLD_START || state == FOLD_WAIT);
    wire child_ready, child_valid, child_yield, child_bank;
    wire child_work_valid, child_work_rsp_ready, child_cmd_valid, child_result_ready;
    wire [3:0] child_error;
    wire [159:0] child_done_continuation;
    wire [1:0] child_dependency_domain;
    wire [7:0] child_dependency_layer;
    wire [31:0] child_dependency_token;
    wire [11:0] child_dependency_length;
    wire [2:0] child_op;
    wire [1:0] child_domain, child_target;
    wire [31:0] child_token, child_data;
    wire [7:0] child_layer, child_scalar;
    wire [11:0] child_length, child_component;
    wire [5:0] child_slot;
    wire child_work_bank;
    wire [63:0] child_addr;
    wire [63:0] residual_control, heads_control, binding_control, head_control;
    wire [63:0] heads_nested_control, post_control, post_nested_control;
    wire child_source_event, child_weight_event, child_projection_event;
    wire [31:0] child_source_bytes, child_weight_bytes, child_projection_bytes;
    wire [63:0] child_live, child_physical;
    anvil_en1_replay_audio_residual #(.COMPACT(COMPACT), .PACKED_FRAME(1)) residual (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == CHILD_START), .start_ready(child_ready),
        .model(model_hold), .precision(precision_hold), .mode(child_mode),
        .generation(generation_hold), .frames(frames_hold), .query_token(historical_token),
        .frame_layer(layer_hold), .frame_slot(slot_hold),
        .audio_base(audio_hold), .audio_weights_base(weights_hold),
        .continuation(child_continuation),
        .dependency_valid(dependency_valid_hold &&
            (child_mode == 1 || dependency_token_hold == historical_token)),
        .dependency_domain(dependency_domain_hold),
        .dependency_layer(dependency_layer_hold), .dependency_token(dependency_token_hold),
        .dependency_length(dependency_length_hold), .dependency_slot(dependency_slot_hold),
        .work_req_valid(child_work_valid),
        .work_req_ready(child_selected && work_req_ready),
        .work_req_op(child_op), .work_req_domain(child_domain),
        .work_req_target(child_target), .work_req_token(child_token),
        .work_req_layer(child_layer), .work_req_length(child_length),
        .work_req_component(child_component), .work_req_slot(child_slot),
        .work_req_bank(child_work_bank), .work_req_scalar_index(child_scalar),
        .work_req_data(child_data),
        .work_rsp_valid(child_selected && work_rsp_valid),
        .work_rsp_ready(child_work_rsp_ready), .work_rsp_data(work_rsp_data),
        .work_rsp_error(work_rsp_error),
        .cmd_valid(child_cmd_valid), .cmd_ready(child_selected && cmd_ready),
        .cmd_write(), .cmd_addr(child_addr), .cmd_wdata(),
        .result_valid(child_selected && result_valid), .result_ready(child_result_ready),
        .result_data(result_data), .result_error(result_error),
        .done_valid(child_valid), .done_ready(rst_n && state == CHILD_WAIT),
        .done_error(child_error), .done_yield(child_yield), .done_bank(child_bank),
        .done_continuation(child_done_continuation),
        .done_dependency_domain(child_dependency_domain),
        .done_dependency_layer(child_dependency_layer),
        .done_dependency_token(child_dependency_token),
        .done_dependency_length(child_dependency_length),
        .input_read_event(input_read_event), .input_read_bytes(input_read_bytes),
        .projection_event(child_projection_event), .projection_bytes(child_projection_bytes),
        .intermediate_event(intermediate_event), .intermediate_bytes(intermediate_bytes),
        .source_read_event(child_source_event), .source_read_bytes(child_source_bytes),
        .weight_read_event(child_weight_event), .weight_read_bytes(child_weight_bytes),
        .vector_live_bytes(child_live), .vector_physical_bytes(child_physical),
        .controller_bytes(residual_control), .heads_controller_bytes(heads_control),
        .binding_controller_bytes(binding_control), .head_controller_bytes(head_control),
        .heads_nested_controller_bytes(heads_nested_control),
        .post_controller_bytes(post_control), .post_nested_controller_bytes(post_nested_control)
    );

    wire fold_ready, fold_valid, fold_work_valid, fold_work_rsp_ready;
    wire fold_cmd_valid, fold_result_ready, fold_source_event, fold_projection_event;
    wire [2:0] fold_op;
    wire [1:0] fold_domain, fold_target;
    wire [31:0] fold_token, fold_source_bytes, fold_projection_bytes;
    wire [7:0] fold_layer, fold_scalar;
    wire [11:0] fold_length, fold_component;
    wire [5:0] fold_slot;
    wire fold_bank;
    wire [63:0] fold_addr, fold_live, fold_physical, fold_control, fold_nested;
    wire [3:0] fold_error;
    wire [31:0] fold_data;
    anvil_en1_audio_history_fold #(
        .FUSE_LEADING_PADDING(1), .SINGLE_CHANNEL(1)
    ) fold (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == FOLD_START), .start_ready(fold_ready),
        .model(model_hold), .precision(precision_hold), .generation(generation_hold),
        .frame_token(query_hold),
        .source_token(historical_token),
        .frame_layer(layer_hold), .frame_slot(slot_hold),
        .kernel(3'd4 - distance_hold), .padding(1'b0),
        .channel(channel_hold), .prior_accumulator(accumulator_hold),
        .audio_weights_base(weights_hold),
        .work_req_valid(fold_work_valid), .work_req_ready(fold_selected && work_req_ready),
        .work_req_op(fold_op), .work_req_domain(fold_domain), .work_req_target(fold_target),
        .work_req_token(fold_token), .work_req_layer(fold_layer),
        .work_req_length(fold_length), .work_req_component(fold_component),
        .work_req_slot(fold_slot), .work_req_bank(fold_bank),
        .work_req_scalar_index(fold_scalar), .work_req_data(fold_data),
        .work_rsp_valid(fold_selected && work_rsp_valid),
        .work_rsp_ready(fold_work_rsp_ready), .work_rsp_data(work_rsp_data),
        .work_rsp_error(work_rsp_error),
        .cmd_valid(fold_cmd_valid), .cmd_ready(fold_selected && cmd_ready),
        .cmd_write(), .cmd_addr(fold_addr), .cmd_wdata(),
        .result_valid(fold_selected && result_valid), .result_ready(fold_result_ready),
        .result_data(result_data), .result_error(result_error),
        .done_valid(fold_valid), .done_ready(rst_n && state == FOLD_WAIT),
        .done_error(fold_error), .done_data(fold_data),
        .source_read_event(fold_source_event),
        .source_read_bytes(fold_source_bytes), .projection_event(fold_projection_event),
        .projection_bytes(fold_projection_bytes),
        .glu_replay_event(glu_replay_event), .glu_replay_bytes(glu_replay_bytes),
        .vector_live_bytes(fold_live), .vector_physical_bytes(fold_physical),
        .controller_bytes(fold_control), .nested_controller_bytes(fold_nested)
    );

    wire frame_operation = (child_op == 4 && child_target == 0) ||
        ((child_op == 6 || child_op == 7) && child_target == 0) ||
        (child_op == 6 && child_target >= 2) ||
        (child_op == 3 && (child_target == 0 || child_target == 3));
    assign work_req_valid = (child_selected && child_work_valid) ||
        (fold_selected && fold_work_valid) ||
        (rst_n && (state == RELEASE_SEND || state == SNAPSHOT_SEND ||
            state == OUTPUT_SEND));
    assign work_rsp_ready = (child_selected && child_work_rsp_ready) ||
        (fold_selected && fold_work_rsp_ready) ||
        (rst_n && (state == RELEASE_WAIT || state == SNAPSHOT_WAIT ||
            state == OUTPUT_WAIT));
    always @* begin
        work_req_op = 0;
        work_req_domain = 0;
        work_req_target = 0;
        work_req_token = 0;
        work_req_layer = 0;
        work_req_length = 0;
        work_req_component = 0;
        work_req_slot = 0;
        work_req_bank = 0;
        work_req_scalar_index = 0;
        work_req_data = 0;
        if (rst_n) begin
            if (child_selected) begin
                work_req_op = child_op;
                work_req_domain = child_domain;
                work_req_target = child_target;
                work_req_token = frame_operation ? query_hold : child_token;
                work_req_layer = child_layer;
                work_req_length = child_length;
                work_req_component = child_component;
                work_req_slot = child_slot;
                work_req_bank = child_work_bank;
                work_req_scalar_index = child_scalar;
                work_req_data = child_data;
            end else if (fold_selected) begin
                work_req_op = fold_op;
                work_req_domain = fold_domain;
                work_req_target = fold_target;
                work_req_token = fold_token;
                work_req_layer = fold_layer;
                work_req_length = fold_length;
                work_req_component = fold_component;
                work_req_slot = fold_slot;
                work_req_bank = fold_bank;
                work_req_scalar_index = fold_scalar;
                work_req_data = fold_data;
            end else begin
                work_req_domain = 2;
                work_req_token = query_hold;
                work_req_layer = layer_hold;
                work_req_length = 1024;
                work_req_slot = slot_hold;
                if (state == SNAPSHOT_SEND || state == SNAPSHOT_WAIT ||
                    state == SNAPSHOT_REGISTER || state == RESTORE_CHECK) begin
                    work_req_op = snapshot_restore ? 7 : 6;
                    work_req_scalar_index = snapshot_word ? 8'd33 : 8'd32;
                    work_req_data = snapshot_word ? accumulator_hold :
                        {6'd0, low_hold, channel_hold};
                end else if (state == OUTPUT_SEND || state == OUTPUT_WAIT ||
                    state == OUTPUT_REGISTER) begin
                    work_req_op = 6;
                    work_req_target = 2;
                    work_req_bank = 1;
                    work_req_component = {2'd0, channel_hold} - 12'd1;
                    work_req_data = output_pair;
                end else if (state == RELEASE_SEND || state == RELEASE_WAIT ||
                    state == RELEASE_REGISTER) begin
                    work_req_op = 7;
                    work_req_target = 2;
                    work_req_component = 0;
                    work_req_bank = release_kind == 2;
                    work_req_scalar_index = release_kind == 1 ? 8'd0 : 8'd1;
                end
            end
        end
    end
    assign cmd_valid = (child_selected && child_cmd_valid) ||
        (fold_selected && fold_cmd_valid);
    assign cmd_write = 0;
    assign cmd_addr = child_selected ? child_addr : (fold_selected ? fold_addr : 64'd0);
    assign cmd_wdata = 0;
    assign result_ready = (child_selected && child_result_ready) ||
        (fold_selected && fold_result_ready);
    assign start_ready = rst_n && state == IDLE;
    assign done_valid = rst_n && state == RESPONSE;
    assign done_error = rst_n ? error_hold : 4'd0;
    assign done_yield = done_valid && yield_hold && error_hold == 0;
    assign done_history_count = done_valid && !done_yield && error_hold == 0 ?
        3'd1 : 3'd0;
    assign done_continuation = done_yield ? yielded_continuation : 160'd0;
    assign done_dependency_domain = done_yield ? yielded_domain : 2'd0;
    assign done_dependency_layer = done_yield ? yielded_layer : 8'd0;
    assign done_dependency_token = done_yield ? yielded_token : 32'd0;
    assign done_dependency_length = done_yield ? yielded_length : 12'd0;
    assign source_read_event = child_source_event || fold_source_event;
    assign source_read_bytes = child_source_bytes + fold_source_bytes;
    assign projection_event = child_projection_event || fold_projection_event;
    assign projection_bytes = child_projection_bytes + fold_projection_bytes;
    wire fold_weight_event = fold_selected && fold_cmd_valid && cmd_ready;
    assign weight_read_event = child_weight_event || fold_weight_event;
    assign weight_read_bytes = child_weight_bytes + (fold_weight_event ? 32'd4 : 32'd0);
    assign vector_live_bytes = rst_n ? child_live + fold_live : 64'd0;
    assign vector_physical_bytes = rst_n ? child_physical + fold_physical : 64'd0;
    assign history_replay_event = rst_n && state == CHILD_START && child_ready &&
        child_mode != 1 && distance_hold != 0;
    assign history_replay_bytes = history_replay_event ? 32'd2048 : 32'd0;
    assign nested_controller_bytes = !rst_n ? 64'd0 :
        residual_control + heads_control + binding_control + head_control +
        heads_nested_control + post_control + post_nested_control + fold_control + fold_nested;
    localparam integer CONTROLLER_BITS =
        $bits(state) + $bits(model_hold) + $bits(precision_hold) + $bits(mode_hold) +
        $bits(child_mode) + $bits(dependency_domain_hold) + $bits(yielded_domain) +
        $bits(generation_hold) + $bits(frames_hold) + $bits(query_hold) +
        $bits(dependency_token_hold) + $bits(yielded_token) +
        $bits(layer_hold) + $bits(dependency_layer_hold) + $bits(yielded_layer) +
        $bits(slot_hold) + $bits(dependency_slot_hold) + $bits(dependency_length_hold) +
        $bits(yielded_length) + $bits(distance_hold) +
        $bits(audio_hold) + $bits(weights_hold) + $bits(continuation_hold) +
        $bits(child_continuation) + $bits(yielded_continuation) +
        $bits(dependency_valid_hold) + $bits(child_yield_hold) + $bits(child_bank_hold) +
        $bits(yield_hold) + $bits(error_hold) +
        $bits(child_error_hold) + $bits(work_error_hold) + $bits(release_kind) +
        $bits(channel_hold) + $bits(low_hold) + $bits(accumulator_hold) +
        $bits(fold_data_hold) + $bits(output_pair) + $bits(snapshot_data) +
        $bits(snapshot_restore) + $bits(snapshot_word);
    assign controller_bytes = rst_n ? (CONTROLLER_BITS + 7) >> 3 : 64'd0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            model_hold <= 0;
            precision_hold <= 0;
            mode_hold <= 0;
            child_mode <= 0;
            dependency_domain_hold <= 0;
            yielded_domain <= 0;
            generation_hold <= 0;
            frames_hold <= 0;
            query_hold <= 0;
            dependency_token_hold <= 0;
            yielded_token <= 0;
            layer_hold <= 0;
            dependency_layer_hold <= 0;
            yielded_layer <= 0;
            slot_hold <= 0;
            dependency_slot_hold <= 0;
            dependency_length_hold <= 0;
            yielded_length <= 0;
            distance_hold <= 0;
            audio_hold <= 0;
            weights_hold <= 0;
            continuation_hold <= 0;
            child_continuation <= 0;
            yielded_continuation <= 0;
            dependency_valid_hold <= 0;
            child_yield_hold <= 0;
            child_bank_hold <= 0;
            yield_hold <= 0;
            error_hold <= 0;
            child_error_hold <= 0;
            work_error_hold <= 0;
            release_kind <= 0;
            channel_hold <= 0;
            low_hold <= 0;
            accumulator_hold <= 0;
            fold_data_hold <= 0;
            output_pair <= 0;
            snapshot_data <= 0;
            snapshot_restore <= 0;
            snapshot_word <= 0;
        end else begin
            case (state)
                IDLE: if (start_valid && start_ready) begin
                    model_hold <= model;
                    precision_hold <= precision;
                    mode_hold <= mode;
                    child_mode <= mode;
                    generation_hold <= generation;
                    frames_hold <= frames;
                    query_hold <= query_token;
                    layer_hold <= frame_layer;
                    slot_hold <= frame_slot;
                    audio_hold <= audio_base;
                    weights_hold <= audio_weights_base;
                    continuation_hold <= continuation;
                    child_continuation <= 0;
                    dependency_valid_hold <= dependency_valid;
                    dependency_domain_hold <= dependency_domain;
                    dependency_layer_hold <= dependency_layer;
                    dependency_token_hold <= dependency_token;
                    dependency_length_hold <= dependency_length;
                    dependency_slot_hold <= dependency_slot;
                    distance_hold <= query_token < 4 ? query_token[2:0] : 3'd4;
                    release_kind <= 0;
                    error_hold <= 0;
                    child_error_hold <= 0;
                    work_error_hold <= 0;
                    child_yield_hold <= 0;
                    child_bank_hold <= 0;
                    yield_hold <= 0;
                    yielded_domain <= 0;
                    yielded_layer <= 0;
                    yielded_token <= 0;
                    yielded_length <= 0;
                    yielded_continuation <= 0;
                    channel_hold <= 0;
                    low_hold <= 0;
                    accumulator_hold <= 0;
                    fold_data_hold <= 0;
                    output_pair <= 0;
                    snapshot_data <= 0;
                    snapshot_restore <= 0;
                    snapshot_word <= 0;
                    state <= VALIDATE;
                end
                VALIDATE: begin
                    if ((model_hold != 1 && model_hold != 2) || precision_hold > 1) begin
                        error_hold <= 6;
                        state <= PUBLISH;
                    end else if (generation_hold == 0 || frames_hold == 0 ||
                        frames_hold > 131072 || query_hold >= tokens_hold ||
                        layer_hold == 0 || layer_hold > 12 ||
                        audio_hold[1:0] != 0 || weights_hold[1:0] != 0) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else if (mode_hold > 2 ||
                        (mode_hold != 1 && continuation_hold != 0) ||
                        (mode_hold == 1 && !input_continuation_tag && !head_continuation_tag) ||
                        (mode_hold == 2 && (!dependency_valid_hold ||
                            dependency_domain_hold != 2 || dependency_layer_hold != logical_layer ||
                            dependency_token_hold != query_hold || dependency_length_hold != 1024 ||
                            dependency_slot_hold >= 16))) begin
                        error_hold <= 7;
                        state <= PUBLISH;
                    end else begin
                        if (mode_hold == 1) begin
                            if (input_continuation_tag) begin
                                distance_hold <= continuation_hold[37:35];
                                child_continuation <= {INPUT_MAGIC, 128'd0};
                            end else begin
                                distance_hold <= resumed_distance[2:0];
                                child_continuation <= continuation_hold;
                            end
                        end
                        if (mode_hold == 1) begin
                            snapshot_restore <= 1;
                            snapshot_word <= 0;
                            state <= SNAPSHOT_SEND;
                        end else
                            state <= TAP_SETUP;
                    end
                end
                CHILD_START: if (child_ready)
                    state <= CHILD_WAIT;
                CHILD_WAIT: if (child_valid) begin
                    child_error_hold <= child_error;
                    child_yield_hold <= child_yield;
                    child_bank_hold <= child_bank;
                    yielded_domain <= child_dependency_domain;
                    yielded_layer <= child_dependency_layer;
                    yielded_token <= child_dependency_token;
                    yielded_length <= child_dependency_length;
                    yielded_continuation <= child_done_continuation;
                    state <= CHILD_CHECK;
                end
                CHILD_CHECK: begin
                    if (child_error_hold != 0) begin
                        error_hold <= child_error_hold;
                        state <= PUBLISH;
                    end else if (child_yield_hold) begin
                        snapshot_restore <= 0;
                        snapshot_word <= 0;
                        if (yielded_domain != 2 || yielded_layer != logical_layer ||
                            yielded_token >= tokens_hold || yielded_length != 1024)
                            error_hold <= 7;
                        else if (yielded_continuation == {INPUT_MAGIC, 128'd0}) begin
                            if (yielded_token != historical_token)
                                error_hold <= 7;
                            else begin
                                yielded_continuation <= input_yield_descriptor;
                                yield_hold <= 1;
                            end
                        end else if ((yielded_continuation[159:128] != HEAD_MAGIC &&
                                yielded_continuation[159:128] != FINAL_BIND_MAGIC) ||
                            (yielded_continuation[159:128] == FINAL_BIND_MAGIC &&
                                (yielded_continuation[37:35] != 0 ||
                                    yielded_token != historical_token)) ||
                            yielded_continuation[127:96] != generation_hold ||
                            yielded_continuation[95:64] != historical_token ||
                            yielded_continuation[63:56] != layer_hold ||
                            yielded_continuation[55:50] != slot_hold ||
                            yielded_continuation[49:48] != model_hold ||
                            yielded_continuation[47:46] != precision_hold ||
                            yielded_continuation[45:38] != logical_layer ||
                            yielded_continuation[34:0] != 0)
                            error_hold <= 7;
                        else
                            yield_hold <= 1;
                        state <= SNAPSHOT_SEND;
                    end else if (child_bank_hold) begin
                        error_hold <= 7;
                        state <= PUBLISH;
                    end else begin
                        release_kind <= 0;
                        state <= RELEASE_SEND;
                    end
                end
                TAP_SETUP: begin
                    child_continuation <= 0;
                    if (dependency_valid_hold && dependency_domain_hold == 2 &&
                        dependency_layer_hold == logical_layer &&
                        dependency_token_hold == historical_token &&
                        dependency_length_hold == 1024)
                        child_mode <= 2;
                    else
                        child_mode <= 0;
                    state <= CHILD_START;
                end
                FOLD_START: if (fold_ready)
                    state <= FOLD_WAIT;
                FOLD_WAIT: if (fold_valid) begin
                    work_error_hold <= fold_error;
                    fold_data_hold <= fold_data;
                    state <= FOLD_CHECK;
                end
                FOLD_CHECK: begin
                    if (work_error_hold != 0) begin
                        error_hold <= work_error_hold;
                        state <= PUBLISH;
                    end else if (distance_hold == 0) begin
                        if (fold_data_hold[31:16] != 0) begin
                            error_hold <= 7;
                            state <= PUBLISH;
                        end else if (!channel_hold[0]) begin
                            low_hold <= fold_data_hold[15:0];
                            release_kind <= 1;
                            state <= RELEASE_SEND;
                        end else begin
                            output_pair <= {fold_data_hold[15:0], low_hold};
                            state <= OUTPUT_SEND;
                        end
                    end else begin
                        accumulator_hold <= fold_data_hold;
                        release_kind <= 1;
                        state <= RELEASE_SEND;
                    end
                end
                RELEASE_SEND: if (work_req_ready)
                    state <= RELEASE_WAIT;
                RELEASE_WAIT: if (work_rsp_valid) begin
                    work_error_hold <= work_rsp_error;
                    state <= RELEASE_REGISTER;
                end
                RELEASE_REGISTER: begin
                    if (work_error_hold != 0) begin
                        error_hold <= work_error_hold;
                        state <= PUBLISH;
                    end else if (release_kind == 0)
                        state <= FOLD_START;
                    else if (release_kind == 1)
                        state <= ADVANCE;
                    else
                        state <= PUBLISH;
                end
                ADVANCE: begin
                    if (distance_hold == 0) begin
                        channel_hold <= channel_hold + 1'b1;
                        distance_hold <= last_distance;
                        accumulator_hold <= 0;
                    end else
                        distance_hold <= distance_hold - 3'd1;
                    child_mode <= 0;
                    child_continuation <= 0;
                    state <= TAP_SETUP;
                end
                OUTPUT_SEND: if (work_req_ready)
                    state <= OUTPUT_WAIT;
                OUTPUT_WAIT: if (work_rsp_valid) begin
                    work_error_hold <= work_rsp_error;
                    state <= OUTPUT_REGISTER;
                end
                OUTPUT_REGISTER: begin
                    if (work_error_hold != 0) begin
                        error_hold <= work_error_hold;
                        state <= PUBLISH;
                    end else begin
                        low_hold <= 0;
                        if (channel_hold == 1023)
                            state <= PUBLISH;
                        else begin
                            release_kind <= 1;
                            state <= RELEASE_SEND;
                        end
                    end
                end
                SNAPSHOT_SEND: if (work_req_ready)
                    state <= SNAPSHOT_WAIT;
                SNAPSHOT_WAIT: if (work_rsp_valid) begin
                    snapshot_data <= work_rsp_data;
                    work_error_hold <= work_rsp_error;
                    state <= SNAPSHOT_REGISTER;
                end
                SNAPSHOT_REGISTER: begin
                    if (work_error_hold != 0 ||
                        (snapshot_restore && !snapshot_word && snapshot_data[31:26] != 0)) begin
                        error_hold <= work_error_hold != 0 ? work_error_hold : 4'd7;
                        yield_hold <= 0;
                        state <= PUBLISH;
                    end else begin
                        if (snapshot_restore) begin
                            if (snapshot_word)
                                accumulator_hold <= snapshot_data;
                            else begin
                                channel_hold <= snapshot_data[9:0];
                                low_hold <= snapshot_data[25:10];
                            end
                        end
                        if (!snapshot_word) begin
                            snapshot_word <= 1;
                            state <= SNAPSHOT_SEND;
                        end else if (snapshot_restore)
                            state <= RESTORE_CHECK;
                        else
                            state <= PUBLISH;
                    end
                end
                RESTORE_CHECK: begin
                    if ((!channel_hold[0] && low_hold != 0) ||
                        (distance_hold == last_distance && accumulator_hold != 0)) begin
                        error_hold <= 7;
                        state <= PUBLISH;
                    end else
                        state <= CHILD_START;
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
        end
    end
endmodule
