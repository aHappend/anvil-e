module anvil_en1_replay_kv_tile #(
    parameter integer COMPACT = 0,
    parameter integer ALLOW_QUERY = 0
) (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] model, precision,
    input wire [7:0] owner,
    input wire [31:0] token, tokens,
    input wire is_value,
    input wire [1:0] kv_head,
    input wire is_query,
    input wire [3:0] query_head,
    input wire [9:0] component,
    input wire [63:0] weights_base,
    input wire source_is_memo,
    input wire [7:0] source_layer,
    input wire [31:0] source_token,
    input wire [5:0] source_slot,
    input wire source_bank,
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
    output wire [31:0] done_data,
    output wire [3:0] done_error,
    output wire owner_reprojection_event,
    output wire [31:0] owner_reprojection_bytes,
    output wire query_projection_event,
    output wire [31:0] query_projection_bytes,
    output wire source_read_event,
    output wire [31:0] source_read_bytes,
    output wire [63:0] controller_state_bytes,
    output wire [63:0] tile_live_bytes, tile_physical_bytes,
    output wire [63:0] tile_shadow_bytes,
    output wire busy
);
    localparam [2:0] IDLE = 0, VALIDATE = 1, TILE_START = 2,
        TILE_RUN = 3, PUBLISH = 4, RESPONSE = 5;
    localparam [2:0] SOURCE_IDLE = 0, SOURCE_VALIDATE = 1,
        SOURCE_SEND = 2, SOURCE_WAIT = 3, SOURCE_REGISTER = 4,
        SOURCE_RESPONSE = 5;
    localparam integer MAX_H = COMPACT ? 8 : 2560;
    localparam integer MAX_D = COMPACT ? 8 : 512;
    reg [2:0] state, source_state;
    reg [1:0] model_hold, precision_hold, head_hold;
    reg [3:0] query_head_hold;
    reg [7:0] owner_hold, source_layer_hold;
    reg [31:0] token_hold, tokens_hold, source_token_hold;
    reg [63:0] weights_hold;
    reg selector_hold, query_hold, memo_hold, bank_hold;
    reg [9:0] component_hold;
    reg [5:0] slot_hold;
    reg [11:0] hidden_hold;
    reg [31:0] dimension_hold;
    reg [1:0] read_model;
    reg [7:0] read_owner;
    reg [31:0] read_token, read_index, read_pair;
    reg [15:0] read_data;
    reg read_error;
    reg [3:0] read_pair_error, error_hold;
    reg [31:0] pair_hold;
    wire [31:0] CONTROLLER_BITS = $bits({
        state, source_state, model_hold, precision_hold, head_hold, query_head_hold,
        owner_hold, source_layer_hold, token_hold, tokens_hold, source_token_hold,
        weights_hold, selector_hold, query_hold, memo_hold, bank_hold, component_hold,
        slot_hold, hidden_hold, dimension_hold, read_model, read_owner, read_token,
        read_index, read_pair, read_data, read_error, read_pair_error, error_hold, pair_hold
    });
    wire [63:0] owner_controller_bytes;

    initial begin
        if ((COMPACT != 0 && COMPACT != 1) ||
            (ALLOW_QUERY != 0 && ALLOW_QUERY != 1))
            $fatal(1, "PARAMETER ERROR: COMPACT and ALLOW_QUERY must be 0 or 1");
    end

    wire native_model, is_global;
    wire [7:0] owner_count, layer_count;
    wire [11:0] selected_hidden;
    anvil_en1_geometry geometry (
        .rst_n(rst_n), .model(model_hold), .layer(owner_hold),
        .is_native(native_model), .layers(layer_count), .owners(owner_count), .owner(),
        .is_global(is_global), .hidden(selected_hidden), .intermediate()
    );
    wire [31:0] selected_dimension = COMPACT ?
        (is_global ? 32'd8 : 32'd4) : (is_global ? 32'd512 : 32'd256);
    wire source_tag_valid = source_token_hold == token_hold &&
        (memo_hold ? source_layer_hold == owner_hold :
            {1'b0, source_layer_hold} == {1'b0, owner_hold} + 9'd1) &&
        (!memo_hold || (slot_hold < 16 && !bank_hold));
    wire source_descriptor_valid = read_model == model_hold &&
        read_owner == owner_hold && read_token == token_hold &&
        read_index < {20'd0, hidden_hold};
    wire tile_ready, tile_valid, tile_source_valid, tile_source_rsp_ready;
    wire [1:0] tile_source_model;
    wire [7:0] tile_source_owner;
    wire [31:0] tile_source_token, tile_source_index, tile_data;
    wire [3:0] tile_error;
    wire run = rst_n && state == TILE_RUN;

    anvil_en1_owner_kv_tile #(.COMPACT(COMPACT), .ALLOW_QUERY(ALLOW_QUERY)) owner_tile (
        .controller_bytes(owner_controller_bytes),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == TILE_START), .start_ready(tile_ready),
        .model(model_hold), .precision(precision_hold),
        .owner(owner_hold), .token(token_hold), .is_value(selector_hold),
        .is_query(query_hold), .query_head(query_head_hold),
        .kv_head(head_hold), .component(component_hold), .weights_base(weights_hold),
        .source_valid(tile_source_valid),
        .source_ready(run && source_state == SOURCE_IDLE),
        .source_model(tile_source_model), .source_owner(tile_source_owner),
        .source_token(tile_source_token), .source_index(tile_source_index),
        .source_normalized(), .input_store_valid(),
        .input_store_index(), .input_store_data(),
        .source_rsp_valid(run && source_state == SOURCE_RESPONSE),
        .source_rsp_ready(tile_source_rsp_ready),
        .source_rsp_data(read_data), .source_rsp_error(read_error),
        .cmd_valid(cmd_valid), .cmd_ready(run && cmd_ready),
        .cmd_write(cmd_write), .cmd_addr(cmd_addr), .cmd_wdata(cmd_wdata),
        .result_valid(run && result_valid), .result_ready(result_ready),
        .result_data(result_data), .result_error(result_error),
        .done_valid(tile_valid),
        .done_ready(run && source_state == SOURCE_IDLE),
        .done_data(tile_data), .done_error(tile_error),
        .projection_event(owner_reprojection_event),
        .projection_bytes(owner_reprojection_bytes),
        .query_projection_event(query_projection_event),
        .query_projection_bytes(query_projection_bytes)
    );

    assign start_ready = rst_n && state == IDLE;
    assign work_req_valid = run && source_state == SOURCE_SEND;
    assign work_req_op = rst_n ? 3'd4 : 3'd0;
    assign work_req_domain = 0;
    assign work_req_target = rst_n && memo_hold ? 2'd1 : 2'd0;
    assign work_req_token = rst_n ? source_token_hold : 32'd0;
    assign work_req_layer = rst_n ? source_layer_hold : 8'd0;
    assign work_req_length = rst_n ? hidden_hold : 12'd0;
    assign work_req_component = rst_n ? {read_index[11:1], 1'b0} : 12'd0;
    assign work_req_slot = rst_n ? slot_hold : 6'd0;
    assign work_req_bank = rst_n && bank_hold;
    assign work_req_scalar_index = 0;
    assign work_req_data = 0;
    assign work_rsp_ready = run && source_state == SOURCE_WAIT;
    assign done_valid = rst_n && state == RESPONSE;
    assign done_data = rst_n ? pair_hold : 32'd0;
    assign done_error = rst_n ? error_hold : 4'd0;
    assign source_read_event = work_rsp_valid && work_rsp_ready;
    assign source_read_bytes = source_read_event ? 32'd4 : 32'd0;
    assign controller_state_bytes = !rst_n ? 64'd0 :
        64'((CONTROLLER_BITS+7) >> 3) + owner_controller_bytes;
    assign tile_live_bytes = rst_n &&
        (state == TILE_START || state == TILE_RUN) ?
        ({52'd0, hidden_hold} + {32'd0, dimension_hold}) << 1 : 64'd0;
    assign tile_shadow_bytes = rst_n &&
        (state == TILE_START || state == TILE_RUN) ?
        (model_hold == 1 ? 64'd3072 : 64'd5120) +
            (is_global ? 64'd1024 : 64'd512) : 64'd0;
    assign tile_physical_bytes = rst_n ? 64'(2*(MAX_H+MAX_D)) : 64'd0;
    assign busy = rst_n && state != IDLE;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            source_state <= SOURCE_IDLE;
            model_hold <= 0;
            precision_hold <= 0;
            head_hold <= 0;
            query_head_hold <= 0;
            owner_hold <= 0;
            source_layer_hold <= 0;
            token_hold <= 0;
            tokens_hold <= 0;
            source_token_hold <= 0;
            weights_hold <= 0;
            selector_hold <= 0;
            query_hold <= 0;
            memo_hold <= 0;
            bank_hold <= 0;
            component_hold <= 0;
            slot_hold <= 0;
            hidden_hold <= 0;
            dimension_hold <= 0;
            read_model <= 0;
            read_owner <= 0;
            read_token <= 0;
            read_index <= 0;
            read_pair <= 0;
            read_data <= 0;
            read_error <= 0;
            read_pair_error <= 0;
            error_hold <= 0;
            pair_hold <= 0;
        end else begin
            case (state)
                IDLE: if (start_valid && start_ready) begin
                    model_hold <= model;
                    precision_hold <= precision;
                    head_hold <= kv_head;
                    query_head_hold <= ALLOW_QUERY && is_query ? query_head : 4'd0;
                    owner_hold <= owner;
                    source_layer_hold <= source_layer;
                    token_hold <= token;
                    tokens_hold <= tokens;
                    source_token_hold <= source_token;
                    weights_hold <= weights_base;
                    selector_hold <= is_value;
                    query_hold <= ALLOW_QUERY && is_query;
                    memo_hold <= source_is_memo;
                    bank_hold <= source_bank;
                    component_hold <= component;
                    slot_hold <= source_slot;
                    error_hold <= 0;
                    pair_hold <= 0;
                    state <= VALIDATE;
                end
                VALIDATE: begin
                    hidden_hold <= COMPACT ? 12'd8 : selected_hidden;
                    dimension_hold <= selected_dimension;
                    if (!native_model || precision_hold > 1) begin
                        error_hold <= 6;
                        state <= PUBLISH;
                    end else if (tokens_hold == 0 || tokens_hold > 131072 ||
                        token_hold >= tokens_hold ||
                        owner_hold >= (query_hold ? layer_count : owner_count) ||
                        component_hold[0] || component_hold >= selected_dimension ||
                        (query_hold ? (selector_hold ||
                            query_head_hold >= (COMPACT ? 4'd2 : 4'd8)) :
                            head_hold >= (COMPACT || model_hold == 1 ? 2'd1 : 2'd2))) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else if (!source_tag_valid) begin
                        error_hold <= 7;
                        state <= PUBLISH;
                    end else
                        state <= TILE_START;
                end
                TILE_START: if (tile_ready)
                    state <= TILE_RUN;
                TILE_RUN: if (tile_valid && source_state == SOURCE_IDLE) begin
                    pair_hold <= tile_data;
                    error_hold <= tile_error;
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

            case (source_state)
                SOURCE_IDLE: if (run && tile_source_valid) begin
                    read_model <= tile_source_model;
                    read_owner <= tile_source_owner;
                    read_token <= tile_source_token;
                    read_index <= tile_source_index;
                    read_error <= 0;
                    read_data <= 0;
                    source_state <= SOURCE_VALIDATE;
                end
                SOURCE_VALIDATE: begin
                    if (!source_descriptor_valid) begin
                        read_error <= 1;
                        source_state <= SOURCE_RESPONSE;
                    end else
                        source_state <= SOURCE_SEND;
                end
                SOURCE_SEND: if (work_req_valid && work_req_ready)
                    source_state <= SOURCE_WAIT;
                SOURCE_WAIT: if (work_rsp_valid && work_rsp_ready) begin
                    read_pair <= work_rsp_data;
                    read_pair_error <= work_rsp_error;
                    source_state <= SOURCE_REGISTER;
                end
                SOURCE_REGISTER: begin
                    read_error <= read_pair_error != 0;
                    read_data <= read_index[0] ? read_pair[31:16] : read_pair[15:0];
                    source_state <= SOURCE_RESPONSE;
                end
                SOURCE_RESPONSE: if (run && tile_source_rsp_ready)
                    source_state <= SOURCE_IDLE;
                default: begin
                    read_error <= 1;
                    source_state <= SOURCE_RESPONSE;
                end
            endcase
        end
    end
endmodule
