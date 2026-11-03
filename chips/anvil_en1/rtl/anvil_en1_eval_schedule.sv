module anvil_en1_eval_schedule #(
    parameter integer COMPACT = 0
) (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] model, precision, modality, domain,
    input wire [31:0] generation, tokens, token,
    input wire [7:0] layer,
    input wire [63:0] tokens_base, weights_base,
    output wire task_valid,
    input wire task_ready,
    output wire [1:0] task_model, task_precision, task_modality, task_domain,
    output wire [1:0] task_mode,
    output wire [31:0] task_generation, task_tokens, task_token,
    output wire [7:0] task_layer,
    output wire [11:0] task_length,
    output wire [5:0] task_frame,
    output wire [63:0] task_tokens_base, task_weights_base,
    output wire [159:0] task_continuation,
    output wire task_dependency_valid,
    output wire [1:0] task_dependency_domain,
    output wire [7:0] task_dependency_layer,
    output wire [31:0] task_dependency_token,
    output wire [11:0] task_dependency_length,
    output wire [5:0] task_dependency_slot,
    input wire task_done_valid,
    output wire task_done_ready,
    input wire [3:0] task_done_error,
    input wire task_done_dependency, task_done_bank,
    input wire [1:0] task_done_dependency_domain,
    input wire [7:0] task_done_dependency_layer,
    input wire [31:0] task_done_dependency_token,
    input wire [11:0] task_done_dependency_length,
    input wire [159:0] task_done_continuation,
    input wire work_req_valid,
    output wire work_req_ready,
    input wire [2:0] work_req_op,
    input wire [1:0] work_req_domain, work_req_target,
    input wire [31:0] work_req_token,
    input wire [7:0] work_req_layer,
    input wire [11:0] work_req_length, work_req_component,
    input wire [5:0] work_req_slot,
    input wire work_req_bank,
    input wire [7:0] work_req_scalar_index,
    input wire [31:0] work_req_data,
    input wire work_write_valid,
    output wire work_write_ready,
    input wire [31:0] work_write_data,
    input wire work_write_first, work_write_last,
    input wire work_write_abort,
    output wire work_rsp_valid,
    input wire work_rsp_ready,
    output wire [3:0] work_rsp_error,
    output wire [31:0] work_rsp_data,
    output wire output_valid,
    input wire output_ready,
    output wire [31:0] output_index,
    output wire [15:0] output_data,
    output wire output_last,
    output wire done_valid,
    input wire done_ready,
    output wire [3:0] done_error,
    output wire [6:0] frame_depth,
    output wire [63:0] scheduler_state_bytes,
    output wire [63:0] workspace_controller_bytes,
    output wire [63:0] live_payload_bytes, production_shadow_bytes,
    output wire [63:0] native_payload_bytes, native_production_shadow_bytes,
    output wire [63:0] backing_reserved_bytes, visibility_metadata_bytes,
    output wire grant_valid,
    input wire grant_ready,
    output wire [4:0] grant_component,
    output wire [63:0] grant_payload_bytes, grant_shadow_bytes,
    output wire [63:0] grant_native_bytes, grant_native_shadow_bytes,
    input wire grant_rsp_valid,
    output wire grant_rsp_ready,
    input wire grant_allowed,
    output wire memo_hit_event, memo_eviction_event,
    output wire backing_valid,
    input wire backing_ready,
    output wire [31:0] backing_generation,
    output wire backing_write,
    output wire [17:0] backing_addr,
    output wire [31:0] backing_wdata,
    input wire backing_rsp_valid,
    output wire backing_rsp_ready,
    input wire [31:0] backing_rsp_data,
    input wire [3:0] backing_rsp_error,
    output wire busy
);
    localparam [5:0] IDLE = 0, VALIDATE = 1, BIND_SEND = 2,
        BIND_WAIT = 3, LOOKUP_SETUP = 4, WS_SEND = 5, WS_WAIT = 6,
        PUSH_SETUP = 7, PUSH_RESULT = 8, TASK_START = 9, TASK_WAIT = 10,
        DEP_VALIDATE = 11, LOOKUP_RESULT = 12, COPY_SETUP = 13,
        COPY_RESULT = 14, POP_SETUP = 15, POP_RESULT = 16,
        AFTER_POP = 17, OUTPUT_SETUP = 18, OUTPUT_CAPTURE = 19,
        OUTPUT_LOW = 20, OUTPUT_HIGH = 21,
        INVALIDATE_SEND = 22, INVALIDATE_WAIT = 23,
        PUBLISH = 24, RESPONSE = 25;
    localparam [31:0] RETURN_MAGIC = 32'h454e3152;
    reg [5:0] state, ws_return;
    reg [1:0] model_hold, precision_hold, modality_hold, root_domain;
    reg [31:0] generation_hold, tokens_hold, root_token;
    reg [7:0] root_layer;
    reg [63:0] tokens_base_hold, weights_base_hold;
    reg [1:0] current_domain, mode_hold, dependency_domain, push_kind;
    reg [7:0] current_layer, dependency_layer;
    reg [31:0] current_token, dependency_token;
    reg [11:0] current_length, dependency_length;
    reg [5:0] current_frame, dependency_slot;
    reg [159:0] continuation_hold;
    reg dependency_valid_hold, lookup_dependency, linear_hold, result_bank;
    reg [1:0] completed_domain;
    reg [7:0] completed_layer;
    reg [31:0] completed_token;
    reg [11:0] completed_length;
    reg [5:0] completed_slot;
    reg [31:0] output_component, output_pair;
    reg [3:0] error_hold, worker_error;
    reg pass_busy, pass_invalid;
    reg [2:0] ws_op;
    reg [1:0] ws_domain, ws_target;
    reg [31:0] ws_token, ws_data;
    reg [7:0] ws_layer, ws_scalar_index;
    reg [11:0] ws_length, ws_component;
    reg [5:0] ws_slot;
    reg ws_bank;
    reg [255:0] ws_continuation;
    reg ws_hit_hold;
    reg [5:0] ws_response_slot;
    reg [31:0] ws_response_data;
    reg [255:0] ws_response_continuation;
    reg [1:0] ws_response_domain;
    reg [31:0] ws_response_token;
    reg [7:0] ws_response_layer;
    reg [11:0] ws_response_length;

    initial begin
        if (COMPACT != 0 && COMPACT != 1)
            $fatal(1, "PARAMETER ERROR: COMPACT must be 0 or 1");
    end

    wire native_model = model_hold == 1 || model_hold == 2;
    wire [7:0] text_layers = model_hold == 1 ? 8'd35 : 8'd42;
    wire [11:0] text_length = COMPACT ? 12'd8 :
        (model_hold == 1 ? 12'd1536 : 12'd2560);
    wire [11:0] root_length =
        (root_domain == 0 || root_domain == 3 ? text_length :
        (root_domain == 1 ? 12'd768 : 12'd1024));
    wire [11:0] selected_dependency_length =
        (dependency_domain == 0 || dependency_domain == 3 ? text_length :
        (dependency_domain == 1 ? 12'd768 : 12'd1024));
    wire root_valid =
        (root_domain == 0 || root_domain == 3 ? root_token < tokens_hold : root_token <= 131071) &&
        (root_domain == 3 ? (root_layer == 1 || root_layer == 2) :
        (root_domain == 0 ? root_layer <= text_layers :
        (root_domain == 1 ? root_layer <= 16 : root_layer <= 12)));
    wire [64:0] tokens_end = {1'b0, tokens_base_hold} +
        {31'd0, tokens_hold, 2'd0} - 65'd1;
    wire [6:0] current_rank = current_domain == 0 ?
        {1'b0, current_layer[5:0]} + 7'd19 :
        (current_domain == 3 ? 7'd18 : {1'b0, current_layer[5:0]} + 7'd1);
    wire [6:0] dependency_rank = dependency_domain == 0 ?
        {1'b0, dependency_layer[5:0]} + 7'd19 :
        (dependency_domain == 3 ? 7'd18 : {1'b0, dependency_layer[5:0]} + 7'd1);
    wire dependency_descriptor_valid =
        (dependency_domain == 0 || dependency_domain == 3 ? dependency_token < tokens_hold :
            dependency_token <= 131071) &&
        dependency_length == selected_dependency_length &&
        (dependency_domain == 3 ? (dependency_layer == 1 || dependency_layer == 2) :
        (dependency_domain == 0 ? dependency_layer <= text_layers :
        (dependency_domain == 1 ? dependency_layer <= 16 :
            dependency_layer <= 12)));
    wire [255:0] return_record = {RETURN_MAGIC, current_domain, current_layer,
        current_token, current_length, current_frame, 4'd0, continuation_hold};
    wire parent_record_valid = ws_response_continuation[255:224] == RETURN_MAGIC &&
        ws_response_continuation[163:160] == 0 &&
        ws_response_continuation[169:164] ==
            (frame_depth[5:0] - 6'd1);
    wire current_work_tag = work_req_domain == current_domain &&
        work_req_layer == current_layer && work_req_token == current_token &&
        work_req_length == current_length && work_req_slot == current_frame;
    wire dependency_work_tag = dependency_valid_hold &&
        work_req_domain == dependency_domain &&
        work_req_layer == dependency_layer && work_req_token == dependency_token &&
        work_req_length == dependency_length && work_req_slot == dependency_slot;
    wire dependency_copy_tag = dependency_valid_hold &&
        dependency_domain == current_domain && dependency_length == current_length &&
        dependency_layer < current_layer && dependency_slot < 16 &&
        work_req_data == {dependency_slot, dependency_layer, dependency_token[17:0]};
    wire work_operation_valid =
        (work_req_op == 3 && work_req_target == 0 && current_work_tag) ||
        (work_req_op == 3 && work_req_target == 3 && current_work_tag &&
            dependency_copy_tag) ||
        (work_req_op == 4 &&
            ((work_req_target == 0 && current_work_tag) ||
             (work_req_target == 1 && dependency_work_tag))) ||
        ((work_req_op == 6 || work_req_op == 7) &&
            work_req_target == 0 && current_work_tag && work_req_scalar_index >= 8) ||
        (work_req_op == 7 && work_req_target == 1 && current_work_tag) ||
        (work_req_op == 7 && work_req_target == 2 && current_work_tag) ||
        (work_req_op == 6 && work_req_target >= 2 && current_work_tag);
    wire pass_request = rst_n && state == TASK_WAIT && !pass_busy &&
        !task_done_valid && work_req_valid;
    wire scheduler_request = rst_n && state == WS_SEND;
    wire ws_ready, ws_valid, ws_write_ready;
    wire [3:0] ws_error, ws_control_error;
    wire ws_control_ready, ws_control_valid, ws_hit;
    wire [5:0] ws_result_slot;
    wire [31:0] ws_result_data, ws_result_token;
    wire [255:0] ws_result_continuation;
    wire [1:0] ws_result_domain, ws_result_model;
    wire [31:0] ws_result_generation;
    wire [7:0] ws_result_layer;
    wire [11:0] ws_result_length;
    anvil_en1_replay_workspace #(.COMPACT(COMPACT)) workspace (
        .clk(clk), .rst_n(rst_n),
        .grant_valid(grant_valid), .grant_ready(grant_ready),
        .grant_component(grant_component),
        .grant_payload_bytes(grant_payload_bytes), .grant_shadow_bytes(grant_shadow_bytes),
        .grant_native_bytes(grant_native_bytes),
        .grant_native_shadow_bytes(grant_native_shadow_bytes),
        .grant_rsp_valid(grant_rsp_valid), .grant_rsp_ready(grant_rsp_ready),
        .grant_allowed(grant_allowed),
        .memo_pin_valid((dependency_valid_hold &&
            (state == TASK_START || state == TASK_WAIT)) ||
            (push_kind == 2 &&
            (state == PUSH_SETUP || state == WS_SEND ||
             state == WS_WAIT || state == PUSH_RESULT))),
        .memo_pin_slot(dependency_slot[3:0]),
        .control_valid(rst_n &&
            (state == BIND_SEND || state == INVALIDATE_SEND)),
        .control_ready(ws_control_ready),
        .control_invalidate(state == INVALIDATE_SEND),
        .control_model(model_hold), .control_generation(generation_hold),
        .control_tokens(tokens_hold),
        .control_rsp_valid(ws_control_valid),
        .control_rsp_ready(rst_n &&
            (state == BIND_WAIT || state == INVALIDATE_WAIT)),
        .control_error(ws_control_error),
        .req_valid(scheduler_request || (pass_request && work_operation_valid)),
        .req_ready(ws_ready),
        .req_op(scheduler_request ? ws_op : work_req_op),
        .req_model(model_hold),
        .req_domain(scheduler_request ? ws_domain : work_req_domain),
        .req_target(scheduler_request ? ws_target : work_req_target),
        .req_generation(generation_hold),
        .req_token(scheduler_request ? ws_token : work_req_token),
        .req_layer(scheduler_request ? ws_layer : work_req_layer),
        .req_length(scheduler_request ? ws_length : work_req_length),
        .req_component(scheduler_request ? ws_component : work_req_component),
        .req_slot(scheduler_request ? ws_slot : work_req_slot),
        .req_bank(scheduler_request ? ws_bank : work_req_bank),
        .req_scalar_index(scheduler_request ? ws_scalar_index : work_req_scalar_index),
        .req_data(scheduler_request ? ws_data : work_req_data),
        .req_continuation(scheduler_request ? ws_continuation : 256'd0),
        .write_valid(rst_n && pass_busy && !pass_invalid && work_write_valid),
        .write_ready(ws_write_ready), .write_data(work_write_data),
        .write_first(work_write_first), .write_last(work_write_last),
        .write_abort(work_write_abort),
        .rsp_valid(ws_valid),
        .rsp_ready(rst_n && (state == WS_WAIT ||
            (pass_busy && !pass_invalid && work_rsp_ready))),
        .rsp_error(ws_error), .rsp_hit(ws_hit),
        .rsp_slot(ws_result_slot), .rsp_data(ws_result_data),
        .rsp_continuation(ws_result_continuation),
        .rsp_model(ws_result_model), .rsp_domain(ws_result_domain),
        .rsp_generation(ws_result_generation), .rsp_token(ws_result_token),
        .rsp_layer(ws_result_layer), .rsp_length(ws_result_length),
        .frame_depth(frame_depth), .live_payload_bytes(live_payload_bytes),
        .production_shadow_bytes(production_shadow_bytes),
        .native_payload_bytes(native_payload_bytes),
        .native_production_shadow_bytes(native_production_shadow_bytes),
        .backing_reserved_bytes(backing_reserved_bytes),
        .visibility_metadata_bytes(visibility_metadata_bytes),
        .controller_bytes(workspace_controller_bytes),
        .memo_hit_event(memo_hit_event), .memo_eviction_event(memo_eviction_event),
        .backing_valid(backing_valid), .backing_ready(backing_ready),
        .backing_generation(backing_generation), .backing_write(backing_write),
        .backing_addr(backing_addr), .backing_wdata(backing_wdata),
        .backing_rsp_valid(backing_rsp_valid),
        .backing_rsp_ready(backing_rsp_ready),
        .backing_rsp_data(backing_rsp_data), .backing_rsp_error(backing_rsp_error)
    );

    assign start_ready = rst_n && state == IDLE;
    assign task_valid = rst_n && state == TASK_START;
    assign task_model = rst_n ? model_hold : 2'd0;
    assign task_precision = rst_n ? precision_hold : 2'd0;
    assign task_modality = rst_n ? modality_hold : 2'd0;
    assign task_domain = rst_n ? current_domain : 2'd0;
    assign task_mode = rst_n ? mode_hold : 2'd0;
    assign task_generation = rst_n ? generation_hold : 32'd0;
    assign task_tokens = rst_n ? tokens_hold : 32'd0;
    assign task_token = rst_n ? current_token : 32'd0;
    assign task_layer = rst_n ? current_layer : 8'd0;
    assign task_length = rst_n ? current_length : 12'd0;
    assign task_frame = rst_n ? current_frame : 6'd0;
    assign task_tokens_base = rst_n ? tokens_base_hold : 64'd0;
    assign task_weights_base = rst_n ? weights_base_hold : 64'd0;
    assign task_continuation = rst_n ? continuation_hold : 160'd0;
    assign task_dependency_valid = rst_n && dependency_valid_hold;
    assign task_dependency_domain = rst_n ? dependency_domain : 2'd0;
    assign task_dependency_layer = rst_n ? dependency_layer : 8'd0;
    assign task_dependency_token = rst_n ? dependency_token : 32'd0;
    assign task_dependency_length = rst_n ? dependency_length : 12'd0;
    assign task_dependency_slot = rst_n ? dependency_slot : 6'd0;
    assign task_done_ready = rst_n && state == TASK_WAIT && !pass_busy &&
        !work_req_valid;
    assign work_req_ready = rst_n && state == TASK_WAIT && !pass_busy &&
        !task_done_valid && (!work_operation_valid || ws_ready);
    assign work_write_ready = rst_n && pass_busy && !pass_invalid && ws_write_ready;
    assign work_rsp_valid = rst_n && pass_busy && (pass_invalid || ws_valid);
    assign work_rsp_error = !rst_n ? 4'd0 :
        (pass_invalid ? 4'd7 : ws_error);
    assign work_rsp_data = rst_n && !pass_invalid ? ws_result_data : 32'd0;
    assign output_valid = rst_n && (state == OUTPUT_LOW || state == OUTPUT_HIGH);
    assign output_index = !rst_n ? 32'd0 :
        (state == OUTPUT_HIGH ? output_component + 1'b1 : output_component);
    assign output_data = !rst_n ? 16'd0 :
        (state == OUTPUT_HIGH ? output_pair[31:16] : output_pair[15:0]);
    assign output_last = rst_n && state == OUTPUT_HIGH &&
        output_component + 32'd2 == {20'd0, completed_length};
    assign done_valid = rst_n && state == RESPONSE;
    assign done_error = rst_n ? error_hold : 4'd0;
    assign busy = rst_n && state != IDLE;
    localparam integer SCHEDULER_BITS =
        $bits(state) + $bits(ws_return) + $bits(model_hold) + $bits(precision_hold) +
        $bits(modality_hold) + $bits(root_domain) + $bits(generation_hold) +
        $bits(tokens_hold) + $bits(root_token) + $bits(root_layer) +
        $bits(tokens_base_hold) + $bits(weights_base_hold) + $bits(current_domain) +
        $bits(mode_hold) + $bits(dependency_domain) + $bits(push_kind) +
        $bits(current_layer) + $bits(dependency_layer) + $bits(current_token) +
        $bits(dependency_token) + $bits(current_length) + $bits(dependency_length) +
        $bits(current_frame) + $bits(dependency_slot) + $bits(continuation_hold) +
        $bits(dependency_valid_hold) + $bits(lookup_dependency) + $bits(linear_hold) +
        $bits(result_bank) + $bits(completed_domain) + $bits(completed_layer) +
        $bits(completed_token) + $bits(completed_length) + $bits(completed_slot) +
        $bits(output_component) + $bits(output_pair) + $bits(error_hold) +
        $bits(worker_error) + $bits(pass_busy) + $bits(pass_invalid) + $bits(ws_op) +
        $bits(ws_domain) + $bits(ws_target) + $bits(ws_token) + $bits(ws_data) +
        $bits(ws_layer) + $bits(ws_scalar_index) + $bits(ws_length) +
        $bits(ws_component) + $bits(ws_slot) + $bits(ws_bank) +
        $bits(ws_continuation) + $bits(ws_hit_hold) + $bits(ws_response_slot) +
        $bits(ws_response_data) + $bits(ws_response_continuation) +
        $bits(ws_response_domain) + $bits(ws_response_token) +
        $bits(ws_response_layer) + $bits(ws_response_length);
    assign scheduler_state_bytes = rst_n ? 64'((SCHEDULER_BITS+7) >> 3) : 64'd0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            ws_return <= 0;
            model_hold <= 0;
            precision_hold <= 0;
            modality_hold <= 0;
            root_domain <= 0;
            generation_hold <= 0;
            tokens_hold <= 0;
            root_token <= 0;
            root_layer <= 0;
            tokens_base_hold <= 0;
            weights_base_hold <= 0;
            current_domain <= 0;
            mode_hold <= 0;
            dependency_domain <= 0;
            push_kind <= 0;
            current_layer <= 0;
            dependency_layer <= 0;
            current_token <= 0;
            dependency_token <= 0;
            current_length <= 0;
            dependency_length <= 0;
            current_frame <= 0;
            dependency_slot <= 0;
            continuation_hold <= 0;
            dependency_valid_hold <= 0;
            lookup_dependency <= 0;
            linear_hold <= 0;
            result_bank <= 0;
            completed_domain <= 0;
            completed_layer <= 0;
            completed_token <= 0;
            completed_length <= 0;
            completed_slot <= 0;
            output_component <= 0;
            output_pair <= 0;
            error_hold <= 0;
            worker_error <= 0;
            pass_busy <= 0;
            pass_invalid <= 0;
            ws_op <= 0;
            ws_domain <= 0;
            ws_target <= 0;
            ws_token <= 0;
            ws_data <= 0;
            ws_layer <= 0;
            ws_scalar_index <= 0;
            ws_length <= 0;
            ws_component <= 0;
            ws_slot <= 0;
            ws_bank <= 0;
            ws_continuation <= 0;
            ws_hit_hold <= 0;
            ws_response_slot <= 0;
            ws_response_data <= 0;
            ws_response_continuation <= 0;
            ws_response_domain <= 0;
            ws_response_token <= 0;
            ws_response_layer <= 0;
            ws_response_length <= 0;
        end else begin
            if (work_req_valid && work_req_ready) begin
                pass_busy <= 1;
                pass_invalid <= !work_operation_valid;
            end
            if (work_rsp_valid && work_rsp_ready) begin
                pass_busy <= 0;
                pass_invalid <= 0;
                if (work_rsp_error != 0)
                    worker_error <= work_rsp_error;
            end
            case (state)
                IDLE: if (start_valid && start_ready) begin
                    model_hold <= model;
                    precision_hold <= precision;
                    modality_hold <= modality;
                    root_domain <= domain;
                    generation_hold <= generation;
                    tokens_hold <= tokens;
                    root_token <= token;
                    root_layer <= layer;
                    tokens_base_hold <= tokens_base;
                    weights_base_hold <= weights_base;
                    error_hold <= 0;
                    worker_error <= 0;
                    output_component <= 0;
                    output_pair <= 0;
                    continuation_hold <= 0;
                    dependency_valid_hold <= 0;
                    lookup_dependency <= 0;
                    pass_busy <= 0;
                    pass_invalid <= 0;
                    state <= VALIDATE;
                end
                VALIDATE: begin
                    if (!native_model || precision_hold > 1) begin
                        error_hold <= 6;
                        state <= INVALIDATE_SEND;
                    end else if (tokens_hold == 0 || tokens_hold > 131072 ||
                        !root_valid || tokens_base_hold[1:0] != 0 ||
                        weights_base_hold[1:0] != 0 || tokens_end[64]) begin
                        error_hold <= 5;
                        state <= INVALIDATE_SEND;
                    end else begin
                        current_domain <= root_domain;
                        current_token <= root_token;
                        current_length <= root_length;
                        linear_hold <= root_domain == 0 && tokens_hold == 1 &&
                            root_token == 0;
                        if (root_domain == 0 && tokens_hold == 1 && root_token == 0)
                            current_layer <= 0;
                        else
                            current_layer <= root_layer;
                        mode_hold <= 0;
                        push_kind <= 0;
                        state <= BIND_SEND;
                    end
                end
                BIND_SEND: if (ws_control_ready)
                    state <= BIND_WAIT;
                BIND_WAIT: if (ws_control_valid) begin
                    if (ws_control_error != 0) begin
                        error_hold <= ws_control_error;
                        state <= INVALIDATE_SEND;
                    end else
                        state <= LOOKUP_SETUP;
                end
                LOOKUP_SETUP: begin
                    ws_op <= 5;
                    ws_target <= 1;
                    ws_domain <= lookup_dependency ? dependency_domain : current_domain;
                    ws_layer <= lookup_dependency ? dependency_layer : current_layer;
                    ws_token <= lookup_dependency ? dependency_token : current_token;
                    ws_length <= lookup_dependency ? dependency_length : current_length;
                    ws_slot <= 0;
                    ws_bank <= 0;
                    ws_component <= 0;
                    ws_scalar_index <= 0;
                    ws_data <= 0;
                    ws_continuation <= 0;
                    ws_return <= LOOKUP_RESULT;
                    state <= WS_SEND;
                end
                WS_SEND: if (ws_ready)
                    state <= WS_WAIT;
                WS_WAIT: if (ws_valid) begin
                    if (ws_error != 0) begin
                        error_hold <= ws_error;
                        state <= INVALIDATE_SEND;
                    end else if (ws_result_model != model_hold ||
                        ws_result_generation != generation_hold) begin
                        error_hold <= 7;
                        state <= INVALIDATE_SEND;
                    end else begin
                        ws_hit_hold <= ws_hit;
                        ws_response_slot <= ws_result_slot;
                        ws_response_data <= ws_result_data;
                        ws_response_continuation <= ws_result_continuation;
                        ws_response_domain <= ws_result_domain;
                        ws_response_token <= ws_result_token;
                        ws_response_layer <= ws_result_layer;
                        ws_response_length <= ws_result_length;
                        state <= ws_return;
                    end
                end
                LOOKUP_RESULT: begin
                    if (lookup_dependency) begin
                        if (ws_hit_hold) begin
                            dependency_slot <= ws_response_slot;
                            dependency_valid_hold <= 1;
                            mode_hold <= 1;
                            state <= TASK_START;
                        end else begin
                            push_kind <= 1;
                            state <= PUSH_SETUP;
                        end
                    end else if (ws_hit_hold) begin
                        completed_domain <= current_domain;
                        completed_layer <= current_layer;
                        completed_token <= current_token;
                        completed_length <= current_length;
                        completed_slot <= ws_response_slot;
                        state <= OUTPUT_SETUP;
                    end else begin
                        push_kind <= 0;
                        state <= PUSH_SETUP;
                    end
                end
                PUSH_SETUP: begin
                    ws_op <= 0;
                    ws_target <= 0;
                    ws_domain <= push_kind == 1 ? dependency_domain : current_domain;
                    ws_layer <= push_kind == 1 ? dependency_layer : current_layer;
                    ws_token <= push_kind == 1 ? dependency_token : current_token;
                    ws_length <= push_kind == 1 ? dependency_length : current_length;
                    ws_slot <= 0;
                    ws_bank <= 0;
                    ws_component <= 0;
                    ws_scalar_index <= 0;
                    ws_data <= 0;
                    ws_continuation <= push_kind == 1 ? return_record : 256'd0;
                    ws_return <= PUSH_RESULT;
                    state <= WS_SEND;
                end
                PUSH_RESULT: begin
                    current_domain <= ws_domain;
                    current_layer <= ws_layer;
                    current_token <= ws_token;
                    current_length <= ws_length;
                    current_frame <= ws_response_slot;
                    if (push_kind == 2) begin
                        mode_hold <= 2;
                        dependency_valid_hold <= 1;
                    end else begin
                        mode_hold <= 0;
                        dependency_valid_hold <= 0;
                    end
                    continuation_hold <= 0;
                    state <= TASK_START;
                end
                TASK_START: if (task_ready) begin
                    worker_error <= 0;
                    state <= TASK_WAIT;
                end
                TASK_WAIT: if (task_done_valid && task_done_ready) begin
                    if (task_done_error != 0 || worker_error != 0) begin
                        if (task_done_error != 0)
                            error_hold <= task_done_error;
                        else
                            error_hold <= worker_error;
                        state <= INVALIDATE_SEND;
                    end else if (task_done_dependency) begin
                        dependency_domain <= task_done_dependency_domain;
                        dependency_layer <= task_done_dependency_layer;
                        dependency_token <= task_done_dependency_token;
                        dependency_length <= task_done_dependency_length;
                        continuation_hold <= task_done_continuation;
                        dependency_valid_hold <= 0;
                        lookup_dependency <= 1;
                        state <= DEP_VALIDATE;
                    end else begin
                        result_bank <= task_done_bank;
                        state <= COPY_SETUP;
                    end
                end
                DEP_VALIDATE: begin
                    if (!dependency_descriptor_valid || dependency_rank >= current_rank) begin
                        error_hold <= 7;
                        state <= INVALIDATE_SEND;
                    end else
                        state <= LOOKUP_SETUP;
                end
                COPY_SETUP: begin
                    ws_op <= 3;
                    ws_target <= 2;
                    ws_domain <= current_domain;
                    ws_layer <= current_layer;
                    ws_token <= current_token;
                    ws_length <= current_length;
                    ws_slot <= current_frame;
                    ws_bank <= result_bank;
                    ws_component <= 0;
                    ws_scalar_index <= 0;
                    ws_data <= 0;
                    ws_continuation <= 0;
                    ws_return <= COPY_RESULT;
                    state <= WS_SEND;
                end
                COPY_RESULT: begin
                    completed_domain <= current_domain;
                    completed_layer <= current_layer;
                    completed_token <= current_token;
                    completed_length <= current_length;
                    completed_slot <= ws_response_slot;
                    state <= POP_SETUP;
                end
                POP_SETUP: begin
                    ws_op <= 1;
                    ws_target <= 0;
                    ws_domain <= current_domain;
                    ws_layer <= current_layer;
                    ws_token <= current_token;
                    ws_length <= current_length;
                    ws_slot <= current_frame;
                    ws_bank <= 0;
                    ws_component <= 0;
                    ws_scalar_index <= 0;
                    ws_data <= 0;
                    ws_continuation <= 0;
                    ws_return <= POP_RESULT;
                    state <= WS_SEND;
                end
                POP_RESULT: begin
                    if (ws_response_slot != current_frame ||
                        ws_response_domain != current_domain ||
                        ws_response_layer != current_layer ||
                        ws_response_token != current_token ||
                        ws_response_length != current_length) begin
                        error_hold <= 7;
                        state <= INVALIDATE_SEND;
                    end else
                        state <= AFTER_POP;
                end
                AFTER_POP: begin
                    if (frame_depth == 0) begin
                        if (linear_hold && current_layer < root_layer) begin
                            dependency_domain <= current_domain;
                            dependency_layer <= current_layer;
                            dependency_token <= current_token;
                            dependency_length <= current_length;
                            dependency_slot <= completed_slot;
                            current_layer <= current_layer + 1'b1;
                            push_kind <= 2;
                            lookup_dependency <= 0;
                            state <= PUSH_SETUP;
                        end else
                            state <= OUTPUT_SETUP;
                    end else if (!parent_record_valid) begin
                        error_hold <= 7;
                        state <= INVALIDATE_SEND;
                    end else begin
                        current_domain <= ws_response_continuation[223:222];
                        current_layer <= ws_response_continuation[221:214];
                        current_token <= ws_response_continuation[213:182];
                        current_length <= ws_response_continuation[181:170];
                        current_frame <= ws_response_continuation[169:164];
                        continuation_hold <= ws_response_continuation[159:0];
                        dependency_domain <= completed_domain;
                        dependency_layer <= completed_layer;
                        dependency_token <= completed_token;
                        dependency_length <= completed_length;
                        dependency_slot <= completed_slot;
                        dependency_valid_hold <= 1;
                        mode_hold <= 1;
                        state <= TASK_START;
                    end
                end
                OUTPUT_SETUP: begin
                    ws_op <= 4;
                    ws_target <= 1;
                    ws_domain <= completed_domain;
                    ws_layer <= completed_layer;
                    ws_token <= completed_token;
                    ws_length <= completed_length;
                    ws_slot <= completed_slot;
                    ws_bank <= 0;
                    ws_component <= output_component[11:0];
                    ws_scalar_index <= 0;
                    ws_data <= 0;
                    ws_continuation <= 0;
                    ws_return <= OUTPUT_CAPTURE;
                    state <= WS_SEND;
                end
                OUTPUT_CAPTURE: begin
                    output_pair <= ws_response_data;
                    state <= OUTPUT_LOW;
                end
                OUTPUT_LOW: if (output_ready)
                    state <= OUTPUT_HIGH;
                OUTPUT_HIGH: if (output_ready) begin
                    if (output_last)
                        state <= INVALIDATE_SEND;
                    else begin
                        output_component <= output_component + 32'd2;
                        state <= OUTPUT_SETUP;
                    end
                end
                INVALIDATE_SEND: if (ws_control_ready)
                    state <= INVALIDATE_WAIT;
                INVALIDATE_WAIT: if (ws_control_valid) begin
                    if (ws_control_error != 0)
                        error_hold <= ws_control_error;
                    state <= PUBLISH;
                end
                PUBLISH: state <= RESPONSE;
                RESPONSE: if (done_ready)
                    state <= IDLE;
                default: begin
                    error_hold <= 7;
                    state <= INVALIDATE_SEND;
                end
            endcase
        end
    end
endmodule
