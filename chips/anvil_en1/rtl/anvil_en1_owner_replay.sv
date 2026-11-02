module anvil_en1_owner_replay #(
    parameter integer COMPACT = 0
) (
    input wire clk, rst_n,
    input wire control_valid,
    output wire control_ready,
    input wire control_invalidate, control_fallback,
    input wire [1:0] control_model, control_precision,
    input wire [31:0] control_generation, control_tokens,
    input wire [63:0] control_weights_base,
    output wire control_rsp_valid,
    input wire control_rsp_ready,
    output wire [3:0] control_error,
    input wire regen_valid,
    output wire regen_ready,
    input wire [1:0] regen_model,
    input wire [7:0] regen_owner,
    input wire [31:0] regen_token,
    input wire regen_is_value,
    input wire [1:0] regen_kv_head,
    input wire [9:0] regen_component,
    output wire regen_rsp_valid,
    input wire regen_rsp_ready,
    output wire [31:0] regen_rsp_data,
    output wire [3:0] regen_rsp_error,
    output wire frontier_read_valid,
    input wire frontier_read_ready,
    output wire [31:0] frontier_read_generation, frontier_read_token,
    output wire [7:0] frontier_read_layer,
    output wire [11:0] frontier_read_component,
    input wire frontier_read_rsp_valid,
    output wire frontier_read_rsp_ready,
    input wire [31:0] frontier_read_rsp_data,
    input wire [3:0] frontier_read_rsp_error,
    output wire ring_read_valid,
    input wire ring_read_ready,
    output wire [1:0] ring_read_model,
    output wire [31:0] ring_read_generation, ring_read_token,
    output wire [7:0] ring_read_owner,
    output wire ring_read_is_value,
    output wire [1:0] ring_read_kv_head,
    output wire [9:0] ring_read_component,
    input wire ring_read_rsp_valid,
    output wire ring_read_rsp_ready,
    input wire ring_read_rsp_hit,
    input wire [31:0] ring_read_rsp_data,
    input wire [3:0] ring_read_rsp_error,
    output wire eval_start_valid,
    input wire eval_start_ready,
    output wire [1:0] eval_model, eval_precision, eval_domain,
    output wire [31:0] eval_generation, eval_token, eval_tokens,
    output wire [7:0] eval_layer,
    input wire eval_output_valid,
    output wire eval_output_ready,
    input wire [31:0] eval_output_index,
    input wire [15:0] eval_output_data,
    input wire eval_output_last,
    input wire eval_done_valid,
    output wire eval_done_ready,
    input wire [3:0] eval_done_error,
    output wire cmd_valid,
    input wire cmd_ready,
    output wire cmd_write,
    output wire [63:0] cmd_addr,
    output wire [31:0] cmd_wdata,
    input wire result_valid,
    output wire result_ready,
    input wire [31:0] result_data,
    input wire result_error,
    output wire [63:0] raw_source_live_bytes, raw_source_physical_bytes,
    output wire [63:0] tile_live_bytes, tile_physical_bytes,
    output wire [63:0] controller_bytes,
    output wire owner_reprojection_event,
    output wire [31:0] owner_reprojection_bytes,
    output wire ring_hit_event,
    output wire busy
);
    generate if (COMPACT != 0 && COMPACT != 1) begin : invalid_parameters
        initial $fatal(1, "PARAMETER ERROR: COMPACT must be 0 or 1");
        assign control_ready = 0;
        assign control_rsp_valid = 0;
        assign control_error = 0;
        assign regen_ready = 0;
        assign regen_rsp_valid = 0;
        assign regen_rsp_data = 0;
        assign regen_rsp_error = 0;
        assign frontier_read_valid = 0;
        assign frontier_read_generation = 0;
        assign frontier_read_token = 0;
        assign frontier_read_layer = 0;
        assign frontier_read_component = 0;
        assign frontier_read_rsp_ready = 0;
        assign ring_read_valid = 0;
        assign ring_read_model = 0;
        assign ring_read_generation = 0;
        assign ring_read_token = 0;
        assign ring_read_owner = 0;
        assign ring_read_is_value = 0;
        assign ring_read_kv_head = 0;
        assign ring_read_component = 0;
        assign ring_read_rsp_ready = 0;
        assign eval_start_valid = 0;
        assign eval_model = 0;
        assign eval_precision = 0;
        assign eval_domain = 0;
        assign eval_generation = 0;
        assign eval_token = 0;
        assign eval_tokens = 0;
        assign eval_layer = 0;
        assign eval_output_ready = 0;
        assign eval_done_ready = 0;
        assign cmd_valid = 0;
        assign cmd_write = 0;
        assign cmd_addr = 0;
        assign cmd_wdata = 0;
        assign result_ready = 0;
        assign raw_source_live_bytes = 0;
        assign raw_source_physical_bytes = 0;
        assign tile_live_bytes = 0;
        assign tile_physical_bytes = 0;
        assign controller_bytes = 0;
        assign owner_reprojection_event = 0;
        assign owner_reprojection_bytes = 0;
        assign ring_hit_event = 0;
        assign busy = 0;
    end else begin : replay
        localparam integer MAX_H = COMPACT ? 8 : 2560;
        localparam integer H_BITS = $clog2(MAX_H);
        localparam [3:0] IDLE = 0, CONTROL_VALIDATE = 1,
            CONTROL_PUBLISH = 2, CONTROL_RESPONSE = 3,
            VALIDATE = 4, RING_SEND = 5, RING_WAIT = 6,
            EVAL_START = 7, EVAL_WAIT = 8, EVAL_COMMIT = 9,
            TILE_START = 10, TILE_WAIT = 11, PUBLISH = 12, RESPONSE = 13;
        localparam [2:0] SOURCE_IDLE = 0, SOURCE_VALIDATE = 1,
            SOURCE_READ = 2, SOURCE_CAPTURE = 3,
            FRONTIER_SEND = 4, FRONTIER_WAIT = 5, SOURCE_RESPONSE = 6;
        reg [3:0] state;
        reg [2:0] source_state;
        reg active, fallback_hold, invalidate_hold, control_fallback_hold;
        reg raw_allocated, raw_committed, vector_bad, vector_complete;
        reg tile_allocated, ring_hit_pulse;
        reg [1:0] model_hold, precision_hold, control_model_hold, control_precision_hold;
        reg [31:0] generation_hold, tokens_hold;
        reg [31:0] control_generation_hold, control_tokens_hold;
        reg [63:0] weights_hold, control_weights_hold;
        reg [1:0] request_model, head_hold;
        reg [7:0] owner_hold;
        reg [31:0] token_hold, hidden_hold, dimension_hold, vector_count;
        reg selector_hold;
        reg [9:0] component_hold;
        reg [3:0] error_hold, eval_error_hold;
        reg [31:0] pair_hold;
        reg [1:0] source_model_hold;
        reg [7:0] source_owner_hold;
        reg [31:0] source_token_hold, source_index_hold;
        reg [15:0] source_data_hold, raw_q;
        reg source_error_hold;
        reg source_normalized_hold, normalized_committed, normalized_bad;
        reg [31:0] normalized_count;
        (* ramstyle = "M20K", nomem2reg *)
        reg [15:0] raw_payload [0:MAX_H-1];
        localparam integer CONTROLLER_BITS = $bits(state) + $bits(source_state) +
            $bits(active) + $bits(fallback_hold) + $bits(invalidate_hold) +
            $bits(control_fallback_hold) + $bits(raw_allocated) +
            $bits(raw_committed) + $bits(vector_bad) + $bits(vector_complete) +
            $bits(tile_allocated) + $bits(ring_hit_pulse) + $bits(model_hold) +
            $bits(precision_hold) + $bits(control_model_hold) +
            $bits(control_precision_hold) + $bits(generation_hold) + $bits(tokens_hold) +
            $bits(control_generation_hold) + $bits(control_tokens_hold) +
            $bits(weights_hold) + $bits(control_weights_hold) + $bits(request_model) +
            $bits(head_hold) + $bits(owner_hold) + $bits(token_hold) +
            $bits(hidden_hold) + $bits(dimension_hold) + $bits(vector_count) +
            $bits(selector_hold) + $bits(component_hold) + $bits(error_hold) +
            $bits(eval_error_hold) + $bits(pair_hold) + $bits(source_model_hold) +
            $bits(source_owner_hold) + $bits(source_token_hold) +
            $bits(source_index_hold) + $bits(source_data_hold) + $bits(raw_q) +
            $bits(source_error_hold) + $bits(source_normalized_hold) +
            $bits(normalized_committed) + $bits(normalized_bad) + $bits(normalized_count);
        wire [63:0] tile_controller_bytes;
        assign controller_bytes = !rst_n ? 64'd0 :
            64'((CONTROLLER_BITS + 7) >> 3) + tile_controller_bytes;

        wire native_owner, global_owner;
        wire [7:0] owners;
        wire [11:0] selected_hidden;
        anvil_en1_geometry geometry (
            .rst_n(rst_n), .model(request_model), .layer(owner_hold),
            .is_native(native_owner), .layers(), .owners(owners), .owner(),
            .is_global(global_owner), .hidden(selected_hidden), .intermediate()
        );
        wire [31:0] selected_dimension = COMPACT ?
            (global_owner ? 32'd8 : 32'd4) :
            (global_owner ? 32'd512 : 32'd256);
        wire valid_head = head_hold < (COMPACT || request_model == 1 ? 2'd1 : 2'd2);
        wire source_descriptor_valid = source_model_hold == model_hold &&
            source_owner_hold == owner_hold && source_token_hold == token_hold &&
            source_index_hold < hidden_hold;
        wire vector_beat_valid = !vector_complete && !vector_bad &&
            vector_count < hidden_hold && eval_output_index == vector_count &&
            eval_output_last == (vector_count == hidden_hold - 1'b1);
        wire vector_write = rst_n && state == EVAL_WAIT &&
            eval_output_valid && eval_output_ready && vector_beat_valid;
        wire vector_complete_now = vector_complete ||
            (eval_output_valid && eval_output_ready && vector_beat_valid &&
                eval_output_last);
        wire vector_bad_now = vector_bad ||
            (eval_output_valid && eval_output_ready && !vector_beat_valid);

        wire tile_ready, tile_valid, tile_source_valid, tile_source_rsp_ready;
        wire [1:0] tile_source_model;
        wire [7:0] tile_source_owner;
        wire [31:0] tile_source_token, tile_source_index, tile_data;
        wire tile_source_normalized, tile_store_valid;
        wire [31:0] tile_store_index;
        wire [15:0] tile_store_data;
        wire tile_store_ok = !normalized_bad && !normalized_committed &&
            normalized_count < hidden_hold && tile_store_index == normalized_count;
        wire [3:0] tile_error;
        anvil_en1_owner_kv_tile #(.COMPACT(COMPACT), .EXTERNAL_INPUT_RAM(1)) owner_tile (
            .controller_bytes(tile_controller_bytes),
            .clk(clk), .rst_n(rst_n),
            .start_valid(rst_n && state == TILE_START), .start_ready(tile_ready),
            .model(request_model), .precision(precision_hold), .owner(owner_hold),
            .token(token_hold), .is_value(selector_hold), .kv_head(head_hold),
            .is_query(1'b0), .query_head(4'd0),
            .component(component_hold), .weights_base(weights_hold),
            .source_valid(tile_source_valid),
            .source_ready(rst_n && state == TILE_WAIT && source_state == SOURCE_IDLE),
            .source_model(tile_source_model), .source_owner(tile_source_owner),
            .source_token(tile_source_token), .source_index(tile_source_index),
            .source_normalized(tile_source_normalized),
            .input_store_valid(tile_store_valid), .input_store_index(tile_store_index),
            .input_store_data(tile_store_data),
            .source_rsp_valid(rst_n && source_state == SOURCE_RESPONSE),
            .source_rsp_ready(tile_source_rsp_ready),
            .source_rsp_data(source_data_hold), .source_rsp_error(source_error_hold),
            .cmd_valid(cmd_valid), .cmd_ready(cmd_ready), .cmd_write(cmd_write),
            .cmd_addr(cmd_addr), .cmd_wdata(cmd_wdata),
            .result_valid(result_valid), .result_ready(result_ready),
            .result_data(result_data), .result_error(result_error),
            .done_valid(tile_valid), .done_ready(rst_n && state == TILE_WAIT),
            .done_data(tile_data), .done_error(tile_error),
            .projection_event(owner_reprojection_event),
            .projection_bytes(owner_reprojection_bytes)
        );

        assign control_ready = rst_n && state == IDLE;
        assign control_rsp_valid = rst_n && state == CONTROL_RESPONSE;
        assign control_error = rst_n ? error_hold : 4'd0;
        assign regen_ready = rst_n && state == IDLE && !control_valid;
        assign regen_rsp_valid = rst_n && state == RESPONSE;
        assign regen_rsp_data = rst_n ? pair_hold : 32'd0;
        assign regen_rsp_error = rst_n ? error_hold : 4'd0;
        assign frontier_read_valid = rst_n && source_state == FRONTIER_SEND;
        assign frontier_read_generation = rst_n ? generation_hold : 32'd0;
        assign frontier_read_token = rst_n ? token_hold : 32'd0;
        assign frontier_read_layer = rst_n ? owner_hold : 8'd0;
        assign frontier_read_component = rst_n ?
            {source_index_hold[11:1], 1'b0} : 12'd0;
        assign frontier_read_rsp_ready = rst_n && source_state == FRONTIER_WAIT;
        assign ring_read_valid = rst_n && state == RING_SEND;
        assign ring_read_model = rst_n ? request_model : 2'd0;
        assign ring_read_generation = rst_n ? generation_hold : 32'd0;
        assign ring_read_token = rst_n ? token_hold : 32'd0;
        assign ring_read_owner = rst_n ? owner_hold : 8'd0;
        assign ring_read_is_value = rst_n && selector_hold;
        assign ring_read_kv_head = rst_n ? head_hold : 2'd0;
        assign ring_read_component = rst_n ? component_hold : 10'd0;
        assign ring_read_rsp_ready = rst_n && state == RING_WAIT;
        assign eval_start_valid = rst_n && state == EVAL_START;
        assign eval_model = rst_n ? request_model : 2'd0;
        assign eval_precision = rst_n ? precision_hold : 2'd0;
        assign eval_domain = 0;
        assign eval_generation = rst_n ? generation_hold : 32'd0;
        assign eval_layer = rst_n ? owner_hold : 8'd0;
        assign eval_token = rst_n ? token_hold : 32'd0;
        assign eval_tokens = rst_n ? tokens_hold : 32'd0;
        assign eval_output_ready = rst_n && state == EVAL_WAIT;
        assign eval_done_ready = rst_n && state == EVAL_WAIT;
        assign raw_source_live_bytes = rst_n && raw_allocated ?
            {32'd0, hidden_hold} << 1 : 64'd0;
        assign raw_source_physical_bytes = rst_n ? 64'(2*MAX_H) : 64'd0;
        assign tile_live_bytes = rst_n && tile_allocated ?
            {32'd0, dimension_hold} << 1 : 64'd0;
        assign tile_physical_bytes = rst_n ? (COMPACT ? 64'd16 : 64'd1024) : 64'd0;
        assign ring_hit_event = rst_n && ring_hit_pulse;
        assign busy = rst_n && state != IDLE;

        always @(posedge clk) begin
            if (vector_write)
                raw_payload[eval_output_index[H_BITS-1:0]] <= eval_output_data;
            else if (rst_n && state == TILE_WAIT && tile_store_valid && tile_store_ok)
                raw_payload[tile_store_index[H_BITS-1:0]] <= tile_store_data;
            if (rst_n && source_state == SOURCE_READ)
                raw_q <= raw_payload[source_index_hold[H_BITS-1:0]];
        end

        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                source_state <= SOURCE_IDLE;
                source_model_hold <= 0;
                source_owner_hold <= 0;
                source_token_hold <= 0;
                source_index_hold <= 0;
                source_data_hold <= 0;
                source_error_hold <= 0;
                source_normalized_hold <= 0;
            end else begin
                case (source_state)
                    SOURCE_IDLE: if (state == TILE_WAIT && tile_source_valid) begin
                        source_model_hold <= tile_source_model;
                        source_owner_hold <= tile_source_owner;
                        source_token_hold <= tile_source_token;
                        source_index_hold <= tile_source_index;
                        source_normalized_hold <= tile_source_normalized;
                        source_data_hold <= 0;
                        source_error_hold <= 0;
                        source_state <= SOURCE_VALIDATE;
                    end
                    SOURCE_VALIDATE: begin
                        if (!source_descriptor_valid ||
                            (source_normalized_hold && !normalized_committed) ||
                            (!source_normalized_hold && fallback_hold && !raw_committed)) begin
                            source_error_hold <= 1;
                            source_state <= SOURCE_RESPONSE;
                        end else if (fallback_hold || source_normalized_hold)
                            source_state <= SOURCE_READ;
                        else
                            source_state <= FRONTIER_SEND;
                    end
                    SOURCE_READ: source_state <= SOURCE_CAPTURE;
                    SOURCE_CAPTURE: begin
                        source_data_hold <= raw_q;
                        source_state <= SOURCE_RESPONSE;
                    end
                    FRONTIER_SEND: if (frontier_read_ready)
                        source_state <= FRONTIER_WAIT;
                    FRONTIER_WAIT: if (frontier_read_rsp_valid && frontier_read_rsp_ready) begin
                        source_data_hold <= source_index_hold[0] ?
                            frontier_read_rsp_data[31:16] : frontier_read_rsp_data[15:0];
                        source_error_hold <= frontier_read_rsp_error != 0;
                        source_state <= SOURCE_RESPONSE;
                    end
                    SOURCE_RESPONSE: if (tile_source_rsp_ready)
                        source_state <= SOURCE_IDLE;
                    default: begin
                        source_data_hold <= 0;
                        source_error_hold <= 1;
                        source_state <= SOURCE_RESPONSE;
                    end
                endcase
            end
        end

        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                state <= IDLE;
                active <= 0;
                fallback_hold <= 0;
                invalidate_hold <= 0;
                control_fallback_hold <= 0;
                raw_allocated <= 0;
                normalized_count <= 0;
                normalized_committed <= 0;
                normalized_bad <= 0;
                raw_committed <= 0;
                vector_bad <= 0;
                vector_complete <= 0;
                tile_allocated <= 0;
                ring_hit_pulse <= 0;
                model_hold <= 0;
                precision_hold <= 0;
                control_model_hold <= 0;
                control_precision_hold <= 0;
                generation_hold <= 0;
                tokens_hold <= 0;
                control_generation_hold <= 0;
                control_tokens_hold <= 0;
                weights_hold <= 0;
                control_weights_hold <= 0;
                request_model <= 0;
                head_hold <= 0;
                owner_hold <= 0;
                token_hold <= 0;
                hidden_hold <= 0;
                dimension_hold <= 0;
                vector_count <= 0;
                selector_hold <= 0;
                component_hold <= 0;
                error_hold <= 0;
                eval_error_hold <= 0;
                pair_hold <= 0;
            end else begin
                ring_hit_pulse <= 0;
                case (state)
                    IDLE: begin
                        if (control_valid && control_ready) begin
                            invalidate_hold <= control_invalidate;
                            control_fallback_hold <= control_fallback;
                            control_model_hold <= control_model;
                            control_precision_hold <= control_precision;
                            control_generation_hold <= control_generation;
                            control_tokens_hold <= control_tokens;
                            control_weights_hold <= control_weights_base;
                            error_hold <= 0;
                            state <= CONTROL_VALIDATE;
                        end else if (regen_valid && regen_ready) begin
                            request_model <= regen_model;
                            owner_hold <= regen_owner;
                            token_hold <= regen_token;
                            selector_hold <= regen_is_value;
                            head_hold <= regen_kv_head;
                            component_hold <= regen_component;
                            error_hold <= 0;
                            eval_error_hold <= 0;
                            pair_hold <= 0;
                            vector_count <= 0;
                            vector_bad <= 0;
                            vector_complete <= 0;
                            raw_allocated <= 0;
                            raw_committed <= 0;
                            state <= VALIDATE;
                        end
                    end
                    CONTROL_VALIDATE: begin
                        if (invalidate_hold) begin
                            active <= 0;
                            raw_allocated <= 0;
                            raw_committed <= 0;
                            tile_allocated <= 0;
                        end else if ((control_model_hold != 1 && control_model_hold != 2) ||
                            control_precision_hold > 1)
                            error_hold <= 6;
                        else if (control_tokens_hold == 0 || control_tokens_hold > 131072 ||
                            control_weights_hold[1:0] != 0)
                            error_hold <= 5;
                        else begin
                            active <= 1;
                            model_hold <= control_model_hold;
                            precision_hold <= control_precision_hold;
                            generation_hold <= control_generation_hold;
                            tokens_hold <= control_tokens_hold;
                            weights_hold <= control_weights_hold;
                            fallback_hold <= control_fallback_hold;
                        end
                        state <= CONTROL_PUBLISH;
                    end
                    CONTROL_PUBLISH: state <= CONTROL_RESPONSE;
                    CONTROL_RESPONSE: if (control_rsp_ready)
                        state <= IDLE;
                    VALIDATE: begin
                        hidden_hold <= COMPACT ? 32'd8 : {20'd0, selected_hidden};
                        dimension_hold <= selected_dimension;
                        if (!native_owner)
                            error_hold <= 6;
                        else if (!active || request_model != model_hold || owner_hold >= owners)
                            error_hold <= 7;
                        else if (token_hold >= tokens_hold || token_hold > 131071 ||
                            component_hold[0] || {22'd0, component_hold} >= selected_dimension ||
                            !valid_head)
                            error_hold <= 5;
                        if (!native_owner || !active || request_model != model_hold ||
                            owner_hold >= owners || token_hold >= tokens_hold ||
                            token_hold > 131071 || component_hold[0] ||
                            {22'd0, component_hold} >= selected_dimension || !valid_head)
                            state <= PUBLISH;
                        else if (fallback_hold)
                            state <= EVAL_START;
                        else if (owner_hold == owners - 8'd2)
                            state <= RING_SEND;
                        else
                            state <= TILE_START;
                    end
                    RING_SEND: if (ring_read_ready)
                        state <= RING_WAIT;
                    RING_WAIT: if (ring_read_rsp_valid && ring_read_rsp_ready) begin
                        if (ring_read_rsp_error != 0) begin
                            error_hold <= ring_read_rsp_error;
                            state <= PUBLISH;
                        end else if (ring_read_rsp_hit) begin
                            pair_hold <= ring_read_rsp_data;
                            ring_hit_pulse <= 1;
                            state <= PUBLISH;
                        end else
                            state <= TILE_START;
                    end
                    EVAL_START: if (eval_start_ready) begin
                        raw_allocated <= 1;
                        state <= EVAL_WAIT;
                    end
                    EVAL_WAIT: begin
                        if (eval_output_valid && eval_output_ready) begin
                            if (!vector_beat_valid)
                                vector_bad <= 1;
                            else begin
                                vector_count <= vector_count + 1'b1;
                                if (eval_output_last)
                                    vector_complete <= 1;
                            end
                        end
                        if (eval_done_valid && eval_done_ready) begin
                            eval_error_hold <= eval_done_error;
                            vector_bad <= vector_bad_now || !vector_complete_now;
                            state <= EVAL_COMMIT;
                        end
                    end
                    EVAL_COMMIT: begin
                        if (eval_error_hold != 0 || vector_bad ||
                            !vector_complete || vector_count != hidden_hold) begin
                            error_hold <= eval_error_hold != 0 ? eval_error_hold : 4'd7;
                            raw_allocated <= 0;
                            raw_committed <= 0;
                            state <= PUBLISH;
                        end else begin
                            raw_committed <= 1;
                            state <= TILE_START;
                        end
                    end
                    TILE_START: if (tile_ready) begin
                        raw_allocated <= 1;
                        normalized_count <= 0;
                        normalized_committed <= 0;
                        normalized_bad <= 0;
                        tile_allocated <= 1;
                        state <= TILE_WAIT;
                    end
                    TILE_WAIT: begin
                        if (tile_store_valid) begin
                            if (!tile_store_ok)
                                normalized_bad <= 1;
                            else begin
                                normalized_count <= normalized_count + 1'b1;
                                if (tile_store_index == hidden_hold - 1'b1)
                                    normalized_committed <= 1;
                            end
                        end
                        if (tile_valid) begin
                            raw_allocated <= 0;
                            raw_committed <= 0;
                            tile_allocated <= 0;
                            if (tile_error != 0) begin
                                error_hold <= tile_error;
                                pair_hold <= 0;
                            end else if (normalized_bad || !normalized_committed) begin
                                error_hold <= 7;
                                pair_hold <= 0;
                            end else begin
                                error_hold <= 0;
                                pair_hold <= tile_data;
                            end
                            state <= PUBLISH;
                        end
                    end
                    PUBLISH: state <= RESPONSE;
                    RESPONSE: if (regen_rsp_ready) begin
                        raw_allocated <= 0;
                        raw_committed <= 0;
                        tile_allocated <= 0;
                        state <= IDLE;
                    end
                    default: begin
                        active <= 0;
                        raw_committed <= 0;
                        pair_hold <= 0;
                        error_hold <= 7;
                        state <= PUBLISH;
                    end
                endcase
            end
        end
    end endgenerate
endmodule
