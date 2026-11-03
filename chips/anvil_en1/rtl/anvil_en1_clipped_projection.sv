module anvil_en1_clipped_projection #(
    parameter integer COMPACT = 0,
    parameter integer EXTERNAL_FP = 0
) (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] model, precision, image_class,
    input wire [63:0] image_base,
    input wire [15:0] tensor_kind, tensor_layer,
    input wire [31:0] row_index,
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
    output wire [63:0] controller_bytes, clamp_controller_bytes,
    output wire arithmetic_valid,
    input wire arithmetic_ready,
    output wire [2:0] arithmetic_operation,
    output wire [31:0] arithmetic_a, arithmetic_b,
    input wire arithmetic_result_valid,
    output wire arithmetic_result_ready,
    input wire [31:0] arithmetic_result_data,
    input wire [3:0] arithmetic_result_error
);
    localparam [4:0] IDLE = 0, VALIDATE = 1, IMAGE_START = 2,
        IMAGE_WAIT = 3, BOUND_SEND = 4, BOUND_WAIT = 5, BOUND_REGISTER = 6,
        BOUND_ADVANCE = 7, INPUT_VALIDATE_START = 8, INPUT_VALIDATE_WAIT = 9,
        OUTPUT_VALIDATE_START = 10, OUTPUT_VALIDATE_WAIT = 11,
        PROJECTION_START = 12, PROJECTION_WAIT = 13,
        OUTPUT_START = 14, OUTPUT_WAIT = 15, PUBLISH = 16, RESPONSE = 17;
    localparam [2:0] S_IDLE = 0, S_SEND = 1, S_WAIT = 2, S_REGISTER = 3,
        S_CLAMP_START = 4, S_CLAMP_WAIT = 5, S_RESPONSE = 6;
    reg [4:0] state;
    reg [2:0] source_state, image_index;
    reg [1:0] model_hold, precision_hold, class_hold;
    reg [63:0] image_base_hold, matrix_base, matrix_bytes, bound_address;
    reg [15:0] kind_hold, layer_hold;
    reg [31:0] row_hold, matrix_rows, matrix_columns, matrix_stride;
    reg [15:0] input_minimum, input_maximum, output_minimum, output_maximum;
    reg [31:0] bound_word, source_index_hold, output_hold;
    reg [15:0] source_data_hold, clipped_source_hold, projected_hold;
    reg bound_error_hold, source_error_hold, clipped_source_error;
    reg [3:0] error_hold;

    initial begin
        if (COMPACT != 0 && COMPACT != 1)
            $fatal(1, "PARAMETER ERROR: COMPACT must be 0 or 1");
        if (EXTERNAL_FP != 0 && EXTERNAL_FP != 1)
            $fatal(1, "PARAMETER ERROR: EXTERNAL_FP must be 0 or 1");
    end

    wire matrix_schema_valid, clip_schema_valid;
    wire [31:0] schema_rows;
    wire [15:0] clip_kind = kind_hold + 16'h4000;
    wire [15:0] selected_kind = image_index == 4 ? kind_hold :
        clip_kind + {2'd0, image_index[1:0], 12'd0};
    anvil_en1_tensor_shape #(.COMPACT(COMPACT)) matrix_schema (
        .rst_n(rst_n), .model(model_hold), .precision(precision_hold),
        .image_class(class_hold), .input_audio(1'b0), .input_items(32'd0),
        .kind(kind_hold), .layer(layer_hold), .valid(matrix_schema_valid),
        .tensor_type(), .rank(), .dim0(), .dim1(), .dim2(), .dim3(),
        .rows(schema_rows), .columns(), .entry_count()
    );
    anvil_en1_tensor_shape #(.COMPACT(COMPACT)) clip_schema (
        .rst_n(rst_n), .model(model_hold), .precision(precision_hold),
        .image_class(class_hold), .input_audio(1'b0), .input_items(32'd0),
        .kind(clip_kind), .layer(layer_hold), .valid(clip_schema_valid),
        .tensor_type(), .rank(), .dim0(), .dim1(), .dim2(), .dim3(),
        .rows(), .columns(), .entry_count()
    );

    wire image_ready, image_valid, image_cmd_valid, image_result_ready;
    wire [63:0] image_cmd_addr, image_done_base, image_done_bytes;
    wire [31:0] image_done_rows, image_done_columns, image_done_stride;
    wire [7:0] image_done_type;
    wire [3:0] image_error;
    wire image_selected = rst_n && (state == IMAGE_START || state == IMAGE_WAIT);
    wire [63:0] primitive_directory_bytes, primitive_projection_bytes;
    anvil_en1_tensor_image #(.COMPACT(COMPACT)) directory (
        .controller_bytes(primitive_directory_bytes),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == IMAGE_START), .start_ready(image_ready),
        .model(model_hold), .precision(precision_hold), .image_class(class_hold),
        .input_audio(1'b0), .input_items(32'd0), .image_base(image_base_hold),
        .tensor_kind(selected_kind), .tensor_layer(layer_hold),
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
    wire projection_selected = rst_n &&
        (state == PROJECTION_START || state == PROJECTION_WAIT);
    anvil_en1_projection #(.EXTERNAL_FP(EXTERNAL_FP)) projection (
        .controller_bytes(primitive_projection_bytes),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == PROJECTION_START), .start_ready(projection_ready),
        .precision(precision_hold), .tensor_base(matrix_base), .tensor_bytes(matrix_bytes),
        .tensor_rows(matrix_rows), .tensor_columns(matrix_columns),
        .row_stride(matrix_stride), .row_index(row_hold),
        .source_valid(projection_source_valid),
        .source_ready(rst_n && state == PROJECTION_WAIT && source_state == S_IDLE),
        .source_index(projection_source_index),
        .source_rsp_valid(rst_n && state == PROJECTION_WAIT && source_state == S_RESPONSE),
        .source_rsp_ready(projection_source_rsp_ready),
        .source_rsp_data(clipped_source_hold), .source_rsp_error(clipped_source_error),
        .cmd_valid(projection_cmd_valid), .cmd_ready(projection_selected && cmd_ready),
        .cmd_write(), .cmd_addr(projection_cmd_addr), .cmd_wdata(),
        .result_valid(projection_selected && result_valid),
        .result_ready(projection_result_ready), .result_data(result_data),
        .result_error(result_error),
        .done_valid(projection_valid),
        .done_ready(rst_n && state == PROJECTION_WAIT && source_state == S_IDLE),
        .done_data(projection_data), .done_error(projection_error),
        .arithmetic_valid(arithmetic_valid), .arithmetic_ready(arithmetic_ready),
        .arithmetic_operation(arithmetic_operation),
        .arithmetic_a(arithmetic_a), .arithmetic_b(arithmetic_b),
        .arithmetic_result_valid(arithmetic_result_valid),
        .arithmetic_result_ready(arithmetic_result_ready),
        .arithmetic_result_data(arithmetic_result_data),
        .arithmetic_result_error(arithmetic_result_error)
    );

    wire clamp_ready, clamp_valid;
    wire [15:0] clamp_data;
    wire [3:0] clamp_error;
    wire clamp_input_interval = state == INPUT_VALIDATE_START ||
        state == INPUT_VALIDATE_WAIT || source_state == S_CLAMP_START ||
        source_state == S_CLAMP_WAIT;
    wire [15:0] clamp_value = source_state == S_CLAMP_START ||
        source_state == S_CLAMP_WAIT ? source_data_hold :
        (state == OUTPUT_START || state == OUTPUT_WAIT ? projected_hold : 16'd0);
    anvil_en1_bf16_clamp clamp (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && (state == INPUT_VALIDATE_START ||
            state == OUTPUT_VALIDATE_START || state == OUTPUT_START ||
            (state == PROJECTION_WAIT && source_state == S_CLAMP_START))),
        .start_ready(clamp_ready), .value(clamp_value),
        .minimum(clamp_input_interval ? input_minimum : output_minimum),
        .maximum(clamp_input_interval ? input_maximum : output_maximum),
        .done_valid(clamp_valid),
        .done_ready(rst_n && (state == INPUT_VALIDATE_WAIT ||
            state == OUTPUT_VALIDATE_WAIT || state == OUTPUT_WAIT ||
            (state == PROJECTION_WAIT && source_state == S_CLAMP_WAIT))),
        .done_data(clamp_data), .done_error(clamp_error),
        .controller_bytes(clamp_controller_bytes)
    );

    wire [64:0] bound_end = {1'b0, image_done_base} + 65'd4;
    assign start_ready = rst_n && state == IDLE;
    assign source_valid = rst_n && state == PROJECTION_WAIT && source_state == S_SEND;
    assign source_index = rst_n ? source_index_hold : 32'd0;
    assign source_rsp_ready = rst_n && state == PROJECTION_WAIT && source_state == S_WAIT;
    assign cmd_valid = rst_n && (image_selected ? image_cmd_valid :
        (projection_selected ? projection_cmd_valid : state == BOUND_SEND));
    assign cmd_write = 0;
    assign cmd_addr = !rst_n ? 64'd0 : (image_selected ? image_cmd_addr :
        (projection_selected ? projection_cmd_addr : bound_address));
    assign cmd_wdata = 0;
    assign result_ready = rst_n && (image_selected ? image_result_ready :
        (projection_selected ? projection_result_ready : state == BOUND_WAIT));
    assign done_valid = rst_n && state == RESPONSE;
    assign done_data = rst_n ? output_hold : 32'd0;
    assign done_error = rst_n ? error_hold : 4'd0;
    wire [31:0] CONTROLLER_BITS =
        $bits(state) + $bits(source_state) + $bits(image_index) +
        $bits(model_hold) + $bits(precision_hold) + $bits(class_hold) +
        $bits(image_base_hold) + $bits(matrix_base) + $bits(matrix_bytes) +
        $bits(bound_address) + $bits(kind_hold) + $bits(layer_hold) +
        $bits(row_hold) + $bits(matrix_rows) + $bits(matrix_columns) +
        $bits(matrix_stride) + $bits(input_minimum) + $bits(input_maximum) +
        $bits(output_minimum) + $bits(output_maximum) + $bits(bound_word) +
        $bits(source_index_hold) + $bits(output_hold) + $bits(source_data_hold) +
        $bits(clipped_source_hold) + $bits(projected_hold) + $bits(bound_error_hold) +
        $bits(source_error_hold) + $bits(clipped_source_error) + $bits(error_hold);
    assign controller_bytes = !rst_n ? 64'd0 : 64'((CONTROLLER_BITS + 7) >> 3) +
        primitive_directory_bytes + primitive_projection_bytes;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            source_state <= S_IDLE;
            source_index_hold <= 0;
            source_data_hold <= 0;
            clipped_source_hold <= 0;
            source_error_hold <= 0;
            clipped_source_error <= 0;
        end else begin
            case (source_state)
                S_IDLE: if (state == PROJECTION_WAIT && projection_source_valid) begin
                    source_index_hold <= projection_source_index;
                    source_error_hold <= 0;
                    clipped_source_error <= 0;
                    source_state <= S_SEND;
                end
                S_SEND: if (source_valid && source_ready)
                    source_state <= S_WAIT;
                S_WAIT: if (source_rsp_valid && source_rsp_ready) begin
                    source_data_hold <= source_rsp_data;
                    source_error_hold <= source_rsp_error;
                    source_state <= S_REGISTER;
                end
                S_REGISTER: begin
                    if (source_error_hold) begin
                        clipped_source_hold <= 0;
                        clipped_source_error <= 1;
                        source_state <= S_RESPONSE;
                    end else
                        source_state <= S_CLAMP_START;
                end
                S_CLAMP_START: if (clamp_ready)
                    source_state <= S_CLAMP_WAIT;
                S_CLAMP_WAIT: if (clamp_valid) begin
                    clipped_source_hold <= clamp_data;
                    clipped_source_error <= clamp_error != 0;
                    source_state <= S_RESPONSE;
                end
                S_RESPONSE: if (state == PROJECTION_WAIT && projection_source_rsp_ready)
                    source_state <= S_IDLE;
                default: begin
                    clipped_source_hold <= 0;
                    clipped_source_error <= 1;
                    source_state <= S_RESPONSE;
                end
            endcase
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            image_index <= 0;
            model_hold <= 0;
            precision_hold <= 0;
            class_hold <= 0;
            image_base_hold <= 0;
            matrix_base <= 0;
            matrix_bytes <= 0;
            bound_address <= 0;
            kind_hold <= 0;
            layer_hold <= 0;
            row_hold <= 0;
            matrix_rows <= 0;
            matrix_columns <= 0;
            matrix_stride <= 0;
            input_minimum <= 0;
            input_maximum <= 0;
            output_minimum <= 0;
            output_maximum <= 0;
            bound_word <= 0;
            bound_error_hold <= 0;
            projected_hold <= 0;
            output_hold <= 0;
            error_hold <= 0;
        end else begin
            case (state)
                IDLE: if (start_valid && start_ready) begin
                    model_hold <= model;
                    precision_hold <= precision;
                    class_hold <= image_class;
                    image_base_hold <= image_base;
                    kind_hold <= tensor_kind;
                    layer_hold <= tensor_layer;
                    row_hold <= row_index;
                    image_index <= 0;
                    output_hold <= 0;
                    error_hold <= 0;
                    state <= VALIDATE;
                end
                VALIDATE: begin
                    if ((model_hold != 1 && model_hold != 2) || precision_hold > 1) begin
                        error_hold <= 6;
                        state <= PUBLISH;
                    end else if ((class_hold != 1 && class_hold != 2) ||
                        kind_hold[15:12] != (class_hold == 1 ? 4'h1 : 4'h2) ||
                        !matrix_schema_valid || !clip_schema_valid ||
                        row_hold >= schema_rows) begin
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
                    end else if (image_index == 4) begin
                        matrix_base <= image_done_base;
                        matrix_bytes <= image_done_bytes;
                        matrix_rows <= image_done_rows;
                        matrix_columns <= image_done_columns;
                        matrix_stride <= image_done_stride;
                        state <= INPUT_VALIDATE_START;
                    end else if (image_done_type != 0 || image_done_rows != 1 ||
                        image_done_columns != 1 || image_done_stride != 4 ||
                        image_done_bytes != 4 || image_done_base[1:0] != 0 ||
                        bound_end[64]) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else begin
                        bound_address <= image_done_base;
                        state <= BOUND_SEND;
                    end
                end
                BOUND_SEND: if (cmd_ready)
                    state <= BOUND_WAIT;
                BOUND_WAIT: if (result_valid && result_ready) begin
                    bound_word <= result_data;
                    bound_error_hold <= result_error;
                    state <= BOUND_REGISTER;
                end
                BOUND_REGISTER: begin
                    if (bound_error_hold) begin
                        error_hold <= 2;
                        state <= PUBLISH;
                    end else begin
                        case (image_index)
                            0: input_minimum <= bound_word[15:0];
                            1: input_maximum <= bound_word[15:0];
                            2: output_minimum <= bound_word[15:0];
                            3: output_maximum <= bound_word[15:0];
                            default: error_hold <= 7;
                        endcase
                        state <= BOUND_ADVANCE;
                    end
                end
                BOUND_ADVANCE: begin
                    if (error_hold != 0)
                        state <= PUBLISH;
                    else begin
                        image_index <= image_index + 1'b1;
                        state <= IMAGE_START;
                    end
                end
                INPUT_VALIDATE_START: if (clamp_ready)
                    state <= INPUT_VALIDATE_WAIT;
                INPUT_VALIDATE_WAIT: if (clamp_valid) begin
                    if (clamp_error != 0) begin
                        error_hold <= clamp_error;
                        state <= PUBLISH;
                    end else
                        state <= OUTPUT_VALIDATE_START;
                end
                OUTPUT_VALIDATE_START: if (clamp_ready)
                    state <= OUTPUT_VALIDATE_WAIT;
                OUTPUT_VALIDATE_WAIT: if (clamp_valid) begin
                    if (clamp_error != 0) begin
                        error_hold <= clamp_error;
                        state <= PUBLISH;
                    end else
                        state <= PROJECTION_START;
                end
                PROJECTION_START: if (projection_ready)
                    state <= PROJECTION_WAIT;
                PROJECTION_WAIT: if (projection_valid && source_state == S_IDLE) begin
                    if (projection_error != 0) begin
                        error_hold <= projection_error;
                        state <= PUBLISH;
                    end else begin
                        projected_hold <= projection_data[15:0];
                        state <= OUTPUT_START;
                    end
                end
                OUTPUT_START: if (clamp_ready)
                    state <= OUTPUT_WAIT;
                OUTPUT_WAIT: if (clamp_valid) begin
                    if (clamp_error != 0) begin
                        error_hold <= clamp_error;
                        output_hold <= 0;
                    end else
                        output_hold <= {16'd0, clamp_data};
                    state <= PUBLISH;
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
