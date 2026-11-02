module anvil_en1_audio_depthwise_row (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] model, precision,
    input wire [7:0] layer,
    input wire [31:0] generation, token, channel,
    input wire [63:0] audio_weights_base,
    output wire source_valid,
    input wire source_ready,
    output wire [1:0] source_model,
    output wire [7:0] source_layer,
    output wire [31:0] source_generation, source_token, source_channel,
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
    output wire weight_read_event,
    output wire [31:0] weight_read_bytes,
    output wire projection_event,
    output wire [31:0] projection_bytes,
    output wire source_read_event,
    output wire [31:0] source_read_bytes,
    output wire [63:0] controller_bytes
);
    localparam [3:0] IDLE = 0, VALIDATE = 1, IMAGE_START = 2,
        IMAGE_WAIT = 3, PROJECTION_START = 4, PROJECTION_WAIT = 5,
        REGISTER = 6, PUBLISH = 7, RESPONSE = 8;
    localparam [2:0] S_IDLE = 0, S_VALIDATE = 1, S_COORDINATE = 2,
        S_SEND = 3, S_WAIT = 4, S_REGISTER = 5, S_RESPONSE = 6;
    reg [3:0] state;
    reg [2:0] source_state;
    reg [1:0] model_hold, precision_hold;
    reg [7:0] layer_hold;
    reg [31:0] generation_hold, token_hold, channel_hold, stride_hold;
    reg [63:0] weights_hold, matrix_base, matrix_bytes;
    reg [31:0] kernel_hold, distance_hold, source_token_hold, output_hold, child_data;
    reg [15:0] source_data_hold;
    reg source_error_hold;
    reg [3:0] child_error_hold, error_hold;

    wire lookup_selected = rst_n && (state == IMAGE_START || state == IMAGE_WAIT);
    wire lookup_ready, lookup_valid, lookup_cmd_valid, lookup_result_ready;
    wire [63:0] lookup_addr, lookup_base, lookup_bytes;
    wire [31:0] lookup_rows, lookup_columns, lookup_stride;
    wire [7:0] lookup_type;
    wire [3:0] lookup_error;
    anvil_en1_tensor_image directory (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == IMAGE_START), .start_ready(lookup_ready),
        .model(model_hold), .precision(precision_hold), .image_class(2'd2),
        .input_audio(1'b0), .input_items(32'd0), .image_base(weights_hold),
        .tensor_kind(16'h210e), .tensor_layer({8'd0, layer_hold}),
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
    anvil_en1_projection depthwise (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == PROJECTION_START), .start_ready(projection_ready),
        .precision(precision_hold), .tensor_base(matrix_base), .tensor_bytes(matrix_bytes),
        .tensor_rows(32'd1024), .tensor_columns(32'd5), .row_stride(stride_hold),
        .row_index(channel_hold), .source_valid(projection_source_valid),
        .source_ready(rst_n && state == PROJECTION_WAIT && source_state == S_IDLE),
        .source_index(projection_index),
        .source_rsp_valid(rst_n && state == PROJECTION_WAIT && source_state == S_RESPONSE),
        .source_rsp_ready(projection_source_rsp_ready),
        .source_rsp_data(source_data_hold), .source_rsp_error(source_error_hold),
        .cmd_valid(projection_cmd_valid), .cmd_ready(projection_selected && cmd_ready),
        .cmd_write(), .cmd_addr(projection_addr), .cmd_wdata(),
        .result_valid(projection_selected && result_valid),
        .result_ready(projection_result_ready), .result_data(result_data),
        .result_error(result_error), .done_valid(projection_valid),
        .done_ready(rst_n && state == PROJECTION_WAIT && source_state == S_IDLE),
        .done_data(projection_data), .done_error(projection_error)
    );
    assign start_ready = rst_n && state == IDLE;
    assign source_valid = rst_n && source_state == S_SEND;
    assign source_rsp_ready = rst_n && source_state == S_WAIT;
    assign source_model = rst_n ? model_hold : 2'd0;
    assign source_layer = rst_n ? layer_hold : 8'd0;
    assign source_generation = rst_n ? generation_hold : 32'd0;
    assign source_token = rst_n ? source_token_hold : 32'd0;
    assign source_channel = rst_n ? channel_hold : 32'd0;
    assign cmd_valid = lookup_selected ? lookup_cmd_valid :
        (projection_selected && projection_cmd_valid);
    assign cmd_write = 0;
    assign cmd_addr = !rst_n ? 64'd0 : (lookup_selected ? lookup_addr :
        (projection_selected ? projection_addr : 64'd0));
    assign cmd_wdata = 0;
    assign result_ready = lookup_selected ? lookup_result_ready :
        (projection_selected && projection_result_ready);
    assign done_valid = rst_n && state == RESPONSE;
    assign done_data = rst_n ? output_hold : 32'd0;
    assign done_error = rst_n ? error_hold : 4'd0;
    assign weight_read_event = cmd_valid && cmd_ready;
    assign weight_read_bytes = weight_read_event ? 32'd4 : 32'd0;
    assign projection_event = rst_n && state == PROJECTION_START && projection_ready;
    assign projection_bytes = projection_event ? stride_hold : 32'd0;
    assign source_read_event = source_valid && source_ready;
    assign source_read_bytes = source_read_event ? 32'd2 : 32'd0;
    localparam integer CONTROLLER_BITS =
        $bits(state) + $bits(source_state) + $bits(model_hold) + $bits(precision_hold) +
        $bits(layer_hold) + $bits(generation_hold) + $bits(token_hold) +
        $bits(channel_hold) + $bits(stride_hold) + $bits(weights_hold) +
        $bits(matrix_base) + $bits(matrix_bytes) + $bits(kernel_hold) +
        $bits(distance_hold) + $bits(source_token_hold) + $bits(output_hold) +
        $bits(child_data) + $bits(source_data_hold) + $bits(source_error_hold) +
        $bits(child_error_hold) + $bits(error_hold);
    assign controller_bytes = rst_n ? (CONTROLLER_BITS + 7) >> 3 : 64'd0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            source_state <= S_IDLE;
            kernel_hold <= 0;
            distance_hold <= 0;
            source_token_hold <= 0;
            source_data_hold <= 0;
            source_error_hold <= 0;
        end else begin
            case (source_state)
                S_IDLE: if (state == PROJECTION_WAIT && projection_source_valid) begin
                    kernel_hold <= projection_index;
                    source_data_hold <= 0;
                    source_error_hold <= 0;
                    source_state <= S_VALIDATE;
                end
                S_VALIDATE: begin
                    if (kernel_hold >= 5) begin
                        source_error_hold <= 1;
                        source_state <= S_RESPONSE;
                    end else begin
                        distance_hold <= 32'd4 - kernel_hold;
                        source_state <= S_COORDINATE;
                    end
                end
                S_COORDINATE: begin
                    if (token_hold < distance_hold)
                        source_state <= S_RESPONSE;
                    else begin
                        source_token_hold <= token_hold - distance_hold;
                        source_state <= S_SEND;
                    end
                end
                S_SEND: if (source_ready)
                    source_state <= S_WAIT;
                S_WAIT: if (source_rsp_valid) begin
                    source_data_hold <= source_rsp_data;
                    source_error_hold <= source_rsp_error;
                    source_state <= S_REGISTER;
                end
                S_REGISTER: source_state <= S_RESPONSE;
                S_RESPONSE: if (state == PROJECTION_WAIT && projection_source_rsp_ready)
                    source_state <= S_IDLE;
                default: begin
                    source_error_hold <= 1;
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
            layer_hold <= 0;
            generation_hold <= 0;
            token_hold <= 0;
            channel_hold <= 0;
            stride_hold <= 0;
            weights_hold <= 0;
            matrix_base <= 0;
            matrix_bytes <= 0;
            output_hold <= 0;
            child_data <= 0;
            child_error_hold <= 0;
            error_hold <= 0;
        end else begin
            case (state)
                IDLE: if (start_valid && start_ready) begin
                    model_hold <= model;
                    precision_hold <= precision;
                    layer_hold <= layer;
                    generation_hold <= generation;
                    token_hold <= token;
                    channel_hold <= channel;
                    weights_hold <= audio_weights_base;
                    output_hold <= 0;
                    child_data <= 0;
                    child_error_hold <= 0;
                    error_hold <= 0;
                    state <= VALIDATE;
                end
                VALIDATE: begin
                    if ((model_hold != 1 && model_hold != 2) || precision_hold > 1) begin
                        error_hold <= 6;
                        state <= PUBLISH;
                    end else if (layer_hold >= 12 || generation_hold == 0 ||
                        token_hold > 131071 || channel_hold >= 1024 ||
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
                    end else if (lookup_rows != 1024 || lookup_columns != 5 ||
                        lookup_type != {6'd0, precision_hold}) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else begin
                        matrix_base <= lookup_base;
                        matrix_bytes <= lookup_bytes;
                        stride_hold <= lookup_stride;
                        state <= PROJECTION_START;
                    end
                end
                PROJECTION_START: if (projection_ready)
                    state <= PROJECTION_WAIT;
                PROJECTION_WAIT: if (projection_valid && source_state == S_IDLE) begin
                    child_data <= projection_data;
                    child_error_hold <= projection_error;
                    state <= REGISTER;
                end
                REGISTER: begin
                    output_hold <= child_error_hold == 0 ? child_data : 32'd0;
                    error_hold <= child_error_hold;
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
