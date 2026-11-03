module anvil_en1_sincos #(
    parameter integer EXTERNAL_FP = 0
) (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [31:0] operand,
    output wire done_valid,
    input wire done_ready,
    output wire [31:0] done_sin, done_cos,
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
    localparam [5:0] IDLE = 0, CLASSIFY = 1, FIXED_SETUP = 2,
        REDUCE = 3, QUADRANT = 4, NORMALIZE = 5, ROUND = 6,
        SQUARE = 7, POLYNOMIAL_SETUP = 8, COEFFICIENT_START = 9,
        COEFFICIENT_WAIT = 10, DIV_START = 11, DIV_WAIT = 12,
        HORNER_MULTIPLY = 13, HORNER_ADD = 14, HORNER_ADVANCE = 15,
        SINE_FINISH = 16, COSINE_SETUP = 17, RESTORE = 18,
        FP_START = 19, FP_WAIT = 20, PUBLISH = 21, RESPONSE = 22;
    localparam [63:0] PI = 64'h00003243f6a8885a,
        TWO_PI = 64'h00006487ed5110b4,
        HALF_PI = 64'h00001921fb54442d,
        QUARTER_PI = 64'h00000c90fdaa2216;
    reg [5:0] state, return_state;
    reg [31:0] angle_hold, reduced_float, squared, polynomial, coefficient_hold;
    reg [31:0] value_hold, sine_hold, cosine_hold, fp_a, fp_b, factorial_float;
    reg [2:0] fp_op;
    reg [3:0] error_hold, degree;
    reg cosine_phase, first_coefficient, reduced_negative;
    reg [1:0] quadrant_hold;
    reg [4:0] reduction_bit;
    reg [63:0] remainder_hold, fixed_normal;
    reg signed [11:0] fixed_exponent;
    wire fp_ready, fp_valid, uint_ready, uint_valid, div_ready, div_valid;
    wire [31:0] fp_data, uint_data, div_data;
    wire [3:0] fp_error, uint_error, div_error;

    function automatic [31:0] factorial(input [3:0] index);
        begin
            case (index)
                0, 1: factorial = 1;
                2: factorial = 2;
                3: factorial = 6;
                4: factorial = 24;
                5: factorial = 120;
                6: factorial = 720;
                7: factorial = 5040;
                8: factorial = 40320;
                9: factorial = 362880;
                10: factorial = 3628800;
                11: factorial = 39916800;
                12: factorial = 479001600;
                default: factorial = 0;
            endcase
        end
    endfunction
    wire [31:0] factorial_integer = factorial(degree);
    wire [63:0] shifted_period = TWO_PI << reduction_bit;
    wire [7:0] fixed_shift = angle_hold[30:23] - 8'd106;
    wire [63:0] fixed_input = {40'd0, 1'b1, angle_hold[22:0]} << fixed_shift;
    wire fixed_round_up = fixed_normal[39] &&
        (|fixed_normal[38:0] || fixed_normal[40]);
    wire [24:0] fixed_rounded = {1'b0, fixed_normal[63:40]} +
        {24'd0, fixed_round_up};
    wire [7:0] fixed_packed_exponent = 8'(fixed_exponent + 12'sd127 +
        (fixed_rounded[24] ? 12'sd1 : 12'sd0));
    wire [23:0] fixed_packed_mantissa = fixed_rounded[24] ?
        fixed_rounded[24:1] : fixed_rounded[23:0];
    wire coefficient_negative = degree[1];
    wire [31:0] signed_coefficient = {coefficient_negative, div_data[30:0]};
    wire [31:0] signed_sine = {reduced_negative ^ sine_hold[31], sine_hold[30:0]};
    reg [31:0] quadrant_sine, quadrant_cosine;
    wire [31:0] CONTROLLER_BITS = $bits(state) + $bits(return_state) +
        $bits(angle_hold) + $bits(reduced_float) + $bits(squared) +
        $bits(polynomial) + $bits(coefficient_hold) + $bits(value_hold) +
        $bits(sine_hold) + $bits(cosine_hold) + $bits(fp_a) + $bits(fp_b) +
        $bits(factorial_float) + $bits(fp_op) + $bits(error_hold) +
        $bits(degree) + $bits(cosine_phase) + $bits(first_coefficient) +
        $bits(reduced_negative) + $bits(quadrant_hold) + $bits(reduction_bit) +
        $bits(remainder_hold) + $bits(fixed_normal) + $bits(fixed_exponent) +
        $bits(quadrant_sine) + $bits(quadrant_cosine);
    wire [63:0] fp_controller_bytes, convert_controller_bytes, div_controller_bytes;
    assign controller_bytes = !rst_n ? 64'd0 :
        64'((CONTROLLER_BITS+7) >> 3) + fp_controller_bytes +
        convert_controller_bytes + div_controller_bytes;

    always @* begin
        quadrant_sine = 0;
        quadrant_cosine = 0;
        if (rst_n) begin
            case (quadrant_hold)
                0: begin
                    quadrant_sine = signed_sine;
                    quadrant_cosine = cosine_hold;
                end
                1: begin
                    quadrant_sine = cosine_hold;
                    quadrant_cosine = {~signed_sine[31], signed_sine[30:0]};
                end
                2: begin
                    quadrant_sine = {~signed_sine[31], signed_sine[30:0]};
                    quadrant_cosine = {~cosine_hold[31], cosine_hold[30:0]};
                end
                3: begin
                    quadrant_sine = {~cosine_hold[31], cosine_hold[30:0]};
                    quadrant_cosine = signed_sine;
                end
            endcase
        end
    end

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
    anvil_en1_uint_to_fp32 factorial_converter (
        .controller_bytes(convert_controller_bytes),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == COEFFICIENT_START), .start_ready(uint_ready),
        .operand(factorial_integer),
        .done_valid(uint_valid), .done_ready(rst_n && state == COEFFICIENT_WAIT),
        .done_data(uint_data), .done_error(uint_error)
    );
    anvil_en1_fp32_divsqrt coefficient_divider (
        .controller_bytes(div_controller_bytes),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == DIV_START), .start_ready(div_ready),
        .operation(2'd0), .operand_a(32'h3f800000), .operand_b(factorial_float),
        .done_valid(div_valid), .done_ready(rst_n && state == DIV_WAIT),
        .done_data(div_data), .done_error(div_error)
    );
    assign start_ready = rst_n && state == IDLE;
    assign done_valid = rst_n && state == RESPONSE;
    assign done_sin = rst_n ? sine_hold : 32'd0;
    assign done_cos = rst_n ? cosine_hold : 32'd0;
    assign done_error = rst_n ? error_hold : 4'd0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            return_state <= 0;
            angle_hold <= 0;
            reduced_float <= 0;
            squared <= 0;
            polynomial <= 0;
            coefficient_hold <= 0;
            value_hold <= 0;
            sine_hold <= 0;
            cosine_hold <= 0;
            fp_a <= 0;
            fp_b <= 0;
            factorial_float <= 0;
            fp_op <= 0;
            error_hold <= 0;
            degree <= 0;
            cosine_phase <= 0;
            first_coefficient <= 0;
            reduced_negative <= 0;
            quadrant_hold <= 0;
            reduction_bit <= 0;
            remainder_hold <= 0;
            fixed_normal <= 0;
            fixed_exponent <= 0;
        end else begin
            case (state)
                IDLE: if (start_valid && start_ready) begin
                    angle_hold <= operand;
                    error_hold <= 0;
                    sine_hold <= 0;
                    cosine_hold <= 0;
                    quadrant_hold <= 0;
                    reduced_negative <= 0;
                    state <= CLASSIFY;
                end
                CLASSIFY: begin
                    if (angle_hold[30:23] == 255) begin
                        sine_hold <= 32'h7fc00000;
                        cosine_hold <= 32'h7fc00000;
                        state <= PUBLISH;
                    end else if (angle_hold[30:0] > 31'h48800000) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else if (angle_hold[30:0] <= 31'h39800000) begin
                        sine_hold <= angle_hold;
                        cosine_hold <= 32'h3f800000;
                        state <= PUBLISH;
                    end else
                        state <= FIXED_SETUP;
                end
                FIXED_SETUP: begin
                    remainder_hold <= fixed_input;
                    reduction_bit <= 17;
                    state <= REDUCE;
                end
                REDUCE: begin
                    if (remainder_hold >= shifted_period)
                        remainder_hold <= remainder_hold - shifted_period;
                    if (reduction_bit == 0)
                        state <= QUADRANT;
                    else
                        reduction_bit <= reduction_bit - 1'b1;
                end
                QUADRANT: begin
                    if (remainder_hold <= QUARTER_PI) begin
                        fixed_normal <= remainder_hold;
                        quadrant_hold <= 0;
                        reduced_negative <= 0;
                    end else if (remainder_hold <= HALF_PI + QUARTER_PI) begin
                        quadrant_hold <= 1;
                        reduced_negative <= remainder_hold < HALF_PI;
                        fixed_normal <= remainder_hold < HALF_PI ?
                            HALF_PI - remainder_hold : remainder_hold - HALF_PI;
                    end else if (remainder_hold <= PI + QUARTER_PI) begin
                        quadrant_hold <= 2;
                        reduced_negative <= remainder_hold < PI;
                        fixed_normal <= remainder_hold < PI ?
                            PI - remainder_hold : remainder_hold - PI;
                    end else if (remainder_hold <= PI + HALF_PI + QUARTER_PI) begin
                        quadrant_hold <= 3;
                        reduced_negative <= remainder_hold < PI + HALF_PI;
                        fixed_normal <= remainder_hold < PI + HALF_PI ?
                            PI + HALF_PI - remainder_hold : remainder_hold - PI - HALF_PI;
                    end else begin
                        quadrant_hold <= 0;
                        reduced_negative <= 1;
                        fixed_normal <= TWO_PI - remainder_hold;
                    end
                    fixed_exponent <= 19;
                    state <= NORMALIZE;
                end
                NORMALIZE: begin
                    if (fixed_normal == 0) begin
                        reduced_float <= 0;
                        state <= SQUARE;
                    end else if (fixed_normal[63])
                        state <= ROUND;
                    else begin
                        fixed_normal <= fixed_normal << 1;
                        fixed_exponent <= fixed_exponent - 1'b1;
                    end
                end
                ROUND: begin
                    reduced_float <= {1'b0, fixed_packed_exponent,
                        fixed_packed_mantissa[22:0]};
                    state <= SQUARE;
                end
                SQUARE: begin
                    fp_op <= 1;
                    fp_a <= reduced_float;
                    fp_b <= reduced_float;
                    return_state <= POLYNOMIAL_SETUP;
                    state <= FP_START;
                end
                POLYNOMIAL_SETUP: begin
                    squared <= value_hold;
                    degree <= 11;
                    cosine_phase <= 0;
                    first_coefficient <= 1;
                    state <= COEFFICIENT_START;
                end
                COEFFICIENT_START: if (uint_ready)
                    state <= COEFFICIENT_WAIT;
                COEFFICIENT_WAIT: if (uint_valid) begin
                    if (uint_error != 0) begin
                        error_hold <= uint_error;
                        sine_hold <= 0;
                        cosine_hold <= 0;
                        state <= PUBLISH;
                    end else begin
                        factorial_float <= uint_data;
                        state <= DIV_START;
                    end
                end
                DIV_START: if (div_ready)
                    state <= DIV_WAIT;
                DIV_WAIT: if (div_valid) begin
                    if (div_error != 0) begin
                        error_hold <= div_error;
                        sine_hold <= 0;
                        cosine_hold <= 0;
                        state <= PUBLISH;
                    end else if (first_coefficient) begin
                        polynomial <= signed_coefficient;
                        first_coefficient <= 0;
                        degree <= degree - 2'd2;
                        state <= COEFFICIENT_START;
                    end else begin
                        coefficient_hold <= signed_coefficient;
                        state <= HORNER_MULTIPLY;
                    end
                end
                HORNER_MULTIPLY: begin
                    fp_op <= 1;
                    fp_a <= polynomial;
                    fp_b <= squared;
                    return_state <= HORNER_ADD;
                    state <= FP_START;
                end
                HORNER_ADD: begin
                    fp_op <= 0;
                    fp_a <= value_hold;
                    fp_b <= coefficient_hold;
                    return_state <= HORNER_ADVANCE;
                    state <= FP_START;
                end
                HORNER_ADVANCE: begin
                    polynomial <= value_hold;
                    if ((!cosine_phase && degree == 1) ||
                        (cosine_phase && degree == 0)) begin
                        if (cosine_phase) begin
                            cosine_hold <= value_hold;
                            state <= RESTORE;
                        end else
                            state <= SINE_FINISH;
                    end else begin
                        degree <= degree - 2'd2;
                        state <= COEFFICIENT_START;
                    end
                end
                SINE_FINISH: begin
                    fp_op <= 1;
                    fp_a <= polynomial;
                    fp_b <= reduced_float;
                    return_state <= COSINE_SETUP;
                    state <= FP_START;
                end
                COSINE_SETUP: begin
                    sine_hold <= value_hold;
                    cosine_phase <= 1;
                    first_coefficient <= 1;
                    degree <= 12;
                    state <= COEFFICIENT_START;
                end
                RESTORE: begin
                    sine_hold <= {angle_hold[31] ^ quadrant_sine[31],
                        quadrant_sine[30:0]};
                    cosine_hold <= quadrant_cosine;
                    state <= PUBLISH;
                end
                FP_START: if (fp_ready)
                    state <= FP_WAIT;
                FP_WAIT: if (fp_valid) begin
                    if (fp_error != 0) begin
                        error_hold <= fp_error;
                        sine_hold <= 0;
                        cosine_hold <= 0;
                        state <= PUBLISH;
                    end else begin
                        value_hold <= fp_data;
                        state <= return_state;
                    end
                end
                PUBLISH: state <= RESPONSE;
                RESPONSE: if (done_ready)
                    state <= IDLE;
                default: begin
                    sine_hold <= 0;
                    cosine_hold <= 0;
                    error_hold <= 7;
                    state <= PUBLISH;
                end
            endcase
        end
    end
endmodule
