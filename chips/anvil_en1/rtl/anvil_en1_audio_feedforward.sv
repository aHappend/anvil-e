module anvil_en1_audio_feedforward #(
    parameter integer EXTERNAL_VECTOR_RAM = 0
) (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] model, precision, mode,
    input wire [7:0] layer,
    input wire [31:0] generation, token,
    input wire [63:0] audio_weights_base,
    output wire source_valid,
    input wire source_ready,
    output wire [1:0] source_model, source_mode,
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
    output wire intermediate_event,
    output wire [31:0] intermediate_bytes,
    output wire [63:0] vector_live_bytes, vector_physical_bytes,
    output wire [2:0] vector_ram_write, vector_ram_read,
    output wire [95:0] vector_ram_waddr, vector_ram_raddr,
    output wire [47:0] vector_ram_wdata,
    input wire [47:0] vector_ram_rdata,
    output wire [63:0] controller_bytes, norm_controller_bytes, clamp_controller_bytes,
    output wire [63:0] mlp_controller_bytes, down_controller_bytes,
    output wire [63:0] down_clamp_controller_bytes,
    output wire [63:0] inner_controller_bytes, inner_clamp_controller_bytes
);
    localparam [5:0] IDLE = 0, VALIDATE = 1, SOURCE_SEND = 2,
        SOURCE_WAIT = 3, SOURCE_REGISTER = 4, INPUT_STORE = 5, INPUT_ADVANCE = 6,
        CLIP_READ = 7, CLIP_CAPTURE = 8, CLIP_START = 9,
        CLIP_WAIT = 10, CLIP_STORE = 11, CLIP_ADVANCE = 12,
        NORM_START = 13, NORM_WAIT = 14, NORM_CHECK = 15,
        MLP_START = 16, MLP_WAIT = 17, MLP_REGISTER = 18, MLP_STORE = 19,
        MLP_ADVANCE = 20, FINAL_READ = 21, FINAL_CAPTURE = 22,
        HALF_NARROW = 23, HALF_WIDEN = 24, RESIDUAL_ADD = 25,
        FINAL_NARROW = 26, OUTPUT_REGISTER = 27, EMIT = 28,
        OUTPUT_ADVANCE = 29, FP_START = 30, FP_WAIT = 31,
        PUBLISH = 32, RESPONSE = 33;
    localparam [2:0] S_IDLE = 0, S_VALIDATE = 1, S_READ = 2,
        S_CAPTURE = 3, S_RESPONSE = 4;
    reg [5:0] state, fp_return;
    reg [2:0] source_state;
    reg [1:0] model_hold, precision_hold, mode_hold;
    reg [7:0] layer_hold;
    reg [31:0] generation_hold, token_hold, index_hold, received, bank_index;
    reg [63:0] weights_hold;
    reg post_phase, vector_allocated, raw_visible, working_visible, branch_visible;
    reg receive_bad, source_error_hold, bank_error, bank_branch_hold;
    reg [15:0] source_hold, clip_input_hold, clip_output_hold, mlp_hold;
    reg [15:0] bank_data, residual_hold, output_hold;
    wire [15:0] raw_q, working_q, branch_q;
    wire [15:0] callback_q = bank_branch_hold ? branch_q : working_q;
    reg [31:0] fp_a, fp_b, fp_value;
    reg [2:0] fp_op;
    reg [3:0] child_error_hold, error_hold;
    initial begin
        if (EXTERNAL_VECTOR_RAM != 0 && EXTERNAL_VECTOR_RAM != 1)
            $fatal(1, "PARAMETER ERROR: EXTERNAL_VECTOR_RAM must be 0 or 1");
    end

    wire norm_selected = rst_n && (state == NORM_START || state == NORM_WAIT);
    wire mlp_selected = rst_n && (state == MLP_START || state == MLP_WAIT);
    wire norm_ready, norm_valid, norm_source_valid, norm_source_rsp_ready;
    wire norm_output_valid, norm_output_last, norm_cmd_valid, norm_result_ready;
    wire [31:0] norm_source_index, norm_output_index;
    wire [15:0] norm_output_data;
    wire [63:0] norm_addr;
    wire [3:0] norm_error;
    wire [15:0] pre_kind = mode_hold == 1 ? 16'h2100 : 16'h2111;
    wire [15:0] post_kind = mode_hold == 1 ? 16'h2103 : 16'h2114;
    anvil_en1_native_norm norm (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == NORM_START), .start_ready(norm_ready),
        .model(model_hold), .precision(precision_hold), .image_class(2'd2),
        .tensor_kind(post_phase ? post_kind : pre_kind),
        .tensor_layer({8'd0, layer_hold}), .vector_length(32'd1024),
        .weights_base(weights_hold),
        .source_valid(norm_source_valid),
        .source_ready(rst_n && state == NORM_WAIT && source_state == S_IDLE),
        .source_index(norm_source_index),
        .source_rsp_valid(rst_n && state == NORM_WAIT && source_state == S_RESPONSE),
        .source_rsp_ready(norm_source_rsp_ready), .source_rsp_data(bank_data),
        .source_rsp_error(bank_error),
        .cmd_valid(norm_cmd_valid), .cmd_ready(norm_selected && cmd_ready),
        .cmd_write(), .cmd_addr(norm_addr), .cmd_wdata(),
        .result_valid(norm_selected && result_valid), .result_ready(norm_result_ready),
        .result_data(result_data), .result_error(result_error),
        .output_valid(norm_output_valid), .output_ready(rst_n && state == NORM_WAIT),
        .output_index(norm_output_index), .output_data(norm_output_data),
        .output_last(norm_output_last), .done_valid(norm_valid),
        .done_ready(rst_n && state == NORM_WAIT && source_state == S_IDLE),
        .done_error(norm_error), .controller_bytes(norm_controller_bytes)
    );
    wire mlp_ready, mlp_valid, mlp_source_valid, mlp_source_rsp_ready;
    wire mlp_cmd_valid, mlp_result_ready;
    wire [31:0] mlp_source_index, mlp_data, mlp_generation, mlp_token;
    wire [1:0] mlp_model, mlp_mode;
    wire [7:0] mlp_layer;
    wire [63:0] mlp_addr;
    wire [3:0] mlp_error;
    anvil_en1_native_mlp_row mlp (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == MLP_START), .start_ready(mlp_ready),
        .model(model_hold), .precision(precision_hold), .mode(mode_hold),
        .layer(layer_hold), .generation(generation_hold), .token(token_hold),
        .output_row(index_hold), .native_weights_base(weights_hold),
        .source_valid(mlp_source_valid),
        .source_ready(rst_n && state == MLP_WAIT && source_state == S_IDLE),
        .source_generation(mlp_generation), .source_token(mlp_token),
        .source_index(mlp_source_index), .source_model(mlp_model),
        .source_mode(mlp_mode), .source_layer(mlp_layer),
        .source_rsp_valid(rst_n && state == MLP_WAIT && source_state == S_RESPONSE),
        .source_rsp_ready(mlp_source_rsp_ready), .source_rsp_data(bank_data),
        .source_rsp_error(bank_error),
        .cmd_valid(mlp_cmd_valid), .cmd_ready(mlp_selected && cmd_ready),
        .cmd_write(), .cmd_addr(mlp_addr), .cmd_wdata(),
        .result_valid(mlp_selected && result_valid), .result_ready(mlp_result_ready),
        .result_data(result_data), .result_error(result_error),
        .done_valid(mlp_valid),
        .done_ready(rst_n && state == MLP_WAIT && source_state == S_IDLE),
        .done_data(mlp_data), .done_error(mlp_error),
        .intermediate_event(intermediate_event), .intermediate_bytes(intermediate_bytes),
        .controller_bytes(mlp_controller_bytes), .down_controller_bytes(down_controller_bytes),
        .down_clamp_controller_bytes(down_clamp_controller_bytes),
        .inner_controller_bytes(inner_controller_bytes),
        .inner_clamp_controller_bytes(inner_clamp_controller_bytes)
    );
    wire clamp_ready, clamp_valid;
    wire [15:0] clamp_data;
    wire [3:0] clamp_error;
    anvil_en1_bf16_clamp clamp (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == CLIP_START), .start_ready(clamp_ready),
        .value(clip_input_hold), .minimum(16'hd015), .maximum(16'h5015),
        .done_valid(clamp_valid), .done_ready(rst_n && state == CLIP_WAIT),
        .done_data(clamp_data), .done_error(clamp_error),
        .controller_bytes(clamp_controller_bytes)
    );
    wire fp_ready, fp_valid;
    wire [31:0] fp_data;
    wire [3:0] fp_error;
    wire [63:0] primitive_fp_bytes;
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
    wire callback_valid = state == NORM_WAIT ? norm_source_valid : mlp_source_valid;
    wire [31:0] callback_index = state == NORM_WAIT ? norm_source_index : mlp_source_index;
    wire callback_ready = state == NORM_WAIT ? norm_source_rsp_ready : mlp_source_rsp_ready;
    wire mlp_tag_good = mlp_generation == generation_hold && mlp_token == token_hold &&
        mlp_model == model_hold && mlp_mode == mode_hold && mlp_layer == layer_hold;
    wire branch_write = rst_n && ((state == CLIP_STORE && post_phase) ||
        (state == NORM_WAIT && norm_output_valid && norm_beat_good &&
            !receive_bad && post_phase) || state == MLP_STORE);
    wire branch_read = rst_n && ((state == CLIP_READ && post_phase) ||
        ((state == NORM_WAIT || state == MLP_WAIT) &&
            source_state == S_READ && bank_branch_hold) || state == FINAL_READ);
    wire [31:0] branch_waddr = state == NORM_WAIT ? norm_output_index : index_hold;
    wire [31:0] branch_raddr = (state == NORM_WAIT || state == MLP_WAIT) ?
        bank_index : index_hold;
    wire [15:0] branch_wdata = state == CLIP_STORE ? clip_output_hold :
        (state == MLP_STORE ? mlp_hold : norm_output_data);
    wire [2:0] bank_write = {branch_write, rst_n && !post_phase &&
        (state == CLIP_STORE || (state == NORM_WAIT && norm_output_valid &&
            norm_beat_good && !receive_bad)), rst_n && state == INPUT_STORE};
    wire [2:0] bank_read = {branch_read, rst_n &&
        (state == NORM_WAIT || state == MLP_WAIT) &&
            source_state == S_READ && !bank_branch_hold,
        rst_n && ((state == CLIP_READ && !post_phase) || state == FINAL_READ)};
    wire [95:0] bank_waddr = {branch_waddr,
        state == CLIP_STORE ? index_hold : norm_output_index, index_hold};
    wire [95:0] bank_raddr = {branch_raddr, bank_index, index_hold};
    wire [47:0] bank_wdata = {branch_wdata,
        state == CLIP_STORE ? clip_output_hold : norm_output_data, source_hold};
    assign vector_ram_write = EXTERNAL_VECTOR_RAM ? bank_write : 3'd0;
    assign vector_ram_read = EXTERNAL_VECTOR_RAM ? bank_read : 3'd0;
    assign vector_ram_waddr = rst_n && EXTERNAL_VECTOR_RAM ? bank_waddr : 96'd0;
    assign vector_ram_raddr = rst_n && EXTERNAL_VECTOR_RAM ? bank_raddr : 96'd0;
    assign vector_ram_wdata = rst_n && EXTERNAL_VECTOR_RAM ? bank_wdata : 48'd0;
    generate if (EXTERNAL_VECTOR_RAM == 1) begin : external_vectors
        assign raw_q = vector_ram_rdata[15:0];
        assign working_q = vector_ram_rdata[31:16];
        assign branch_q = vector_ram_rdata[47:32];
    end else begin : local_vectors
        (* ramstyle = "M20K", nomem2reg *) reg [15:0] residual [0:1023];
        (* ramstyle = "M20K", nomem2reg *) reg [15:0] working [0:1023];
        (* ramstyle = "M20K", nomem2reg *) reg [15:0] branch [0:1023];
        reg [15:0] residual_read_q, working_read_q, branch_read_q;
        assign raw_q = residual_read_q;
        assign working_q = working_read_q;
        assign branch_q = branch_read_q;
        always @(posedge clk) begin
            if (bank_write[0] && bank_waddr[31:0] < 1024)
                residual[bank_waddr[9:0]] <= bank_wdata[15:0];
            if (bank_write[1] && bank_waddr[63:32] < 1024)
                working[bank_waddr[41:32]] <= bank_wdata[31:16];
            if (bank_read[0] && bank_raddr[31:0] < 1024)
                residual_read_q <= residual[bank_raddr[9:0]];
            if (bank_read[1] && bank_raddr[63:32] < 1024)
                working_read_q <= working[bank_raddr[41:32]];
            if (bank_write[2] && branch_waddr < 1024)
                branch[branch_waddr[9:0]] <= branch_wdata;
            if (bank_read[2] && branch_raddr < 1024)
                branch_read_q <= branch[branch_raddr[9:0]];
        end
    end endgenerate
    assign start_ready = rst_n && state == IDLE;
    assign source_valid = rst_n && state == SOURCE_SEND;
    assign source_rsp_ready = rst_n && state == SOURCE_WAIT;
    assign source_model = rst_n ? model_hold : 2'd0;
    assign source_mode = rst_n ? mode_hold : 2'd0;
    assign source_layer = rst_n ? layer_hold : 8'd0;
    assign source_generation = rst_n ? generation_hold : 32'd0;
    assign source_token = rst_n ? token_hold : 32'd0;
    assign source_index = rst_n ? index_hold : 32'd0;
    assign cmd_valid = norm_selected ? norm_cmd_valid : (mlp_selected && mlp_cmd_valid);
    assign cmd_write = 0;
    assign cmd_addr = !rst_n ? 64'd0 :
        (norm_selected ? norm_addr : (mlp_selected ? mlp_addr : 64'd0));
    assign cmd_wdata = 0;
    assign result_ready = norm_selected ? norm_result_ready : (mlp_selected && mlp_result_ready);
    assign output_valid = rst_n && state == EMIT;
    assign output_index = rst_n ? index_hold : 32'd0;
    assign output_data = rst_n ? output_hold : 16'd0;
    assign output_last = rst_n && state == EMIT && index_hold == 1023;
    assign done_valid = rst_n && state == RESPONSE;
    assign done_error = rst_n ? error_hold : 4'd0;
    assign weight_read_event = cmd_valid && cmd_ready;
    assign weight_read_bytes = weight_read_event ? 32'd4 : 32'd0;
    assign vector_live_bytes = rst_n && vector_allocated ? 64'd6144 : 64'd0;
    assign vector_physical_bytes = rst_n ?
        (EXTERNAL_VECTOR_RAM ? 64'd0 : 64'd6144) : 64'd0;
    localparam integer CONTROLLER_BITS =
        $bits(state) + $bits(fp_return) + $bits(source_state) +
        $bits(model_hold) + $bits(precision_hold) + $bits(mode_hold) + $bits(layer_hold) +
        $bits(generation_hold) + $bits(token_hold) + $bits(index_hold) +
        $bits(received) + $bits(bank_index) + $bits(weights_hold) + $bits(post_phase) +
        $bits(vector_allocated) + $bits(raw_visible) + $bits(working_visible) +
        $bits(branch_visible) + $bits(receive_bad) + $bits(source_error_hold) +
        $bits(bank_error) + $bits(bank_branch_hold) + $bits(source_hold) +
        $bits(clip_input_hold) + $bits(clip_output_hold) + $bits(mlp_hold) +
        (EXTERNAL_VECTOR_RAM ? 0 : 48) +
        $bits(bank_data) + $bits(residual_hold) + $bits(output_hold) +
        $bits(fp_a) + $bits(fp_b) + $bits(fp_value) + $bits(fp_op) +
        $bits(child_error_hold) + $bits(error_hold);
    assign controller_bytes = !rst_n ? 64'd0 :
        64'((CONTROLLER_BITS + 7) >> 3) + primitive_fp_bytes;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            source_state <= S_IDLE;
            bank_index <= 0;
            bank_data <= 0;
            bank_error <= 0;
            bank_branch_hold <= 0;
        end else begin
            case (source_state)
                S_IDLE: if ((state == NORM_WAIT || state == MLP_WAIT) && callback_valid) begin
                    bank_index <= callback_index;
                    bank_branch_hold <= state == NORM_WAIT && post_phase;
                    bank_error <= state == MLP_WAIT && !mlp_tag_good;
                    bank_data <= 0;
                    source_state <= S_VALIDATE;
                end
                S_VALIDATE: begin
                    if (bank_error || bank_index >= 1024 ||
                        (bank_branch_hold ? !branch_visible : !working_visible)) begin
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
                S_RESPONSE: if ((state == NORM_WAIT || state == MLP_WAIT) && callback_ready)
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
            mode_hold <= 0;
            layer_hold <= 0;
            generation_hold <= 0;
            token_hold <= 0;
            index_hold <= 0;
            received <= 0;
            weights_hold <= 0;
            post_phase <= 0;
            vector_allocated <= 0;
            raw_visible <= 0;
            working_visible <= 0;
            branch_visible <= 0;
            receive_bad <= 0;
            source_error_hold <= 0;
            source_hold <= 0;
            clip_input_hold <= 0;
            clip_output_hold <= 0;
            mlp_hold <= 0;
            residual_hold <= 0;
            output_hold <= 0;
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
                    mode_hold <= mode;
                    layer_hold <= layer;
                    generation_hold <= generation;
                    token_hold <= token;
                    weights_hold <= audio_weights_base;
                    index_hold <= 0;
                    received <= 0;
                    post_phase <= 0;
                    vector_allocated <= 1;
                    raw_visible <= 0;
                    working_visible <= 0;
                    branch_visible <= 0;
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
                    end else if ((mode_hold != 1 && mode_hold != 2) ||
                        layer_hold >= 12 || generation_hold == 0 ||
                        token_hold > 131071 || weights_hold[1:0] != 0) begin
                        error_hold <= 5;
                        state <= PUBLISH;
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
                    end else
                        state <= INPUT_STORE;
                end
                INPUT_STORE: state <= INPUT_ADVANCE;
                INPUT_ADVANCE: begin
                    if (index_hold == 1023) begin
                        raw_visible <= 1;
                        index_hold <= 0;
                        state <= CLIP_READ;
                    end else begin
                        index_hold <= index_hold + 1'b1;
                        state <= SOURCE_SEND;
                    end
                end
                CLIP_READ: begin
                    if (post_phase ? !branch_visible : !raw_visible) begin
                        error_hold <= 7;
                        state <= PUBLISH;
                    end else
                        state <= CLIP_CAPTURE;
                end
                CLIP_CAPTURE: begin
                    clip_input_hold <= post_phase ? branch_q : raw_q;
                    state <= CLIP_START;
                end
                CLIP_START: if (clamp_ready)
                    state <= CLIP_WAIT;
                CLIP_WAIT: if (clamp_valid) begin
                    if (clamp_error != 0) begin
                        error_hold <= clamp_error;
                        state <= PUBLISH;
                    end else begin
                        clip_output_hold <= clamp_data;
                        state <= CLIP_STORE;
                    end
                end
                CLIP_STORE: state <= CLIP_ADVANCE;
                CLIP_ADVANCE: begin
                    if (index_hold == 1023) begin
                        if (!post_phase)
                            working_visible <= 1;
                        index_hold <= 0;
                        state <= NORM_START;
                    end else begin
                        index_hold <= index_hold + 1'b1;
                        state <= CLIP_READ;
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
                    end else if (post_phase) begin
                        index_hold <= 0;
                        state <= FINAL_READ;
                    end else begin
                        index_hold <= 0;
                        state <= MLP_START;
                    end
                end
                MLP_START: if (mlp_ready)
                    state <= MLP_WAIT;
                MLP_WAIT: if (mlp_valid && source_state == S_IDLE) begin
                    mlp_hold <= mlp_data[15:0];
                    child_error_hold <= mlp_error;
                    state <= MLP_REGISTER;
                end
                MLP_REGISTER: begin
                    if (child_error_hold != 0) begin
                        error_hold <= child_error_hold;
                        state <= PUBLISH;
                    end else
                        state <= MLP_STORE;
                end
                MLP_STORE: state <= MLP_ADVANCE;
                MLP_ADVANCE: begin
                    if (index_hold == 1023) begin
                        branch_visible <= 1;
                        post_phase <= 1;
                        index_hold <= 0;
                        state <= CLIP_READ;
                    end else begin
                        index_hold <= index_hold + 1'b1;
                        state <= MLP_START;
                    end
                end
                FINAL_READ: begin
                    if (!raw_visible || !branch_visible) begin
                        error_hold <= 7;
                        state <= PUBLISH;
                    end else
                        state <= FINAL_CAPTURE;
                end
                FINAL_CAPTURE: begin
                    residual_hold <= raw_q;
                    fp_a <= {branch_q, 16'd0};
                    fp_b <= 32'h3f000000;
                    fp_op <= 1;
                    fp_return <= HALF_NARROW;
                    state <= FP_START;
                end
                HALF_NARROW: begin
                    fp_a <= fp_value;
                    fp_b <= 0;
                    fp_op <= 3;
                    fp_return <= HALF_WIDEN;
                    state <= FP_START;
                end
                HALF_WIDEN: begin
                    fp_a <= {16'd0, fp_value[15:0]};
                    fp_b <= 0;
                    fp_op <= 2;
                    fp_return <= RESIDUAL_ADD;
                    state <= FP_START;
                end
                RESIDUAL_ADD: begin
                    fp_a <= {residual_hold, 16'd0};
                    fp_b <= fp_value;
                    fp_op <= 0;
                    fp_return <= FINAL_NARROW;
                    state <= FP_START;
                end
                FINAL_NARROW: begin
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
                        state <= FINAL_READ;
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
                        state <= fp_return;
                    end
                end
                PUBLISH: state <= RESPONSE;
                RESPONSE: if (done_ready) begin
                    vector_allocated <= 0;
                    raw_visible <= 0;
                    working_visible <= 0;
                    branch_visible <= 0;
                    state <= IDLE;
                end
                default: begin
                    error_hold <= 7;
                    state <= PUBLISH;
                end
            endcase
        end
    end
endmodule
