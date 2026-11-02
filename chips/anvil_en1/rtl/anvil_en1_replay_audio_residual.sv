module anvil_en1_replay_audio_residual #(
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
    output wire [63:0] controller_bytes, heads_controller_bytes,
    output wire [63:0] binding_controller_bytes, head_controller_bytes,
    output wire [63:0] heads_nested_controller_bytes,
    output wire [63:0] post_controller_bytes, post_nested_controller_bytes
);
    localparam [3:0] IDLE = 0, VALIDATE = 1, HEADS_START = 2,
        HEADS_WAIT = 3, HEADS_CHECK = 4, POST_START = 5, POST_WAIT = 6,
        PAIR_SEND = 7, PAIR_WAIT = 8, PAIR_REGISTER = 9, POST_CHECK = 10,
        PUBLISH = 11, RESPONSE = 12;
    localparam [2:0] S_IDLE = 0, S_VALIDATE = 1, S_SEND = 2,
        S_WAIT = 3, S_REGISTER = 4, S_RESPONSE = 5;
    reg [3:0] state;
    reg [2:0] source_state;
    reg [1:0] model_hold, precision_hold, mode_hold, dependency_domain_hold;
    reg [31:0] generation_hold, frames_hold, query_hold, dependency_token_hold;
    reg [7:0] layer_hold, dependency_layer_hold;
    reg [5:0] slot_hold, dependency_slot_hold;
    reg [11:0] dependency_length_hold;
    reg dependency_valid_hold, yield_hold, child_yield_hold, child_bank_hold;
    reg source_kind_hold, source_bad;
    reg [63:0] audio_hold, weights_hold;
    reg [159:0] continuation_hold, yielded_continuation;
    reg [1:0] yielded_domain;
    reg [7:0] yielded_layer;
    reg [31:0] yielded_token, received, source_index_hold, source_pair_hold, pair_hold;
    reg [11:0] yielded_length;
    reg [15:0] low_hold, source_data_hold;
    reg [3:0] error_hold, child_error_hold, work_error_hold;
    reg [3:0] source_error_hold, first_source_error;

    initial begin
        if (COMPACT != 0 && COMPACT != 1)
            $fatal(1, "PARAMETER ERROR: COMPACT must be 0 or 1");
    end
    wire [7:0] logical_layer = layer_hold - 1'b1;
    wire heads_selected = rst_n && (state == HEADS_START || state == HEADS_WAIT);
    wire heads_ready, heads_valid, heads_yield, heads_bank, heads_work_valid;
    wire heads_work_rsp_ready, heads_cmd_valid, heads_result_ready;
    wire [3:0] heads_error;
    wire [159:0] heads_continuation;
    wire [1:0] heads_dependency_domain;
    wire [7:0] heads_dependency_layer;
    wire [31:0] heads_dependency_token;
    wire [11:0] heads_dependency_length;
    wire [2:0] heads_op;
    wire [1:0] heads_domain, heads_target;
    wire [31:0] heads_token, heads_data;
    wire [7:0] heads_layer, heads_scalar;
    wire [11:0] heads_length, heads_component;
    wire [5:0] heads_slot;
    wire heads_work_bank;
    wire [63:0] heads_addr, heads_live, heads_physical;
    wire heads_input_event, heads_projection_event, heads_intermediate_event;
    wire heads_source_event, heads_weight_event;
    wire [31:0] heads_input_bytes, heads_projection_bytes, heads_intermediate_bytes;
    wire [31:0] heads_source_bytes, heads_weight_bytes;
    anvil_en1_replay_audio_heads #(.COMPACT(COMPACT)) heads (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == HEADS_START), .start_ready(heads_ready),
        .model(model_hold), .precision(precision_hold), .mode(mode_hold),
        .generation(generation_hold), .frames(frames_hold), .query_token(query_hold),
        .frame_layer(layer_hold), .frame_slot(slot_hold),
        .audio_base(audio_hold), .audio_weights_base(weights_hold),
        .continuation(continuation_hold),
        .dependency_valid(dependency_valid_hold), .dependency_domain(dependency_domain_hold),
        .dependency_layer(dependency_layer_hold), .dependency_token(dependency_token_hold),
        .dependency_length(dependency_length_hold), .dependency_slot(dependency_slot_hold),
        .work_req_valid(heads_work_valid),
        .work_req_ready(heads_selected && work_req_ready),
        .work_req_op(heads_op), .work_req_domain(heads_domain),
        .work_req_target(heads_target), .work_req_token(heads_token),
        .work_req_layer(heads_layer), .work_req_length(heads_length),
        .work_req_component(heads_component), .work_req_slot(heads_slot),
        .work_req_bank(heads_work_bank), .work_req_scalar_index(heads_scalar),
        .work_req_data(heads_data),
        .work_rsp_valid(heads_selected && work_rsp_valid),
        .work_rsp_ready(heads_work_rsp_ready), .work_rsp_data(work_rsp_data),
        .work_rsp_error(work_rsp_error),
        .cmd_valid(heads_cmd_valid), .cmd_ready(heads_selected && cmd_ready),
        .cmd_write(), .cmd_addr(heads_addr), .cmd_wdata(),
        .result_valid(heads_selected && result_valid),
        .result_ready(heads_result_ready), .result_data(result_data), .result_error(result_error),
        .done_valid(heads_valid), .done_ready(rst_n && state == HEADS_WAIT),
        .done_error(heads_error), .done_yield(heads_yield), .done_bank(heads_bank),
        .done_continuation(heads_continuation),
        .done_dependency_domain(heads_dependency_domain),
        .done_dependency_layer(heads_dependency_layer),
        .done_dependency_token(heads_dependency_token),
        .done_dependency_length(heads_dependency_length),
        .input_read_event(heads_input_event), .input_read_bytes(heads_input_bytes),
        .projection_event(heads_projection_event), .projection_bytes(heads_projection_bytes),
        .intermediate_event(heads_intermediate_event),
        .intermediate_bytes(heads_intermediate_bytes),
        .source_read_event(heads_source_event), .source_read_bytes(heads_source_bytes),
        .weight_read_event(heads_weight_event), .weight_read_bytes(heads_weight_bytes),
        .vector_live_bytes(heads_live), .vector_physical_bytes(heads_physical),
        .controller_bytes(heads_controller_bytes),
        .binding_controller_bytes(binding_controller_bytes),
        .head_controller_bytes(head_controller_bytes),
        .nested_controller_bytes(heads_nested_controller_bytes)
    );

    wire post_selected = rst_n && (state == POST_START || state == POST_WAIT ||
        state == PAIR_SEND || state == PAIR_WAIT || state == PAIR_REGISTER);
    wire post_ready, post_valid, post_cmd_valid, post_result_ready;
    wire post_source_valid, post_source_rsp_ready, post_source_kind;
    wire [1:0] post_source_model;
    wire [7:0] post_source_layer;
    wire [31:0] post_source_generation, post_source_token, post_source_index;
    wire post_output_valid, post_output_last, post_input_event;
    wire post_projection_event, post_intermediate_event;
    wire [31:0] post_output_index, post_input_bytes;
    wire [31:0] post_projection_bytes, post_intermediate_bytes;
    wire [15:0] post_output_data;
    wire [3:0] post_error;
    wire [63:0] post_addr, post_live, post_physical;
    wire [63:0] pre_control, unused_head_control, projection_control, projection_clamp_control;
    wire [63:0] norm_control, clamp_control;
    wire post_beat_good = received < 1024 && post_output_index == received &&
        post_output_last == (received == 1023);
    anvil_en1_audio_attention_residual #(.FRAME_HEADS(1)) post_attention (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == POST_START), .start_ready(post_ready),
        .model(model_hold), .precision(precision_hold), .layer(logical_layer),
        .generation(generation_hold), .frames(frames_hold), .token(query_hold),
        .audio_base(audio_hold), .audio_weights_base(weights_hold),
        .source_valid(post_source_valid),
        .source_ready(rst_n && state == POST_WAIT && source_state == S_IDLE),
        .source_kind(post_source_kind), .source_model(post_source_model),
        .source_layer(post_source_layer), .source_generation(post_source_generation),
        .source_token(post_source_token), .source_index(post_source_index),
        .source_rsp_valid(post_selected && source_state == S_RESPONSE),
        .source_rsp_ready(post_source_rsp_ready),
        .source_rsp_data(source_data_hold), .source_rsp_error(source_error_hold != 0),
        .cmd_valid(post_cmd_valid), .cmd_ready(post_selected && cmd_ready),
        .cmd_write(), .cmd_addr(post_addr), .cmd_wdata(),
        .result_valid(post_selected && result_valid), .result_ready(post_result_ready),
        .result_data(result_data), .result_error(result_error),
        .output_valid(post_output_valid),
        .output_ready(rst_n && state == POST_WAIT && source_state == S_IDLE),
        .output_index(post_output_index), .output_data(post_output_data),
        .output_last(post_output_last), .done_valid(post_valid),
        .done_ready(rst_n && state == POST_WAIT && source_state == S_IDLE && !post_output_valid),
        .done_error(post_error),
        .input_read_event(post_input_event), .input_read_bytes(post_input_bytes),
        .projection_event(post_projection_event), .projection_bytes(post_projection_bytes),
        .intermediate_event(post_intermediate_event),
        .intermediate_bytes(post_intermediate_bytes),
        .vector_live_bytes(post_live), .vector_physical_bytes(post_physical),
        .controller_bytes(post_controller_bytes), .pre_controller_bytes(pre_control),
        .head_controller_bytes(unused_head_control),
        .projection_controller_bytes(projection_control),
        .projection_clamp_controller_bytes(projection_clamp_control),
        .norm_controller_bytes(norm_control), .clamp_controller_bytes(clamp_control)
    );
    wire source_send = rst_n && state == POST_WAIT && source_state == S_SEND;
    wire source_wait = rst_n && state == POST_WAIT && source_state == S_WAIT;
    assign work_req_valid = (heads_selected && heads_work_valid) || source_send ||
        (rst_n && state == PAIR_SEND);
    assign work_rsp_ready = (heads_selected && heads_work_rsp_ready) || source_wait ||
        (rst_n && state == PAIR_WAIT);
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
            if (heads_selected) begin
                work_req_op = heads_op;
                work_req_domain = heads_domain;
                work_req_target = heads_target;
                work_req_token = heads_token;
                work_req_layer = heads_layer;
                work_req_length = heads_length;
                work_req_component = heads_component;
                work_req_slot = heads_slot;
                work_req_bank = heads_work_bank;
                work_req_scalar_index = heads_scalar;
                work_req_data = heads_data;
            end else begin
                work_req_domain = 2;
                work_req_token = query_hold;
                work_req_layer = layer_hold;
                work_req_length = 1024;
                work_req_slot = slot_hold;
                if (source_state != S_IDLE && state == POST_WAIT) begin
                    work_req_op = 4;
                    work_req_bank = source_kind_hold;
                    work_req_component = source_index_hold[11:0] & 12'hffe;
                end else if (state == PAIR_SEND || state == PAIR_WAIT ||
                    state == PAIR_REGISTER) begin
                    work_req_op = 6;
                    work_req_target = 2;
                    work_req_component = received[11:0] - 12'd2;
                    work_req_data = pair_hold;
                end
            end
        end
    end
    assign cmd_valid = (heads_selected && heads_cmd_valid) ||
        (post_selected && post_cmd_valid);
    assign cmd_write = 0;
    assign cmd_addr = !rst_n ? 64'd0 : (heads_selected ? heads_addr :
        (post_selected ? post_addr : 64'd0));
    assign cmd_wdata = 0;
    assign result_ready = (heads_selected && heads_result_ready) ||
        (post_selected && post_result_ready);
    assign start_ready = rst_n && state == IDLE;
    assign done_valid = rst_n && state == RESPONSE;
    assign done_error = rst_n ? error_hold : 4'd0;
    assign done_yield = done_valid && yield_hold && error_hold == 0;
    assign done_bank = 0;
    assign done_continuation = done_yield ? yielded_continuation : 160'd0;
    assign done_dependency_domain = done_yield ? yielded_domain : 2'd0;
    assign done_dependency_layer = done_yield ? yielded_layer : 8'd0;
    assign done_dependency_token = done_yield ? yielded_token : 32'd0;
    assign done_dependency_length = done_yield ? yielded_length : 12'd0;
    wire post_source_event = rst_n && state == POST_WAIT &&
        source_state == S_IDLE && post_source_valid;
    wire post_weight_event = post_selected && post_cmd_valid && cmd_ready;
    assign input_read_event = heads_input_event || post_input_event;
    assign input_read_bytes = heads_input_bytes + post_input_bytes;
    assign projection_event = heads_projection_event || post_projection_event;
    assign projection_bytes = heads_projection_bytes + post_projection_bytes;
    assign intermediate_event = heads_intermediate_event || post_intermediate_event;
    assign intermediate_bytes = heads_intermediate_bytes + post_intermediate_bytes;
    assign source_read_event = heads_source_event || post_source_event;
    assign source_read_bytes = heads_source_bytes + (post_source_event ? 32'd2 : 32'd0);
    assign weight_read_event = heads_weight_event || post_weight_event;
    assign weight_read_bytes = heads_weight_bytes + (post_weight_event ? 32'd4 : 32'd0);
    assign vector_live_bytes = !rst_n ? 64'd0 : heads_live + post_live;
    assign vector_physical_bytes = !rst_n ? 64'd0 : heads_physical + post_physical;
    assign post_nested_controller_bytes = !rst_n ? 64'd0 :
        pre_control + unused_head_control + projection_control + projection_clamp_control +
        norm_control + clamp_control;
    localparam integer CONTROLLER_BITS =
        $bits(state) + $bits(source_state) + $bits(model_hold) + $bits(precision_hold) +
        $bits(mode_hold) + $bits(dependency_domain_hold) + $bits(generation_hold) +
        $bits(frames_hold) + $bits(query_hold) + $bits(dependency_token_hold) +
        $bits(layer_hold) + $bits(dependency_layer_hold) + $bits(slot_hold) +
        $bits(dependency_slot_hold) + $bits(dependency_length_hold) +
        $bits(dependency_valid_hold) + $bits(yield_hold) + $bits(child_yield_hold) +
        $bits(child_bank_hold) + $bits(source_kind_hold) + $bits(source_bad) +
        $bits(audio_hold) + $bits(weights_hold) + $bits(continuation_hold) +
        $bits(yielded_continuation) + $bits(yielded_domain) + $bits(yielded_layer) +
        $bits(yielded_token) + $bits(received) + $bits(source_index_hold) +
        $bits(source_pair_hold) + $bits(pair_hold) + $bits(yielded_length) +
        $bits(low_hold) + $bits(source_data_hold) + $bits(error_hold) +
        $bits(child_error_hold) + $bits(work_error_hold) + $bits(source_error_hold) +
        $bits(first_source_error);
    assign controller_bytes = rst_n ? (CONTROLLER_BITS + 7) >> 3 : 64'd0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            source_state <= S_IDLE;
            source_kind_hold <= 0;
            source_bad <= 0;
            source_index_hold <= 0;
            source_pair_hold <= 0;
            source_data_hold <= 0;
            source_error_hold <= 0;
            first_source_error <= 0;
        end else begin
            if (start_valid && start_ready)
                first_source_error <= 0;
            case (source_state)
                S_IDLE: if (state == POST_WAIT && post_source_valid) begin
                    source_kind_hold <= post_source_kind;
                    source_index_hold <= post_source_index;
                    source_bad <= post_source_model != model_hold ||
                        post_source_layer != logical_layer ||
                        post_source_generation != generation_hold ||
                        post_source_token != query_hold;
                    source_data_hold <= 0;
                    source_error_hold <= 0;
                    source_state <= S_VALIDATE;
                end
                S_VALIDATE: begin
                    if (source_bad || source_index_hold >= 1024 || received != 0 ||
                        error_hold != 0 || first_source_error != 0) begin
                        source_error_hold <= first_source_error != 0 ? first_source_error :
                            (error_hold != 0 ? error_hold : 4'd7);
                        if (first_source_error == 0)
                            first_source_error <= error_hold != 0 ? error_hold : 4'd7;
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
                S_RESPONSE: if (post_selected && post_source_rsp_ready)
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
            query_hold <= 0;
            dependency_token_hold <= 0;
            layer_hold <= 0;
            dependency_layer_hold <= 0;
            slot_hold <= 0;
            dependency_slot_hold <= 0;
            dependency_length_hold <= 0;
            dependency_valid_hold <= 0;
            yield_hold <= 0;
            child_yield_hold <= 0;
            child_bank_hold <= 0;
            audio_hold <= 0;
            weights_hold <= 0;
            continuation_hold <= 0;
            yielded_continuation <= 0;
            yielded_domain <= 0;
            yielded_layer <= 0;
            yielded_token <= 0;
            yielded_length <= 0;
            received <= 0;
            pair_hold <= 0;
            low_hold <= 0;
            error_hold <= 0;
            child_error_hold <= 0;
            work_error_hold <= 0;
        end else begin
            case (state)
                IDLE: if (start_valid && start_ready) begin
                    model_hold <= model;
                    precision_hold <= precision;
                    mode_hold <= mode;
                    generation_hold <= generation;
                    frames_hold <= frames;
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
                    yield_hold <= 0;
                    child_yield_hold <= 0;
                    child_bank_hold <= 0;
                    yielded_continuation <= 0;
                    yielded_domain <= 0;
                    yielded_layer <= 0;
                    yielded_token <= 0;
                    yielded_length <= 0;
                    received <= 0;
                    pair_hold <= 0;
                    low_hold <= 0;
                    error_hold <= 0;
                    child_error_hold <= 0;
                    work_error_hold <= 0;
                    state <= VALIDATE;
                end
                VALIDATE: begin
                    if ((model_hold != 1 && model_hold != 2) || precision_hold > 1) begin
                        error_hold <= 6;
                        state <= PUBLISH;
                    end else if (generation_hold == 0 || frames_hold == 0 ||
                        frames_hold > 131072 || query_hold >= ((frames_hold + 32'd3) >> 2) ||
                        layer_hold == 0 || layer_hold > 12 ||
                        audio_hold[1:0] != 0 || weights_hold[1:0] != 0) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else
                        state <= HEADS_START;
                end
                HEADS_START: if (heads_ready)
                    state <= HEADS_WAIT;
                HEADS_WAIT: if (heads_valid) begin
                    child_error_hold <= heads_error;
                    child_yield_hold <= heads_yield;
                    child_bank_hold <= heads_bank;
                    yielded_continuation <= heads_continuation;
                    yielded_domain <= heads_dependency_domain;
                    yielded_layer <= heads_dependency_layer;
                    yielded_token <= heads_dependency_token;
                    yielded_length <= heads_dependency_length;
                    state <= HEADS_CHECK;
                end
                HEADS_CHECK: begin
                    if (child_error_hold != 0) begin
                        error_hold <= child_error_hold;
                        state <= PUBLISH;
                    end else if (child_yield_hold) begin
                        if (yielded_domain != 2 || yielded_layer != logical_layer ||
                            yielded_length != 1024 ||
                            yielded_token >= ((frames_hold + 32'd3) >> 2)) begin
                            error_hold <= 7;
                        end else
                            yield_hold <= 1;
                        state <= PUBLISH;
                    end else if (!child_bank_hold) begin
                        error_hold <= 7;
                        state <= PUBLISH;
                    end else
                        state <= POST_START;
                end
                POST_START: if (post_ready)
                    state <= POST_WAIT;
                POST_WAIT: begin
                    if (post_output_valid && source_state == S_IDLE) begin
                        if (error_hold == 0 && first_source_error == 0) begin
                            if (!post_beat_good)
                                error_hold <= 7;
                            else begin
                                received <= received + 1'b1;
                                if (!received[0])
                                    low_hold <= post_output_data;
                                else begin
                                    pair_hold <= {post_output_data, low_hold};
                                    state <= PAIR_SEND;
                                end
                            end
                        end
                    end else if (post_valid && source_state == S_IDLE) begin
                        child_error_hold <= post_error;
                        state <= POST_CHECK;
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
                    state <= POST_WAIT;
                end
                POST_CHECK: begin
                    if (error_hold == 0) begin
                        if (first_source_error != 0 || child_error_hold != 0)
                            error_hold <= first_source_error != 0 ?
                                first_source_error : child_error_hold;
                        else if (received != 1024 || low_hold != 0)
                            error_hold <= 7;
                    end
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
        end
    end
endmodule
