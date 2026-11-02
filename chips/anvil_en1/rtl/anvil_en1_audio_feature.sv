module anvil_en1_audio_feature #(
    parameter integer COMPACT = 0
) (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] model, precision,
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
    output wire [63:0] vector_live_bytes, vector_physical_bytes,
    output wire [63:0] controller_bytes, native_controller_bytes, modality_controller_bytes
);
    localparam [3:0] IDLE = 0, VALIDATE = 1, NATIVE_START = 2,
        NATIVE_WAIT = 3, NATIVE_CHECK = 4, MODALITY_START = 5,
        MODALITY_WAIT = 6, MODALITY_CHECK = 7, PUBLISH = 8, RESPONSE = 9;
    localparam [2:0] S_IDLE = 0, S_VALIDATE = 1, S_READ = 2,
        S_CAPTURE = 3, S_RESPONSE = 4;
    reg [3:0] state;
    reg [2:0] source_state;
    reg [1:0] model_hold, precision_hold;
    reg [31:0] generation_hold, token_hold, received, hidden_hold, bank_index;
    reg [63:0] weights_hold;
    reg receive_bad, vector_allocated, vector_visible, bank_error;
    reg [15:0] bank_q, bank_data;
    reg [3:0] child_error_hold, error_hold;
    (* ramstyle = "M20K", nomem2reg *) reg [15:0] projected [0:1535];

    initial begin
        if (COMPACT != 0 && COMPACT != 1)
            $fatal(1, "PARAMETER ERROR: COMPACT must be 0 or 1");
    end
    wire native_selected = rst_n && (state == NATIVE_START || state == NATIVE_WAIT);
    wire native_ready, native_valid, native_cmd_valid, native_result_ready;
    wire native_source_valid, native_source_rsp_ready, native_output_valid, native_output_last;
    wire native_projection_event;
    wire [1:0] native_source_model;
    wire [31:0] native_source_generation, native_source_token, native_source_index;
    wire [31:0] native_output_index, native_projection_bytes;
    wire [15:0] native_output_data;
    wire [63:0] native_addr;
    wire [3:0] native_error;
    anvil_en1_audio_output native_output (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == NATIVE_START), .start_ready(native_ready),
        .model(model_hold), .precision(precision_hold),
        .generation(generation_hold), .token(token_hold), .audio_weights_base(weights_hold),
        .source_valid(native_source_valid), .source_ready(native_selected && source_ready),
        .source_model(native_source_model), .source_generation(native_source_generation),
        .source_token(native_source_token), .source_index(native_source_index),
        .source_rsp_valid(native_selected && source_rsp_valid),
        .source_rsp_ready(native_source_rsp_ready),
        .source_rsp_data(source_rsp_data), .source_rsp_error(source_rsp_error),
        .cmd_valid(native_cmd_valid), .cmd_ready(native_selected && cmd_ready),
        .cmd_write(), .cmd_addr(native_addr), .cmd_wdata(),
        .result_valid(native_selected && result_valid), .result_ready(native_result_ready),
        .result_data(result_data), .result_error(result_error),
        .output_valid(native_output_valid), .output_ready(rst_n && state == NATIVE_WAIT),
        .output_index(native_output_index), .output_data(native_output_data),
        .output_last(native_output_last), .done_valid(native_valid),
        .done_ready(rst_n && state == NATIVE_WAIT), .done_error(native_error),
        .weight_read_event(), .weight_read_bytes(),
        .projection_event(native_projection_event), .projection_bytes(native_projection_bytes),
        .controller_bytes(native_controller_bytes)
    );
    wire modality_selected = rst_n && (state == MODALITY_START || state == MODALITY_WAIT);
    wire modality_ready, modality_valid, modality_cmd_valid, modality_result_ready;
    wire modality_source_valid, modality_source_rsp_ready;
    wire modality_output_valid, modality_output_last, modality_projection_event;
    wire [1:0] modality_source_model, modality_source_class;
    wire [31:0] modality_generation, modality_token, modality_index;
    wire [31:0] modality_output_index, modality_projection_bytes;
    wire [15:0] modality_output_data;
    wire [63:0] modality_addr, modality_live, modality_physical;
    wire [3:0] modality_error;
    anvil_en1_modality_projection #(.COMPACT(COMPACT)) modality (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == MODALITY_START), .start_ready(modality_ready),
        .model(model_hold), .precision(precision_hold), .image_class(2'd2),
        .generation(generation_hold), .soft_token(token_hold), .weights_base(weights_hold),
        .source_valid(modality_source_valid),
        .source_ready(rst_n && state == MODALITY_WAIT && source_state == S_IDLE),
        .source_generation(modality_generation), .source_token(modality_token),
        .source_index(modality_index), .source_model(modality_source_model),
        .source_class(modality_source_class),
        .source_rsp_valid(rst_n && state == MODALITY_WAIT && source_state == S_RESPONSE),
        .source_rsp_ready(modality_source_rsp_ready),
        .source_rsp_data(bank_data), .source_rsp_error(bank_error),
        .cmd_valid(modality_cmd_valid), .cmd_ready(modality_selected && cmd_ready),
        .cmd_write(), .cmd_addr(modality_addr), .cmd_wdata(),
        .result_valid(modality_selected && result_valid), .result_ready(modality_result_ready),
        .result_data(result_data), .result_error(result_error),
        .output_valid(modality_output_valid), .output_ready(modality_selected && output_ready),
        .output_index(modality_output_index), .output_data(modality_output_data),
        .output_last(modality_output_last), .done_valid(modality_valid),
        .done_ready(rst_n && state == MODALITY_WAIT && source_state == S_IDLE),
        .done_error(modality_error), .weight_read_event(), .weight_read_bytes(),
        .projection_event(modality_projection_event), .projection_bytes(modality_projection_bytes),
        .vector_live_bytes(modality_live), .vector_physical_bytes(modality_physical),
        .controller_bytes(modality_controller_bytes)
    );
    wire native_beat_good = received < 1536 && native_output_index == received &&
        native_output_last == (received == 1535);
    wire modality_beat_good = received < hidden_hold && modality_output_index == received &&
        modality_output_last == (received + 1'b1 == hidden_hold);
    wire source_tag_good = modality_source_model == model_hold && modality_source_class == 2 &&
        modality_generation == generation_hold && modality_token == token_hold;
    always @(posedge clk) begin
        if (rst_n && state == NATIVE_WAIT && native_output_valid &&
            native_beat_good && !receive_bad)
            projected[native_output_index[10:0]] <= native_output_data;
        if (rst_n && state == MODALITY_WAIT && source_state == S_READ)
            bank_q <= projected[bank_index[10:0]];
    end
    assign start_ready = rst_n && state == IDLE;
    assign source_valid = native_selected && native_source_valid;
    assign source_rsp_ready = native_selected && native_source_rsp_ready;
    assign source_model = rst_n ? native_source_model : 2'd0;
    assign source_layer = rst_n ? 8'd12 : 8'd0;
    assign source_generation = rst_n ? native_source_generation : 32'd0;
    assign source_token = rst_n ? native_source_token : 32'd0;
    assign source_index = rst_n ? native_source_index : 32'd0;
    assign cmd_valid = native_selected ? native_cmd_valid : (modality_selected && modality_cmd_valid);
    assign cmd_write = 0;
    assign cmd_addr = !rst_n ? 64'd0 : (native_selected ? native_addr :
        (modality_selected ? modality_addr : 64'd0));
    assign cmd_wdata = 0;
    assign result_ready = native_selected ? native_result_ready :
        (modality_selected && modality_result_ready);
    assign output_valid = modality_selected && modality_output_valid;
    assign output_index = rst_n ? modality_output_index : 32'd0;
    assign output_data = rst_n ? modality_output_data : 16'd0;
    assign output_last = modality_selected && modality_output_last;
    assign done_valid = rst_n && state == RESPONSE;
    assign done_error = rst_n ? error_hold : 4'd0;
    assign weight_read_event = cmd_valid && cmd_ready;
    assign weight_read_bytes = weight_read_event ? 32'd4 : 32'd0;
    assign projection_event = native_projection_event || modality_projection_event;
    assign projection_bytes = native_projection_bytes + modality_projection_bytes;
    assign vector_live_bytes = !rst_n ? 64'd0 :
        (vector_allocated ? 64'd3072 : 64'd0) + modality_live;
    assign vector_physical_bytes = rst_n ? 64'd3072 + modality_physical : 64'd0;
    localparam integer CONTROLLER_BITS =
        $bits(state) + $bits(source_state) + $bits(model_hold) + $bits(precision_hold) +
        $bits(generation_hold) + $bits(token_hold) + $bits(received) +
        $bits(hidden_hold) + $bits(bank_index) + $bits(weights_hold) +
        $bits(receive_bad) + $bits(vector_allocated) + $bits(vector_visible) +
        $bits(bank_error) + $bits(bank_q) + $bits(bank_data) +
        $bits(child_error_hold) + $bits(error_hold);
    assign controller_bytes = rst_n ? (CONTROLLER_BITS + 7) >> 3 : 64'd0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            source_state <= S_IDLE;
            bank_index <= 0;
            bank_data <= 0;
            bank_error <= 0;
        end else begin
            case (source_state)
                S_IDLE: if (state == MODALITY_WAIT && modality_source_valid) begin
                    bank_index <= modality_index;
                    bank_data <= 0;
                    bank_error <= !source_tag_good;
                    source_state <= S_VALIDATE;
                end
                S_VALIDATE: begin
                    if (bank_error || !vector_visible || bank_index >= 1536) begin
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
                S_RESPONSE: if (state == MODALITY_WAIT && modality_source_rsp_ready)
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
            generation_hold <= 0;
            token_hold <= 0;
            received <= 0;
            hidden_hold <= 0;
            weights_hold <= 0;
            receive_bad <= 0;
            vector_allocated <= 0;
            vector_visible <= 0;
            child_error_hold <= 0;
            error_hold <= 0;
        end else begin
            if (state == NATIVE_WAIT && native_output_valid) begin
                if (!native_beat_good)
                    receive_bad <= 1;
                if (received < 1536)
                    received <= received + 1'b1;
            end
            if (state == MODALITY_WAIT && modality_output_valid && output_ready) begin
                if (!modality_beat_good)
                    receive_bad <= 1;
                if (received < hidden_hold)
                    received <= received + 1'b1;
            end
            case (state)
                IDLE: if (start_valid && start_ready) begin
                    model_hold <= model;
                    precision_hold <= precision;
                    generation_hold <= generation;
                    token_hold <= token;
                    weights_hold <= audio_weights_base;
                    hidden_hold <= COMPACT ? 32'd8 : (model == 1 ? 32'd1536 : 32'd2560);
                    received <= 0;
                    receive_bad <= 0;
                    vector_allocated <= 1;
                    vector_visible <= 0;
                    child_error_hold <= 0;
                    error_hold <= 0;
                    state <= VALIDATE;
                end
                VALIDATE: begin
                    if ((model_hold != 1 && model_hold != 2) || precision_hold > 1) begin
                        error_hold <= 6;
                        state <= PUBLISH;
                    end else if (generation_hold == 0 || token_hold > 131071 ||
                        weights_hold[1:0] != 0) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else
                        state <= NATIVE_START;
                end
                NATIVE_START: if (native_ready)
                    state <= NATIVE_WAIT;
                NATIVE_WAIT: if (native_valid) begin
                    child_error_hold <= native_error;
                    state <= NATIVE_CHECK;
                end
                NATIVE_CHECK: begin
                    if (child_error_hold != 0) begin
                        error_hold <= child_error_hold;
                        state <= PUBLISH;
                    end else if (receive_bad || received != 1536) begin
                        error_hold <= 7;
                        state <= PUBLISH;
                    end else begin
                        vector_visible <= 1;
                        state <= MODALITY_START;
                    end
                end
                MODALITY_START: if (modality_ready) begin
                    received <= 0;
                    receive_bad <= 0;
                    state <= MODALITY_WAIT;
                end
                MODALITY_WAIT: if (modality_valid && source_state == S_IDLE) begin
                    child_error_hold <= modality_error;
                    state <= MODALITY_CHECK;
                end
                MODALITY_CHECK: begin
                    if (child_error_hold != 0)
                        error_hold <= child_error_hold;
                    else if (receive_bad || received != hidden_hold)
                        error_hold <= 7;
                    state <= PUBLISH;
                end
                PUBLISH: state <= RESPONSE;
                RESPONSE: if (done_ready) begin
                    vector_allocated <= 0;
                    vector_visible <= 0;
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
