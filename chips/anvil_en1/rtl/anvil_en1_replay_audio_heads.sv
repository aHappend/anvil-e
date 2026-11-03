module anvil_en1_replay_audio_heads #(
    parameter integer COMPACT = 0,
    parameter integer DEFER_QUERY_BINDING = 0,
    parameter integer FINAL_FEEDFORWARD = 0
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
    output wire done_yield, done_bank,
    output wire [159:0] done_continuation,
    output wire [1:0] done_dependency_domain,
    output wire [7:0] done_dependency_layer,
    output wire [31:0] done_dependency_token,
    output wire [11:0] done_dependency_length,
    output wire input_read_event, projection_event, intermediate_event,
    output wire source_read_event, weight_read_event,
    output wire [31:0] input_read_bytes, projection_bytes, intermediate_bytes,
    output wire [31:0] source_read_bytes, weight_read_bytes,
    output wire [63:0] vector_live_bytes, vector_physical_bytes,
    output wire [63:0] controller_bytes, binding_controller_bytes,
    output wire [63:0] head_controller_bytes, nested_controller_bytes
);
    localparam [4:0] IDLE = 0, VALIDATE = 1, BIND_START = 2,
        BIND_WAIT = 3, HEAD_START = 4, HEAD_WAIT = 5, HEAD_CHECK = 6,
        PAIR_SEND = 7, PAIR_WAIT = 8, PAIR_REGISTER = 9,
        SCALAR_SEND = 10, SCALAR_WAIT = 11, SCALAR_REGISTER = 12,
        RESTORE_CHECK = 13, PUBLISH = 14, RESPONSE = 15,
        FINAL_BIND_START = 16, FINAL_BIND_WAIT = 17,
        FINAL_RAW_START = 18, FINAL_RAW_WAIT = 19;
    localparam [2:0] S_IDLE = 0, S_VALIDATE = 1, S_SEND = 2,
        S_WAIT = 3, S_REGISTER = 4, S_RESPONSE = 5;
    localparam [31:0] INPUT_MAGIC = 32'h454e3148;
    localparam [31:0] FINAL_BIND_MAGIC = 32'h454e3150;
    reg [4:0] state;
    reg [2:0] source_state;
    reg [1:0] model_hold, precision_hold, mode_hold, dependency_domain_hold;
    reg [31:0] generation_hold, frames_hold, tokens_hold, query_hold;
    reg [31:0] dependency_token_hold, yielded_token;
    reg [7:0] layer_hold, dependency_layer_hold;
    reg [5:0] slot_hold, dependency_slot_hold;
    reg [11:0] dependency_length_hold;
    reg dependency_valid_hold, resume_hold, yield_hold, scalar_restore, raw_binding;
    reg scalar_word, source_dependency, source_tag_bad;
    reg [2:0] head_hold;
    reg [10:0] output_count;
    reg [15:0] low_hold, source_data_hold;
    reg [31:0] pair_hold, scalar_hold, restored_count;
    reg [31:0] source_index_hold, source_token_hold, source_pair_hold;
    reg [63:0] audio_hold, weights_hold;
    reg [159:0] continuation_hold, yield_continuation;
    reg [3:0] error_hold, child_error_hold, work_error_hold, source_error_hold;
    reg [3:0] first_source_error;
    reg child_yield_hold;

    initial begin
        if (COMPACT != 0 && COMPACT != 1)
            $fatal(1, "PARAMETER ERROR: COMPACT must be 0 or 1");
        if (DEFER_QUERY_BINDING != 0 && DEFER_QUERY_BINDING != 1)
            $fatal(1, "PARAMETER ERROR: DEFER_QUERY_BINDING must be 0 or 1");
        if ((FINAL_FEEDFORWARD != 0 && FINAL_FEEDFORWARD != 1) ||
            (FINAL_FEEDFORWARD && !DEFER_QUERY_BINDING))
            $fatal(1, "PARAMETER ERROR: FINAL_FEEDFORWARD requires DEFER_QUERY_BINDING");
    end
    wire [7:0] logical_layer = layer_hold - 1'b1;
    wire input_continuation = continuation_hold == {INPUT_MAGIC, 128'd0};
    wire head_continuation = continuation_hold[159:128] == 32'h454e3141 &&
        continuation_hold[127:96] == generation_hold &&
        continuation_hold[95:64] == query_hold &&
        continuation_hold[63:56] == layer_hold &&
        continuation_hold[55:50] == slot_hold &&
        continuation_hold[49:48] == model_hold &&
        continuation_hold[47:46] == precision_hold &&
        continuation_hold[45:38] == logical_layer &&
        continuation_hold[34:0] == 0;
    wire dependency_tag = dependency_valid_hold && dependency_domain_hold == 2 &&
        dependency_layer_hold == logical_layer && dependency_length_hold == 1024 &&
        dependency_slot_hold < 16 && dependency_token_hold < tokens_hold;
    wire [159:0] final_bind_descriptor = {FINAL_BIND_MAGIC, generation_hold,
        query_hold, layer_hold, slot_hold, model_hold, precision_hold,
        logical_layer, 3'd0, 35'd0};
    wire final_bind_continuation = DEFER_QUERY_BINDING &&
        continuation_hold == final_bind_descriptor;
    wire binding_selected = rst_n && (state == BIND_START || state == BIND_WAIT ||
        (!FINAL_FEEDFORWARD && (state == FINAL_BIND_START || state == FINAL_BIND_WAIT)));
    wire binding_ready, binding_valid, binding_yield;
    wire binding_work_valid, binding_work_rsp_ready;
    wire [3:0] binding_error;
    wire [2:0] binding_op;
    wire [1:0] binding_domain, binding_target;
    wire [31:0] binding_token, binding_data;
    wire [7:0] binding_layer, binding_scalar;
    wire [11:0] binding_length, binding_component;
    wire [5:0] binding_slot;
    wire binding_bank;
    anvil_en1_replay_frame_input #(.COMPACT(COMPACT), .DOMAIN(2)) predecessor (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && (state == BIND_START ||
            (!FINAL_FEEDFORWARD && state == FINAL_BIND_START))),
        .start_ready(binding_ready),
        .model(model_hold), .token(query_hold), .tokens(tokens_hold),
        .frame_layer(layer_hold), .frame_slot(slot_hold), .input_bank(1'b0),
        .dependency_valid(dependency_valid_hold &&
            (!DEFER_QUERY_BINDING || dependency_token_hold == query_hold)),
        .dependency_domain(dependency_domain_hold),
        .dependency_layer(dependency_layer_hold), .dependency_token(dependency_token_hold),
        .dependency_length(dependency_length_hold), .dependency_slot(dependency_slot_hold),
        .work_req_valid(binding_work_valid),
        .work_req_ready(binding_selected && work_req_ready),
        .work_req_op(binding_op), .work_req_domain(binding_domain),
        .work_req_target(binding_target), .work_req_token(binding_token),
        .work_req_layer(binding_layer), .work_req_length(binding_length),
        .work_req_component(binding_component), .work_req_slot(binding_slot),
        .work_req_bank(binding_bank), .work_req_scalar_index(binding_scalar),
        .work_req_data(binding_data),
        .work_rsp_valid(binding_selected && work_rsp_valid),
        .work_rsp_ready(binding_work_rsp_ready), .work_rsp_error(work_rsp_error),
        .done_valid(binding_valid),
        .done_ready(rst_n && (state == BIND_WAIT || state == FINAL_BIND_WAIT)),
        .done_error(binding_error), .done_dependency(binding_yield),
        .done_dependency_domain(), .done_dependency_layer(),
        .done_dependency_token(), .done_dependency_length(),
        .controller_state_bytes(binding_controller_bytes), .busy()
    );

    wire head_running = state == HEAD_WAIT || state == FINAL_RAW_WAIT;
    wire head_selected = rst_n && (state == HEAD_START || head_running ||
        state == FINAL_RAW_START ||
        state == PAIR_SEND || state == PAIR_WAIT || state == PAIR_REGISTER);
    wire head_ready, head_valid, head_yield, head_work_valid, head_work_rsp_ready;
    wire head_source_valid, head_source_rsp_ready, head_need_valid;
    wire [1:0] head_source_model, need_model, need_precision, need_selector;
    wire [7:0] head_source_layer, need_layer, head_dependency_layer;
    wire [31:0] head_source_generation, head_source_token, head_source_index;
    wire [31:0] need_generation, need_token, head_dependency_token;
    wire [2:0] need_head;
    wire [9:0] need_component, head_output_index;
    wire head_output_valid, head_output_last;
    wire [15:0] head_output_data;
    wire [159:0] head_outer;
    wire [3:0] head_error;
    wire [2:0] head_op;
    wire [1:0] head_domain, head_target;
    wire [31:0] head_token, head_data;
    wire [7:0] head_layer, head_scalar;
    wire [11:0] head_length, head_component;
    wire [5:0] head_slot;
    wire head_bank;
    wire [63:0] executor_control, numerical_head_control, block_control, input_control;
    wire [63:0] tile_control, clipped_control, clamp_control, position_control, softplus_control;
    wire [63:0] pre_control, pre_nested_control;
    wire need_tag = need_model == model_hold && need_precision == precision_hold &&
        need_generation == generation_hold && need_layer == logical_layer &&
        need_head == head_hold && need_selector < 3 && need_component < 128 &&
        !need_component[0] && need_token < tokens_hold;
    wire [1:0] need_action = error_hold != 0 || first_source_error != 0 || !need_tag ? 2'd2 :
        ((!DEFER_QUERY_BINDING && need_token == query_hold) ||
            (dependency_tag && need_token == dependency_token_hold) ?
            2'd0 : 2'd1);
    wire [10:0] head_begin = raw_binding ? 11'd0 : {head_hold, 7'd0};
    wire [10:0] head_end = raw_binding ? 11'd1024 : head_begin + 11'd128;
    wire output_good = output_count >= head_begin && output_count < head_end &&
        head_output_index == output_count - head_begin &&
        head_output_last == (output_count + 11'd1 == head_end);
    anvil_en1_replay_audio_attention attention (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && (state == HEAD_START || state == FINAL_RAW_START)),
        .start_ready(head_ready), .raw_only(raw_binding),
        .model(model_hold), .precision(precision_hold), .generation(generation_hold),
        .frames(frames_hold), .query_token(query_hold), .layer(logical_layer),
        .frame_layer(layer_hold), .head(head_hold), .frame_slot(slot_hold),
        .audio_base(audio_hold), .audio_weights_base(weights_hold),
        .resume_valid(resume_hold), .continuation(continuation_hold),
        .need_valid(head_need_valid),
        .need_ready(rst_n && head_running && source_state == S_IDLE),
        .need_action(need_action), .need_model(need_model), .need_precision(need_precision),
        .need_selector(need_selector), .need_generation(need_generation), .need_token(need_token),
        .need_layer(need_layer), .need_head(need_head), .need_component(need_component),
        .source_valid(head_source_valid),
        .source_ready(rst_n && head_running && source_state == S_IDLE),
        .source_model(head_source_model), .source_layer(head_source_layer),
        .source_generation(head_source_generation), .source_token(head_source_token),
        .source_index(head_source_index),
        .source_rsp_valid(head_selected && source_state == S_RESPONSE),
        .source_rsp_ready(head_source_rsp_ready), .source_rsp_data(source_data_hold),
        .source_rsp_error(source_error_hold != 0),
        .work_req_valid(head_work_valid),
        .work_req_ready(rst_n && head_running && source_state == S_IDLE && work_req_ready),
        .work_req_op(head_op), .work_req_domain(head_domain), .work_req_target(head_target),
        .work_req_token(head_token), .work_req_layer(head_layer),
        .work_req_length(head_length), .work_req_component(head_component),
        .work_req_slot(head_slot), .work_req_bank(head_bank),
        .work_req_scalar_index(head_scalar), .work_req_data(head_data),
        .work_rsp_valid(rst_n && head_running && source_state == S_IDLE && work_rsp_valid),
        .work_rsp_ready(head_work_rsp_ready), .work_rsp_data(work_rsp_data),
        .work_rsp_error(work_rsp_error),
        .cmd_valid(cmd_valid), .cmd_ready(head_selected && cmd_ready),
        .cmd_write(cmd_write), .cmd_addr(cmd_addr), .cmd_wdata(cmd_wdata),
        .result_valid(head_selected && result_valid), .result_ready(result_ready),
        .result_data(result_data), .result_error(result_error),
        .output_valid(head_output_valid),
        .output_ready(rst_n && head_running && source_state == S_IDLE),
        .output_index(head_output_index), .output_data(head_output_data),
        .output_last(head_output_last), .done_valid(head_valid),
        .done_ready(rst_n && head_running && source_state == S_IDLE && !head_output_valid),
        .done_error(head_error), .done_yield(head_yield),
        .done_continuation(head_outer), .done_dependency_layer(head_dependency_layer),
        .done_dependency_token(head_dependency_token),
        .input_read_event(input_read_event), .input_read_bytes(input_read_bytes),
        .projection_event(projection_event), .projection_bytes(projection_bytes),
        .intermediate_event(intermediate_event), .intermediate_bytes(intermediate_bytes),
        .source_read_event(source_read_event), .source_read_bytes(source_read_bytes),
        .weight_read_event(weight_read_event), .weight_read_bytes(weight_read_bytes),
        .vector_live_bytes(vector_live_bytes), .vector_physical_bytes(vector_physical_bytes),
        .pre_controller_bytes(pre_control), .pre_nested_controller_bytes(pre_nested_control),
        .controller_bytes(head_controller_bytes), .executor_controller_bytes(executor_control),
        .head_controller_bytes(numerical_head_control), .block_controller_bytes(block_control),
        .input_controller_bytes(input_control), .tile_controller_bytes(tile_control),
        .clipped_controller_bytes(clipped_control), .clamp_controller_bytes(clamp_control),
        .position_controller_bytes(position_control), .softplus_controller_bytes(softplus_control)
    );

    wire source_send = rst_n && head_running && source_state == S_SEND;
    wire source_wait = rst_n && head_running && source_state == S_WAIT;
    wire local_send = rst_n && (state == PAIR_SEND || state == SCALAR_SEND);
    wire local_wait = rst_n && (state == PAIR_WAIT || state == SCALAR_WAIT);
    assign work_req_valid = (binding_selected && binding_work_valid) ||
        source_send || local_send ||
        (rst_n && head_running && source_state == S_IDLE && head_work_valid);
    assign work_rsp_ready = (binding_selected && binding_work_rsp_ready) ||
        source_wait || local_wait ||
        (rst_n && head_running && source_state == S_IDLE && head_work_rsp_ready);
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
            work_req_domain = 2;
            work_req_token = query_hold;
            work_req_layer = layer_hold;
            work_req_length = 1024;
            work_req_slot = slot_hold;
            if (binding_selected) begin
                work_req_op = binding_op;
                work_req_domain = binding_domain;
                work_req_target = binding_target;
                work_req_token = binding_token;
                work_req_layer = binding_layer;
                work_req_length = binding_length;
                work_req_component = binding_component;
                work_req_slot = binding_slot;
                work_req_bank = binding_bank;
                work_req_scalar_index = binding_scalar;
                work_req_data = binding_data;
            end else if (source_state != S_IDLE && head_running) begin
                work_req_op = 4;
                work_req_target = source_dependency ? 1 : 0;
                work_req_token = source_dependency ? source_token_hold : query_hold;
                work_req_layer = source_dependency ? logical_layer : layer_hold;
                work_req_component = source_index_hold[11:0] & 12'hffe;
                work_req_slot = source_dependency ? dependency_slot_hold : slot_hold;
            end else if (state == PAIR_SEND || state == PAIR_WAIT || state == PAIR_REGISTER) begin
                work_req_op = 6;
                work_req_target = 2;
                work_req_bank = !raw_binding;
                work_req_component = {1'b0, output_count} - 12'd2;
                work_req_data = pair_hold;
            end else if (state == SCALAR_SEND || state == SCALAR_WAIT ||
                state == SCALAR_REGISTER) begin
                work_req_op = scalar_restore ? 7 : 6;
                work_req_scalar_index = scalar_word ? 31 : 30;
                work_req_data = scalar_word ? {16'd0, low_hold} : {21'd0, output_count};
            end else begin
                work_req_op = head_op;
                work_req_domain = head_domain;
                work_req_target = head_target;
                work_req_token = head_token;
                work_req_layer = head_layer;
                work_req_length = head_length;
                work_req_component = head_component;
                work_req_slot = head_slot;
                work_req_bank = head_bank;
                work_req_scalar_index = head_scalar;
                work_req_data = head_data;
            end
        end
    end
    assign start_ready = rst_n && state == IDLE;
    assign done_valid = rst_n && state == RESPONSE;
    assign done_error = rst_n ? error_hold : 4'd0;
    assign done_yield = done_valid && yield_hold && error_hold == 0;
    assign done_bank = done_valid && !yield_hold && error_hold == 0;
    assign done_continuation = done_yield ? yield_continuation : 160'd0;
    assign done_dependency_domain = done_yield ? 2'd2 : 2'd0;
    assign done_dependency_layer = done_yield ? logical_layer : 8'd0;
    assign done_dependency_token = done_yield ? yielded_token : 32'd0;
    assign done_dependency_length = done_yield ? 12'd1024 : 12'd0;
    assign nested_controller_bytes = !rst_n ? 64'd0 :
        executor_control + numerical_head_control + block_control + input_control +
        tile_control + clipped_control + clamp_control + position_control +
        softplus_control + pre_control + pre_nested_control;
    localparam integer CONTROLLER_BITS =
        $bits(state) + $bits(source_state) + $bits(model_hold) + $bits(precision_hold) +
        $bits(mode_hold) + $bits(dependency_domain_hold) + $bits(generation_hold) +
        $bits(frames_hold) + $bits(tokens_hold) + $bits(query_hold) +
        $bits(dependency_token_hold) + $bits(yielded_token) + $bits(layer_hold) +
        $bits(dependency_layer_hold) + $bits(slot_hold) + $bits(dependency_slot_hold) +
        $bits(dependency_length_hold) + $bits(dependency_valid_hold) + $bits(resume_hold) +
        $bits(yield_hold) + $bits(scalar_restore) + $bits(raw_binding) + $bits(scalar_word) +
        $bits(source_dependency) + $bits(source_tag_bad) + $bits(head_hold) +
        $bits(output_count) + $bits(low_hold) + $bits(source_data_hold) + $bits(pair_hold) +
        $bits(scalar_hold) + $bits(restored_count) + $bits(source_index_hold) +
        $bits(source_token_hold) + $bits(source_pair_hold) + $bits(audio_hold) +
        $bits(weights_hold) + $bits(continuation_hold) + $bits(yield_continuation) +
        $bits(error_hold) + $bits(child_error_hold) + $bits(work_error_hold) +
        $bits(source_error_hold) + $bits(first_source_error) + $bits(child_yield_hold);
    assign controller_bytes = rst_n ? (CONTROLLER_BITS + 7) >> 3 : 64'd0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            source_state <= S_IDLE;
            source_index_hold <= 0;
            source_token_hold <= 0;
            source_pair_hold <= 0;
            source_data_hold <= 0;
            source_dependency <= 0;
            source_tag_bad <= 0;
            source_error_hold <= 0;
            first_source_error <= 0;
        end else begin
            if (start_valid && start_ready)
                first_source_error <= 0;
            case (source_state)
                S_IDLE: if (head_running && head_source_valid) begin
                    source_index_hold <= head_source_index;
                    source_token_hold <= head_source_token;
                    source_dependency <= DEFER_QUERY_BINDING || head_source_token != query_hold;
                    source_tag_bad <= head_source_model != model_hold ||
                        head_source_generation != generation_hold ||
                        head_source_layer != logical_layer;
                    source_data_hold <= 0;
                    source_error_hold <= 0;
                    source_state <= S_VALIDATE;
                end
                S_VALIDATE: begin
                    if (source_tag_bad || source_index_hold >= 1024 ||
                        (source_dependency && (!dependency_tag ||
                            source_token_hold != dependency_token_hold)) ||
                        error_hold != 0 || first_source_error != 0) begin
                        source_error_hold <= 7;
                        if (first_source_error == 0)
                            first_source_error <= 7;
                        source_state <= S_RESPONSE;
                    end else
                        source_state <= S_SEND;
                end
                S_SEND: if (work_req_ready)
                    source_state <= S_WAIT;
                S_WAIT: if (work_rsp_valid) begin
                    source_pair_hold <= work_rsp_data;
                    source_error_hold <= work_rsp_error;
                    source_state <= S_REGISTER;
                end
                S_REGISTER: begin
                    if (source_error_hold != 0) begin
                        if (first_source_error == 0)
                            first_source_error <= source_error_hold;
                    end else if (source_index_hold[0])
                        source_data_hold <= source_pair_hold[31:16];
                    else
                        source_data_hold <= source_pair_hold[15:0];
                    source_state <= S_RESPONSE;
                end
                S_RESPONSE: if (head_selected && head_source_rsp_ready)
                    source_state <= S_IDLE;
                default: begin
                    source_error_hold <= 7;
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
            model_hold <= 0;
            precision_hold <= 0;
            mode_hold <= 0;
            dependency_domain_hold <= 0;
            generation_hold <= 0;
            frames_hold <= 0;
            tokens_hold <= 0;
            query_hold <= 0;
            dependency_token_hold <= 0;
            yielded_token <= 0;
            layer_hold <= 0;
            dependency_layer_hold <= 0;
            slot_hold <= 0;
            dependency_slot_hold <= 0;
            dependency_length_hold <= 0;
            dependency_valid_hold <= 0;
            resume_hold <= 0;
            raw_binding <= 0;
            yield_hold <= 0;
            scalar_restore <= 0;
            scalar_word <= 0;
            head_hold <= 0;
            output_count <= 0;
            low_hold <= 0;
            pair_hold <= 0;
            scalar_hold <= 0;
            restored_count <= 0;
            audio_hold <= 0;
            weights_hold <= 0;
            continuation_hold <= 0;
            yield_continuation <= 0;
            error_hold <= 0;
            child_error_hold <= 0;
            work_error_hold <= 0;
            child_yield_hold <= 0;
        end else begin
            case (state)
                IDLE: if (start_valid && start_ready) begin
                    model_hold <= model;
                    precision_hold <= precision;
                    mode_hold <= mode;
                    generation_hold <= generation;
                    frames_hold <= frames;
                    tokens_hold <= (frames + 32'd3) >> 2;
                    query_hold <= query_token;
                    layer_hold <= frame_layer;
                    slot_hold <= frame_slot;
                    audio_hold <= audio_base;
                    weights_hold <= audio_weights_base;
                    continuation_hold <= continuation;
                    dependency_valid_hold <= dependency_valid;
                    dependency_domain_hold <= dependency_domain;
                    dependency_layer_hold <= dependency_layer;
                    dependency_token_hold <= dependency_token;
                    dependency_length_hold <= dependency_length;
                    dependency_slot_hold <= dependency_slot;
                    resume_hold <= 0;
                    raw_binding <= 0;
                    yield_hold <= 0;
                    scalar_restore <= 0;
                    scalar_word <= 0;
                    head_hold <= 0;
                    output_count <= 0;
                    low_hold <= 0;
                    pair_hold <= 0;
                    restored_count <= 0;
                    scalar_hold <= 0;
                    yield_continuation <= 0;
                    yielded_token <= 0;
                    error_hold <= 0;
                    child_error_hold <= 0;
                    child_yield_hold <= 0;
                    work_error_hold <= 0;
                    state <= VALIDATE;
                end
                VALIDATE: begin
                    if ((model_hold != 1 && model_hold != 2) || precision_hold > 1) begin
                        error_hold <= 6;
                        state <= PUBLISH;
                    end else if (generation_hold == 0 || frames_hold == 0 ||
                        frames_hold > 131072 || query_hold >= tokens_hold ||
                        audio_hold[1:0] != 0 || weights_hold[1:0] != 0 ||
                        layer_hold == 0 || layer_hold > 12) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else if (mode_hold > 2 ||
                        (mode_hold == 1 && !input_continuation && !head_continuation &&
                            !final_bind_continuation) ||
                        (mode_hold != 1 && continuation_hold != 0) ||
                        (mode_hold == 2 && (!dependency_tag ||
                            dependency_token_hold != query_hold))) begin
                        error_hold <= 7;
                        state <= PUBLISH;
                    end else if (mode_hold == 1 && final_bind_continuation) begin
                        output_count <= 1024;
                        state <= FINAL_BIND_START;
                    end else if (mode_hold == 1 && head_continuation) begin
                        head_hold <= continuation_hold[37:35];
                        resume_hold <= 1;
                        scalar_restore <= 1;
                        scalar_word <= 0;
                        state <= SCALAR_SEND;
                    end else if (DEFER_QUERY_BINDING)
                        state <= HEAD_START;
                    else
                        state <= BIND_START;
                end
                BIND_START: if (binding_ready)
                    state <= BIND_WAIT;
                FINAL_BIND_START: begin
                    if (FINAL_FEEDFORWARD) begin
                        if (!dependency_tag || dependency_token_hold != query_hold) begin
                            yielded_token <= query_hold;
                            yield_hold <= 1;
                            yield_continuation <= final_bind_descriptor;
                            state <= PUBLISH;
                        end else begin
                            raw_binding <= 1;
                            resume_hold <= 0;
                            output_count <= 0;
                            low_hold <= 0;
                            state <= FINAL_RAW_START;
                        end
                    end else if (binding_ready)
                        state <= FINAL_BIND_WAIT;
                end
                BIND_WAIT, FINAL_BIND_WAIT: if (binding_valid) begin
                    if (binding_error != 0) begin
                        error_hold <= binding_error;
                        state <= PUBLISH;
                    end else if (binding_yield) begin
                        yielded_token <= query_hold;
                        yield_hold <= 1;
                        if (state == FINAL_BIND_WAIT)
                            yield_continuation <= final_bind_descriptor;
                        else
                            yield_continuation <= {INPUT_MAGIC, 128'd0};
                        state <= PUBLISH;
                    end else if (state == FINAL_BIND_WAIT)
                        state <= PUBLISH;
                    else
                        state <= HEAD_START;
                end
                HEAD_START: if (head_ready)
                    state <= HEAD_WAIT;
                FINAL_RAW_START: if (head_ready)
                    state <= FINAL_RAW_WAIT;
                HEAD_WAIT, FINAL_RAW_WAIT: begin
                    if (head_output_valid && source_state == S_IDLE) begin
                        if (error_hold == 0 && first_source_error == 0) begin
                            if (!output_good) begin
                                error_hold <= 7;
                            end else begin
                                output_count <= output_count + 1'b1;
                                if (!output_count[0])
                                    low_hold <= head_output_data;
                                else begin
                                    pair_hold <= {head_output_data, low_hold};
                                    state <= PAIR_SEND;
                                end
                            end
                        end
                    end else if (head_valid && source_state == S_IDLE) begin
                        child_error_hold <= head_error;
                        child_yield_hold <= head_yield;
                        yield_continuation <= head_outer;
                        yielded_token <= head_dependency_token;
                        if (head_yield && head_dependency_layer != logical_layer && error_hold == 0)
                            error_hold <= 7;
                        state <= HEAD_CHECK;
                    end
                end
                HEAD_CHECK: begin
                    if (error_hold != 0 || first_source_error != 0 || child_error_hold != 0) begin
                        if (error_hold == 0)
                            error_hold <= first_source_error != 0 ?
                                first_source_error : child_error_hold;
                        state <= PUBLISH;
                    end else if (raw_binding) begin
                        if (child_yield_hold || output_count != 1024 || low_hold != 0)
                            error_hold <= 7;
                        state <= PUBLISH;
                    end else if (child_yield_hold) begin
                        if (yielded_token >= tokens_hold ||
                            output_count < head_begin || output_count >= head_end) begin
                            error_hold <= 7;
                            state <= PUBLISH;
                        end else begin
                            scalar_restore <= 0;
                            scalar_word <= 0;
                            state <= SCALAR_SEND;
                        end
                    end else if (output_count != head_end || low_hold != 0) begin
                        error_hold <= 7;
                        state <= PUBLISH;
                    end else if (head_hold == 7) begin
                        if (DEFER_QUERY_BINDING)
                            state <= FINAL_BIND_START;
                        else
                            state <= PUBLISH;
                    end else begin
                        head_hold <= head_hold + 1'b1;
                        resume_hold <= 0;
                        continuation_hold <= 0;
                        state <= HEAD_START;
                    end
                end
                PAIR_SEND: if (work_req_ready)
                    state <= PAIR_WAIT;
                PAIR_WAIT: if (work_rsp_valid) begin
                    work_error_hold <= work_rsp_error;
                    state <= PAIR_REGISTER;
                end
                PAIR_REGISTER: begin
                    low_hold <= 0;
                    if (work_error_hold != 0 && error_hold == 0)
                        error_hold <= work_error_hold;
                    if (raw_binding)
                        state <= FINAL_RAW_WAIT;
                    else
                        state <= HEAD_WAIT;
                end
                SCALAR_SEND: if (work_req_ready)
                    state <= SCALAR_WAIT;
                SCALAR_WAIT: if (work_rsp_valid) begin
                    scalar_hold <= work_rsp_data;
                    work_error_hold <= work_rsp_error;
                    state <= SCALAR_REGISTER;
                end
                SCALAR_REGISTER: begin
                    if (work_error_hold != 0) begin
                        error_hold <= work_error_hold;
                        state <= PUBLISH;
                    end else if (scalar_restore && scalar_word && scalar_hold[31:16] != 0) begin
                        error_hold <= 7;
                        state <= PUBLISH;
                    end else begin
                        if (scalar_restore) begin
                            if (scalar_word)
                                low_hold <= scalar_hold[15:0];
                            else
                                restored_count <= scalar_hold;
                        end
                        if (!scalar_word) begin
                            scalar_word <= 1;
                            state <= SCALAR_SEND;
                        end else if (scalar_restore)
                            state <= RESTORE_CHECK;
                        else begin
                            yield_hold <= 1;
                            state <= PUBLISH;
                        end
                    end
                end
                RESTORE_CHECK: begin
                    if (restored_count < {21'd0, head_begin} ||
                        restored_count >= {21'd0, head_end} ||
                        (!restored_count[0] && low_hold != 0)) begin
                        error_hold <= 7;
                        state <= PUBLISH;
                    end else begin
                        output_count <= restored_count[10:0];
                        state <= HEAD_START;
                    end
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
