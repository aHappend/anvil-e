module anvil_en1_vision_soft_token #(
    parameter integer COMPACT = 0
) (
    input wire image_immutable, image_invalidate,
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] model, precision,
    input wire [31:0] generation, patches, patch_rows, patch_columns,
    input wire [31:0] pool_count, soft_token, expected_soft_tokens,
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
    output wire [31:0] done_pool_index, done_soft_tokens,
    output wire [3:0] done_error,
    output wire input_read_event,
    output wire [31:0] input_read_bytes,
    output wire weight_read_event,
    output wire [31:0] weight_read_bytes,
    output wire projection_event,
    output wire [31:0] projection_bytes,
    output wire source_read_event,
    output wire [31:0] source_read_bytes,
    output wire [63:0] vector_live_bytes, vector_physical_bytes,
    output wire [63:0] controller_bytes, mapping_controller_bytes,
    output wire [63:0] feature_controller_bytes, pool_controller_bytes,
    output wire [63:0] mapping_divider_controller_bytes,
    output wire [63:0] pool_divider_controller_bytes, projection_controller_bytes
);
    localparam [3:0] IDLE = 0, VALIDATE = 1, MAP_START = 2,
        MAP_WAIT = 3, MAP_CHECK = 4, FEATURE_START = 5, FEATURE_WAIT = 6,
        FEATURE_CHECK = 7, PUBLISH = 8, RESPONSE = 9;
    reg [3:0] state;
    reg [1:0] model_hold, precision_hold;
    reg [31:0] generation_hold, patches_hold, rows_hold, columns_hold;
    reg [31:0] count_hold, ordinal_hold, expected_hold, selected_bin, actual_count;
    reg [31:0] received;
    reg [63:0] image_hold, weights_hold;
    reg feature_mask_hold, receive_bad;
    reg [3:0] child_error_hold, error_hold;
    initial begin
        if (COMPACT != 0 && COMPACT != 1)
            $fatal(1, "PARAMETER ERROR: COMPACT must be 0 or 1");
    end
    wire map_ready, map_valid, map_cmd_valid, map_result_ready;
    wire [63:0] map_addr, map_live, map_physical;
    wire [31:0] map_bin, map_count, map_input_bytes;
    wire [3:0] map_error;
    wire map_input_event;
    wire map_selected = rst_n && (state == MAP_START || state == MAP_WAIT);
    anvil_en1_vision_bins mapping (
        .image_immutable(image_immutable === 1'b1),
        .image_invalidate((image_invalidate === 1'b1)),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == MAP_START), .start_ready(map_ready),
        .model(model_hold), .generation(generation_hold), .patches(patches_hold),
        .patch_rows(rows_hold), .patch_columns(columns_hold),
        .pool_count(count_hold), .soft_token(ordinal_hold),
        .expected_soft_tokens(expected_hold), .image_base(image_hold),
        .cmd_valid(map_cmd_valid), .cmd_ready(map_selected && cmd_ready),
        .cmd_write(), .cmd_addr(map_addr), .cmd_wdata(),
        .result_valid(map_selected && result_valid), .result_ready(map_result_ready),
        .result_data(result_data), .result_error(result_error),
        .done_valid(map_valid), .done_ready(rst_n && state == MAP_WAIT),
        .done_pool_index(map_bin), .done_soft_tokens(map_count), .done_error(map_error),
        .input_read_event(map_input_event), .input_read_bytes(map_input_bytes),
        .mask_live_bytes(map_live), .mask_physical_bytes(map_physical),
        .controller_bytes(mapping_controller_bytes),
        .divider_controller_bytes(mapping_divider_controller_bytes)
    );
    wire feature_ready, feature_valid, feature_mask;
    wire feature_cmd_valid, feature_result_ready;
    wire feature_output_valid, feature_output_last;
    wire [15:0] feature_output_data;
    wire [31:0] feature_output_index, feature_input_bytes;
    wire [63:0] feature_addr, feature_live, feature_physical;
    wire [3:0] feature_error;
    wire feature_input_event;
    wire feature_selected = rst_n && (state == FEATURE_START || state == FEATURE_WAIT);
    anvil_en1_vision_feature #(.COMPACT(COMPACT)) feature (
        .image_immutable(image_immutable === 1'b1),
        .image_invalidate((image_invalidate === 1'b1)),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == FEATURE_START), .start_ready(feature_ready),
        .model(model_hold), .precision(precision_hold),
        .generation(generation_hold), .patches(patches_hold),
        .patch_rows(rows_hold), .patch_columns(columns_hold),
        .pool_count(count_hold), .pool_index(selected_bin),
        .image_base(image_hold), .vision_weights_base(weights_hold),
        .source_valid(source_valid), .source_ready(feature_selected && source_ready),
        .source_generation(source_generation), .source_patch(source_patch),
        .source_index(source_index), .source_model(source_model), .source_layer(source_layer),
        .source_rsp_valid(feature_selected && source_rsp_valid),
        .source_rsp_ready(source_rsp_ready),
        .source_rsp_data(source_rsp_data), .source_rsp_error(source_rsp_error),
        .cmd_valid(feature_cmd_valid), .cmd_ready(feature_selected && cmd_ready),
        .cmd_write(), .cmd_addr(feature_addr), .cmd_wdata(),
        .result_valid(feature_selected && result_valid),
        .result_ready(feature_result_ready), .result_data(result_data),
        .result_error(result_error),
        .output_valid(feature_output_valid),
        .output_ready(feature_selected && output_ready),
        .output_index(feature_output_index), .output_data(feature_output_data),
        .output_last(feature_output_last),
        .done_valid(feature_valid), .done_ready(rst_n && state == FEATURE_WAIT),
        .done_mask(feature_mask), .done_error(feature_error),
        .input_read_event(feature_input_event), .input_read_bytes(feature_input_bytes),
        .weight_read_event(weight_read_event), .weight_read_bytes(weight_read_bytes),
        .projection_event(projection_event), .projection_bytes(projection_bytes),
        .source_read_event(source_read_event), .source_read_bytes(source_read_bytes),
        .vector_live_bytes(feature_live), .vector_physical_bytes(feature_physical),
        .controller_bytes(feature_controller_bytes), .pool_controller_bytes(pool_controller_bytes),
        .divider_controller_bytes(pool_divider_controller_bytes),
        .projection_controller_bytes(projection_controller_bytes)
    );
    wire [31:0] hidden_length = COMPACT ? 32'd8 :
        (model_hold == 1 ? 32'd1536 : 32'd2560);
    wire output_accepted = output_valid && output_ready;
    wire beat_good = received < hidden_length && feature_output_index == received &&
        feature_output_last == (received + 1'b1 == hidden_length);
    assign start_ready = rst_n && state == IDLE;
    assign cmd_valid = map_selected ? map_cmd_valid :
        (feature_selected && feature_cmd_valid);
    assign cmd_write = 0;
    assign cmd_addr = !rst_n ? 64'd0 :
        (map_selected ? map_addr : (feature_selected ? feature_addr : 64'd0));
    assign cmd_wdata = 0;
    assign result_ready = map_selected ? map_result_ready :
        (feature_selected && feature_result_ready);
    assign output_valid = feature_selected && feature_output_valid;
    assign output_data = rst_n && feature_selected ? feature_output_data : 16'd0;
    assign output_index = rst_n && feature_selected ? feature_output_index : 32'd0;
    assign output_last = feature_selected && feature_output_last;
    assign done_valid = rst_n && state == RESPONSE;
    assign done_pool_index = rst_n && state == RESPONSE && error_hold == 0 ?
        selected_bin : 32'd0;
    assign done_soft_tokens = rst_n && state == RESPONSE ? actual_count : 32'd0;
    assign done_error = rst_n ? error_hold : 4'd0;
    assign input_read_event = map_input_event || feature_input_event;
    assign input_read_bytes = map_input_bytes + feature_input_bytes;
    assign vector_live_bytes = rst_n ? map_live + feature_live : 64'd0;
    assign vector_physical_bytes = rst_n ? map_physical + feature_physical : 64'd0;
    wire [31:0] CONTROLLER_BITS =
        $bits(state) + $bits(model_hold) + $bits(precision_hold) +
        $bits(generation_hold) + $bits(patches_hold) + $bits(rows_hold) +
        $bits(columns_hold) + $bits(count_hold) + $bits(ordinal_hold) +
        $bits(expected_hold) + $bits(selected_bin) + $bits(actual_count) +
        $bits(received) + $bits(image_hold) + $bits(weights_hold) +
        $bits(feature_mask_hold) + $bits(receive_bad) +
        $bits(child_error_hold) + $bits(error_hold);
    assign controller_bytes = rst_n ? (CONTROLLER_BITS + 7) >> 3 : 64'd0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            model_hold <= 0;
            precision_hold <= 0;
            generation_hold <= 0;
            patches_hold <= 0;
            rows_hold <= 0;
            columns_hold <= 0;
            count_hold <= 0;
            ordinal_hold <= 0;
            expected_hold <= 0;
            selected_bin <= 0;
            actual_count <= 0;
            received <= 0;
            image_hold <= 0;
            weights_hold <= 0;
            feature_mask_hold <= 0;
            receive_bad <= 0;
            child_error_hold <= 0;
            error_hold <= 0;
        end else begin
            if (output_accepted) begin
                if (!beat_good)
                    receive_bad <= 1;
                if (received < hidden_length)
                    received <= received + 1'b1;
            end
            case (state)
                IDLE: if (start_valid && start_ready) begin
                    model_hold <= model;
                    precision_hold <= precision;
                    generation_hold <= generation;
                    patches_hold <= patches;
                    rows_hold <= patch_rows;
                    columns_hold <= patch_columns;
                    count_hold <= pool_count;
                    ordinal_hold <= soft_token;
                    expected_hold <= expected_soft_tokens;
                    image_hold <= image_base;
                    weights_hold <= vision_weights_base;
                    selected_bin <= 0;
                    actual_count <= 0;
                    received <= 0;
                    feature_mask_hold <= 0;
                    receive_bad <= 0;
                    child_error_hold <= 0;
                    error_hold <= 0;
                    state <= VALIDATE;
                end
                VALIDATE: begin
                    if ((model_hold != 1 && model_hold != 2) || precision_hold > 1) begin
                        error_hold <= 6;
                        state <= PUBLISH;
                    end else if (generation_hold == 0 || weights_hold[1:0] != 0) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else
                        state <= MAP_START;
                end
                MAP_START: if (map_ready)
                    state <= MAP_WAIT;
                MAP_WAIT: if (map_valid) begin
                    selected_bin <= map_bin;
                    actual_count <= map_count;
                    child_error_hold <= map_error;
                    state <= MAP_CHECK;
                end
                MAP_CHECK: begin
                    if (child_error_hold != 0) begin
                        error_hold <= child_error_hold;
                        state <= PUBLISH;
                    end else
                        state <= FEATURE_START;
                end
                FEATURE_START: if (feature_ready)
                    state <= FEATURE_WAIT;
                FEATURE_WAIT: if (feature_valid) begin
                    child_error_hold <= feature_error;
                    feature_mask_hold <= feature_mask;
                    state <= FEATURE_CHECK;
                end
                FEATURE_CHECK: begin
                    if (child_error_hold != 0)
                        error_hold <= child_error_hold;
                    else if (!feature_mask_hold || receive_bad || received != hidden_length)
                        error_hold <= 7;
                    state <= PUBLISH;
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
