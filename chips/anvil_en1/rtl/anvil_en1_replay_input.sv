module anvil_en1_replay_input #(
    parameter integer COMPACT = 0
) (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] model, precision, modality, mode,
    input wire [31:0] tokens, token,
    input wire [7:0] frame_layer,
    input wire [5:0] frame_slot,
    input wire [63:0] tokens_base, weights_base,
    input wire [159:0] continuation,
    input wire dependency_valid,
    input wire [1:0] dependency_domain,
    input wire [7:0] dependency_layer,
    input wire [31:0] dependency_token,
    input wire [11:0] dependency_length,
    input wire [5:0] dependency_slot,
    output wire modality_valid,
    input wire modality_ready,
    output wire [1:0] modality_model, modality_kind,
    output wire [31:0] modality_token, modality_index,
    input wire modality_rsp_valid,
    output wire modality_rsp_ready,
    input wire [15:0] modality_rsp_data,
    input wire modality_rsp_error,
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
    output wire work_write_valid,
    input wire work_write_ready,
    output wire [31:0] work_write_data,
    output wire work_write_first, work_write_last, work_write_abort,
    input wire work_rsp_valid,
    output wire work_rsp_ready,
    input wire [3:0] work_rsp_error,
    input wire [31:0] work_rsp_data,
    output wire cmd_valid,
    input wire cmd_ready,
    output wire cmd_write,
    output wire input_read_event,
    output wire [63:0] cmd_addr,
    output wire [31:0] cmd_wdata,
    input wire result_valid,
    output wire result_ready,
    input wire [31:0] result_data,
    input wire result_error,
    output wire done_valid,
    input wire done_ready,
    output wire [3:0] done_error,
    output wire done_bank,
    output wire done_yield,
    output wire [159:0] done_continuation,
    output wire [1:0] done_dependency_domain,
    output wire [7:0] done_dependency_layer,
    output wire [31:0] done_dependency_token,
    output wire [11:0] done_dependency_length,
    output wire [63:0] embedding_live_bytes, embedding_physical_bytes,
    output wire [63:0] controller_state_bytes,
    output wire busy
);
    localparam [4:0] IDLE = 0, VALIDATE = 1, TOKEN_ADDRESS = 2,
        TOKEN_SEND = 3, TOKEN_WAIT = 4, TOKEN_REGISTER = 5,
        EMBED_START = 6, STORE_SEND = 7, INPUT_LOW = 8,
        INPUT_HIGH = 9, WRITE_SEND = 10, STORE_WAIT = 11,
        EMBED_WAIT = 12, PUBLISH = 13, RESPONSE = 14, ABORT_SEND = 15,
        MODALITY_BIND = 16, EMBED_PREFILL = 17, FEATURE_VALIDATE = 18,
        FEATURE_SEND = 19, FEATURE_WAIT = 20, FEATURE_REGISTER = 21,
        FEATURE_RESPONSE = 22;
    localparam [159:0] MODALITY_CONTINUATION = {32'h454e314d, 128'd0};
    localparam integer MAX_H = COMPACT ? 8 : 2560;
    localparam integer P = COMPACT ? 4 : 256;
    reg [4:0] state;
    reg [1:0] model_hold, precision_hold, modality_hold, selected_modality, mode_hold;
    reg [159:0] continuation_hold;
    reg dependency_valid_hold, yield_hold, feature_error_hold;
    reg [1:0] dependency_domain_hold;
    reg [7:0] dependency_layer_hold;
    reg [31:0] dependency_token_hold, feature_index_hold, feature_pair_hold;
    reg [11:0] dependency_length_hold;
    reg [5:0] dependency_slot_hold;
    reg [15:0] feature_data_hold;
    reg [3:0] feature_work_error;
    reg [31:0] tokens_hold, token_hold, token_id_hold, input_count, pair_index;
    reg [11:0] hidden_hold;
    reg [7:0] layer_hold;
    reg [5:0] slot_hold;
    reg [63:0] tokens_base_hold, weights_base_hold, token_address_hold;
    reg [15:0] low_hold;
    reg [31:0] pair_hold;
    reg [3:0] error_hold;
    reg token_error_hold, embed_active, store_open;

    initial begin
        if (COMPACT != 0 && COMPACT != 1)
            $fatal(1, "PARAMETER ERROR: COMPACT must be 0 or 1");
    end

    wire native_model = model_hold == 1 || model_hold == 2;
    wire [11:0] selected_hidden = COMPACT ? 12'd8 :
        (model_hold == 1 ? 12'd1536 : 12'd2560);
    wire [64:0] token_address_sum = {1'b0, tokens_base_hold} +
        {31'd0, token_hold, 2'd0};
    wire [64:0] token_address_end = token_address_sum + 65'd3;
    wire image_token = token_id_hold == (COMPACT ? 32'd28 : 32'd258880);
    wire audio_token = token_id_hold == (COMPACT ? 32'd29 : 32'd258881);
    wire image_allowed = modality_hold == 1 || modality_hold == 3;
    wire audio_allowed = modality_hold == 2 || modality_hold == 3;
    wire native_feature = selected_modality == 1 || selected_modality == 2;
    wire feature_tag_good = dependency_valid_hold && dependency_domain_hold == 3 &&
        dependency_layer_hold == {6'd0, selected_modality} && dependency_token_hold == token_hold &&
        dependency_length_hold == hidden_hold && dependency_slot_hold < 16;
    wire embed_modality_valid, embed_modality_rsp_ready;
    wire [1:0] embed_modality_model, embed_modality_kind;
    wire [31:0] embed_modality_token, embed_modality_index;
    wire feature_callback_good = embed_modality_model == model_hold &&
        embed_modality_kind == selected_modality && embed_modality_token == token_hold &&
        embed_modality_index < {20'd0, hidden_hold};
    wire embed_ready, embed_valid, embed_input_valid;
    wire [3:0] embed_error;
    wire [31:0] embed_input_index;
    wire [15:0] embed_input_data;
    wire embed_input_last;
    wire embed_cmd_valid, embed_result_ready, embed_input_event;
    wire [63:0] embed_cmd_addr;
    wire premature_failure = embed_valid && embed_error != 0;
    wire stream_position = state == INPUT_LOW || state == INPUT_HIGH;
    wire draining_input = state == ABORT_SEND || state == STORE_WAIT ||
        state == EMBED_WAIT;
    wire embed_input_ready = rst_n && embed_active &&
        ((stream_position && !work_rsp_valid) || draining_input);
    wire input_beat_valid = embed_input_index == input_count &&
        input_count < {20'd0, hidden_hold} &&
        embed_input_last == (input_count + 1'b1 == {20'd0, hidden_hold});

    anvil_en1_embedding_ple #(.COMPACT(COMPACT)) reconstruct (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == EMBED_START), .start_ready(embed_ready),
        .model(model_hold), .precision(precision_hold),
        .modality(selected_modality), .layer(8'd0), .token(token_hold),
        .tokens_base(tokens_base_hold), .weights_base(weights_base_hold),
        .modality_valid(embed_modality_valid),
        .modality_ready(native_feature ? (rst_n && state == EMBED_PREFILL) : modality_ready),
        .modality_model(embed_modality_model), .modality_kind(embed_modality_kind),
        .modality_token(embed_modality_token), .modality_index(embed_modality_index),
        .modality_rsp_valid(native_feature ? (rst_n && state == FEATURE_RESPONSE) : modality_rsp_valid),
        .modality_rsp_ready(embed_modality_rsp_ready),
        .modality_rsp_data(native_feature ? feature_data_hold : modality_rsp_data),
        .modality_rsp_error(native_feature ? feature_error_hold : modality_rsp_error),
        .input_valid(embed_input_valid), .input_ready(embed_input_ready),
        .input_index(embed_input_index), .input_data(embed_input_data),
        .input_last(embed_input_last),
        .ple_valid(), .ple_ready(rst_n && embed_active),
        .ple_index(), .ple_data(), .ple_last(),
        .cmd_valid(embed_cmd_valid),
        .cmd_ready(rst_n && embed_active && cmd_ready),
        .cmd_write(), .cmd_addr(embed_cmd_addr), .cmd_wdata(),
        .input_read_event(embed_input_event),
        .result_valid(rst_n && embed_active && result_valid),
        .result_ready(embed_result_ready),
        .result_data(result_data), .result_error(result_error),
        .done_valid(embed_valid),
        .done_ready(rst_n && state == EMBED_WAIT),
        .done_error(embed_error), .live_payload_bytes(embedding_live_bytes),
        .physical_payload_bytes(embedding_physical_bytes)
    );

    assign start_ready = rst_n && state == IDLE;
    assign modality_valid = rst_n && !native_feature && embed_modality_valid;
    assign modality_model = rst_n ? embed_modality_model : 2'd0;
    assign modality_kind = rst_n ? embed_modality_kind : 2'd0;
    assign modality_token = rst_n ? embed_modality_token : 32'd0;
    assign modality_index = rst_n ? embed_modality_index : 32'd0;
    assign modality_rsp_ready = rst_n && !native_feature && embed_modality_rsp_ready;
    assign work_req_valid = rst_n && (state == STORE_SEND || state == FEATURE_SEND);
    assign work_req_op = !rst_n ? 3'd0 : (state == FEATURE_SEND ? 3'd4 : 3'd3);
    assign work_req_domain = rst_n && state == FEATURE_SEND ? 2'd3 : 2'd0;
    assign work_req_target = rst_n && state == FEATURE_SEND ? 2'd1 : 2'd0;
    assign work_req_token = rst_n ? token_hold : 32'd0;
    assign work_req_layer = !rst_n ? 8'd0 :
        (state == FEATURE_SEND ? {6'd0, selected_modality} : layer_hold);
    assign work_req_length = rst_n ? hidden_hold : 12'd0;
    assign work_req_component = rst_n && state == FEATURE_SEND ?
        {feature_index_hold[11:1], 1'b0} : 12'd0;
    assign work_req_slot = !rst_n ? 6'd0 :
        (state == FEATURE_SEND ? dependency_slot_hold : slot_hold);
    assign work_req_bank = 0;
    assign work_req_scalar_index = 0;
    assign work_req_data = 0;
    assign work_write_valid = rst_n &&
        (state == ABORT_SEND || state == WRITE_SEND);
    assign work_write_data = rst_n ? pair_hold : 32'd0;
    assign work_write_first = rst_n && pair_index == 0;
    assign work_write_last = rst_n &&
        pair_index + 1'b1 == {21'd0, hidden_hold[11:1]};
    assign work_write_abort = rst_n && state == ABORT_SEND;
    assign work_rsp_ready = rst_n && (store_open || state == FEATURE_WAIT);
    assign cmd_valid = rst_n &&
        (state == TOKEN_SEND || (embed_active && embed_cmd_valid));
    assign cmd_write = 0;
    assign input_read_event = (rst_n && state == TOKEN_SEND && cmd_ready) ||
        embed_input_event;
    assign cmd_addr = !rst_n ? 64'd0 :
        (embed_active ? embed_cmd_addr : token_address_hold);
    assign cmd_wdata = 0;
    assign result_ready = rst_n &&
        (state == TOKEN_WAIT || (embed_active && embed_result_ready));
    assign done_valid = rst_n && state == RESPONSE;
    assign done_error = rst_n ? error_hold : 4'd0;
    assign done_bank = 0;
    assign done_yield = rst_n && yield_hold && error_hold == 0;
    assign done_continuation = rst_n && yield_hold ? MODALITY_CONTINUATION : 160'd0;
    assign done_dependency_domain = rst_n && yield_hold ? 2'd3 : 2'd0;
    assign done_dependency_layer = rst_n && yield_hold ? {6'd0, selected_modality} : 8'd0;
    assign done_dependency_token = rst_n && yield_hold ? token_hold : 32'd0;
    assign done_dependency_length = rst_n && yield_hold ? hidden_hold : 12'd0;
    localparam integer CONTROLLER_BITS =
        $bits(state) + $bits(model_hold) + $bits(precision_hold) + $bits(modality_hold) +
        $bits(selected_modality) + $bits(mode_hold) + $bits(continuation_hold) +
        $bits(dependency_valid_hold) + $bits(yield_hold) + $bits(feature_error_hold) +
        $bits(dependency_domain_hold) + $bits(dependency_layer_hold) + $bits(dependency_token_hold) +
        $bits(feature_index_hold) + $bits(feature_pair_hold) + $bits(dependency_length_hold) +
        $bits(dependency_slot_hold) + $bits(feature_data_hold) + $bits(feature_work_error) +
        $bits(tokens_hold) + $bits(token_hold) + $bits(token_id_hold) + $bits(input_count) +
        $bits(pair_index) + $bits(hidden_hold) + $bits(layer_hold) + $bits(slot_hold) +
        $bits(tokens_base_hold) + $bits(weights_base_hold) + $bits(token_address_hold) +
        $bits(low_hold) + $bits(pair_hold) + $bits(error_hold) + $bits(token_error_hold) +
        $bits(embed_active) + $bits(store_open);
    assign controller_state_bytes = rst_n ? (CONTROLLER_BITS + 7) >> 3 : 64'd0;
    assign busy = rst_n && state != IDLE;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            model_hold <= 0;
            precision_hold <= 0;
            modality_hold <= 0;
            selected_modality <= 0;
            mode_hold <= 0;
            continuation_hold <= 0;
            dependency_valid_hold <= 0;
            dependency_domain_hold <= 0;
            dependency_layer_hold <= 0;
            dependency_token_hold <= 0;
            dependency_length_hold <= 0;
            dependency_slot_hold <= 0;
            yield_hold <= 0;
            feature_error_hold <= 0;
            feature_index_hold <= 0;
            feature_pair_hold <= 0;
            feature_data_hold <= 0;
            feature_work_error <= 0;
            tokens_hold <= 0;
            token_hold <= 0;
            token_id_hold <= 0;
            input_count <= 0;
            pair_index <= 0;
            hidden_hold <= 0;
            layer_hold <= 0;
            slot_hold <= 0;
            tokens_base_hold <= 0;
            weights_base_hold <= 0;
            token_address_hold <= 0;
            low_hold <= 0;
            pair_hold <= 0;
            error_hold <= 0;
            token_error_hold <= 0;
            embed_active <= 0;
            store_open <= 0;
        end else begin
            case (state)
                IDLE: if (start_valid && start_ready) begin
                    model_hold <= model;
                    precision_hold <= precision;
                    modality_hold <= modality;
                    mode_hold <= mode;
                    continuation_hold <= continuation;
                    dependency_valid_hold <= dependency_valid;
                    dependency_domain_hold <= dependency_domain;
                    dependency_layer_hold <= dependency_layer;
                    dependency_token_hold <= dependency_token;
                    dependency_length_hold <= dependency_length;
                    dependency_slot_hold <= dependency_slot;
                    yield_hold <= 0;
                    feature_error_hold <= 0;
                    feature_data_hold <= 0;
                    feature_work_error <= 0;
                    tokens_hold <= tokens;
                    token_hold <= token;
                    layer_hold <= frame_layer;
                    slot_hold <= frame_slot;
                    tokens_base_hold <= tokens_base;
                    weights_base_hold <= weights_base;
                    selected_modality <= 0;
                    token_id_hold <= 0;
                    input_count <= 0;
                    pair_index <= 0;
                    low_hold <= 0;
                    pair_hold <= 0;
                    error_hold <= 0;
                    token_error_hold <= 0;
                    embed_active <= 0;
                    store_open <= 0;
                    state <= VALIDATE;
                end
                VALIDATE: begin
                    if (!native_model || precision_hold > 1) begin
                        error_hold <= 6;
                        state <= PUBLISH;
                    end else if (tokens_hold == 0 || tokens_hold > 131072 ||
                        token_hold >= tokens_hold || layer_hold != 0 ||
                        tokens_base_hold[1:0] != 0 || weights_base_hold[1:0] != 0) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else begin
                        hidden_hold <= selected_hidden;
                        state <= TOKEN_ADDRESS;
                    end
                end
                TOKEN_ADDRESS: begin
                    if (token_address_sum[64] || token_address_end[64]) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else begin
                        token_address_hold <= token_address_sum[63:0];
                        state <= TOKEN_SEND;
                    end
                end
                TOKEN_SEND: if (cmd_ready)
                    state <= TOKEN_WAIT;
                TOKEN_WAIT: if (result_valid && result_ready) begin
                    token_id_hold <= result_data;
                    token_error_hold <= result_error;
                    state <= TOKEN_REGISTER;
                end
                TOKEN_REGISTER: begin
                    if (token_error_hold) begin
                        error_hold <= 2;
                        state <= PUBLISH;
                    end else if ((image_token && !image_allowed) ||
                        (audio_token && !audio_allowed)) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else begin
                        if (image_token)
                            selected_modality <= 1;
                        else if (audio_token)
                            selected_modality <= 2;
                        else
                            selected_modality <= 0;
                        state <= MODALITY_BIND;
                    end
                end
                MODALITY_BIND: begin
                    if (mode_hold > 1 ||
                        (mode_hold == 0 && (continuation_hold != 0 || dependency_valid_hold)) ||
                        (mode_hold == 1 && (!native_feature ||
                            continuation_hold != MODALITY_CONTINUATION || !feature_tag_good))) begin
                        error_hold <= 7;
                        state <= PUBLISH;
                    end else if (native_feature && !dependency_valid_hold) begin
                        yield_hold <= 1;
                        state <= PUBLISH;
                    end else
                        state <= EMBED_START;
                end
                EMBED_START: if (embed_ready) begin
                    embed_active <= 1;
                    state <= EMBED_PREFILL;
                end
                EMBED_PREFILL: begin
                    if (native_feature && embed_modality_valid) begin
                        feature_index_hold <= embed_modality_index;
                        feature_data_hold <= 0;
                        feature_error_hold <= !feature_callback_good || error_hold != 0;
                        state <= FEATURE_VALIDATE;
                    end else if (embed_valid) begin
                        if (error_hold == 0) begin
                            if (embed_error != 0)
                                error_hold <= embed_error;
                            else
                                error_hold <= 7;
                        end
                        state <= EMBED_WAIT;
                    end else if (embed_input_valid)
                        state <= STORE_SEND;
                end
                FEATURE_VALIDATE: begin
                    if (feature_error_hold || !feature_tag_good) begin
                        feature_error_hold <= 1;
                        if (error_hold == 0)
                            error_hold <= 7;
                        state <= FEATURE_RESPONSE;
                    end else
                        state <= FEATURE_SEND;
                end
                FEATURE_SEND: if (work_req_ready)
                    state <= FEATURE_WAIT;
                FEATURE_WAIT: if (work_rsp_valid) begin
                    feature_pair_hold <= work_rsp_data;
                    feature_work_error <= work_rsp_error;
                    state <= FEATURE_REGISTER;
                end
                FEATURE_REGISTER: begin
                    feature_error_hold <= feature_work_error != 0;
                    if (feature_work_error != 0) begin
                        feature_data_hold <= 0;
                        if (error_hold == 0)
                            error_hold <= feature_work_error;
                    end else
                        feature_data_hold <= feature_index_hold[0] ?
                            feature_pair_hold[31:16] : feature_pair_hold[15:0];
                    state <= FEATURE_RESPONSE;
                end
                FEATURE_RESPONSE: if (embed_modality_rsp_ready)
                    state <= EMBED_PREFILL;
                STORE_SEND: begin
                    if (work_req_valid && work_req_ready) begin
                        store_open <= 1;
                        if (embed_valid) begin
                            if (embed_error != 0)
                                error_hold <= embed_error;
                            else
                                error_hold <= 7;
                            state <= ABORT_SEND;
                        end else
                            state <= INPUT_LOW;
                    end
                end
                INPUT_LOW: begin
                    if (embed_valid) begin
                        if (embed_error != 0)
                            error_hold <= embed_error;
                        else
                            error_hold <= 7;
                        state <= ABORT_SEND;
                    end else if (embed_input_valid && embed_input_ready) begin
                        if (!input_beat_valid) begin
                            error_hold <= 7;
                            state <= ABORT_SEND;
                        end else begin
                            low_hold <= embed_input_data;
                            input_count <= input_count + 1'b1;
                            state <= INPUT_HIGH;
                        end
                    end
                end
                INPUT_HIGH: begin
                    if (embed_valid) begin
                        if (embed_error != 0)
                            error_hold <= embed_error;
                        else
                            error_hold <= 7;
                        state <= ABORT_SEND;
                    end else if (embed_input_valid && embed_input_ready) begin
                        if (!input_beat_valid) begin
                            error_hold <= 7;
                            state <= ABORT_SEND;
                        end else begin
                            pair_hold <= {embed_input_data, low_hold};
                            input_count <= input_count + 1'b1;
                            state <= WRITE_SEND;
                        end
                    end
                end
                WRITE_SEND: begin
                    if (premature_failure)
                        error_hold <= embed_error;
                    if (work_write_valid && work_write_ready) begin
                        if (work_write_last)
                            state <= STORE_WAIT;
                        else if (premature_failure)
                            state <= ABORT_SEND;
                        else begin
                            pair_index <= pair_index + 1'b1;
                            state <= INPUT_LOW;
                        end
                    end
                end
                ABORT_SEND: if (work_write_valid && work_write_ready)
                    state <= STORE_WAIT;
                STORE_WAIT: begin end
                EMBED_WAIT: if (embed_valid) begin
                    embed_active <= 0;
                    if (error_hold == 0 && embed_error != 0)
                        error_hold <= embed_error;
                    state <= PUBLISH;
                end
                PUBLISH: state <= RESPONSE;
                RESPONSE: if (done_ready)
                    state <= IDLE;
                default: begin
                    error_hold <= 7;
                    if (store_open)
                        state <= ABORT_SEND;
                    else if (embed_active)
                        state <= EMBED_WAIT;
                    else
                        state <= PUBLISH;
                end
            endcase
            if (store_open && work_rsp_valid && work_rsp_ready) begin
                store_open <= 0;
                if (error_hold == 0) begin
                    if (embed_valid && embed_error != 0)
                        error_hold <= embed_error;
                    else if (work_rsp_error != 0)
                        error_hold <= work_rsp_error;
                    else if (state != STORE_WAIT)
                        error_hold <= 7;
                end
                state <= EMBED_WAIT;
            end
        end
    end
endmodule
