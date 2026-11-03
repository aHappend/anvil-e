module anvil_en1_owner_kv_tile #(
    parameter integer COMPACT = 0,
    parameter integer ALLOW_QUERY = 0,
    parameter integer EXTERNAL_INPUT_RAM = 0
) (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] model, precision,
    input wire [7:0] owner,
    input wire [31:0] token,
    input wire is_value,
    input wire [1:0] kv_head,
    input wire is_query,
    input wire [3:0] query_head,
    input wire [9:0] component,
    input wire [63:0] weights_base,
    output wire source_valid,
    input wire source_ready,
    output wire [1:0] source_model,
    output wire [7:0] source_owner,
    output wire [31:0] source_token, source_index,
    output wire source_normalized,
    output wire input_store_valid,
    output wire [31:0] input_store_index,
    output wire [15:0] input_store_data,
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
    output wire query_projection_event,
    output wire [31:0] query_projection_bytes,
    output wire [63:0] controller_bytes
);
    generate if ((COMPACT != 0 && COMPACT != 1) ||
        (ALLOW_QUERY != 0 && ALLOW_QUERY != 1) ||
        (EXTERNAL_INPUT_RAM != 0 && EXTERNAL_INPUT_RAM != 1)) begin : invalid_parameters
        initial $fatal(1, "PARAMETER ERROR: COMPACT, ALLOW_QUERY and EXTERNAL_INPUT_RAM must be 0 or 1");
        assign start_ready = 0;
        assign source_valid = 0;
        assign source_model = 0;
        assign source_owner = 0;
        assign source_token = 0;
        assign source_index = 0;
        assign source_normalized = 0;
        assign input_store_valid = 0;
        assign input_store_index = 0;
        assign input_store_data = 0;
        assign source_rsp_ready = 0;
        assign cmd_valid = 0;
        assign cmd_write = 0;
        assign cmd_addr = 0;
        assign cmd_wdata = 0;
        assign result_ready = 0;
        assign done_valid = 0;
        assign done_data = 0;
        assign done_error = 0;
        assign projection_event = 0;
        assign projection_bytes = 0;
        assign query_projection_event = 0;
        assign query_projection_bytes = 0;
        assign controller_bytes = 0;
    end else begin : tile
        localparam integer MAX_H = COMPACT ? 8 : 2560;
        localparam integer MAX_D = COMPACT ? 8 : 512;
        localparam integer H_BITS = $clog2(MAX_H);
        localparam integer D_BITS = $clog2(MAX_D);
        localparam [4:0] IDLE = 0, VALIDATE = 1, LOOKUP_START = 2,
            LOOKUP_WAIT = 3, LOOKUP_FINISH = 4, NORM_START = 5,
            NORM_WAIT = 6, NORM_FINISH = 7, PROJECTION_START = 8,
            PROJECTION_WAIT = 9, PROJECTION_ADVANCE = 10,
            PAIR_SETUP = 11, PAIR_FIRST_READ = 12, PAIR_FIRST_CAPTURE = 13,
            PAIR_SECOND_READ = 14, PAIR_SECOND_CAPTURE = 15,
            ROTARY_START = 16, ROTARY_WAIT = 17,
            PAIR_ADVANCE = 18, PUBLISH = 19, RESPONSE = 20;
        localparam [2:0] SRC_IDLE = 0, SRC_READ = 1,
            SRC_PUBLISH = 2, SRC_RESPONSE = 3;
        localparam [2:0] SCALE_IDLE = 0, SCALE_START = 1,
            SCALE_WAIT = 2, SCALE_PUBLISH = 3, SCALE_RESPONSE = 4;
        localparam [1:0] MEMORY_LOOKUP = 0, MEMORY_PROJECTION = 1,
            MEMORY_SCALE = 2;
        reg [4:0] state;
        reg [2:0] src_state, scale_state;
        reg [1:0] model_hold, precision_hold, memory_owner;
        reg [3:0] head_hold;
        reg [7:0] owner_hold;
        reg [31:0] token_hold, hidden_hold, dimension_hold, heads_hold;
        reg [63:0] weights_hold;
        reg [9:0] component_hold, current_component, pair_base;
        reg selector_hold, query_hold, global_hold, input_norm, second_component;
        reg src_is_head, src_is_projection;
        reg [31:0] src_index_hold, scale_index_hold, projection_index;
        reg [15:0] src_data_hold, scale_data_hold;
        reg [15:0] first_source, second_source, first_output, component_output;
        reg [15:0] lookup_kind;
        reg [63:0] descriptor_base, descriptor_bytes, scale_base, scale_bytes;
        reg [31:0] descriptor_rows, descriptor_columns, descriptor_stride;
        reg [31:0] scale_columns, scale_stride;
        reg [15:0] projection_data_hold;
        reg [31:0] output_hold;
        reg [3:0] error_hold;
        reg scale_error_hold;
        wire [15:0] input_q;
        reg [15:0] head_q;
        wire [31:0] CONTROLLER_BITS = $bits({
            state, src_state, scale_state, model_hold, precision_hold, memory_owner,
            head_hold, owner_hold, token_hold, hidden_hold, dimension_hold, heads_hold,
            weights_hold, component_hold, current_component, pair_base, selector_hold,
            query_hold, global_hold, input_norm, second_component, src_is_head,
            src_is_projection, src_index_hold, scale_index_hold, projection_index,
            src_data_hold, scale_data_hold, first_source, second_source, first_output,
            component_output, lookup_kind, descriptor_base, descriptor_bytes,
            scale_base, scale_bytes, descriptor_rows, descriptor_columns,
            descriptor_stride, scale_columns, scale_stride, projection_data_hold,
            output_hold, error_hold, scale_error_hold, input_q, head_q
        });
        wire [63:0] lookup_controller_bytes, projection_controller_bytes;
        wire [63:0] norm_controller_bytes, weight_controller_bytes, rotary_controller_bytes;
        wire [63:0] fp_controller_bytes;
        assign controller_bytes = !rst_n ? 64'd0 :
            64'((CONTROLLER_BITS+7) >> 3) + lookup_controller_bytes +
            projection_controller_bytes + norm_controller_bytes +
            weight_controller_bytes + rotary_controller_bytes + fp_controller_bytes;
        wire projection_phase = state == PROJECTION_START || state == PROJECTION_WAIT;
        wire norm_phase = state == NORM_START || state == NORM_WAIT;
        wire scale_phase = scale_state == SCALE_START || scale_state == SCALE_WAIT;
        wire rotary_phase = state == ROTARY_START || state == ROTARY_WAIT;
        wire fp_ready, fp_valid;
        wire [31:0] fp_data;
        wire [3:0] fp_error;
        wire projection_arithmetic_valid, projection_arithmetic_result_ready;
        wire norm_arithmetic_valid, norm_arithmetic_result_ready;
        wire scale_arithmetic_valid, scale_arithmetic_result_ready;
        wire rotary_arithmetic_valid, rotary_arithmetic_result_ready;
        wire [2:0] projection_arithmetic_operation, norm_arithmetic_operation;
        wire [2:0] scale_arithmetic_operation, rotary_arithmetic_operation;
        wire [31:0] projection_arithmetic_a, projection_arithmetic_b;
        wire [31:0] norm_arithmetic_a, norm_arithmetic_b;
        wire [31:0] scale_arithmetic_a, scale_arithmetic_b;
        wire [31:0] rotary_arithmetic_a, rotary_arithmetic_b;
        (* ramstyle = "M20K", nomem2reg *)
        reg [15:0] head_payload [0:MAX_D-1];

        wire native_owner, selected_global;
        wire [7:0] selected_owner_count, selected_layer_count;
        wire [11:0] selected_hidden;
        anvil_en1_geometry geometry (
            .rst_n(rst_n), .model(model_hold), .layer(owner_hold),
            .is_native(native_owner), .layers(selected_layer_count),
            .owners(selected_owner_count),
            .owner(), .is_global(selected_global), .hidden(selected_hidden),
            .intermediate()
        );
        wire lookup_ready, lookup_valid;
        wire [63:0] lookup_base, lookup_bytes;
        wire [31:0] lookup_rows, lookup_columns, lookup_stride;
        wire [3:0] lookup_error;
        wire lookup_cmd_valid, lookup_result_ready;
        wire [63:0] lookup_cmd_addr;
        anvil_en1_tensor_image #(.COMPACT(COMPACT)) tensor_lookup (
            .controller_bytes(lookup_controller_bytes),
            .clk(clk), .rst_n(rst_n),
            .start_valid(rst_n && state == LOOKUP_START), .start_ready(lookup_ready),
            .model(model_hold), .precision(precision_hold), .image_class(2'd0),
            .input_audio(1'b0), .input_items(32'd0), .image_base(weights_hold),
            .tensor_kind(lookup_kind), .tensor_layer({8'd0, owner_hold}),
            .cmd_valid(lookup_cmd_valid),
            .cmd_ready(rst_n && memory_owner == MEMORY_LOOKUP && cmd_ready),
            .cmd_write(), .cmd_addr(lookup_cmd_addr), .cmd_wdata(),
            .result_valid(rst_n && memory_owner == MEMORY_LOOKUP && result_valid),
            .result_ready(lookup_result_ready), .result_data(result_data),
            .result_error(result_error),
            .done_valid(lookup_valid), .done_ready(rst_n && state == LOOKUP_WAIT),
            .done_base(lookup_base), .done_bytes(lookup_bytes),
            .done_rows(lookup_rows), .done_columns(lookup_columns),
            .done_stride(lookup_stride), .done_type(), .done_error(lookup_error)
        );
        wire projection_ready, projection_valid;
        wire [31:0] projection_data;
        wire [3:0] projection_error;
        wire projection_source_valid, projection_source_rsp_ready;
        wire [31:0] projection_source_index;
        wire projection_cmd_valid, projection_result_ready;
        wire [63:0] projection_cmd_addr;
        wire [31:0] projection_row =
            (32'(head_hold) * dimension_hold) + projection_index;
        anvil_en1_projection #(.EXTERNAL_FP(1)) projection_unit (
            .controller_bytes(projection_controller_bytes),
            .clk(clk), .rst_n(rst_n),
            .start_valid(rst_n && state == PROJECTION_START), .start_ready(projection_ready),
            .precision(precision_hold), .tensor_base(descriptor_base),
            .tensor_bytes(descriptor_bytes), .tensor_rows(descriptor_rows),
            .tensor_columns(descriptor_columns), .row_stride(descriptor_stride),
            .row_index(projection_row),
            .source_valid(projection_source_valid),
            .source_ready(EXTERNAL_INPUT_RAM ?
                (rst_n && state == PROJECTION_WAIT && source_ready) :
                (rst_n && src_state == SRC_IDLE && state == PROJECTION_WAIT)),
            .source_index(projection_source_index),
            .source_rsp_valid(EXTERNAL_INPUT_RAM ?
                (rst_n && state == PROJECTION_WAIT && source_rsp_valid) :
                (rst_n && src_state == SRC_RESPONSE && src_is_projection)),
            .source_rsp_ready(projection_source_rsp_ready),
            .source_rsp_data(EXTERNAL_INPUT_RAM ? source_rsp_data : src_data_hold),
            .source_rsp_error(EXTERNAL_INPUT_RAM && source_rsp_error),
            .cmd_valid(projection_cmd_valid),
            .cmd_ready(rst_n && memory_owner == MEMORY_PROJECTION && cmd_ready),
            .cmd_write(), .cmd_addr(projection_cmd_addr), .cmd_wdata(),
            .result_valid(rst_n && memory_owner == MEMORY_PROJECTION && result_valid),
            .result_ready(projection_result_ready), .result_data(result_data),
            .result_error(result_error),
            .done_valid(projection_valid),
            .done_ready(rst_n && state == PROJECTION_WAIT),
            .done_data(projection_data), .done_error(projection_error),
            .arithmetic_valid(projection_arithmetic_valid),
            .arithmetic_ready(projection_phase && fp_ready),
            .arithmetic_operation(projection_arithmetic_operation),
            .arithmetic_a(projection_arithmetic_a), .arithmetic_b(projection_arithmetic_b),
            .arithmetic_result_valid(projection_phase && fp_valid),
            .arithmetic_result_ready(projection_arithmetic_result_ready),
            .arithmetic_result_data(fp_data), .arithmetic_result_error(fp_error)
        );
        wire norm_ready, norm_valid, norm_source_valid, norm_source_ready;
        wire norm_source_rsp_valid, norm_source_rsp_ready;
        wire [31:0] norm_source_index;
        wire [15:0] norm_source_data;
        wire norm_source_error;
        wire norm_scale_valid, norm_scale_rsp_ready;
        wire [31:0] norm_scale_index;
        wire normalized_valid;
        wire [31:0] normalized_index;
        wire [15:0] normalized_data;
        wire [3:0] norm_error;
        assign norm_source_ready = input_norm ? source_ready :
            (rst_n && src_state == SRC_IDLE && state == NORM_WAIT);
        assign norm_source_rsp_valid = input_norm ? source_rsp_valid :
            (rst_n && src_state == SRC_RESPONSE && !src_is_projection);
        assign norm_source_data = input_norm ? source_rsp_data : src_data_hold;
        assign norm_source_error = input_norm && source_rsp_error;
        anvil_en1_norm #(.EXTERNAL_FP(1)) norm_unit (
            .controller_bytes(norm_controller_bytes),
            .clk(clk), .rst_n(rst_n),
            .start_valid(rst_n && state == NORM_START), .start_ready(norm_ready),
            .layer_norm(1'b0), .learned_scale(input_norm || query_hold || !selector_hold),
            .vector_length(input_norm ? hidden_hold : dimension_hold),
            .epsilon(32'h358637bd),
            .source_valid(norm_source_valid), .source_ready(norm_source_ready),
            .source_index(norm_source_index), .source_rsp_valid(norm_source_rsp_valid),
            .source_rsp_ready(norm_source_rsp_ready), .source_rsp_data(norm_source_data),
            .source_rsp_error(norm_source_error),
            .scale_valid(norm_scale_valid),
            .scale_ready(rst_n && scale_state == SCALE_IDLE && state == NORM_WAIT),
            .scale_index(norm_scale_index),
            .scale_rsp_valid(rst_n && scale_state == SCALE_RESPONSE),
            .scale_rsp_ready(norm_scale_rsp_ready),
            .scale_rsp_data(scale_data_hold), .scale_rsp_error(scale_error_hold),
            .normalized_valid(normalized_valid),
            .normalized_ready(rst_n && state == NORM_WAIT),
            .normalized_index(normalized_index), .normalized_data(normalized_data),
            .normalized_last(),
            .done_valid(norm_valid), .done_ready(rst_n && state == NORM_WAIT),
            .done_error(norm_error),
            .arithmetic_valid(norm_arithmetic_valid),
            .arithmetic_ready(norm_phase && !scale_phase && fp_ready),
            .arithmetic_operation(norm_arithmetic_operation),
            .arithmetic_a(norm_arithmetic_a), .arithmetic_b(norm_arithmetic_b),
            .arithmetic_result_valid(norm_phase && !scale_phase && fp_valid),
            .arithmetic_result_ready(norm_arithmetic_result_ready),
            .arithmetic_result_data(fp_data), .arithmetic_result_error(fp_error)
        );
        wire scale_ready, scale_valid;
        wire [31:0] scale_data;
        wire [3:0] scale_error;
        wire scale_cmd_valid, scale_result_ready;
        wire [63:0] scale_cmd_addr;
        anvil_en1_weight_read #(.EXTERNAL_FP(1)) scale_reader (
            .controller_bytes(weight_controller_bytes),
            .clk(clk), .rst_n(rst_n),
            .start_valid(rst_n && scale_state == SCALE_START), .start_ready(scale_ready),
            .precision(2'd0), .tensor_base(scale_base), .tensor_bytes(scale_bytes),
            .tensor_rows(32'd1), .tensor_columns(scale_columns),
            .row_stride(scale_stride), .row_index(32'd0), .column_index(scale_index_hold),
            .cmd_valid(scale_cmd_valid),
            .cmd_ready(rst_n && memory_owner == MEMORY_SCALE && cmd_ready),
            .cmd_write(), .cmd_addr(scale_cmd_addr), .cmd_wdata(),
            .result_valid(rst_n && memory_owner == MEMORY_SCALE && result_valid),
            .result_ready(scale_result_ready), .result_data(result_data),
            .result_error(result_error),
            .done_valid(scale_valid), .done_ready(rst_n && scale_state == SCALE_WAIT),
            .done_data(scale_data), .done_error(scale_error),
            .arithmetic_valid(scale_arithmetic_valid),
            .arithmetic_ready(scale_phase && fp_ready),
            .arithmetic_operation(scale_arithmetic_operation),
            .arithmetic_a(scale_arithmetic_a), .arithmetic_b(scale_arithmetic_b),
            .arithmetic_result_valid(scale_phase && fp_valid),
            .arithmetic_result_ready(scale_arithmetic_result_ready),
            .arithmetic_result_data(fp_data), .arithmetic_result_error(fp_error)
        );
        wire rotary_ready, rotary_valid;
        wire [31:0] rotary_data;
        wire [3:0] rotary_error;
        anvil_en1_rotary_pair #(.EXTERNAL_FP(1)) rotary_unit (
            .controller_bytes(rotary_controller_bytes),
            .clk(clk), .rst_n(rst_n),
            .start_valid(rst_n && state == ROTARY_START), .start_ready(rotary_ready),
            .mode(global_hold ? 2'd1 : 2'd0), .dimension(dimension_hold[9:0]),
            .pair_index(pair_base[8:0]), .position(token_hold),
            .vector_pair({second_source, first_source}),
            .done_valid(rotary_valid), .done_ready(rst_n && state == ROTARY_WAIT),
            .done_data(rotary_data), .done_error(rotary_error),
            .arithmetic_valid(rotary_arithmetic_valid),
            .arithmetic_ready(rotary_phase && fp_ready),
            .arithmetic_operation(rotary_arithmetic_operation),
            .arithmetic_a(rotary_arithmetic_a), .arithmetic_b(rotary_arithmetic_b),
            .arithmetic_result_valid(rotary_phase && fp_valid),
            .arithmetic_result_ready(rotary_arithmetic_result_ready),
            .arithmetic_result_data(fp_data), .arithmetic_result_error(fp_error)
        );
        anvil_en1_fp32 fp_unit (
            .controller_bytes(fp_controller_bytes),
            .clk(clk), .rst_n(rst_n),
            .start_valid(rst_n && (scale_phase ? scale_arithmetic_valid :
                (projection_phase ? projection_arithmetic_valid :
                (norm_phase ? norm_arithmetic_valid :
                (rotary_phase && rotary_arithmetic_valid))))),
            .start_ready(fp_ready),
            .operation(scale_phase ? scale_arithmetic_operation :
                (projection_phase ? projection_arithmetic_operation :
                (norm_phase ? norm_arithmetic_operation : rotary_arithmetic_operation))),
            .operand_a(scale_phase ? scale_arithmetic_a :
                (projection_phase ? projection_arithmetic_a :
                (norm_phase ? norm_arithmetic_a : rotary_arithmetic_a))),
            .operand_b(scale_phase ? scale_arithmetic_b :
                (projection_phase ? projection_arithmetic_b :
                (norm_phase ? norm_arithmetic_b : rotary_arithmetic_b))),
            .done_valid(fp_valid),
            .done_ready(rst_n && (scale_phase ? scale_arithmetic_result_ready :
                (projection_phase ? projection_arithmetic_result_ready :
                (norm_phase ? norm_arithmetic_result_ready :
                (rotary_phase && rotary_arithmetic_result_ready))))),
            .done_data(fp_data), .done_error(fp_error)
        );

        wire scratch_norm_write = rst_n && state == NORM_WAIT && normalized_valid;
        wire scratch_projection_write = rst_n && state == PROJECTION_ADVANCE;
        wire input_read = rst_n && src_state == SRC_READ && !src_is_head;
        wire head_read = rst_n && ((src_state == SRC_READ && src_is_head) ||
            state == PAIR_FIRST_READ || state == PAIR_SECOND_READ);
        wire [31:0] pair_second_address = selector_hold ?
            {22'd0, current_component} + 32'd1 :
            {22'd0, pair_base} + (dimension_hold >> 1);
        wire [31:0] pair_first_address = selector_hold ?
            {22'd0, current_component} : {22'd0, pair_base};
        wire [31:0] head_read_address = src_state == SRC_READ ?
            src_index_hold : (state == PAIR_FIRST_READ ?
                pair_first_address : pair_second_address);
        if (!EXTERNAL_INPUT_RAM) begin : internal_input_ram
            (* ramstyle = "M20K", nomem2reg *)
            reg [15:0] input_payload [0:MAX_H-1];
            reg [15:0] input_ram_q;
            assign input_q = input_ram_q;
            always @(posedge clk) begin
                if (scratch_norm_write && input_norm)
                    input_payload[normalized_index[H_BITS-1:0]] <= normalized_data;
                if (input_read)
                    input_ram_q <= input_payload[src_index_hold[H_BITS-1:0]];
            end
        end else begin : external_input_ram
            assign input_q = 16'd0;
        end
        always @(posedge clk) begin
            if (scratch_projection_write)
                head_payload[projection_index[D_BITS-1:0]] <= projection_data_hold;
            else if (scratch_norm_write && !input_norm)
                head_payload[normalized_index[D_BITS-1:0]] <= normalized_data;
            if (head_read)
                head_q <= head_payload[head_read_address[D_BITS-1:0]];
        end

        assign start_ready = rst_n && state == IDLE;
        wire external_projection = EXTERNAL_INPUT_RAM && state == PROJECTION_WAIT;
        assign source_valid = rst_n && (external_projection ?
            projection_source_valid : (input_norm && norm_source_valid));
        assign source_model = rst_n ? model_hold : 2'd0;
        assign source_owner = rst_n ? owner_hold : 8'd0;
        assign source_token = rst_n ? token_hold : 32'd0;
        assign source_index = !rst_n ? 32'd0 : (external_projection ?
            projection_source_index : (input_norm ? norm_source_index : 32'd0));
        assign source_normalized = rst_n && external_projection;
        assign source_rsp_ready = rst_n && (external_projection ?
            projection_source_rsp_ready : (input_norm && norm_source_rsp_ready));
        assign input_store_valid = EXTERNAL_INPUT_RAM && scratch_norm_write && input_norm;
        assign input_store_index = rst_n && EXTERNAL_INPUT_RAM ? normalized_index : 32'd0;
        assign input_store_data = rst_n && EXTERNAL_INPUT_RAM ? normalized_data : 16'd0;
        assign cmd_valid = rst_n && (memory_owner == MEMORY_LOOKUP ? lookup_cmd_valid :
            (memory_owner == MEMORY_PROJECTION ? projection_cmd_valid : scale_cmd_valid));
        assign cmd_write = 0;
        assign cmd_addr = !rst_n ? 64'd0 :
            (memory_owner == MEMORY_LOOKUP ? lookup_cmd_addr :
                (memory_owner == MEMORY_PROJECTION ? projection_cmd_addr : scale_cmd_addr));
        assign cmd_wdata = 0;
        assign result_ready = rst_n &&
            (memory_owner == MEMORY_LOOKUP ? lookup_result_ready :
                (memory_owner == MEMORY_PROJECTION ? projection_result_ready : scale_result_ready));
        assign done_valid = rst_n && state == RESPONSE;
        assign done_data = rst_n ? output_hold : 32'd0;
        assign done_error = rst_n ? error_hold : 4'd0;
        wire completed_projection = rst_n && state == PROJECTION_WAIT &&
            projection_valid && projection_error == 0;
        assign projection_event = completed_projection && !query_hold;
        assign projection_bytes = rst_n ? 32'd2 : 32'd0;
        assign query_projection_event = completed_projection && query_hold;
        assign query_projection_bytes = rst_n ? 32'd2 : 32'd0;

        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                src_state <= SRC_IDLE;
                src_is_head <= 0;
                src_is_projection <= 0;
                src_index_hold <= 0;
                src_data_hold <= 0;
            end else begin
                case (src_state)
                    SRC_IDLE: begin
                        if (!EXTERNAL_INPUT_RAM &&
                            state == PROJECTION_WAIT && projection_source_valid) begin
                            src_index_hold <= projection_source_index;
                            src_is_head <= 0;
                            src_is_projection <= 1;
                            src_state <= SRC_READ;
                        end else if (state == NORM_WAIT && !input_norm &&
                            norm_source_valid) begin
                            src_index_hold <= norm_source_index;
                            src_is_head <= 1;
                            src_is_projection <= 0;
                            src_state <= SRC_READ;
                        end
                    end
                    SRC_READ: src_state <= SRC_PUBLISH;
                    SRC_PUBLISH: begin
                        src_data_hold <= src_is_head ? head_q : input_q;
                        src_state <= SRC_RESPONSE;
                    end
                    SRC_RESPONSE: if (src_is_projection ?
                        projection_source_rsp_ready : norm_source_rsp_ready)
                        src_state <= SRC_IDLE;
                    default: src_state <= SRC_IDLE;
                endcase
            end
        end
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                scale_state <= SCALE_IDLE;
                scale_index_hold <= 0;
                scale_data_hold <= 0;
                scale_error_hold <= 0;
            end else begin
                case (scale_state)
                    SCALE_IDLE: if (state == NORM_WAIT && norm_scale_valid) begin
                        scale_index_hold <= norm_scale_index;
                        scale_error_hold <= 0;
                        scale_state <= SCALE_START;
                    end
                    SCALE_START: if (scale_ready)
                        scale_state <= SCALE_WAIT;
                    SCALE_WAIT: if (scale_valid) begin
                        scale_data_hold <= scale_data[31:16];
                        scale_error_hold <= scale_error != 0;
                        scale_state <= SCALE_PUBLISH;
                    end
                    SCALE_PUBLISH: scale_state <= SCALE_RESPONSE;
                    SCALE_RESPONSE: if (norm_scale_rsp_ready)
                        scale_state <= SCALE_IDLE;
                    default: scale_state <= SCALE_IDLE;
                endcase
            end
        end
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                state <= IDLE;
                model_hold <= 0;
                precision_hold <= 0;
                head_hold <= 0;
                memory_owner <= 0;
                owner_hold <= 0;
                token_hold <= 0;
                hidden_hold <= 0;
                dimension_hold <= 0;
                heads_hold <= 0;
                weights_hold <= 0;
                component_hold <= 0;
                current_component <= 0;
                pair_base <= 0;
                selector_hold <= 0;
                query_hold <= 0;
                global_hold <= 0;
                input_norm <= 0;
                second_component <= 0;
                projection_index <= 0;
                first_source <= 0;
                second_source <= 0;
                first_output <= 0;
                component_output <= 0;
                lookup_kind <= 0;
                descriptor_base <= 0;
                descriptor_bytes <= 0;
                descriptor_rows <= 0;
                descriptor_columns <= 0;
                descriptor_stride <= 0;
                scale_base <= 0;
                scale_bytes <= 0;
                scale_columns <= 0;
                scale_stride <= 0;
                projection_data_hold <= 0;
                output_hold <= 0;
                error_hold <= 0;
            end else begin
                case (state)
                    IDLE: if (start_valid && start_ready) begin
                        model_hold <= model;
                        precision_hold <= precision;
                        head_hold <= ALLOW_QUERY && is_query ? query_head : {2'd0, kv_head};
                        owner_hold <= owner;
                        token_hold <= token;
                        weights_hold <= weights_base;
                        component_hold <= component;
                        selector_hold <= is_value;
                        query_hold <= ALLOW_QUERY && is_query;
                        input_norm <= 1;
                        second_component <= 0;
                        projection_index <= 0;
                        output_hold <= 0;
                        error_hold <= 0;
                        state <= VALIDATE;
                    end
                    VALIDATE: begin
                        hidden_hold <= COMPACT ? 32'd8 : {20'd0, selected_hidden};
                        dimension_hold <= COMPACT ?
                            (selected_global ? 32'd8 : 32'd4) :
                            (selected_global ? 32'd512 : 32'd256);
                        heads_hold <= query_hold ? (COMPACT ? 32'd2 : 32'd8) :
                            (COMPACT || model_hold == 1 ? 32'd1 : 32'd2);
                        global_hold <= selected_global;
                        if (!native_owner || precision_hold > 1) begin
                            error_hold <= 6;
                            state <= PUBLISH;
                        end else if (owner_hold >= (query_hold ?
                            selected_layer_count : selected_owner_count)) begin
                            error_hold <= 7;
                            state <= PUBLISH;
                        end else if (token_hold > 131071 || component_hold[0] ||
                            component_hold >= (COMPACT ?
                                (selected_global ? 10'd8 : 10'd4) :
                                (selected_global ? 10'd512 : 10'd256)) ||
                            (query_hold && selector_hold) ||
                            head_hold >= (query_hold ? (COMPACT ? 4'd2 : 4'd8) :
                                (COMPACT || model_hold == 1 ? 4'd1 : 4'd2))) begin
                            error_hold <= 5;
                            state <= PUBLISH;
                        end else begin
                            lookup_kind <= 16'h0100;
                            memory_owner <= MEMORY_LOOKUP;
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
                            descriptor_base <= lookup_base;
                            descriptor_bytes <= lookup_bytes;
                            descriptor_rows <= lookup_rows;
                            descriptor_columns <= lookup_columns;
                            descriptor_stride <= lookup_stride;
                            state <= LOOKUP_FINISH;
                        end
                    end
                    LOOKUP_FINISH: begin
                        if (lookup_kind == 16'h0100 || lookup_kind == 16'h0102 ||
                            lookup_kind == 16'h0104) begin
                            scale_base <= descriptor_base;
                            scale_bytes <= descriptor_bytes;
                            scale_columns <= descriptor_columns;
                            scale_stride <= descriptor_stride;
                            memory_owner <= MEMORY_SCALE;
                            state <= NORM_START;
                        end else if (descriptor_rows != heads_hold * dimension_hold ||
                            descriptor_columns != hidden_hold) begin
                            error_hold <= 5;
                            state <= PUBLISH;
                        end else begin
                            memory_owner <= MEMORY_PROJECTION;
                            projection_index <= 0;
                            state <= PROJECTION_START;
                        end
                    end
                    NORM_START: if (norm_ready)
                        state <= NORM_WAIT;
                    NORM_WAIT: if (norm_valid) begin
                        if (norm_error != 0) begin
                            error_hold <= norm_error;
                            state <= PUBLISH;
                        end else
                            state <= NORM_FINISH;
                    end
                    NORM_FINISH: begin
                        if (input_norm) begin
                            input_norm <= 0;
                            lookup_kind <= query_hold ? 16'h0101 :
                                (selector_hold ? 16'h0105 : 16'h0103);
                            memory_owner <= MEMORY_LOOKUP;
                            state <= LOOKUP_START;
                        end else begin
                            current_component <= component_hold;
                            second_component <= 0;
                            state <= PAIR_SETUP;
                        end
                    end
                    PROJECTION_START: if (projection_ready)
                        state <= PROJECTION_WAIT;
                    PROJECTION_WAIT: if (projection_valid) begin
                        if (projection_error != 0) begin
                            error_hold <= projection_error;
                            state <= PUBLISH;
                        end else begin
                            projection_data_hold <= projection_data[15:0];
                            state <= PROJECTION_ADVANCE;
                        end
                    end
                    PROJECTION_ADVANCE: begin
                        if (projection_index == dimension_hold - 1'b1) begin
                            if (selector_hold) begin
                                memory_owner <= MEMORY_SCALE;
                                state <= NORM_START;
                            end else begin
                                lookup_kind <= query_hold ? 16'h0102 : 16'h0104;
                                memory_owner <= MEMORY_LOOKUP;
                                state <= LOOKUP_START;
                            end
                        end else begin
                            projection_index <= projection_index + 1'b1;
                            state <= PROJECTION_START;
                        end
                    end
                    PAIR_SETUP: begin
                        pair_base <= current_component &
                            ((dimension_hold[9:0] >> 1) - 1'b1);
                        state <= PAIR_FIRST_READ;
                    end
                    PAIR_FIRST_READ: state <= PAIR_FIRST_CAPTURE;
                    PAIR_FIRST_CAPTURE: begin
                        first_source <= head_q;
                        state <= PAIR_SECOND_READ;
                    end
                    PAIR_SECOND_READ: state <= PAIR_SECOND_CAPTURE;
                    PAIR_SECOND_CAPTURE: begin
                        second_source <= head_q;
                        if (selector_hold) begin
                            output_hold <= {head_q, first_source};
                            state <= PUBLISH;
                        end else
                            state <= ROTARY_START;
                    end
                    ROTARY_START: if (rotary_ready)
                        state <= ROTARY_WAIT;
                    ROTARY_WAIT: if (rotary_valid) begin
                        if (rotary_error != 0) begin
                            error_hold <= rotary_error;
                            output_hold <= 0;
                            state <= PUBLISH;
                        end else begin
                            component_output <= {22'd0, current_component} <
                                (dimension_hold >> 1) ? rotary_data[15:0] : rotary_data[31:16];
                            state <= PAIR_ADVANCE;
                        end
                    end
                    PAIR_ADVANCE: begin
                        if (second_component) begin
                            output_hold <= {component_output, first_output};
                            state <= PUBLISH;
                        end else begin
                            first_output <= component_output;
                            second_component <= 1;
                            current_component <= component_hold + 1'b1;
                            state <= PAIR_SETUP;
                        end
                    end
                    PUBLISH: state <= RESPONSE;
                    RESPONSE: if (done_ready)
                        state <= IDLE;
                    default: begin
                        output_hold <= 0;
                        error_hold <= 7;
                        state <= PUBLISH;
                    end
                endcase
            end
        end
    end endgenerate
endmodule
