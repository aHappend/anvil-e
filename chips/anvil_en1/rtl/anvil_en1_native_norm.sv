module anvil_en1_native_norm (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] model, precision, image_class,
    input wire [15:0] tensor_kind, tensor_layer,
    input wire [31:0] vector_length,
    input wire [63:0] weights_base,
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
    output wire output_valid,
    input wire output_ready,
    output wire [31:0] output_index,
    output wire [15:0] output_data,
    output wire output_last,
    output wire done_valid,
    input wire done_ready,
    output wire [3:0] done_error,
    output wire [63:0] controller_bytes
);
    localparam [3:0] IDLE = 0, VALIDATE = 1, LOOKUP_START = 2,
        LOOKUP_WAIT = 3, NORM_START = 4, NORM_WAIT = 5,
        PUBLISH = 6, RESPONSE = 7;
    localparam [2:0] SCALE_IDLE = 0, SCALE_START = 1, SCALE_WAIT = 2,
        SCALE_REGISTER = 3, SCALE_RESPONSE = 4;
    reg [3:0] state;
    reg [2:0] scale_state;
    reg [1:0] model_hold, precision_hold, class_hold;
    reg [15:0] kind_hold, layer_hold;
    reg [31:0] length_hold, columns_hold, stride_hold, index_hold;
    reg [63:0] weights_hold, base_hold, bytes_hold;
    reg [15:0] scale_hold;
    reg [3:0] error_hold, scale_error_hold;
    wire vision_norm = class_hold == 1 && layer_hold < 16 &&
        (kind_hold == 16'h1100 || kind_hold == 16'h1107 ||
         kind_hold == 16'h1108 || kind_hold == 16'h110c);
    wire audio_layer_norm = class_hold == 2 && layer_hold == 16'hffff &&
        (kind_hold == 16'h2001 || kind_hold == 16'h2003);
    wire audio_rms_norm = class_hold == 2 && layer_hold < 12 &&
        (kind_hold == 16'h2100 || kind_hold == 16'h2103 ||
         kind_hold == 16'h2104 || kind_hold == 16'h210b ||
         kind_hold == 16'h210c || kind_hold == 16'h210f ||
         kind_hold == 16'h2111 || kind_hold == 16'h2114 ||
         kind_hold == 16'h2115);
    wire legal_kind = vision_norm || audio_layer_norm || audio_rms_norm;
    wire [31:0] expected_length = vision_norm ? 32'd768 :
        (audio_layer_norm ? (kind_hold == 16'h2001 ? 32'd128 : 32'd32) : 32'd1024);
    wire lookup_selected = rst_n && (state == LOOKUP_START || state == LOOKUP_WAIT);
    wire norm_selected = rst_n && (state == NORM_START || state == NORM_WAIT);
    wire lookup_ready, lookup_valid, lookup_cmd_valid, lookup_result_ready;
    wire [63:0] lookup_addr, lookup_base, lookup_bytes;
    wire [31:0] lookup_rows, lookup_columns, lookup_stride;
    wire [7:0] lookup_type;
    wire [3:0] lookup_error;
    wire [63:0] primitive_directory_bytes, primitive_norm_bytes, primitive_weight_bytes;
    wire [63:0] primitive_fp_bytes;
    wire fp_ready, fp_valid;
    wire [31:0] fp_data;
    wire [3:0] fp_error;
    wire scale_phase = scale_state == SCALE_START || scale_state == SCALE_WAIT;
    wire norm_arithmetic_valid, norm_arithmetic_result_ready;
    wire weight_arithmetic_valid, weight_arithmetic_result_ready;
    wire [2:0] norm_arithmetic_operation, weight_arithmetic_operation;
    wire [31:0] norm_arithmetic_a, norm_arithmetic_b;
    wire [31:0] weight_arithmetic_a, weight_arithmetic_b;
    anvil_en1_tensor_image directory (
        .controller_bytes(primitive_directory_bytes),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == LOOKUP_START), .start_ready(lookup_ready),
        .model(model_hold), .precision(precision_hold), .image_class(class_hold),
        .input_audio(1'b0), .input_items(32'd0), .image_base(weights_hold),
        .tensor_kind(kind_hold), .tensor_layer(layer_hold),
        .cmd_valid(lookup_cmd_valid), .cmd_ready(lookup_selected && cmd_ready),
        .cmd_write(), .cmd_addr(lookup_addr), .cmd_wdata(),
        .result_valid(lookup_selected && result_valid), .result_ready(lookup_result_ready),
        .result_data(result_data), .result_error(result_error),
        .done_valid(lookup_valid), .done_ready(rst_n && state == LOOKUP_WAIT),
        .done_base(lookup_base), .done_bytes(lookup_bytes), .done_rows(lookup_rows),
        .done_columns(lookup_columns), .done_stride(lookup_stride),
        .done_type(lookup_type), .done_error(lookup_error)
    );
    wire norm_ready, norm_valid, norm_source_valid, norm_source_rsp_ready;
    wire norm_scale_valid, norm_scale_rsp_ready;
    wire [31:0] norm_source_index, norm_scale_index;
    wire [3:0] norm_error;
    anvil_en1_norm #(.EXTERNAL_FP(1)) norm (
        .controller_bytes(primitive_norm_bytes),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == NORM_START), .start_ready(norm_ready),
        .layer_norm(audio_layer_norm), .learned_scale(1'b1),
        .vector_length(length_hold), .epsilon(32'h358637bd),
        .source_valid(norm_source_valid), .source_ready(norm_selected && source_ready),
        .source_index(norm_source_index),
        .source_rsp_valid(norm_selected && source_rsp_valid),
        .source_rsp_ready(norm_source_rsp_ready), .source_rsp_data(source_rsp_data),
        .source_rsp_error(source_rsp_error),
        .scale_valid(norm_scale_valid),
        .scale_ready(rst_n && state == NORM_WAIT && scale_state == SCALE_IDLE),
        .scale_index(norm_scale_index),
        .scale_rsp_valid(rst_n && scale_state == SCALE_RESPONSE),
        .scale_rsp_ready(norm_scale_rsp_ready), .scale_rsp_data(scale_hold),
        .scale_rsp_error(scale_error_hold != 0),
        .normalized_valid(output_valid), .normalized_ready(norm_selected && output_ready),
        .normalized_index(output_index), .normalized_data(output_data),
        .normalized_last(output_last), .done_valid(norm_valid),
        .done_ready(rst_n && state == NORM_WAIT && scale_state == SCALE_IDLE),
        .done_error(norm_error),
        .arithmetic_valid(norm_arithmetic_valid),
        .arithmetic_ready(norm_selected && !scale_phase && fp_ready),
        .arithmetic_operation(norm_arithmetic_operation),
        .arithmetic_a(norm_arithmetic_a), .arithmetic_b(norm_arithmetic_b),
        .arithmetic_result_valid(norm_selected && !scale_phase && fp_valid),
        .arithmetic_result_ready(norm_arithmetic_result_ready),
        .arithmetic_result_data(fp_data), .arithmetic_result_error(fp_error)
    );
    wire weight_ready, weight_valid, weight_cmd_valid, weight_result_ready;
    wire [63:0] weight_addr;
    wire [31:0] weight_data;
    wire [3:0] weight_error;
    anvil_en1_weight_read #(.EXTERNAL_FP(1)) scales (
        .controller_bytes(primitive_weight_bytes),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && scale_state == SCALE_START), .start_ready(weight_ready),
        .precision(2'd0), .tensor_base(base_hold), .tensor_bytes(bytes_hold),
        .tensor_rows(32'd1), .tensor_columns(columns_hold), .row_stride(stride_hold),
        .row_index(32'd0), .column_index(index_hold),
        .cmd_valid(weight_cmd_valid), .cmd_ready(norm_selected && cmd_ready),
        .cmd_write(), .cmd_addr(weight_addr), .cmd_wdata(),
        .result_valid(norm_selected && result_valid), .result_ready(weight_result_ready),
        .result_data(result_data), .result_error(result_error),
        .done_valid(weight_valid), .done_ready(rst_n && scale_state == SCALE_WAIT),
        .done_data(weight_data), .done_error(weight_error),
        .arithmetic_valid(weight_arithmetic_valid),
        .arithmetic_ready(scale_phase && fp_ready),
        .arithmetic_operation(weight_arithmetic_operation),
        .arithmetic_a(weight_arithmetic_a), .arithmetic_b(weight_arithmetic_b),
        .arithmetic_result_valid(scale_phase && fp_valid),
        .arithmetic_result_ready(weight_arithmetic_result_ready),
        .arithmetic_result_data(fp_data), .arithmetic_result_error(fp_error)
    );
    anvil_en1_fp32 arithmetic (
        .controller_bytes(primitive_fp_bytes),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && norm_selected &&
            (scale_phase ? weight_arithmetic_valid : norm_arithmetic_valid)),
        .start_ready(fp_ready),
        .operation(scale_phase ? weight_arithmetic_operation : norm_arithmetic_operation),
        .operand_a(scale_phase ? weight_arithmetic_a : norm_arithmetic_a),
        .operand_b(scale_phase ? weight_arithmetic_b : norm_arithmetic_b),
        .done_valid(fp_valid),
        .done_ready(rst_n && norm_selected &&
            (scale_phase ? weight_arithmetic_result_ready : norm_arithmetic_result_ready)),
        .done_data(fp_data), .done_error(fp_error)
    );
    assign start_ready = rst_n && state == IDLE;
    assign source_valid = norm_selected && norm_source_valid;
    assign source_index = rst_n ? norm_source_index : 32'd0;
    assign source_rsp_ready = norm_selected && norm_source_rsp_ready;
    assign cmd_valid = lookup_selected ? lookup_cmd_valid :
        (norm_selected && weight_cmd_valid);
    assign cmd_write = 0;
    assign cmd_addr = !rst_n ? 64'd0 : (lookup_selected ? lookup_addr :
        (norm_selected ? weight_addr : 64'd0));
    assign cmd_wdata = 0;
    assign result_ready = lookup_selected ? lookup_result_ready :
        (norm_selected && weight_result_ready);
    assign done_valid = rst_n && state == RESPONSE;
    assign done_error = rst_n ? error_hold : 4'd0;
    localparam integer CONTROLLER_BITS = $bits(state) + $bits(scale_state) +
        $bits(model_hold) + $bits(precision_hold) + $bits(class_hold) +
        $bits(kind_hold) + $bits(layer_hold) + $bits(length_hold) +
        $bits(columns_hold) + $bits(stride_hold) + $bits(index_hold) +
        $bits(weights_hold) + $bits(base_hold) + $bits(bytes_hold) +
        $bits(scale_hold) + $bits(error_hold) + $bits(scale_error_hold);
    assign controller_bytes = !rst_n ? 64'd0 : 64'((CONTROLLER_BITS + 7) >> 3) +
        primitive_directory_bytes + primitive_norm_bytes + primitive_weight_bytes +
        primitive_fp_bytes;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scale_state <= SCALE_IDLE;
            index_hold <= 0;
            scale_hold <= 0;
            scale_error_hold <= 0;
        end else begin
            case (scale_state)
                SCALE_IDLE: if (state == NORM_WAIT && norm_scale_valid) begin
                    index_hold <= norm_scale_index;
                    scale_hold <= 0;
                    scale_error_hold <= 0;
                    scale_state <= SCALE_START;
                end
                SCALE_START: if (weight_ready)
                    scale_state <= SCALE_WAIT;
                SCALE_WAIT: if (weight_valid) begin
                    scale_hold <= weight_error == 0 ? weight_data[31:16] : 16'd0;
                    scale_error_hold <= weight_error;
                    scale_state <= SCALE_REGISTER;
                end
                SCALE_REGISTER: scale_state <= SCALE_RESPONSE;
                SCALE_RESPONSE: if (norm_scale_rsp_ready)
                    scale_state <= SCALE_IDLE;
                default: begin
                    scale_error_hold <= 7;
                    scale_hold <= 0;
                    scale_state <= SCALE_REGISTER;
                end
            endcase
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            model_hold <= 0;
            precision_hold <= 0;
            class_hold <= 0;
            kind_hold <= 0;
            layer_hold <= 0;
            length_hold <= 0;
            columns_hold <= 0;
            stride_hold <= 0;
            weights_hold <= 0;
            base_hold <= 0;
            bytes_hold <= 0;
            error_hold <= 0;
        end else begin
            case (state)
                IDLE: if (start_valid && start_ready) begin
                    model_hold <= model;
                    precision_hold <= precision;
                    class_hold <= image_class;
                    kind_hold <= tensor_kind;
                    layer_hold <= tensor_layer;
                    length_hold <= vector_length;
                    weights_hold <= weights_base;
                    error_hold <= 0;
                    state <= VALIDATE;
                end
                VALIDATE: begin
                    if ((model_hold != 1 && model_hold != 2) || precision_hold > 1) begin
                        error_hold <= 6;
                        state <= PUBLISH;
                    end else if (!legal_kind || length_hold != expected_length ||
                        weights_hold[1:0] != 0) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else
                        state <= LOOKUP_START;
                end
                LOOKUP_START: if (lookup_ready)
                    state <= LOOKUP_WAIT;
                LOOKUP_WAIT: if (lookup_valid) begin
                    if (lookup_error != 0) begin
                        error_hold <= lookup_error;
                        state <= PUBLISH;
                    end else if (lookup_rows != 1 || lookup_columns != length_hold ||
                        lookup_type != 0) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else begin
                        base_hold <= lookup_base;
                        bytes_hold <= lookup_bytes;
                        columns_hold <= lookup_columns;
                        stride_hold <= lookup_stride;
                        state <= NORM_START;
                    end
                end
                NORM_START: if (norm_ready)
                    state <= NORM_WAIT;
                NORM_WAIT: begin
                    if (scale_state == SCALE_WAIT && weight_valid &&
                        weight_error != 0 && error_hold == 0)
                        error_hold <= weight_error;
                    if (norm_valid && scale_state == SCALE_IDLE) begin
                        if (error_hold == 0)
                            error_hold <= norm_error;
                        state <= PUBLISH;
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
