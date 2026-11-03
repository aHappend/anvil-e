module anvil_en1_vision_attention_row (
    input wire image_immutable, image_invalidate,
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] model, precision,
    input wire [31:0] generation, patches, patch_rows, patch_columns, query_patch, output_row,
    input wire [7:0] layer,
    input wire [63:0] image_base, vision_weights_base,
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
    output wire done_valid,
    input wire done_ready,
    output wire [31:0] done_data,
    output wire [3:0] done_error,
    output wire input_read_event,
    output wire [31:0] input_read_bytes,
    output wire projection_event,
    output wire [31:0] projection_bytes,
    output wire [63:0] controller_bytes, output_controller_bytes, output_clamp_controller_bytes,
    output wire [63:0] executor_controller_bytes, head_controller_bytes,
    output wire [63:0] tile_controller_bytes, clipped_controller_bytes, clamp_controller_bytes,
    output wire [63:0] tile_live_bytes, tile_physical_bytes
);
    localparam [3:0] IDLE = 0, VALIDATE = 1, ROW_START = 2,
        ROW_WAIT = 3, REGISTER = 4, PUBLISH = 5, RESPONSE = 6,
        EXTENT_PRODUCT = 7, EXTENT_VALIDATE = 8;
    localparam [3:0] SRC_IDLE = 0, SRC_VALIDATE = 1, HEAD_START = 2,
        HEAD_WAIT = 3, HEAD_REGISTER = 4, SRC_REGISTER = 5, SRC_RESPONSE = 6;
    reg [3:0] state;
    reg [3:0] src_state;
    reg [1:0] model_hold, precision_hold;
    reg [31:0] generation_hold, patches_hold, rows_hold, columns_hold;
    reg [31:0] query_hold, row_hold, source_index_hold, output_count, output_hold;
    reg [31:0] extent_hold;
    reg [7:0] layer_hold;
    reg [63:0] image_hold, weights_hold;
    reg [15:0] component_hold;
    reg component_seen, head_bad;
    reg [3:0] source_error_hold, first_error, error_hold;
    wire projection_selected = rst_n && (state == ROW_START || state == ROW_WAIT) &&
        (src_state == SRC_IDLE || src_state == SRC_VALIDATE ||
         src_state == SRC_REGISTER || src_state == SRC_RESPONSE);
    wire head_selected = rst_n && state == ROW_WAIT &&
        (src_state == HEAD_START || src_state == HEAD_WAIT || src_state == HEAD_REGISTER);
    wire row_ready, row_valid, row_cmd_valid, row_result_ready;
    wire row_source_valid, row_source_rsp_ready;
    wire [31:0] row_source_index, row_data;
    wire [63:0] row_addr;
    wire [3:0] row_error;
    anvil_en1_clipped_projection output_projection (
        .image_immutable(image_immutable === 1'b1),
        .image_invalidate((image_invalidate === 1'b1)),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == ROW_START), .start_ready(row_ready),
        .model(model_hold), .precision(precision_hold), .image_class(2'd1),
        .image_base(weights_hold), .tensor_kind(16'h1106),
        .tensor_layer({8'd0, layer_hold}), .row_index(row_hold),
        .source_valid(row_source_valid),
        .source_ready(rst_n && state == ROW_WAIT && src_state == SRC_IDLE),
        .source_index(row_source_index),
        .source_rsp_valid(rst_n && state == ROW_WAIT && src_state == SRC_RESPONSE),
        .source_rsp_ready(row_source_rsp_ready), .source_rsp_data(component_hold),
        .source_rsp_error(source_error_hold != 0),
        .cmd_valid(row_cmd_valid), .cmd_ready(projection_selected && cmd_ready),
        .cmd_write(), .cmd_addr(row_addr), .cmd_wdata(),
        .result_valid(projection_selected && result_valid), .result_ready(row_result_ready),
        .result_data(result_data), .result_error(result_error),
        .done_valid(row_valid),
        .done_ready(rst_n && state == ROW_WAIT && src_state == SRC_IDLE),
        .done_data(row_data), .done_error(row_error),
        .controller_bytes(output_controller_bytes),
        .clamp_controller_bytes(output_clamp_controller_bytes)
    );
    wire head_ready, head_valid, head_output_valid, head_output_last;
    wire head_cmd_valid, head_result_ready;
    wire [9:0] head_output_index;
    wire [15:0] head_output_data;
    wire [63:0] head_addr;
    wire [3:0] head_error;
    anvil_en1_vision_attention_execute executor (
        .image_immutable(image_immutable === 1'b1),
        .image_invalidate((image_invalidate === 1'b1)),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == ROW_WAIT && src_state == HEAD_START),
        .start_ready(head_ready),
        .model(model_hold), .precision(precision_hold), .generation(generation_hold),
        .patches(patches_hold), .patch_rows(rows_hold), .patch_columns(columns_hold),
        .query_patch(query_hold), .layer(layer_hold), .head(source_index_hold[9:6]),
        .image_base(image_hold), .vision_weights_base(weights_hold),
        .resume_valid(1'b0), .resume_checkpoint(512'd0),
        .need_valid(), .need_ready(1'b0), .need_action(2'd0),
        .need_generation(), .need_patch(), .need_model(), .need_precision(),
        .need_selector(), .need_layer(), .need_head(), .need_component(),
        .checkpoint_valid(), .checkpoint_ready(1'b0), .checkpoint_data(),
        .source_valid(source_valid), .source_ready(head_selected && source_ready),
        .source_generation(source_generation), .source_patch(source_patch),
        .source_index(source_index), .source_model(source_model), .source_layer(source_layer),
        .source_rsp_valid(head_selected && source_rsp_valid),
        .source_rsp_ready(source_rsp_ready), .source_rsp_data(source_rsp_data),
        .source_rsp_error(source_rsp_error),
        .cmd_valid(head_cmd_valid), .cmd_ready(head_selected && cmd_ready),
        .cmd_write(), .cmd_addr(head_addr), .cmd_wdata(),
        .result_valid(head_selected && result_valid), .result_ready(head_result_ready),
        .result_data(result_data), .result_error(result_error),
        .output_valid(head_output_valid),
        .output_ready(rst_n && state == ROW_WAIT && src_state == HEAD_WAIT),
        .output_index(head_output_index), .output_data(head_output_data),
        .output_last(head_output_last), .done_valid(head_valid),
        .done_ready(rst_n && state == ROW_WAIT && src_state == HEAD_WAIT),
        .done_error(head_error), .input_read_event(input_read_event),
        .input_read_bytes(input_read_bytes), .projection_event(projection_event),
        .projection_bytes(projection_bytes), .controller_bytes(executor_controller_bytes),
        .head_controller_bytes(head_controller_bytes), .tile_controller_bytes(tile_controller_bytes),
        .clipped_controller_bytes(clipped_controller_bytes), .clamp_controller_bytes(clamp_controller_bytes),
        .tile_live_bytes(tile_live_bytes), .tile_physical_bytes(tile_physical_bytes)
    );
    assign start_ready = rst_n && state == IDLE;
    assign cmd_valid = projection_selected ? row_cmd_valid : (head_selected && head_cmd_valid);
    assign cmd_write = 0;
    assign cmd_addr = !rst_n ? 64'd0 : (projection_selected ? row_addr :
        (head_selected ? head_addr : 64'd0));
    assign cmd_wdata = 0;
    assign result_ready = projection_selected ? row_result_ready :
        (head_selected && head_result_ready);
    assign done_valid = rst_n && state == RESPONSE;
    assign done_data = rst_n ? output_hold : 32'd0;
    assign done_error = rst_n ? error_hold : 4'd0;
    wire [31:0] CONTROLLER_BITS =
        $bits(state) + $bits(src_state) + $bits(model_hold) + $bits(precision_hold) +
        $bits(generation_hold) + $bits(patches_hold) + $bits(rows_hold) +
        $bits(columns_hold) + $bits(query_hold) + $bits(row_hold) +
        $bits(source_index_hold) + $bits(output_count) + $bits(output_hold) + $bits(extent_hold) +
        $bits(layer_hold) + $bits(image_hold) + $bits(weights_hold) +
        $bits(component_hold) + $bits(component_seen) + $bits(head_bad) +
        $bits(source_error_hold) + $bits(first_error) + $bits(error_hold);
    assign controller_bytes = rst_n ? (CONTROLLER_BITS + 7) >> 3 : 64'd0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            src_state <= SRC_IDLE;
            source_index_hold <= 0;
            output_count <= 0;
            component_hold <= 0;
            component_seen <= 0;
            head_bad <= 0;
            source_error_hold <= 0;
            first_error <= 0;
        end else begin
            if (state == IDLE && start_valid && start_ready)
                first_error <= 0;
            case (src_state)
                SRC_IDLE: if (state == ROW_WAIT && row_source_valid) begin
                    source_index_hold <= row_source_index;
                    output_count <= 0;
                    component_hold <= 0;
                    component_seen <= 0;
                    head_bad <= 0;
                    source_error_hold <= 0;
                    src_state <= SRC_VALIDATE;
                end
                SRC_VALIDATE: begin
                    if (source_index_hold >= 768 || first_error != 0) begin
                        source_error_hold <= first_error != 0 ? first_error : 4'd7;
                        if (first_error == 0)
                            first_error <= 7;
                        src_state <= SRC_REGISTER;
                    end else
                        src_state <= HEAD_START;
                end
                HEAD_START: if (head_ready)
                    src_state <= HEAD_WAIT;
                HEAD_WAIT: begin
                    if (head_output_valid) begin
                        if (head_output_index != output_count || output_count >= 64 ||
                            head_output_last != (output_count == 63))
                            head_bad <= 1;
                        else begin
                            output_count <= output_count + 1'b1;
                            if (head_output_index == {4'd0, source_index_hold[5:0]}) begin
                                component_hold <= head_output_data;
                                component_seen <= 1;
                            end
                        end
                    end
                    if (head_valid) begin
                        source_error_hold <= head_error;
                        src_state <= HEAD_REGISTER;
                    end
                end
                HEAD_REGISTER: begin
                    if (source_error_hold != 0) begin
                        if (first_error == 0)
                            first_error <= source_error_hold;
                    end else if (head_bad || !component_seen || output_count != 64) begin
                        source_error_hold <= 7;
                        if (first_error == 0)
                            first_error <= 7;
                    end
                    src_state <= SRC_REGISTER;
                end
                SRC_REGISTER: src_state <= SRC_RESPONSE;
                SRC_RESPONSE: if (row_source_rsp_ready)
                    src_state <= SRC_IDLE;
                default: begin
                    source_error_hold <= 7;
                    if (first_error == 0)
                        first_error <= 7;
                    src_state <= SRC_REGISTER;
                end
            endcase
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            model_hold <= 0;
            precision_hold <= 0;
            generation_hold <= 0;
            patches_hold <= 0;
            rows_hold <= 0;
            columns_hold <= 0;
            query_hold <= 0;
            row_hold <= 0;
            layer_hold <= 0;
            image_hold <= 0;
            weights_hold <= 0;
            output_hold <= 0;
            extent_hold <= 0;
            error_hold <= 0;
        end else begin
            case (state)
                IDLE: if (start_valid && start_ready) begin
                    model_hold <= model;
                    precision_hold <= precision;
                    generation_hold <= generation;
                    patches_hold <= patches;
                    rows_hold <= patch_rows;
                    columns_hold <= patch_columns;
                    query_hold <= query_patch;
                    row_hold <= output_row;
                    layer_hold <= layer;
                    image_hold <= image_base;
                    weights_hold <= vision_weights_base;
                    output_hold <= 0;
                    error_hold <= 0;
                    state <= VALIDATE;
                end
                VALIDATE: begin
                    if ((model_hold != 1 && model_hold != 2) || precision_hold > 1) begin
                        error_hold <= 6;
                        state <= PUBLISH;
                    end else if (row_hold >= 768 || layer_hold >= 16 ||
                        patches_hold == 0 || patches_hold > 131072 ||
                        query_hold >= patches_hold || rows_hold == 0 || rows_hold > 10240 ||
                        columns_hold == 0 || columns_hold > 10240 ||
                        image_hold[1:0] != 0 || weights_hold[1:0] != 0) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else
                        state <= EXTENT_PRODUCT;
                end
                EXTENT_PRODUCT: begin
                    extent_hold <= rows_hold[15:0] * columns_hold[15:0];
                    state <= EXTENT_VALIDATE;
                end
                EXTENT_VALIDATE: begin
                    if (extent_hold != patches_hold) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else
                        state <= ROW_START;
                end
                ROW_START: if (row_ready)
                    state <= ROW_WAIT;
                ROW_WAIT: if (row_valid && src_state == SRC_IDLE) begin
                    output_hold <= row_error == 0 && first_error == 0 ? row_data : 32'd0;
                    error_hold <= first_error != 0 ? first_error : row_error;
                    state <= REGISTER;
                end
                REGISTER: state <= PUBLISH;
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
