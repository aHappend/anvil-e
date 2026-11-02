module anvil_en1_replay_input #(
    parameter integer COMPACT = 0
) (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] model, precision, modality,
    input wire [31:0] tokens, token,
    input wire [7:0] frame_layer,
    input wire [5:0] frame_slot,
    input wire [63:0] tokens_base, weights_base,
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
    output wire done_bank,
    output wire [63:0] embedding_live_bytes, embedding_physical_bytes,
    output wire [63:0] controller_state_bytes,
    output wire busy
);
    localparam [3:0] IDLE = 0, VALIDATE = 1, TOKEN_ADDRESS = 2,
        TOKEN_SEND = 3, TOKEN_WAIT = 4, TOKEN_REGISTER = 5,
        EMBED_START = 6, STORE_SEND = 7, INPUT_LOW = 8,
        INPUT_HIGH = 9, WRITE_SEND = 10, STORE_WAIT = 11,
        EMBED_WAIT = 12, PUBLISH = 13, RESPONSE = 14, ABORT_SEND = 15;
    localparam integer MAX_H = COMPACT ? 8 : 2560;
    localparam integer P = COMPACT ? 4 : 256;
    reg [3:0] state;
    reg [1:0] model_hold, precision_hold, modality_hold, selected_modality;
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
    wire embed_ready, embed_valid, embed_input_valid;
    wire [3:0] embed_error;
    wire [31:0] embed_input_index;
    wire [15:0] embed_input_data;
    wire embed_input_last;
    wire embed_cmd_valid, embed_result_ready;
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
        .modality_valid(modality_valid), .modality_ready(modality_ready),
        .modality_model(modality_model), .modality_kind(modality_kind),
        .modality_token(modality_token), .modality_index(modality_index),
        .modality_rsp_valid(modality_rsp_valid),
        .modality_rsp_ready(modality_rsp_ready),
        .modality_rsp_data(modality_rsp_data),
        .modality_rsp_error(modality_rsp_error),
        .input_valid(embed_input_valid), .input_ready(embed_input_ready),
        .input_index(embed_input_index), .input_data(embed_input_data),
        .input_last(embed_input_last),
        .ple_valid(), .ple_ready(rst_n && embed_active),
        .ple_index(), .ple_data(), .ple_last(),
        .cmd_valid(embed_cmd_valid),
        .cmd_ready(rst_n && embed_active && cmd_ready),
        .cmd_write(), .cmd_addr(embed_cmd_addr), .cmd_wdata(),
        .result_valid(rst_n && embed_active && result_valid),
        .result_ready(embed_result_ready),
        .result_data(result_data), .result_error(result_error),
        .done_valid(embed_valid),
        .done_ready(rst_n && state == EMBED_WAIT),
        .done_error(embed_error)
    );

    assign start_ready = rst_n && state == IDLE;
    assign work_req_valid = rst_n && state == STORE_SEND;
    assign work_req_op = rst_n ? 3'd3 : 3'd0;
    assign work_req_domain = 0;
    assign work_req_target = 0;
    assign work_req_token = rst_n ? token_hold : 32'd0;
    assign work_req_layer = rst_n ? layer_hold : 8'd0;
    assign work_req_length = rst_n ? hidden_hold : 12'd0;
    assign work_req_component = 0;
    assign work_req_slot = rst_n ? slot_hold : 6'd0;
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
    assign work_rsp_ready = rst_n && store_open;
    assign cmd_valid = rst_n &&
        (state == TOKEN_SEND || (embed_active && embed_cmd_valid));
    assign cmd_write = 0;
    assign cmd_addr = !rst_n ? 64'd0 :
        (embed_active ? embed_cmd_addr : token_address_hold);
    assign cmd_wdata = 0;
    assign result_ready = rst_n &&
        (state == TOKEN_WAIT || (embed_active && embed_result_ready));
    assign done_valid = rst_n && state == RESPONSE;
    assign done_error = rst_n ? error_hold : 4'd0;
    assign done_bank = 0;
    assign embedding_live_bytes = rst_n && embed_active ?
        ({52'd0, hidden_hold} + 64'(P)) << 1 : 64'd0;
    assign embedding_physical_bytes = rst_n ? 64'(2*(MAX_H+P)) : 64'd0;
    assign controller_state_bytes = rst_n ? 64'd56 : 64'd0;
    assign busy = rst_n && state != IDLE;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            model_hold <= 0;
            precision_hold <= 0;
            modality_hold <= 0;
            selected_modality <= 0;
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
                        state <= EMBED_START;
                    end
                end
                EMBED_START: if (embed_ready) begin
                    embed_active <= 1;
                    state <= STORE_SEND;
                end
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
            if (work_rsp_valid && work_rsp_ready) begin
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
