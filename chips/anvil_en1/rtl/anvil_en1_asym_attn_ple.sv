module anvil_en1_asym_attn_ple #(
    parameter integer COMPACT = 0,
    parameter integer POST_ONLY = 0,
    parameter integer EXTERNAL_VECTOR_RAM = 0,
    parameter integer SHARED_RESIDUAL = 0,
    parameter integer SHARED_PLE = 0
) (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] model, precision,
    input wire [7:0] layer,
    input wire [31:0] token,
    input wire [63:0] weights_base,
    output wire source_valid,
    input wire source_ready,
    output wire [1:0] source_model,
    output wire [7:0] source_layer,
    output wire [31:0] source_token, source_index,
    output wire source_is_ple,
    output wire source_is_branch,
    input wire source_rsp_valid,
    output wire source_rsp_ready,
    input wire [15:0] source_rsp_data,
    input wire source_rsp_error,
    output wire mask_valid,
    input wire mask_ready,
    output wire [31:0] mask_token,
    input wire mask_rsp_valid,
    output wire mask_rsp_ready,
    input wire mask_rsp_data, mask_rsp_error,
    output wire req_valid,
    input wire req_ready,
    output wire [2:0] req_op,
    output wire [1:0] req_model,
    output wire [7:0] req_layer,
    output wire [31:0] req_token,
    output wire req_is_value,
    output wire [1:0] req_kv_head,
    output wire [9:0] req_component,
    output wire [63:0] req_base,
    input wire rsp_valid,
    output wire rsp_ready,
    input wire [63:0] rsp_addr,
    input wire [7:0] rsp_owner,
    input wire rsp_alias,
    input wire [3:0] rsp_error,
    input wire [1:0] rsp_space,
    output wire fetch_valid,
    input wire fetch_ready,
    output wire [1:0] fetch_model,
    output wire [7:0] fetch_owner,
    output wire [31:0] fetch_token,
    output wire fetch_is_value,
    output wire [1:0] fetch_kv_head,
    output wire [9:0] fetch_component,
    input wire fetch_rsp_valid,
    output wire fetch_rsp_ready,
    input wire [15:0] fetch_rsp_data,
    input wire [3:0] fetch_rsp_error,
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
    output wire output_last,
    output wire done_valid,
    input wire done_ready,
    output wire [3:0] done_error,
    output wire [63:0] live_payload_bytes, physical_payload_bytes,
    output wire [63:0] production_shadow_bytes,
    output wire [3:0] vector_ram_write, vector_ram_read,
    output wire [47:0] vector_ram_waddr, vector_ram_raddr,
    output wire [63:0] vector_ram_wdata,
    input wire [63:0] vector_ram_rdata,
    output wire [3:0] attention_activity,
    output wire avoided_projection_event,
    output wire [31:0] avoided_projection_bytes,
    output wire [63:0] controller_bytes
);
    generate if ((COMPACT != 0 && COMPACT != 1) ||
        (POST_ONLY != 0 && POST_ONLY != 1) ||
        (EXTERNAL_VECTOR_RAM != 0 && EXTERNAL_VECTOR_RAM != 1) ||
        (SHARED_RESIDUAL != 0 && SHARED_RESIDUAL != 1) ||
        (SHARED_PLE != 0 && SHARED_PLE != 1) ||
        ((SHARED_RESIDUAL == 1 || SHARED_PLE == 1) &&
            EXTERNAL_VECTOR_RAM != 1)) begin : invalid_parameters
        initial $fatal(1, "PARAMETER ERROR: COMPACT, POST_ONLY, EXTERNAL_VECTOR_RAM, SHARED_RESIDUAL and SHARED_PLE must be 0 or 1; shared retained vectors require external vectors");
        assign start_ready = 0;
        assign source_valid = 0;
        assign source_model = 0;
        assign source_layer = 0;
        assign source_token = 0;
        assign source_index = 0;
        assign source_is_ple = 0;
        assign source_is_branch = 0;
        assign source_rsp_ready = 0;
        assign mask_valid = 0;
        assign mask_token = 0;
        assign mask_rsp_ready = 0;
        assign req_valid = 0;
        assign req_op = 0;
        assign req_model = 0;
        assign req_layer = 0;
        assign req_token = 0;
        assign req_is_value = 0;
        assign req_kv_head = 0;
        assign req_component = 0;
        assign req_base = 0;
        assign rsp_ready = 0;
        assign fetch_valid = 0;
        assign fetch_model = 0;
        assign fetch_owner = 0;
        assign fetch_token = 0;
        assign fetch_is_value = 0;
        assign fetch_kv_head = 0;
        assign fetch_component = 0;
        assign fetch_rsp_ready = 0;
        assign cmd_valid = 0;
        assign cmd_write = 0;
        assign cmd_addr = 0;
        assign cmd_wdata = 0;
        assign result_ready = 0;
        assign output_valid = 0;
        assign output_index = 0;
        assign output_data = 0;
        assign output_last = 0;
        assign done_valid = 0;
        assign done_error = 0;
        assign live_payload_bytes = 0;
        assign production_shadow_bytes = 0;
        assign physical_payload_bytes = 0;
        assign vector_ram_write = 0;
        assign vector_ram_read = 0;
        assign vector_ram_waddr = 0;
        assign vector_ram_raddr = 0;
        assign vector_ram_wdata = 0;
        assign attention_activity = 0;
        assign avoided_projection_event = 0;
        assign avoided_projection_bytes = 0;
        assign controller_bytes = 0;
    end else begin : engine
        localparam integer MAX_H = COMPACT ? 8 : 2560;
        localparam integer MAX_D = COMPACT ? 8 : 512;
        localparam integer Q = COMPACT ? 2 : 8;
        localparam integer P = COMPACT ? 4 : 256;
        localparam integer H_BITS = $clog2(MAX_H);
        localparam integer P_BITS = $clog2(P);
        localparam [5:0] IDLE = 0, VALIDATE = 1, LOAD_START = 2,
            LOAD_WAIT = 3, LOAD_CHECK = 4, LOAD_WRITE = 5,
            NORM_SETUP = 6, LOOKUP_START = 7, LOOKUP_WAIT = 8,
            LOOKUP_REGISTER = 9, NORM_DESCRIPTOR = 10, NORM_START = 11,
            NORM_WAIT = 12, QUERY_LOOKUP = 13, QUERY_DESCRIPTOR = 14,
            PROJECTION_START = 15, PROJECTION_WAIT = 16,
            PROJECTION_WRITE = 17, ROTARY_FIRST_READ = 18,
            ROTARY_FIRST_CAPTURE = 19, ROTARY_SECOND_READ = 20,
            ROTARY_SECOND_CAPTURE = 21, ROTARY_START = 22, ROTARY_WAIT = 23,
            ROTARY_FIRST_WRITE = 24, ROTARY_SECOND_WRITE = 25,
            ATTENTION_START = 26, ATTENTION_WAIT = 27,
            OUTPUT_PROJECTION_LOOKUP = 28, OUTPUT_PROJECTION_DESCRIPTOR = 29,
            RESIDUAL_READ = 30, RESIDUAL_CAPTURE = 31,
            RESIDUAL_ADD = 32, NARROW = 33, RESIDUAL_WRITE = 34,
            GATE_LOOKUP = 35, GATE_DESCRIPTOR = 36,
            UP_DESCRIPTOR = 37, DOWN_DESCRIPTOR = 38,
            GATED_START = 39, GATED_WAIT = 40, GATED_WRITE = 41,
            SCALAR_LOOKUP = 42, SCALAR_DESCRIPTOR = 43,
            SCALAR_START = 44, SCALAR_WAIT = 45,
            SCALAR_READ = 46, SCALAR_CAPTURE = 47,
            SCALAR_MULTIPLY = 48, SCALAR_WRITE = 49,
            OUTPUT_READ = 50, OUTPUT_CAPTURE = 51, OUTPUT_WAIT = 52,
            FP_START = 53, FP_WAIT = 54, PUBLISH = 55, RESPONSE = 56,
            OUTPUT_ROW_NARROW = 57, OUTPUT_ROW_WRITE = 58;
        localparam [2:0] N_INPUT = 0, N_QUERY = 1, N_POST_ATTENTION = 2,
            N_PRE_FF = 3, N_POST_FF = 4, N_POST_PLE = 5;
        localparam [2:0] B_RESIDUAL = 0, B_WORK = 1, B_BRANCH = 2,
            B_QUERY = 3, B_ATTENTION = 4, B_PLE = 5;
        localparam [2:0] S_IDLE = 0, S_READ = 1, S_PUBLISH = 2, S_RESPONSE = 3;
        localparam [2:0] C_NORM = 0, C_PROJECTION = 1, C_GATED = 2,
            C_QUERY = 3, C_UP = 4;
        localparam [2:0] W_IDLE = 0, W_START = 1, W_WAIT = 2,
            W_PUBLISH = 3, W_RESPONSE = 4;
        localparam [3:0] O_IDLE = 0, O_WEIGHT_START = 1, O_WEIGHT_WAIT = 2,
            O_CONVERT_START = 3, O_CONVERT_WAIT = 4,
            O_MULTIPLY_START = 5, O_MULTIPLY_WAIT = 6,
            O_ADD_START = 7, O_ADD_WAIT = 8, O_ACK = 9, O_DRAIN = 10;
        localparam [1:0] M_LOOKUP = 0, M_PROJECTION = 1,
            M_GATED = 2, M_WEIGHT = 3;
        reg [5:0] state, lookup_return, fp_return, narrow_return;
        reg [2:0] norm_phase, norm_bank, norm_destination;
        reg [2:0] src_state, src_client, src_bank, scale_state;
        reg [1:0] model_hold, precision_hold, memory_owner, residual_phase;
        reg [7:0] layer_hold;
        reg [31:0] token_hold, hidden_hold, dimension_hold;
        reg [63:0] weights_hold;
        reg global_hold, load_ple, load_branch, projection_query, gated_ple;
        reg [3:0] head;
        reg [31:0] index, pair_index, norm_length, projection_row;
        reg [15:0] lookup_kind, load_data, output_hold;
        reg load_error, src_error_hold, scale_error_hold;
        reg [31:0] src_index_hold, scale_index_hold;
        reg [15:0] src_data_hold, scale_data_hold;
        reg [63:0] descriptor_base, descriptor_bytes, scale_base, scale_bytes;
        reg [31:0] descriptor_rows, descriptor_columns, descriptor_stride;
        reg [31:0] scale_columns, scale_stride;
        reg [63:0] gate_base_hold, gate_bytes_hold, up_base_hold, up_bytes_hold;
        reg [63:0] down_base_hold, down_bytes_hold;
        reg [31:0] gate_rows_hold, gate_columns_hold, gate_stride_hold;
        reg [31:0] up_rows_hold, up_columns_hold, up_stride_hold;
        reg [31:0] down_rows_hold, down_columns_hold, down_stride_hold;
        reg [31:0] scalar_hold, fp_a, fp_b, value_hold, rotary_data_hold;
        reg [15:0] branch_data_hold, residual_data_hold, rotary_first, rotary_second;
        reg [2:0] fp_op;
        reg [3:0] error_hold;
        reg [3:0] output_state, output_error;
        reg [31:0] output_row, output_accumulator, output_value, output_weight;
        reg residual_allocated, work_allocated, branch_allocated;
        reg query_allocated, attention_allocated, ple_allocated;
        wire [15:0] residual_q, work_q, branch_q, ple_q;
        wire [15:0] query_q = branch_q;
        wire [15:0] attention_q;
        localparam integer CONTROLLER_BITS = $bits({
            state, lookup_return, fp_return, narrow_return, norm_phase, norm_bank,
            norm_destination, src_state, src_client, src_bank, scale_state,
            model_hold, precision_hold, memory_owner, residual_phase, layer_hold,
            token_hold, hidden_hold, dimension_hold, weights_hold, global_hold,
            load_ple, load_branch, projection_query, gated_ple, head, index,
            pair_index, norm_length, projection_row, lookup_kind, load_data,
            output_hold, load_error, src_error_hold, scale_error_hold, src_index_hold,
            scale_index_hold, src_data_hold, scale_data_hold, descriptor_base,
            descriptor_bytes, scale_base, scale_bytes, descriptor_rows,
            descriptor_columns, descriptor_stride, scale_columns, scale_stride,
            gate_base_hold, gate_bytes_hold, up_base_hold, up_bytes_hold,
            down_base_hold, down_bytes_hold, gate_rows_hold, gate_columns_hold,
            gate_stride_hold, up_rows_hold, up_columns_hold, up_stride_hold,
            down_rows_hold, down_columns_hold, down_stride_hold, scalar_hold,
            fp_a, fp_b, value_hold, rotary_data_hold, branch_data_hold,
            residual_data_hold, rotary_first, rotary_second, fp_op, error_hold,
            output_state, output_error, output_row, output_accumulator,
            output_value, output_weight,
            residual_allocated, work_allocated, branch_allocated,
            query_allocated, attention_allocated, ple_allocated,
            residual_q, work_q, branch_q, ple_q
        }) - (EXTERNAL_VECTOR_RAM ? 64 : 0) + (POST_ONLY ? 0 : 16);
        wire [63:0] lookup_controller_bytes, norm_controller_bytes;
        wire [63:0] projection_controller_bytes, rotary_controller_bytes;
        wire [63:0] attention_controller_bytes, gated_controller_bytes;
        wire [63:0] weight_controller_bytes, fp_controller_bytes;
        localparam [2:0] FP_NORM = 0, FP_PROJECTION = 1, FP_ROTARY = 2,
            FP_ATTENTION = 3, FP_GATED = 4, FP_WEIGHT = 5,
            FP_OUTPUT = 6, FP_LOCAL = 7;
        wire [6:0] arithmetic_valid, arithmetic_result_ready;
        wire [20:0] arithmetic_operation;
        wire [223:0] arithmetic_a, arithmetic_b;
        wire fp_ready, fp_valid;
        wire [31:0] fp_data;
        wire [3:0] fp_error;
        wire weight_phase = scale_state == W_START || scale_state == W_WAIT ||
            state == SCALAR_START || state == SCALAR_WAIT ||
            output_state == O_WEIGHT_START || output_state == O_WEIGHT_WAIT;
        wire output_arithmetic = output_state >= O_CONVERT_START &&
            output_state <= O_ADD_WAIT;
        wire [2:0] fp_owner = weight_phase ? FP_WEIGHT :
            (output_arithmetic ? FP_OUTPUT :
            (state == NORM_START || state == NORM_WAIT ? FP_NORM :
            (state == PROJECTION_START || state == PROJECTION_WAIT ? FP_PROJECTION :
            (state == ROTARY_START || state == ROTARY_WAIT ? FP_ROTARY :
            (state == ATTENTION_START || state == ATTENTION_WAIT ? FP_ATTENTION :
            (state == GATED_START || state == GATED_WAIT ? FP_GATED : FP_LOCAL))))));
        assign arithmetic_valid[FP_OUTPUT] = rst_n && (
            output_state == O_CONVERT_START || output_state == O_MULTIPLY_START ||
            output_state == O_ADD_START);
        assign arithmetic_operation[3*FP_OUTPUT+:3] =
            output_state == O_CONVERT_START ? 3'd2 :
            (output_state == O_MULTIPLY_START ? 3'd1 : 3'd0);
        assign arithmetic_a[32*FP_OUTPUT+:32] =
            output_state == O_CONVERT_START ? {16'd0, attention_component_data} :
            (output_state == O_MULTIPLY_START ? output_value : output_accumulator);
        assign arithmetic_b[32*FP_OUTPUT+:32] =
            output_state == O_MULTIPLY_START ? output_weight :
            (output_state == O_ADD_START ? output_value : 32'd0);
        assign arithmetic_result_ready[FP_OUTPUT] = rst_n && (
            output_state == O_CONVERT_WAIT || output_state == O_MULTIPLY_WAIT ||
            output_state == O_ADD_WAIT);
        assign controller_bytes = !rst_n ? 64'd0 :
            64'((CONTROLLER_BITS+7) >> 3) + lookup_controller_bytes +
            norm_controller_bytes + projection_controller_bytes + rotary_controller_bytes +
            attention_controller_bytes + gated_controller_bytes +
            weight_controller_bytes + fp_controller_bytes;
        wire native_model, selected_global;
        wire [7:0] layer_count;
        wire [11:0] selected_hidden;
        anvil_en1_geometry geometry (
            .rst_n(rst_n), .model(model_hold), .layer(layer_hold),
            .is_native(native_model), .layers(layer_count), .owners(), .owner(),
            .is_global(selected_global), .hidden(selected_hidden), .intermediate()
        );
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
            .tensor_kind(lookup_kind), .tensor_layer({8'd0, layer_hold}),
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
        wire projection_ready, projection_valid, projection_cmd_valid;
        wire projection_result_ready, projection_source_valid, projection_source_rsp_ready;
        wire [31:0] projection_data, projection_source_index;
        wire [63:0] projection_cmd_addr;
        wire [3:0] projection_error;
        if (POST_ONLY) begin : no_projection
            assign projection_controller_bytes = 0;
            assign projection_ready = 0;
            assign projection_valid = 0;
            assign projection_cmd_valid = 0;
            assign projection_result_ready = 0;
            assign projection_source_valid = 0;
            assign projection_source_rsp_ready = 0;
            assign projection_data = 0;
            assign projection_source_index = 0;
            assign projection_cmd_addr = 0;
            assign projection_error = 0;
            assign arithmetic_valid[FP_PROJECTION] = 0;
            assign arithmetic_result_ready[FP_PROJECTION] = 0;
            assign arithmetic_operation[3*FP_PROJECTION+:3] = 0;
            assign arithmetic_a[32*FP_PROJECTION+:32] = 0;
            assign arithmetic_b[32*FP_PROJECTION+:32] = 0;
        end else begin : full_projection
        anvil_en1_projection #(.EXTERNAL_FP(1)) projection_unit (
            .controller_bytes(projection_controller_bytes),
            .clk(clk), .rst_n(rst_n),
            .start_valid(rst_n && state == PROJECTION_START), .start_ready(projection_ready),
            .precision(precision_hold), .tensor_base(descriptor_base),
            .tensor_bytes(descriptor_bytes), .tensor_rows(descriptor_rows),
            .tensor_columns(descriptor_columns), .row_stride(descriptor_stride),
            .row_index(projection_row),
            .source_valid(projection_source_valid),
            .source_ready(rst_n && src_state == S_IDLE && state == PROJECTION_WAIT),
            .source_index(projection_source_index),
            .source_rsp_valid(rst_n && src_state == S_RESPONSE && src_client == C_PROJECTION),
            .source_rsp_ready(projection_source_rsp_ready),
            .source_rsp_data(src_data_hold), .source_rsp_error(src_error_hold),
            .cmd_valid(projection_cmd_valid),
            .cmd_ready(rst_n && memory_owner == M_PROJECTION && cmd_ready),
            .cmd_write(), .cmd_addr(projection_cmd_addr), .cmd_wdata(),
            .result_valid(rst_n && memory_owner == M_PROJECTION && result_valid),
            .result_ready(projection_result_ready),
            .result_data(result_data), .result_error(result_error),
            .done_valid(projection_valid), .done_ready(rst_n && state == PROJECTION_WAIT),
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
        end
        wire norm_ready, norm_valid, norm_source_valid, norm_source_rsp_ready;
        wire norm_scale_valid, norm_scale_rsp_ready, normalized_valid;
        wire [31:0] norm_source_index, norm_scale_index, normalized_index;
        wire [15:0] normalized_data;
        wire [3:0] norm_error;
        anvil_en1_norm #(.EXTERNAL_FP(1)) norm_unit (
            .controller_bytes(norm_controller_bytes),
            .clk(clk), .rst_n(rst_n),
            .start_valid(rst_n && state == NORM_START), .start_ready(norm_ready),
            .layer_norm(1'b0), .learned_scale(1'b1),
            .vector_length(norm_length), .epsilon(32'h358637bd),
            .source_valid(norm_source_valid),
            .source_ready(rst_n && src_state == S_IDLE && state == NORM_WAIT),
            .source_index(norm_source_index),
            .source_rsp_valid(rst_n && src_state == S_RESPONSE && src_client == C_NORM),
            .source_rsp_ready(norm_source_rsp_ready),
            .source_rsp_data(src_data_hold), .source_rsp_error(src_error_hold),
            .scale_valid(norm_scale_valid),
            .scale_ready(rst_n && scale_state == W_IDLE && state == NORM_WAIT),
            .scale_index(norm_scale_index),
            .scale_rsp_valid(rst_n && scale_state == W_RESPONSE),
            .scale_rsp_ready(norm_scale_rsp_ready),
            .scale_rsp_data(scale_data_hold), .scale_rsp_error(scale_error_hold),
            .normalized_valid(normalized_valid),
            .normalized_ready(rst_n && state == NORM_WAIT),
            .normalized_index(normalized_index), .normalized_data(normalized_data),
            .normalized_last(),
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
        wire rotary_ready, rotary_valid;
        wire [31:0] rotary_data;
        wire [3:0] rotary_error;
        if (POST_ONLY) begin : no_rotary
            assign rotary_controller_bytes = 0;
            assign rotary_ready = 0;
            assign rotary_valid = 0;
            assign rotary_data = 0;
            assign rotary_error = 0;
            assign arithmetic_valid[FP_ROTARY] = 0;
            assign arithmetic_result_ready[FP_ROTARY] = 0;
            assign arithmetic_operation[3*FP_ROTARY+:3] = 0;
            assign arithmetic_a[32*FP_ROTARY+:32] = 0;
            assign arithmetic_b[32*FP_ROTARY+:32] = 0;
        end else begin : full_rotary
        anvil_en1_rotary_pair #(.EXTERNAL_FP(1)) rotary_unit (
            .controller_bytes(rotary_controller_bytes),
            .clk(clk), .rst_n(rst_n),
            .start_valid(rst_n && state == ROTARY_START), .start_ready(rotary_ready),
            .mode(global_hold ? 2'd1 : 2'd0), .dimension(dimension_hold[9:0]),
            .pair_index(pair_index[8:0]), .position(token_hold),
            .vector_pair({rotary_second, rotary_first}),
            .done_valid(rotary_valid), .done_ready(rst_n && state == ROTARY_WAIT),
            .done_data(rotary_data), .done_error(rotary_error),
            .arithmetic_valid(arithmetic_valid[FP_ROTARY]),
            .arithmetic_ready(fp_owner == FP_ROTARY && fp_ready),
            .arithmetic_operation(arithmetic_operation[3*FP_ROTARY+:3]),
            .arithmetic_a(arithmetic_a[32*FP_ROTARY+:32]),
            .arithmetic_b(arithmetic_b[32*FP_ROTARY+:32]),
            .arithmetic_result_valid(fp_owner == FP_ROTARY && fp_valid),
            .arithmetic_result_ready(arithmetic_result_ready[FP_ROTARY]),
            .arithmetic_result_data(fp_data), .arithmetic_result_error(fp_error)
        );
        end
        wire attention_ready, attention_valid, query_valid, query_rsp_ready;
        wire attention_component_valid, attention_component_last;
        wire [9:0] query_component, attention_component_index;
        wire [15:0] attention_component_data;
        wire [3:0] attention_error;
        if (POST_ONLY) begin : no_attention
            assign attention_controller_bytes = 0;
            assign attention_ready = 0;
            assign attention_valid = 0;
            assign query_valid = 0;
            assign query_rsp_ready = 0;
            assign query_component = 0;
            assign attention_component_valid = 0;
            assign attention_component_last = 0;
            assign attention_component_index = 0;
            assign attention_component_data = 0;
            assign attention_error = 0;
            assign attention_activity = 0;
            assign mask_valid = 0;
            assign mask_token = 0;
            assign mask_rsp_ready = 0;
            assign req_valid = 0;
            assign req_op = 0;
            assign req_model = 0;
            assign req_layer = 0;
            assign req_token = 0;
            assign req_is_value = 0;
            assign req_kv_head = 0;
            assign req_component = 0;
            assign req_base = 0;
            assign rsp_ready = 0;
            assign fetch_valid = 0;
            assign fetch_model = 0;
            assign fetch_owner = 0;
            assign fetch_token = 0;
            assign fetch_is_value = 0;
            assign fetch_kv_head = 0;
            assign fetch_component = 0;
            assign fetch_rsp_ready = 0;
            assign arithmetic_valid[FP_ATTENTION] = 0;
            assign arithmetic_result_ready[FP_ATTENTION] = 0;
            assign arithmetic_operation[3*FP_ATTENTION+:3] = 0;
            assign arithmetic_a[32*FP_ATTENTION+:32] = 0;
            assign arithmetic_b[32*FP_ATTENTION+:32] = 0;
        end else begin : full_attention
        anvil_en1_attention_head #(.COMPACT(COMPACT), .EXTERNAL_FP(1)) attention_unit (
            .controller_bytes(attention_controller_bytes),
            .clk(clk), .rst_n(rst_n),
            .start_valid(rst_n && state == ATTENTION_START), .start_ready(attention_ready),
            .model(model_hold), .layer(layer_hold), .query_head(head),
            .query_position(token_hold),
            .resume_valid(1'b0), .resume_checkpoint(384'd0),
            .need_valid(), .need_ready(1'b0), .need_action(2'd0),
            .need_model(), .need_owner(), .need_token(), .need_is_value(),
            .need_kv_head(), .need_component(),
            .checkpoint_valid(), .checkpoint_ready(1'b0), .checkpoint_data(),
            .query_valid(query_valid),
            .query_ready(rst_n && src_state == S_IDLE && state == ATTENTION_WAIT),
            .query_component(query_component),
            .query_rsp_valid(rst_n && src_state == S_RESPONSE && src_client == C_QUERY),
            .query_rsp_ready(query_rsp_ready), .query_rsp_data(src_data_hold),
            .query_rsp_error(src_error_hold),
            .mask_valid(mask_valid), .mask_ready(mask_ready), .mask_token(mask_token),
            .mask_rsp_valid(mask_rsp_valid), .mask_rsp_ready(mask_rsp_ready),
            .mask_rsp_data(mask_rsp_data), .mask_rsp_error(mask_rsp_error),
            .req_valid(req_valid), .req_ready(req_ready), .req_op(req_op),
            .req_model(req_model), .req_layer(req_layer), .req_token(req_token),
            .req_is_value(req_is_value), .req_kv_head(req_kv_head),
            .req_component(req_component), .req_base(req_base),
            .rsp_valid(rsp_valid), .rsp_ready(rsp_ready), .rsp_addr(rsp_addr),
            .rsp_owner(rsp_owner), .rsp_alias(rsp_alias), .rsp_error(rsp_error),
            .rsp_space(rsp_space),
            .fetch_valid(fetch_valid), .fetch_ready(fetch_ready),
            .fetch_model(fetch_model), .fetch_owner(fetch_owner), .fetch_token(fetch_token),
            .fetch_is_value(fetch_is_value), .fetch_kv_head(fetch_kv_head),
            .fetch_component(fetch_component),
            .fetch_rsp_valid(fetch_rsp_valid), .fetch_rsp_ready(fetch_rsp_ready),
            .fetch_rsp_data(fetch_rsp_data), .fetch_rsp_error(fetch_rsp_error),
            .component_valid(attention_component_valid),
            .component_ready(rst_n && state == ATTENTION_WAIT &&
                (output_state == O_ACK || output_state == O_DRAIN)),
            .component_index(attention_component_index),
            .component_data(attention_component_data),
            .component_last(attention_component_last),
            .done_valid(attention_valid), .done_ready(rst_n && state == ATTENTION_WAIT),
            .done_error(attention_error), .attention_activity(attention_activity),
            .arithmetic_valid(arithmetic_valid[FP_ATTENTION]),
            .arithmetic_ready(fp_owner == FP_ATTENTION && fp_ready),
            .arithmetic_operation(arithmetic_operation[3*FP_ATTENTION+:3]),
            .arithmetic_a(arithmetic_a[32*FP_ATTENTION+:32]),
            .arithmetic_b(arithmetic_b[32*FP_ATTENTION+:32]),
            .arithmetic_result_valid(fp_owner == FP_ATTENTION && fp_valid),
            .arithmetic_result_ready(arithmetic_result_ready[FP_ATTENTION]),
            .arithmetic_result_data(fp_data), .arithmetic_result_error(fp_error)
        );
        end
        wire gated_ready, gated_valid, gated_cmd_valid, gated_result_ready;
        wire gated_source_valid, gated_source_rsp_ready, gated_up_valid, gated_up_rsp_ready;
        wire [31:0] gated_data, gated_source_index, gated_up_index;
        wire [63:0] gated_cmd_addr;
        wire [3:0] gated_error;
        anvil_en1_gated_projection #(.EXTERNAL_FP(1)) gated_unit (
            .controller_bytes(gated_controller_bytes),
            .clk(clk), .rst_n(rst_n),
            .start_valid(rst_n && state == GATED_START), .start_ready(gated_ready),
            .precision(precision_hold), .activation(2'd0), .up_mode(gated_ple ? 2'd1 : 2'd0),
            .gate_base(gate_base_hold), .gate_bytes(gate_bytes_hold),
            .up_base(up_base_hold), .up_bytes(up_bytes_hold),
            .down_base(down_base_hold), .down_bytes(down_bytes_hold),
            .gate_rows(gate_rows_hold), .gate_columns(gate_columns_hold),
            .gate_stride(gate_stride_hold),
            .up_rows(up_rows_hold), .up_columns(up_columns_hold), .up_stride(up_stride_hold),
            .down_rows(down_rows_hold), .down_columns(down_columns_hold),
            .down_stride(down_stride_hold), .down_row(index),
            .source_valid(gated_source_valid),
            .source_ready(rst_n && src_state == S_IDLE && state == GATED_WAIT),
            .source_index(gated_source_index),
            .source_rsp_valid(rst_n && src_state == S_RESPONSE && src_client == C_GATED),
            .source_rsp_ready(gated_source_rsp_ready),
            .source_rsp_data(src_data_hold), .source_rsp_error(src_error_hold),
            .up_valid(gated_up_valid),
            .up_ready(rst_n && src_state == S_IDLE && state == GATED_WAIT),
            .up_index(gated_up_index),
            .up_rsp_valid(rst_n && src_state == S_RESPONSE && src_client == C_UP),
            .up_rsp_ready(gated_up_rsp_ready), .up_rsp_data(src_data_hold),
            .up_rsp_error(src_error_hold),
            .cmd_valid(gated_cmd_valid),
            .cmd_ready(rst_n && memory_owner == M_GATED && cmd_ready),
            .cmd_write(), .cmd_addr(gated_cmd_addr), .cmd_wdata(),
            .result_valid(rst_n && memory_owner == M_GATED && result_valid),
            .result_ready(gated_result_ready), .result_data(result_data),
            .result_error(result_error),
            .done_valid(gated_valid), .done_ready(rst_n && state == GATED_WAIT),
            .done_data(gated_data), .done_error(gated_error),
            .arithmetic_valid(arithmetic_valid[FP_GATED]),
            .arithmetic_ready(fp_owner == FP_GATED && fp_ready),
            .arithmetic_operation(arithmetic_operation[3*FP_GATED+:3]),
            .arithmetic_a(arithmetic_a[32*FP_GATED+:32]),
            .arithmetic_b(arithmetic_b[32*FP_GATED+:32]),
            .arithmetic_result_valid(fp_owner == FP_GATED && fp_valid),
            .arithmetic_result_ready(arithmetic_result_ready[FP_GATED]),
            .arithmetic_result_data(fp_data), .arithmetic_result_error(fp_error)
        );
        wire weight_ready, weight_valid, weight_cmd_valid, weight_result_ready;
        wire [31:0] weight_data;
        wire [63:0] weight_cmd_addr;
        wire [3:0] weight_error;
        anvil_en1_weight_read #(.EXTERNAL_FP(1)) weight_reader (
            .controller_bytes(weight_controller_bytes),
            .clk(clk), .rst_n(rst_n),
            .start_valid(rst_n && (scale_state == W_START || state == SCALAR_START ||
                output_state == O_WEIGHT_START)),
            .start_ready(weight_ready),
            .precision(output_state == O_WEIGHT_START || output_state == O_WEIGHT_WAIT ?
                precision_hold : 2'd0),
            .tensor_base(state == ATTENTION_WAIT ? gate_base_hold : scale_base),
            .tensor_bytes(state == ATTENTION_WAIT ? gate_bytes_hold : scale_bytes),
            .tensor_rows(state == ATTENTION_WAIT ? gate_rows_hold : 32'd1),
            .tensor_columns(state == ATTENTION_WAIT ? gate_columns_hold : scale_columns),
            .row_stride(state == ATTENTION_WAIT ? gate_stride_hold : scale_stride),
            .row_index(state == ATTENTION_WAIT ? output_row : 32'd0),
            .column_index(state == ATTENTION_WAIT ?
                head_offset + {22'd0, attention_component_index} :
                (state == SCALAR_START || state == SCALAR_WAIT ?
                    32'd0 : scale_index_hold)),
            .cmd_valid(weight_cmd_valid),
            .cmd_ready(rst_n && memory_owner == M_WEIGHT && cmd_ready),
            .cmd_write(), .cmd_addr(weight_cmd_addr), .cmd_wdata(),
            .result_valid(rst_n && memory_owner == M_WEIGHT && result_valid),
            .result_ready(weight_result_ready), .result_data(result_data),
            .result_error(result_error),
            .done_valid(weight_valid),
            .done_ready(rst_n && (scale_state == W_WAIT || state == SCALAR_WAIT ||
                output_state == O_WEIGHT_WAIT)),
            .done_data(weight_data), .done_error(weight_error),
            .arithmetic_valid(arithmetic_valid[FP_WEIGHT]),
            .arithmetic_ready(fp_owner == FP_WEIGHT && fp_ready),
            .arithmetic_operation(arithmetic_operation[3*FP_WEIGHT+:3]),
            .arithmetic_a(arithmetic_a[32*FP_WEIGHT+:32]),
            .arithmetic_b(arithmetic_b[32*FP_WEIGHT+:32]),
            .arithmetic_result_valid(fp_owner == FP_WEIGHT && fp_valid),
            .arithmetic_result_ready(arithmetic_result_ready[FP_WEIGHT]),
            .arithmetic_result_data(fp_data), .arithmetic_result_error(fp_error)
        );
        anvil_en1_fp32 fp_unit (
            .controller_bytes(fp_controller_bytes),
            .clk(clk), .rst_n(rst_n),
            .start_valid(rst_n && (fp_owner == FP_LOCAL ?
                state == FP_START : arithmetic_valid[fp_owner])),
            .start_ready(fp_ready),
            .operation(fp_owner == FP_LOCAL ? fp_op : arithmetic_operation[3*fp_owner+:3]),
            .operand_a(fp_owner == FP_LOCAL ? fp_a : arithmetic_a[32*fp_owner+:32]),
            .operand_b(fp_owner == FP_LOCAL ? fp_b : arithmetic_b[32*fp_owner+:32]),
            .done_valid(fp_valid),
            .done_ready(rst_n && (fp_owner == FP_LOCAL ?
                state == FP_WAIT : arithmetic_result_ready[fp_owner])),
            .done_data(fp_data), .done_error(fp_error)
        );

        wire [31:0] head_offset = COMPACT ?
            ({28'd0, head} << (global_hold ? 3 : 2)) :
            ({28'd0, head} << (global_hold ? 9 : 8));
        wire [31:0] rotary_second_index = pair_index + (dimension_hold >> 1);
        wire norm_write = rst_n && state == NORM_WAIT && normalized_valid;
        wire residual_read = rst_n && ((src_state == S_READ && src_bank == B_RESIDUAL) ||
            state == RESIDUAL_READ || state == SCALAR_READ || state == OUTPUT_READ);
        wire [31:0] residual_read_index = src_state == S_READ ? src_index_hold : index;
        wire branch_read = rst_n && ((src_state == S_READ && src_bank == B_BRANCH) ||
            state == RESIDUAL_READ);
        wire [31:0] branch_read_index = src_state == S_READ ? src_index_hold : index;
        wire query_read = rst_n && ((src_state == S_READ && src_bank == B_QUERY) ||
            state == ROTARY_FIRST_READ || state == ROTARY_SECOND_READ);
        wire [31:0] query_read_index = src_state == S_READ ? src_index_hold :
            (state == ROTARY_FIRST_READ ? pair_index : rotary_second_index);
        wire residual_load = state == LOAD_WRITE && !load_ple && !load_branch;
        wire branch_norm = norm_write &&
            (norm_destination == B_BRANCH || norm_destination == B_QUERY);
        wire [3:0] bank_write = {
            rst_n && state == LOAD_WRITE && load_ple,
            rst_n && (branch_norm || (state == LOAD_WRITE && load_branch) ||
                state == PROJECTION_WRITE || state == GATED_WRITE ||
                state == ROTARY_FIRST_WRITE || state == ROTARY_SECOND_WRITE),
            norm_write && norm_destination == B_WORK,
            rst_n && (residual_load || state == RESIDUAL_WRITE || state == SCALAR_WRITE)
        };
        wire [3:0] bank_read = {
            rst_n && src_state == S_READ && src_bank == B_PLE,
            branch_read || query_read,
            rst_n && src_state == S_READ && src_bank == B_WORK,
            residual_read
        };
        wire [47:0] bank_waddr = {index[11:0],
            (branch_norm ? normalized_index[11:0] :
                (state == ROTARY_FIRST_WRITE ? pair_index[11:0] :
                (state == ROTARY_SECOND_WRITE ? rotary_second_index[11:0] : index[11:0]))),
            normalized_index[11:0], index[11:0]};
        wire [47:0] bank_raddr = {src_index_hold[11:0],
            (branch_read ? branch_read_index[11:0] : query_read_index[11:0]),
            src_index_hold[11:0], residual_read_index[11:0]};
        wire [63:0] bank_wdata = {load_data,
            (branch_norm ? normalized_data : (state == LOAD_WRITE ? load_data :
                (state == ROTARY_FIRST_WRITE ? rotary_data_hold[15:0] :
                (state == ROTARY_SECOND_WRITE ? rotary_data_hold[31:16] : branch_data_hold)))),
            normalized_data, (residual_load ? load_data : value_hold[15:0])};
        wire [63:0] bank_rdata;
        assign {ple_q, branch_q, work_q, residual_q} = bank_rdata;
        assign vector_ram_write = EXTERNAL_VECTOR_RAM ? bank_write : 4'd0;
        assign vector_ram_read = EXTERNAL_VECTOR_RAM ? bank_read : 4'd0;
        assign vector_ram_waddr = rst_n && EXTERNAL_VECTOR_RAM ? bank_waddr : 48'd0;
        assign vector_ram_raddr = rst_n && EXTERNAL_VECTOR_RAM ? bank_raddr : 48'd0;
        assign vector_ram_wdata = rst_n && EXTERNAL_VECTOR_RAM ? bank_wdata : 64'd0;
        if (EXTERNAL_VECTOR_RAM) begin : external_vectors
            assign bank_rdata = vector_ram_rdata;
        end else begin : internal_vectors
            genvar bank;
            for (bank=0; bank<4; bank=bank+1) begin : banks
                localparam integer BANK_WORDS = bank == 3 ? P : MAX_H;
                localparam integer BANK_BITS = bank == 3 ? P_BITS : H_BITS;
                (* ramstyle = "M20K", nomem2reg *)
                reg [15:0] payload [0:BANK_WORDS-1];
                reg [15:0] read_q;
                assign bank_rdata[16*bank+:16] = read_q;
                always @(posedge clk) begin
                    if (bank_write[bank])
                        payload[bank_waddr[12*bank+:BANK_BITS]] <= bank_wdata[16*bank+:16];
                    if (bank_read[bank])
                        read_q <= payload[bank_raddr[12*bank+:BANK_BITS]];
                end
            end
        end
        if (POST_ONLY) begin : no_attention_payload
            assign attention_q = 16'd0;
        end else begin : full_attention_payload
            (* ramstyle = "M20K", nomem2reg *)
            reg [15:0] payload [0:MAX_H-1];
            reg [15:0] read_q;
            assign attention_q = read_q;
            always @(posedge clk) begin
                if (rst_n && state == OUTPUT_ROW_WRITE)
                    payload[output_row[H_BITS-1:0]] <= value_hold[15:0];
                if (rst_n && src_state == S_READ && src_bank == B_ATTENTION)
                    read_q <= payload[src_index_hold[H_BITS-1:0]];
            end
        end

        assign start_ready = rst_n && state == IDLE;
        wire [63:0] live_residual_work =
            (residual_allocated && !SHARED_RESIDUAL ?
                {32'd0, hidden_hold} << 1 : 64'd0) +
            (work_allocated ? {32'd0, hidden_hold} << 1 : 64'd0);
        wire [63:0] live_branch_ple =
            (branch_allocated ? {32'd0, hidden_hold} << 1 :
                (query_allocated ? {32'd0, dimension_hold} << 1 : 64'd0)) +
            (ple_allocated && !SHARED_PLE ? 64'(2*P) : 64'd0);
        wire [63:0] live_attention = attention_allocated ?
            {32'd0, hidden_hold} << 1 : 64'd0;
        assign live_payload_bytes = rst_n ?
            (live_residual_work + live_branch_ple) + live_attention : 64'd0;
        wire [63:0] shadow_hidden = model_hold == 1 ? 64'd3072 : 64'd5120;
        wire [63:0] shadow_head = global_hold ? 64'd1024 : 64'd512;
        wire [63:0] shadow_residual_work =
            (residual_allocated && !SHARED_RESIDUAL ? shadow_hidden : 64'd0) +
            (work_allocated ? shadow_hidden : 64'd0);
        wire [63:0] shadow_branch_ple =
            (branch_allocated ? shadow_hidden :
                (query_allocated ? shadow_head : 64'd0)) +
            (ple_allocated && !SHARED_PLE ? 64'd512 : 64'd0);
        assign production_shadow_bytes = rst_n ?
            (shadow_residual_work + shadow_branch_ple) +
                (attention_allocated ? shadow_hidden : 64'd0) : 64'd0;
        assign physical_payload_bytes = rst_n ?
            64'(2*((EXTERNAL_VECTOR_RAM ? 0 : 3*MAX_H+P) +
                (POST_ONLY ? 0 : MAX_H))) : 64'd0;

        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                residual_allocated <= 0;
                work_allocated <= 0;
                branch_allocated <= 0;
                query_allocated <= 0;
                attention_allocated <= 0;
                ple_allocated <= 0;
            end else if (state == PUBLISH) begin
                residual_allocated <= 0;
                work_allocated <= 0;
                branch_allocated <= 0;
                query_allocated <= 0;
                attention_allocated <= 0;
                ple_allocated <= 0;
            end else begin
                if (state == VALIDATE && native_model && precision_hold <= 1 &&
                    layer_hold < layer_count && token_hold <= 131071 &&
                    weights_hold[1:0] == 0)
                    residual_allocated <= 1;
                if (state == LOAD_START && source_ready && load_ple)
                    ple_allocated <= 1;
                if (state == LOAD_START && source_ready && load_branch)
                    branch_allocated <= 1;
                if (state == NORM_SETUP && (norm_phase == N_INPUT || norm_phase == N_PRE_FF))
                    work_allocated <= 1;
                if (state == QUERY_DESCRIPTOR)
                    query_allocated <= 1;
                if (state == OUTPUT_PROJECTION_DESCRIPTOR)
                    attention_allocated <= 1;
                if (state == ATTENTION_WAIT && attention_valid) begin
                    query_allocated <= 0;
                    if (head + 1'b1 == Q && output_row + 1'b1 == hidden_hold)
                        work_allocated <= 0;
                end
                if (state == NORM_SETUP && norm_phase == N_POST_ATTENTION)
                    branch_allocated <= 1;
                if ((state == PROJECTION_START && projection_ready && !projection_query) ||
                    (state == GATED_START && gated_ready))
                    branch_allocated <= 1;
                if (state == NORM_WAIT && norm_valid && norm_phase == N_POST_ATTENTION)
                    attention_allocated <= 0;
                if (state == RESIDUAL_WRITE && index + 1'b1 == hidden_hold)
                    branch_allocated <= 0;
                if (state == GATED_WRITE && index + 1'b1 == hidden_hold) begin
                    if (gated_ple)
                        ple_allocated <= 0;
                    else
                        work_allocated <= 0;
                end
                if (output_valid && output_ready && output_last)
                    residual_allocated <= 0;
            end
        end
        assign source_valid = rst_n && state == LOAD_START;
        assign source_model = rst_n ? model_hold : 2'd0;
        assign source_layer = rst_n ? layer_hold : 8'd0;
        assign source_token = rst_n ? token_hold : 32'd0;
        assign source_index = rst_n ? index : 32'd0;
        assign source_is_ple = rst_n && load_ple;
        assign source_is_branch = rst_n && load_branch;
        assign source_rsp_ready = rst_n && state == LOAD_WAIT;
        assign cmd_valid = rst_n && (memory_owner == M_LOOKUP ? lookup_cmd_valid :
            memory_owner == M_PROJECTION ? projection_cmd_valid :
            memory_owner == M_GATED ? gated_cmd_valid : weight_cmd_valid);
        assign cmd_write = 0;
        assign cmd_addr = rst_n ? (memory_owner == M_LOOKUP ? lookup_cmd_addr :
            memory_owner == M_PROJECTION ? projection_cmd_addr :
            memory_owner == M_GATED ? gated_cmd_addr : weight_cmd_addr) : 64'd0;
        assign cmd_wdata = 0;
        assign result_ready = rst_n && (memory_owner == M_LOOKUP ? lookup_result_ready :
            memory_owner == M_PROJECTION ? projection_result_ready :
            memory_owner == M_GATED ? gated_result_ready : weight_result_ready);
        assign output_valid = rst_n && state == OUTPUT_WAIT;
        assign output_index = rst_n ? index : 32'd0;
        assign output_data = rst_n ? output_hold : 16'd0;
        assign output_last = rst_n && state == OUTPUT_WAIT && index == hidden_hold - 1'b1;
        assign done_valid = rst_n && state == RESPONSE;
        assign done_error = rst_n ? error_hold : 4'd0;
        assign avoided_projection_event = done_valid && done_ready && error_hold == 0 &&
            layer_hold >= (model_hold == 1 ? 8'd15 : 8'd24);
        assign avoided_projection_bytes = !avoided_projection_event ? 32'd0 :
            dimension_hold << ((COMPACT || model_hold == 1) ? 2 : 3);

        wire [31:0] src_limit = src_bank == B_QUERY ? dimension_hold :
            src_bank == B_PLE ? 32'(P) : hidden_hold;
        wire src_allocated = src_bank == B_RESIDUAL ? residual_allocated :
            src_bank == B_WORK ? work_allocated :
            src_bank == B_BRANCH ? branch_allocated :
            src_bank == B_QUERY ? query_allocated :
            src_bank == B_ATTENTION ? attention_allocated :
            src_bank == B_PLE ? ple_allocated : 1'b0;
        wire src_response_ready = src_client == C_NORM ? norm_source_rsp_ready :
            src_client == C_PROJECTION ? projection_source_rsp_ready :
            src_client == C_GATED ? gated_source_rsp_ready :
            src_client == C_QUERY ? query_rsp_ready : gated_up_rsp_ready;
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                src_state <= S_IDLE;
                src_client <= 0;
                src_bank <= 0;
                src_index_hold <= 0;
                src_data_hold <= 0;
                src_error_hold <= 0;
            end else begin
                case (src_state)
                    S_IDLE: begin
                        if (state == NORM_WAIT && norm_source_valid) begin
                            src_client <= C_NORM;
                            src_bank <= norm_bank;
                            src_index_hold <= norm_source_index;
                            src_state <= S_READ;
                        end else if (state == PROJECTION_WAIT && projection_source_valid) begin
                            src_client <= C_PROJECTION;
                            if (projection_query)
                                src_bank <= B_WORK;
                            else
                                src_bank <= B_ATTENTION;
                            src_index_hold <= projection_source_index;
                            src_state <= S_READ;
                        end else if (state == GATED_WAIT && gated_source_valid) begin
                            src_client <= C_GATED;
                            if (gated_ple)
                                src_bank <= B_RESIDUAL;
                            else
                                src_bank <= B_WORK;
                            src_index_hold <= gated_source_index;
                            src_state <= S_READ;
                        end else if (state == GATED_WAIT && gated_up_valid) begin
                            src_client <= C_UP;
                            src_bank <= B_PLE;
                            src_index_hold <= gated_up_index;
                            src_state <= S_READ;
                        end else if (state == ATTENTION_WAIT && query_valid) begin
                            src_client <= C_QUERY;
                            src_bank <= B_QUERY;
                            src_index_hold <= {22'd0, query_component};
                            src_state <= S_READ;
                        end
                    end
                    S_READ: begin
                        src_error_hold <= !src_allocated || src_index_hold >= src_limit;
                        src_state <= S_PUBLISH;
                    end
                    S_PUBLISH: begin
                        if (src_error_hold)
                            src_data_hold <= 0;
                        else begin
                            case (src_bank)
                                B_RESIDUAL: src_data_hold <= residual_q;
                                B_WORK: src_data_hold <= work_q;
                                B_BRANCH: src_data_hold <= branch_q;
                                B_QUERY: src_data_hold <= query_q;
                                B_ATTENTION: src_data_hold <= attention_q;
                                B_PLE: src_data_hold <= ple_q;
                                default: begin
                                    src_data_hold <= 0;
                                    src_error_hold <= 1;
                                end
                            endcase
                        end
                        src_state <= S_RESPONSE;
                    end
                    S_RESPONSE: if (src_response_ready)
                        src_state <= S_IDLE;
                    default: src_state <= S_IDLE;
                endcase
            end
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
                        scale_state <= W_START;
                    end
                    W_START: if (weight_ready)
                        scale_state <= W_WAIT;
                    W_WAIT: if (weight_valid) begin
                        scale_data_hold <= weight_data[31:16];
                        scale_error_hold <= weight_error != 0;
                        scale_state <= W_PUBLISH;
                    end
                    W_PUBLISH: scale_state <= W_RESPONSE;
                    W_RESPONSE: if (norm_scale_rsp_ready)
                        scale_state <= W_IDLE;
                    default: scale_state <= W_IDLE;
                endcase
            end
        end

        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                output_state <= O_IDLE;
                output_error <= 0;
                output_accumulator <= 0;
                output_value <= 0;
                output_weight <= 0;
            end else if (state == IDLE || state == PUBLISH) begin
                output_state <= O_IDLE;
                output_error <= 0;
                output_accumulator <= 0;
                output_value <= 0;
                output_weight <= 0;
            end else if (state == OUTPUT_PROJECTION_DESCRIPTOR ||
                state == OUTPUT_ROW_WRITE) begin
                output_state <= O_IDLE;
                output_accumulator <= 0;
            end else begin
                case (output_state)
                    O_IDLE: if (state == ATTENTION_WAIT && attention_component_valid)
                        output_state <= O_WEIGHT_START;
                    O_WEIGHT_START: if (weight_ready)
                        output_state <= O_WEIGHT_WAIT;
                    O_WEIGHT_WAIT: if (weight_valid) begin
                        if (weight_error != 0) begin
                            output_error <= weight_error;
                            output_state <= O_DRAIN;
                        end else begin
                            output_weight <= weight_data;
                            output_state <= O_CONVERT_START;
                        end
                    end
                    O_CONVERT_START: if (fp_ready)
                        output_state <= O_CONVERT_WAIT;
                    O_MULTIPLY_START: if (fp_ready)
                        output_state <= O_MULTIPLY_WAIT;
                    O_ADD_START: if (fp_ready)
                        output_state <= O_ADD_WAIT;
                    O_CONVERT_WAIT, O_MULTIPLY_WAIT, O_ADD_WAIT: if (fp_valid) begin
                        if (fp_error != 0) begin
                            output_error <= fp_error;
                            output_state <= O_DRAIN;
                        end else if (output_state == O_CONVERT_WAIT) begin
                            output_value <= fp_data;
                            output_state <= O_MULTIPLY_START;
                        end else if (output_state == O_MULTIPLY_WAIT) begin
                            output_value <= fp_data;
                            output_state <= O_ADD_START;
                        end else begin
                            output_accumulator <= fp_data;
                            output_state <= O_ACK;
                        end
                    end
                    O_ACK: if (state == ATTENTION_WAIT && attention_component_valid)
                        output_state <= O_IDLE;
                    O_DRAIN: begin end
                    default: begin
                        output_error <= 7;
                        output_state <= O_DRAIN;
                    end
                endcase
            end
        end
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                state <= IDLE;
                lookup_return <= 0;
                fp_return <= 0;
                narrow_return <= 0;
                norm_phase <= 0;
                norm_bank <= 0;
                norm_destination <= 0;
                model_hold <= 0;
                precision_hold <= 0;
                memory_owner <= 0;
                residual_phase <= 0;
                layer_hold <= 0;
                token_hold <= 0;
                hidden_hold <= 0;
                dimension_hold <= 0;
                weights_hold <= 0;
                global_hold <= 0;
                load_ple <= 0;
                load_branch <= 0;
                projection_query <= 0;
                gated_ple <= 0;
                head <= 0;
                index <= 0;
                pair_index <= 0;
                norm_length <= 0;
                projection_row <= 0;
                lookup_kind <= 0;
                load_data <= 0;
                output_hold <= 0;
                load_error <= 0;
                descriptor_base <= 0;
                descriptor_bytes <= 0;
                descriptor_rows <= 0;
                descriptor_columns <= 0;
                descriptor_stride <= 0;
                scale_base <= 0;
                scale_bytes <= 0;
                scale_columns <= 0;
                scale_stride <= 0;
                gate_base_hold <= 0;
                gate_bytes_hold <= 0;
                up_base_hold <= 0;
                up_bytes_hold <= 0;
                down_base_hold <= 0;
                down_bytes_hold <= 0;
                gate_rows_hold <= 0;
                gate_columns_hold <= 0;
                gate_stride_hold <= 0;
                up_rows_hold <= 0;
                up_columns_hold <= 0;
                up_stride_hold <= 0;
                down_rows_hold <= 0;
                down_columns_hold <= 0;
                down_stride_hold <= 0;
                scalar_hold <= 0;
                fp_a <= 0;
                fp_b <= 0;
                value_hold <= 0;
                rotary_data_hold <= 0;
                branch_data_hold <= 0;
                residual_data_hold <= 0;
                rotary_first <= 0;
                rotary_second <= 0;
                fp_op <= 0;
                error_hold <= 0;
                output_row <= 0;
            end else begin
                case (state)
                    IDLE: if (start_valid && start_ready) begin
                        model_hold <= model;
                        precision_hold <= precision;
                        layer_hold <= layer;
                        token_hold <= token;
                        weights_hold <= weights_base;
                        load_ple <= 0;
                        load_branch <= 0;
                        index <= 0;
                        head <= 0;
                        output_row <= 0;
                        gated_ple <= 0;
                        error_hold <= 0;
                        output_hold <= 0;
                        state <= VALIDATE;
                    end
                    VALIDATE: begin
                        if (!native_model || precision_hold > 1) begin
                            error_hold <= 6;
                            state <= PUBLISH;
                        end else if (layer_hold >= layer_count || token_hold > 131071 ||
                            weights_hold[1:0] != 0) begin
                            error_hold <= 5;
                            state <= PUBLISH;
                        end else begin
                            hidden_hold <= COMPACT ? 32'd8 : {20'd0, selected_hidden};
                            dimension_hold <= COMPACT ?
                                (selected_global ? 32'd8 : 32'd4) :
                                (selected_global ? 32'd512 : 32'd256);
                            global_hold <= selected_global;
                            state <= LOAD_START;
                        end
                    end
                    LOAD_START: if (source_ready)
                        state <= LOAD_WAIT;
                    LOAD_WAIT: if (source_rsp_valid) begin
                        load_data <= source_rsp_data;
                        load_error <= source_rsp_error;
                        state <= LOAD_CHECK;
                    end
                    LOAD_CHECK: begin
                        if (load_error) begin
                            error_hold <= 7;
                            state <= PUBLISH;
                        end else
                            state <= LOAD_WRITE;
                    end
                    LOAD_WRITE: begin
                        if (index + 1'b1 == (load_ple ? 32'(P) : hidden_hold)) begin
                            index <= 0;
                            if (load_branch) begin
                                load_branch <= 0;
                                norm_phase <= N_POST_ATTENTION;
                                state <= NORM_SETUP;
                            end else if (load_ple && POST_ONLY) begin
                                load_ple <= 0;
                                load_branch <= 1;
                                state <= LOAD_START;
                            end else if (load_ple) begin
                                norm_phase <= N_INPUT;
                                state <= NORM_SETUP;
                            end else begin
                                load_ple <= 1;
                                state <= LOAD_START;
                            end
                        end else begin
                            index <= index + 1'b1;
                            state <= LOAD_START;
                        end
                    end
                    NORM_SETUP: begin
                        memory_owner <= M_LOOKUP;
                        lookup_return <= NORM_DESCRIPTOR;
                        norm_length <= hidden_hold;
                        norm_bank <= B_BRANCH;
                        norm_destination <= B_BRANCH;
                        case (norm_phase)
                            N_INPUT: begin
                                lookup_kind <= 16'h0100;
                                norm_bank <= B_RESIDUAL;
                                norm_destination <= B_WORK;
                            end
                            N_QUERY: begin
                                lookup_kind <= 16'h0102;
                                norm_length <= dimension_hold;
                                norm_bank <= B_QUERY;
                                norm_destination <= B_QUERY;
                            end
                            N_POST_ATTENTION: begin
                                lookup_kind <= 16'h0107;
                                if (!POST_ONLY)
                                    norm_bank <= B_ATTENTION;
                            end
                            N_PRE_FF: begin
                                lookup_kind <= 16'h0108;
                                norm_bank <= B_RESIDUAL;
                                norm_destination <= B_WORK;
                            end
                            N_POST_FF: lookup_kind <= 16'h010c;
                            N_POST_PLE: lookup_kind <= 16'h010f;
                            default: lookup_kind <= 0;
                        endcase
                        if (norm_phase > N_POST_PLE) begin
                            error_hold <= 7;
                            state <= PUBLISH;
                        end else
                            state <= LOOKUP_START;
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
                            state <= LOOKUP_REGISTER;
                        end
                    end
                    LOOKUP_REGISTER: state <= lookup_return;
                    NORM_DESCRIPTOR: begin
                        scale_base <= descriptor_base;
                        scale_bytes <= descriptor_bytes;
                        scale_columns <= descriptor_columns;
                        scale_stride <= descriptor_stride;
                        memory_owner <= M_WEIGHT;
                        state <= NORM_START;
                    end
                    NORM_START: if (norm_ready)
                        state <= NORM_WAIT;
                    NORM_WAIT: if (norm_valid) begin
                        if (norm_error != 0) begin
                            error_hold <= norm_error;
                            state <= PUBLISH;
                        end else begin
                            index <= 0;
                            case (norm_phase)
                                N_INPUT: state <= OUTPUT_PROJECTION_LOOKUP;
                                N_QUERY: begin
                                    pair_index <= 0;
                                    state <= ROTARY_FIRST_READ;
                                end
                                N_POST_ATTENTION: begin
                                    residual_phase <= 0;
                                    state <= RESIDUAL_READ;
                                end
                                N_PRE_FF: begin
                                    gated_ple <= 0;
                                    state <= GATE_LOOKUP;
                                end
                                N_POST_FF: begin
                                    residual_phase <= 1;
                                    state <= RESIDUAL_READ;
                                end
                                N_POST_PLE: begin
                                    residual_phase <= 2;
                                    state <= RESIDUAL_READ;
                                end
                                default: begin
                                    error_hold <= 7;
                                    state <= PUBLISH;
                                end
                            endcase
                        end
                    end
                    QUERY_LOOKUP: begin
                        lookup_kind <= 16'h0101;
                        lookup_return <= QUERY_DESCRIPTOR;
                        memory_owner <= M_LOOKUP;
                        state <= LOOKUP_START;
                    end
                    QUERY_DESCRIPTOR: begin
                        projection_query <= 1;
                        projection_row <= head_offset;
                        index <= 0;
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
                            branch_data_hold <= projection_data[15:0];
                            state <= PROJECTION_WRITE;
                        end
                    end
                    PROJECTION_WRITE: begin
                        if (index + 1'b1 == (projection_query ? dimension_hold : hidden_hold)) begin
                            if (projection_query)
                                norm_phase <= N_QUERY;
                            else
                                norm_phase <= N_POST_ATTENTION;
                            state <= NORM_SETUP;
                        end else begin
                            index <= index + 1'b1;
                            projection_row <= projection_row + 1'b1;
                            state <= PROJECTION_START;
                        end
                    end
                    ROTARY_FIRST_READ: state <= ROTARY_FIRST_CAPTURE;
                    ROTARY_FIRST_CAPTURE: begin
                        rotary_first <= query_q;
                        state <= ROTARY_SECOND_READ;
                    end
                    ROTARY_SECOND_READ: state <= ROTARY_SECOND_CAPTURE;
                    ROTARY_SECOND_CAPTURE: begin
                        rotary_second <= query_q;
                        state <= ROTARY_START;
                    end
                    ROTARY_START: if (rotary_ready)
                        state <= ROTARY_WAIT;
                    ROTARY_WAIT: if (rotary_valid) begin
                        if (rotary_error != 0) begin
                            error_hold <= rotary_error;
                            state <= PUBLISH;
                        end else begin
                            rotary_data_hold <= rotary_data;
                            state <= ROTARY_FIRST_WRITE;
                        end
                    end
                    ROTARY_FIRST_WRITE: state <= ROTARY_SECOND_WRITE;
                    ROTARY_SECOND_WRITE: begin
                        if (pair_index + 1'b1 == (dimension_hold >> 1))
                            state <= ATTENTION_START;
                        else begin
                            pair_index <= pair_index + 1'b1;
                            state <= ROTARY_FIRST_READ;
                        end
                    end
                    ATTENTION_START: if (attention_ready)
                        state <= ATTENTION_WAIT;
                    ATTENTION_WAIT: if (attention_valid) begin
                        if (attention_error != 0 || output_error != 0) begin
                            error_hold <= output_error != 0 ? output_error : attention_error;
                            state <= PUBLISH;
                        end else if (head + 1'b1 == Q)
                            state <= OUTPUT_ROW_NARROW;
                        else begin
                            head <= head + 1'b1;
                            state <= QUERY_LOOKUP;
                        end
                    end
                    OUTPUT_PROJECTION_LOOKUP: begin
                        lookup_kind <= 16'h0106;
                        lookup_return <= OUTPUT_PROJECTION_DESCRIPTOR;
                        memory_owner <= M_LOOKUP;
                        state <= LOOKUP_START;
                    end
                    OUTPUT_PROJECTION_DESCRIPTOR: begin
                        gate_base_hold <= descriptor_base;
                        gate_bytes_hold <= descriptor_bytes;
                        gate_rows_hold <= descriptor_rows;
                        gate_columns_hold <= descriptor_columns;
                        gate_stride_hold <= descriptor_stride;
                        state <= QUERY_LOOKUP;
                    end
                    OUTPUT_ROW_NARROW: begin
                        fp_op <= 3;
                        fp_a <= output_accumulator;
                        fp_b <= 0;
                        fp_return <= OUTPUT_ROW_WRITE;
                        state <= FP_START;
                    end
                    OUTPUT_ROW_WRITE: begin
                        head <= 0;
                        if (output_row + 1'b1 == hidden_hold) begin
                            norm_phase <= N_POST_ATTENTION;
                            state <= NORM_SETUP;
                        end else begin
                            output_row <= output_row + 1'b1;
                            state <= QUERY_LOOKUP;
                        end
                    end
                    RESIDUAL_READ: state <= RESIDUAL_CAPTURE;
                    RESIDUAL_CAPTURE: begin
                        residual_data_hold <= residual_q;
                        branch_data_hold <= branch_q;
                        state <= RESIDUAL_ADD;
                    end
                    RESIDUAL_ADD: begin
                        fp_op <= 0;
                        fp_a <= {residual_data_hold, 16'd0};
                        fp_b <= {branch_data_hold, 16'd0};
                        fp_return <= NARROW;
                        narrow_return <= RESIDUAL_WRITE;
                        state <= FP_START;
                    end
                    NARROW: begin
                        fp_op <= 3;
                        fp_a <= value_hold;
                        fp_b <= 0;
                        fp_return <= narrow_return;
                        state <= FP_START;
                    end
                    RESIDUAL_WRITE: begin
                        if (index + 1'b1 == hidden_hold) begin
                            index <= 0;
                            if (residual_phase == 0) begin
                                norm_phase <= N_PRE_FF;
                                state <= NORM_SETUP;
                            end else if (residual_phase == 1) begin
                                gated_ple <= 1;
                                state <= GATE_LOOKUP;
                            end else
                                state <= SCALAR_LOOKUP;
                        end else begin
                            index <= index + 1'b1;
                            state <= RESIDUAL_READ;
                        end
                    end
                    GATE_LOOKUP: begin
                        lookup_kind <= gated_ple ? 16'h010d : 16'h0109;
                        lookup_return <= GATE_DESCRIPTOR;
                        memory_owner <= M_LOOKUP;
                        state <= LOOKUP_START;
                    end
                    GATE_DESCRIPTOR: begin
                        gate_base_hold <= descriptor_base;
                        gate_bytes_hold <= descriptor_bytes;
                        gate_rows_hold <= descriptor_rows;
                        gate_columns_hold <= descriptor_columns;
                        gate_stride_hold <= descriptor_stride;
                        if (gated_ple) begin
                            lookup_kind <= 16'h010e;
                            lookup_return <= DOWN_DESCRIPTOR;
                        end else begin
                            lookup_kind <= 16'h010a;
                            lookup_return <= UP_DESCRIPTOR;
                        end
                        state <= LOOKUP_START;
                    end
                    UP_DESCRIPTOR: begin
                        up_base_hold <= descriptor_base;
                        up_bytes_hold <= descriptor_bytes;
                        up_rows_hold <= descriptor_rows;
                        up_columns_hold <= descriptor_columns;
                        up_stride_hold <= descriptor_stride;
                        lookup_kind <= 16'h010b;
                        lookup_return <= DOWN_DESCRIPTOR;
                        state <= LOOKUP_START;
                    end
                    DOWN_DESCRIPTOR: begin
                        down_base_hold <= descriptor_base;
                        down_bytes_hold <= descriptor_bytes;
                        down_rows_hold <= descriptor_rows;
                        down_columns_hold <= descriptor_columns;
                        down_stride_hold <= descriptor_stride;
                        index <= 0;
                        memory_owner <= M_GATED;
                        state <= GATED_START;
                    end
                    GATED_START: if (gated_ready)
                        state <= GATED_WAIT;
                    GATED_WAIT: if (gated_valid) begin
                        if (gated_error != 0) begin
                            error_hold <= gated_error;
                            state <= PUBLISH;
                        end else begin
                            branch_data_hold <= gated_data[15:0];
                            state <= GATED_WRITE;
                        end
                    end
                    GATED_WRITE: begin
                        if (index + 1'b1 == hidden_hold) begin
                            if (gated_ple)
                                norm_phase <= N_POST_PLE;
                            else
                                norm_phase <= N_POST_FF;
                            state <= NORM_SETUP;
                        end else begin
                            index <= index + 1'b1;
                            state <= GATED_START;
                        end
                    end
                    SCALAR_LOOKUP: begin
                        lookup_kind <= 16'h0110;
                        lookup_return <= SCALAR_DESCRIPTOR;
                        memory_owner <= M_LOOKUP;
                        state <= LOOKUP_START;
                    end
                    SCALAR_DESCRIPTOR: begin
                        scale_base <= descriptor_base;
                        scale_bytes <= descriptor_bytes;
                        scale_columns <= descriptor_columns;
                        scale_stride <= descriptor_stride;
                        memory_owner <= M_WEIGHT;
                        state <= SCALAR_START;
                    end
                    SCALAR_START: if (weight_ready)
                        state <= SCALAR_WAIT;
                    SCALAR_WAIT: if (weight_valid) begin
                        if (weight_error != 0) begin
                            error_hold <= weight_error;
                            state <= PUBLISH;
                        end else begin
                            scalar_hold <= weight_data;
                            index <= 0;
                            state <= SCALAR_READ;
                        end
                    end
                    SCALAR_READ: state <= SCALAR_CAPTURE;
                    SCALAR_CAPTURE: begin
                        residual_data_hold <= residual_q;
                        state <= SCALAR_MULTIPLY;
                    end
                    SCALAR_MULTIPLY: begin
                        fp_op <= 1;
                        fp_a <= {residual_data_hold, 16'd0};
                        fp_b <= scalar_hold;
                        fp_return <= NARROW;
                        narrow_return <= SCALAR_WRITE;
                        state <= FP_START;
                    end
                    SCALAR_WRITE: begin
                        if (index + 1'b1 == hidden_hold) begin
                            index <= 0;
                            state <= OUTPUT_READ;
                        end else begin
                            index <= index + 1'b1;
                            state <= SCALAR_READ;
                        end
                    end
                    OUTPUT_READ: state <= OUTPUT_CAPTURE;
                    OUTPUT_CAPTURE: begin
                        output_hold <= residual_q;
                        state <= OUTPUT_WAIT;
                    end
                    OUTPUT_WAIT: if (output_ready) begin
                        if (index + 1'b1 == hidden_hold)
                            state <= PUBLISH;
                        else begin
                            index <= index + 1'b1;
                            state <= OUTPUT_READ;
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
                            state <= fp_return;
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
