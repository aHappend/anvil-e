module anvil_en1_native_mlp_row #(
    parameter integer EXTERNAL_FP = 0
) (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] model, precision, mode,
    input wire [7:0] layer,
    input wire [31:0] generation, token, output_row,
    input wire [63:0] native_weights_base,
    output wire source_valid,
    input wire source_ready,
    output wire [31:0] source_generation, source_token, source_index,
    output wire [1:0] source_model, source_mode,
    output wire [7:0] source_layer,
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
    output wire done_valid,
    input wire done_ready,
    output wire [31:0] done_data,
    output wire [3:0] done_error,
    output wire intermediate_event,
    output wire [31:0] intermediate_bytes,
    output wire [63:0] controller_bytes,
    output wire [63:0] down_controller_bytes, down_clamp_controller_bytes,
    output wire [63:0] inner_controller_bytes, inner_clamp_controller_bytes,
    output wire arithmetic_valid,
    input wire arithmetic_ready,
    output wire [2:0] arithmetic_operation,
    output wire [31:0] arithmetic_a, arithmetic_b,
    input wire arithmetic_result_valid,
    output wire arithmetic_result_ready,
    input wire [31:0] arithmetic_result_data,
    input wire [3:0] arithmetic_result_error
);
    localparam [2:0] IDLE = 0, VALIDATE = 1, DOWN_START = 2,
        DOWN_WAIT = 3, REGISTER = 4, PUBLISH = 5, RESPONSE = 6;
    localparam [3:0] S_IDLE = 0, S_VALIDATE = 1, S_GATE_START = 2,
        S_GATE_WAIT = 3, S_UP_START = 4, S_UP_WAIT = 5,
        S_GEGLU_START = 6, S_GEGLU_WAIT = 7,
        S_ACTIVATION_START = 8, S_ACTIVATION_WAIT = 9,
        S_NARROW_START = 10, S_NARROW_WAIT = 11,
        S_REGISTER = 12, S_RESPONSE = 13;
    reg [2:0] state;
    reg [3:0] source_state;
    reg [1:0] model_hold, precision_hold, mode_hold;
    reg [7:0] layer_hold;
    reg [31:0] generation_hold, token_hold, row_hold, intermediate_index;
    reg [63:0] weights_hold;
    reg [15:0] gate_hold, up_hold, intermediate_hold;
    reg [31:0] activation_hold, output_hold;
    reg [3:0] intermediate_error, first_error, error_hold;
    localparam [2:0] FP_DOWN = 0, FP_INNER = 1, FP_GEGLU = 2,
        FP_ACTIVATION = 3, FP_LOCAL = 4;
    wire [3:0] child_arithmetic_valid, child_arithmetic_result_ready;
    wire [11:0] child_arithmetic_operation;
    wire [127:0] child_arithmetic_a, child_arithmetic_b;
    wire fp_ready, fp_valid;
    wire [31:0] fp_data;
    wire [3:0] fp_error;
    initial begin
        if (EXTERNAL_FP != 0 && EXTERNAL_FP != 1)
            $fatal(1, "PARAMETER ERROR: EXTERNAL_FP must be 0 or 1");
    end

    wire [1:0] image_class = mode_hold == 0 ? 2'd1 : 2'd2;
    wire [15:0] gate_kind = mode_hold == 0 ? 16'h1109 :
        (mode_hold == 1 ? 16'h2101 : 16'h2112);
    wire [15:0] down_kind = mode_hold == 0 ? 16'h110b :
        (mode_hold == 1 ? 16'h2102 : 16'h2113);
    wire inner_up = source_state == S_UP_START || source_state == S_UP_WAIT;
    wire [15:0] inner_kind = inner_up ? 16'h110a : gate_kind;
    wire [31:0] hidden_length = mode_hold == 0 ? 32'd768 : 32'd1024;
    wire [31:0] intermediate_length = mode_hold == 0 ? 32'd3072 : 32'd4096;

    wire down_ready, down_valid, down_cmd_valid, down_result_ready;
    wire down_source_valid, down_source_rsp_ready;
    wire [31:0] down_data, down_source_index;
    wire [63:0] down_cmd_addr;
    wire [3:0] down_error;
    wire inner_selected = rst_n && state == DOWN_WAIT &&
        (source_state == S_GATE_START || source_state == S_GATE_WAIT ||
            source_state == S_UP_START || source_state == S_UP_WAIT);
    wire down_selected = rst_n &&
        (state == DOWN_START || state == DOWN_WAIT) && !inner_selected;
    wire [2:0] fp_owner = inner_selected ? FP_INNER :
        (source_state == S_GEGLU_START || source_state == S_GEGLU_WAIT ? FP_GEGLU :
        (source_state == S_ACTIVATION_START || source_state == S_ACTIVATION_WAIT ?
            FP_ACTIVATION :
        (source_state == S_NARROW_START || source_state == S_NARROW_WAIT ?
            FP_LOCAL : FP_DOWN)));
    anvil_en1_clipped_projection #(.EXTERNAL_FP(1)) down (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == DOWN_START), .start_ready(down_ready),
        .model(model_hold), .precision(precision_hold), .image_class(image_class),
        .image_base(weights_hold), .tensor_kind(down_kind),
        .tensor_layer({8'd0, layer_hold}), .row_index(row_hold),
        .source_valid(down_source_valid),
        .source_ready(rst_n && state == DOWN_WAIT && source_state == S_IDLE),
        .source_index(down_source_index),
        .source_rsp_valid(rst_n && state == DOWN_WAIT && source_state == S_RESPONSE),
        .source_rsp_ready(down_source_rsp_ready),
        .source_rsp_data(intermediate_hold), .source_rsp_error(intermediate_error != 0),
        .cmd_valid(down_cmd_valid), .cmd_ready(down_selected && cmd_ready),
        .cmd_write(), .cmd_addr(down_cmd_addr), .cmd_wdata(),
        .result_valid(down_selected && result_valid), .result_ready(down_result_ready),
        .result_data(result_data), .result_error(result_error),
        .done_valid(down_valid),
        .done_ready(rst_n && state == DOWN_WAIT && source_state == S_IDLE),
        .done_data(down_data), .done_error(down_error),
        .controller_bytes(down_controller_bytes),
        .clamp_controller_bytes(down_clamp_controller_bytes),
        .arithmetic_valid(child_arithmetic_valid[FP_DOWN]),
        .arithmetic_ready(fp_owner == FP_DOWN && fp_ready),
        .arithmetic_operation(child_arithmetic_operation[3*FP_DOWN+:3]),
        .arithmetic_a(child_arithmetic_a[32*FP_DOWN+:32]),
        .arithmetic_b(child_arithmetic_b[32*FP_DOWN+:32]),
        .arithmetic_result_valid(fp_owner == FP_DOWN && fp_valid),
        .arithmetic_result_ready(child_arithmetic_result_ready[FP_DOWN]),
        .arithmetic_result_data(fp_data), .arithmetic_result_error(fp_error)
    );

    wire inner_ready, inner_valid, inner_cmd_valid, inner_result_ready;
    wire [31:0] inner_data;
    wire [63:0] inner_cmd_addr;
    wire [3:0] inner_error;
    anvil_en1_clipped_projection #(.EXTERNAL_FP(1)) inner (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == DOWN_WAIT &&
            (source_state == S_GATE_START || source_state == S_UP_START)),
        .start_ready(inner_ready),
        .model(model_hold), .precision(precision_hold), .image_class(image_class),
        .image_base(weights_hold), .tensor_kind(inner_kind),
        .tensor_layer({8'd0, layer_hold}), .row_index(intermediate_index),
        .source_valid(source_valid), .source_ready(inner_selected && source_ready),
        .source_index(source_index),
        .source_rsp_valid(inner_selected && source_rsp_valid),
        .source_rsp_ready(source_rsp_ready),
        .source_rsp_data(source_rsp_data), .source_rsp_error(source_rsp_error),
        .cmd_valid(inner_cmd_valid), .cmd_ready(inner_selected && cmd_ready),
        .cmd_write(), .cmd_addr(inner_cmd_addr), .cmd_wdata(),
        .result_valid(inner_selected && result_valid), .result_ready(inner_result_ready),
        .result_data(result_data), .result_error(result_error),
        .done_valid(inner_valid),
        .done_ready(rst_n && state == DOWN_WAIT &&
            (source_state == S_GATE_WAIT || source_state == S_UP_WAIT)),
        .done_data(inner_data), .done_error(inner_error),
        .controller_bytes(inner_controller_bytes),
        .clamp_controller_bytes(inner_clamp_controller_bytes),
        .arithmetic_valid(child_arithmetic_valid[FP_INNER]),
        .arithmetic_ready(fp_owner == FP_INNER && fp_ready),
        .arithmetic_operation(child_arithmetic_operation[3*FP_INNER+:3]),
        .arithmetic_a(child_arithmetic_a[32*FP_INNER+:32]),
        .arithmetic_b(child_arithmetic_b[32*FP_INNER+:32]),
        .arithmetic_result_valid(fp_owner == FP_INNER && fp_valid),
        .arithmetic_result_ready(child_arithmetic_result_ready[FP_INNER]),
        .arithmetic_result_data(fp_data), .arithmetic_result_error(fp_error)
    );

    wire geglu_ready, geglu_valid, activation_ready, activation_valid;
    wire [31:0] geglu_data, activation_data;
    wire [3:0] geglu_error, activation_error;
    wire [63:0] primitive_geglu_bytes, primitive_activation_bytes, primitive_fp_bytes;
    anvil_en1_geglu_pair #(.EXTERNAL_FP(1)) geglu (
        .controller_bytes(primitive_geglu_bytes),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == DOWN_WAIT && source_state == S_GEGLU_START),
        .start_ready(geglu_ready), .operation(2'd0), .gate_data(gate_hold), .up_data(up_hold),
        .done_valid(geglu_valid),
        .done_ready(rst_n && state == DOWN_WAIT && source_state == S_GEGLU_WAIT),
        .done_data(geglu_data), .done_error(geglu_error),
        .arithmetic_valid(child_arithmetic_valid[FP_GEGLU]),
        .arithmetic_ready(fp_owner == FP_GEGLU && fp_ready),
        .arithmetic_operation(child_arithmetic_operation[3*FP_GEGLU+:3]),
        .arithmetic_a(child_arithmetic_a[32*FP_GEGLU+:32]),
        .arithmetic_b(child_arithmetic_b[32*FP_GEGLU+:32]),
        .arithmetic_result_valid(fp_owner == FP_GEGLU && fp_valid),
        .arithmetic_result_ready(child_arithmetic_result_ready[FP_GEGLU]),
        .arithmetic_result_data(fp_data), .arithmetic_result_error(fp_error)
    );
    anvil_en1_activation #(.EXTERNAL_FP(1)) activation (
        .controller_bytes(primitive_activation_bytes),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == DOWN_WAIT && source_state == S_ACTIVATION_START),
        .start_ready(activation_ready), .operation(2'd3), .operand({gate_hold, 16'd0}),
        .done_valid(activation_valid),
        .done_ready(rst_n && state == DOWN_WAIT && source_state == S_ACTIVATION_WAIT),
        .done_data(activation_data), .done_error(activation_error),
        .arithmetic_valid(child_arithmetic_valid[FP_ACTIVATION]),
        .arithmetic_ready(fp_owner == FP_ACTIVATION && fp_ready),
        .arithmetic_operation(child_arithmetic_operation[3*FP_ACTIVATION+:3]),
        .arithmetic_a(child_arithmetic_a[32*FP_ACTIVATION+:32]),
        .arithmetic_b(child_arithmetic_b[32*FP_ACTIVATION+:32]),
        .arithmetic_result_valid(fp_owner == FP_ACTIVATION && fp_valid),
        .arithmetic_result_ready(child_arithmetic_result_ready[FP_ACTIVATION]),
        .arithmetic_result_data(fp_data), .arithmetic_result_error(fp_error)
    );
    wire fp_start_valid = rst_n && (fp_owner == FP_LOCAL ?
        (state == DOWN_WAIT && source_state == S_NARROW_START) :
        child_arithmetic_valid[fp_owner[1:0]]);
    wire fp_done_ready = rst_n && (fp_owner == FP_LOCAL ?
        (state == DOWN_WAIT && source_state == S_NARROW_WAIT) :
        child_arithmetic_result_ready[fp_owner[1:0]]);
    wire [2:0] fp_operation = fp_owner == FP_LOCAL ? 3'd3 :
        child_arithmetic_operation[3*fp_owner[1:0]+:3];
    wire [31:0] fp_operand_a = fp_owner == FP_LOCAL ? activation_hold :
        child_arithmetic_a[32*fp_owner[1:0]+:32];
    wire [31:0] fp_operand_b = fp_owner == FP_LOCAL ? 32'd0 :
        child_arithmetic_b[32*fp_owner[1:0]+:32];
    assign arithmetic_valid = EXTERNAL_FP == 1 && fp_start_valid;
    assign arithmetic_operation = rst_n && EXTERNAL_FP == 1 ? fp_operation : 3'd0;
    assign arithmetic_a = rst_n && EXTERNAL_FP == 1 ? fp_operand_a : 32'd0;
    assign arithmetic_b = rst_n && EXTERNAL_FP == 1 ? fp_operand_b : 32'd0;
    assign arithmetic_result_ready = EXTERNAL_FP == 1 && fp_done_ready;
    generate if (EXTERNAL_FP == 1) begin : external_arithmetic
        assign primitive_fp_bytes = 64'd0;
        assign fp_ready = rst_n && arithmetic_ready;
        assign fp_valid = rst_n && arithmetic_result_valid;
        assign fp_data = rst_n ? arithmetic_result_data : 32'd0;
        assign fp_error = rst_n ? arithmetic_result_error : 4'd0;
    end else begin : internal_arithmetic
        anvil_en1_fp32 arithmetic (
            .controller_bytes(primitive_fp_bytes),
            .clk(clk), .rst_n(rst_n),
            .start_valid(fp_start_valid), .start_ready(fp_ready),
            .operation(fp_operation), .operand_a(fp_operand_a), .operand_b(fp_operand_b),
            .done_valid(fp_valid), .done_ready(fp_done_ready),
            .done_data(fp_data), .done_error(fp_error)
        );
    end endgenerate

    assign start_ready = rst_n && state == IDLE;
    assign source_generation = rst_n ? generation_hold : 32'd0;
    assign source_token = rst_n ? token_hold : 32'd0;
    assign source_model = rst_n ? model_hold : 2'd0;
    assign source_mode = rst_n ? mode_hold : 2'd0;
    assign source_layer = rst_n ? layer_hold : 8'd0;
    assign cmd_valid = rst_n && (inner_selected ? inner_cmd_valid :
        (down_selected && down_cmd_valid));
    assign cmd_write = 0;
    assign cmd_addr = !rst_n ? 64'd0 : (inner_selected ? inner_cmd_addr :
        (down_selected ? down_cmd_addr : 64'd0));
    assign cmd_wdata = 0;
    assign result_ready = rst_n && (inner_selected ? inner_result_ready :
        (down_selected && down_result_ready));
    assign done_valid = rst_n && state == RESPONSE;
    assign done_data = rst_n ? output_hold : 32'd0;
    assign done_error = rst_n ? error_hold : 4'd0;
    assign intermediate_event = rst_n && state == DOWN_WAIT &&
        source_state == S_RESPONSE && down_source_rsp_ready && intermediate_error == 0;
    assign intermediate_bytes = intermediate_event ? 32'd2 : 32'd0;
    localparam integer CONTROLLER_BITS =
        $bits(state) + $bits(source_state) + $bits(model_hold) +
        $bits(precision_hold) + $bits(mode_hold) + $bits(layer_hold) +
        $bits(generation_hold) + $bits(token_hold) + $bits(row_hold) +
        $bits(intermediate_index) + $bits(weights_hold) + $bits(gate_hold) +
        $bits(up_hold) + $bits(intermediate_hold) + $bits(activation_hold) +
        $bits(output_hold) + $bits(intermediate_error) + $bits(first_error) +
        $bits(error_hold);
    assign controller_bytes = !rst_n ? 64'd0 : 64'((CONTROLLER_BITS + 7) >> 3) +
        primitive_geglu_bytes + primitive_activation_bytes + primitive_fp_bytes;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            source_state <= S_IDLE;
            intermediate_index <= 0;
            gate_hold <= 0;
            up_hold <= 0;
            intermediate_hold <= 0;
            activation_hold <= 0;
            intermediate_error <= 0;
            first_error <= 0;
        end else begin
            if (state == IDLE && start_valid && start_ready)
                first_error <= 0;
            case (source_state)
                S_IDLE: if (state == DOWN_WAIT && down_source_valid) begin
                    intermediate_index <= down_source_index;
                    intermediate_hold <= 0;
                    intermediate_error <= 0;
                    source_state <= S_VALIDATE;
                end
                S_VALIDATE: begin
                    if (intermediate_index >= intermediate_length) begin
                        intermediate_error <= 7;
                        if (first_error == 0)
                            first_error <= 7;
                        source_state <= S_REGISTER;
                    end else
                        source_state <= S_GATE_START;
                end
                S_GATE_START: if (inner_ready)
                    source_state <= S_GATE_WAIT;
                S_GATE_WAIT: if (inner_valid) begin
                    if (inner_error != 0) begin
                        intermediate_error <= inner_error;
                        if (first_error == 0)
                            first_error <= inner_error;
                        source_state <= S_REGISTER;
                    end else begin
                        gate_hold <= inner_data[15:0];
                        if (mode_hold == 0)
                            source_state <= S_UP_START;
                        else
                            source_state <= S_ACTIVATION_START;
                    end
                end
                S_UP_START: if (inner_ready)
                    source_state <= S_UP_WAIT;
                S_UP_WAIT: if (inner_valid) begin
                    if (inner_error != 0) begin
                        intermediate_error <= inner_error;
                        if (first_error == 0)
                            first_error <= inner_error;
                        source_state <= S_REGISTER;
                    end else begin
                        up_hold <= inner_data[15:0];
                        source_state <= S_GEGLU_START;
                    end
                end
                S_GEGLU_START: if (geglu_ready)
                    source_state <= S_GEGLU_WAIT;
                S_GEGLU_WAIT: if (geglu_valid) begin
                    intermediate_hold <= geglu_error == 0 ? geglu_data[15:0] : 16'd0;
                    intermediate_error <= geglu_error;
                    if (geglu_error != 0 && first_error == 0)
                        first_error <= geglu_error;
                    source_state <= S_REGISTER;
                end
                S_ACTIVATION_START: if (activation_ready)
                    source_state <= S_ACTIVATION_WAIT;
                S_ACTIVATION_WAIT: if (activation_valid) begin
                    if (activation_error != 0) begin
                        intermediate_error <= activation_error;
                        if (first_error == 0)
                            first_error <= activation_error;
                        source_state <= S_REGISTER;
                    end else begin
                        activation_hold <= activation_data;
                        source_state <= S_NARROW_START;
                    end
                end
                S_NARROW_START: if (fp_ready)
                    source_state <= S_NARROW_WAIT;
                S_NARROW_WAIT: if (fp_valid) begin
                    intermediate_hold <= fp_error == 0 ? fp_data[15:0] : 16'd0;
                    intermediate_error <= fp_error;
                    if (fp_error != 0 && first_error == 0)
                        first_error <= fp_error;
                    source_state <= S_REGISTER;
                end
                S_REGISTER: source_state <= S_RESPONSE;
                S_RESPONSE: if (state == DOWN_WAIT && down_source_rsp_ready)
                    source_state <= S_IDLE;
                default: begin
                    intermediate_hold <= 0;
                    intermediate_error <= 7;
                    if (first_error == 0)
                        first_error <= 7;
                    source_state <= S_REGISTER;
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
            layer_hold <= 0;
            generation_hold <= 0;
            token_hold <= 0;
            row_hold <= 0;
            weights_hold <= 0;
            output_hold <= 0;
            error_hold <= 0;
        end else begin
            case (state)
                IDLE: if (start_valid && start_ready) begin
                    model_hold <= model;
                    precision_hold <= precision;
                    mode_hold <= mode;
                    layer_hold <= layer;
                    generation_hold <= generation;
                    token_hold <= token;
                    row_hold <= output_row;
                    weights_hold <= native_weights_base;
                    output_hold <= 0;
                    error_hold <= 0;
                    state <= VALIDATE;
                end
                VALIDATE: begin
                    if ((model_hold != 1 && model_hold != 2) ||
                        precision_hold > 1 || mode_hold > 2) begin
                        error_hold <= 6;
                        state <= PUBLISH;
                    end else if (layer_hold >= (mode_hold == 0 ? 8'd16 : 8'd12) ||
                        token_hold > 131071 || row_hold >= hidden_length ||
                        weights_hold[1:0] != 0) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else
                        state <= DOWN_START;
                end
                DOWN_START: if (down_ready)
                    state <= DOWN_WAIT;
                DOWN_WAIT: if (down_valid && source_state == S_IDLE) begin
                    output_hold <= down_error == 0 ? down_data : 32'd0;
                    error_hold <= first_error != 0 ? first_error : down_error;
                    state <= REGISTER;
                end
                REGISTER: state <= PUBLISH;
                PUBLISH: state <= RESPONSE;
                RESPONSE: if (done_valid && done_ready)
                    state <= IDLE;
                default: begin
                    output_hold <= 0;
                    error_hold <= 7;
                    state <= PUBLISH;
                end
            endcase
        end
    end
endmodule
