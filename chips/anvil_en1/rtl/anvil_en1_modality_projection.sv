module anvil_en1_modality_projection #(
    parameter integer COMPACT = 0
) (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] model, precision, image_class,
    input wire [31:0] generation, soft_token,
    input wire [63:0] weights_base,
    output wire source_valid,
    input wire source_ready,
    output wire [31:0] source_generation, source_token, source_index,
    output wire [1:0] source_model, source_class,
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
    output wire [63:0] vector_live_bytes, vector_physical_bytes, controller_bytes
);
    localparam [4:0] IDLE = 0, VALIDATE = 1, IMAGE_START = 2,
        IMAGE_WAIT = 3, NORM_START = 4, NORM_WAIT = 5, NORM_CHECK = 6,
        PROJECTION_START = 7, PROJECTION_WAIT = 8, OUTPUT_REGISTER = 9,
        EMIT = 10, ADVANCE = 11, PUBLISH = 12, RESPONSE = 13;
    localparam [2:0] S_IDLE = 0, S_VALIDATE = 1, S_READ = 2,
        S_CAPTURE = 3, S_RESPONSE = 4;
    reg [4:0] state;
    reg [2:0] source_state;
    reg [1:0] model_hold, precision_hold, class_hold;
    reg [31:0] generation_hold, token_hold, length_hold, hidden_hold, row_hold;
    reg [63:0] weights_hold, matrix_base, matrix_bytes;
    reg [31:0] matrix_rows, matrix_columns, matrix_stride, received;
    reg [31:0] bank_index, projected_hold;
    reg [15:0] bank_data, bank_q, output_hold;
    reg bank_error, vector_visible, vector_allocated, receive_bad;
    reg [3:0] norm_error_hold, error_hold;
    (* ramstyle = "M20K", nomem2reg *) reg [15:0] normalized [0:1535];

    initial begin
        if (COMPACT != 0 && COMPACT != 1)
            $fatal(1, "PARAMETER ERROR: COMPACT must be 0 or 1");
    end
    wire image_ready, image_valid, image_cmd_valid, image_result_ready;
    wire [63:0] image_addr, image_base_result, image_bytes_result;
    wire [31:0] image_rows, image_columns, image_stride;
    wire [7:0] image_type;
    wire [3:0] image_error;
    wire image_selected = rst_n && (state == IMAGE_START || state == IMAGE_WAIT);
    wire [63:0] primitive_directory_bytes, primitive_norm_bytes, primitive_projection_bytes;
    anvil_en1_tensor_image #(.COMPACT(COMPACT)) directory (
        .controller_bytes(primitive_directory_bytes),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == IMAGE_START), .start_ready(image_ready),
        .model(model_hold), .precision(precision_hold), .image_class(class_hold),
        .input_audio(1'b0), .input_items(32'd0), .image_base(weights_hold),
        .tensor_kind(class_hold == 1 ? 16'h1200 : 16'h2202),
        .tensor_layer(16'hffff),
        .cmd_valid(image_cmd_valid), .cmd_ready(image_selected && cmd_ready),
        .cmd_write(), .cmd_addr(image_addr), .cmd_wdata(),
        .result_valid(image_selected && result_valid), .result_ready(image_result_ready),
        .result_data(result_data), .result_error(result_error),
        .done_valid(image_valid), .done_ready(rst_n && state == IMAGE_WAIT),
        .done_base(image_base_result), .done_bytes(image_bytes_result),
        .done_rows(image_rows), .done_columns(image_columns), .done_stride(image_stride),
        .done_type(image_type), .done_error(image_error)
    );
    wire norm_ready, norm_valid, norm_source_valid, norm_source_rsp_ready;
    wire [31:0] norm_source_index, norm_index;
    wire norm_output_valid, norm_last;
    wire [15:0] norm_data;
    wire [3:0] norm_error;
    wire norm_selected = rst_n && (state == NORM_START || state == NORM_WAIT);
    anvil_en1_norm norm (
        .controller_bytes(primitive_norm_bytes),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == NORM_START), .start_ready(norm_ready),
        .layer_norm(1'b0), .learned_scale(1'b0),
        .vector_length(length_hold), .epsilon(32'h358637bd),
        .source_valid(norm_source_valid), .source_ready(norm_selected && source_ready),
        .source_index(norm_source_index),
        .source_rsp_valid(norm_selected && source_rsp_valid),
        .source_rsp_ready(norm_source_rsp_ready),
        .source_rsp_data(source_rsp_data), .source_rsp_error(source_rsp_error),
        .scale_valid(), .scale_ready(1'b0), .scale_index(),
        .scale_rsp_valid(1'b0), .scale_rsp_ready(), .scale_rsp_data(16'd0),
        .scale_rsp_error(1'b0),
        .normalized_valid(norm_output_valid), .normalized_ready(rst_n && state == NORM_WAIT),
        .normalized_index(norm_index), .normalized_data(norm_data), .normalized_last(norm_last),
        .done_valid(norm_valid), .done_ready(rst_n && state == NORM_WAIT),
        .done_error(norm_error)
    );
    wire norm_beat_good = received < length_hold && norm_index == received &&
        norm_last == (received + 1'b1 == length_hold);
    always @(posedge clk) begin
        if (rst_n && state == NORM_WAIT && norm_output_valid &&
            norm_beat_good && !receive_bad)
            normalized[norm_index[10:0]] <= norm_data;
        if (rst_n && state == PROJECTION_WAIT && source_state == S_READ)
            bank_q <= normalized[bank_index[10:0]];
    end
    wire projection_ready, projection_valid, projection_cmd_valid, projection_result_ready;
    wire projection_source_valid, projection_source_rsp_ready;
    wire [31:0] projection_source_index, projection_data;
    wire [63:0] projection_addr;
    wire [3:0] projection_error;
    wire projection_selected = rst_n &&
        (state == PROJECTION_START || state == PROJECTION_WAIT);
    anvil_en1_projection projection (
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
        .source_rsp_data(bank_data), .source_rsp_error(bank_error),
        .cmd_valid(projection_cmd_valid), .cmd_ready(projection_selected && cmd_ready),
        .cmd_write(), .cmd_addr(projection_addr), .cmd_wdata(),
        .result_valid(projection_selected && result_valid),
        .result_ready(projection_result_ready), .result_data(result_data),
        .result_error(result_error),
        .done_valid(projection_valid),
        .done_ready(rst_n && state == PROJECTION_WAIT && source_state == S_IDLE),
        .done_data(projection_data), .done_error(projection_error)
    );
    assign start_ready = rst_n && state == IDLE;
    assign source_valid = norm_selected && norm_source_valid;
    assign source_generation = rst_n ? generation_hold : 32'd0;
    assign source_token = rst_n ? token_hold : 32'd0;
    assign source_index = rst_n ? norm_source_index : 32'd0;
    assign source_model = rst_n ? model_hold : 2'd0;
    assign source_class = rst_n ? class_hold : 2'd0;
    assign source_rsp_ready = norm_selected && norm_source_rsp_ready;
    assign cmd_valid = image_selected ? image_cmd_valid :
        (projection_selected && projection_cmd_valid);
    assign cmd_write = 0;
    assign cmd_addr = !rst_n ? 64'd0 :
        (image_selected ? image_addr : (projection_selected ? projection_addr : 64'd0));
    assign cmd_wdata = 0;
    assign result_ready = image_selected ? image_result_ready :
        (projection_selected && projection_result_ready);
    assign output_valid = rst_n && state == EMIT;
    assign output_index = rst_n ? row_hold : 32'd0;
    assign output_data = rst_n ? output_hold : 16'd0;
    assign output_last = rst_n && state == EMIT && row_hold + 1'b1 == hidden_hold;
    assign done_valid = rst_n && state == RESPONSE;
    assign done_error = rst_n ? error_hold : 4'd0;
    assign weight_read_event = cmd_valid && cmd_ready;
    assign weight_read_bytes = weight_read_event ? 32'd4 : 32'd0;
    assign projection_event = rst_n && state == PROJECTION_START && projection_ready;
    assign projection_bytes = projection_event ? matrix_stride : 32'd0;
    assign vector_live_bytes = rst_n && vector_allocated ?
        {31'd0, length_hold, 1'b0} : 64'd0;
    assign vector_physical_bytes = rst_n ? 64'd3072 : 64'd0;
    wire [31:0] CONTROLLER_BITS =
        $bits(state) + $bits(source_state) + $bits(model_hold) + $bits(precision_hold) +
        $bits(class_hold) + $bits(generation_hold) + $bits(token_hold) +
        $bits(length_hold) + $bits(hidden_hold) + $bits(row_hold) +
        $bits(weights_hold) + $bits(matrix_base) + $bits(matrix_bytes) +
        $bits(matrix_rows) + $bits(matrix_columns) + $bits(matrix_stride) +
        $bits(received) + $bits(bank_index) + $bits(projected_hold) + $bits(bank_data) +
        $bits(bank_q) + $bits(output_hold) + $bits(bank_error) + $bits(vector_visible) +
        $bits(vector_allocated) + $bits(receive_bad) + $bits(norm_error_hold) + $bits(error_hold);
    assign controller_bytes = !rst_n ? 64'd0 : 64'((CONTROLLER_BITS + 7) >> 3) +
        primitive_directory_bytes + primitive_norm_bytes + primitive_projection_bytes;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            source_state <= S_IDLE;
            bank_index <= 0;
            bank_data <= 0;
            bank_error <= 0;
        end else begin
            case (source_state)
                S_IDLE: if (state == PROJECTION_WAIT && projection_source_valid) begin
                    bank_index <= projection_source_index;
                    bank_data <= 0;
                    bank_error <= 0;
                    source_state <= S_VALIDATE;
                end
                S_VALIDATE: begin
                    if (!vector_visible || bank_index >= length_hold) begin
                        bank_error <= 1;
                        source_state <= S_RESPONSE;
                    end else
                        source_state <= S_READ;
                end
                S_READ: source_state <= S_CAPTURE;
                S_CAPTURE: begin
                    bank_data <= bank_q;
                    source_state <= S_RESPONSE;
                end
                S_RESPONSE: if (state == PROJECTION_WAIT && projection_source_rsp_ready)
                    source_state <= S_IDLE;
                default: begin
                    bank_error <= 1;
                    source_state <= S_RESPONSE;
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
            generation_hold <= 0;
            token_hold <= 0;
            length_hold <= 0;
            hidden_hold <= 0;
            row_hold <= 0;
            weights_hold <= 0;
            matrix_base <= 0;
            matrix_bytes <= 0;
            matrix_rows <= 0;
            matrix_columns <= 0;
            matrix_stride <= 0;
            received <= 0;
            projected_hold <= 0;
            output_hold <= 0;
            vector_visible <= 0;
            vector_allocated <= 0;
            receive_bad <= 0;
            norm_error_hold <= 0;
            error_hold <= 0;
        end else begin
            if (state == NORM_WAIT && norm_output_valid) begin
                if (!norm_beat_good)
                    receive_bad <= 1;
                if (received < length_hold)
                    received <= received + 1'b1;
            end
            case (state)
                IDLE: if (start_valid && start_ready) begin
                    model_hold <= model;
                    precision_hold <= precision;
                    class_hold <= image_class;
                    generation_hold <= generation;
                    token_hold <= soft_token;
                    weights_hold <= weights_base;
                    length_hold <= image_class == 1 ? 32'd768 : 32'd1536;
                    hidden_hold <= COMPACT ? 32'd8 :
                        (model == 1 ? 32'd1536 : 32'd2560);
                    row_hold <= 0;
                    received <= 0;
                    output_hold <= 0;
                    vector_visible <= 0;
                    vector_allocated <= 0;
                    receive_bad <= 0;
                    norm_error_hold <= 0;
                    error_hold <= 0;
                    state <= VALIDATE;
                end
                VALIDATE: begin
                    if ((model_hold != 1 && model_hold != 2) || precision_hold > 1) begin
                        error_hold <= 6;
                        state <= PUBLISH;
                    end else if ((class_hold != 1 && class_hold != 2) ||
                        generation_hold == 0 || token_hold > 131071 ||
                        weights_hold[1:0] != 0) begin
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
                    end else if (image_rows != hidden_hold || image_columns != length_hold ||
                        image_type != {6'd0, precision_hold}) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else begin
                        matrix_base <= image_base_result;
                        matrix_bytes <= image_bytes_result;
                        matrix_rows <= image_rows;
                        matrix_columns <= image_columns;
                        matrix_stride <= image_stride;
                        state <= NORM_START;
                    end
                end
                NORM_START: if (norm_ready) begin
                    vector_allocated <= 1;
                    state <= NORM_WAIT;
                end
                NORM_WAIT: if (norm_valid) begin
                    norm_error_hold <= norm_error;
                    state <= NORM_CHECK;
                end
                NORM_CHECK: begin
                    if (norm_error_hold != 0) begin
                        error_hold <= norm_error_hold;
                        state <= PUBLISH;
                    end else if (receive_bad || received != length_hold) begin
                        error_hold <= 7;
                        state <= PUBLISH;
                    end else begin
                        vector_visible <= 1;
                        state <= PROJECTION_START;
                    end
                end
                PROJECTION_START: if (projection_ready)
                    state <= PROJECTION_WAIT;
                PROJECTION_WAIT: if (projection_valid && source_state == S_IDLE) begin
                    if (projection_error != 0) begin
                        error_hold <= projection_error;
                        state <= PUBLISH;
                    end else begin
                        projected_hold <= projection_data;
                        state <= OUTPUT_REGISTER;
                    end
                end
                OUTPUT_REGISTER: begin
                    output_hold <= projected_hold[15:0];
                    state <= EMIT;
                end
                EMIT: if (output_ready)
                    state <= ADVANCE;
                ADVANCE: begin
                    if (row_hold + 1'b1 == hidden_hold)
                        state <= PUBLISH;
                    else begin
                        row_hold <= row_hold + 1'b1;
                        state <= PROJECTION_START;
                    end
                end
                PUBLISH: state <= RESPONSE;
                RESPONSE: if (done_ready) begin
                    vector_visible <= 0;
                    vector_allocated <= 0;
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
