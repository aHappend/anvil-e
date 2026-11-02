module anvil_en1_audio_output (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] model, precision,
    input wire [31:0] generation, token,
    input wire [63:0] audio_weights_base,
    output wire source_valid,
    input wire source_ready,
    output wire [1:0] source_model,
    output wire [31:0] source_generation, source_token, source_index,
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
    output wire weight_read_event,
    output wire [31:0] weight_read_bytes,
    output wire projection_event,
    output wire [31:0] projection_bytes,
    output wire [63:0] controller_bytes
);
    localparam [4:0] IDLE = 0, VALIDATE = 1, IMAGE_START = 2,
        IMAGE_WAIT = 3, PROJECTION_START = 4, PROJECTION_WAIT = 5,
        PROJECTION_CHECK = 6, BIAS_START = 7, BIAS_WAIT = 8, BIAS_CHECK = 9,
        NARROW = 10, OUTPUT_REGISTER = 11, EMIT = 12, ADVANCE = 13,
        FP_START = 14, FP_WAIT = 15, PUBLISH = 16, RESPONSE = 17;
    reg [4:0] state, fp_return;
    reg [1:0] model_hold, precision_hold;
    reg [31:0] generation_hold, token_hold, row, matrix_stride, bias_stride;
    reg [63:0] weights_hold, matrix_base, matrix_bytes, bias_base, bias_bytes;
    reg lookup_bias;
    reg [15:0] projection_hold, bias_hold, output_hold;
    reg [31:0] fp_a, fp_b, fp_value;
    reg [2:0] fp_op;
    reg [3:0] child_error_hold, error_hold;

    wire lookup_selected = rst_n && (state == IMAGE_START || state == IMAGE_WAIT);
    wire lookup_ready, lookup_valid, lookup_cmd_valid, lookup_result_ready;
    wire [63:0] lookup_addr, lookup_base, lookup_bytes;
    wire [31:0] lookup_rows, lookup_columns, lookup_stride;
    wire [7:0] lookup_type;
    wire [3:0] lookup_error;
    wire [63:0] primitive_directory_bytes, primitive_projection_bytes;
    wire [63:0] primitive_weight_bytes, primitive_fp_bytes;
    anvil_en1_tensor_image directory (
        .controller_bytes(primitive_directory_bytes),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == IMAGE_START), .start_ready(lookup_ready),
        .model(model_hold), .precision(precision_hold), .image_class(2'd2),
        .input_audio(1'b0), .input_items(32'd0), .image_base(weights_hold),
        .tensor_kind(lookup_bias ? 16'h2201 : 16'h2200), .tensor_layer(16'hffff),
        .cmd_valid(lookup_cmd_valid), .cmd_ready(lookup_selected && cmd_ready),
        .cmd_write(), .cmd_addr(lookup_addr), .cmd_wdata(),
        .result_valid(lookup_selected && result_valid), .result_ready(lookup_result_ready),
        .result_data(result_data), .result_error(result_error),
        .done_valid(lookup_valid), .done_ready(rst_n && state == IMAGE_WAIT),
        .done_base(lookup_base), .done_bytes(lookup_bytes), .done_rows(lookup_rows),
        .done_columns(lookup_columns), .done_stride(lookup_stride),
        .done_type(lookup_type), .done_error(lookup_error)
    );
    wire projection_selected = rst_n &&
        (state == PROJECTION_START || state == PROJECTION_WAIT);
    wire projection_ready, projection_valid, projection_cmd_valid, projection_result_ready;
    wire projection_source_valid, projection_source_rsp_ready;
    wire [31:0] projection_index, projection_data;
    wire [63:0] projection_addr;
    wire [3:0] projection_error;
    anvil_en1_projection projection (
        .controller_bytes(primitive_projection_bytes),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == PROJECTION_START), .start_ready(projection_ready),
        .precision(precision_hold), .tensor_base(matrix_base), .tensor_bytes(matrix_bytes),
        .tensor_rows(32'd1536), .tensor_columns(32'd1024),
        .row_stride(matrix_stride), .row_index(row),
        .source_valid(projection_source_valid), .source_ready(projection_selected && source_ready),
        .source_index(projection_index),
        .source_rsp_valid(projection_selected && source_rsp_valid),
        .source_rsp_ready(projection_source_rsp_ready),
        .source_rsp_data(source_rsp_data), .source_rsp_error(source_rsp_error),
        .cmd_valid(projection_cmd_valid), .cmd_ready(projection_selected && cmd_ready),
        .cmd_write(), .cmd_addr(projection_addr), .cmd_wdata(),
        .result_valid(projection_selected && result_valid),
        .result_ready(projection_result_ready), .result_data(result_data),
        .result_error(result_error), .done_valid(projection_valid),
        .done_ready(rst_n && state == PROJECTION_WAIT),
        .done_data(projection_data), .done_error(projection_error)
    );
    wire bias_selected = rst_n && (state == BIAS_START || state == BIAS_WAIT);
    wire bias_ready, bias_valid, bias_cmd_valid, bias_result_ready;
    wire [31:0] bias_data;
    wire [63:0] bias_addr;
    wire [3:0] bias_error;
    anvil_en1_weight_read bias_reader (
        .controller_bytes(primitive_weight_bytes),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == BIAS_START), .start_ready(bias_ready),
        .precision(2'd0), .tensor_base(bias_base), .tensor_bytes(bias_bytes),
        .tensor_rows(32'd1), .tensor_columns(32'd1536), .row_stride(bias_stride),
        .row_index(32'd0), .column_index(row),
        .cmd_valid(bias_cmd_valid), .cmd_ready(bias_selected && cmd_ready),
        .cmd_write(), .cmd_addr(bias_addr), .cmd_wdata(),
        .result_valid(bias_selected && result_valid), .result_ready(bias_result_ready),
        .result_data(result_data), .result_error(result_error),
        .done_valid(bias_valid), .done_ready(rst_n && state == BIAS_WAIT),
        .done_data(bias_data), .done_error(bias_error)
    );
    wire fp_ready, fp_valid;
    wire [31:0] fp_data;
    wire [3:0] fp_error;
    anvil_en1_fp32 arithmetic (
        .controller_bytes(primitive_fp_bytes),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == FP_START), .start_ready(fp_ready),
        .operation(fp_op), .operand_a(fp_a), .operand_b(fp_b),
        .done_valid(fp_valid), .done_ready(rst_n && state == FP_WAIT),
        .done_data(fp_data), .done_error(fp_error)
    );
    assign start_ready = rst_n && state == IDLE;
    assign source_valid = projection_selected && projection_source_valid;
    assign source_rsp_ready = projection_selected && projection_source_rsp_ready;
    assign source_model = rst_n ? model_hold : 2'd0;
    assign source_generation = rst_n ? generation_hold : 32'd0;
    assign source_token = rst_n ? token_hold : 32'd0;
    assign source_index = projection_selected ? projection_index : 32'd0;
    assign cmd_valid = lookup_selected ? lookup_cmd_valid :
        (projection_selected ? projection_cmd_valid : (bias_selected && bias_cmd_valid));
    assign cmd_write = 0;
    assign cmd_addr = !rst_n ? 64'd0 : (lookup_selected ? lookup_addr :
        (projection_selected ? projection_addr : (bias_selected ? bias_addr : 64'd0)));
    assign cmd_wdata = 0;
    assign result_ready = lookup_selected ? lookup_result_ready :
        (projection_selected ? projection_result_ready : (bias_selected && bias_result_ready));
    assign output_valid = rst_n && state == EMIT;
    assign output_index = rst_n ? row : 32'd0;
    assign output_data = rst_n ? output_hold : 16'd0;
    assign output_last = rst_n && state == EMIT && row == 1535;
    assign done_valid = rst_n && state == RESPONSE;
    assign done_error = rst_n ? error_hold : 4'd0;
    assign weight_read_event = cmd_valid && cmd_ready;
    assign weight_read_bytes = weight_read_event ? 32'd4 : 32'd0;
    assign projection_event = rst_n && state == PROJECTION_START && projection_ready;
    assign projection_bytes = projection_event ? matrix_stride : 32'd0;
    localparam integer CONTROLLER_BITS =
        $bits(state) + $bits(fp_return) + $bits(model_hold) + $bits(precision_hold) +
        $bits(generation_hold) + $bits(token_hold) + $bits(row) + $bits(matrix_stride) +
        $bits(bias_stride) + $bits(weights_hold) + $bits(matrix_base) +
        $bits(matrix_bytes) + $bits(bias_base) + $bits(bias_bytes) + $bits(lookup_bias) +
        $bits(projection_hold) + $bits(bias_hold) + $bits(output_hold) + $bits(fp_a) +
        $bits(fp_b) + $bits(fp_value) + $bits(fp_op) +
        $bits(child_error_hold) + $bits(error_hold);
    assign controller_bytes = !rst_n ? 64'd0 : 64'((CONTROLLER_BITS + 7) >> 3) +
        primitive_directory_bytes + primitive_projection_bytes +
        primitive_weight_bytes + primitive_fp_bytes;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            fp_return <= 0;
            model_hold <= 0;
            precision_hold <= 0;
            generation_hold <= 0;
            token_hold <= 0;
            row <= 0;
            matrix_stride <= 0;
            bias_stride <= 0;
            weights_hold <= 0;
            matrix_base <= 0;
            matrix_bytes <= 0;
            bias_base <= 0;
            bias_bytes <= 0;
            lookup_bias <= 0;
            projection_hold <= 0;
            bias_hold <= 0;
            output_hold <= 0;
            fp_a <= 0;
            fp_b <= 0;
            fp_value <= 0;
            fp_op <= 0;
            child_error_hold <= 0;
            error_hold <= 0;
        end else begin
            case (state)
                IDLE: if (start_valid && start_ready) begin
                    model_hold <= model;
                    precision_hold <= precision;
                    generation_hold <= generation;
                    token_hold <= token;
                    weights_hold <= audio_weights_base;
                    row <= 0;
                    lookup_bias <= 0;
                    projection_hold <= 0;
                    bias_hold <= 0;
                    output_hold <= 0;
                    child_error_hold <= 0;
                    error_hold <= 0;
                    state <= VALIDATE;
                end
                VALIDATE: begin
                    if ((model_hold != 1 && model_hold != 2) || precision_hold > 1) begin
                        error_hold <= 6;
                        state <= PUBLISH;
                    end else if (generation_hold == 0 || token_hold > 131071 ||
                        weights_hold[1:0] != 0) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else
                        state <= IMAGE_START;
                end
                IMAGE_START: if (lookup_ready)
                    state <= IMAGE_WAIT;
                IMAGE_WAIT: if (lookup_valid) begin
                    if (lookup_error != 0) begin
                        error_hold <= lookup_error;
                        state <= PUBLISH;
                    end else if (!lookup_bias) begin
                        if (lookup_rows != 1536 || lookup_columns != 1024 ||
                            lookup_type != {6'd0, precision_hold}) begin
                            error_hold <= 5;
                            state <= PUBLISH;
                        end else begin
                            matrix_base <= lookup_base;
                            matrix_bytes <= lookup_bytes;
                            matrix_stride <= lookup_stride;
                            lookup_bias <= 1;
                            state <= IMAGE_START;
                        end
                    end else if (lookup_rows != 1 || lookup_columns != 1536 ||
                        lookup_type != 0) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else begin
                        bias_base <= lookup_base;
                        bias_bytes <= lookup_bytes;
                        bias_stride <= lookup_stride;
                        state <= PROJECTION_START;
                    end
                end
                PROJECTION_START: if (projection_ready)
                    state <= PROJECTION_WAIT;
                PROJECTION_WAIT: if (projection_valid) begin
                    projection_hold <= projection_data[15:0];
                    child_error_hold <= projection_error;
                    state <= PROJECTION_CHECK;
                end
                PROJECTION_CHECK: begin
                    if (child_error_hold != 0) begin
                        error_hold <= child_error_hold;
                        state <= PUBLISH;
                    end else
                        state <= BIAS_START;
                end
                BIAS_START: if (bias_ready)
                    state <= BIAS_WAIT;
                BIAS_WAIT: if (bias_valid) begin
                    bias_hold <= bias_data[31:16];
                    child_error_hold <= bias_error;
                    state <= BIAS_CHECK;
                end
                BIAS_CHECK: begin
                    if (child_error_hold != 0) begin
                        error_hold <= child_error_hold;
                        state <= PUBLISH;
                    end else begin
                        fp_a <= {projection_hold, 16'd0};
                        fp_b <= {bias_hold, 16'd0};
                        fp_op <= 0;
                        fp_return <= NARROW;
                        state <= FP_START;
                    end
                end
                NARROW: begin
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
                    state <= ADVANCE;
                ADVANCE: begin
                    if (row == 1535)
                        state <= PUBLISH;
                    else begin
                        row <= row + 1'b1;
                        state <= PROJECTION_START;
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
