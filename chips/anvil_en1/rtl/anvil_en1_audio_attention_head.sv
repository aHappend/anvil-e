module anvil_en1_audio_attention_head #(
    parameter integer REPLAY = 0
) (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] model, precision,
    input wire [31:0] generation, tokens, query_token,
    input wire [7:0] layer,
    input wire [2:0] head,
    input wire resume_valid,
    input wire [1023:0] resume_checkpoint,
    output wire mask_valid,
    input wire mask_ready,
    output wire [31:0] mask_token,
    input wire mask_rsp_valid,
    output wire mask_rsp_ready,
    input wire mask_rsp_data, mask_rsp_error,
    output wire need_valid,
    input wire need_ready,
    input wire [1:0] need_action,
    output wire qkv_valid,
    input wire qkv_ready,
    output wire [1:0] qkv_model, qkv_precision, qkv_selector,
    output wire [31:0] qkv_generation, qkv_token,
    output wire [7:0] qkv_layer,
    output wire [2:0] qkv_head,
    output wire [9:0] qkv_component,
    input wire qkv_rsp_valid,
    output wire qkv_rsp_ready,
    input wire [63:0] qkv_rsp_data,
    input wire [3:0] qkv_rsp_error,
    output wire checkpoint_valid,
    input wire checkpoint_ready,
    output reg [1023:0] checkpoint_data,
    output wire output_valid,
    input wire output_ready,
    output wire [9:0] output_index,
    output wire [15:0] output_data,
    output wire output_last,
    output wire done_valid,
    input wire done_ready,
    output wire done_yield,
    output wire [3:0] done_error,
    output wire [63:0] controller_bytes
);
    localparam [5:0] IDLE = 0, VALIDATE = 1, BLOCK_START = 2,
        BLOCK_WAIT = 3, BLOCK_REGISTER = 4, RESTORE = 5,
        KEY_SETUP = 6, KEY_REGISTER = 7, MASK_SEND = 8,
        MASK_WAIT = 9, MASK_REGISTER = 10, DOT_SETUP = 11,
        MASKED_SCORE = 12, NEED = 13, SERVICE_SEND = 14,
        SERVICE_WAIT = 15, SERVICE_REGISTER = 16,
        CONTENT_MULTIPLY = 17, CONTENT_ADD = 18, CONTENT_REGISTER = 19,
        RELATIVE_MULTIPLY = 20, RELATIVE_ADD = 21, DOT_ADVANCE = 22,
        SCORE_SUM = 23, SOFTCAP_START = 24, SOFTCAP_WAIT = 25,
        SCORE_REGISTER = 26, SCORE_PROCESS = 27, EXP_ARGUMENT = 28,
        EXP_START = 29, EXP_WAIT = 30, EXP_REGISTER = 31,
        SUM_ADD = 32, SUM_REGISTER = 33, PROBABILITY = 34,
        VALUE_SETUP = 35, VALUE_MULTIPLY = 36, VALUE_ADD = 37,
        VALUE_REGISTER = 38, KEY_ADVANCE = 39, PASS_FINISH = 40,
        INVERSE_START = 41, INVERSE_WAIT = 42, OUTPUT_NARROW = 43,
        OUTPUT_REGISTER = 44, EMIT = 45, OUTPUT_ADVANCE = 46,
        FP_START = 47, FP_WAIT = 48, YIELD = 49,
        PUBLISH = 50, RESPONSE = 51;
    reg [5:0] state, fp_return;
    reg [1:0] model_hold, precision_hold, phase, selector_hold;
    reg [31:0] generation_hold, tokens_hold, query_hold, block_start_hold;
    reg [31:0] block_quotient, key_token_hold;
    reg [3:0] block_offset;
    reg [4:0] key_column;
    reg [6:0] dot_component, output_component;
    reg [7:0] layer_hold;
    reg [2:0] head_hold;
    reg [32:0] key_position;
    reg allowed_hold, padded_hold, mask_hold, mask_error_hold, resume_hold, yield_hold;
    reg [1023:0] checkpoint_hold;
    reg [63:0] pair_hold;
    reg [31:0] query_component_hold, service_component_hold;
    reg [31:0] content_accumulator, relative_accumulator, maximum, exponential_sum;
    reg [31:0] inverse_sum, value_accumulator, exponential, probability, score_hold;
    reg [31:0] fp_a, fp_b, fp_value, exp_operand;
    reg [2:0] fp_op;
    reg [15:0] output_hold;
    reg [3:0] service_error_hold, error_hold;

    initial begin
        if (REPLAY != 0 && REPLAY != 1)
            $fatal(1, "PARAMETER ERROR: REPLAY must be 0 or 1");
    end
    wire block_ready, block_valid;
    wire [31:0] block_data, block_remainder;
    wire [3:0] block_error;
    anvil_en1_uint_div blocks (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == BLOCK_START), .start_ready(block_ready),
        .numerator(query_hold), .denominator(32'd12),
        .done_valid(block_valid), .done_ready(rst_n && state == BLOCK_WAIT),
        .quotient(block_data), .remainder(block_remainder),
        .done_error(block_error)
    );
    wire fp_ready, fp_valid, exp_ready, exp_valid, inverse_ready, inverse_valid;
    wire cap_ready, cap_valid;
    wire [31:0] fp_data, exp_data, inverse_data, cap_data;
    wire [3:0] fp_error, exp_error, inverse_error, cap_error;
    anvil_en1_fp32 arithmetic (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == FP_START), .start_ready(fp_ready),
        .operation(fp_op), .operand_a(fp_a), .operand_b(fp_b),
        .done_valid(fp_valid), .done_ready(rst_n && state == FP_WAIT),
        .done_data(fp_data), .done_error(fp_error)
    );
    anvil_en1_softcap cap (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == SOFTCAP_START), .start_ready(cap_ready),
        .cap_50(1'b1), .input_binary32(1'b1), .output_binary32(1'b1),
        .operand(fp_value), .done_valid(cap_valid),
        .done_ready(rst_n && state == SOFTCAP_WAIT),
        .done_data(cap_data), .done_error(cap_error)
    );
    anvil_en1_exp exponent (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == EXP_START), .start_ready(exp_ready),
        .operand(exp_operand), .done_valid(exp_valid),
        .done_ready(rst_n && state == EXP_WAIT),
        .done_data(exp_data), .done_error(exp_error)
    );
    anvil_en1_fp32_divsqrt reciprocal (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == INVERSE_START), .start_ready(inverse_ready),
        .operation(2'd0), .operand_a(32'h3f800000), .operand_b(exponential_sum),
        .done_valid(inverse_valid), .done_ready(rst_n && state == INVERSE_WAIT),
        .done_data(inverse_data), .done_error(inverse_error)
    );
    wire [6:0] service_component = selector_hold == 2 ?
        output_component : dot_component;
    wire [31:0] service_word = service_component[0] ? pair_hold[63:32] : pair_hold[31:0];
    wire key_in_range = !key_position[32] && key_position[31:0] < tokens_hold;
    wire key_causal = key_in_range && key_position[31:0] <= query_hold &&
        query_hold - key_position[31:0] < 12;
    wire maximum_nan = maximum[30:23] == 255 && maximum[22:0] != 0;
    wire score_nan = score_hold[30:23] == 255 && score_hold[22:0] != 0;
    wire both_zero = maximum[30:0] == 0 && score_hold[30:0] == 0;
    wire score_greater = !both_zero && (maximum[31] != score_hold[31] ?
        !score_hold[31] : (score_hold[31] ?
        score_hold[30:0] < maximum[30:0] : score_hold[30:0] > maximum[30:0]));
    wire [32:0] restored_key_position = {1'b0, block_start_hold} +
        {1'b0, checkpoint_hold[223:192]} - 33'd12;
    wire restored_in_range = !restored_key_position[32] &&
        restored_key_position[31:0] < tokens_hold;
    wire restored_causal = restored_in_range && restored_key_position[31:0] <= query_hold &&
        query_hold - restored_key_position[31:0] < 12;
    wire checkpoint_matches =
        checkpoint_hold[31:0] == 32'h454e3141 &&
        checkpoint_hold[63:32] == generation_hold &&
        checkpoint_hold[67:64] == {precision_hold, model_hold} &&
        checkpoint_hold[75:68] == layer_hold &&
        checkpoint_hold[78:76] == head_hold &&
        checkpoint_hold[80:79] <= 2 &&
        checkpoint_hold[95:83] == 0 &&
        checkpoint_hold[127:96] == tokens_hold &&
        checkpoint_hold[159:128] == query_hold &&
        checkpoint_hold[191:160] == block_start_hold &&
        checkpoint_hold[223:192] < 24 &&
        checkpoint_hold[255:231] == 0 && checkpoint_hold[287:263] == 0 &&
        checkpoint_hold[351:320] == 0 &&
        checkpoint_hold[671:642] == 0 &&
        checkpoint_hold[640] == !restored_in_range &&
        (!checkpoint_hold[641] || restored_causal) &&
        (checkpoint_hold[82:81] == 2 ?
            checkpoint_hold[80:79] == 2 : checkpoint_hold[641]) &&
        (checkpoint_hold[80:79] == 2 || checkpoint_hold[262:256] == 0) &&
        checkpoint_hold[703:672] == {28'd0, block_offset} &&
        checkpoint_hold[1023:704] == 0;
    always @* begin
        checkpoint_data = 0;
        if (rst_n && REPLAY) begin
            checkpoint_data[31:0] = 32'h454e3141;
            checkpoint_data[63:32] = generation_hold;
            checkpoint_data[95:64] =
                {13'd0, selector_hold, phase, head_hold, layer_hold, precision_hold, model_hold};
            checkpoint_data[127:96] = tokens_hold;
            checkpoint_data[159:128] = query_hold;
            checkpoint_data[191:160] = block_start_hold;
            checkpoint_data[223:192] = {27'd0, key_column};
            checkpoint_data[255:224] = {25'd0, dot_component};
            checkpoint_data[287:256] = {25'd0, output_component};
            checkpoint_data[319:288] = query_component_hold;
            checkpoint_data[351:320] = 0;
            checkpoint_data[383:352] = content_accumulator;
            checkpoint_data[415:384] = relative_accumulator;
            checkpoint_data[447:416] = maximum;
            checkpoint_data[479:448] = exponential_sum;
            checkpoint_data[511:480] = inverse_sum;
            checkpoint_data[543:512] = value_accumulator;
            checkpoint_data[575:544] = exponential;
            checkpoint_data[607:576] = probability;
            checkpoint_data[639:608] = score_hold;
            checkpoint_data[671:640] = {30'd0, allowed_hold, padded_hold};
            checkpoint_data[703:672] = {28'd0, block_offset};
        end
    end
    assign start_ready = rst_n && state == IDLE;
    assign mask_valid = rst_n && state == MASK_SEND;
    assign mask_token = rst_n ? key_token_hold : 32'd0;
    assign mask_rsp_ready = rst_n && state == MASK_WAIT;
    assign need_valid = rst_n && REPLAY && state == NEED;
    assign qkv_valid = rst_n && state == SERVICE_SEND;
    assign qkv_model = rst_n ? model_hold : 2'd0;
    assign qkv_precision = rst_n ? precision_hold : 2'd0;
    assign qkv_selector = rst_n ? selector_hold : 2'd0;
    assign qkv_generation = rst_n ? generation_hold : 32'd0;
    assign qkv_token = !rst_n ? 32'd0 :
        (selector_hold == 0 ? query_hold :
        (selector_hold == 3 ? query_hold - key_token_hold : key_token_hold));
    assign qkv_layer = rst_n ? layer_hold : 8'd0;
    assign qkv_head = rst_n ? head_hold : 3'd0;
    assign qkv_component = rst_n ? {3'd0, service_component[6:1], 1'b0} : 10'd0;
    assign qkv_rsp_ready = rst_n && state == SERVICE_WAIT;
    assign checkpoint_valid = rst_n && REPLAY && state == YIELD;
    assign output_valid = rst_n && state == EMIT;
    assign output_index = rst_n ? {3'd0, output_component} : 10'd0;
    assign output_data = rst_n ? output_hold : 16'd0;
    assign output_last = rst_n && state == EMIT && output_component == 127;
    assign done_valid = rst_n && state == RESPONSE;
    assign done_yield = rst_n && yield_hold;
    assign done_error = rst_n ? error_hold : 4'd0;
    localparam integer CONTROLLER_BITS =
        $bits(state) + $bits(fp_return) + $bits(model_hold) + $bits(precision_hold) +
        $bits(phase) + $bits(selector_hold) + $bits(generation_hold) + $bits(tokens_hold) +
        $bits(query_hold) + $bits(block_start_hold) + $bits(block_quotient) +
        $bits(key_token_hold) + $bits(block_offset) + $bits(key_column) +
        $bits(dot_component) + $bits(output_component) + $bits(layer_hold) +
        $bits(head_hold) + $bits(key_position) + $bits(allowed_hold) +
        $bits(padded_hold) + $bits(mask_hold) + $bits(mask_error_hold) +
        $bits(resume_hold) + $bits(yield_hold) + $bits(checkpoint_hold) +
        $bits(pair_hold) + $bits(query_component_hold) + $bits(service_component_hold) +
        $bits(content_accumulator) + $bits(relative_accumulator) + $bits(maximum) +
        $bits(exponential_sum) + $bits(inverse_sum) + $bits(value_accumulator) +
        $bits(exponential) + $bits(probability) + $bits(score_hold) +
        $bits(fp_a) + $bits(fp_b) + $bits(fp_value) + $bits(exp_operand) +
        $bits(fp_op) + $bits(output_hold) + $bits(service_error_hold) + $bits(error_hold);
    assign controller_bytes = rst_n ? (CONTROLLER_BITS + 7) >> 3 : 64'd0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            fp_return <= 0;
            model_hold <= 0;
            precision_hold <= 0;
            phase <= 0;
            selector_hold <= 0;
            generation_hold <= 0;
            tokens_hold <= 0;
            query_hold <= 0;
            block_start_hold <= 0;
            block_quotient <= 0;
            key_token_hold <= 0;
            block_offset <= 0;
            key_column <= 0;
            dot_component <= 0;
            output_component <= 0;
            layer_hold <= 0;
            head_hold <= 0;
            key_position <= 0;
            allowed_hold <= 0;
            padded_hold <= 0;
            mask_hold <= 0;
            mask_error_hold <= 0;
            resume_hold <= 0;
            yield_hold <= 0;
            checkpoint_hold <= 0;
            pair_hold <= 0;
            query_component_hold <= 0;
            service_component_hold <= 0;
            content_accumulator <= 0;
            relative_accumulator <= 0;
            maximum <= 0;
            exponential_sum <= 0;
            inverse_sum <= 0;
            value_accumulator <= 0;
            exponential <= 0;
            probability <= 0;
            score_hold <= 0;
            fp_a <= 0;
            fp_b <= 0;
            fp_value <= 0;
            exp_operand <= 0;
            fp_op <= 0;
            output_hold <= 0;
            service_error_hold <= 0;
            error_hold <= 0;
        end else begin
            case (state)
                IDLE: if (start_valid && start_ready) begin
                    model_hold <= model;
                    precision_hold <= precision;
                    generation_hold <= generation;
                    tokens_hold <= tokens;
                    query_hold <= query_token;
                    layer_hold <= layer;
                    head_hold <= head;
                    phase <= 0;
                    selector_hold <= 0;
                    key_column <= 0;
                    dot_component <= 0;
                    output_component <= 0;
                    content_accumulator <= 0;
                    relative_accumulator <= 0;
                    maximum <= 32'hff800000;
                    exponential_sum <= 0;
                    inverse_sum <= 0;
                    value_accumulator <= 0;
                    output_hold <= 0;
                    error_hold <= 0;
                    yield_hold <= 0;
                    resume_hold <= REPLAY && resume_valid;
                    if (REPLAY)
                        checkpoint_hold <= resume_checkpoint;
                    state <= VALIDATE;
                end
                VALIDATE: begin
                    if ((model_hold != 1 && model_hold != 2) || precision_hold > 1) begin
                        error_hold <= 6;
                        state <= PUBLISH;
                    end else if (generation_hold == 0 || tokens_hold == 0 ||
                        tokens_hold > 131072 || query_hold >= tokens_hold || layer_hold >= 12) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else
                        state <= BLOCK_START;
                end
                BLOCK_START: if (block_ready)
                    state <= BLOCK_WAIT;
                BLOCK_WAIT: if (block_valid) begin
                    if (block_error != 0) begin
                        error_hold <= block_error;
                        state <= PUBLISH;
                    end else begin
                        block_quotient <= block_data;
                        block_offset <= block_remainder[3:0];
                        state <= BLOCK_REGISTER;
                    end
                end
                BLOCK_REGISTER: begin
                    block_start_hold <= (block_quotient << 3) + (block_quotient << 2);
                    if (resume_hold)
                        state <= RESTORE;
                    else
                        state <= KEY_SETUP;
                end
                RESTORE: begin
                    if (!checkpoint_matches) begin
                        error_hold <= 7;
                        state <= PUBLISH;
                    end else begin
                        phase <= checkpoint_hold[80:79];
                        selector_hold <= checkpoint_hold[82:81];
                        key_column <= checkpoint_hold[196:192];
                        dot_component <= checkpoint_hold[230:224];
                        output_component <= checkpoint_hold[262:256];
                        query_component_hold <= checkpoint_hold[319:288];
                        content_accumulator <= checkpoint_hold[383:352];
                        relative_accumulator <= checkpoint_hold[415:384];
                        maximum <= checkpoint_hold[447:416];
                        exponential_sum <= checkpoint_hold[479:448];
                        inverse_sum <= checkpoint_hold[511:480];
                        value_accumulator <= checkpoint_hold[543:512];
                        exponential <= checkpoint_hold[575:544];
                        probability <= checkpoint_hold[607:576];
                        score_hold <= checkpoint_hold[639:608];
                        padded_hold <= checkpoint_hold[640];
                        allowed_hold <= checkpoint_hold[641];
                        key_position <= restored_key_position;
                        key_token_hold <= restored_key_position[31:0];
                        state <= NEED;
                    end
                end
                KEY_SETUP: begin
                    key_position <= {1'b0, block_start_hold} + {28'd0, key_column} - 33'd12;
                    state <= KEY_REGISTER;
                end
                KEY_REGISTER: begin
                    key_token_hold <= key_position[31:0];
                    padded_hold <= !key_in_range;
                    allowed_hold <= 0;
                    if (key_causal)
                        state <= MASK_SEND;
                    else
                        state <= MASKED_SCORE;
                end
                MASK_SEND: if (mask_ready)
                    state <= MASK_WAIT;
                MASK_WAIT: if (mask_rsp_valid && mask_rsp_ready) begin
                    mask_hold <= mask_rsp_data;
                    mask_error_hold <= mask_rsp_error;
                    state <= MASK_REGISTER;
                end
                MASK_REGISTER: begin
                    if (mask_error_hold) begin
                        error_hold <= 7;
                        state <= PUBLISH;
                    end else if (!mask_hold)
                        state <= MASKED_SCORE;
                    else begin
                        allowed_hold <= 1;
                        state <= DOT_SETUP;
                    end
                end
                DOT_SETUP: begin
                    dot_component <= 0;
                    content_accumulator <= 0;
                    relative_accumulator <= 0;
                    selector_hold <= 0;
                    state <= NEED;
                end
                MASKED_SCORE: begin
                    score_hold <= 32'hce6e6b28;
                    state <= SCORE_PROCESS;
                end
                NEED: begin
                    if (!REPLAY)
                        state <= SERVICE_SEND;
                    else if (need_valid && need_ready) begin
                        if (need_action == 0)
                            state <= SERVICE_SEND;
                        else if (need_action == 1)
                            state <= YIELD;
                        else begin
                            error_hold <= 7;
                            state <= PUBLISH;
                        end
                    end
                end
                SERVICE_SEND: if (qkv_ready)
                    state <= SERVICE_WAIT;
                SERVICE_WAIT: if (qkv_rsp_valid && qkv_rsp_ready) begin
                    pair_hold <= qkv_rsp_data;
                    service_error_hold <= qkv_rsp_error;
                    state <= SERVICE_REGISTER;
                end
                SERVICE_REGISTER: begin
                    if (service_error_hold != 0) begin
                        error_hold <= service_error_hold;
                        state <= PUBLISH;
                    end else if (selector_hold == 0) begin
                        query_component_hold <= service_word;
                        selector_hold <= 1;
                        state <= NEED;
                    end else begin
                        service_component_hold <= service_word;
                        if (selector_hold == 1)
                            state <= CONTENT_MULTIPLY;
                        else if (selector_hold == 3)
                            state <= RELATIVE_MULTIPLY;
                        else
                            state <= VALUE_MULTIPLY;
                    end
                end
                CONTENT_MULTIPLY: begin
                    fp_op <= 1;
                    fp_a <= query_component_hold;
                    fp_b <= service_component_hold;
                    fp_return <= CONTENT_ADD;
                    state <= FP_START;
                end
                CONTENT_ADD: begin
                    fp_op <= 0;
                    fp_a <= content_accumulator;
                    fp_b <= fp_value;
                    fp_return <= CONTENT_REGISTER;
                    state <= FP_START;
                end
                CONTENT_REGISTER: begin
                    content_accumulator <= fp_value;
                    selector_hold <= 3;
                    state <= NEED;
                end
                RELATIVE_MULTIPLY: begin
                    fp_op <= 1;
                    fp_a <= query_component_hold;
                    fp_b <= service_component_hold;
                    fp_return <= RELATIVE_ADD;
                    state <= FP_START;
                end
                RELATIVE_ADD: begin
                    fp_op <= 0;
                    fp_a <= relative_accumulator;
                    fp_b <= fp_value;
                    fp_return <= DOT_ADVANCE;
                    state <= FP_START;
                end
                DOT_ADVANCE: begin
                    relative_accumulator <= fp_value;
                    if (dot_component == 127)
                        state <= SCORE_SUM;
                    else begin
                        dot_component <= dot_component + 1'b1;
                        selector_hold <= 0;
                        state <= NEED;
                    end
                end
                SCORE_SUM: begin
                    fp_op <= 0;
                    fp_a <= content_accumulator;
                    fp_b <= relative_accumulator;
                    fp_return <= SOFTCAP_START;
                    state <= FP_START;
                end
                SOFTCAP_START: if (cap_ready)
                    state <= SOFTCAP_WAIT;
                SOFTCAP_WAIT: if (cap_valid) begin
                    if (cap_error != 0) begin
                        error_hold <= cap_error;
                        state <= PUBLISH;
                    end else begin
                        score_hold <= cap_data;
                        state <= SCORE_REGISTER;
                    end
                end
                SCORE_REGISTER: state <= SCORE_PROCESS;
                SCORE_PROCESS: begin
                    if (phase == 0) begin
                        if (maximum_nan || score_nan)
                            maximum <= 32'h7fc00000;
                        else if (score_greater)
                            maximum <= score_hold;
                        state <= KEY_ADVANCE;
                    end else
                        state <= EXP_ARGUMENT;
                end
                EXP_ARGUMENT: begin
                    fp_op <= 0;
                    fp_a <= score_hold;
                    fp_b <= {~maximum[31], maximum[30:0]};
                    fp_return <= EXP_START;
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
                    fp_return <= SUM_REGISTER;
                    state <= FP_START;
                end
                SUM_REGISTER: begin
                    exponential_sum <= fp_value;
                    state <= KEY_ADVANCE;
                end
                PROBABILITY: begin
                    fp_op <= 1;
                    fp_a <= exponential;
                    fp_b <= inverse_sum;
                    fp_return <= VALUE_SETUP;
                    state <= FP_START;
                end
                VALUE_SETUP: begin
                    probability <= fp_value;
                    if (padded_hold) begin
                        service_component_hold <= 0;
                        state <= VALUE_MULTIPLY;
                    end else begin
                        selector_hold <= 2;
                        state <= NEED;
                    end
                end
                VALUE_MULTIPLY: begin
                    fp_op <= 1;
                    fp_a <= probability;
                    fp_b <= service_component_hold;
                    fp_return <= VALUE_ADD;
                    state <= FP_START;
                end
                VALUE_ADD: begin
                    fp_op <= 0;
                    fp_a <= value_accumulator;
                    fp_b <= fp_value;
                    fp_return <= VALUE_REGISTER;
                    state <= FP_START;
                end
                VALUE_REGISTER: begin
                    value_accumulator <= fp_value;
                    state <= KEY_ADVANCE;
                end
                KEY_ADVANCE: begin
                    if (key_column == 23)
                        state <= PASS_FINISH;
                    else begin
                        key_column <= key_column + 1'b1;
                        state <= KEY_SETUP;
                    end
                end
                PASS_FINISH: begin
                    key_column <= 0;
                    if (phase == 0) begin
                        phase <= 1;
                        exponential_sum <= 0;
                        state <= KEY_SETUP;
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
                        value_accumulator <= 0;
                        phase <= 2;
                        state <= KEY_SETUP;
                    end
                end
                OUTPUT_NARROW: begin
                    fp_op <= 3;
                    fp_a <= value_accumulator;
                    fp_b <= 0;
                    fp_return <= OUTPUT_REGISTER;
                    state <= FP_START;
                end
                OUTPUT_REGISTER: begin
                    output_hold <= fp_value[15:0];
                    state <= EMIT;
                end
                EMIT: if (output_ready) begin
                    if (output_component == 127)
                        state <= PUBLISH;
                    else
                        state <= OUTPUT_ADVANCE;
                end
                OUTPUT_ADVANCE: begin
                    output_component <= output_component + 1'b1;
                    value_accumulator <= 0;
                    key_column <= 0;
                    state <= KEY_SETUP;
                end
                FP_START: if (fp_ready)
                    state <= FP_WAIT;
                FP_WAIT: if (fp_valid) begin
                    if (fp_error != 0) begin
                        error_hold <= fp_error;
                        state <= PUBLISH;
                    end else begin
                        fp_value <= fp_data;
                        if (fp_return == EXP_START)
                            exp_operand <= fp_data;
                        state <= fp_return;
                    end
                end
                YIELD: if (checkpoint_ready) begin
                    yield_hold <= 1;
                    state <= PUBLISH;
                end
                PUBLISH: state <= RESPONSE;
                RESPONSE: if (done_ready)
                    state <= IDLE;
                default: begin
                    error_hold <= 7;
                    state <= PUBLISH;
                end
            endcase
        end
    end
endmodule
