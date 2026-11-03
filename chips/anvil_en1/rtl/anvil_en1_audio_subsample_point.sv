module anvil_en1_audio_subsample_point (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] model, precision,
    input wire stage,
    input wire [31:0] generation, frames, output_time, output_frequency,
    input wire [63:0] audio_weights_base,
    output wire source_valid,
    input wire source_ready,
    output wire [31:0] source_generation, source_time, source_frequency, source_channel,
    output wire [1:0] source_model,
    output wire source_stage,
    input wire source_rsp_valid,
    output wire source_rsp_ready,
    input wire [15:0] source_rsp_data,
    input wire source_rsp_error,
    output wire mask_valid,
    input wire mask_ready,
    output wire [31:0] mask_generation, mask_frame,
    output wire [1:0] mask_model,
    input wire mask_rsp_valid,
    output wire mask_rsp_ready,
    input wire [31:0] mask_rsp_data,
    input wire mask_rsp_error,
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
    output wire output_last, output_mask,
    output wire done_valid,
    input wire done_ready,
    output wire done_mask,
    output wire [3:0] done_error,
    output wire weight_read_event,
    output wire [31:0] weight_read_bytes,
    output wire projection_event,
    output wire [31:0] projection_bytes,
    output wire source_read_event, mask_read_event,
    output wire [31:0] source_read_bytes, mask_read_bytes,
    output wire [63:0] vector_live_bytes, vector_physical_bytes,
    output wire [63:0] controller_bytes, convolution_controller_bytes,
    output wire [63:0] divider_controller_bytes, norm_controller_bytes
);
    localparam [4:0] IDLE = 0, VALIDATE = 1, SHAPE = 2,
        SHAPE_VALIDATE = 3, MASK_FRAME = 4, MASK_SEND = 5, MASK_WAIT = 6,
        MASK_REGISTER = 7, CONV_START = 8, CONV_WAIT = 9,
        CONV_REGISTER = 10, CONV_STORE = 11, CHANNEL_ADVANCE = 12,
        NORM_START = 13, NORM_WAIT = 14, NORM_CHECK = 15,
        PUBLISH = 16, RESPONSE = 17;
    localparam [2:0] S_IDLE = 0, S_VALIDATE = 1, S_READ = 2,
        S_CAPTURE = 3, S_RESPONSE = 4;
    localparam [1:0] O_IDLE = 0, O_CLASSIFY = 1, O_EMIT = 2;
    reg [4:0] state;
    reg [2:0] source_state;
    reg [1:0] output_state;
    reg [1:0] model_hold, precision_hold;
    reg stage_hold;
    reg [31:0] generation_hold, frames_hold, time_hold, frequency_hold;
    reg [31:0] half_frames, output_times, output_frequencies, channels_hold, channel_hold;
    reg [31:0] mask_frame_hold, mask_word, source_index_hold, received, emitted;
    reg [31:0] output_index_hold, conv_value;
    reg [63:0] weights_hold;
    reg mask_hold, mask_error_hold, allocated, vector_visible, source_error_hold;
    reg receive_bad, output_last_hold;
    reg [15:0] bank_q, source_data_hold, output_data_hold;
    reg [3:0] child_error_hold, error_hold;
    (* ramstyle = "M20K", nomem2reg *) reg [15:0] convolved [0:127];

    wire conv_ready, conv_valid, conv_cmd_valid, conv_result_ready;
    wire conv_mask_valid, conv_mask_rsp_ready;
    wire [31:0] conv_mask_generation, conv_mask_frame, conv_result;
    wire [1:0] conv_mask_model;
    wire [63:0] conv_addr;
    wire [3:0] conv_error;
    wire conv_mask_event;
    wire [31:0] conv_mask_bytes;
    wire conv_selected = rst_n && (state == CONV_START || state == CONV_WAIT);
    anvil_en1_audio_conv_row convolution (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == CONV_START), .start_ready(conv_ready),
        .model(model_hold), .precision(precision_hold), .stage(stage_hold),
        .generation(generation_hold), .frames(frames_hold),
        .output_time(time_hold), .output_frequency(frequency_hold),
        .output_channel(channel_hold), .audio_weights_base(weights_hold),
        .source_valid(source_valid), .source_ready(conv_selected && source_ready),
        .source_generation(source_generation), .source_time(source_time),
        .source_frequency(source_frequency), .source_channel(source_channel),
        .source_model(source_model), .source_stage(source_stage),
        .source_rsp_valid(conv_selected && source_rsp_valid),
        .source_rsp_ready(source_rsp_ready),
        .source_rsp_data(source_rsp_data), .source_rsp_error(source_rsp_error),
        .mask_valid(conv_mask_valid), .mask_ready(conv_selected && mask_ready),
        .mask_generation(conv_mask_generation), .mask_frame(conv_mask_frame),
        .mask_model(conv_mask_model), .mask_rsp_valid(conv_selected && mask_rsp_valid),
        .mask_rsp_ready(conv_mask_rsp_ready), .mask_rsp_data(mask_rsp_data),
        .mask_rsp_error(mask_rsp_error),
        .cmd_valid(conv_cmd_valid), .cmd_ready(conv_selected && cmd_ready),
        .cmd_write(), .cmd_addr(conv_addr), .cmd_wdata(),
        .result_valid(conv_selected && result_valid), .result_ready(conv_result_ready),
        .result_data(result_data), .result_error(result_error),
        .done_valid(conv_valid), .done_ready(rst_n && state == CONV_WAIT),
        .done_data(conv_result), .done_error(conv_error),
        .weight_read_event(), .weight_read_bytes(),
        .projection_event(projection_event), .projection_bytes(projection_bytes),
        .source_read_event(source_read_event), .source_read_bytes(source_read_bytes),
        .mask_read_event(conv_mask_event), .mask_read_bytes(conv_mask_bytes),
        .controller_bytes(convolution_controller_bytes),
        .divider_controller_bytes(divider_controller_bytes)
    );
    wire norm_ready, norm_valid, norm_source_valid, norm_source_rsp_ready;
    wire norm_cmd_valid, norm_result_ready, norm_output_valid, norm_output_last;
    wire [31:0] norm_source_index, norm_output_index;
    wire [15:0] norm_output_data;
    wire [63:0] norm_addr;
    wire [3:0] norm_error;
    wire norm_selected = rst_n && (state == NORM_START || state == NORM_WAIT);
    anvil_en1_native_norm channel_norm (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == NORM_START), .start_ready(norm_ready),
        .model(model_hold), .precision(precision_hold), .image_class(2'd2),
        .tensor_kind(stage_hold ? 16'h2003 : 16'h2001), .tensor_layer(16'hffff),
        .vector_length(channels_hold), .weights_base(weights_hold),
        .source_valid(norm_source_valid),
        .source_ready(rst_n && state == NORM_WAIT && source_state == S_IDLE),
        .source_index(norm_source_index),
        .source_rsp_valid(rst_n && state == NORM_WAIT && source_state == S_RESPONSE),
        .source_rsp_ready(norm_source_rsp_ready),
        .source_rsp_data(source_data_hold), .source_rsp_error(source_error_hold),
        .cmd_valid(norm_cmd_valid), .cmd_ready(norm_selected && cmd_ready),
        .cmd_write(), .cmd_addr(norm_addr), .cmd_wdata(),
        .result_valid(norm_selected && result_valid), .result_ready(norm_result_ready),
        .result_data(result_data), .result_error(result_error),
        .output_valid(norm_output_valid),
        .output_ready(rst_n && state == NORM_WAIT && output_state == O_IDLE),
        .output_index(norm_output_index), .output_data(norm_output_data),
        .output_last(norm_output_last),
        .done_valid(norm_valid),
        .done_ready(rst_n && state == NORM_WAIT &&
            source_state == S_IDLE && output_state == O_IDLE),
        .done_error(norm_error), .controller_bytes(norm_controller_bytes)
    );
    wire norm_output_accepted = rst_n && state == NORM_WAIT &&
        output_state == O_IDLE && norm_output_valid;
    wire beat_good = received < channels_hold && norm_output_index == received &&
        norm_output_last == (received + 1'b1 == channels_hold);
    wire output_nan = output_data_hold[14:7] == 8'hff && output_data_hold[6:0] != 0;
    always @(posedge clk) begin
        if (rst_n && state == CONV_STORE)
            convolved[channel_hold[6:0]] <= conv_value[15:0];
        if (rst_n && source_state == S_READ)
            bank_q <= convolved[source_index_hold[6:0]];
    end
    assign start_ready = rst_n && state == IDLE;
    assign mask_valid = rst_n && (state == MASK_SEND ||
        (conv_selected && conv_mask_valid));
    assign mask_generation = !rst_n ? 32'd0 :
        (conv_selected ? conv_mask_generation : generation_hold);
    assign mask_model = !rst_n ? 2'd0 : (conv_selected ? conv_mask_model : model_hold);
    assign mask_frame = !rst_n ? 32'd0 :
        (conv_selected ? conv_mask_frame : mask_frame_hold);
    assign mask_rsp_ready = rst_n && (state == MASK_WAIT ||
        (conv_selected && conv_mask_rsp_ready));
    assign cmd_valid = conv_selected ? conv_cmd_valid :
        (norm_selected && norm_cmd_valid);
    assign cmd_write = 0;
    assign cmd_addr = !rst_n ? 64'd0 :
        (conv_selected ? conv_addr : (norm_selected ? norm_addr : 64'd0));
    assign cmd_wdata = 0;
    assign result_ready = conv_selected ? conv_result_ready :
        (norm_selected && norm_result_ready);
    assign output_valid = rst_n && output_state == O_EMIT;
    assign output_index = rst_n ? output_index_hold : 32'd0;
    assign output_data = rst_n ? output_data_hold : 16'd0;
    assign output_last = rst_n && output_state == O_EMIT && output_last_hold;
    assign output_mask = rst_n && mask_hold;
    assign done_valid = rst_n && state == RESPONSE;
    assign done_mask = rst_n && state == RESPONSE && error_hold == 0 && mask_hold;
    assign done_error = rst_n ? error_hold : 4'd0;
    assign weight_read_event = cmd_valid && cmd_ready;
    assign weight_read_bytes = weight_read_event ? 32'd4 : 32'd0;
    assign mask_read_event = (rst_n && state == MASK_SEND && mask_ready) || conv_mask_event;
    assign mask_read_bytes = (rst_n && state == MASK_SEND && mask_ready ? 32'd4 : 32'd0) +
        conv_mask_bytes;
    assign vector_live_bytes = rst_n && allocated ? 64'd256 : 64'd0;
    assign vector_physical_bytes = rst_n ? 64'd256 : 64'd0;
    wire [31:0] CONTROLLER_BITS =
        $bits(state) + $bits(source_state) + $bits(output_state) +
        $bits(model_hold) + $bits(precision_hold) + $bits(stage_hold) +
        $bits(generation_hold) + $bits(frames_hold) + $bits(time_hold) +
        $bits(frequency_hold) + $bits(half_frames) + $bits(output_times) +
        $bits(output_frequencies) + $bits(channels_hold) + $bits(channel_hold) +
        $bits(mask_frame_hold) + $bits(mask_word) + $bits(source_index_hold) +
        $bits(received) + $bits(emitted) + $bits(output_index_hold) +
        $bits(conv_value) + $bits(weights_hold) + $bits(mask_hold) +
        $bits(mask_error_hold) + $bits(allocated) + $bits(vector_visible) +
        $bits(source_error_hold) + $bits(receive_bad) + $bits(output_last_hold) +
        $bits(bank_q) + $bits(source_data_hold) + $bits(output_data_hold) +
        $bits(child_error_hold) + $bits(error_hold);
    assign controller_bytes = rst_n ? (CONTROLLER_BITS + 7) >> 3 : 64'd0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            source_state <= S_IDLE;
            source_index_hold <= 0;
            source_data_hold <= 0;
            source_error_hold <= 0;
        end else begin
            case (source_state)
                S_IDLE: if (state == NORM_WAIT && norm_source_valid) begin
                    source_index_hold <= norm_source_index;
                    source_data_hold <= 0;
                    source_error_hold <= 0;
                    source_state <= S_VALIDATE;
                end
                S_VALIDATE: begin
                    if (!vector_visible || source_index_hold >= channels_hold) begin
                        source_error_hold <= 1;
                        source_state <= S_RESPONSE;
                    end else
                        source_state <= S_READ;
                end
                S_READ: source_state <= S_CAPTURE;
                S_CAPTURE: begin
                    source_data_hold <= bank_q;
                    source_state <= S_RESPONSE;
                end
                S_RESPONSE: if (state == NORM_WAIT && norm_source_rsp_ready)
                    source_state <= S_IDLE;
                default: begin
                    source_error_hold <= 1;
                    source_state <= S_RESPONSE;
                end
            endcase
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            output_state <= O_IDLE;
            output_index_hold <= 0;
            output_data_hold <= 0;
            output_last_hold <= 0;
            received <= 0;
            emitted <= 0;
            receive_bad <= 0;
        end else begin
            if (state == IDLE && start_valid && start_ready) begin
                received <= 0;
                emitted <= 0;
                receive_bad <= 0;
            end
            case (output_state)
                O_IDLE: if (norm_output_accepted) begin
                    output_index_hold <= norm_output_index;
                    output_data_hold <= norm_output_data;
                    output_last_hold <= norm_output_last;
                    if (!beat_good)
                        receive_bad <= 1;
                    if (received < channels_hold)
                        received <= received + 1'b1;
                    output_state <= O_CLASSIFY;
                end
                O_CLASSIFY: begin
                    if (output_nan)
                        output_data_hold <= 16'h7fc0;
                    else if (output_data_hold[15] && output_data_hold[14:0] != 0)
                        output_data_hold <= 0;
                    output_state <= O_EMIT;
                end
                O_EMIT: if (output_ready) begin
                    if (emitted < channels_hold)
                        emitted <= emitted + 1'b1;
                    output_state <= O_IDLE;
                end
                default: begin
                    receive_bad <= 1;
                    output_state <= O_IDLE;
                end
            endcase
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            model_hold <= 0;
            precision_hold <= 0;
            stage_hold <= 0;
            generation_hold <= 0;
            frames_hold <= 0;
            time_hold <= 0;
            frequency_hold <= 0;
            half_frames <= 0;
            output_times <= 0;
            output_frequencies <= 0;
            channels_hold <= 0;
            channel_hold <= 0;
            mask_frame_hold <= 0;
            mask_word <= 0;
            conv_value <= 0;
            weights_hold <= 0;
            mask_hold <= 0;
            mask_error_hold <= 0;
            allocated <= 0;
            vector_visible <= 0;
            child_error_hold <= 0;
            error_hold <= 0;
        end else begin
            case (state)
                IDLE: if (start_valid && start_ready) begin
                    model_hold <= model;
                    precision_hold <= precision;
                    stage_hold <= stage;
                    generation_hold <= generation;
                    frames_hold <= frames;
                    time_hold <= output_time;
                    frequency_hold <= output_frequency;
                    weights_hold <= audio_weights_base;
                    channel_hold <= 0;
                    mask_hold <= 0;
                    allocated <= 1;
                    vector_visible <= 0;
                    child_error_hold <= 0;
                    error_hold <= 0;
                    state <= VALIDATE;
                end
                VALIDATE: begin
                    if ((model_hold != 1 && model_hold != 2) || precision_hold > 1) begin
                        error_hold <= 6;
                        state <= PUBLISH;
                    end else if (generation_hold == 0 || frames_hold == 0 ||
                        frames_hold > 131072 || weights_hold[1:0] != 0) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else begin
                        half_frames <= (frames_hold >> 1) + {31'd0, frames_hold[0]};
                        state <= SHAPE;
                    end
                end
                SHAPE: begin
                    output_times <= stage_hold ?
                        (half_frames >> 1) + {31'd0, half_frames[0]} : half_frames;
                    output_frequencies <= stage_hold ? 32'd32 : 32'd64;
                    channels_hold <= stage_hold ? 32'd32 : 32'd128;
                    state <= SHAPE_VALIDATE;
                end
                SHAPE_VALIDATE: begin
                    if (time_hold >= output_times || frequency_hold >= output_frequencies) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else
                        state <= MASK_FRAME;
                end
                MASK_FRAME: begin
                    mask_frame_hold <= stage_hold ? time_hold << 2 : time_hold << 1;
                    state <= MASK_SEND;
                end
                MASK_SEND: if (mask_ready)
                    state <= MASK_WAIT;
                MASK_WAIT: if (mask_rsp_valid) begin
                    mask_word <= mask_rsp_data;
                    mask_error_hold <= mask_rsp_error;
                    state <= MASK_REGISTER;
                end
                MASK_REGISTER: begin
                    if (mask_error_hold) begin
                        error_hold <= 7;
                        state <= PUBLISH;
                    end else if (mask_word > 1) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else begin
                        mask_hold <= mask_word[0];
                        state <= CONV_START;
                    end
                end
                CONV_START: if (conv_ready)
                    state <= CONV_WAIT;
                CONV_WAIT: if (conv_valid) begin
                    conv_value <= conv_result;
                    child_error_hold <= conv_error;
                    state <= CONV_REGISTER;
                end
                CONV_REGISTER: begin
                    if (child_error_hold != 0) begin
                        error_hold <= child_error_hold;
                        state <= PUBLISH;
                    end else
                        state <= CONV_STORE;
                end
                CONV_STORE: state <= CHANNEL_ADVANCE;
                CHANNEL_ADVANCE: begin
                    if (channel_hold + 1'b1 == channels_hold) begin
                        vector_visible <= 1;
                        state <= NORM_START;
                    end else begin
                        channel_hold <= channel_hold + 1'b1;
                        state <= CONV_START;
                    end
                end
                NORM_START: if (norm_ready)
                    state <= NORM_WAIT;
                NORM_WAIT: if (norm_valid && source_state == S_IDLE && output_state == O_IDLE) begin
                    child_error_hold <= norm_error;
                    state <= NORM_CHECK;
                end
                NORM_CHECK: begin
                    if (child_error_hold != 0)
                        error_hold <= child_error_hold;
                    else if (receive_bad || received != channels_hold || emitted != channels_hold)
                        error_hold <= 7;
                    state <= PUBLISH;
                end
                PUBLISH: state <= RESPONSE;
                RESPONSE: if (done_ready) begin
                    vector_visible <= 0;
                    allocated <= 0;
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
