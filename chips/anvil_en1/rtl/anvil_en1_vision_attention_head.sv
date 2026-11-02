module anvil_en1_vision_attention_head #(
    parameter integer REPLAY = 0
) (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] model, precision,
    input wire [31:0] generation, patches, query_patch,
    input wire [7:0] layer,
    input wire [3:0] head,
    input wire resume_valid,
    input wire [511:0] resume_checkpoint,
    output wire mask_valid,
    input wire mask_ready,
    output wire [31:0] mask_patch,
    input wire mask_rsp_valid,
    output wire mask_rsp_ready,
    input wire mask_rsp_data, mask_rsp_error,
    output wire need_valid,
    input wire need_ready,
    input wire [1:0] need_action,
    output wire qkv_valid,
    input wire qkv_ready,
    output wire [1:0] qkv_model, qkv_precision, qkv_selector,
    output wire [31:0] qkv_patch,
    output wire [7:0] qkv_layer,
    output wire [3:0] qkv_head,
    output wire [9:0] qkv_component,
    input wire qkv_rsp_valid,
    output wire qkv_rsp_ready,
    input wire [31:0] qkv_rsp_data,
    input wire [3:0] qkv_rsp_error,
    output wire checkpoint_valid,
    input wire checkpoint_ready,
    output wire [511:0] checkpoint_data,
    output wire output_valid,
    input wire output_ready,
    output wire [9:0] output_index,
    output wire [15:0] output_data,
    output wire output_last,
    output wire done_valid,
    input wire done_ready,
    output wire [3:0] done_error,
    output wire [63:0] controller_bytes
);
    localparam [5:0] IDLE = 0, VALIDATE = 1, RESTORE = 2,
        MASK_SEND = 3, MASK_WAIT = 4, MASK_REGISTER = 5,
        QUERY_SETUP = 6, NEED = 7, SERVICE_SEND = 8, SERVICE_WAIT = 9,
        SERVICE_REGISTER = 10, DOT_MULTIPLY = 11, DOT_ADD = 12,
        DOT_ADVANCE = 13, SCORE = 14, EXP_ARGUMENT = 15,
        EXP_SEND = 16, EXP_WAIT = 17, EXP_REGISTER = 18,
        SUM_ADD = 19, PROBABILITY = 20, PROBABILITY_NARROW = 21,
        VALUE_SETUP = 22, VALUE_MULTIPLY = 23, VALUE_ADD = 24,
        VALUE_ADVANCE = 25, KEY_ADVANCE = 26, PASS_FINISH = 27,
        INVERSE_SEND = 28, INVERSE_WAIT = 29, OUTPUT_NARROW = 30,
        OUTPUT_PREPARE = 31, EMIT = 32, FP_SEND = 33, FP_WAIT = 34,
        YIELD = 35, PUBLISH = 36, RESPONSE = 37;
    reg [5:0] state, fp_return;
    reg [1:0] model_hold, precision_hold, phase, selector_hold;
    reg [31:0] generation_hold, patches_hold, query_hold, key, active_keys;
    reg [7:0] layer_hold;
    reg [3:0] head_hold;
    reg [5:0] dot_component, output_component;
    reg [15:0] query_component_hold, service_component_hold, probability_hold, output_hold;
    reg mask_hold, mask_error_hold, resume_hold;
    reg [511:0] checkpoint_hold;
    reg [31:0] pair_hold, dot_accumulator, maximum, exponential_sum, inverse_sum;
    reg [31:0] value_accumulator, exponential, fp_a, fp_b, fp_value, exp_operand;
    reg [2:0] fp_op;
    reg [3:0] service_error_hold, error_hold;

    initial begin
        if (REPLAY != 0 && REPLAY != 1)
            $fatal(1, "PARAMETER ERROR: REPLAY must be 0 or 1");
    end

    wire fp_ready, fp_valid, exp_ready, exp_valid, inverse_ready, inverse_valid;
    wire [31:0] fp_data, exp_data, inverse_data;
    wire [3:0] fp_error, exp_error, inverse_error;
    wire [63:0] primitive_fp_bytes, primitive_exp_bytes, primitive_div_bytes;
    anvil_en1_fp32 arithmetic (
        .controller_bytes(primitive_fp_bytes),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == FP_SEND), .start_ready(fp_ready),
        .operation(fp_op), .operand_a(fp_a), .operand_b(fp_b),
        .done_valid(fp_valid), .done_ready(rst_n && state == FP_WAIT),
        .done_data(fp_data), .done_error(fp_error)
    );
    anvil_en1_exp exponent (
        .controller_bytes(primitive_exp_bytes),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == EXP_SEND), .start_ready(exp_ready),
        .operand(exp_operand),
        .done_valid(exp_valid), .done_ready(rst_n && state == EXP_WAIT),
        .done_data(exp_data), .done_error(exp_error)
    );
    anvil_en1_fp32_divsqrt reciprocal (
        .controller_bytes(primitive_div_bytes),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == INVERSE_SEND), .start_ready(inverse_ready),
        .operation(2'd0), .operand_a(32'h3f800000), .operand_b(exponential_sum),
        .done_valid(inverse_valid), .done_ready(rst_n && state == INVERSE_WAIT),
        .done_data(inverse_data), .done_error(inverse_error)
    );

    wire [5:0] service_component = selector_hold == 2 ?
        output_component : dot_component;
    wire maximum_nan = maximum[30:23] == 255 && maximum[22:0] != 0;
    wire score_nan = dot_accumulator[30:23] == 255 && dot_accumulator[22:0] != 0;
    wire both_zero = maximum[30:0] == 0 && dot_accumulator[30:0] == 0;
    wire score_greater = !both_zero && (maximum[31] != dot_accumulator[31] ?
        !dot_accumulator[31] : (dot_accumulator[31] ?
        dot_accumulator[30:0] < maximum[30:0] :
        dot_accumulator[30:0] > maximum[30:0]));
    wire [511:0] live_checkpoint = {
        32'h454e3156, generation_hold, model_hold, precision_hold,
        layer_hold, head_hold, query_hold, patches_hold, key, active_keys,
        phase, dot_component, output_component, selector_hold,
        query_component_hold, probability_hold, dot_accumulator, maximum,
        exponential_sum, inverse_sum, value_accumulator, 96'd0
    };
    wire checkpoint_matches = checkpoint_hold[511:480] == 32'h454e3156 &&
        checkpoint_hold[479:448] == generation_hold &&
        checkpoint_hold[447:446] == model_hold &&
        checkpoint_hold[445:444] == precision_hold &&
        checkpoint_hold[443:436] == layer_hold &&
        checkpoint_hold[435:432] == head_hold &&
        checkpoint_hold[431:400] == query_hold &&
        checkpoint_hold[399:368] == patches_hold &&
        checkpoint_hold[367:336] < patches_hold &&
        checkpoint_hold[335:304] != 0 &&
        checkpoint_hold[335:304] <= patches_hold &&
        (checkpoint_hold[303:302] != 0 ||
            checkpoint_hold[335:304] <= checkpoint_hold[367:336] + 1'b1) &&
        checkpoint_hold[303:302] <= 2 &&
        checkpoint_hold[289:288] <= 2 &&
        (checkpoint_hold[289:288] != 2 || checkpoint_hold[303:302] == 2) &&
        (checkpoint_hold[303:302] == 2 || checkpoint_hold[295:290] == 0) &&
        checkpoint_hold[95:0] == 0;

    assign start_ready = rst_n && state == IDLE;
    assign mask_valid = rst_n && state == MASK_SEND;
    assign mask_patch = rst_n ? key : 32'd0;
    assign mask_rsp_ready = rst_n && state == MASK_WAIT;
    assign need_valid = rst_n && REPLAY && state == NEED;
    assign qkv_valid = rst_n && state == SERVICE_SEND;
    assign qkv_model = rst_n ? model_hold : 2'd0;
    assign qkv_precision = rst_n ? precision_hold : 2'd0;
    assign qkv_selector = rst_n ? selector_hold : 2'd0;
    assign qkv_patch = !rst_n ? 32'd0 : (selector_hold == 0 ? query_hold : key);
    assign qkv_layer = rst_n ? layer_hold : 8'd0;
    assign qkv_head = rst_n ? head_hold : 4'd0;
    assign qkv_component = rst_n ? {4'd0, service_component[5:1], 1'b0} : 10'd0;
    assign qkv_rsp_ready = rst_n && state == SERVICE_WAIT;
    assign checkpoint_valid = rst_n && REPLAY && state == YIELD;
    assign checkpoint_data = rst_n && REPLAY ? live_checkpoint : 512'd0;
    assign output_valid = rst_n && state == EMIT;
    assign output_index = rst_n ? {4'd0, output_component} : 10'd0;
    assign output_data = rst_n ? output_hold : 16'd0;
    assign output_last = rst_n && state == EMIT && output_component == 63;
    assign done_valid = rst_n && state == RESPONSE;
    assign done_error = rst_n ? error_hold : 4'd0;
    localparam integer CONTROLLER_BITS =
        $bits(state) + $bits(fp_return) + $bits(model_hold) + $bits(precision_hold) +
        $bits(phase) + $bits(selector_hold) + $bits(generation_hold) +
        $bits(patches_hold) + $bits(query_hold) + $bits(key) + $bits(active_keys) +
        $bits(layer_hold) + $bits(head_hold) + $bits(dot_component) +
        $bits(output_component) + $bits(query_component_hold) +
        $bits(service_component_hold) + $bits(probability_hold) + $bits(output_hold) +
        $bits(mask_hold) + $bits(mask_error_hold) + $bits(resume_hold) +
        $bits(checkpoint_hold) + $bits(pair_hold) + $bits(dot_accumulator) +
        $bits(maximum) + $bits(exponential_sum) + $bits(inverse_sum) +
        $bits(value_accumulator) + $bits(exponential) + $bits(fp_a) + $bits(fp_b) +
        $bits(fp_value) + $bits(exp_operand) + $bits(fp_op) +
        $bits(service_error_hold) + $bits(error_hold);
    assign controller_bytes = !rst_n ? 64'd0 : 64'((CONTROLLER_BITS + 7) >> 3) +
        primitive_fp_bytes + primitive_exp_bytes + primitive_div_bytes;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            fp_return <= 0;
            model_hold <= 0;
            precision_hold <= 0;
            phase <= 0;
            selector_hold <= 0;
            generation_hold <= 0;
            patches_hold <= 0;
            query_hold <= 0;
            key <= 0;
            active_keys <= 0;
            layer_hold <= 0;
            head_hold <= 0;
            dot_component <= 0;
            output_component <= 0;
            query_component_hold <= 0;
            service_component_hold <= 0;
            probability_hold <= 0;
            output_hold <= 0;
            mask_hold <= 0;
            mask_error_hold <= 0;
            resume_hold <= 0;
            checkpoint_hold <= 0;
            pair_hold <= 0;
            dot_accumulator <= 0;
            maximum <= 0;
            exponential_sum <= 0;
            inverse_sum <= 0;
            value_accumulator <= 0;
            exponential <= 0;
            fp_a <= 0;
            fp_b <= 0;
            fp_value <= 0;
            exp_operand <= 0;
            fp_op <= 0;
            service_error_hold <= 0;
            error_hold <= 0;
        end else begin
            case (state)
                IDLE: if (start_valid && start_ready) begin
                    model_hold <= model;
                    precision_hold <= precision;
                    generation_hold <= generation;
                    patches_hold <= patches;
                    query_hold <= query_patch;
                    layer_hold <= layer;
                    head_hold <= head;
                    key <= 0;
                    phase <= 0;
                    active_keys <= 0;
                    output_component <= 0;
                    dot_component <= 0;
                    selector_hold <= 0;
                    query_component_hold <= 0;
                    probability_hold <= 0;
                    dot_accumulator <= 0;
                    maximum <= 32'hff800000;
                    exponential_sum <= 0;
                    inverse_sum <= 0;
                    value_accumulator <= 0;
                    output_hold <= 0;
                    error_hold <= 0;
                    resume_hold <= REPLAY && resume_valid;
                    if (REPLAY)
                        checkpoint_hold <= resume_checkpoint;
                    state <= VALIDATE;
                end
                VALIDATE: begin
                    if ((model_hold != 1 && model_hold != 2) || precision_hold > 1) begin
                        error_hold <= 6;
                        state <= PUBLISH;
                    end else if (patches_hold == 0 || patches_hold > 131072 ||
                        query_hold >= patches_hold || layer_hold >= 16 || head_hold >= 12) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else if (resume_hold)
                        state <= RESTORE;
                    else
                        state <= MASK_SEND;
                end
                RESTORE: begin
                    if (!REPLAY || !checkpoint_matches) begin
                        error_hold <= 7;
                        state <= PUBLISH;
                    end else begin
                        key <= checkpoint_hold[367:336];
                        active_keys <= checkpoint_hold[335:304];
                        phase <= checkpoint_hold[303:302];
                        dot_component <= checkpoint_hold[301:296];
                        output_component <= checkpoint_hold[295:290];
                        selector_hold <= checkpoint_hold[289:288];
                        query_component_hold <= checkpoint_hold[287:272];
                        probability_hold <= checkpoint_hold[271:256];
                        dot_accumulator <= checkpoint_hold[255:224];
                        maximum <= checkpoint_hold[223:192];
                        exponential_sum <= checkpoint_hold[191:160];
                        inverse_sum <= checkpoint_hold[159:128];
                        value_accumulator <= checkpoint_hold[127:96];
                        state <= NEED;
                    end
                end
                MASK_SEND: if (mask_valid && mask_ready)
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
                        state <= KEY_ADVANCE;
                    else begin
                        dot_component <= 0;
                        dot_accumulator <= 0;
                        if (phase == 0)
                            active_keys <= active_keys + 1'b1;
                        state <= QUERY_SETUP;
                    end
                end
                QUERY_SETUP: begin
                    selector_hold <= 0;
                    state <= NEED;
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
                SERVICE_SEND: if (qkv_valid && qkv_ready)
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
                        query_component_hold <= service_component[0] ?
                            pair_hold[31:16] : pair_hold[15:0];
                        selector_hold <= 1;
                        state <= NEED;
                    end else begin
                        service_component_hold <= service_component[0] ?
                            pair_hold[31:16] : pair_hold[15:0];
                        if (selector_hold == 1)
                            state <= DOT_MULTIPLY;
                        else
                            state <= VALUE_MULTIPLY;
                    end
                end
                DOT_MULTIPLY: begin
                    fp_op <= 1;
                    fp_a <= {query_component_hold, 16'd0};
                    fp_b <= {service_component_hold, 16'd0};
                    fp_return <= DOT_ADD;
                    state <= FP_SEND;
                end
                DOT_ADD: begin
                    fp_op <= 0;
                    fp_a <= dot_accumulator;
                    fp_b <= fp_value;
                    fp_return <= DOT_ADVANCE;
                    state <= FP_SEND;
                end
                DOT_ADVANCE: begin
                    dot_accumulator <= fp_value;
                    if (dot_component == 63)
                        state <= SCORE;
                    else begin
                        dot_component <= dot_component + 1'b1;
                        state <= QUERY_SETUP;
                    end
                end
                SCORE: begin
                    if (phase == 0) begin
                        if (score_nan)
                            maximum <= 32'h7fc00000;
                        else if (!maximum_nan && score_greater)
                            maximum <= dot_accumulator;
                        state <= KEY_ADVANCE;
                    end else
                        state <= EXP_ARGUMENT;
                end
                EXP_ARGUMENT: begin
                    fp_op <= 0;
                    fp_a <= dot_accumulator;
                    fp_b <= {~maximum[31], maximum[30:0]};
                    fp_return <= EXP_SEND;
                    state <= FP_SEND;
                end
                EXP_SEND: if (exp_ready)
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
                    fp_return <= KEY_ADVANCE;
                    state <= FP_SEND;
                end
                PROBABILITY: begin
                    fp_op <= 1;
                    fp_a <= exponential;
                    fp_b <= inverse_sum;
                    fp_return <= PROBABILITY_NARROW;
                    state <= FP_SEND;
                end
                PROBABILITY_NARROW: begin
                    fp_op <= 3;
                    fp_a <= fp_value;
                    fp_b <= 0;
                    fp_return <= VALUE_SETUP;
                    state <= FP_SEND;
                end
                VALUE_SETUP: begin
                    probability_hold <= fp_value[15:0];
                    selector_hold <= 2;
                    state <= NEED;
                end
                VALUE_MULTIPLY: begin
                    fp_op <= 1;
                    fp_a <= {probability_hold, 16'd0};
                    fp_b <= {service_component_hold, 16'd0};
                    fp_return <= VALUE_ADD;
                    state <= FP_SEND;
                end
                VALUE_ADD: begin
                    fp_op <= 0;
                    fp_a <= value_accumulator;
                    fp_b <= fp_value;
                    fp_return <= VALUE_ADVANCE;
                    state <= FP_SEND;
                end
                VALUE_ADVANCE: begin
                    value_accumulator <= fp_value;
                    state <= KEY_ADVANCE;
                end
                KEY_ADVANCE: begin
                    if (key == patches_hold - 1'b1)
                        state <= PASS_FINISH;
                    else begin
                        key <= key + 1'b1;
                        state <= MASK_SEND;
                    end
                end
                PASS_FINISH: begin
                    key <= 0;
                    if (phase == 0) begin
                        if (active_keys == 0) begin
                            error_hold <= 5;
                            state <= PUBLISH;
                        end else begin
                            phase <= 1;
                            state <= MASK_SEND;
                        end
                    end else if (phase == 1)
                        state <= INVERSE_SEND;
                    else
                        state <= OUTPUT_NARROW;
                end
                INVERSE_SEND: if (inverse_ready)
                    state <= INVERSE_WAIT;
                INVERSE_WAIT: if (inverse_valid) begin
                    if (inverse_error != 0) begin
                        error_hold <= inverse_error;
                        state <= PUBLISH;
                    end else begin
                        inverse_sum <= inverse_data;
                        phase <= 2;
                        key <= 0;
                        state <= MASK_SEND;
                    end
                end
                OUTPUT_NARROW: begin
                    fp_op <= 3;
                    fp_a <= value_accumulator;
                    fp_b <= 0;
                    fp_return <= OUTPUT_PREPARE;
                    state <= FP_SEND;
                end
                OUTPUT_PREPARE: begin
                    output_hold <= fp_value[15:0];
                    state <= EMIT;
                end
                EMIT: if (output_valid && output_ready) begin
                    if (output_component == 63)
                        state <= PUBLISH;
                    else begin
                        output_component <= output_component + 1'b1;
                        value_accumulator <= 0;
                        key <= 0;
                        state <= MASK_SEND;
                    end
                end
                FP_SEND: if (fp_ready)
                    state <= FP_WAIT;
                FP_WAIT: if (fp_valid) begin
                    if (fp_error != 0) begin
                        error_hold <= fp_error;
                        state <= PUBLISH;
                    end else begin
                        fp_value <= fp_data;
                        if (fp_return == EXP_SEND)
                            exp_operand <= fp_data;
                        if (fp_return == KEY_ADVANCE && phase == 1)
                            exponential_sum <= fp_data;
                        state <= fp_return;
                    end
                end
                YIELD: if (checkpoint_valid && checkpoint_ready)
                    state <= IDLE;
                PUBLISH: state <= RESPONSE;
                RESPONSE: if (done_valid && done_ready)
                    state <= IDLE;
                default: begin
                    output_hold <= 0;
                    error_hold <= 7;
                    state <= PUBLISH;
                end
            endcase
        end
    end
endmodule
