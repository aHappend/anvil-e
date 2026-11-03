module anvil_en1_audio_relative_position (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [3:0] distance,
    input wire [9:0] component,
    output wire done_valid,
    input wire done_ready,
    output wire [15:0] done_data,
    output wire [3:0] done_error,
    output wire [63:0] controller_bytes
);
    localparam [4:0] IDLE = 0, VALIDATE = 1, INCREMENT_START = 2,
        INCREMENT_WAIT = 3, INDEX_START = 4, INDEX_WAIT = 5,
        EXP_ARGUMENT = 6, EXP_START = 7, EXP_WAIT = 8,
        DISTANCE_START = 9, DISTANCE_WAIT = 10, ANGLE = 11,
        TRIG_START = 12, TRIG_WAIT = 13, NARROW = 14,
        OUTPUT_REGISTER = 15, FP_START = 16, FP_WAIT = 17,
        PUBLISH = 18, RESPONSE = 19;
    reg [4:0] state, fp_return;
    reg [3:0] distance_hold, error_hold;
    reg [9:0] component_hold;
    reg [31:0] increment, index_float, inverse, distance_float, exp_argument;
    reg [31:0] fp_a, fp_b, fp_value, trig_value;
    reg [15:0] output_hold;
    reg [2:0] fp_op;
    wire fp_ready, fp_valid, div_ready, div_valid, uint_ready, uint_valid;
    wire exp_ready, exp_valid, trig_ready, trig_valid;
    wire [31:0] fp_data, div_data, uint_data, exp_data, sine_data, cosine_data;
    wire [3:0] fp_error, div_error, uint_error, exp_error, trig_error;
    wire [63:0] primitive_fp_bytes, primitive_div_bytes, primitive_convert_bytes;
    wire [63:0] primitive_exp_bytes, primitive_trig_bytes;
    wire exp_phase = state == EXP_START || state == EXP_WAIT;
    wire exp_arithmetic_valid, exp_arithmetic_result_ready;
    wire [2:0] exp_arithmetic_operation;
    wire [31:0] exp_arithmetic_a, exp_arithmetic_b;
    anvil_en1_fp32 arithmetic (
        .controller_bytes(primitive_fp_bytes),
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
    anvil_en1_fp32_divsqrt timescale_increment (
        .controller_bytes(primitive_div_bytes),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == INCREMENT_START), .start_ready(div_ready),
        .operation(2'd0), .operand_a(32'h41135d8e), .operand_b(32'h43ff8000),
        .done_valid(div_valid), .done_ready(rst_n && state == INCREMENT_WAIT),
        .done_data(div_data), .done_error(div_error)
    );
    anvil_en1_uint_to_fp32 integer_converter (
        .controller_bytes(primitive_convert_bytes),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && (state == INDEX_START || state == DISTANCE_START)),
        .start_ready(uint_ready),
        .operand(state == INDEX_START ? {23'd0, component_hold[8:0]} :
            {28'd0, distance_hold}),
        .done_valid(uint_valid),
        .done_ready(rst_n && (state == INDEX_WAIT || state == DISTANCE_WAIT)),
        .done_data(uint_data), .done_error(uint_error)
    );
    anvil_en1_exp #(.EXTERNAL_FP(1)) exponent (
        .controller_bytes(primitive_exp_bytes),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == EXP_START), .start_ready(exp_ready),
        .operand(exp_argument),
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
    anvil_en1_sincos trigonometry (
        .controller_bytes(primitive_trig_bytes),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == TRIG_START), .start_ready(trig_ready),
        .operand(fp_value), .done_valid(trig_valid),
        .done_ready(rst_n && state == TRIG_WAIT),
        .done_sin(sine_data), .done_cos(cosine_data), .done_error(trig_error)
    );
    assign start_ready = rst_n && state == IDLE;
    assign done_valid = rst_n && state == RESPONSE;
    assign done_data = rst_n ? output_hold : 16'd0;
    assign done_error = rst_n ? error_hold : 4'd0;
    wire [31:0] CONTROLLER_BITS =
        $bits(state) + $bits(fp_return) + $bits(distance_hold) +
        $bits(error_hold) + $bits(component_hold) + $bits(increment) +
        $bits(index_float) + $bits(inverse) + $bits(distance_float) +
        $bits(exp_argument) + $bits(fp_a) + $bits(fp_b) +
        $bits(fp_value) + $bits(trig_value) + $bits(output_hold) + $bits(fp_op);
    assign controller_bytes = !rst_n ? 64'd0 : 64'((CONTROLLER_BITS + 7) >> 3) +
        primitive_fp_bytes + primitive_div_bytes + primitive_convert_bytes +
        primitive_exp_bytes + primitive_trig_bytes;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            fp_return <= 0;
            distance_hold <= 0;
            error_hold <= 0;
            component_hold <= 0;
            increment <= 0;
            index_float <= 0;
            inverse <= 0;
            distance_float <= 0;
            exp_argument <= 0;
            fp_a <= 0;
            fp_b <= 0;
            fp_value <= 0;
            trig_value <= 0;
            output_hold <= 0;
            fp_op <= 0;
        end else begin
            case (state)
                IDLE: if (start_valid && start_ready) begin
                    distance_hold <= distance;
                    component_hold <= component;
                    output_hold <= 0;
                    error_hold <= 0;
                    state <= VALIDATE;
                end
                VALIDATE: begin
                    if (distance_hold > 12) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else
                        state <= INCREMENT_START;
                end
                INCREMENT_START: if (div_ready)
                    state <= INCREMENT_WAIT;
                INCREMENT_WAIT: if (div_valid) begin
                    if (div_error != 0) begin
                        error_hold <= div_error;
                        state <= PUBLISH;
                    end else begin
                        increment <= div_data;
                        state <= INDEX_START;
                    end
                end
                INDEX_START: if (uint_ready)
                    state <= INDEX_WAIT;
                INDEX_WAIT: if (uint_valid) begin
                    if (uint_error != 0) begin
                        error_hold <= uint_error;
                        state <= PUBLISH;
                    end else begin
                        index_float <= uint_data;
                        state <= EXP_ARGUMENT;
                    end
                end
                EXP_ARGUMENT: begin
                    fp_op <= 1;
                    fp_a <= index_float;
                    fp_b <= {1'b1, increment[30:0]};
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
                        inverse <= exp_data;
                        state <= DISTANCE_START;
                    end
                end
                DISTANCE_START: if (uint_ready)
                    state <= DISTANCE_WAIT;
                DISTANCE_WAIT: if (uint_valid) begin
                    if (uint_error != 0) begin
                        error_hold <= uint_error;
                        state <= PUBLISH;
                    end else begin
                        distance_float <= uint_data;
                        state <= ANGLE;
                    end
                end
                ANGLE: begin
                    fp_op <= 1;
                    fp_a <= distance_float;
                    fp_b <= inverse;
                    fp_return <= TRIG_START;
                    state <= FP_START;
                end
                TRIG_START: if (trig_ready)
                    state <= TRIG_WAIT;
                TRIG_WAIT: if (trig_valid) begin
                    if (trig_error != 0) begin
                        error_hold <= trig_error;
                        state <= PUBLISH;
                    end else begin
                        trig_value <= component_hold[9] ? cosine_data : sine_data;
                        state <= NARROW;
                    end
                end
                NARROW: begin
                    fp_op <= 3;
                    fp_a <= trig_value;
                    fp_b <= 0;
                    fp_return <= OUTPUT_REGISTER;
                    state <= FP_START;
                end
                OUTPUT_REGISTER: begin
                    output_hold <= fp_value[15:0];
                    state <= PUBLISH;
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
                            exp_argument <= fp_data;
                        state <= fp_return;
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
