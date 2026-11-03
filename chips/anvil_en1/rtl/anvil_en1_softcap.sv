module anvil_en1_softcap #(
    parameter integer EXTERNAL_FP = 0
) (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire cap_50, input_binary32, output_binary32,
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
    localparam [3:0] IDLE = 0, DIV_START = 1, DIV_WAIT = 2,
        TANH_START = 3, TANH_WAIT = 4, MULTIPLY = 5,
        NARROW = 6, FP_START = 7, FP_WAIT = 8,
        PUBLISH = 9, RESPONSE = 10;
    reg [3:0] state, return_state;
    reg [31:0] operand_hold, cap_hold, value_hold, fp_a, fp_b, output_hold;
    reg [2:0] fp_op;
    reg [3:0] error_hold;
    reg output_binary32_hold;
    wire [31:0] CONTROLLER_BITS = $bits(state) + $bits(return_state) +
        $bits(operand_hold) + $bits(cap_hold) + $bits(value_hold) + $bits(fp_a) +
        $bits(fp_b) + $bits(output_hold) + $bits(fp_op) + $bits(error_hold) +
        $bits(output_binary32_hold);
    wire [63:0] div_controller_bytes, activation_controller_bytes, fp_controller_bytes;
    assign controller_bytes = !rst_n ? 64'd0 :
        64'((CONTROLLER_BITS+7) >> 3) + div_controller_bytes +
        activation_controller_bytes + fp_controller_bytes;
    wire div_ready, div_valid, tanh_ready, tanh_valid, fp_ready, fp_valid;
    wire [31:0] div_data, tanh_data, fp_data;
    wire [3:0] div_error, tanh_error, fp_error;
    wire tanh_phase = state == TANH_START || state == TANH_WAIT;
    wire tanh_arithmetic_valid, tanh_arithmetic_result_ready;
    wire [2:0] tanh_arithmetic_operation;
    wire [31:0] tanh_arithmetic_a, tanh_arithmetic_b;

    initial begin
        if (EXTERNAL_FP != 0 && EXTERNAL_FP != 1)
            $fatal(1, "PARAMETER ERROR: EXTERNAL_FP must be 0 or 1");
    end

    anvil_en1_fp32_divsqrt cap_divider (
        .controller_bytes(div_controller_bytes),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == DIV_START), .start_ready(div_ready),
        .operation(2'd0), .operand_a(operand_hold), .operand_b(cap_hold),
        .done_valid(div_valid), .done_ready(rst_n && state == DIV_WAIT),
        .done_data(div_data), .done_error(div_error)
    );
    anvil_en1_activation #(.EXTERNAL_FP(1)) tanh_unit (
        .controller_bytes(activation_controller_bytes),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == TANH_START), .start_ready(tanh_ready),
        .operation(2'd0), .operand(value_hold),
        .done_valid(tanh_valid), .done_ready(rst_n && state == TANH_WAIT),
        .done_data(tanh_data), .done_error(tanh_error),
        .arithmetic_valid(tanh_arithmetic_valid),
        .arithmetic_ready(tanh_phase && fp_ready),
        .arithmetic_operation(tanh_arithmetic_operation),
        .arithmetic_a(tanh_arithmetic_a), .arithmetic_b(tanh_arithmetic_b),
        .arithmetic_result_valid(tanh_phase && fp_valid),
        .arithmetic_result_ready(tanh_arithmetic_result_ready),
        .arithmetic_result_data(fp_data), .arithmetic_result_error(fp_error)
    );
    wire fp_start_valid = rst_n &&
        (tanh_phase ? tanh_arithmetic_valid : state == FP_START);
    wire fp_done_ready = rst_n &&
        (tanh_phase ? tanh_arithmetic_result_ready : state == FP_WAIT);
    wire [2:0] fp_operation = tanh_phase ? tanh_arithmetic_operation : fp_op;
    wire [31:0] fp_operand_a = tanh_phase ? tanh_arithmetic_a : fp_a;
    wire [31:0] fp_operand_b = tanh_phase ? tanh_arithmetic_b : fp_b;
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
            operand_hold <= 0;
            cap_hold <= 0;
            value_hold <= 0;
            fp_a <= 0;
            fp_b <= 0;
            output_hold <= 0;
            fp_op <= 0;
            error_hold <= 0;
            output_binary32_hold <= 0;
        end else begin
            case (state)
                IDLE: if (start_valid && start_ready) begin
                    operand_hold <= input_binary32 ? operand : {operand[15:0], 16'd0};
                    cap_hold <= cap_50 ? 32'h42480000 : 32'h41f00000;
                    output_binary32_hold <= output_binary32;
                    output_hold <= 0;
                    error_hold <= 0;
                    state <= DIV_START;
                end
                DIV_START: if (div_ready)
                    state <= DIV_WAIT;
                DIV_WAIT: if (div_valid) begin
                    if (div_error != 0) begin
                        error_hold <= div_error;
                        state <= PUBLISH;
                    end else begin
                        value_hold <= div_data;
                        state <= TANH_START;
                    end
                end
                TANH_START: if (tanh_ready)
                    state <= TANH_WAIT;
                TANH_WAIT: if (tanh_valid) begin
                    if (tanh_error != 0) begin
                        error_hold <= tanh_error;
                        state <= PUBLISH;
                    end else begin
                        value_hold <= tanh_data;
                        state <= MULTIPLY;
                    end
                end
                MULTIPLY: begin
                    fp_op <= 1;
                    fp_a <= value_hold;
                    fp_b <= cap_hold;
                    return_state <= NARROW;
                    state <= FP_START;
                end
                NARROW: begin
                    if (output_binary32_hold) begin
                        output_hold <= value_hold;
                        state <= PUBLISH;
                    end else begin
                        fp_op <= 3;
                        fp_a <= value_hold;
                        fp_b <= 0;
                        return_state <= PUBLISH;
                        state <= FP_START;
                    end
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
                        if (return_state == PUBLISH)
                            output_hold <= fp_data;
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
