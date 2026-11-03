module anvil_en1_replay_vision_attention (
    input wire image_immutable, image_invalidate,
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] model, precision,
    input wire [31:0] generation, patches, patch_rows, patch_columns, query_patch,
    input wire [7:0] layer, frame_layer,
    input wire [3:0] head,
    input wire [5:0] frame_slot,
    input wire [63:0] image_base, vision_weights_base,
    input wire resume_valid,
    input wire [159:0] continuation,
    output wire need_valid,
    input wire need_ready,
    input wire [1:0] need_action,
    output wire [31:0] need_generation, need_patch,
    output wire [1:0] need_model, need_precision, need_selector,
    output wire [7:0] need_layer,
    output wire [3:0] need_head,
    output wire [9:0] need_component,
    output wire source_valid,
    input wire source_ready,
    output wire [31:0] source_generation, source_patch, source_index,
    output wire [1:0] source_model,
    output wire [7:0] source_layer,
    input wire source_rsp_valid,
    output wire source_rsp_ready,
    input wire [15:0] source_rsp_data,
    input wire source_rsp_error,
    output wire work_req_valid,
    input wire work_req_ready,
    output wire [2:0] work_req_op,
    output wire [1:0] work_req_domain, work_req_target,
    output wire [31:0] work_req_token,
    output wire [7:0] work_req_layer,
    output wire [11:0] work_req_length, work_req_component,
    output wire [5:0] work_req_slot,
    output wire work_req_bank,
    output wire [7:0] work_req_scalar_index,
    output wire [31:0] work_req_data,
    input wire work_rsp_valid,
    output wire work_rsp_ready,
    input wire [31:0] work_rsp_data,
    input wire [3:0] work_rsp_error,
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
    output wire done_yield,
    output wire [159:0] done_continuation,
    output wire [7:0] done_dependency_layer,
    output wire [31:0] done_dependency_patch,
    output wire input_read_event,
    output wire [31:0] input_read_bytes,
    output wire projection_event,
    output wire [31:0] projection_bytes,
    output wire [63:0] controller_bytes, executor_controller_bytes, head_controller_bytes,
    output wire [63:0] tile_controller_bytes, clipped_controller_bytes, clamp_controller_bytes,
    output wire [63:0] tile_live_bytes, tile_physical_bytes
);
    localparam [3:0] IDLE = 0, VALIDATE = 1, RESTORE_SEND = 2,
        RESTORE_WAIT = 3, RESTORE_REGISTER = 4, ENGINE_START = 5,
        ENGINE_RUN = 6, SAVE_SEND = 7, SAVE_WAIT = 8,
        SAVE_REGISTER = 9, PUBLISH = 10, RESPONSE = 11,
        EXTENT_PRODUCT = 12, EXTENT_VALIDATE = 13;
    reg [3:0] state, word_index;
    reg [1:0] model_hold, precision_hold;
    reg [31:0] generation_hold, patches_hold, rows_hold, columns_hold, query_hold, extent_hold;
    reg [7:0] layer_hold, frame_layer_hold;
    reg [3:0] head_hold;
    reg [5:0] frame_slot_hold;
    reg [63:0] image_base_hold, weights_hold;
    reg [159:0] continuation_hold;
    reg [511:0] checkpoint_hold;
    reg resume_hold, yield_hold;
    reg [31:0] scalar_data_hold, dependency_patch_hold;
    reg [3:0] scalar_error_hold, error_hold;

    wire outer_matches = continuation_hold[159:128] == 32'h454e3157 &&
        continuation_hold[127:96] == generation_hold &&
        continuation_hold[95:64] == query_hold &&
        continuation_hold[63:56] == frame_layer_hold &&
        continuation_hold[55:50] == frame_slot_hold &&
        continuation_hold[49:48] == model_hold &&
        continuation_hold[47:46] == precision_hold &&
        continuation_hold[45:38] == layer_hold &&
        continuation_hold[37:34] == head_hold &&
        continuation_hold[33:0] == 0;
    wire [159:0] outer_continuation = {32'h454e3157, generation_hold, query_hold,
        frame_layer_hold, frame_slot_hold, model_hold, precision_hold,
        layer_hold, head_hold, 34'd0};
    wire run = rst_n && state == ENGINE_RUN;
    wire engine_ready, engine_valid, engine_checkpoint_valid;
    wire engine_need_valid;
    wire [511:0] engine_checkpoint;
    wire [3:0] engine_error;
    anvil_en1_vision_attention_execute #(.REPLAY(1)) executor (
        .image_immutable(image_immutable === 1'b1),
        .image_invalidate((image_invalidate === 1'b1)),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == ENGINE_START), .start_ready(engine_ready),
        .model(model_hold), .precision(precision_hold), .generation(generation_hold),
        .patches(patches_hold), .patch_rows(rows_hold), .patch_columns(columns_hold),
        .query_patch(query_hold), .layer(layer_hold), .head(head_hold),
        .image_base(image_base_hold), .vision_weights_base(weights_hold),
        .resume_valid(resume_hold), .resume_checkpoint(checkpoint_hold),
        .need_valid(engine_need_valid), .need_ready(run && need_ready),
        .need_action(need_action),
        .need_generation(need_generation), .need_patch(need_patch),
        .need_model(need_model), .need_precision(need_precision), .need_selector(need_selector),
        .need_layer(need_layer), .need_head(need_head), .need_component(need_component),
        .checkpoint_valid(engine_checkpoint_valid), .checkpoint_ready(run),
        .checkpoint_data(engine_checkpoint),
        .source_valid(source_valid), .source_ready(run && source_ready),
        .source_generation(source_generation), .source_patch(source_patch), .source_index(source_index),
        .source_model(source_model), .source_layer(source_layer),
        .source_rsp_valid(run && source_rsp_valid), .source_rsp_ready(source_rsp_ready),
        .source_rsp_data(source_rsp_data), .source_rsp_error(source_rsp_error),
        .cmd_valid(cmd_valid), .cmd_ready(run && cmd_ready),
        .cmd_write(cmd_write), .cmd_addr(cmd_addr), .cmd_wdata(cmd_wdata),
        .result_valid(run && result_valid), .result_ready(result_ready),
        .result_data(result_data), .result_error(result_error),
        .output_valid(output_valid), .output_ready(run && output_ready),
        .output_index(output_index), .output_data(output_data), .output_last(output_last),
        .done_valid(engine_valid), .done_ready(run), .done_error(engine_error),
        .input_read_event(input_read_event), .input_read_bytes(input_read_bytes),
        .projection_event(projection_event), .projection_bytes(projection_bytes),
        .controller_bytes(executor_controller_bytes), .head_controller_bytes(head_controller_bytes),
        .tile_controller_bytes(tile_controller_bytes), .clipped_controller_bytes(clipped_controller_bytes),
        .clamp_controller_bytes(clamp_controller_bytes),
        .tile_live_bytes(tile_live_bytes), .tile_physical_bytes(tile_physical_bytes)
    );

    assign start_ready = rst_n && state == IDLE;
    assign need_valid = run && engine_need_valid;
    assign work_req_valid = rst_n && (state == SAVE_SEND || state == RESTORE_SEND);
    assign work_req_op = !rst_n ? 3'd0 : (state == SAVE_SEND ? 3'd6 : 3'd7);
    assign work_req_domain = rst_n ? 2'd1 : 2'd0;
    assign work_req_target = 0;
    assign work_req_token = rst_n ? query_hold : 32'd0;
    assign work_req_layer = rst_n ? frame_layer_hold : 8'd0;
    assign work_req_length = rst_n ? 12'd768 : 12'd0;
    assign work_req_component = 0;
    assign work_req_slot = rst_n ? frame_slot_hold : 6'd0;
    assign work_req_bank = 0;
    assign work_req_scalar_index = rst_n ? {4'd0, word_index} + 8'd8 : 8'd0;
    assign work_req_data = rst_n && state == SAVE_SEND ?
        checkpoint_hold[{word_index, 5'd0} +: 32] : 32'd0;
    assign work_rsp_ready = rst_n && (state == SAVE_WAIT || state == RESTORE_WAIT);
    assign done_valid = rst_n && state == RESPONSE;
    assign done_error = rst_n ? error_hold : 4'd0;
    assign done_yield = rst_n && yield_hold && error_hold == 0;
    assign done_continuation = done_yield ? outer_continuation : 160'd0;
    assign done_dependency_layer = done_yield ? layer_hold : 8'd0;
    assign done_dependency_patch = done_yield ? dependency_patch_hold : 32'd0;
    wire [31:0] CONTROLLER_BITS =
        $bits(state) + $bits(word_index) + $bits(model_hold) + $bits(precision_hold) +
        $bits(generation_hold) + $bits(patches_hold) + $bits(rows_hold) +
        $bits(columns_hold) + $bits(query_hold) + $bits(extent_hold) + $bits(layer_hold) +
        $bits(frame_layer_hold) + $bits(head_hold) + $bits(frame_slot_hold) +
        $bits(image_base_hold) + $bits(weights_hold) + $bits(continuation_hold) +
        $bits(checkpoint_hold) + $bits(resume_hold) + $bits(yield_hold) +
        $bits(scalar_data_hold) + $bits(dependency_patch_hold) +
        $bits(scalar_error_hold) + $bits(error_hold);
    assign controller_bytes = rst_n ? (CONTROLLER_BITS + 7) >> 3 : 64'd0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            word_index <= 0;
            model_hold <= 0;
            precision_hold <= 0;
            generation_hold <= 0;
            patches_hold <= 0;
            rows_hold <= 0;
            columns_hold <= 0;
            query_hold <= 0;
            extent_hold <= 0;
            layer_hold <= 0;
            frame_layer_hold <= 0;
            head_hold <= 0;
            frame_slot_hold <= 0;
            image_base_hold <= 0;
            weights_hold <= 0;
            continuation_hold <= 0;
            checkpoint_hold <= 0;
            resume_hold <= 0;
            yield_hold <= 0;
            scalar_data_hold <= 0;
            dependency_patch_hold <= 0;
            scalar_error_hold <= 0;
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
                    frame_layer_hold <= frame_layer;
                    head_hold <= head;
                    frame_slot_hold <= frame_slot;
                    image_base_hold <= image_base;
                    weights_hold <= vision_weights_base;
                    continuation_hold <= continuation;
                    checkpoint_hold <= 0;
                    resume_hold <= resume_valid;
                    yield_hold <= 0;
                    dependency_patch_hold <= 0;
                    word_index <= 0;
                    scalar_error_hold <= 0;
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
                    end else if (frame_layer_hold == 0 || frame_layer_hold > 16 ||
                        {1'b0, layer_hold} + 9'd1 != {1'b0, frame_layer_hold} ||
                        (resume_hold && !outer_matches)) begin
                        error_hold <= 7;
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
                    end else if (resume_hold)
                        state <= RESTORE_SEND;
                    else
                        state <= ENGINE_START;
                end
                RESTORE_SEND: if (work_req_valid && work_req_ready)
                    state <= RESTORE_WAIT;
                RESTORE_WAIT: if (work_rsp_valid && work_rsp_ready) begin
                    scalar_data_hold <= work_rsp_data;
                    scalar_error_hold <= work_rsp_error;
                    state <= RESTORE_REGISTER;
                end
                RESTORE_REGISTER: begin
                    if (scalar_error_hold != 0) begin
                        error_hold <= scalar_error_hold;
                        state <= PUBLISH;
                    end else begin
                        checkpoint_hold[{word_index, 5'd0} +: 32] <= scalar_data_hold;
                        if (word_index == 15)
                            state <= ENGINE_START;
                        else begin
                            word_index <= word_index + 1'b1;
                            state <= RESTORE_SEND;
                        end
                    end
                end
                ENGINE_START: if (engine_ready)
                    state <= ENGINE_RUN;
                ENGINE_RUN: begin
                    if (engine_checkpoint_valid) begin
                        checkpoint_hold <= engine_checkpoint;
                        dependency_patch_hold <= need_patch;
                        word_index <= 0;
                        state <= SAVE_SEND;
                    end else if (engine_valid) begin
                        error_hold <= engine_error;
                        state <= PUBLISH;
                    end
                end
                SAVE_SEND: if (work_req_valid && work_req_ready)
                    state <= SAVE_WAIT;
                SAVE_WAIT: if (work_rsp_valid && work_rsp_ready) begin
                    scalar_error_hold <= work_rsp_error;
                    state <= SAVE_REGISTER;
                end
                SAVE_REGISTER: begin
                    if (scalar_error_hold != 0) begin
                        error_hold <= scalar_error_hold;
                        state <= PUBLISH;
                    end else if (word_index == 15) begin
                        yield_hold <= 1;
                        state <= PUBLISH;
                    end else begin
                        word_index <= word_index + 1'b1;
                        state <= SAVE_SEND;
                    end
                end
                PUBLISH: state <= RESPONSE;
                RESPONSE: if (done_valid && done_ready)
                    state <= IDLE;
                default: begin
                    yield_hold <= 0;
                    error_hold <= 7;
                    state <= PUBLISH;
                end
            endcase
        end
    end
endmodule
