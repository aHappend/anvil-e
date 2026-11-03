module anvil_en1_vision_feature #(
    parameter integer COMPACT = 0
) (
    input wire image_immutable, image_invalidate,
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] model, precision,
    input wire [31:0] generation, patches, patch_rows, patch_columns,
    input wire [31:0] pool_count, pool_index,
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
    output wire done_mask,
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
    output wire [63:0] controller_bytes, pool_controller_bytes,
    output wire [63:0] divider_controller_bytes, projection_controller_bytes
);
    localparam [3:0] IDLE = 0, VALIDATE = 1, POOL_START = 2,
        POOL_WAIT = 3, POOL_CHECK = 4, PROJECTION_START = 5,
        PROJECTION_WAIT = 6, REGISTER = 7, PUBLISH = 8, RESPONSE = 9;
    localparam [2:0] S_IDLE = 0, S_VALIDATE = 1, S_READ = 2,
        S_CAPTURE = 3, S_RESPONSE = 4;
    reg [3:0] state;
    reg [2:0] source_state;
    reg [1:0] model_hold, precision_hold;
    reg [31:0] generation_hold, patches_hold, rows_hold, columns_hold;
    reg [31:0] count_hold, index_hold, received, bank_index;
    reg [63:0] image_hold, weights_hold;
    reg [15:0] bank_q, bank_data;
    reg mask_hold, receive_bad, vector_visible, vector_allocated, bank_error;
    reg [3:0] child_error_hold, error_hold;
    (* ramstyle = "M20K", nomem2reg *) reg [15:0] pooled [0:767];

    initial begin
        if (COMPACT != 0 && COMPACT != 1)
            $fatal(1, "PARAMETER ERROR: COMPACT must be 0 or 1");
    end
    wire pool_ready, pool_valid, pool_cmd_valid, pool_result_ready;
    wire pool_output_valid, pool_output_last, pool_output_mask;
    wire [31:0] pool_output_index;
    wire [15:0] pool_output_data;
    wire [63:0] pool_addr;
    wire [3:0] pool_error;
    wire pool_selected = rst_n && (state == POOL_START || state == POOL_WAIT);
    anvil_en1_vision_pool pool (
        .image_immutable(image_immutable === 1'b1),
        .image_invalidate((image_invalidate === 1'b1)),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == POOL_START), .start_ready(pool_ready),
        .model(model_hold), .generation(generation_hold), .patches(patches_hold),
        .patch_rows(rows_hold), .patch_columns(columns_hold),
        .pool_count(count_hold), .pool_index(index_hold), .image_base(image_hold),
        .source_valid(source_valid), .source_ready(pool_selected && source_ready),
        .source_generation(source_generation), .source_patch(source_patch),
        .source_index(source_index), .source_model(source_model), .source_layer(source_layer),
        .source_rsp_valid(pool_selected && source_rsp_valid),
        .source_rsp_ready(source_rsp_ready),
        .source_rsp_data(source_rsp_data), .source_rsp_error(source_rsp_error),
        .cmd_valid(pool_cmd_valid), .cmd_ready(pool_selected && cmd_ready),
        .cmd_write(), .cmd_addr(pool_addr), .cmd_wdata(),
        .result_valid(pool_selected && result_valid), .result_ready(pool_result_ready),
        .result_data(result_data), .result_error(result_error),
        .output_valid(pool_output_valid), .output_ready(rst_n && state == POOL_WAIT),
        .output_index(pool_output_index), .output_data(pool_output_data),
        .output_last(pool_output_last), .output_mask(pool_output_mask),
        .done_valid(pool_valid), .done_ready(rst_n && state == POOL_WAIT),
        .done_error(pool_error), .input_read_event(input_read_event),
        .input_read_bytes(input_read_bytes), .source_read_event(source_read_event),
        .source_read_bytes(source_read_bytes), .controller_bytes(pool_controller_bytes),
        .divider_controller_bytes(divider_controller_bytes)
    );
    wire pool_beat_good = received < 768 && pool_output_index == received &&
        pool_output_last == (received == 767) &&
        (received == 0 || pool_output_mask == mask_hold);
    wire projection_ready, projection_valid, projection_source_valid, projection_source_rsp_ready;
    wire [31:0] projection_source_index;
    wire [31:0] projection_generation, projection_token;
    wire [1:0] projection_model, projection_class;
    wire projection_cmd_valid, projection_result_ready;
    wire [63:0] projection_addr, projection_live, projection_physical;
    wire [3:0] projection_error;
    wire projection_selected = rst_n &&
        (state == PROJECTION_START || state == PROJECTION_WAIT);
    anvil_en1_modality_projection #(.COMPACT(COMPACT)) projection (
        .image_immutable(image_immutable === 1'b1),
        .image_invalidate((image_invalidate === 1'b1)),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == PROJECTION_START), .start_ready(projection_ready),
        .model(model_hold), .precision(precision_hold), .image_class(2'd1),
        .generation(generation_hold), .soft_token(index_hold), .weights_base(weights_hold),
        .source_valid(projection_source_valid),
        .source_ready(rst_n && state == PROJECTION_WAIT && source_state == S_IDLE),
        .source_generation(projection_generation), .source_token(projection_token),
        .source_index(projection_source_index), .source_model(projection_model),
        .source_class(projection_class),
        .source_rsp_valid(rst_n && state == PROJECTION_WAIT && source_state == S_RESPONSE),
        .source_rsp_ready(projection_source_rsp_ready), .source_rsp_data(bank_data),
        .source_rsp_error(bank_error),
        .cmd_valid(projection_cmd_valid), .cmd_ready(projection_selected && cmd_ready),
        .cmd_write(), .cmd_addr(projection_addr), .cmd_wdata(),
        .result_valid(projection_selected && result_valid),
        .result_ready(projection_result_ready), .result_data(result_data),
        .result_error(result_error),
        .output_valid(output_valid), .output_ready(projection_selected && output_ready),
        .output_index(output_index), .output_data(output_data), .output_last(output_last),
        .done_valid(projection_valid), .done_ready(rst_n && state == PROJECTION_WAIT),
        .done_error(projection_error), .weight_read_event(weight_read_event),
        .weight_read_bytes(weight_read_bytes),
        .projection_event(projection_event), .projection_bytes(projection_bytes),
        .vector_live_bytes(projection_live), .vector_physical_bytes(projection_physical),
        .controller_bytes(projection_controller_bytes)
    );
    wire source_tag_good = projection_generation == generation_hold &&
        projection_token == index_hold && projection_model == model_hold &&
        projection_class == 1;
    always @(posedge clk) begin
        if (rst_n && state == POOL_WAIT && pool_output_valid &&
            pool_beat_good && !receive_bad)
            pooled[pool_output_index[9:0]] <= pool_output_data;
        if (rst_n && state == PROJECTION_WAIT && source_state == S_READ)
            bank_q <= pooled[bank_index[9:0]];
    end
    assign start_ready = rst_n && state == IDLE;
    assign cmd_valid = pool_selected ? pool_cmd_valid :
        (projection_selected && projection_cmd_valid);
    assign cmd_write = 0;
    assign cmd_addr = !rst_n ? 64'd0 :
        (pool_selected ? pool_addr : (projection_selected ? projection_addr : 64'd0));
    assign cmd_wdata = 0;
    assign result_ready = pool_selected ? pool_result_ready :
        (projection_selected && projection_result_ready);
    assign done_valid = rst_n && state == RESPONSE;
    assign done_mask = rst_n && state == RESPONSE && error_hold == 0 && mask_hold;
    assign done_error = rst_n ? error_hold : 4'd0;
    assign vector_live_bytes = rst_n ?
        (vector_allocated ? 64'd1536 : 64'd0) + projection_live : 64'd0;
    assign vector_physical_bytes = rst_n ? 64'd1536 + projection_physical : 64'd0;
    wire [31:0] CONTROLLER_BITS =
        $bits(state) + $bits(source_state) + $bits(model_hold) + $bits(precision_hold) +
        $bits(generation_hold) + $bits(patches_hold) + $bits(rows_hold) +
        $bits(columns_hold) + $bits(count_hold) + $bits(index_hold) + $bits(received) +
        $bits(bank_index) + $bits(image_hold) + $bits(weights_hold) + $bits(bank_q) +
        $bits(bank_data) + $bits(mask_hold) + $bits(receive_bad) + $bits(vector_visible) +
        $bits(vector_allocated) + $bits(bank_error) + $bits(child_error_hold) + $bits(error_hold);
    assign controller_bytes = rst_n ? (CONTROLLER_BITS + 7) >> 3 : 64'd0;
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
                    bank_error <= !source_tag_good;
                    source_state <= S_VALIDATE;
                end
                S_VALIDATE: begin
                    if (bank_error || !vector_visible || !mask_hold || bank_index >= 768) begin
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
            generation_hold <= 0;
            patches_hold <= 0;
            rows_hold <= 0;
            columns_hold <= 0;
            count_hold <= 0;
            index_hold <= 0;
            received <= 0;
            image_hold <= 0;
            weights_hold <= 0;
            mask_hold <= 0;
            receive_bad <= 0;
            vector_visible <= 0;
            vector_allocated <= 0;
            child_error_hold <= 0;
            error_hold <= 0;
        end else begin
            if (state == POOL_WAIT && pool_output_valid) begin
                if (received == 0)
                    mask_hold <= pool_output_mask;
                if (!pool_beat_good)
                    receive_bad <= 1;
                if (received < 768)
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
                    index_hold <= pool_index;
                    image_hold <= image_base;
                    weights_hold <= vision_weights_base;
                    received <= 0;
                    mask_hold <= 0;
                    receive_bad <= 0;
                    vector_visible <= 0;
                    vector_allocated <= 0;
                    child_error_hold <= 0;
                    error_hold <= 0;
                    state <= VALIDATE;
                end
                VALIDATE: begin
                    if ((model_hold != 1 && model_hold != 2) || precision_hold > 1) begin
                        error_hold <= 6;
                        state <= PUBLISH;
                    end else if (generation_hold == 0 || count_hold == 0 ||
                        index_hold >= count_hold || weights_hold[1:0] != 0) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else
                        state <= POOL_START;
                end
                POOL_START: if (pool_ready) begin
                    vector_allocated <= 1;
                    state <= POOL_WAIT;
                end
                POOL_WAIT: if (pool_valid) begin
                    child_error_hold <= pool_error;
                    state <= POOL_CHECK;
                end
                POOL_CHECK: begin
                    if (child_error_hold != 0) begin
                        error_hold <= child_error_hold;
                        state <= PUBLISH;
                    end else if (receive_bad || received != 768) begin
                        error_hold <= 7;
                        state <= PUBLISH;
                    end else if (!mask_hold)
                        state <= PUBLISH;
                    else begin
                        vector_visible <= 1;
                        state <= PROJECTION_START;
                    end
                end
                PROJECTION_START: if (projection_ready)
                    state <= PROJECTION_WAIT;
                PROJECTION_WAIT: if (projection_valid) begin
                    child_error_hold <= projection_error;
                    state <= REGISTER;
                end
                REGISTER: begin
                    error_hold <= child_error_hold;
                    state <= PUBLISH;
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
