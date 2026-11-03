module anvil_en1_rope_frequency #(
    parameter integer EXTERNAL_FP = 0
) (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] mode,
    input wire [9:0] dimension,
    input wire [8:0] pair_index,
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
    localparam [3:0] IDLE = 0, VALIDATE = 1, ROOT_START = 2,
        ROOT_WAIT = 3, TEST_BIT = 4, PRODUCT_START = 5,
        PRODUCT_WAIT = 6, ADVANCE = 7, RECIPROCAL_START = 8,
        RECIPROCAL_WAIT = 9, PUBLISH = 10, RESPONSE = 11;
    reg [3:0] state;
    reg [1:0] mode_hold;
    reg [9:0] dimension_hold;
    reg [8:0] index_hold, bit_hold;
    reg [31:0] root_hold, product_hold, output_hold;
    reg [3:0] error_hold;
    wire [31:0] CONTROLLER_BITS = $bits(state) + $bits(mode_hold) +
        $bits(dimension_hold) + $bits(index_hold) + $bits(bit_hold) +
        $bits(root_hold) + $bits(product_hold) + $bits(output_hold) + $bits(error_hold);
    wire [63:0] div_controller_bytes, fp_controller_bytes;
    assign controller_bytes = !rst_n ? 64'd0 :
        64'((CONTROLLER_BITS+7) >> 3) + div_controller_bytes + fp_controller_bytes;
    wire root_ready, root_valid, product_ready, product_valid;
    wire [31:0] root_data, product_data;
    wire [3:0] root_error, product_error;
    wire valid_dimension = dimension_hold == 4 || dimension_hold == 8 ||
        dimension_hold == 16 || dimension_hold == 32 ||
        dimension_hold == 64 || dimension_hold == 128 ||
        dimension_hold == 256 || dimension_hold == 512;
    wire root_request = rst_n &&
        (state == ROOT_START || state == RECIPROCAL_START);

    anvil_en1_fp32_divsqrt root_divider (
        .controller_bytes(div_controller_bytes),
        .clk(clk), .rst_n(rst_n),
        .start_valid(root_request), .start_ready(root_ready),
        .operation(state == RECIPROCAL_START ? 2'd0 : 2'd1),
        .operand_a(state == RECIPROCAL_START ? 32'h3f800000 : root_hold),
        .operand_b(product_hold),
        .done_valid(root_valid),
        .done_ready(rst_n && (state == ROOT_WAIT || state == RECIPROCAL_WAIT)),
        .done_data(root_data), .done_error(root_error)
    );
    initial begin
        if (EXTERNAL_FP != 0 && EXTERNAL_FP != 1)
            $fatal(1, "PARAMETER ERROR: EXTERNAL_FP must be 0 or 1");
    end
    assign arithmetic_valid = rst_n && EXTERNAL_FP == 1 && state == PRODUCT_START;
    assign arithmetic_operation = rst_n && EXTERNAL_FP == 1 ? 3'd1 : 3'd0;
    assign arithmetic_a = rst_n && EXTERNAL_FP == 1 ? product_hold : 32'd0;
    assign arithmetic_b = rst_n && EXTERNAL_FP == 1 ? root_hold : 32'd0;
    assign arithmetic_result_ready = rst_n && EXTERNAL_FP == 1 && state == PRODUCT_WAIT;
    generate
        if (EXTERNAL_FP == 1) begin : external_arithmetic
            assign fp_controller_bytes = 64'd0;
            assign product_ready = rst_n && arithmetic_ready;
            assign product_valid = rst_n && arithmetic_result_valid;
            assign product_data = rst_n ? arithmetic_result_data : 32'd0;
            assign product_error = rst_n ? arithmetic_result_error : 4'd0;
        end else begin : internal_arithmetic
            anvil_en1_fp32 multiplier (
                .controller_bytes(fp_controller_bytes),
                .clk(clk), .rst_n(rst_n),
                .start_valid(rst_n && state == PRODUCT_START), .start_ready(product_ready),
                .operation(3'd1), .operand_a(product_hold), .operand_b(root_hold),
                .done_valid(product_valid), .done_ready(rst_n && state == PRODUCT_WAIT),
                .done_data(product_data), .done_error(product_error)
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
            mode_hold <= 0;
            dimension_hold <= 0;
            index_hold <= 0;
            bit_hold <= 0;
            root_hold <= 0;
            product_hold <= 0;
            output_hold <= 0;
            error_hold <= 0;
        end else begin
            case (state)
                IDLE: if (start_valid && start_ready) begin
                    mode_hold <= mode;
                    dimension_hold <= dimension;
                    index_hold <= pair_index;
                    bit_hold <= dimension[9:2];
                    product_hold <= 32'h3f800000;
                    output_hold <= 0;
                    error_hold <= 0;
                    case (mode)
                        0: root_hold <= 32'h461c4000;
                        1: root_hold <= 32'h49742400;
                        2: root_hold <= 32'h42c80000;
                        default: root_hold <= 0;
                    endcase
                    state <= VALIDATE;
                end
                VALIDATE: begin
                    if (mode_hold == 3) begin
                        error_hold <= 6;
                        state <= PUBLISH;
                    end else if (!valid_dimension ||
                        {1'b0, index_hold} >= (dimension_hold >> 1)) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else if (mode_hold == 1 &&
                        {1'b0, index_hold} >= (dimension_hold >> 3)) begin
                        output_hold <= 0;
                        state <= PUBLISH;
                    end else if (index_hold == 0) begin
                        output_hold <= 32'h3f800000;
                        state <= PUBLISH;
                    end else
                        state <= ROOT_START;
                end
                ROOT_START: if (root_ready)
                    state <= ROOT_WAIT;
                ROOT_WAIT: if (root_valid) begin
                    if (root_error != 0) begin
                        error_hold <= root_error;
                        state <= PUBLISH;
                    end else begin
                        root_hold <= root_data;
                        state <= TEST_BIT;
                    end
                end
                TEST_BIT: begin
                    if ((index_hold & bit_hold) != 0)
                        state <= PRODUCT_START;
                    else
                        state <= ADVANCE;
                end
                PRODUCT_START: if (product_ready)
                    state <= PRODUCT_WAIT;
                PRODUCT_WAIT: if (product_valid) begin
                    if (product_error != 0) begin
                        error_hold <= product_error;
                        state <= PUBLISH;
                    end else begin
                        product_hold <= product_data;
                        state <= ADVANCE;
                    end
                end
                ADVANCE: begin
                    if (bit_hold == 1)
                        state <= RECIPROCAL_START;
                    else begin
                        bit_hold <= bit_hold >> 1;
                        state <= ROOT_START;
                    end
                end
                RECIPROCAL_START: if (root_ready)
                    state <= RECIPROCAL_WAIT;
                RECIPROCAL_WAIT: if (root_valid) begin
                    if (root_error != 0)
                        error_hold <= root_error;
                    else
                        output_hold <= root_data;
                    state <= PUBLISH;
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
