module anvil_en1_replay_audio_input (
    input wire image_immutable, image_invalidate,
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] model, precision,
    input wire [31:0] generation, frames, token,
    input wire [7:0] frame_layer,
    input wire [5:0] frame_slot,
    input wire [63:0] audio_base, audio_weights_base,
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
    output wire input_read_event, projection_event, point_replay_event,
    output wire [31:0] input_read_bytes, projection_bytes, point_replay_bytes,
    output wire [63:0] vector_live_bytes, vector_physical_bytes,
    output wire [63:0] controller_bytes, nested_controller_bytes
);
    localparam [3:0] IDLE = 0, VALIDATE = 1, CHILD_START = 2,
        CHILD_WAIT = 3, CHILD_CHECK = 4, PAIR_SEND = 5,
        PAIR_WAIT = 6, PAIR_REGISTER = 7, PUBLISH = 8, RESPONSE = 9;
    reg [3:0] state;
    reg [1:0] model_hold, precision_hold;
    reg [31:0] generation_hold, frames_hold, tokens_hold, token_hold, received;
    reg [7:0] layer_hold;
    reg [5:0] slot_hold;
    reg [63:0] audio_hold, weights_hold;
    reg [15:0] low_hold;
    reg [31:0] pair_hold;
    reg [11:0] pair_component;
    reg receive_bad;
    reg [3:0] child_error_hold, work_error_hold, error_hold;
    wire child_selected = rst_n && (state == CHILD_START || state == CHILD_WAIT ||
        state == PAIR_SEND || state == PAIR_WAIT || state == PAIR_REGISTER);
    wire child_ready, child_valid, child_cmd_valid, child_result_ready;
    wire child_output_valid, child_output_last;
    wire [31:0] child_output_index;
    wire [15:0] child_output_data;
    wire [63:0] child_addr, child_control, child_nested_control;
    wire [3:0] child_error;
    anvil_en1_audio_subsample immutable_input (
        .image_immutable(image_immutable === 1'b1),
        .image_invalidate((image_invalidate === 1'b1)),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == CHILD_START), .start_ready(child_ready),
        .model(model_hold), .precision(precision_hold), .generation(generation_hold),
        .frames(frames_hold), .token(token_hold),
        .audio_base(audio_hold), .audio_weights_base(weights_hold),
        .cmd_valid(child_cmd_valid), .cmd_ready(child_selected && cmd_ready),
        .cmd_write(), .cmd_addr(child_addr), .cmd_wdata(),
        .result_valid(child_selected && result_valid), .result_ready(child_result_ready),
        .result_data(result_data), .result_error(result_error),
        .output_valid(child_output_valid), .output_ready(rst_n && state == CHILD_WAIT),
        .output_index(child_output_index), .output_data(child_output_data),
        .output_last(child_output_last), .output_mask(),
        .done_valid(child_valid),
        .done_ready(rst_n && state == CHILD_WAIT && !child_output_valid),
        .done_mask(), .done_error(child_error),
        .input_read_event(input_read_event), .input_read_bytes(input_read_bytes),
        .weight_read_event(), .weight_read_bytes(),
        .projection_event(projection_event), .projection_bytes(projection_bytes),
        .point_replay_event(point_replay_event), .point_replay_bytes(point_replay_bytes),
        .vector_live_bytes(vector_live_bytes), .vector_physical_bytes(vector_physical_bytes),
        .controller_bytes(child_control), .nested_controller_bytes(child_nested_control)
    );
    wire beat_good = received < 1024 && child_output_index == received &&
        child_output_last == (received == 1023);
    assign start_ready = rst_n && state == IDLE;
    assign work_req_valid = rst_n && state == PAIR_SEND;
    assign work_req_op = rst_n ? 3'd6 : 3'd0;
    assign work_req_domain = rst_n ? 2'd2 : 2'd0;
    assign work_req_target = rst_n ? 2'd2 : 2'd0;
    assign work_req_token = rst_n ? token_hold : 32'd0;
    assign work_req_layer = rst_n ? layer_hold : 8'd0;
    assign work_req_length = rst_n ? 12'd1024 : 12'd0;
    assign work_req_component = rst_n ? pair_component : 12'd0;
    assign work_req_slot = rst_n ? slot_hold : 6'd0;
    assign work_req_bank = 0;
    assign work_req_scalar_index = 0;
    assign work_req_data = rst_n ? pair_hold : 32'd0;
    assign work_rsp_ready = rst_n && state == PAIR_WAIT;
    assign cmd_valid = child_selected && child_cmd_valid;
    assign cmd_write = 0;
    assign cmd_addr = child_selected ? child_addr : 64'd0;
    assign cmd_wdata = 0;
    assign result_ready = child_selected && child_result_ready;
    assign done_valid = rst_n && state == RESPONSE;
    assign done_error = rst_n ? error_hold : 4'd0;
    assign done_bank = 0;
    assign nested_controller_bytes = rst_n ? child_control + child_nested_control : 64'd0;
    wire [31:0] CONTROLLER_BITS =
        $bits(state) + $bits(model_hold) + $bits(precision_hold) + $bits(generation_hold) +
        $bits(frames_hold) + $bits(tokens_hold) + $bits(token_hold) + $bits(received) +
        $bits(layer_hold) + $bits(slot_hold) + $bits(audio_hold) + $bits(weights_hold) +
        $bits(low_hold) + $bits(pair_hold) + $bits(pair_component) + $bits(receive_bad) +
        $bits(child_error_hold) + $bits(work_error_hold) + $bits(error_hold);
    assign controller_bytes = rst_n ? (CONTROLLER_BITS + 7) >> 3 : 64'd0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            model_hold <= 0;
            precision_hold <= 0;
            generation_hold <= 0;
            frames_hold <= 0;
            tokens_hold <= 0;
            token_hold <= 0;
            received <= 0;
            layer_hold <= 0;
            slot_hold <= 0;
            audio_hold <= 0;
            weights_hold <= 0;
            low_hold <= 0;
            pair_hold <= 0;
            pair_component <= 0;
            receive_bad <= 0;
            child_error_hold <= 0;
            work_error_hold <= 0;
            error_hold <= 0;
        end else begin
            case (state)
                IDLE: if (start_valid && start_ready) begin
                    model_hold <= model;
                    precision_hold <= precision;
                    generation_hold <= generation;
                    frames_hold <= frames;
                    tokens_hold <= (frames + 32'd3) >> 2;
                    token_hold <= token;
                    layer_hold <= frame_layer;
                    slot_hold <= frame_slot;
                    audio_hold <= audio_base;
                    weights_hold <= audio_weights_base;
                    received <= 0;
                    receive_bad <= 0;
                    child_error_hold <= 0;
                    work_error_hold <= 0;
                    error_hold <= 0;
                    state <= VALIDATE;
                end
                VALIDATE: begin
                    if ((model_hold != 1 && model_hold != 2) || precision_hold > 1) begin
                        error_hold <= 6;
                        state <= PUBLISH;
                    end else if (generation_hold == 0 || frames_hold == 0 || frames_hold > 131072 ||
                        token_hold >= tokens_hold || audio_hold[1:0] != 0 ||
                        weights_hold[1:0] != 0) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else if (layer_hold != 0) begin
                        error_hold <= 7;
                        state <= PUBLISH;
                    end else
                        state <= CHILD_START;
                end
                CHILD_START: if (child_ready)
                    state <= CHILD_WAIT;
                CHILD_WAIT: begin
                    if (child_output_valid) begin
                        if (!beat_good) begin
                            receive_bad <= 1;
                            if (error_hold == 0)
                                error_hold <= 7;
                        end
                        if (received < 1024)
                            received <= received + 1'b1;
                        if (beat_good && !receive_bad && error_hold == 0) begin
                            if (!received[0])
                                low_hold <= child_output_data;
                            else begin
                                pair_hold <= {child_output_data, low_hold};
                                pair_component <= {received[11:1], 1'b0};
                                state <= PAIR_SEND;
                            end
                        end
                    end else if (child_valid) begin
                        child_error_hold <= child_error;
                        state <= CHILD_CHECK;
                    end
                end
                CHILD_CHECK: begin
                    if (error_hold == 0) begin
                        if (child_error_hold != 0)
                            error_hold <= child_error_hold;
                        else if (receive_bad || received != 1024)
                            error_hold <= 7;
                    end
                    state <= PUBLISH;
                end
                PAIR_SEND: if (work_req_ready)
                    state <= PAIR_WAIT;
                PAIR_WAIT: if (work_rsp_valid) begin
                    work_error_hold <= work_rsp_error;
                    state <= PAIR_REGISTER;
                end
                PAIR_REGISTER: begin
                    if (work_error_hold != 0 && error_hold == 0)
                        error_hold <= work_error_hold;
                    state <= CHILD_WAIT;
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
