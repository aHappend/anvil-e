module anvil_en1_norm #(
    parameter integer EXTERNAL_FP = 0
) (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire layer_norm, learned_scale,
    input wire [31:0] vector_length,
    input wire [31:0] epsilon,
    output wire source_valid,
    input wire source_ready,
    output wire [31:0] source_index,
    input wire source_rsp_valid,
    output wire source_rsp_ready,
    input wire [15:0] source_rsp_data,
    input wire source_rsp_error,
    output wire scale_valid,
    input wire scale_ready,
    output wire [31:0] scale_index,
    input wire scale_rsp_valid,
    output wire scale_rsp_ready,
    input wire [15:0] scale_rsp_data,
    input wire scale_rsp_error,
    output wire normalized_valid,
    input wire normalized_ready,
    output wire [31:0] normalized_index,
    output wire [15:0] normalized_data,
    output wire normalized_last,
    output wire done_valid,
    input wire done_ready,
    output wire [3:0] done_error,
    output wire [63:0] controller_bytes,
    output wire arithmetic_valid,
    input wire arithmetic_ready,
    output wire [2:0] arithmetic_operation,
    output wire [31:0] arithmetic_a, arithmetic_b,
    input wire arithmetic_result_valid,
    output wire arithmetic_result_ready,
    input wire [31:0] arithmetic_result_data,
    input wire [3:0] arithmetic_result_error
);
    localparam [5:0] IDLE = 0, VALIDATE = 1, LENGTH_START = 2,
        LENGTH_WAIT = 3, SOURCE_START = 4, SOURCE_WAIT = 5,
        SOURCE_REGISTER = 6, TRANSFORM = 7, SQUARE = 8, REDUCE = 9,
        ADVANCE = 10, FINISH_REDUCTION = 11, AFTER_MEAN = 12,
        ADD_EPSILON = 13, INVERSE_SETUP = 14,
        START_OUTPUT = 16, NORMALIZE = 17, APPLY_SCALE = 18,
        SCALE_START = 19, SCALE_WAIT = 20, SCALE_REGISTER = 21,
        SCALE_MULTIPLY = 22, NARROW = 23, OUTPUT_PREPARE = 24,
        OUTPUT_WAIT = 25, FP_START = 26, FP_WAIT = 27,
        RD_START = 28, RD_WAIT = 29, PUBLISH = 30, RESPONSE = 31;
    reg [5:0] state, return_state;
    reg layer_hold, learned_hold;
    reg [31:0] length_hold, epsilon_hold, index, length_float;
    reg [1:0] phase;
    reg [31:0] accumulator, mean_hold, inverse_hold, value_hold, normalized_hold;
    reg [15:0] source_hold, scale_hold, output_hold;
    reg response_error_hold;
    reg [31:0] fp_a, fp_b, rd_a, rd_b;
    reg [2:0] fp_op;
    reg [1:0] rd_op;
    reg [3:0] error_hold;
    wire [31:0] CONTROLLER_BITS = $bits(state) + $bits(return_state) +
        $bits(layer_hold) + $bits(learned_hold) + $bits(length_hold) +
        $bits(epsilon_hold) + $bits(index) + $bits(length_float) + $bits(phase) +
        $bits(accumulator) + $bits(mean_hold) + $bits(inverse_hold) +
        $bits(value_hold) + $bits(normalized_hold) + $bits(source_hold) +
        $bits(scale_hold) + $bits(output_hold) + $bits(response_error_hold) +
        $bits(fp_a) + $bits(fp_b) + $bits(rd_a) + $bits(rd_b) +
        $bits(fp_op) + $bits(rd_op) + $bits(error_hold);
    wire [63:0] convert_controller_bytes, fp_controller_bytes, div_controller_bytes;
    assign controller_bytes = !rst_n ? 64'd0 :
        64'((CONTROLLER_BITS+7) >> 3) + convert_controller_bytes +
        fp_controller_bytes + div_controller_bytes;
    wire length_ready, length_valid, fp_ready, fp_valid, rd_ready, rd_valid;
    wire [31:0] length_data, fp_data, rd_data;
    wire [3:0] length_error, fp_error, rd_error;

    anvil_en1_uint_to_fp32 length_converter (
        .controller_bytes(convert_controller_bytes),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == LENGTH_START), .start_ready(length_ready),
        .operand(length_hold),
        .done_valid(length_valid), .done_ready(rst_n && state == LENGTH_WAIT),
        .done_data(length_data), .done_error(length_error)
    );
    initial begin
        if (EXTERNAL_FP != 0 && EXTERNAL_FP != 1)
            $fatal(1, "PARAMETER ERROR: EXTERNAL_FP must be 0 or 1");
    end
    assign arithmetic_valid = rst_n && EXTERNAL_FP == 1 && state == FP_START;
    assign arithmetic_operation = rst_n && EXTERNAL_FP == 1 ? fp_op : 3'd0;
    assign arithmetic_a = rst_n && EXTERNAL_FP == 1 ? fp_a : 32'd0;
    assign arithmetic_b = rst_n && EXTERNAL_FP == 1 ? fp_b : 32'd0;
    assign arithmetic_result_ready = rst_n && EXTERNAL_FP == 1 && state == FP_WAIT;
    generate
        if (EXTERNAL_FP == 1) begin : external_arithmetic
            assign fp_controller_bytes = 64'd0;
            assign fp_ready = rst_n && arithmetic_ready;
            assign fp_valid = rst_n && arithmetic_result_valid;
            assign fp_data = rst_n ? arithmetic_result_data : 32'd0;
            assign fp_error = rst_n ? arithmetic_result_error : 4'd0;
        end else begin : internal_arithmetic
            anvil_en1_fp32 fp_unit (
                .controller_bytes(fp_controller_bytes),
                .clk(clk), .rst_n(rst_n),
                .start_valid(rst_n && state == FP_START), .start_ready(fp_ready),
                .operation(fp_op), .operand_a(fp_a), .operand_b(fp_b),
                .done_valid(fp_valid), .done_ready(rst_n && state == FP_WAIT),
                .done_data(fp_data), .done_error(fp_error)
            );
        end
    endgenerate
    anvil_en1_fp32_divsqrt root_divider (
        .controller_bytes(div_controller_bytes),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == RD_START), .start_ready(rd_ready),
        .operation(rd_op), .operand_a(rd_a), .operand_b(rd_b),
        .done_valid(rd_valid), .done_ready(rst_n && state == RD_WAIT),
        .done_data(rd_data), .done_error(rd_error)
    );

    assign start_ready = rst_n && state == IDLE;
    assign source_valid = rst_n && state == SOURCE_START;
    assign source_index = rst_n ? index : 32'd0;
    assign source_rsp_ready = rst_n && state == SOURCE_WAIT;
    assign scale_valid = rst_n && state == SCALE_START;
    assign scale_index = rst_n ? index : 32'd0;
    assign scale_rsp_ready = rst_n && state == SCALE_WAIT;
    assign normalized_valid = rst_n && state == OUTPUT_WAIT;
    assign normalized_index = rst_n ? index : 32'd0;
    assign normalized_data = rst_n ? output_hold : 16'd0;
    assign normalized_last = rst_n && state == OUTPUT_WAIT &&
        index == length_hold - 1'b1;
    assign done_valid = rst_n && state == RESPONSE;
    assign done_error = rst_n ? error_hold : 4'd0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            return_state <= 0;
            layer_hold <= 0;
            learned_hold <= 0;
            length_hold <= 0;
            epsilon_hold <= 0;
            index <= 0;
            length_float <= 0;
            phase <= 0;
            accumulator <= 0;
            mean_hold <= 0;
            inverse_hold <= 0;
            value_hold <= 0;
            normalized_hold <= 0;
            source_hold <= 0;
            scale_hold <= 0;
            output_hold <= 0;
            response_error_hold <= 0;
            fp_a <= 0;
            fp_b <= 0;
            rd_a <= 0;
            rd_b <= 0;
            fp_op <= 0;
            rd_op <= 0;
            error_hold <= 0;
        end else begin
            case (state)
                IDLE: if (start_valid && start_ready) begin
                    layer_hold <= layer_norm;
                    learned_hold <= learned_scale;
                    length_hold <= vector_length;
                    epsilon_hold <= epsilon;
                    phase <= 0;
                    index <= 0;
                    accumulator <= 0;
                    mean_hold <= 0;
                    error_hold <= 0;
                    state <= VALIDATE;
                end
                VALIDATE: begin
                    if (length_hold == 0 || length_hold > 16384 ||
                        epsilon_hold[31] || epsilon_hold[30:23] == 255) begin
                        error_hold <= 1;
                        state <= PUBLISH;
                    end else
                        state <= LENGTH_START;
                end
                LENGTH_START: if (length_ready)
                    state <= LENGTH_WAIT;
                LENGTH_WAIT: if (length_valid) begin
                    if (length_error != 0) begin
                        error_hold <= length_error;
                        state <= PUBLISH;
                    end else begin
                        length_float <= length_data;
                        state <= SOURCE_START;
                    end
                end
                SOURCE_START: if (source_ready)
                    state <= SOURCE_WAIT;
                SOURCE_WAIT: if (source_rsp_valid && source_rsp_ready) begin
                    source_hold <= source_rsp_data;
                    response_error_hold <= source_rsp_error;
                    state <= SOURCE_REGISTER;
                end
                SOURCE_REGISTER: begin
                    if (response_error_hold) begin
                        error_hold <= 7;
                        state <= PUBLISH;
                    end else begin
                        fp_op <= 2;
                        fp_a <= {16'd0, source_hold};
                        fp_b <= 0;
                        return_state <= TRANSFORM;
                        state <= FP_START;
                    end
                end
                TRANSFORM: begin
                    if (layer_hold && phase != 0) begin
                        fp_op <= 0;
                        fp_a <= value_hold;
                        fp_b <= {~mean_hold[31], mean_hold[30:0]};
                        if (phase == 1)
                            return_state <= SQUARE;
                        else
                            return_state <= NORMALIZE;
                        state <= FP_START;
                    end else if (phase == 2)
                        state <= NORMALIZE;
                    else if (layer_hold)
                        state <= REDUCE;
                    else
                        state <= SQUARE;
                end
                SQUARE: begin
                    fp_op <= 1;
                    fp_a <= value_hold;
                    fp_b <= value_hold;
                    return_state <= REDUCE;
                    state <= FP_START;
                end
                REDUCE: begin
                    fp_op <= 0;
                    fp_a <= accumulator;
                    fp_b <= value_hold;
                    return_state <= ADVANCE;
                    state <= FP_START;
                end
                ADVANCE: begin
                    accumulator <= value_hold;
                    if (index == length_hold - 1'b1)
                        state <= FINISH_REDUCTION;
                    else begin
                        index <= index + 1'b1;
                        state <= SOURCE_START;
                    end
                end
                FINISH_REDUCTION: begin
                    rd_op <= 0;
                    rd_a <= accumulator;
                    rd_b <= length_float;
                    if (layer_hold && phase == 0)
                        return_state <= AFTER_MEAN;
                    else
                        return_state <= ADD_EPSILON;
                    state <= RD_START;
                end
                AFTER_MEAN: begin
                    mean_hold <= value_hold;
                    phase <= 1;
                    index <= 0;
                    accumulator <= 0;
                    state <= SOURCE_START;
                end
                ADD_EPSILON: begin
                    fp_op <= 0;
                    fp_a <= value_hold;
                    fp_b <= epsilon_hold;
                    return_state <= INVERSE_SETUP;
                    state <= FP_START;
                end
                INVERSE_SETUP: begin
                    rd_op <= 2;
                    rd_a <= value_hold;
                    rd_b <= 0;
                    return_state <= START_OUTPUT;
                    state <= RD_START;
                end
                START_OUTPUT: begin
                    inverse_hold <= value_hold;
                    index <= 0;
                    phase <= 2;
                    state <= SOURCE_START;
                end
                NORMALIZE: begin
                    fp_op <= 1;
                    fp_a <= value_hold;
                    fp_b <= inverse_hold;
                    return_state <= APPLY_SCALE;
                    state <= FP_START;
                end
                APPLY_SCALE: begin
                    normalized_hold <= value_hold;
                    if (learned_hold)
                        state <= SCALE_START;
                    else
                        state <= NARROW;
                end
                SCALE_START: if (scale_ready)
                    state <= SCALE_WAIT;
                SCALE_WAIT: if (scale_rsp_valid && scale_rsp_ready) begin
                    scale_hold <= scale_rsp_data;
                    response_error_hold <= scale_rsp_error;
                    state <= SCALE_REGISTER;
                end
                SCALE_REGISTER: begin
                    if (response_error_hold) begin
                        error_hold <= 2;
                        state <= PUBLISH;
                    end else begin
                        fp_op <= 2;
                        fp_a <= {16'd0, scale_hold};
                        fp_b <= 0;
                        return_state <= SCALE_MULTIPLY;
                        state <= FP_START;
                    end
                end
                SCALE_MULTIPLY: begin
                    fp_op <= 1;
                    fp_a <= normalized_hold;
                    fp_b <= value_hold;
                    return_state <= NARROW;
                    state <= FP_START;
                end
                NARROW: begin
                    fp_op <= 3;
                    fp_a <= value_hold;
                    fp_b <= 0;
                    return_state <= OUTPUT_PREPARE;
                    state <= FP_START;
                end
                OUTPUT_PREPARE: begin
                    output_hold <= value_hold[15:0];
                    state <= OUTPUT_WAIT;
                end
                OUTPUT_WAIT: if (normalized_ready) begin
                    if (index == length_hold - 1'b1)
                        state <= PUBLISH;
                    else begin
                        index <= index + 1'b1;
                        state <= SOURCE_START;
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
                        state <= return_state;
                    end
                end
                RD_START: if (rd_ready)
                    state <= RD_WAIT;
                RD_WAIT: if (rd_valid) begin
                    if (rd_error != 0) begin
                        error_hold <= rd_error;
                        state <= PUBLISH;
                    end else begin
                        value_hold <= rd_data;
                        state <= return_state;
                    end
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
