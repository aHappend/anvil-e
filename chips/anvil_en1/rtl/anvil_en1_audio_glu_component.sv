module anvil_en1_audio_glu_component #(
    parameter integer EXTERNAL_VECTOR_RAM = 0
) (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] model, precision,
    input wire [7:0] layer,
    input wire [31:0] generation, token, channel,
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
    output wire done_valid,
    input wire done_ready,
    output wire [31:0] done_data,
    output wire [3:0] done_error,
    output wire weight_read_event,
    output wire [31:0] weight_read_bytes,
    output wire projection_event,
    output wire [31:0] projection_bytes,
    output wire [63:0] vector_live_bytes, vector_physical_bytes,
    output wire vector_ram_write, vector_ram_read,
    output wire [31:0] vector_ram_waddr, vector_ram_raddr,
    output wire [15:0] vector_ram_wdata,
    input wire [15:0] vector_ram_rdata,
    output wire [63:0] controller_bytes, norm_controller_bytes,
    output wire [63:0] projection_controller_bytes, clamp_controller_bytes
);
    localparam [3:0] IDLE = 0, VALIDATE = 1, NORM_START = 2,
        NORM_WAIT = 3, NORM_CHECK = 4, PROJECTION_START = 5,
        PROJECTION_WAIT = 6, PROJECTION_CHECK = 7, GLU_START = 8,
        GLU_WAIT = 9, PUBLISH = 10, RESPONSE = 11;
    localparam [2:0] S_IDLE = 0, S_VALIDATE = 1, S_READ = 2,
        S_CAPTURE = 3, S_RESPONSE = 4;
    reg [3:0] state;
    reg [2:0] source_state;
    reg [1:0] model_hold, precision_hold;
    reg [7:0] layer_hold;
    reg [31:0] generation_hold, token_hold, channel_hold, received, bank_index;
    reg [63:0] weights_hold;
    reg second_half, vector_allocated, vector_visible, receive_bad, bank_error;
    reg [15:0] first_half, gate_hold, projected_hold, bank_data;
    wire [15:0] bank_q;
    reg [31:0] output_hold;
    reg [3:0] child_error_hold, error_hold;
    initial begin
        if (EXTERNAL_VECTOR_RAM != 0 && EXTERNAL_VECTOR_RAM != 1)
            $fatal(1, "PARAMETER ERROR: EXTERNAL_VECTOR_RAM must be 0 or 1");
    end

    wire norm_selected = rst_n && (state == NORM_START || state == NORM_WAIT);
    wire norm_ready, norm_valid, norm_cmd_valid, norm_result_ready;
    wire norm_source_valid, norm_source_rsp_ready, norm_output_valid, norm_output_last;
    wire [31:0] norm_source_index, norm_output_index;
    wire [15:0] norm_output_data;
    wire [63:0] norm_addr;
    wire [3:0] norm_error;
    anvil_en1_native_norm norm (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == NORM_START), .start_ready(norm_ready),
        .model(model_hold), .precision(precision_hold), .image_class(2'd2),
        .tensor_kind(16'h210c), .tensor_layer({8'd0, layer_hold}),
        .vector_length(32'd1024), .weights_base(weights_hold),
        .source_valid(norm_source_valid), .source_ready(norm_selected && source_ready),
        .source_index(norm_source_index),
        .source_rsp_valid(norm_selected && source_rsp_valid),
        .source_rsp_ready(norm_source_rsp_ready), .source_rsp_data(source_rsp_data),
        .source_rsp_error(source_rsp_error),
        .cmd_valid(norm_cmd_valid), .cmd_ready(norm_selected && cmd_ready),
        .cmd_write(), .cmd_addr(norm_addr), .cmd_wdata(),
        .result_valid(norm_selected && result_valid), .result_ready(norm_result_ready),
        .result_data(result_data), .result_error(result_error),
        .output_valid(norm_output_valid), .output_ready(rst_n && state == NORM_WAIT),
        .output_index(norm_output_index), .output_data(norm_output_data),
        .output_last(norm_output_last), .done_valid(norm_valid),
        .done_ready(rst_n && state == NORM_WAIT), .done_error(norm_error),
        .controller_bytes(norm_controller_bytes)
    );
    wire projection_selected = rst_n &&
        (state == PROJECTION_START || state == PROJECTION_WAIT);
    wire projection_ready, projection_valid, projection_cmd_valid, projection_result_ready;
    wire projection_source_valid, projection_source_rsp_ready;
    wire [31:0] projection_index, projection_data;
    wire [63:0] projection_addr;
    wire [3:0] projection_error;
    wire [31:0] projection_row = second_half ?
        {21'd0, 1'b1, channel_hold[9:0]} : channel_hold;
    anvil_en1_clipped_projection projection (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == PROJECTION_START), .start_ready(projection_ready),
        .model(model_hold), .precision(precision_hold), .image_class(2'd2),
        .image_base(weights_hold), .tensor_kind(16'h210d),
        .tensor_layer({8'd0, layer_hold}), .row_index(projection_row),
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
        .controller_bytes(projection_controller_bytes),
        .clamp_controller_bytes(clamp_controller_bytes)
    );
    wire glu_ready, glu_valid;
    wire [31:0] glu_data;
    wire [3:0] glu_error;
    wire [63:0] primitive_geglu_bytes;
    anvil_en1_geglu_pair glu (
        .controller_bytes(primitive_geglu_bytes),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == GLU_START), .start_ready(glu_ready),
        .operation(2'd2), .gate_data(gate_hold), .up_data(first_half),
        .done_valid(glu_valid), .done_ready(rst_n && state == GLU_WAIT),
        .done_data(glu_data), .done_error(glu_error)
    );

    wire norm_beat_good = received < 1024 && norm_output_index == received &&
        norm_output_last == (received == 1023);
    wire bank_write = rst_n && state == NORM_WAIT && norm_output_valid &&
        norm_beat_good && !receive_bad;
    wire bank_read = rst_n && state == PROJECTION_WAIT && source_state == S_READ;
    assign vector_ram_write = EXTERNAL_VECTOR_RAM && bank_write;
    assign vector_ram_read = EXTERNAL_VECTOR_RAM && bank_read;
    assign vector_ram_waddr = rst_n && EXTERNAL_VECTOR_RAM ? norm_output_index : 32'd0;
    assign vector_ram_raddr = rst_n && EXTERNAL_VECTOR_RAM ? bank_index : 32'd0;
    assign vector_ram_wdata = rst_n && EXTERNAL_VECTOR_RAM ? norm_output_data : 16'd0;
    generate if (EXTERNAL_VECTOR_RAM == 1) begin : external_vector
        assign bank_q = vector_ram_rdata;
    end else begin : local_vector
        (* ramstyle = "M20K", nomem2reg *) reg [15:0] normalized [0:1023];
        reg [15:0] read_q;
        assign bank_q = read_q;
        always @(posedge clk) begin
            if (bank_write && norm_output_index < 1024)
                normalized[norm_output_index[9:0]] <= norm_output_data;
            if (bank_read && bank_index < 1024)
                read_q <= normalized[bank_index[9:0]];
        end
    end endgenerate
    assign start_ready = rst_n && state == IDLE;
    assign source_valid = norm_selected && norm_source_valid;
    assign source_rsp_ready = norm_selected && norm_source_rsp_ready;
    assign source_model = rst_n ? model_hold : 2'd0;
    assign source_layer = rst_n ? layer_hold : 8'd0;
    assign source_generation = rst_n ? generation_hold : 32'd0;
    assign source_token = rst_n ? token_hold : 32'd0;
    assign source_index = norm_selected ? norm_source_index : 32'd0;
    assign cmd_valid = norm_selected ? norm_cmd_valid :
        (projection_selected && projection_cmd_valid);
    assign cmd_write = 0;
    assign cmd_addr = !rst_n ? 64'd0 : (norm_selected ? norm_addr :
        (projection_selected ? projection_addr : 64'd0));
    assign cmd_wdata = 0;
    assign result_ready = norm_selected ? norm_result_ready :
        (projection_selected && projection_result_ready);
    assign done_valid = rst_n && state == RESPONSE;
    assign done_data = rst_n ? output_hold : 32'd0;
    assign done_error = rst_n ? error_hold : 4'd0;
    assign weight_read_event = cmd_valid && cmd_ready;
    assign weight_read_bytes = weight_read_event ? 32'd4 : 32'd0;
    assign projection_event = rst_n && state == PROJECTION_START && projection_ready;
    assign projection_bytes = !projection_event ? 32'd0 :
        (precision_hold == 0 ? 32'd2048 : 32'd576);
    assign vector_live_bytes = rst_n && vector_allocated ? 64'd2048 : 64'd0;
    assign vector_physical_bytes = rst_n && !EXTERNAL_VECTOR_RAM ? 64'd2048 : 64'd0;
    wire [31:0] CONTROLLER_BITS =
        $bits(state) + $bits(source_state) + $bits(model_hold) + $bits(precision_hold) +
        $bits(layer_hold) + $bits(generation_hold) + $bits(token_hold) +
        $bits(channel_hold) + $bits(received) + $bits(bank_index) + $bits(weights_hold) +
        $bits(second_half) + $bits(vector_allocated) + $bits(vector_visible) +
        $bits(receive_bad) + $bits(bank_error) + $bits(first_half) + $bits(gate_hold) +
        $bits(projected_hold) + (EXTERNAL_VECTOR_RAM ? 0 : 16) +
        $bits(bank_data) + $bits(output_hold) +
        $bits(child_error_hold) + $bits(error_hold);
    assign controller_bytes = !rst_n ? 64'd0 :
        64'((CONTROLLER_BITS + 7) >> 3) + primitive_geglu_bytes;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            source_state <= S_IDLE;
            bank_index <= 0;
            bank_error <= 0;
            bank_data <= 0;
        end else begin
            case (source_state)
                S_IDLE: if (state == PROJECTION_WAIT && projection_source_valid) begin
                    bank_index <= projection_index;
                    bank_error <= 0;
                    bank_data <= 0;
                    source_state <= S_VALIDATE;
                end
                S_VALIDATE: begin
                    if (bank_index >= 1024 || !vector_visible) begin
                        bank_error <= 1;
                        source_state <= S_RESPONSE;
                    end else
                        source_state <= S_READ;
                end
                S_READ: source_state <= S_CAPTURE;
                S_CAPTURE: begin
                    bank_data <= bank_q;
                    source_state <= S_RESPONSE;
                end
                S_RESPONSE: if (state == PROJECTION_WAIT && projection_source_rsp_ready)
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
            model_hold <= 0;
            precision_hold <= 0;
            layer_hold <= 0;
            generation_hold <= 0;
            token_hold <= 0;
            channel_hold <= 0;
            received <= 0;
            weights_hold <= 0;
            second_half <= 0;
            vector_allocated <= 0;
            vector_visible <= 0;
            receive_bad <= 0;
            first_half <= 0;
            gate_hold <= 0;
            projected_hold <= 0;
            output_hold <= 0;
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
                    channel_hold <= channel;
                    weights_hold <= audio_weights_base;
                    second_half <= 0;
                    vector_allocated <= 1;
                    vector_visible <= 0;
                    receive_bad <= 0;
                    received <= 0;
                    first_half <= 0;
                    gate_hold <= 0;
                    projected_hold <= 0;
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
                        token_hold > 131071 || channel_hold >= 1024 ||
                        weights_hold[1:0] != 0) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else
                        state <= NORM_START;
                end
                NORM_START: if (norm_ready)
                    state <= NORM_WAIT;
                NORM_WAIT: if (norm_valid) begin
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
                        vector_visible <= 1;
                        state <= PROJECTION_START;
                    end
                end
                PROJECTION_START: if (projection_ready)
                    state <= PROJECTION_WAIT;
                PROJECTION_WAIT: if (projection_valid && source_state == S_IDLE) begin
                    projected_hold <= projection_data[15:0];
                    child_error_hold <= projection_error;
                    state <= PROJECTION_CHECK;
                end
                PROJECTION_CHECK: begin
                    if (child_error_hold != 0) begin
                        error_hold <= child_error_hold;
                        state <= PUBLISH;
                    end else if (!second_half) begin
                        first_half <= projected_hold;
                        second_half <= 1;
                        state <= PROJECTION_START;
                    end else begin
                        gate_hold <= projected_hold;
                        state <= GLU_START;
                    end
                end
                GLU_START: if (glu_ready)
                    state <= GLU_WAIT;
                GLU_WAIT: if (glu_valid) begin
                    output_hold <= glu_error == 0 ? glu_data : 32'd0;
                    error_hold <= glu_error;
                    state <= PUBLISH;
                end
                PUBLISH: state <= RESPONSE;
                RESPONSE: if (done_ready) begin
                    vector_allocated <= 0;
                    vector_visible <= 0;
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
