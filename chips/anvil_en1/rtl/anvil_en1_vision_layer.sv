module anvil_en1_vision_layer (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] model, precision,
    input wire [31:0] generation, patches, patch_rows, patch_columns, query_patch,
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
    output wire output_valid,
    input wire output_ready,
    output wire [31:0] output_index,
    output wire [15:0] output_data,
    output wire output_last,
    output wire done_valid,
    input wire done_ready,
    output wire [3:0] done_error,
    output wire input_read_event,
    output wire [31:0] input_read_bytes,
    output wire projection_event,
    output wire [31:0] projection_bytes,
    output wire intermediate_event,
    output wire [31:0] intermediate_bytes,
    output wire [63:0] vector_live_bytes, vector_physical_bytes,
    output wire [63:0] controller_bytes, post_controller_bytes, norm_controller_bytes,
    output wire [63:0] mlp_controller_bytes, down_controller_bytes, down_clamp_controller_bytes,
    output wire [63:0] inner_controller_bytes, inner_clamp_controller_bytes,
    output wire [63:0] row_controller_bytes, output_controller_bytes, output_clamp_controller_bytes,
    output wire [63:0] executor_controller_bytes, head_controller_bytes,
    output wire [63:0] tile_controller_bytes, clipped_controller_bytes, clamp_controller_bytes
);
    localparam [3:0] IDLE = 0, VALIDATE = 1, EXTENT_PRODUCT = 2,
        EXTENT_VALIDATE = 3, POST_START = 4, POST_WAIT = 5,
        REGISTER = 6, PUBLISH = 7, RESPONSE = 8;
    localparam [2:0] BRANCH_IDLE = 0, BRANCH_VALIDATE = 1, ROW_START = 2,
        ROW_WAIT = 3, BRANCH_REGISTER = 4, BRANCH_RESPONSE = 5;
    reg [3:0] state;
    reg [2:0] branch_state;
    reg [1:0] model_hold, precision_hold;
    reg [31:0] generation_hold, patches_hold, rows_hold, columns_hold, query_hold;
    reg [31:0] extent_hold, row_hold;
    reg [7:0] layer_hold;
    reg [63:0] image_hold, weights_hold;
    reg [15:0] branch_hold;
    reg [3:0] branch_error, first_error, error_hold;
    wire post_selected = rst_n && (state == POST_START || state == POST_WAIT);
    wire row_selected = rst_n && state == POST_WAIT &&
        (branch_state == ROW_START || branch_state == ROW_WAIT);
    wire post_ready, post_valid, post_source_valid, post_source_branch, post_source_rsp_ready;
    wire [31:0] post_source_index;
    wire [3:0] post_error;
    wire post_cmd_valid, post_result_ready;
    wire [63:0] post_addr, post_live, post_physical;
    wire raw_selected = rst_n && state == POST_WAIT &&
        branch_state == BRANCH_IDLE && !post_source_branch;
    anvil_en1_vision_post_layer post (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == POST_START), .start_ready(post_ready),
        .model(model_hold), .precision(precision_hold), .layer(layer_hold),
        .generation(generation_hold), .patch(query_hold), .vision_weights_base(weights_hold),
        .source_valid(post_source_valid),
        .source_ready(rst_n && state == POST_WAIT && branch_state == BRANCH_IDLE &&
            (post_source_branch || source_ready)),
        .source_model(), .source_layer(), .source_generation(), .source_patch(),
        .source_index(post_source_index), .source_is_branch(post_source_branch),
        .source_rsp_valid(rst_n && state == POST_WAIT &&
            (post_source_branch ? branch_state == BRANCH_RESPONSE : source_rsp_valid)),
        .source_rsp_ready(post_source_rsp_ready),
        .source_rsp_data(post_source_branch ? branch_hold : source_rsp_data),
        .source_rsp_error(post_source_branch ? branch_error != 0 : source_rsp_error),
        .cmd_valid(post_cmd_valid), .cmd_ready(post_selected && !row_selected && cmd_ready),
        .cmd_write(), .cmd_addr(post_addr), .cmd_wdata(),
        .result_valid(post_selected && !row_selected && result_valid),
        .result_ready(post_result_ready), .result_data(result_data), .result_error(result_error),
        .output_valid(output_valid), .output_ready(post_selected && output_ready),
        .output_index(output_index), .output_data(output_data), .output_last(output_last),
        .done_valid(post_valid), .done_ready(rst_n && state == POST_WAIT),
        .done_error(post_error), .intermediate_event(intermediate_event),
        .intermediate_bytes(intermediate_bytes),
        .vector_live_bytes(post_live), .vector_physical_bytes(post_physical),
        .controller_bytes(post_controller_bytes), .norm_controller_bytes(norm_controller_bytes),
        .mlp_controller_bytes(mlp_controller_bytes), .down_controller_bytes(down_controller_bytes),
        .down_clamp_controller_bytes(down_clamp_controller_bytes),
        .inner_controller_bytes(inner_controller_bytes),
        .inner_clamp_controller_bytes(inner_clamp_controller_bytes)
    );
    wire row_ready, row_valid, row_source_valid, row_source_rsp_ready;
    wire [31:0] row_source_generation, row_source_patch, row_source_index, row_data;
    wire [1:0] row_source_model;
    wire [7:0] row_source_layer;
    wire [3:0] row_error;
    wire row_cmd_valid, row_result_ready;
    wire [63:0] row_addr, tile_live, tile_physical;
    anvil_en1_vision_attention_row attention (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == POST_WAIT && branch_state == ROW_START),
        .start_ready(row_ready),
        .model(model_hold), .precision(precision_hold), .generation(generation_hold),
        .patches(patches_hold), .patch_rows(rows_hold), .patch_columns(columns_hold),
        .query_patch(query_hold), .output_row(row_hold), .layer(layer_hold),
        .image_base(image_hold), .vision_weights_base(weights_hold),
        .source_valid(row_source_valid), .source_ready(row_selected && source_ready),
        .source_generation(row_source_generation), .source_patch(row_source_patch),
        .source_index(row_source_index), .source_model(row_source_model),
        .source_layer(row_source_layer),
        .source_rsp_valid(row_selected && source_rsp_valid),
        .source_rsp_ready(row_source_rsp_ready),
        .source_rsp_data(source_rsp_data), .source_rsp_error(source_rsp_error),
        .cmd_valid(row_cmd_valid), .cmd_ready(row_selected && cmd_ready),
        .cmd_write(), .cmd_addr(row_addr), .cmd_wdata(),
        .result_valid(row_selected && result_valid), .result_ready(row_result_ready),
        .result_data(result_data), .result_error(result_error),
        .done_valid(row_valid),
        .done_ready(rst_n && state == POST_WAIT && branch_state == ROW_WAIT),
        .done_data(row_data), .done_error(row_error),
        .input_read_event(input_read_event), .input_read_bytes(input_read_bytes),
        .projection_event(projection_event), .projection_bytes(projection_bytes),
        .controller_bytes(row_controller_bytes),
        .output_controller_bytes(output_controller_bytes),
        .output_clamp_controller_bytes(output_clamp_controller_bytes),
        .executor_controller_bytes(executor_controller_bytes),
        .head_controller_bytes(head_controller_bytes), .tile_controller_bytes(tile_controller_bytes),
        .clipped_controller_bytes(clipped_controller_bytes), .clamp_controller_bytes(clamp_controller_bytes),
        .tile_live_bytes(tile_live), .tile_physical_bytes(tile_physical)
    );
    assign start_ready = rst_n && state == IDLE;
    assign source_valid = row_selected ? row_source_valid :
        (raw_selected && post_source_valid);
    assign source_generation = !rst_n ? 32'd0 :
        (row_selected ? row_source_generation : generation_hold);
    assign source_patch = !rst_n ? 32'd0 : (row_selected ? row_source_patch : query_hold);
    assign source_index = !rst_n ? 32'd0 : (row_selected ? row_source_index : post_source_index);
    assign source_model = !rst_n ? 2'd0 : (row_selected ? row_source_model : model_hold);
    assign source_layer = !rst_n ? 8'd0 : (row_selected ? row_source_layer : layer_hold);
    assign source_rsp_ready = row_selected ? row_source_rsp_ready :
        (raw_selected && post_source_rsp_ready);
    assign cmd_valid = row_selected ? row_cmd_valid : (post_selected && post_cmd_valid);
    assign cmd_write = 0;
    assign cmd_addr = !rst_n ? 64'd0 : (row_selected ? row_addr :
        (post_selected ? post_addr : 64'd0));
    assign cmd_wdata = 0;
    assign result_ready = row_selected ? row_result_ready :
        (post_selected && post_result_ready);
    assign done_valid = rst_n && state == RESPONSE;
    assign done_error = rst_n ? error_hold : 4'd0;
    assign vector_live_bytes = rst_n ? post_live + tile_live : 64'd0;
    assign vector_physical_bytes = rst_n ? post_physical + tile_physical : 64'd0;
    localparam integer CONTROLLER_BITS =
        $bits(state) + $bits(branch_state) + $bits(model_hold) + $bits(precision_hold) +
        $bits(generation_hold) + $bits(patches_hold) + $bits(rows_hold) +
        $bits(columns_hold) + $bits(query_hold) + $bits(extent_hold) + $bits(row_hold) +
        $bits(layer_hold) + $bits(image_hold) + $bits(weights_hold) + $bits(branch_hold) +
        $bits(branch_error) + $bits(first_error) + $bits(error_hold);
    assign controller_bytes = rst_n ? (CONTROLLER_BITS + 7) >> 3 : 64'd0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            branch_state <= BRANCH_IDLE;
            row_hold <= 0;
            branch_hold <= 0;
            branch_error <= 0;
            first_error <= 0;
        end else begin
            if (state == IDLE && start_valid && start_ready)
                first_error <= 0;
            case (branch_state)
                BRANCH_IDLE: if (state == POST_WAIT && post_source_valid && post_source_branch) begin
                    row_hold <= post_source_index;
                    branch_hold <= 0;
                    branch_error <= 0;
                    branch_state <= BRANCH_VALIDATE;
                end
                BRANCH_VALIDATE: begin
                    if (row_hold >= 768 || first_error != 0) begin
                        branch_error <= first_error != 0 ? first_error : 4'd7;
                        if (first_error == 0)
                            first_error <= 7;
                        branch_state <= BRANCH_REGISTER;
                    end else
                        branch_state <= ROW_START;
                end
                ROW_START: if (row_ready)
                    branch_state <= ROW_WAIT;
                ROW_WAIT: if (row_valid) begin
                    branch_hold <= row_error == 0 ? row_data[15:0] : 16'd0;
                    branch_error <= row_error;
                    if (row_error != 0 && first_error == 0)
                        first_error <= row_error;
                    branch_state <= BRANCH_REGISTER;
                end
                BRANCH_REGISTER: branch_state <= BRANCH_RESPONSE;
                BRANCH_RESPONSE: if (post_source_rsp_ready)
                    branch_state <= BRANCH_IDLE;
                default: begin
                    branch_error <= 7;
                    if (first_error == 0)
                        first_error <= 7;
                    branch_state <= BRANCH_REGISTER;
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
            extent_hold <= 0;
            layer_hold <= 0;
            image_hold <= 0;
            weights_hold <= 0;
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
                    layer_hold <= layer;
                    image_hold <= image_base;
                    weights_hold <= vision_weights_base;
                    error_hold <= 0;
                    state <= VALIDATE;
                end
                VALIDATE: begin
                    if ((model_hold != 1 && model_hold != 2) || precision_hold > 1) begin
                        error_hold <= 6;
                        state <= PUBLISH;
                    end else if (layer_hold >= 16 || patches_hold == 0 ||
                        patches_hold > 131072 || query_hold >= patches_hold ||
                        rows_hold == 0 || rows_hold > 10240 ||
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
                        state <= POST_START;
                end
                POST_START: if (post_ready)
                    state <= POST_WAIT;
                POST_WAIT: if (post_valid && branch_state == BRANCH_IDLE) begin
                    error_hold <= first_error != 0 ? first_error : post_error;
                    state <= REGISTER;
                end
                REGISTER: state <= PUBLISH;
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
