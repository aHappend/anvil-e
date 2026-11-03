module anvil_en1_vision_pool (
    input wire image_immutable, image_invalidate,
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] model,
    input wire [31:0] generation, patches, patch_rows, patch_columns,
    input wire [31:0] pool_count, pool_index,
    input wire [63:0] image_base,
    output wire source_valid,
    input wire source_ready,
    output wire [31:0] source_generation, source_patch, source_index,
    output wire [1:0] source_model,
    output wire [7:0] source_layer,
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
    output wire output_valid,
    input wire output_ready,
    output wire [31:0] output_index,
    output wire [15:0] output_data,
    output wire output_last, output_mask,
    output wire done_valid,
    input wire done_ready,
    output wire [3:0] done_error,
    output wire input_read_event,
    output wire [31:0] input_read_bytes,
    output wire source_read_event,
    output wire [31:0] source_read_bytes,
    output wire [63:0] controller_bytes, divider_controller_bytes
);
    localparam [5:0] IDLE = 0, VALIDATE = 1, GRID_PRODUCT = 2,
        GRID_VALIDATE = 3, IMAGE_START = 4, IMAGE_WAIT = 5,
        COORD_OFFSET = 6, COORD_ADDRESS = 7, COORD_BOUNDS = 8,
        X_SEND = 9, X_WAIT = 10, X_REGISTER = 11,
        Y_ADDRESS = 12, Y_BOUNDS = 13, Y_SEND = 14, Y_WAIT = 15,
        Y_REGISTER = 16, COORD_VALIDATE = 17, SCAN_ADVANCE = 18,
        STRIDE_SETUP = 19, STRIDE_RESULT = 20,
        UINT_START = 21, UINT_WAIT = 22,
        RECIPROCAL_SETUP = 23, RECIPROCAL_RESULT = 24,
        ROOT_RESULT = 25, RD_START = 26, RD_WAIT = 27,
        COMPONENT_START = 28, MAP_X_SETUP = 29, MAP_X_RESULT = 30,
        MAP_Y_RESULT = 31, MAP_PRODUCT = 32, MAP_ADD = 33,
        MAP_VALIDATE = 34, SOURCE_SEND = 35, SOURCE_WAIT = 36,
        SOURCE_REGISTER = 37, WIDEN = 38, PRODUCT = 39,
        ADD = 40, PATCH_ADVANCE = 41, POOL_NARROW = 42,
        POOL_WIDEN = 43, SCALE = 44, OUTPUT_NARROW = 45,
        OUTPUT_REGISTER = 46, EMIT = 47, COMPONENT_ADVANCE = 48,
        FP_START = 49, FP_WAIT = 50, PUBLISH = 51, RESPONSE = 52;
    reg [5:0] state, uint_return, fp_return, rd_return;
    reg [1:0] model_hold;
    reg [31:0] generation_hold, patches_hold, rows_hold, columns_hold;
    reg [31:0] pool_count_hold, pool_index_hold, grid_hold, pool_extent_hold;
    reg [63:0] image_hold, coords_base, coords_bytes, coord_offset, coord_address;
    reg [31:0] patch_hold, component_hold, x_hold, y_hold, coordinate_word;
    reg coordinate_error, initial_scan, any_nonpadding, padding_hold, mask_hold, match_hold;
    reg [31:0] maximum_x, stride_hold, pool_x, pool_y, bin_product, bin_hold;
    reg [31:0] uint_a, uint_b, uint_value;
    reg [31:0] fp_a, fp_b, fp_value, rd_a, rd_b, rd_value;
    reg [2:0] fp_op;
    reg [1:0] rd_op;
    reg [31:0] reciprocal_hold, root_hold, accumulator;
    reg [15:0] source_hold, output_hold;
    reg source_error_hold;
    reg [3:0] error_hold;

    wire image_ready, image_valid, image_cmd_valid, image_result_ready;
    wire [63:0] image_addr, image_data_base, image_data_bytes;
    wire [31:0] image_rows, image_columns, image_stride;
    wire [7:0] image_type;
    wire [3:0] image_error;
    wire image_selected = rst_n && (state == IMAGE_START || state == IMAGE_WAIT);
    wire [63:0] primitive_directory_bytes, primitive_fp_bytes, primitive_div_bytes;
    anvil_en1_tensor_image directory (
        .image_immutable(image_immutable === 1'b1),
        .image_invalidate((image_invalidate === 1'b1)),
        .controller_bytes(primitive_directory_bytes),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == IMAGE_START), .start_ready(image_ready),
        .model(model_hold), .precision(2'd0), .image_class(2'd3),
        .input_audio(1'b0), .input_items(patches_hold), .image_base(image_hold),
        .tensor_kind(16'h3001), .tensor_layer(16'hffff),
        .cmd_valid(image_cmd_valid), .cmd_ready(image_selected && cmd_ready),
        .cmd_write(), .cmd_addr(image_addr), .cmd_wdata(),
        .result_valid(image_selected && result_valid), .result_ready(image_result_ready),
        .result_data(result_data), .result_error(result_error),
        .done_valid(image_valid), .done_ready(rst_n && state == IMAGE_WAIT),
        .done_base(image_data_base), .done_bytes(image_data_bytes),
        .done_rows(image_rows), .done_columns(image_columns), .done_stride(image_stride),
        .done_type(image_type), .done_error(image_error)
    );
    wire uint_ready, uint_valid;
    wire [31:0] uint_quotient, uint_remainder;
    wire [3:0] uint_error;
    anvil_en1_uint_div integer_divider (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == UINT_START), .start_ready(uint_ready),
        .numerator(uint_a), .denominator(uint_b),
        .done_valid(uint_valid), .done_ready(rst_n && state == UINT_WAIT),
        .quotient(uint_quotient), .remainder(uint_remainder), .done_error(uint_error),
        .controller_bytes(divider_controller_bytes)
    );
    wire fp_ready, fp_valid, rd_ready, rd_valid;
    wire [31:0] fp_data, rd_data;
    wire [3:0] fp_error, rd_error;
    anvil_en1_fp32 arithmetic (
        .controller_bytes(primitive_fp_bytes),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == FP_START), .start_ready(fp_ready),
        .operation(fp_op), .operand_a(fp_a), .operand_b(fp_b),
        .done_valid(fp_valid), .done_ready(rst_n && state == FP_WAIT),
        .done_data(fp_data), .done_error(fp_error)
    );
    anvil_en1_fp32_divsqrt root_divider (
        .controller_bytes(primitive_div_bytes),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == RD_START), .start_ready(rd_ready),
        .operation(rd_op), .operand_a(rd_a), .operand_b(rd_b),
        .done_valid(rd_valid), .done_ready(rst_n && state == RD_WAIT),
        .done_data(rd_data), .done_error(rd_error)
    );
    wire [64:0] coordinate_sum = {1'b0, coords_base} + {1'b0, coord_offset};
    wire [64:0] coordinates_end = {1'b0, coords_base} + {1'b0, coords_bytes};
    wire [64:0] coordinate_row_end = {1'b0, coord_address} + 65'd8;
    wire [64:0] coordinate_y = {1'b0, coord_address} + 65'd4;
    wire [64:0] coordinate_y_end = {1'b0, coord_address} + 65'd4;
    wire both_padding = x_hold == 32'hffffffff && y_hold == 32'hffffffff;
    wire valid_coordinates = !x_hold[31] && !y_hold[31] &&
        x_hold < columns_hold && y_hold < rows_hold;
    assign start_ready = rst_n && state == IDLE;
    assign cmd_valid = rst_n && (image_selected ? image_cmd_valid :
        (state == X_SEND || state == Y_SEND));
    assign cmd_write = 0;
    assign cmd_addr = !rst_n ? 64'd0 :
        (image_selected ? image_addr : coord_address);
    assign cmd_wdata = 0;
    assign result_ready = rst_n && (image_selected ? image_result_ready :
        (state == X_WAIT || state == Y_WAIT));
    assign source_valid = rst_n && state == SOURCE_SEND;
    assign source_generation = rst_n ? generation_hold : 32'd0;
    assign source_model = rst_n ? model_hold : 2'd0;
    assign source_layer = rst_n ? 8'd16 : 8'd0;
    assign source_patch = rst_n ? patch_hold : 32'd0;
    assign source_index = rst_n ? component_hold : 32'd0;
    assign source_rsp_ready = rst_n && state == SOURCE_WAIT;
    assign output_valid = rst_n && state == EMIT;
    assign output_index = rst_n ? component_hold : 32'd0;
    assign output_data = rst_n ? output_hold : 16'd0;
    assign output_last = rst_n && state == EMIT && component_hold == 767;
    assign output_mask = rst_n && mask_hold;
    assign done_valid = rst_n && state == RESPONSE;
    assign done_error = rst_n ? error_hold : 4'd0;
    assign input_read_event = cmd_valid && cmd_ready;
    assign input_read_bytes = input_read_event ? 32'd4 : 32'd0;
    assign source_read_event = source_valid && source_ready;
    assign source_read_bytes = source_read_event ? 32'd2 : 32'd0;
    wire [31:0] CONTROLLER_BITS =
        $bits(state) + $bits(uint_return) + $bits(fp_return) + $bits(rd_return) +
        $bits(model_hold) + $bits(generation_hold) + $bits(patches_hold) +
        $bits(rows_hold) + $bits(columns_hold) + $bits(pool_count_hold) +
        $bits(pool_index_hold) + $bits(grid_hold) + $bits(pool_extent_hold) +
        $bits(image_hold) + $bits(coords_base) + $bits(coords_bytes) +
        $bits(coord_offset) + $bits(coord_address) + $bits(patch_hold) +
        $bits(component_hold) + $bits(x_hold) + $bits(y_hold) + $bits(coordinate_word) +
        $bits(coordinate_error) + $bits(initial_scan) + $bits(any_nonpadding) +
        $bits(padding_hold) + $bits(mask_hold) + $bits(match_hold) + $bits(maximum_x) +
        $bits(stride_hold) + $bits(pool_x) + $bits(pool_y) + $bits(bin_product) +
        $bits(bin_hold) + $bits(uint_a) + $bits(uint_b) + $bits(uint_value) +
        $bits(fp_a) + $bits(fp_b) + $bits(fp_value) + $bits(rd_a) + $bits(rd_b) +
        $bits(rd_value) + $bits(fp_op) + $bits(rd_op) + $bits(reciprocal_hold) +
        $bits(root_hold) + $bits(accumulator) + $bits(source_hold) +
        $bits(output_hold) + $bits(source_error_hold) + $bits(error_hold);
    assign controller_bytes = !rst_n ? 64'd0 : 64'((CONTROLLER_BITS + 7) >> 3) +
        primitive_directory_bytes + primitive_fp_bytes + primitive_div_bytes;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            uint_return <= 0;
            fp_return <= 0;
            rd_return <= 0;
            model_hold <= 0;
            generation_hold <= 0;
            patches_hold <= 0;
            rows_hold <= 0;
            columns_hold <= 0;
            pool_count_hold <= 0;
            pool_index_hold <= 0;
            grid_hold <= 0;
            pool_extent_hold <= 0;
            image_hold <= 0;
            coords_base <= 0;
            coords_bytes <= 0;
            coord_offset <= 0;
            coord_address <= 0;
            patch_hold <= 0;
            component_hold <= 0;
            x_hold <= 0;
            y_hold <= 0;
            coordinate_word <= 0;
            coordinate_error <= 0;
            initial_scan <= 0;
            any_nonpadding <= 0;
            padding_hold <= 0;
            mask_hold <= 0;
            match_hold <= 0;
            maximum_x <= 0;
            stride_hold <= 0;
            pool_x <= 0;
            pool_y <= 0;
            bin_product <= 0;
            bin_hold <= 0;
            uint_a <= 0;
            uint_b <= 0;
            uint_value <= 0;
            fp_a <= 0;
            fp_b <= 0;
            fp_value <= 0;
            rd_a <= 0;
            rd_b <= 0;
            rd_value <= 0;
            fp_op <= 0;
            rd_op <= 0;
            reciprocal_hold <= 0;
            root_hold <= 0;
            accumulator <= 0;
            source_hold <= 0;
            output_hold <= 0;
            source_error_hold <= 0;
            error_hold <= 0;
        end else begin
            case (state)
                IDLE: if (start_valid && start_ready) begin
                    model_hold <= model;
                    generation_hold <= generation;
                    patches_hold <= patches;
                    rows_hold <= patch_rows;
                    columns_hold <= patch_columns;
                    pool_count_hold <= pool_count;
                    pool_index_hold <= pool_index;
                    image_hold <= image_base;
                    component_hold <= 0;
                    patch_hold <= 0;
                    initial_scan <= 1;
                    maximum_x <= 1;
                    any_nonpadding <= 0;
                    mask_hold <= 0;
                    match_hold <= 0;
                    output_hold <= 0;
                    error_hold <= 0;
                    state <= VALIDATE;
                end
                VALIDATE: begin
                    if (model_hold != 1 && model_hold != 2) begin
                        error_hold <= 6;
                        state <= PUBLISH;
                    end else if (generation_hold == 0 || patches_hold == 0 ||
                        patches_hold > 131072 || rows_hold == 0 || rows_hold > 10240 ||
                        columns_hold == 0 || columns_hold > 10240 ||
                        pool_count_hold == 0 || pool_count_hold > 14563 ||
                        pool_index_hold >= pool_count_hold || image_hold[1:0] != 0) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else
                        state <= GRID_PRODUCT;
                end
                GRID_PRODUCT: begin
                    grid_hold <= rows_hold[15:0] * columns_hold[15:0];
                    pool_extent_hold <= (pool_count_hold << 3) + pool_count_hold;
                    state <= GRID_VALIDATE;
                end
                GRID_VALIDATE: begin
                    if (grid_hold != patches_hold || pool_extent_hold != patches_hold) begin
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
                    end else if (image_rows != patches_hold || image_columns != 2 ||
                        image_stride != 8 || image_type != 3) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else begin
                        coords_base <= image_data_base;
                        coords_bytes <= image_data_bytes;
                        state <= COORD_OFFSET;
                    end
                end
                COORD_OFFSET: begin
                    coord_offset <= {32'd0, patch_hold} << 3;
                    state <= COORD_ADDRESS;
                end
                COORD_ADDRESS: begin
                    if (coordinate_sum[64]) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else begin
                        coord_address <= coordinate_sum[63:0];
                        state <= COORD_BOUNDS;
                    end
                end
                COORD_BOUNDS: begin
                    if (coordinates_end[64] || coordinate_row_end[64] ||
                        coordinate_row_end > coordinates_end || coord_address[1:0] != 0) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else
                        state <= X_SEND;
                end
                X_SEND: if (cmd_ready)
                    state <= X_WAIT;
                X_WAIT: if (result_valid) begin
                    coordinate_word <= result_data;
                    coordinate_error <= result_error;
                    state <= X_REGISTER;
                end
                X_REGISTER: begin
                    if (coordinate_error) begin
                        error_hold <= 2;
                        state <= PUBLISH;
                    end else begin
                        x_hold <= coordinate_word;
                        state <= Y_ADDRESS;
                    end
                end
                Y_ADDRESS: begin
                    if (coordinate_y[64]) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else begin
                        coord_address <= coordinate_y[63:0];
                        state <= Y_BOUNDS;
                    end
                end
                Y_BOUNDS: begin
                    if (coordinate_y_end[64] || coordinate_y_end > coordinates_end) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else
                        state <= Y_SEND;
                end
                Y_SEND: if (cmd_ready)
                    state <= Y_WAIT;
                Y_WAIT: if (result_valid) begin
                    coordinate_word <= result_data;
                    coordinate_error <= result_error;
                    state <= Y_REGISTER;
                end
                Y_REGISTER: begin
                    if (coordinate_error) begin
                        error_hold <= 2;
                        state <= PUBLISH;
                    end else begin
                        y_hold <= coordinate_word;
                        state <= COORD_VALIDATE;
                    end
                end
                COORD_VALIDATE: begin
                    if (!both_padding && !valid_coordinates) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else begin
                        padding_hold <= both_padding;
                        if (initial_scan) begin
                            if (!both_padding) begin
                                any_nonpadding <= 1;
                                if (x_hold + 1'b1 > maximum_x)
                                    maximum_x <= x_hold + 1'b1;
                            end
                            state <= SCAN_ADVANCE;
                        end else
                            state <= MAP_X_SETUP;
                    end
                end
                SCAN_ADVANCE: begin
                    if (patch_hold + 1'b1 == patches_hold)
                        state <= STRIDE_SETUP;
                    else begin
                        patch_hold <= patch_hold + 1'b1;
                        state <= COORD_OFFSET;
                    end
                end
                STRIDE_SETUP: begin
                    if (!any_nonpadding) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else begin
                        uint_a <= maximum_x;
                        uint_b <= 3;
                        uint_return <= STRIDE_RESULT;
                        state <= UINT_START;
                    end
                end
                STRIDE_RESULT: begin
                    stride_hold <= uint_value;
                    state <= RECIPROCAL_SETUP;
                end
                RECIPROCAL_SETUP: begin
                    rd_a <= 32'h3f800000;
                    rd_b <= 32'h41100000;
                    rd_op <= 0;
                    rd_return <= RECIPROCAL_RESULT;
                    state <= RD_START;
                end
                RECIPROCAL_RESULT: begin
                    reciprocal_hold <= rd_value;
                    rd_a <= 32'h44400000;
                    rd_b <= 0;
                    rd_op <= 1;
                    rd_return <= ROOT_RESULT;
                    state <= RD_START;
                end
                ROOT_RESULT: begin
                    root_hold <= rd_value;
                    initial_scan <= 0;
                    state <= COMPONENT_START;
                end
                COMPONENT_START: begin
                    accumulator <= 0;
                    patch_hold <= 0;
                    state <= COORD_OFFSET;
                end
                MAP_X_SETUP: begin
                    uint_a <= padding_hold ? 32'd0 : x_hold;
                    uint_b <= 3;
                    uint_return <= MAP_X_RESULT;
                    state <= UINT_START;
                end
                MAP_X_RESULT: begin
                    pool_x <= uint_value;
                    uint_a <= padding_hold ? 32'd0 : y_hold;
                    uint_b <= 3;
                    uint_return <= MAP_Y_RESULT;
                    state <= UINT_START;
                end
                MAP_Y_RESULT: begin
                    pool_y <= uint_value;
                    state <= MAP_PRODUCT;
                end
                MAP_PRODUCT: begin
                    bin_product <= stride_hold[15:0] * pool_y[15:0];
                    state <= MAP_ADD;
                end
                MAP_ADD: begin
                    bin_hold <= bin_product + pool_x;
                    state <= MAP_VALIDATE;
                end
                MAP_VALIDATE: begin
                    if (bin_hold >= pool_count_hold) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else begin
                        match_hold <= bin_hold == pool_index_hold;
                        if (bin_hold == pool_index_hold)
                            mask_hold <= 1;
                        if (padding_hold) begin
                            fp_value <= 0;
                            state <= PRODUCT;
                        end else
                            state <= SOURCE_SEND;
                    end
                end
                SOURCE_SEND: if (source_ready)
                    state <= SOURCE_WAIT;
                SOURCE_WAIT: if (source_rsp_valid) begin
                    source_hold <= source_rsp_data;
                    source_error_hold <= source_rsp_error;
                    state <= SOURCE_REGISTER;
                end
                SOURCE_REGISTER: begin
                    if (source_error_hold) begin
                        error_hold <= 7;
                        state <= PUBLISH;
                    end else
                        state <= WIDEN;
                end
                WIDEN: begin
                    fp_a <= {16'd0, source_hold};
                    fp_b <= 0;
                    fp_op <= 2;
                    fp_return <= PRODUCT;
                    state <= FP_START;
                end
                PRODUCT: begin
                    fp_a <= fp_value;
                    fp_b <= match_hold ? reciprocal_hold : 32'd0;
                    fp_op <= 1;
                    fp_return <= ADD;
                    state <= FP_START;
                end
                ADD: begin
                    fp_a <= accumulator;
                    fp_b <= fp_value;
                    fp_op <= 0;
                    fp_return <= PATCH_ADVANCE;
                    state <= FP_START;
                end
                PATCH_ADVANCE: begin
                    accumulator <= fp_value;
                    if (patch_hold + 1'b1 == patches_hold)
                        state <= POOL_NARROW;
                    else begin
                        patch_hold <= patch_hold + 1'b1;
                        state <= COORD_OFFSET;
                    end
                end
                POOL_NARROW: begin
                    fp_a <= accumulator;
                    fp_b <= 0;
                    fp_op <= 3;
                    fp_return <= POOL_WIDEN;
                    state <= FP_START;
                end
                POOL_WIDEN: begin
                    fp_a <= {16'd0, fp_value[15:0]};
                    fp_b <= 0;
                    fp_op <= 2;
                    fp_return <= SCALE;
                    state <= FP_START;
                end
                SCALE: begin
                    fp_a <= fp_value;
                    fp_b <= root_hold;
                    fp_op <= 1;
                    fp_return <= OUTPUT_NARROW;
                    state <= FP_START;
                end
                OUTPUT_NARROW: begin
                    fp_a <= fp_value;
                    fp_b <= 0;
                    fp_op <= 3;
                    fp_return <= OUTPUT_REGISTER;
                    state <= FP_START;
                end
                OUTPUT_REGISTER: begin
                    output_hold <= fp_value[15:0];
                    state <= EMIT;
                end
                EMIT: if (output_ready)
                    state <= COMPONENT_ADVANCE;
                COMPONENT_ADVANCE: begin
                    if (component_hold == 767)
                        state <= PUBLISH;
                    else begin
                        component_hold <= component_hold + 1'b1;
                        state <= COMPONENT_START;
                    end
                end
                UINT_START: if (uint_ready)
                    state <= UINT_WAIT;
                UINT_WAIT: if (uint_valid) begin
                    if (uint_error != 0) begin
                        error_hold <= uint_error;
                        state <= PUBLISH;
                    end else begin
                        uint_value <= uint_quotient;
                        state <= uint_return;
                    end
                end
                FP_START: if (fp_ready)
                    state <= FP_WAIT;
                FP_WAIT: if (fp_valid) begin
                    if (fp_error != 0) begin
                        error_hold <= fp_error;
                        state <= PUBLISH;
                    end else begin
                        fp_value <= fp_data;
                        state <= fp_return;
                    end
                end
                RD_START: if (rd_ready)
                    state <= RD_WAIT;
                RD_WAIT: if (rd_valid) begin
                    if (rd_error != 0) begin
                        error_hold <= rd_error;
                        state <= PUBLISH;
                    end else begin
                        rd_value <= rd_data;
                        state <= rd_return;
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
