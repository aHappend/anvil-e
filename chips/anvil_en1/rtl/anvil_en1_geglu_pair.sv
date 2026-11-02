module anvil_en1_geglu_pair (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] operation,
    input wire [15:0] gate_data, up_data,
    output wire done_valid,
    input wire done_ready,
    output wire [31:0] done_data,
    output wire [3:0] done_error,
    output wire [63:0] controller_bytes
);
    localparam [3:0] IDLE = 0, VALIDATE = 1, ACTIVATION_START = 2,
        ACTIVATION_WAIT = 3, MATERIALIZE_GATE = 4, MULTIPLY = 5,
        MATERIALIZE_PRODUCT = 6, FP_START = 7, FP_WAIT = 8,
        PUBLISH = 9, RESPONSE = 10;
    reg [3:0] state, return_state;
    reg [1:0] op_hold, activation_op;
    reg [15:0] gate_hold, up_hold;
    reg [31:0] value_hold, fp_a, fp_b, output_hold;
    reg [2:0] fp_op;
    reg [3:0] error_hold;
    localparam integer CONTROLLER_BITS = $bits(state) + $bits(return_state) +
        $bits(op_hold) + $bits(activation_op) + $bits(gate_hold) + $bits(up_hold) +
        $bits(value_hold) + $bits(fp_a) + $bits(fp_b) + $bits(output_hold) +
        $bits(fp_op) + $bits(error_hold);
    wire [63:0] activation_controller_bytes, fp_controller_bytes;
    assign controller_bytes = !rst_n ? 64'd0 :
        64'((CONTROLLER_BITS+7) >> 3) + activation_controller_bytes + fp_controller_bytes;
    wire activation_ready, activation_valid, fp_ready, fp_valid;
    wire [31:0] activation_data, fp_data;
    wire [3:0] activation_error, fp_error;

    anvil_en1_activation activation_unit (
        .controller_bytes(activation_controller_bytes),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == ACTIVATION_START), .start_ready(activation_ready),
        .operation(activation_op), .operand({gate_hold, 16'd0}),
        .done_valid(activation_valid), .done_ready(rst_n && state == ACTIVATION_WAIT),
        .done_data(activation_data), .done_error(activation_error)
    );
    anvil_en1_fp32 fp_unit (
        .controller_bytes(fp_controller_bytes),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == FP_START), .start_ready(fp_ready),
        .operation(fp_op), .operand_a(fp_a), .operand_b(fp_b),
        .done_valid(fp_valid), .done_ready(rst_n && state == FP_WAIT),
        .done_data(fp_data), .done_error(fp_error)
    );
    assign start_ready = rst_n && state == IDLE;
    assign done_valid = rst_n && state == RESPONSE;
    assign done_data = rst_n ? output_hold : 32'd0;
    assign done_error = rst_n ? error_hold : 4'd0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            return_state <= 0;
            op_hold <= 0;
            activation_op <= 0;
            gate_hold <= 0;
            up_hold <= 0;
            value_hold <= 0;
            fp_a <= 0;
            fp_b <= 0;
            output_hold <= 0;
            fp_op <= 0;
            error_hold <= 0;
        end else begin
            case (state)
                IDLE: if (start_valid && start_ready) begin
                    op_hold <= operation;
                    gate_hold <= gate_data;
                    up_hold <= up_data;
                    output_hold <= 0;
                    error_hold <= 0;
                    case (operation)
                        0: activation_op <= 1;
                        1: activation_op <= 2;
                        2: activation_op <= 3;
                        default: activation_op <= 0;
                    endcase
                    state <= VALIDATE;
                end
                VALIDATE: begin
                    if (op_hold == 3) begin
                        error_hold <= 6;
                        state <= PUBLISH;
                    end else
                        state <= ACTIVATION_START;
                end
                ACTIVATION_START: if (activation_ready)
                    state <= ACTIVATION_WAIT;
                ACTIVATION_WAIT: if (activation_valid) begin
                    if (activation_error != 0) begin
                        error_hold <= activation_error;
                        state <= PUBLISH;
                    end else begin
                        value_hold <= activation_data;
                        state <= MATERIALIZE_GATE;
                    end
                end
                MATERIALIZE_GATE: begin
                    fp_op <= 3;
                    fp_a <= value_hold;
                    fp_b <= 0;
                    return_state <= MULTIPLY;
                    state <= FP_START;
                end
                MULTIPLY: begin
                    fp_op <= 1;
                    fp_a <= {value_hold[15:0], 16'd0};
                    fp_b <= {up_hold, 16'd0};
                    return_state <= MATERIALIZE_PRODUCT;
                    state <= FP_START;
                end
                MATERIALIZE_PRODUCT: begin
                    fp_op <= 3;
                    fp_a <= value_hold;
                    fp_b <= 0;
                    return_state <= PUBLISH;
                    state <= FP_START;
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
