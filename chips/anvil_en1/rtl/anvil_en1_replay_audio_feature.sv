module anvil_en1_replay_audio_feature #(
    parameter integer COMPACT = 0
) (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] model, precision, mode, modality,
    input wire [31:0] generation, frames, tokens, token,
    input wire [7:0] frame_layer,
    input wire [5:0] frame_slot,
    input wire [63:0] audio_weights_base, audio_base, tokens_base,
    input wire [159:0] continuation,
    input wire dependency_valid,
    input wire [1:0] dependency_domain,
    input wire [7:0] dependency_layer,
    input wire [31:0] dependency_token,
    input wire [11:0] dependency_length,
    input wire [5:0] dependency_slot,
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
    output wire done_valid,
    input wire done_ready,
    output wire [3:0] done_error,
    output wire done_yield, done_bank,
    output wire [159:0] done_continuation,
    output wire [1:0] done_dependency_domain,
    output wire [7:0] done_dependency_layer,
    output wire [31:0] done_dependency_token,
    output wire [11:0] done_dependency_length,
    output wire projection_event, source_read_event,
    output wire [31:0] projection_bytes, source_read_bytes,
    output wire input_read_event,
    output wire [31:0] input_read_bytes,
    output wire [63:0] vector_live_bytes, vector_physical_bytes,
    output wire [63:0] controller_bytes, nested_controller_bytes
);
    localparam [4:0] IDLE = 0, VALIDATE = 1, CHILD_START = 2,
        CHILD_WAIT = 3, SOURCE_VALIDATE = 4, SOURCE_SEND = 5,
        SOURCE_WAIT = 6, SOURCE_REGISTER = 7, SOURCE_RESPONSE = 8,
        PAIR_SEND = 9, PAIR_WAIT = 10, PAIR_REGISTER = 11,
        CHILD_CHECK = 12, PUBLISH = 13, RESPONSE = 14,
        MAP_START = 15, MAP_WAIT = 16, MAP_CHECK = 17;
    reg [4:0] state;
    reg [1:0] model_hold, precision_hold, mode_hold, modality_hold, dependency_domain_hold;
    reg [31:0] generation_hold, frames_hold, token_hold, received, source_index_hold;
    reg [31:0] tokens_hold, mapped_token_hold;
    reg [7:0] layer_hold, dependency_layer_hold;
    reg [5:0] slot_hold, dependency_slot_hold;
    reg [31:0] dependency_token_hold;
    reg [11:0] dependency_length_hold, hidden_hold, pair_component;
    reg [63:0] weights_hold, audio_hold, tokens_base_hold;
    reg [159:0] continuation_hold;
    reg dependency_valid_hold, yield_hold, receive_bad, source_error_hold;
    reg [15:0] low_hold, source_data_hold;
    reg [31:0] pair_hold, source_pair_hold;
    reg [3:0] child_error_hold, work_error_hold, map_error_hold, error_hold;

    initial begin
        if (COMPACT != 0 && COMPACT != 1)
            $fatal(1, "PARAMETER ERROR: COMPACT must be 0 or 1");
    end
    wire dependency_tag_good = dependency_domain_hold == 2 &&
        dependency_layer_hold == 12 && dependency_token_hold == mapped_token_hold &&
        dependency_length_hold == 1024 && dependency_slot_hold < 16;
    wire continuation_tag_good = continuation_hold[159:128] == 32'h454e3146 &&
        continuation_hold[95:0] == 0 &&
        mapped_token_hold < ((frames_hold + 32'd3) >> 2);
    wire map_selected = rst_n && (state == MAP_START || state == MAP_WAIT);
    wire map_ready, map_valid, map_cmd_valid, map_result_ready;
    wire [31:0] map_token;
    wire [63:0] map_addr, map_control, map_nested_control;
    wire [3:0] map_error;
    anvil_en1_native_token_map #(.COMPACT(COMPACT)) mapping (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == MAP_START), .start_ready(map_ready),
        .model(model_hold), .modality(modality_hold), .kind(2'd2),
        .generation(generation_hold), .tokens(tokens_hold), .token(token_hold),
        .audio_frames(frames_hold), .tokens_base(tokens_base_hold), .audio_base(audio_hold),
        .cmd_valid(map_cmd_valid), .cmd_ready(map_selected && cmd_ready),
        .cmd_write(), .cmd_addr(map_addr), .cmd_wdata(),
        .result_valid(map_selected && result_valid), .result_ready(map_result_ready),
        .result_data(result_data), .result_error(result_error),
        .done_valid(map_valid), .done_ready(rst_n && state == MAP_WAIT),
        .done_ordinal(), .done_count(), .done_native_token(map_token), .done_error(map_error),
        .input_read_event(input_read_event), .input_read_bytes(input_read_bytes),
        .controller_bytes(map_control), .nested_controller_bytes(map_nested_control)
    );
    wire child_selected = rst_n && state >= CHILD_START && state <= CHILD_CHECK;
    wire child_ready, child_valid, child_cmd_valid, child_result_ready;
    wire child_source_valid, child_source_rsp_ready, child_output_valid, child_output_last;
    wire [1:0] child_source_model;
    wire [7:0] child_source_layer;
    wire [31:0] child_source_generation, child_source_token, child_source_index;
    wire [31:0] child_output_index;
    wire [15:0] child_output_data;
    wire [63:0] child_addr, feature_control, native_control, modality_control;
    wire [3:0] child_error;
    wire output_accepting = rst_n && state == CHILD_WAIT && !child_source_valid;
    wire source_tag_good = child_source_model == model_hold &&
        child_source_layer == 12 && child_source_generation == generation_hold &&
        child_source_token == mapped_token_hold && child_source_index < 1024;
    wire beat_good = received < {20'd0, hidden_hold} &&
        child_output_index == received &&
        child_output_last == (received + 1'b1 == {20'd0, hidden_hold});
    anvil_en1_audio_feature #(.COMPACT(COMPACT)) feature (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == CHILD_START), .start_ready(child_ready),
        .model(model_hold), .precision(precision_hold),
        .generation(generation_hold), .token(mapped_token_hold), .audio_weights_base(weights_hold),
        .source_valid(child_source_valid),
        .source_ready(rst_n && state == CHILD_WAIT),
        .source_model(child_source_model), .source_layer(child_source_layer),
        .source_generation(child_source_generation), .source_token(child_source_token),
        .source_index(child_source_index),
        .source_rsp_valid(rst_n && state == SOURCE_RESPONSE),
        .source_rsp_ready(child_source_rsp_ready),
        .source_rsp_data(source_data_hold), .source_rsp_error(source_error_hold),
        .cmd_valid(child_cmd_valid), .cmd_ready(child_selected && cmd_ready),
        .cmd_write(), .cmd_addr(child_addr), .cmd_wdata(),
        .result_valid(child_selected && result_valid), .result_ready(child_result_ready),
        .result_data(result_data), .result_error(result_error),
        .output_valid(child_output_valid), .output_ready(output_accepting),
        .output_index(child_output_index), .output_data(child_output_data),
        .output_last(child_output_last),
        .done_valid(child_valid),
        .done_ready(rst_n && state == CHILD_WAIT &&
            !child_source_valid && !child_output_valid),
        .done_error(child_error), .weight_read_event(), .weight_read_bytes(),
        .projection_event(projection_event), .projection_bytes(projection_bytes),
        .vector_live_bytes(vector_live_bytes), .vector_physical_bytes(vector_physical_bytes),
        .controller_bytes(feature_control), .native_controller_bytes(native_control),
        .modality_controller_bytes(modality_control)
    );
    assign start_ready = rst_n && state == IDLE;
    assign work_req_valid = rst_n && (state == SOURCE_SEND || state == PAIR_SEND);
    assign work_req_op = !rst_n ? 3'd0 : (state == SOURCE_SEND ? 3'd4 : 3'd6);
    assign work_req_domain = !rst_n ? 2'd0 : (state == SOURCE_SEND ? 2'd2 : 2'd3);
    assign work_req_target = !rst_n ? 2'd0 : (state == SOURCE_SEND ? 2'd1 : 2'd2);
    assign work_req_token = !rst_n ? 32'd0 :
        (state == SOURCE_SEND ? mapped_token_hold : token_hold);
    assign work_req_layer = !rst_n ? 8'd0 : (state == SOURCE_SEND ? 8'd12 : layer_hold);
    assign work_req_length = !rst_n ? 12'd0 :
        (state == SOURCE_SEND ? 12'd1024 : hidden_hold);
    assign work_req_component = !rst_n ? 12'd0 :
        (state == SOURCE_SEND ? {source_index_hold[11:1], 1'b0} : pair_component);
    assign work_req_slot = !rst_n ? 6'd0 :
        (state == SOURCE_SEND ? dependency_slot_hold : slot_hold);
    assign work_req_bank = 0;
    assign work_req_scalar_index = 0;
    assign work_req_data = rst_n ? pair_hold : 32'd0;
    assign work_rsp_ready = rst_n && (state == SOURCE_WAIT || state == PAIR_WAIT);
    assign cmd_valid = (child_selected && child_cmd_valid) || (map_selected && map_cmd_valid);
    assign cmd_write = 0;
    assign cmd_addr = map_selected ? map_addr : (child_selected ? child_addr : 64'd0);
    assign cmd_wdata = 0;
    assign result_ready = (child_selected && child_result_ready) || (map_selected && map_result_ready);
    assign done_valid = rst_n && state == RESPONSE;
    assign done_error = rst_n ? error_hold : 4'd0;
    assign done_yield = rst_n && yield_hold && error_hold == 0;
    assign done_bank = 0;
    assign done_continuation = rst_n && yield_hold ?
        {32'h454e3146, mapped_token_hold, 96'd0} : 160'd0;
    assign done_dependency_domain = rst_n && yield_hold ? 2'd2 : 2'd0;
    assign done_dependency_layer = rst_n && yield_hold ? 8'd12 : 8'd0;
    assign done_dependency_token = rst_n && yield_hold ? mapped_token_hold : 32'd0;
    assign done_dependency_length = rst_n && yield_hold ? 12'd1024 : 12'd0;
    assign source_read_event = rst_n && state == SOURCE_SEND && work_req_ready;
    assign source_read_bytes = source_read_event ? 32'd4 : 32'd0;
    assign nested_controller_bytes = rst_n ?
        feature_control + native_control + modality_control + map_control + map_nested_control : 64'd0;
    wire [31:0] CONTROLLER_BITS =
        $bits(state) + $bits(model_hold) + $bits(precision_hold) + $bits(mode_hold) + $bits(modality_hold) +
        $bits(dependency_domain_hold) + $bits(generation_hold) + $bits(frames_hold) +
        $bits(tokens_hold) + $bits(mapped_token_hold) + $bits(audio_hold) + $bits(tokens_base_hold) +
        $bits(token_hold) + $bits(received) + $bits(source_index_hold) + $bits(layer_hold) +
        $bits(dependency_layer_hold) + $bits(slot_hold) + $bits(dependency_slot_hold) +
        $bits(dependency_token_hold) + $bits(dependency_length_hold) + $bits(hidden_hold) +
        $bits(pair_component) + $bits(weights_hold) + $bits(continuation_hold) +
        $bits(dependency_valid_hold) + $bits(yield_hold) + $bits(receive_bad) +
        $bits(source_error_hold) + $bits(low_hold) + $bits(source_data_hold) +
        $bits(pair_hold) + $bits(source_pair_hold) + $bits(child_error_hold) +
        $bits(work_error_hold) + $bits(map_error_hold) + $bits(error_hold);
    assign controller_bytes = rst_n ? (CONTROLLER_BITS + 7) >> 3 : 64'd0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            model_hold <= 0;
            precision_hold <= 0;
            mode_hold <= 0;
            modality_hold <= 0;
            dependency_domain_hold <= 0;
            generation_hold <= 0;
            frames_hold <= 0;
            tokens_hold <= 0;
            mapped_token_hold <= 0;
            token_hold <= 0;
            received <= 0;
            source_index_hold <= 0;
            layer_hold <= 0;
            dependency_layer_hold <= 0;
            slot_hold <= 0;
            dependency_slot_hold <= 0;
            dependency_token_hold <= 0;
            dependency_length_hold <= 0;
            hidden_hold <= 0;
            pair_component <= 0;
            weights_hold <= 0;
            audio_hold <= 0;
            tokens_base_hold <= 0;
            continuation_hold <= 0;
            dependency_valid_hold <= 0;
            yield_hold <= 0;
            receive_bad <= 0;
            source_error_hold <= 0;
            low_hold <= 0;
            source_data_hold <= 0;
            pair_hold <= 0;
            source_pair_hold <= 0;
            child_error_hold <= 0;
            work_error_hold <= 0;
            map_error_hold <= 0;
            error_hold <= 0;
        end else begin
            case (state)
                IDLE: if (start_valid && start_ready) begin
                    model_hold <= model;
                    precision_hold <= precision;
                    mode_hold <= mode;
                    modality_hold <= modality;
                    generation_hold <= generation;
                    frames_hold <= frames;
                    tokens_hold <= tokens;
                    mapped_token_hold <= continuation[127:96];
                    token_hold <= token;
                    layer_hold <= frame_layer;
                    slot_hold <= frame_slot;
                    weights_hold <= audio_weights_base;
                    audio_hold <= audio_base;
                    tokens_base_hold <= tokens_base;
                    continuation_hold <= continuation;
                    dependency_valid_hold <= dependency_valid;
                    dependency_domain_hold <= dependency_domain;
                    dependency_layer_hold <= dependency_layer;
                    dependency_token_hold <= dependency_token;
                    dependency_length_hold <= dependency_length;
                    dependency_slot_hold <= dependency_slot;
                    hidden_hold <= COMPACT ? 12'd8 :
                        (model == 1 ? 12'd1536 : 12'd2560);
                    received <= 0;
                    receive_bad <= 0;
                    low_hold <= 0;
                    yield_hold <= 0;
                    source_error_hold <= 0;
                    source_data_hold <= 0;
                    child_error_hold <= 0;
                    work_error_hold <= 0;
                    map_error_hold <= 0;
                    error_hold <= 0;
                    state <= VALIDATE;
                end
                VALIDATE: begin
                    if ((model_hold != 1 && model_hold != 2) || precision_hold > 1) begin
                        error_hold <= 6;
                        state <= PUBLISH;
                    end else if (generation_hold == 0 || frames_hold == 0 ||
                        frames_hold > 131072 || tokens_hold == 0 || tokens_hold > 131072 ||
                        token_hold >= tokens_hold || tokens_base_hold[1:0] != 0 ||
                        audio_hold[1:0] != 0 || (modality_hold != 2 && modality_hold != 3) ||
                        weights_hold[1:0] != 0) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else if (layer_hold != 2 || mode_hold > 1 ||
                        (mode_hold == 0 && (continuation_hold != 0 || dependency_valid_hold)) ||
                        (mode_hold == 1 && (!continuation_tag_good ||
                            !dependency_valid_hold || !dependency_tag_good))) begin
                        error_hold <= 7;
                        state <= PUBLISH;
                    end else if (!dependency_valid_hold)
                        state <= MAP_START;
                    else
                        state <= CHILD_START;
                end
                MAP_START: if (map_ready)
                    state <= MAP_WAIT;
                MAP_WAIT: if (map_valid) begin
                    mapped_token_hold <= map_token;
                    map_error_hold <= map_error;
                    state <= MAP_CHECK;
                end
                MAP_CHECK: begin
                    if (map_error_hold != 0)
                        error_hold <= map_error_hold;
                    else if (mapped_token_hold >= ((frames_hold + 32'd3) >> 2))
                        error_hold <= 7;
                    else
                        yield_hold <= 1;
                    state <= PUBLISH;
                end
                CHILD_START: if (child_ready)
                    state <= CHILD_WAIT;
                CHILD_WAIT: begin
                    if (child_source_valid) begin
                        source_index_hold <= child_source_index;
                        source_data_hold <= 0;
                        source_error_hold <= !source_tag_good || error_hold != 0;
                        state <= SOURCE_VALIDATE;
                    end else if (child_output_valid) begin
                        if (!beat_good) begin
                            receive_bad <= 1;
                            if (error_hold == 0)
                                error_hold <= 7;
                        end
                        if (received < {20'd0, hidden_hold})
                            received <= received + 1'b1;
                        if (beat_good && !receive_bad && error_hold == 0) begin
                            if (!received[0])
                                low_hold <= child_output_data;
                            else begin
                                pair_hold <= {child_output_data, low_hold};
                                pair_component <= {received[11:1], 1'b0};
                                state <= PAIR_SEND;
                            end
                        end
                    end else if (child_valid) begin
                        child_error_hold <= child_error;
                        state <= CHILD_CHECK;
                    end
                end
                SOURCE_VALIDATE: begin
                    if (source_error_hold || !dependency_tag_good) begin
                        source_error_hold <= 1;
                        if (error_hold == 0)
                            error_hold <= 7;
                        state <= SOURCE_RESPONSE;
                    end else
                        state <= SOURCE_SEND;
                end
                SOURCE_SEND: if (work_req_ready)
                    state <= SOURCE_WAIT;
                SOURCE_WAIT: if (work_rsp_valid) begin
                    source_pair_hold <= work_rsp_data;
                    work_error_hold <= work_rsp_error;
                    state <= SOURCE_REGISTER;
                end
                SOURCE_REGISTER: begin
                    source_error_hold <= work_error_hold != 0;
                    if (work_error_hold != 0) begin
                        source_data_hold <= 0;
                        if (error_hold == 0)
                            error_hold <= work_error_hold;
                    end else
                        source_data_hold <= source_index_hold[0] ?
                            source_pair_hold[31:16] : source_pair_hold[15:0];
                    state <= SOURCE_RESPONSE;
                end
                SOURCE_RESPONSE: if (child_source_rsp_ready)
                    state <= CHILD_WAIT;
                PAIR_SEND: if (work_req_ready)
                    state <= PAIR_WAIT;
                PAIR_WAIT: if (work_rsp_valid) begin
                    work_error_hold <= work_rsp_error;
                    state <= PAIR_REGISTER;
                end
                PAIR_REGISTER: begin
                    if (work_error_hold != 0 && error_hold == 0)
                        error_hold <= work_error_hold;
                    state <= CHILD_WAIT;
                end
                CHILD_CHECK: begin
                    if (error_hold == 0) begin
                        if (child_error_hold != 0)
                            error_hold <= child_error_hold;
                        else if (receive_bad || received != {20'd0, hidden_hold} || received[0])
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
