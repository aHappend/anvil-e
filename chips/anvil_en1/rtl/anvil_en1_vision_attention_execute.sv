module anvil_en1_vision_attention_execute #(
    parameter integer REPLAY = 0
) (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] model, precision,
    input wire [31:0] generation, patches, patch_rows, patch_columns, query_patch,
    input wire [7:0] layer,
    input wire [3:0] head,
    input wire [63:0] image_base, vision_weights_base,
    input wire resume_valid,
    input wire [511:0] resume_checkpoint,
    output wire need_valid,
    input wire need_ready,
    input wire [1:0] need_action,
    output wire [31:0] need_generation, need_patch,
    output wire [1:0] need_model, need_precision, need_selector,
    output wire [7:0] need_layer,
    output wire [3:0] need_head,
    output wire [9:0] need_component,
    output wire checkpoint_valid,
    input wire checkpoint_ready,
    output wire [511:0] checkpoint_data,
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
    output wire [9:0] output_index,
    output wire [15:0] output_data,
    output wire output_last,
    output wire done_valid,
    input wire done_ready,
    output wire [3:0] done_error,
    output wire input_read_event,
    output wire [31:0] input_read_bytes,
    output wire projection_event,
    output wire [31:0] projection_bytes,
    output wire [63:0] controller_bytes, head_controller_bytes,
    output wire [63:0] tile_controller_bytes, clipped_controller_bytes, clamp_controller_bytes,
    output wire [63:0] tile_live_bytes, tile_physical_bytes
);
    localparam [3:0] IDLE = 0, VALIDATE = 1, EXTENT_PRODUCT = 2,
        EXTENT_VALIDATE = 3, LOOKUP_START = 4, LOOKUP_WAIT = 5,
        HEAD_START = 6, HEAD_RUN = 7, PUBLISH = 8, RESPONSE = 9;
    localparam [4:0] S_IDLE = 0, S_OFFSET = 1, S_ADDRESS = 2,
        S_X_SEND = 3, S_X_WAIT = 4, S_X_REGISTER = 5, S_Y_ADDRESS = 6,
        S_Y_SEND = 7, S_Y_WAIT = 8, S_Y_REGISTER = 9, S_VALIDATE = 10,
        S_TILE_START = 11, S_TILE_WAIT = 12, S_TILE_REGISTER = 13,
        S_MASK_RESPONSE = 14, S_TILE_RESPONSE = 15,
        S_END = 16, S_CHECK = 17;
    reg [3:0] state;
    reg [4:0] service_state;
    reg [1:0] model_hold, precision_hold, selector_hold;
    reg [31:0] generation_hold, patches_hold, rows_hold, columns_hold, query_hold;
    reg [31:0] extent_hold, service_patch, x_hold, y_hold, word_hold;
    reg [7:0] layer_hold;
    reg [3:0] head_hold;
    reg [9:0] component_hold;
    reg [63:0] image_base_hold, weights_hold, coords_base, coords_bytes;
    reg [63:0] coord_offset, coord_address;
    reg [64:0] coord_start_hold, coord_end_hold, payload_end_hold;
    reg service_mask, mask_data_hold, memory_error_hold, resume_hold;
    reg [511:0] checkpoint_hold;
    reg [31:0] tile_data_hold;
    reg [3:0] service_error_hold, first_service_error, error_hold;

    initial begin
        if (REPLAY != 0 && REPLAY != 1)
            $fatal(1, "PARAMETER ERROR: REPLAY must be 0 or 1");
    end

    wire lookup_ready, lookup_valid, lookup_cmd_valid, lookup_result_ready;
    wire [63:0] lookup_cmd_addr, lookup_base, lookup_bytes;
    wire [3:0] lookup_error;
    wire lookup_selected = rst_n && (state == LOOKUP_START || state == LOOKUP_WAIT);
    wire [63:0] primitive_directory_bytes;
    anvil_en1_tensor_image directory (
        .controller_bytes(primitive_directory_bytes),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == LOOKUP_START), .start_ready(lookup_ready),
        .model(model_hold), .precision(2'd0), .image_class(2'd3),
        .input_audio(1'b0), .input_items(patches_hold), .image_base(image_base_hold),
        .tensor_kind(16'h3001), .tensor_layer(16'hffff),
        .cmd_valid(lookup_cmd_valid), .cmd_ready(lookup_selected && cmd_ready),
        .cmd_write(), .cmd_addr(lookup_cmd_addr), .cmd_wdata(),
        .result_valid(lookup_selected && result_valid), .result_ready(lookup_result_ready),
        .result_data(result_data), .result_error(result_error),
        .done_valid(lookup_valid), .done_ready(rst_n && state == LOOKUP_WAIT),
        .done_base(lookup_base), .done_bytes(lookup_bytes), .done_rows(),
        .done_columns(), .done_stride(), .done_type(), .done_error(lookup_error)
    );

    wire head_ready, head_valid, head_mask_valid, head_mask_rsp_ready;
    wire head_need_valid, head_qkv_valid, head_qkv_rsp_ready, head_checkpoint_valid;
    wire [31:0] head_mask_patch, head_qkv_patch;
    wire [1:0] head_qkv_model, head_qkv_precision, head_qkv_selector;
    wire [7:0] head_qkv_layer;
    wire [3:0] head_qkv_head, head_error;
    wire [9:0] head_qkv_component;
    wire [511:0] head_checkpoint;
    wire run = rst_n && state == HEAD_RUN;
    wire service_idle = service_state == S_IDLE;
    anvil_en1_vision_attention_head #(.REPLAY(REPLAY)) attention (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == HEAD_START), .start_ready(head_ready),
        .model(model_hold), .precision(precision_hold), .generation(generation_hold),
        .patches(patches_hold), .query_patch(query_hold), .layer(layer_hold), .head(head_hold),
        .resume_valid(resume_hold), .resume_checkpoint(checkpoint_hold),
        .mask_valid(head_mask_valid), .mask_ready(run && service_idle),
        .mask_patch(head_mask_patch),
        .mask_rsp_valid(run && service_state == S_MASK_RESPONSE),
        .mask_rsp_ready(head_mask_rsp_ready),
        .mask_rsp_data(mask_data_hold), .mask_rsp_error(service_error_hold != 0),
        .need_valid(head_need_valid), .need_ready(run && service_idle && need_ready),
        .need_action(need_action),
        .qkv_valid(head_qkv_valid), .qkv_ready(run && service_idle),
        .qkv_model(head_qkv_model), .qkv_precision(head_qkv_precision),
        .qkv_selector(head_qkv_selector), .qkv_patch(head_qkv_patch),
        .qkv_layer(head_qkv_layer), .qkv_head(head_qkv_head),
        .qkv_component(head_qkv_component),
        .qkv_rsp_valid(run && service_state == S_TILE_RESPONSE),
        .qkv_rsp_ready(head_qkv_rsp_ready),
        .qkv_rsp_data(tile_data_hold), .qkv_rsp_error(service_error_hold),
        .checkpoint_valid(head_checkpoint_valid),
        .checkpoint_ready(run && service_idle && checkpoint_ready),
        .checkpoint_data(head_checkpoint),
        .output_valid(output_valid), .output_ready(run && output_ready),
        .output_index(output_index), .output_data(output_data), .output_last(output_last),
        .done_valid(head_valid), .done_ready(run && service_idle),
        .done_error(head_error), .controller_bytes(head_controller_bytes)
    );

    wire tile_ready, tile_valid, tile_cmd_valid, tile_result_ready;
    wire [63:0] tile_cmd_addr;
    wire [31:0] tile_data;
    wire [3:0] tile_error;
    wire tile_selected = run &&
        (service_state == S_TILE_START || service_state == S_TILE_WAIT);
    anvil_en1_vision_qkv_tile tile (
        .clk(clk), .rst_n(rst_n),
        .start_valid(run && service_state == S_TILE_START), .start_ready(tile_ready),
        .model(model_hold), .precision(precision_hold), .selector(selector_hold),
        .layer(layer_hold), .patch(service_patch), .patch_x(x_hold), .patch_y(y_hold),
        .head(head_hold), .component(component_hold), .vision_weights_base(weights_hold),
        .source_valid(source_valid), .source_ready(tile_selected && source_ready),
        .source_model(source_model), .source_layer(source_layer), .source_patch(source_patch),
        .source_index(source_index),
        .source_rsp_valid(tile_selected && source_rsp_valid),
        .source_rsp_ready(source_rsp_ready),
        .source_rsp_data(source_rsp_data), .source_rsp_error(source_rsp_error),
        .cmd_valid(tile_cmd_valid), .cmd_ready(tile_selected && cmd_ready),
        .cmd_write(), .cmd_addr(tile_cmd_addr), .cmd_wdata(),
        .result_valid(tile_selected && result_valid), .result_ready(tile_result_ready),
        .result_data(result_data), .result_error(result_error),
        .done_valid(tile_valid), .done_ready(run && service_state == S_TILE_WAIT),
        .done_data(tile_data), .done_error(tile_error),
        .projection_event(projection_event), .projection_bytes(projection_bytes),
        .vector_live_bytes(tile_live_bytes), .vector_physical_bytes(tile_physical_bytes),
        .controller_bytes(tile_controller_bytes), .clipped_controller_bytes(clipped_controller_bytes),
        .clamp_controller_bytes(clamp_controller_bytes)
    );

    wire coord_send = run && (service_state == S_X_SEND || service_state == S_Y_SEND);
    wire coord_wait = run && (service_state == S_X_WAIT || service_state == S_Y_WAIT);
    wire [64:0] coord_sum = {1'b0, coords_base} + {1'b0, coord_offset};
    wire [64:0] coord_end = coord_start_hold + 65'd8;
    wire [64:0] payload_end = {1'b0, coords_base} + {1'b0, coords_bytes};
    wire [64:0] y_sum = {1'b0, coord_address} + 65'd4;
    wire coordinates_padding = x_hold == 32'hffffffff && y_hold == 32'hffffffff;
    wire coordinates_in_range = !x_hold[31] && !y_hold[31] &&
        x_hold < columns_hold && y_hold < rows_hold;
    assign start_ready = rst_n && state == IDLE;
    assign need_valid = run && service_idle && head_need_valid;
    assign need_generation = rst_n ? generation_hold : 32'd0;
    assign need_patch = rst_n ? head_qkv_patch : 32'd0;
    assign need_model = rst_n ? head_qkv_model : 2'd0;
    assign need_precision = rst_n ? head_qkv_precision : 2'd0;
    assign need_selector = rst_n ? head_qkv_selector : 2'd0;
    assign need_layer = rst_n ? head_qkv_layer : 8'd0;
    assign need_head = rst_n ? head_qkv_head : 4'd0;
    assign need_component = rst_n ? head_qkv_component : 10'd0;
    assign checkpoint_valid = run && service_idle && head_checkpoint_valid;
    assign checkpoint_data = rst_n ? head_checkpoint : 512'd0;
    assign source_generation = rst_n ? generation_hold : 32'd0;
    assign cmd_valid = rst_n && (lookup_selected ? lookup_cmd_valid :
        (tile_selected ? tile_cmd_valid : coord_send));
    assign cmd_write = 0;
    assign cmd_addr = !rst_n ? 64'd0 : (lookup_selected ? lookup_cmd_addr :
        (tile_selected ? tile_cmd_addr : coord_address));
    assign cmd_wdata = 0;
    assign result_ready = rst_n && (lookup_selected ? lookup_result_ready :
        (tile_selected ? tile_result_ready : coord_wait));
    assign done_valid = rst_n && state == RESPONSE;
    assign done_error = rst_n ? error_hold : 4'd0;
    assign input_read_event = rst_n && cmd_valid && cmd_ready &&
        (lookup_selected || coord_send);
    assign input_read_bytes = input_read_event ? 32'd4 : 32'd0;
    localparam integer CONTROLLER_BITS =
        $bits(state) + $bits(service_state) + $bits(model_hold) +
        $bits(precision_hold) + $bits(selector_hold) + $bits(generation_hold) +
        $bits(patches_hold) + $bits(rows_hold) + $bits(columns_hold) + $bits(query_hold) +
        $bits(extent_hold) + $bits(service_patch) + $bits(x_hold) + $bits(y_hold) +
        $bits(word_hold) + $bits(layer_hold) + $bits(head_hold) + $bits(component_hold) +
        $bits(image_base_hold) + $bits(weights_hold) + $bits(coords_base) +
        $bits(coords_bytes) + $bits(coord_offset) + $bits(coord_address) +
        $bits(coord_start_hold) + $bits(coord_end_hold) + $bits(payload_end_hold) +
        $bits(service_mask) + $bits(mask_data_hold) + $bits(memory_error_hold) +
        $bits(resume_hold) + $bits(checkpoint_hold) + $bits(tile_data_hold) +
        $bits(service_error_hold) + $bits(first_service_error) + $bits(error_hold);
    assign controller_bytes = !rst_n ? 64'd0 :
        64'((CONTROLLER_BITS + 7) >> 3) + primitive_directory_bytes;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            service_state <= S_IDLE;
            selector_hold <= 0;
            service_patch <= 0;
            x_hold <= 0;
            y_hold <= 0;
            word_hold <= 0;
            component_hold <= 0;
            coord_offset <= 0;
            coord_address <= 0;
            coord_start_hold <= 0;
            coord_end_hold <= 0;
            payload_end_hold <= 0;
            service_mask <= 0;
            mask_data_hold <= 0;
            memory_error_hold <= 0;
            tile_data_hold <= 0;
            service_error_hold <= 0;
            first_service_error <= 0;
        end else begin
            if (state == IDLE && start_valid && start_ready)
                first_service_error <= 0;
            case (service_state)
                S_IDLE: if (run && head_mask_valid) begin
                    service_mask <= 1;
                    service_patch <= head_mask_patch;
                    mask_data_hold <= 0;
                    service_error_hold <= 0;
                    service_state <= S_OFFSET;
                end else if (run && head_qkv_valid) begin
                    service_mask <= 0;
                    service_patch <= head_qkv_patch;
                    selector_hold <= head_qkv_selector;
                    component_hold <= head_qkv_component;
                    tile_data_hold <= 0;
                    service_error_hold <= 0;
                    service_state <= S_OFFSET;
                end
                S_OFFSET: begin
                    if (service_patch >= patches_hold) begin
                        service_error_hold <= 5;
                        if (first_service_error == 0)
                            first_service_error <= 5;
                        if (service_mask)
                            service_state <= S_MASK_RESPONSE;
                        else
                            service_state <= S_TILE_RESPONSE;
                    end else begin
                        coord_offset <= {29'd0, service_patch, 3'd0};
                        service_state <= S_ADDRESS;
                    end
                end
                S_ADDRESS: begin
                    coord_start_hold <= coord_sum;
                    service_state <= S_END;
                end
                S_END: begin
                    coord_end_hold <= coord_end;
                    payload_end_hold <= payload_end;
                    service_state <= S_CHECK;
                end
                S_CHECK: begin
                    if (coords_base[1:0] != 0 || coord_start_hold[64] ||
                        coord_end_hold[64] || payload_end_hold[64] ||
                        coord_end_hold > payload_end_hold) begin
                        service_error_hold <= 5;
                        if (first_service_error == 0)
                            first_service_error <= 5;
                        if (service_mask)
                            service_state <= S_MASK_RESPONSE;
                        else
                            service_state <= S_TILE_RESPONSE;
                    end else begin
                        coord_address <= coord_start_hold[63:0];
                        service_state <= S_X_SEND;
                    end
                end
                S_X_SEND: if (cmd_valid && cmd_ready)
                    service_state <= S_X_WAIT;
                S_X_WAIT: if (result_valid && result_ready) begin
                    word_hold <= result_data;
                    memory_error_hold <= result_error;
                    service_state <= S_X_REGISTER;
                end
                S_X_REGISTER: begin
                    if (memory_error_hold) begin
                        service_error_hold <= 2;
                        if (first_service_error == 0)
                            first_service_error <= 2;
                        if (service_mask)
                            service_state <= S_MASK_RESPONSE;
                        else
                            service_state <= S_TILE_RESPONSE;
                    end else begin
                        x_hold <= word_hold;
                        service_state <= S_Y_ADDRESS;
                    end
                end
                S_Y_ADDRESS: begin
                    if (y_sum[64]) begin
                        service_error_hold <= 5;
                        if (first_service_error == 0)
                            first_service_error <= 5;
                        if (service_mask)
                            service_state <= S_MASK_RESPONSE;
                        else
                            service_state <= S_TILE_RESPONSE;
                    end else begin
                        coord_address <= y_sum[63:0];
                        service_state <= S_Y_SEND;
                    end
                end
                S_Y_SEND: if (cmd_valid && cmd_ready)
                    service_state <= S_Y_WAIT;
                S_Y_WAIT: if (result_valid && result_ready) begin
                    word_hold <= result_data;
                    memory_error_hold <= result_error;
                    service_state <= S_Y_REGISTER;
                end
                S_Y_REGISTER: begin
                    if (memory_error_hold) begin
                        service_error_hold <= 2;
                        if (first_service_error == 0)
                            first_service_error <= 2;
                        if (service_mask)
                            service_state <= S_MASK_RESPONSE;
                        else
                            service_state <= S_TILE_RESPONSE;
                    end else begin
                        y_hold <= word_hold;
                        service_state <= S_VALIDATE;
                    end
                end
                S_VALIDATE: begin
                    if (!coordinates_padding && !coordinates_in_range) begin
                        service_error_hold <= 5;
                        if (first_service_error == 0)
                            first_service_error <= 5;
                        if (service_mask)
                            service_state <= S_MASK_RESPONSE;
                        else
                            service_state <= S_TILE_RESPONSE;
                    end else if (service_mask) begin
                        mask_data_hold <= !coordinates_padding;
                        service_state <= S_MASK_RESPONSE;
                    end else if (selector_hold > 2 || component_hold[0] ||
                        component_hold >= 64) begin
                        service_error_hold <= 7;
                        if (first_service_error == 0)
                            first_service_error <= 7;
                        service_state <= S_TILE_RESPONSE;
                    end else
                        service_state <= S_TILE_START;
                end
                S_TILE_START: if (tile_ready)
                    service_state <= S_TILE_WAIT;
                S_TILE_WAIT: if (tile_valid) begin
                    tile_data_hold <= tile_data;
                    service_error_hold <= tile_error;
                    if (tile_error != 0 && first_service_error == 0)
                        first_service_error <= tile_error;
                    service_state <= S_TILE_REGISTER;
                end
                S_TILE_REGISTER: service_state <= S_TILE_RESPONSE;
                S_MASK_RESPONSE: if (run && head_mask_rsp_ready)
                    service_state <= S_IDLE;
                S_TILE_RESPONSE: if (run && head_qkv_rsp_ready)
                    service_state <= S_IDLE;
                default: begin
                    mask_data_hold <= 0;
                    tile_data_hold <= 0;
                    service_error_hold <= 7;
                    if (first_service_error == 0)
                        first_service_error <= 7;
                    if (service_mask)
                        service_state <= S_MASK_RESPONSE;
                    else
                        service_state <= S_TILE_RESPONSE;
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
            head_hold <= 0;
            image_base_hold <= 0;
            weights_hold <= 0;
            coords_base <= 0;
            coords_bytes <= 0;
            resume_hold <= 0;
            checkpoint_hold <= 0;
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
                    head_hold <= head;
                    image_base_hold <= image_base;
                    weights_hold <= vision_weights_base;
                    resume_hold <= REPLAY && resume_valid;
                    if (REPLAY)
                        checkpoint_hold <= resume_checkpoint;
                    error_hold <= 0;
                    state <= VALIDATE;
                end
                VALIDATE: begin
                    if ((model_hold != 1 && model_hold != 2) || precision_hold > 1) begin
                        error_hold <= 6;
                        state <= PUBLISH;
                    end else if (patches_hold == 0 || patches_hold > 131072 ||
                        query_hold >= patches_hold || layer_hold >= 16 || head_hold >= 12 ||
                        rows_hold == 0 || rows_hold > 10240 ||
                        columns_hold == 0 || columns_hold > 10240 ||
                        image_base_hold[1:0] != 0 || weights_hold[1:0] != 0) begin
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
                        state <= LOOKUP_START;
                end
                LOOKUP_START: if (lookup_ready)
                    state <= LOOKUP_WAIT;
                LOOKUP_WAIT: if (lookup_valid) begin
                    if (lookup_error != 0) begin
                        error_hold <= lookup_error;
                        state <= PUBLISH;
                    end else begin
                        coords_base <= lookup_base;
                        coords_bytes <= lookup_bytes;
                        state <= HEAD_START;
                    end
                end
                HEAD_START: if (head_ready)
                    state <= HEAD_RUN;
                HEAD_RUN: begin
                    if (checkpoint_valid && checkpoint_ready)
                        state <= IDLE;
                    else if (head_valid && service_idle) begin
                        error_hold <= first_service_error != 0 ? first_service_error : head_error;
                        state <= PUBLISH;
                    end
                end
                PUBLISH: state <= RESPONSE;
                RESPONSE: if (done_valid && done_ready)
                    state <= IDLE;
                default: begin
                    error_hold <= 7;
                    state <= PUBLISH;
                end
            endcase
        end
    end
endmodule
