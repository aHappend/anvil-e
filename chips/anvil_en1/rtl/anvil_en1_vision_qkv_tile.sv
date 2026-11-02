module anvil_en1_vision_qkv_tile (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] model, precision, selector,
    input wire [7:0] layer,
    input wire [31:0] patch, patch_x, patch_y,
    input wire [3:0] head,
    input wire [9:0] component,
    input wire [63:0] vision_weights_base,
    output wire source_valid,
    input wire source_ready,
    output wire [1:0] source_model,
    output wire [7:0] source_layer,
    output wire [31:0] source_patch, source_index,
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
    output wire projection_event,
    output wire [31:0] projection_bytes,
    output wire [63:0] vector_live_bytes, vector_physical_bytes,
    output wire [63:0] controller_bytes, clipped_controller_bytes, clamp_controller_bytes
);
    localparam [4:0] IDLE = 0, VALIDATE = 1, LOOKUP_START = 2,
        LOOKUP_WAIT = 3, NORM_START = 4, NORM_WAIT = 5, NORM_FINISH = 6,
        PROJECTION_START = 7, PROJECTION_WAIT = 8, PROJECTION_ADVANCE = 9,
        PAIR_SETUP = 10, PAIR_FIRST_READ = 11, PAIR_FIRST_CAPTURE = 12,
        PAIR_SECOND_READ = 13, PAIR_SECOND_CAPTURE = 14,
        ROTARY_START = 15, ROTARY_WAIT = 16, PAIR_ADVANCE = 17,
        PUBLISH = 18, RESPONSE = 19;
    localparam [2:0] SRC_IDLE = 0, SRC_VALIDATE = 1, SRC_READ = 2,
        SRC_CAPTURE = 3, SRC_RESPONSE = 4;
    localparam [2:0] SCALE_IDLE = 0, SCALE_START = 1, SCALE_WAIT = 2,
        SCALE_PUBLISH = 3, SCALE_RESPONSE = 4;
    reg [4:0] state;
    reg [2:0] src_state, scale_state;
    reg [1:0] model_hold, precision_hold, selector_hold;
    reg [7:0] layer_hold;
    reg [31:0] patch_hold, x_hold, y_hold;
    reg [3:0] head_hold;
    reg [5:0] component_hold, current_component, pair_base, projection_index;
    reg [63:0] weights_hold, scale_base, scale_bytes;
    reg [31:0] scale_columns, scale_stride, scale_index_hold;
    reg [15:0] scale_data_hold;
    reg [3:0] scale_failure_hold;
    reg scale_error_hold;
    reg input_norm, second_component, input_allocated, head_allocated;
    reg input_committed, head_committed, raw_head_committed;
    reg norm_bad, norm_complete;
    reg [31:0] norm_count, src_index_hold;
    reg src_is_head, src_is_projection, src_error_hold;
    reg [15:0] src_data_hold, input_q, head_q;
    reg [15:0] first_source, second_source, first_output, component_output;
    reg [31:0] output_hold;
    reg [3:0] error_hold;
    (* ramstyle = "M20K", nomem2reg *)
    reg [15:0] input_payload [0:767];
    (* ramstyle = "M20K", nomem2reg *)
    reg [15:0] head_payload [0:63];

    wire lookup_ready, lookup_valid, lookup_cmd_valid, lookup_result_ready;
    wire [63:0] lookup_cmd_addr, lookup_base, lookup_bytes;
    wire [31:0] lookup_columns, lookup_stride;
    wire [3:0] lookup_error;
    wire [15:0] lookup_kind = input_norm ? 16'h1100 :
        (selector_hold == 0 ? 16'h1102 : 16'h1104);
    wire lookup_selected = rst_n && (state == LOOKUP_START || state == LOOKUP_WAIT);
    anvil_en1_tensor_image directory (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == LOOKUP_START), .start_ready(lookup_ready),
        .model(model_hold), .precision(precision_hold), .image_class(2'd1),
        .input_audio(1'b0), .input_items(32'd0), .image_base(weights_hold),
        .tensor_kind(lookup_kind), .tensor_layer({8'd0, layer_hold}),
        .cmd_valid(lookup_cmd_valid), .cmd_ready(lookup_selected && cmd_ready),
        .cmd_write(), .cmd_addr(lookup_cmd_addr), .cmd_wdata(),
        .result_valid(lookup_selected && result_valid), .result_ready(lookup_result_ready),
        .result_data(result_data), .result_error(result_error),
        .done_valid(lookup_valid), .done_ready(rst_n && state == LOOKUP_WAIT),
        .done_base(lookup_base), .done_bytes(lookup_bytes), .done_rows(),
        .done_columns(lookup_columns), .done_stride(lookup_stride),
        .done_type(), .done_error(lookup_error)
    );

    wire projection_ready, projection_valid, projection_cmd_valid, projection_result_ready;
    wire [63:0] projection_cmd_addr;
    wire [31:0] projection_data, projection_source_index;
    wire [3:0] projection_error;
    wire projection_source_valid, projection_source_rsp_ready;
    wire [15:0] projection_kind = selector_hold == 0 ? 16'h1101 :
        (selector_hold == 1 ? 16'h1103 : 16'h1105);
    wire [31:0] projection_row = {22'd0, head_hold, projection_index};
    wire projection_selected = rst_n &&
        (state == PROJECTION_START || state == PROJECTION_WAIT);
    anvil_en1_clipped_projection projection (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == PROJECTION_START), .start_ready(projection_ready),
        .model(model_hold), .precision(precision_hold), .image_class(2'd1),
        .image_base(weights_hold), .tensor_kind(projection_kind),
        .tensor_layer({8'd0, layer_hold}), .row_index(projection_row),
        .source_valid(projection_source_valid),
        .source_ready(rst_n && state == PROJECTION_WAIT && src_state == SRC_IDLE),
        .source_index(projection_source_index),
        .source_rsp_valid(rst_n && src_state == SRC_RESPONSE && src_is_projection),
        .source_rsp_ready(projection_source_rsp_ready),
        .source_rsp_data(src_data_hold), .source_rsp_error(src_error_hold),
        .cmd_valid(projection_cmd_valid), .cmd_ready(projection_selected && cmd_ready),
        .cmd_write(), .cmd_addr(projection_cmd_addr), .cmd_wdata(),
        .result_valid(projection_selected && result_valid),
        .result_ready(projection_result_ready), .result_data(result_data),
        .result_error(result_error),
        .done_valid(projection_valid),
        .done_ready(rst_n && state == PROJECTION_WAIT && src_state == SRC_IDLE),
        .done_data(projection_data), .done_error(projection_error),
        .controller_bytes(clipped_controller_bytes),
        .clamp_controller_bytes(clamp_controller_bytes)
    );

    wire norm_ready, norm_valid, norm_source_valid, norm_source_rsp_ready;
    wire [31:0] norm_source_index, norm_scale_index, normalized_index;
    wire [15:0] normalized_data;
    wire norm_scale_valid, norm_scale_rsp_ready, normalized_valid, normalized_last;
    wire [3:0] norm_error;
    wire norm_selected = rst_n && (state == NORM_START || state == NORM_WAIT);
    anvil_en1_norm norm (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == NORM_START), .start_ready(norm_ready),
        .layer_norm(1'b0), .learned_scale(input_norm || selector_hold != 2),
        .vector_length(input_norm ? 32'd768 : 32'd64), .epsilon(32'h358637bd),
        .source_valid(norm_source_valid),
        .source_ready(input_norm ? (norm_selected && source_ready) :
            (rst_n && state == NORM_WAIT && src_state == SRC_IDLE)),
        .source_index(norm_source_index),
        .source_rsp_valid(input_norm ? (norm_selected && source_rsp_valid) :
            (rst_n && src_state == SRC_RESPONSE && !src_is_projection)),
        .source_rsp_ready(norm_source_rsp_ready),
        .source_rsp_data(input_norm ? source_rsp_data : src_data_hold),
        .source_rsp_error(input_norm ? source_rsp_error : src_error_hold),
        .scale_valid(norm_scale_valid),
        .scale_ready(rst_n && state == NORM_WAIT && scale_state == SCALE_IDLE),
        .scale_index(norm_scale_index),
        .scale_rsp_valid(rst_n && scale_state == SCALE_RESPONSE),
        .scale_rsp_ready(norm_scale_rsp_ready), .scale_rsp_data(scale_data_hold),
        .scale_rsp_error(scale_error_hold),
        .normalized_valid(normalized_valid), .normalized_ready(rst_n && state == NORM_WAIT),
        .normalized_index(normalized_index), .normalized_data(normalized_data),
        .normalized_last(normalized_last),
        .done_valid(norm_valid),
        .done_ready(rst_n && state == NORM_WAIT &&
            scale_state == SCALE_IDLE && src_state == SRC_IDLE),
        .done_error(norm_error)
    );

    wire scale_ready, scale_valid, scale_cmd_valid, scale_result_ready;
    wire [63:0] scale_cmd_addr;
    wire [31:0] scale_data;
    wire [3:0] scale_error;
    anvil_en1_weight_read scales (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && scale_state == SCALE_START), .start_ready(scale_ready),
        .precision(2'd0), .tensor_base(scale_base), .tensor_bytes(scale_bytes),
        .tensor_rows(32'd1), .tensor_columns(scale_columns), .row_stride(scale_stride),
        .row_index(32'd0), .column_index(scale_index_hold),
        .cmd_valid(scale_cmd_valid), .cmd_ready(norm_selected && cmd_ready),
        .cmd_write(), .cmd_addr(scale_cmd_addr), .cmd_wdata(),
        .result_valid(norm_selected && result_valid), .result_ready(scale_result_ready),
        .result_data(result_data), .result_error(result_error),
        .done_valid(scale_valid), .done_ready(rst_n && scale_state == SCALE_WAIT),
        .done_data(scale_data), .done_error(scale_error)
    );

    wire rotary_ready, rotary_valid;
    wire [31:0] rotary_data;
    wire [3:0] rotary_error;
    wire [31:0] rotary_position = current_component[5] ? y_hold : x_hold;
    anvil_en1_rotary_pair #(.SIGNED_POSITION(1)) rotary (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == ROTARY_START), .start_ready(rotary_ready),
        .mode(2'd2), .dimension(10'd32),
        .pair_index({5'd0, current_component[3:0]}),
        .position(rotary_position), .vector_pair({second_source, first_source}),
        .done_valid(rotary_valid), .done_ready(rst_n && state == ROTARY_WAIT),
        .done_data(rotary_data), .done_error(rotary_error)
    );

    wire both_padding = x_hold == 32'hffffffff && y_hold == 32'hffffffff;
    wire coordinate_range = !x_hold[31] && !y_hold[31] &&
        x_hold < 10240 && y_hold < 10240;
    wire [31:0] norm_length = input_norm ? 32'd768 : 32'd64;
    wire normalized_accept = rst_n && state == NORM_WAIT && normalized_valid;
    wire normalized_well_formed = normalized_index == norm_count &&
        normalized_index < norm_length &&
        normalized_last == (normalized_index == norm_length - 1'b1) &&
        !norm_complete && !norm_bad;
    wire projection_accept = rst_n && state == PROJECTION_WAIT &&
        projection_valid && src_state == SRC_IDLE;

    assign start_ready = rst_n && state == IDLE;
    assign source_valid = norm_selected && input_norm && norm_source_valid;
    assign source_model = rst_n ? model_hold : 2'd0;
    assign source_layer = rst_n ? layer_hold : 8'd0;
    assign source_patch = rst_n ? patch_hold : 32'd0;
    assign source_index = rst_n ? norm_source_index : 32'd0;
    assign source_rsp_ready = norm_selected && input_norm && norm_source_rsp_ready;
    assign cmd_valid = rst_n && (lookup_selected ? lookup_cmd_valid :
        (projection_selected ? projection_cmd_valid : (norm_selected && scale_cmd_valid)));
    assign cmd_write = 0;
    assign cmd_addr = !rst_n ? 64'd0 : (lookup_selected ? lookup_cmd_addr :
        (projection_selected ? projection_cmd_addr : (norm_selected ? scale_cmd_addr : 64'd0)));
    assign cmd_wdata = 0;
    assign result_ready = rst_n && (lookup_selected ? lookup_result_ready :
        (projection_selected ? projection_result_ready : (norm_selected && scale_result_ready)));
    assign done_valid = rst_n && state == RESPONSE;
    assign done_data = rst_n ? output_hold : 32'd0;
    assign done_error = rst_n ? error_hold : 4'd0;
    assign projection_event = projection_accept && projection_error == 0;
    assign projection_bytes = projection_event ? 32'd2 : 32'd0;
    assign vector_live_bytes = rst_n ?
        (input_allocated ? 64'd1536 : 64'd0) + (head_allocated ? 64'd128 : 64'd0) : 64'd0;
    assign vector_physical_bytes = rst_n ? 64'd1664 : 64'd0;
    localparam integer CONTROLLER_BITS =
        $bits(state) + $bits(src_state) + $bits(scale_state) +
        $bits(model_hold) + $bits(precision_hold) + $bits(selector_hold) +
        $bits(layer_hold) + $bits(patch_hold) + $bits(x_hold) + $bits(y_hold) +
        $bits(head_hold) + $bits(component_hold) + $bits(current_component) +
        $bits(pair_base) + $bits(projection_index) + $bits(weights_hold) +
        $bits(scale_base) + $bits(scale_bytes) + $bits(scale_columns) +
        $bits(scale_stride) + $bits(scale_index_hold) + $bits(scale_data_hold) +
        $bits(scale_failure_hold) + $bits(scale_error_hold) +
        $bits(input_norm) + $bits(second_component) +
        $bits(input_allocated) + $bits(head_allocated) +
        $bits(input_committed) + $bits(head_committed) + $bits(raw_head_committed) +
        $bits(norm_bad) + $bits(norm_complete) + $bits(norm_count) +
        $bits(src_index_hold) + $bits(src_is_head) + $bits(src_is_projection) +
        $bits(src_error_hold) + $bits(src_data_hold) + $bits(input_q) + $bits(head_q) +
        $bits(first_source) + $bits(second_source) + $bits(first_output) +
        $bits(component_output) + $bits(output_hold) + $bits(error_hold);
    assign controller_bytes = rst_n ? (CONTROLLER_BITS + 7) >> 3 : 64'd0;

    always @(posedge clk) begin
        if (normalized_accept && normalized_well_formed) begin
            if (input_norm)
                input_payload[normalized_index[9:0]] <= normalized_data;
            else
                head_payload[normalized_index[5:0]] <= normalized_data;
        end
        if (projection_accept && projection_error == 0)
            head_payload[projection_index] <= projection_data[15:0];
        if (rst_n && src_state == SRC_READ) begin
            if (src_is_head)
                head_q <= head_payload[src_index_hold[5:0]];
            else
                input_q <= input_payload[src_index_hold[9:0]];
        end
        if (rst_n && state == PAIR_FIRST_READ)
            head_q <= head_payload[pair_base];
        if (rst_n && state == PAIR_SECOND_READ)
            head_q <= head_payload[{pair_base[5], 1'b1, pair_base[3:0]}];
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            src_state <= SRC_IDLE;
            src_index_hold <= 0;
            src_is_head <= 0;
            src_is_projection <= 0;
            src_data_hold <= 0;
            src_error_hold <= 0;
        end else begin
            case (src_state)
                SRC_IDLE: begin
                    if (state == PROJECTION_WAIT && projection_source_valid) begin
                        src_index_hold <= projection_source_index;
                        src_is_head <= 0;
                        src_is_projection <= 1;
                        src_error_hold <= 0;
                        src_state <= SRC_VALIDATE;
                    end else if (state == NORM_WAIT && !input_norm && norm_source_valid) begin
                        src_index_hold <= norm_source_index;
                        src_is_head <= 1;
                        src_is_projection <= 0;
                        src_error_hold <= 0;
                        src_state <= SRC_VALIDATE;
                    end
                end
                SRC_VALIDATE: begin
                    if ((src_is_head && (!raw_head_committed || src_index_hold >= 64)) ||
                        (!src_is_head && (!input_committed || src_index_hold >= 768))) begin
                        src_data_hold <= 0;
                        src_error_hold <= 1;
                        src_state <= SRC_RESPONSE;
                    end else
                        src_state <= SRC_READ;
                end
                SRC_READ: src_state <= SRC_CAPTURE;
                SRC_CAPTURE: begin
                    src_data_hold <= src_is_head ? head_q : input_q;
                    src_state <= SRC_RESPONSE;
                end
                SRC_RESPONSE: if ((src_is_projection && projection_source_rsp_ready) ||
                    (!src_is_projection && norm_source_rsp_ready))
                    src_state <= SRC_IDLE;
                default: begin
                    src_data_hold <= 0;
                    src_error_hold <= 1;
                    src_state <= SRC_RESPONSE;
                end
            endcase
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scale_state <= SCALE_IDLE;
            scale_index_hold <= 0;
            scale_data_hold <= 0;
            scale_error_hold <= 0;
            scale_failure_hold <= 0;
        end else begin
            case (scale_state)
                SCALE_IDLE: if (state == NORM_WAIT && norm_scale_valid) begin
                    scale_index_hold <= norm_scale_index;
                    scale_error_hold <= 0;
                    scale_failure_hold <= 0;
                    scale_state <= SCALE_START;
                end
                SCALE_START: if (scale_ready)
                    scale_state <= SCALE_WAIT;
                SCALE_WAIT: if (scale_valid) begin
                    scale_data_hold <= scale_data[31:16];
                    scale_error_hold <= scale_error != 0;
                    scale_failure_hold <= scale_error;
                    scale_state <= SCALE_PUBLISH;
                end
                SCALE_PUBLISH: scale_state <= SCALE_RESPONSE;
                SCALE_RESPONSE: if (norm_scale_rsp_ready)
                    scale_state <= SCALE_IDLE;
                default: begin
                    scale_data_hold <= 0;
                    scale_error_hold <= 1;
                    scale_failure_hold <= 7;
                    scale_state <= SCALE_RESPONSE;
                end
            endcase
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            model_hold <= 0;
            precision_hold <= 0;
            selector_hold <= 0;
            layer_hold <= 0;
            patch_hold <= 0;
            x_hold <= 0;
            y_hold <= 0;
            head_hold <= 0;
            component_hold <= 0;
            current_component <= 0;
            pair_base <= 0;
            projection_index <= 0;
            weights_hold <= 0;
            scale_base <= 0;
            scale_bytes <= 0;
            scale_columns <= 0;
            scale_stride <= 0;
            input_norm <= 0;
            second_component <= 0;
            input_allocated <= 0;
            head_allocated <= 0;
            input_committed <= 0;
            head_committed <= 0;
            raw_head_committed <= 0;
            norm_bad <= 0;
            norm_complete <= 0;
            norm_count <= 0;
            first_source <= 0;
            second_source <= 0;
            first_output <= 0;
            component_output <= 0;
            output_hold <= 0;
            error_hold <= 0;
        end else begin
            if (normalized_accept) begin
                if (!normalized_well_formed)
                    norm_bad <= 1;
                else begin
                    norm_count <= norm_count + 1'b1;
                    if (normalized_last)
                        norm_complete <= 1;
                end
            end
            case (state)
                IDLE: if (start_valid && start_ready) begin
                    model_hold <= model;
                    precision_hold <= precision;
                    selector_hold <= selector;
                    layer_hold <= layer;
                    patch_hold <= patch;
                    x_hold <= patch_x;
                    y_hold <= patch_y;
                    head_hold <= head;
                    component_hold <= component[5:0];
                    current_component <= component[5:0];
                    input_norm <= 1;
                    second_component <= 0;
                    input_allocated <= 0;
                    head_allocated <= 0;
                    input_committed <= 0;
                    head_committed <= 0;
                    raw_head_committed <= 0;
                    norm_bad <= 0;
                    norm_complete <= 0;
                    norm_count <= 0;
                    projection_index <= 0;
                    weights_hold <= vision_weights_base;
                    output_hold <= 0;
                    error_hold <= 0;
                    if (component[9:6] != 0 || component[0])
                        error_hold <= 5;
                    state <= VALIDATE;
                end
                VALIDATE: begin
                    if ((model_hold != 1 && model_hold != 2) || precision_hold > 1) begin
                        error_hold <= 6;
                        state <= PUBLISH;
                    end else if (error_hold != 0 || selector_hold == 3 || layer_hold >= 16 ||
                        patch_hold > 131071 || head_hold >= 12 ||
                        (!both_padding && !coordinate_range)) begin
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else begin
                        input_allocated <= 1;
                        state <= LOOKUP_START;
                    end
                end
                LOOKUP_START: if (lookup_ready)
                    state <= LOOKUP_WAIT;
                LOOKUP_WAIT: if (lookup_valid) begin
                    if (lookup_error != 0) begin
                        error_hold <= lookup_error;
                        state <= PUBLISH;
                    end else begin
                        scale_base <= lookup_base;
                        scale_bytes <= lookup_bytes;
                        scale_columns <= lookup_columns;
                        scale_stride <= lookup_stride;
                        norm_bad <= 0;
                        norm_complete <= 0;
                        norm_count <= 0;
                        state <= NORM_START;
                    end
                end
                NORM_START: if (norm_ready)
                    state <= NORM_WAIT;
                NORM_WAIT: if (norm_valid && scale_state == SCALE_IDLE && src_state == SRC_IDLE) begin
                    if (norm_error != 0) begin
                        error_hold <= scale_error_hold && scale_failure_hold != 0 ?
                            scale_failure_hold : norm_error;
                        state <= PUBLISH;
                    end else
                        state <= NORM_FINISH;
                end
                NORM_FINISH: begin
                    if (norm_bad || !norm_complete || norm_count != norm_length) begin
                        error_hold <= 7;
                        state <= PUBLISH;
                    end else if (input_norm) begin
                        input_committed <= 1;
                        head_allocated <= 1;
                        projection_index <= 0;
                        state <= PROJECTION_START;
                    end else begin
                        head_committed <= 1;
                        state <= PAIR_SETUP;
                    end
                end
                PROJECTION_START: if (projection_ready)
                    state <= PROJECTION_WAIT;
                PROJECTION_WAIT: if (projection_accept) begin
                    if (projection_error != 0) begin
                        error_hold <= projection_error;
                        state <= PUBLISH;
                    end else
                        state <= PROJECTION_ADVANCE;
                end
                PROJECTION_ADVANCE: begin
                    if (projection_index == 63) begin
                        raw_head_committed <= 1;
                        input_norm <= 0;
                        norm_bad <= 0;
                        norm_complete <= 0;
                        norm_count <= 0;
                        if (selector_hold == 2)
                            state <= NORM_START;
                        else
                            state <= LOOKUP_START;
                    end else begin
                        projection_index <= projection_index + 1'b1;
                        state <= PROJECTION_START;
                    end
                end
                PAIR_SETUP: begin
                    if (!head_committed) begin
                        error_hold <= 7;
                        state <= PUBLISH;
                    end else begin
                        pair_base <= {current_component[5], 1'b0, current_component[3:0]};
                        state <= PAIR_FIRST_READ;
                    end
                end
                PAIR_FIRST_READ: state <= PAIR_FIRST_CAPTURE;
                PAIR_FIRST_CAPTURE: begin
                    first_source <= head_q;
                    state <= PAIR_SECOND_READ;
                end
                PAIR_SECOND_READ: state <= PAIR_SECOND_CAPTURE;
                PAIR_SECOND_CAPTURE: begin
                    second_source <= head_q;
                    if (selector_hold == 2) begin
                        component_output <= current_component[4] ? head_q : first_source;
                        state <= PAIR_ADVANCE;
                    end else
                        state <= ROTARY_START;
                end
                ROTARY_START: if (rotary_ready)
                    state <= ROTARY_WAIT;
                ROTARY_WAIT: if (rotary_valid) begin
                    if (rotary_error != 0) begin
                        error_hold <= rotary_error;
                        state <= PUBLISH;
                    end else begin
                        component_output <= current_component[4] ?
                            rotary_data[31:16] : rotary_data[15:0];
                        state <= PAIR_ADVANCE;
                    end
                end
                PAIR_ADVANCE: begin
                    if (second_component) begin
                        output_hold <= {component_output, first_output};
                        state <= PUBLISH;
                    end else begin
                        first_output <= component_output;
                        current_component <= component_hold + 6'd1;
                        second_component <= 1;
                        state <= PAIR_SETUP;
                    end
                end
                PUBLISH: state <= RESPONSE;
                RESPONSE: if (done_ready) begin
                    input_allocated <= 0;
                    head_allocated <= 0;
                    input_committed <= 0;
                    head_committed <= 0;
                    raw_head_committed <= 0;
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
