module anvil_en1_audio_history_fold #(
    parameter integer FUSE_LEADING_PADDING = 0
) (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] model, precision,
    input wire [31:0] generation, frame_token, source_token,
    input wire [7:0] frame_layer,
    input wire [5:0] frame_slot,
    input wire [2:0] kernel,
    input wire padding,
    input wire [63:0] audio_weights_base,
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
    output wire source_read_event, projection_event, glu_replay_event,
    output wire [31:0] source_read_bytes, projection_bytes, glu_replay_bytes,
    output wire [63:0] vector_live_bytes, vector_physical_bytes,
    output wire [63:0] controller_bytes, nested_controller_bytes
);
    localparam [5:0] IDLE = 0, VALIDATE = 1, IMAGE_START = 2,
        IMAGE_WAIT = 3, IMAGE_CHECK = 4, WEIGHT_START = 5,
        WEIGHT_WAIT = 6, GLU_START = 7, GLU_WAIT = 8,
        WIDEN = 9, MULTIPLY = 10, ACC_READ_SEND = 11,
        ACC_READ_WAIT = 12, ACC_READ_REGISTER = 13, ADD = 14,
        ACC_WRITE_SEND = 15, ACC_WRITE_WAIT = 16, ACC_WRITE_REGISTER = 17,
        NARROW = 18, PACK = 19, OUTPUT_SEND = 20,
        OUTPUT_WAIT = 21, OUTPUT_REGISTER = 22, ADVANCE = 23,
        FP_START = 24, FP_WAIT = 25, PUBLISH = 26, RESPONSE = 27,
        REDUCE_REGISTER = 28;
    localparam [2:0] S_IDLE = 0, S_VALIDATE = 1, S_SEND = 2,
        S_WAIT = 3, S_REGISTER = 4, S_RESPONSE = 5;
    reg [5:0] state, fp_return;
    reg [2:0] source_state, kernel_hold, requested_kernel_hold, fp_op;
    reg [1:0] model_hold, precision_hold;
    reg [31:0] generation_hold, frame_token_hold, source_token_hold;
    reg [7:0] layer_hold;
    reg [5:0] slot_hold;
    reg padding_hold, requested_padding_hold, fused_hold, source_bad;
    reg [63:0] weights_hold, matrix_base, matrix_bytes;
    reg [31:0] matrix_stride, channel_hold, weight_hold, accumulator_hold;
    reg [31:0] fp_a, fp_b, fp_value, product_hold, output_pair;
    reg [31:0] source_index_hold, source_pair_hold;
    reg [15:0] glu_hold, low_hold, source_data_hold;
    reg [3:0] error_hold, source_error_hold, first_source_error, work_error_hold;

    initial begin
        if (FUSE_LEADING_PADDING != 0 && FUSE_LEADING_PADDING != 1)
            $fatal(1, "PARAMETER ERROR: FUSE_LEADING_PADDING must be 0 or 1");
    end
    wire [2:0] first_kernel = frame_token < 4 ?
        3'd4 - frame_token[2:0] : 3'd0;
    wire fuse_start = FUSE_LEADING_PADDING && !padding && kernel == first_kernel;
    wire initialize_accumulator = fused_hold || requested_kernel_hold == 0;
    wire [2:0] held_first_kernel = frame_token_hold < 4 ?
        3'd4 - frame_token_hold[2:0] : 3'd0;
    wire image_selected = rst_n && (state == IMAGE_START || state == IMAGE_WAIT);
    wire image_ready, image_valid, image_cmd_valid, image_result_ready;
    wire [63:0] image_addr, image_base, image_bytes, image_control;
    wire [31:0] image_rows, image_columns, image_stride;
    wire [7:0] image_type;
    wire [3:0] image_error;
    anvil_en1_tensor_image directory (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == IMAGE_START), .start_ready(image_ready),
        .model(model_hold), .precision(precision_hold), .image_class(2'd2),
        .input_audio(1'b0), .input_items(32'd0), .image_base(weights_hold),
        .tensor_kind(16'h210e), .tensor_layer({8'd0, layer_hold - 8'd1}),
        .cmd_valid(image_cmd_valid), .cmd_ready(image_selected && cmd_ready),
        .cmd_write(), .cmd_addr(image_addr), .cmd_wdata(),
        .result_valid(image_selected && result_valid), .result_ready(image_result_ready),
        .result_data(result_data), .result_error(result_error),
        .done_valid(image_valid), .done_ready(rst_n && state == IMAGE_WAIT),
        .done_base(image_base), .done_bytes(image_bytes), .done_rows(image_rows),
        .done_columns(image_columns), .done_stride(image_stride), .done_type(image_type),
        .done_error(image_error), .controller_bytes(image_control)
    );
    wire weight_selected = rst_n && (state == WEIGHT_START || state == WEIGHT_WAIT);
    wire weight_ready, weight_valid, weight_cmd_valid, weight_result_ready;
    wire [63:0] weight_addr, weight_control;
    wire [31:0] weight_data;
    wire [3:0] weight_error;
    anvil_en1_weight_read weight_reader (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == WEIGHT_START), .start_ready(weight_ready),
        .precision(precision_hold), .tensor_base(matrix_base), .tensor_bytes(matrix_bytes),
        .tensor_rows(32'd1024), .tensor_columns(32'd5), .row_stride(matrix_stride),
        .row_index(channel_hold), .column_index({29'd0, kernel_hold}),
        .cmd_valid(weight_cmd_valid), .cmd_ready(weight_selected && cmd_ready),
        .cmd_write(), .cmd_addr(weight_addr), .cmd_wdata(),
        .result_valid(weight_selected && result_valid), .result_ready(weight_result_ready),
        .result_data(result_data), .result_error(result_error),
        .done_valid(weight_valid), .done_ready(rst_n && state == WEIGHT_WAIT),
        .done_data(weight_data), .done_error(weight_error), .controller_bytes(weight_control)
    );
    wire glu_selected = rst_n && (state == GLU_START || state == GLU_WAIT);
    wire glu_ready, glu_valid, glu_cmd_valid, glu_result_ready;
    wire glu_source_valid, glu_source_rsp_ready;
    wire [1:0] glu_source_model;
    wire [7:0] glu_source_layer;
    wire [31:0] glu_source_generation, glu_source_token, glu_source_index;
    wire [31:0] glu_data, glu_projection_bytes;
    wire [63:0] glu_addr, glu_control, glu_norm_control, glu_projection_control;
    wire [63:0] glu_clamp_control;
    wire [3:0] glu_error;
    wire glu_projection_event;
    anvil_en1_audio_glu_component gated_input (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == GLU_START), .start_ready(glu_ready),
        .model(model_hold), .precision(precision_hold), .layer(layer_hold - 8'd1),
        .generation(generation_hold), .token(source_token_hold), .channel(channel_hold),
        .audio_weights_base(weights_hold),
        .source_valid(glu_source_valid),
        .source_ready(rst_n && state == GLU_WAIT && source_state == S_IDLE),
        .source_model(glu_source_model), .source_layer(glu_source_layer),
        .source_generation(glu_source_generation), .source_token(glu_source_token),
        .source_index(glu_source_index),
        .source_rsp_valid(rst_n && state == GLU_WAIT && source_state == S_RESPONSE),
        .source_rsp_ready(glu_source_rsp_ready), .source_rsp_data(source_data_hold),
        .source_rsp_error(source_error_hold != 0),
        .cmd_valid(glu_cmd_valid), .cmd_ready(glu_selected && cmd_ready),
        .cmd_write(), .cmd_addr(glu_addr), .cmd_wdata(),
        .result_valid(glu_selected && result_valid), .result_ready(glu_result_ready),
        .result_data(result_data), .result_error(result_error),
        .done_valid(glu_valid),
        .done_ready(rst_n && state == GLU_WAIT && source_state == S_IDLE),
        .done_data(glu_data), .done_error(glu_error),
        .weight_read_event(), .weight_read_bytes(),
        .projection_event(glu_projection_event), .projection_bytes(glu_projection_bytes),
        .vector_live_bytes(vector_live_bytes), .vector_physical_bytes(vector_physical_bytes),
        .vector_ram_write(), .vector_ram_read(), .vector_ram_waddr(),
        .vector_ram_raddr(), .vector_ram_wdata(), .vector_ram_rdata(16'd0),
        .controller_bytes(glu_control), .norm_controller_bytes(glu_norm_control),
        .projection_controller_bytes(glu_projection_control),
        .clamp_controller_bytes(glu_clamp_control)
    );
    wire fp_ready, fp_valid;
    wire [31:0] fp_data;
    wire [3:0] fp_error;
    wire [63:0] fp_control;
    anvil_en1_fp32 arithmetic (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == FP_START), .start_ready(fp_ready),
        .operation(fp_op), .operand_a(fp_a), .operand_b(fp_b),
        .done_valid(fp_valid), .done_ready(rst_n && state == FP_WAIT),
        .done_data(fp_data), .done_error(fp_error), .controller_bytes(fp_control)
    );
    wire source_send = rst_n && state == GLU_WAIT && source_state == S_SEND;
    wire source_wait = rst_n && state == GLU_WAIT && source_state == S_WAIT;
    wire accumulator_request = (state == ACC_READ_SEND && !initialize_accumulator) ||
        state == ACC_WRITE_SEND;
    wire output_request = state == OUTPUT_SEND;
    assign work_req_valid = source_send || (rst_n && (accumulator_request || output_request));
    assign work_rsp_ready = source_wait || (rst_n &&
        (state == ACC_READ_WAIT || state == ACC_WRITE_WAIT || state == OUTPUT_WAIT));
    assign work_req_op = !rst_n ? 3'd0 :
        (source_send || state == ACC_READ_SEND ? 3'd4 : 3'd6);
    assign work_req_domain = rst_n ? 2'd2 : 2'd0;
    assign work_req_target = !rst_n ? 2'd0 :
        (output_request ? (initialize_accumulator ? 2'd2 : 2'd3) :
        (state == ACC_WRITE_SEND ? (initialize_accumulator ? 2'd2 : 2'd3) : 2'd0));
    assign work_req_token = rst_n ? frame_token_hold : 32'd0;
    assign work_req_layer = rst_n ? layer_hold : 8'd0;
    assign work_req_length = rst_n ? 12'd1024 : 12'd0;
    assign work_req_slot = rst_n ? slot_hold : 6'd0;
    assign work_req_bank = rst_n && (accumulator_request || output_request);
    assign work_req_scalar_index = !rst_n ? 8'd0 :
        (accumulator_request ? {7'd0, channel_hold[9]} : 8'd0);
    assign work_req_component = !rst_n ? 12'd0 :
        (accumulator_request ? {2'd0, channel_hold[8:0], 1'b0} :
        (output_request ? {2'd0, channel_hold[9:1], 1'b0} :
            (source_index_hold[11:0] & 12'hffe)));
    assign work_req_data = !rst_n ? 32'd0 :
        (output_request ? output_pair : fp_value);
    assign cmd_valid = (image_selected && image_cmd_valid) ||
        (weight_selected && weight_cmd_valid) || (glu_selected && glu_cmd_valid);
    assign cmd_write = 0;
    assign cmd_addr = image_selected ? image_addr :
        (weight_selected ? weight_addr : (glu_selected ? glu_addr : 64'd0));
    assign cmd_wdata = 0;
    assign result_ready = (image_selected && image_result_ready) ||
        (weight_selected && weight_result_ready) || (glu_selected && glu_result_ready);
    assign start_ready = rst_n && state == IDLE;
    assign done_valid = rst_n && state == RESPONSE;
    assign done_error = rst_n ? error_hold : 4'd0;
    assign source_read_event = rst_n && state == GLU_WAIT &&
        source_state == S_IDLE && glu_source_valid;
    assign source_read_bytes = source_read_event ? 32'd2 : 32'd0;
    wire kernel_projection = rst_n && state == WEIGHT_START && weight_ready;
    assign projection_event = glu_projection_event || kernel_projection;
    assign projection_bytes = glu_projection_bytes +
        (kernel_projection ? (precision_hold == 0 ? 32'd2 : 32'd18) : 32'd0);
    assign glu_replay_event = rst_n && state == GLU_START && glu_ready;
    assign glu_replay_bytes = glu_replay_event ? 32'd2048 : 32'd0;
    assign nested_controller_bytes = !rst_n ? 64'd0 :
        image_control + weight_control + glu_control + glu_norm_control +
        glu_projection_control + glu_clamp_control + fp_control;
    localparam integer CONTROLLER_BITS =
        $bits(state) + $bits(fp_return) + $bits(source_state) + $bits(kernel_hold) +
        $bits(requested_kernel_hold) + $bits(requested_padding_hold) + $bits(fused_hold) +
        $bits(fp_op) + $bits(model_hold) + $bits(precision_hold) +
        $bits(generation_hold) + $bits(frame_token_hold) + $bits(source_token_hold) +
        $bits(layer_hold) + $bits(slot_hold) + $bits(padding_hold) + $bits(source_bad) +
        $bits(weights_hold) + $bits(matrix_base) + $bits(matrix_bytes) +
        $bits(matrix_stride) + $bits(channel_hold) + $bits(weight_hold) +
        $bits(accumulator_hold) + $bits(fp_a) + $bits(fp_b) + $bits(fp_value) +
        $bits(product_hold) + $bits(output_pair) + $bits(source_index_hold) +
        $bits(source_pair_hold) + $bits(glu_hold) + $bits(low_hold) +
        $bits(source_data_hold) + $bits(error_hold) + $bits(source_error_hold) +
        $bits(first_source_error) + $bits(work_error_hold);
    assign controller_bytes = rst_n ? (CONTROLLER_BITS + 7) >> 3 : 64'd0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            source_state <= S_IDLE;
            source_index_hold <= 0;
            source_pair_hold <= 0;
            source_data_hold <= 0;
            source_bad <= 0;
            source_error_hold <= 0;
            first_source_error <= 0;
        end else begin
            if (start_valid && start_ready)
                first_source_error <= 0;
            case (source_state)
                S_IDLE: if (source_read_event) begin
                    source_index_hold <= glu_source_index;
                    source_bad <= glu_source_model != model_hold ||
                        glu_source_layer != layer_hold - 8'd1 ||
                        glu_source_generation != generation_hold ||
                        glu_source_token != source_token_hold;
                    source_error_hold <= 0;
                    source_data_hold <= 0;
                    source_state <= S_VALIDATE;
                end
                S_VALIDATE: begin
                    if (source_bad || source_index_hold >= 1024 || padding_hold ||
                        first_source_error != 0) begin
                        source_error_hold <= first_source_error != 0 ? first_source_error : 4'd7;
                        if (first_source_error == 0)
                            first_source_error <= 7;
                        source_state <= S_RESPONSE;
                    end else
                        source_state <= S_SEND;
                end
                S_SEND: if (work_req_ready)
                    source_state <= S_WAIT;
                S_WAIT: if (work_rsp_valid) begin
                    source_pair_hold <= work_rsp_data;
                    source_error_hold <= work_rsp_error;
                    source_state <= S_REGISTER;
                end
                S_REGISTER: begin
                    if (source_error_hold != 0) begin
                        if (first_source_error == 0)
                            first_source_error <= source_error_hold;
                    end else
                        source_data_hold <= source_index_hold[0] ?
                            source_pair_hold[31:16] : source_pair_hold[15:0];
                    source_state <= S_RESPONSE;
                end
                S_RESPONSE: if (rst_n && state == GLU_WAIT && glu_source_rsp_ready)
                    source_state <= S_IDLE;
                default: begin
                    source_error_hold <= 7;
                    if (first_source_error == 0)
                        first_source_error <= 7;
                    source_state <= S_RESPONSE;
                end
            endcase
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            fp_return <= 0;
            kernel_hold <= 0;
            requested_kernel_hold <= 0;
            fp_op <= 0;
            model_hold <= 0;
            precision_hold <= 0;
            generation_hold <= 0;
            frame_token_hold <= 0;
            source_token_hold <= 0;
            layer_hold <= 0;
            slot_hold <= 0;
            padding_hold <= 0;
            requested_padding_hold <= 0;
            fused_hold <= 0;
            weights_hold <= 0;
            matrix_base <= 0;
            matrix_bytes <= 0;
            matrix_stride <= 0;
            channel_hold <= 0;
            weight_hold <= 0;
            accumulator_hold <= 0;
            fp_a <= 0;
            fp_b <= 0;
            fp_value <= 0;
            product_hold <= 0;
            output_pair <= 0;
            glu_hold <= 0;
            low_hold <= 0;
            error_hold <= 0;
            work_error_hold <= 0;
        end else begin
            case (state)
                IDLE: if (start_valid && start_ready) begin
                    model_hold <= model;
                    precision_hold <= precision;
                    generation_hold <= generation;
                    frame_token_hold <= frame_token;
                    source_token_hold <= source_token;
                    layer_hold <= frame_layer;
                    slot_hold <= frame_slot;
                    kernel_hold <= fuse_start ? 3'd0 : kernel;
                    requested_kernel_hold <= kernel;
                    padding_hold <= fuse_start ? first_kernel != 0 : padding;
                    requested_padding_hold <= padding;
                    fused_hold <= fuse_start;
                    weights_hold <= audio_weights_base;
                    channel_hold <= 0;
                    accumulator_hold <= 0;
                    low_hold <= 0;
                    error_hold <= 0;
                    work_error_hold <= 0;
                    state <= VALIDATE;
                end
                VALIDATE: begin
                    if ((model_hold != 1 && model_hold != 2) || precision_hold > 1) begin
                        error_hold <= 6;
                        state <= PUBLISH;
                    end else if (generation_hold == 0 || layer_hold == 0 ||
                        layer_hold > 12 || frame_token_hold > 131071 ||
                        requested_kernel_hold > 4 || weights_hold[1:0] != 0 ||
                        requested_padding_hold !=
                            (frame_token_hold < 32'd4 - {29'd0, requested_kernel_hold}) ||
                        (!requested_padding_hold && source_token_hold !=
                            frame_token_hold - (32'd4 - {29'd0, requested_kernel_hold}))) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else
                        state <= IMAGE_START;
                end
                IMAGE_START: if (image_ready)
                    state <= IMAGE_WAIT;
                IMAGE_WAIT: if (image_valid) begin
                    matrix_base <= image_base;
                    matrix_bytes <= image_bytes;
                    matrix_stride <= image_stride;
                    work_error_hold <= image_error;
                    if (image_rows != 1024 || image_columns != 5 ||
                        image_type != {6'd0, precision_hold})
                        work_error_hold <= image_error != 0 ? image_error : 4'd5;
                    state <= IMAGE_CHECK;
                end
                IMAGE_CHECK: begin
                    if (work_error_hold != 0) begin
                        error_hold <= work_error_hold;
                        state <= PUBLISH;
                    end else
                        state <= WEIGHT_START;
                end
                WEIGHT_START: if (weight_ready)
                    state <= WEIGHT_WAIT;
                WEIGHT_WAIT: if (weight_valid) begin
                    if (weight_error != 0) begin
                        error_hold <= weight_error;
                        state <= PUBLISH;
                    end else begin
                        weight_hold <= weight_data;
                        if (padding_hold) begin
                            glu_hold <= 0;
                            state <= WIDEN;
                        end else
                            state <= GLU_START;
                    end
                end
                GLU_START: if (glu_ready)
                    state <= GLU_WAIT;
                GLU_WAIT: if (glu_valid && source_state == S_IDLE) begin
                    if (glu_error != 0 || first_source_error != 0) begin
                        error_hold <= first_source_error != 0 ? first_source_error : glu_error;
                        state <= PUBLISH;
                    end else begin
                        glu_hold <= glu_data[15:0];
                        state <= WIDEN;
                    end
                end
                WIDEN: begin
                    fp_op <= 2;
                    fp_a <= {16'd0, glu_hold};
                    fp_b <= 0;
                    fp_return <= MULTIPLY;
                    state <= FP_START;
                end
                MULTIPLY: begin
                    fp_op <= 1;
                    fp_a <= fp_value;
                    fp_b <= weight_hold;
                    fp_return <= ACC_READ_SEND;
                    state <= FP_START;
                end
                ACC_READ_SEND: begin
                    product_hold <= fp_value;
                    if (kernel_hold == 0) begin
                        accumulator_hold <= 0;
                        state <= ADD;
                    end else if (fused_hold) begin
                        state <= ADD;
                    end else if (work_req_ready)
                        state <= ACC_READ_WAIT;
                end
                ACC_READ_WAIT: if (work_rsp_valid) begin
                    accumulator_hold <= work_rsp_data;
                    work_error_hold <= work_rsp_error;
                    state <= ACC_READ_REGISTER;
                end
                ACC_READ_REGISTER: begin
                    if (work_error_hold != 0) begin
                        error_hold <= work_error_hold;
                        state <= PUBLISH;
                    end else
                        state <= ADD;
                end
                ADD: begin
                    fp_op <= 0;
                    fp_a <= accumulator_hold;
                    fp_b <= product_hold;
                    fp_return <= REDUCE_REGISTER;
                    state <= FP_START;
                end
                REDUCE_REGISTER: begin
                    if (fused_hold && kernel_hold < requested_kernel_hold) begin
                        accumulator_hold <= fp_value;
                        kernel_hold <= kernel_hold + 3'd1;
                        padding_hold <= kernel_hold + 3'd1 < held_first_kernel;
                        state <= WEIGHT_START;
                    end else if (kernel_hold == 4)
                        state <= NARROW;
                    else
                        state <= ACC_WRITE_SEND;
                end
                ACC_WRITE_SEND: if (work_req_ready)
                    state <= ACC_WRITE_WAIT;
                ACC_WRITE_WAIT: if (work_rsp_valid) begin
                    work_error_hold <= work_rsp_error;
                    state <= ACC_WRITE_REGISTER;
                end
                ACC_WRITE_REGISTER: begin
                    if (work_error_hold != 0) begin
                        error_hold <= work_error_hold;
                        state <= PUBLISH;
                    end else
                        state <= ADVANCE;
                end
                NARROW: begin
                    fp_op <= 3;
                    fp_a <= fp_value;
                    fp_b <= 0;
                    fp_return <= PACK;
                    state <= FP_START;
                end
                PACK: begin
                    if (!channel_hold[0]) begin
                        low_hold <= fp_value[15:0];
                        state <= ADVANCE;
                    end else begin
                        output_pair <= {fp_value[15:0], low_hold};
                        state <= OUTPUT_SEND;
                    end
                end
                OUTPUT_SEND: if (work_req_ready)
                    state <= OUTPUT_WAIT;
                OUTPUT_WAIT: if (work_rsp_valid) begin
                    work_error_hold <= work_rsp_error;
                    state <= OUTPUT_REGISTER;
                end
                OUTPUT_REGISTER: begin
                    if (work_error_hold != 0) begin
                        error_hold <= work_error_hold;
                        state <= PUBLISH;
                    end else
                        state <= ADVANCE;
                end
                ADVANCE: begin
                    if (channel_hold == 1023)
                        state <= PUBLISH;
                    else begin
                        channel_hold <= channel_hold + 1'b1;
                        kernel_hold <= fused_hold ? 3'd0 : requested_kernel_hold;
                        padding_hold <= fused_hold ?
                            held_first_kernel != 0 : requested_padding_hold;
                        state <= WEIGHT_START;
                    end
                end
                FP_START: if (fp_ready)
                    state <= FP_WAIT;
                FP_WAIT: if (fp_valid) begin
                    fp_value <= fp_data;
                    if (fp_error != 0) begin
                        error_hold <= fp_error;
                        state <= PUBLISH;
                    end else
                        state <= fp_return;
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
