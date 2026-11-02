module anvil_en1_replay_frame_input #(
    parameter integer COMPACT = 0,
    parameter integer DOMAIN = 0
) (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] model,
    input wire [31:0] token, tokens,
    input wire [7:0] frame_layer,
    input wire [5:0] frame_slot,
    input wire input_bank,
    input wire dependency_valid,
    input wire [1:0] dependency_domain,
    input wire [7:0] dependency_layer,
    input wire [31:0] dependency_token,
    input wire [11:0] dependency_length,
    input wire [5:0] dependency_slot,
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
    output wire done_valid,
    input wire done_ready,
    output wire [3:0] done_error,
    output wire done_dependency,
    output wire [1:0] done_dependency_domain,
    output wire [7:0] done_dependency_layer,
    output wire [31:0] done_dependency_token,
    output wire [11:0] done_dependency_length,
    output wire [63:0] controller_state_bytes,
    output wire busy
);
    localparam [2:0] IDLE = 0, VALIDATE = 1, COPY_SEND = 2,
        COPY_WAIT = 3, COPY_REGISTER = 4, PUBLISH = 5, RESPONSE = 6;
    reg [2:0] state;
    reg [1:0] model_hold, dependency_domain_hold;
    reg [31:0] token_hold, tokens_hold, dependency_token_hold;
    reg [7:0] frame_layer_hold, dependency_layer_hold;
    reg [5:0] frame_slot_hold, dependency_slot_hold;
    reg bank_hold, dependency_valid_hold, yield_hold;
    reg [11:0] length_hold, dependency_length_hold;
    reg [3:0] error_hold, copy_error_hold;

    initial begin
        if (COMPACT != 0 && COMPACT != 1)
            $fatal(1, "PARAMETER ERROR: COMPACT must be 0 or 1");
        if (DOMAIN < 0 || DOMAIN > 2)
            $fatal(1, "PARAMETER ERROR: DOMAIN must be 0, 1 or 2");
    end

    wire native_model = model_hold == 1 || model_hold == 2;
    wire [7:0] layers = DOMAIN == 1 ? 8'd16 : (DOMAIN == 2 ? 8'd12 :
        (model_hold == 1 ? 8'd35 : 8'd42));
    wire [11:0] selected_length = DOMAIN == 1 ? 12'd768 :
        (DOMAIN == 2 ? 12'd1024 : (COMPACT ? 12'd8 :
        (model_hold == 1 ? 12'd1536 : 12'd2560)));
    wire descriptor_valid = frame_layer_hold != 0 && frame_layer_hold <= layers &&
        tokens_hold != 0 && tokens_hold <= 131072 && token_hold < tokens_hold;
    wire dependency_tag_valid = dependency_domain_hold == DOMAIN &&
        {1'b0, dependency_layer_hold} + 9'd1 == {1'b0, frame_layer_hold} &&
        dependency_token_hold == token_hold && dependency_length_hold == selected_length &&
        dependency_slot_hold < 16;

    assign start_ready = rst_n && state == IDLE;
    assign work_req_valid = rst_n && state == COPY_SEND;
    assign work_req_op = rst_n ? 3'd3 : 3'd0;
    assign work_req_domain = rst_n ? 2'(DOMAIN) : 2'd0;
    assign work_req_target = rst_n ? 2'd3 : 2'd0;
    assign work_req_token = rst_n ? token_hold : 32'd0;
    assign work_req_layer = rst_n ? frame_layer_hold : 8'd0;
    assign work_req_length = rst_n ? length_hold : 12'd0;
    assign work_req_component = 0;
    assign work_req_slot = rst_n ? frame_slot_hold : 6'd0;
    assign work_req_bank = rst_n && bank_hold;
    assign work_req_scalar_index = 0;
    assign work_req_data = rst_n ?
        {dependency_slot_hold, dependency_layer_hold, dependency_token_hold[17:0]} : 32'd0;
    assign work_rsp_ready = rst_n && state == COPY_WAIT;
    assign done_valid = rst_n && state == RESPONSE;
    assign done_error = rst_n ? error_hold : 4'd0;
    assign done_dependency = rst_n && yield_hold && error_hold == 0;
    assign done_dependency_domain = rst_n ? 2'(DOMAIN) : 2'd0;
    assign done_dependency_layer = rst_n && yield_hold ? frame_layer_hold - 1'b1 : 8'd0;
    assign done_dependency_token = rst_n && yield_hold ? token_hold : 32'd0;
    assign done_dependency_length = rst_n && yield_hold ? length_hold : 12'd0;
    localparam integer CONTROLLER_BITS =
        $bits(state) + $bits(model_hold) + $bits(dependency_domain_hold) +
        $bits(token_hold) + $bits(tokens_hold) + $bits(dependency_token_hold) +
        $bits(frame_layer_hold) + $bits(dependency_layer_hold) +
        $bits(frame_slot_hold) + $bits(dependency_slot_hold) +
        $bits(bank_hold) + $bits(dependency_valid_hold) + $bits(yield_hold) +
        $bits(length_hold) + $bits(dependency_length_hold) +
        $bits(error_hold) + $bits(copy_error_hold);
    assign controller_state_bytes = rst_n ? (CONTROLLER_BITS + 7) >> 3 : 64'd0;
    assign busy = rst_n && state != IDLE;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            model_hold <= 0;
            dependency_domain_hold <= 0;
            token_hold <= 0;
            tokens_hold <= 0;
            dependency_token_hold <= 0;
            frame_layer_hold <= 0;
            dependency_layer_hold <= 0;
            frame_slot_hold <= 0;
            dependency_slot_hold <= 0;
            bank_hold <= 0;
            dependency_valid_hold <= 0;
            yield_hold <= 0;
            length_hold <= 0;
            dependency_length_hold <= 0;
            error_hold <= 0;
            copy_error_hold <= 0;
        end else begin
            case (state)
                IDLE: if (start_valid && start_ready) begin
                    model_hold <= model;
                    token_hold <= token;
                    tokens_hold <= tokens;
                    frame_layer_hold <= frame_layer;
                    frame_slot_hold <= frame_slot;
                    bank_hold <= input_bank;
                    dependency_valid_hold <= dependency_valid;
                    dependency_domain_hold <= dependency_domain;
                    dependency_layer_hold <= dependency_layer;
                    dependency_token_hold <= dependency_token;
                    dependency_length_hold <= dependency_length;
                    dependency_slot_hold <= dependency_slot;
                    error_hold <= 0;
                    copy_error_hold <= 0;
                    yield_hold <= 0;
                    state <= VALIDATE;
                end
                VALIDATE: begin
                    length_hold <= selected_length;
                    if (!native_model) begin
                        error_hold <= 6;
                        state <= PUBLISH;
                    end else if (!descriptor_valid) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else if (!dependency_valid_hold) begin
                        yield_hold <= 1;
                        state <= PUBLISH;
                    end else if (!dependency_tag_valid) begin
                        error_hold <= 7;
                        state <= PUBLISH;
                    end else
                        state <= COPY_SEND;
                end
                COPY_SEND: if (work_req_valid && work_req_ready)
                    state <= COPY_WAIT;
                COPY_WAIT: if (work_rsp_valid && work_rsp_ready) begin
                    copy_error_hold <= work_rsp_error;
                    state <= COPY_REGISTER;
                end
                COPY_REGISTER: begin
                    error_hold <= copy_error_hold;
                    state <= PUBLISH;
                end
                PUBLISH: state <= RESPONSE;
                RESPONSE: if (done_ready)
                    state <= IDLE;
                default: begin
                    error_hold <= 7;
                    yield_hold <= 0;
                    state <= PUBLISH;
                end
            endcase
        end
    end
endmodule
