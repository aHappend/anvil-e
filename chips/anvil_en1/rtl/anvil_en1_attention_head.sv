module anvil_en1_attention_head #(
    parameter integer COMPACT = 0,
    parameter integer REPLAY = 0
) (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] model,
    input wire [7:0] layer,
    input wire [3:0] query_head,
    input wire [31:0] query_position,
    input wire resume_valid,
    input wire [383:0] resume_checkpoint,
    output wire need_valid,
    input wire need_ready,
    input wire [1:0] need_action,
    output wire [1:0] need_model,
    output wire [7:0] need_owner,
    output wire [31:0] need_token,
    output wire need_is_value,
    output wire [1:0] need_kv_head,
    output wire [9:0] need_component,
    output wire checkpoint_valid,
    input wire checkpoint_ready,
    output wire [383:0] checkpoint_data,
    output wire query_valid,
    input wire query_ready,
    output wire [9:0] query_component,
    input wire query_rsp_valid,
    output wire query_rsp_ready,
    input wire [15:0] query_rsp_data,
    input wire query_rsp_error,
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
    output wire component_valid,
    input wire component_ready,
    output wire [9:0] component_index,
    output wire [15:0] component_data,
    output wire component_last,
    output wire done_valid,
    input wire done_ready,
    output wire [3:0] done_error,
    output wire [3:0] attention_activity,
    output wire [63:0] controller_bytes
);
    generate if ((COMPACT != 0 && COMPACT != 1) ||
        (REPLAY != 0 && REPLAY != 1)) begin : invalid_parameters
        initial $fatal(1, "PARAMETER ERROR: COMPACT and REPLAY must be 0 or 1");
        assign start_ready = 0;
        assign need_valid = 0;
        assign need_model = 0;
        assign need_owner = 0;
        assign need_token = 0;
        assign need_is_value = 0;
        assign need_kv_head = 0;
        assign need_component = 0;
        assign checkpoint_valid = 0;
        assign checkpoint_data = 0;
        assign query_valid = 0;
        assign query_component = 0;
        assign query_rsp_ready = 0;
        assign mask_valid = 0;
        assign mask_token = 0;
        assign mask_rsp_ready = 0;
        assign req_valid = 0;
        assign req_op = 0;
        assign req_model = 0;
        assign req_layer = 0;
        assign req_token = 0;
        assign req_is_value = 0;
        assign req_kv_head = 0;
        assign req_component = 0;
        assign req_base = 0;
        assign rsp_ready = 0;
        assign fetch_valid = 0;
        assign fetch_model = 0;
        assign fetch_owner = 0;
        assign fetch_token = 0;
        assign fetch_is_value = 0;
        assign fetch_kv_head = 0;
        assign fetch_component = 0;
        assign fetch_rsp_ready = 0;
        assign component_valid = 0;
        assign component_index = 0;
        assign component_data = 0;
        assign component_last = 0;
        assign done_valid = 0;
        assign done_error = 0;
        assign attention_activity = 0;
        assign controller_bytes = 0;
    end else begin : attention
        localparam [5:0] IDLE = 0, VALIDATE = 1, MASK_START = 2,
            MASK_WAIT = 3, MASK_REGISTER = 4, QUERY_START = 5,
            QUERY_WAIT = 6, QUERY_REGISTER = 7, META_START = 8,
            META_WAIT = 9, META_REGISTER = 10, FETCH_START = 11,
            FETCH_WAIT = 12, FETCH_REGISTER = 13, DOT_MULTIPLY = 14,
            DOT_ADD = 15, DOT_ADVANCE = 16, SCORE = 17,
            EXP_ARGUMENT = 18, EXP_START = 19, EXP_WAIT = 20,
            EXP_REGISTER = 21, SUM_ADD = 22, PROBABILITY = 23,
            PROBABILITY_NARROW = 24, VALUE_REQUEST = 25,
            VALUE_MULTIPLY = 26, VALUE_ADD = 27, VALUE_ADVANCE = 28,
            KEY_ADVANCE = 29, PASS_FINISH = 30,
            INVERSE_START = 31, INVERSE_WAIT = 32,
            OUTPUT_NARROW = 33, OUTPUT_PREPARE = 34, OUTPUT_WAIT = 35,
            FP_START = 36, FP_WAIT = 37, PUBLISH = 38, RESPONSE = 39,
            REPLAY_NEED = 40, REPLAY_YIELD = 41, REPLAY_RESTORE = 42;
        reg [5:0] state, return_state;
        reg [1:0] model_hold, phase, head_hold;
        reg [7:0] layer_hold, owner_hold;
        reg [3:0] query_head_hold;
        reg [31:0] position_hold, first_token, token, active_keys;
        reg [9:0] dimension_hold, dot_component, output_component, cache_component;
        reg cache_selector, mask_hold, source_error_hold;
        reg [15:0] query_hold, cache_hold, probability_hold, output_hold;
        reg [31:0] dot_accumulator, maximum, exponential_sum, inverse_sum;
        reg [31:0] value_accumulator, value_hold, exponential, fp_a, fp_b, exp_a;
        reg [63:0] cache_addr_hold;
        reg cache_alias_hold;
        reg [1:0] cache_space_hold;
        reg [3:0] error_hold, cache_error_hold;
        reg [2:0] fp_op;
        reg resume_hold;
        reg [383:0] checkpoint_hold;
        localparam integer CONTROLLER_BITS = $bits({
            state, return_state, model_hold, phase, head_hold, layer_hold, owner_hold,
            query_head_hold, position_hold, first_token, token, active_keys,
            dimension_hold, dot_component, output_component, cache_component,
            cache_selector, mask_hold, source_error_hold, query_hold, cache_hold,
            probability_hold, output_hold, dot_accumulator, maximum, exponential_sum,
            inverse_sum, value_accumulator, value_hold, exponential, fp_a, fp_b,
            exp_a, cache_addr_hold, cache_alias_hold, cache_space_hold, error_hold,
            cache_error_hold, fp_op, resume_hold, checkpoint_hold
        });
        wire [63:0] fp_controller_bytes, exp_controller_bytes, div_controller_bytes;
        assign controller_bytes = !rst_n ? 64'd0 :
            64'((CONTROLLER_BITS+7) >> 3) + fp_controller_bytes +
            exp_controller_bytes + div_controller_bytes;
        wire native_model, is_global;
        wire [7:0] layer_count;
        wire fp_ready, fp_valid, exp_ready, exp_valid, inverse_ready, inverse_valid;
        wire [31:0] fp_data, exp_data, inverse_data;
        wire [3:0] fp_error, exp_error, inverse_error;
        wire [31:0] window_length = COMPACT ? 32'd4 : 32'd512;
        wire [9:0] selected_dimension = COMPACT ?
            (is_global ? 10'd8 : 10'd4) : (is_global ? 10'd512 : 10'd256);
        wire [31:0] selected_first = !is_global && position_hold >= window_length ?
            position_hold - window_length + 1'b1 : 32'd0;
        wire [31:0] selected_keys = position_hold - selected_first + 1'b1;
        wire checkpoint_descriptor_valid =
            checkpoint_hold[383:352] == 32'h454e3141 &&
            checkpoint_hold[351:343] == 0 &&
            checkpoint_hold[342:341] == model_hold &&
            checkpoint_hold[340:333] == layer_hold &&
            checkpoint_hold[332:329] == query_head_hold &&
            checkpoint_hold[328:297] == position_hold &&
            checkpoint_hold[296:265] >= selected_first &&
            checkpoint_hold[296:265] <= position_hold &&
            checkpoint_hold[264:233] != 0 &&
            checkpoint_hold[264:233] <= selected_keys &&
            checkpoint_hold[232:231] <= 2 &&
            checkpoint_hold[230:221] < selected_dimension &&
            checkpoint_hold[220:211] < selected_dimension &&
            checkpoint_hold[210:201] ==
                (checkpoint_hold[200] ? checkpoint_hold[220:211] :
                    checkpoint_hold[230:221]) &&
            (!checkpoint_hold[200] || checkpoint_hold[232:231] == 2);
        wire [383:0] live_checkpoint = {32'h454e3141, 9'd0,
            model_hold, layer_hold, query_head_hold, position_hold,
            token, active_keys, phase, dot_component, output_component,
            cache_component, cache_selector, owner_hold, query_hold,
            probability_hold, dot_accumulator, maximum, exponential_sum,
            inverse_sum, value_accumulator};
        wire max_nan = maximum[30:23] == 255 && maximum[22:0] != 0;
        wire score_nan = dot_accumulator[30:23] == 255 &&
            dot_accumulator[22:0] != 0;
        wire score_greater = maximum[31] != dot_accumulator[31] ?
            !dot_accumulator[31] : (dot_accumulator[31] ?
            dot_accumulator[30:0] < maximum[30:0] :
            dot_accumulator[30:0] > maximum[30:0]);

        anvil_en1_geometry geometry (
            .rst_n(rst_n), .model(model_hold), .layer(layer_hold),
            .is_native(native_model), .layers(layer_count), .owners(),
            .owner(), .is_global(is_global), .hidden(), .intermediate()
        );
        wire exp_phase = state == EXP_START || state == EXP_WAIT;
        wire exp_arithmetic_valid, exp_arithmetic_result_ready;
        wire [2:0] exp_arithmetic_operation;
        wire [31:0] exp_arithmetic_a, exp_arithmetic_b;
        anvil_en1_fp32 fp_unit (
            .controller_bytes(fp_controller_bytes),
            .clk(clk), .rst_n(rst_n),
            .start_valid(rst_n && (exp_phase ? exp_arithmetic_valid : state == FP_START)),
            .start_ready(fp_ready),
            .operation(exp_phase ? exp_arithmetic_operation : fp_op),
            .operand_a(exp_phase ? exp_arithmetic_a : fp_a),
            .operand_b(exp_phase ? exp_arithmetic_b : fp_b),
            .done_valid(fp_valid),
            .done_ready(exp_phase ? exp_arithmetic_result_ready : rst_n && state == FP_WAIT),
            .done_data(fp_data), .done_error(fp_error)
        );
        anvil_en1_exp #(.EXTERNAL_FP(1)) exp_unit (
            .controller_bytes(exp_controller_bytes),
            .clk(clk), .rst_n(rst_n),
            .start_valid(rst_n && state == EXP_START), .start_ready(exp_ready),
            .operand(exp_a),
            .done_valid(exp_valid), .done_ready(rst_n && state == EXP_WAIT),
            .done_data(exp_data), .done_error(exp_error),
            .arithmetic_valid(exp_arithmetic_valid),
            .arithmetic_ready(exp_phase && fp_ready),
            .arithmetic_operation(exp_arithmetic_operation),
            .arithmetic_a(exp_arithmetic_a), .arithmetic_b(exp_arithmetic_b),
            .arithmetic_result_valid(exp_phase && fp_valid),
            .arithmetic_result_ready(exp_arithmetic_result_ready),
            .arithmetic_result_data(fp_data), .arithmetic_result_error(fp_error)
        );
        anvil_en1_fp32_divsqrt inverse_unit (
            .controller_bytes(div_controller_bytes),
            .clk(clk), .rst_n(rst_n),
            .start_valid(rst_n && state == INVERSE_START), .start_ready(inverse_ready),
            .operation(2'd0), .operand_a(32'h3f800000), .operand_b(exponential_sum),
            .done_valid(inverse_valid), .done_ready(rst_n && state == INVERSE_WAIT),
            .done_data(inverse_data), .done_error(inverse_error)
        );

        assign start_ready = rst_n && state == IDLE;
        assign need_valid = rst_n && REPLAY && state == REPLAY_NEED;
        assign need_model = rst_n && REPLAY ? model_hold : 2'd0;
        assign need_owner = rst_n && REPLAY ? owner_hold : 8'd0;
        assign need_token = rst_n && REPLAY ? token : 32'd0;
        assign need_is_value = rst_n && REPLAY && cache_selector;
        assign need_kv_head = rst_n && REPLAY ? head_hold : 2'd0;
        assign need_component = rst_n && REPLAY ? cache_component : 10'd0;
        assign checkpoint_valid = rst_n && REPLAY && state == REPLAY_YIELD;
        assign checkpoint_data = rst_n && REPLAY ? live_checkpoint : 384'd0;
        assign query_valid = rst_n && state == QUERY_START;
        assign query_component = rst_n ? dot_component : 10'd0;
        assign query_rsp_ready = rst_n && state == QUERY_WAIT;
        assign mask_valid = rst_n && state == MASK_START;
        assign mask_token = rst_n ? token : 32'd0;
        assign mask_rsp_ready = rst_n && state == MASK_WAIT;
        assign req_valid = rst_n && state == META_START;
        assign req_op = 0;
        assign req_model = rst_n ? model_hold : 2'd0;
        assign req_layer = rst_n ? layer_hold : 8'd0;
        assign req_token = rst_n ? token : 32'd0;
        assign req_is_value = rst_n && cache_selector;
        assign req_kv_head = rst_n ? head_hold : 2'd0;
        assign req_component = rst_n ? cache_component : 10'd0;
        assign req_base = 0;
        assign rsp_ready = rst_n && state == META_WAIT;
        assign fetch_valid = rst_n && state == FETCH_START;
        assign fetch_model = rst_n ? model_hold : 2'd0;
        assign fetch_owner = rst_n ? owner_hold : 8'd0;
        assign fetch_token = rst_n ? token : 32'd0;
        assign fetch_is_value = rst_n && cache_selector;
        assign fetch_kv_head = rst_n ? head_hold : 2'd0;
        assign fetch_component = rst_n ? cache_component : 10'd0;
        assign fetch_rsp_ready = rst_n && state == FETCH_WAIT;
        assign component_valid = rst_n && state == OUTPUT_WAIT;
        assign component_index = rst_n ? output_component : 10'd0;
        assign component_data = rst_n ? output_hold : 16'd0;
        assign component_last = rst_n && state == OUTPUT_WAIT &&
            output_component == dimension_hold - 1'b1;
        assign done_valid = rst_n && state == RESPONSE;
        assign done_error = rst_n ? error_hold : 4'd0;
        wire lane_available = rst_n && native_model && layer_hold < layer_count &&
            state != IDLE && state != VALIDATE && state != PUBLISH &&
            state != RESPONSE;
        wire component_issue = lane_available && state == FP_START && fp_ready &&
            fp_op == 1 && (return_state == DOT_ADD || return_state == VALUE_ADD);
        assign attention_activity = {
            lane_available && is_global, lane_available && !is_global,
            component_issue && is_global, component_issue && !is_global
        };

        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                state <= IDLE;
                return_state <= 0;
                model_hold <= 0;
                phase <= 0;
                head_hold <= 0;
                layer_hold <= 0;
                owner_hold <= 0;
                query_head_hold <= 0;
                position_hold <= 0;
                first_token <= 0;
                token <= 0;
                active_keys <= 0;
                dimension_hold <= 0;
                dot_component <= 0;
                output_component <= 0;
                cache_component <= 0;
                cache_selector <= 0;
                mask_hold <= 0;
                source_error_hold <= 0;
                query_hold <= 0;
                cache_hold <= 0;
                probability_hold <= 0;
                output_hold <= 0;
                dot_accumulator <= 0;
                maximum <= 0;
                exponential_sum <= 0;
                inverse_sum <= 0;
                value_accumulator <= 0;
                value_hold <= 0;
                exponential <= 0;
                fp_a <= 0;
                fp_b <= 0;
                exp_a <= 0;
                cache_addr_hold <= 0;
                cache_alias_hold <= 0;
                cache_space_hold <= 0;
                error_hold <= 0;
                cache_error_hold <= 0;
                fp_op <= 0;
                resume_hold <= 0;
                checkpoint_hold <= 0;
            end else begin
                case (state)
                    IDLE: if (start_valid && start_ready) begin
                        model_hold <= model;
                        layer_hold <= layer;
                        query_head_hold <= query_head;
                        position_hold <= query_position;
                        output_hold <= 0;
                        error_hold <= 0;
                        phase <= 0;
                        active_keys <= 0;
                        maximum <= 32'hff800000;
                        exponential_sum <= 0;
                        value_accumulator <= 0;
                        output_component <= 0;
                        resume_hold <= REPLAY && resume_valid;
                        if (REPLAY)
                            checkpoint_hold <= resume_checkpoint;
                        state <= VALIDATE;
                    end
                    VALIDATE: begin
                        if (!native_model) begin
                            error_hold <= 6;
                            state <= PUBLISH;
                        end else if (layer_hold >= layer_count || position_hold > 131071 ||
                            query_head_hold >= (COMPACT ? 4'd2 : 4'd8)) begin
                            error_hold <= 5;
                            state <= PUBLISH;
                        end else begin
                            dimension_hold <= selected_dimension;
                            head_hold <= COMPACT || model_hold == 1 ? 2'd0 :
                                query_head_hold[3:2];
                            first_token <= selected_first;
                            if (resume_hold)
                                state <= REPLAY_RESTORE;
                            else begin
                                token <= selected_first;
                                state <= MASK_START;
                            end
                        end
                    end
                    REPLAY_RESTORE: begin
                        if (!REPLAY || !checkpoint_descriptor_valid) begin
                            error_hold <= 7;
                            state <= PUBLISH;
                        end else begin
                            token <= checkpoint_hold[296:265];
                            active_keys <= checkpoint_hold[264:233];
                            phase <= checkpoint_hold[232:231];
                            dot_component <= checkpoint_hold[230:221];
                            output_component <= checkpoint_hold[220:211];
                            cache_component <= checkpoint_hold[210:201];
                            cache_selector <= checkpoint_hold[200];
                            query_hold <= checkpoint_hold[191:176];
                            probability_hold <= checkpoint_hold[175:160];
                            dot_accumulator <= checkpoint_hold[159:128];
                            maximum <= checkpoint_hold[127:96];
                            exponential_sum <= checkpoint_hold[95:64];
                            inverse_sum <= checkpoint_hold[63:32];
                            value_accumulator <= checkpoint_hold[31:0];
                            source_error_hold <= 0;
                            cache_error_hold <= 0;
                            state <= META_START;
                        end
                    end
                    MASK_START: if (mask_ready)
                        state <= MASK_WAIT;
                    MASK_WAIT: if (mask_rsp_valid) begin
                        mask_hold <= mask_rsp_data;
                        source_error_hold <= mask_rsp_error;
                        state <= MASK_REGISTER;
                    end
                    MASK_REGISTER: begin
                        if (source_error_hold) begin
                            error_hold <= 7;
                            state <= PUBLISH;
                        end else if (!mask_hold)
                            state <= KEY_ADVANCE;
                        else begin
                            dot_component <= 0;
                            dot_accumulator <= 0;
                            if (phase == 0)
                                active_keys <= active_keys + 1'b1;
                            state <= QUERY_START;
                        end
                    end
                    QUERY_START: if (query_ready)
                        state <= QUERY_WAIT;
                    QUERY_WAIT: if (query_rsp_valid) begin
                        query_hold <= query_rsp_data;
                        source_error_hold <= query_rsp_error;
                        state <= QUERY_REGISTER;
                    end
                    QUERY_REGISTER: begin
                        if (source_error_hold) begin
                            error_hold <= 7;
                            state <= PUBLISH;
                        end else begin
                            cache_selector <= 0;
                            cache_component <= dot_component;
                            state <= META_START;
                        end
                    end
                    META_START: if (req_ready)
                        state <= META_WAIT;
                    META_WAIT: if (rsp_valid) begin
                        owner_hold <= rsp_owner;
                        cache_addr_hold <= rsp_addr;
                        cache_space_hold <= rsp_space;
                        cache_alias_hold <= rsp_alias;
                        cache_error_hold <= rsp_error;
                        state <= META_REGISTER;
                    end
                    META_REGISTER: begin
                        if (cache_error_hold != 0) begin
                            error_hold <= cache_error_hold;
                            state <= PUBLISH;
                        end else if (cache_space_hold == 0 || cache_space_hold == 3 ||
                            cache_addr_hold[1:0] != 0) begin
                            error_hold <= 7;
                            state <= PUBLISH;
                        end else if (REPLAY)
                            state <= REPLAY_NEED;
                        else
                            state <= FETCH_START;
                    end
                    REPLAY_NEED: if (need_valid && need_ready) begin
                        if (need_action == 0)
                            state <= FETCH_START;
                        else if (need_action == 1)
                            state <= REPLAY_YIELD;
                        else begin
                            error_hold <= 7;
                            state <= PUBLISH;
                        end
                    end
                    REPLAY_YIELD: if (checkpoint_valid && checkpoint_ready)
                        state <= IDLE;
                    FETCH_START: if (fetch_ready)
                        state <= FETCH_WAIT;
                    FETCH_WAIT: if (fetch_rsp_valid) begin
                        cache_hold <= fetch_rsp_data;
                        cache_error_hold <= fetch_rsp_error;
                        state <= FETCH_REGISTER;
                    end
                    FETCH_REGISTER: begin
                        if (cache_error_hold != 0) begin
                            error_hold <= cache_error_hold;
                            state <= PUBLISH;
                        end else if (cache_selector)
                            state <= VALUE_MULTIPLY;
                        else
                            state <= DOT_MULTIPLY;
                    end
                    DOT_MULTIPLY: begin
                        fp_op <= 1;
                        fp_a <= {query_hold, 16'd0};
                        fp_b <= {cache_hold, 16'd0};
                        return_state <= DOT_ADD;
                        state <= FP_START;
                    end
                    DOT_ADD: begin
                        fp_op <= 0;
                        fp_a <= dot_accumulator;
                        fp_b <= value_hold;
                        return_state <= DOT_ADVANCE;
                        state <= FP_START;
                    end
                    DOT_ADVANCE: begin
                        dot_accumulator <= value_hold;
                        if (dot_component == dimension_hold - 1'b1)
                            state <= SCORE;
                        else begin
                            dot_component <= dot_component + 1'b1;
                            state <= QUERY_START;
                        end
                    end
                    SCORE: begin
                        if (phase == 0) begin
                            if (score_nan)
                                maximum <= 32'h7fc00000;
                            else if (!max_nan && score_greater)
                                maximum <= dot_accumulator;
                            state <= KEY_ADVANCE;
                        end else
                            state <= EXP_ARGUMENT;
                    end
                    EXP_ARGUMENT: begin
                        fp_op <= 0;
                        fp_a <= dot_accumulator;
                        fp_b <= {~maximum[31], maximum[30:0]};
                        return_state <= EXP_START;
                        state <= FP_START;
                    end
                    EXP_START: if (exp_ready)
                        state <= EXP_WAIT;
                    EXP_WAIT: if (exp_valid) begin
                        if (exp_error != 0) begin
                            error_hold <= exp_error;
                            state <= PUBLISH;
                        end else begin
                            exponential <= exp_data;
                            state <= EXP_REGISTER;
                        end
                    end
                    EXP_REGISTER: begin
                        if (phase == 1)
                            state <= SUM_ADD;
                        else
                            state <= PROBABILITY;
                    end
                    SUM_ADD: begin
                        fp_op <= 0;
                        fp_a <= exponential_sum;
                        fp_b <= exponential;
                        return_state <= KEY_ADVANCE;
                        state <= FP_START;
                    end
                    PROBABILITY: begin
                        fp_op <= 1;
                        fp_a <= exponential;
                        fp_b <= inverse_sum;
                        return_state <= PROBABILITY_NARROW;
                        state <= FP_START;
                    end
                    PROBABILITY_NARROW: begin
                        fp_op <= 3;
                        fp_a <= value_hold;
                        fp_b <= 0;
                        return_state <= VALUE_REQUEST;
                        state <= FP_START;
                    end
                    VALUE_REQUEST: begin
                        probability_hold <= value_hold[15:0];
                        cache_selector <= 1;
                        cache_component <= output_component;
                        state <= META_START;
                    end
                    VALUE_MULTIPLY: begin
                        fp_op <= 1;
                        fp_a <= {probability_hold, 16'd0};
                        fp_b <= {cache_hold, 16'd0};
                        return_state <= VALUE_ADD;
                        state <= FP_START;
                    end
                    VALUE_ADD: begin
                        fp_op <= 0;
                        fp_a <= value_accumulator;
                        fp_b <= value_hold;
                        return_state <= VALUE_ADVANCE;
                        state <= FP_START;
                    end
                    VALUE_ADVANCE: begin
                        value_accumulator <= value_hold;
                        state <= KEY_ADVANCE;
                    end
                    KEY_ADVANCE: begin
                        if (token == position_hold)
                            state <= PASS_FINISH;
                        else begin
                            token <= token + 1'b1;
                            state <= MASK_START;
                        end
                    end
                    PASS_FINISH: begin
                        token <= first_token;
                        if (phase == 0) begin
                            if (active_keys == 0)
                                state <= OUTPUT_NARROW;
                            else begin
                                phase <= 1;
                                state <= MASK_START;
                            end
                        end else if (phase == 1)
                            state <= INVERSE_START;
                        else
                            state <= OUTPUT_NARROW;
                    end
                    INVERSE_START: if (inverse_ready)
                        state <= INVERSE_WAIT;
                    INVERSE_WAIT: if (inverse_valid) begin
                        if (inverse_error != 0) begin
                            error_hold <= inverse_error;
                            state <= PUBLISH;
                        end else begin
                            inverse_sum <= inverse_data;
                            phase <= 2;
                            token <= first_token;
                            state <= MASK_START;
                        end
                    end
                    OUTPUT_NARROW: begin
                        fp_op <= 3;
                        fp_a <= value_accumulator;
                        fp_b <= 0;
                        return_state <= OUTPUT_PREPARE;
                        state <= FP_START;
                    end
                    OUTPUT_PREPARE: begin
                        output_hold <= value_hold[15:0];
                        state <= OUTPUT_WAIT;
                    end
                    OUTPUT_WAIT: if (component_ready) begin
                        if (output_component == dimension_hold - 1'b1)
                            state <= PUBLISH;
                        else begin
                            output_component <= output_component + 1'b1;
                            value_accumulator <= 0;
                            token <= first_token;
                            if (active_keys == 0)
                                state <= OUTPUT_NARROW;
                            else
                                state <= MASK_START;
                        end
                    end
                    FP_START: if (fp_ready)
                        state <= FP_WAIT;
                    FP_WAIT: if (fp_valid) begin
                        if (fp_error != 0) begin
                            error_hold <= fp_error;
                            state <= PUBLISH;
                        end else begin
                            value_hold <= fp_data;
                            if (return_state == EXP_START)
                                exp_a <= fp_data;
                            if (return_state == KEY_ADVANCE && phase == 1)
                                exponential_sum <= fp_data;
                            state <= return_state;
                        end
                    end
                    PUBLISH: state <= RESPONSE;
                    RESPONSE: if (done_ready)
                        state <= IDLE;
                    default: begin
                        output_hold <= 0;
                        error_hold <= 7;
                        state <= PUBLISH;
                    end
                endcase
            end
        end
    endgenerate
endmodule
