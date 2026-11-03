module anvil_en1_tensor_image #(
    parameter integer COMPACT = 0
) (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] model, precision, image_class,
    input wire input_audio,
    input wire [31:0] input_items,
    input wire [63:0] image_base,
    input wire [15:0] tensor_kind, tensor_layer,
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
    output wire [63:0] done_base, done_bytes,
    output wire [31:0] done_rows, done_columns, done_stride,
    output wire [7:0] done_type,
    output wire [3:0] done_error,
    output wire [63:0] controller_bytes
);
    localparam integer LEGAL = COMPACT == 0 || COMPACT == 1;
    generate if (!LEGAL) begin : invalid_parameters
        initial $fatal(1, "PARAMETER ERROR: COMPACT must be 0 or 1");
        assign start_ready = 0;
        assign cmd_valid = 0;
        assign cmd_write = 0;
        assign cmd_addr = 0;
        assign cmd_wdata = 0;
        assign result_ready = 0;
        assign done_valid = 0;
        assign done_base = 0;
        assign done_bytes = 0;
        assign done_rows = 0;
        assign done_columns = 0;
        assign done_stride = 0;
        assign done_type = 0;
        assign done_error = 0;
        assign controller_bytes = 0;
    end else begin : reader
        localparam [4:0] IDLE = 0, BASE_VALIDATE = 1, MEMORY_START = 2,
            MEMORY_WAIT = 3, MEMORY_REGISTER = 4, HEADER_ADVANCE = 5,
            HEADER_VALIDATE = 6, ENTRY_START = 7, ENTRY_ADVANCE = 8,
            ENTRY_PRODUCTS = 9, ENTRY_REDUCE = 10, ENTRY_SUM = 11,
            ENTRY_VALIDATE = 12, PAIR_START = 13, PAIR_ADVANCE = 14,
            PAIR_VALIDATE = 15, ENTRY_FINISH = 16, FINISH = 17,
            PUBLISH = 18, RESPONSE = 19;
        reg [4:0] state, return_state;
        reg [1:0] model_hold, precision_hold, class_hold;
        reg audio_hold;
        reg [31:0] items_hold;
        reg [15:0] kind_hold, layer_hold;
        reg [63:0] base_hold, directory_base, address_hold;
        reg [159:0] header;
        reg [351:0] entry;
        reg [159:0] prior_entry;
        reg [31:0] word_hold;
        reg memory_error_hold, found, header_word_error, entry_word_error;
        reg [3:0] word_index, error_hold;
        reg [31:0] entry_index, prior_index;
        reg [31:0] ep00, ep01, ep10, ep11;
        reg [63:0] extent_partial_a, extent_partial_b, required_bytes;
        reg [63:0] output_base, output_bytes;
        reg [31:0] output_rows, output_columns, output_stride;
        reg [7:0] output_type;
        localparam integer CONTROLLER_BITS = $bits(state) + $bits(return_state) +
            $bits(model_hold) + $bits(precision_hold) + $bits(class_hold) +
            $bits(audio_hold) + $bits(items_hold) + $bits(kind_hold) +
            $bits(layer_hold) + $bits(base_hold) + $bits(directory_base) +
            $bits(address_hold) + $bits(header) + $bits(entry) +
            $bits(prior_entry) + $bits(word_hold) + $bits(memory_error_hold) +
            $bits(found) + $bits(header_word_error) + $bits(entry_word_error) +
            $bits(word_index) + $bits(error_hold) +
            $bits(entry_index) + $bits(prior_index) + $bits(ep00) + $bits(ep01) +
            $bits(ep10) + $bits(ep11) + $bits(extent_partial_a) +
            $bits(extent_partial_b) + $bits(required_bytes) + $bits(output_base) +
            $bits(output_bytes) + $bits(output_rows) + $bits(output_columns) +
            $bits(output_stride) + $bits(output_type);
        assign controller_bytes = rst_n ? 64'((CONTROLLER_BITS+7) >> 3) : 64'd0;
        wire requested_valid, shape_valid;
        wire [31:0] expected_count, shape_rows, shape_columns;
        wire [31:0] shape_d0, shape_d1, shape_d2, shape_d3;
        wire [7:0] shape_type, shape_rank;
        anvil_en1_tensor_shape #(.COMPACT(COMPACT)) requested_shape (
            .rst_n(rst_n), .model(model_hold), .precision(precision_hold),
            .image_class(class_hold), .input_audio(audio_hold), .input_items(items_hold),
            .kind(kind_hold), .layer(layer_hold), .valid(requested_valid),
            .tensor_type(), .rank(), .dim0(), .dim1(), .dim2(), .dim3(),
            .rows(), .columns(), .entry_count(expected_count)
        );
        anvil_en1_tensor_shape #(.COMPACT(COMPACT)) current_shape (
            .rst_n(rst_n), .model(model_hold), .precision(precision_hold),
            .image_class(class_hold), .input_audio(audio_hold), .input_items(items_hold),
            .kind(entry[15:0]), .layer(entry[31:16]), .valid(shape_valid),
            .tensor_type(shape_type), .rank(shape_rank),
            .dim0(shape_d0), .dim1(shape_d1), .dim2(shape_d2), .dim3(shape_d3),
            .rows(shape_rows), .columns(shape_columns), .entry_count()
        );

        wire [63:0] image_bytes = header[63:0];
        wire [63:0] directory_offset = header[159:96];
        wire [31:0] directory_count = header[95:64];
        wire [64:0] base_header_end = {1'b0, base_hold} + 65'd64;
        wire [64:0] image_end = {1'b0, base_hold} + {1'b0, image_bytes};
        wire [64:0] directory_end =
            {1'b0, directory_offset} + {27'd0, directory_count, 6'd0};
        wire [64:0] directory_sum =
            {1'b0, base_hold} + {1'b0, directory_offset};
        wire [63:0] entry_offset = entry[127:64];
        wire [63:0] entry_bytes = entry[191:128];
        wire [64:0] entry_end = {1'b0, entry_offset} + {1'b0, entry_bytes};
        wire [64:0] payload_sum = {1'b0, base_hold} + {1'b0, entry_offset};
        wire [64:0] entry_address =
            {1'b0, directory_base} + {27'd0, entry_index, 6'd0};
        wire [64:0] prior_address =
            {1'b0, directory_base} + {27'd0, prior_index, 6'd0};
        wire [64:0] prior_end =
            {1'b0, prior_entry[95:32]} + {1'b0, prior_entry[159:96]};
        wire [63:0] columns_wide = {32'd0, shape_columns};
        wire [63:0] q4_blocks_exact = (columns_wide + 31) >> 5;
        wire [63:0] q4_bytes = (q4_blocks_exact << 4) + (q4_blocks_exact << 1);
        wire [63:0] required_stride = shape_type == 1 ?
            (q4_bytes + 3) & 64'hfffffffffffffffc :
            (shape_type == 0 ? ((columns_wide + 1) >> 1) << 2 : columns_wide << 2);
        wire header_word_bad =
            (word_index == 0 && word_hold !=
                (class_hold == 3 ? 32'h31494e41 : 32'h31564e41)) ||
            (word_index == 1 && word_hold != 32'h00010000) ||
            (word_index == 2 && word_hold != {30'd0, model_hold}) ||
            (word_index == 3 && word_hold !=
                (class_hold == 3 ? 32'd0 : {30'd0, precision_hold})) ||
            (word_index == 7 && word_hold != 32'd64) ||
            (word_index >= 10 && word_hold != 0);
        wire header_bad = header_word_error || image_bytes < 64 || image_end[64] ||
            directory_count != expected_count ||
            directory_offset < 64 ||
            directory_offset[1:0] != 0 || directory_end[64] ||
            directory_end[63:0] > image_bytes ||
            directory_sum[64];
        wire entry_bad = !shape_valid || entry[39:32] != shape_type ||
            entry[47:40] != shape_rank || entry[63:48] != 0 ||
            entry[223:192] != shape_d0 || entry[255:224] != shape_d1 ||
            entry[287:256] != shape_d2 || entry[319:288] != shape_d3 ||
            required_stride[63:32] != 0 || required_stride == 0 ||
            entry[351:320] != required_stride[31:0] ||
            entry_word_error || entry_offset < 64 || entry_offset[1:0] != 0 ||
            entry_bytes != required_bytes || entry_end[64] ||
            entry_end[63:0] > image_bytes || payload_sum[64] ||
            (entry_offset < directory_end[63:0] &&
                directory_offset < entry_end[63:0]);
        wire prior_bad = entry[31:0] == prior_entry[31:0] ||
            prior_end[64] ||
            (entry_offset < prior_end[63:0] &&
                prior_entry[95:32] < entry_end[63:0]);

        assign start_ready = rst_n && state == IDLE;
        assign cmd_valid = rst_n && state == MEMORY_START;
        assign cmd_write = 0;
        assign cmd_addr = rst_n ? address_hold : 64'd0;
        assign cmd_wdata = 0;
        assign result_ready = rst_n && state == MEMORY_WAIT;
        assign done_valid = rst_n && state == RESPONSE;
        assign done_base = rst_n ? output_base : 64'd0;
        assign done_bytes = rst_n ? output_bytes : 64'd0;
        assign done_rows = rst_n ? output_rows : 32'd0;
        assign done_columns = rst_n ? output_columns : 32'd0;
        assign done_stride = rst_n ? output_stride : 32'd0;
        assign done_type = rst_n ? output_type : 8'd0;
        assign done_error = rst_n ? error_hold : 4'd0;

        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                state <= IDLE;
                return_state <= 0;
                model_hold <= 0;
                precision_hold <= 0;
                class_hold <= 0;
                audio_hold <= 0;
                items_hold <= 0;
                kind_hold <= 0;
                layer_hold <= 0;
                base_hold <= 0;
                directory_base <= 0;
                address_hold <= 0;
                header <= 0;
                entry <= 0;
                prior_entry <= 0;
                word_hold <= 0;
                memory_error_hold <= 0;
                found <= 0;
                header_word_error <= 0;
                entry_word_error <= 0;
                word_index <= 0;
                error_hold <= 0;
                entry_index <= 0;
                prior_index <= 0;
                ep00 <= 0;
                ep01 <= 0;
                ep10 <= 0;
                ep11 <= 0;
                extent_partial_a <= 0;
                extent_partial_b <= 0;
                required_bytes <= 0;
                output_base <= 0;
                output_bytes <= 0;
                output_rows <= 0;
                output_columns <= 0;
                output_stride <= 0;
                output_type <= 0;
            end else begin
                case (state)
                    IDLE: if (start_valid && start_ready) begin
                        model_hold <= model;
                        precision_hold <= precision;
                        class_hold <= image_class;
                        audio_hold <= input_audio;
                        items_hold <= input_items;
                        kind_hold <= tensor_kind;
                        layer_hold <= tensor_layer;
                        base_hold <= image_base;
                        found <= 0;
                        header_word_error <= 0;
                        entry_word_error <= 0;
                        word_index <= 0;
                        error_hold <= 0;
                        entry_index <= 0;
                        output_base <= 0;
                        output_bytes <= 0;
                        output_rows <= 0;
                        output_columns <= 0;
                        output_stride <= 0;
                        output_type <= 0;
                        state <= BASE_VALIDATE;
                    end
                    BASE_VALIDATE: begin
                        if ((model_hold != 1 && model_hold != 2) || precision_hold > 1) begin
                            error_hold <= 6;
                            state <= PUBLISH;
                        end else if (!requested_valid || base_hold[1:0] != 0 ||
                            base_header_end[64]) begin
                            error_hold <= 5;
                            state <= PUBLISH;
                        end else begin
                            address_hold <= base_hold;
                            return_state <= HEADER_ADVANCE;
                            state <= MEMORY_START;
                        end
                    end
                    MEMORY_START: if (cmd_ready)
                        state <= MEMORY_WAIT;
                    MEMORY_WAIT: if (result_valid && result_ready) begin
                        word_hold <= result_data;
                        memory_error_hold <= result_error;
                        state <= MEMORY_REGISTER;
                    end
                    MEMORY_REGISTER: begin
                        if (memory_error_hold) begin
                            error_hold <= 2;
                            state <= PUBLISH;
                        end else
                            state <= return_state;
                    end
                    HEADER_ADVANCE: begin
                        header_word_error <= header_word_error || header_word_bad;
                        case (word_index)
                            4: header[31:0] <= word_hold;
                            5: header[63:32] <= word_hold;
                            6: header[95:64] <= word_hold;
                            8: header[127:96] <= word_hold;
                            9: header[159:128] <= word_hold;
                            default: begin end
                        endcase
                        if (word_index == 15)
                            state <= HEADER_VALIDATE;
                        else begin
                            word_index <= word_index + 1'b1;
                            address_hold <= address_hold + 4;
                            state <= MEMORY_START;
                        end
                    end
                    HEADER_VALIDATE: begin
                        if (header_bad) begin
                            error_hold <= 5;
                            state <= PUBLISH;
                        end else begin
                            directory_base <= directory_sum[63:0];
                            state <= ENTRY_START;
                        end
                    end
                    ENTRY_START: begin
                        if (entry_address[64] || entry_index >= directory_count) begin
                            error_hold <= 5;
                            state <= PUBLISH;
                        end else begin
                            address_hold <= entry_address[63:0];
                            word_index <= 0;
                            entry_word_error <= 0;
                            return_state <= ENTRY_ADVANCE;
                            state <= MEMORY_START;
                        end
                    end
                    ENTRY_ADVANCE: begin
                        if (word_index < 11)
                            entry[32*word_index+:32] <= word_hold;
                        else if (word_hold != 0)
                            entry_word_error <= 1;
                        if (word_index == 15)
                            state <= ENTRY_PRODUCTS;
                        else begin
                            word_index <= word_index + 1'b1;
                            address_hold <= address_hold + 4;
                            state <= MEMORY_START;
                        end
                    end
                    ENTRY_PRODUCTS: begin
                        ep00 <= shape_rows[15:0] * entry[335:320];
                        ep01 <= shape_rows[15:0] * entry[351:336];
                        ep10 <= shape_rows[31:16] * entry[335:320];
                        ep11 <= shape_rows[31:16] * entry[351:336];
                        state <= ENTRY_REDUCE;
                    end
                    ENTRY_REDUCE: begin
                        extent_partial_a <= {32'd0, ep00} + {16'd0, ep01, 16'd0};
                        extent_partial_b <= {16'd0, ep10, 16'd0} + {ep11, 32'd0};
                        state <= ENTRY_SUM;
                    end
                    ENTRY_SUM: begin
                        required_bytes <= extent_partial_a + extent_partial_b;
                        state <= ENTRY_VALIDATE;
                    end
                    ENTRY_VALIDATE: begin
                        if (entry_bad) begin
                            error_hold <= 5;
                            state <= PUBLISH;
                        end else begin
                            prior_index <= 0;
                            if (entry_index == 0)
                                state <= ENTRY_FINISH;
                            else
                                state <= PAIR_START;
                        end
                    end
                    PAIR_START: begin
                        if (prior_address[64] || prior_index >= entry_index) begin
                            error_hold <= 5;
                            state <= PUBLISH;
                        end else begin
                            address_hold <= prior_address[63:0];
                            word_index <= 0;
                            return_state <= PAIR_ADVANCE;
                            state <= MEMORY_START;
                        end
                    end
                    PAIR_ADVANCE: begin
                        case (word_index)
                            0: prior_entry[31:0] <= word_hold;
                            2: prior_entry[63:32] <= word_hold;
                            3: prior_entry[95:64] <= word_hold;
                            4: prior_entry[127:96] <= word_hold;
                            5: prior_entry[159:128] <= word_hold;
                            default: begin end
                        endcase
                        if (word_index == 5)
                            state <= PAIR_VALIDATE;
                        else begin
                            word_index <= word_index + 1'b1;
                            address_hold <= address_hold + 4;
                            state <= MEMORY_START;
                        end
                    end
                    PAIR_VALIDATE: begin
                        if (prior_bad) begin
                            error_hold <= 5;
                            state <= PUBLISH;
                        end else if (prior_index == entry_index - 1'b1)
                            state <= ENTRY_FINISH;
                        else begin
                            prior_index <= prior_index + 1'b1;
                            state <= PAIR_START;
                        end
                    end
                    ENTRY_FINISH: begin
                        if (entry[31:0] == {layer_hold, kind_hold}) begin
                            found <= 1;
                            output_base <= payload_sum[63:0];
                            output_bytes <= entry_bytes;
                            output_rows <= shape_rows;
                            output_columns <= shape_columns;
                            output_stride <= entry[351:320];
                            output_type <= shape_type;
                        end
                        if (entry_index == directory_count - 1'b1)
                            state <= FINISH;
                        else begin
                            entry_index <= entry_index + 1'b1;
                            state <= ENTRY_START;
                        end
                    end
                    FINISH: begin
                        if (!found)
                            error_hold <= 5;
                        state <= PUBLISH;
                    end
                    PUBLISH: begin
                        if (error_hold != 0) begin
                            output_base <= 0;
                            output_bytes <= 0;
                            output_rows <= 0;
                            output_columns <= 0;
                            output_stride <= 0;
                            output_type <= 0;
                        end
                        state <= RESPONSE;
                    end
                    RESPONSE: if (done_ready)
                        state <= IDLE;
                    default: begin
                        error_hold <= 7;
                        state <= PUBLISH;
                    end
                endcase
            end
        end
    end endgenerate
endmodule
