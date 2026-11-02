module anvil_en1_audio_subsample_execute (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] model, precision,
    input wire stage,
    input wire [31:0] generation, frames, output_time, output_frequency,
    input wire [63:0] audio_base, audio_weights_base,
    output wire generated_valid,
    input wire generated_ready,
    output wire [31:0] generated_generation, generated_time, generated_frequency,
    output wire [31:0] generated_channel,
    output wire [1:0] generated_model,
    input wire generated_rsp_valid,
    output wire generated_rsp_ready,
    input wire [15:0] generated_rsp_data,
    input wire generated_rsp_error,
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
    output wire input_read_event, weight_read_event,
    output wire [31:0] input_read_bytes, weight_read_bytes,
    output wire projection_event,
    output wire [31:0] projection_bytes,
    output wire generated_read_event,
    output wire [31:0] generated_read_bytes,
    output wire [63:0] vector_live_bytes, vector_physical_bytes,
    output wire [63:0] controller_bytes, input_controller_bytes,
    output wire [63:0] point_controller_bytes, convolution_controller_bytes,
    output wire [63:0] divider_controller_bytes, norm_controller_bytes
);
    localparam [2:0] IDLE = 0, VALIDATE = 1, POINT_START = 2,
        POINT_WAIT = 3, REGISTER = 4, PUBLISH = 5, RESPONSE = 6;
    localparam [3:0] C_IDLE = 0, C_VALIDATE = 1, C_INPUT_START = 2,
        C_INPUT_WAIT = 3, C_GENERATED_SEND = 4, C_GENERATED_WAIT = 5,
        C_REGISTER = 6, C_RESPONSE = 7;
    reg [2:0] state;
    reg [3:0] callback_state;
    reg [1:0] model_hold, precision_hold, callback_model;
    reg stage_hold, callback_mask, callback_stage;
    reg [31:0] generation_hold, frames_hold, time_hold, frequency_hold;
    reg [31:0] callback_generation, callback_time, callback_frequency, callback_channel;
    reg [63:0] audio_hold, weights_hold;
    reg [31:0] callback_data;
    reg [3:0] callback_error, callback_failure, child_error_hold, error_hold;
    reg mask_hold;

    wire point_ready, point_valid, point_mask;
    wire [3:0] point_error;
    wire point_cmd_valid, point_result_ready;
    wire [63:0] point_addr;
    wire point_source_valid, point_source_rsp_ready, point_source_stage;
    wire [31:0] point_source_generation, point_source_time, point_source_frequency;
    wire [31:0] point_source_channel;
    wire [1:0] point_source_model;
    wire point_mask_valid, point_mask_rsp_ready;
    wire [31:0] point_mask_generation, point_mask_frame;
    wire [1:0] point_mask_model;
    wire point_selected = rst_n && (state == POINT_START || state == POINT_WAIT);
    wire input_selected = rst_n &&
        (callback_state == C_INPUT_START || callback_state == C_INPUT_WAIT);
    wire point_source_ready = rst_n && state == POINT_WAIT &&
        callback_state == C_IDLE && !point_mask_valid;
    wire point_mask_ready = rst_n && state == POINT_WAIT && callback_state == C_IDLE;
    wire callback_rsp = rst_n && state == POINT_WAIT && callback_state == C_RESPONSE;
    anvil_en1_audio_subsample_point point (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == POINT_START), .start_ready(point_ready),
        .model(model_hold), .precision(precision_hold), .stage(stage_hold),
        .generation(generation_hold), .frames(frames_hold),
        .output_time(time_hold), .output_frequency(frequency_hold),
        .audio_weights_base(weights_hold),
        .source_valid(point_source_valid), .source_ready(point_source_ready),
        .source_generation(point_source_generation), .source_time(point_source_time),
        .source_frequency(point_source_frequency), .source_channel(point_source_channel),
        .source_model(point_source_model), .source_stage(point_source_stage),
        .source_rsp_valid(callback_rsp && !callback_mask),
        .source_rsp_ready(point_source_rsp_ready),
        .source_rsp_data(callback_data[15:0]), .source_rsp_error(callback_error != 0),
        .mask_valid(point_mask_valid), .mask_ready(point_mask_ready),
        .mask_generation(point_mask_generation), .mask_frame(point_mask_frame),
        .mask_model(point_mask_model),
        .mask_rsp_valid(callback_rsp && callback_mask),
        .mask_rsp_ready(point_mask_rsp_ready), .mask_rsp_data(callback_data),
        .mask_rsp_error(callback_error != 0),
        .cmd_valid(point_cmd_valid),
        .cmd_ready(point_selected && !input_selected && cmd_ready),
        .cmd_write(), .cmd_addr(point_addr), .cmd_wdata(),
        .result_valid(point_selected && !input_selected && result_valid),
        .result_ready(point_result_ready), .result_data(result_data),
        .result_error(result_error),
        .output_valid(output_valid), .output_ready(point_selected && output_ready),
        .output_index(output_index), .output_data(output_data),
        .output_last(output_last), .output_mask(output_mask),
        .done_valid(point_valid),
        .done_ready(rst_n && state == POINT_WAIT && callback_state == C_IDLE),
        .done_mask(point_mask), .done_error(point_error),
        .weight_read_event(), .weight_read_bytes(),
        .projection_event(projection_event), .projection_bytes(projection_bytes),
        .source_read_event(), .source_read_bytes(), .mask_read_event(), .mask_read_bytes(),
        .vector_live_bytes(vector_live_bytes), .vector_physical_bytes(vector_physical_bytes),
        .controller_bytes(point_controller_bytes),
        .convolution_controller_bytes(convolution_controller_bytes),
        .divider_controller_bytes(divider_controller_bytes), .norm_controller_bytes(norm_controller_bytes)
    );
    wire input_ready, input_valid, input_cmd_valid, input_result_ready;
    wire [63:0] input_addr;
    wire [31:0] input_data;
    wire [3:0] input_error;
    anvil_en1_audio_input original_input (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && callback_state == C_INPUT_START), .start_ready(input_ready),
        .model(model_hold), .kind(callback_mask ? 2'd1 : 2'd0),
        .generation(generation_hold), .frames(frames_hold), .frame(callback_time),
        .frequency(callback_mask ? 32'd0 : callback_frequency), .audio_base(audio_hold),
        .cmd_valid(input_cmd_valid), .cmd_ready(input_selected && cmd_ready),
        .cmd_write(), .cmd_addr(input_addr), .cmd_wdata(),
        .result_valid(input_selected && result_valid), .result_ready(input_result_ready),
        .result_data(result_data), .result_error(result_error),
        .done_valid(input_valid), .done_ready(rst_n && callback_state == C_INPUT_WAIT),
        .done_data(input_data), .done_error(input_error),
        .input_read_event(input_read_event), .input_read_bytes(input_read_bytes),
        .controller_bytes(input_controller_bytes)
    );
    wire [31:0] half_frames = (frames_hold >> 1) + {31'd0, frames_hold[0]};
    wire callback_tag_good = callback_model == model_hold &&
        callback_generation == generation_hold;
    wire callback_source_good = callback_stage == stage_hold &&
        (callback_stage ? (callback_time < half_frames &&
            callback_frequency < 64 && callback_channel < 128) :
            (callback_time < frames_hold && callback_frequency < 128 && callback_channel == 0));
    assign start_ready = rst_n && state == IDLE;
    assign generated_valid = rst_n && callback_state == C_GENERATED_SEND;
    assign generated_generation = rst_n ? callback_generation : 32'd0;
    assign generated_model = rst_n ? callback_model : 2'd0;
    assign generated_time = rst_n ? callback_time : 32'd0;
    assign generated_frequency = rst_n ? callback_frequency : 32'd0;
    assign generated_channel = rst_n ? callback_channel : 32'd0;
    assign generated_rsp_ready = rst_n && callback_state == C_GENERATED_WAIT;
    assign cmd_valid = input_selected ? input_cmd_valid :
        (point_selected && point_cmd_valid);
    assign cmd_write = 0;
    assign cmd_addr = !rst_n ? 64'd0 : (input_selected ? input_addr :
        (point_selected ? point_addr : 64'd0));
    assign cmd_wdata = 0;
    assign result_ready = input_selected ? input_result_ready :
        (point_selected && point_result_ready);
    assign done_valid = rst_n && state == RESPONSE;
    assign done_mask = rst_n && state == RESPONSE && error_hold == 0 && mask_hold;
    assign done_error = rst_n ? error_hold : 4'd0;
    assign weight_read_event = !input_selected && point_selected && point_cmd_valid && cmd_ready;
    assign weight_read_bytes = weight_read_event ? 32'd4 : 32'd0;
    assign generated_read_event = generated_valid && generated_ready;
    assign generated_read_bytes = generated_read_event ? 32'd2 : 32'd0;
    localparam integer CONTROLLER_BITS =
        $bits(state) + $bits(callback_state) + $bits(model_hold) +
        $bits(precision_hold) + $bits(callback_model) + $bits(stage_hold) +
        $bits(callback_mask) + $bits(callback_stage) +
        $bits(generation_hold) + $bits(frames_hold) + $bits(time_hold) +
        $bits(frequency_hold) + $bits(callback_generation) + $bits(callback_time) +
        $bits(callback_frequency) + $bits(callback_channel) + $bits(audio_hold) +
        $bits(weights_hold) + $bits(callback_data) + $bits(callback_error) +
        $bits(callback_failure) + $bits(child_error_hold) + $bits(error_hold) + $bits(mask_hold);
    assign controller_bytes = rst_n ? (CONTROLLER_BITS + 7) >> 3 : 64'd0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            callback_state <= C_IDLE;
            callback_model <= 0;
            callback_mask <= 0;
            callback_stage <= 0;
            callback_generation <= 0;
            callback_time <= 0;
            callback_frequency <= 0;
            callback_channel <= 0;
            callback_data <= 0;
            callback_error <= 0;
            callback_failure <= 0;
        end else begin
            if (state == IDLE && start_valid && start_ready)
                callback_failure <= 0;
            case (callback_state)
                C_IDLE: begin
                    if (point_mask_valid && point_mask_ready) begin
                        callback_mask <= 1;
                        callback_model <= point_mask_model;
                        callback_generation <= point_mask_generation;
                        callback_time <= point_mask_frame;
                        callback_frequency <= 0;
                        callback_channel <= 0;
                        callback_data <= 0;
                        callback_error <= 0;
                        callback_state <= C_VALIDATE;
                    end else if (point_source_valid && point_source_ready) begin
                        callback_mask <= 0;
                        callback_stage <= point_source_stage;
                        callback_model <= point_source_model;
                        callback_generation <= point_source_generation;
                        callback_time <= point_source_time;
                        callback_frequency <= point_source_frequency;
                        callback_channel <= point_source_channel;
                        callback_data <= 0;
                        callback_error <= 0;
                        callback_state <= C_VALIDATE;
                    end
                end
                C_VALIDATE: begin
                    if (callback_failure != 0) begin
                        callback_error <= callback_failure;
                        callback_state <= C_REGISTER;
                    end else if (!callback_tag_good ||
                        (callback_mask ? callback_time >= frames_hold : !callback_source_good)) begin
                        callback_error <= 7;
                        callback_failure <= 7;
                        callback_state <= C_REGISTER;
                    end else if (callback_mask || !callback_stage)
                        callback_state <= C_INPUT_START;
                    else
                        callback_state <= C_GENERATED_SEND;
                end
                C_INPUT_START: if (input_ready)
                    callback_state <= C_INPUT_WAIT;
                C_INPUT_WAIT: if (input_valid) begin
                    callback_data <= input_data;
                    callback_error <= input_error;
                    if (input_error != 0 && callback_failure == 0)
                        callback_failure <= input_error;
                    callback_state <= C_REGISTER;
                end
                C_GENERATED_SEND: if (generated_ready)
                    callback_state <= C_GENERATED_WAIT;
                C_GENERATED_WAIT: if (generated_rsp_valid) begin
                    callback_data <= {16'd0, generated_rsp_data};
                    callback_error <= generated_rsp_error ? 4'd7 : 4'd0;
                    if (generated_rsp_error && callback_failure == 0)
                        callback_failure <= 7;
                    callback_state <= C_REGISTER;
                end
                C_REGISTER: callback_state <= C_RESPONSE;
                C_RESPONSE: if (callback_mask ? point_mask_rsp_ready : point_source_rsp_ready)
                    callback_state <= C_IDLE;
                default: begin
                    callback_error <= 7;
                    if (callback_failure == 0)
                        callback_failure <= 7;
                    callback_state <= C_REGISTER;
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
            audio_hold <= 0;
            weights_hold <= 0;
            child_error_hold <= 0;
            error_hold <= 0;
            mask_hold <= 0;
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
                    audio_hold <= audio_base;
                    weights_hold <= audio_weights_base;
                    child_error_hold <= 0;
                    error_hold <= 0;
                    mask_hold <= 0;
                    state <= VALIDATE;
                end
                VALIDATE: begin
                    if ((model_hold != 1 && model_hold != 2) || precision_hold > 1) begin
                        error_hold <= 6;
                        state <= PUBLISH;
                    end else if (generation_hold == 0 || frames_hold == 0 ||
                        frames_hold > 131072 || audio_hold[1:0] != 0 || weights_hold[1:0] != 0) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else
                        state <= POINT_START;
                end
                POINT_START: if (point_ready)
                    state <= POINT_WAIT;
                POINT_WAIT: if (point_valid && callback_state == C_IDLE) begin
                    child_error_hold <= point_error;
                    mask_hold <= point_mask;
                    state <= REGISTER;
                end
                REGISTER: begin
                    error_hold <= callback_failure != 0 ? callback_failure : child_error_hold;
                    state <= PUBLISH;
                end
                PUBLISH: state <= RESPONSE;
                RESPONSE: if (done_ready)
                    state <= IDLE;
                default: begin
                    error_hold <= 7;
                    state <= PUBLISH;
                end
            endcase
        end
    end
endmodule
