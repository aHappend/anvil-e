module anvil_en1_replay_attention_projection #(
    parameter integer COMPACT = 0
) (
    input wire image_immutable, image_invalidate,
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] model, precision,
    input wire [7:0] layer, frame_layer,
    input wire [31:0] token, tokens,
    input wire [63:0] weights_base,
    input wire [5:0] frame_slot,
    input wire input_bank, output_bank,
    input wire resume_valid,
    input wire [159:0] continuation,
    input wire dependency_valid,
    input wire [1:0] dependency_domain,
    input wire [7:0] dependency_layer,
    input wire [31:0] dependency_token,
    input wire [11:0] dependency_length,
    input wire [5:0] dependency_slot,
    output wire mask_valid,
    input wire mask_ready,
    output wire [31:0] mask_token,
    input wire mask_rsp_valid,
    output wire mask_rsp_ready,
    input wire mask_rsp_data, mask_rsp_error,
    output wire req_valid,
    input wire req_ready,
    output wire [2:0] req_op,
    output wire [1:0] req_model,
    output wire [7:0] req_layer,
    output wire [31:0] req_token,
    output wire req_is_value,
    output wire [1:0] req_kv_head,
    output wire [9:0] req_component,
    output wire [63:0] req_base,
    input wire rsp_valid,
    output wire rsp_ready,
    input wire [63:0] rsp_addr,
    input wire [7:0] rsp_owner,
    input wire rsp_alias,
    input wire [3:0] rsp_error,
    input wire [1:0] rsp_space,
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
    output wire done_valid,
    input wire done_ready,
    output wire [3:0] done_error,
    output wire done_yield, done_bank,
    output wire [159:0] done_continuation,
    output wire [7:0] done_dependency_layer,
    output wire [31:0] done_dependency_token,
    output wire owner_reprojection_event,
    output wire [31:0] owner_reprojection_bytes,
    output wire query_projection_event,
    output wire [31:0] query_projection_bytes,
    output wire source_read_event,
    output wire [31:0] source_read_bytes,
    output wire [63:0] controller_state_bytes,
    output wire [63:0] executor_controller_bytes, checkpoint_controller_bytes,
    output wire [63:0] tile_controller_bytes, tile_live_bytes, tile_physical_bytes,
    output wire [63:0] tile_shadow_bytes,
    output wire [3:0] attention_activity,
    output wire busy
);
    localparam [4:0] IDLE = 0, VALIDATE = 1, LOOKUP_START = 2,
        LOOKUP_WAIT = 3, LOOKUP_REGISTER = 4, RESTORE_SEND = 5,
        RESTORE_WAIT = 6, RESTORE_REGISTER = 7, HEAD_START = 8,
        HEAD_RUN = 9, WEIGHT_START = 10, WEIGHT_WAIT = 11,
        COLUMN_MULTIPLY = 12, COLUMN_ADD = 13, COLUMN_COMMIT = 14,
        FP_START = 15, FP_WAIT = 16, ROW_NARROW = 17, ROW_PACK = 18,
        PAIR_SEND = 19, PAIR_WAIT = 20, PAIR_REGISTER = 21,
        SAVE_SEND = 22, SAVE_WAIT = 23, SAVE_REGISTER = 24,
        DRAIN_HEAD = 25, PUBLISH = 26, RESPONSE = 27;
    localparam [31:0] CONTINUATION_MAGIC = 32'h454e3150;
    reg [4:0] state, fp_return;
    reg [1:0] model_hold, precision_hold, dependency_domain_hold;
    reg [7:0] layer_hold, frame_layer_hold, dependency_layer_hold;
    reg [31:0] token_hold, tokens_hold, dependency_token_hold;
    reg [63:0] weights_hold;
    reg [5:0] slot_hold, dependency_slot_hold;
    reg input_bank_hold, output_bank_hold, resume_hold, dependency_valid_hold;
    reg [11:0] length_hold, dependency_length_hold, row;
    reg [3:0] head;
    reg [9:0] component, dimension_hold;
    reg [31:0] sum, weight_hold, fp_a, fp_b, fp_value, pair_hold, scalar_hold;
    reg [15:0] low_hold, element_hold;
    reg [2:0] fp_op, word_index;
    reg [63:0] matrix_base, matrix_bytes;
    reg [31:0] matrix_rows, matrix_columns, matrix_stride;
    reg [159:0] outer_hold, inner_hold;
    reg [3:0] error_hold, work_error_hold;
    reg head_active, yield_hold;
    reg [7:0] dependency_owner_hold;
    reg [31:0] dependency_position_hold;
    wire [63:0] lookup_controller_bytes, weight_controller_bytes, fp_controller_bytes;

    initial begin
        if (COMPACT != 0 && COMPACT != 1)
            $fatal(1, "PARAMETER ERROR: COMPACT must be 0 or 1");
    end

    wire native_model, global_layer;
    wire [7:0] layers;
    wire [11:0] selected_hidden;
    anvil_en1_geometry geometry (
        .rst_n(rst_n), .model(model_hold), .layer(layer_hold),
        .is_native(native_model), .layers(layers), .owners(), .owner(),
        .is_global(global_layer), .hidden(selected_hidden), .intermediate()
    );
    wire [11:0] selected_length = COMPACT ? 12'd8 : selected_hidden;
    wire [9:0] selected_dimension = COMPACT ?
        (global_layer ? 10'd8 : 10'd4) :
        (global_layer ? 10'd512 : 10'd256);
    wire [3:0] query_heads = COMPACT ? 4'd2 : 4'd8;
    wire descriptor_valid = layer_hold < layers && tokens_hold != 0 &&
        tokens_hold <= 131072 && token_hold < tokens_hold && weights_hold[1:0] == 0;
    wire frame_valid = input_bank_hold != output_bank_hold &&
        {1'b0, frame_layer_hold} == {1'b0, layer_hold} + 9'd1;
    wire resume_descriptor_valid = outer_hold[159:128] == CONTINUATION_MAGIC &&
        outer_hold[127:116] < selected_length &&
        outer_hold[115:112] < query_heads &&
        outer_hold[111:102] <= selected_dimension && outer_hold[53:0] == 0;
    wire [31:0] weight_column = global_layer ?
        ({28'd0, head} << (COMPACT ? 3 : 9)) + {22'd0, component} :
        ({28'd0, head} << (COMPACT ? 2 : 8)) + {22'd0, component};
    wire weight_selected = rst_n && (state == WEIGHT_START || state == WEIGHT_WAIT);
    wire lookup_selected = rst_n &&
        (state == LOOKUP_START || state == LOOKUP_WAIT);
    wire own_work = rst_n && (state == RESTORE_SEND || state == RESTORE_WAIT ||
        state == RESTORE_REGISTER || state == SAVE_SEND || state == SAVE_WAIT ||
        state == SAVE_REGISTER || state == PAIR_SEND || state == PAIR_WAIT ||
        state == PAIR_REGISTER);
    wire [159:0] outer_record = {CONTINUATION_MAGIC, row, head, component,
        sum, low_hold, 54'd0};
    wire [31:0] checkpoint_word = inner_hold[32*word_index+:32];

    wire lookup_ready, lookup_valid, lookup_cmd_valid, lookup_result_ready;
    wire [63:0] lookup_cmd_addr, lookup_base, lookup_bytes;
    wire [31:0] lookup_rows, lookup_columns, lookup_stride;
    wire [3:0] lookup_error;
    anvil_en1_tensor_image #(.COMPACT(COMPACT)) matrix_lookup (
        .image_immutable(image_immutable === 1'b1),
        .image_invalidate((image_invalidate === 1'b1)),
        .controller_bytes(lookup_controller_bytes),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == LOOKUP_START), .start_ready(lookup_ready),
        .model(model_hold), .precision(precision_hold), .image_class(2'd0),
        .input_audio(1'b0), .input_items(32'd0), .image_base(weights_hold),
        .tensor_kind(16'h0106), .tensor_layer({8'd0, layer_hold}),
        .cmd_valid(lookup_cmd_valid), .cmd_ready(lookup_selected && cmd_ready),
        .cmd_write(), .cmd_addr(lookup_cmd_addr), .cmd_wdata(),
        .result_valid(lookup_selected && result_valid),
        .result_ready(lookup_result_ready), .result_data(result_data),
        .result_error(result_error), .done_valid(lookup_valid),
        .done_ready(rst_n && state == LOOKUP_WAIT), .done_base(lookup_base),
        .done_bytes(lookup_bytes), .done_rows(lookup_rows),
        .done_columns(lookup_columns), .done_stride(lookup_stride),
        .done_type(), .done_error(lookup_error)
    );

    wire weight_ready, weight_valid, weight_cmd_valid, weight_result_ready;
    wire [63:0] weight_cmd_addr;
    wire [31:0] weight_data;
    wire [3:0] weight_error;
    anvil_en1_weight_read output_weight (
        .controller_bytes(weight_controller_bytes),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == WEIGHT_START), .start_ready(weight_ready),
        .precision(precision_hold), .tensor_base(matrix_base),
        .tensor_bytes(matrix_bytes), .tensor_rows(matrix_rows),
        .tensor_columns(matrix_columns), .row_stride(matrix_stride),
        .row_index({20'd0, row}), .column_index(weight_column),
        .cmd_valid(weight_cmd_valid), .cmd_ready(weight_selected && cmd_ready),
        .cmd_write(), .cmd_addr(weight_cmd_addr), .cmd_wdata(),
        .result_valid(weight_selected && result_valid),
        .result_ready(weight_result_ready), .result_data(result_data),
        .result_error(result_error), .done_valid(weight_valid),
        .done_ready(rst_n && state == WEIGHT_WAIT),
        .done_data(weight_data), .done_error(weight_error)
    );

    wire fp_ready, fp_valid;
    wire [31:0] fp_data;
    wire [3:0] fp_error;
    anvil_en1_fp32 arithmetic (
        .controller_bytes(fp_controller_bytes),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == FP_START), .start_ready(fp_ready),
        .operation(fp_op), .operand_a(fp_a), .operand_b(fp_b),
        .done_valid(fp_valid), .done_ready(rst_n && state == FP_WAIT),
        .done_data(fp_data), .done_error(fp_error)
    );

    wire executor_ready, executor_valid, executor_yield;
    wire [3:0] executor_error;
    wire [159:0] executor_continuation;
    wire [7:0] executor_owner;
    wire [31:0] executor_token;
    wire executor_output_valid, executor_output_last;
    wire [9:0] executor_output_index;
    wire [15:0] executor_output_data;
    wire executor_work_valid, executor_work_rsp_ready;
    wire [2:0] executor_work_op;
    wire [1:0] executor_work_domain, executor_work_target;
    wire [31:0] executor_work_token, executor_work_data;
    wire [7:0] executor_work_layer, executor_work_scalar_index;
    wire [11:0] executor_work_length, executor_work_component;
    wire [5:0] executor_work_slot;
    wire executor_work_bank;
    wire executor_cmd_valid, executor_result_ready;
    wire [63:0] executor_cmd_addr;
    wire executor_memory = rst_n && head_active && !weight_selected;
    wire executor_work = rst_n && head_active && !own_work;
    wire head_done_ready = rst_n &&
        (state == HEAD_RUN || state == DRAIN_HEAD) && !executor_output_valid;
    anvil_en1_replay_attention_execute #(.COMPACT(COMPACT), .PAUSABLE(1)) executor (
        .image_immutable(image_immutable === 1'b1),
        .image_invalidate((image_invalidate === 1'b1)),
        .clk(clk), .rst_n(rst_n),
        .attention_activity(attention_activity),
        .start_valid(rst_n && state == HEAD_START), .start_ready(executor_ready),
        .model(model_hold), .precision(precision_hold), .layer(layer_hold),
        .query_head(head), .query_position(token_hold), .tokens(tokens_hold),
        .weights_base(weights_hold), .frame_layer(frame_layer_hold),
        .frame_slot(slot_hold), .input_bank(input_bank_hold),
        .resume_valid(resume_hold), .continuation(inner_hold),
        .dependency_valid(dependency_valid_hold),
        .dependency_domain(dependency_domain_hold),
        .dependency_layer(dependency_layer_hold),
        .dependency_token(dependency_token_hold),
        .dependency_length(dependency_length_hold),
        .dependency_slot(dependency_slot_hold),
        .pause(head_active && state != HEAD_RUN && state != DRAIN_HEAD),
        .cancel(state == DRAIN_HEAD),
        .mask_valid(mask_valid), .mask_ready(head_active && mask_ready),
        .mask_token(mask_token), .mask_rsp_valid(head_active && mask_rsp_valid),
        .mask_rsp_ready(mask_rsp_ready), .mask_rsp_data(mask_rsp_data),
        .mask_rsp_error(mask_rsp_error),
        .req_valid(req_valid), .req_ready(head_active && req_ready),
        .req_op(req_op), .req_model(req_model), .req_layer(req_layer),
        .req_token(req_token), .req_is_value(req_is_value),
        .req_kv_head(req_kv_head), .req_component(req_component), .req_base(req_base),
        .rsp_valid(head_active && rsp_valid), .rsp_ready(rsp_ready),
        .rsp_addr(rsp_addr), .rsp_owner(rsp_owner), .rsp_alias(rsp_alias),
        .rsp_error(rsp_error), .rsp_space(rsp_space),
        .work_req_valid(executor_work_valid),
        .work_req_ready(executor_work && work_req_ready),
        .work_req_op(executor_work_op), .work_req_domain(executor_work_domain),
        .work_req_target(executor_work_target), .work_req_token(executor_work_token),
        .work_req_layer(executor_work_layer), .work_req_length(executor_work_length),
        .work_req_component(executor_work_component), .work_req_slot(executor_work_slot),
        .work_req_bank(executor_work_bank),
        .work_req_scalar_index(executor_work_scalar_index),
        .work_req_data(executor_work_data),
        .work_rsp_valid(executor_work && work_rsp_valid),
        .work_rsp_ready(executor_work_rsp_ready),
        .work_rsp_data(work_rsp_data), .work_rsp_error(work_rsp_error),
        .cmd_valid(executor_cmd_valid), .cmd_ready(executor_memory && cmd_ready),
        .cmd_write(), .cmd_addr(executor_cmd_addr), .cmd_wdata(),
        .result_valid(executor_memory && result_valid),
        .result_ready(executor_result_ready), .result_data(result_data),
        .result_error(result_error),
        .output_valid(executor_output_valid),
        .output_ready(rst_n && (state == HEAD_RUN || state == DRAIN_HEAD)),
        .output_index(executor_output_index), .output_data(executor_output_data),
        .output_last(executor_output_last), .done_valid(executor_valid),
        .done_ready(head_done_ready), .done_error(executor_error),
        .done_yield(executor_yield), .done_continuation(executor_continuation),
        .done_owner(executor_owner), .done_token(executor_token),
        .done_is_value(), .done_kv_head(), .done_component(),
        .owner_reprojection_event(owner_reprojection_event),
        .owner_reprojection_bytes(owner_reprojection_bytes),
        .query_projection_event(query_projection_event),
        .query_projection_bytes(query_projection_bytes),
        .source_read_event(source_read_event), .source_read_bytes(source_read_bytes),
        .controller_state_bytes(executor_controller_bytes),
        .checkpoint_controller_bytes(checkpoint_controller_bytes),
        .tile_controller_bytes(tile_controller_bytes), .tile_live_bytes(tile_live_bytes),
        .tile_shadow_bytes(tile_shadow_bytes),
        .tile_physical_bytes(tile_physical_bytes), .pair_live_bytes(), .busy()
    );

    assign start_ready = rst_n && state == IDLE;
    assign work_req_valid = rst_n && (state == SAVE_SEND ||
        state == RESTORE_SEND || state == PAIR_SEND ||
        (executor_work && executor_work_valid));
    assign work_req_op = !rst_n ? 3'd0 : (own_work ?
        (state == RESTORE_SEND || state == RESTORE_WAIT ||
            state == RESTORE_REGISTER ? 3'd7 : 3'd6) : executor_work_op);
    assign work_req_domain = !rst_n ? 2'd0 :
        (own_work ? 2'd0 : executor_work_domain);
    assign work_req_target = !rst_n ? 2'd0 :
        (own_work ? (state == PAIR_SEND || state == PAIR_WAIT ||
            state == PAIR_REGISTER ? 2'd2 : 2'd0) : executor_work_target);
    assign work_req_token = !rst_n ? 32'd0 :
        (own_work ? token_hold : executor_work_token);
    assign work_req_layer = !rst_n ? 8'd0 :
        (own_work ? frame_layer_hold : executor_work_layer);
    assign work_req_length = !rst_n ? 12'd0 :
        (own_work ? length_hold : executor_work_length);
    assign work_req_component = !rst_n ? 12'd0 :
        (own_work ? {row[11:1], 1'b0} : executor_work_component);
    assign work_req_slot = !rst_n ? 6'd0 :
        (own_work ? slot_hold : executor_work_slot);
    assign work_req_bank = rst_n && (own_work ? output_bank_hold : executor_work_bank);
    assign work_req_scalar_index = !rst_n ? 8'd0 :
        (own_work ? {5'd0, word_index} + 8'd15 : executor_work_scalar_index);
    assign work_req_data = !rst_n ? 32'd0 : (own_work ?
        (state == PAIR_SEND || state == PAIR_WAIT || state == PAIR_REGISTER ?
            pair_hold : checkpoint_word) : executor_work_data);
    assign work_rsp_ready = rst_n && (state == SAVE_WAIT ||
        state == RESTORE_WAIT || state == PAIR_WAIT ||
        (executor_work && executor_work_rsp_ready));
    assign cmd_valid = rst_n && (lookup_selected ? lookup_cmd_valid :
        (weight_selected ? weight_cmd_valid : (executor_memory && executor_cmd_valid)));
    assign cmd_write = 0;
    assign cmd_addr = !rst_n ? 64'd0 : (lookup_selected ? lookup_cmd_addr :
        (weight_selected ? weight_cmd_addr : executor_cmd_addr));
    assign cmd_wdata = 0;
    assign result_ready = rst_n && (lookup_selected ? lookup_result_ready :
        (weight_selected ? weight_result_ready : (executor_memory && executor_result_ready)));
    assign done_valid = rst_n && state == RESPONSE;
    assign done_error = rst_n ? error_hold : 4'd0;
    assign done_yield = rst_n && yield_hold && error_hold == 0;
    assign done_bank = rst_n && output_bank_hold;
    assign done_continuation = rst_n && yield_hold ? outer_record : 160'd0;
    assign done_dependency_layer = rst_n && yield_hold ? dependency_owner_hold : 8'd0;
    assign done_dependency_token = rst_n && yield_hold ? dependency_position_hold : 32'd0;
    assign busy = rst_n && state != IDLE;
    wire [31:0] CONTROLLER_BITS =
        $bits(state) + $bits(fp_return) +
        $bits(model_hold) + $bits(precision_hold) + $bits(dependency_domain_hold) +
        $bits(layer_hold) + $bits(frame_layer_hold) + $bits(dependency_layer_hold) +
        $bits(token_hold) + $bits(tokens_hold) + $bits(dependency_token_hold) +
        $bits(weights_hold) + $bits(slot_hold) + $bits(dependency_slot_hold) +
        $bits(input_bank_hold) + $bits(output_bank_hold) + $bits(resume_hold) +
        $bits(dependency_valid_hold) + $bits(length_hold) + $bits(dependency_length_hold) +
        $bits(row) + $bits(head) + $bits(component) + $bits(dimension_hold) +
        $bits(sum) + $bits(weight_hold) + $bits(fp_a) + $bits(fp_b) +
        $bits(fp_value) + $bits(pair_hold) + $bits(scalar_hold) +
        $bits(low_hold) + $bits(element_hold) + $bits(fp_op) + $bits(word_index) +
        $bits(matrix_base) + $bits(matrix_bytes) + $bits(matrix_rows) +
        $bits(matrix_columns) + $bits(matrix_stride) +
        $bits(outer_hold) + $bits(inner_hold) + $bits(error_hold) + $bits(work_error_hold) +
        $bits(head_active) + $bits(yield_hold) +
        $bits(dependency_owner_hold) + $bits(dependency_position_hold);
    assign controller_state_bytes = !rst_n ? 64'd0 :
        64'((CONTROLLER_BITS + 7) >> 3) + lookup_controller_bytes +
        weight_controller_bytes + fp_controller_bytes;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            fp_return <= 0;
            model_hold <= 0;
            precision_hold <= 0;
            dependency_domain_hold <= 0;
            layer_hold <= 0;
            frame_layer_hold <= 0;
            dependency_layer_hold <= 0;
            token_hold <= 0;
            tokens_hold <= 0;
            dependency_token_hold <= 0;
            weights_hold <= 0;
            slot_hold <= 0;
            dependency_slot_hold <= 0;
            input_bank_hold <= 0;
            output_bank_hold <= 0;
            resume_hold <= 0;
            dependency_valid_hold <= 0;
            length_hold <= 0;
            dependency_length_hold <= 0;
            row <= 0;
            head <= 0;
            component <= 0;
            dimension_hold <= 0;
            sum <= 0;
            weight_hold <= 0;
            fp_a <= 0;
            fp_b <= 0;
            fp_value <= 0;
            pair_hold <= 0;
            scalar_hold <= 0;
            low_hold <= 0;
            element_hold <= 0;
            fp_op <= 0;
            word_index <= 0;
            matrix_base <= 0;
            matrix_bytes <= 0;
            matrix_rows <= 0;
            matrix_columns <= 0;
            matrix_stride <= 0;
            outer_hold <= 0;
            inner_hold <= 0;
            error_hold <= 0;
            work_error_hold <= 0;
            head_active <= 0;
            yield_hold <= 0;
            dependency_owner_hold <= 0;
            dependency_position_hold <= 0;
        end else begin
            case (state)
                IDLE: if (start_valid && start_ready) begin
                    model_hold <= model;
                    precision_hold <= precision;
                    layer_hold <= layer;
                    frame_layer_hold <= frame_layer;
                    token_hold <= token;
                    tokens_hold <= tokens;
                    weights_hold <= weights_base;
                    slot_hold <= frame_slot;
                    input_bank_hold <= input_bank;
                    output_bank_hold <= output_bank;
                    resume_hold <= resume_valid;
                    outer_hold <= continuation;
                    inner_hold <= 0;
                    dependency_valid_hold <= dependency_valid;
                    dependency_domain_hold <= dependency_domain;
                    dependency_layer_hold <= dependency_layer;
                    dependency_token_hold <= dependency_token;
                    dependency_length_hold <= dependency_length;
                    dependency_slot_hold <= dependency_slot;
                    row <= 0;
                    head <= 0;
                    component <= 0;
                    sum <= 0;
                    low_hold <= 0;
                    word_index <= 0;
                    head_active <= 0;
                    yield_hold <= 0;
                    error_hold <= 0;
                    work_error_hold <= 0;
                    dependency_owner_hold <= 0;
                    dependency_position_hold <= 0;
                    state <= VALIDATE;
                end
                VALIDATE: begin
                    length_hold <= selected_length;
                    dimension_hold <= selected_dimension;
                    if (!native_model || precision_hold > 1) begin
                        error_hold <= 6;
                        state <= PUBLISH;
                    end else if (!descriptor_valid) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else if (!frame_valid || (resume_hold && !resume_descriptor_valid)) begin
                        error_hold <= 7;
                        state <= PUBLISH;
                    end else begin
                        if (resume_hold) begin
                            row <= outer_hold[127:116];
                            head <= outer_hold[115:112];
                            component <= outer_hold[111:102];
                            sum <= outer_hold[101:70];
                            low_hold <= outer_hold[69:54];
                        end
                        state <= LOOKUP_START;
                    end
                end
                LOOKUP_START: if (lookup_ready)
                    state <= LOOKUP_WAIT;
                LOOKUP_WAIT: if (lookup_valid) begin
                    if (lookup_error != 0) begin
                        error_hold <= lookup_error;
                        state <= PUBLISH;
                    end else begin
                        matrix_base <= lookup_base;
                        matrix_bytes <= lookup_bytes;
                        matrix_rows <= lookup_rows;
                        matrix_columns <= lookup_columns;
                        matrix_stride <= lookup_stride;
                        state <= LOOKUP_REGISTER;
                    end
                end
                LOOKUP_REGISTER: begin
                    if (matrix_rows != {20'd0, length_hold} ||
                        matrix_columns != (COMPACT ?
                            (global_layer ? 32'd16 : 32'd8) :
                            (global_layer ? 32'd4096 : 32'd2048))) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else if (resume_hold) begin
                        word_index <= 0;
                        state <= RESTORE_SEND;
                    end else
                        state <= HEAD_START;
                end
                RESTORE_SEND: if (work_req_ready)
                    state <= RESTORE_WAIT;
                RESTORE_WAIT: if (work_rsp_valid) begin
                    scalar_hold <= work_rsp_data;
                    work_error_hold <= work_rsp_error;
                    state <= RESTORE_REGISTER;
                end
                RESTORE_REGISTER: begin
                    if (work_error_hold != 0) begin
                        error_hold <= work_error_hold;
                        state <= PUBLISH;
                    end else begin
                        inner_hold[32*word_index+:32] <= scalar_hold;
                        if (word_index == 4)
                            state <= HEAD_START;
                        else begin
                            word_index <= word_index + 1'b1;
                            state <= RESTORE_SEND;
                        end
                    end
                end
                HEAD_START: if (executor_ready) begin
                    head_active <= 1;
                    state <= HEAD_RUN;
                end
                HEAD_RUN: begin
                    if (executor_output_valid) begin
                        if (component >= dimension_hold ||
                            executor_output_index != component ||
                            executor_output_last != (component + 10'd1 == dimension_hold)) begin
                            error_hold <= 7;
                            state <= DRAIN_HEAD;
                        end else begin
                            element_hold <= executor_output_data;
                            state <= WEIGHT_START;
                        end
                    end else if (executor_valid && head_done_ready) begin
                        head_active <= 0;
                        if (executor_error != 0) begin
                            error_hold <= executor_error;
                            state <= PUBLISH;
                        end else if (executor_yield) begin
                            inner_hold <= executor_continuation;
                            dependency_owner_hold <= executor_owner;
                            dependency_position_hold <= executor_token;
                            word_index <= 0;
                            state <= SAVE_SEND;
                        end else if (component != dimension_hold) begin
                            error_hold <= 7;
                            state <= PUBLISH;
                        end else if (head + 4'd1 == query_heads) begin
                            resume_hold <= 0;
                            state <= ROW_NARROW;
                        end else begin
                            head <= head + 1'b1;
                            component <= 0;
                            resume_hold <= 0;
                            inner_hold <= 0;
                            state <= HEAD_START;
                        end
                    end
                end
                WEIGHT_START: if (weight_ready)
                    state <= WEIGHT_WAIT;
                WEIGHT_WAIT: if (weight_valid) begin
                    if (weight_error != 0) begin
                        error_hold <= weight_error;
                        state <= DRAIN_HEAD;
                    end else begin
                        weight_hold <= weight_data;
                        state <= COLUMN_MULTIPLY;
                    end
                end
                COLUMN_MULTIPLY: begin
                    fp_op <= 1;
                    fp_a <= {element_hold, 16'd0};
                    fp_b <= weight_hold;
                    fp_return <= COLUMN_ADD;
                    state <= FP_START;
                end
                COLUMN_ADD: begin
                    fp_op <= 0;
                    fp_a <= sum;
                    fp_b <= fp_value;
                    fp_return <= COLUMN_COMMIT;
                    state <= FP_START;
                end
                COLUMN_COMMIT: begin
                    sum <= fp_value;
                    component <= component + 1'b1;
                    state <= HEAD_RUN;
                end
                FP_START: if (fp_ready)
                    state <= FP_WAIT;
                FP_WAIT: if (fp_valid) begin
                    if (fp_error != 0) begin
                        error_hold <= fp_error;
                        if (head_active)
                            state <= DRAIN_HEAD;
                        else
                            state <= PUBLISH;
                    end else begin
                        fp_value <= fp_data;
                        state <= fp_return;
                    end
                end
                ROW_NARROW: begin
                    fp_op <= 3;
                    fp_a <= sum;
                    fp_b <= 0;
                    fp_return <= ROW_PACK;
                    state <= FP_START;
                end
                ROW_PACK: begin
                    if (!row[0]) begin
                        low_hold <= fp_value[15:0];
                        row <= row + 1'b1;
                        head <= 0;
                        component <= 0;
                        sum <= 0;
                        inner_hold <= 0;
                        state <= HEAD_START;
                    end else begin
                        pair_hold <= {fp_value[15:0], low_hold};
                        state <= PAIR_SEND;
                    end
                end
                PAIR_SEND: if (work_req_ready)
                    state <= PAIR_WAIT;
                PAIR_WAIT: if (work_rsp_valid) begin
                    work_error_hold <= work_rsp_error;
                    state <= PAIR_REGISTER;
                end
                PAIR_REGISTER: begin
                    if (work_error_hold != 0) begin
                        error_hold <= work_error_hold;
                        state <= PUBLISH;
                    end else if (row + 12'd1 == length_hold)
                        state <= PUBLISH;
                    else begin
                        row <= row + 1'b1;
                        head <= 0;
                        component <= 0;
                        sum <= 0;
                        inner_hold <= 0;
                        state <= HEAD_START;
                    end
                end
                SAVE_SEND: if (work_req_ready)
                    state <= SAVE_WAIT;
                SAVE_WAIT: if (work_rsp_valid) begin
                    work_error_hold <= work_rsp_error;
                    state <= SAVE_REGISTER;
                end
                SAVE_REGISTER: begin
                    if (work_error_hold != 0) begin
                        error_hold <= work_error_hold;
                        state <= PUBLISH;
                    end else if (word_index == 4) begin
                        yield_hold <= 1;
                        state <= PUBLISH;
                    end else begin
                        word_index <= word_index + 1'b1;
                        state <= SAVE_SEND;
                    end
                end
                DRAIN_HEAD: if (executor_valid && head_done_ready) begin
                    head_active <= 0;
                    state <= PUBLISH;
                end
                PUBLISH: state <= RESPONSE;
                RESPONSE: if (done_ready)
                    state <= IDLE;
                default: begin
                    error_hold <= 7;
                    yield_hold <= 0;
                    if (head_active)
                        state <= DRAIN_HEAD;
                    else
                        state <= PUBLISH;
                end
            endcase
        end
    end
endmodule
