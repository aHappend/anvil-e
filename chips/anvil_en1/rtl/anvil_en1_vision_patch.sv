module anvil_en1_vision_patch (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] model, precision,
    input wire [63:0] image_base, vision_weights_base,
    input wire [31:0] patch_count, patch_rows, patch_columns, patch_index,
    output wire cmd_valid,
    input wire cmd_ready,
    output wire cmd_write,
    output wire [63:0] cmd_addr,
    output wire [31:0] cmd_wdata,
    input wire result_valid,
    output wire result_ready,
    input wire [31:0] result_data,
    input wire result_error,
    output wire output_valid,
    input wire output_ready,
    output wire [31:0] output_index,
    output wire [15:0] output_data,
    output wire output_last,
    output wire [31:0] patch_x, patch_y,
    output wire patch_padding,
    output wire done_valid,
    input wire done_ready,
    output wire [3:0] done_error,
    output wire [63:0] controller_bytes
);
    localparam [5:0] IDLE = 0, VALIDATE = 1, EXTENT_PRODUCT = 2,
        EXTENT_VALIDATE = 3, IMAGE_START = 4, IMAGE_WAIT = 5,
        INPUT_OFFSETS = 6, INPUT_ADDRESS = 7, COORD_X_SEND = 8,
        COORD_X_WAIT = 9, COORD_X_REGISTER = 10, COORD_Y_ADDRESS = 11,
        COORD_Y_SEND = 12, COORD_Y_WAIT = 13, COORD_Y_REGISTER = 14,
        COORD_VALIDATE = 15, PROJECTION_START = 16, PROJECTION_WAIT = 17,
        POSITION_X_START = 18, POSITION_X_WAIT = 19,
        POSITION_Y_START = 20, POSITION_Y_WAIT = 21,
        POSITION_ADD = 22, FP_START = 23, FP_WAIT = 24,
        POSITION_NARROW = 25, FINAL_ADD = 26, FINAL_NARROW = 27,
        EMIT = 28, ADVANCE = 29, PUBLISH = 30, RESPONSE = 31;
    localparam [4:0] S_IDLE = 0, S_ADDRESS = 1, S_READ_SEND = 2,
        S_READ_WAIT = 3, S_REGISTER = 4,
        S_WIDEN_START = 5, S_WIDEN_WAIT = 6,
        S_SUBTRACT_START = 7, S_SUBTRACT_WAIT = 8,
        S_MULTIPLY_START = 9, S_MULTIPLY_WAIT = 10,
        S_NARROW_START = 11, S_NARROW_WAIT = 12, S_RESPONSE = 13,
        S_SUB_NARROW_START = 14, S_SUB_NARROW_WAIT = 15,
        S_SUB_WIDEN_START = 16, S_SUB_WIDEN_WAIT = 17;
    reg [5:0] state, fp_return;
    reg [4:0] source_state;
    reg [1:0] model_hold, precision_hold, image_index;
    reg [63:0] image_base_hold, weights_base_hold;
    reg [31:0] count_hold, rows_hold, columns_hold, patch_hold, patch_product;
    reg [63:0] pixels_base, pixels_bytes, coords_base, coords_bytes;
    reg [63:0] matrix_base, matrix_bytes, positions_base, positions_bytes;
    reg [31:0] matrix_rows, matrix_columns, matrix_stride;
    reg [31:0] positions_rows, positions_columns, positions_stride;
    reg [63:0] pixel_row_offset, coord_row_offset, pixel_row_base, coord_address;
    reg [31:0] x_hold, y_hold, coord_word, row;
    reg padding_hold, coord_error_hold;
    reg [31:0] position_x_value, position_y_value, fp_a, fp_b, fp_value;
    reg [2:0] fp_op;
    reg [15:0] projected_hold, output_hold;
    reg [3:0] error_hold;
    reg [31:0] source_index_hold, source_word, source_fp_value;
    reg [63:0] source_address;
    reg source_lane, source_memory_error, source_error_hold;
    reg [3:0] source_failure_hold;
    reg [15:0] source_data_hold, source_output_hold;

    wire image_ready, image_valid, image_cmd_valid, image_result_ready;
    wire [63:0] image_cmd_addr, image_done_base, image_done_bytes;
    wire [31:0] image_done_rows, image_done_columns, image_done_stride;
    wire [7:0] image_done_type;
    wire [3:0] image_error;
    wire image_selected = rst_n && (state == IMAGE_START || state == IMAGE_WAIT);
    wire input_image = image_index < 2;
    wire [15:0] image_kind = image_index == 0 ? 16'h3000 :
        (image_index == 1 ? 16'h3001 : (image_index == 2 ? 16'h1000 : 16'h1001));
    anvil_en1_tensor_image directory (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == IMAGE_START), .start_ready(image_ready),
        .model(model_hold), .precision(input_image ? 2'd0 : precision_hold),
        .image_class(input_image ? 2'd3 : 2'd1),
        .input_audio(1'b0), .input_items(count_hold),
        .image_base(input_image ? image_base_hold : weights_base_hold),
        .tensor_kind(image_kind), .tensor_layer(16'hffff),
        .cmd_valid(image_cmd_valid), .cmd_ready(image_selected && cmd_ready),
        .cmd_write(), .cmd_addr(image_cmd_addr), .cmd_wdata(),
        .result_valid(image_selected && result_valid), .result_ready(image_result_ready),
        .result_data(result_data), .result_error(result_error),
        .done_valid(image_valid), .done_ready(rst_n && state == IMAGE_WAIT),
        .done_base(image_done_base), .done_bytes(image_done_bytes),
        .done_rows(image_done_rows), .done_columns(image_done_columns),
        .done_stride(image_done_stride), .done_type(image_done_type),
        .done_error(image_error)
    );

    wire projection_ready, projection_valid, projection_cmd_valid;
    wire projection_result_ready, projection_source_valid, projection_source_rsp_ready;
    wire [31:0] projection_source_index, projection_data;
    wire [63:0] projection_cmd_addr;
    wire [3:0] projection_error;
    wire pixel_selected = rst_n && state == PROJECTION_WAIT && source_state != S_IDLE;
    wire projection_selected = rst_n && !pixel_selected &&
        (state == PROJECTION_START || state == PROJECTION_WAIT);
    anvil_en1_projection projection (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == PROJECTION_START), .start_ready(projection_ready),
        .precision(precision_hold), .tensor_base(matrix_base), .tensor_bytes(matrix_bytes),
        .tensor_rows(matrix_rows), .tensor_columns(matrix_columns),
        .row_stride(matrix_stride), .row_index(row),
        .source_valid(projection_source_valid),
        .source_ready(rst_n && state == PROJECTION_WAIT && source_state == S_IDLE),
        .source_index(projection_source_index),
        .source_rsp_valid(rst_n && state == PROJECTION_WAIT && source_state == S_RESPONSE),
        .source_rsp_ready(projection_source_rsp_ready),
        .source_rsp_data(source_output_hold), .source_rsp_error(source_error_hold),
        .cmd_valid(projection_cmd_valid), .cmd_ready(projection_selected && cmd_ready),
        .cmd_write(), .cmd_addr(projection_cmd_addr), .cmd_wdata(),
        .result_valid(projection_selected && result_valid),
        .result_ready(projection_result_ready), .result_data(result_data),
        .result_error(result_error),
        .done_valid(projection_valid),
        .done_ready(rst_n && state == PROJECTION_WAIT && source_state == S_IDLE),
        .done_data(projection_data), .done_error(projection_error)
    );

    wire position_ready, position_valid, position_cmd_valid, position_result_ready;
    wire [63:0] position_cmd_addr;
    wire [31:0] position_data;
    wire [3:0] position_error;
    wire position_y_selected = state == POSITION_Y_START || state == POSITION_Y_WAIT;
    wire position_selected = rst_n && (position_y_selected ||
        state == POSITION_X_START || state == POSITION_X_WAIT);
    wire [31:0] position_row = position_y_selected ? y_hold + 32'd10240 : x_hold;
    anvil_en1_weight_read positions (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && (state == POSITION_X_START || state == POSITION_Y_START)),
        .start_ready(position_ready), .precision(2'd0),
        .tensor_base(positions_base), .tensor_bytes(positions_bytes),
        .tensor_rows(positions_rows), .tensor_columns(positions_columns),
        .row_stride(positions_stride), .row_index(position_row), .column_index(row),
        .cmd_valid(position_cmd_valid), .cmd_ready(position_selected && cmd_ready),
        .cmd_write(), .cmd_addr(position_cmd_addr), .cmd_wdata(),
        .result_valid(position_selected && result_valid),
        .result_ready(position_result_ready), .result_data(result_data),
        .result_error(result_error),
        .done_valid(position_valid),
        .done_ready(rst_n && (state == POSITION_X_WAIT || state == POSITION_Y_WAIT)),
        .done_data(position_data), .done_error(position_error)
    );

    wire fp_ready, fp_valid;
    wire [31:0] fp_data;
    wire [3:0] fp_error;
    wire source_fp_start = state == PROJECTION_WAIT &&
        (source_state == S_WIDEN_START || source_state == S_SUBTRACT_START ||
        source_state == S_MULTIPLY_START || source_state == S_NARROW_START ||
        source_state == S_SUB_NARROW_START || source_state == S_SUB_WIDEN_START);
    wire source_fp_wait = state == PROJECTION_WAIT &&
        (source_state == S_WIDEN_WAIT || source_state == S_SUBTRACT_WAIT ||
        source_state == S_MULTIPLY_WAIT || source_state == S_NARROW_WAIT ||
        source_state == S_SUB_NARROW_WAIT || source_state == S_SUB_WIDEN_WAIT);
    wire source_widen = source_state == S_WIDEN_START || source_state == S_WIDEN_WAIT ||
        source_state == S_SUB_WIDEN_START || source_state == S_SUB_WIDEN_WAIT;
    wire source_subtract = source_state == S_SUBTRACT_START || source_state == S_SUBTRACT_WAIT;
    wire source_multiply = source_state == S_MULTIPLY_START || source_state == S_MULTIPLY_WAIT;
    wire [2:0] source_fp_op = source_widen ? 3'd2 :
        (source_subtract ? 3'd0 : (source_multiply ? 3'd1 : 3'd3));
    wire [31:0] source_fp_a = source_widen ? {16'd0, source_data_hold} : source_fp_value;
    wire [31:0] source_fp_b = source_subtract ? 32'hbf000000 :
        (source_multiply ? 32'h40000000 : 32'd0);
    anvil_en1_fp32 arithmetic (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && (state == FP_START || source_fp_start)),
        .start_ready(fp_ready),
        .operation(source_fp_start || source_fp_wait ? source_fp_op : fp_op),
        .operand_a(source_fp_start || source_fp_wait ? source_fp_a : fp_a),
        .operand_b(source_fp_start || source_fp_wait ? source_fp_b : fp_b),
        .done_valid(fp_valid),
        .done_ready(rst_n && (state == FP_WAIT || source_fp_wait)),
        .done_data(fp_data), .done_error(fp_error)
    );

    wire [63:0] pixel_offset = ({32'd0, patch_hold} << 10) +
        ({32'd0, patch_hold} << 9);
    wire [64:0] pixel_row_sum = {1'b0, pixels_base} + {1'b0, pixel_row_offset};
    wire [64:0] pixel_row_end = pixel_row_sum + 65'd1536;
    wire [64:0] pixels_end = {1'b0, pixels_base} + {1'b0, pixels_bytes};
    wire [64:0] coord_row_sum = {1'b0, coords_base} + {1'b0, coord_row_offset};
    wire [64:0] coord_row_end = coord_row_sum + 65'd8;
    wire [64:0] coords_end = {1'b0, coords_base} + {1'b0, coords_bytes};
    wire [64:0] coord_y_sum = {1'b0, coord_address} + 65'd4;
    wire [64:0] source_sum = {1'b0, pixel_row_base} + {32'd0, source_index_hold, 1'b0};
    wire [64:0] source_aligned = source_sum & 65'h1fffffffffffffffc;
    wire [64:0] source_end = source_aligned + 65'd4;
    wire both_padding = x_hold == 32'hffffffff && y_hold == 32'hffffffff;
    wire coords_valid = !x_hold[31] && !y_hold[31] &&
        x_hold < columns_hold && y_hold < rows_hold;

    assign start_ready = rst_n && state == IDLE;
    assign cmd_valid = rst_n && (image_selected ? image_cmd_valid :
        (pixel_selected ? source_state == S_READ_SEND :
        (projection_selected ? projection_cmd_valid :
        (position_selected ? position_cmd_valid :
        (state == COORD_X_SEND || state == COORD_Y_SEND)))));
    assign cmd_write = 0;
    assign cmd_addr = !rst_n ? 64'd0 : (image_selected ? image_cmd_addr :
        (pixel_selected ? source_address : (projection_selected ? projection_cmd_addr :
        (position_selected ? position_cmd_addr : coord_address))));
    assign cmd_wdata = 0;
    assign result_ready = rst_n && (image_selected ? image_result_ready :
        (pixel_selected ? source_state == S_READ_WAIT :
        (projection_selected ? projection_result_ready :
        (position_selected ? position_result_ready :
        (state == COORD_X_WAIT || state == COORD_Y_WAIT)))));
    assign output_valid = rst_n && state == EMIT;
    assign output_index = rst_n ? row : 32'd0;
    assign output_data = rst_n ? output_hold : 16'd0;
    assign output_last = rst_n && row == 767;
    assign patch_x = rst_n ? x_hold : 32'd0;
    assign patch_y = rst_n ? y_hold : 32'd0;
    assign patch_padding = rst_n && padding_hold;
    assign done_valid = rst_n && state == RESPONSE;
    assign done_error = rst_n ? error_hold : 4'd0;
    localparam integer CONTROLLER_BITS =
        $bits(state) + $bits(fp_return) + $bits(source_state) +
        $bits(model_hold) + $bits(precision_hold) + $bits(image_index) +
        $bits(image_base_hold) + $bits(weights_base_hold) +
        $bits(count_hold) + $bits(rows_hold) + $bits(columns_hold) +
        $bits(patch_hold) + $bits(patch_product) +
        $bits(pixels_base) + $bits(pixels_bytes) + $bits(coords_base) + $bits(coords_bytes) +
        $bits(matrix_base) + $bits(matrix_bytes) + $bits(positions_base) + $bits(positions_bytes) +
        $bits(matrix_rows) + $bits(matrix_columns) + $bits(matrix_stride) +
        $bits(positions_rows) + $bits(positions_columns) + $bits(positions_stride) +
        $bits(pixel_row_offset) + $bits(coord_row_offset) + $bits(pixel_row_base) +
        $bits(coord_address) + $bits(x_hold) + $bits(y_hold) + $bits(coord_word) + $bits(row) +
        $bits(padding_hold) + $bits(coord_error_hold) + $bits(position_x_value) +
        $bits(position_y_value) + $bits(fp_a) + $bits(fp_b) + $bits(fp_value) +
        $bits(fp_op) + $bits(projected_hold) + $bits(output_hold) + $bits(error_hold) +
        $bits(source_index_hold) + $bits(source_word) + $bits(source_fp_value) +
        $bits(source_address) + $bits(source_lane) + $bits(source_memory_error) +
        $bits(source_error_hold) + $bits(source_failure_hold) +
        $bits(source_data_hold) + $bits(source_output_hold);
    assign controller_bytes = rst_n ? (CONTROLLER_BITS + 7) >> 3 : 64'd0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            source_state <= S_IDLE;
            source_index_hold <= 0;
            source_word <= 0;
            source_fp_value <= 0;
            source_address <= 0;
            source_lane <= 0;
            source_memory_error <= 0;
            source_error_hold <= 0;
            source_failure_hold <= 0;
            source_data_hold <= 0;
            source_output_hold <= 0;
        end else begin
            if (state == PROJECTION_START && projection_ready)
                source_failure_hold <= 0;
            case (source_state)
                S_IDLE: if (state == PROJECTION_WAIT && projection_source_valid) begin
                    source_index_hold <= projection_source_index;
                    source_error_hold <= 0;
                    source_failure_hold <= 0;
                    source_output_hold <= 0;
                    source_state <= S_ADDRESS;
                end
                S_ADDRESS: begin
                    if (source_index_hold >= 768 || source_sum[64] ||
                        source_end[64] || source_end > pixels_end ||
                        source_end > {1'b0, pixel_row_base} + 65'd1536) begin
                        source_error_hold <= 1;
                        source_failure_hold <= 5;
                        source_state <= S_RESPONSE;
                    end else begin
                        source_address <= source_aligned[63:0];
                        source_lane <= source_sum[1];
                        source_state <= S_READ_SEND;
                    end
                end
                S_READ_SEND: if (cmd_valid && cmd_ready)
                    source_state <= S_READ_WAIT;
                S_READ_WAIT: if (result_valid && result_ready) begin
                    source_word <= result_data;
                    source_memory_error <= result_error;
                    source_state <= S_REGISTER;
                end
                S_REGISTER: begin
                    if (source_memory_error) begin
                        source_error_hold <= 1;
                        source_failure_hold <= 2;
                        source_state <= S_RESPONSE;
                    end else begin
                        source_data_hold <= source_lane ? source_word[31:16] : source_word[15:0];
                        source_state <= S_WIDEN_START;
                    end
                end
                S_WIDEN_START: if (fp_ready)
                    source_state <= S_WIDEN_WAIT;
                S_WIDEN_WAIT: if (fp_valid) begin
                    source_fp_value <= fp_data;
                    if (fp_error != 0) begin
                        source_error_hold <= 1;
                        source_failure_hold <= fp_error;
                        source_state <= S_RESPONSE;
                    end else
                        source_state <= S_SUBTRACT_START;
                end
                S_SUBTRACT_START: if (fp_ready)
                    source_state <= S_SUBTRACT_WAIT;
                S_SUBTRACT_WAIT: if (fp_valid) begin
                    source_fp_value <= fp_data;
                    if (fp_error != 0) begin
                        source_error_hold <= 1;
                        source_failure_hold <= fp_error;
                        source_state <= S_RESPONSE;
                    end else
                        source_state <= S_SUB_NARROW_START;
                end
                S_SUB_NARROW_START: if (fp_ready)
                    source_state <= S_SUB_NARROW_WAIT;
                S_SUB_NARROW_WAIT: if (fp_valid) begin
                    source_data_hold <= fp_data[15:0];
                    if (fp_error != 0) begin
                        source_error_hold <= 1;
                        source_failure_hold <= fp_error;
                        source_state <= S_RESPONSE;
                    end else
                        source_state <= S_SUB_WIDEN_START;
                end
                S_SUB_WIDEN_START: if (fp_ready)
                    source_state <= S_SUB_WIDEN_WAIT;
                S_SUB_WIDEN_WAIT: if (fp_valid) begin
                    source_fp_value <= fp_data;
                    if (fp_error != 0) begin
                        source_error_hold <= 1;
                        source_failure_hold <= fp_error;
                        source_state <= S_RESPONSE;
                    end else
                        source_state <= S_MULTIPLY_START;
                end
                S_MULTIPLY_START: if (fp_ready)
                    source_state <= S_MULTIPLY_WAIT;
                S_MULTIPLY_WAIT: if (fp_valid) begin
                    source_fp_value <= fp_data;
                    if (fp_error != 0) begin
                        source_error_hold <= 1;
                        source_failure_hold <= fp_error;
                        source_state <= S_RESPONSE;
                    end else
                        source_state <= S_NARROW_START;
                end
                S_NARROW_START: if (fp_ready)
                    source_state <= S_NARROW_WAIT;
                S_NARROW_WAIT: if (fp_valid) begin
                    source_output_hold <= fp_data[15:0];
                    source_error_hold <= fp_error != 0;
                    source_failure_hold <= fp_error;
                    source_state <= S_RESPONSE;
                end
                S_RESPONSE: if (state == PROJECTION_WAIT && projection_source_rsp_ready)
                    source_state <= S_IDLE;
                default: begin
                    source_output_hold <= 0;
                    source_error_hold <= 1;
                    source_failure_hold <= 7;
                    source_state <= S_RESPONSE;
                end
            endcase
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            fp_return <= 0;
            model_hold <= 0;
            precision_hold <= 0;
            image_index <= 0;
            image_base_hold <= 0;
            weights_base_hold <= 0;
            count_hold <= 0;
            rows_hold <= 0;
            columns_hold <= 0;
            patch_hold <= 0;
            patch_product <= 0;
            pixels_base <= 0;
            pixels_bytes <= 0;
            coords_base <= 0;
            coords_bytes <= 0;
            matrix_base <= 0;
            matrix_bytes <= 0;
            positions_base <= 0;
            positions_bytes <= 0;
            matrix_rows <= 0;
            matrix_columns <= 0;
            matrix_stride <= 0;
            positions_rows <= 0;
            positions_columns <= 0;
            positions_stride <= 0;
            pixel_row_offset <= 0;
            coord_row_offset <= 0;
            pixel_row_base <= 0;
            coord_address <= 0;
            x_hold <= 0;
            y_hold <= 0;
            coord_word <= 0;
            row <= 0;
            padding_hold <= 0;
            coord_error_hold <= 0;
            position_x_value <= 0;
            position_y_value <= 0;
            fp_a <= 0;
            fp_b <= 0;
            fp_value <= 0;
            fp_op <= 0;
            projected_hold <= 0;
            output_hold <= 0;
            error_hold <= 0;
        end else begin
            case (state)
                IDLE: if (start_valid && start_ready) begin
                    model_hold <= model;
                    precision_hold <= precision;
                    image_base_hold <= image_base;
                    weights_base_hold <= vision_weights_base;
                    count_hold <= patch_count;
                    rows_hold <= patch_rows;
                    columns_hold <= patch_columns;
                    patch_hold <= patch_index;
                    image_index <= 0;
                    row <= 0;
                    padding_hold <= 0;
                    output_hold <= 0;
                    error_hold <= 0;
                    state <= VALIDATE;
                end
                VALIDATE: begin
                    if ((model_hold != 1 && model_hold != 2) || precision_hold > 1) begin
                        error_hold <= 6;
                        state <= PUBLISH;
                    end else if (count_hold == 0 || count_hold > 131072 ||
                        rows_hold == 0 || rows_hold > 10240 ||
                        columns_hold == 0 || columns_hold > 10240 ||
                        patch_hold >= count_hold) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else
                        state <= EXTENT_PRODUCT;
                end
                EXTENT_PRODUCT: begin
                    patch_product <= rows_hold[15:0] * columns_hold[15:0];
                    state <= EXTENT_VALIDATE;
                end
                EXTENT_VALIDATE: begin
                    if (patch_product != count_hold) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else
                        state <= IMAGE_START;
                end
                IMAGE_START: if (image_ready)
                    state <= IMAGE_WAIT;
                IMAGE_WAIT: if (image_valid) begin
                    if (image_error != 0) begin
                        error_hold <= image_error;
                        state <= PUBLISH;
                    end else if (image_index == 0) begin
                        pixels_base <= image_done_base;
                        pixels_bytes <= image_done_bytes;
                        image_index <= 1;
                        state <= IMAGE_START;
                    end else if (image_index == 1) begin
                        coords_base <= image_done_base;
                        coords_bytes <= image_done_bytes;
                        image_index <= 2;
                        state <= IMAGE_START;
                    end else if (image_index == 2) begin
                        matrix_base <= image_done_base;
                        matrix_bytes <= image_done_bytes;
                        matrix_rows <= image_done_rows;
                        matrix_columns <= image_done_columns;
                        matrix_stride <= image_done_stride;
                        image_index <= 3;
                        state <= IMAGE_START;
                    end else begin
                        positions_base <= image_done_base;
                        positions_bytes <= image_done_bytes;
                        positions_rows <= image_done_rows;
                        positions_columns <= image_done_columns;
                        positions_stride <= image_done_stride;
                        state <= INPUT_OFFSETS;
                    end
                end
                INPUT_OFFSETS: begin
                    pixel_row_offset <= pixel_offset;
                    coord_row_offset <= {32'd0, patch_hold} << 3;
                    state <= INPUT_ADDRESS;
                end
                INPUT_ADDRESS: begin
                    if (pixel_row_sum[64] || pixel_row_end[64] || pixels_end[64] ||
                        pixel_row_end > pixels_end || coord_row_sum[64] ||
                        coord_row_end[64] || coords_end[64] || coord_row_end > coords_end ||
                        pixel_row_sum[1:0] != 0 || coord_row_sum[1:0] != 0) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else begin
                        pixel_row_base <= pixel_row_sum[63:0];
                        coord_address <= coord_row_sum[63:0];
                        state <= COORD_X_SEND;
                    end
                end
                COORD_X_SEND: if (cmd_valid && cmd_ready)
                    state <= COORD_X_WAIT;
                COORD_X_WAIT: if (result_valid && result_ready) begin
                    coord_word <= result_data;
                    coord_error_hold <= result_error;
                    state <= COORD_X_REGISTER;
                end
                COORD_X_REGISTER: begin
                    if (coord_error_hold) begin
                        error_hold <= 2;
                        state <= PUBLISH;
                    end else begin
                        x_hold <= coord_word;
                        state <= COORD_Y_ADDRESS;
                    end
                end
                COORD_Y_ADDRESS: begin
                    if (coord_y_sum[64]) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else begin
                        coord_address <= coord_y_sum[63:0];
                        state <= COORD_Y_SEND;
                    end
                end
                COORD_Y_SEND: if (cmd_valid && cmd_ready)
                    state <= COORD_Y_WAIT;
                COORD_Y_WAIT: if (result_valid && result_ready) begin
                    coord_word <= result_data;
                    coord_error_hold <= result_error;
                    state <= COORD_Y_REGISTER;
                end
                COORD_Y_REGISTER: begin
                    if (coord_error_hold) begin
                        error_hold <= 2;
                        state <= PUBLISH;
                    end else begin
                        y_hold <= coord_word;
                        state <= COORD_VALIDATE;
                    end
                end
                COORD_VALIDATE: begin
                    if (!both_padding && !coords_valid) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else begin
                        padding_hold <= both_padding;
                        state <= PROJECTION_START;
                    end
                end
                PROJECTION_START: if (projection_ready)
                    state <= PROJECTION_WAIT;
                PROJECTION_WAIT: if (projection_valid && source_state == S_IDLE) begin
                    if (projection_error != 0) begin
                        error_hold <= source_failure_hold != 0 ?
                            source_failure_hold : projection_error;
                        state <= PUBLISH;
                    end else begin
                        projected_hold <= projection_data[15:0];
                        if (padding_hold) begin
                            output_hold <= projection_data[15:0];
                            state <= EMIT;
                        end else
                            state <= POSITION_X_START;
                    end
                end
                POSITION_X_START: if (position_ready)
                    state <= POSITION_X_WAIT;
                POSITION_X_WAIT: if (position_valid) begin
                    if (position_error != 0) begin
                        error_hold <= position_error;
                        state <= PUBLISH;
                    end else begin
                        position_x_value <= position_data;
                        state <= POSITION_Y_START;
                    end
                end
                POSITION_Y_START: if (position_ready)
                    state <= POSITION_Y_WAIT;
                POSITION_Y_WAIT: if (position_valid) begin
                    if (position_error != 0) begin
                        error_hold <= position_error;
                        state <= PUBLISH;
                    end else begin
                        position_y_value <= position_data;
                        state <= POSITION_ADD;
                    end
                end
                POSITION_ADD: begin
                    fp_op <= 0;
                    fp_a <= position_x_value;
                    fp_b <= position_y_value;
                    fp_return <= POSITION_NARROW;
                    state <= FP_START;
                end
                POSITION_NARROW: begin
                    fp_op <= 3;
                    fp_a <= fp_value;
                    fp_b <= 0;
                    fp_return <= FINAL_ADD;
                    state <= FP_START;
                end
                FINAL_ADD: begin
                    fp_op <= 0;
                    fp_a <= {projected_hold, 16'd0};
                    fp_b <= {fp_value[15:0], 16'd0};
                    fp_return <= FINAL_NARROW;
                    state <= FP_START;
                end
                FINAL_NARROW: begin
                    fp_op <= 3;
                    fp_a <= fp_value;
                    fp_b <= 0;
                    fp_return <= EMIT;
                    state <= FP_START;
                end
                FP_START: if (fp_ready)
                    state <= FP_WAIT;
                FP_WAIT: if (fp_valid) begin
                    fp_value <= fp_data;
                    if (fp_error != 0) begin
                        error_hold <= fp_error;
                        state <= PUBLISH;
                    end else begin
                        if (fp_return == EMIT)
                            output_hold <= fp_data[15:0];
                        state <= fp_return;
                    end
                end
                EMIT: if (output_ready)
                    state <= ADVANCE;
                ADVANCE: begin
                    if (row == 767)
                        state <= PUBLISH;
                    else begin
                        row <= row + 1'b1;
                        state <= PROJECTION_START;
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
