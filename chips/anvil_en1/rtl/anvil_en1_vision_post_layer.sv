module anvil_en1_vision_post_layer #(
    parameter integer EXTERNAL_BRANCH_RAM = 0
) (
    input wire image_immutable, image_invalidate,
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] model, precision,
    input wire [7:0] layer,
    input wire [31:0] generation, patch,
    input wire [63:0] vision_weights_base,
    output wire source_valid,
    input wire source_ready,
    output wire [1:0] source_model,
    output wire [7:0] source_layer,
    output wire [31:0] source_generation, source_patch, source_index,
    output wire source_is_branch,
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
    output wire intermediate_event,
    output wire [31:0] intermediate_bytes,
    output wire [63:0] vector_live_bytes, vector_physical_bytes,
    output wire branch_ram_write, branch_ram_read,
    output wire [31:0] branch_ram_waddr, branch_ram_raddr,
    output wire [15:0] branch_ram_wdata,
    input wire [15:0] branch_ram_rdata,
    output wire [63:0] controller_bytes, norm_controller_bytes, mlp_controller_bytes,
    output wire [63:0] down_controller_bytes, down_clamp_controller_bytes,
    output wire [63:0] inner_controller_bytes, inner_clamp_controller_bytes
);
    localparam [4:0] IDLE = 0, VALIDATE = 1, LOAD_SEND = 2,
        LOAD_WAIT = 3, LOAD_REGISTER = 4, LOAD_ADVANCE = 5,
        NORM_START = 6, NORM_WAIT = 7, NORM_FINISH = 8,
        RESIDUAL_READ = 9, RESIDUAL_CAPTURE = 10,
        ADD_START = 11, ADD_WAIT = 12, NARROW_START = 13,
        NARROW_WAIT = 14, RESIDUAL_STORE = 15, RESIDUAL_ADVANCE = 16,
        MLP_START = 17, MLP_WAIT = 18, MLP_STORE = 19, MLP_ADVANCE = 20,
        OUTPUT_WAIT = 21, PUBLISH = 22, RESPONSE = 23;
    localparam [2:0] SRC_IDLE = 0, SRC_VALIDATE = 1, SRC_READ = 2,
        SRC_CAPTURE = 3, SRC_REGISTER = 4, SRC_RESPONSE = 5;
    reg [4:0] state;
    reg [2:0] src_state;
    reg [1:0] model_hold, precision_hold, phase, src_bank;
    reg [7:0] layer_hold;
    reg [31:0] generation_hold, patch_hold, index, norm_count, src_index_hold;
    reg [63:0] weights_hold;
    reg loading_branch, raw_allocated, branch_allocated, mlp_allocated;
    reg raw_committed, branch_committed, mlp_committed, norm_bad, norm_complete;
    reg src_mlp, src_error_hold, load_error_hold;
    reg [15:0] load_hold, src_hold, raw_q, mlp_q, residual_raw;
    wire [15:0] branch_q;
    reg [15:0] residual_branch, residual_hold;
    reg [31:0] sum_hold;
    reg [3:0] error_hold;
    (* ramstyle = "M20K", nomem2reg *)
    reg [15:0] raw_payload [0:767];
    (* ramstyle = "M20K", nomem2reg *)
    reg [15:0] mlp_payload [0:767];
    initial begin
        if (EXTERNAL_BRANCH_RAM != 0 && EXTERNAL_BRANCH_RAM != 1)
            $fatal(1, "PARAMETER ERROR: EXTERNAL_BRANCH_RAM must be 0 or 1");
    end
    wire norm_selected = rst_n && (state == NORM_START || state == NORM_WAIT);
    wire mlp_selected = rst_n && (state == MLP_START || state == MLP_WAIT);
    wire fp_ready, fp_valid;
    wire [31:0] fp_data;
    wire [3:0] fp_error;
    wire [1:0] child_arithmetic_valid, child_arithmetic_result_ready;
    wire [5:0] child_arithmetic_operation;
    wire [63:0] child_arithmetic_a, child_arithmetic_b;
    wire [15:0] norm_kind = phase == 0 ? 16'h1107 :
        (phase == 1 ? 16'h1108 : 16'h110c);
    wire norm_ready, norm_valid, norm_source_valid, norm_source_rsp_ready;
    wire norm_output_valid, norm_output_last, norm_cmd_valid, norm_result_ready;
    wire [31:0] norm_source_index, norm_output_index;
    wire [15:0] norm_output_data;
    wire [63:0] norm_addr;
    wire [3:0] norm_error;
    anvil_en1_native_norm #(.EXTERNAL_FP(1)) normalization (
        .image_immutable(image_immutable === 1'b1),
        .image_invalidate((image_invalidate === 1'b1)),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == NORM_START), .start_ready(norm_ready),
        .model(model_hold), .precision(precision_hold), .image_class(2'd1),
        .tensor_kind(norm_kind), .tensor_layer({8'd0, layer_hold}),
        .vector_length(32'd768), .weights_base(weights_hold),
        .source_valid(norm_source_valid),
        .source_ready(rst_n && state == NORM_WAIT && src_state == SRC_IDLE),
        .source_index(norm_source_index),
        .source_rsp_valid(rst_n && src_state == SRC_RESPONSE && !src_mlp),
        .source_rsp_ready(norm_source_rsp_ready), .source_rsp_data(src_hold),
        .source_rsp_error(src_error_hold),
        .cmd_valid(norm_cmd_valid), .cmd_ready(norm_selected && cmd_ready),
        .cmd_write(), .cmd_addr(norm_addr), .cmd_wdata(),
        .result_valid(norm_selected && result_valid), .result_ready(norm_result_ready),
        .result_data(result_data), .result_error(result_error),
        .output_valid(norm_output_valid), .output_ready(rst_n && state == NORM_WAIT),
        .output_index(norm_output_index), .output_data(norm_output_data),
        .output_last(norm_output_last), .done_valid(norm_valid),
        .done_ready(rst_n && state == NORM_WAIT && src_state == SRC_IDLE),
        .done_error(norm_error), .controller_bytes(norm_controller_bytes),
        .arithmetic_valid(child_arithmetic_valid[0]),
        .arithmetic_ready(norm_selected && fp_ready),
        .arithmetic_operation(child_arithmetic_operation[0+:3]),
        .arithmetic_a(child_arithmetic_a[0+:32]),
        .arithmetic_b(child_arithmetic_b[0+:32]),
        .arithmetic_result_valid(norm_selected && fp_valid),
        .arithmetic_result_ready(child_arithmetic_result_ready[0]),
        .arithmetic_result_data(fp_data), .arithmetic_result_error(fp_error)
    );
    wire mlp_ready, mlp_valid, mlp_source_valid, mlp_source_rsp_ready;
    wire mlp_cmd_valid, mlp_result_ready;
    wire [31:0] mlp_source_index, mlp_data;
    wire [63:0] mlp_addr;
    wire [3:0] mlp_error;
    anvil_en1_native_mlp_row #(.EXTERNAL_FP(1), .IMAGE_CLASS(1)) mlp (
        .image_immutable(image_immutable === 1'b1),
        .image_invalidate((image_invalidate === 1'b1)),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == MLP_START), .start_ready(mlp_ready),
        .model(model_hold), .precision(precision_hold), .mode(2'd0),
        .layer(layer_hold), .generation(generation_hold), .token(patch_hold),
        .output_row(index), .native_weights_base(weights_hold),
        .source_valid(mlp_source_valid),
        .source_ready(rst_n && state == MLP_WAIT && src_state == SRC_IDLE),
        .source_generation(), .source_token(), .source_index(mlp_source_index),
        .source_model(), .source_mode(), .source_layer(),
        .source_rsp_valid(rst_n && src_state == SRC_RESPONSE && src_mlp),
        .source_rsp_ready(mlp_source_rsp_ready), .source_rsp_data(src_hold),
        .source_rsp_error(src_error_hold),
        .cmd_valid(mlp_cmd_valid), .cmd_ready(mlp_selected && cmd_ready),
        .cmd_write(), .cmd_addr(mlp_addr), .cmd_wdata(),
        .result_valid(mlp_selected && result_valid), .result_ready(mlp_result_ready),
        .result_data(result_data), .result_error(result_error),
        .done_valid(mlp_valid),
        .done_ready(rst_n && state == MLP_WAIT && src_state == SRC_IDLE),
        .done_data(mlp_data), .done_error(mlp_error),
        .intermediate_event(intermediate_event), .intermediate_bytes(intermediate_bytes),
        .controller_bytes(mlp_controller_bytes),
        .down_controller_bytes(down_controller_bytes),
        .down_clamp_controller_bytes(down_clamp_controller_bytes),
        .inner_controller_bytes(inner_controller_bytes),
        .inner_clamp_controller_bytes(inner_clamp_controller_bytes),
        .arithmetic_valid(child_arithmetic_valid[1]),
        .arithmetic_ready(mlp_selected && fp_ready),
        .arithmetic_operation(child_arithmetic_operation[3+:3]),
        .arithmetic_a(child_arithmetic_a[32+:32]),
        .arithmetic_b(child_arithmetic_b[32+:32]),
        .arithmetic_result_valid(mlp_selected && fp_valid),
        .arithmetic_result_ready(child_arithmetic_result_ready[1]),
        .arithmetic_result_data(fp_data), .arithmetic_result_error(fp_error)
    );
    wire narrowing = state == NARROW_START || state == NARROW_WAIT;
    wire [63:0] primitive_fp_bytes;
    anvil_en1_fp32 residual (
        .controller_bytes(primitive_fp_bytes),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && (norm_selected ? child_arithmetic_valid[0] :
            (mlp_selected ? child_arithmetic_valid[1] :
            (state == ADD_START || state == NARROW_START)))),
        .start_ready(fp_ready),
        .operation(norm_selected ? child_arithmetic_operation[0+:3] :
            (mlp_selected ? child_arithmetic_operation[3+:3] :
            (narrowing ? 3'd3 : 3'd0))),
        .operand_a(norm_selected ? child_arithmetic_a[0+:32] :
            (mlp_selected ? child_arithmetic_a[32+:32] :
            (narrowing ? sum_hold : {residual_raw, 16'd0}))),
        .operand_b(norm_selected ? child_arithmetic_b[0+:32] :
            (mlp_selected ? child_arithmetic_b[32+:32] :
            (narrowing ? 32'd0 : {residual_branch, 16'd0}))),
        .done_valid(fp_valid),
        .done_ready(rst_n && (norm_selected ? child_arithmetic_result_ready[0] :
            (mlp_selected ? child_arithmetic_result_ready[1] :
            (state == ADD_WAIT || state == NARROW_WAIT)))),
        .done_data(fp_data), .done_error(fp_error)
    );
    wire norm_accept = rst_n && state == NORM_WAIT && norm_output_valid;
    wire norm_well_formed = !norm_bad && !norm_complete &&
        norm_output_index == norm_count && norm_output_index < 768 &&
        norm_output_last == (norm_output_index == 767);
    wire load_store = rst_n && state == LOAD_REGISTER && !load_error_hold;
    assign start_ready = rst_n && state == IDLE;
    assign source_valid = rst_n && state == LOAD_SEND;
    assign source_model = rst_n ? model_hold : 2'd0;
    assign source_layer = rst_n ? layer_hold : 8'd0;
    assign source_generation = rst_n ? generation_hold : 32'd0;
    assign source_patch = rst_n ? patch_hold : 32'd0;
    assign source_index = rst_n ? index : 32'd0;
    assign source_is_branch = rst_n && loading_branch;
    assign source_rsp_ready = rst_n && state == LOAD_WAIT;
    assign cmd_valid = norm_selected ? norm_cmd_valid : (mlp_selected && mlp_cmd_valid);
    assign cmd_write = 0;
    assign cmd_addr = !rst_n ? 64'd0 : (norm_selected ? norm_addr :
        (mlp_selected ? mlp_addr : 64'd0));
    assign cmd_wdata = 0;
    assign result_ready = norm_selected ? norm_result_ready :
        (mlp_selected && mlp_result_ready);
    assign output_valid = rst_n && state == OUTPUT_WAIT;
    assign output_index = rst_n ? index : 32'd0;
    assign output_data = rst_n ? residual_hold : 16'd0;
    assign output_last = rst_n && state == OUTPUT_WAIT && index == 767;
    assign done_valid = rst_n && state == RESPONSE;
    assign done_error = rst_n ? error_hold : 4'd0;
    assign vector_live_bytes = rst_n ?
        (raw_allocated ? 64'd1536 : 64'd0) +
        (branch_allocated ? 64'd1536 : 64'd0) +
        (mlp_allocated ? 64'd1536 : 64'd0) : 64'd0;
    assign vector_physical_bytes = rst_n ?
        (EXTERNAL_BRANCH_RAM ? 64'd3072 : 64'd4608) : 64'd0;
    wire [31:0] CONTROLLER_BITS =
        $bits(state) + $bits(src_state) + $bits(model_hold) + $bits(precision_hold) +
        $bits(phase) + $bits(src_bank) + $bits(layer_hold) + $bits(generation_hold) +
        $bits(patch_hold) + $bits(index) + $bits(norm_count) + $bits(src_index_hold) +
        $bits(weights_hold) + $bits(loading_branch) + $bits(raw_allocated) +
        $bits(branch_allocated) + $bits(mlp_allocated) + $bits(raw_committed) +
        $bits(branch_committed) + $bits(mlp_committed) + $bits(norm_bad) +
        $bits(norm_complete) + $bits(src_mlp) + $bits(src_error_hold) +
        $bits(load_error_hold) + $bits(load_hold) + $bits(src_hold) + $bits(raw_q) +
        (EXTERNAL_BRANCH_RAM ? 0 : 16) + $bits(mlp_q) + $bits(residual_raw) +
        $bits(residual_branch) + $bits(residual_hold) + $bits(sum_hold) + $bits(error_hold);
    assign controller_bytes = !rst_n ? 64'd0 :
        64'((CONTROLLER_BITS + 7) >> 3) + primitive_fp_bytes;

    wire branch_write = (load_store && loading_branch) ||
        (norm_accept && norm_well_formed && phase != 2);
    wire branch_read = rst_n &&
        ((state == RESIDUAL_READ && phase == 0) ||
         (src_state == SRC_READ && state != RESIDUAL_READ && src_bank == 1));
    wire [31:0] branch_waddr = load_store && loading_branch ?
        index : norm_output_index;
    wire [31:0] branch_raddr = state == RESIDUAL_READ ? index : src_index_hold;
    wire [15:0] branch_wdata = load_store && loading_branch ?
        load_hold : norm_output_data;
    assign branch_ram_write = rst_n && EXTERNAL_BRANCH_RAM && branch_write;
    assign branch_ram_read = rst_n && EXTERNAL_BRANCH_RAM && branch_read;
    assign branch_ram_waddr = rst_n && EXTERNAL_BRANCH_RAM ? branch_waddr : 32'd0;
    assign branch_ram_raddr = rst_n && EXTERNAL_BRANCH_RAM ? branch_raddr : 32'd0;
    assign branch_ram_wdata = rst_n && EXTERNAL_BRANCH_RAM ? branch_wdata : 16'd0;
    generate if (EXTERNAL_BRANCH_RAM == 1) begin : external_branch
        assign branch_q = branch_ram_rdata;
    end else begin : local_branch
        (* ramstyle = "M20K", nomem2reg *)
        reg [15:0] payload [0:767];
        reg [15:0] read_q;
        assign branch_q = read_q;
        always @(posedge clk) begin
            if (rst_n) begin
                if (branch_write && branch_waddr < 768)
                    payload[branch_waddr[9:0]] <= branch_wdata;
                if (branch_read && branch_raddr < 768)
                    read_q <= payload[branch_raddr[9:0]];
            end
        end
    end endgenerate
    always @(posedge clk) begin
        if (load_store && !loading_branch)
            raw_payload[index[9:0]] <= load_hold;
        else if (rst_n && state == RESIDUAL_STORE)
            raw_payload[index[9:0]] <= residual_hold;
        if (rst_n && state == MLP_STORE)
            mlp_payload[index[9:0]] <= residual_hold;
        else if (norm_accept && norm_well_formed && phase == 2)
            mlp_payload[norm_output_index[9:0]] <= norm_output_data;
        if (rst_n && state == RESIDUAL_READ) begin
            raw_q <= raw_payload[index[9:0]];
            if (phase != 0)
                mlp_q <= mlp_payload[index[9:0]];
        end else if (rst_n && src_state == SRC_READ) begin
            if (src_bank == 0)
                raw_q <= raw_payload[src_index_hold[9:0]];
            else if (src_bank != 1)
                mlp_q <= mlp_payload[src_index_hold[9:0]];
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            src_state <= SRC_IDLE;
            src_bank <= 0;
            src_index_hold <= 0;
            src_mlp <= 0;
            src_error_hold <= 0;
            src_hold <= 0;
        end else begin
            case (src_state)
                SRC_IDLE: begin
                    if (state == NORM_WAIT && norm_source_valid) begin
                        src_index_hold <= norm_source_index;
                        src_bank <= phase == 0 ? 2'd1 : (phase == 1 ? 2'd0 : 2'd2);
                        src_mlp <= 0;
                        src_error_hold <= 0;
                        src_hold <= 0;
                        src_state <= SRC_VALIDATE;
                    end else if (state == MLP_WAIT && mlp_source_valid) begin
                        src_index_hold <= mlp_source_index;
                        src_bank <= 1;
                        src_mlp <= 1;
                        src_error_hold <= 0;
                        src_hold <= 0;
                        src_state <= SRC_VALIDATE;
                    end
                end
                SRC_VALIDATE: begin
                    if (src_index_hold >= 768 ||
                        (src_bank == 0 && !raw_committed) ||
                        (src_bank == 1 && !branch_committed) ||
                        (src_bank == 2 && !mlp_committed)) begin
                        src_error_hold <= 1;
                        src_state <= SRC_REGISTER;
                    end else
                        src_state <= SRC_READ;
                end
                SRC_READ: src_state <= SRC_CAPTURE;
                SRC_CAPTURE: begin
                    if (src_bank == 0)
                        src_hold <= raw_q;
                    else if (src_bank == 1)
                        src_hold <= branch_q;
                    else
                        src_hold <= mlp_q;
                    src_state <= SRC_REGISTER;
                end
                SRC_REGISTER: src_state <= SRC_RESPONSE;
                SRC_RESPONSE: if (src_mlp ? mlp_source_rsp_ready : norm_source_rsp_ready)
                    src_state <= SRC_IDLE;
                default: begin
                    src_error_hold <= 1;
                    src_hold <= 0;
                    src_state <= SRC_REGISTER;
                end
            endcase
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            model_hold <= 0;
            precision_hold <= 0;
            layer_hold <= 0;
            generation_hold <= 0;
            patch_hold <= 0;
            weights_hold <= 0;
            index <= 0;
            phase <= 0;
            norm_count <= 0;
            loading_branch <= 0;
            raw_allocated <= 0;
            branch_allocated <= 0;
            mlp_allocated <= 0;
            raw_committed <= 0;
            branch_committed <= 0;
            mlp_committed <= 0;
            norm_bad <= 0;
            norm_complete <= 0;
            load_hold <= 0;
            load_error_hold <= 0;
            residual_raw <= 0;
            residual_branch <= 0;
            residual_hold <= 0;
            sum_hold <= 0;
            error_hold <= 0;
        end else begin
            case (state)
                IDLE: if (start_valid && start_ready) begin
                    model_hold <= model;
                    precision_hold <= precision;
                    layer_hold <= layer;
                    generation_hold <= generation;
                    patch_hold <= patch;
                    weights_hold <= vision_weights_base;
                    index <= 0;
                    phase <= 0;
                    loading_branch <= 0;
                    raw_committed <= 0;
                    branch_committed <= 0;
                    mlp_committed <= 0;
                    norm_bad <= 0;
                    norm_complete <= 0;
                    norm_count <= 0;
                    error_hold <= 0;
                    state <= VALIDATE;
                end
                VALIDATE: begin
                    if ((model_hold != 1 && model_hold != 2) || precision_hold > 1) begin
                        error_hold <= 6;
                        state <= PUBLISH;
                    end else if (layer_hold >= 16 || patch_hold > 131071 ||
                        weights_hold[1:0] != 0) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else begin
                        raw_allocated <= 1;
                        state <= LOAD_SEND;
                    end
                end
                LOAD_SEND: if (source_ready)
                    state <= LOAD_WAIT;
                LOAD_WAIT: if (source_rsp_valid && source_rsp_ready) begin
                    load_hold <= source_rsp_data;
                    load_error_hold <= source_rsp_error;
                    state <= LOAD_REGISTER;
                end
                LOAD_REGISTER: begin
                    if (load_error_hold) begin
                        error_hold <= 7;
                        state <= PUBLISH;
                    end else
                        state <= LOAD_ADVANCE;
                end
                LOAD_ADVANCE: begin
                    if (index == 767) begin
                        index <= 0;
                        if (!loading_branch) begin
                            raw_committed <= 1;
                            loading_branch <= 1;
                            branch_allocated <= 1;
                            state <= LOAD_SEND;
                        end else begin
                            branch_committed <= 1;
                            norm_count <= 0;
                            norm_bad <= 0;
                            norm_complete <= 0;
                            state <= NORM_START;
                        end
                    end else begin
                        index <= index + 1'b1;
                        state <= LOAD_SEND;
                    end
                end
                NORM_START: if (norm_ready)
                    state <= NORM_WAIT;
                NORM_WAIT: begin
                    if (norm_accept) begin
                        if (!norm_well_formed)
                            norm_bad <= 1;
                        else begin
                            norm_count <= norm_count + 1'b1;
                            if (norm_output_last)
                                norm_complete <= 1;
                        end
                    end
                    if (norm_valid && src_state == SRC_IDLE) begin
                        if (norm_error != 0) begin
                            error_hold <= norm_error;
                            state <= PUBLISH;
                        end else
                            state <= NORM_FINISH;
                    end
                end
                NORM_FINISH: begin
                    if (norm_bad || !norm_complete || norm_count != 768) begin
                        error_hold <= 7;
                        state <= PUBLISH;
                    end else begin
                        index <= 0;
                        if (phase == 1) begin
                            branch_committed <= 1;
                            mlp_allocated <= 1;
                            state <= MLP_START;
                        end else
                            state <= RESIDUAL_READ;
                    end
                end
                RESIDUAL_READ: state <= RESIDUAL_CAPTURE;
                RESIDUAL_CAPTURE: begin
                    residual_raw <= raw_q;
                    residual_branch <= phase == 0 ? branch_q : mlp_q;
                    state <= ADD_START;
                end
                ADD_START: if (fp_ready)
                    state <= ADD_WAIT;
                ADD_WAIT: if (fp_valid) begin
                    if (fp_error != 0) begin
                        error_hold <= fp_error;
                        state <= PUBLISH;
                    end else begin
                        sum_hold <= fp_data;
                        state <= NARROW_START;
                    end
                end
                NARROW_START: if (fp_ready)
                    state <= NARROW_WAIT;
                NARROW_WAIT: if (fp_valid) begin
                    if (fp_error != 0) begin
                        error_hold <= fp_error;
                        state <= PUBLISH;
                    end else begin
                        residual_hold <= fp_data[15:0];
                        if (phase == 0)
                            state <= RESIDUAL_STORE;
                        else
                            state <= OUTPUT_WAIT;
                    end
                end
                RESIDUAL_STORE: state <= RESIDUAL_ADVANCE;
                RESIDUAL_ADVANCE: begin
                    if (index == 767) begin
                        phase <= 1;
                        norm_count <= 0;
                        norm_bad <= 0;
                        norm_complete <= 0;
                        state <= NORM_START;
                    end else begin
                        index <= index + 1'b1;
                        state <= RESIDUAL_READ;
                    end
                end
                MLP_START: if (mlp_ready)
                    state <= MLP_WAIT;
                MLP_WAIT: if (mlp_valid && src_state == SRC_IDLE) begin
                    if (mlp_error != 0) begin
                        error_hold <= mlp_error;
                        state <= PUBLISH;
                    end else begin
                        residual_hold <= mlp_data[15:0];
                        state <= MLP_STORE;
                    end
                end
                MLP_STORE: state <= MLP_ADVANCE;
                MLP_ADVANCE: begin
                    if (index == 767) begin
                        mlp_committed <= 1;
                        phase <= 2;
                        norm_count <= 0;
                        norm_bad <= 0;
                        norm_complete <= 0;
                        state <= NORM_START;
                    end else begin
                        index <= index + 1'b1;
                        state <= MLP_START;
                    end
                end
                OUTPUT_WAIT: if (output_valid && output_ready) begin
                    if (index == 767)
                        state <= PUBLISH;
                    else begin
                        index <= index + 1'b1;
                        state <= RESIDUAL_READ;
                    end
                end
                PUBLISH: state <= RESPONSE;
                RESPONSE: if (done_ready) begin
                    raw_allocated <= 0;
                    branch_allocated <= 0;
                    mlp_allocated <= 0;
                    raw_committed <= 0;
                    branch_committed <= 0;
                    mlp_committed <= 0;
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
