module anvil_en1_projection (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] precision,
    input wire [63:0] tensor_base, tensor_bytes,
    input wire [31:0] tensor_rows, tensor_columns, row_stride, row_index,
    output wire source_valid,
    input wire source_ready,
    output wire [31:0] source_index,
    input wire source_rsp_valid,
    output wire source_rsp_ready,
    input wire [15:0] source_rsp_data,
    input wire source_rsp_error,
    output wire cmd_valid,
    input wire cmd_ready,
    output wire cmd_write,
    output wire [63:0] cmd_addr,
    output wire [31:0] cmd_wdata,
    input wire result_valid,
    output wire result_ready,
    input wire [31:0] result_data,
    input wire result_error,
    output wire done_valid,
    input wire done_ready,
    output wire [31:0] done_data,
    output wire [3:0] done_error,
    output wire [63:0] controller_bytes
);
    localparam [3:0] IDLE = 0, VALIDATE = 1, WEIGHT_START = 2,
        WEIGHT_WAIT = 3, SOURCE_START = 4, SOURCE_WAIT = 5,
        SOURCE_REGISTER = 6, FP_START = 7, FP_WAIT = 8,
        MULTIPLY = 9, ACCUMULATE = 10, ADVANCE = 11,
        MATERIALIZE = 12, PUBLISH = 13, RESPONSE = 14;
    reg [3:0] state, return_state;
    reg [1:0] precision_hold;
    reg [63:0] base_hold, bytes_hold;
    reg [31:0] rows_hold, columns_hold, stride_hold, row_hold, column;
    reg [31:0] weight_hold, accumulator, value_hold, output_hold, fp_a, fp_b;
    reg [15:0] source_hold;
    reg source_error_hold;
    reg [3:0] error_hold;
    reg [2:0] fp_op;
    localparam integer CONTROLLER_BITS = $bits(state) + $bits(return_state) +
        $bits(precision_hold) + $bits(base_hold) + $bits(bytes_hold) +
        $bits(rows_hold) + $bits(columns_hold) + $bits(stride_hold) +
        $bits(row_hold) + $bits(column) + $bits(weight_hold) +
        $bits(accumulator) + $bits(value_hold) + $bits(output_hold) +
        $bits(fp_a) + $bits(fp_b) + $bits(source_hold) +
        $bits(source_error_hold) + $bits(error_hold) + $bits(fp_op);
    wire [63:0] weight_controller_bytes, fp_controller_bytes;
    assign controller_bytes = !rst_n ? 64'd0 :
        64'((CONTROLLER_BITS+7) >> 3) + weight_controller_bytes + fp_controller_bytes;
    wire weight_ready, weight_valid, fp_ready, fp_valid;
    wire [31:0] weight_data, fp_data;
    wire [3:0] weight_error, fp_error;

    anvil_en1_weight_read weight_reader (
        .controller_bytes(weight_controller_bytes),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == WEIGHT_START), .start_ready(weight_ready),
        .precision(precision_hold), .tensor_base(base_hold), .tensor_bytes(bytes_hold),
        .tensor_rows(rows_hold), .tensor_columns(columns_hold), .row_stride(stride_hold),
        .row_index(row_hold), .column_index(column),
        .cmd_valid(cmd_valid), .cmd_ready(cmd_ready), .cmd_write(cmd_write),
        .cmd_addr(cmd_addr), .cmd_wdata(cmd_wdata),
        .result_valid(result_valid), .result_ready(result_ready),
        .result_data(result_data), .result_error(result_error),
        .done_valid(weight_valid), .done_ready(rst_n && state == WEIGHT_WAIT),
        .done_data(weight_data), .done_error(weight_error)
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
    assign source_valid = rst_n && state == SOURCE_START;
    assign source_index = rst_n ? column : 32'd0;
    assign source_rsp_ready = rst_n && state == SOURCE_WAIT;
    assign done_valid = rst_n && state == RESPONSE;
    assign done_data = rst_n ? output_hold : 32'd0;
    assign done_error = rst_n ? error_hold : 4'd0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            return_state <= 0;
            precision_hold <= 0;
            base_hold <= 0;
            bytes_hold <= 0;
            rows_hold <= 0;
            columns_hold <= 0;
            stride_hold <= 0;
            row_hold <= 0;
            column <= 0;
            weight_hold <= 0;
            accumulator <= 0;
            value_hold <= 0;
            output_hold <= 0;
            fp_a <= 0;
            fp_b <= 0;
            source_hold <= 0;
            source_error_hold <= 0;
            error_hold <= 0;
            fp_op <= 0;
        end else begin
            case (state)
                IDLE: if (start_valid && start_ready) begin
                    precision_hold <= precision;
                    base_hold <= tensor_base;
                    bytes_hold <= tensor_bytes;
                    rows_hold <= tensor_rows;
                    columns_hold <= tensor_columns;
                    stride_hold <= row_stride;
                    row_hold <= row_index;
                    column <= 0;
                    accumulator <= 0;
                    error_hold <= 0;
                    state <= VALIDATE;
                end
                VALIDATE: begin
                    if (precision_hold > 1) begin
                        output_hold <= 0;
                        error_hold <= 6;
                        state <= PUBLISH;
                    end else if (columns_hold == 0 || columns_hold > 1048576 ||
                        rows_hold == 0 || rows_hold > 1048576 || row_hold >= rows_hold) begin
                        output_hold <= 0;
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else
                        state <= WEIGHT_START;
                end
                WEIGHT_START: if (weight_ready)
                    state <= WEIGHT_WAIT;
                WEIGHT_WAIT: if (weight_valid) begin
                    if (weight_error != 0) begin
                        output_hold <= 0;
                        error_hold <= weight_error;
                        state <= PUBLISH;
                    end else begin
                        weight_hold <= weight_data;
                        state <= SOURCE_START;
                    end
                end
                SOURCE_START: if (source_ready)
                    state <= SOURCE_WAIT;
                SOURCE_WAIT: if (source_rsp_valid && source_rsp_ready) begin
                    source_hold <= source_rsp_data;
                    source_error_hold <= source_rsp_error;
                    state <= SOURCE_REGISTER;
                end
                SOURCE_REGISTER: begin
                    if (source_error_hold) begin
                        output_hold <= 0;
                        error_hold <= 7;
                        state <= PUBLISH;
                    end else begin
                        fp_op <= 2;
                        fp_a <= {16'd0, source_hold};
                        fp_b <= 0;
                        return_state <= MULTIPLY;
                        state <= FP_START;
                    end
                end
                MULTIPLY: begin
                    fp_op <= 1;
                    fp_a <= value_hold;
                    fp_b <= weight_hold;
                    return_state <= ACCUMULATE;
                    state <= FP_START;
                end
                ACCUMULATE: begin
                    fp_op <= 0;
                    fp_a <= accumulator;
                    fp_b <= value_hold;
                    return_state <= ADVANCE;
                    state <= FP_START;
                end
                ADVANCE: begin
                    accumulator <= value_hold;
                    if (column == columns_hold - 1'b1)
                        state <= MATERIALIZE;
                    else begin
                        column <= column + 1'b1;
                        state <= WEIGHT_START;
                    end
                end
                MATERIALIZE: begin
                    fp_op <= 3;
                    fp_a <= accumulator;
                    fp_b <= 0;
                    return_state <= PUBLISH;
                    state <= FP_START;
                end
                FP_START: if (fp_ready)
                    state <= FP_WAIT;
                FP_WAIT: if (fp_valid) begin
                    value_hold <= fp_data;
                    if (return_state == PUBLISH)
                        output_hold <= fp_data;
                    if (fp_error != 0) begin
                        output_hold <= 0;
                        error_hold <= fp_error;
                        state <= PUBLISH;
                    end else
                        state <= return_state;
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
