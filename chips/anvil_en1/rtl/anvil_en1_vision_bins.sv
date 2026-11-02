module anvil_en1_vision_bins (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] model,
    input wire [31:0] generation, patches, patch_rows, patch_columns,
    input wire [31:0] pool_count, soft_token, expected_soft_tokens,
    input wire [63:0] image_base,
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
    output wire [31:0] done_pool_index, done_soft_tokens,
    output wire [3:0] done_error,
    output wire input_read_event,
    output wire [31:0] input_read_bytes,
    output wire [63:0] mask_live_bytes, mask_physical_bytes,
    output wire [63:0] controller_bytes, divider_controller_bytes
);
    localparam [5:0] IDLE = 0, VALIDATE = 1, GRID_PRODUCT = 2,
        GRID_VALIDATE = 3, IMAGE_START = 4, IMAGE_WAIT = 5,
        CLEAR = 6, COORD_OFFSET = 7, COORD_ADDRESS = 8,
        COORD_BOUNDS = 9, X_SEND = 10, X_WAIT = 11, X_REGISTER = 12,
        Y_ADDRESS = 13, Y_BOUNDS = 14, Y_SEND = 15, Y_WAIT = 16,
        Y_REGISTER = 17, COORD_VALIDATE = 18, SCAN_ADVANCE = 19,
        STRIDE_SETUP = 20, STRIDE_RESULT = 21,
        UINT_START = 22, UINT_WAIT = 23,
        MAP_X_SETUP = 24, MAP_X_RESULT = 25, MAP_Y_RESULT = 26,
        MAP_PRODUCT = 27, MAP_ADD = 28, MAP_VALIDATE = 29,
        MASK_READ = 30, MASK_CAPTURE = 31, MASK_WRITE = 32,
        PATCH_ADVANCE = 33, ENUM_READ = 34, ENUM_CAPTURE = 35,
        ENUM_BIT = 36, ENUM_ADVANCE = 37, COUNT_VALIDATE = 38,
        PUBLISH = 39, RESPONSE = 40;
    reg [5:0] state, uint_return;
    reg [1:0] model_hold;
    reg [31:0] generation_hold, patches_hold, rows_hold, columns_hold;
    reg [31:0] count_hold, ordinal_hold, expected_hold, grid_hold, extent_hold;
    reg [63:0] image_hold, coords_base, coords_bytes, coord_offset, coord_address;
    reg [31:0] patch_hold, x_hold, y_hold, coordinate_word;
    reg coordinate_error, initial_scan, any_nonpadding, padding_hold, allocated;
    reg [31:0] maximum_x, stride_hold, pool_x, pool_y, bin_product, bin_hold;
    reg [31:0] uint_a, uint_b, uint_value;
    reg [8:0] clear_word, mask_word;
    reg [4:0] mask_bit;
    reg [31:0] mask_q, mask_hold, mask_write_data;
    reg [31:0] enum_bin, valid_count, selected_bin;
    reg selected;
    reg [3:0] error_hold;
    (* ramstyle = "M20K", nomem2reg *) reg [31:0] bins [0:455];

    wire image_ready, image_valid, image_cmd_valid, image_result_ready;
    wire [63:0] image_addr, image_data_base, image_data_bytes;
    wire [31:0] image_rows, image_columns, image_stride;
    wire [7:0] image_type;
    wire [3:0] image_error;
    wire image_selected = rst_n && (state == IMAGE_START || state == IMAGE_WAIT);
    anvil_en1_tensor_image directory (
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
    wire [31:0] uint_quotient;
    wire [3:0] uint_error;
    anvil_en1_uint_div integer_divider (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == UINT_START), .start_ready(uint_ready),
        .numerator(uint_a), .denominator(uint_b),
        .done_valid(uint_valid), .done_ready(rst_n && state == UINT_WAIT),
        .quotient(uint_quotient), .remainder(), .done_error(uint_error),
        .controller_bytes(divider_controller_bytes)
    );
    wire [64:0] coordinate_sum = {1'b0, coords_base} + {1'b0, coord_offset};
    wire [64:0] coordinates_end = {1'b0, coords_base} + {1'b0, coords_bytes};
    wire [64:0] coordinate_row_end = {1'b0, coord_address} + 65'd8;
    wire [64:0] coordinate_y = {1'b0, coord_address} + 65'd4;
    wire [64:0] coordinate_y_end = {1'b0, coord_address} + 65'd4;
    wire both_padding = x_hold == 32'hffffffff && y_hold == 32'hffffffff;
    wire valid_coordinates = !x_hold[31] && !y_hold[31] &&
        x_hold < columns_hold && y_hold < rows_hold;
    wire [31:0] set_mask = 32'h00000001 << mask_bit;
    always @(posedge clk) begin
        if (rst_n && state == CLEAR)
            bins[clear_word] <= 0;
        else if (rst_n && state == MASK_WRITE)
            bins[mask_word] <= mask_write_data;
        if (rst_n && (state == MASK_READ || state == ENUM_READ))
            mask_q <= bins[mask_word];
    end
    assign start_ready = rst_n && state == IDLE;
    assign cmd_valid = rst_n && (image_selected ? image_cmd_valid :
        (state == X_SEND || state == Y_SEND));
    assign cmd_write = 0;
    assign cmd_addr = !rst_n ? 64'd0 : (image_selected ? image_addr : coord_address);
    assign cmd_wdata = 0;
    assign result_ready = rst_n && (image_selected ? image_result_ready :
        (state == X_WAIT || state == Y_WAIT));
    assign done_valid = rst_n && state == RESPONSE;
    assign done_pool_index = rst_n && state == RESPONSE && error_hold == 0 ?
        selected_bin : 32'd0;
    assign done_soft_tokens = rst_n && state == RESPONSE ? valid_count : 32'd0;
    assign done_error = rst_n ? error_hold : 4'd0;
    assign input_read_event = cmd_valid && cmd_ready;
    assign input_read_bytes = input_read_event ? 32'd4 : 32'd0;
    assign mask_live_bytes = rst_n && allocated ? 64'd1824 : 64'd0;
    assign mask_physical_bytes = rst_n ? 64'd1824 : 64'd0;
    localparam integer CONTROLLER_BITS =
        $bits(state) + $bits(uint_return) + $bits(model_hold) +
        $bits(generation_hold) + $bits(patches_hold) + $bits(rows_hold) +
        $bits(columns_hold) + $bits(count_hold) + $bits(ordinal_hold) +
        $bits(expected_hold) + $bits(grid_hold) + $bits(extent_hold) +
        $bits(image_hold) + $bits(coords_base) + $bits(coords_bytes) +
        $bits(coord_offset) + $bits(coord_address) + $bits(patch_hold) +
        $bits(x_hold) + $bits(y_hold) + $bits(coordinate_word) +
        $bits(coordinate_error) + $bits(initial_scan) + $bits(any_nonpadding) +
        $bits(padding_hold) + $bits(allocated) + $bits(maximum_x) +
        $bits(stride_hold) + $bits(pool_x) + $bits(pool_y) +
        $bits(bin_product) + $bits(bin_hold) + $bits(uint_a) +
        $bits(uint_b) + $bits(uint_value) + $bits(clear_word) +
        $bits(mask_word) + $bits(mask_bit) + $bits(mask_q) +
        $bits(mask_hold) + $bits(mask_write_data) + $bits(enum_bin) +
        $bits(valid_count) + $bits(selected_bin) + $bits(selected) + $bits(error_hold);
    assign controller_bytes = rst_n ? (CONTROLLER_BITS + 7) >> 3 : 64'd0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            uint_return <= 0;
            model_hold <= 0;
            generation_hold <= 0;
            patches_hold <= 0;
            rows_hold <= 0;
            columns_hold <= 0;
            count_hold <= 0;
            ordinal_hold <= 0;
            expected_hold <= 0;
            grid_hold <= 0;
            extent_hold <= 0;
            image_hold <= 0;
            coords_base <= 0;
            coords_bytes <= 0;
            coord_offset <= 0;
            coord_address <= 0;
            patch_hold <= 0;
            x_hold <= 0;
            y_hold <= 0;
            coordinate_word <= 0;
            coordinate_error <= 0;
            initial_scan <= 0;
            any_nonpadding <= 0;
            padding_hold <= 0;
            allocated <= 0;
            maximum_x <= 0;
            stride_hold <= 0;
            pool_x <= 0;
            pool_y <= 0;
            bin_product <= 0;
            bin_hold <= 0;
            uint_a <= 0;
            uint_b <= 0;
            uint_value <= 0;
            clear_word <= 0;
            mask_word <= 0;
            mask_bit <= 0;
            mask_hold <= 0;
            mask_write_data <= 0;
            enum_bin <= 0;
            valid_count <= 0;
            selected_bin <= 0;
            selected <= 0;
            error_hold <= 0;
        end else begin
            case (state)
                IDLE: if (start_valid && start_ready) begin
                    model_hold <= model;
                    generation_hold <= generation;
                    patches_hold <= patches;
                    rows_hold <= patch_rows;
                    columns_hold <= patch_columns;
                    count_hold <= pool_count;
                    ordinal_hold <= soft_token;
                    expected_hold <= expected_soft_tokens;
                    image_hold <= image_base;
                    patch_hold <= 0;
                    initial_scan <= 1;
                    maximum_x <= 1;
                    any_nonpadding <= 0;
                    clear_word <= 0;
                    mask_word <= 0;
                    mask_bit <= 0;
                    enum_bin <= 0;
                    valid_count <= 0;
                    selected_bin <= 0;
                    selected <= 0;
                    allocated <= 1;
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
                        count_hold == 0 || count_hold > 14563 ||
                        expected_hold == 0 || expected_hold > count_hold ||
                        ordinal_hold >= expected_hold || image_hold[1:0] != 0) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else
                        state <= GRID_PRODUCT;
                end
                GRID_PRODUCT: begin
                    grid_hold <= rows_hold[15:0] * columns_hold[15:0];
                    extent_hold <= (count_hold << 3) + count_hold;
                    state <= GRID_VALIDATE;
                end
                GRID_VALIDATE: begin
                    if (grid_hold != patches_hold || extent_hold != patches_hold) begin
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
                        state <= CLEAR;
                    end
                end
                CLEAR: begin
                    if (clear_word == 455)
                        state <= COORD_OFFSET;
                    else
                        clear_word <= clear_word + 1'b1;
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
                    initial_scan <= 0;
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
                    if (bin_hold >= count_hold) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else begin
                        mask_word <= bin_hold[13:5];
                        mask_bit <= bin_hold[4:0];
                        state <= MASK_READ;
                    end
                end
                MASK_READ: state <= MASK_CAPTURE;
                MASK_CAPTURE: begin
                    mask_write_data <= mask_q | set_mask;
                    state <= MASK_WRITE;
                end
                MASK_WRITE: state <= PATCH_ADVANCE;
                PATCH_ADVANCE: begin
                    if (patch_hold + 1'b1 == patches_hold) begin
                        mask_word <= 0;
                        state <= ENUM_READ;
                    end else begin
                        patch_hold <= patch_hold + 1'b1;
                        state <= COORD_OFFSET;
                    end
                end
                ENUM_READ: state <= ENUM_CAPTURE;
                ENUM_CAPTURE: begin
                    mask_hold <= mask_q;
                    state <= ENUM_BIT;
                end
                ENUM_BIT: begin
                    if (mask_hold[enum_bin[4:0]]) begin
                        if (valid_count == ordinal_hold) begin
                            selected_bin <= enum_bin;
                            selected <= 1;
                        end
                        valid_count <= valid_count + 1'b1;
                    end
                    state <= ENUM_ADVANCE;
                end
                ENUM_ADVANCE: begin
                    if (enum_bin + 1'b1 == count_hold)
                        state <= COUNT_VALIDATE;
                    else begin
                        enum_bin <= enum_bin + 1'b1;
                        if (enum_bin[4:0] == 31) begin
                            mask_word <= mask_word + 1'b1;
                            state <= ENUM_READ;
                        end else
                            state <= ENUM_BIT;
                    end
                end
                COUNT_VALIDATE: begin
                    if (!selected || valid_count != expected_hold)
                        error_hold <= 7;
                    state <= PUBLISH;
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
                PUBLISH: state <= RESPONSE;
                RESPONSE: if (done_ready) begin
                    allocated <= 0;
                    state <= IDLE;
                end
                default: begin
                    error_hold <= 7;
                    state <= PUBLISH;
                end
            endcase
        end
    end
endmodule
