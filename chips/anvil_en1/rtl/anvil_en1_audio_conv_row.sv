module anvil_en1_audio_conv_row (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] model, precision,
    input wire stage,
    input wire [31:0] generation, frames, output_time, output_frequency, output_channel,
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
    output wire done_valid,
    input wire done_ready,
    output wire [31:0] done_data,
    output wire [3:0] done_error,
    output wire weight_read_event,
    output wire [31:0] weight_read_bytes,
    output wire projection_event,
    output wire [31:0] projection_bytes,
    output wire source_read_event, mask_read_event,
    output wire [31:0] source_read_bytes, mask_read_bytes,
    output wire [63:0] controller_bytes, divider_controller_bytes
);
    localparam [3:0] IDLE = 0, VALIDATE = 1, SHAPE = 2, SHAPE_VALIDATE = 3,
        IMAGE_START = 4, IMAGE_WAIT = 5, PROJECTION_START = 6,
        PROJECTION_WAIT = 7, REGISTER = 8, PUBLISH = 9, RESPONSE = 10;
    localparam [4:0] S_IDLE = 0, S_VALIDATE = 1, S_CHANNEL_SETUP = 2,
        S_CHANNEL_RESULT = 3, S_KERNEL_RESULT = 4, S_ORIGIN = 5,
        S_SUM = 6, S_BOUNDS = 7, S_COORDINATE = 8, S_MASK_FRAME = 9,
        S_MASK_SEND = 10, S_MASK_WAIT = 11, S_MASK_REGISTER = 12,
        S_SOURCE_SEND = 13, S_SOURCE_WAIT = 14, S_SOURCE_REGISTER = 15,
        S_WIDEN = 16, S_MULTIPLY = 17, S_NARROW = 18,
        S_OUTPUT = 19, S_RESPONSE = 20,
        S_UINT_START = 21, S_UINT_WAIT = 22, S_FP_START = 23, S_FP_WAIT = 24;
    reg [3:0] state;
    reg [4:0] source_state, uint_return, fp_return;
    reg [1:0] model_hold, precision_hold;
    reg stage_hold;
    reg [31:0] generation_hold, frames_hold, time_hold, frequency_hold, channel_hold;
    reg [31:0] half_frames, input_times, output_times, input_frequencies, output_frequencies;
    reg [31:0] input_channels, output_channels, matrix_columns, matrix_stride;
    reg [63:0] weights_hold, matrix_base, matrix_bytes;
    reg [31:0] source_column, source_channel_hold, kernel_y, kernel_x;
    reg [31:0] time_origin, frequency_origin, time_sum, frequency_sum;
    reg [31:0] source_time_hold, source_frequency_hold, mask_frame_hold;
    reg [31:0] mask_word;
    reg mask_error_hold, mask_hold, source_error_hold;
    reg [15:0] source_data_hold, source_output_hold;
    reg [31:0] uint_a, uint_b, uint_value, uint_remainder;
    reg [31:0] fp_a, fp_b, fp_value, output_hold, projection_hold;
    reg [2:0] fp_op;
    reg [3:0] source_failure_hold, child_error_hold, error_hold;

    wire lookup_ready, lookup_valid, lookup_cmd_valid, lookup_result_ready;
    wire [63:0] lookup_addr, lookup_base, lookup_bytes;
    wire [31:0] lookup_rows, lookup_columns, lookup_stride;
    wire [7:0] lookup_type;
    wire [3:0] lookup_error;
    wire lookup_selected = rst_n && (state == IMAGE_START || state == IMAGE_WAIT);
    wire [63:0] primitive_directory_bytes, primitive_projection_bytes, primitive_fp_bytes;
    anvil_en1_tensor_image directory (
        .controller_bytes(primitive_directory_bytes),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == IMAGE_START), .start_ready(lookup_ready),
        .model(model_hold), .precision(precision_hold), .image_class(2'd2),
        .input_audio(1'b0), .input_items(32'd0), .image_base(weights_hold),
        .tensor_kind(stage_hold ? 16'h2002 : 16'h2000), .tensor_layer(16'hffff),
        .cmd_valid(lookup_cmd_valid), .cmd_ready(lookup_selected && cmd_ready),
        .cmd_write(), .cmd_addr(lookup_addr), .cmd_wdata(),
        .result_valid(lookup_selected && result_valid), .result_ready(lookup_result_ready),
        .result_data(result_data), .result_error(result_error),
        .done_valid(lookup_valid), .done_ready(rst_n && state == IMAGE_WAIT),
        .done_base(lookup_base), .done_bytes(lookup_bytes), .done_rows(lookup_rows),
        .done_columns(lookup_columns), .done_stride(lookup_stride),
        .done_type(lookup_type), .done_error(lookup_error)
    );
    wire projection_ready, projection_valid, projection_source_valid, projection_source_rsp_ready;
    wire projection_cmd_valid, projection_result_ready;
    wire [31:0] projection_source_index, projection_data;
    wire [63:0] projection_addr;
    wire [3:0] projection_error;
    wire projection_selected = rst_n &&
        (state == PROJECTION_START || state == PROJECTION_WAIT);
    anvil_en1_projection convolution (
        .controller_bytes(primitive_projection_bytes),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == PROJECTION_START), .start_ready(projection_ready),
        .precision(precision_hold), .tensor_base(matrix_base), .tensor_bytes(matrix_bytes),
        .tensor_rows(output_channels), .tensor_columns(matrix_columns),
        .row_stride(matrix_stride), .row_index(channel_hold),
        .source_valid(projection_source_valid),
        .source_ready(rst_n && state == PROJECTION_WAIT && source_state == S_IDLE),
        .source_index(projection_source_index),
        .source_rsp_valid(rst_n && source_state == S_RESPONSE),
        .source_rsp_ready(projection_source_rsp_ready),
        .source_rsp_data(source_output_hold), .source_rsp_error(source_failure_hold != 0),
        .cmd_valid(projection_cmd_valid), .cmd_ready(projection_selected && cmd_ready),
        .cmd_write(), .cmd_addr(projection_addr), .cmd_wdata(),
        .result_valid(projection_selected && result_valid),
        .result_ready(projection_result_ready), .result_data(result_data),
        .result_error(result_error),
        .done_valid(projection_valid),
        .done_ready(rst_n && state == PROJECTION_WAIT && source_state == S_IDLE),
        .done_data(projection_data), .done_error(projection_error)
    );
    wire uint_ready, uint_valid;
    wire [31:0] uint_quotient, uint_remainder_result;
    wire [3:0] uint_error;
    anvil_en1_uint_div coordinate_divider (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && source_state == S_UINT_START), .start_ready(uint_ready),
        .numerator(uint_a), .denominator(uint_b),
        .done_valid(uint_valid), .done_ready(rst_n && source_state == S_UINT_WAIT),
        .quotient(uint_quotient), .remainder(uint_remainder_result),
        .done_error(uint_error), .controller_bytes(divider_controller_bytes)
    );
    wire fp_ready, fp_valid;
    wire [31:0] fp_data;
    wire [3:0] fp_error;
    anvil_en1_fp32 source_arithmetic (
        .controller_bytes(primitive_fp_bytes),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && source_state == S_FP_START), .start_ready(fp_ready),
        .operation(fp_op), .operand_a(fp_a), .operand_b(fp_b),
        .done_valid(fp_valid), .done_ready(rst_n && source_state == S_FP_WAIT),
        .done_data(fp_data), .done_error(fp_error)
    );
    assign start_ready = rst_n && state == IDLE;
    assign cmd_valid = lookup_selected ? lookup_cmd_valid :
        (projection_selected && projection_cmd_valid);
    assign cmd_write = 0;
    assign cmd_addr = !rst_n ? 64'd0 : (lookup_selected ? lookup_addr :
        (projection_selected ? projection_addr : 64'd0));
    assign cmd_wdata = 0;
    assign result_ready = lookup_selected ? lookup_result_ready :
        (projection_selected && projection_result_ready);
    assign source_valid = rst_n && source_state == S_SOURCE_SEND;
    assign source_generation = rst_n ? generation_hold : 32'd0;
    assign source_model = rst_n ? model_hold : 2'd0;
    assign source_stage = rst_n && stage_hold;
    assign source_time = rst_n ? source_time_hold : 32'd0;
    assign source_frequency = rst_n ? source_frequency_hold : 32'd0;
    assign source_channel = rst_n ? source_channel_hold : 32'd0;
    assign source_rsp_ready = rst_n && source_state == S_SOURCE_WAIT;
    assign mask_valid = rst_n && source_state == S_MASK_SEND;
    assign mask_generation = rst_n ? generation_hold : 32'd0;
    assign mask_model = rst_n ? model_hold : 2'd0;
    assign mask_frame = rst_n ? mask_frame_hold : 32'd0;
    assign mask_rsp_ready = rst_n && source_state == S_MASK_WAIT;
    assign done_valid = rst_n && state == RESPONSE;
    assign done_data = rst_n ? output_hold : 32'd0;
    assign done_error = rst_n ? error_hold : 4'd0;
    assign weight_read_event = cmd_valid && cmd_ready;
    assign weight_read_bytes = weight_read_event ? 32'd4 : 32'd0;
    assign projection_event = rst_n && state == PROJECTION_START && projection_ready;
    assign projection_bytes = projection_event ? matrix_stride : 32'd0;
    assign source_read_event = source_valid && source_ready;
    assign source_read_bytes = source_read_event ? 32'd2 : 32'd0;
    assign mask_read_event = mask_valid && mask_ready;
    assign mask_read_bytes = mask_read_event ? 32'd4 : 32'd0;
    wire [31:0] CONTROLLER_BITS =
        $bits(state) + $bits(source_state) + $bits(uint_return) + $bits(fp_return) +
        $bits(model_hold) + $bits(precision_hold) + $bits(stage_hold) +
        $bits(generation_hold) + $bits(frames_hold) + $bits(time_hold) +
        $bits(frequency_hold) + $bits(channel_hold) + $bits(half_frames) +
        $bits(input_times) + $bits(output_times) + $bits(input_frequencies) +
        $bits(output_frequencies) + $bits(input_channels) + $bits(output_channels) +
        $bits(matrix_columns) + $bits(matrix_stride) + $bits(weights_hold) +
        $bits(matrix_base) + $bits(matrix_bytes) + $bits(source_column) +
        $bits(source_channel_hold) + $bits(kernel_y) +
        $bits(kernel_x) + $bits(time_origin) + $bits(frequency_origin) +
        $bits(time_sum) + $bits(frequency_sum) + $bits(source_time_hold) +
        $bits(source_frequency_hold) + $bits(mask_frame_hold) + $bits(mask_word) +
        $bits(mask_error_hold) + $bits(mask_hold) + $bits(source_error_hold) +
        $bits(source_data_hold) + $bits(source_output_hold) + $bits(uint_a) +
        $bits(uint_b) + $bits(uint_value) + $bits(uint_remainder) +
        $bits(fp_a) + $bits(fp_b) + $bits(fp_value) + $bits(output_hold) +
        $bits(projection_hold) + $bits(fp_op) + $bits(source_failure_hold) +
        $bits(child_error_hold) + $bits(error_hold);
    assign controller_bytes = !rst_n ? 64'd0 : 64'((CONTROLLER_BITS + 7) >> 3) +
        primitive_directory_bytes + primitive_projection_bytes + primitive_fp_bytes;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            source_state <= S_IDLE;
            uint_return <= 0;
            fp_return <= 0;
            source_column <= 0;
            source_channel_hold <= 0;
            kernel_y <= 0;
            kernel_x <= 0;
            time_origin <= 0;
            frequency_origin <= 0;
            time_sum <= 0;
            frequency_sum <= 0;
            source_time_hold <= 0;
            source_frequency_hold <= 0;
            mask_frame_hold <= 0;
            mask_word <= 0;
            mask_error_hold <= 0;
            mask_hold <= 0;
            source_error_hold <= 0;
            source_data_hold <= 0;
            source_output_hold <= 0;
            uint_a <= 0;
            uint_b <= 0;
            uint_value <= 0;
            uint_remainder <= 0;
            fp_a <= 0;
            fp_b <= 0;
            fp_value <= 0;
            fp_op <= 0;
            source_failure_hold <= 0;
        end else begin
            if (state == IDLE && start_valid && start_ready)
                source_failure_hold <= 0;
            case (source_state)
                S_IDLE: if (state == PROJECTION_WAIT && projection_source_valid) begin
                    source_column <= projection_source_index;
                    source_output_hold <= 0;
                    source_state <= S_VALIDATE;
                end
                S_VALIDATE: begin
                    if (source_column >= matrix_columns) begin
                        source_failure_hold <= 5;
                        source_state <= S_RESPONSE;
                    end else
                        source_state <= S_CHANNEL_SETUP;
                end
                S_CHANNEL_SETUP: begin
                    uint_a <= source_column;
                    uint_b <= 9;
                    uint_return <= S_CHANNEL_RESULT;
                    source_state <= S_UINT_START;
                end
                S_CHANNEL_RESULT: begin
                    if (uint_value >= input_channels) begin
                        source_failure_hold <= 5;
                        source_state <= S_RESPONSE;
                    end else begin
                        source_channel_hold <= uint_value;
                        uint_a <= uint_remainder;
                        uint_b <= 3;
                        uint_return <= S_KERNEL_RESULT;
                        source_state <= S_UINT_START;
                    end
                end
                S_KERNEL_RESULT: begin
                    kernel_y <= uint_value;
                    kernel_x <= uint_remainder;
                    source_state <= S_ORIGIN;
                end
                S_ORIGIN: begin
                    time_origin <= time_hold << 1;
                    frequency_origin <= frequency_hold << 1;
                    source_state <= S_SUM;
                end
                S_SUM: begin
                    time_sum <= time_origin + kernel_y;
                    frequency_sum <= frequency_origin + kernel_x;
                    source_state <= S_BOUNDS;
                end
                S_BOUNDS: begin
                    if (time_sum == 0 || frequency_sum == 0 ||
                        time_sum > input_times || frequency_sum > input_frequencies) begin
                        source_output_hold <= 0;
                        source_state <= S_RESPONSE;
                    end else
                        source_state <= S_COORDINATE;
                end
                S_COORDINATE: begin
                    source_time_hold <= time_sum - 1'b1;
                    source_frequency_hold <= frequency_sum - 1'b1;
                    source_state <= S_MASK_FRAME;
                end
                S_MASK_FRAME: begin
                    mask_frame_hold <= stage_hold ? source_time_hold << 1 : source_time_hold;
                    source_state <= S_MASK_SEND;
                end
                S_MASK_SEND: if (mask_ready)
                    source_state <= S_MASK_WAIT;
                S_MASK_WAIT: if (mask_rsp_valid) begin
                    mask_word <= mask_rsp_data;
                    mask_error_hold <= mask_rsp_error;
                    source_state <= S_MASK_REGISTER;
                end
                S_MASK_REGISTER: begin
                    if (mask_error_hold) begin
                        source_failure_hold <= 7;
                        source_state <= S_RESPONSE;
                    end else if (mask_word > 1) begin
                        source_failure_hold <= 5;
                        source_state <= S_RESPONSE;
                    end else begin
                        mask_hold <= mask_word[0];
                        source_state <= S_SOURCE_SEND;
                    end
                end
                S_SOURCE_SEND: if (source_ready)
                    source_state <= S_SOURCE_WAIT;
                S_SOURCE_WAIT: if (source_rsp_valid) begin
                    source_data_hold <= source_rsp_data;
                    source_error_hold <= source_rsp_error;
                    source_state <= S_SOURCE_REGISTER;
                end
                S_SOURCE_REGISTER: begin
                    if (source_error_hold) begin
                        source_failure_hold <= 7;
                        source_state <= S_RESPONSE;
                    end else
                        source_state <= S_WIDEN;
                end
                S_WIDEN: begin
                    fp_a <= {16'd0, source_data_hold};
                    fp_b <= 0;
                    fp_op <= 2;
                    fp_return <= S_MULTIPLY;
                    source_state <= S_FP_START;
                end
                S_MULTIPLY: begin
                    fp_a <= fp_value;
                    fp_b <= mask_hold ? 32'h3f800000 : 32'd0;
                    fp_op <= 1;
                    fp_return <= S_NARROW;
                    source_state <= S_FP_START;
                end
                S_NARROW: begin
                    fp_a <= fp_value;
                    fp_b <= 0;
                    fp_op <= 3;
                    fp_return <= S_OUTPUT;
                    source_state <= S_FP_START;
                end
                S_OUTPUT: begin
                    source_output_hold <= fp_value[15:0];
                    source_state <= S_RESPONSE;
                end
                S_RESPONSE: if (projection_source_rsp_ready)
                    source_state <= S_IDLE;
                S_UINT_START: if (uint_ready)
                    source_state <= S_UINT_WAIT;
                S_UINT_WAIT: if (uint_valid) begin
                    if (uint_error != 0) begin
                        source_failure_hold <= uint_error;
                        source_state <= S_RESPONSE;
                    end else begin
                        uint_value <= uint_quotient;
                        uint_remainder <= uint_remainder_result;
                        source_state <= uint_return;
                    end
                end
                S_FP_START: if (fp_ready)
                    source_state <= S_FP_WAIT;
                S_FP_WAIT: if (fp_valid) begin
                    if (fp_error != 0) begin
                        source_failure_hold <= fp_error;
                        source_state <= S_RESPONSE;
                    end else begin
                        fp_value <= fp_data;
                        source_state <= fp_return;
                    end
                end
                default: begin
                    source_failure_hold <= 7;
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
            stage_hold <= 0;
            generation_hold <= 0;
            frames_hold <= 0;
            time_hold <= 0;
            frequency_hold <= 0;
            channel_hold <= 0;
            half_frames <= 0;
            input_times <= 0;
            output_times <= 0;
            input_frequencies <= 0;
            output_frequencies <= 0;
            input_channels <= 0;
            output_channels <= 0;
            matrix_columns <= 0;
            matrix_stride <= 0;
            weights_hold <= 0;
            matrix_base <= 0;
            matrix_bytes <= 0;
            output_hold <= 0;
            projection_hold <= 0;
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
                    channel_hold <= output_channel;
                    weights_hold <= audio_weights_base;
                    output_hold <= 0;
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
                    input_times <= stage_hold ? half_frames : frames_hold;
                    output_times <= stage_hold ?
                        (half_frames >> 1) + {31'd0, half_frames[0]} : half_frames;
                    input_frequencies <= stage_hold ? 32'd64 : 32'd128;
                    output_frequencies <= stage_hold ? 32'd32 : 32'd64;
                    input_channels <= stage_hold ? 32'd128 : 32'd1;
                    output_channels <= stage_hold ? 32'd32 : 32'd128;
                    matrix_columns <= stage_hold ? 32'd1152 : 32'd9;
                    state <= SHAPE_VALIDATE;
                end
                SHAPE_VALIDATE: begin
                    if (time_hold >= output_times || frequency_hold >= output_frequencies ||
                        channel_hold >= output_channels) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else
                        state <= IMAGE_START;
                end
                IMAGE_START: if (lookup_ready)
                    state <= IMAGE_WAIT;
                IMAGE_WAIT: if (lookup_valid) begin
                    if (lookup_error != 0) begin
                        error_hold <= lookup_error;
                        state <= PUBLISH;
                    end else if (lookup_rows != output_channels ||
                        lookup_columns != matrix_columns ||
                        lookup_type != {6'd0, precision_hold}) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else begin
                        matrix_base <= lookup_base;
                        matrix_bytes <= lookup_bytes;
                        matrix_stride <= lookup_stride;
                        state <= PROJECTION_START;
                    end
                end
                PROJECTION_START: if (projection_ready)
                    state <= PROJECTION_WAIT;
                PROJECTION_WAIT: if (projection_valid && source_state == S_IDLE) begin
                    projection_hold <= projection_data;
                    child_error_hold <= projection_error;
                    state <= REGISTER;
                end
                REGISTER: begin
                    if (source_failure_hold != 0)
                        error_hold <= source_failure_hold;
                    else
                        error_hold <= child_error_hold;
                    if (source_failure_hold == 0 && child_error_hold == 0)
                        output_hold <= projection_hold;
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
