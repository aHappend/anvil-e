module anvil_en1_audio_subsample (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] model, precision,
    input wire [31:0] generation, frames, token,
    input wire [63:0] audio_base, audio_weights_base,
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
    output wire point_replay_event,
    output wire [31:0] point_replay_bytes,
    output wire [63:0] vector_live_bytes, vector_physical_bytes,
    output wire [63:0] controller_bytes, nested_controller_bytes
);
    localparam [3:0] IDLE = 0, VALIDATE = 1, SHAPE = 2,
        SHAPE_VALIDATE = 3, IMAGE_START = 4, IMAGE_WAIT = 5,
        PROJECTION_START = 6, PROJECTION_WAIT = 7, PROJECTION_REGISTER = 8,
        EMIT = 9, ADVANCE = 10, PUBLISH = 11, RESPONSE = 12;
    localparam [2:0] S_IDLE = 0, S_VALIDATE = 1, S_START = 2,
        S_WAIT = 3, S_CHECK = 4, S_RESPONSE = 5;
    localparam [2:0] D_IDLE = 0, D_VALIDATE = 1, D_START = 2,
        D_WAIT = 3, D_CHECK = 4, D_RESPONSE = 5;
    reg [3:0] state;
    reg [2:0] source_state, dependency_state;
    reg [1:0] model_hold, precision_hold, dependency_model;
    reg [31:0] generation_hold, frames_hold, token_hold, half_frames, output_times;
    reg [63:0] audio_hold, weights_hold, matrix_base, matrix_bytes;
    reg [31:0] matrix_stride, row, projection_hold;
    reg [15:0] output_hold;
    reg [3:0] projection_error_hold, error_hold;
    reg [31:0] source_column, source_received;
    reg [15:0] source_data_hold;
    reg source_found, source_bad, source_mask_hold, mask_seen, mask_hold;
    reg [3:0] source_error_hold, source_child_error, source_failure;
    reg [31:0] dependency_generation, dependency_time, dependency_frequency, dependency_channel;
    reg [31:0] dependency_received;
    reg [15:0] dependency_data_hold;
    reg dependency_found, dependency_bad;
    reg [3:0] dependency_error_hold, dependency_child_error, dependency_failure;

    wire lookup_ready, lookup_valid, lookup_cmd_valid, lookup_result_ready;
    wire [63:0] lookup_addr, lookup_base, lookup_bytes;
    wire [31:0] lookup_rows, lookup_columns, lookup_stride;
    wire [7:0] lookup_type;
    wire [3:0] lookup_error;
    wire lookup_selected = rst_n && (state == IMAGE_START || state == IMAGE_WAIT);
    anvil_en1_tensor_image directory (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == IMAGE_START), .start_ready(lookup_ready),
        .model(model_hold), .precision(precision_hold), .image_class(2'd2),
        .input_audio(1'b0), .input_items(32'd0), .image_base(weights_hold),
        .tensor_kind(16'h2004), .tensor_layer(16'hffff),
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
    wire [63:0] projection_addr;
    wire [31:0] projection_data, projection_source_index;
    wire [3:0] projection_error;
    wire projection_selected = rst_n &&
        (state == PROJECTION_START || state == PROJECTION_WAIT);
    wire projection_memory = projection_selected && source_state == S_IDLE;
    anvil_en1_projection input_projection (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == PROJECTION_START), .start_ready(projection_ready),
        .precision(precision_hold), .tensor_base(matrix_base), .tensor_bytes(matrix_bytes),
        .tensor_rows(32'd1024), .tensor_columns(32'd1024), .row_stride(matrix_stride),
        .row_index(row), .source_valid(projection_source_valid),
        .source_ready(rst_n && state == PROJECTION_WAIT && source_state == S_IDLE),
        .source_index(projection_source_index),
        .source_rsp_valid(rst_n && source_state == S_RESPONSE),
        .source_rsp_ready(projection_source_rsp_ready),
        .source_rsp_data(source_data_hold), .source_rsp_error(source_error_hold != 0),
        .cmd_valid(projection_cmd_valid), .cmd_ready(projection_memory && cmd_ready),
        .cmd_write(), .cmd_addr(projection_addr), .cmd_wdata(),
        .result_valid(projection_memory && result_valid),
        .result_ready(projection_result_ready), .result_data(result_data),
        .result_error(result_error),
        .done_valid(projection_valid),
        .done_ready(rst_n && state == PROJECTION_WAIT && source_state == S_IDLE),
        .done_data(projection_data), .done_error(projection_error)
    );
    wire upper_ready, upper_valid, upper_mask;
    wire upper_cmd_valid, upper_result_ready, upper_output_valid, upper_output_last;
    wire [63:0] upper_addr, upper_live, upper_physical;
    wire [31:0] upper_output_index;
    wire [15:0] upper_output_data;
    wire [3:0] upper_error;
    wire dependency_valid, dependency_rsp_ready;
    wire [31:0] dependency_req_generation, dependency_req_time;
    wire [31:0] dependency_req_frequency, dependency_req_channel;
    wire [1:0] dependency_req_model;
    wire upper_input_event, upper_weight_event, upper_projection_event;
    wire [31:0] upper_input_bytes, upper_weight_bytes, upper_projection_bytes;
    wire [63:0] upper_controller, upper_input_controller, upper_point_controller;
    wire [63:0] upper_conv_controller, upper_div_controller, upper_norm_controller;
    wire upper_selected = rst_n && (source_state == S_START || source_state == S_WAIT);
    wire lower_selected = rst_n &&
        (dependency_state == D_START || dependency_state == D_WAIT);
    anvil_en1_audio_subsample_execute stage_one (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && source_state == S_START), .start_ready(upper_ready),
        .model(model_hold), .precision(precision_hold), .stage(1'b1),
        .generation(generation_hold), .frames(frames_hold), .output_time(token_hold),
        .output_frequency({27'd0, source_column[9:5]}),
        .audio_base(audio_hold), .audio_weights_base(weights_hold),
        .generated_valid(dependency_valid),
        .generated_ready(rst_n && source_state == S_WAIT && dependency_state == D_IDLE),
        .generated_generation(dependency_req_generation), .generated_time(dependency_req_time),
        .generated_frequency(dependency_req_frequency), .generated_channel(dependency_req_channel),
        .generated_model(dependency_req_model),
        .generated_rsp_valid(rst_n && dependency_state == D_RESPONSE),
        .generated_rsp_ready(dependency_rsp_ready), .generated_rsp_data(dependency_data_hold),
        .generated_rsp_error(dependency_error_hold != 0),
        .cmd_valid(upper_cmd_valid), .cmd_ready(upper_selected && !lower_selected && cmd_ready),
        .cmd_write(), .cmd_addr(upper_addr), .cmd_wdata(),
        .result_valid(upper_selected && !lower_selected && result_valid),
        .result_ready(upper_result_ready), .result_data(result_data), .result_error(result_error),
        .output_valid(upper_output_valid), .output_ready(rst_n && source_state == S_WAIT),
        .output_index(upper_output_index), .output_data(upper_output_data),
        .output_last(upper_output_last), .output_mask(),
        .done_valid(upper_valid),
        .done_ready(rst_n && source_state == S_WAIT && dependency_state == D_IDLE),
        .done_mask(upper_mask), .done_error(upper_error),
        .input_read_event(upper_input_event), .weight_read_event(upper_weight_event),
        .input_read_bytes(upper_input_bytes), .weight_read_bytes(upper_weight_bytes),
        .projection_event(upper_projection_event), .projection_bytes(upper_projection_bytes),
        .generated_read_event(), .generated_read_bytes(),
        .vector_live_bytes(upper_live), .vector_physical_bytes(upper_physical),
        .controller_bytes(upper_controller), .input_controller_bytes(upper_input_controller),
        .point_controller_bytes(upper_point_controller), .convolution_controller_bytes(upper_conv_controller),
        .divider_controller_bytes(upper_div_controller), .norm_controller_bytes(upper_norm_controller)
    );
    wire lower_ready, lower_valid, lower_cmd_valid, lower_result_ready;
    wire lower_output_valid, lower_output_last;
    wire [63:0] lower_addr, lower_live, lower_physical;
    wire [31:0] lower_output_index;
    wire [15:0] lower_output_data;
    wire [3:0] lower_error;
    wire lower_input_event, lower_weight_event, lower_projection_event;
    wire [31:0] lower_input_bytes, lower_weight_bytes, lower_projection_bytes;
    wire [63:0] lower_controller, lower_input_controller, lower_point_controller;
    wire [63:0] lower_conv_controller, lower_div_controller, lower_norm_controller;
    anvil_en1_audio_subsample_execute stage_zero (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && dependency_state == D_START), .start_ready(lower_ready),
        .model(model_hold), .precision(precision_hold), .stage(1'b0),
        .generation(generation_hold), .frames(frames_hold),
        .output_time(dependency_time), .output_frequency(dependency_frequency),
        .audio_base(audio_hold), .audio_weights_base(weights_hold),
        .generated_valid(), .generated_ready(1'b0),
        .generated_generation(), .generated_time(), .generated_frequency(), .generated_channel(),
        .generated_model(), .generated_rsp_valid(1'b0), .generated_rsp_ready(),
        .generated_rsp_data(16'd0), .generated_rsp_error(1'b0),
        .cmd_valid(lower_cmd_valid), .cmd_ready(lower_selected && cmd_ready),
        .cmd_write(), .cmd_addr(lower_addr), .cmd_wdata(),
        .result_valid(lower_selected && result_valid), .result_ready(lower_result_ready),
        .result_data(result_data), .result_error(result_error),
        .output_valid(lower_output_valid),
        .output_ready(rst_n && dependency_state == D_WAIT),
        .output_index(lower_output_index), .output_data(lower_output_data),
        .output_last(lower_output_last), .output_mask(),
        .done_valid(lower_valid), .done_ready(rst_n && dependency_state == D_WAIT),
        .done_mask(), .done_error(lower_error),
        .input_read_event(lower_input_event), .weight_read_event(lower_weight_event),
        .input_read_bytes(lower_input_bytes), .weight_read_bytes(lower_weight_bytes),
        .projection_event(lower_projection_event), .projection_bytes(lower_projection_bytes),
        .generated_read_event(), .generated_read_bytes(),
        .vector_live_bytes(lower_live), .vector_physical_bytes(lower_physical),
        .controller_bytes(lower_controller), .input_controller_bytes(lower_input_controller),
        .point_controller_bytes(lower_point_controller), .convolution_controller_bytes(lower_conv_controller),
        .divider_controller_bytes(lower_div_controller), .norm_controller_bytes(lower_norm_controller)
    );
    wire upper_beat_good = source_received < 32 && upper_output_index == source_received &&
        upper_output_last == (source_received == 31);
    wire lower_beat_good = dependency_received < 128 &&
        lower_output_index == dependency_received &&
        lower_output_last == (dependency_received == 127);
    wire dependency_tag_good = dependency_model == model_hold &&
        dependency_generation == generation_hold && dependency_time < half_frames &&
        dependency_frequency < 64 && dependency_channel < 128;
    wire outer_weight_event = cmd_ready &&
        ((lookup_selected && lookup_cmd_valid) ||
         (projection_memory && projection_cmd_valid));
    wire outer_projection_event = rst_n && state == PROJECTION_START && projection_ready;
    assign start_ready = rst_n && state == IDLE;
    assign cmd_valid = !rst_n ? 1'b0 :
        (lower_selected ? lower_cmd_valid : (upper_selected ? upper_cmd_valid :
        (lookup_selected ? lookup_cmd_valid : (projection_memory && projection_cmd_valid))));
    assign cmd_write = 0;
    assign cmd_addr = !rst_n ? 64'd0 :
        (lower_selected ? lower_addr : (upper_selected ? upper_addr :
        (lookup_selected ? lookup_addr : (projection_memory ? projection_addr : 64'd0))));
    assign cmd_wdata = 0;
    assign result_ready = !rst_n ? 1'b0 :
        (lower_selected ? lower_result_ready : (upper_selected ? upper_result_ready :
        (lookup_selected ? lookup_result_ready : (projection_memory && projection_result_ready))));
    assign output_valid = rst_n && state == EMIT;
    assign output_index = rst_n ? row : 32'd0;
    assign output_data = rst_n ? output_hold : 16'd0;
    assign output_last = rst_n && state == EMIT && row == 1023;
    assign output_mask = rst_n && mask_seen && mask_hold;
    assign done_valid = rst_n && state == RESPONSE;
    assign done_mask = rst_n && state == RESPONSE && error_hold == 0 && mask_seen && mask_hold;
    assign done_error = rst_n ? error_hold : 4'd0;
    assign input_read_event = upper_input_event || lower_input_event;
    assign input_read_bytes = upper_input_bytes + lower_input_bytes;
    assign weight_read_event = outer_weight_event || upper_weight_event || lower_weight_event;
    assign weight_read_bytes = (outer_weight_event ? 32'd4 : 32'd0) +
        upper_weight_bytes + lower_weight_bytes;
    assign projection_event = outer_projection_event || upper_projection_event || lower_projection_event;
    assign projection_bytes = (outer_projection_event ? matrix_stride : 32'd0) +
        upper_projection_bytes + lower_projection_bytes;
    assign point_replay_event = rst_n && dependency_state == D_START && lower_ready;
    assign point_replay_bytes = point_replay_event ? 32'd256 : 32'd0;
    assign vector_live_bytes = rst_n ? upper_live + lower_live : 64'd0;
    assign vector_physical_bytes = rst_n ? upper_physical + lower_physical : 64'd0;
    assign nested_controller_bytes = rst_n ?
        upper_controller + upper_input_controller + upper_point_controller +
        upper_conv_controller + upper_div_controller + upper_norm_controller +
        lower_controller + lower_input_controller + lower_point_controller +
        lower_conv_controller + lower_div_controller + lower_norm_controller : 64'd0;
    localparam integer CONTROLLER_BITS =
        $bits(state) + $bits(source_state) + $bits(dependency_state) +
        $bits(model_hold) + $bits(precision_hold) + $bits(dependency_model) +
        $bits(generation_hold) + $bits(frames_hold) + $bits(token_hold) +
        $bits(half_frames) + $bits(output_times) + $bits(audio_hold) +
        $bits(weights_hold) + $bits(matrix_base) + $bits(matrix_bytes) +
        $bits(matrix_stride) + $bits(row) + $bits(projection_hold) +
        $bits(output_hold) + $bits(projection_error_hold) + $bits(error_hold) +
        $bits(source_column) + $bits(source_received) + $bits(source_data_hold) +
        $bits(source_found) + $bits(source_bad) + $bits(source_mask_hold) +
        $bits(mask_seen) + $bits(mask_hold) + $bits(source_error_hold) +
        $bits(source_child_error) + $bits(source_failure) +
        $bits(dependency_generation) + $bits(dependency_time) +
        $bits(dependency_frequency) + $bits(dependency_channel) +
        $bits(dependency_received) + $bits(dependency_data_hold) +
        $bits(dependency_found) + $bits(dependency_bad) +
        $bits(dependency_error_hold) + $bits(dependency_child_error) + $bits(dependency_failure);
    assign controller_bytes = rst_n ? (CONTROLLER_BITS + 7) >> 3 : 64'd0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dependency_state <= D_IDLE;
            dependency_model <= 0;
            dependency_generation <= 0;
            dependency_time <= 0;
            dependency_frequency <= 0;
            dependency_channel <= 0;
            dependency_received <= 0;
            dependency_data_hold <= 0;
            dependency_found <= 0;
            dependency_bad <= 0;
            dependency_error_hold <= 0;
            dependency_child_error <= 0;
            dependency_failure <= 0;
        end else begin
            if (state == IDLE && start_valid && start_ready)
                dependency_failure <= 0;
            if (dependency_state == D_WAIT && lower_output_valid) begin
                if (!lower_beat_good)
                    dependency_bad <= 1;
                if (lower_output_index == dependency_channel) begin
                    dependency_data_hold <= lower_output_data;
                    dependency_found <= 1;
                end
                if (dependency_received < 128)
                    dependency_received <= dependency_received + 1'b1;
            end
            case (dependency_state)
                D_IDLE: if (source_state == S_WAIT && dependency_valid) begin
                    dependency_model <= dependency_req_model;
                    dependency_generation <= dependency_req_generation;
                    dependency_time <= dependency_req_time;
                    dependency_frequency <= dependency_req_frequency;
                    dependency_channel <= dependency_req_channel;
                    dependency_received <= 0;
                    dependency_data_hold <= 0;
                    dependency_found <= 0;
                    dependency_bad <= 0;
                    dependency_error_hold <= 0;
                    dependency_child_error <= 0;
                    dependency_state <= D_VALIDATE;
                end
                D_VALIDATE: begin
                    if (dependency_failure != 0) begin
                        dependency_error_hold <= dependency_failure;
                        dependency_state <= D_RESPONSE;
                    end else if (!dependency_tag_good) begin
                        dependency_error_hold <= 7;
                        dependency_failure <= 7;
                        dependency_state <= D_RESPONSE;
                    end else
                        dependency_state <= D_START;
                end
                D_START: if (lower_ready)
                    dependency_state <= D_WAIT;
                D_WAIT: if (lower_valid) begin
                    dependency_child_error <= lower_error;
                    dependency_state <= D_CHECK;
                end
                D_CHECK: begin
                    if (dependency_child_error != 0) begin
                        dependency_error_hold <= dependency_child_error;
                        dependency_failure <= dependency_child_error;
                    end else if (dependency_bad || !dependency_found || dependency_received != 128) begin
                        dependency_error_hold <= 7;
                        dependency_failure <= 7;
                    end
                    dependency_state <= D_RESPONSE;
                end
                D_RESPONSE: if (dependency_rsp_ready)
                    dependency_state <= D_IDLE;
                default: begin
                    dependency_error_hold <= 7;
                    dependency_failure <= 7;
                    dependency_state <= D_RESPONSE;
                end
            endcase
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            source_state <= S_IDLE;
            source_column <= 0;
            source_received <= 0;
            source_data_hold <= 0;
            source_found <= 0;
            source_bad <= 0;
            source_mask_hold <= 0;
            mask_seen <= 0;
            mask_hold <= 0;
            source_error_hold <= 0;
            source_child_error <= 0;
            source_failure <= 0;
        end else begin
            if (state == IDLE && start_valid && start_ready) begin
                source_failure <= 0;
                mask_seen <= 0;
                mask_hold <= 0;
            end
            if (source_state == S_WAIT && upper_output_valid) begin
                if (!upper_beat_good)
                    source_bad <= 1;
                if (upper_output_index == {27'd0, source_column[4:0]}) begin
                    source_data_hold <= upper_output_data;
                    source_found <= 1;
                end
                if (source_received < 32)
                    source_received <= source_received + 1'b1;
            end
            case (source_state)
                S_IDLE: if (state == PROJECTION_WAIT && projection_source_valid) begin
                    source_column <= projection_source_index;
                    source_received <= 0;
                    source_data_hold <= 0;
                    source_found <= 0;
                    source_bad <= 0;
                    source_error_hold <= 0;
                    source_child_error <= 0;
                    source_state <= S_VALIDATE;
                end
                S_VALIDATE: begin
                    if (source_failure != 0) begin
                        source_error_hold <= source_failure;
                        source_state <= S_RESPONSE;
                    end else if (source_column >= 1024) begin
                        source_error_hold <= 5;
                        source_failure <= 5;
                        source_state <= S_RESPONSE;
                    end else
                        source_state <= S_START;
                end
                S_START: if (upper_ready)
                    source_state <= S_WAIT;
                S_WAIT: if (upper_valid && dependency_state == D_IDLE) begin
                    source_child_error <= upper_error;
                    source_mask_hold <= upper_mask;
                    source_state <= S_CHECK;
                end
                S_CHECK: begin
                    if (dependency_failure != 0) begin
                        source_error_hold <= dependency_failure;
                        source_failure <= dependency_failure;
                    end else if (source_child_error != 0) begin
                        source_error_hold <= source_child_error;
                        source_failure <= source_child_error;
                    end else if (source_bad || !source_found || source_received != 32 ||
                        (mask_seen && mask_hold != source_mask_hold)) begin
                        source_error_hold <= 7;
                        source_failure <= 7;
                    end else begin
                        mask_hold <= source_mask_hold;
                        mask_seen <= 1;
                    end
                    source_state <= S_RESPONSE;
                end
                S_RESPONSE: if (projection_source_rsp_ready)
                    source_state <= S_IDLE;
                default: begin
                    source_error_hold <= 7;
                    source_failure <= 7;
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
            frames_hold <= 0;
            token_hold <= 0;
            half_frames <= 0;
            output_times <= 0;
            audio_hold <= 0;
            weights_hold <= 0;
            matrix_base <= 0;
            matrix_bytes <= 0;
            matrix_stride <= 0;
            row <= 0;
            projection_hold <= 0;
            output_hold <= 0;
            projection_error_hold <= 0;
            error_hold <= 0;
        end else begin
            case (state)
                IDLE: if (start_valid && start_ready) begin
                    model_hold <= model;
                    precision_hold <= precision;
                    generation_hold <= generation;
                    frames_hold <= frames;
                    token_hold <= token;
                    audio_hold <= audio_base;
                    weights_hold <= audio_weights_base;
                    row <= 0;
                    output_hold <= 0;
                    error_hold <= 0;
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
                    end else begin
                        half_frames <= (frames_hold >> 1) + {31'd0, frames_hold[0]};
                        state <= SHAPE;
                    end
                end
                SHAPE: begin
                    output_times <= (half_frames >> 1) + {31'd0, half_frames[0]};
                    state <= SHAPE_VALIDATE;
                end
                SHAPE_VALIDATE: begin
                    if (token_hold >= output_times) begin
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
                    end else if (lookup_rows != 1024 || lookup_columns != 1024 ||
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
                    projection_error_hold <= projection_error;
                    state <= PROJECTION_REGISTER;
                end
                PROJECTION_REGISTER: begin
                    if (source_failure != 0) begin
                        error_hold <= source_failure;
                        state <= PUBLISH;
                    end else if (projection_error_hold != 0) begin
                        error_hold <= projection_error_hold;
                        state <= PUBLISH;
                    end else if (!mask_seen) begin
                        error_hold <= 7;
                        state <= PUBLISH;
                    end else begin
                        output_hold <= projection_hold[15:0];
                        state <= EMIT;
                    end
                end
                EMIT: if (output_ready)
                    state <= ADVANCE;
                ADVANCE: begin
                    if (row == 1023)
                        state <= PUBLISH;
                    else begin
                        row <= row + 1'b1;
                        state <= PROJECTION_START;
                    end
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
