module anvil_en1_audio_lightconv #(
    parameter integer EXTERNAL_VECTOR_RAM = 0,
    parameter integer PRECOMPUTED_DEPTHWISE = 0,
    parameter integer RAW_SOURCE_CALLBACK = 0
) (
    input wire image_immutable, image_invalidate,
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] model, precision,
    input wire [7:0] layer,
    input wire [31:0] generation, token,
    input wire [63:0] audio_weights_base,
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
    output wire [31:0] output_index,
    output wire [15:0] output_data,
    output wire output_last,
    output wire done_valid,
    input wire done_ready,
    output wire [3:0] done_error,
    output wire weight_read_event,
    output wire [31:0] weight_read_bytes,
    output wire projection_event,
    output wire [31:0] projection_bytes,
    output wire glu_replay_event,
    output wire [31:0] glu_replay_bytes,
    output wire [63:0] vector_live_bytes, vector_physical_bytes,
    output wire [2:0] vector_ram_write, vector_ram_read,
    output wire [95:0] vector_ram_waddr, vector_ram_raddr,
    output wire [47:0] vector_ram_wdata,
    input wire [47:0] vector_ram_rdata,
    output wire [63:0] controller_bytes, nested_controller_bytes
);
    localparam [5:0] IDLE = 0, VALIDATE = 1, SOURCE_SEND = 2,
        SOURCE_WAIT = 3, SOURCE_REGISTER = 4, INPUT_STORE = 5, INPUT_ADVANCE = 6,
        CONV_START = 7, CONV_WAIT = 8, CONV_CHECK = 9, CONV_STORE = 10,
        CONV_ADVANCE = 11, WORK_READ = 12, WORK_CAPTURE = 13,
        CLAMP_START = 14, CLAMP_WAIT = 15, WORK_STORE = 16, WORK_ADVANCE = 17,
        NORM_START = 18, NORM_WAIT = 19, NORM_CHECK = 20,
        ACTIVATION_START = 21, ACTIVATION_WAIT = 22, ACTIVATION_NARROW = 23,
        PROJECTION_START = 24, PROJECTION_WAIT = 25, PROJECTION_CHECK = 26,
        RESIDUAL_READ = 27, RESIDUAL_CAPTURE = 28, RESIDUAL_NARROW = 29,
        OUTPUT_REGISTER = 30, EMIT = 31, OUTPUT_ADVANCE = 32,
        FP_START = 33, FP_WAIT = 34, PUBLISH = 35, RESPONSE = 36,
        DEPTHWISE_SEND = 37, DEPTHWISE_WAIT = 38, DEPTHWISE_REGISTER = 39;
    localparam [2:0] S_IDLE = 0, S_VALIDATE = 1, S_READ = 2,
        S_CAPTURE = 3, S_RESPONSE = 4;
    localparam [2:0] D_IDLE = 0, D_VALIDATE = 1, D_START = 2,
        D_WAIT = 3, D_CHECK = 4, D_RESPONSE = 5;
    reg [5:0] state, fp_return;
    reg [2:0] source_state, dependency_state;
    reg [1:0] model_hold, precision_hold, dependency_model;
    reg [7:0] layer_hold, dependency_layer;
    reg [31:0] generation_hold, token_hold, index_hold, received, bank_index;
    reg [31:0] dependency_generation, dependency_token, dependency_channel;
    reg [63:0] weights_hold;
    reg vector_allocated, raw_visible, working_visible, activation_phase;
    reg source_error_hold, receive_bad, bank_error;
    reg [15:0] source_hold, conv_hold, work_hold, output_hold;
    reg [15:0] bank_data, dependency_data;
    wire [15:0] raw_q, work_q;
    wire [15:0] callback_q = work_q;
    reg [31:0] projection_hold, fp_a, fp_b, fp_value;
    reg [2:0] fp_op;
    reg [3:0] child_error_hold, error_hold;
    reg [3:0] dependency_child_error, dependency_error, dependency_failure;
    initial begin
        if (EXTERNAL_VECTOR_RAM != 0 && EXTERNAL_VECTOR_RAM != 1)
            $fatal(1, "PARAMETER ERROR: EXTERNAL_VECTOR_RAM must be 0 or 1");
        if (PRECOMPUTED_DEPTHWISE != 0 && PRECOMPUTED_DEPTHWISE != 1)
            $fatal(1, "PARAMETER ERROR: PRECOMPUTED_DEPTHWISE must be 0 or 1");
        if (RAW_SOURCE_CALLBACK != 0 && RAW_SOURCE_CALLBACK != 1)
            $fatal(1, "PARAMETER ERROR: RAW_SOURCE_CALLBACK must be 0 or 1");
    end

    wire glu_selected = rst_n && (dependency_state == D_START || dependency_state == D_WAIT);
    wire conv_selected = rst_n && !glu_selected &&
        (state == CONV_START || state == CONV_WAIT);
    wire conv_ready, conv_valid, conv_cmd_valid, conv_result_ready;
    wire dependency_valid, dependency_rsp_ready;
    wire [1:0] dependency_req_model;
    wire [7:0] dependency_req_layer;
    wire [31:0] dependency_req_generation, dependency_req_token, dependency_req_channel;
    wire [31:0] conv_data, conv_weight_bytes, conv_projection_bytes;
    wire [63:0] conv_addr, conv_controller;
    wire [3:0] conv_error;
    wire conv_weight_event, conv_projection_event;
    generate if (PRECOMPUTED_DEPTHWISE == 0) begin : computed_depthwise
    anvil_en1_audio_depthwise_row convolution (
        .image_immutable(image_immutable === 1'b1),
        .image_invalidate((image_invalidate === 1'b1)),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && PRECOMPUTED_DEPTHWISE == 0 && state == CONV_START),
        .start_ready(conv_ready),
        .model(model_hold), .precision(precision_hold), .layer(layer_hold),
        .generation(generation_hold), .token(token_hold), .channel(index_hold),
        .audio_weights_base(weights_hold),
        .source_valid(dependency_valid),
        .source_ready(rst_n && state == CONV_WAIT && dependency_state == D_IDLE),
        .source_model(dependency_req_model), .source_layer(dependency_req_layer),
        .source_generation(dependency_req_generation),
        .source_token(dependency_req_token), .source_channel(dependency_req_channel),
        .source_rsp_valid(rst_n && state == CONV_WAIT && dependency_state == D_RESPONSE),
        .source_rsp_ready(dependency_rsp_ready), .source_rsp_data(dependency_data),
        .source_rsp_error(dependency_error != 0),
        .cmd_valid(conv_cmd_valid), .cmd_ready(conv_selected && cmd_ready),
        .cmd_write(), .cmd_addr(conv_addr), .cmd_wdata(),
        .result_valid(conv_selected && result_valid), .result_ready(conv_result_ready),
        .result_data(result_data), .result_error(result_error),
        .done_valid(conv_valid),
        .done_ready(rst_n && state == CONV_WAIT && dependency_state == D_IDLE),
        .done_data(conv_data), .done_error(conv_error),
        .weight_read_event(conv_weight_event), .weight_read_bytes(conv_weight_bytes),
        .projection_event(conv_projection_event), .projection_bytes(conv_projection_bytes),
        .source_read_event(), .source_read_bytes(), .controller_bytes(conv_controller)
    );
    end else begin : supplied_depthwise
        assign conv_ready = 0;
        assign conv_valid = 0;
        assign conv_cmd_valid = 0;
        assign conv_result_ready = 0;
        assign dependency_valid = 0;
        assign dependency_rsp_ready = 0;
        assign dependency_req_model = 0;
        assign dependency_req_layer = 0;
        assign dependency_req_generation = 0;
        assign dependency_req_token = 0;
        assign dependency_req_channel = 0;
        assign conv_data = 0;
        assign conv_weight_bytes = 0;
        assign conv_projection_bytes = 0;
        assign conv_addr = 0;
        assign conv_controller = 0;
        assign conv_error = 0;
        assign conv_weight_event = 0;
        assign conv_projection_event = 0;
    end endgenerate
    wire glu_ready, glu_valid, glu_cmd_valid, glu_result_ready;
    wire glu_source_valid, glu_source_rsp_ready, glu_weight_event, glu_projection_event;
    wire [1:0] glu_source_model;
    wire [7:0] glu_source_layer;
    wire [31:0] glu_source_generation, glu_source_token, glu_source_index;
    wire [31:0] glu_data, glu_weight_bytes, glu_projection_bytes;
    wire [63:0] glu_addr, glu_live, glu_physical, glu_controller;
    wire [63:0] glu_norm_controller, glu_projection_controller, glu_clamp_controller;
    wire [3:0] glu_error;
    wire glu_ram_write, glu_ram_read;
    wire [31:0] glu_ram_waddr, glu_ram_raddr;
    wire [15:0] glu_ram_wdata;
    generate if (PRECOMPUTED_DEPTHWISE == 0) begin : computed_gated_input
    anvil_en1_audio_glu_component #(
        .EXTERNAL_VECTOR_RAM(EXTERNAL_VECTOR_RAM)
    ) gated_input (
        .image_immutable(image_immutable === 1'b1),
        .image_invalidate((image_invalidate === 1'b1)),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && dependency_state == D_START), .start_ready(glu_ready),
        .model(dependency_model), .precision(precision_hold), .layer(dependency_layer),
        .generation(dependency_generation), .token(dependency_token),
        .channel(dependency_channel), .audio_weights_base(weights_hold),
        .source_valid(glu_source_valid), .source_ready(glu_selected && source_ready),
        .source_model(glu_source_model), .source_layer(glu_source_layer),
        .source_generation(glu_source_generation), .source_token(glu_source_token),
        .source_index(glu_source_index),
        .source_rsp_valid(glu_selected && source_rsp_valid),
        .source_rsp_ready(glu_source_rsp_ready),
        .source_rsp_data(source_rsp_data), .source_rsp_error(source_rsp_error),
        .cmd_valid(glu_cmd_valid), .cmd_ready(glu_selected && cmd_ready),
        .cmd_write(), .cmd_addr(glu_addr), .cmd_wdata(),
        .result_valid(glu_selected && result_valid), .result_ready(glu_result_ready),
        .result_data(result_data), .result_error(result_error),
        .done_valid(glu_valid), .done_ready(rst_n && dependency_state == D_WAIT),
        .done_data(glu_data), .done_error(glu_error),
        .weight_read_event(glu_weight_event), .weight_read_bytes(glu_weight_bytes),
        .projection_event(glu_projection_event), .projection_bytes(glu_projection_bytes),
        .vector_live_bytes(glu_live), .vector_physical_bytes(glu_physical),
        .vector_ram_write(glu_ram_write), .vector_ram_read(glu_ram_read),
        .vector_ram_waddr(glu_ram_waddr), .vector_ram_raddr(glu_ram_raddr),
        .vector_ram_wdata(glu_ram_wdata), .vector_ram_rdata(vector_ram_rdata[47:32]),
        .controller_bytes(glu_controller), .norm_controller_bytes(glu_norm_controller),
        .projection_controller_bytes(glu_projection_controller),
        .clamp_controller_bytes(glu_clamp_controller)
    );
    end else begin : supplied_gated_input
        assign glu_ready = 0;
        assign glu_valid = 0;
        assign glu_cmd_valid = 0;
        assign glu_result_ready = 0;
        assign glu_source_valid = 0;
        assign glu_source_rsp_ready = 0;
        assign glu_weight_event = 0;
        assign glu_projection_event = 0;
        assign glu_source_model = 0;
        assign glu_source_layer = 0;
        assign glu_source_generation = 0;
        assign glu_source_token = 0;
        assign glu_source_index = 0;
        assign glu_data = 0;
        assign glu_weight_bytes = 0;
        assign glu_projection_bytes = 0;
        assign glu_addr = 0;
        assign glu_live = 0;
        assign glu_physical = 0;
        assign glu_controller = 0;
        assign glu_norm_controller = 0;
        assign glu_projection_controller = 0;
        assign glu_clamp_controller = 0;
        assign glu_error = 0;
        assign glu_ram_write = 0;
        assign glu_ram_read = 0;
        assign glu_ram_waddr = 0;
        assign glu_ram_raddr = 0;
        assign glu_ram_wdata = 0;
    end endgenerate
    wire norm_selected = rst_n && (state == NORM_START || state == NORM_WAIT);
    wire norm_ready, norm_valid, norm_cmd_valid, norm_result_ready;
    wire norm_source_valid, norm_source_rsp_ready, norm_output_valid, norm_output_last;
    wire [31:0] norm_source_index, norm_output_index;
    wire [15:0] norm_output_data;
    wire [63:0] norm_addr, norm_controller;
    wire [3:0] norm_error;
    anvil_en1_native_norm norm (
        .image_immutable(image_immutable === 1'b1),
        .image_invalidate((image_invalidate === 1'b1)),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == NORM_START), .start_ready(norm_ready),
        .model(model_hold), .precision(precision_hold), .image_class(2'd2),
        .tensor_kind(16'h210f), .tensor_layer({8'd0, layer_hold}),
        .vector_length(32'd1024), .weights_base(weights_hold),
        .source_valid(norm_source_valid),
        .source_ready(rst_n && state == NORM_WAIT && source_state == S_IDLE),
        .source_index(norm_source_index),
        .source_rsp_valid(rst_n && state == NORM_WAIT && source_state == S_RESPONSE),
        .source_rsp_ready(norm_source_rsp_ready),
        .source_rsp_data(bank_data), .source_rsp_error(bank_error),
        .cmd_valid(norm_cmd_valid), .cmd_ready(norm_selected && cmd_ready),
        .cmd_write(), .cmd_addr(norm_addr), .cmd_wdata(),
        .result_valid(norm_selected && result_valid), .result_ready(norm_result_ready),
        .result_data(result_data), .result_error(result_error),
        .output_valid(norm_output_valid), .output_ready(rst_n && state == NORM_WAIT),
        .output_index(norm_output_index), .output_data(norm_output_data),
        .output_last(norm_output_last), .done_valid(norm_valid),
        .done_ready(rst_n && state == NORM_WAIT && source_state == S_IDLE),
        .done_error(norm_error), .controller_bytes(norm_controller)
    );
    wire projection_selected = rst_n &&
        (state == PROJECTION_START || state == PROJECTION_WAIT);
    wire projection_ready, projection_valid, projection_cmd_valid, projection_result_ready;
    wire projection_source_valid, projection_source_rsp_ready;
    wire [31:0] projection_index, projection_data;
    wire [63:0] projection_addr, projection_controller, projection_clamp_controller;
    wire [3:0] projection_error;
    anvil_en1_clipped_projection projection (
        .image_immutable(image_immutable === 1'b1),
        .image_invalidate((image_invalidate === 1'b1)),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == PROJECTION_START), .start_ready(projection_ready),
        .model(model_hold), .precision(precision_hold), .image_class(2'd2),
        .image_base(weights_hold), .tensor_kind(16'h2110),
        .tensor_layer({8'd0, layer_hold}), .row_index(index_hold),
        .source_valid(projection_source_valid),
        .source_ready(rst_n && state == PROJECTION_WAIT && source_state == S_IDLE),
        .source_index(projection_index),
        .source_rsp_valid(rst_n && state == PROJECTION_WAIT && source_state == S_RESPONSE),
        .source_rsp_ready(projection_source_rsp_ready),
        .source_rsp_data(bank_data), .source_rsp_error(bank_error),
        .cmd_valid(projection_cmd_valid), .cmd_ready(projection_selected && cmd_ready),
        .cmd_write(), .cmd_addr(projection_addr), .cmd_wdata(),
        .result_valid(projection_selected && result_valid),
        .result_ready(projection_result_ready), .result_data(result_data),
        .result_error(result_error), .done_valid(projection_valid),
        .done_ready(rst_n && state == PROJECTION_WAIT && source_state == S_IDLE),
        .done_data(projection_data), .done_error(projection_error),
        .controller_bytes(projection_controller),
        .clamp_controller_bytes(projection_clamp_controller)
    );
    wire clamp_ready, clamp_valid;
    wire [15:0] clamp_data;
    wire [3:0] clamp_error;
    wire [63:0] clamp_controller;
    anvil_en1_bf16_clamp clamp (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == CLAMP_START), .start_ready(clamp_ready),
        .value(work_hold), .minimum(16'hd015), .maximum(16'h5015),
        .done_valid(clamp_valid), .done_ready(rst_n && state == CLAMP_WAIT),
        .done_data(clamp_data), .done_error(clamp_error),
        .controller_bytes(clamp_controller)
    );
    wire activation_ready, activation_valid, fp_ready, fp_valid;
    wire [31:0] activation_data, fp_data;
    wire [3:0] activation_error, fp_error;
    wire [63:0] primitive_activation_bytes, primitive_fp_bytes;
    anvil_en1_activation activation (
        .controller_bytes(primitive_activation_bytes),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == ACTIVATION_START), .start_ready(activation_ready),
        .operation(2'd2), .operand({work_hold, 16'd0}),
        .done_valid(activation_valid), .done_ready(rst_n && state == ACTIVATION_WAIT),
        .done_data(activation_data), .done_error(activation_error)
    );
    anvil_en1_fp32 arithmetic (
        .controller_bytes(primitive_fp_bytes),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == FP_START), .start_ready(fp_ready),
        .operation(fp_op), .operand_a(fp_a), .operand_b(fp_b),
        .done_valid(fp_valid), .done_ready(rst_n && state == FP_WAIT),
        .done_data(fp_data), .done_error(fp_error)
    );
    wire norm_beat_good = received < 1024 && norm_output_index == received &&
        norm_output_last == (received == 1023);
    wire bank_callback_valid = state == NORM_WAIT ? norm_source_valid : projection_source_valid;
    wire [31:0] bank_callback_index = state == NORM_WAIT ? norm_source_index : projection_index;
    wire bank_callback_ready = state == NORM_WAIT ? norm_source_rsp_ready : projection_source_rsp_ready;
    wire dependency_tags_good = dependency_model == model_hold &&
        dependency_layer == layer_hold && dependency_generation == generation_hold &&
        dependency_token <= token_hold && dependency_channel == index_hold &&
        dependency_channel < 1024;
    wire norm_store = rst_n && state == NORM_WAIT && norm_output_valid &&
        norm_beat_good && !receive_bad;
    wire callback_read = rst_n && (state == NORM_WAIT || state == PROJECTION_WAIT) &&
        source_state == S_READ;
    wire [1:0] bank_write = {rst_n &&
        (state == CONV_STORE || state == WORK_STORE || norm_store),
        rst_n && !RAW_SOURCE_CALLBACK && state == INPUT_STORE};
    wire [1:0] bank_read = {rst_n && (state == WORK_READ || callback_read),
        rst_n && !RAW_SOURCE_CALLBACK && state == RESIDUAL_READ};
    wire [63:0] bank_waddr = {norm_store ? norm_output_index : index_hold, index_hold};
    wire [63:0] bank_raddr = {callback_read ? bank_index : index_hold, index_hold};
    wire [31:0] bank_wdata = {state == CONV_STORE ? conv_hold :
        (state == WORK_STORE ? work_hold : norm_output_data), source_hold};
    assign vector_ram_write = EXTERNAL_VECTOR_RAM ? {glu_ram_write, bank_write} : 3'd0;
    assign vector_ram_read = EXTERNAL_VECTOR_RAM ? {glu_ram_read, bank_read} : 3'd0;
    assign vector_ram_waddr = rst_n && EXTERNAL_VECTOR_RAM ?
        {glu_ram_waddr, bank_waddr} : 96'd0;
    assign vector_ram_raddr = rst_n && EXTERNAL_VECTOR_RAM ?
        {glu_ram_raddr, bank_raddr} : 96'd0;
    assign vector_ram_wdata = rst_n && EXTERNAL_VECTOR_RAM ?
        {glu_ram_wdata, bank_wdata} : 48'd0;
    generate if (EXTERNAL_VECTOR_RAM == 1) begin : external_vectors
        assign raw_q = vector_ram_rdata[15:0];
        assign work_q = vector_ram_rdata[31:16];
    end else begin : local_vectors
        (* ramstyle = "M20K", nomem2reg *) reg [15:0] working [0:1023];
        reg [15:0] working_read_q;
        assign work_q = working_read_q;
        if (RAW_SOURCE_CALLBACK == 0) begin : retained_raw
            (* ramstyle = "M20K", nomem2reg *) reg [15:0] residual [0:1023];
            reg [15:0] residual_read_q;
            assign raw_q = residual_read_q;
            always @(posedge clk) begin
                if (bank_write[0] && bank_waddr[31:0] < 1024)
                    residual[bank_waddr[9:0]] <= bank_wdata[15:0];
                if (bank_read[0] && bank_raddr[31:0] < 1024)
                    residual_read_q <= residual[bank_raddr[9:0]];
            end
        end else begin : callback_raw
            assign raw_q = 16'd0;
        end
        always @(posedge clk) begin
            if (bank_write[1] && bank_waddr[63:32] < 1024)
                working[bank_waddr[41:32]] <= bank_wdata[31:16];
            if (bank_read[1] && bank_raddr[63:32] < 1024)
                working_read_q <= working[bank_raddr[41:32]];
        end
    end endgenerate
    assign start_ready = rst_n && state == IDLE;
    assign source_valid = !rst_n ? 1'b0 :
        (glu_selected ? glu_source_valid :
            (state == SOURCE_SEND || state == DEPTHWISE_SEND));
    assign source_rsp_ready = !rst_n ? 1'b0 :
        (glu_selected ? glu_source_rsp_ready :
            (state == SOURCE_WAIT || state == DEPTHWISE_WAIT));
    assign source_model = !rst_n ? 2'd0 : (glu_selected ? glu_source_model : model_hold);
    assign source_layer = !rst_n ? 8'd0 : (glu_selected ? glu_source_layer : layer_hold);
    assign source_generation = !rst_n ? 32'd0 :
        (glu_selected ? glu_source_generation : generation_hold);
    assign source_token = !rst_n ? 32'd0 : (glu_selected ? glu_source_token : token_hold);
    assign source_index = !rst_n ? 32'd0 : (glu_selected ? glu_source_index :
        (PRECOMPUTED_DEPTHWISE != 0 &&
            (state == DEPTHWISE_SEND || state == DEPTHWISE_WAIT ||
             state == DEPTHWISE_REGISTER) ? index_hold + 32'd1024 : index_hold));
    assign cmd_valid = !rst_n ? 1'b0 : (glu_selected ? glu_cmd_valid :
        (conv_selected ? conv_cmd_valid : (norm_selected ? norm_cmd_valid :
        (projection_selected && projection_cmd_valid))));
    assign cmd_write = 0;
    assign cmd_addr = !rst_n ? 64'd0 : (glu_selected ? glu_addr :
        (conv_selected ? conv_addr : (norm_selected ? norm_addr :
        (projection_selected ? projection_addr : 64'd0))));
    assign cmd_wdata = 0;
    assign result_ready = !rst_n ? 1'b0 : (glu_selected ? glu_result_ready :
        (conv_selected ? conv_result_ready : (norm_selected ? norm_result_ready :
        (projection_selected && projection_result_ready))));
    assign output_valid = rst_n && state == EMIT;
    assign output_index = rst_n ? index_hold : 32'd0;
    assign output_data = rst_n ? output_hold : 16'd0;
    assign output_last = rst_n && state == EMIT && index_hold == 1023;
    assign done_valid = rst_n && state == RESPONSE;
    assign done_error = rst_n ? error_hold : 4'd0;
    assign weight_read_event = cmd_valid && cmd_ready;
    assign weight_read_bytes = weight_read_event ? 32'd4 : 32'd0;
    wire end_projection_event = rst_n && state == PROJECTION_START && projection_ready;
    assign projection_event = conv_projection_event || glu_projection_event || end_projection_event;
    assign projection_bytes = conv_projection_bytes + glu_projection_bytes +
        (end_projection_event ? (precision_hold == 0 ? 32'd2048 : 32'd576) : 32'd0);
    assign glu_replay_event = rst_n && dependency_state == D_START && glu_ready;
    assign glu_replay_bytes = glu_replay_event ? 32'd2048 : 32'd0;
    assign vector_live_bytes = !rst_n ? 64'd0 :
        (vector_allocated ? (RAW_SOURCE_CALLBACK ? 64'd2048 : 64'd4096) : 64'd0) +
            glu_live;
    assign vector_physical_bytes = rst_n ?
        (EXTERNAL_VECTOR_RAM ? 64'd0 :
            (RAW_SOURCE_CALLBACK ? 64'd2048 : 64'd4096)) + glu_physical : 64'd0;
    assign nested_controller_bytes = rst_n ?
        conv_controller + glu_controller + glu_norm_controller +
        glu_projection_controller + glu_clamp_controller + norm_controller +
        projection_controller + projection_clamp_controller + clamp_controller : 64'd0;
    wire [31:0] CONTROLLER_BITS =
        $bits(state) + $bits(fp_return) + $bits(source_state) + $bits(dependency_state) +
        $bits(model_hold) + $bits(precision_hold) + $bits(dependency_model) +
        $bits(layer_hold) + $bits(dependency_layer) + $bits(generation_hold) +
        $bits(token_hold) + $bits(index_hold) + $bits(received) + $bits(bank_index) +
        $bits(dependency_generation) + $bits(dependency_token) +
        $bits(dependency_channel) + $bits(weights_hold) + $bits(vector_allocated) +
        $bits(raw_visible) + $bits(working_visible) + $bits(activation_phase) +
        $bits(source_error_hold) + $bits(receive_bad) + $bits(bank_error) +
        $bits(source_hold) + $bits(conv_hold) + $bits(work_hold) + $bits(output_hold) +
        (EXTERNAL_VECTOR_RAM ? 0 : (RAW_SOURCE_CALLBACK ? 16 : 32)) + $bits(bank_data) +
        $bits(dependency_data) + $bits(projection_hold) + $bits(fp_a) + $bits(fp_b) +
        $bits(fp_value) + $bits(fp_op) + $bits(child_error_hold) + $bits(error_hold) +
        $bits(dependency_child_error) + $bits(dependency_error) + $bits(dependency_failure);
    assign controller_bytes = !rst_n ? 64'd0 : 64'((CONTROLLER_BITS + 7) >> 3) +
        primitive_activation_bytes + primitive_fp_bytes;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dependency_state <= D_IDLE;
            dependency_model <= 0;
            dependency_layer <= 0;
            dependency_generation <= 0;
            dependency_token <= 0;
            dependency_channel <= 0;
            dependency_data <= 0;
            dependency_child_error <= 0;
            dependency_error <= 0;
            dependency_failure <= 0;
        end else begin
            if (state == IDLE && start_valid && start_ready)
                dependency_failure <= 0;
            case (dependency_state)
                D_IDLE: if (state == CONV_WAIT && dependency_valid) begin
                    dependency_model <= dependency_req_model;
                    dependency_layer <= dependency_req_layer;
                    dependency_generation <= dependency_req_generation;
                    dependency_token <= dependency_req_token;
                    dependency_channel <= dependency_req_channel;
                    dependency_data <= 0;
                    dependency_child_error <= 0;
                    dependency_error <= 0;
                    dependency_state <= D_VALIDATE;
                end
                D_VALIDATE: begin
                    if (dependency_failure != 0) begin
                        dependency_error <= dependency_failure;
                        dependency_state <= D_RESPONSE;
                    end else if (!dependency_tags_good) begin
                        dependency_error <= 7;
                        dependency_failure <= 7;
                        dependency_state <= D_RESPONSE;
                    end else if (token_hold - dependency_token > 4) begin
                        dependency_error <= 7;
                        dependency_failure <= 7;
                        dependency_state <= D_RESPONSE;
                    end else
                        dependency_state <= D_START;
                end
                D_START: if (glu_ready)
                    dependency_state <= D_WAIT;
                D_WAIT: if (glu_valid) begin
                    dependency_data <= glu_data[15:0];
                    dependency_child_error <= glu_error;
                    dependency_state <= D_CHECK;
                end
                D_CHECK: begin
                    if (dependency_child_error != 0) begin
                        dependency_error <= dependency_child_error;
                        dependency_failure <= dependency_child_error;
                        dependency_data <= 0;
                    end
                    dependency_state <= D_RESPONSE;
                end
                D_RESPONSE: if (state == CONV_WAIT && dependency_rsp_ready)
                    dependency_state <= D_IDLE;
                default: begin
                    dependency_data <= 0;
                    dependency_error <= 7;
                    dependency_failure <= 7;
                    dependency_state <= D_RESPONSE;
                end
            endcase
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            source_state <= S_IDLE;
            bank_index <= 0;
            bank_data <= 0;
            bank_error <= 0;
        end else begin
            case (source_state)
                S_IDLE: if ((state == NORM_WAIT || state == PROJECTION_WAIT) &&
                    bank_callback_valid) begin
                    bank_index <= bank_callback_index;
                    bank_error <= 0;
                    bank_data <= 0;
                    source_state <= S_VALIDATE;
                end
                S_VALIDATE: begin
                    if (bank_index >= 1024 || !working_visible) begin
                        bank_error <= 1;
                        source_state <= S_RESPONSE;
                    end else
                        source_state <= S_READ;
                end
                S_READ: source_state <= S_CAPTURE;
                S_CAPTURE: begin
                    bank_data <= callback_q;
                    source_state <= S_RESPONSE;
                end
                S_RESPONSE: if ((state == NORM_WAIT || state == PROJECTION_WAIT) &&
                    bank_callback_ready)
                    source_state <= S_IDLE;
                default: begin
                    bank_error <= 1;
                    source_state <= S_RESPONSE;
                end
            endcase
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            fp_return <= 0;
            model_hold <= 0;
            precision_hold <= 0;
            layer_hold <= 0;
            generation_hold <= 0;
            token_hold <= 0;
            index_hold <= 0;
            received <= 0;
            weights_hold <= 0;
            vector_allocated <= 0;
            raw_visible <= 0;
            working_visible <= 0;
            activation_phase <= 0;
            source_error_hold <= 0;
            receive_bad <= 0;
            source_hold <= 0;
            conv_hold <= 0;
            work_hold <= 0;
            output_hold <= 0;
            projection_hold <= 0;
            fp_a <= 0;
            fp_b <= 0;
            fp_value <= 0;
            fp_op <= 0;
            child_error_hold <= 0;
            error_hold <= 0;
        end else begin
            if (state == NORM_WAIT && norm_output_valid) begin
                if (!norm_beat_good)
                    receive_bad <= 1;
                if (received < 1024)
                    received <= received + 1'b1;
            end
            case (state)
                IDLE: if (start_valid && start_ready) begin
                    model_hold <= model;
                    precision_hold <= precision;
                    layer_hold <= layer;
                    generation_hold <= generation;
                    token_hold <= token;
                    weights_hold <= audio_weights_base;
                    index_hold <= 0;
                    received <= 0;
                    vector_allocated <= 1;
                    raw_visible <= 0;
                    working_visible <= 0;
                    activation_phase <= 0;
                    receive_bad <= 0;
                    output_hold <= 0;
                    child_error_hold <= 0;
                    error_hold <= 0;
                    state <= VALIDATE;
                end
                VALIDATE: begin
                    if ((model_hold != 1 && model_hold != 2) || precision_hold > 1) begin
                        error_hold <= 6;
                        state <= PUBLISH;
                    end else if (layer_hold >= 12 || generation_hold == 0 ||
                        token_hold > 131071 || weights_hold[1:0] != 0) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else if (RAW_SOURCE_CALLBACK) begin
                        raw_visible <= 1;
                        state <= CONV_START;
                    end else
                        state <= SOURCE_SEND;
                end
                SOURCE_SEND: if (source_ready)
                    state <= SOURCE_WAIT;
                SOURCE_WAIT: if (source_rsp_valid) begin
                    source_hold <= source_rsp_data;
                    source_error_hold <= source_rsp_error;
                    state <= SOURCE_REGISTER;
                end
                SOURCE_REGISTER: begin
                    if (source_error_hold) begin
                        error_hold <= 7;
                        state <= PUBLISH;
                    end else if (RAW_SOURCE_CALLBACK) begin
                        fp_a <= {source_hold, 16'd0};
                        fp_b <= {projection_hold[15:0], 16'd0};
                        fp_op <= 0;
                        fp_return <= RESIDUAL_NARROW;
                        state <= FP_START;
                    end else
                        state <= INPUT_STORE;
                end
                INPUT_STORE: state <= INPUT_ADVANCE;
                INPUT_ADVANCE: begin
                    if (index_hold == 1023) begin
                        raw_visible <= 1;
                        index_hold <= 0;
                        state <= CONV_START;
                    end else begin
                        index_hold <= index_hold + 1'b1;
                        state <= SOURCE_SEND;
                    end
                end
                CONV_START: begin
                    if (PRECOMPUTED_DEPTHWISE != 0)
                        state <= DEPTHWISE_SEND;
                    else if (conv_ready)
                        state <= CONV_WAIT;
                end
                DEPTHWISE_SEND: if (source_ready)
                    state <= DEPTHWISE_WAIT;
                DEPTHWISE_WAIT: if (source_rsp_valid) begin
                    conv_hold <= source_rsp_data;
                    source_error_hold <= source_rsp_error;
                    state <= DEPTHWISE_REGISTER;
                end
                DEPTHWISE_REGISTER: begin
                    if (source_error_hold) begin
                        error_hold <= 7;
                        state <= PUBLISH;
                    end else
                        state <= CONV_STORE;
                end
                CONV_WAIT: if (conv_valid && dependency_state == D_IDLE) begin
                    conv_hold <= conv_data[15:0];
                    child_error_hold <= conv_error;
                    state <= CONV_CHECK;
                end
                CONV_CHECK: begin
                    if (dependency_failure != 0) begin
                        error_hold <= dependency_failure;
                        state <= PUBLISH;
                    end else if (child_error_hold != 0) begin
                        error_hold <= child_error_hold;
                        state <= PUBLISH;
                    end else
                        state <= CONV_STORE;
                end
                CONV_STORE: state <= CONV_ADVANCE;
                CONV_ADVANCE: begin
                    if (index_hold == 1023) begin
                        working_visible <= 1;
                        index_hold <= 0;
                        state <= WORK_READ;
                    end else begin
                        index_hold <= index_hold + 1'b1;
                        state <= CONV_START;
                    end
                end
                WORK_READ: begin
                    if (!working_visible) begin
                        error_hold <= 7;
                        state <= PUBLISH;
                    end else
                        state <= WORK_CAPTURE;
                end
                WORK_CAPTURE: begin
                    work_hold <= work_q;
                    if (activation_phase)
                        state <= ACTIVATION_START;
                    else
                        state <= CLAMP_START;
                end
                CLAMP_START: if (clamp_ready)
                    state <= CLAMP_WAIT;
                CLAMP_WAIT: if (clamp_valid) begin
                    if (clamp_error != 0) begin
                        error_hold <= clamp_error;
                        state <= PUBLISH;
                    end else begin
                        work_hold <= clamp_data;
                        state <= WORK_STORE;
                    end
                end
                ACTIVATION_START: if (activation_ready)
                    state <= ACTIVATION_WAIT;
                ACTIVATION_WAIT: if (activation_valid) begin
                    if (activation_error != 0) begin
                        error_hold <= activation_error;
                        state <= PUBLISH;
                    end else begin
                        fp_value <= activation_data;
                        state <= ACTIVATION_NARROW;
                    end
                end
                ACTIVATION_NARROW: begin
                    fp_a <= fp_value;
                    fp_b <= 0;
                    fp_op <= 3;
                    fp_return <= WORK_STORE;
                    state <= FP_START;
                end
                WORK_STORE: state <= WORK_ADVANCE;
                WORK_ADVANCE: begin
                    if (index_hold == 1023) begin
                        index_hold <= 0;
                        if (activation_phase)
                            state <= PROJECTION_START;
                        else
                            state <= NORM_START;
                    end else begin
                        index_hold <= index_hold + 1'b1;
                        state <= WORK_READ;
                    end
                end
                NORM_START: if (norm_ready) begin
                    received <= 0;
                    receive_bad <= 0;
                    state <= NORM_WAIT;
                end
                NORM_WAIT: if (norm_valid && source_state == S_IDLE) begin
                    child_error_hold <= norm_error;
                    state <= NORM_CHECK;
                end
                NORM_CHECK: begin
                    if (child_error_hold != 0) begin
                        error_hold <= child_error_hold;
                        state <= PUBLISH;
                    end else if (receive_bad || received != 1024) begin
                        error_hold <= 7;
                        state <= PUBLISH;
                    end else begin
                        activation_phase <= 1;
                        index_hold <= 0;
                        state <= WORK_READ;
                    end
                end
                PROJECTION_START: if (projection_ready)
                    state <= PROJECTION_WAIT;
                PROJECTION_WAIT: if (projection_valid && source_state == S_IDLE) begin
                    projection_hold <= projection_data;
                    child_error_hold <= projection_error;
                    state <= PROJECTION_CHECK;
                end
                PROJECTION_CHECK: begin
                    if (child_error_hold != 0) begin
                        error_hold <= child_error_hold;
                        state <= PUBLISH;
                    end else if (RAW_SOURCE_CALLBACK)
                        state <= SOURCE_SEND;
                    else
                        state <= RESIDUAL_READ;
                end
                RESIDUAL_READ: begin
                    if (!raw_visible) begin
                        error_hold <= 7;
                        state <= PUBLISH;
                    end else
                        state <= RESIDUAL_CAPTURE;
                end
                RESIDUAL_CAPTURE: begin
                    fp_a <= {raw_q, 16'd0};
                    fp_b <= {projection_hold[15:0], 16'd0};
                    fp_op <= 0;
                    fp_return <= RESIDUAL_NARROW;
                    state <= FP_START;
                end
                RESIDUAL_NARROW: begin
                    fp_a <= fp_value;
                    fp_b <= 0;
                    fp_op <= 3;
                    fp_return <= OUTPUT_REGISTER;
                    state <= FP_START;
                end
                OUTPUT_REGISTER: begin
                    output_hold <= fp_value[15:0];
                    state <= EMIT;
                end
                EMIT: if (output_ready)
                    state <= OUTPUT_ADVANCE;
                OUTPUT_ADVANCE: begin
                    if (index_hold == 1023)
                        state <= PUBLISH;
                    else begin
                        index_hold <= index_hold + 1'b1;
                        state <= PROJECTION_START;
                    end
                end
                FP_START: if (fp_ready)
                    state <= FP_WAIT;
                FP_WAIT: if (fp_valid) begin
                    if (fp_error != 0) begin
                        error_hold <= fp_error;
                        state <= PUBLISH;
                    end else begin
                        fp_value <= fp_data;
                        if (fp_return == WORK_STORE)
                            work_hold <= fp_data[15:0];
                        state <= fp_return;
                    end
                end
                PUBLISH: state <= RESPONSE;
                RESPONSE: if (done_ready) begin
                    vector_allocated <= 0;
                    raw_visible <= 0;
                    working_visible <= 0;
                    state <= IDLE;
                end
                default: begin
                    output_hold <= 0;
                    error_hold <= 7;
                    state <= PUBLISH;
                end
            endcase
        end
    end
endmodule
