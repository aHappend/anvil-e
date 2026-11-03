module anvil_en1_audio_input (
    input wire image_immutable, image_invalidate,
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] model, kind,
    input wire [31:0] generation, frames, frame, frequency,
    input wire [63:0] audio_base,
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
    output wire input_read_event,
    output wire [31:0] input_read_bytes,
    output wire [63:0] controller_bytes
);
    localparam [3:0] IDLE = 0, VALIDATE = 1, IMAGE_START = 2, IMAGE_WAIT = 3,
        ROW_OFFSET = 4, ELEMENT_OFFSET = 5, ADDRESS = 6, BOUNDS = 7,
        SEND = 8, WAIT = 9, REGISTER = 10, PUBLISH = 11, RESPONSE = 12;
    reg [3:0] state;
    reg [1:0] model_hold, kind_hold;
    reg [31:0] generation_hold, frames_hold, frame_hold, frequency_hold;
    reg [63:0] audio_hold, payload_base, payload_bytes, row_offset;
    reg [63:0] element_offset, read_address;
    reg lane_hold, memory_error_hold;
    reg [31:0] word_hold, output_hold;
    reg [3:0] error_hold;
    wire lookup_ready, lookup_valid, lookup_cmd_valid, lookup_result_ready;
    wire [63:0] lookup_addr, lookup_base, lookup_bytes;
    wire [31:0] lookup_rows, lookup_columns, lookup_stride;
    wire [7:0] lookup_type;
    wire [3:0] lookup_error;
    wire lookup_selected = rst_n && (state == IMAGE_START || state == IMAGE_WAIT);
    wire [63:0] primitive_directory_bytes;
    anvil_en1_tensor_image directory (
        .image_immutable(image_immutable === 1'b1),
        .image_invalidate((image_invalidate === 1'b1)),
        .controller_bytes(primitive_directory_bytes),
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == IMAGE_START), .start_ready(lookup_ready),
        .model(model_hold), .precision(2'd0), .image_class(2'd3),
        .input_audio(1'b1), .input_items(frames_hold), .image_base(audio_hold),
        .tensor_kind(kind_hold == 0 ? 16'h3010 : 16'h3011), .tensor_layer(16'hffff),
        .cmd_valid(lookup_cmd_valid), .cmd_ready(lookup_selected && cmd_ready),
        .cmd_write(), .cmd_addr(lookup_addr), .cmd_wdata(),
        .result_valid(lookup_selected && result_valid), .result_ready(lookup_result_ready),
        .result_data(result_data), .result_error(result_error),
        .done_valid(lookup_valid), .done_ready(rst_n && state == IMAGE_WAIT),
        .done_base(lookup_base), .done_bytes(lookup_bytes), .done_rows(lookup_rows),
        .done_columns(lookup_columns), .done_stride(lookup_stride),
        .done_type(lookup_type), .done_error(lookup_error)
    );
    wire feature_shape = kind_hold == 0 && lookup_rows == frames_hold &&
        lookup_columns == 128 && lookup_stride == 256 && lookup_type == 0;
    wire mask_shape = kind_hold == 1 && lookup_rows == 1 &&
        lookup_columns == frames_hold && lookup_type == 2;
    wire [64:0] address_sum = {1'b0, payload_base} + {1'b0, element_offset};
    wire [64:0] payload_end = {1'b0, payload_base} + {1'b0, payload_bytes};
    wire [64:0] read_end = {1'b0, read_address} + 65'd4;
    assign start_ready = rst_n && state == IDLE;
    assign cmd_valid = lookup_selected ? lookup_cmd_valid : (rst_n && state == SEND);
    assign cmd_write = 0;
    assign cmd_addr = !rst_n ? 64'd0 : (lookup_selected ? lookup_addr : read_address);
    assign cmd_wdata = 0;
    assign result_ready = lookup_selected ? lookup_result_ready : (rst_n && state == WAIT);
    assign done_valid = rst_n && state == RESPONSE;
    assign done_data = rst_n ? output_hold : 32'd0;
    assign done_error = rst_n ? error_hold : 4'd0;
    assign input_read_event = cmd_valid && cmd_ready;
    assign input_read_bytes = input_read_event ? 32'd4 : 32'd0;
    wire [31:0] CONTROLLER_BITS =
        $bits(state) + $bits(model_hold) + $bits(kind_hold) +
        $bits(generation_hold) + $bits(frames_hold) + $bits(frame_hold) +
        $bits(frequency_hold) + $bits(audio_hold) + $bits(payload_base) +
        $bits(payload_bytes) + $bits(row_offset) + $bits(element_offset) +
        $bits(read_address) + $bits(lane_hold) + $bits(memory_error_hold) +
        $bits(word_hold) + $bits(output_hold) + $bits(error_hold);
    assign controller_bytes = !rst_n ? 64'd0 :
        64'((CONTROLLER_BITS + 7) >> 3) + primitive_directory_bytes;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            model_hold <= 0;
            kind_hold <= 0;
            generation_hold <= 0;
            frames_hold <= 0;
            frame_hold <= 0;
            frequency_hold <= 0;
            audio_hold <= 0;
            payload_base <= 0;
            payload_bytes <= 0;
            row_offset <= 0;
            element_offset <= 0;
            read_address <= 0;
            lane_hold <= 0;
            memory_error_hold <= 0;
            word_hold <= 0;
            output_hold <= 0;
            error_hold <= 0;
        end else begin
            case (state)
                IDLE: if (start_valid && start_ready) begin
                    model_hold <= model;
                    kind_hold <= kind;
                    generation_hold <= generation;
                    frames_hold <= frames;
                    frame_hold <= frame;
                    frequency_hold <= frequency;
                    audio_hold <= audio_base;
                    output_hold <= 0;
                    error_hold <= 0;
                    state <= VALIDATE;
                end
                VALIDATE: begin
                    if (model_hold != 1 && model_hold != 2) begin
                        error_hold <= 6;
                        state <= PUBLISH;
                    end else if (generation_hold == 0 || frames_hold == 0 ||
                        frames_hold > 131072 || frame_hold >= frames_hold ||
                        kind_hold > 1 || (kind_hold == 0 && frequency_hold >= 128) ||
                        (kind_hold == 1 && frequency_hold != 0) || audio_hold[1:0] != 0) begin
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
                    end else if (!feature_shape && !mask_shape) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else begin
                        payload_base <= lookup_base;
                        payload_bytes <= lookup_bytes;
                        state <= ROW_OFFSET;
                    end
                end
                ROW_OFFSET: begin
                    row_offset <= kind_hold == 0 ?
                        {32'd0, frame_hold} << 8 : {32'd0, frame_hold} << 2;
                    state <= ELEMENT_OFFSET;
                end
                ELEMENT_OFFSET: begin
                    element_offset <= kind_hold == 0 ?
                        row_offset + ({32'd0, frequency_hold} << 1) : row_offset;
                    lane_hold <= kind_hold == 0 && frequency_hold[0];
                    state <= ADDRESS;
                end
                ADDRESS: begin
                    if (address_sum[64]) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else begin
                        read_address <= {address_sum[63:2], 2'b00};
                        state <= BOUNDS;
                    end
                end
                BOUNDS: begin
                    if (payload_end[64] || read_end[64] || read_address < payload_base ||
                        read_end > payload_end) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else
                        state <= SEND;
                end
                SEND: if (cmd_ready)
                    state <= WAIT;
                WAIT: if (result_valid) begin
                    word_hold <= result_data;
                    memory_error_hold <= result_error;
                    state <= REGISTER;
                end
                REGISTER: begin
                    if (memory_error_hold)
                        error_hold <= 2;
                    else if (kind_hold == 1 && word_hold > 1)
                        error_hold <= 5;
                    else if (kind_hold == 1)
                        output_hold <= word_hold;
                    else
                        output_hold <= lane_hold ?
                            {16'd0, word_hold[31:16]} : {16'd0, word_hold[15:0]};
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
