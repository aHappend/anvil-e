module anvil_en1_audio_attention_residual #(
    parameter integer FRAME_HEADS = 0,
    parameter integer PRECOMPUTED_RAW = 0
) (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] model, precision,
    input wire [7:0] layer,
    input wire [31:0] generation, frames, token,
    input wire [63:0] audio_base, audio_weights_base,
    output wire source_valid,
    input wire source_ready,
    output wire source_kind,
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
    output wire projection_event, intermediate_event,
    output wire [31:0] projection_bytes, intermediate_bytes,
    output wire [63:0] vector_live_bytes, vector_physical_bytes,
    output wire [63:0] controller_bytes, pre_controller_bytes, head_controller_bytes,
    output wire [63:0] projection_controller_bytes, projection_clamp_controller_bytes,
    output wire [63:0] norm_controller_bytes, clamp_controller_bytes
);
    localparam [5:0] IDLE = 0, VALIDATE = 1, PRE_START = 2, PRE_WAIT = 3,
        PRE_CHECK = 4, HEAD_START = 5, HEAD_WAIT = 6, HEAD_CHECK = 7,
        PROJECTION_START = 8, PROJECTION_WAIT = 9, PROJECTION_REGISTER = 10,
        CLAMP_START = 11, CLAMP_WAIT = 12, STORE = 13, ROW_ADVANCE = 14,
        NORM_START = 15, NORM_WAIT = 16, RESIDUAL_READ = 17,
        RESIDUAL_CAPTURE = 18, RESIDUAL_ADD = 19, NARROW = 20,
        OUTPUT_REGISTER = 21, EMIT = 22, OUTPUT_ADVANCE = 23,
        NORM_CHECK = 24, FP_START = 25, FP_WAIT = 26,
        PUBLISH = 27, RESPONSE = 28,
        RAW_SEND = 29, RAW_WAIT = 30, RAW_STORE = 31;
    localparam [3:0] S_IDLE = 0, S_VALIDATE = 1, S_READ = 2, S_CAPTURE = 3,
        S_RESPONSE = 4, REBUILD_START = 5, REBUILD_WAIT = 6, REBUILD_CHECK = 7;
    reg [5:0] state, fp_return;
    reg [3:0] source_state;
    reg [1:0] model_hold, precision_hold, source_bank;
    reg [7:0] layer_hold;
    reg [2:0] head_hold;
    reg [31:0] generation_hold, frames_hold, tokens_hold, token_hold;
    reg [31:0] raw_received, normalized_received, received, emitted, row_hold;
    reg [31:0] source_token_hold, source_index_hold, cache_token, output_index_hold;
    reg [63:0] audio_hold, weights_hold;
    reg raw_allocated, head_allocated, cache_allocated, working_allocated;
    reg raw_visible, head_visible, cache_visible, working_visible;
    reg pre_bad, receive_bad, source_tag_bad;
    reg [15:0] cache_q, head_q, working_q, source_data_hold;
    wire [15:0] residual_q;
    reg [15:0] projection_hold, clamped_hold, normalized_hold, output_hold;
    reg [31:0] fp_a, fp_b, fp_value;
    reg [2:0] fp_op;
    reg [3:0] child_error_hold, source_error_hold, first_source_error, error_hold;
    (* ramstyle = "M20K", nomem2reg *) reg [15:0] heads [0:1023];
    (* ramstyle = "M20K", nomem2reg *) reg [15:0] normalized_source [0:1023];
    (* ramstyle = "M20K", nomem2reg *) reg [15:0] working [0:1023];

    initial begin
        if (FRAME_HEADS != 0 && FRAME_HEADS != 1)
            $fatal(1, "PARAMETER ERROR: FRAME_HEADS must be 0 or 1");
        if ((PRECOMPUTED_RAW != 0 && PRECOMPUTED_RAW != 1) ||
            (PRECOMPUTED_RAW && !FRAME_HEADS))
            $fatal(1, "PARAMETER ERROR: PRECOMPUTED_RAW requires FRAME_HEADS");
    end
    wire pre_selected = rst_n && (state == PRE_START || state == PRE_WAIT ||
        (state == HEAD_WAIT && (source_state == REBUILD_START || source_state == REBUILD_WAIT)));
    wire head_selected = rst_n && !FRAME_HEADS &&
        (state == HEAD_START || state == HEAD_WAIT) && !pre_selected;
    wire projection_selected = rst_n && (state == PROJECTION_START || state == PROJECTION_WAIT);
    wire norm_selected = rst_n && (state == NORM_START || state == NORM_WAIT ||
        state == RESIDUAL_READ || state == RESIDUAL_CAPTURE || state == RESIDUAL_ADD ||
        state == NARROW || state == OUTPUT_REGISTER || state == EMIT ||
        state == OUTPUT_ADVANCE || state == FP_START || state == FP_WAIT ||
        state == RAW_SEND || state == RAW_WAIT || state == RAW_STORE);
    wire pre_ready, pre_valid, pre_output_valid, pre_output_last, pre_output_kind;
    wire pre_cmd_valid, pre_result_ready;
    wire pre_source_valid, pre_source_rsp_ready;
    wire [1:0] pre_source_model;
    wire [7:0] pre_source_layer;
    wire [31:0] pre_source_generation, pre_source_token, pre_source_index;
    wire [31:0] pre_output_index;
    wire [15:0] pre_output_data;
    wire [63:0] pre_addr, pre_live, pre_physical;
    wire [3:0] pre_error;
    wire [63:0] pre_control, pre_norm_control, pre_clamp_control;
    wire [63:0] ff_control, ff_norm_control, ff_clamp_control, mlp_control;
    wire [63:0] down_control, down_clamp_control, inner_control, inner_clamp_control;
    wire [31:0] pre_token = state == PRE_START || state == PRE_WAIT ?
        token_hold : source_token_hold;
    generate if (FRAME_HEADS == 0) begin : standalone_pre_attention
    anvil_en1_audio_pre_attention pre_attention (
        .clk(clk), .rst_n(rst_n),
        .raw_only(1'b0),
        .start_valid(rst_n && (state == PRE_START ||
            (state == HEAD_WAIT && source_state == REBUILD_START))),
        .start_ready(pre_ready), .model(model_hold), .precision(precision_hold),
        .layer(layer_hold), .generation(generation_hold), .token(pre_token),
        .audio_weights_base(weights_hold),
        .source_valid(pre_source_valid), .source_ready(pre_selected && source_ready),
        .source_model(pre_source_model), .source_layer(pre_source_layer),
        .source_generation(pre_source_generation), .source_token(pre_source_token),
        .source_index(pre_source_index),
        .source_rsp_valid(pre_selected && source_rsp_valid),
        .source_rsp_ready(pre_source_rsp_ready), .source_rsp_data(source_rsp_data),
        .source_rsp_error(source_rsp_error),
        .cmd_valid(pre_cmd_valid), .cmd_ready(pre_selected && cmd_ready),
        .cmd_write(), .cmd_addr(pre_addr), .cmd_wdata(),
        .result_valid(pre_selected && result_valid), .result_ready(pre_result_ready),
        .result_data(result_data), .result_error(result_error),
        .output_valid(pre_output_valid), .output_ready(pre_selected),
        .output_kind(pre_output_kind), .output_index(pre_output_index),
        .output_data(pre_output_data), .output_last(pre_output_last),
        .done_valid(pre_valid),
        .done_ready(rst_n && (state == PRE_WAIT ||
            (state == HEAD_WAIT && source_state == REBUILD_WAIT))),
        .done_error(pre_error), .intermediate_event(intermediate_event),
        .intermediate_bytes(intermediate_bytes),
        .vector_live_bytes(pre_live), .vector_physical_bytes(pre_physical),
        .controller_bytes(pre_control), .norm_controller_bytes(pre_norm_control),
        .clamp_controller_bytes(pre_clamp_control), .ff_controller_bytes(ff_control),
        .ff_norm_controller_bytes(ff_norm_control), .ff_clamp_controller_bytes(ff_clamp_control),
        .mlp_controller_bytes(mlp_control), .down_controller_bytes(down_control),
        .down_clamp_controller_bytes(down_clamp_control),
        .inner_controller_bytes(inner_control), .inner_clamp_controller_bytes(inner_clamp_control)
    );
    end else if (!PRECOMPUTED_RAW) begin : frame_raw_feedforward
        anvil_en1_audio_feedforward #(.RAW_SOURCE_CALLBACK(1)) feedforward (
            .clk(clk), .rst_n(rst_n),
            .start_valid(rst_n && state == PRE_START), .start_ready(pre_ready),
            .model(model_hold), .precision(precision_hold), .mode(2'd1),
            .layer(layer_hold), .generation(generation_hold), .token(token_hold),
            .audio_weights_base(weights_hold),
            .source_valid(pre_source_valid), .source_ready(pre_selected && source_ready),
            .source_model(pre_source_model), .source_mode(),
            .source_layer(pre_source_layer), .source_generation(pre_source_generation),
            .source_token(pre_source_token), .source_index(pre_source_index),
            .source_rsp_valid(pre_selected && source_rsp_valid),
            .source_rsp_ready(pre_source_rsp_ready), .source_rsp_data(source_rsp_data),
            .source_rsp_error(source_rsp_error),
            .cmd_valid(pre_cmd_valid), .cmd_ready(pre_selected && cmd_ready),
            .cmd_write(), .cmd_addr(pre_addr), .cmd_wdata(),
            .result_valid(pre_selected && result_valid), .result_ready(pre_result_ready),
            .result_data(result_data), .result_error(result_error),
            .output_valid(pre_output_valid), .output_ready(pre_selected),
            .output_index(pre_output_index), .output_data(pre_output_data),
            .output_last(pre_output_last), .done_valid(pre_valid),
            .done_ready(rst_n && state == PRE_WAIT), .done_error(pre_error),
            .weight_read_event(), .weight_read_bytes(),
            .intermediate_event(intermediate_event), .intermediate_bytes(intermediate_bytes),
            .vector_live_bytes(pre_live), .vector_physical_bytes(pre_physical),
            .vector_ram_write(), .vector_ram_read(), .vector_ram_waddr(),
            .vector_ram_raddr(), .vector_ram_wdata(), .vector_ram_rdata(48'd0),
            .controller_bytes(ff_control), .norm_controller_bytes(ff_norm_control),
            .clamp_controller_bytes(ff_clamp_control), .mlp_controller_bytes(mlp_control),
            .down_controller_bytes(down_control), .down_clamp_controller_bytes(down_clamp_control),
            .inner_controller_bytes(inner_control), .inner_clamp_controller_bytes(inner_clamp_control)
        );
        assign pre_output_kind = 0;
        assign pre_control = 0;
        assign pre_norm_control = 0;
        assign pre_clamp_control = 0;
    end else begin : supplied_raw_feedforward
        assign pre_ready = 0;
        assign pre_valid = 0;
        assign pre_output_valid = 0;
        assign pre_output_last = 0;
        assign pre_output_kind = 0;
        assign pre_output_index = 0;
        assign pre_output_data = 0;
        assign pre_error = 0;
        assign pre_cmd_valid = 0;
        assign pre_addr = 0;
        assign pre_result_ready = 0;
        assign pre_source_valid = 0;
        assign pre_source_rsp_ready = 0;
        assign pre_source_model = 0;
        assign pre_source_layer = 0;
        assign pre_source_generation = 0;
        assign pre_source_token = 0;
        assign pre_source_index = 0;
        assign pre_live = 0;
        assign pre_physical = 0;
        assign pre_control = 0;
        assign pre_norm_control = 0;
        assign pre_clamp_control = 0;
        assign ff_control = 0;
        assign ff_norm_control = 0;
        assign ff_clamp_control = 0;
        assign mlp_control = 0;
        assign down_control = 0;
        assign down_clamp_control = 0;
        assign inner_control = 0;
        assign inner_clamp_control = 0;
        assign intermediate_event = 0;
        assign intermediate_bytes = 0;
    end endgenerate
    assign pre_controller_bytes = !rst_n ? 64'd0 :
        pre_control + pre_norm_control + pre_clamp_control + ff_control +
        ff_norm_control + ff_clamp_control + mlp_control + down_control +
        down_clamp_control + inner_control + inner_clamp_control;
    wire head_ready, head_valid, head_output_valid, head_output_last;
    wire head_source_valid, head_source_rsp_ready, head_cmd_valid, head_result_ready;
    wire [1:0] head_source_model;
    wire [7:0] head_source_layer;
    wire [31:0] head_source_generation, head_source_token, head_source_index;
    wire [9:0] head_output_index;
    wire [15:0] head_output_data;
    wire [63:0] head_addr;
    wire [3:0] head_error;
    wire [63:0] executor_control, arithmetic_head_control, block_control, input_control, tile_control;
    wire [63:0] clipped_control, tile_clamp_control, position_control, softplus_control;
    wire head_projection_event;
    wire [31:0] head_projection_bytes;
    generate if (FRAME_HEADS == 0) begin : standalone_attention
    anvil_en1_audio_attention_execute attention (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && !FRAME_HEADS && state == HEAD_START), .start_ready(head_ready),
        .model(model_hold), .precision(precision_hold), .generation(generation_hold),
        .frames(frames_hold), .query_token(token_hold), .layer(layer_hold), .head(head_hold),
        .audio_base(audio_hold), .audio_weights_base(weights_hold),
        .resume_valid(1'b0), .resume_checkpoint(1024'd0),
        .need_valid(), .need_ready(1'b0), .need_action(2'd0),
        .need_model(), .need_precision(), .need_selector(), .need_generation(), .need_token(),
        .need_layer(), .need_head(), .need_component(),
        .checkpoint_valid(), .checkpoint_ready(1'b0), .checkpoint_data(),
        .source_valid(head_source_valid),
        .source_ready(rst_n && state == HEAD_WAIT && source_state == S_IDLE),
        .source_model(head_source_model), .source_layer(head_source_layer),
        .source_generation(head_source_generation), .source_token(head_source_token),
        .source_index(head_source_index),
        .source_rsp_valid(rst_n && state == HEAD_WAIT && source_state == S_RESPONSE),
        .source_rsp_ready(head_source_rsp_ready), .source_rsp_data(source_data_hold),
        .source_rsp_error(source_error_hold != 0),
        .cmd_valid(head_cmd_valid), .cmd_ready(head_selected && cmd_ready),
        .cmd_write(), .cmd_addr(head_addr), .cmd_wdata(),
        .result_valid(head_selected && result_valid), .result_ready(head_result_ready),
        .result_data(result_data), .result_error(result_error),
        .output_valid(head_output_valid), .output_ready(rst_n && state == HEAD_WAIT),
        .output_index(head_output_index), .output_data(head_output_data), .output_last(head_output_last),
        .done_valid(head_valid),
        .done_ready(rst_n && state == HEAD_WAIT && source_state == S_IDLE),
        .done_yield(), .done_error(head_error),
        .input_read_event(input_read_event), .input_read_bytes(input_read_bytes),
        .weight_read_event(), .weight_read_bytes(),
        .projection_event(head_projection_event), .projection_bytes(head_projection_bytes),
        .controller_bytes(executor_control), .head_controller_bytes(arithmetic_head_control),
        .block_controller_bytes(block_control),
        .input_controller_bytes(input_control), .tile_controller_bytes(tile_control),
        .clipped_controller_bytes(clipped_control), .clamp_controller_bytes(tile_clamp_control),
        .position_controller_bytes(position_control), .softplus_controller_bytes(softplus_control)
    );
    end else begin : supplied_heads
        assign head_ready = 0;
        assign head_valid = 0;
        assign head_output_valid = 0;
        assign head_output_last = 0;
        assign head_source_valid = 0;
        assign head_source_rsp_ready = 0;
        assign head_cmd_valid = 0;
        assign head_result_ready = 0;
        assign head_source_model = 0;
        assign head_source_layer = 0;
        assign head_source_generation = 0;
        assign head_source_token = 0;
        assign head_source_index = 0;
        assign head_output_index = 0;
        assign head_output_data = 0;
        assign head_addr = 0;
        assign head_error = 0;
        assign executor_control = 0;
        assign arithmetic_head_control = 0;
        assign block_control = 0;
        assign input_control = 0;
        assign tile_control = 0;
        assign clipped_control = 0;
        assign tile_clamp_control = 0;
        assign position_control = 0;
        assign softplus_control = 0;
        assign head_projection_event = 0;
        assign head_projection_bytes = 0;
        assign input_read_event = 0;
        assign input_read_bytes = 0;
    end endgenerate
    assign head_controller_bytes = !rst_n || FRAME_HEADS ? 64'd0 :
        executor_control + arithmetic_head_control + block_control + input_control + tile_control +
        clipped_control + tile_clamp_control + position_control + softplus_control;
    wire projection_ready, projection_valid, projection_source_valid, projection_source_rsp_ready;
    wire projection_cmd_valid, projection_result_ready;
    wire [31:0] projection_source_index, projection_data;
    wire [63:0] projection_addr;
    wire [3:0] projection_error;
    anvil_en1_clipped_projection post_projection (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == PROJECTION_START), .start_ready(projection_ready),
        .model(model_hold), .precision(precision_hold), .image_class(2'd2),
        .image_base(weights_hold), .tensor_kind(16'h210a),
        .tensor_layer({8'd0, layer_hold}), .row_index(row_hold),
        .source_valid(projection_source_valid),
        .source_ready(rst_n && state == PROJECTION_WAIT &&
            (FRAME_HEADS ? source_ready : source_state == S_IDLE)),
        .source_index(projection_source_index),
        .source_rsp_valid(rst_n && state == PROJECTION_WAIT &&
            (FRAME_HEADS ? source_rsp_valid : source_state == S_RESPONSE)),
        .source_rsp_ready(projection_source_rsp_ready),
        .source_rsp_data(FRAME_HEADS ? source_rsp_data : source_data_hold),
        .source_rsp_error(FRAME_HEADS ? source_rsp_error : source_error_hold != 0),
        .cmd_valid(projection_cmd_valid), .cmd_ready(projection_selected && cmd_ready),
        .cmd_write(), .cmd_addr(projection_addr), .cmd_wdata(),
        .result_valid(projection_selected && result_valid), .result_ready(projection_result_ready),
        .result_data(result_data), .result_error(result_error),
        .done_valid(projection_valid),
        .done_ready(rst_n && state == PROJECTION_WAIT && source_state == S_IDLE),
        .done_data(projection_data), .done_error(projection_error),
        .controller_bytes(projection_controller_bytes),
        .clamp_controller_bytes(projection_clamp_controller_bytes)
    );
    wire clamp_ready, clamp_valid, norm_ready, norm_valid, fp_ready, fp_valid;
    wire [15:0] clamp_data;
    wire [3:0] clamp_error, norm_error, fp_error;
    anvil_en1_bf16_clamp clamp (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == CLAMP_START), .start_ready(clamp_ready),
        .value(projection_hold), .minimum(16'hd015), .maximum(16'h5015),
        .done_valid(clamp_valid), .done_ready(rst_n && state == CLAMP_WAIT),
        .done_data(clamp_data), .done_error(clamp_error), .controller_bytes(clamp_controller_bytes)
    );
    wire norm_source_valid, norm_source_rsp_ready, norm_cmd_valid, norm_result_ready;
    wire norm_output_valid, norm_output_last;
    wire [31:0] norm_source_index, norm_output_index;
    wire [15:0] norm_output_data;
    wire [63:0] norm_addr;
    anvil_en1_native_norm norm (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == NORM_START), .start_ready(norm_ready),
        .model(model_hold), .precision(precision_hold), .image_class(2'd2),
        .tensor_kind(16'h210b), .tensor_layer({8'd0, layer_hold}),
        .vector_length(32'd1024), .weights_base(weights_hold),
        .source_valid(norm_source_valid),
        .source_ready(rst_n && state == NORM_WAIT && source_state == S_IDLE),
        .source_index(norm_source_index),
        .source_rsp_valid(rst_n && state == NORM_WAIT && source_state == S_RESPONSE),
        .source_rsp_ready(norm_source_rsp_ready), .source_rsp_data(source_data_hold),
        .source_rsp_error(source_error_hold != 0),
        .cmd_valid(norm_cmd_valid), .cmd_ready(norm_selected && cmd_ready),
        .cmd_write(), .cmd_addr(norm_addr), .cmd_wdata(),
        .result_valid(norm_selected && result_valid), .result_ready(norm_result_ready),
        .result_data(result_data), .result_error(result_error),
        .output_valid(norm_output_valid), .output_ready(rst_n && state == NORM_WAIT),
        .output_index(norm_output_index), .output_data(norm_output_data), .output_last(norm_output_last),
        .done_valid(norm_valid),
        .done_ready(rst_n && state == NORM_WAIT && source_state == S_IDLE && !norm_output_valid),
        .done_error(norm_error), .controller_bytes(norm_controller_bytes)
    );
    wire [31:0] fp_data;
    wire [63:0] primitive_fp_bytes;
    anvil_en1_fp32 arithmetic (
        .controller_bytes(primitive_fp_bytes),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == FP_START), .start_ready(fp_ready),
        .operation(fp_op), .operand_a(fp_a), .operand_b(fp_b),
        .done_valid(fp_valid), .done_ready(rst_n && state == FP_WAIT),
        .done_data(fp_data), .done_error(fp_error)
    );
    wire pre_raw_good = raw_received < 1024 && normalized_received == 0 &&
        pre_output_index == raw_received && pre_output_last == (raw_received == 1023);
    wire pre_normalized_good = raw_received == 1024 && normalized_received < 1024 &&
        pre_output_index == normalized_received && pre_output_last == (normalized_received == 1023);
    wire pre_beat_good = !pre_bad && (pre_output_kind ? pre_normalized_good : pre_raw_good);
    wire pre_complete = !pre_bad && raw_received == 1024 &&
        normalized_received == (FRAME_HEADS ? 0 : 1024);
    wire head_beat_good = received < 128 && head_output_index == received &&
        head_output_last == (received == 127);
    wire norm_beat_good = received < 1024 && norm_output_index == received &&
        norm_output_last == (received == 1023);
    wire head_source_tag = head_source_generation == generation_hold &&
        head_source_model == model_hold && head_source_layer == layer_hold;
    wire callback_valid = state == HEAD_WAIT ? head_source_valid :
        (state == PROJECTION_WAIT ? projection_source_valid : norm_source_valid);
    wire [31:0] callback_index = state == HEAD_WAIT ? head_source_index :
        (state == PROJECTION_WAIT ? projection_source_index : norm_source_index);
    wire callback_ready = state == HEAD_WAIT ? head_source_rsp_ready :
        (state == PROJECTION_WAIT ? projection_source_rsp_ready : norm_source_rsp_ready);
    wire rebuilding_start = rst_n && state == HEAD_WAIT &&
        source_state == REBUILD_START && pre_ready;
    wire cache_miss = rst_n && source_state == S_VALIDATE && source_bank == 0 &&
        !source_tag_bad && source_index_hold < 1024 && source_token_hold < tokens_hold &&
        first_source_error == 0 && (!cache_visible || cache_token != source_token_hold);
    generate if (!PRECOMPUTED_RAW) begin : retained_raw_residual
        (* ramstyle = "M20K", nomem2reg *) reg [15:0] residual [0:1023];
        reg [15:0] read_q;
        assign residual_q = read_q;
        always @(posedge clk) begin
            if (pre_selected && pre_output_valid && pre_beat_good &&
                !pre_output_kind && state == PRE_WAIT)
                residual[pre_output_index[9:0]] <= pre_output_data;
            if (rst_n && state == RESIDUAL_READ && output_index_hold < 1024 && raw_visible)
                read_q <= residual[output_index_hold[9:0]];
        end
    end else begin : callback_raw_residual
        assign residual_q = 0;
    end endgenerate
    always @(posedge clk) begin
        if (pre_selected && pre_output_valid && pre_beat_good) begin
            if (pre_output_kind && !FRAME_HEADS)
                normalized_source[pre_output_index[9:0]] <= pre_output_data;
        end
        if (rst_n && !FRAME_HEADS && state == HEAD_WAIT &&
            head_output_valid && !receive_bad && head_beat_good)
            heads[{head_hold, head_output_index[6:0]}] <= head_output_data;
        if (rst_n && state == STORE)
            working[row_hold[9:0]] <= clamped_hold;
        if (rst_n && source_state == S_READ) begin
            if (source_bank == 0 && !FRAME_HEADS)
                cache_q <= normalized_source[source_index_hold[9:0]];
            else if (source_bank == 1 && !FRAME_HEADS)
                head_q <= heads[source_index_hold[9:0]];
            else
                working_q <= working[source_index_hold[9:0]];
        end
    end
    assign start_ready = rst_n && state == IDLE;
    wire frame_source = rst_n && FRAME_HEADS && state == PROJECTION_WAIT;
    wire raw_source = rst_n && PRECOMPUTED_RAW &&
        (state == RAW_SEND || state == RAW_WAIT);
    assign source_valid = (pre_selected && pre_source_valid) ||
        (frame_source && projection_source_valid) ||
        (raw_source && state == RAW_SEND);
    assign source_kind = frame_source;
    assign source_model = !rst_n ? 2'd0 :
        (pre_selected ? pre_source_model : (frame_source || raw_source ? model_hold : 2'd0));
    assign source_layer = !rst_n ? 8'd0 :
        (pre_selected ? pre_source_layer : (frame_source || raw_source ? layer_hold : 8'd0));
    assign source_generation = !rst_n ? 32'd0 :
        (pre_selected ? pre_source_generation :
            (frame_source || raw_source ? generation_hold : 32'd0));
    assign source_token = !rst_n ? 32'd0 :
        (pre_selected ? pre_source_token : (frame_source || raw_source ? token_hold : 32'd0));
    assign source_index = !rst_n ? 32'd0 :
        (pre_selected ? pre_source_index : (frame_source ? projection_source_index :
            (raw_source ? output_index_hold : 32'd0)));
    assign source_rsp_ready = (pre_selected && pre_source_rsp_ready) ||
        (frame_source && projection_source_rsp_ready) ||
        (raw_source && state == RAW_WAIT);
    assign cmd_valid = pre_selected ? pre_cmd_valid : (head_selected ? head_cmd_valid :
        (projection_selected ? projection_cmd_valid : (norm_selected && norm_cmd_valid)));
    assign cmd_write = 0;
    assign cmd_addr = !rst_n ? 64'd0 : (pre_selected ? pre_addr :
        (head_selected ? head_addr : (projection_selected ? projection_addr :
        (norm_selected ? norm_addr : 64'd0))));
    assign cmd_wdata = 0;
    assign result_ready = pre_selected ? pre_result_ready : (head_selected ? head_result_ready :
        (projection_selected ? projection_result_ready : (norm_selected && norm_result_ready)));
    assign output_valid = rst_n && state == EMIT;
    assign output_index = rst_n ? output_index_hold : 32'd0;
    assign output_data = rst_n ? output_hold : 16'd0;
    assign output_last = rst_n && state == EMIT && output_index_hold == 1023;
    assign done_valid = rst_n && state == RESPONSE;
    assign done_error = rst_n ? error_hold : 4'd0;
    wire output_projection_event = rst_n && state == PROJECTION_WAIT &&
        source_state == S_IDLE && projection_valid && projection_error == 0;
    assign projection_event = head_projection_event || output_projection_event;
    assign projection_bytes = head_projection_bytes + (output_projection_event ? 32'd2 : 32'd0);
    assign vector_live_bytes = !rst_n ? 64'd0 :
        (raw_allocated ? 64'd2048 : 64'd0) + (head_allocated ? 64'd2048 : 64'd0) +
        (cache_allocated ? 64'd2048 : 64'd0) + (working_allocated ? 64'd2048 : 64'd0) + pre_live;
    assign vector_physical_bytes = rst_n ?
        (FRAME_HEADS ? (PRECOMPUTED_RAW ? 64'd2048 : 64'd4096) :
            64'd8192) + pre_physical : 64'd0;
    localparam integer CONTROLLER_BITS =
        $bits(state) + $bits(fp_return) + $bits(source_state) + $bits(model_hold) +
        $bits(precision_hold) + $bits(source_bank) + $bits(layer_hold) + $bits(head_hold) +
        $bits(generation_hold) + $bits(frames_hold) + $bits(tokens_hold) + $bits(token_hold) +
        $bits(raw_received) + $bits(normalized_received) + $bits(received) + $bits(emitted) +
        $bits(row_hold) + $bits(source_token_hold) + $bits(source_index_hold) +
        $bits(cache_token) + $bits(output_index_hold) + $bits(audio_hold) + $bits(weights_hold) +
        $bits(raw_allocated) + $bits(head_allocated) + $bits(cache_allocated) +
        $bits(working_allocated) + $bits(raw_visible) + $bits(head_visible) +
        $bits(cache_visible) + $bits(working_visible) + $bits(pre_bad) + $bits(receive_bad) +
        $bits(source_tag_bad) + $bits(cache_q) + $bits(head_q) + $bits(working_q) +
        (PRECOMPUTED_RAW ? 0 : $bits(residual_q)) +
        $bits(source_data_hold) + $bits(projection_hold) +
        $bits(clamped_hold) + $bits(normalized_hold) + $bits(output_hold) +
        $bits(fp_a) + $bits(fp_b) + $bits(fp_value) + $bits(fp_op) +
        $bits(child_error_hold) + $bits(source_error_hold) + $bits(first_source_error) + $bits(error_hold);
    assign controller_bytes = !rst_n ? 64'd0 :
        64'((CONTROLLER_BITS + 7) >> 3) + primitive_fp_bytes;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            source_state <= S_IDLE;
            source_bank <= 0;
            source_token_hold <= 0;
            source_index_hold <= 0;
            source_tag_bad <= 0;
            source_data_hold <= 0;
            source_error_hold <= 0;
            first_source_error <= 0;
        end else begin
            if (state == IDLE && start_valid && start_ready)
                first_source_error <= 0;
            case (source_state)
                S_IDLE: if ((state == HEAD_WAIT ||
                    (!FRAME_HEADS && state == PROJECTION_WAIT) || state == NORM_WAIT) &&
                    callback_valid) begin
                    source_bank <= state == HEAD_WAIT ? 2'd0 :
                        (state == PROJECTION_WAIT ? 2'd1 : 2'd2);
                    source_index_hold <= callback_index;
                    source_token_hold <= state == HEAD_WAIT ? head_source_token : token_hold;
                    source_tag_bad <= state == HEAD_WAIT && !head_source_tag;
                    source_error_hold <= 0;
                    source_data_hold <= 0;
                    source_state <= S_VALIDATE;
                end
                S_VALIDATE: begin
                    if (source_tag_bad || source_index_hold >= 1024 ||
                        first_source_error != 0 ||
                        (source_bank == 0 && source_token_hold >= tokens_hold) ||
                        (source_bank == 1 && !head_visible) ||
                        (source_bank == 2 && !working_visible)) begin
                        source_error_hold <= first_source_error != 0 ? first_source_error : 4'd7;
                        if (first_source_error == 0)
                            first_source_error <= 7;
                        source_state <= S_RESPONSE;
                    end else if (source_bank == 0 &&
                        (!cache_visible || cache_token != source_token_hold))
                        source_state <= REBUILD_START;
                    else
                        source_state <= S_READ;
                end
                REBUILD_START: if (pre_ready)
                    source_state <= REBUILD_WAIT;
                REBUILD_WAIT: if (pre_valid) begin
                    source_error_hold <= pre_error;
                    source_state <= REBUILD_CHECK;
                end
                REBUILD_CHECK: begin
                    if (source_error_hold != 0 || !pre_complete) begin
                        if (source_error_hold == 0)
                            source_error_hold <= 7;
                        if (first_source_error == 0)
                            first_source_error <= source_error_hold != 0 ? source_error_hold : 4'd7;
                        source_state <= S_RESPONSE;
                    end else
                        source_state <= S_READ;
                end
                S_READ: source_state <= S_CAPTURE;
                S_CAPTURE: begin
                    if (source_bank == 0)
                        source_data_hold <= cache_q;
                    else if (source_bank == 1)
                        source_data_hold <= head_q;
                    else
                        source_data_hold <= working_q;
                    source_state <= S_RESPONSE;
                end
                S_RESPONSE: if (callback_ready)
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
            model_hold <= 0;
            precision_hold <= 0;
            layer_hold <= 0;
            head_hold <= 0;
            generation_hold <= 0;
            frames_hold <= 0;
            tokens_hold <= 0;
            token_hold <= 0;
            raw_received <= 0;
            normalized_received <= 0;
            received <= 0;
            emitted <= 0;
            row_hold <= 0;
            cache_token <= 0;
            output_index_hold <= 0;
            audio_hold <= 0;
            weights_hold <= 0;
            raw_allocated <= 0;
            head_allocated <= 0;
            cache_allocated <= 0;
            working_allocated <= 0;
            raw_visible <= 0;
            head_visible <= 0;
            cache_visible <= 0;
            working_visible <= 0;
            pre_bad <= 0;
            receive_bad <= 0;
            projection_hold <= 0;
            clamped_hold <= 0;
            normalized_hold <= 0;
            output_hold <= 0;
            fp_a <= 0;
            fp_b <= 0;
            fp_value <= 0;
            fp_op <= 0;
            child_error_hold <= 0;
            error_hold <= 0;
        end else begin
            if (pre_selected && pre_output_valid) begin
                if (!pre_beat_good)
                    pre_bad <= 1;
                if (!pre_output_kind && state == PRE_WAIT && pre_beat_good)
                    raw_allocated <= 1;
                if (pre_output_kind) begin
                    if (normalized_received < 1024)
                        normalized_received <= normalized_received + 1'b1;
                end else if (raw_received < 1024)
                    raw_received <= raw_received + 1'b1;
            end
            if (cache_miss) begin
                cache_visible <= 0;
                cache_allocated <= !FRAME_HEADS;
            end
            if (rebuilding_start) begin
                raw_received <= 0;
                normalized_received <= 0;
                pre_bad <= 0;
                cache_token <= source_token_hold;
            end
            if (state == HEAD_WAIT && source_state == REBUILD_CHECK &&
                source_error_hold == 0 && pre_complete)
                cache_visible <= 1;
            if (state == HEAD_WAIT && head_output_valid) begin
                if (!head_beat_good)
                    receive_bad <= 1;
                if (received < 128)
                    received <= received + 1'b1;
            end
            case (state)
                IDLE: if (start_valid && start_ready) begin
                    model_hold <= model;
                    precision_hold <= precision;
                    layer_hold <= layer;
                    generation_hold <= generation;
                    frames_hold <= frames;
                    tokens_hold <= (frames + 32'd3) >> 2;
                    token_hold <= token;
                    audio_hold <= audio_base;
                    weights_hold <= audio_weights_base;
                    raw_received <= 0;
                    normalized_received <= 0;
                    received <= 0;
                    emitted <= 0;
                    row_hold <= 0;
                    head_hold <= 0;
                    raw_allocated <= 0;
                    cache_allocated <= !FRAME_HEADS;
                    head_allocated <= 0;
                    working_allocated <= 0;
                    raw_visible <= 0;
                    head_visible <= 0;
                    cache_visible <= 0;
                    working_visible <= 0;
                    pre_bad <= 0;
                    receive_bad <= 0;
                    child_error_hold <= 0;
                    error_hold <= 0;
                    state <= VALIDATE;
                end
                VALIDATE: begin
                    if ((model_hold != 1 && model_hold != 2) || precision_hold > 1) begin
                        error_hold <= 6;
                        state <= PUBLISH;
                    end else if (generation_hold == 0 || frames_hold == 0 || frames_hold > 131072 ||
                        token_hold >= tokens_hold || layer_hold >= 12 ||
                        audio_hold[1:0] != 0 || weights_hold[1:0] != 0) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else if (PRECOMPUTED_RAW) begin
                        raw_visible <= 1;
                        working_allocated <= 1;
                        state <= PROJECTION_START;
                    end else
                        state <= PRE_START;
                end
                RAW_SEND: if (source_ready)
                    state <= RAW_WAIT;
                RAW_WAIT: if (source_rsp_valid) begin
                    projection_hold <= source_rsp_data;
                    child_error_hold <= source_rsp_error ? 4'd3 : 4'd0;
                    state <= RAW_STORE;
                end
                RAW_STORE: begin
                    if (child_error_hold != 0) begin
                        error_hold <= child_error_hold;
                        state <= OUTPUT_ADVANCE;
                    end else
                        state <= RESIDUAL_ADD;
                end
                PRE_START: if (pre_ready) begin
                    cache_token <= token_hold;
                    state <= PRE_WAIT;
                end
                PRE_WAIT: if (pre_valid) begin
                    child_error_hold <= pre_error;
                    state <= PRE_CHECK;
                end
                PRE_CHECK: begin
                    if (child_error_hold != 0 || !pre_complete) begin
                        error_hold <= child_error_hold != 0 ? child_error_hold : 4'd7;
                        state <= PUBLISH;
                    end else begin
                        raw_visible <= 1;
                        if (FRAME_HEADS) begin
                            working_allocated <= 1;
                            row_hold <= 0;
                            state <= PROJECTION_START;
                        end else begin
                            cache_visible <= 1;
                            head_allocated <= 1;
                            state <= HEAD_START;
                        end
                    end
                end
                HEAD_START: if (head_ready) begin
                    received <= 0;
                    receive_bad <= 0;
                    state <= HEAD_WAIT;
                end
                HEAD_WAIT: if (head_valid && source_state == S_IDLE) begin
                    child_error_hold <= head_error;
                    state <= HEAD_CHECK;
                end
                HEAD_CHECK: begin
                    if (first_source_error != 0 || child_error_hold != 0 ||
                        receive_bad || received != 128) begin
                        error_hold <= first_source_error != 0 ? first_source_error :
                            (child_error_hold != 0 ? child_error_hold : 4'd7);
                        state <= PUBLISH;
                    end else if (head_hold != 7) begin
                        head_hold <= head_hold + 1'b1;
                        state <= HEAD_START;
                    end else begin
                        head_visible <= 1;
                        cache_visible <= 0;
                        cache_allocated <= 0;
                        working_allocated <= 1;
                        row_hold <= 0;
                        state <= PROJECTION_START;
                    end
                end
                PROJECTION_START: if (projection_ready)
                    state <= PROJECTION_WAIT;
                PROJECTION_WAIT: if (projection_valid && source_state == S_IDLE) begin
                    child_error_hold <= projection_error;
                    projection_hold <= projection_data[15:0];
                    state <= PROJECTION_REGISTER;
                end
                PROJECTION_REGISTER: begin
                    if (first_source_error != 0 || child_error_hold != 0) begin
                        error_hold <= first_source_error != 0 ? first_source_error : child_error_hold;
                        state <= PUBLISH;
                    end else
                        state <= CLAMP_START;
                end
                CLAMP_START: if (clamp_ready)
                    state <= CLAMP_WAIT;
                CLAMP_WAIT: if (clamp_valid) begin
                    if (clamp_error != 0) begin
                        error_hold <= clamp_error;
                        state <= PUBLISH;
                    end else begin
                        clamped_hold <= clamp_data;
                        state <= STORE;
                    end
                end
                STORE: state <= ROW_ADVANCE;
                ROW_ADVANCE: begin
                    if (row_hold == 1023) begin
                        working_visible <= 1;
                        head_visible <= 0;
                        head_allocated <= 0;
                        state <= NORM_START;
                    end else begin
                        row_hold <= row_hold + 1'b1;
                        state <= PROJECTION_START;
                    end
                end
                NORM_START: if (norm_ready) begin
                    received <= 0;
                    emitted <= 0;
                    receive_bad <= 0;
                    state <= NORM_WAIT;
                end
                NORM_WAIT: begin
                    if (norm_output_valid) begin
                        if (!norm_beat_good)
                            receive_bad <= 1;
                        if (received < 1024)
                            received <= received + 1'b1;
                        if (error_hold == 0) begin
                            normalized_hold <= norm_output_data;
                            output_index_hold <= norm_output_index;
                            state <= RESIDUAL_READ;
                        end
                    end else if (norm_valid && source_state == S_IDLE) begin
                        child_error_hold <= norm_error;
                        state <= NORM_CHECK;
                    end
                end
                RESIDUAL_READ: begin
                    if (!raw_visible || output_index_hold >= 1024) begin
                        receive_bad <= 1;
                        if (error_hold == 0)
                            error_hold <= 7;
                        state <= OUTPUT_ADVANCE;
                    end else if (PRECOMPUTED_RAW)
                        state <= RAW_SEND;
                    else
                        state <= RESIDUAL_CAPTURE;
                end
                RESIDUAL_CAPTURE: state <= RESIDUAL_ADD;
                RESIDUAL_ADD: begin
                    fp_op <= 0;
                    fp_a <= {PRECOMPUTED_RAW ? projection_hold : residual_q, 16'd0};
                    fp_b <= {normalized_hold, 16'd0};
                    fp_return <= NARROW;
                    state <= FP_START;
                end
                NARROW: begin
                    fp_op <= 3;
                    fp_a <= fp_value;
                    fp_b <= 0;
                    fp_return <= OUTPUT_REGISTER;
                    state <= FP_START;
                end
                OUTPUT_REGISTER: begin
                    output_hold <= fp_value[15:0];
                    state <= EMIT;
                end
                EMIT: if (output_ready) begin
                    if (emitted < 1024)
                        emitted <= emitted + 1'b1;
                    state <= OUTPUT_ADVANCE;
                end
                OUTPUT_ADVANCE: state <= NORM_WAIT;
                NORM_CHECK: begin
                    if (error_hold == 0) begin
                        if (first_source_error != 0 || child_error_hold != 0)
                            error_hold <= first_source_error != 0 ? first_source_error : child_error_hold;
                        else if (receive_bad || received != 1024 || emitted != 1024)
                            error_hold <= 7;
                    end
                    state <= PUBLISH;
                end
                FP_START: if (fp_ready)
                    state <= FP_WAIT;
                FP_WAIT: if (fp_valid) begin
                    if (fp_error != 0) begin
                        if (error_hold == 0)
                            error_hold <= fp_error;
                        state <= OUTPUT_ADVANCE;
                    end else begin
                        fp_value <= fp_data;
                        state <= fp_return;
                    end
                end
                PUBLISH: state <= RESPONSE;
                RESPONSE: if (done_ready) begin
                    raw_visible <= 0;
                    head_visible <= 0;
                    cache_visible <= 0;
                    working_visible <= 0;
                    raw_allocated <= 0;
                    head_allocated <= 0;
                    cache_allocated <= 0;
                    working_allocated <= 0;
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
