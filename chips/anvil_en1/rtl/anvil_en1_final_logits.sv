module anvil_en1_final_logits #(
    parameter integer COMPACT = 0,
    parameter integer EXTERNAL_PAYLOAD_RAM = 0
) (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] model, precision,
    input wire [63:0] weights_base,
    output wire source_valid,
    input wire source_ready,
    output wire [31:0] source_index,
    output wire source_is_normalized,
    input wire source_rsp_valid,
    output wire source_rsp_ready,
    input wire [15:0] source_rsp_data,
    input wire source_rsp_error,
    output wire normalized_store_valid,
    input wire normalized_store_ready,
    output wire [31:0] normalized_store_index,
    output wire [15:0] normalized_store_data,
    output wire normalized_store_last,
    output wire cmd_valid,
    input wire cmd_ready,
    output wire cmd_write,
    output wire [63:0] cmd_addr,
    output wire [31:0] cmd_wdata,
    input wire result_valid,
    output wire result_ready,
    input wire [31:0] result_data,
    input wire result_error,
    output wire logit_valid,
    input wire logit_ready,
    output wire [15:0] logit_data,
    output wire [17:0] logit_index,
    output wire logit_last,
    output wire done_valid,
    input wire done_ready,
    output wire [3:0] done_error,
    output wire [63:0] live_payload_bytes, physical_payload_bytes,
    output wire [63:0] controller_bytes
);
    generate if ((COMPACT != 0 && COMPACT != 1) ||
        (EXTERNAL_PAYLOAD_RAM != 0 && EXTERNAL_PAYLOAD_RAM != 1)) begin : invalid_parameters
        initial $fatal(1, "PARAMETER ERROR: COMPACT and EXTERNAL_PAYLOAD_RAM must be 0 or 1");
        assign start_ready = 0;
        assign source_valid = 0;
        assign source_index = 0;
        assign source_is_normalized = 0;
        assign source_rsp_ready = 0;
        assign normalized_store_valid = 0;
        assign normalized_store_index = 0;
        assign normalized_store_data = 0;
        assign normalized_store_last = 0;
        assign cmd_valid = 0;
        assign cmd_write = 0;
        assign cmd_addr = 0;
        assign cmd_wdata = 0;
        assign result_ready = 0;
        assign logit_valid = 0;
        assign logit_data = 0;
        assign logit_index = 0;
        assign logit_last = 0;
        assign done_valid = 0;
        assign done_error = 0;
        assign live_payload_bytes = 0;
        assign physical_payload_bytes = 0;
        assign controller_bytes = 0;
    end else begin : final_head
        localparam integer MAX_H = COMPACT ? 8 : 2560;
        localparam integer H_BITS = $clog2(MAX_H);
        localparam integer VOCABULARY = COMPACT ? 32 : 262144;
        localparam [4:0] IDLE = 0, VALIDATE = 1, LOOKUP_START = 2,
            LOOKUP_WAIT = 3, NORM_DESCRIPTOR = 4, NORM_START = 5,
            NORM_WAIT = 6, EMBEDDING_LOOKUP = 7, EMBEDDING_DESCRIPTOR = 8,
            PROJECTION_START = 9, PROJECTION_WAIT = 10,
            SOFTCAP_START = 11, SOFTCAP_WAIT = 12, LOGIT_RESPONSE = 13,
            PUBLISH = 14, RESPONSE = 15;
        localparam [2:0] W_IDLE = 0, W_START = 1, W_WAIT = 2,
            W_PUBLISH = 3, W_RESPONSE = 4;
        localparam [1:0] S_IDLE = 0, S_READ = 1, S_PUBLISH = 2, S_RESPONSE = 3;
        localparam [1:0] M_LOOKUP = 0, M_SCALE = 1, M_PROJECTION = 2;
        reg [4:0] state, lookup_return;
        reg [2:0] scale_state;
        reg [1:0] source_state, model_hold, precision_hold, memory_owner;
        reg [63:0] weights_hold;
        reg [15:0] lookup_kind;
        reg [31:0] hidden_hold, normalized_count;
        reg [17:0] row_hold;
        reg [63:0] descriptor_base, descriptor_bytes;
        reg [31:0] descriptor_rows, descriptor_columns, descriptor_stride;
        reg [31:0] scale_index_hold, projection_index_hold;
        reg [15:0] scale_data_hold, projection_source_hold, logit_hold;
        reg scale_error_hold, projection_source_error, normalization_error;
        reg normalized_committed;
        reg payload_allocated;
        reg [31:0] raw_logit_hold;
        reg [3:0] error_hold;
        wire [15:0] normalized_q;
        localparam integer CONTROLLER_BITS = $bits({
            state, lookup_return, scale_state, source_state, model_hold, precision_hold,
            memory_owner, weights_hold, lookup_kind, hidden_hold, normalized_count,
            row_hold, descriptor_base, descriptor_bytes, descriptor_rows,
            descriptor_columns, descriptor_stride, scale_index_hold,
            projection_index_hold, scale_data_hold, projection_source_hold,
            logit_hold, scale_error_hold, projection_source_error, normalization_error,
            normalized_committed, payload_allocated, raw_logit_hold, error_hold, normalized_q
        });
        wire [63:0] lookup_controller_bytes, norm_controller_bytes;
        wire [63:0] weight_controller_bytes, projection_controller_bytes, cap_controller_bytes;
        wire [63:0] fp_controller_bytes;
        localparam [1:0] FP_NORM = 0, FP_WEIGHT = 1, FP_PROJECTION = 2, FP_CAP = 3;
        wire [3:0] arithmetic_valid, arithmetic_result_ready;
        wire [11:0] arithmetic_operation;
        wire [127:0] arithmetic_a, arithmetic_b;
        wire fp_ready, fp_valid;
        wire [31:0] fp_data;
        wire [3:0] fp_error;
        wire scale_phase = scale_state == W_START || scale_state == W_WAIT;
        wire [1:0] fp_owner = scale_phase ? FP_WEIGHT :
            (state == NORM_START || state == NORM_WAIT ? FP_NORM :
            (state == PROJECTION_START || state == PROJECTION_WAIT ? FP_PROJECTION : FP_CAP));
        assign controller_bytes = !rst_n ? 64'd0 :
            64'((CONTROLLER_BITS+7) >> 3) + lookup_controller_bytes +
            norm_controller_bytes + weight_controller_bytes +
            projection_controller_bytes + cap_controller_bytes + fp_controller_bytes;
        wire lookup_ready, lookup_valid, lookup_cmd_valid, lookup_result_ready;
        wire [63:0] lookup_cmd_addr, lookup_base, lookup_bytes;
        wire [31:0] lookup_rows, lookup_columns, lookup_stride;
        wire [3:0] lookup_error;
        anvil_en1_tensor_image #(.COMPACT(COMPACT)) tensor_lookup (
            .controller_bytes(lookup_controller_bytes),
            .clk(clk), .rst_n(rst_n),
            .start_valid(rst_n && state == LOOKUP_START), .start_ready(lookup_ready),
            .model(model_hold), .precision(precision_hold),
            .image_class(2'd0), .input_audio(1'b0), .input_items(32'd0),
            .image_base(weights_hold), .tensor_kind(lookup_kind),
            .tensor_layer(16'hffff),
            .cmd_valid(lookup_cmd_valid),
            .cmd_ready(rst_n && memory_owner == M_LOOKUP && cmd_ready),
            .cmd_write(), .cmd_addr(lookup_cmd_addr), .cmd_wdata(),
            .result_valid(rst_n && memory_owner == M_LOOKUP && result_valid),
            .result_ready(lookup_result_ready), .result_data(result_data),
            .result_error(result_error),
            .done_valid(lookup_valid), .done_ready(rst_n && state == LOOKUP_WAIT),
            .done_base(lookup_base), .done_bytes(lookup_bytes),
            .done_rows(lookup_rows), .done_columns(lookup_columns),
            .done_stride(lookup_stride), .done_type(), .done_error(lookup_error)
        );
        wire norm_ready, norm_valid, norm_source_valid, norm_source_rsp_ready;
        wire [31:0] norm_source_index;
        wire norm_scale_valid, norm_scale_rsp_ready;
        wire [31:0] norm_scale_index;
        wire normalized_valid, normalized_last;
        wire [31:0] normalized_index;
        wire [15:0] normalized_data;
        wire [3:0] norm_error;
        wire norm_output_ready;
        anvil_en1_norm #(.EXTERNAL_FP(1)) norm_unit (
            .controller_bytes(norm_controller_bytes),
            .clk(clk), .rst_n(rst_n),
            .start_valid(rst_n && state == NORM_START), .start_ready(norm_ready),
            .layer_norm(1'b0), .learned_scale(1'b1),
            .vector_length(hidden_hold), .epsilon(32'h358637bd),
            .source_valid(norm_source_valid),
            .source_ready(rst_n && state == NORM_WAIT && source_ready),
            .source_index(norm_source_index),
            .source_rsp_valid(rst_n && state == NORM_WAIT && source_rsp_valid),
            .source_rsp_ready(norm_source_rsp_ready),
            .source_rsp_data(source_rsp_data), .source_rsp_error(source_rsp_error),
            .scale_valid(norm_scale_valid),
            .scale_ready(rst_n && state == NORM_WAIT && scale_state == W_IDLE),
            .scale_index(norm_scale_index),
            .scale_rsp_valid(rst_n && scale_state == W_RESPONSE),
            .scale_rsp_ready(norm_scale_rsp_ready),
            .scale_rsp_data(scale_data_hold), .scale_rsp_error(scale_error_hold),
            .normalized_valid(normalized_valid),
            .normalized_ready(norm_output_ready),
            .normalized_index(normalized_index), .normalized_data(normalized_data),
            .normalized_last(normalized_last),
            .done_valid(norm_valid), .done_ready(rst_n && state == NORM_WAIT),
            .done_error(norm_error),
            .arithmetic_valid(arithmetic_valid[FP_NORM]),
            .arithmetic_ready(fp_owner == FP_NORM && fp_ready),
            .arithmetic_operation(arithmetic_operation[3*FP_NORM+:3]),
            .arithmetic_a(arithmetic_a[32*FP_NORM+:32]),
            .arithmetic_b(arithmetic_b[32*FP_NORM+:32]),
            .arithmetic_result_valid(fp_owner == FP_NORM && fp_valid),
            .arithmetic_result_ready(arithmetic_result_ready[FP_NORM]),
            .arithmetic_result_data(fp_data), .arithmetic_result_error(fp_error)
        );
        wire scale_ready, scale_valid, scale_cmd_valid, scale_result_ready;
        wire [63:0] scale_cmd_addr;
        wire [31:0] scale_data;
        wire [3:0] scale_error;
        anvil_en1_weight_read #(.EXTERNAL_FP(1)) scale_reader (
            .controller_bytes(weight_controller_bytes),
            .clk(clk), .rst_n(rst_n),
            .start_valid(rst_n && scale_state == W_START), .start_ready(scale_ready),
            .precision(2'd0), .tensor_base(descriptor_base),
            .tensor_bytes(descriptor_bytes), .tensor_rows(descriptor_rows),
            .tensor_columns(descriptor_columns), .row_stride(descriptor_stride),
            .row_index(32'd0), .column_index(scale_index_hold),
            .cmd_valid(scale_cmd_valid),
            .cmd_ready(rst_n && memory_owner == M_SCALE && cmd_ready),
            .cmd_write(), .cmd_addr(scale_cmd_addr), .cmd_wdata(),
            .result_valid(rst_n && memory_owner == M_SCALE && result_valid),
            .result_ready(scale_result_ready), .result_data(result_data),
            .result_error(result_error),
            .done_valid(scale_valid), .done_ready(rst_n && scale_state == W_WAIT),
            .done_data(scale_data), .done_error(scale_error),
            .arithmetic_valid(arithmetic_valid[FP_WEIGHT]),
            .arithmetic_ready(fp_owner == FP_WEIGHT && fp_ready),
            .arithmetic_operation(arithmetic_operation[3*FP_WEIGHT+:3]),
            .arithmetic_a(arithmetic_a[32*FP_WEIGHT+:32]),
            .arithmetic_b(arithmetic_b[32*FP_WEIGHT+:32]),
            .arithmetic_result_valid(fp_owner == FP_WEIGHT && fp_valid),
            .arithmetic_result_ready(arithmetic_result_ready[FP_WEIGHT]),
            .arithmetic_result_data(fp_data), .arithmetic_result_error(fp_error)
        );
        wire projection_ready, projection_valid, projection_cmd_valid;
        wire projection_result_ready, projection_source_valid, projection_source_rsp_ready;
        wire [63:0] projection_cmd_addr;
        wire [31:0] projection_source_index, projection_data;
        wire [3:0] projection_error;
        anvil_en1_projection #(.EXTERNAL_FP(1)) projection_unit (
            .controller_bytes(projection_controller_bytes),
            .clk(clk), .rst_n(rst_n),
            .start_valid(rst_n && state == PROJECTION_START),
            .start_ready(projection_ready), .precision(precision_hold),
            .tensor_base(descriptor_base), .tensor_bytes(descriptor_bytes),
            .tensor_rows(descriptor_rows), .tensor_columns(descriptor_columns),
            .row_stride(descriptor_stride), .row_index({14'd0, row_hold}),
            .source_valid(projection_source_valid),
            .source_ready(rst_n && state == PROJECTION_WAIT &&
                (EXTERNAL_PAYLOAD_RAM ? source_ready : source_state == S_IDLE)),
            .source_index(projection_source_index),
            .source_rsp_valid(rst_n && (EXTERNAL_PAYLOAD_RAM ?
                state == PROJECTION_WAIT && source_rsp_valid : source_state == S_RESPONSE)),
            .source_rsp_ready(projection_source_rsp_ready),
            .source_rsp_data(EXTERNAL_PAYLOAD_RAM ? source_rsp_data : projection_source_hold),
            .source_rsp_error(EXTERNAL_PAYLOAD_RAM ?
                source_rsp_error || !normalized_committed : projection_source_error),
            .cmd_valid(projection_cmd_valid),
            .cmd_ready(rst_n && memory_owner == M_PROJECTION && cmd_ready),
            .cmd_write(), .cmd_addr(projection_cmd_addr), .cmd_wdata(),
            .result_valid(rst_n && memory_owner == M_PROJECTION && result_valid),
            .result_ready(projection_result_ready), .result_data(result_data),
            .result_error(result_error),
            .done_valid(projection_valid),
            .done_ready(rst_n && state == PROJECTION_WAIT),
            .done_data(projection_data), .done_error(projection_error),
            .arithmetic_valid(arithmetic_valid[FP_PROJECTION]),
            .arithmetic_ready(fp_owner == FP_PROJECTION && fp_ready),
            .arithmetic_operation(arithmetic_operation[3*FP_PROJECTION+:3]),
            .arithmetic_a(arithmetic_a[32*FP_PROJECTION+:32]),
            .arithmetic_b(arithmetic_b[32*FP_PROJECTION+:32]),
            .arithmetic_result_valid(fp_owner == FP_PROJECTION && fp_valid),
            .arithmetic_result_ready(arithmetic_result_ready[FP_PROJECTION]),
            .arithmetic_result_data(fp_data), .arithmetic_result_error(fp_error)
        );
        wire softcap_ready, softcap_valid;
        wire [31:0] softcap_data;
        wire [3:0] softcap_error;
        anvil_en1_softcap #(.EXTERNAL_FP(1)) softcap_unit (
            .controller_bytes(cap_controller_bytes),
            .clk(clk), .rst_n(rst_n),
            .start_valid(rst_n && state == SOFTCAP_START), .start_ready(softcap_ready),
            .cap_50(1'b0), .input_binary32(1'b0), .output_binary32(1'b0),
            .operand(raw_logit_hold), .done_valid(softcap_valid),
            .done_ready(rst_n && state == SOFTCAP_WAIT),
            .done_data(softcap_data), .done_error(softcap_error),
            .arithmetic_valid(arithmetic_valid[FP_CAP]),
            .arithmetic_ready(fp_owner == FP_CAP && fp_ready),
            .arithmetic_operation(arithmetic_operation[3*FP_CAP+:3]),
            .arithmetic_a(arithmetic_a[32*FP_CAP+:32]),
            .arithmetic_b(arithmetic_b[32*FP_CAP+:32]),
            .arithmetic_result_valid(fp_owner == FP_CAP && fp_valid),
            .arithmetic_result_ready(arithmetic_result_ready[FP_CAP]),
            .arithmetic_result_data(fp_data), .arithmetic_result_error(fp_error)
        );
        anvil_en1_fp32 fp_unit (
            .controller_bytes(fp_controller_bytes),
            .clk(clk), .rst_n(rst_n),
            .start_valid(rst_n && arithmetic_valid[fp_owner]), .start_ready(fp_ready),
            .operation(arithmetic_operation[3*fp_owner+:3]),
            .operand_a(arithmetic_a[32*fp_owner+:32]),
            .operand_b(arithmetic_b[32*fp_owner+:32]),
            .done_valid(fp_valid),
            .done_ready(rst_n && arithmetic_result_ready[fp_owner]),
            .done_data(fp_data), .done_error(fp_error)
        );
        wire norm_beat_valid = normalized_index == normalized_count &&
            normalized_index < hidden_hold &&
            normalized_last == (normalized_index == hidden_hold - 1'b1);
        assign norm_output_ready = rst_n && state == NORM_WAIT &&
            (!EXTERNAL_PAYLOAD_RAM || !norm_beat_valid || normalized_store_ready);
        wire norm_write = normalized_valid && norm_output_ready && norm_beat_valid;
        wire projection_read_valid = normalized_committed &&
            projection_index_hold < hidden_hold;
        if (EXTERNAL_PAYLOAD_RAM == 0) begin : internal_payload
            (* ramstyle = "M20K", nomem2reg *)
            reg [15:0] normalized_payload [0:MAX_H-1];
            reg [15:0] payload_q;
            assign normalized_q = payload_q;
            always @(posedge clk) begin
                if (norm_write)
                    normalized_payload[normalized_index[H_BITS-1:0]] <= normalized_data;
                if (rst_n && source_state == S_READ && projection_read_valid)
                    payload_q <= normalized_payload[projection_index_hold[H_BITS-1:0]];
            end
        end else begin : external_payload
            assign normalized_q = 16'd0;
        end

        assign normalized_store_valid = rst_n && EXTERNAL_PAYLOAD_RAM &&
            state == NORM_WAIT && normalized_valid && norm_beat_valid;
        assign normalized_store_index = rst_n && EXTERNAL_PAYLOAD_RAM ?
            normalized_index : 32'd0;
        assign normalized_store_data = rst_n && EXTERNAL_PAYLOAD_RAM ?
            normalized_data : 16'd0;
        assign normalized_store_last = rst_n && EXTERNAL_PAYLOAD_RAM && normalized_last;

        assign start_ready = rst_n && state == IDLE;
        assign source_is_normalized = rst_n && EXTERNAL_PAYLOAD_RAM &&
            state == PROJECTION_WAIT;
        assign source_valid = rst_n && (state == NORM_WAIT ? norm_source_valid :
            (source_is_normalized && projection_source_valid));
        assign source_index = !rst_n ? 32'd0 :
            (source_is_normalized ? projection_source_index : norm_source_index);
        assign source_rsp_ready = rst_n && (state == NORM_WAIT ? norm_source_rsp_ready :
            (source_is_normalized && projection_source_rsp_ready));
        assign cmd_valid = rst_n && (memory_owner == M_LOOKUP ? lookup_cmd_valid :
            memory_owner == M_SCALE ? scale_cmd_valid : projection_cmd_valid);
        assign cmd_write = 0;
        assign cmd_addr = rst_n ? (memory_owner == M_LOOKUP ? lookup_cmd_addr :
            memory_owner == M_SCALE ? scale_cmd_addr : projection_cmd_addr) : 64'd0;
        assign cmd_wdata = 0;
        assign result_ready = rst_n && (memory_owner == M_LOOKUP ? lookup_result_ready :
            memory_owner == M_SCALE ? scale_result_ready : projection_result_ready);
        assign logit_valid = rst_n && state == LOGIT_RESPONSE;
        assign logit_data = rst_n ? logit_hold : 16'd0;
        assign logit_index = rst_n ? row_hold : 18'd0;
        assign logit_last = rst_n && state == LOGIT_RESPONSE && row_hold == VOCABULARY - 1;
        assign done_valid = rst_n && state == RESPONSE;
        assign done_error = rst_n ? error_hold : 4'd0;
        assign live_payload_bytes = rst_n && !EXTERNAL_PAYLOAD_RAM && payload_allocated ?
            {32'd0, hidden_hold} << 1 : 64'd0;
        assign physical_payload_bytes = rst_n && !EXTERNAL_PAYLOAD_RAM ?
            64'(2*MAX_H) : 64'd0;

        always @(posedge clk or negedge rst_n) begin
            if (!rst_n)
                payload_allocated <= 0;
            else if (done_valid && done_ready)
                payload_allocated <= 0;
            else if (state == VALIDATE && (model_hold == 1 || model_hold == 2) &&
                precision_hold <= 1)
                payload_allocated <= 1;
        end

        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                scale_state <= W_IDLE;
                scale_index_hold <= 0;
                scale_data_hold <= 0;
                scale_error_hold <= 0;
            end else begin
                case (scale_state)
                    W_IDLE: if (state == NORM_WAIT && norm_scale_valid) begin
                        scale_index_hold <= norm_scale_index;
                        scale_error_hold <= 0;
                        scale_state <= W_START;
                    end
                    W_START: if (scale_ready)
                        scale_state <= W_WAIT;
                    W_WAIT: if (scale_valid) begin
                        scale_data_hold <= scale_data[31:16];
                        scale_error_hold <= scale_error != 0;
                        scale_state <= W_PUBLISH;
                    end
                    W_PUBLISH: scale_state <= W_RESPONSE;
                    W_RESPONSE: if (norm_scale_rsp_ready)
                        scale_state <= W_IDLE;
                    default: begin
                        scale_data_hold <= 0;
                        scale_error_hold <= 1;
                        scale_state <= W_RESPONSE;
                    end
                endcase
            end
        end
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                source_state <= S_IDLE;
                projection_index_hold <= 0;
                projection_source_hold <= 0;
                projection_source_error <= 0;
            end else begin
                case (source_state)
                    S_IDLE: if (!EXTERNAL_PAYLOAD_RAM &&
                        state == PROJECTION_WAIT && projection_source_valid) begin
                        projection_index_hold <= projection_source_index;
                        source_state <= S_READ;
                    end
                    S_READ: begin
                        projection_source_error <= !projection_read_valid;
                        source_state <= S_PUBLISH;
                    end
                    S_PUBLISH: begin
                        projection_source_hold <= projection_source_error ? 16'd0 : normalized_q;
                        source_state <= S_RESPONSE;
                    end
                    S_RESPONSE: if (projection_source_rsp_ready)
                        source_state <= S_IDLE;
                    default: begin
                        projection_source_hold <= 0;
                        projection_source_error <= 1;
                        source_state <= S_RESPONSE;
                    end
                endcase
            end
        end
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                state <= IDLE;
                lookup_return <= 0;
                model_hold <= 0;
                precision_hold <= 0;
                memory_owner <= M_LOOKUP;
                weights_hold <= 0;
                lookup_kind <= 0;
                hidden_hold <= 0;
                normalized_count <= 0;
                row_hold <= 0;
                descriptor_base <= 0;
                descriptor_bytes <= 0;
                descriptor_rows <= 0;
                descriptor_columns <= 0;
                descriptor_stride <= 0;
                logit_hold <= 0;
                raw_logit_hold <= 0;
                error_hold <= 0;
                normalization_error <= 0;
                normalized_committed <= 0;
            end else begin
                case (state)
                    IDLE: if (start_valid && start_ready) begin
                        model_hold <= model;
                        precision_hold <= precision;
                        weights_hold <= weights_base;
                        memory_owner <= M_LOOKUP;
                        normalized_count <= 0;
                        normalized_committed <= 0;
                        normalization_error <= 0;
                        row_hold <= 0;
                        logit_hold <= 0;
                        raw_logit_hold <= 0;
                        error_hold <= 0;
                        state <= VALIDATE;
                    end
                    VALIDATE: begin
                        if ((model_hold != 1 && model_hold != 2) || precision_hold > 1) begin
                            error_hold <= 6;
                            state <= PUBLISH;
                        end else begin
                            hidden_hold <= COMPACT ? 32'd8 :
                                (model_hold == 1 ? 32'd1536 : 32'd2560);
                            lookup_kind <= 16'h0004;
                            lookup_return <= NORM_DESCRIPTOR;
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
                            state <= lookup_return;
                        end
                    end
                    NORM_DESCRIPTOR: begin
                        memory_owner <= M_SCALE;
                        state <= NORM_START;
                    end
                    NORM_START: if (norm_ready)
                        state <= NORM_WAIT;
                    NORM_WAIT: begin
                        if (normalized_valid && norm_output_ready) begin
                            if (!norm_beat_valid)
                                normalization_error <= 1;
                            if (normalized_count < hidden_hold)
                                normalized_count <= normalized_count + 1'b1;
                            else
                                normalization_error <= 1;
                        end
                        if (norm_valid) begin
                            if (norm_error != 0) begin
                                error_hold <= norm_error;
                                state <= PUBLISH;
                            end else if (normalization_error || normalized_count != hidden_hold) begin
                                error_hold <= 7;
                                state <= PUBLISH;
                            end else begin
                                normalized_committed <= 1;
                                state <= EMBEDDING_LOOKUP;
                            end
                        end
                    end
                    EMBEDDING_LOOKUP: begin
                        lookup_kind <= 16'h0000;
                        lookup_return <= EMBEDDING_DESCRIPTOR;
                        memory_owner <= M_LOOKUP;
                        state <= LOOKUP_START;
                    end
                    EMBEDDING_DESCRIPTOR: begin
                        memory_owner <= M_PROJECTION;
                        state <= PROJECTION_START;
                    end
                    PROJECTION_START: if (projection_ready)
                        state <= PROJECTION_WAIT;
                    PROJECTION_WAIT: if (projection_valid) begin
                        if (projection_error != 0) begin
                            error_hold <= projection_error;
                            state <= PUBLISH;
                        end else begin
                            raw_logit_hold <= projection_data;
                            state <= SOFTCAP_START;
                        end
                    end
                    SOFTCAP_START: if (softcap_ready)
                        state <= SOFTCAP_WAIT;
                    SOFTCAP_WAIT: if (softcap_valid) begin
                        if (softcap_error != 0) begin
                            error_hold <= softcap_error;
                            state <= PUBLISH;
                        end else begin
                            logit_hold <= softcap_data[15:0];
                            state <= LOGIT_RESPONSE;
                        end
                    end
                    LOGIT_RESPONSE: if (logit_ready) begin
                        if (row_hold == VOCABULARY - 1)
                            state <= PUBLISH;
                        else begin
                            row_hold <= row_hold + 1'b1;
                            state <= PROJECTION_START;
                        end
                    end
                    PUBLISH: begin
                        normalized_committed <= 0;
                        state <= RESPONSE;
                    end
                    RESPONSE: if (done_ready)
                        state <= IDLE;
                    default: begin
                        error_hold <= 7;
                        normalized_committed <= 0;
                        state <= PUBLISH;
                    end
                endcase
            end
        end
    end endgenerate
endmodule
