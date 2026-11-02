module anvil_en1_embedding_ple #(
    parameter integer COMPACT = 0
) (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] model, precision, modality,
    input wire [7:0] layer,
    input wire [31:0] token,
    input wire [63:0] tokens_base, weights_base,
    output wire modality_valid,
    input wire modality_ready,
    output wire [1:0] modality_model, modality_kind,
    output wire [31:0] modality_token, modality_index,
    input wire modality_rsp_valid,
    output wire modality_rsp_ready,
    input wire [15:0] modality_rsp_data,
    input wire modality_rsp_error,
    output wire input_valid,
    input wire input_ready,
    output wire [31:0] input_index,
    output wire [15:0] input_data,
    output wire input_last,
    output wire ple_valid,
    input wire ple_ready,
    output wire [31:0] ple_index,
    output wire [15:0] ple_data,
    output wire ple_last,
    output wire cmd_valid,
    input wire cmd_ready,
    output wire cmd_write,
    output wire input_read_event,
    output wire [63:0] cmd_addr,
    output wire [31:0] cmd_wdata,
    input wire result_valid,
    output wire result_ready,
    input wire [31:0] result_data,
    input wire result_error,
    output wire done_valid,
    input wire done_ready,
    output wire [3:0] done_error,
    output wire [63:0] live_payload_bytes, physical_payload_bytes,
    output wire [63:0] controller_bytes
);
    generate if (COMPACT != 0 && COMPACT != 1) begin : invalid_parameters
        initial $fatal(1, "PARAMETER ERROR: COMPACT must be 0 or 1");
        assign start_ready = 0;
        assign modality_valid = 0;
        assign modality_model = 0;
        assign modality_kind = 0;
        assign modality_token = 0;
        assign modality_index = 0;
        assign modality_rsp_ready = 0;
        assign input_valid = 0;
        assign input_index = 0;
        assign input_data = 0;
        assign input_last = 0;
        assign ple_valid = 0;
        assign ple_index = 0;
        assign ple_data = 0;
        assign ple_last = 0;
        assign cmd_valid = 0;
        assign cmd_write = 0;
        assign input_read_event = 0;
        assign cmd_addr = 0;
        assign cmd_wdata = 0;
        assign result_ready = 0;
        assign done_valid = 0;
        assign done_error = 0;
        assign live_payload_bytes = 0;
        assign physical_payload_bytes = 0;
        assign controller_bytes = 0;
    end else begin : frontend
        localparam integer MAX_H = COMPACT ? 8 : 2560;
        localparam integer P = COMPACT ? 4 : 256;
        localparam integer H_BITS = $clog2(MAX_H);
        localparam integer P_BITS = $clog2(P);
        localparam [5:0] IDLE = 0, VALIDATE = 1, TOKEN_ADDRESS = 2,
            TOKEN_COMMAND = 3, TOKEN_WAIT = 4, TOKEN_CHECK = 5,
            ROOT_START = 6, ROOT_WAIT = 7, ROOT_NARROW = 8,
            ROOT_SAVE = 9, LOOKUP_START = 10, LOOKUP_WAIT = 11,
            LOOKUP_FINISH = 12, WEIGHT_START = 13, WEIGHT_WAIT = 14,
            EMBED_MULTIPLY = 15, EMBED_NARROW = 16, EMBED_WRITE = 17,
            FEATURE_START = 18, FEATURE_WAIT = 19, FEATURE_REGISTER = 20,
            PROJECTION_START = 21, PROJECTION_WAIT = 22,
            CONTEXT_SCALE = 23, CONTEXT_NARROW = 24, CONTEXT_WRITE = 25,
            NORM_START = 26, NORM_WAIT = 27, IDENTITY_MULTIPLY = 28,
            IDENTITY_NARROW = 29, COMBINE_READ = 30, COMBINE_ADD = 31,
            COMBINE_NARROW = 32, COMBINE_SCALE = 33,
            COMBINE_FINAL_NARROW = 34, COMBINE_WRITE = 35,
            INPUT_READ = 36, INPUT_CAPTURE = 37, INPUT_OUTPUT = 38,
            PLE_READ = 39, PLE_CAPTURE = 40, PLE_OUTPUT = 41,
            FP_START = 42, FP_WAIT = 43, PUBLISH = 44, RESPONSE = 45;
        localparam [2:0] SRC_IDLE = 0, SRC_READ = 1,
            SRC_PUBLISH = 2, SRC_RESPONSE = 3;
        localparam [2:0] SCALE_IDLE = 0, SCALE_START = 1,
            SCALE_WAIT = 2, SCALE_PUBLISH = 3, SCALE_RESPONSE = 4;
        localparam [1:0] MEMORY_TOKEN = 0, MEMORY_LOOKUP = 1,
            MEMORY_WEIGHT = 2, MEMORY_PROJECTION = 3;
        reg [5:0] state, return_state;
        reg [2:0] src_state, scale_state;
        reg [1:0] model_hold, precision_hold, modality_hold, memory_owner;
        reg [7:0] layer_hold;
        reg [31:0] token_hold, token_id, hidden_hold, vocabulary_hold;
        reg [63:0] tokens_hold, weights_hold, token_address_hold;
        reg [31:0] index, value_hold, fp_a, fp_b, hidden_float, root_data_hold;
        reg [15:0] hidden_scale, inverse_hidden_scale, output_hold, feature_hold;
        reg root_inverse, token_error_hold, feature_error_hold, weight_is_identity;
        reg src_is_ple, src_is_projection;
        reg [31:0] src_index_hold, scale_index_hold;
        reg [15:0] src_data_hold, scale_data_hold;
        reg scale_error_hold;
        reg [15:0] lookup_kind;
        reg [63:0] descriptor_base, descriptor_bytes;
        reg [31:0] descriptor_rows, descriptor_columns, descriptor_stride;
        reg [2:0] fp_op;
        reg [3:0] error_hold;
        reg payload_allocated;
        reg [15:0] input_q, ple_q;
        localparam integer CONTROLLER_BITS = $bits({
            state, return_state, src_state, scale_state, model_hold, precision_hold,
            modality_hold, memory_owner, layer_hold, token_hold, token_id,
            hidden_hold, vocabulary_hold, tokens_hold, weights_hold, token_address_hold,
            index, value_hold, fp_a, fp_b, hidden_float, root_data_hold, hidden_scale,
            inverse_hidden_scale, output_hold, feature_hold, root_inverse,
            token_error_hold, feature_error_hold, weight_is_identity, src_is_ple,
            src_is_projection, src_index_hold, scale_index_hold, src_data_hold,
            scale_data_hold, scale_error_hold, lookup_kind, descriptor_base,
            descriptor_bytes, descriptor_rows, descriptor_columns, descriptor_stride,
            fp_op, error_hold, payload_allocated, input_q, ple_q
        });
        wire [63:0] lookup_controller_bytes, weight_controller_bytes;
        wire [63:0] projection_controller_bytes, norm_controller_bytes;
        wire [63:0] div_controller_bytes, fp_controller_bytes;
        assign controller_bytes = !rst_n ? 64'd0 :
            64'((CONTROLLER_BITS+7) >> 3) + lookup_controller_bytes +
            weight_controller_bytes + projection_controller_bytes +
            norm_controller_bytes + div_controller_bytes + fp_controller_bytes;
        (* ramstyle = "M20K", nomem2reg *)
        reg [15:0] input_payload [0:MAX_H-1];
        (* ramstyle = "M20K", nomem2reg *)
        reg [15:0] ple_payload [0:P-1];

        wire native_model;
        wire [7:0] layer_count;
        wire [11:0] geometry_hidden;
        anvil_en1_geometry geometry (
            .rst_n(rst_n), .model(model_hold), .layer(layer_hold),
            .is_native(native_model), .layers(layer_count), .owners(), .owner(),
            .is_global(), .hidden(geometry_hidden), .intermediate()
        );
        wire [64:0] token_address_sum = {1'b0, tokens_hold} + {31'd0, token_hold, 2'd0};
        wire [64:0] token_address_end = token_address_sum + 65'd4;
        wire [31:0] image_id = COMPACT ? 32'd28 : 32'd258880;
        wire [31:0] audio_id = COMPACT ? 32'd29 : 32'd258881;
        wire [31:0] identity_id = modality_hold == 0 ? token_id : 32'd0;
        wire [31:0] layer_slice = {24'd0, layer_hold} << (COMPACT ? 2 : 8);

        wire lookup_ready, lookup_valid, lookup_cmd_valid, lookup_result_ready;
        wire [63:0] lookup_base, lookup_bytes, lookup_cmd_addr;
        wire [31:0] lookup_rows, lookup_columns, lookup_stride;
        wire [3:0] lookup_error;
        anvil_en1_tensor_image #(.COMPACT(COMPACT)) tensor_lookup (
            .controller_bytes(lookup_controller_bytes),
            .clk(clk), .rst_n(rst_n),
            .start_valid(rst_n && state == LOOKUP_START), .start_ready(lookup_ready),
            .model(model_hold), .precision(precision_hold), .image_class(2'd0),
            .input_audio(1'b0), .input_items(32'd0), .image_base(weights_hold),
            .tensor_kind(lookup_kind), .tensor_layer(16'hffff),
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
        wire weight_ready, weight_valid, weight_cmd_valid, weight_result_ready;
        wire [63:0] weight_cmd_addr;
        wire [31:0] weight_data;
        wire [3:0] weight_error;
        wire norm_weight = state == NORM_WAIT;
        wire [31:0] weight_row = norm_weight ? 32'd0 :
            (weight_is_identity ? identity_id : token_id);
        wire [31:0] weight_column = norm_weight ? scale_index_hold :
            (weight_is_identity ? layer_slice + index : index);
        anvil_en1_weight_read weight_reader (
            .controller_bytes(weight_controller_bytes),
            .clk(clk), .rst_n(rst_n),
            .start_valid(rst_n && (state == WEIGHT_START || scale_state == SCALE_START)),
            .start_ready(weight_ready), .precision(norm_weight ? 2'd0 : precision_hold),
            .tensor_base(descriptor_base), .tensor_bytes(descriptor_bytes),
            .tensor_rows(descriptor_rows), .tensor_columns(descriptor_columns),
            .row_stride(descriptor_stride), .row_index(weight_row), .column_index(weight_column),
            .cmd_valid(weight_cmd_valid),
            .cmd_ready(rst_n && memory_owner == MEMORY_WEIGHT && cmd_ready),
            .cmd_write(), .cmd_addr(weight_cmd_addr), .cmd_wdata(),
            .result_valid(rst_n && memory_owner == MEMORY_WEIGHT && result_valid),
            .result_ready(weight_result_ready), .result_data(result_data),
            .result_error(result_error),
            .done_valid(weight_valid),
            .done_ready(rst_n && (state == WEIGHT_WAIT || scale_state == SCALE_WAIT)),
            .done_data(weight_data), .done_error(weight_error)
        );
        wire projection_ready, projection_valid, projection_cmd_valid, projection_result_ready;
        wire projection_source_valid, projection_source_rsp_ready;
        wire [31:0] projection_source_index, projection_data;
        wire [63:0] projection_cmd_addr;
        wire [3:0] projection_error;
        anvil_en1_projection projection_unit (
            .controller_bytes(projection_controller_bytes),
            .clk(clk), .rst_n(rst_n),
            .start_valid(rst_n && state == PROJECTION_START), .start_ready(projection_ready),
            .precision(precision_hold), .tensor_base(descriptor_base),
            .tensor_bytes(descriptor_bytes), .tensor_rows(descriptor_rows),
            .tensor_columns(descriptor_columns), .row_stride(descriptor_stride),
            .row_index(layer_slice + index),
            .source_valid(projection_source_valid),
            .source_ready(rst_n && src_state == SRC_IDLE && state == PROJECTION_WAIT),
            .source_index(projection_source_index),
            .source_rsp_valid(rst_n && src_state == SRC_RESPONSE && src_is_projection),
            .source_rsp_ready(projection_source_rsp_ready), .source_rsp_data(src_data_hold),
            .source_rsp_error(1'b0),
            .cmd_valid(projection_cmd_valid),
            .cmd_ready(rst_n && memory_owner == MEMORY_PROJECTION && cmd_ready),
            .cmd_write(), .cmd_addr(projection_cmd_addr), .cmd_wdata(),
            .result_valid(rst_n && memory_owner == MEMORY_PROJECTION && result_valid),
            .result_ready(projection_result_ready), .result_data(result_data),
            .result_error(result_error),
            .done_valid(projection_valid), .done_ready(rst_n && state == PROJECTION_WAIT),
            .done_data(projection_data), .done_error(projection_error)
        );
        wire norm_ready, norm_valid, norm_source_valid, norm_source_rsp_ready;
        wire [31:0] norm_source_index, norm_scale_index, normalized_index;
        wire norm_scale_valid, norm_scale_rsp_ready, normalized_valid;
        wire [15:0] normalized_data;
        wire [3:0] norm_error;
        anvil_en1_norm norm_unit (
            .controller_bytes(norm_controller_bytes),
            .clk(clk), .rst_n(rst_n),
            .start_valid(rst_n && state == NORM_START), .start_ready(norm_ready),
            .layer_norm(1'b0), .learned_scale(1'b1), .vector_length(32'(P)),
            .epsilon(32'h358637bd),
            .source_valid(norm_source_valid),
            .source_ready(rst_n && src_state == SRC_IDLE && state == NORM_WAIT),
            .source_index(norm_source_index),
            .source_rsp_valid(rst_n && src_state == SRC_RESPONSE && !src_is_projection),
            .source_rsp_ready(norm_source_rsp_ready), .source_rsp_data(src_data_hold),
            .source_rsp_error(1'b0),
            .scale_valid(norm_scale_valid),
            .scale_ready(rst_n && scale_state == SCALE_IDLE && state == NORM_WAIT),
            .scale_index(norm_scale_index),
            .scale_rsp_valid(rst_n && scale_state == SCALE_RESPONSE),
            .scale_rsp_ready(norm_scale_rsp_ready), .scale_rsp_data(scale_data_hold),
            .scale_rsp_error(scale_error_hold),
            .normalized_valid(normalized_valid),
            .normalized_ready(rst_n && state == NORM_WAIT),
            .normalized_index(normalized_index), .normalized_data(normalized_data),
            .normalized_last(),
            .done_valid(norm_valid), .done_ready(rst_n && state == NORM_WAIT),
            .done_error(norm_error)
        );
        wire root_ready, root_valid, fp_ready, fp_valid;
        wire [31:0] root_data, fp_data;
        wire [3:0] root_error, fp_error;
        anvil_en1_fp32_divsqrt root_unit (
            .controller_bytes(div_controller_bytes),
            .clk(clk), .rst_n(rst_n),
            .start_valid(rst_n && state == ROOT_START), .start_ready(root_ready),
            .operation(root_inverse ? 2'd2 : 2'd1),
            .operand_a(hidden_float), .operand_b(32'd0),
            .done_valid(root_valid), .done_ready(rst_n && state == ROOT_WAIT),
            .done_data(root_data), .done_error(root_error)
        );
        anvil_en1_fp32 fp_unit (
            .controller_bytes(fp_controller_bytes),
            .clk(clk), .rst_n(rst_n),
            .start_valid(rst_n && state == FP_START), .start_ready(fp_ready),
            .operation(fp_op), .operand_a(fp_a), .operand_b(fp_b),
            .done_valid(fp_valid), .done_ready(rst_n && state == FP_WAIT),
            .done_data(fp_data), .done_error(fp_error)
        );

        wire input_write = rst_n && state == EMBED_WRITE;
        wire context_write = rst_n && state == CONTEXT_WRITE;
        wire combine_write = rst_n && state == COMBINE_WRITE;
        wire norm_write = rst_n && state == NORM_WAIT && normalized_valid;
        wire input_read = rst_n && ((src_state == SRC_READ && !src_is_ple) ||
            state == INPUT_READ);
        wire ple_read = rst_n && ((src_state == SRC_READ && src_is_ple) ||
            state == COMBINE_READ || state == PLE_READ);
        wire [31:0] input_read_index = src_state == SRC_READ ? src_index_hold : index;
        wire [31:0] ple_read_index = src_state == SRC_READ ? src_index_hold : index;
        always @(posedge clk) begin
            if (input_write)
                input_payload[index[H_BITS-1:0]] <= value_hold[15:0];
            if (norm_write)
                ple_payload[normalized_index[P_BITS-1:0]] <= normalized_data;
            else if (context_write || combine_write)
                ple_payload[index[P_BITS-1:0]] <= value_hold[15:0];
            if (input_read)
                input_q <= input_payload[input_read_index[H_BITS-1:0]];
            if (ple_read)
                ple_q <= ple_payload[ple_read_index[P_BITS-1:0]];
        end

        assign start_ready = rst_n && state == IDLE;
        assign modality_valid = rst_n && state == FEATURE_START;
        assign modality_model = rst_n ? model_hold : 2'd0;
        assign modality_kind = rst_n ? modality_hold : 2'd0;
        assign modality_token = rst_n ? token_hold : 32'd0;
        assign modality_index = rst_n ? index : 32'd0;
        assign modality_rsp_ready = rst_n && state == FEATURE_WAIT;
        assign input_valid = rst_n && state == INPUT_OUTPUT;
        assign input_index = rst_n ? index : 32'd0;
        assign input_data = rst_n ? output_hold : 16'd0;
        assign input_last = rst_n && state == INPUT_OUTPUT && index == hidden_hold - 1'b1;
        assign ple_valid = rst_n && state == PLE_OUTPUT;
        assign ple_index = rst_n ? index : 32'd0;
        assign ple_data = rst_n ? output_hold : 16'd0;
        assign ple_last = rst_n && state == PLE_OUTPUT && index == P - 1;
        assign cmd_valid = rst_n && (memory_owner == MEMORY_TOKEN ? state == TOKEN_COMMAND :
            (memory_owner == MEMORY_LOOKUP ? lookup_cmd_valid :
                (memory_owner == MEMORY_WEIGHT ? weight_cmd_valid : projection_cmd_valid)));
        assign cmd_write = 0;
        assign input_read_event = rst_n && memory_owner == MEMORY_TOKEN &&
            state == TOKEN_COMMAND && cmd_ready;
        assign cmd_addr = !rst_n ? 64'd0 :
            (memory_owner == MEMORY_TOKEN ? token_address_hold :
                (memory_owner == MEMORY_LOOKUP ? lookup_cmd_addr :
                    (memory_owner == MEMORY_WEIGHT ? weight_cmd_addr : projection_cmd_addr)));
        assign cmd_wdata = 0;
        assign result_ready = rst_n && (memory_owner == MEMORY_TOKEN ? state == TOKEN_WAIT :
            (memory_owner == MEMORY_LOOKUP ? lookup_result_ready :
                (memory_owner == MEMORY_WEIGHT ? weight_result_ready : projection_result_ready)));
        assign done_valid = rst_n && state == RESPONSE;
        assign done_error = rst_n ? error_hold : 4'd0;
        assign live_payload_bytes = rst_n && payload_allocated ?
            ({32'd0, hidden_hold} << 1) + 64'(2*P) : 64'd0;
        assign physical_payload_bytes = rst_n ? 64'(2*(MAX_H+P)) : 64'd0;

        always @(posedge clk or negedge rst_n) begin
            if (!rst_n)
                payload_allocated <= 0;
            else if (done_valid && done_ready)
                payload_allocated <= 0;
            else if (state == VALIDATE && native_model && precision_hold <= 1 &&
                modality_hold != 3 && layer_hold < layer_count &&
                token_hold <= 131071 && tokens_hold[1:0] == 0)
                payload_allocated <= 1;
        end

        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                src_state <= SRC_IDLE;
                src_is_ple <= 0;
                src_is_projection <= 0;
                src_index_hold <= 0;
                src_data_hold <= 0;
            end else begin
                case (src_state)
                    SRC_IDLE: begin
                        if (state == PROJECTION_WAIT && projection_source_valid) begin
                            src_index_hold <= projection_source_index;
                            src_is_ple <= 0;
                            src_is_projection <= 1;
                            src_state <= SRC_READ;
                        end else if (state == NORM_WAIT && norm_source_valid) begin
                            src_index_hold <= norm_source_index;
                            src_is_ple <= 1;
                            src_is_projection <= 0;
                            src_state <= SRC_READ;
                        end
                    end
                    SRC_READ: src_state <= SRC_PUBLISH;
                    SRC_PUBLISH: begin
                        src_data_hold <= src_is_ple ? ple_q : input_q;
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
                    SCALE_START: if (weight_ready)
                        scale_state <= SCALE_WAIT;
                    SCALE_WAIT: if (weight_valid) begin
                        scale_data_hold <= weight_data[31:16];
                        scale_error_hold <= weight_error != 0;
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
                return_state <= 0;
                model_hold <= 0;
                precision_hold <= 0;
                modality_hold <= 0;
                memory_owner <= 0;
                layer_hold <= 0;
                token_hold <= 0;
                token_id <= 0;
                hidden_hold <= 0;
                vocabulary_hold <= 0;
                tokens_hold <= 0;
                weights_hold <= 0;
                token_address_hold <= 0;
                index <= 0;
                value_hold <= 0;
                fp_a <= 0;
                fp_b <= 0;
                hidden_float <= 0;
                root_data_hold <= 0;
                hidden_scale <= 0;
                inverse_hidden_scale <= 0;
                output_hold <= 0;
                feature_hold <= 0;
                root_inverse <= 0;
                token_error_hold <= 0;
                feature_error_hold <= 0;
                weight_is_identity <= 0;
                lookup_kind <= 0;
                descriptor_base <= 0;
                descriptor_bytes <= 0;
                descriptor_rows <= 0;
                descriptor_columns <= 0;
                descriptor_stride <= 0;
                fp_op <= 0;
                error_hold <= 0;
            end else begin
                case (state)
                    IDLE: if (start_valid && start_ready) begin
                        model_hold <= model;
                        precision_hold <= precision;
                        modality_hold <= modality;
                        layer_hold <= layer;
                        token_hold <= token;
                        tokens_hold <= tokens_base;
                        weights_hold <= weights_base;
                        index <= 0;
                        root_inverse <= 0;
                        weight_is_identity <= 0;
                        output_hold <= 0;
                        error_hold <= 0;
                        state <= VALIDATE;
                    end
                    VALIDATE: begin
                        hidden_hold <= COMPACT ? 32'd8 : {20'd0, geometry_hidden};
                        vocabulary_hold <= COMPACT ? 32'd32 : 32'd262144;
                        hidden_float <= COMPACT ? 32'h41000000 :
                            (model_hold == 1 ? 32'h44c00000 : 32'h45200000);
                        if (!native_model || precision_hold > 1 || modality_hold == 3) begin
                            error_hold <= 6;
                            state <= PUBLISH;
                        end else if (layer_hold >= layer_count || token_hold > 131071 ||
                            tokens_hold[1:0] != 0) begin
                            error_hold <= 5;
                            state <= PUBLISH;
                        end else
                            state <= TOKEN_ADDRESS;
                    end
                    TOKEN_ADDRESS: begin
                        if (token_address_sum[64] || token_address_end[64]) begin
                            error_hold <= 5;
                            state <= PUBLISH;
                        end else begin
                            token_address_hold <= token_address_sum[63:0];
                            memory_owner <= MEMORY_TOKEN;
                            state <= TOKEN_COMMAND;
                        end
                    end
                    TOKEN_COMMAND: if (cmd_ready)
                        state <= TOKEN_WAIT;
                    TOKEN_WAIT: if (result_valid && result_ready) begin
                        token_id <= result_data;
                        token_error_hold <= result_error;
                        state <= TOKEN_CHECK;
                    end
                    TOKEN_CHECK: begin
                        if (token_error_hold) begin
                            error_hold <= 2;
                            state <= PUBLISH;
                        end else if (token_id >= vocabulary_hold) begin
                            error_hold <= 5;
                            state <= PUBLISH;
                        end else if ((modality_hold == 1 && token_id != image_id) ||
                            (modality_hold == 2 && token_id != audio_id) ||
                            (modality_hold == 0 && (token_id == image_id || token_id == audio_id))) begin
                            error_hold <= 7;
                            state <= PUBLISH;
                        end else
                            state <= ROOT_START;
                    end
                    ROOT_START: if (root_ready)
                        state <= ROOT_WAIT;
                    ROOT_WAIT: if (root_valid) begin
                        if (root_error != 0) begin
                            error_hold <= root_error;
                            state <= PUBLISH;
                        end else begin
                            root_data_hold <= root_data;
                            state <= ROOT_NARROW;
                        end
                    end
                    ROOT_NARROW: begin
                        fp_op <= 3;
                        fp_a <= root_data_hold;
                        fp_b <= 0;
                        return_state <= ROOT_SAVE;
                        state <= FP_START;
                    end
                    ROOT_SAVE: begin
                        if (!root_inverse) begin
                            hidden_scale <= value_hold[15:0];
                            root_inverse <= 1;
                            state <= ROOT_START;
                        end else begin
                            inverse_hidden_scale <= value_hold[15:0];
                            if (modality_hold != 0)
                                state <= FEATURE_START;
                            else begin
                                lookup_kind <= 16'h0000;
                                memory_owner <= MEMORY_LOOKUP;
                                state <= LOOKUP_START;
                            end
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
                        index <= 0;
                        case (lookup_kind)
                            16'h0000: begin
                                weight_is_identity <= 0;
                                memory_owner <= MEMORY_WEIGHT;
                                state <= WEIGHT_START;
                            end
                            16'h0001: begin
                                weight_is_identity <= 1;
                                memory_owner <= MEMORY_WEIGHT;
                                state <= WEIGHT_START;
                            end
                            16'h0002: begin
                                memory_owner <= MEMORY_PROJECTION;
                                state <= PROJECTION_START;
                            end
                            16'h0003: begin
                                memory_owner <= MEMORY_WEIGHT;
                                state <= NORM_START;
                            end
                            default: begin
                                error_hold <= 7;
                                state <= PUBLISH;
                            end
                        endcase
                    end
                    WEIGHT_START: if (weight_ready)
                        state <= WEIGHT_WAIT;
                    WEIGHT_WAIT: if (weight_valid) begin
                        if (weight_error != 0) begin
                            error_hold <= weight_error;
                            state <= PUBLISH;
                        end else begin
                            value_hold <= weight_data;
                            if (weight_is_identity)
                                state <= IDENTITY_MULTIPLY;
                            else
                                state <= EMBED_MULTIPLY;
                        end
                    end
                    EMBED_MULTIPLY: begin
                        fp_op <= 1;
                        fp_a <= value_hold;
                        fp_b <= {hidden_scale, 16'd0};
                        return_state <= EMBED_NARROW;
                        state <= FP_START;
                    end
                    EMBED_NARROW: begin
                        fp_op <= 3;
                        fp_a <= value_hold;
                        fp_b <= 0;
                        return_state <= EMBED_WRITE;
                        state <= FP_START;
                    end
                    EMBED_WRITE: begin
                        if (index == hidden_hold - 1'b1) begin
                            lookup_kind <= 16'h0002;
                            memory_owner <= MEMORY_LOOKUP;
                            state <= LOOKUP_START;
                        end else begin
                            index <= index + 1'b1;
                            if (modality_hold != 0)
                                state <= FEATURE_START;
                            else
                                state <= WEIGHT_START;
                        end
                    end
                    FEATURE_START: if (modality_ready)
                        state <= FEATURE_WAIT;
                    FEATURE_WAIT: if (modality_rsp_valid && modality_rsp_ready) begin
                        feature_hold <= modality_rsp_data;
                        feature_error_hold <= modality_rsp_error;
                        state <= FEATURE_REGISTER;
                    end
                    FEATURE_REGISTER: begin
                        if (feature_error_hold) begin
                            error_hold <= 7;
                            state <= PUBLISH;
                        end else begin
                            value_hold <= {16'd0, feature_hold};
                            state <= EMBED_WRITE;
                        end
                    end
                    PROJECTION_START: if (projection_ready)
                        state <= PROJECTION_WAIT;
                    PROJECTION_WAIT: if (projection_valid) begin
                        if (projection_error != 0) begin
                            error_hold <= projection_error;
                            state <= PUBLISH;
                        end else begin
                            value_hold <= projection_data;
                            state <= CONTEXT_SCALE;
                        end
                    end
                    CONTEXT_SCALE: begin
                        fp_op <= 1;
                        fp_a <= {value_hold[15:0], 16'd0};
                        fp_b <= {inverse_hidden_scale, 16'd0};
                        return_state <= CONTEXT_NARROW;
                        state <= FP_START;
                    end
                    CONTEXT_NARROW: begin
                        fp_op <= 3;
                        fp_a <= value_hold;
                        fp_b <= 0;
                        return_state <= CONTEXT_WRITE;
                        state <= FP_START;
                    end
                    CONTEXT_WRITE: begin
                        if (index == P - 1) begin
                            lookup_kind <= 16'h0003;
                            memory_owner <= MEMORY_LOOKUP;
                            state <= LOOKUP_START;
                        end else begin
                            index <= index + 1'b1;
                            state <= PROJECTION_START;
                        end
                    end
                    NORM_START: if (norm_ready)
                        state <= NORM_WAIT;
                    NORM_WAIT: if (norm_valid) begin
                        if (norm_error != 0) begin
                            error_hold <= norm_error;
                            state <= PUBLISH;
                        end else begin
                            lookup_kind <= 16'h0001;
                            memory_owner <= MEMORY_LOOKUP;
                            state <= LOOKUP_START;
                        end
                    end
                    IDENTITY_MULTIPLY: begin
                        fp_op <= 1;
                        fp_a <= value_hold;
                        fp_b <= COMPACT ? 32'h40000000 : 32'h41800000;
                        return_state <= IDENTITY_NARROW;
                        state <= FP_START;
                    end
                    IDENTITY_NARROW: begin
                        fp_op <= 3;
                        fp_a <= value_hold;
                        fp_b <= 0;
                        return_state <= COMBINE_READ;
                        state <= FP_START;
                    end
                    COMBINE_READ: state <= COMBINE_ADD;
                    COMBINE_ADD: begin
                        fp_op <= 0;
                        fp_a <= {value_hold[15:0], 16'd0};
                        fp_b <= {ple_q, 16'd0};
                        return_state <= COMBINE_NARROW;
                        state <= FP_START;
                    end
                    COMBINE_NARROW: begin
                        fp_op <= 3;
                        fp_a <= value_hold;
                        fp_b <= 0;
                        return_state <= COMBINE_SCALE;
                        state <= FP_START;
                    end
                    COMBINE_SCALE: begin
                        fp_op <= 1;
                        fp_a <= {value_hold[15:0], 16'd0};
                        fp_b <= 32'h3f350000;
                        return_state <= COMBINE_FINAL_NARROW;
                        state <= FP_START;
                    end
                    COMBINE_FINAL_NARROW: begin
                        fp_op <= 3;
                        fp_a <= value_hold;
                        fp_b <= 0;
                        return_state <= COMBINE_WRITE;
                        state <= FP_START;
                    end
                    COMBINE_WRITE: begin
                        if (index == P - 1) begin
                            index <= 0;
                            state <= INPUT_READ;
                        end else begin
                            index <= index + 1'b1;
                            state <= WEIGHT_START;
                        end
                    end
                    INPUT_READ: state <= INPUT_CAPTURE;
                    INPUT_CAPTURE: begin
                        output_hold <= input_q;
                        state <= INPUT_OUTPUT;
                    end
                    INPUT_OUTPUT: if (input_ready) begin
                        if (index == hidden_hold - 1'b1) begin
                            index <= 0;
                            state <= PLE_READ;
                        end else begin
                            index <= index + 1'b1;
                            state <= INPUT_READ;
                        end
                    end
                    PLE_READ: state <= PLE_CAPTURE;
                    PLE_CAPTURE: begin
                        output_hold <= ple_q;
                        state <= PLE_OUTPUT;
                    end
                    PLE_OUTPUT: if (ple_ready) begin
                        if (index == P - 1)
                            state <= PUBLISH;
                        else begin
                            index <= index + 1'b1;
                            state <= PLE_READ;
                        end
                    end
                    FP_START: if (fp_ready)
                        state <= FP_WAIT;
                    FP_WAIT: if (fp_valid) begin
                        if (fp_error != 0) begin
                            error_hold <= fp_error;
                            state <= PUBLISH;
                        end else begin
                            value_hold <= fp_data;
                            state <= return_state;
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
    end endgenerate
endmodule
