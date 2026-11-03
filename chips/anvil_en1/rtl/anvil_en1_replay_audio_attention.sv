module anvil_en1_replay_audio_attention (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] model, precision,
    input wire [31:0] generation, frames, query_token,
    input wire [7:0] layer, frame_layer,
    input wire [2:0] head,
    input wire [5:0] frame_slot,
    input wire [63:0] audio_base, audio_weights_base,
    input wire resume_valid,
    input wire [159:0] continuation,
    output wire need_valid,
    input wire need_ready,
    input wire [1:0] need_action,
    output wire [1:0] need_model, need_precision, need_selector,
    output wire [31:0] need_generation, need_token,
    output wire [7:0] need_layer,
    output wire [2:0] need_head,
    output wire [9:0] need_component,
    output wire source_valid,
    input wire source_ready,
    output wire [1:0] source_model,
    output wire [7:0] source_layer,
    output wire [31:0] source_generation, source_token, source_index,
    input wire source_rsp_valid,
    output wire source_rsp_ready,
    input wire [15:0] source_rsp_data,
    input wire source_rsp_error,
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
    output wire [7:0] done_dependency_layer,
    output wire [31:0] done_dependency_token,
    output wire input_read_event, projection_event,
    output wire [31:0] input_read_bytes, projection_bytes,
    output wire intermediate_event,
    output wire [31:0] intermediate_bytes,
    output wire source_read_event, weight_read_event,
    output wire [31:0] source_read_bytes, weight_read_bytes,
    output wire [63:0] vector_live_bytes, vector_physical_bytes,
    output wire [63:0] pre_controller_bytes, pre_nested_controller_bytes,
    output wire [63:0] controller_bytes, executor_controller_bytes, head_controller_bytes,
    output wire [63:0] block_controller_bytes, input_controller_bytes,
    output wire [63:0] tile_controller_bytes, clipped_controller_bytes, clamp_controller_bytes,
    output wire [63:0] position_controller_bytes, softplus_controller_bytes
);
    localparam [3:0] IDLE = 0, VALIDATE = 1,
        RESTORE_SEND = 2, RESTORE_WAIT = 3, RESTORE_REGISTER = 4,
        ENGINE_START = 5, ENGINE_RUN = 6, ENGINE_DRAIN = 7,
        SAVE_SEND = 8, SAVE_WAIT = 9, SAVE_REGISTER = 10,
        PUBLISH = 11, RESPONSE = 12, INPUT_START = 13,
        INPUT_RUN = 14, INPUT_CHECK = 15;
    localparam [2:0] S_IDLE = 0, S_VALIDATE = 1, S_READ = 2,
        S_CAPTURE = 3, S_RESPONSE = 4;
    localparam [31:0] MAGIC = 32'h454e3141;
    reg [3:0] state;
    reg [4:0] word_index;
    reg [1:0] model_hold, precision_hold;
    reg [31:0] generation_hold, frames_hold, tokens_hold, query_hold, dependency_token_hold;
    reg [7:0] layer_hold, frame_layer_hold;
    reg [2:0] head_hold;
    reg [5:0] slot_hold;
    reg [63:0] audio_hold, weights_hold;
    reg [159:0] continuation_hold;
    reg [1023:0] checkpoint_hold;
    reg resume_hold, yield_hold, decision_seen, checkpoint_seen;
    reg [31:0] scalar_hold;
    reg [3:0] scalar_error_hold, error_hold;
    reg [2:0] source_state;
    reg [31:0] cache_token, rebuild_token, raw_received, norm_received;
    reg [31:0] source_index_hold;
    reg cache_allocated, cache_visible, receive_bad, source_tag_bad;
    reg [15:0] cache_q, cache_data_hold;
    reg [3:0] input_error_hold, cache_error_hold, first_source_error;
    (* ramstyle = "M20K", nomem2reg *) reg [15:0] normalized [0:1023];
    wire [159:0] outer = {MAGIC, generation_hold, query_hold,
        frame_layer_hold, slot_hold, model_hold, precision_hold,
        layer_hold, head_hold, 35'd0};
    wire outer_matches = continuation_hold == outer;
    wire run = rst_n && state == ENGINE_RUN;
    wire engine_selected = rst_n &&
        (state == ENGINE_START || state == ENGINE_RUN || state == ENGINE_DRAIN);
    wire engine_ready, engine_valid, engine_yield, engine_checkpoint_valid;
    wire engine_need_valid;
    wire [1023:0] engine_checkpoint;
    wire [3:0] engine_error;
    wire [1:0] engine_need_model, engine_need_precision, engine_need_selector;
    wire [31:0] engine_need_generation, engine_need_token;
    wire [7:0] engine_need_layer;
    wire [2:0] engine_need_head;
    wire [9:0] engine_need_component;
    wire need_tag_good = engine_need_model == model_hold &&
        engine_need_precision == precision_hold && engine_need_generation == generation_hold &&
        engine_need_layer == layer_hold && engine_need_head == head_hold &&
        engine_need_selector <= 3 && engine_need_component < 128 &&
        !engine_need_component[0] &&
        (engine_need_selector == 3 ? engine_need_token <= 12 : engine_need_token < tokens_hold);
    wire cache_hit = cache_visible && cache_token == engine_need_token;
    wire local_need = engine_need_selector == 3 || cache_hit;
    wire outward_need = run && engine_need_valid && need_tag_good &&
        error_hold == 0 && !local_need;
    wire legal_action = need_action <= 2;
    wire [1:0] action = !need_tag_good || error_hold != 0 ? 2'd2 :
        (local_need ? 2'd0 : (legal_action ? need_action : 2'd2));
    wire engine_need_ready = run &&
        (!need_tag_good || error_hold != 0 || local_need ||
            (need_ready && action != 0));
    wire engine_source_valid, engine_source_rsp_ready, engine_cmd_valid, engine_result_ready;
    wire [1:0] engine_source_model;
    wire [7:0] engine_source_layer;
    wire [31:0] engine_source_generation, engine_source_token, engine_source_index;
    wire engine_output_valid, engine_output_last;
    wire engine_weight_event;
    wire [31:0] engine_weight_bytes;
    wire [9:0] engine_output_index;
    wire [15:0] engine_output_data;
    wire [63:0] engine_addr;
    wire pre_selected = rst_n && (state == INPUT_START || state == INPUT_RUN);
    wire pre_ready, pre_valid, pre_cmd_valid, pre_result_ready;
    wire pre_source_valid, pre_source_rsp_ready;
    wire [1:0] pre_source_model;
    wire [7:0] pre_source_layer;
    wire [31:0] pre_source_generation, pre_source_token, pre_source_index;
    wire pre_output_valid, pre_output_kind, pre_output_last;
    wire [31:0] pre_output_index;
    wire [15:0] pre_output_data;
    wire [63:0] pre_addr, pre_live, pre_physical;
    wire [3:0] pre_error;
    wire [63:0] pre_norm_control, pre_clamp_control, pre_ff_control;
    wire [63:0] pre_ff_norm_control, pre_ff_clamp_control, pre_mlp_control;
    wire [63:0] pre_down_control, pre_down_clamp_control;
    wire [63:0] pre_inner_control, pre_inner_clamp_control;
    wire pre_beat_good = pre_output_kind ?
        (raw_received == 1024 && norm_received < 1024 &&
            pre_output_index == norm_received &&
            pre_output_last == (norm_received == 1023)) :
        (norm_received == 0 && raw_received < 1024 &&
            pre_output_index == raw_received &&
            pre_output_last == (raw_received == 1023));
    anvil_en1_audio_pre_attention pre_attention (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == INPUT_START), .start_ready(pre_ready),
        .model(model_hold), .precision(precision_hold), .layer(layer_hold),
        .generation(generation_hold), .token(rebuild_token),
        .audio_weights_base(weights_hold),
        .source_valid(pre_source_valid), .source_ready(pre_selected && source_ready),
        .source_model(pre_source_model), .source_layer(pre_source_layer),
        .source_generation(pre_source_generation), .source_token(pre_source_token),
        .source_index(pre_source_index),
        .source_rsp_valid(pre_selected && source_rsp_valid),
        .source_rsp_ready(pre_source_rsp_ready),
        .source_rsp_data(source_rsp_data), .source_rsp_error(source_rsp_error),
        .cmd_valid(pre_cmd_valid), .cmd_ready(pre_selected && cmd_ready),
        .cmd_write(), .cmd_addr(pre_addr), .cmd_wdata(),
        .result_valid(pre_selected && result_valid), .result_ready(pre_result_ready),
        .result_data(result_data), .result_error(result_error),
        .output_valid(pre_output_valid), .output_ready(rst_n && state == INPUT_RUN),
        .output_kind(pre_output_kind), .output_index(pre_output_index),
        .output_data(pre_output_data), .output_last(pre_output_last),
        .done_valid(pre_valid),
        .done_ready(rst_n && state == INPUT_RUN && !pre_output_valid),
        .done_error(pre_error),
        .intermediate_event(intermediate_event), .intermediate_bytes(intermediate_bytes),
        .vector_live_bytes(pre_live), .vector_physical_bytes(pre_physical),
        .controller_bytes(pre_controller_bytes), .norm_controller_bytes(pre_norm_control),
        .clamp_controller_bytes(pre_clamp_control), .ff_controller_bytes(pre_ff_control),
        .ff_norm_controller_bytes(pre_ff_norm_control),
        .ff_clamp_controller_bytes(pre_ff_clamp_control),
        .mlp_controller_bytes(pre_mlp_control), .down_controller_bytes(pre_down_control),
        .down_clamp_controller_bytes(pre_down_clamp_control),
        .inner_controller_bytes(pre_inner_control),
        .inner_clamp_controller_bytes(pre_inner_clamp_control)
    );
    anvil_en1_audio_attention_execute #(.REPLAY(1)) executor (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == ENGINE_START), .start_ready(engine_ready),
        .model(model_hold), .precision(precision_hold), .generation(generation_hold),
        .frames(frames_hold), .query_token(query_hold), .layer(layer_hold), .head(head_hold),
        .audio_base(audio_hold), .audio_weights_base(weights_hold),
        .resume_valid(resume_hold), .resume_checkpoint(checkpoint_hold),
        .need_valid(engine_need_valid), .need_ready(engine_need_ready), .need_action(action),
        .need_model(engine_need_model), .need_precision(engine_need_precision),
        .need_selector(engine_need_selector), .need_generation(engine_need_generation),
        .need_token(engine_need_token), .need_layer(engine_need_layer),
        .need_head(engine_need_head), .need_component(engine_need_component),
        .checkpoint_valid(engine_checkpoint_valid), .checkpoint_ready(run),
        .checkpoint_data(engine_checkpoint),
        .source_valid(engine_source_valid),
        .source_ready(engine_selected && source_state == S_IDLE),
        .source_model(engine_source_model), .source_layer(engine_source_layer),
        .source_generation(engine_source_generation), .source_token(engine_source_token),
        .source_index(engine_source_index),
        .source_rsp_valid(engine_selected && source_state == S_RESPONSE),
        .source_rsp_ready(engine_source_rsp_ready),
        .source_rsp_data(cache_data_hold), .source_rsp_error(cache_error_hold != 0),
        .cmd_valid(engine_cmd_valid), .cmd_ready(engine_selected && cmd_ready),
        .cmd_write(), .cmd_addr(engine_addr), .cmd_wdata(),
        .result_valid(engine_selected && result_valid), .result_ready(engine_result_ready),
        .result_data(result_data), .result_error(result_error),
        .output_valid(engine_output_valid), .output_ready(run && output_ready),
        .output_index(engine_output_index), .output_data(engine_output_data),
        .output_last(engine_output_last), .done_valid(engine_valid),
        .done_ready(rst_n && (state == ENGINE_RUN || state == ENGINE_DRAIN)),
        .done_yield(engine_yield), .done_error(engine_error),
        .input_read_event(input_read_event), .input_read_bytes(input_read_bytes),
        .weight_read_event(engine_weight_event), .weight_read_bytes(engine_weight_bytes),
        .projection_event(projection_event), .projection_bytes(projection_bytes),
        .controller_bytes(executor_controller_bytes), .head_controller_bytes(head_controller_bytes),
        .block_controller_bytes(block_controller_bytes),
        .input_controller_bytes(input_controller_bytes),
        .tile_controller_bytes(tile_controller_bytes),
        .clipped_controller_bytes(clipped_controller_bytes),
        .clamp_controller_bytes(clamp_controller_bytes),
        .position_controller_bytes(position_controller_bytes),
        .softplus_controller_bytes(softplus_controller_bytes)
    );

    assign start_ready = rst_n && state == IDLE;
    assign need_valid = outward_need;
    assign need_model = rst_n ? engine_need_model : 2'd0;
    assign need_precision = rst_n ? engine_need_precision : 2'd0;
    assign need_selector = rst_n ? engine_need_selector : 2'd0;
    assign need_generation = rst_n ? engine_need_generation : 32'd0;
    assign need_token = rst_n ? engine_need_token : 32'd0;
    assign need_layer = rst_n ? engine_need_layer : 8'd0;
    assign need_head = rst_n ? engine_need_head : 3'd0;
    assign need_component = rst_n ? engine_need_component : 10'd0;
    assign source_valid = pre_selected && pre_source_valid;
    assign source_rsp_ready = pre_selected && pre_source_rsp_ready;
    assign source_model = pre_selected ? pre_source_model : 2'd0;
    assign source_layer = pre_selected ? pre_source_layer : 8'd0;
    assign source_generation = pre_selected ? pre_source_generation : 32'd0;
    assign source_token = pre_selected ? pre_source_token : 32'd0;
    assign source_index = pre_selected ? pre_source_index : 32'd0;
    assign cmd_valid = (engine_selected && engine_cmd_valid) ||
        (pre_selected && pre_cmd_valid);
    assign cmd_write = 0;
    assign cmd_addr = engine_selected ? engine_addr : (pre_selected ? pre_addr : 64'd0);
    assign cmd_wdata = 0;
    assign result_ready = (engine_selected && engine_result_ready) ||
        (pre_selected && pre_result_ready);
    assign source_read_event = pre_selected && pre_source_valid && source_ready;
    assign source_read_bytes = source_read_event ? 32'd2 : 32'd0;
    assign weight_read_event = engine_weight_event ||
        (pre_selected && pre_cmd_valid && cmd_ready);
    assign weight_read_bytes = engine_weight_bytes +
        ((pre_selected && pre_cmd_valid && cmd_ready) ? 32'd4 : 32'd0);
    assign output_valid = run && engine_output_valid;
    assign output_index = rst_n ? engine_output_index : 10'd0;
    assign output_data = rst_n ? engine_output_data : 16'd0;
    assign output_last = output_valid && engine_output_last;
    assign work_req_valid = rst_n && (state == SAVE_SEND || state == RESTORE_SEND);
    assign work_req_op = !rst_n ? 3'd0 : (state == SAVE_SEND ? 3'd6 : 3'd7);
    assign work_req_domain = rst_n ? 2'd2 : 2'd0;
    assign work_req_target = 0;
    assign work_req_token = rst_n ? query_hold : 32'd0;
    assign work_req_layer = rst_n ? frame_layer_hold : 8'd0;
    assign work_req_length = rst_n ? 12'd1024 : 12'd0;
    assign work_req_component = 0;
    assign work_req_slot = rst_n ? slot_hold : 6'd0;
    assign work_req_bank = 0;
    assign work_req_scalar_index = rst_n ? {3'd0, word_index} + 8'd8 : 8'd0;
    assign work_req_data = rst_n && state == SAVE_SEND ?
        checkpoint_hold[{word_index, 5'd0} +: 32] : 32'd0;
    assign work_rsp_ready = rst_n && (state == SAVE_WAIT || state == RESTORE_WAIT);
    assign done_valid = rst_n && state == RESPONSE;
    assign done_error = rst_n ? error_hold : 4'd0;
    assign done_yield = done_valid && yield_hold && error_hold == 0;
    assign done_continuation = done_yield ? outer : 160'd0;
    assign done_dependency_layer = done_yield ? layer_hold : 8'd0;
    assign done_dependency_token = done_yield ? dependency_token_hold : 32'd0;
    localparam integer CONTROLLER_BITS =
        $bits(state) + $bits(word_index) + $bits(model_hold) + $bits(precision_hold) +
        $bits(generation_hold) + $bits(frames_hold) + $bits(tokens_hold) +
        $bits(query_hold) + $bits(dependency_token_hold) + $bits(layer_hold) +
        $bits(frame_layer_hold) + $bits(head_hold) + $bits(slot_hold) +
        $bits(audio_hold) + $bits(weights_hold) + $bits(continuation_hold) +
        $bits(checkpoint_hold) + $bits(resume_hold) + $bits(yield_hold) +
        $bits(decision_seen) + $bits(checkpoint_seen) + $bits(scalar_hold) +
        $bits(scalar_error_hold) + $bits(error_hold) +
        $bits(source_state) + $bits(cache_token) + $bits(rebuild_token) +
        $bits(raw_received) + $bits(norm_received) + $bits(source_index_hold) +
        $bits(cache_allocated) + $bits(cache_visible) + $bits(receive_bad) +
        $bits(source_tag_bad) + $bits(cache_q) + $bits(cache_data_hold) +
        $bits(input_error_hold) + $bits(cache_error_hold) + $bits(first_source_error);
    assign controller_bytes = rst_n ? (CONTROLLER_BITS + 7) >> 3 : 64'd0;
    assign vector_live_bytes = !rst_n ? 64'd0 :
        (cache_allocated ? 64'd2048 : 64'd0) + pre_live;
    assign vector_physical_bytes = rst_n ? 64'd2048 + pre_physical : 64'd0;
    assign pre_nested_controller_bytes = !rst_n ? 64'd0 :
        pre_norm_control + pre_clamp_control + pre_ff_control +
        pre_ff_norm_control + pre_ff_clamp_control + pre_mlp_control +
        pre_down_control + pre_down_clamp_control +
        pre_inner_control + pre_inner_clamp_control;

    always @(posedge clk) begin
        if (rst_n && state == INPUT_RUN && pre_output_valid &&
            pre_output_kind && pre_beat_good && !receive_bad)
            normalized[pre_output_index[9:0]] <= pre_output_data;
        if (rst_n && source_state == S_READ)
            cache_q <= normalized[source_index_hold[9:0]];
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            source_state <= S_IDLE;
            source_index_hold <= 0;
            source_tag_bad <= 0;
            cache_data_hold <= 0;
            cache_error_hold <= 0;
            first_source_error <= 0;
        end else begin
            if (start_valid && start_ready)
                first_source_error <= 0;
            case (source_state)
                S_IDLE: if (engine_selected && engine_source_valid) begin
                    source_index_hold <= engine_source_index;
                    source_tag_bad <= engine_source_model != model_hold ||
                        engine_source_generation != generation_hold ||
                        engine_source_layer != layer_hold ||
                        engine_source_token != cache_token;
                    cache_data_hold <= 0;
                    cache_error_hold <= 0;
                    source_state <= S_VALIDATE;
                end
                S_VALIDATE: begin
                    if (source_tag_bad || !cache_visible || source_index_hold >= 1024) begin
                        cache_error_hold <= 7;
                        if (first_source_error == 0)
                            first_source_error <= 7;
                        source_state <= S_RESPONSE;
                    end else
                        source_state <= S_READ;
                end
                S_READ: source_state <= S_CAPTURE;
                S_CAPTURE: begin
                    cache_data_hold <= cache_q;
                    source_state <= S_RESPONSE;
                end
                S_RESPONSE: if (engine_selected && engine_source_rsp_ready)
                    source_state <= S_IDLE;
                default: begin
                    cache_error_hold <= 7;
                    if (first_source_error == 0)
                        first_source_error <= 7;
                    source_state <= S_RESPONSE;
                end
            endcase
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            word_index <= 0;
            model_hold <= 0;
            precision_hold <= 0;
            generation_hold <= 0;
            frames_hold <= 0;
            tokens_hold <= 0;
            query_hold <= 0;
            dependency_token_hold <= 0;
            layer_hold <= 0;
            frame_layer_hold <= 0;
            head_hold <= 0;
            slot_hold <= 0;
            audio_hold <= 0;
            weights_hold <= 0;
            continuation_hold <= 0;
            checkpoint_hold <= 0;
            resume_hold <= 0;
            yield_hold <= 0;
            decision_seen <= 0;
            checkpoint_seen <= 0;
            scalar_hold <= 0;
            scalar_error_hold <= 0;
            error_hold <= 0;
            cache_token <= 0;
            rebuild_token <= 0;
            raw_received <= 0;
            norm_received <= 0;
            cache_allocated <= 0;
            cache_visible <= 0;
            receive_bad <= 0;
            input_error_hold <= 0;
        end else begin
            if (engine_need_valid && engine_need_ready && action == 1) begin
                dependency_token_hold <= engine_need_token;
                decision_seen <= 1;
            end
            case (state)
                IDLE: if (start_valid && start_ready) begin
                    model_hold <= model;
                    precision_hold <= precision;
                    generation_hold <= generation;
                    frames_hold <= frames;
                    tokens_hold <= (frames + 32'd3) >> 2;
                    query_hold <= query_token;
                    layer_hold <= layer;
                    frame_layer_hold <= frame_layer;
                    head_hold <= head;
                    slot_hold <= frame_slot;
                    audio_hold <= audio_base;
                    weights_hold <= audio_weights_base;
                    continuation_hold <= continuation;
                    checkpoint_hold <= 0;
                    resume_hold <= resume_valid;
                    yield_hold <= 0;
                    decision_seen <= 0;
                    checkpoint_seen <= 0;
                    dependency_token_hold <= 0;
                    word_index <= 0;
                    scalar_error_hold <= 0;
                    error_hold <= 0;
                    cache_token <= 0;
                    rebuild_token <= 0;
                    raw_received <= 0;
                    norm_received <= 0;
                    cache_allocated <= 0;
                    cache_visible <= 0;
                    receive_bad <= 0;
                    input_error_hold <= 0;
                    state <= VALIDATE;
                end
                VALIDATE: begin
                    if ((model_hold != 1 && model_hold != 2) || precision_hold > 1) begin
                        error_hold <= 6;
                        state <= PUBLISH;
                    end else if (generation_hold == 0 || frames_hold == 0 || frames_hold > 131072 ||
                        query_hold >= tokens_hold || layer_hold >= 12 ||
                        audio_hold[1:0] != 0 || weights_hold[1:0] != 0) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else if (frame_layer_hold == 0 || frame_layer_hold > 12 ||
                        {1'b0, layer_hold} + 9'd1 != {1'b0, frame_layer_hold} ||
                        (resume_hold && !outer_matches)) begin
                        error_hold <= 7;
                        state <= PUBLISH;
                    end else if (resume_hold)
                        state <= RESTORE_SEND;
                    else
                        state <= ENGINE_START;
                end
                RESTORE_SEND: if (work_req_ready)
                    state <= RESTORE_WAIT;
                RESTORE_WAIT: if (work_rsp_valid) begin
                    scalar_hold <= work_rsp_data;
                    scalar_error_hold <= work_rsp_error;
                    state <= RESTORE_REGISTER;
                end
                RESTORE_REGISTER: begin
                    if (scalar_error_hold != 0) begin
                        error_hold <= scalar_error_hold;
                        state <= PUBLISH;
                    end else begin
                        checkpoint_hold[{word_index, 5'd0} +: 32] <= scalar_hold;
                        if (word_index == 21)
                            state <= ENGINE_START;
                        else begin
                            word_index <= word_index + 1'b1;
                            state <= RESTORE_SEND;
                        end
                    end
                end
                ENGINE_START: if (engine_ready)
                    state <= ENGINE_RUN;
                ENGINE_RUN: begin
                    if (engine_checkpoint_valid) begin
                        checkpoint_hold <= engine_checkpoint;
                        checkpoint_seen <= 1;
                        if (!decision_seen || engine_checkpoint[1023:704] != 0)
                            error_hold <= 7;
                        state <= ENGINE_DRAIN;
                    end else if (engine_valid) begin
                        if (error_hold == 0) begin
                            if (first_source_error != 0)
                                error_hold <= first_source_error;
                            else if (engine_error != 0)
                                error_hold <= engine_error;
                            else if (engine_yield)
                                error_hold <= 7;
                        end
                        state <= PUBLISH;
                    end else if (outward_need && need_ready && action == 0) begin
                        rebuild_token <= engine_need_token;
                        cache_visible <= 0;
                        cache_allocated <= 0;
                        raw_received <= 0;
                        norm_received <= 0;
                        receive_bad <= 0;
                        input_error_hold <= 0;
                        state <= INPUT_START;
                    end
                end
                INPUT_START: if (pre_ready)
                    state <= INPUT_RUN;
                INPUT_RUN: begin
                    if (pre_output_valid) begin
                        if (!pre_beat_good)
                            receive_bad <= 1;
                        if (pre_output_kind) begin
                            if (pre_beat_good && !receive_bad)
                                cache_allocated <= 1;
                            if (norm_received < 1024)
                                norm_received <= norm_received + 1'b1;
                        end else if (raw_received < 1024)
                            raw_received <= raw_received + 1'b1;
                    end else if (pre_valid) begin
                        input_error_hold <= pre_error;
                        state <= INPUT_CHECK;
                    end
                end
                INPUT_CHECK: begin
                    if (input_error_hold != 0) begin
                        if (error_hold == 0)
                            error_hold <= input_error_hold;
                    end else if (receive_bad || raw_received != 1024 || norm_received != 1024) begin
                        if (error_hold == 0)
                            error_hold <= 7;
                    end else begin
                        cache_token <= rebuild_token;
                        cache_visible <= 1;
                    end
                    state <= ENGINE_RUN;
                end
                ENGINE_DRAIN: if (engine_valid) begin
                    if (engine_error != 0) begin
                        if (error_hold == 0)
                            error_hold <= engine_error;
                        state <= PUBLISH;
                    end else if (error_hold != 0 || !engine_yield || !checkpoint_seen ||
                        !decision_seen) begin
                        if (error_hold == 0)
                            error_hold <= 7;
                        state <= PUBLISH;
                    end else begin
                        word_index <= 0;
                        state <= SAVE_SEND;
                    end
                end
                SAVE_SEND: if (work_req_ready)
                    state <= SAVE_WAIT;
                SAVE_WAIT: if (work_rsp_valid) begin
                    scalar_error_hold <= work_rsp_error;
                    state <= SAVE_REGISTER;
                end
                SAVE_REGISTER: begin
                    if (scalar_error_hold != 0) begin
                        error_hold <= scalar_error_hold;
                        state <= PUBLISH;
                    end else if (word_index == 21) begin
                        yield_hold <= 1;
                        state <= PUBLISH;
                    end else begin
                        word_index <= word_index + 1'b1;
                        state <= SAVE_SEND;
                    end
                end
                PUBLISH: state <= RESPONSE;
                RESPONSE: if (done_ready) begin
                    cache_visible <= 0;
                    cache_allocated <= 0;
                    state <= IDLE;
                end
                default: begin
                    yield_hold <= 0;
                    error_hold <= 7;
                    state <= PUBLISH;
                end
            endcase
        end
    end
endmodule
