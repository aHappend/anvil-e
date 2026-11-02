module anvil_en1_replay_attention #(
    parameter integer COMPACT = 0
) (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] model,
    input wire [7:0] layer,
    input wire [3:0] query_head,
    input wire [31:0] query_position, tokens,
    input wire [7:0] frame_layer,
    input wire [5:0] frame_slot,
    input wire resume_valid,
    input wire [159:0] continuation,
    output wire query_valid,
    input wire query_ready,
    output wire [9:0] query_component,
    input wire query_rsp_valid,
    output wire query_rsp_ready,
    input wire [15:0] query_rsp_data,
    input wire query_rsp_error,
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
    output wire fetch_valid,
    input wire fetch_ready,
    output wire [1:0] fetch_model,
    output wire [7:0] fetch_owner,
    output wire [31:0] fetch_token,
    output wire fetch_is_value,
    output wire [1:0] fetch_kv_head,
    output wire [9:0] fetch_component,
    input wire fetch_rsp_valid,
    output wire fetch_rsp_ready,
    input wire [15:0] fetch_rsp_data,
    input wire [3:0] fetch_rsp_error,
    output wire need_valid,
    input wire need_ready,
    input wire [1:0] need_action,
    output wire [1:0] need_model,
    output wire [7:0] need_owner,
    output wire [31:0] need_token,
    output wire need_is_value,
    output wire [1:0] need_kv_head,
    output wire [9:0] need_component,
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
    output wire [7:0] done_owner,
    output wire [31:0] done_token,
    output wire done_is_value,
    output wire [1:0] done_kv_head,
    output wire [9:0] done_component,
    output wire [63:0] controller_state_bytes,
    output wire [3:0] attention_activity,
    output wire busy
);
    localparam [3:0] IDLE = 0, VALIDATE = 1,
        RESTORE_SEND = 2, RESTORE_WAIT = 3, RESTORE_REGISTER = 4,
        HEAD_START = 5, HEAD_RUN = 6,
        SAVE_SEND = 7, SAVE_WAIT = 8, SAVE_REGISTER = 9,
        PUBLISH = 10, RESPONSE = 11;
    reg [3:0] state;
    reg [1:0] model_hold;
    reg [7:0] layer_hold, frame_layer_hold;
    reg [3:0] query_head_hold;
    reg [31:0] position_hold, tokens_hold;
    reg [5:0] frame_slot_hold;
    reg [11:0] hidden_hold;
    reg resume_hold;
    reg [383:0] checkpoint_hold;
    reg [2:0] word_index;
    reg [31:0] scalar_data_hold;
    reg [3:0] scalar_error_hold, error_hold;
    reg yield_hold;
    reg [7:0] owner_hold;
    reg [31:0] token_hold;
    reg selector_hold;
    reg [1:0] kv_head_hold;
    reg [9:0] component_hold;
    reg [31:0] scalar_write_data;

    initial begin
        if (COMPACT != 0 && COMPACT != 1)
            $fatal(1, "PARAMETER ERROR: COMPACT must be 0 or 1");
    end

    wire native_model = model_hold == 1 || model_hold == 2;
    wire [7:0] layer_count = model_hold == 1 ? 8'd35 : 8'd42;
    wire [11:0] selected_hidden = COMPACT ? 12'd8 :
        (model_hold == 1 ? 12'd1536 : 12'd2560);
    wire descriptor_valid = tokens_hold != 0 && tokens_hold <= 131072 &&
        position_hold < tokens_hold &&
        query_head_hold < (COMPACT ? 4'd2 : 4'd8);
    wire frame_valid = frame_layer_hold != 0 &&
        frame_layer_hold <= layer_count &&
        {1'b0, layer_hold} + 9'd1 == {1'b0, frame_layer_hold};
    wire head_ready, head_valid, head_checkpoint_valid;
    wire [3:0] head_error;
    wire [383:0] head_checkpoint;
    wire [1:0] head_need_kv_head;
    wire run = rst_n && state == HEAD_RUN;

    anvil_en1_attention_head #(.COMPACT(COMPACT), .REPLAY(1)) attention (
        .clk(clk), .rst_n(rst_n),
        .attention_activity(attention_activity),
        .start_valid(rst_n && state == HEAD_START), .start_ready(head_ready),
        .model(model_hold), .layer(layer_hold), .query_head(query_head_hold),
        .query_position(position_hold),
        .resume_valid(resume_hold), .resume_checkpoint(checkpoint_hold),
        .need_valid(need_valid), .need_ready(run && need_ready),
        .need_action(need_action),
        .need_model(need_model), .need_owner(need_owner), .need_token(need_token),
        .need_is_value(need_is_value), .need_kv_head(head_need_kv_head),
        .need_component(need_component),
        .checkpoint_valid(head_checkpoint_valid), .checkpoint_ready(run),
        .checkpoint_data(head_checkpoint),
        .query_valid(query_valid), .query_ready(run && query_ready),
        .query_component(query_component),
        .query_rsp_valid(run && query_rsp_valid), .query_rsp_ready(query_rsp_ready),
        .query_rsp_data(query_rsp_data), .query_rsp_error(query_rsp_error),
        .mask_valid(mask_valid), .mask_ready(run && mask_ready),
        .mask_token(mask_token),
        .mask_rsp_valid(run && mask_rsp_valid), .mask_rsp_ready(mask_rsp_ready),
        .mask_rsp_data(mask_rsp_data), .mask_rsp_error(mask_rsp_error),
        .req_valid(req_valid), .req_ready(run && req_ready),
        .req_op(req_op), .req_model(req_model), .req_layer(req_layer),
        .req_token(req_token), .req_is_value(req_is_value),
        .req_kv_head(req_kv_head), .req_component(req_component), .req_base(req_base),
        .rsp_valid(run && rsp_valid), .rsp_ready(rsp_ready),
        .rsp_addr(rsp_addr), .rsp_owner(rsp_owner), .rsp_alias(rsp_alias),
        .rsp_error(rsp_error), .rsp_space(rsp_space),
        .fetch_valid(fetch_valid), .fetch_ready(run && fetch_ready),
        .fetch_model(fetch_model), .fetch_owner(fetch_owner), .fetch_token(fetch_token),
        .fetch_is_value(fetch_is_value), .fetch_kv_head(fetch_kv_head),
        .fetch_component(fetch_component),
        .fetch_rsp_valid(run && fetch_rsp_valid), .fetch_rsp_ready(fetch_rsp_ready),
        .fetch_rsp_data(fetch_rsp_data), .fetch_rsp_error(fetch_rsp_error),
        .component_valid(output_valid), .component_ready(run && output_ready),
        .component_index(output_index), .component_data(output_data),
        .component_last(output_last),
        .done_valid(head_valid), .done_ready(run), .done_error(head_error)
    );

    always @* begin
        scalar_write_data = 0;
        if (rst_n) begin
            case (word_index)
                0: scalar_write_data = checkpoint_hold[191:160];
                1: scalar_write_data = checkpoint_hold[223:192];
                2: scalar_write_data = checkpoint_hold[255:224];
                3: scalar_write_data = checkpoint_hold[287:256];
                4: scalar_write_data = checkpoint_hold[319:288];
                5: scalar_write_data = checkpoint_hold[351:320];
                6: scalar_write_data = checkpoint_hold[383:352];
                default: scalar_write_data = 0;
            endcase
        end
    end

    assign start_ready = rst_n && state == IDLE;
    assign need_kv_head = rst_n ? head_need_kv_head : 2'd0;
    assign work_req_valid = rst_n &&
        (state == SAVE_SEND || state == RESTORE_SEND);
    assign work_req_op = !rst_n ? 3'd0 :
        (state == SAVE_SEND ? 3'd6 : 3'd7);
    assign work_req_domain = 0;
    assign work_req_target = 0;
    assign work_req_token = rst_n ? position_hold : 32'd0;
    assign work_req_layer = rst_n ? frame_layer_hold : 8'd0;
    assign work_req_length = rst_n ? hidden_hold : 12'd0;
    assign work_req_component = 0;
    assign work_req_slot = rst_n ? frame_slot_hold : 6'd0;
    assign work_req_bank = 0;
    assign work_req_scalar_index = rst_n ? {5'd0, word_index} + 8'd8 : 8'd0;
    assign work_req_data = rst_n && state == SAVE_SEND ? scalar_write_data : 32'd0;
    assign work_rsp_ready = rst_n &&
        (state == SAVE_WAIT || state == RESTORE_WAIT);
    assign done_valid = rst_n && state == RESPONSE;
    assign done_error = rst_n ? error_hold : 4'd0;
    assign done_yield = rst_n && yield_hold && error_hold == 0;
    assign done_continuation = rst_n && yield_hold ? checkpoint_hold[159:0] : 160'd0;
    assign done_owner = rst_n && yield_hold ? owner_hold : 8'd0;
    assign done_token = rst_n && yield_hold ? token_hold : 32'd0;
    assign done_is_value = rst_n && yield_hold && selector_hold;
    assign done_kv_head = rst_n && yield_hold ? kv_head_hold : 2'd0;
    assign done_component = rst_n && yield_hold ? component_hold : 10'd0;
    assign controller_state_bytes = rst_n ? 64'd74 : 64'd0;
    assign busy = rst_n && state != IDLE;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            model_hold <= 0;
            layer_hold <= 0;
            frame_layer_hold <= 0;
            query_head_hold <= 0;
            position_hold <= 0;
            tokens_hold <= 0;
            frame_slot_hold <= 0;
            hidden_hold <= 0;
            resume_hold <= 0;
            checkpoint_hold <= 0;
            word_index <= 0;
            scalar_data_hold <= 0;
            scalar_error_hold <= 0;
            error_hold <= 0;
            yield_hold <= 0;
            owner_hold <= 0;
            token_hold <= 0;
            selector_hold <= 0;
            kv_head_hold <= 0;
            component_hold <= 0;
        end else begin
            case (state)
                IDLE: if (start_valid && start_ready) begin
                    model_hold <= model;
                    layer_hold <= layer;
                    frame_layer_hold <= frame_layer;
                    query_head_hold <= query_head;
                    position_hold <= query_position;
                    tokens_hold <= tokens;
                    frame_slot_hold <= frame_slot;
                    resume_hold <= resume_valid;
                    checkpoint_hold <= {224'd0, continuation};
                    word_index <= 0;
                    scalar_data_hold <= 0;
                    scalar_error_hold <= 0;
                    error_hold <= 0;
                    yield_hold <= 0;
                    owner_hold <= 0;
                    token_hold <= 0;
                    selector_hold <= 0;
                    kv_head_hold <= 0;
                    component_hold <= 0;
                    state <= VALIDATE;
                end
                VALIDATE: begin
                    hidden_hold <= selected_hidden;
                    if (!native_model) begin
                        error_hold <= 6;
                        state <= PUBLISH;
                    end else if (!descriptor_valid) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else if (!frame_valid) begin
                        error_hold <= 7;
                        state <= PUBLISH;
                    end else if (resume_hold)
                        state <= RESTORE_SEND;
                    else
                        state <= HEAD_START;
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
                        case (word_index)
                            0: checkpoint_hold[191:160] <= scalar_data_hold;
                            1: checkpoint_hold[223:192] <= scalar_data_hold;
                            2: checkpoint_hold[255:224] <= scalar_data_hold;
                            3: checkpoint_hold[287:256] <= scalar_data_hold;
                            4: checkpoint_hold[319:288] <= scalar_data_hold;
                            5: checkpoint_hold[351:320] <= scalar_data_hold;
                            6: checkpoint_hold[383:352] <= scalar_data_hold;
                            default: begin
                                error_hold <= 7;
                                state <= PUBLISH;
                            end
                        endcase
                        if (word_index == 6)
                            state <= HEAD_START;
                        else if (word_index < 6) begin
                            word_index <= word_index + 1'b1;
                            state <= RESTORE_SEND;
                        end
                    end
                end
                HEAD_START: if (head_ready)
                    state <= HEAD_RUN;
                HEAD_RUN: begin
                    if (head_checkpoint_valid) begin
                        checkpoint_hold <= head_checkpoint;
                        owner_hold <= need_owner;
                        token_hold <= need_token;
                        selector_hold <= need_is_value;
                        kv_head_hold <= head_need_kv_head;
                        component_hold <= need_component;
                        word_index <= 0;
                        state <= SAVE_SEND;
                    end else if (head_valid) begin
                        error_hold <= head_error;
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
                    end else if (word_index == 6) begin
                        yield_hold <= 1;
                        state <= PUBLISH;
                    end else if (word_index < 6) begin
                        word_index <= word_index + 1'b1;
                        state <= SAVE_SEND;
                    end else begin
                        error_hold <= 7;
                        state <= PUBLISH;
                    end
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
