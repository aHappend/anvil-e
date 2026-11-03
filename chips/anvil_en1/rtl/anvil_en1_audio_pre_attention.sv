module anvil_en1_audio_pre_attention #(
    parameter integer RAW_SOURCE_CALLBACK = 0
) (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire raw_only,
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
    output wire output_kind,
    output wire [31:0] output_index,
    output wire [15:0] output_data,
    output wire output_last,
    output wire done_valid,
    input wire done_ready,
    output wire [3:0] done_error,
    output wire intermediate_event,
    output wire [31:0] intermediate_bytes,
    output wire [63:0] vector_live_bytes, vector_physical_bytes,
    output wire [63:0] controller_bytes, norm_controller_bytes, clamp_controller_bytes,
    output wire [63:0] ff_controller_bytes, ff_norm_controller_bytes, ff_clamp_controller_bytes,
    output wire [63:0] mlp_controller_bytes, down_controller_bytes, down_clamp_controller_bytes,
    output wire [63:0] inner_controller_bytes, inner_clamp_controller_bytes
);
    localparam [4:0] IDLE = 0, VALIDATE = 1, FF_START = 2, FF_WAIT = 3,
        CLAMP_START = 4, CLAMP_WAIT = 5, STORE = 6, ADVANCE = 7,
        FF_CHECK = 8, NORM_START = 9, NORM_WAIT = 10, NORM_CHECK = 11,
        PUBLISH = 12, RESPONSE = 13;
    localparam [2:0] S_IDLE = 0, S_VALIDATE = 1, S_READ = 2,
        S_CAPTURE = 3, S_RESPONSE = 4;
    reg [4:0] state;
    reg [2:0] source_state;
    reg [1:0] model_hold, precision_hold;
    reg [7:0] layer_hold;
    reg [31:0] generation_hold, token_hold, received, index_hold, source_index_hold;
    reg [63:0] weights_hold;
    reg [15:0] raw_hold, clamped_hold, bank_data;
    reg receive_bad, allocated, visible, bank_error, vector_ram_fault, raw_only_hold;
    reg [3:0] child_error_hold, error_hold;
    initial begin
        if (RAW_SOURCE_CALLBACK != 0 && RAW_SOURCE_CALLBACK != 1)
            $fatal(1, "PARAMETER ERROR: RAW_SOURCE_CALLBACK must be 0 or 1");
    end
    wire ff_selected = rst_n && (state == FF_START || state == FF_WAIT ||
        state == CLAMP_START || state == CLAMP_WAIT || state == STORE || state == ADVANCE);
    wire ff_ready, ff_valid, ff_source_valid, ff_source_rsp_ready;
    wire ff_cmd_valid, ff_result_ready, ff_output_valid, ff_output_last;
    wire [1:0] ff_source_model, ff_source_mode;
    wire [7:0] ff_source_layer;
    wire [31:0] ff_source_generation, ff_source_token, ff_source_index, ff_output_index;
    wire [15:0] ff_output_data;
    wire [63:0] ff_addr, ff_live, ff_physical;
    wire [3:0] ff_error;
    wire [2:0] ff_ram_write, ff_ram_read;
    wire [95:0] ff_ram_waddr, ff_ram_raddr;
    wire [47:0] ff_ram_wdata, ff_ram_rdata;
    wire [15:0] bank_q = ff_ram_rdata[15:0];
    anvil_en1_audio_feedforward #(
        .EXTERNAL_VECTOR_RAM(1), .RAW_SOURCE_CALLBACK(RAW_SOURCE_CALLBACK)
    ) feedforward (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == FF_START), .start_ready(ff_ready),
        .model(model_hold), .precision(precision_hold), .mode(2'd1),
        .layer(layer_hold), .generation(generation_hold), .token(token_hold),
        .audio_weights_base(weights_hold),
        .source_valid(ff_source_valid), .source_ready(ff_selected && source_ready),
        .source_model(ff_source_model), .source_mode(ff_source_mode),
        .source_layer(ff_source_layer), .source_generation(ff_source_generation),
        .source_token(ff_source_token), .source_index(ff_source_index),
        .source_rsp_valid(ff_selected && source_rsp_valid),
        .source_rsp_ready(ff_source_rsp_ready), .source_rsp_data(source_rsp_data),
        .source_rsp_error(source_rsp_error),
        .cmd_valid(ff_cmd_valid), .cmd_ready(ff_selected && cmd_ready),
        .cmd_write(), .cmd_addr(ff_addr), .cmd_wdata(),
        .result_valid(ff_selected && result_valid), .result_ready(ff_result_ready),
        .result_data(result_data), .result_error(result_error),
        .output_valid(ff_output_valid),
        .output_ready(rst_n && state == FF_WAIT &&
            (error_hold != 0 || vector_ram_fault || output_ready)),
        .output_index(ff_output_index), .output_data(ff_output_data), .output_last(ff_output_last),
        .done_valid(ff_valid), .done_ready(rst_n && state == FF_WAIT && !ff_output_valid),
        .done_error(ff_error), .weight_read_event(), .weight_read_bytes(),
        .intermediate_event(intermediate_event), .intermediate_bytes(intermediate_bytes),
        .vector_live_bytes(ff_live), .vector_physical_bytes(ff_physical),
        .vector_ram_write(ff_ram_write), .vector_ram_read(ff_ram_read),
        .vector_ram_waddr(ff_ram_waddr), .vector_ram_raddr(ff_ram_raddr),
        .vector_ram_wdata(ff_ram_wdata), .vector_ram_rdata(ff_ram_rdata),
        .controller_bytes(ff_controller_bytes), .norm_controller_bytes(ff_norm_controller_bytes),
        .clamp_controller_bytes(ff_clamp_controller_bytes),
        .mlp_controller_bytes(mlp_controller_bytes), .down_controller_bytes(down_controller_bytes),
        .down_clamp_controller_bytes(down_clamp_controller_bytes),
        .inner_controller_bytes(inner_controller_bytes),
        .inner_clamp_controller_bytes(inner_clamp_controller_bytes)
    );
    wire clamp_ready, clamp_valid;
    wire [15:0] clamp_data;
    wire [3:0] clamp_error;
    anvil_en1_bf16_clamp clamp (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == CLAMP_START), .start_ready(clamp_ready),
        .value(raw_hold), .minimum(16'hd015), .maximum(16'h5015),
        .done_valid(clamp_valid), .done_ready(rst_n && state == CLAMP_WAIT),
        .done_data(clamp_data), .done_error(clamp_error), .controller_bytes(clamp_controller_bytes)
    );
    wire norm_selected = rst_n && (state == NORM_START || state == NORM_WAIT);
    wire norm_ready, norm_valid, norm_source_valid, norm_source_rsp_ready;
    wire norm_cmd_valid, norm_result_ready, norm_output_valid, norm_output_last;
    wire [31:0] norm_source_index, norm_output_index;
    wire [15:0] norm_output_data;
    wire [63:0] norm_addr;
    wire [3:0] norm_error;
    anvil_en1_native_norm norm (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == NORM_START), .start_ready(norm_ready),
        .model(model_hold), .precision(precision_hold), .image_class(2'd2),
        .tensor_kind(16'h2104), .tensor_layer({8'd0, layer_hold}),
        .vector_length(32'd1024), .weights_base(weights_hold),
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
        .output_valid(norm_output_valid), .output_ready(norm_selected && output_ready),
        .output_index(norm_output_index), .output_data(norm_output_data), .output_last(norm_output_last),
        .done_valid(norm_valid), .done_ready(rst_n && state == NORM_WAIT && source_state == S_IDLE),
        .done_error(norm_error), .controller_bytes(norm_controller_bytes)
    );
    wire ff_beat_good = received < 1024 && ff_output_index == received &&
        ff_output_last == (received == 1023);
    wire norm_beat_good = received < 1024 && norm_output_index == received &&
        norm_output_last == (received == 1023);
    // Each accepted output has already consumed its raw word for the last time.
    wire store_output = rst_n && state == STORE && !receive_bad && index_hold < 1024;
    wire read_output = rst_n && state == NORM_WAIT && source_state == S_READ;
    wire [2:0] vector_range_fault;
    wire vector_access_fault = |vector_range_fault;
    genvar bank;
    generate for (bank = 0; bank < 3; bank = bank + 1) begin : shared_vectors
        (* ramstyle = "M20K", nomem2reg *) reg [15:0] payload [0:1023];
        reg [15:0] read_q;
        wire output_write = bank == 0 && store_output;
        wire output_read = bank == 0 && read_output;
        wire [31:0] ff_waddr = ff_ram_waddr[32*bank+:32];
        wire [31:0] ff_raddr = ff_ram_raddr[32*bank+:32];
        wire [31:0] waddr = output_write ? index_hold : ff_waddr;
        wire [31:0] raddr = output_read ? source_index_hold : ff_raddr;
        wire [15:0] wdata = output_write ? clamped_hold : ff_ram_wdata[16*bank+:16];
        assign vector_range_fault[bank] = rst_n &&
            ((ff_ram_write[bank] && ff_waddr >= 1024) ||
             (ff_ram_read[bank] && ff_raddr >= 1024) ||
             (output_write && ff_ram_write[bank]) ||
             (output_read && ff_ram_read[bank]) ||
             (output_write && ff_ram_read[bank] && ff_raddr == index_hold) ||
             (output_read && ff_ram_write[bank]));
        assign ff_ram_rdata[16*bank+:16] = read_q;
        always @(posedge clk) begin
            if (rst_n && !vector_access_fault) begin
                if (output_write || ff_ram_write[bank])
                    payload[waddr[9:0]] <= wdata;
                if (output_read || ff_ram_read[bank])
                    read_q <= payload[raddr[9:0]];
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
    assign start_ready = rst_n && state == IDLE;
    assign source_valid = ff_selected && ff_source_valid;
    assign source_rsp_ready = ff_selected && ff_source_rsp_ready;
    assign source_model = rst_n ? ff_source_model : 2'd0;
    assign source_layer = rst_n ? ff_source_layer : 8'd0;
    assign source_generation = rst_n ? ff_source_generation : 32'd0;
    assign source_token = rst_n ? ff_source_token : 32'd0;
    assign source_index = rst_n ? ff_source_index : 32'd0;
    assign cmd_valid = ff_selected ? ff_cmd_valid : (norm_selected && norm_cmd_valid);
    assign cmd_write = 0;
    assign cmd_addr = !rst_n ? 64'd0 : (ff_selected ? ff_addr :
        (norm_selected ? norm_addr : 64'd0));
    assign cmd_wdata = 0;
    assign result_ready = ff_selected ? ff_result_ready : (norm_selected && norm_result_ready);
    assign output_valid = rst_n && error_hold == 0 && !vector_ram_fault &&
        (state == FF_WAIT ? ff_output_valid :
        (state == NORM_WAIT && norm_output_valid));
    assign output_kind = rst_n && state == NORM_WAIT;
    assign output_index = !rst_n ? 32'd0 :
        (state == FF_WAIT ? ff_output_index : (state == NORM_WAIT ? norm_output_index : 32'd0));
    assign output_data = !rst_n ? 16'd0 :
        (state == FF_WAIT ? ff_output_data : (state == NORM_WAIT ? norm_output_data : 16'd0));
    assign output_last = rst_n && (state == FF_WAIT ? ff_output_last :
        (state == NORM_WAIT && norm_output_last));
    assign done_valid = rst_n && state == RESPONSE;
    assign done_error = !rst_n ? 4'd0 :
        (error_hold != 0 ? error_hold : (vector_ram_fault ? 4'd7 : 4'd0));
    assign vector_live_bytes = !rst_n ? 64'd0 :
        (allocated && (RAW_SOURCE_CALLBACK || ff_live == 0) ?
            64'd2048 : 64'd0) + ff_live;
    assign vector_physical_bytes = rst_n ? 64'd6144 + ff_physical : 64'd0;
    wire [31:0] CONTROLLER_BITS =
        $bits(state) + $bits(source_state) + $bits(model_hold) + $bits(precision_hold) +
        $bits(layer_hold) + $bits(generation_hold) + $bits(token_hold) +
        $bits(received) + $bits(index_hold) + $bits(source_index_hold) + $bits(weights_hold) +
        $bits(raw_hold) + $bits(clamped_hold) + $bits(bank_data) + 48 +
        $bits(receive_bad) + $bits(allocated) + $bits(visible) + $bits(bank_error) +
        $bits(vector_ram_fault) + $bits(raw_only_hold) +
        $bits(child_error_hold) + $bits(error_hold);
    assign controller_bytes = rst_n ? (CONTROLLER_BITS + 7) >> 3 : 64'd0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            source_state <= S_IDLE;
            source_index_hold <= 0;
            bank_data <= 0;
            bank_error <= 0;
        end else begin
            case (source_state)
                S_IDLE: if (state == NORM_WAIT && norm_source_valid) begin
                    source_index_hold <= norm_source_index;
                    bank_data <= 0;
                    bank_error <= 0;
                    source_state <= S_VALIDATE;
                end
                S_VALIDATE: begin
                    if (!visible || vector_ram_fault || source_index_hold >= 1024) begin
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
                S_RESPONSE: if (norm_source_rsp_ready)
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
            received <= 0;
            index_hold <= 0;
            weights_hold <= 0;
            raw_hold <= 0;
            clamped_hold <= 0;
            receive_bad <= 0;
            raw_only_hold <= 0;
            allocated <= 0;
            visible <= 0;
            child_error_hold <= 0;
            error_hold <= 0;
        end else begin
            if (state == NORM_WAIT && norm_output_valid && output_ready) begin
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
                    raw_only_hold <= raw_only;
                    received <= 0;
                    receive_bad <= 0;
                    allocated <= 0;
                    visible <= 0;
                    child_error_hold <= 0;
                    error_hold <= 0;
                    state <= VALIDATE;
                end
                VALIDATE: begin
                    if ((model_hold != 1 && model_hold != 2) || precision_hold > 1) begin
                        error_hold <= 6;
                        state <= PUBLISH;
                    end else if (generation_hold == 0 || layer_hold >= 12 || token_hold > 131071 ||
                        weights_hold[1:0] != 0) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else
                        state <= FF_START;
                end
                FF_START: if (ff_ready)
                    state <= FF_WAIT;
                FF_WAIT: begin
                    if (ff_output_valid && (error_hold != 0 || vector_ram_fault)) begin
                        if (received < 1024)
                            received <= received + 1'b1;
                    end else if (ff_output_valid && output_ready) begin
                        allocated <= !raw_only_hold;
                        raw_hold <= ff_output_data;
                        index_hold <= ff_output_index;
                        if (!ff_beat_good)
                            receive_bad <= 1;
                        if (received < 1024)
                            received <= received + 1'b1;
                        if (!raw_only_hold)
                            state <= CLAMP_START;
                    end else if (ff_valid && !ff_output_valid) begin
                        child_error_hold <= ff_error;
                        state <= FF_CHECK;
                    end
                end
                CLAMP_START: if (clamp_ready)
                    state <= CLAMP_WAIT;
                CLAMP_WAIT: if (clamp_valid) begin
                    clamped_hold <= clamp_data;
                    if (clamp_error != 0) begin
                        if (error_hold == 0)
                            error_hold <= clamp_error;
                        state <= ADVANCE;
                    end else
                        state <= STORE;
                end
                STORE: state <= ADVANCE;
                ADVANCE: state <= FF_WAIT;
                FF_CHECK: begin
                    if (child_error_hold != 0 || error_hold != 0 || vector_ram_fault) begin
                        if (error_hold == 0)
                            error_hold <= child_error_hold != 0 ? child_error_hold : 4'd7;
                        state <= PUBLISH;
                    end else if (receive_bad || received != 1024) begin
                        error_hold <= 7;
                        state <= PUBLISH;
                    end else if (raw_only_hold)
                        state <= PUBLISH;
                    else begin
                        visible <= 1;
                        state <= NORM_START;
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
                    if (child_error_hold != 0)
                        error_hold <= child_error_hold;
                    else if (receive_bad || received != 1024)
                        error_hold <= 7;
                    state <= PUBLISH;
                end
                PUBLISH: state <= RESPONSE;
                RESPONSE: if (done_ready) begin
                    allocated <= 0;
                    visible <= 0;
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
