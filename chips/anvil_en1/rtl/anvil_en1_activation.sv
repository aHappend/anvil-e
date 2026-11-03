module anvil_en1_activation #(
    parameter integer EXTERNAL_FP = 0
) (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] operation,
    input wire [31:0] operand,
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
    localparam [4:0] IDLE = 0, CLASSIFY = 1, GELU_SQUARE = 2,
        GELU_CUBE = 3, GELU_CUBIC_SCALE = 4, GELU_SUM = 5,
        GELU_ARGUMENT = 6, TANH_CLASSIFY = 7, TANH_SCALE = 8,
        TANH_NUMERATOR = 9, TANH_DENOMINATOR = 10, TANH_DIVIDE = 11,
        TANH_RETURN = 12, GELU_FACTOR = 13, GELU_HALF = 14,
        GELU_FINISH = 15, SIGMOID_ARGUMENT = 16, SIGMOID_DENOMINATOR = 17,
        SIGMOID_DIVIDE = 18, SIGMOID_RETURN = 19, SILU_FINISH = 20,
        FP_START = 21, FP_WAIT = 22, EXP_START = 23, EXP_WAIT = 24,
        DIV_START = 25, DIV_WAIT = 26, PUBLISH = 27, RESPONSE = 28;
    reg [4:0] state, return_state;
    reg [1:0] op;
    reg [31:0] x, value_hold, exponential, numerator, factor, tanh_argument;
    reg [31:0] fp_a, fp_b, exp_a, div_a, div_b, output_hold;
    reg [2:0] fp_op;
    reg [3:0] error_hold;
    wire [31:0] CONTROLLER_BITS = $bits(state) + $bits(return_state) +
        $bits(op) + $bits(x) + $bits(value_hold) + $bits(exponential) +
        $bits(numerator) + $bits(factor) + $bits(tanh_argument) + $bits(fp_a) +
        $bits(fp_b) + $bits(exp_a) + $bits(div_a) + $bits(div_b) +
        $bits(output_hold) + $bits(fp_op) + $bits(error_hold);
    wire [63:0] fp_controller_bytes, exp_controller_bytes, div_controller_bytes;
    assign controller_bytes = !rst_n ? 64'd0 :
        64'((CONTROLLER_BITS+7) >> 3) + fp_controller_bytes +
        exp_controller_bytes + div_controller_bytes;
    wire fp_ready, fp_valid, exp_ready, exp_valid, div_ready, div_valid;
    wire [31:0] fp_data, exp_data, div_data;
    wire [3:0] fp_error, exp_error, div_error;
    wire fp_accept = rst_n && state == FP_WAIT;
    wire exp_accept = rst_n && state == EXP_WAIT;
    wire div_accept = rst_n && state == DIV_WAIT;
    wire negative_sigmoid = x[31];
    wire tanh_negative = tanh_argument[31];
    wire [31:0] tanh_signed = {tanh_negative, value_hold[30:0]};
    wire exp_phase = state == EXP_START || state == EXP_WAIT;
    wire exp_arithmetic_valid, exp_arithmetic_result_ready;
    wire [2:0] exp_arithmetic_operation;
    wire [31:0] exp_arithmetic_a, exp_arithmetic_b;

    initial begin
        if (EXTERNAL_FP != 0 && EXTERNAL_FP != 1)
            $fatal(1, "PARAMETER ERROR: EXTERNAL_FP must be 0 or 1");
    end

    wire fp_start_valid = rst_n &&
        (exp_phase ? exp_arithmetic_valid : state == FP_START);
    wire fp_done_ready = rst_n &&
        (exp_phase ? exp_arithmetic_result_ready : fp_accept);
    wire [2:0] fp_operation = exp_phase ? exp_arithmetic_operation : fp_op;
    wire [31:0] fp_operand_a = exp_phase ? exp_arithmetic_a : fp_a;
    wire [31:0] fp_operand_b = exp_phase ? exp_arithmetic_b : fp_b;
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
    anvil_en1_exp #(.EXTERNAL_FP(1)) exp_unit (
        .controller_bytes(exp_controller_bytes),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == EXP_START), .start_ready(exp_ready),
        .operand(exp_a), .done_valid(exp_valid), .done_ready(exp_accept),
        .done_data(exp_data), .done_error(exp_error),
        .arithmetic_valid(exp_arithmetic_valid),
        .arithmetic_ready(exp_phase && fp_ready),
        .arithmetic_operation(exp_arithmetic_operation),
        .arithmetic_a(exp_arithmetic_a), .arithmetic_b(exp_arithmetic_b),
        .arithmetic_result_valid(exp_phase && fp_valid),
        .arithmetic_result_ready(exp_arithmetic_result_ready),
        .arithmetic_result_data(fp_data), .arithmetic_result_error(fp_error)
    );
    anvil_en1_fp32_divsqrt div_unit (
        .controller_bytes(div_controller_bytes),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == DIV_START), .start_ready(div_ready),
        .operation(2'd0), .operand_a(div_a), .operand_b(div_b),
        .done_valid(div_valid), .done_ready(div_accept),
        .done_data(div_data), .done_error(div_error)
    );

    assign start_ready = rst_n && state == IDLE;
    assign done_valid = rst_n && state == RESPONSE;
    assign done_data = rst_n ? output_hold : 32'd0;
    assign done_error = rst_n ? error_hold : 4'd0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            return_state <= 0;
            op <= 0;
            x <= 0;
            value_hold <= 0;
            exponential <= 0;
            numerator <= 0;
            factor <= 0;
            tanh_argument <= 0;
            fp_a <= 0;
            fp_b <= 0;
            exp_a <= 0;
            div_a <= 0;
            div_b <= 0;
            output_hold <= 0;
            fp_op <= 0;
            error_hold <= 0;
        end else begin
            case (state)
                IDLE: if (start_valid && start_ready) begin
                    op <= operation;
                    x <= operand;
                    tanh_argument <= operand;
                    error_hold <= 0;
                    state <= CLASSIFY;
                end
                CLASSIFY: begin
                    if (x[30:23] == 255 && x[22:0] != 0) begin
                        output_hold <= 32'h7fc00000;
                        state <= PUBLISH;
                    end else if (op == 0)
                        state <= TANH_CLASSIFY;
                    else if (op == 1) begin
                        if (x[30:23] == 255) begin
                            output_hold <= x[31] ? 32'h7fc00000 : x;
                            state <= PUBLISH;
                        end else
                            state <= GELU_SQUARE;
                    end else
                        state <= SIGMOID_ARGUMENT;
                end
                GELU_SQUARE: begin
                    fp_op <= 1;
                    fp_a <= x;
                    fp_b <= x;
                    return_state <= GELU_CUBE;
                    state <= FP_START;
                end
                GELU_CUBE: begin
                    fp_op <= 1;
                    fp_a <= value_hold;
                    fp_b <= x;
                    return_state <= GELU_CUBIC_SCALE;
                    state <= FP_START;
                end
                GELU_CUBIC_SCALE: begin
                    fp_op <= 1;
                    fp_a <= value_hold;
                    fp_b <= 32'h3d372713;
                    return_state <= GELU_SUM;
                    state <= FP_START;
                end
                GELU_SUM: begin
                    fp_op <= 0;
                    fp_a <= x;
                    fp_b <= value_hold;
                    return_state <= GELU_ARGUMENT;
                    state <= FP_START;
                end
                GELU_ARGUMENT: begin
                    fp_op <= 1;
                    fp_a <= value_hold;
                    fp_b <= 32'h3f4c422a;
                    return_state <= TANH_CLASSIFY;
                    state <= FP_START;
                end
                TANH_CLASSIFY: begin
                    if (op == 1)
                        tanh_argument <= value_hold;
                    if ((op == 1 ? value_hold[30:0] : tanh_argument[30:0]) >=
                        31'h41000000) begin
                        value_hold <= 32'h3f800000;
                        state <= TANH_RETURN;
                    end else if ((op == 1 ? value_hold[30:0] : tanh_argument[30:0]) == 0) begin
                        value_hold <= 0;
                        state <= TANH_RETURN;
                    end else
                        state <= TANH_SCALE;
                end
                TANH_SCALE: begin
                    fp_op <= 1;
                    fp_a <= {1'b1, tanh_argument[30:0]};
                    fp_b <= 32'h40000000;
                    return_state <= TANH_NUMERATOR;
                    state <= FP_START;
                end
                TANH_NUMERATOR: begin
                    exp_a <= value_hold;
                    return_state <= TANH_DENOMINATOR;
                    state <= EXP_START;
                end
                TANH_DENOMINATOR: begin
                    fp_op <= 0;
                    fp_a <= 32'h3f800000;
                    fp_b <= {1'b1, exponential[30:0]};
                    return_state <= TANH_DIVIDE;
                    state <= FP_START;
                end
                TANH_DIVIDE: begin
                    numerator <= value_hold;
                    fp_op <= 0;
                    fp_a <= 32'h3f800000;
                    fp_b <= exponential;
                    return_state <= DIV_START;
                    state <= FP_START;
                end
                DIV_START: begin
                    if (div_ready)
                        state <= DIV_WAIT;
                end
                TANH_RETURN: begin
                    if (op == 1) begin
                        value_hold <= tanh_signed;
                        state <= GELU_FACTOR;
                    end else begin
                        output_hold <= tanh_signed;
                        state <= PUBLISH;
                    end
                end
                GELU_FACTOR: begin
                    fp_op <= 0;
                    fp_a <= 32'h3f800000;
                    fp_b <= value_hold;
                    return_state <= GELU_HALF;
                    state <= FP_START;
                end
                GELU_HALF: begin
                    factor <= value_hold;
                    fp_op <= 1;
                    fp_a <= 32'h3f000000;
                    fp_b <= x;
                    return_state <= GELU_FINISH;
                    state <= FP_START;
                end
                GELU_FINISH: begin
                    fp_op <= 1;
                    fp_a <= value_hold;
                    fp_b <= factor;
                    return_state <= PUBLISH;
                    state <= FP_START;
                end
                SIGMOID_ARGUMENT: begin
                    exp_a <= {1'b1, x[30:0]};
                    return_state <= SIGMOID_DENOMINATOR;
                    state <= EXP_START;
                end
                SIGMOID_DENOMINATOR: begin
                    fp_op <= 0;
                    fp_a <= 32'h3f800000;
                    fp_b <= exponential;
                    return_state <= SIGMOID_DIVIDE;
                    state <= FP_START;
                end
                SIGMOID_DIVIDE: begin
                    div_a <= negative_sigmoid ? exponential : 32'h3f800000;
                    div_b <= value_hold;
                    return_state <= SIGMOID_RETURN;
                    state <= DIV_START;
                end
                SIGMOID_RETURN: begin
                    if (op == 2)
                        state <= SILU_FINISH;
                    else begin
                        output_hold <= value_hold;
                        state <= PUBLISH;
                    end
                end
                SILU_FINISH: begin
                    fp_op <= 1;
                    fp_a <= x;
                    fp_b <= value_hold;
                    return_state <= PUBLISH;
                    state <= FP_START;
                end
                FP_START: if (fp_ready)
                    state <= FP_WAIT;
                FP_WAIT: if (fp_valid && fp_accept) begin
                    if (fp_error != 0) begin
                        output_hold <= 0;
                        error_hold <= fp_error;
                        state <= PUBLISH;
                    end else begin
                        value_hold <= fp_data;
                        if (return_state == DIV_START) begin
                            div_a <= numerator;
                            div_b <= fp_data;
                            return_state <= TANH_RETURN;
                        end
                        if (return_state == PUBLISH)
                            output_hold <= fp_data;
                        state <= return_state;
                    end
                end
                EXP_START: if (exp_ready)
                    state <= EXP_WAIT;
                EXP_WAIT: if (exp_valid && exp_accept) begin
                    if (exp_error != 0) begin
                        output_hold <= 0;
                        error_hold <= exp_error;
                        state <= PUBLISH;
                    end else begin
                        exponential <= exp_data;
                        state <= return_state;
                    end
                end
                DIV_WAIT: if (div_valid && div_accept) begin
                    if (div_error != 0) begin
                        output_hold <= 0;
                        error_hold <= div_error;
                        state <= PUBLISH;
                    end else begin
                        value_hold <= div_data;
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
