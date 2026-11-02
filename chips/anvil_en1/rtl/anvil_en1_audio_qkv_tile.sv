module anvil_en1_audio_qkv_tile (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] model, precision, selector,
    input wire [7:0] layer,
    input wire [31:0] generation, token,
    input wire [2:0] head,
    input wire [9:0] component,
    input wire [63:0] audio_weights_base,
    output wire source_valid,
    input wire source_ready,
    output wire [1:0] source_model,
    output wire [7:0] source_layer,
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
    output wire done_valid,
    input wire done_ready,
    output wire [63:0] done_data,
    output wire [3:0] done_error,
    output wire projection_event,
    output wire [31:0] projection_bytes,
    output wire [63:0] controller_bytes, clipped_controller_bytes, clamp_controller_bytes,
    output wire [63:0] position_controller_bytes, softplus_controller_bytes
);
    localparam [5:0] IDLE = 0, VALIDATE = 1, LOOKUP_START = 2,
        LOOKUP_WAIT = 3, ROW_START = 4, ROW_WAIT = 5,
        ROW_REGISTER = 6, SCALE_START = 7, SCALE_WAIT = 8,
        SOFTPLUS_START = 9, SOFTPLUS_WAIT = 10, FACTOR_NARROW = 11,
        FACTOR_REGISTER = 12, QUERY_SCALE = 13, QUERY_FACTOR = 14,
        KEY_SCALE = 15, ROW_FINISH = 16, ROW_ADVANCE = 17,
        FP_START = 18, FP_WAIT = 19, PUBLISH = 20, RESPONSE = 21;
    localparam [2:0] S_IDLE = 0, S_VALIDATE = 1, POSITION_START = 2,
        POSITION_WAIT = 3, S_REGISTER = 4, S_RESPONSE = 5;
    reg [5:0] state, fp_return;
    reg [2:0] source_state;
    reg [1:0] model_hold, precision_hold, selector_hold;
    reg [7:0] layer_hold;
    reg [31:0] generation_hold, token_hold, position_index;
    reg [2:0] head_hold;
    reg [6:0] component_hold;
    reg second_lane;
    reg [63:0] weights_hold, tensor_base_hold, tensor_bytes_hold, output_hold;
    reg [31:0] tensor_rows_hold, tensor_columns_hold, tensor_stride_hold;
    reg [31:0] projected_hold, scale_hold, softplus_hold, factor_hold;
    reg [31:0] fp_a, fp_b, fp_value, first_hold;
    reg [2:0] fp_op;
    reg [15:0] position_data_hold;
    reg [3:0] error_hold, position_error_hold, first_source_error;

    wire [6:0] current_component = component_hold + {6'd0, second_lane};
    wire [31:0] matrix_row = {22'd0, head_hold, current_component};
    wire lookup_selected = rst_n && (state == LOOKUP_START || state == LOOKUP_WAIT);
    wire row_selected = rst_n && (state == ROW_START || state == ROW_WAIT);
    wire scale_selected = rst_n && (state == SCALE_START || state == SCALE_WAIT);
    wire lookup_ready, lookup_valid, lookup_cmd_valid, lookup_result_ready;
    wire [63:0] lookup_addr, lookup_base, lookup_bytes;
    wire [31:0] lookup_rows, lookup_columns, lookup_stride;
    wire [3:0] lookup_error;
    anvil_en1_tensor_image directory (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == LOOKUP_START), .start_ready(lookup_ready),
        .model(model_hold), .precision(precision_hold), .image_class(2'd2),
        .input_audio(1'b0), .input_items(32'd0), .image_base(weights_hold),
        .tensor_kind(selector_hold == 0 ? 16'h2109 : 16'h2108),
        .tensor_layer({8'd0, layer_hold}),
        .cmd_valid(lookup_cmd_valid), .cmd_ready(lookup_selected && cmd_ready),
        .cmd_write(), .cmd_addr(lookup_addr), .cmd_wdata(),
        .result_valid(lookup_selected && result_valid), .result_ready(lookup_result_ready),
        .result_data(result_data), .result_error(result_error),
        .done_valid(lookup_valid), .done_ready(rst_n && state == LOOKUP_WAIT),
        .done_base(lookup_base), .done_bytes(lookup_bytes), .done_rows(lookup_rows),
        .done_columns(lookup_columns), .done_stride(lookup_stride),
        .done_type(), .done_error(lookup_error)
    );
    wire clipped_ready, clipped_valid, clipped_source_valid, clipped_source_rsp_ready;
    wire clipped_cmd_valid, clipped_result_ready;
    wire [31:0] clipped_source_index, clipped_data;
    wire [63:0] clipped_addr;
    wire [3:0] clipped_error;
    wire clipped_selected = row_selected && selector_hold != 3;
    wire [15:0] clipped_kind = selector_hold == 0 ? 16'h2105 :
        (selector_hold == 1 ? 16'h2106 : 16'h2107);
    anvil_en1_clipped_projection clipped (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == ROW_START && selector_hold != 3),
        .start_ready(clipped_ready),
        .model(model_hold), .precision(precision_hold), .image_class(2'd2),
        .image_base(weights_hold), .tensor_kind(clipped_kind),
        .tensor_layer({8'd0, layer_hold}), .row_index(matrix_row),
        .source_valid(clipped_source_valid), .source_ready(clipped_selected && source_ready),
        .source_index(clipped_source_index),
        .source_rsp_valid(clipped_selected && source_rsp_valid),
        .source_rsp_ready(clipped_source_rsp_ready),
        .source_rsp_data(source_rsp_data), .source_rsp_error(source_rsp_error),
        .cmd_valid(clipped_cmd_valid), .cmd_ready(clipped_selected && cmd_ready),
        .cmd_write(), .cmd_addr(clipped_addr), .cmd_wdata(),
        .result_valid(clipped_selected && result_valid), .result_ready(clipped_result_ready),
        .result_data(result_data), .result_error(result_error),
        .done_valid(clipped_valid),
        .done_ready(rst_n && state == ROW_WAIT && selector_hold != 3),
        .done_data(clipped_data), .done_error(clipped_error),
        .controller_bytes(clipped_controller_bytes),
        .clamp_controller_bytes(clamp_controller_bytes)
    );
    wire relative_ready, relative_valid, relative_source_valid, relative_source_rsp_ready;
    wire relative_cmd_valid, relative_result_ready;
    wire [31:0] relative_source_index, relative_data;
    wire [63:0] relative_addr;
    wire [3:0] relative_error;
    wire relative_selected = row_selected && selector_hold == 3;
    anvil_en1_projection relative_projection (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == ROW_START && selector_hold == 3),
        .start_ready(relative_ready), .precision(precision_hold),
        .tensor_base(tensor_base_hold), .tensor_bytes(tensor_bytes_hold),
        .tensor_rows(tensor_rows_hold), .tensor_columns(tensor_columns_hold),
        .row_stride(tensor_stride_hold), .row_index(matrix_row),
        .source_valid(relative_source_valid),
        .source_ready(rst_n && state == ROW_WAIT && selector_hold == 3 &&
            source_state == S_IDLE),
        .source_index(relative_source_index),
        .source_rsp_valid(rst_n && source_state == S_RESPONSE),
        .source_rsp_ready(relative_source_rsp_ready),
        .source_rsp_data(position_data_hold), .source_rsp_error(position_error_hold != 0),
        .cmd_valid(relative_cmd_valid), .cmd_ready(relative_selected && cmd_ready),
        .cmd_write(), .cmd_addr(relative_addr), .cmd_wdata(),
        .result_valid(relative_selected && result_valid), .result_ready(relative_result_ready),
        .result_data(result_data), .result_error(result_error),
        .done_valid(relative_valid),
        .done_ready(rst_n && state == ROW_WAIT && selector_hold == 3 && source_state == S_IDLE),
        .done_data(relative_data), .done_error(relative_error)
    );
    wire position_ready, position_valid;
    wire [15:0] position_data;
    wire [3:0] position_error;
    anvil_en1_audio_relative_position position (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && source_state == POSITION_START), .start_ready(position_ready),
        .distance(token_hold[3:0]), .component(position_index[9:0]),
        .done_valid(position_valid), .done_ready(rst_n && source_state == POSITION_WAIT),
        .done_data(position_data), .done_error(position_error),
        .controller_bytes(position_controller_bytes)
    );
    wire scale_ready, scale_valid, scale_cmd_valid, scale_result_ready;
    wire [31:0] scale_data;
    wire [63:0] scale_addr;
    wire [3:0] scale_error;
    anvil_en1_weight_read scales (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == SCALE_START), .start_ready(scale_ready),
        .precision(2'd0), .tensor_base(tensor_base_hold), .tensor_bytes(tensor_bytes_hold),
        .tensor_rows(tensor_rows_hold), .tensor_columns(tensor_columns_hold),
        .row_stride(tensor_stride_hold), .row_index(32'd0),
        .column_index({25'd0, current_component}),
        .cmd_valid(scale_cmd_valid), .cmd_ready(scale_selected && cmd_ready),
        .cmd_write(), .cmd_addr(scale_addr), .cmd_wdata(),
        .result_valid(scale_selected && result_valid), .result_ready(scale_result_ready),
        .result_data(result_data), .result_error(result_error),
        .done_valid(scale_valid), .done_ready(rst_n && state == SCALE_WAIT),
        .done_data(scale_data), .done_error(scale_error)
    );
    wire softplus_ready, softplus_valid, fp_ready, fp_valid;
    wire [31:0] softplus_data, fp_data;
    wire [3:0] softplus_error, fp_error;
    anvil_en1_softplus softplus (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == SOFTPLUS_START), .start_ready(softplus_ready),
        .operand(scale_hold), .done_valid(softplus_valid),
        .done_ready(rst_n && state == SOFTPLUS_WAIT),
        .done_data(softplus_data), .done_error(softplus_error),
        .controller_bytes(softplus_controller_bytes)
    );
    anvil_en1_fp32 arithmetic (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == FP_START), .start_ready(fp_ready),
        .operation(fp_op), .operand_a(fp_a), .operand_b(fp_b),
        .done_valid(fp_valid), .done_ready(rst_n && state == FP_WAIT),
        .done_data(fp_data), .done_error(fp_error)
    );
    wire row_ready = selector_hold == 3 ? relative_ready : clipped_ready;
    wire row_valid = selector_hold == 3 ? relative_valid : clipped_valid;
    wire [31:0] row_data = selector_hold == 3 ? relative_data : clipped_data;
    wire [3:0] row_error = selector_hold == 3 ? relative_error : clipped_error;
    wire row_accept = rst_n && state == ROW_WAIT && row_valid &&
        (selector_hold != 3 || source_state == S_IDLE);
    assign start_ready = rst_n && state == IDLE;
    assign source_valid = clipped_selected && clipped_source_valid;
    assign source_rsp_ready = clipped_selected && clipped_source_rsp_ready;
    assign source_model = rst_n ? model_hold : 2'd0;
    assign source_layer = rst_n ? layer_hold : 8'd0;
    assign source_generation = rst_n ? generation_hold : 32'd0;
    assign source_token = rst_n ? token_hold : 32'd0;
    assign source_index = rst_n ? clipped_source_index : 32'd0;
    assign cmd_valid = lookup_selected ? lookup_cmd_valid :
        (clipped_selected ? clipped_cmd_valid :
        (relative_selected ? relative_cmd_valid : (scale_selected && scale_cmd_valid)));
    assign cmd_write = 0;
    assign cmd_addr = !rst_n ? 64'd0 : (lookup_selected ? lookup_addr :
        (clipped_selected ? clipped_addr : (relative_selected ? relative_addr :
        (scale_selected ? scale_addr : 64'd0))));
    assign cmd_wdata = 0;
    assign result_ready = lookup_selected ? lookup_result_ready :
        (clipped_selected ? clipped_result_ready :
        (relative_selected ? relative_result_ready : (scale_selected && scale_result_ready)));
    assign done_valid = rst_n && state == RESPONSE;
    assign done_data = rst_n ? output_hold : 64'd0;
    assign done_error = rst_n ? error_hold : 4'd0;
    assign projection_event = row_accept && row_error == 0 && first_source_error == 0;
    assign projection_bytes = projection_event ? 32'd2 : 32'd0;
    localparam integer CONTROLLER_BITS =
        $bits(state) + $bits(fp_return) + $bits(source_state) +
        $bits(model_hold) + $bits(precision_hold) + $bits(selector_hold) +
        $bits(layer_hold) + $bits(generation_hold) + $bits(token_hold) +
        $bits(position_index) + $bits(head_hold) + $bits(component_hold) +
        $bits(second_lane) + $bits(weights_hold) + $bits(tensor_base_hold) +
        $bits(tensor_bytes_hold) + $bits(output_hold) + $bits(tensor_rows_hold) +
        $bits(tensor_columns_hold) + $bits(tensor_stride_hold) +
        $bits(projected_hold) + $bits(scale_hold) + $bits(softplus_hold) +
        $bits(factor_hold) + $bits(fp_a) + $bits(fp_b) + $bits(fp_value) +
        $bits(first_hold) + $bits(fp_op) + $bits(position_data_hold) +
        $bits(error_hold) + $bits(position_error_hold) + $bits(first_source_error);
    assign controller_bytes = rst_n ? (CONTROLLER_BITS + 7) >> 3 : 64'd0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            source_state <= S_IDLE;
            position_index <= 0;
            position_data_hold <= 0;
            position_error_hold <= 0;
            first_source_error <= 0;
        end else begin
            if (state == IDLE && start_valid && start_ready)
                first_source_error <= 0;
            case (source_state)
                S_IDLE: if (relative_selected && state == ROW_WAIT && relative_source_valid) begin
                    position_index <= relative_source_index;
                    position_data_hold <= 0;
                    position_error_hold <= 0;
                    source_state <= S_VALIDATE;
                end
                S_VALIDATE: begin
                    if (position_index >= 1024 || first_source_error != 0) begin
                        position_error_hold <= first_source_error != 0 ? first_source_error : 4'd7;
                        if (first_source_error == 0)
                            first_source_error <= 7;
                        source_state <= S_REGISTER;
                    end else
                        source_state <= POSITION_START;
                end
                POSITION_START: if (position_ready)
                    source_state <= POSITION_WAIT;
                POSITION_WAIT: if (position_valid) begin
                    position_data_hold <= position_data;
                    position_error_hold <= position_error;
                    if (first_source_error == 0 && position_error != 0)
                        first_source_error <= position_error;
                    source_state <= S_REGISTER;
                end
                S_REGISTER: source_state <= S_RESPONSE;
                S_RESPONSE: if (relative_source_rsp_ready)
                    source_state <= S_IDLE;
                default: begin
                    position_error_hold <= 7;
                    if (first_source_error == 0)
                        first_source_error <= 7;
                    source_state <= S_REGISTER;
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
            selector_hold <= 0;
            layer_hold <= 0;
            generation_hold <= 0;
            token_hold <= 0;
            head_hold <= 0;
            component_hold <= 0;
            second_lane <= 0;
            weights_hold <= 0;
            tensor_base_hold <= 0;
            tensor_bytes_hold <= 0;
            tensor_rows_hold <= 0;
            tensor_columns_hold <= 0;
            tensor_stride_hold <= 0;
            output_hold <= 0;
            projected_hold <= 0;
            scale_hold <= 0;
            softplus_hold <= 0;
            factor_hold <= 0;
            fp_a <= 0;
            fp_b <= 0;
            fp_value <= 0;
            first_hold <= 0;
            fp_op <= 0;
            error_hold <= 0;
        end else begin
            case (state)
                IDLE: if (start_valid && start_ready) begin
                    model_hold <= model;
                    precision_hold <= precision;
                    selector_hold <= selector;
                    layer_hold <= layer;
                    generation_hold <= generation;
                    token_hold <= token;
                    head_hold <= head;
                    component_hold <= component[6:0];
                    second_lane <= 0;
                    weights_hold <= audio_weights_base;
                    output_hold <= 0;
                    first_hold <= 0;
                    error_hold <= 0;
                    // Preserve the full public component validation before narrowing.
                    if (component >= 128 || component[0])
                        error_hold <= 5;
                    state <= VALIDATE;
                end
                VALIDATE: begin
                    if ((model_hold != 1 && model_hold != 2) || precision_hold > 1) begin
                        error_hold <= 6;
                        state <= PUBLISH;
                    end else if (error_hold != 0 || generation_hold == 0 || layer_hold >= 12 ||
                        weights_hold[1:0] != 0 ||
                        (selector_hold == 3 ? token_hold > 12 : token_hold > 131071)) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else if (selector_hold == 0 || selector_hold == 3)
                        state <= LOOKUP_START;
                    else
                        state <= ROW_START;
                end
                LOOKUP_START: if (lookup_ready)
                    state <= LOOKUP_WAIT;
                LOOKUP_WAIT: if (lookup_valid) begin
                    if (lookup_error != 0) begin
                        error_hold <= lookup_error;
                        state <= PUBLISH;
                    end else if (selector_hold == 0 ?
                        (lookup_rows != 1 || lookup_columns != 128) :
                        (lookup_rows != 1024 || lookup_columns != 1024)) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else begin
                        tensor_base_hold <= lookup_base;
                        tensor_bytes_hold <= lookup_bytes;
                        tensor_rows_hold <= lookup_rows;
                        tensor_columns_hold <= lookup_columns;
                        tensor_stride_hold <= lookup_stride;
                        state <= ROW_START;
                    end
                end
                ROW_START: if (row_ready)
                    state <= ROW_WAIT;
                ROW_WAIT: if (row_accept) begin
                    if (first_source_error != 0 || row_error != 0) begin
                        error_hold <= first_source_error != 0 ? first_source_error : row_error;
                        output_hold <= 0;
                        state <= PUBLISH;
                    end else begin
                        projected_hold <= {row_data[15:0], 16'd0};
                        state <= ROW_REGISTER;
                    end
                end
                ROW_REGISTER: begin
                    if (selector_hold == 0)
                        state <= SCALE_START;
                    else if (selector_hold == 1)
                        state <= KEY_SCALE;
                    else begin
                        fp_value <= projected_hold;
                        state <= ROW_FINISH;
                    end
                end
                SCALE_START: if (scale_ready)
                    state <= SCALE_WAIT;
                SCALE_WAIT: if (scale_valid) begin
                    if (scale_error != 0) begin
                        error_hold <= scale_error;
                        output_hold <= 0;
                        state <= PUBLISH;
                    end else begin
                        scale_hold <= scale_data;
                        state <= SOFTPLUS_START;
                    end
                end
                SOFTPLUS_START: if (softplus_ready)
                    state <= SOFTPLUS_WAIT;
                SOFTPLUS_WAIT: if (softplus_valid) begin
                    if (softplus_error != 0) begin
                        error_hold <= softplus_error;
                        output_hold <= 0;
                        state <= PUBLISH;
                    end else begin
                        softplus_hold <= softplus_data;
                        state <= FACTOR_NARROW;
                    end
                end
                FACTOR_NARROW: begin
                    fp_op <= 3;
                    fp_a <= softplus_hold;
                    fp_b <= 0;
                    fp_return <= FACTOR_REGISTER;
                    state <= FP_START;
                end
                FACTOR_REGISTER: begin
                    factor_hold <= {fp_value[15:0], 16'd0};
                    state <= QUERY_SCALE;
                end
                QUERY_SCALE: begin
                    fp_op <= 1;
                    fp_a <= projected_hold;
                    fp_b <= 32'h3e0293ee;
                    fp_return <= QUERY_FACTOR;
                    state <= FP_START;
                end
                QUERY_FACTOR: begin
                    fp_op <= 1;
                    fp_a <= fp_value;
                    fp_b <= factor_hold;
                    fp_return <= ROW_FINISH;
                    state <= FP_START;
                end
                KEY_SCALE: begin
                    fp_op <= 1;
                    fp_a <= projected_hold;
                    fp_b <= 32'h3ff28370;
                    fp_return <= ROW_FINISH;
                    state <= FP_START;
                end
                ROW_FINISH: begin
                    if (second_lane) begin
                        output_hold <= {fp_value, first_hold};
                        state <= PUBLISH;
                    end else begin
                        first_hold <= fp_value;
                        state <= ROW_ADVANCE;
                    end
                end
                ROW_ADVANCE: begin
                    second_lane <= 1;
                    state <= ROW_START;
                end
                FP_START: if (fp_ready)
                    state <= FP_WAIT;
                FP_WAIT: if (fp_valid) begin
                    if (fp_error != 0) begin
                        error_hold <= fp_error;
                        output_hold <= 0;
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
                    error_hold <= 7;
                    output_hold <= 0;
                    state <= PUBLISH;
                end
            endcase
        end
    end
endmodule
