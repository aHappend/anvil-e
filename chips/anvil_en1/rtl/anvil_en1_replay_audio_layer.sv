module anvil_en1_replay_audio_layer #(
    parameter integer COMPACT = 0,
    parameter integer EXTERNAL_VECTOR_RAM = 0
) (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] model, precision, mode,
    input wire [31:0] generation, frames, query_token,
    input wire [7:0] frame_layer,
    input wire [5:0] frame_slot,
    input wire [63:0] audio_base, audio_weights_base,
    input wire [159:0] continuation,
    input wire dependency_valid,
    input wire [1:0] dependency_domain,
    input wire [7:0] dependency_layer,
    input wire [31:0] dependency_token,
    input wire [11:0] dependency_length,
    input wire [5:0] dependency_slot,
    output wire work_req_valid,
    input wire work_req_ready,
    output reg [2:0] work_req_op,
    output reg [1:0] work_req_domain, work_req_target,
    output reg [31:0] work_req_token,
    output reg [7:0] work_req_layer,
    output reg [11:0] work_req_length, work_req_component,
    output reg [5:0] work_req_slot,
    output reg work_req_bank,
    output reg [7:0] work_req_scalar_index,
    output reg [31:0] work_req_data,
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
    output wire [3:0] done_error,
    output wire done_yield, done_bank,
    output wire [159:0] done_continuation,
    output wire [1:0] done_dependency_domain,
    output wire [7:0] done_dependency_layer,
    output wire [31:0] done_dependency_token,
    output wire [11:0] done_dependency_length,
    output wire input_read_event, projection_event, intermediate_event,
    output wire source_read_event, weight_read_event, history_replay_event, glu_replay_event,
    output wire [31:0] input_read_bytes, projection_bytes, intermediate_bytes,
    output wire [31:0] source_read_bytes, weight_read_bytes, history_replay_bytes, glu_replay_bytes,
    output wire [63:0] vector_live_bytes, vector_physical_bytes,
    output wire [2:0] vector_ram_write, vector_ram_read,
    output wire [95:0] vector_ram_waddr, vector_ram_raddr,
    output wire [47:0] vector_ram_wdata,
    input wire [47:0] vector_ram_rdata,
    output wire [63:0] controller_bytes, nested_controller_bytes
);
    localparam [4:0] IDLE = 0, VALIDATE = 1, HISTORY_START = 2,
        HISTORY_WAIT = 3, HISTORY_CHECK = 4, CONV_START = 5, CONV_WAIT = 6,
        CONV_CHECK = 7, FF_START = 8, FF_WAIT = 9, FF_CHECK = 10,
        CLAMP_START = 11, CLAMP_WAIT = 12, CLAMP_REGISTER = 13,
        NORM_START = 14, NORM_WAIT = 15, NORM_CHECK = 16,
        PAIR_SEND = 17, PAIR_WAIT = 18, PAIR_REGISTER = 19,
        PUBLISH = 20, RESPONSE = 21, RELEASE_SEND = 22,
        RELEASE_WAIT = 23, RELEASE_REGISTER = 24;
    localparam [2:0] S_IDLE = 0, S_VALIDATE = 1, S_SEND = 2,
        S_WAIT = 3, S_REGISTER = 4, S_RESPONSE = 5;
    reg [4:0] state;
    reg [2:0] source_state;
    reg [1:0] model_hold, precision_hold, mode_hold, phase_hold;
    reg [1:0] dependency_domain_hold, yielded_domain, source_slice_hold;
    reg [31:0] generation_hold, frames_hold, query_hold, dependency_token_hold;
    reg [31:0] yielded_token, received, pair_hold, source_index_hold, source_token_hold;
    reg [31:0] source_pair_hold;
    reg [7:0] layer_hold, dependency_layer_hold, yielded_layer;
    reg [5:0] slot_hold, dependency_slot_hold;
    reg [11:0] dependency_length_hold, yielded_length;
    reg [2:0] history_count_hold;
    reg [63:0] audio_hold, weights_hold;
    reg [159:0] continuation_hold, yielded_continuation;
    reg dependency_valid_hold, child_yield_hold, yield_hold;
    reg source_bank_hold, source_bad;
    reg [15:0] low_hold, clamp_input_hold, clamp_data_hold, source_data_hold;
    reg [3:0] error_hold, child_error_hold, work_error_hold;
    reg [3:0] source_error_hold, first_source_error;
    reg vector_ram_fault;
    reg [1:0] vector_owner;

    initial begin
        if (COMPACT != 0 && COMPACT != 1)
            $fatal(1, "PARAMETER ERROR: COMPACT must be 0 or 1");
        if (EXTERNAL_VECTOR_RAM != 0 && EXTERNAL_VECTOR_RAM != 1)
            $fatal(1, "PARAMETER ERROR: EXTERNAL_VECTOR_RAM must be 0 or 1");
    end
    wire [7:0] logical_layer = layer_hold - 1'b1;
    wire [31:0] tokens_hold = (frames_hold + 32'd3) >> 2;
    wire [2:0] last_distance = query_hold < 4 ? query_hold[2:0] : 3'd4;
    wire history_selected = rst_n && (state == HISTORY_START || state == HISTORY_WAIT);
    wire history_ready, history_valid, history_yield, history_work_valid;
    wire history_work_rsp_ready, history_cmd_valid, history_result_ready;
    wire [3:0] history_error;
    wire [2:0] history_count, history_op;
    wire [159:0] history_continuation;
    wire [1:0] history_dependency_domain, history_domain, history_target;
    wire [7:0] history_dependency_layer, history_layer, history_scalar;
    wire [31:0] history_dependency_token, history_token, history_data;
    wire [11:0] history_dependency_length, history_length, history_component;
    wire [5:0] history_slot;
    wire history_work_bank;
    wire [63:0] history_addr, history_live, history_physical, history_control, history_nested;
    wire history_input_event, history_projection_event, history_intermediate_event;
    wire history_source_event, history_weight_event;
    wire [31:0] history_input_bytes, history_projection_bytes, history_intermediate_bytes;
    wire [31:0] history_source_bytes, history_weight_bytes;
    anvil_en1_replay_audio_history #(.COMPACT(COMPACT)) histories (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == HISTORY_START), .start_ready(history_ready),
        .model(model_hold), .precision(precision_hold), .mode(mode_hold),
        .generation(generation_hold), .frames(frames_hold), .query_token(query_hold),
        .frame_layer(layer_hold), .frame_slot(slot_hold),
        .audio_base(audio_hold), .audio_weights_base(weights_hold),
        .continuation(continuation_hold),
        .dependency_valid(dependency_valid_hold), .dependency_domain(dependency_domain_hold),
        .dependency_layer(dependency_layer_hold), .dependency_token(dependency_token_hold),
        .dependency_length(dependency_length_hold), .dependency_slot(dependency_slot_hold),
        .work_req_valid(history_work_valid),
        .work_req_ready(history_selected && work_req_ready),
        .work_req_op(history_op), .work_req_domain(history_domain),
        .work_req_target(history_target), .work_req_token(history_token),
        .work_req_layer(history_layer), .work_req_length(history_length),
        .work_req_component(history_component), .work_req_slot(history_slot),
        .work_req_bank(history_work_bank), .work_req_scalar_index(history_scalar),
        .work_req_data(history_data),
        .work_rsp_valid(history_selected && work_rsp_valid),
        .work_rsp_ready(history_work_rsp_ready), .work_rsp_data(work_rsp_data),
        .work_rsp_error(work_rsp_error),
        .cmd_valid(history_cmd_valid), .cmd_ready(history_selected && cmd_ready),
        .cmd_write(), .cmd_addr(history_addr), .cmd_wdata(),
        .result_valid(history_selected && result_valid), .result_ready(history_result_ready),
        .result_data(result_data), .result_error(result_error),
        .done_valid(history_valid), .done_ready(rst_n && state == HISTORY_WAIT),
        .done_error(history_error), .done_yield(history_yield),
        .done_history_count(history_count), .done_continuation(history_continuation),
        .done_dependency_domain(history_dependency_domain),
        .done_dependency_layer(history_dependency_layer),
        .done_dependency_token(history_dependency_token),
        .done_dependency_length(history_dependency_length),
        .input_read_event(history_input_event), .input_read_bytes(history_input_bytes),
        .projection_event(history_projection_event), .projection_bytes(history_projection_bytes),
        .intermediate_event(history_intermediate_event),
        .intermediate_bytes(history_intermediate_bytes),
        .source_read_event(history_source_event), .source_read_bytes(history_source_bytes),
        .weight_read_event(history_weight_event), .weight_read_bytes(history_weight_bytes),
        .history_replay_event(history_replay_event), .history_replay_bytes(history_replay_bytes),
        .vector_live_bytes(history_live), .vector_physical_bytes(history_physical),
        .controller_bytes(history_control), .nested_controller_bytes(history_nested)
    );

    wire pair_phase = state == PAIR_SEND || state == PAIR_WAIT || state == PAIR_REGISTER;
    wire release_phase = state == RELEASE_SEND || state == RELEASE_WAIT ||
        state == RELEASE_REGISTER;
    wire conv_selected = rst_n && (state == CONV_START || state == CONV_WAIT ||
        (pair_phase && phase_hold == 0));
    wire ff_selected = rst_n && (state == FF_START || state == FF_WAIT ||
        state == CLAMP_START || state == CLAMP_WAIT || state == CLAMP_REGISTER ||
        (pair_phase && phase_hold == 1));
    wire norm_selected = rst_n && (state == NORM_START || state == NORM_WAIT ||
        (pair_phase && phase_hold == 2));
    wire waiting = rst_n && (state == CONV_WAIT || state == FF_WAIT || state == NORM_WAIT);
    wire callback_accept = waiting && source_state == S_IDLE;
    wire conv_ready, conv_valid, conv_cmd_valid, conv_result_ready;
    wire conv_source_valid, conv_source_rsp_ready, conv_output_valid, conv_output_last;
    wire [1:0] conv_source_model;
    wire [7:0] conv_source_layer;
    wire [31:0] conv_source_generation, conv_source_token, conv_source_index, conv_output_index;
    wire [15:0] conv_output_data;
    wire [3:0] conv_error;
    wire [63:0] conv_addr, conv_live, conv_physical, conv_control, conv_nested;
    wire [2:0] conv_ram_write, conv_ram_read, ff_ram_write, ff_ram_read;
    wire [95:0] conv_ram_waddr, conv_ram_raddr, ff_ram_waddr, ff_ram_raddr;
    wire [47:0] conv_ram_wdata, ff_ram_wdata, shared_ram_rdata;
    wire conv_projection_event;
    wire [31:0] conv_projection_bytes;
    wire conv_start = rst_n && state == CONV_START && vector_owner == 0;
    wire ff_start = rst_n && state == FF_START && vector_owner == 0;
    anvil_en1_audio_lightconv #(.EXTERNAL_VECTOR_RAM(1)) convolution (
        .clk(clk), .rst_n(rst_n),
        .start_valid(conv_start), .start_ready(conv_ready),
        .model(model_hold), .precision(precision_hold), .layer(logical_layer),
        .generation(generation_hold), .token(query_hold), .audio_weights_base(weights_hold),
        .source_valid(conv_source_valid), .source_ready(callback_accept && state == CONV_WAIT),
        .source_model(conv_source_model), .source_layer(conv_source_layer),
        .source_generation(conv_source_generation), .source_token(conv_source_token),
        .source_index(conv_source_index),
        .source_rsp_valid(rst_n && state == CONV_WAIT && source_state == S_RESPONSE),
        .source_rsp_ready(conv_source_rsp_ready), .source_rsp_data(source_data_hold),
        .source_rsp_error(source_error_hold != 0),
        .cmd_valid(conv_cmd_valid), .cmd_ready(conv_selected && cmd_ready),
        .cmd_write(), .cmd_addr(conv_addr), .cmd_wdata(),
        .result_valid(conv_selected && result_valid), .result_ready(conv_result_ready),
        .result_data(result_data), .result_error(result_error),
        .output_valid(conv_output_valid),
        .output_ready(callback_accept && state == CONV_WAIT && !conv_source_valid),
        .output_index(conv_output_index), .output_data(conv_output_data),
        .output_last(conv_output_last), .done_valid(conv_valid),
        .done_ready(callback_accept && state == CONV_WAIT &&
            !conv_output_valid && !conv_source_valid),
        .done_error(conv_error), .weight_read_event(), .weight_read_bytes(),
        .projection_event(conv_projection_event), .projection_bytes(conv_projection_bytes),
        .glu_replay_event(glu_replay_event), .glu_replay_bytes(glu_replay_bytes),
        .vector_live_bytes(conv_live), .vector_physical_bytes(conv_physical),
        .vector_ram_write(conv_ram_write), .vector_ram_read(conv_ram_read),
        .vector_ram_waddr(conv_ram_waddr), .vector_ram_raddr(conv_ram_raddr),
        .vector_ram_wdata(conv_ram_wdata), .vector_ram_rdata(shared_ram_rdata),
        .controller_bytes(conv_control), .nested_controller_bytes(conv_nested)
    );

    wire ff_ready, ff_valid, ff_cmd_valid, ff_result_ready;
    wire ff_source_valid, ff_source_rsp_ready, ff_output_valid, ff_output_last;
    wire [1:0] ff_source_model, ff_source_mode;
    wire [7:0] ff_source_layer;
    wire [31:0] ff_source_generation, ff_source_token, ff_source_index, ff_output_index;
    wire [15:0] ff_output_data;
    wire [3:0] ff_error;
    wire [63:0] ff_addr, ff_live, ff_physical, ff_control;
    wire [63:0] ff_norm_control, ff_clamp_control, ff_mlp_control, ff_down_control;
    wire [63:0] ff_down_clamp_control, ff_inner_control, ff_inner_clamp_control;
    wire ff_intermediate_event;
    wire [31:0] ff_intermediate_bytes;
    anvil_en1_audio_feedforward #(.EXTERNAL_VECTOR_RAM(1)) feed_forward2 (
        .clk(clk), .rst_n(rst_n),
        .start_valid(ff_start), .start_ready(ff_ready),
        .model(model_hold), .precision(precision_hold), .mode(2'd2), .layer(logical_layer),
        .generation(generation_hold), .token(query_hold), .audio_weights_base(weights_hold),
        .source_valid(ff_source_valid), .source_ready(callback_accept && state == FF_WAIT),
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
        .output_valid(ff_output_valid),
        .output_ready(callback_accept && state == FF_WAIT && !ff_source_valid),
        .output_index(ff_output_index), .output_data(ff_output_data),
        .output_last(ff_output_last), .done_valid(ff_valid),
        .done_ready(callback_accept && state == FF_WAIT && !ff_output_valid && !ff_source_valid),
        .done_error(ff_error), .weight_read_event(), .weight_read_bytes(),
        .intermediate_event(ff_intermediate_event), .intermediate_bytes(ff_intermediate_bytes),
        .vector_live_bytes(ff_live), .vector_physical_bytes(ff_physical),
        .vector_ram_write(ff_ram_write), .vector_ram_read(ff_ram_read),
        .vector_ram_waddr(ff_ram_waddr), .vector_ram_raddr(ff_ram_raddr),
        .vector_ram_wdata(ff_ram_wdata), .vector_ram_rdata(shared_ram_rdata),
        .controller_bytes(ff_control), .norm_controller_bytes(ff_norm_control),
        .clamp_controller_bytes(ff_clamp_control), .mlp_controller_bytes(ff_mlp_control),
        .down_controller_bytes(ff_down_control), .down_clamp_controller_bytes(ff_down_clamp_control),
        .inner_controller_bytes(ff_inner_control), .inner_clamp_controller_bytes(ff_inner_clamp_control)
    );
    wire clamp_ready, clamp_valid;
    wire [15:0] clamped_data;
    wire [3:0] clamp_error;
    wire [63:0] clamp_control;
    anvil_en1_bf16_clamp final_clamp (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == CLAMP_START), .start_ready(clamp_ready),
        .value(clamp_input_hold), .minimum(16'hd015), .maximum(16'h5015),
        .done_valid(clamp_valid), .done_ready(rst_n && state == CLAMP_WAIT),
        .done_data(clamped_data), .done_error(clamp_error), .controller_bytes(clamp_control)
    );
    wire norm_ready, norm_valid, norm_cmd_valid, norm_result_ready;
    wire norm_source_valid, norm_source_rsp_ready, norm_output_valid, norm_output_last;
    wire [31:0] norm_source_index, norm_output_index;
    wire [15:0] norm_output_data;
    wire [3:0] norm_error;
    wire [63:0] norm_addr, norm_control;
    anvil_en1_native_norm norm_out (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == NORM_START), .start_ready(norm_ready),
        .model(model_hold), .precision(precision_hold), .image_class(2'd2),
        .tensor_kind(16'h2115), .tensor_layer({8'd0, logical_layer}),
        .vector_length(32'd1024), .weights_base(weights_hold),
        .source_valid(norm_source_valid), .source_ready(callback_accept && state == NORM_WAIT),
        .source_index(norm_source_index),
        .source_rsp_valid(rst_n && state == NORM_WAIT && source_state == S_RESPONSE),
        .source_rsp_ready(norm_source_rsp_ready), .source_rsp_data(source_data_hold),
        .source_rsp_error(source_error_hold != 0),
        .cmd_valid(norm_cmd_valid), .cmd_ready(norm_selected && cmd_ready),
        .cmd_write(), .cmd_addr(norm_addr), .cmd_wdata(),
        .result_valid(norm_selected && result_valid), .result_ready(norm_result_ready),
        .result_data(result_data), .result_error(result_error),
        .output_valid(norm_output_valid),
        .output_ready(callback_accept && state == NORM_WAIT && !norm_source_valid),
        .output_index(norm_output_index), .output_data(norm_output_data),
        .output_last(norm_output_last), .done_valid(norm_valid),
        .done_ready(callback_accept && state == NORM_WAIT &&
            !norm_output_valid && !norm_source_valid),
        .done_error(norm_error), .controller_bytes(norm_control)
    );

    wire callback_valid = state == CONV_WAIT ? conv_source_valid :
        (state == FF_WAIT ? ff_source_valid : norm_source_valid);
    wire callback_rsp_ready = state == CONV_WAIT ? conv_source_rsp_ready :
        (state == FF_WAIT ? ff_source_rsp_ready : norm_source_rsp_ready);
    wire [31:0] callback_index = state == CONV_WAIT ? conv_source_index :
        (state == FF_WAIT ? ff_source_index : norm_source_index);
    wire callback_bad = state == CONV_WAIT ?
        (conv_source_model != model_hold || conv_source_layer != logical_layer ||
         conv_source_generation != generation_hold) :
        (state == FF_WAIT && (ff_source_model != model_hold || ff_source_mode != 2 ||
         ff_source_layer != logical_layer || ff_source_generation != generation_hold ||
         ff_source_token != query_hold));
    wire [31:0] source_distance = query_hold - source_token_hold;
    wire active_output_valid = state == CONV_WAIT ? conv_output_valid :
        (state == FF_WAIT ? ff_output_valid : norm_output_valid);
    wire [31:0] active_output_index = state == CONV_WAIT ? conv_output_index :
        (state == FF_WAIT ? ff_output_index : norm_output_index);
    wire [15:0] active_output_data = state == CONV_WAIT ? conv_output_data :
        (state == FF_WAIT ? ff_output_data : norm_output_data);
    wire active_output_last = state == CONV_WAIT ? conv_output_last :
        (state == FF_WAIT ? ff_output_last : norm_output_last);
    wire output_good = received < 1024 && active_output_index == received &&
        active_output_last == (received == 1023);
    wire active_done_valid = state == CONV_WAIT ? conv_valid :
        (state == FF_WAIT ? ff_valid : norm_valid);
    wire [3:0] active_done_error = state == CONV_WAIT ? conv_error :
        (state == FF_WAIT ? ff_error : norm_error);
    wire source_send = waiting && source_state == S_SEND;
    wire source_wait = waiting && source_state == S_WAIT;
    assign work_req_valid = (history_selected && history_work_valid) || source_send ||
        (rst_n && (state == PAIR_SEND || state == RELEASE_SEND));
    assign work_rsp_ready = (history_selected && history_work_rsp_ready) || source_wait ||
        (rst_n && (state == PAIR_WAIT || state == RELEASE_WAIT));
    always @* begin
        work_req_op = 0;
        work_req_domain = 0;
        work_req_target = 0;
        work_req_token = 0;
        work_req_layer = 0;
        work_req_length = 0;
        work_req_component = 0;
        work_req_slot = 0;
        work_req_bank = 0;
        work_req_scalar_index = 0;
        work_req_data = 0;
        if (rst_n) begin
            if (history_selected) begin
                work_req_op = history_op;
                work_req_domain = history_domain;
                work_req_target = history_target;
                work_req_token = history_token;
                work_req_layer = history_layer;
                work_req_length = history_length;
                work_req_component = history_component;
                work_req_slot = history_slot;
                work_req_bank = history_work_bank;
                work_req_scalar_index = history_scalar;
                work_req_data = history_data;
            end else begin
                work_req_domain = 2;
                work_req_token = query_hold;
                work_req_layer = layer_hold;
                work_req_length = 1024;
                work_req_slot = slot_hold;
                if (release_phase) begin
                    work_req_op = 7;
                    work_req_target = 2;
                    if (phase_hold == 0) begin
                        work_req_bank = history_count_hold != 2;
                        work_req_scalar_index = history_count_hold == 2 ? 8'd2 :
                            {5'd0, history_count_hold} - 8'd3;
                    end else
                        work_req_bank = phase_hold == 2;
                end else if (waiting && source_state != S_IDLE) begin
                    work_req_op = 4;
                    work_req_component = source_index_hold[11:0] & 12'hffe;
                    work_req_bank = source_bank_hold;
                    work_req_scalar_index = {6'd0, source_slice_hold};
                end else if (pair_phase) begin
                    work_req_op = 6;
                    work_req_target = 2;
                    work_req_component = received[11:0] - 12'd2;
                    work_req_bank = phase_hold == 1;
                    work_req_data = pair_hold;
                end
            end
        end
    end
    assign cmd_valid = (history_selected && history_cmd_valid) ||
        (conv_selected && conv_cmd_valid) || (ff_selected && ff_cmd_valid) ||
        (norm_selected && norm_cmd_valid);
    assign cmd_write = 0;
    assign cmd_addr = history_selected ? history_addr : (conv_selected ? conv_addr :
        (ff_selected ? ff_addr : (norm_selected ? norm_addr : 64'd0)));
    assign cmd_wdata = 0;
    assign result_ready = (history_selected && history_result_ready) ||
        (conv_selected && conv_result_ready) || (ff_selected && ff_result_ready) ||
        (norm_selected && norm_result_ready);
    assign start_ready = rst_n && state == IDLE;
    assign done_valid = rst_n && state == RESPONSE;
    assign done_error = !rst_n ? 4'd0 :
        (error_hold != 0 ? error_hold : (vector_ram_fault ? 4'd7 : 4'd0));
    assign done_yield = done_valid && yield_hold && done_error == 0;
    assign done_bank = 0;
    assign done_continuation = done_yield ? yielded_continuation : 160'd0;
    assign done_dependency_domain = done_yield ? yielded_domain : 2'd0;
    assign done_dependency_layer = done_yield ? yielded_layer : 8'd0;
    assign done_dependency_token = done_yield ? yielded_token : 32'd0;
    assign done_dependency_length = done_yield ? yielded_length : 12'd0;
    wire source_event = callback_accept && callback_valid;
    wire weight_event = !history_selected && cmd_valid && cmd_ready;
    assign input_read_event = history_input_event;
    assign input_read_bytes = history_input_bytes;
    assign projection_event = history_projection_event || conv_projection_event;
    assign projection_bytes = history_projection_bytes + conv_projection_bytes;
    assign intermediate_event = history_intermediate_event || ff_intermediate_event;
    assign intermediate_bytes = history_intermediate_bytes + ff_intermediate_bytes;
    assign source_read_event = history_source_event || source_event;
    assign source_read_bytes = history_source_bytes + (source_event ? 32'd2 : 32'd0);
    assign weight_read_event = history_weight_event || weight_event;
    assign weight_read_bytes = history_weight_bytes + (weight_event ? 32'd4 : 32'd0);
    assign vector_live_bytes = !rst_n ? 64'd0 : history_live + conv_live + ff_live;
    assign vector_physical_bytes = !rst_n ? 64'd0 :
        history_physical + conv_physical + ff_physical +
            (EXTERNAL_VECTOR_RAM ? 64'd0 : 64'd6144);
    assign nested_controller_bytes = !rst_n ? 64'd0 :
        history_control + history_nested + conv_control + conv_nested +
        ff_control + ff_norm_control + ff_clamp_control + ff_mlp_control +
        ff_down_control + ff_down_clamp_control + ff_inner_control +
        ff_inner_clamp_control + clamp_control + norm_control;
    localparam integer CONTROLLER_BITS =
        $bits(state) + $bits(source_state) + $bits(model_hold) + $bits(precision_hold) +
        $bits(mode_hold) + $bits(phase_hold) + $bits(dependency_domain_hold) +
        $bits(yielded_domain) + $bits(source_slice_hold) + $bits(generation_hold) +
        $bits(frames_hold) + $bits(query_hold) + $bits(dependency_token_hold) +
        $bits(yielded_token) + $bits(received) + $bits(pair_hold) +
        $bits(source_index_hold) + $bits(source_token_hold) + $bits(source_pair_hold) +
        $bits(layer_hold) + $bits(dependency_layer_hold) + $bits(yielded_layer) +
        $bits(slot_hold) + $bits(dependency_slot_hold) + $bits(dependency_length_hold) +
        $bits(yielded_length) + $bits(history_count_hold) + $bits(audio_hold) +
        $bits(weights_hold) + $bits(continuation_hold) + $bits(yielded_continuation) +
        $bits(dependency_valid_hold) + $bits(child_yield_hold) + $bits(yield_hold) +
        $bits(source_bank_hold) + $bits(source_bad) + $bits(low_hold) +
        $bits(clamp_input_hold) + $bits(clamp_data_hold) + $bits(source_data_hold) +
        $bits(error_hold) + $bits(child_error_hold) + $bits(work_error_hold) +
        $bits(source_error_hold) + $bits(first_source_error) +
        $bits(vector_ram_fault) + $bits(vector_owner) +
        (EXTERNAL_VECTOR_RAM ? 0 : 48);
    assign controller_bytes = rst_n ? (CONTROLLER_BITS + 7) >> 3 : 64'd0;

    wire conv_ram_access = |conv_ram_write || |conv_ram_read;
    wire ff_ram_access = |ff_ram_write || |ff_ram_read;
    wire vector_owner_fault = rst_n &&
        ((conv_ram_access && ff_ram_access) ||
         (conv_ram_access && !conv_selected) ||
         (ff_ram_access && !ff_selected) ||
         (conv_ram_access && vector_owner != 1) ||
         (ff_ram_access && vector_owner != 2) ||
         (|history_live && (|conv_live || |ff_live)) ||
         (|conv_live && |ff_live) ||
         history_live > 64'd16384 || conv_live > 64'd6144 ||
         ff_live > 64'd6144);
    wire [2:0] vector_range_fault;
    wire vector_access_fault = vector_owner_fault || |vector_range_fault;
    genvar bank;
    generate for (bank=0; bank<3; bank=bank+1) begin : shared_vectors
        wire [31:0] conv_waddr = conv_ram_waddr[32*bank+:32];
        wire [31:0] conv_raddr = conv_ram_raddr[32*bank+:32];
        wire [31:0] ff_waddr = ff_ram_waddr[32*bank+:32];
        wire [31:0] ff_raddr = ff_ram_raddr[32*bank+:32];
        assign vector_range_fault[bank] = rst_n &&
            ((conv_ram_write[bank] && conv_waddr >= 1024) ||
             (conv_ram_read[bank] && conv_raddr >= 1024) ||
             (ff_ram_write[bank] && ff_waddr >= 1024) ||
             (ff_ram_read[bank] && ff_raddr >= 1024));
        wire write_enable = conv_ram_write[bank] || ff_ram_write[bank];
        wire read_enable = conv_ram_read[bank] || ff_ram_read[bank];
        wire [31:0] waddr = conv_ram_write[bank] ? conv_waddr : ff_waddr;
        wire [31:0] raddr = conv_ram_read[bank] ? conv_raddr : ff_raddr;
        wire [15:0] wdata = conv_ram_write[bank] ?
            conv_ram_wdata[16*bank+:16] : ff_ram_wdata[16*bank+:16];
        assign vector_ram_write[bank] = rst_n && EXTERNAL_VECTOR_RAM &&
            !vector_access_fault && write_enable;
        assign vector_ram_read[bank] = rst_n && EXTERNAL_VECTOR_RAM &&
            !vector_access_fault && read_enable;
        assign vector_ram_waddr[32*bank+:32] =
            rst_n && EXTERNAL_VECTOR_RAM ? waddr : 32'd0;
        assign vector_ram_raddr[32*bank+:32] =
            rst_n && EXTERNAL_VECTOR_RAM ? raddr : 32'd0;
        assign vector_ram_wdata[16*bank+:16] =
            rst_n && EXTERNAL_VECTOR_RAM ? wdata : 16'd0;
        if (EXTERNAL_VECTOR_RAM == 1) begin : external_bank
            assign shared_ram_rdata[16*bank+:16] = vector_ram_rdata[16*bank+:16];
        end else begin : local_bank
            (* ramstyle = "M20K", nomem2reg *) reg [15:0] payload [0:1023];
            reg [15:0] read_q;
            assign shared_ram_rdata[16*bank+:16] = read_q;
            always @(posedge clk) begin
                if (rst_n && !vector_access_fault) begin
                    if (write_enable)
                        payload[waddr[9:0]] <= wdata;
                    if (read_enable)
                        read_q <= payload[raddr[9:0]];
                end
            end
        end
    end endgenerate
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            vector_ram_fault <= 0;
        else if (start_valid && start_ready)
            vector_ram_fault <= 0;
        else if (vector_access_fault)
            vector_ram_fault <= 1;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            vector_owner <= 0;
        else if (conv_start && conv_ready)
            vector_owner <= 1;
        else if (ff_start && ff_ready)
            vector_owner <= 2;
        else if ((vector_owner == 1 && conv_valid && callback_accept &&
                state == CONV_WAIT && !conv_output_valid && !conv_source_valid) ||
            (vector_owner == 2 && ff_valid && callback_accept &&
                state == FF_WAIT && !ff_output_valid && !ff_source_valid))
            vector_owner <= 0;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            source_state <= S_IDLE;
            source_slice_hold <= 0;
            source_index_hold <= 0;
            source_token_hold <= 0;
            source_pair_hold <= 0;
            source_bank_hold <= 0;
            source_bad <= 0;
            source_data_hold <= 0;
            source_error_hold <= 0;
            first_source_error <= 0;
        end else begin
            if (start_valid && start_ready)
                first_source_error <= 0;
            case (source_state)
                S_IDLE: if (source_event) begin
                    source_index_hold <= callback_index;
                    source_token_hold <= state == CONV_WAIT ? conv_source_token : query_hold;
                    source_bad <= callback_bad;
                    source_bank_hold <= 0;
                    source_slice_hold <= 0;
                    source_data_hold <= 0;
                    source_error_hold <= 0;
                    source_state <= S_VALIDATE;
                end
                S_VALIDATE: begin
                    if (source_bad || source_index_hold >= 1024 ||
                        error_hold != 0 || first_source_error != 0 ||
                        (state != NORM_WAIT && received != 0) ||
                        (state == CONV_WAIT && (source_token_hold > query_hold ||
                            source_distance > {29'd0, last_distance}))) begin
                        source_error_hold <= first_source_error != 0 ? first_source_error :
                            (error_hold != 0 ? error_hold : 4'd7);
                        if (first_source_error == 0)
                            first_source_error <= error_hold != 0 ? error_hold : 4'd7;
                        source_state <= S_RESPONSE;
                    end else begin
                        if (state == CONV_WAIT && source_distance != {29'd0, last_distance}) begin
                            source_bank_hold <= source_distance != 0;
                            source_slice_hold <= source_distance == 0 ? 2'd2 :
                                source_distance[1:0] - 2'd1;
                        end else if (state == NORM_WAIT)
                            source_bank_hold <= 1;
                        source_state <= S_SEND;
                    end
                end
                S_SEND: if (work_req_ready)
                    source_state <= S_WAIT;
                S_WAIT: if (work_rsp_valid) begin
                    source_pair_hold <= work_rsp_data;
                    source_error_hold <= work_rsp_error;
                    source_state <= S_REGISTER;
                end
                S_REGISTER: begin
                    if (source_error_hold != 0) begin
                        if (first_source_error == 0)
                            first_source_error <= source_error_hold;
                    end else
                        source_data_hold <= source_index_hold[0] ?
                            source_pair_hold[31:16] : source_pair_hold[15:0];
                    source_state <= S_RESPONSE;
                end
                S_RESPONSE: if (waiting && callback_rsp_ready)
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
            mode_hold <= 0;
            phase_hold <= 0;
            dependency_domain_hold <= 0;
            yielded_domain <= 0;
            generation_hold <= 0;
            frames_hold <= 0;
            query_hold <= 0;
            dependency_token_hold <= 0;
            yielded_token <= 0;
            received <= 0;
            pair_hold <= 0;
            layer_hold <= 0;
            dependency_layer_hold <= 0;
            yielded_layer <= 0;
            slot_hold <= 0;
            dependency_slot_hold <= 0;
            dependency_length_hold <= 0;
            yielded_length <= 0;
            history_count_hold <= 0;
            audio_hold <= 0;
            weights_hold <= 0;
            continuation_hold <= 0;
            yielded_continuation <= 0;
            dependency_valid_hold <= 0;
            child_yield_hold <= 0;
            yield_hold <= 0;
            low_hold <= 0;
            clamp_input_hold <= 0;
            clamp_data_hold <= 0;
            error_hold <= 0;
            child_error_hold <= 0;
            work_error_hold <= 0;
        end else begin
            case (state)
                IDLE: if (start_valid && start_ready) begin
                    model_hold <= model;
                    precision_hold <= precision;
                    mode_hold <= mode;
                    generation_hold <= generation;
                    frames_hold <= frames;
                    query_hold <= query_token;
                    layer_hold <= frame_layer;
                    slot_hold <= frame_slot;
                    audio_hold <= audio_base;
                    weights_hold <= audio_weights_base;
                    continuation_hold <= continuation;
                    dependency_valid_hold <= dependency_valid;
                    dependency_domain_hold <= dependency_domain;
                    dependency_layer_hold <= dependency_layer;
                    dependency_token_hold <= dependency_token;
                    dependency_length_hold <= dependency_length;
                    dependency_slot_hold <= dependency_slot;
                    received <= 0;
                    phase_hold <= 0;
                    pair_hold <= 0;
                    low_hold <= 0;
                    clamp_input_hold <= 0;
                    clamp_data_hold <= 0;
                    error_hold <= 0;
                    child_error_hold <= 0;
                    work_error_hold <= 0;
                    child_yield_hold <= 0;
                    yield_hold <= 0;
                    history_count_hold <= 0;
                    yielded_domain <= 0;
                    yielded_layer <= 0;
                    yielded_token <= 0;
                    yielded_length <= 0;
                    yielded_continuation <= 0;
                    state <= VALIDATE;
                end
                VALIDATE: begin
                    if ((model_hold != 1 && model_hold != 2) || precision_hold > 1) begin
                        error_hold <= 6;
                        state <= PUBLISH;
                    end else if (generation_hold == 0 || frames_hold == 0 ||
                        frames_hold > 131072 || query_hold >= tokens_hold ||
                        layer_hold == 0 || layer_hold > 12 ||
                        audio_hold[1:0] != 0 || weights_hold[1:0] != 0) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else
                        state <= HISTORY_START;
                end
                HISTORY_START: if (history_ready)
                    state <= HISTORY_WAIT;
                HISTORY_WAIT: if (history_valid) begin
                    child_error_hold <= history_error;
                    child_yield_hold <= history_yield;
                    history_count_hold <= history_count;
                    yielded_continuation <= history_continuation;
                    yielded_domain <= history_dependency_domain;
                    yielded_layer <= history_dependency_layer;
                    yielded_token <= history_dependency_token;
                    yielded_length <= history_dependency_length;
                    state <= HISTORY_CHECK;
                end
                HISTORY_CHECK: begin
                    if (child_error_hold != 0) begin
                        error_hold <= child_error_hold;
                        state <= PUBLISH;
                    end else if (child_yield_hold) begin
                        if (yielded_domain != 2 || yielded_layer != logical_layer ||
                            yielded_token >= tokens_hold || yielded_length != 1024)
                            error_hold <= 7;
                        else
                            yield_hold <= 1;
                        state <= PUBLISH;
                    end else if (history_count_hold != last_distance + 3'd1) begin
                        error_hold <= 7;
                        state <= PUBLISH;
                    end else begin
                        phase_hold <= 0;
                        state <= CONV_START;
                    end
                end
                CONV_START: if (conv_start && conv_ready)
                    state <= CONV_WAIT;
                FF_START: if (ff_start && ff_ready)
                    state <= FF_WAIT;
                NORM_START: if (norm_ready)
                    state <= NORM_WAIT;
                CONV_WAIT, FF_WAIT, NORM_WAIT: begin
                    if (active_output_valid && source_state == S_IDLE && !callback_valid) begin
                        if (error_hold == 0 && first_source_error == 0) begin
                            if (!output_good)
                                error_hold <= 7;
                            else if (state == FF_WAIT) begin
                                clamp_input_hold <= active_output_data;
                                state <= CLAMP_START;
                            end else begin
                                received <= received + 1'b1;
                                if (!received[0])
                                    low_hold <= active_output_data;
                                else begin
                                    pair_hold <= {active_output_data, low_hold};
                                    state <= PAIR_SEND;
                                end
                            end
                        end
                    end else if (active_done_valid && source_state == S_IDLE &&
                        !active_output_valid && !callback_valid) begin
                        child_error_hold <= active_done_error;
                        if (state == CONV_WAIT)
                            state <= CONV_CHECK;
                        else if (state == FF_WAIT)
                            state <= FF_CHECK;
                        else
                            state <= NORM_CHECK;
                    end
                end
                CLAMP_START: if (clamp_ready)
                    state <= CLAMP_WAIT;
                CLAMP_WAIT: if (clamp_valid) begin
                    if (clamp_error != 0) begin
                        error_hold <= clamp_error;
                        state <= FF_WAIT;
                    end else begin
                        clamp_data_hold <= clamped_data;
                        state <= CLAMP_REGISTER;
                    end
                end
                CLAMP_REGISTER: begin
                    received <= received + 1'b1;
                    if (!received[0]) begin
                        low_hold <= clamp_data_hold;
                        state <= FF_WAIT;
                    end else begin
                        pair_hold <= {clamp_data_hold, low_hold};
                        state <= PAIR_SEND;
                    end
                end
                PAIR_SEND: if (work_req_ready)
                    state <= PAIR_WAIT;
                PAIR_WAIT: if (work_rsp_valid) begin
                    work_error_hold <= work_rsp_error;
                    state <= PAIR_REGISTER;
                end
                PAIR_REGISTER: begin
                    low_hold <= 0;
                    if (work_error_hold != 0 && error_hold == 0)
                        error_hold <= work_error_hold;
                    if (phase_hold == 0)
                        state <= CONV_WAIT;
                    else if (phase_hold == 1)
                        state <= FF_WAIT;
                    else
                        state <= NORM_WAIT;
                end
                CONV_CHECK, FF_CHECK, NORM_CHECK: begin
                    if (error_hold != 0 || first_source_error != 0 || child_error_hold != 0) begin
                        if (error_hold == 0)
                            error_hold <= first_source_error != 0 ?
                                first_source_error : child_error_hold;
                        state <= PUBLISH;
                    end else if (received != 1024 || low_hold != 0) begin
                        error_hold <= 7;
                        state <= PUBLISH;
                    end else if (state == CONV_CHECK) begin
                        received <= 0;
                        if (history_count_hold == 1) begin
                            phase_hold <= 1;
                            state <= FF_START;
                        end else
                            state <= RELEASE_SEND;
                    end else if (state == FF_CHECK) begin
                        received <= 0;
                        state <= RELEASE_SEND;
                    end else
                        state <= RELEASE_SEND;
                end
                RELEASE_SEND: if (work_req_ready)
                    state <= RELEASE_WAIT;
                RELEASE_WAIT: if (work_rsp_valid) begin
                    work_error_hold <= work_rsp_error;
                    state <= RELEASE_REGISTER;
                end
                RELEASE_REGISTER: begin
                    if (work_error_hold != 0) begin
                        error_hold <= work_error_hold;
                        state <= PUBLISH;
                    end else if (phase_hold == 0) begin
                        history_count_hold <= history_count_hold - 3'd1;
                        if (history_count_hold == 2) begin
                            phase_hold <= 1;
                            state <= FF_START;
                        end else
                            state <= RELEASE_SEND;
                    end else if (phase_hold == 1) begin
                        phase_hold <= 2;
                        state <= NORM_START;
                    end else
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
