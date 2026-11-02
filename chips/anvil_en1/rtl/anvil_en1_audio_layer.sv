module anvil_en1_audio_layer (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] model, precision,
    input wire [7:0] layer,
    input wire [31:0] generation, frames, token,
    input wire [63:0] audio_base, audio_weights_base,
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
    output wire projection_event, intermediate_event, attention_replay_event,
    output wire [31:0] projection_bytes, intermediate_bytes, attention_replay_bytes,
    output wire glu_replay_event,
    output wire [31:0] glu_replay_bytes,
    output wire [63:0] vector_live_bytes, vector_physical_bytes,
    output wire [63:0] controller_bytes, nested_controller_bytes
);
    localparam [4:0] IDLE = 0, VALIDATE = 1,
        ATTENTION_START = 2, ATTENTION_WAIT = 3, ATTENTION_CHECK = 4,
        CONV_START = 5, CONV_WAIT = 6, CONV_CHECK = 7,
        FF_START = 8, FF_WAIT = 9, FF_CHECK = 10,
        CLAMP_START = 11, CLAMP_WAIT = 12, CLAMP_STORE = 13,
        NORM_START = 14, NORM_WAIT = 15, NORM_CHECK = 16,
        PUBLISH = 17, RESPONSE = 18;
    localparam [3:0] S_IDLE = 0, S_VALIDATE = 1, S_READ = 2,
        S_CAPTURE = 3, S_RESPONSE = 4, REBUILD_START = 5,
        REBUILD_WAIT = 6, REBUILD_CHECK = 7;
    reg [4:0] state;
    reg [3:0] source_state;
    reg [1:0] model_hold, precision_hold, source_model_hold, source_bank;
    reg [7:0] layer_hold, source_layer_hold;
    reg [31:0] generation_hold, frames_hold, tokens_hold, token_hold;
    reg [31:0] received, rebuilt, source_generation_hold, source_token_hold;
    reg [31:0] source_index_hold, cache_token, clamp_index;
    reg [63:0] audio_hold, weights_hold;
    reg query_allocated, cache_allocated, working_allocated;
    reg query_visible, cache_visible, working_visible;
    reg receive_bad, rebuild_bad, source_tag_bad;
    reg [15:0] query_q, cache_q, working_q, source_data_hold;
    reg [15:0] clamp_input, clamped_hold;
    reg [3:0] error_hold, child_error_hold, source_error_hold, first_source_error;
    (* ramstyle = "M20K", nomem2reg *) reg [15:0] query_bank [0:1023];
    (* ramstyle = "M20K", nomem2reg *) reg [15:0] cache_bank [0:1023];
    (* ramstyle = "M20K", nomem2reg *) reg [15:0] working_bank [0:1023];

    wire rebuilding = rst_n && state == CONV_WAIT &&
        (source_state == REBUILD_START || source_state == REBUILD_WAIT);
    wire attention_selected = rst_n &&
        (state == ATTENTION_START || state == ATTENTION_WAIT || rebuilding);
    wire conv_selected = rst_n && !rebuilding &&
        (state == CONV_START || state == CONV_WAIT);
    wire ff_selected = rst_n && (state == FF_START || state == FF_WAIT ||
        state == CLAMP_START || state == CLAMP_WAIT || state == CLAMP_STORE);
    wire norm_selected = rst_n && (state == NORM_START || state == NORM_WAIT);
    wire attention_ready, attention_valid, attention_cmd_valid, attention_result_ready;
    wire attention_source_valid, attention_source_rsp_ready;
    wire [1:0] attention_source_model;
    wire [7:0] attention_source_layer;
    wire [31:0] attention_source_generation, attention_source_token, attention_source_index;
    wire attention_output_valid, attention_output_last;
    wire [31:0] attention_output_index;
    wire [15:0] attention_output_data;
    wire [63:0] attention_addr, attention_live, attention_physical;
    wire [3:0] attention_error;
    wire attention_projection_event, attention_intermediate_event;
    wire [31:0] attention_projection_bytes, attention_intermediate_bytes;
    wire [63:0] attention_control, attention_pre_control, attention_head_control;
    wire [63:0] attention_projection_control, attention_projection_clamp_control;
    wire [63:0] attention_norm_control, attention_clamp_control;
    anvil_en1_audio_attention_residual attention_residual (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && (state == ATTENTION_START ||
            (state == CONV_WAIT && source_state == REBUILD_START))),
        .start_ready(attention_ready), .model(model_hold), .precision(precision_hold),
        .layer(layer_hold), .generation(generation_hold), .frames(frames_hold),
        .token(rebuilding ? source_token_hold : token_hold),
        .audio_base(audio_hold), .audio_weights_base(weights_hold),
        .source_valid(attention_source_valid),
        .source_ready(attention_selected && source_ready),
        .source_model(attention_source_model), .source_layer(attention_source_layer),
        .source_generation(attention_source_generation),
        .source_token(attention_source_token), .source_index(attention_source_index),
        .source_rsp_valid(attention_selected && source_rsp_valid),
        .source_rsp_ready(attention_source_rsp_ready),
        .source_rsp_data(source_rsp_data), .source_rsp_error(source_rsp_error),
        .cmd_valid(attention_cmd_valid), .cmd_ready(attention_selected && cmd_ready),
        .cmd_write(), .cmd_addr(attention_addr), .cmd_wdata(),
        .result_valid(attention_selected && result_valid),
        .result_ready(attention_result_ready), .result_data(result_data),
        .result_error(result_error),
        .output_valid(attention_output_valid), .output_ready(attention_selected),
        .output_index(attention_output_index), .output_data(attention_output_data),
        .output_last(attention_output_last),
        .done_valid(attention_valid),
        .done_ready(rst_n && (state == ATTENTION_WAIT ||
            (state == CONV_WAIT && source_state == REBUILD_WAIT)) && !attention_output_valid),
        .done_error(attention_error),
        .input_read_event(input_read_event), .input_read_bytes(input_read_bytes),
        .projection_event(attention_projection_event),
        .projection_bytes(attention_projection_bytes),
        .intermediate_event(attention_intermediate_event),
        .intermediate_bytes(attention_intermediate_bytes),
        .vector_live_bytes(attention_live), .vector_physical_bytes(attention_physical),
        .controller_bytes(attention_control), .pre_controller_bytes(attention_pre_control),
        .head_controller_bytes(attention_head_control),
        .projection_controller_bytes(attention_projection_control),
        .projection_clamp_controller_bytes(attention_projection_clamp_control),
        .norm_controller_bytes(attention_norm_control),
        .clamp_controller_bytes(attention_clamp_control)
    );

    wire conv_ready, conv_valid, conv_cmd_valid, conv_result_ready;
    wire conv_source_valid, conv_source_rsp_ready;
    wire [1:0] conv_source_model;
    wire [7:0] conv_source_layer;
    wire [31:0] conv_source_generation, conv_source_token, conv_source_index;
    wire conv_output_valid, conv_output_last;
    wire [31:0] conv_output_index;
    wire [15:0] conv_output_data;
    wire [63:0] conv_addr, conv_live, conv_physical, conv_control, conv_nested_control;
    wire [3:0] conv_error;
    wire conv_projection_event;
    wire [31:0] conv_projection_bytes;
    anvil_en1_audio_lightconv light_convolution (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == CONV_START), .start_ready(conv_ready),
        .model(model_hold), .precision(precision_hold), .layer(layer_hold),
        .generation(generation_hold), .token(token_hold), .audio_weights_base(weights_hold),
        .source_valid(conv_source_valid),
        .source_ready(rst_n && state == CONV_WAIT && source_state == S_IDLE),
        .source_model(conv_source_model), .source_layer(conv_source_layer),
        .source_generation(conv_source_generation),
        .source_token(conv_source_token), .source_index(conv_source_index),
        .source_rsp_valid(rst_n && state == CONV_WAIT && source_state == S_RESPONSE),
        .source_rsp_ready(conv_source_rsp_ready), .source_rsp_data(source_data_hold),
        .source_rsp_error(source_error_hold != 0),
        .cmd_valid(conv_cmd_valid), .cmd_ready(conv_selected && cmd_ready),
        .cmd_write(), .cmd_addr(conv_addr), .cmd_wdata(),
        .result_valid(conv_selected && result_valid), .result_ready(conv_result_ready),
        .result_data(result_data), .result_error(result_error),
        .output_valid(conv_output_valid), .output_ready(rst_n && state == CONV_WAIT),
        .output_index(conv_output_index), .output_data(conv_output_data),
        .output_last(conv_output_last), .done_valid(conv_valid),
        .done_ready(rst_n && state == CONV_WAIT && source_state == S_IDLE && !conv_output_valid),
        .done_error(conv_error), .weight_read_event(), .weight_read_bytes(),
        .projection_event(conv_projection_event), .projection_bytes(conv_projection_bytes),
        .glu_replay_event(glu_replay_event), .glu_replay_bytes(glu_replay_bytes),
        .vector_live_bytes(conv_live), .vector_physical_bytes(conv_physical),
        .controller_bytes(conv_control), .nested_controller_bytes(conv_nested_control)
    );

    wire ff_ready, ff_valid, ff_cmd_valid, ff_result_ready;
    wire ff_source_valid, ff_source_rsp_ready;
    wire [1:0] ff_source_model, ff_source_mode;
    wire [7:0] ff_source_layer;
    wire [31:0] ff_source_generation, ff_source_token, ff_source_index;
    wire ff_output_valid, ff_output_last;
    wire [31:0] ff_output_index;
    wire [15:0] ff_output_data;
    wire [63:0] ff_addr, ff_live, ff_physical;
    wire [3:0] ff_error;
    wire ff_intermediate_event;
    wire [31:0] ff_intermediate_bytes;
    wire [63:0] ff_control, ff_norm_control, ff_clamp_control, ff_mlp_control;
    wire [63:0] ff_down_control, ff_down_clamp_control;
    wire [63:0] ff_inner_control, ff_inner_clamp_control;
    anvil_en1_audio_feedforward feed_forward2 (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == FF_START), .start_ready(ff_ready),
        .model(model_hold), .precision(precision_hold), .mode(2'd2),
        .layer(layer_hold), .generation(generation_hold), .token(token_hold),
        .audio_weights_base(weights_hold),
        .source_valid(ff_source_valid),
        .source_ready(rst_n && state == FF_WAIT && source_state == S_IDLE),
        .source_model(ff_source_model), .source_mode(ff_source_mode),
        .source_layer(ff_source_layer), .source_generation(ff_source_generation),
        .source_token(ff_source_token), .source_index(ff_source_index),
        .source_rsp_valid(rst_n && state == FF_WAIT && source_state == S_RESPONSE),
        .source_rsp_ready(ff_source_rsp_ready), .source_rsp_data(source_data_hold),
        .source_rsp_error(source_error_hold != 0),
        .cmd_valid(ff_cmd_valid), .cmd_ready(ff_selected && cmd_ready),
        .cmd_write(), .cmd_addr(ff_addr), .cmd_wdata(),
        .result_valid(ff_selected && result_valid), .result_ready(ff_result_ready),
        .result_data(result_data), .result_error(result_error),
        .output_valid(ff_output_valid), .output_ready(rst_n && state == FF_WAIT),
        .output_index(ff_output_index), .output_data(ff_output_data),
        .output_last(ff_output_last), .done_valid(ff_valid),
        .done_ready(rst_n && state == FF_WAIT && source_state == S_IDLE && !ff_output_valid),
        .done_error(ff_error), .weight_read_event(), .weight_read_bytes(),
        .intermediate_event(ff_intermediate_event), .intermediate_bytes(ff_intermediate_bytes),
        .vector_live_bytes(ff_live), .vector_physical_bytes(ff_physical),
        .controller_bytes(ff_control), .norm_controller_bytes(ff_norm_control),
        .clamp_controller_bytes(ff_clamp_control), .mlp_controller_bytes(ff_mlp_control),
        .down_controller_bytes(ff_down_control),
        .down_clamp_controller_bytes(ff_down_clamp_control),
        .inner_controller_bytes(ff_inner_control),
        .inner_clamp_controller_bytes(ff_inner_clamp_control)
    );

    wire clamp_ready, clamp_valid;
    wire [15:0] clamp_data;
    wire [3:0] clamp_error;
    wire [63:0] clamp_control;
    anvil_en1_bf16_clamp final_clamp (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == CLAMP_START), .start_ready(clamp_ready),
        .value(clamp_input), .minimum(16'hd015), .maximum(16'h5015),
        .done_valid(clamp_valid), .done_ready(rst_n && state == CLAMP_WAIT),
        .done_data(clamp_data), .done_error(clamp_error), .controller_bytes(clamp_control)
    );
    wire norm_ready, norm_valid, norm_cmd_valid, norm_result_ready;
    wire norm_source_valid, norm_source_rsp_ready;
    wire [31:0] norm_source_index;
    wire norm_output_valid, norm_output_last;
    wire [31:0] norm_output_index;
    wire [15:0] norm_output_data;
    wire [63:0] norm_addr, norm_control;
    wire [3:0] norm_error;
    wire norm_beat_good = received < 1024 && norm_output_index == received &&
        norm_output_last == (received == 1023);
    wire norm_emit = rst_n && state == NORM_WAIT &&
        !receive_bad && norm_beat_good && error_hold == 0 && first_source_error == 0;
    wire norm_accept = rst_n && state == NORM_WAIT && (norm_emit ? output_ready : 1'b1);
    anvil_en1_native_norm final_norm (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == NORM_START), .start_ready(norm_ready),
        .model(model_hold), .precision(precision_hold), .image_class(2'd2),
        .tensor_kind(16'h2115), .tensor_layer({8'd0, layer_hold}),
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
        .output_valid(norm_output_valid), .output_ready(norm_accept),
        .output_index(norm_output_index), .output_data(norm_output_data),
        .output_last(norm_output_last), .done_valid(norm_valid),
        .done_ready(rst_n && state == NORM_WAIT && source_state == S_IDLE && !norm_output_valid),
        .done_error(norm_error), .controller_bytes(norm_control)
    );

    wire attention_beat_good = received < 1024 && attention_output_index == received &&
        attention_output_last == (received == 1023);
    wire rebuild_beat_good = rebuilt < 1024 && attention_output_index == rebuilt &&
        attention_output_last == (rebuilt == 1023);
    wire conv_beat_good = received < 1024 && conv_output_index == received &&
        conv_output_last == (received == 1023);
    wire ff_beat_good = received < 1024 && ff_output_index == received &&
        ff_output_last == (received == 1023);
    wire callback_valid = state == CONV_WAIT ? conv_source_valid :
        (state == FF_WAIT ? ff_source_valid : norm_source_valid);
    wire callback_rsp_ready = state == CONV_WAIT ? conv_source_rsp_ready :
        (state == FF_WAIT ? ff_source_rsp_ready : norm_source_rsp_ready);
    wire [31:0] callback_index = state == CONV_WAIT ? conv_source_index :
        (state == FF_WAIT ? ff_source_index : norm_source_index);
    wire callback_tag_bad = state == CONV_WAIT ?
        (conv_source_model != model_hold || conv_source_layer != layer_hold ||
         conv_source_generation != generation_hold) :
        (state == FF_WAIT &&
         (ff_source_model != model_hold || ff_source_mode != 2 ||
          ff_source_layer != layer_hold || ff_source_generation != generation_hold ||
          ff_source_token != token_hold));
    wire historical_source_legal = source_model_hold == model_hold &&
        source_layer_hold == layer_hold && source_generation_hold == generation_hold &&
        source_token_hold < tokens_hold && source_token_hold <= token_hold;

    always @(posedge clk) begin
        if (rst_n && state == ATTENTION_WAIT && attention_output_valid &&
            !receive_bad && attention_beat_good)
            query_bank[attention_output_index[9:0]] <= attention_output_data;
        if (rst_n && state == CONV_WAIT && source_state == REBUILD_WAIT &&
            attention_output_valid && !rebuild_bad && rebuild_beat_good)
            cache_bank[attention_output_index[9:0]] <= attention_output_data;
        if (rst_n && state == CONV_WAIT && conv_output_valid &&
            !receive_bad && conv_beat_good)
            working_bank[conv_output_index[9:0]] <= conv_output_data;
        if (rst_n && state == CLAMP_STORE)
            query_bank[clamp_index[9:0]] <= clamped_hold;
        if (rst_n && source_state == S_READ) begin
            if (source_bank == 0)
                query_q <= query_bank[source_index_hold[9:0]];
            else if (source_bank == 1)
                cache_q <= cache_bank[source_index_hold[9:0]];
            else
                working_q <= working_bank[source_index_hold[9:0]];
        end
    end
    assign start_ready = rst_n && state == IDLE;
    assign source_valid = attention_selected && attention_source_valid;
    assign source_rsp_ready = attention_selected && attention_source_rsp_ready;
    assign source_model = attention_selected ? attention_source_model : 2'd0;
    assign source_layer = attention_selected ? attention_source_layer : 8'd0;
    assign source_generation = attention_selected ? attention_source_generation : 32'd0;
    assign source_token = attention_selected ? attention_source_token : 32'd0;
    assign source_index = attention_selected ? attention_source_index : 32'd0;
    assign cmd_valid = attention_selected ? attention_cmd_valid :
        (conv_selected ? conv_cmd_valid : (ff_selected ? ff_cmd_valid :
        (norm_selected && norm_cmd_valid)));
    assign cmd_write = 0;
    assign cmd_addr = attention_selected ? attention_addr :
        (conv_selected ? conv_addr : (ff_selected ? ff_addr :
        (norm_selected ? norm_addr : 64'd0)));
    assign cmd_wdata = 0;
    assign result_ready = attention_selected ? attention_result_ready :
        (conv_selected ? conv_result_ready : (ff_selected ? ff_result_ready :
        (norm_selected && norm_result_ready)));
    assign output_valid = norm_emit && norm_output_valid;
    assign output_index = rst_n ? norm_output_index : 32'd0;
    assign output_data = rst_n ? norm_output_data : 16'd0;
    assign output_last = output_valid && norm_output_last;
    assign done_valid = rst_n && state == RESPONSE;
    assign done_error = rst_n ? error_hold : 4'd0;
    assign projection_event = attention_projection_event || conv_projection_event;
    assign projection_bytes = attention_projection_bytes + conv_projection_bytes;
    assign intermediate_event = attention_intermediate_event || ff_intermediate_event;
    assign intermediate_bytes = attention_intermediate_bytes + ff_intermediate_bytes;
    assign attention_replay_event = rst_n && state == CONV_WAIT &&
        source_state == REBUILD_START && attention_ready;
    assign attention_replay_bytes = attention_replay_event ? 32'd2048 : 32'd0;
    assign vector_live_bytes = !rst_n ? 64'd0 :
        (query_allocated ? 64'd2048 : 64'd0) + (cache_allocated ? 64'd2048 : 64'd0) +
        (working_allocated ? 64'd2048 : 64'd0) + attention_live + conv_live + ff_live;
    assign vector_physical_bytes = rst_n ?
        64'd6144 + attention_physical + conv_physical + ff_physical : 64'd0;
    assign nested_controller_bytes = !rst_n ? 64'd0 :
        attention_control + attention_pre_control + attention_head_control +
        attention_projection_control + attention_projection_clamp_control +
        attention_norm_control + attention_clamp_control +
        conv_control + conv_nested_control + ff_control + ff_norm_control +
        ff_clamp_control + ff_mlp_control + ff_down_control + ff_down_clamp_control +
        ff_inner_control + ff_inner_clamp_control + clamp_control + norm_control;
    localparam integer CONTROLLER_BITS =
        $bits(state) + $bits(source_state) + $bits(model_hold) + $bits(precision_hold) +
        $bits(source_model_hold) + $bits(source_bank) + $bits(layer_hold) +
        $bits(source_layer_hold) + $bits(generation_hold) + $bits(frames_hold) +
        $bits(tokens_hold) + $bits(token_hold) + $bits(received) + $bits(rebuilt) +
        $bits(source_generation_hold) + $bits(source_token_hold) + $bits(source_index_hold) +
        $bits(cache_token) + $bits(clamp_index) + $bits(audio_hold) + $bits(weights_hold) +
        $bits(query_allocated) + $bits(cache_allocated) + $bits(working_allocated) +
        $bits(query_visible) + $bits(cache_visible) + $bits(working_visible) +
        $bits(receive_bad) + $bits(rebuild_bad) + $bits(source_tag_bad) +
        $bits(query_q) + $bits(cache_q) + $bits(working_q) + $bits(source_data_hold) +
        $bits(clamp_input) + $bits(clamped_hold) + $bits(error_hold) +
        $bits(child_error_hold) + $bits(source_error_hold) + $bits(first_source_error);
    assign controller_bytes = rst_n ? (CONTROLLER_BITS + 7) >> 3 : 64'd0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            source_state <= S_IDLE;
            source_model_hold <= 0;
            source_layer_hold <= 0;
            source_generation_hold <= 0;
            source_token_hold <= 0;
            source_index_hold <= 0;
            source_bank <= 0;
            source_tag_bad <= 0;
            source_data_hold <= 0;
            source_error_hold <= 0;
            first_source_error <= 0;
        end else begin
            if (state == IDLE && start_valid && start_ready)
                first_source_error <= 0;
            case (source_state)
                S_IDLE: if ((state == CONV_WAIT || state == FF_WAIT || state == NORM_WAIT) &&
                    callback_valid) begin
                    source_model_hold <= state == CONV_WAIT ? conv_source_model : model_hold;
                    source_layer_hold <= state == CONV_WAIT ? conv_source_layer : layer_hold;
                    source_generation_hold <= state == CONV_WAIT ?
                        conv_source_generation : generation_hold;
                    source_token_hold <= state == CONV_WAIT ? conv_source_token : token_hold;
                    source_index_hold <= callback_index;
                    source_bank <= state == CONV_WAIT ?
                        (conv_source_token == token_hold ? 2'd0 : 2'd1) :
                        (state == FF_WAIT ? 2'd2 : 2'd0);
                    source_tag_bad <= callback_tag_bad;
                    source_data_hold <= 0;
                    source_error_hold <= 0;
                    source_state <= S_VALIDATE;
                end
                S_VALIDATE: begin
                    if (first_source_error != 0 || source_tag_bad ||
                        source_index_hold >= 1024 ||
                        (state == CONV_WAIT && (!historical_source_legal ||
                            token_hold - source_token_hold > 4)) ||
                        (source_bank == 0 && !query_visible) ||
                        (source_bank == 2 && !working_visible)) begin
                        source_error_hold <= first_source_error != 0 ? first_source_error : 4'd7;
                        if (first_source_error == 0)
                            first_source_error <= 7;
                        source_state <= S_RESPONSE;
                    end else if (source_bank == 1 &&
                        (!cache_visible || cache_token != source_token_hold))
                        source_state <= REBUILD_START;
                    else
                        source_state <= S_READ;
                end
                REBUILD_START: if (attention_ready)
                    source_state <= REBUILD_WAIT;
                REBUILD_WAIT: if (attention_valid && !attention_output_valid) begin
                    source_error_hold <= attention_error;
                    source_state <= REBUILD_CHECK;
                end
                REBUILD_CHECK: begin
                    if (source_error_hold != 0 || rebuild_bad || rebuilt != 1024) begin
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
                        source_data_hold <= query_q;
                    else if (source_bank == 1)
                        source_data_hold <= cache_q;
                    else
                        source_data_hold <= working_q;
                    source_state <= S_RESPONSE;
                end
                S_RESPONSE: if (callback_rsp_ready)
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
            model_hold <= 0;
            precision_hold <= 0;
            layer_hold <= 0;
            generation_hold <= 0;
            frames_hold <= 0;
            tokens_hold <= 0;
            token_hold <= 0;
            received <= 0;
            rebuilt <= 0;
            cache_token <= 0;
            clamp_index <= 0;
            audio_hold <= 0;
            weights_hold <= 0;
            query_allocated <= 0;
            cache_allocated <= 0;
            working_allocated <= 0;
            query_visible <= 0;
            cache_visible <= 0;
            working_visible <= 0;
            receive_bad <= 0;
            rebuild_bad <= 0;
            clamp_input <= 0;
            clamped_hold <= 0;
            error_hold <= 0;
            child_error_hold <= 0;
        end else begin
            if (state == CONV_WAIT && source_state == S_VALIDATE && source_bank == 1 &&
                first_source_error == 0 && !source_tag_bad && source_index_hold < 1024 &&
                historical_source_legal && token_hold - source_token_hold <= 4 &&
                (!cache_visible || cache_token != source_token_hold)) begin
                cache_visible <= 0;
                cache_allocated <= 1;
            end
            if (attention_replay_event) begin
                rebuilt <= 0;
                rebuild_bad <= 0;
                cache_token <= source_token_hold;
            end
            if (state == CONV_WAIT && source_state == REBUILD_WAIT && attention_output_valid) begin
                if (!rebuild_beat_good)
                    rebuild_bad <= 1;
                if (rebuilt < 1024)
                    rebuilt <= rebuilt + 1'b1;
            end
            if (state == CONV_WAIT && source_state == REBUILD_CHECK &&
                source_error_hold == 0 && !rebuild_bad && rebuilt == 1024)
                cache_visible <= 1;
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
                    received <= 0;
                    rebuilt <= 0;
                    receive_bad <= 0;
                    rebuild_bad <= 0;
                    query_allocated <= 1;
                    query_visible <= 0;
                    cache_allocated <= 0;
                    cache_visible <= 0;
                    working_allocated <= 0;
                    working_visible <= 0;
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
                    end else
                        state <= ATTENTION_START;
                end
                ATTENTION_START: if (attention_ready)
                    state <= ATTENTION_WAIT;
                ATTENTION_WAIT: begin
                    if (attention_output_valid) begin
                        if (!attention_beat_good)
                            receive_bad <= 1;
                        if (received < 1024)
                            received <= received + 1'b1;
                    end else if (attention_valid) begin
                        child_error_hold <= attention_error;
                        state <= ATTENTION_CHECK;
                    end
                end
                ATTENTION_CHECK: begin
                    if (child_error_hold != 0 || receive_bad || received != 1024) begin
                        error_hold <= child_error_hold != 0 ? child_error_hold : 4'd7;
                        state <= PUBLISH;
                    end else begin
                        query_visible <= 1;
                        working_allocated <= 1;
                        state <= CONV_START;
                    end
                end
                CONV_START: if (conv_ready) begin
                    received <= 0;
                    receive_bad <= 0;
                    state <= CONV_WAIT;
                end
                CONV_WAIT: begin
                    if (conv_output_valid) begin
                        if (!conv_beat_good)
                            receive_bad <= 1;
                        if (received < 1024)
                            received <= received + 1'b1;
                    end else if (conv_valid && source_state == S_IDLE) begin
                        child_error_hold <= conv_error;
                        state <= CONV_CHECK;
                    end
                end
                CONV_CHECK: begin
                    if (first_source_error != 0 || child_error_hold != 0 ||
                        receive_bad || received != 1024) begin
                        error_hold <= first_source_error != 0 ? first_source_error :
                            (child_error_hold != 0 ? child_error_hold : 4'd7);
                        state <= PUBLISH;
                    end else begin
                        working_visible <= 1;
                        query_visible <= 0;
                        cache_visible <= 0;
                        cache_allocated <= 0;
                        state <= FF_START;
                    end
                end
                FF_START: if (ff_ready) begin
                    received <= 0;
                    receive_bad <= 0;
                    state <= FF_WAIT;
                end
                FF_WAIT: begin
                    if (ff_output_valid) begin
                        if (!ff_beat_good)
                            receive_bad <= 1;
                        if (received < 1024)
                            received <= received + 1'b1;
                        if (ff_beat_good && !receive_bad && error_hold == 0) begin
                            clamp_index <= ff_output_index;
                            clamp_input <= ff_output_data;
                            state <= CLAMP_START;
                        end
                    end else if (ff_valid && source_state == S_IDLE) begin
                        child_error_hold <= ff_error;
                        state <= FF_CHECK;
                    end
                end
                CLAMP_START: if (clamp_ready)
                    state <= CLAMP_WAIT;
                CLAMP_WAIT: if (clamp_valid) begin
                    if (clamp_error != 0) begin
                        if (error_hold == 0)
                            error_hold <= clamp_error;
                        state <= FF_WAIT;
                    end else begin
                        clamped_hold <= clamp_data;
                        state <= CLAMP_STORE;
                    end
                end
                CLAMP_STORE: state <= FF_WAIT;
                FF_CHECK: begin
                    if (first_source_error != 0 || child_error_hold != 0 ||
                        error_hold != 0 || receive_bad || received != 1024) begin
                        if (error_hold == 0)
                            error_hold <= first_source_error != 0 ? first_source_error :
                                (child_error_hold != 0 ? child_error_hold : 4'd7);
                        state <= PUBLISH;
                    end else begin
                        query_visible <= 1;
                        working_visible <= 0;
                        working_allocated <= 0;
                        state <= NORM_START;
                    end
                end
                NORM_START: if (norm_ready) begin
                    received <= 0;
                    receive_bad <= 0;
                    state <= NORM_WAIT;
                end
                NORM_WAIT: begin
                    if (norm_output_valid && norm_accept) begin
                        if (!norm_beat_good)
                            receive_bad <= 1;
                        if (received < 1024)
                            received <= received + 1'b1;
                    end else if (norm_valid && source_state == S_IDLE && !norm_output_valid) begin
                        child_error_hold <= norm_error;
                        state <= NORM_CHECK;
                    end
                end
                NORM_CHECK: begin
                    if (first_source_error != 0 || child_error_hold != 0 ||
                        receive_bad || received != 1024)
                        error_hold <= first_source_error != 0 ? first_source_error :
                            (child_error_hold != 0 ? child_error_hold : 4'd7);
                    state <= PUBLISH;
                end
                PUBLISH: state <= RESPONSE;
                RESPONSE: if (done_ready) begin
                    query_visible <= 0;
                    cache_visible <= 0;
                    working_visible <= 0;
                    query_allocated <= 0;
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
