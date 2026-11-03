module anvil_en1_native_token_map #(
    parameter integer COMPACT = 0
) (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] model, modality, kind,
    input wire [31:0] generation, tokens, token, audio_frames,
    input wire [63:0] tokens_base, audio_base,
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
    output wire [31:0] done_ordinal, done_count, done_native_token,
    output wire [3:0] done_error,
    output wire input_read_event,
    output wire [31:0] input_read_bytes,
    output wire [63:0] controller_bytes, nested_controller_bytes
);
    localparam [4:0] IDLE = 0, VALIDATE = 1, TOKEN_ADDRESS = 2,
        TOKEN_SEND = 3, TOKEN_WAIT = 4, TOKEN_CHECK = 5,
        TOKEN_ADVANCE = 6, TOKEN_FINISH = 7, MASK_START = 8,
        MASK_WAIT = 9, MASK_CHECK = 10, MASK_ADVANCE = 11,
        MASK_FINISH = 12, PUBLISH = 13, RESPONSE = 14;
    reg [4:0] state;
    reg [1:0] model_hold, modality_hold, kind_hold;
    reg [31:0] generation_hold, tokens_hold, token_hold, frames_hold;
    reg [63:0] tokens_base_hold, audio_base_hold, token_address_hold;
    reg [31:0] cursor, token_word, ordinal_hold, count_hold;
    reg [31:0] audio_tokens_hold, audio_cursor, valid_count, selected_token, mask_word;
    reg target_found, native_found, memory_error_hold;
    reg [3:0] mask_error_hold, error_hold;
    initial begin
        if (COMPACT != 0 && COMPACT != 1)
            $fatal(1, "PARAMETER ERROR: COMPACT must be 0 or 1");
    end
    wire image_allowed = modality_hold == 1 || modality_hold == 3;
    wire audio_allowed = modality_hold == 2 || modality_hold == 3;
    wire image_placeholder = token_word == (COMPACT ? 32'd28 : 32'd258880);
    wire audio_placeholder = token_word == (COMPACT ? 32'd29 : 32'd258881);
    wire selected_placeholder = kind_hold == 1 ? image_placeholder : audio_placeholder;
    wire [64:0] stream_end = {1'b0, tokens_base_hold} + {31'd0, tokens_hold, 2'd0};
    wire [64:0] token_sum = {1'b0, tokens_base_hold} + {31'd0, cursor, 2'd0};
    wire [64:0] token_end = token_sum + 65'd4;
    wire mask_selected = rst_n &&
        (state == MASK_START || state == MASK_WAIT || state == MASK_CHECK);
    wire mask_ready, mask_valid, mask_cmd_valid, mask_result_ready;
    wire [63:0] mask_addr;
    wire [31:0] mask_data;
    wire [3:0] mask_error;
    anvil_en1_audio_input immutable_mask (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == MASK_START), .start_ready(mask_ready),
        .model(model_hold), .kind(2'd1), .generation(generation_hold),
        .frames(frames_hold), .frame({audio_cursor[29:0], 2'd0}), .frequency(32'd0),
        .audio_base(audio_base_hold),
        .cmd_valid(mask_cmd_valid), .cmd_ready(mask_selected && cmd_ready),
        .cmd_write(), .cmd_addr(mask_addr), .cmd_wdata(),
        .result_valid(mask_selected && result_valid), .result_ready(mask_result_ready),
        .result_data(result_data), .result_error(result_error),
        .done_valid(mask_valid), .done_ready(rst_n && state == MASK_WAIT),
        .done_data(mask_data), .done_error(mask_error),
        .input_read_event(), .input_read_bytes(),
        .controller_bytes(nested_controller_bytes)
    );
    assign start_ready = rst_n && state == IDLE;
    assign cmd_valid = rst_n && (state == TOKEN_SEND || (mask_selected && mask_cmd_valid));
    assign cmd_write = 0;
    assign cmd_addr = !rst_n ? 64'd0 : (mask_selected ? mask_addr : token_address_hold);
    assign cmd_wdata = 0;
    assign result_ready = rst_n && (state == TOKEN_WAIT || (mask_selected && mask_result_ready));
    assign done_valid = rst_n && state == RESPONSE;
    assign done_ordinal = rst_n ? ordinal_hold : 32'd0;
    assign done_count = rst_n ? count_hold : 32'd0;
    assign done_native_token = rst_n ? selected_token : 32'd0;
    assign done_error = rst_n ? error_hold : 4'd0;
    assign input_read_event = cmd_valid && cmd_ready;
    assign input_read_bytes = input_read_event ? 32'd4 : 32'd0;
    wire [31:0] CONTROLLER_BITS =
        $bits(state) + $bits(model_hold) + $bits(modality_hold) + $bits(kind_hold) +
        $bits(generation_hold) + $bits(tokens_hold) + $bits(token_hold) + $bits(frames_hold) +
        $bits(tokens_base_hold) + $bits(audio_base_hold) + $bits(token_address_hold) +
        $bits(cursor) + $bits(token_word) + $bits(ordinal_hold) + $bits(count_hold) +
        $bits(audio_tokens_hold) + $bits(audio_cursor) + $bits(valid_count) +
        $bits(selected_token) + $bits(mask_word) + $bits(target_found) + $bits(native_found) +
        $bits(memory_error_hold) + $bits(mask_error_hold) + $bits(error_hold);
    assign controller_bytes = rst_n ? (CONTROLLER_BITS + 7) >> 3 : 64'd0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            model_hold <= 0;
            modality_hold <= 0;
            kind_hold <= 0;
            generation_hold <= 0;
            tokens_hold <= 0;
            token_hold <= 0;
            frames_hold <= 0;
            tokens_base_hold <= 0;
            audio_base_hold <= 0;
            token_address_hold <= 0;
            cursor <= 0;
            token_word <= 0;
            ordinal_hold <= 0;
            count_hold <= 0;
            audio_tokens_hold <= 0;
            audio_cursor <= 0;
            valid_count <= 0;
            selected_token <= 0;
            mask_word <= 0;
            target_found <= 0;
            native_found <= 0;
            memory_error_hold <= 0;
            mask_error_hold <= 0;
            error_hold <= 0;
        end else begin
            case (state)
                IDLE: if (start_valid && start_ready) begin
                    model_hold <= model;
                    modality_hold <= modality;
                    kind_hold <= kind;
                    generation_hold <= generation;
                    tokens_hold <= tokens;
                    token_hold <= token;
                    frames_hold <= audio_frames;
                    tokens_base_hold <= tokens_base;
                    audio_base_hold <= audio_base;
                    cursor <= 0;
                    ordinal_hold <= 0;
                    count_hold <= 0;
                    audio_tokens_hold <= (audio_frames + 32'd3) >> 2;
                    audio_cursor <= 0;
                    valid_count <= 0;
                    selected_token <= 0;
                    target_found <= 0;
                    native_found <= 0;
                    memory_error_hold <= 0;
                    mask_error_hold <= 0;
                    error_hold <= 0;
                    state <= VALIDATE;
                end
                VALIDATE: begin
                    if (model_hold != 1 && model_hold != 2) begin
                        error_hold <= 6;
                        state <= PUBLISH;
                    end else if (generation_hold == 0 || tokens_hold == 0 ||
                        tokens_hold > 131072 || token_hold >= tokens_hold ||
                        tokens_base_hold[1:0] != 0 || stream_end[64] ||
                        (kind_hold != 1 && kind_hold != 2) ||
                        (kind_hold == 1 && !image_allowed) ||
                        (kind_hold == 2 && (!audio_allowed || frames_hold == 0 ||
                            frames_hold > 131072 || audio_base_hold[1:0] != 0))) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else
                        state <= TOKEN_ADDRESS;
                end
                TOKEN_ADDRESS: begin
                    if (token_sum[64] || token_end[64] || token_end > stream_end) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else begin
                        token_address_hold <= token_sum[63:0];
                        state <= TOKEN_SEND;
                    end
                end
                TOKEN_SEND: if (cmd_ready)
                    state <= TOKEN_WAIT;
                TOKEN_WAIT: if (result_valid) begin
                    token_word <= result_data;
                    memory_error_hold <= result_error;
                    state <= TOKEN_CHECK;
                end
                TOKEN_CHECK: begin
                    if (memory_error_hold) begin
                        error_hold <= 2;
                        state <= PUBLISH;
                    end else if (token_word >= (COMPACT ? 32'd32 : 32'd262144) ||
                        (image_placeholder && !image_allowed) ||
                        (audio_placeholder && !audio_allowed)) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else if (cursor == token_hold && !selected_placeholder) begin
                        error_hold <= 7;
                        state <= PUBLISH;
                    end else begin
                        if (selected_placeholder) begin
                            if (cursor == token_hold) begin
                                ordinal_hold <= count_hold;
                                target_found <= 1;
                            end
                            count_hold <= count_hold + 1'b1;
                        end
                        state <= TOKEN_ADVANCE;
                    end
                end
                TOKEN_ADVANCE: begin
                    if (cursor + 1'b1 == tokens_hold)
                        state <= TOKEN_FINISH;
                    else begin
                        cursor <= cursor + 1'b1;
                        state <= TOKEN_ADDRESS;
                    end
                end
                TOKEN_FINISH: begin
                    if (!target_found || count_hold == 0 || ordinal_hold >= count_hold) begin
                        error_hold <= 7;
                        state <= PUBLISH;
                    end else if (kind_hold == 1) begin
                        selected_token <= ordinal_hold;
                        state <= PUBLISH;
                    end else
                        state <= MASK_START;
                end
                MASK_START: if (mask_ready)
                    state <= MASK_WAIT;
                MASK_WAIT: if (mask_valid) begin
                    mask_word <= mask_data;
                    mask_error_hold <= mask_error;
                    state <= MASK_CHECK;
                end
                MASK_CHECK: begin
                    if (mask_error_hold != 0) begin
                        error_hold <= mask_error_hold;
                        state <= PUBLISH;
                    end else if (mask_word > 1) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else begin
                        if (mask_word == 1) begin
                            if (valid_count == ordinal_hold) begin
                                selected_token <= audio_cursor;
                                native_found <= 1;
                            end
                            valid_count <= valid_count + 1'b1;
                        end
                        state <= MASK_ADVANCE;
                    end
                end
                MASK_ADVANCE: begin
                    if (audio_cursor + 1'b1 == audio_tokens_hold)
                        state <= MASK_FINISH;
                    else begin
                        audio_cursor <= audio_cursor + 1'b1;
                        state <= MASK_START;
                    end
                end
                MASK_FINISH: begin
                    if (!native_found || valid_count != count_hold)
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
