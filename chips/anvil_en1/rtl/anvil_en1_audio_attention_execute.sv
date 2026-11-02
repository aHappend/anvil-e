module anvil_en1_audio_attention_execute #(
    parameter integer REPLAY = 0
) (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] model, precision,
    input wire [31:0] generation, frames, query_token,
    input wire [7:0] layer,
    input wire [2:0] head,
    input wire [63:0] audio_base, audio_weights_base,
    input wire resume_valid,
    input wire [1023:0] resume_checkpoint,
    output wire need_valid,
    input wire need_ready,
    input wire [1:0] need_action,
    output wire [1:0] need_model, need_precision, need_selector,
    output wire [31:0] need_generation, need_token,
    output wire [7:0] need_layer,
    output wire [2:0] need_head,
    output wire [9:0] need_component,
    output wire checkpoint_valid,
    input wire checkpoint_ready,
    output wire [1023:0] checkpoint_data,
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
    output wire [9:0] output_index,
    output wire [15:0] output_data,
    output wire output_last,
    output wire done_valid,
    input wire done_ready,
    output wire done_yield,
    output wire [3:0] done_error,
    output wire input_read_event,
    output wire [31:0] input_read_bytes,
    output wire weight_read_event,
    output wire [31:0] weight_read_bytes,
    output wire projection_event,
    output wire [31:0] projection_bytes,
    output wire [63:0] controller_bytes, head_controller_bytes, input_controller_bytes,
    output wire [63:0] tile_controller_bytes, clipped_controller_bytes, clamp_controller_bytes,
    output wire [63:0] position_controller_bytes, softplus_controller_bytes
);
    localparam [3:0] IDLE = 0, VALIDATE = 1, HEAD_START = 2,
        HEAD_RUN = 3, HEAD_CHECK = 4, PUBLISH = 5, RESPONSE = 6;
    localparam [3:0] S_IDLE = 0, S_VALIDATE = 1,
        MASK_START = 2, MASK_WAIT = 3, MASK_REGISTER = 4, MASK_RESPONSE = 5,
        TILE_START = 6, TILE_WAIT = 7, TILE_REGISTER = 8, TILE_RESPONSE = 9;
    reg [3:0] state, service_state;
    reg [1:0] model_hold, precision_hold, selector_hold;
    reg [31:0] generation_hold, frames_hold, tokens_hold, query_hold, service_token;
    reg [7:0] layer_hold;
    reg [2:0] head_hold;
    reg [9:0] component_hold;
    reg [63:0] audio_hold, weights_hold, pair_hold;
    reg [1023:0] checkpoint_hold;
    reg service_mask, mask_data_hold, resume_hold, yield_hold, receive_bad;
    reg [31:0] received;
    reg [3:0] service_error_hold, first_service_error, child_error_hold, error_hold;
    initial begin
        if (REPLAY != 0 && REPLAY != 1)
            $fatal(1, "PARAMETER ERROR: REPLAY must be 0 or 1");
    end
    wire run = rst_n && state == HEAD_RUN;
    wire service_idle = service_state == S_IDLE;
    wire head_ready, head_valid, head_yield, head_mask_valid, head_mask_rsp_ready;
    wire head_need_valid, head_qkv_valid, head_qkv_rsp_ready, head_checkpoint_valid;
    wire head_output_valid, head_output_last;
    wire [31:0] head_mask_token, head_qkv_generation, head_qkv_token;
    wire [1:0] head_qkv_model, head_qkv_precision, head_qkv_selector;
    wire [7:0] head_qkv_layer;
    wire [2:0] head_qkv_head;
    wire [9:0] head_qkv_component, head_output_index;
    wire [15:0] head_output_data;
    wire [3:0] head_error;
    wire [1023:0] head_checkpoint;
    anvil_en1_audio_attention_head #(.REPLAY(REPLAY)) attention (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == HEAD_START), .start_ready(head_ready),
        .model(model_hold), .precision(precision_hold), .generation(generation_hold),
        .tokens(tokens_hold), .query_token(query_hold), .layer(layer_hold), .head(head_hold),
        .resume_valid(resume_hold), .resume_checkpoint(checkpoint_hold),
        .mask_valid(head_mask_valid), .mask_ready(run && service_idle),
        .mask_token(head_mask_token),
        .mask_rsp_valid(run && service_state == MASK_RESPONSE),
        .mask_rsp_ready(head_mask_rsp_ready), .mask_rsp_data(mask_data_hold),
        .mask_rsp_error(service_error_hold != 0),
        .need_valid(head_need_valid), .need_ready(run && service_idle && need_ready),
        .need_action(need_action),
        .qkv_valid(head_qkv_valid), .qkv_ready(run && service_idle),
        .qkv_model(head_qkv_model), .qkv_precision(head_qkv_precision),
        .qkv_selector(head_qkv_selector), .qkv_generation(head_qkv_generation),
        .qkv_token(head_qkv_token), .qkv_layer(head_qkv_layer), .qkv_head(head_qkv_head),
        .qkv_component(head_qkv_component),
        .qkv_rsp_valid(run && service_state == TILE_RESPONSE),
        .qkv_rsp_ready(head_qkv_rsp_ready), .qkv_rsp_data(pair_hold),
        .qkv_rsp_error(service_error_hold),
        .checkpoint_valid(head_checkpoint_valid),
        .checkpoint_ready(run && service_idle && checkpoint_ready),
        .checkpoint_data(head_checkpoint),
        .output_valid(head_output_valid), .output_ready(run && output_ready),
        .output_index(head_output_index), .output_data(head_output_data),
        .output_last(head_output_last), .done_valid(head_valid),
        .done_ready(run && service_idle), .done_yield(head_yield),
        .done_error(head_error), .controller_bytes(head_controller_bytes)
    );
    wire mask_ready, mask_valid, mask_cmd_valid, mask_result_ready;
    wire [31:0] mask_data;
    wire [63:0] mask_addr;
    wire [3:0] mask_error;
    wire mask_selected = run && (service_state == MASK_START || service_state == MASK_WAIT);
    anvil_en1_audio_input original_mask (
        .clk(clk), .rst_n(rst_n),
        .start_valid(run && service_state == MASK_START), .start_ready(mask_ready),
        .model(model_hold), .kind(2'd1), .generation(generation_hold),
        .frames(frames_hold), .frame(service_token << 2), .frequency(32'd0),
        .audio_base(audio_hold),
        .cmd_valid(mask_cmd_valid), .cmd_ready(mask_selected && cmd_ready),
        .cmd_write(), .cmd_addr(mask_addr), .cmd_wdata(),
        .result_valid(mask_selected && result_valid), .result_ready(mask_result_ready),
        .result_data(result_data), .result_error(result_error),
        .done_valid(mask_valid), .done_ready(run && service_state == MASK_WAIT),
        .done_data(mask_data), .done_error(mask_error),
        .input_read_event(input_read_event), .input_read_bytes(input_read_bytes),
        .controller_bytes(input_controller_bytes)
    );
    wire tile_ready, tile_valid, tile_cmd_valid, tile_result_ready;
    wire tile_source_valid, tile_source_rsp_ready;
    wire [1:0] tile_source_model;
    wire [7:0] tile_source_layer;
    wire [31:0] tile_source_generation, tile_source_token, tile_source_index;
    wire [63:0] tile_data, tile_addr;
    wire [3:0] tile_error;
    wire tile_selected = run && (service_state == TILE_START || service_state == TILE_WAIT);
    anvil_en1_audio_qkv_tile tile (
        .clk(clk), .rst_n(rst_n),
        .start_valid(run && service_state == TILE_START), .start_ready(tile_ready),
        .model(model_hold), .precision(precision_hold), .selector(selector_hold),
        .layer(layer_hold), .generation(generation_hold), .token(service_token),
        .head(head_hold), .component(component_hold), .audio_weights_base(weights_hold),
        .source_valid(tile_source_valid), .source_ready(tile_selected && source_ready),
        .source_model(tile_source_model), .source_layer(tile_source_layer),
        .source_generation(tile_source_generation), .source_token(tile_source_token),
        .source_index(tile_source_index),
        .source_rsp_valid(tile_selected && source_rsp_valid),
        .source_rsp_ready(tile_source_rsp_ready),
        .source_rsp_data(source_rsp_data), .source_rsp_error(source_rsp_error),
        .cmd_valid(tile_cmd_valid), .cmd_ready(tile_selected && cmd_ready),
        .cmd_write(), .cmd_addr(tile_addr), .cmd_wdata(),
        .result_valid(tile_selected && result_valid), .result_ready(tile_result_ready),
        .result_data(result_data), .result_error(result_error),
        .done_valid(tile_valid), .done_ready(run && service_state == TILE_WAIT),
        .done_data(tile_data), .done_error(tile_error),
        .projection_event(projection_event), .projection_bytes(projection_bytes),
        .controller_bytes(tile_controller_bytes), .clipped_controller_bytes(clipped_controller_bytes),
        .clamp_controller_bytes(clamp_controller_bytes),
        .position_controller_bytes(position_controller_bytes),
        .softplus_controller_bytes(softplus_controller_bytes)
    );
    wire qkv_tag_good = head_qkv_model == model_hold && head_qkv_precision == precision_hold &&
        head_qkv_generation == generation_hold && head_qkv_layer == layer_hold &&
        head_qkv_head == head_hold && head_qkv_component < 128 && !head_qkv_component[0];
    wire service_descriptor_good = service_mask ? service_token < tokens_hold :
        (selector_hold == 3 ? service_token <= 12 : service_token < tokens_hold);
    wire output_good = received < 128 && head_output_index == received &&
        head_output_last == (received == 127);
    assign start_ready = rst_n && state == IDLE;
    assign need_valid = run && service_idle && head_need_valid;
    assign need_model = rst_n ? head_qkv_model : 2'd0;
    assign need_precision = rst_n ? head_qkv_precision : 2'd0;
    assign need_selector = rst_n ? head_qkv_selector : 2'd0;
    assign need_generation = rst_n ? head_qkv_generation : 32'd0;
    assign need_token = rst_n ? head_qkv_token : 32'd0;
    assign need_layer = rst_n ? head_qkv_layer : 8'd0;
    assign need_head = rst_n ? head_qkv_head : 3'd0;
    assign need_component = rst_n ? head_qkv_component : 10'd0;
    assign checkpoint_valid = run && service_idle && head_checkpoint_valid;
    assign checkpoint_data = rst_n ? head_checkpoint : 1024'd0;
    assign source_valid = tile_selected && tile_source_valid;
    assign source_rsp_ready = tile_selected && tile_source_rsp_ready;
    assign source_model = rst_n ? tile_source_model : 2'd0;
    assign source_layer = rst_n ? tile_source_layer : 8'd0;
    assign source_generation = rst_n ? tile_source_generation : 32'd0;
    assign source_token = rst_n ? tile_source_token : 32'd0;
    assign source_index = rst_n ? tile_source_index : 32'd0;
    assign cmd_valid = mask_selected ? mask_cmd_valid : (tile_selected && tile_cmd_valid);
    assign cmd_write = 0;
    assign cmd_addr = !rst_n ? 64'd0 :
        (mask_selected ? mask_addr : (tile_selected ? tile_addr : 64'd0));
    assign cmd_wdata = 0;
    assign result_ready = mask_selected ? mask_result_ready : (tile_selected && tile_result_ready);
    assign output_valid = run && head_output_valid;
    assign output_index = rst_n ? head_output_index : 10'd0;
    assign output_data = rst_n ? head_output_data : 16'd0;
    assign output_last = run && head_output_last;
    assign done_valid = rst_n && state == RESPONSE;
    assign done_yield = rst_n && yield_hold;
    assign done_error = rst_n ? error_hold : 4'd0;
    assign weight_read_event = tile_selected && tile_cmd_valid && cmd_ready;
    assign weight_read_bytes = weight_read_event ? 32'd4 : 32'd0;
    localparam integer CONTROLLER_BITS =
        $bits(state) + $bits(service_state) + $bits(model_hold) + $bits(precision_hold) +
        $bits(selector_hold) + $bits(generation_hold) + $bits(frames_hold) +
        $bits(tokens_hold) + $bits(query_hold) + $bits(service_token) + $bits(layer_hold) +
        $bits(head_hold) + $bits(component_hold) + $bits(audio_hold) + $bits(weights_hold) +
        $bits(pair_hold) + $bits(checkpoint_hold) + $bits(service_mask) +
        $bits(mask_data_hold) + $bits(resume_hold) + $bits(yield_hold) +
        $bits(receive_bad) + $bits(received) + $bits(service_error_hold) +
        $bits(first_service_error) + $bits(child_error_hold) + $bits(error_hold);
    assign controller_bytes = rst_n ? (CONTROLLER_BITS + 7) >> 3 : 64'd0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            service_state <= S_IDLE;
            selector_hold <= 0;
            service_token <= 0;
            component_hold <= 0;
            pair_hold <= 0;
            service_mask <= 0;
            mask_data_hold <= 0;
            service_error_hold <= 0;
            first_service_error <= 0;
        end else begin
            if (state == IDLE && start_valid && start_ready)
                first_service_error <= 0;
            case (service_state)
                S_IDLE: if (run && head_mask_valid) begin
                    service_mask <= 1;
                    service_token <= head_mask_token;
                    service_error_hold <= 0;
                    mask_data_hold <= 0;
                    service_state <= S_VALIDATE;
                end else if (run && head_qkv_valid) begin
                    service_mask <= 0;
                    service_token <= head_qkv_token;
                    selector_hold <= head_qkv_selector;
                    component_hold <= head_qkv_component;
                    service_error_hold <= qkv_tag_good ? 4'd0 : 4'd7;
                    pair_hold <= 0;
                    service_state <= S_VALIDATE;
                end
                S_VALIDATE: begin
                    if (!service_descriptor_good || service_error_hold != 0 ||
                        first_service_error != 0) begin
                        service_error_hold <= first_service_error != 0 ? first_service_error : 4'd7;
                        if (first_service_error == 0)
                            first_service_error <= 7;
                        if (service_mask)
                            service_state <= MASK_REGISTER;
                        else
                            service_state <= TILE_REGISTER;
                    end else if (service_mask)
                        service_state <= MASK_START;
                    else
                        service_state <= TILE_START;
                end
                MASK_START: if (mask_ready)
                    service_state <= MASK_WAIT;
                MASK_WAIT: if (mask_valid) begin
                    mask_data_hold <= mask_data[0];
                    service_error_hold <= mask_error;
                    if (first_service_error == 0 && mask_error != 0)
                        first_service_error <= mask_error;
                    service_state <= MASK_REGISTER;
                end
                MASK_REGISTER: service_state <= MASK_RESPONSE;
                MASK_RESPONSE: if (head_mask_rsp_ready)
                    service_state <= S_IDLE;
                TILE_START: if (tile_ready)
                    service_state <= TILE_WAIT;
                TILE_WAIT: if (tile_valid) begin
                    pair_hold <= tile_data;
                    service_error_hold <= tile_error;
                    if (first_service_error == 0 && tile_error != 0)
                        first_service_error <= tile_error;
                    service_state <= TILE_REGISTER;
                end
                TILE_REGISTER: service_state <= TILE_RESPONSE;
                TILE_RESPONSE: if (head_qkv_rsp_ready)
                    service_state <= S_IDLE;
                default: begin
                    service_error_hold <= 7;
                    if (first_service_error == 0)
                        first_service_error <= 7;
                    if (service_mask)
                        service_state <= MASK_REGISTER;
                    else
                        service_state <= TILE_REGISTER;
                end
            endcase
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            model_hold <= 0;
            precision_hold <= 0;
            generation_hold <= 0;
            frames_hold <= 0;
            tokens_hold <= 0;
            query_hold <= 0;
            layer_hold <= 0;
            head_hold <= 0;
            audio_hold <= 0;
            weights_hold <= 0;
            checkpoint_hold <= 0;
            resume_hold <= 0;
            yield_hold <= 0;
            receive_bad <= 0;
            received <= 0;
            child_error_hold <= 0;
            error_hold <= 0;
        end else begin
            if (run && head_output_valid && output_ready) begin
                if (!output_good)
                    receive_bad <= 1;
                if (received < 128)
                    received <= received + 1'b1;
            end
            case (state)
                IDLE: if (start_valid && start_ready) begin
                    model_hold <= model;
                    precision_hold <= precision;
                    generation_hold <= generation;
                    frames_hold <= frames;
                    tokens_hold <= (frames + 32'd3) >> 2;
                    query_hold <= query_token;
                    layer_hold <= layer;
                    head_hold <= head;
                    audio_hold <= audio_base;
                    weights_hold <= audio_weights_base;
                    resume_hold <= REPLAY && resume_valid;
                    if (REPLAY)
                        checkpoint_hold <= resume_checkpoint;
                    yield_hold <= 0;
                    receive_bad <= 0;
                    received <= REPLAY && resume_valid ?
                        {25'd0, resume_checkpoint[262:256]} : 32'd0;
                    child_error_hold <= 0;
                    error_hold <= 0;
                    state <= VALIDATE;
                end
                VALIDATE: begin
                    if ((model_hold != 1 && model_hold != 2) || precision_hold > 1) begin
                        error_hold <= 6;
                        state <= PUBLISH;
                    end else if (generation_hold == 0 || frames_hold == 0 || frames_hold > 131072 ||
                        query_hold >= tokens_hold || layer_hold >= 12 ||
                        audio_hold[1:0] != 0 || weights_hold[1:0] != 0) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else
                        state <= HEAD_START;
                end
                HEAD_START: if (head_ready)
                    state <= HEAD_RUN;
                HEAD_RUN: if (head_valid && service_idle) begin
                    child_error_hold <= head_error;
                    yield_hold <= head_yield;
                    state <= HEAD_CHECK;
                end
                HEAD_CHECK: begin
                    if (first_service_error != 0)
                        error_hold <= first_service_error;
                    else if (child_error_hold != 0)
                        error_hold <= child_error_hold;
                    else if (receive_bad || (!yield_hold && received != 128))
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
