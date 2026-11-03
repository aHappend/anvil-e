module anvil_en1_rotary_pair #(
    parameter integer SIGNED_POSITION = 0,
    parameter integer EXTERNAL_FP = 0
) (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] mode,
    input wire [9:0] dimension,
    input wire [8:0] pair_index,
    input wire [31:0] position,
    input wire [31:0] vector_pair,
    output wire done_valid,
    input wire done_ready,
    output wire [31:0] done_data,
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
    localparam [5:0] IDLE = 0, VALIDATE = 1, FREQUENCY_START = 2,
        FREQUENCY_WAIT = 3, POSITION_START = 4, POSITION_WAIT = 5,
        ANGLE = 6, TRIG_START = 7, TRIG_WAIT = 8, NARROW_SINE = 9,
        NARROW_COSINE = 10, SAVE_COSINE = 11, FIRST_COSINE = 12,
        FIRST_SINE = 13, FIRST_SUM = 14, FIRST_NARROW = 15,
        SECOND_COSINE = 16, SECOND_SINE = 17, SECOND_SUM = 18,
        SECOND_NARROW = 19, OUTPUT_PREPARE = 20,
        FP_START = 21, FP_WAIT = 22, PUBLISH = 23, RESPONSE = 24;
    reg [5:0] state, return_state;
    reg [1:0] mode_hold;
    reg [9:0] dimension_hold;
    reg [8:0] index_hold;
    reg [31:0] position_hold, pair_hold, frequency_hold, position_float;
    reg [31:0] angle_hold, sine_float, cosine_float, value_hold, product_hold;
    reg [31:0] fp_a, fp_b, output_hold;
    reg [15:0] sine_bf16, cosine_bf16, first_output;
    reg [2:0] fp_op;
    reg [3:0] error_hold;
    wire [31:0] CONTROLLER_BITS = $bits(state) + $bits(return_state) +
        $bits(mode_hold) + $bits(dimension_hold) + $bits(index_hold) +
        $bits(position_hold) + $bits(pair_hold) + $bits(frequency_hold) +
        $bits(position_float) + $bits(angle_hold) + $bits(sine_float) +
        $bits(cosine_float) + $bits(value_hold) + $bits(product_hold) +
        $bits(fp_a) + $bits(fp_b) + $bits(output_hold) + $bits(sine_bf16) +
        $bits(cosine_bf16) + $bits(first_output) + $bits(fp_op) + $bits(error_hold);
    wire [63:0] frequency_controller_bytes, convert_controller_bytes;
    wire [63:0] trig_controller_bytes, fp_controller_bytes;
    assign controller_bytes = !rst_n ? 64'd0 :
        64'((CONTROLLER_BITS+7) >> 3) + frequency_controller_bytes +
        convert_controller_bytes + trig_controller_bytes + fp_controller_bytes;
    wire frequency_ready, frequency_valid, position_ready, position_valid;
    wire trig_ready, trig_valid, fp_ready, fp_valid;
    wire [31:0] frequency_data, position_data, trig_sine, trig_cosine, fp_data;
    wire [3:0] frequency_error, position_error, trig_error, fp_error;
    wire negative_position = SIGNED_POSITION == 1 && position_hold[31];
    wire [31:0] position_magnitude = negative_position ?
        (~position_hold + 32'd1) : position_hold;
    wire frequency_phase = state == FREQUENCY_START || state == FREQUENCY_WAIT;
    wire trig_phase = state == TRIG_START || state == TRIG_WAIT;
    wire frequency_arithmetic_valid, frequency_arithmetic_result_ready;
    wire trig_arithmetic_valid, trig_arithmetic_result_ready;
    wire [2:0] frequency_arithmetic_operation, trig_arithmetic_operation;
    wire [31:0] frequency_arithmetic_a, frequency_arithmetic_b;
    wire [31:0] trig_arithmetic_a, trig_arithmetic_b;

    initial begin
        if (SIGNED_POSITION != 0 && SIGNED_POSITION != 1)
            $fatal(1, "PARAMETER ERROR: SIGNED_POSITION must be 0 or 1");
        if (EXTERNAL_FP != 0 && EXTERNAL_FP != 1)
            $fatal(1, "PARAMETER ERROR: EXTERNAL_FP must be 0 or 1");
    end

    anvil_en1_rope_frequency #(.EXTERNAL_FP(1)) frequency_unit (
        .controller_bytes(frequency_controller_bytes),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == FREQUENCY_START), .start_ready(frequency_ready),
        .mode(mode_hold), .dimension(dimension_hold), .pair_index(index_hold),
        .done_valid(frequency_valid), .done_ready(rst_n && state == FREQUENCY_WAIT),
        .done_data(frequency_data), .done_error(frequency_error),
        .arithmetic_valid(frequency_arithmetic_valid),
        .arithmetic_ready(frequency_phase && fp_ready),
        .arithmetic_operation(frequency_arithmetic_operation),
        .arithmetic_a(frequency_arithmetic_a), .arithmetic_b(frequency_arithmetic_b),
        .arithmetic_result_valid(frequency_phase && fp_valid),
        .arithmetic_result_ready(frequency_arithmetic_result_ready),
        .arithmetic_result_data(fp_data), .arithmetic_result_error(fp_error)
    );
    anvil_en1_uint_to_fp32 position_converter (
        .controller_bytes(convert_controller_bytes),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == POSITION_START), .start_ready(position_ready),
        .operand(position_magnitude),
        .done_valid(position_valid), .done_ready(rst_n && state == POSITION_WAIT),
        .done_data(position_data), .done_error(position_error)
    );
    anvil_en1_sincos #(.EXTERNAL_FP(1)) trig_unit (
        .controller_bytes(trig_controller_bytes),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == TRIG_START), .start_ready(trig_ready),
        .operand(angle_hold),
        .done_valid(trig_valid), .done_ready(rst_n && state == TRIG_WAIT),
        .done_sin(trig_sine), .done_cos(trig_cosine), .done_error(trig_error),
        .arithmetic_valid(trig_arithmetic_valid),
        .arithmetic_ready(trig_phase && fp_ready),
        .arithmetic_operation(trig_arithmetic_operation),
        .arithmetic_a(trig_arithmetic_a), .arithmetic_b(trig_arithmetic_b),
        .arithmetic_result_valid(trig_phase && fp_valid),
        .arithmetic_result_ready(trig_arithmetic_result_ready),
        .arithmetic_result_data(fp_data), .arithmetic_result_error(fp_error)
    );
    wire fp_start_valid = rst_n && (frequency_phase ? frequency_arithmetic_valid :
        (trig_phase ? trig_arithmetic_valid : state == FP_START));
    wire fp_done_ready = rst_n && (frequency_phase ? frequency_arithmetic_result_ready :
        (trig_phase ? trig_arithmetic_result_ready : state == FP_WAIT));
    wire [2:0] fp_operation = frequency_phase ? frequency_arithmetic_operation :
        (trig_phase ? trig_arithmetic_operation : fp_op);
    wire [31:0] fp_operand_a = frequency_phase ? frequency_arithmetic_a :
        (trig_phase ? trig_arithmetic_a : fp_a);
    wire [31:0] fp_operand_b = frequency_phase ? frequency_arithmetic_b :
        (trig_phase ? trig_arithmetic_b : fp_b);
    assign arithmetic_valid = EXTERNAL_FP == 1 && fp_start_valid;
    assign arithmetic_operation = rst_n && EXTERNAL_FP == 1 ? fp_operation : 3'd0;
    assign arithmetic_a = rst_n && EXTERNAL_FP == 1 ? fp_operand_a : 32'd0;
    assign arithmetic_b = rst_n && EXTERNAL_FP == 1 ? fp_operand_b : 32'd0;
    assign arithmetic_result_ready = EXTERNAL_FP == 1 && fp_done_ready;
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
                .start_valid(fp_start_valid), .start_ready(fp_ready),
                .operation(fp_operation), .operand_a(fp_operand_a), .operand_b(fp_operand_b),
                .done_valid(fp_valid), .done_ready(fp_done_ready),
                .done_data(fp_data), .done_error(fp_error)
            );
        end
    endgenerate
    assign start_ready = rst_n && state == IDLE;
    assign done_valid = rst_n && state == RESPONSE;
    assign done_data = rst_n ? output_hold : 32'd0;
    assign done_error = rst_n ? error_hold : 4'd0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            return_state <= 0;
            mode_hold <= 0;
            dimension_hold <= 0;
            index_hold <= 0;
            position_hold <= 0;
            pair_hold <= 0;
            frequency_hold <= 0;
            position_float <= 0;
            angle_hold <= 0;
            sine_float <= 0;
            cosine_float <= 0;
            value_hold <= 0;
            product_hold <= 0;
            fp_a <= 0;
            fp_b <= 0;
            output_hold <= 0;
            sine_bf16 <= 0;
            cosine_bf16 <= 0;
            first_output <= 0;
            fp_op <= 0;
            error_hold <= 0;
        end else begin
            case (state)
                IDLE: if (start_valid && start_ready) begin
                    mode_hold <= mode;
                    dimension_hold <= dimension;
                    index_hold <= pair_index;
                    position_hold <= position;
                    pair_hold <= vector_pair;
                    output_hold <= 0;
                    error_hold <= 0;
                    state <= VALIDATE;
                end
                VALIDATE: begin
                    if (position_magnitude > 131071) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else
                        state <= FREQUENCY_START;
                end
                FREQUENCY_START: if (frequency_ready)
                    state <= FREQUENCY_WAIT;
                FREQUENCY_WAIT: if (frequency_valid) begin
                    if (frequency_error != 0) begin
                        error_hold <= frequency_error;
                        state <= PUBLISH;
                    end else begin
                        frequency_hold <= frequency_data;
                        state <= POSITION_START;
                    end
                end
                POSITION_START: if (position_ready)
                    state <= POSITION_WAIT;
                POSITION_WAIT: if (position_valid) begin
                    if (position_error != 0) begin
                        error_hold <= position_error;
                        state <= PUBLISH;
                    end else begin
                        position_float <= negative_position ?
                            {1'b1, position_data[30:0]} : position_data;
                        state <= ANGLE;
                    end
                end
                ANGLE: begin
                    fp_op <= 1;
                    fp_a <= frequency_hold;
                    fp_b <= position_float;
                    return_state <= TRIG_START;
                    state <= FP_START;
                end
                TRIG_START: if (trig_ready)
                    state <= TRIG_WAIT;
                TRIG_WAIT: if (trig_valid) begin
                    if (trig_error != 0) begin
                        error_hold <= trig_error;
                        state <= PUBLISH;
                    end else begin
                        sine_float <= trig_sine;
                        cosine_float <= trig_cosine;
                        state <= NARROW_SINE;
                    end
                end
                NARROW_SINE: begin
                    fp_op <= 3;
                    fp_a <= sine_float;
                    fp_b <= 0;
                    return_state <= NARROW_COSINE;
                    state <= FP_START;
                end
                NARROW_COSINE: begin
                    sine_bf16 <= value_hold[15:0];
                    fp_op <= 3;
                    fp_a <= cosine_float;
                    fp_b <= 0;
                    return_state <= SAVE_COSINE;
                    state <= FP_START;
                end
                SAVE_COSINE: begin
                    cosine_bf16 <= value_hold[15:0];
                    state <= FIRST_COSINE;
                end
                FIRST_COSINE: begin
                    fp_op <= 1;
                    fp_a <= {pair_hold[15:0], 16'd0};
                    fp_b <= {cosine_bf16, 16'd0};
                    return_state <= FIRST_SINE;
                    state <= FP_START;
                end
                FIRST_SINE: begin
                    product_hold <= value_hold;
                    fp_op <= 1;
                    fp_a <= {pair_hold[31:16], 16'd0};
                    fp_b <= {sine_bf16, 16'd0};
                    return_state <= FIRST_SUM;
                    state <= FP_START;
                end
                FIRST_SUM: begin
                    fp_op <= 0;
                    fp_a <= product_hold;
                    fp_b <= {~value_hold[31], value_hold[30:0]};
                    return_state <= FIRST_NARROW;
                    state <= FP_START;
                end
                FIRST_NARROW: begin
                    fp_op <= 3;
                    fp_a <= value_hold;
                    fp_b <= 0;
                    return_state <= SECOND_COSINE;
                    state <= FP_START;
                end
                SECOND_COSINE: begin
                    first_output <= value_hold[15:0];
                    fp_op <= 1;
                    fp_a <= {pair_hold[31:16], 16'd0};
                    fp_b <= {cosine_bf16, 16'd0};
                    return_state <= SECOND_SINE;
                    state <= FP_START;
                end
                SECOND_SINE: begin
                    product_hold <= value_hold;
                    fp_op <= 1;
                    fp_a <= {pair_hold[15:0], 16'd0};
                    fp_b <= {sine_bf16, 16'd0};
                    return_state <= SECOND_SUM;
                    state <= FP_START;
                end
                SECOND_SUM: begin
                    fp_op <= 0;
                    fp_a <= product_hold;
                    fp_b <= value_hold;
                    return_state <= SECOND_NARROW;
                    state <= FP_START;
                end
                SECOND_NARROW: begin
                    fp_op <= 3;
                    fp_a <= value_hold;
                    fp_b <= 0;
                    return_state <= OUTPUT_PREPARE;
                    state <= FP_START;
                end
                OUTPUT_PREPARE: begin
                    output_hold <= {value_hold[15:0], first_output};
                    state <= PUBLISH;
                end
                FP_START: if (fp_ready)
                    state <= FP_WAIT;
                FP_WAIT: if (fp_valid) begin
                    if (fp_error != 0) begin
                        output_hold <= 0;
                        error_hold <= fp_error;
                        state <= PUBLISH;
                    end else begin
                        value_hold <= fp_data;
                        if (return_state == TRIG_START)
                            angle_hold <= fp_data;
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
endmodule
