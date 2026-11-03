module anvil_en1_replay_image_feature #(
    parameter integer COMPACT = 0
) (
    input wire clk, rst_n, cancel,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] model, precision, mode, modality,
    input wire [31:0] generation, tokens, token,
    input wire [31:0] patches, patch_rows, patch_columns,
    input wire [7:0] frame_layer,
    input wire [5:0] frame_slot,
    input wire [63:0] image_base, vision_weights_base, tokens_base,
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
    output wire projection_event, source_read_event, input_read_event,
    output wire [31:0] projection_bytes, source_read_bytes, input_read_bytes,
    output wire [63:0] vector_live_bytes, vector_physical_bytes,
    output wire [63:0] controller_bytes, nested_controller_bytes
);
    localparam [4:0] IDLE = 0, VALIDATE = 1, MAP_START = 2,
        MAP_WAIT = 3, MAP_CHECK = 4, CHILD_START = 5, CHILD_WAIT = 6,
        SOURCE_VALIDATE = 7, SOURCE_SEND = 8, SOURCE_WAIT = 9,
        SOURCE_REGISTER = 10, SOURCE_RESPONSE = 11,
        PAIR_SEND = 12, PAIR_WAIT = 13, PAIR_REGISTER = 14,
        CHILD_CHECK = 15, PUBLISH = 16, RESPONSE = 17,
        SUSPENDED = 18, RESUME = 19;
    reg [4:0] state;
    reg [1:0] model_hold, precision_hold, modality_hold;
    reg [31:0] generation_hold, tokens_hold, token_hold;
    reg [31:0] patches_hold, rows_hold, columns_hold, pool_count_hold;
    reg [31:0] ordinal_hold, count_hold, received, source_patch_hold, source_index_hold;
    reg [7:0] layer_hold;
    reg [5:0] slot_hold, dependency_slot_hold;
    reg [63:0] image_hold, weights_hold, tokens_base_hold;
    reg [11:0] hidden_hold, pair_component;
    reg [159:0] continuation_hold;
    reg [31:0] dependency_token_hold;
    reg [7:0] dependency_layer_hold;
    reg [11:0] dependency_length_hold;
    reg [1:0] dependency_domain_hold;
    reg dependency_valid_hold, yield_hold, receive_bad, source_error_hold;
    reg [15:0] low_hold, source_data_hold;
    reg [31:0] pair_hold, source_pair_hold;
    reg [3:0] child_error_hold, work_error_hold, map_error_hold, error_hold;

    initial begin
        if (COMPACT != 0 && COMPACT != 1)
            $fatal(1, "PARAMETER ERROR: COMPACT must be 0 or 1");
    end
    wire [159:0] expected_continuation =
        {32'h454e3149, generation_hold, token_hold, source_patch_hold, source_index_hold};
    wire dependency_tag_good = dependency_valid_hold && dependency_domain_hold == 1 &&
        dependency_layer_hold == 16 && dependency_token_hold == source_patch_hold &&
        dependency_length_hold == 768 && dependency_slot_hold < 16;
    wire resume_descriptor_good = model == model_hold && precision == precision_hold &&
        modality == modality_hold && generation == generation_hold &&
        tokens == tokens_hold && token == token_hold && frame_layer == layer_hold &&
        frame_slot == slot_hold && image_base == image_hold &&
        vision_weights_base == weights_hold && tokens_base == tokens_base_hold &&
        patches == patches_hold && patch_rows == rows_hold && patch_columns == columns_hold;
    wire map_selected = rst_n && !cancel && (state == MAP_START || state == MAP_WAIT);
    wire map_ready, map_valid, map_cmd_valid, map_result_ready;
    wire [31:0] map_ordinal, map_count;
    wire [63:0] map_addr, map_control, map_nested;
    wire [3:0] map_error;
    anvil_en1_native_token_map #(.COMPACT(COMPACT)) mapping (
        .clk(clk), .rst_n(rst_n),
        .start_valid(map_selected && state == MAP_START), .start_ready(map_ready),
        .model(model_hold), .modality(modality_hold), .kind(2'd1),
        .generation(generation_hold), .tokens(tokens_hold), .token(token_hold),
        .audio_frames(32'd0), .tokens_base(tokens_base_hold), .audio_base(64'd0),
        .cmd_valid(map_cmd_valid), .cmd_ready(map_selected && cmd_ready),
        .cmd_write(), .cmd_addr(map_addr), .cmd_wdata(),
        .result_valid(map_selected && result_valid), .result_ready(map_result_ready),
        .result_data(result_data), .result_error(result_error),
        .done_valid(map_valid), .done_ready(map_selected && state == MAP_WAIT),
        .done_ordinal(map_ordinal), .done_count(map_count), .done_native_token(),
        .done_error(map_error), .input_read_event(), .input_read_bytes(),
        .controller_bytes(map_control), .nested_controller_bytes(map_nested)
    );
    // A feature can depend only on lower-rank vision work, never another feature.
    // Keep its literal pooling FSM and RAM live while that dependency executes.
    wire child_rst_n = rst_n && !cancel && state != IDLE;
    wire child_selected = child_rst_n && state >= CHILD_START && state <= CHILD_CHECK;
    wire child_ready, child_valid, child_cmd_valid, child_result_ready;
    wire child_source_valid, child_source_rsp_ready, child_output_valid, child_output_last;
    wire [1:0] child_source_model;
    wire [7:0] child_source_layer;
    wire [31:0] child_source_generation, child_source_patch, child_source_index;
    wire [31:0] child_output_index;
    wire [15:0] child_output_data;
    wire [63:0] child_addr, child_live, child_physical;
    wire [63:0] soft_control, bins_control, feature_control, pool_control;
    wire [63:0] bins_div_control, pool_div_control, projection_control;
    wire [3:0] child_error;
    wire child_input_event;
    wire [31:0] child_input_bytes;
    wire source_tag_good = child_source_model == model_hold &&
        child_source_layer == 16 && child_source_generation == generation_hold &&
        child_source_patch < patches_hold && child_source_index < 768;
    wire beat_good = received < {20'd0, hidden_hold} &&
        child_output_index == received &&
        child_output_last == (received + 1'b1 == {20'd0, hidden_hold});
    wire output_accepting = rst_n && !cancel && state == CHILD_WAIT && !child_source_valid;
    anvil_en1_vision_soft_token #(.COMPACT(COMPACT)) feature (
        .clk(clk), .rst_n(child_rst_n),
        .start_valid(child_selected && state == CHILD_START), .start_ready(child_ready),
        .model(model_hold), .precision(precision_hold), .generation(generation_hold),
        .patches(patches_hold), .patch_rows(rows_hold), .patch_columns(columns_hold),
        .pool_count(pool_count_hold), .soft_token(ordinal_hold),
        .expected_soft_tokens(count_hold), .image_base(image_hold),
        .vision_weights_base(weights_hold),
        .source_valid(child_source_valid),
        .source_ready(rst_n && !cancel && state == CHILD_WAIT),
        .source_generation(child_source_generation), .source_patch(child_source_patch),
        .source_index(child_source_index), .source_model(child_source_model),
        .source_layer(child_source_layer),
        .source_rsp_valid(rst_n && !cancel && state == SOURCE_RESPONSE),
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
        .done_ready(rst_n && !cancel && state == CHILD_WAIT &&
            !child_source_valid && !child_output_valid),
        .done_pool_index(), .done_soft_tokens(), .done_error(child_error),
        .input_read_event(child_input_event), .input_read_bytes(child_input_bytes),
        .weight_read_event(), .weight_read_bytes(),
        .projection_event(projection_event), .projection_bytes(projection_bytes),
        .source_read_event(), .source_read_bytes(),
        .vector_live_bytes(child_live), .vector_physical_bytes(child_physical),
        .controller_bytes(soft_control), .mapping_controller_bytes(bins_control),
        .feature_controller_bytes(feature_control), .pool_controller_bytes(pool_control),
        .mapping_divider_controller_bytes(bins_div_control),
        .pool_divider_controller_bytes(pool_div_control),
        .projection_controller_bytes(projection_control)
    );
    wire divide_ready, divide_valid;
    wire [31:0] divide_quotient, divide_remainder;
    wire [3:0] divide_error;
    wire [63:0] divide_control;
    reg dividing;
    anvil_en1_uint_div pool_extent (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && !cancel && state == VALIDATE && !dividing),
        .start_ready(divide_ready), .numerator(patches_hold), .denominator(32'd9),
        .done_valid(divide_valid), .done_ready(rst_n && state == VALIDATE && dividing),
        .quotient(divide_quotient), .remainder(divide_remainder), .done_error(divide_error),
        .controller_bytes(divide_control)
    );
    assign start_ready = rst_n && !cancel && (state == IDLE || state == SUSPENDED);
    assign work_req_valid = rst_n && !cancel && (state == SOURCE_SEND || state == PAIR_SEND);
    assign work_req_op = !rst_n ? 3'd0 : (state == SOURCE_SEND ? 3'd4 : 3'd6);
    assign work_req_domain = !rst_n ? 2'd0 : (state == SOURCE_SEND ? 2'd1 : 2'd3);
    assign work_req_target = !rst_n ? 2'd0 : (state == SOURCE_SEND ? 2'd1 : 2'd2);
    assign work_req_token = !rst_n ? 32'd0 :
        (state == SOURCE_SEND ? source_patch_hold : token_hold);
    assign work_req_layer = !rst_n ? 8'd0 : (state == SOURCE_SEND ? 8'd16 : layer_hold);
    assign work_req_length = !rst_n ? 12'd0 :
        (state == SOURCE_SEND ? 12'd768 : hidden_hold);
    assign work_req_component = !rst_n ? 12'd0 :
        (state == SOURCE_SEND ? {source_index_hold[11:1], 1'b0} : pair_component);
    assign work_req_slot = !rst_n ? 6'd0 :
        (state == SOURCE_SEND ? dependency_slot_hold : slot_hold);
    assign work_req_bank = 0;
    assign work_req_scalar_index = 0;
    assign work_req_data = rst_n ? pair_hold : 32'd0;
    assign work_rsp_ready = rst_n && !cancel && (state == SOURCE_WAIT || state == PAIR_WAIT);
    assign cmd_valid = (map_selected && map_cmd_valid) || (child_selected && child_cmd_valid);
    assign cmd_write = 0;
    assign cmd_addr = map_selected ? map_addr : (child_selected ? child_addr : 64'd0);
    assign cmd_wdata = 0;
    assign result_ready = (map_selected && map_result_ready) || (child_selected && child_result_ready);
    assign done_valid = rst_n && !cancel && state == RESPONSE;
    assign done_error = rst_n ? error_hold : 4'd0;
    assign done_yield = rst_n && yield_hold && error_hold == 0;
    assign done_bank = 0;
    assign done_continuation = rst_n && yield_hold ? expected_continuation : 160'd0;
    assign done_dependency_domain = rst_n && yield_hold ? 2'd1 : 2'd0;
    assign done_dependency_layer = rst_n && yield_hold ? 8'd16 : 8'd0;
    assign done_dependency_token = rst_n && yield_hold ? source_patch_hold : 32'd0;
    assign done_dependency_length = rst_n && yield_hold ? 12'd768 : 12'd0;
    assign source_read_event = work_req_valid && work_req_ready && state == SOURCE_SEND;
    assign source_read_bytes = source_read_event ? 32'd4 : 32'd0;
    // Directory/coordinate traffic is input traffic; matrix traffic is counted
    // by the memory-map observer, not by relabeling all child reads as inputs.
    assign input_read_event = (map_selected && map_cmd_valid && cmd_ready) || child_input_event;
    assign input_read_bytes = (map_selected && map_cmd_valid && cmd_ready ? 32'd4 : 32'd0) +
        child_input_bytes;
    assign vector_live_bytes = rst_n ? child_live : 64'd0;
    assign vector_physical_bytes = !rst_n ? 64'd0 :
        (child_rst_n ? child_physical : 64'd6432);
    assign nested_controller_bytes = rst_n ? map_control + map_nested + divide_control +
        soft_control + bins_control + feature_control + pool_control +
        bins_div_control + pool_div_control + projection_control : 64'd0;
    wire [31:0] CONTROLLER_BITS =
        $bits(state) + $bits(model_hold) + $bits(precision_hold) + $bits(modality_hold) +
        $bits(generation_hold) + $bits(tokens_hold) + $bits(token_hold) +
        $bits(patches_hold) + $bits(rows_hold) + $bits(columns_hold) + $bits(pool_count_hold) +
        $bits(ordinal_hold) + $bits(count_hold) + $bits(received) +
        $bits(source_patch_hold) + $bits(source_index_hold) + $bits(layer_hold) +
        $bits(slot_hold) + $bits(dependency_slot_hold) + $bits(image_hold) +
        $bits(weights_hold) + $bits(tokens_base_hold) + $bits(hidden_hold) +
        $bits(pair_component) + $bits(continuation_hold) + $bits(dependency_token_hold) +
        $bits(dependency_layer_hold) + $bits(dependency_length_hold) +
        $bits(dependency_domain_hold) + $bits(dependency_valid_hold) + $bits(yield_hold) +
        $bits(receive_bad) + $bits(source_error_hold) + $bits(low_hold) +
        $bits(source_data_hold) + $bits(pair_hold) + $bits(source_pair_hold) +
        $bits(child_error_hold) + $bits(work_error_hold) + $bits(map_error_hold) +
        $bits(error_hold) + $bits(dividing);
    assign controller_bytes = rst_n ? (CONTROLLER_BITS + 7) >> 3 : 64'd0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            model_hold <= 0;
            precision_hold <= 0;
            modality_hold <= 0;
            generation_hold <= 0;
            tokens_hold <= 0;
            token_hold <= 0;
            patches_hold <= 0;
            rows_hold <= 0;
            columns_hold <= 0;
            pool_count_hold <= 0;
            ordinal_hold <= 0;
            count_hold <= 0;
            received <= 0;
            source_patch_hold <= 0;
            source_index_hold <= 0;
            layer_hold <= 0;
            slot_hold <= 0;
            dependency_slot_hold <= 0;
            image_hold <= 0;
            weights_hold <= 0;
            tokens_base_hold <= 0;
            hidden_hold <= 0;
            pair_component <= 0;
            continuation_hold <= 0;
            dependency_token_hold <= 0;
            dependency_layer_hold <= 0;
            dependency_length_hold <= 0;
            dependency_domain_hold <= 0;
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
            dividing <= 0;
        end else if (cancel) begin
            state <= IDLE;
            yield_hold <= 0;
            dependency_valid_hold <= 0;
            error_hold <= 0;
            dividing <= 0;
        end else begin
            case (state)
                IDLE: if (start_valid && start_ready) begin
                    model_hold <= model;
                    precision_hold <= precision;
                    modality_hold <= modality;
                    generation_hold <= generation;
                    tokens_hold <= tokens;
                    token_hold <= token;
                    patches_hold <= patches;
                    rows_hold <= patch_rows;
                    columns_hold <= patch_columns;
                    layer_hold <= frame_layer;
                    slot_hold <= frame_slot;
                    image_hold <= image_base;
                    weights_hold <= vision_weights_base;
                    tokens_base_hold <= tokens_base;
                    hidden_hold <= COMPACT ? 12'd8 :
                        (model == 1 ? 12'd1536 : 12'd2560);
                    received <= 0;
                    receive_bad <= 0;
                    low_hold <= 0;
                    yield_hold <= 0;
                    dependency_valid_hold <= 0;
                    error_hold <= 0;
                    dividing <= 0;
                    if (mode != 0 || continuation != 0 || dependency_valid) begin
                        error_hold <= 7;
                        state <= PUBLISH;
                    end else
                        state <= VALIDATE;
                end
                VALIDATE: begin
                    if (!dividing && divide_ready)
                        dividing <= 1;
                    if (dividing && divide_valid) begin
                        dividing <= 0;
                        if ((model_hold != 1 && model_hold != 2) || precision_hold > 1) begin
                            error_hold <= 6;
                            state <= PUBLISH;
                        end else if (generation_hold == 0 || tokens_hold == 0 ||
                            tokens_hold > 131072 || token_hold >= tokens_hold ||
                            patches_hold == 0 || patches_hold > 131072 ||
                            rows_hold == 0 || columns_hold == 0 ||
                            (modality_hold != 1 && modality_hold != 3) ||
                            image_hold[1:0] != 0 || weights_hold[1:0] != 0 ||
                            tokens_base_hold[1:0] != 0) begin
                            error_hold <= 5;
                            state <= PUBLISH;
                        end else if (layer_hold != 1 || divide_error != 0 ||
                            divide_remainder != 0 || divide_quotient == 0) begin
                            error_hold <= 7;
                            state <= PUBLISH;
                        end else begin
                            pool_count_hold <= divide_quotient;
                            state <= MAP_START;
                        end
                    end
                end
                MAP_START: if (map_ready)
                    state <= MAP_WAIT;
                MAP_WAIT: if (map_valid) begin
                    ordinal_hold <= map_ordinal;
                    count_hold <= map_count;
                    map_error_hold <= map_error;
                    state <= MAP_CHECK;
                end
                MAP_CHECK: begin
                    if (map_error_hold != 0) begin
                        error_hold <= map_error_hold;
                        state <= PUBLISH;
                    end else
                        state <= CHILD_START;
                end
                CHILD_START: if (child_ready)
                    state <= CHILD_WAIT;
                CHILD_WAIT: begin
                    if (child_source_valid) begin
                        source_patch_hold <= child_source_patch;
                        source_index_hold <= child_source_index;
                        source_error_hold <= !source_tag_good || error_hold != 0;
                        source_data_hold <= 0;
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
                    if (source_error_hold) begin
                        if (error_hold == 0)
                            error_hold <= 7;
                        state <= SOURCE_RESPONSE;
                    end else if (dependency_tag_good)
                        state <= SOURCE_SEND;
                    else begin
                        yield_hold <= 1;
                        state <= PUBLISH;
                    end
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
                RESPONSE: if (done_ready) begin
                    if (yield_hold && error_hold == 0)
                        state <= SUSPENDED;
                    else
                        state <= IDLE;
                end
                SUSPENDED: if (start_valid && start_ready) begin
                    yield_hold <= 0;
                    dependency_valid_hold <= dependency_valid;
                    dependency_domain_hold <= dependency_domain;
                    dependency_layer_hold <= dependency_layer;
                    dependency_token_hold <= dependency_token;
                    dependency_length_hold <= dependency_length;
                    dependency_slot_hold <= dependency_slot;
                    continuation_hold <= continuation;
                    if (mode != 1 || !resume_descriptor_good) begin
                        source_error_hold <= 1;
                        error_hold <= 7;
                    end
                    state <= RESUME;
                end
                RESUME: begin
                    if (source_error_hold || continuation_hold != expected_continuation ||
                        !dependency_tag_good) begin
                        source_error_hold <= 1;
                        error_hold <= 7;
                        state <= SOURCE_RESPONSE;
                    end else
                        state <= SOURCE_SEND;
                end
                default: begin
                    error_hold <= 7;
                    yield_hold <= 0;
                    state <= PUBLISH;
                end
            endcase
        end
    end
endmodule
