module anvil_en1_tensor_shape #(
    parameter integer COMPACT = 0
) (
    input wire rst_n,
    input wire [1:0] model, precision, image_class,
    input wire input_audio,
    input wire [31:0] input_items,
    input wire [15:0] kind, layer,
    output wire valid,
    output wire [7:0] tensor_type, rank,
    output wire [31:0] dim0, dim1, dim2, dim3,
    output wire [31:0] rows, columns, entry_count
);
    generate if (COMPACT != 0 && COMPACT != 1) begin : invalid_parameters
        initial $fatal(1, "PARAMETER ERROR: COMPACT must be 0 or 1");
        assign valid = 0;
        assign tensor_type = 0;
        assign rank = 0;
        assign dim0 = 0;
        assign dim1 = 0;
        assign dim2 = 0;
        assign dim3 = 0;
        assign rows = 0;
        assign columns = 0;
        assign entry_count = 0;
    end else begin : shape
        reg valid_hold, matrix_type, clipped, clip_scalar;
        reg [7:0] type_hold, rank_hold;
        reg [31:0] d0, d1, d2, d3, rows_hold, columns_hold, count_hold;
        reg [15:0] base_kind;
        wire [7:0] layers, owners;
        wire is_global;
        wire [13:0] production_intermediate;
        wire [11:0] production_hidden;
        anvil_en1_geometry geometry (
            .rst_n(rst_n), .model(model), .layer(layer[7:0]),
            .is_native(), .layers(layers), .owners(owners), .owner(),
            .is_global(is_global), .hidden(production_hidden),
            .intermediate(production_intermediate)
        );
        wire [31:0] h = COMPACT ? 32'd8 : {20'd0, production_hidden};
        wire [31:0] p = COMPACT ? 32'd4 : 32'd256;
        wire [31:0] vocabulary = COMPACT ? 32'd32 : 32'd262144;
        wire [31:0] q = COMPACT ? 32'd2 : 32'd8;
        wire [31:0] k = COMPACT || model == 1 ? 32'd1 : 32'd2;
        wire [31:0] d = COMPACT ? (is_global ? 32'd8 : 32'd4) :
            (is_global ? 32'd512 : 32'd256);
        wire [31:0] intermediate = COMPACT ?
            (model == 1 && layer >= 15 ? 32'd32 : 32'd16) :
            {18'd0, production_intermediate};

        always @* begin
            valid_hold = 0;
            matrix_type = 0;
            clipped = 0;
            clip_scalar = 0;
            type_hold = 0;
            rank_hold = 1;
            d0 = 1;
            d1 = 1;
            d2 = 1;
            d3 = 1;
            rows_hold = 1;
            columns_hold = 1;
            count_hold = 0;
            base_kind = kind;
            if (rst_n && (model == 1 || model == 2) && precision <= 1) begin
                case (image_class)
                    0: begin
                        count_hold = model == 1 ? 540 : 665;
                        if (layer == 16'hffff) begin
                            case (kind)
                                16'h0000: begin
                                    valid_hold = 1;
                                    matrix_type = 1;
                                    rank_hold = 2;
                                    d0 = vocabulary;
                                    d1 = h;
                                end
                                16'h0001: begin
                                    valid_hold = 1;
                                    matrix_type = 1;
                                    rank_hold = 2;
                                    d0 = vocabulary;
                                    d1 = {24'd0, layers} * p;
                                end
                                16'h0002: begin
                                    valid_hold = 1;
                                    matrix_type = 1;
                                    rank_hold = 2;
                                    d0 = {24'd0, layers} * p;
                                    d1 = h;
                                end
                                16'h0003: begin valid_hold = 1; d0 = p; end
                                16'h0004: begin valid_hold = 1; d0 = h; end
                                default: valid_hold = 0;
                            endcase
                        end else if (layer < {8'd0, layers}) begin
                            case (kind)
                                16'h0100, 16'h0107, 16'h0108,
                                16'h010c, 16'h010f: begin valid_hold = 1; d0 = h; end
                                16'h0101: begin
                                    valid_hold = 1; matrix_type = 1; rank_hold = 2;
                                    d0 = q*d; d1 = h;
                                end
                                16'h0102: begin valid_hold = 1; d0 = d; end
                                16'h0103, 16'h0105: begin
                                    valid_hold = layer < {8'd0, owners};
                                    matrix_type = 1; rank_hold = 2;
                                    d0 = k*d; d1 = h;
                                end
                                16'h0104: begin
                                    valid_hold = layer < {8'd0, owners}; d0 = d;
                                end
                                16'h0106: begin
                                    valid_hold = 1; matrix_type = 1; rank_hold = 2;
                                    d0 = h; d1 = q*d;
                                end
                                16'h0109, 16'h010a: begin
                                    valid_hold = 1; matrix_type = 1; rank_hold = 2;
                                    d0 = intermediate; d1 = h;
                                end
                                16'h010b: begin
                                    valid_hold = 1; matrix_type = 1; rank_hold = 2;
                                    d0 = h; d1 = intermediate;
                                end
                                16'h010d: begin
                                    valid_hold = 1; matrix_type = 1; rank_hold = 2;
                                    d0 = p; d1 = h;
                                end
                                16'h010e: begin
                                    valid_hold = 1; matrix_type = 1; rank_hold = 2;
                                    d0 = h; d1 = p;
                                end
                                16'h0110: begin valid_hold = 1; rank_hold = 0; end
                                default: valid_hold = 0;
                            endcase
                        end
                    end
                    1: begin
                        count_hold = 659;
                        if (kind[15:12] >= 5 && kind[15:12] <= 8) begin
                            base_kind = {4'h1, kind[11:0]};
                            clip_scalar = 1;
                        end
                        if (layer == 16'hffff && !clip_scalar) begin
                            case (kind)
                                16'h1000: begin
                                    valid_hold = 1; matrix_type = 1; rank_hold = 2;
                                    d0 = 768; d1 = 768;
                                end
                                16'h1001: begin
                                    valid_hold = 1; rank_hold = 3;
                                    d0 = 2; d1 = 10240; d2 = 768;
                                end
                                16'h1200: begin
                                    valid_hold = 1; matrix_type = 1; rank_hold = 2;
                                    d0 = h; d1 = 768;
                                end
                                default: valid_hold = 0;
                            endcase
                        end else if (layer < 16) begin
                            case (base_kind)
                                16'h1100, 16'h1107, 16'h1108, 16'h110c:
                                    begin valid_hold = 1; d0 = 768; end
                                16'h1102, 16'h1104: begin valid_hold = 1; d0 = 64; end
                                16'h1101, 16'h1103, 16'h1105, 16'h1106: begin
                                    valid_hold = 1; matrix_type = 1; clipped = 1;
                                    rank_hold = 2; d0 = 768; d1 = 768;
                                end
                                16'h1109, 16'h110a: begin
                                    valid_hold = 1; matrix_type = 1; clipped = 1;
                                    rank_hold = 2; d0 = 3072; d1 = 768;
                                end
                                16'h110b: begin
                                    valid_hold = 1; matrix_type = 1; clipped = 1;
                                    rank_hold = 2; d0 = 768; d1 = 3072;
                                end
                                default: valid_hold = 0;
                            endcase
                        end
                    end
                    2: begin
                        count_hold = 752;
                        if (kind[15:12] >= 6 && kind[15:12] <= 9) begin
                            base_kind = {4'h2, kind[11:0]};
                            clip_scalar = 1;
                        end
                        if (layer == 16'hffff && !clip_scalar) begin
                            case (kind)
                                16'h2000: begin
                                    valid_hold = 1; matrix_type = 1; rank_hold = 4;
                                    d0 = 128; d1 = 1; d2 = 3; d3 = 3;
                                end
                                16'h2001: begin valid_hold = 1; d0 = 128; end
                                16'h2002: begin
                                    valid_hold = 1; matrix_type = 1; rank_hold = 4;
                                    d0 = 32; d1 = 128; d2 = 3; d3 = 3;
                                end
                                16'h2003: begin valid_hold = 1; d0 = 32; end
                                16'h2004: begin
                                    valid_hold = 1; matrix_type = 1; rank_hold = 2;
                                    d0 = 1024; d1 = 1024;
                                end
                                16'h2200: begin
                                    valid_hold = 1; matrix_type = 1; rank_hold = 2;
                                    d0 = 1536; d1 = 1024;
                                end
                                16'h2201: begin valid_hold = 1; d0 = 1536; end
                                16'h2202: begin
                                    valid_hold = 1; matrix_type = 1; rank_hold = 2;
                                    d0 = h; d1 = 1536;
                                end
                                default: valid_hold = 0;
                            endcase
                        end else if (layer < 12) begin
                            case (base_kind)
                                16'h2100, 16'h2103, 16'h2104, 16'h210b, 16'h210c,
                                16'h210f, 16'h2111, 16'h2114, 16'h2115:
                                    begin valid_hold = 1; d0 = 1024; end
                                16'h2109: begin valid_hold = 1; d0 = 128; end
                                16'h2101, 16'h2112: begin
                                    valid_hold = 1; matrix_type = 1; clipped = 1;
                                    rank_hold = 2; d0 = 4096; d1 = 1024;
                                end
                                16'h2102, 16'h2113: begin
                                    valid_hold = 1; matrix_type = 1; clipped = 1;
                                    rank_hold = 2; d0 = 1024; d1 = 4096;
                                end
                                16'h2105, 16'h2106, 16'h2107, 16'h210a, 16'h2110: begin
                                    valid_hold = 1; matrix_type = 1; clipped = 1;
                                    rank_hold = 2; d0 = 1024; d1 = 1024;
                                end
                                16'h2108: begin
                                    valid_hold = 1; matrix_type = 1;
                                    rank_hold = 2; d0 = 1024; d1 = 1024;
                                end
                                16'h210d: begin
                                    valid_hold = 1; matrix_type = 1; clipped = 1;
                                    rank_hold = 2; d0 = 2048; d1 = 1024;
                                end
                                16'h210e: begin
                                    valid_hold = 1; matrix_type = 1; rank_hold = 3;
                                    d0 = 1024; d1 = 1; d2 = 5;
                                end
                                default: valid_hold = 0;
                            endcase
                        end
                    end
                    3: begin
                        count_hold = 2;
                        if (layer == 16'hffff && input_items != 0) begin
                            if (!input_audio) begin
                                case (kind)
                                    16'h3000: begin
                                        valid_hold = 1; rank_hold = 2;
                                        d0 = input_items; d1 = 768;
                                    end
                                    16'h3001: begin
                                        valid_hold = 1; type_hold = 3; rank_hold = 2;
                                        d0 = input_items; d1 = 2;
                                    end
                                    default: valid_hold = 0;
                                endcase
                            end else begin
                                case (kind)
                                    16'h3010: begin
                                        valid_hold = 1; rank_hold = 2;
                                        d0 = input_items; d1 = 128;
                                    end
                                    16'h3011: begin
                                        valid_hold = 1; type_hold = 2; d0 = input_items;
                                    end
                                    default: valid_hold = 0;
                                endcase
                            end
                        end
                    end
                    default: valid_hold = 0;
                endcase
                if (clip_scalar) begin
                    valid_hold = valid_hold && clipped;
                    matrix_type = 0;
                    rank_hold = 0;
                    d0 = 1; d1 = 1; d2 = 1; d3 = 1;
                end
                if (matrix_type)
                    type_hold = {6'd0, precision};
                if (rank_hold <= 1) begin
                    rows_hold = 1;
                    columns_hold = d0;
                end else if (matrix_type && rank_hold > 2) begin
                    rows_hold = d0;
                    columns_hold = d1*d2*d3;
                end else if (rank_hold == 3) begin
                    rows_hold = d0*d1;
                    columns_hold = d2;
                end else begin
                    rows_hold = d0;
                    columns_hold = d1;
                end
            end
        end

        assign valid = rst_n && valid_hold;
        assign tensor_type = rst_n ? type_hold : 8'd0;
        assign rank = rst_n ? rank_hold : 8'd0;
        assign dim0 = rst_n ? d0 : 32'd0;
        assign dim1 = rst_n ? d1 : 32'd0;
        assign dim2 = rst_n ? d2 : 32'd0;
        assign dim3 = rst_n ? d3 : 32'd0;
        assign rows = rst_n ? rows_hold : 32'd0;
        assign columns = rst_n ? columns_hold : 32'd0;
        assign entry_count = rst_n ? count_hold : 32'd0;
    end endgenerate
endmodule
