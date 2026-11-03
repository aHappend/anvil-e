module anvil_en1_weight_read #(
    parameter integer EXTERNAL_FP = 0
) (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] precision,
    input wire [63:0] tensor_base, tensor_bytes,
    input wire [31:0] tensor_rows, tensor_columns, row_stride,
    input wire [31:0] row_index, column_index,
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
    localparam [4:0] IDLE = 0, EXTENT_PRODUCTS = 1, EXTENT_REDUCE = 2,
        EXTENT_SUM = 3, VALIDATE = 4, ROW_ADDRESS = 5,
        ELEMENT_ADDRESS = 6, READ_START = 7, READ_WAIT = 8,
        READ_REGISTER = 9, DECODE = 10, FP_START = 11, FP_WAIT = 12,
        Q4_NIBBLE_ADDRESS = 13, Q4_MULTIPLY = 14,
        PUBLISH = 15, RESPONSE = 16;
    reg [4:0] state, return_state;
    reg [1:0] precision_hold;
    reg [63:0] base_hold, bytes_hold, row_base, address_hold;
    reg [31:0] rows_hold, columns_hold, stride_hold, row_hold, column_hold;
    reg [31:0] expected_stride, column_offset, nibble_offset;
    reg [31:0] rp00, rp01, rp10, rp11, ep00, ep01, ep10, ep11;
    reg [63:0] row_partial_a, row_partial_b, extent_partial_a, extent_partial_b;
    reg [63:0] row_offset, required_bytes;
    reg [31:0] word_hold, scale_hold, output_hold, fp_a, fp_b;
    reg [2:0] fp_op;
    reg [3:0] error_hold;
    reg memory_error_hold, reading_nibble;
    reg [1:0] lane_hold;
    localparam integer CONTROLLER_BITS = $bits(state) + $bits(return_state) +
        $bits(precision_hold) + $bits(base_hold) + $bits(bytes_hold) +
        $bits(row_base) + $bits(address_hold) + $bits(rows_hold) +
        $bits(columns_hold) + $bits(stride_hold) + $bits(row_hold) +
        $bits(column_hold) + $bits(expected_stride) + $bits(column_offset) +
        $bits(nibble_offset) + $bits(rp00) + $bits(rp01) + $bits(rp10) +
        $bits(rp11) + $bits(ep00) + $bits(ep01) + $bits(ep10) + $bits(ep11) +
        $bits(row_partial_a) + $bits(row_partial_b) + $bits(extent_partial_a) +
        $bits(extent_partial_b) + $bits(row_offset) + $bits(required_bytes) +
        $bits(word_hold) + $bits(scale_hold) + $bits(output_hold) +
        $bits(fp_a) + $bits(fp_b) + $bits(fp_op) + $bits(error_hold) +
        $bits(memory_error_hold) + $bits(reading_nibble) + $bits(lane_hold);
    wire [63:0] fp_controller_bytes;
    assign controller_bytes = !rst_n ? 64'd0 :
        64'((CONTROLLER_BITS+7) >> 3) + fp_controller_bytes;
    wire fp_ready, fp_valid;
    wire [31:0] fp_data;
    wire [3:0] fp_error;

    initial begin
        if (EXTERNAL_FP != 0 && EXTERNAL_FP != 1)
            $fatal(1, "PARAMETER ERROR: EXTERNAL_FP must be 0 or 1");
    end

    function automatic [31:0] nibble_float(input [3:0] nibble);
        begin
            case (nibble)
                0: nibble_float = 32'hc1000000;
                1: nibble_float = 32'hc0e00000;
                2: nibble_float = 32'hc0c00000;
                3: nibble_float = 32'hc0a00000;
                4: nibble_float = 32'hc0800000;
                5: nibble_float = 32'hc0400000;
                6: nibble_float = 32'hc0000000;
                7: nibble_float = 32'hbf800000;
                8: nibble_float = 0;
                9: nibble_float = 32'h3f800000;
                10: nibble_float = 32'h40000000;
                11: nibble_float = 32'h40400000;
                12: nibble_float = 32'h40800000;
                13: nibble_float = 32'h40a00000;
                14: nibble_float = 32'h40c00000;
                15: nibble_float = 32'h40e00000;
            endcase
        end
    endfunction

    wire [31:0] q4_blocks = (columns_hold + 31) >> 5;
    wire [31:0] q4_row_bytes = (q4_blocks << 4) + (q4_blocks << 1);
    wire [31:0] block_index = column_hold >> 5;
    wire [31:0] block_offset = (block_index << 4) + (block_index << 1);
    wire [31:0] stride_expected = precision_hold == 0 ?
        ((columns_hold + 1) >> 1) << 2 : (q4_row_bytes + 3) & 32'hfffffffc;
    wire [64:0] tensor_end = {1'b0, base_hold} + {1'b0, bytes_hold};
    wire [64:0] row_sum = {1'b0, base_hold} + {1'b0, row_offset};
    wire [64:0] element_sum = {1'b0, row_base} + {33'd0, column_offset};
    wire [64:0] nibble_sum = {1'b0, row_base} + {33'd0, nibble_offset};
    wire [15:0] half_word = lane_hold[1] ? word_hold[31:16] : word_hold[15:0];
    wire [7:0] nibble_byte = word_hold >> {lane_hold, 3'd0};
    wire [3:0] nibble = column_hold[4] ? nibble_byte[7:4] : nibble_byte[3:0];
    wire [31:0] nibble_value = nibble_float(nibble);

    wire fp_start_valid = rst_n && state == FP_START;
    wire fp_done_ready = rst_n && state == FP_WAIT;
    assign arithmetic_valid = EXTERNAL_FP == 1 && fp_start_valid;
    assign arithmetic_operation = rst_n && EXTERNAL_FP == 1 ? fp_op : 3'd0;
    assign arithmetic_a = rst_n && EXTERNAL_FP == 1 ? fp_a : 32'd0;
    assign arithmetic_b = rst_n && EXTERNAL_FP == 1 ? fp_b : 32'd0;
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
                .operation(fp_op), .operand_a(fp_a), .operand_b(fp_b),
                .done_valid(fp_valid), .done_ready(fp_done_ready),
                .done_data(fp_data), .done_error(fp_error)
            );
        end
    endgenerate

    assign start_ready = rst_n && state == IDLE;
    assign cmd_valid = rst_n && state == READ_START;
    assign cmd_write = 0;
    assign cmd_addr = rst_n ? address_hold : 64'd0;
    assign cmd_wdata = 0;
    assign result_ready = rst_n && state == READ_WAIT;
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
            row_base <= 0;
            address_hold <= 0;
            rows_hold <= 0;
            columns_hold <= 0;
            stride_hold <= 0;
            row_hold <= 0;
            column_hold <= 0;
            expected_stride <= 0;
            column_offset <= 0;
            nibble_offset <= 0;
            rp00 <= 0;
            rp01 <= 0;
            rp10 <= 0;
            rp11 <= 0;
            ep00 <= 0;
            ep01 <= 0;
            ep10 <= 0;
            ep11 <= 0;
            row_partial_a <= 0;
            row_partial_b <= 0;
            extent_partial_a <= 0;
            extent_partial_b <= 0;
            row_offset <= 0;
            required_bytes <= 0;
            word_hold <= 0;
            scale_hold <= 0;
            output_hold <= 0;
            fp_a <= 0;
            fp_b <= 0;
            fp_op <= 0;
            error_hold <= 0;
            memory_error_hold <= 0;
            reading_nibble <= 0;
            lane_hold <= 0;
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
                    column_hold <= column_index;
                    error_hold <= 0;
                    reading_nibble <= 0;
                    state <= EXTENT_PRODUCTS;
                end
                EXTENT_PRODUCTS: begin
                    rp00 <= row_hold[15:0] * stride_hold[15:0];
                    rp01 <= row_hold[15:0] * stride_hold[31:16];
                    rp10 <= row_hold[31:16] * stride_hold[15:0];
                    rp11 <= row_hold[31:16] * stride_hold[31:16];
                    ep00 <= rows_hold[15:0] * stride_hold[15:0];
                    ep01 <= rows_hold[15:0] * stride_hold[31:16];
                    ep10 <= rows_hold[31:16] * stride_hold[15:0];
                    ep11 <= rows_hold[31:16] * stride_hold[31:16];
                    expected_stride <= stride_expected;
                    column_offset <= precision_hold == 0 ?
                        ((column_hold >> 1) << 2) : block_offset;
                    nibble_offset <= block_offset + 2 + {28'd0, column_hold[3:0]};
                    state <= EXTENT_REDUCE;
                end
                EXTENT_REDUCE: begin
                    row_partial_a <= {32'd0, rp00} + {16'd0, rp01, 16'd0};
                    row_partial_b <= {16'd0, rp10, 16'd0} + {rp11, 32'd0};
                    extent_partial_a <= {32'd0, ep00} + {16'd0, ep01, 16'd0};
                    extent_partial_b <= {16'd0, ep10, 16'd0} + {ep11, 32'd0};
                    state <= EXTENT_SUM;
                end
                EXTENT_SUM: begin
                    row_offset <= row_partial_a + row_partial_b;
                    required_bytes <= extent_partial_a + extent_partial_b;
                    state <= VALIDATE;
                end
                VALIDATE: begin
                    if (precision_hold > 1) begin
                        error_hold <= 6;
                        output_hold <= 0;
                        state <= PUBLISH;
                    end else if (rows_hold == 0 || rows_hold > 1048576 ||
                        columns_hold == 0 || columns_hold > 1048576 ||
                        row_hold >= rows_hold || column_hold >= columns_hold ||
                        base_hold[1:0] != 0 || stride_hold != expected_stride ||
                        bytes_hold != required_bytes || tensor_end[64]) begin
                        error_hold <= 5;
                        output_hold <= 0;
                        state <= PUBLISH;
                    end else
                        state <= ROW_ADDRESS;
                end
                ROW_ADDRESS: begin
                    if (row_sum[64]) begin
                        error_hold <= 5;
                        output_hold <= 0;
                        state <= PUBLISH;
                    end else begin
                        row_base <= row_sum[63:0];
                        state <= ELEMENT_ADDRESS;
                    end
                end
                ELEMENT_ADDRESS: begin
                    if (element_sum[64]) begin
                        error_hold <= 5;
                        output_hold <= 0;
                        state <= PUBLISH;
                    end else begin
                        address_hold <= {element_sum[63:2], 2'd0};
                        lane_hold <= precision_hold == 0 ?
                            {column_hold[0], 1'b0} : element_sum[1:0];
                        state <= READ_START;
                    end
                end
                READ_START: if (cmd_ready)
                    state <= READ_WAIT;
                READ_WAIT: if (result_valid && result_ready) begin
                    word_hold <= result_data;
                    memory_error_hold <= result_error;
                    state <= READ_REGISTER;
                end
                READ_REGISTER: begin
                    if (memory_error_hold) begin
                        output_hold <= 0;
                        error_hold <= 2;
                        state <= PUBLISH;
                    end else
                        state <= DECODE;
                end
                DECODE: begin
                    if (reading_nibble)
                        state <= Q4_MULTIPLY;
                    else begin
                        fp_op <= precision_hold == 0 ? 3'd2 : 3'd4;
                        fp_a <= {16'd0, half_word};
                        fp_b <= 0;
                        return_state <= precision_hold == 0 ? PUBLISH : Q4_NIBBLE_ADDRESS;
                        state <= FP_START;
                    end
                end
                Q4_NIBBLE_ADDRESS: begin
                    if (nibble_sum[64]) begin
                        output_hold <= 0;
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else begin
                        scale_hold <= output_hold;
                        address_hold <= {nibble_sum[63:2], 2'd0};
                        lane_hold <= nibble_sum[1:0];
                        reading_nibble <= 1;
                        state <= READ_START;
                    end
                end
                Q4_MULTIPLY: begin
                    fp_op <= 1;
                    fp_a <= scale_hold;
                    fp_b <= nibble_value;
                    return_state <= PUBLISH;
                    state <= FP_START;
                end
                FP_START: if (fp_ready)
                    state <= FP_WAIT;
                FP_WAIT: if (fp_valid) begin
                    output_hold <= fp_data;
                    if (fp_error != 0) begin
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
