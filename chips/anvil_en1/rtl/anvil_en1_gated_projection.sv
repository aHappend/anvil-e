module anvil_en1_gated_projection (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] precision, activation, up_mode,
    input wire [63:0] gate_base, gate_bytes, up_base, up_bytes, down_base, down_bytes,
    input wire [31:0] gate_rows, gate_columns, gate_stride,
    input wire [31:0] up_rows, up_columns, up_stride,
    input wire [31:0] down_rows, down_columns, down_stride, down_row,
    output wire source_valid,
    input wire source_ready,
    output wire [31:0] source_index,
    input wire source_rsp_valid,
    output wire source_rsp_ready,
    input wire [15:0] source_rsp_data,
    input wire source_rsp_error,
    output wire up_valid,
    input wire up_ready,
    output wire [31:0] up_index,
    input wire up_rsp_valid,
    output wire up_rsp_ready,
    input wire [15:0] up_rsp_data,
    input wire up_rsp_error,
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
    output wire [3:0] done_error
);
    localparam [4:0] IDLE = 0, VALIDATE = 1, GATE_SETUP = 2,
        PROJECTION_START = 3, PROJECTION_WAIT = 4, UP_SETUP = 5,
        UP_START = 6, UP_WAIT = 7, UP_REGISTER = 8,
        GATED_START = 9, GATED_WAIT = 10, DOWN_SETUP = 11,
        DOWN_START = 12, DOWN_WAIT = 13, MULTIPLY = 14,
        ACCUMULATE = 15, ADVANCE = 16, NARROW = 17,
        FP_START = 18, FP_WAIT = 19, PUBLISH = 20, RESPONSE = 21;
    reg [4:0] state, return_state;
    reg [1:0] precision_hold, activation_hold, up_mode_hold;
    reg [63:0] gate_base_hold, gate_bytes_hold, up_base_hold, up_bytes_hold;
    reg [63:0] down_base_hold, down_bytes_hold, projection_base, projection_bytes;
    reg [31:0] gate_rows_hold, gate_columns_hold, gate_stride_hold;
    reg [31:0] up_rows_hold, up_columns_hold, up_stride_hold;
    reg [31:0] down_rows_hold, down_columns_hold, down_stride_hold, down_row_hold;
    reg [31:0] projection_rows, projection_columns, projection_stride;
    reg [31:0] index, accumulator, value_hold, down_weight, output_hold, fp_a, fp_b;
    reg [15:0] gate_hold, up_hold, gated_hold;
    reg source_error_hold, projection_is_up, memory_down;
    reg [2:0] fp_op;
    reg [3:0] error_hold;
    wire projection_ready, projection_valid, gated_ready, gated_valid;
    wire down_ready, down_valid, fp_ready, fp_valid;
    wire [31:0] projection_data, gated_data, down_data, fp_data;
    wire [3:0] projection_error, gated_error, down_error, fp_error;
    wire projection_cmd_valid, projection_cmd_write, projection_result_ready;
    wire down_cmd_valid, down_cmd_write, down_result_ready;
    wire [63:0] projection_cmd_addr, down_cmd_addr;
    wire [31:0] projection_cmd_wdata, down_cmd_wdata;

    anvil_en1_projection projection_unit (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == PROJECTION_START), .start_ready(projection_ready),
        .precision(precision_hold),
        .tensor_base(projection_base), .tensor_bytes(projection_bytes),
        .tensor_rows(projection_rows), .tensor_columns(projection_columns),
        .row_stride(projection_stride), .row_index(index),
        .source_valid(source_valid), .source_ready(source_ready),
        .source_index(source_index),
        .source_rsp_valid(source_rsp_valid), .source_rsp_ready(source_rsp_ready),
        .source_rsp_data(source_rsp_data), .source_rsp_error(source_rsp_error),
        .cmd_valid(projection_cmd_valid),
        .cmd_ready(rst_n && !memory_down && cmd_ready),
        .cmd_write(projection_cmd_write), .cmd_addr(projection_cmd_addr),
        .cmd_wdata(projection_cmd_wdata),
        .result_valid(rst_n && !memory_down && result_valid),
        .result_ready(projection_result_ready),
        .result_data(result_data), .result_error(result_error),
        .done_valid(projection_valid), .done_ready(rst_n && state == PROJECTION_WAIT),
        .done_data(projection_data), .done_error(projection_error)
    );
    anvil_en1_geglu_pair gated_unit (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == GATED_START), .start_ready(gated_ready),
        .operation(activation_hold), .gate_data(gate_hold), .up_data(up_hold),
        .done_valid(gated_valid), .done_ready(rst_n && state == GATED_WAIT),
        .done_data(gated_data), .done_error(gated_error)
    );
    anvil_en1_weight_read down_reader (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == DOWN_START), .start_ready(down_ready),
        .precision(precision_hold),
        .tensor_base(down_base_hold), .tensor_bytes(down_bytes_hold),
        .tensor_rows(down_rows_hold), .tensor_columns(down_columns_hold),
        .row_stride(down_stride_hold), .row_index(down_row_hold), .column_index(index),
        .cmd_valid(down_cmd_valid), .cmd_ready(rst_n && memory_down && cmd_ready),
        .cmd_write(down_cmd_write), .cmd_addr(down_cmd_addr), .cmd_wdata(down_cmd_wdata),
        .result_valid(rst_n && memory_down && result_valid), .result_ready(down_result_ready),
        .result_data(result_data), .result_error(result_error),
        .done_valid(down_valid), .done_ready(rst_n && state == DOWN_WAIT),
        .done_data(down_data), .done_error(down_error)
    );
    anvil_en1_fp32 fp_unit (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == FP_START), .start_ready(fp_ready),
        .operation(fp_op), .operand_a(fp_a), .operand_b(fp_b),
        .done_valid(fp_valid), .done_ready(rst_n && state == FP_WAIT),
        .done_data(fp_data), .done_error(fp_error)
    );
    assign start_ready = rst_n && state == IDLE;
    assign up_valid = rst_n && state == UP_START;
    assign up_index = rst_n ? index : 32'd0;
    assign up_rsp_ready = rst_n && state == UP_WAIT;
    assign cmd_valid = rst_n && (memory_down ? down_cmd_valid : projection_cmd_valid);
    assign cmd_write = rst_n && (memory_down ? down_cmd_write : projection_cmd_write);
    assign cmd_addr = rst_n ? (memory_down ? down_cmd_addr : projection_cmd_addr) : 64'd0;
    assign cmd_wdata = rst_n ? (memory_down ? down_cmd_wdata : projection_cmd_wdata) : 32'd0;
    assign result_ready = rst_n &&
        (memory_down ? down_result_ready : projection_result_ready);
    assign done_valid = rst_n && state == RESPONSE;
    assign done_data = rst_n ? output_hold : 32'd0;
    assign done_error = rst_n ? error_hold : 4'd0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            return_state <= 0;
            precision_hold <= 0;
            activation_hold <= 0;
            up_mode_hold <= 0;
            gate_base_hold <= 0;
            gate_bytes_hold <= 0;
            up_base_hold <= 0;
            up_bytes_hold <= 0;
            down_base_hold <= 0;
            down_bytes_hold <= 0;
            projection_base <= 0;
            projection_bytes <= 0;
            gate_rows_hold <= 0;
            gate_columns_hold <= 0;
            gate_stride_hold <= 0;
            up_rows_hold <= 0;
            up_columns_hold <= 0;
            up_stride_hold <= 0;
            down_rows_hold <= 0;
            down_columns_hold <= 0;
            down_stride_hold <= 0;
            down_row_hold <= 0;
            projection_rows <= 0;
            projection_columns <= 0;
            projection_stride <= 0;
            index <= 0;
            accumulator <= 0;
            value_hold <= 0;
            down_weight <= 0;
            output_hold <= 0;
            fp_a <= 0;
            fp_b <= 0;
            gate_hold <= 0;
            up_hold <= 0;
            gated_hold <= 0;
            source_error_hold <= 0;
            projection_is_up <= 0;
            memory_down <= 0;
            fp_op <= 0;
            error_hold <= 0;
        end else begin
            case (state)
                IDLE: if (start_valid && start_ready) begin
                    precision_hold <= precision;
                    activation_hold <= activation;
                    up_mode_hold <= up_mode;
                    gate_base_hold <= gate_base;
                    gate_bytes_hold <= gate_bytes;
                    up_base_hold <= up_base;
                    up_bytes_hold <= up_bytes;
                    down_base_hold <= down_base;
                    down_bytes_hold <= down_bytes;
                    gate_rows_hold <= gate_rows;
                    gate_columns_hold <= gate_columns;
                    gate_stride_hold <= gate_stride;
                    up_rows_hold <= up_rows;
                    up_columns_hold <= up_columns;
                    up_stride_hold <= up_stride;
                    down_rows_hold <= down_rows;
                    down_columns_hold <= down_columns;
                    down_stride_hold <= down_stride;
                    down_row_hold <= down_row;
                    index <= 0;
                    accumulator <= 0;
                    output_hold <= 0;
                    error_hold <= 0;
                    state <= VALIDATE;
                end
                VALIDATE: begin
                    if (precision_hold > 1 || activation_hold == 3 || up_mode_hold == 3) begin
                        error_hold <= 6;
                        state <= PUBLISH;
                    end else if (gate_rows_hold == 0 || gate_rows_hold > 12288 ||
                        gate_columns_hold == 0 || gate_columns_hold > 2560 ||
                        down_columns_hold != gate_rows_hold ||
                        down_rows_hold == 0 || down_rows_hold > 2560 ||
                        down_row_hold >= down_rows_hold ||
                        (up_mode_hold == 0 && (up_rows_hold != gate_rows_hold ||
                        up_columns_hold != gate_columns_hold))) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else
                        state <= GATE_SETUP;
                end
                GATE_SETUP: begin
                    projection_base <= gate_base_hold;
                    projection_bytes <= gate_bytes_hold;
                    projection_rows <= gate_rows_hold;
                    projection_columns <= gate_columns_hold;
                    projection_stride <= gate_stride_hold;
                    projection_is_up <= 0;
                    memory_down <= 0;
                    state <= PROJECTION_START;
                end
                PROJECTION_START: if (projection_ready)
                    state <= PROJECTION_WAIT;
                PROJECTION_WAIT: if (projection_valid) begin
                    if (projection_error != 0) begin
                        error_hold <= projection_error;
                        state <= PUBLISH;
                    end else if (projection_is_up) begin
                        up_hold <= projection_data[15:0];
                        state <= GATED_START;
                    end else begin
                        gate_hold <= projection_data[15:0];
                        state <= UP_SETUP;
                    end
                end
                UP_SETUP: begin
                    if (up_mode_hold == 0) begin
                        projection_base <= up_base_hold;
                        projection_bytes <= up_bytes_hold;
                        projection_rows <= up_rows_hold;
                        projection_columns <= up_columns_hold;
                        projection_stride <= up_stride_hold;
                        projection_is_up <= 1;
                        state <= PROJECTION_START;
                    end else if (up_mode_hold == 1)
                        state <= UP_START;
                    else begin
                        up_hold <= 16'h3f80;
                        state <= GATED_START;
                    end
                end
                UP_START: if (up_ready)
                    state <= UP_WAIT;
                UP_WAIT: if (up_rsp_valid) begin
                    up_hold <= up_rsp_data;
                    source_error_hold <= up_rsp_error;
                    state <= UP_REGISTER;
                end
                UP_REGISTER: begin
                    if (source_error_hold) begin
                        error_hold <= 7;
                        state <= PUBLISH;
                    end else
                        state <= GATED_START;
                end
                GATED_START: if (gated_ready)
                    state <= GATED_WAIT;
                GATED_WAIT: if (gated_valid) begin
                    if (gated_error != 0) begin
                        error_hold <= gated_error;
                        state <= PUBLISH;
                    end else begin
                        gated_hold <= gated_data[15:0];
                        state <= DOWN_SETUP;
                    end
                end
                DOWN_SETUP: begin
                    memory_down <= 1;
                    state <= DOWN_START;
                end
                DOWN_START: if (down_ready)
                    state <= DOWN_WAIT;
                DOWN_WAIT: if (down_valid) begin
                    if (down_error != 0) begin
                        error_hold <= down_error;
                        state <= PUBLISH;
                    end else begin
                        down_weight <= down_data;
                        state <= MULTIPLY;
                    end
                end
                MULTIPLY: begin
                    fp_op <= 1;
                    fp_a <= {gated_hold, 16'd0};
                    fp_b <= down_weight;
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
                    if (index == gate_rows_hold - 1'b1)
                        state <= NARROW;
                    else begin
                        index <= index + 1'b1;
                        state <= GATE_SETUP;
                    end
                end
                NARROW: begin
                    fp_op <= 3;
                    fp_a <= accumulator;
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
