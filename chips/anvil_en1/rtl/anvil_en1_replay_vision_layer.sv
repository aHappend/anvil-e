module anvil_en1_replay_vision_layer #(
    parameter integer COMPACT = 0,
    parameter integer EXTERNAL_BRANCH_RAM = 0
) (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] model, precision, mode,
    input wire [31:0] generation, patches, patch_rows, patch_columns, query_patch,
    input wire [7:0] frame_layer,
    input wire [5:0] frame_slot,
    input wire [63:0] image_base, vision_weights_base,
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
    output wire input_read_event,
    output wire [31:0] input_read_bytes,
    output wire projection_event,
    output wire [31:0] projection_bytes,
    output wire intermediate_event,
    output wire [31:0] intermediate_bytes,
    output wire source_read_event,
    output wire [31:0] source_read_bytes,
    output wire [63:0] vector_live_bytes, vector_physical_bytes,
    output wire branch_ram_write, branch_ram_read,
    output wire [31:0] branch_ram_waddr, branch_ram_raddr,
    output wire [15:0] branch_ram_wdata,
    input wire [15:0] branch_ram_rdata,
    output wire [63:0] controller_bytes, binding_controller_bytes,
    output wire [63:0] patch_controller_bytes, replay_controller_bytes,
    output wire [63:0] executor_controller_bytes, head_controller_bytes,
    output wire [63:0] tile_controller_bytes, clipped_controller_bytes, clamp_controller_bytes,
    output wire [63:0] output_controller_bytes, output_clamp_controller_bytes,
    output wire [63:0] post_controller_bytes, norm_controller_bytes,
    output wire [63:0] mlp_controller_bytes, down_controller_bytes, down_clamp_controller_bytes,
    output wire [63:0] inner_controller_bytes, inner_clamp_controller_bytes
);
    localparam [5:0] IDLE = 0, VALIDATE = 1, EXTENT_PRODUCT = 2,
        EXTENT_VALIDATE = 3, BIND_START = 4, BIND_WAIT = 5,
        PATCH_START = 6, PATCH_WAIT = 7, PATCH_CHECK = 8,
        HEAD_START = 9, HEAD_WAIT = 10, HEAD_CHECK = 11,
        PAIR_SEND = 12, PAIR_WAIT = 13, PAIR_REGISTER = 14,
        SAVE_SEND = 15, SAVE_WAIT = 16, SAVE_REGISTER = 17,
        RESTORE_SEND = 18, RESTORE_WAIT = 19, RESTORE_REGISTER = 20,
        RESTORE_CHECK = 21, PROJECTION_START = 22, PROJECTION_WAIT = 23,
        PROJECTION_CHECK = 24, PROJECTION_STORE = 25, PROJECTION_ADVANCE = 26,
        COPY_READ = 27, COPY_CAPTURE = 28, COPY_PACK = 29,
        POST_START = 30, POST_WAIT = 31, POST_CHECK = 32,
        PUBLISH = 33, RESPONSE = 34, RELEASE_SEND = 35,
        RELEASE_WAIT = 36, RELEASE_REGISTER = 37;
    localparam [2:0] S_IDLE = 0, S_VALIDATE = 1, S_SEND = 2,
        S_WAIT = 3, S_REGISTER = 4, S_RESPONSE = 5;
    localparam [31:0] INPUT_MAGIC = 32'h454e314a;
    reg [5:0] state, pair_return;
    reg [2:0] source_state;
    reg [1:0] model_hold, precision_hold, mode_hold, dependency_domain_hold;
    reg [31:0] generation_hold, patches_hold, rows_hold, columns_hold, query_hold, extent_hold;
    reg [7:0] layer_hold, dependency_layer_hold;
    reg [5:0] slot_hold, dependency_slot_hold;
    reg [31:0] dependency_token_hold;
    reg [11:0] dependency_length_hold;
    reg dependency_valid_hold, head_resume, yield_hold, projected_allocated;
    reg [1:0] scalar_word;
    reg receive_bad, projected_visible, source_dependency, source_bank, source_bad;
    reg [63:0] image_hold, weights_hold;
    reg [159:0] continuation_hold, yield_continuation;
    reg [31:0] received, row_hold, source_index_hold, source_token_hold;
    reg [31:0] pair_hold, scalar_hold, source_pair_hold, projected_hold, restored_head_word;
    reg [15:0] low_hold, copy_low, source_data_hold;
    wire [15:0] projected_q;
    reg [3:0] head_hold, child_error_hold, error_hold, work_error_hold, source_error_hold;
    reg [31:0] yielded_patch;
    reg branch_ram_fault;

    initial begin
        if (COMPACT != 0 && COMPACT != 1)
            $fatal(1, "PARAMETER ERROR: COMPACT must be 0 or 1");
        if (EXTERNAL_BRANCH_RAM != 0 && EXTERNAL_BRANCH_RAM != 1)
            $fatal(1, "PARAMETER ERROR: EXTERNAL_BRANCH_RAM must be 0 or 1");
    end
    wire [7:0] logical_layer = layer_hold - 1'b1;
    wire input_continuation = continuation_hold == {INPUT_MAGIC, 128'd0};
    wire head_continuation = continuation_hold[159:128] == 32'h454e3157 &&
        continuation_hold[127:96] == generation_hold &&
        continuation_hold[95:64] == query_hold &&
        continuation_hold[63:56] == layer_hold &&
        continuation_hold[55:50] == slot_hold &&
        continuation_hold[49:48] == model_hold &&
        continuation_hold[47:46] == precision_hold &&
        continuation_hold[45:38] == logical_layer &&
        continuation_hold[37:34] < 12 && continuation_hold[33:0] == 0;
    wire dependency_tag = dependency_valid_hold && dependency_domain_hold == 1 &&
        dependency_layer_hold == logical_layer && dependency_length_hold == 768 &&
        dependency_slot_hold < 16 && dependency_token_hold < patches_hold;

    wire binding_selected = rst_n && (state == BIND_START || state == BIND_WAIT);
    wire binding_ready, binding_valid, binding_yield, binding_work_valid, binding_work_rsp_ready;
    wire [3:0] binding_error;
    wire [2:0] binding_op;
    wire [1:0] binding_domain, binding_target;
    wire [31:0] binding_token, binding_data;
    wire [7:0] binding_layer, binding_scalar;
    wire [11:0] binding_length, binding_component;
    wire [5:0] binding_slot;
    wire binding_bank;
    anvil_en1_replay_frame_input #(.COMPACT(COMPACT), .DOMAIN(1)) predecessor (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == BIND_START), .start_ready(binding_ready),
        .model(model_hold), .token(query_hold), .tokens(patches_hold),
        .frame_layer(layer_hold), .frame_slot(slot_hold), .input_bank(1'b0),
        .dependency_valid(dependency_valid_hold), .dependency_domain(dependency_domain_hold),
        .dependency_layer(dependency_layer_hold), .dependency_token(dependency_token_hold),
        .dependency_length(dependency_length_hold), .dependency_slot(dependency_slot_hold),
        .work_req_valid(binding_work_valid), .work_req_ready(binding_selected && work_req_ready),
        .work_req_op(binding_op), .work_req_domain(binding_domain), .work_req_target(binding_target),
        .work_req_token(binding_token), .work_req_layer(binding_layer),
        .work_req_length(binding_length), .work_req_component(binding_component),
        .work_req_slot(binding_slot), .work_req_bank(binding_bank),
        .work_req_scalar_index(binding_scalar), .work_req_data(binding_data),
        .work_rsp_valid(binding_selected && work_rsp_valid), .work_rsp_ready(binding_work_rsp_ready),
        .work_rsp_error(work_rsp_error), .done_valid(binding_valid),
        .done_ready(rst_n && state == BIND_WAIT), .done_error(binding_error),
        .done_dependency(binding_yield), .done_dependency_domain(),
        .done_dependency_layer(), .done_dependency_token(), .done_dependency_length(),
        .controller_state_bytes(binding_controller_bytes), .busy()
    );

    wire patch_selected = rst_n && (state == PATCH_START || state == PATCH_WAIT);
    wire patch_ready, patch_valid, patch_output_valid, patch_output_last;
    wire patch_cmd_valid, patch_result_ready, patch_input_event, head_input_event;
    wire [31:0] patch_input_bytes, head_input_bytes;
    wire [31:0] patch_output_index;
    wire [15:0] patch_output_data;
    wire [63:0] patch_addr;
    wire [3:0] patch_error;
    anvil_en1_vision_patch original_patch (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == PATCH_START), .start_ready(patch_ready),
        .model(model_hold), .precision(precision_hold), .image_base(image_hold),
        .vision_weights_base(weights_hold), .patch_count(patches_hold),
        .patch_rows(rows_hold), .patch_columns(columns_hold), .patch_index(query_hold),
        .cmd_valid(patch_cmd_valid), .cmd_ready(patch_selected && cmd_ready),
        .cmd_write(), .cmd_addr(patch_addr), .cmd_wdata(),
        .result_valid(patch_selected && result_valid), .result_ready(patch_result_ready),
        .result_data(result_data), .result_error(result_error),
        .output_valid(patch_output_valid), .output_ready(rst_n && state == PATCH_WAIT),
        .output_index(patch_output_index), .output_data(patch_output_data),
        .output_last(patch_output_last), .patch_x(), .patch_y(), .patch_padding(),
        .done_valid(patch_valid), .done_ready(rst_n && state == PATCH_WAIT && !patch_output_valid),
        .done_error(patch_error), .controller_bytes(patch_controller_bytes),
        .input_read_event(patch_input_event), .input_read_bytes(patch_input_bytes)
    );

    wire head_selected = rst_n && (state == HEAD_START || state == HEAD_WAIT);
    wire head_ready, head_valid, head_yield, head_work_valid, head_work_rsp_ready;
    wire head_output_valid, head_output_last, head_cmd_valid, head_result_ready;
    wire head_source_valid, head_source_rsp_ready, need_valid;
    wire [1:0] head_source_model, need_model, need_precision, need_selector;
    wire [7:0] head_source_layer, need_layer, head_dependency_layer;
    wire [31:0] head_source_generation, head_source_patch, head_source_index;
    wire [31:0] need_generation, need_patch, head_dependency_patch;
    wire [3:0] need_head;
    wire [9:0] need_component, head_output_index;
    wire [15:0] head_output_data;
    wire [3:0] head_error;
    wire [159:0] head_outer;
    wire [2:0] head_work_op;
    wire [1:0] head_work_domain, head_work_target;
    wire [31:0] head_work_token, head_work_data;
    wire [7:0] head_work_layer, head_work_scalar;
    wire [11:0] head_work_length, head_work_component;
    wire [5:0] head_work_slot;
    wire head_work_bank;
    wire [63:0] head_addr, tile_live, tile_physical;
    wire need_tag = need_generation == generation_hold && need_model == model_hold &&
        need_precision == precision_hold && need_layer == logical_layer &&
        need_head == head_hold && need_selector <= 2 && need_component < 64;
    wire [1:0] need_action = error_hold != 0 || !need_tag ? 2'd2 :
        (need_patch == query_hold || (dependency_tag && need_patch == dependency_token_hold) ?
            2'd0 : 2'd1);
    anvil_en1_replay_vision_attention attention (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == HEAD_START), .start_ready(head_ready),
        .model(model_hold), .precision(precision_hold), .generation(generation_hold),
        .patches(patches_hold), .patch_rows(rows_hold), .patch_columns(columns_hold),
        .query_patch(query_hold), .layer(logical_layer), .frame_layer(layer_hold),
        .head(head_hold), .frame_slot(slot_hold), .image_base(image_hold),
        .vision_weights_base(weights_hold), .resume_valid(head_resume),
        .continuation(continuation_hold),
        .need_valid(need_valid),
        .need_ready(rst_n && state == HEAD_WAIT && source_state == S_IDLE),
        .need_action(need_action), .need_generation(need_generation), .need_patch(need_patch),
        .need_model(need_model), .need_precision(need_precision), .need_selector(need_selector),
        .need_layer(need_layer), .need_head(need_head), .need_component(need_component),
        .source_valid(head_source_valid),
        .source_ready(rst_n && state == HEAD_WAIT && source_state == S_IDLE),
        .source_generation(head_source_generation), .source_patch(head_source_patch),
        .source_index(head_source_index), .source_model(head_source_model),
        .source_layer(head_source_layer),
        .source_rsp_valid(rst_n && state == HEAD_WAIT && source_state == S_RESPONSE),
        .source_rsp_ready(head_source_rsp_ready), .source_rsp_data(source_data_hold),
        .source_rsp_error(source_error_hold != 0),
        .work_req_valid(head_work_valid),
        .work_req_ready(head_selected && source_state == S_IDLE && work_req_ready),
        .work_req_op(head_work_op), .work_req_domain(head_work_domain),
        .work_req_target(head_work_target), .work_req_token(head_work_token),
        .work_req_layer(head_work_layer), .work_req_length(head_work_length),
        .work_req_component(head_work_component), .work_req_slot(head_work_slot),
        .work_req_bank(head_work_bank), .work_req_scalar_index(head_work_scalar),
        .work_req_data(head_work_data),
        .work_rsp_valid(head_selected && source_state == S_IDLE && work_rsp_valid),
        .work_rsp_ready(head_work_rsp_ready), .work_rsp_data(work_rsp_data),
        .work_rsp_error(work_rsp_error),
        .cmd_valid(head_cmd_valid), .cmd_ready(head_selected && cmd_ready),
        .cmd_write(), .cmd_addr(head_addr), .cmd_wdata(),
        .result_valid(head_selected && result_valid), .result_ready(head_result_ready),
        .result_data(result_data), .result_error(result_error),
        .output_valid(head_output_valid), .output_ready(rst_n && state == HEAD_WAIT),
        .output_index(head_output_index), .output_data(head_output_data),
        .output_last(head_output_last), .done_valid(head_valid),
        .done_ready(rst_n && state == HEAD_WAIT && !head_output_valid && source_state == S_IDLE),
        .done_error(head_error), .done_yield(head_yield), .done_continuation(head_outer),
        .done_dependency_layer(head_dependency_layer), .done_dependency_patch(head_dependency_patch),
        .input_read_event(head_input_event), .input_read_bytes(head_input_bytes),
        .projection_event(projection_event), .projection_bytes(projection_bytes),
        .controller_bytes(replay_controller_bytes), .executor_controller_bytes(executor_controller_bytes),
        .head_controller_bytes(head_controller_bytes), .tile_controller_bytes(tile_controller_bytes),
        .clipped_controller_bytes(clipped_controller_bytes), .clamp_controller_bytes(clamp_controller_bytes),
        .tile_live_bytes(tile_live), .tile_physical_bytes(tile_physical)
    );

    wire projection_selected = rst_n && (state == PROJECTION_START || state == PROJECTION_WAIT);
    wire projection_ready, projection_valid, projection_source_valid, projection_source_rsp_ready;
    wire projection_cmd_valid, projection_result_ready;
    wire [31:0] projection_source_index, projection_data;
    wire [63:0] projection_addr;
    wire [3:0] projection_error;
    anvil_en1_clipped_projection output_projection (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == PROJECTION_START), .start_ready(projection_ready),
        .model(model_hold), .precision(precision_hold), .image_class(2'd1),
        .image_base(weights_hold), .tensor_kind(16'h1106),
        .tensor_layer({8'd0, logical_layer}), .row_index(row_hold),
        .source_valid(projection_source_valid),
        .source_ready(rst_n && state == PROJECTION_WAIT && source_state == S_IDLE),
        .source_index(projection_source_index),
        .source_rsp_valid(rst_n && state == PROJECTION_WAIT && source_state == S_RESPONSE),
        .source_rsp_ready(projection_source_rsp_ready), .source_rsp_data(source_data_hold),
        .source_rsp_error(source_error_hold != 0),
        .cmd_valid(projection_cmd_valid), .cmd_ready(projection_selected && cmd_ready),
        .cmd_write(), .cmd_addr(projection_addr), .cmd_wdata(),
        .result_valid(projection_selected && result_valid), .result_ready(projection_result_ready),
        .result_data(result_data), .result_error(result_error),
        .done_valid(projection_valid),
        .done_ready(rst_n && state == PROJECTION_WAIT && source_state == S_IDLE),
        .done_data(projection_data), .done_error(projection_error),
        .controller_bytes(output_controller_bytes), .clamp_controller_bytes(output_clamp_controller_bytes)
    );

    wire post_selected = rst_n && (state == POST_START || state == POST_WAIT);
    wire post_ready, post_valid, post_source_valid, post_source_branch, post_source_rsp_ready;
    wire post_output_valid, post_output_last, post_cmd_valid, post_result_ready;
    wire [1:0] post_source_model;
    wire [7:0] post_source_layer;
    wire [31:0] post_source_generation, post_source_patch, post_source_index, post_output_index;
    wire [15:0] post_output_data;
    wire [63:0] post_addr, post_live, post_physical;
    wire [3:0] post_error;
    wire post_branch_write, post_branch_read;
    wire [31:0] post_branch_waddr, post_branch_raddr;
    wire [15:0] post_branch_wdata;
    anvil_en1_vision_post_layer #(.EXTERNAL_BRANCH_RAM(1)) post (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == POST_START && error_hold == 0), .start_ready(post_ready),
        .model(model_hold), .precision(precision_hold), .layer(logical_layer),
        .generation(generation_hold), .patch(query_hold), .vision_weights_base(weights_hold),
        .source_valid(post_source_valid),
        .source_ready(rst_n && state == POST_WAIT && source_state == S_IDLE),
        .source_model(post_source_model), .source_layer(post_source_layer),
        .source_generation(post_source_generation), .source_patch(post_source_patch),
        .source_index(post_source_index), .source_is_branch(post_source_branch),
        .source_rsp_valid(rst_n && state == POST_WAIT && source_state == S_RESPONSE),
        .source_rsp_ready(post_source_rsp_ready), .source_rsp_data(source_data_hold),
        .source_rsp_error(source_error_hold != 0),
        .cmd_valid(post_cmd_valid), .cmd_ready(post_selected && cmd_ready),
        .cmd_write(), .cmd_addr(post_addr), .cmd_wdata(),
        .result_valid(post_selected && result_valid), .result_ready(post_result_ready),
        .result_data(result_data), .result_error(result_error),
        .output_valid(post_output_valid),
        .output_ready(rst_n && state == POST_WAIT && source_state == S_IDLE),
        .output_index(post_output_index), .output_data(post_output_data),
        .output_last(post_output_last), .done_valid(post_valid),
        .done_ready(rst_n && state == POST_WAIT && !post_output_valid && source_state == S_IDLE),
        .done_error(post_error), .intermediate_event(intermediate_event),
        .intermediate_bytes(intermediate_bytes),
        .vector_live_bytes(post_live), .vector_physical_bytes(post_physical),
        .branch_ram_write(post_branch_write), .branch_ram_read(post_branch_read),
        .branch_ram_waddr(post_branch_waddr), .branch_ram_raddr(post_branch_raddr),
        .branch_ram_wdata(post_branch_wdata), .branch_ram_rdata(projected_q),
        .controller_bytes(post_controller_bytes), .norm_controller_bytes(norm_controller_bytes),
        .mlp_controller_bytes(mlp_controller_bytes), .down_controller_bytes(down_controller_bytes),
        .down_clamp_controller_bytes(down_clamp_controller_bytes),
        .inner_controller_bytes(inner_controller_bytes), .inner_clamp_controller_bytes(inner_clamp_controller_bytes)
    );

    wire callback_valid = state == HEAD_WAIT ? head_source_valid :
        (state == PROJECTION_WAIT ? projection_source_valid : post_source_valid);
    wire [31:0] callback_index = state == HEAD_WAIT ? head_source_index :
        (state == PROJECTION_WAIT ? projection_source_index : post_source_index);
    wire callback_ready = state == HEAD_WAIT ? head_source_rsp_ready :
        (state == PROJECTION_WAIT ? projection_source_rsp_ready : post_source_rsp_ready);
    wire callback_selected = state == HEAD_WAIT || state == PROJECTION_WAIT || state == POST_WAIT;
    wire callback_tag_good = state == HEAD_WAIT ?
        (head_source_model == model_hold && head_source_generation == generation_hold &&
         head_source_layer == logical_layer && head_source_patch < patches_hold) :
        (state == PROJECTION_WAIT ||
         (post_source_model == model_hold && post_source_generation == generation_hold &&
          post_source_layer == logical_layer && post_source_patch == query_hold));
    wire scalar_selected = state == SAVE_SEND || state == SAVE_WAIT || state == SAVE_REGISTER ||
        state == RESTORE_SEND || state == RESTORE_WAIT || state == RESTORE_REGISTER;
    wire pair_selected = state == PAIR_SEND || state == PAIR_WAIT || state == PAIR_REGISTER;
    wire source_selected = source_state != S_IDLE;
    wire head_work_selected = head_selected && !source_selected;
    wire stream_valid = state == PATCH_WAIT ? patch_output_valid :
        (state == HEAD_WAIT ? head_output_valid : post_output_valid);
    wire [31:0] stream_index = state == PATCH_WAIT ? patch_output_index :
        (state == HEAD_WAIT ? ({28'd0, head_hold} << 6) + {22'd0, head_output_index} :
            post_output_index);
    wire [15:0] stream_data = state == PATCH_WAIT ? patch_output_data :
        (state == HEAD_WAIT ? head_output_data : post_output_data);
    wire stream_last = state == PATCH_WAIT ? patch_output_last :
        (state == HEAD_WAIT ? head_output_last : post_output_last);
    wire stream_good = received < 768 && stream_index == received &&
        (state == HEAD_WAIT ?
            (head_output_index < 64 && stream_last == (head_output_index == 63)) :
            stream_last == (received == 767));
    wire stream_accept = stream_valid && (state == PATCH_WAIT || state == HEAD_WAIT ||
        (state == POST_WAIT && source_state == S_IDLE));
    wire projection_access = state == PROJECTION_STORE || state == COPY_READ;
    wire post_branch_access = post_branch_write || post_branch_read;
    wire branch_access_fault = rst_n &&
        ((projection_access && post_branch_access) ||
         (state == PROJECTION_STORE && row_hold >= 768) ||
         (state == COPY_READ && received >= 768) ||
         (post_branch_access && !post_selected) ||
         (post_branch_write && post_branch_waddr >= 768) ||
         (post_branch_read && post_branch_raddr >= 768) ||
         (projected_allocated && (|tile_live || |post_live)) ||
         (|tile_live && |post_live) ||
         tile_live > 64'd1664 || post_live > 64'd4608);
    wire shared_branch_write = state == PROJECTION_STORE || post_branch_write;
    wire shared_branch_read = state == COPY_READ || post_branch_read;
    wire [31:0] shared_branch_waddr = state == PROJECTION_STORE ?
        row_hold : post_branch_waddr;
    wire [31:0] shared_branch_raddr = state == COPY_READ ?
        received : post_branch_raddr;
    wire [15:0] shared_branch_wdata = state == PROJECTION_STORE ?
        projected_hold[15:0] : post_branch_wdata;
    assign branch_ram_write = rst_n && EXTERNAL_BRANCH_RAM &&
        !branch_access_fault && shared_branch_write;
    assign branch_ram_read = rst_n && EXTERNAL_BRANCH_RAM &&
        !branch_access_fault && shared_branch_read;
    assign branch_ram_waddr = rst_n && EXTERNAL_BRANCH_RAM ? shared_branch_waddr : 32'd0;
    assign branch_ram_raddr = rst_n && EXTERNAL_BRANCH_RAM ? shared_branch_raddr : 32'd0;
    assign branch_ram_wdata = rst_n && EXTERNAL_BRANCH_RAM ? shared_branch_wdata : 16'd0;
    generate if (EXTERNAL_BRANCH_RAM == 1) begin : external_branch
        assign projected_q = branch_ram_rdata;
    end else begin : local_branch
        (* ramstyle = "M20K", nomem2reg *) reg [15:0] projected [0:767];
        reg [15:0] read_q;
        assign projected_q = read_q;
        always @(posedge clk) begin
            if (rst_n && !branch_access_fault) begin
                if (shared_branch_write)
                    projected[shared_branch_waddr[9:0]] <= shared_branch_wdata;
                if (shared_branch_read)
                    read_q <= projected[shared_branch_raddr[9:0]];
            end
        end
    end endgenerate
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            branch_ram_fault <= 0;
        else if (start_valid && start_ready)
            branch_ram_fault <= 0;
        else if (branch_access_fault)
            branch_ram_fault <= 1;
    end

    assign start_ready = rst_n && state == IDLE;
    wire release_selected = state == RELEASE_SEND || state == RELEASE_WAIT ||
        state == RELEASE_REGISTER;
    assign work_req_valid = rst_n && (release_selected ? state == RELEASE_SEND :
        (binding_selected ? binding_work_valid :
        (pair_selected ? state == PAIR_SEND :
         (scalar_selected ? (state == SAVE_SEND || state == RESTORE_SEND) :
          (source_selected ? source_state == S_SEND : (head_work_selected && head_work_valid))))));
    assign work_rsp_ready = rst_n && (release_selected ? state == RELEASE_WAIT :
        (binding_selected ? binding_work_rsp_ready :
        (pair_selected ? state == PAIR_WAIT :
         (scalar_selected ? (state == SAVE_WAIT || state == RESTORE_WAIT) :
          (source_selected ? source_state == S_WAIT : (head_work_selected && head_work_rsp_ready))))));
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
            work_req_domain = 1;
            work_req_token = query_hold;
            work_req_layer = layer_hold;
            work_req_length = 768;
            work_req_slot = slot_hold;
            if (release_selected) begin
                work_req_op = 7;
                work_req_target = 2;
            end else if (binding_selected) begin
                work_req_op = binding_op;
                work_req_domain = binding_domain;
                work_req_target = binding_target;
                work_req_token = binding_token;
                work_req_layer = binding_layer;
                work_req_length = binding_length;
                work_req_component = binding_component;
                work_req_slot = binding_slot;
                work_req_bank = binding_bank;
                work_req_scalar_index = binding_scalar;
                work_req_data = binding_data;
            end else if (pair_selected) begin
                work_req_op = 6;
                work_req_target = 2;
                work_req_bank = pair_return != PATCH_WAIT;
                work_req_component = received[11:0] - 12'd2;
                work_req_data = pair_hold;
            end else if (scalar_selected) begin
                work_req_op = state == RESTORE_SEND || state == RESTORE_WAIT ||
                    state == RESTORE_REGISTER ? 3'd7 : 3'd6;
                work_req_scalar_index = scalar_word == 2 ? 8'd17 :
                    (scalar_word == 1 ? 8'd25 : 8'd24);
                work_req_data = scalar_word == 1 ? {16'd0, low_hold} : received;
            end else if (source_selected) begin
                work_req_op = 4;
                work_req_component = {source_index_hold[11:1], 1'b0};
                work_req_bank = source_bank;
                if (source_dependency) begin
                    work_req_target = 1;
                    work_req_token = dependency_token_hold;
                    work_req_layer = dependency_layer_hold;
                    work_req_slot = dependency_slot_hold;
                end
            end else if (head_work_selected) begin
                work_req_op = head_work_op;
                work_req_domain = head_work_domain;
                work_req_target = head_work_target;
                work_req_token = head_work_token;
                work_req_layer = head_work_layer;
                work_req_length = head_work_length;
                work_req_component = head_work_component;
                work_req_slot = head_work_slot;
                work_req_bank = head_work_bank;
                work_req_scalar_index = head_work_scalar;
                work_req_data = head_work_data;
            end
        end
    end
    assign cmd_valid = patch_selected ? patch_cmd_valid : (head_selected ? head_cmd_valid :
        (projection_selected ? projection_cmd_valid : (post_selected && post_cmd_valid)));
    assign cmd_write = 0;
    assign input_read_event = patch_input_event || head_input_event;
    assign input_read_bytes = patch_input_bytes + head_input_bytes;
    assign cmd_addr = !rst_n ? 64'd0 : (patch_selected ? patch_addr :
        (head_selected ? head_addr : (projection_selected ? projection_addr :
            (post_selected ? post_addr : 64'd0))));
    assign cmd_wdata = 0;
    assign result_ready = patch_selected ? patch_result_ready : (head_selected ? head_result_ready :
        (projection_selected ? projection_result_ready : (post_selected && post_result_ready)));
    assign done_valid = rst_n && state == RESPONSE;
    assign done_error = rst_n ? error_hold : 4'd0;
    assign done_yield = rst_n && yield_hold && error_hold == 0;
    assign done_bank = rst_n && layer_hold != 0;
    assign done_continuation = done_yield ? yield_continuation : 160'd0;
    assign done_dependency_domain = done_yield ? 2'd1 : 2'd0;
    assign done_dependency_layer = done_yield ? logical_layer : 8'd0;
    assign done_dependency_token = done_yield ? yielded_patch : 32'd0;
    assign done_dependency_length = done_yield ? 12'd768 : 12'd0;
    assign source_read_event = rst_n && source_state == S_SEND && work_req_valid && work_req_ready;
    assign source_read_bytes = source_read_event ? 32'd2 : 32'd0;
    assign vector_live_bytes = !rst_n ? 64'd0 :
        (projected_allocated ? 64'd1536 : 64'd0) + tile_live + post_live;
    assign vector_physical_bytes = !rst_n ? 64'd0 :
        (EXTERNAL_BRANCH_RAM ? 64'd0 : 64'd1536) + tile_physical + post_physical;
    localparam integer CONTROLLER_BITS =
        $bits(state) + $bits(pair_return) + $bits(source_state) +
        $bits(model_hold) + $bits(precision_hold) + $bits(mode_hold) +
        $bits(dependency_domain_hold) + $bits(generation_hold) + $bits(patches_hold) +
        $bits(rows_hold) + $bits(columns_hold) + $bits(query_hold) + $bits(extent_hold) +
        $bits(layer_hold) + $bits(dependency_layer_hold) + $bits(slot_hold) +
        $bits(dependency_slot_hold) + $bits(dependency_token_hold) +
        $bits(dependency_length_hold) + $bits(dependency_valid_hold) + $bits(head_resume) +
        $bits(yield_hold) + $bits(scalar_word) + $bits(projected_allocated) +
        $bits(receive_bad) + $bits(projected_visible) + $bits(source_dependency) +
        $bits(source_bank) + $bits(source_bad) + $bits(image_hold) + $bits(weights_hold) +
        $bits(continuation_hold) + $bits(yield_continuation) + $bits(received) +
        $bits(row_hold) + $bits(source_index_hold) + $bits(source_token_hold) +
        $bits(pair_hold) + $bits(scalar_hold) + $bits(source_pair_hold) +
        $bits(projected_hold) + $bits(restored_head_word) +
        $bits(low_hold) + $bits(copy_low) + (EXTERNAL_BRANCH_RAM ? 0 : 16) +
        $bits(source_data_hold) + $bits(head_hold) + $bits(child_error_hold) +
        $bits(error_hold) + $bits(work_error_hold) + $bits(source_error_hold) +
        $bits(yielded_patch) + $bits(branch_ram_fault);
    assign controller_bytes = rst_n ? (CONTROLLER_BITS + 7) >> 3 : 64'd0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            source_state <= S_IDLE;
            source_index_hold <= 0;
            source_token_hold <= 0;
            source_dependency <= 0;
            source_bank <= 0;
            source_bad <= 0;
            source_pair_hold <= 0;
            source_data_hold <= 0;
            source_error_hold <= 0;
        end else begin
            case (source_state)
                S_IDLE: if (callback_selected && callback_valid) begin
                    source_index_hold <= callback_index;
                    source_token_hold <= state == HEAD_WAIT ? head_source_patch : query_hold;
                    source_dependency <= state == HEAD_WAIT && head_source_patch != query_hold;
                    source_bank <= state == PROJECTION_WAIT ||
                        (state == POST_WAIT && post_source_branch);
                    source_bad <= !callback_tag_good;
                    source_data_hold <= 0;
                    source_error_hold <= 0;
                    source_state <= S_VALIDATE;
                end
                S_VALIDATE: begin
                    if (source_bad || source_index_hold >= 768 ||
                        (source_dependency && (!dependency_tag ||
                            source_token_hold != dependency_token_hold))) begin
                        source_error_hold <= 7;
                        source_state <= S_RESPONSE;
                    end else
                        source_state <= S_SEND;
                end
                S_SEND: if (work_req_valid && work_req_ready)
                    source_state <= S_WAIT;
                S_WAIT: if (work_rsp_valid && work_rsp_ready) begin
                    source_pair_hold <= work_rsp_data;
                    source_error_hold <= work_rsp_error;
                    source_state <= S_REGISTER;
                end
                S_REGISTER: begin
                    source_data_hold <= source_error_hold != 0 ? 16'd0 :
                        (source_index_hold[0] ? source_pair_hold[31:16] : source_pair_hold[15:0]);
                    source_state <= S_RESPONSE;
                end
                S_RESPONSE: if (callback_ready)
                    source_state <= S_IDLE;
                default: begin
                    source_error_hold <= 7;
                    source_state <= S_RESPONSE;
                end
            endcase
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            pair_return <= IDLE;
            model_hold <= 0;
            precision_hold <= 0;
            mode_hold <= 0;
            dependency_domain_hold <= 0;
            generation_hold <= 0;
            patches_hold <= 0;
            rows_hold <= 0;
            columns_hold <= 0;
            query_hold <= 0;
            extent_hold <= 0;
            layer_hold <= 0;
            dependency_layer_hold <= 0;
            slot_hold <= 0;
            dependency_slot_hold <= 0;
            dependency_token_hold <= 0;
            dependency_length_hold <= 0;
            dependency_valid_hold <= 0;
            head_resume <= 0;
            yield_hold <= 0;
            scalar_word <= 0;
            projected_allocated <= 0;
            receive_bad <= 0;
            projected_visible <= 0;
            image_hold <= 0;
            weights_hold <= 0;
            continuation_hold <= 0;
            yield_continuation <= 0;
            received <= 0;
            row_hold <= 0;
            pair_hold <= 0;
            scalar_hold <= 0;
            projected_hold <= 0;
            restored_head_word <= 0;
            low_hold <= 0;
            copy_low <= 0;
            head_hold <= 0;
            child_error_hold <= 0;
            error_hold <= 0;
            work_error_hold <= 0;
            yielded_patch <= 0;
        end else begin
            if (source_state == S_RESPONSE && callback_ready && source_error_hold != 0 &&
                error_hold == 0)
                error_hold <= source_error_hold;
            if (stream_accept) begin
                if (!stream_good)
                    receive_bad <= 1;
                if (received < 768)
                    received <= received + 1'b1;
                if (stream_good && error_hold == 0 && !receive_bad) begin
                    if (!received[0])
                        low_hold <= stream_data;
                    else begin
                        pair_hold <= {stream_data, low_hold};
                        pair_return <= state;
                        state <= PAIR_SEND;
                    end
                end
            end
            case (state)
                IDLE: if (start_valid && start_ready) begin
                    model_hold <= model;
                    precision_hold <= precision;
                    mode_hold <= mode;
                    generation_hold <= generation;
                    patches_hold <= patches;
                    rows_hold <= patch_rows;
                    columns_hold <= patch_columns;
                    query_hold <= query_patch;
                    layer_hold <= frame_layer;
                    slot_hold <= frame_slot;
                    image_hold <= image_base;
                    weights_hold <= vision_weights_base;
                    continuation_hold <= continuation;
                    dependency_valid_hold <= dependency_valid;
                    dependency_domain_hold <= dependency_domain;
                    dependency_layer_hold <= dependency_layer;
                    dependency_token_hold <= dependency_token;
                    dependency_length_hold <= dependency_length;
                    dependency_slot_hold <= dependency_slot;
                    head_resume <= 0;
                    yield_hold <= 0;
                    scalar_word <= 0;
                    restored_head_word <= 0;
                    projected_allocated <= 0;
                    projected_visible <= 0;
                    receive_bad <= 0;
                    received <= 0;
                    row_hold <= 0;
                    head_hold <= 0;
                    low_hold <= 0;
                    error_hold <= 0;
                    child_error_hold <= 0;
                    work_error_hold <= 0;
                    yield_continuation <= 0;
                    yielded_patch <= 0;
                    state <= VALIDATE;
                end
                VALIDATE: begin
                    if ((model_hold != 1 && model_hold != 2) || precision_hold > 1) begin
                        error_hold <= 6;
                        state <= PUBLISH;
                    end else if (generation_hold == 0 || patches_hold == 0 || patches_hold > 131072 ||
                        query_hold >= patches_hold || rows_hold == 0 || rows_hold > 10240 ||
                        columns_hold == 0 || columns_hold > 10240 || layer_hold > 16 ||
                        image_hold[1:0] != 0 || weights_hold[1:0] != 0) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else if (mode_hold == 3 ||
                        (layer_hold == 0 && (mode_hold != 0 || continuation_hold != 0)) ||
                        (mode_hold == 1 && (!dependency_valid_hold ||
                            (!input_continuation && !head_continuation))) ||
                        (mode_hold != 1 && continuation_hold != 0)) begin
                        error_hold <= 7;
                        state <= PUBLISH;
                    end else
                        state <= EXTENT_PRODUCT;
                end
                EXTENT_PRODUCT: begin
                    extent_hold <= rows_hold[15:0] * columns_hold[15:0];
                    state <= EXTENT_VALIDATE;
                end
                EXTENT_VALIDATE: begin
                    if (extent_hold != patches_hold) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else if (layer_hold == 0)
                        state <= PATCH_START;
                    else if (mode_hold == 1 && head_continuation) begin
                        if (!dependency_tag) begin
                            error_hold <= 7;
                            state <= PUBLISH;
                        end else begin
                            head_hold <= continuation_hold[37:34];
                            scalar_word <= 0;
                            state <= RESTORE_SEND;
                        end
                    end else
                        state <= BIND_START;
                end
                BIND_START: if (binding_ready)
                    state <= BIND_WAIT;
                BIND_WAIT: if (binding_valid) begin
                    if (binding_error != 0) begin
                        error_hold <= binding_error;
                        state <= PUBLISH;
                    end else if (binding_yield) begin
                        yield_hold <= 1;
                        yielded_patch <= query_hold;
                        yield_continuation <= {INPUT_MAGIC, 128'd0};
                        state <= PUBLISH;
                    end else begin
                        dependency_valid_hold <= 0;
                        state <= HEAD_START;
                    end
                end
                PATCH_START: if (patch_ready)
                    state <= PATCH_WAIT;
                PATCH_WAIT: if (patch_valid && !patch_output_valid) begin
                    child_error_hold <= patch_error;
                    state <= PATCH_CHECK;
                end
                PATCH_CHECK, POST_CHECK: begin
                    if (error_hold == 0) begin
                        if (child_error_hold != 0)
                            error_hold <= child_error_hold;
                        else if (receive_bad || received != 768 || branch_ram_fault)
                            error_hold <= 7;
                    end
                    if (state == POST_CHECK && error_hold == 0 &&
                        child_error_hold == 0 && !receive_bad &&
                        received == 768 && !branch_ram_fault)
                        state <= RELEASE_SEND;
                    else
                        state <= PUBLISH;
                end
                RELEASE_SEND: if (work_req_ready)
                    state <= RELEASE_WAIT;
                RELEASE_WAIT: if (work_rsp_valid) begin
                    work_error_hold <= work_rsp_error;
                    state <= RELEASE_REGISTER;
                end
                RELEASE_REGISTER: begin
                    if (work_error_hold != 0)
                        error_hold <= work_error_hold;
                    state <= PUBLISH;
                end
                HEAD_START: if (head_ready)
                    state <= HEAD_WAIT;
                HEAD_WAIT: if (head_valid && !head_output_valid && source_state == S_IDLE) begin
                    child_error_hold <= head_error;
                    if (head_yield && head_error == 0 && error_hold == 0 && !receive_bad) begin
                        if (head_dependency_layer != logical_layer || head_dependency_patch >= patches_hold ||
                            head_dependency_patch == query_hold) begin
                            error_hold <= 7;
                            state <= PUBLISH;
                        end else begin
                            yielded_patch <= head_dependency_patch;
                            yield_continuation <= head_outer;
                            scalar_word <= 0;
                            state <= SAVE_SEND;
                        end
                    end else
                        state <= HEAD_CHECK;
                end
                HEAD_CHECK: begin
                    if (error_hold != 0 || child_error_hold != 0 || receive_bad ||
                        received != (({28'd0, head_hold} + 32'd1) << 6)) begin
                        if (error_hold == 0)
                            error_hold <= child_error_hold != 0 ? child_error_hold : 4'd7;
                        state <= PUBLISH;
                    end else if (head_hold == 11) begin
                        row_hold <= 0;
                        projected_allocated <= 1;
                        state <= PROJECTION_START;
                    end else begin
                        head_hold <= head_hold + 1'b1;
                        head_resume <= 0;
                        state <= HEAD_START;
                    end
                end
                PAIR_SEND: if (work_req_valid && work_req_ready)
                    state <= PAIR_WAIT;
                PAIR_WAIT: if (work_rsp_valid && work_rsp_ready) begin
                    work_error_hold <= work_rsp_error;
                    state <= PAIR_REGISTER;
                end
                PAIR_REGISTER: begin
                    if (work_error_hold != 0 && error_hold == 0)
                        error_hold <= work_error_hold;
                    state <= pair_return;
                end
                SAVE_SEND: if (work_req_valid && work_req_ready)
                    state <= SAVE_WAIT;
                SAVE_WAIT: if (work_rsp_valid && work_rsp_ready) begin
                    work_error_hold <= work_rsp_error;
                    state <= SAVE_REGISTER;
                end
                SAVE_REGISTER: begin
                    if (work_error_hold != 0) begin
                        error_hold <= work_error_hold;
                        state <= PUBLISH;
                    end else if (scalar_word == 1) begin
                        yield_hold <= 1;
                        state <= PUBLISH;
                    end else begin
                        scalar_word <= 1;
                        state <= SAVE_SEND;
                    end
                end
                RESTORE_SEND: if (work_req_valid && work_req_ready)
                    state <= RESTORE_WAIT;
                RESTORE_WAIT: if (work_rsp_valid && work_rsp_ready) begin
                    scalar_hold <= work_rsp_data;
                    work_error_hold <= work_rsp_error;
                    state <= RESTORE_REGISTER;
                end
                RESTORE_REGISTER: begin
                    if (work_error_hold != 0 || (scalar_word == 1 && scalar_hold[31:16] != 0)) begin
                        error_hold <= work_error_hold != 0 ? work_error_hold : 4'd7;
                        state <= PUBLISH;
                    end else if (scalar_word == 2) begin
                        restored_head_word <= scalar_hold;
                        state <= RESTORE_CHECK;
                    end else if (scalar_word == 1) begin
                        low_hold <= scalar_hold[15:0];
                        scalar_word <= 2;
                        state <= RESTORE_SEND;
                    end else begin
                        received <= scalar_hold;
                        scalar_word <= 1;
                        state <= RESTORE_SEND;
                    end
                end
                RESTORE_CHECK: begin
                    if (received < ({28'd0, head_hold} << 6) ||
                        received >= (({28'd0, head_hold} + 32'd1) << 6) ||
                        received[5:0] != restored_head_word[7:2] ||
                        (restored_head_word[15:14] != 2 && received[5:0] != 0)) begin
                        error_hold <= 7;
                        state <= PUBLISH;
                    end else begin
                        head_resume <= 1;
                        state <= HEAD_START;
                    end
                end
                PROJECTION_START: if (projection_ready)
                    state <= PROJECTION_WAIT;
                PROJECTION_WAIT: if (projection_valid && source_state == S_IDLE) begin
                    child_error_hold <= projection_error;
                    projected_hold <= projection_data;
                    state <= PROJECTION_CHECK;
                end
                PROJECTION_CHECK: begin
                    if (error_hold != 0 || child_error_hold != 0) begin
                        if (error_hold == 0)
                            error_hold <= child_error_hold;
                        state <= PUBLISH;
                    end else
                        state <= PROJECTION_STORE;
                end
                PROJECTION_STORE: state <= PROJECTION_ADVANCE;
                PROJECTION_ADVANCE: begin
                    if (row_hold == 767) begin
                        projected_visible <= 1;
                        received <= 0;
                        state <= COPY_READ;
                    end else begin
                        row_hold <= row_hold + 1'b1;
                        state <= PROJECTION_START;
                    end
                end
                COPY_READ: begin
                    if (error_hold != 0 || !projected_visible || received >= 768) begin
                        if (error_hold == 0)
                            error_hold <= 7;
                        state <= PUBLISH;
                    end else
                        state <= COPY_CAPTURE;
                end
                COPY_CAPTURE: begin
                    if (!received[0]) begin
                        copy_low <= projected_q;
                        received <= received + 1'b1;
                        state <= COPY_READ;
                    end else begin
                        pair_hold <= {projected_q, copy_low};
                        received <= received + 1'b1;
                        state <= COPY_PACK;
                    end
                end
                COPY_PACK: begin
                    pair_return <= COPY_READ;
                    if (received == 768)
                        pair_return <= POST_START;
                    state <= PAIR_SEND;
                end
                POST_START: begin
                    if (error_hold != 0)
                        state <= PUBLISH;
                    else if (post_ready) begin
                        projected_allocated <= 0;
                        projected_visible <= 0;
                        received <= 0;
                        receive_bad <= 0;
                        state <= POST_WAIT;
                    end
                end
                POST_WAIT: if (post_valid && !post_output_valid && source_state == S_IDLE) begin
                    child_error_hold <= post_error;
                    state <= POST_CHECK;
                end
                PUBLISH: begin
                    if (error_hold == 0 && branch_ram_fault)
                        error_hold <= 7;
                    state <= RESPONSE;
                end
                RESPONSE: if (done_ready) begin
                    projected_allocated <= 0;
                    projected_visible <= 0;
                    state <= IDLE;
                end
                default: begin
                    error_hold <= 7;
                    yield_hold <= 0;
                    state <= PUBLISH;
                end
            endcase
        end
    end
endmodule
