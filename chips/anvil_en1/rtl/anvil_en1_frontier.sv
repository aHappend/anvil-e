module anvil_en1_frontier #(
    parameter integer COMPACT = 0
) (
    input wire clk, rst_n,
    input wire control_valid,
    output wire control_ready,
    input wire [1:0] control_op, control_model,
    input wire [31:0] control_generation, control_tokens,
    output wire control_rsp_valid,
    input wire control_rsp_ready,
    output wire [3:0] control_error,
    output wire fallback_needed,
    output wire [31:0] padded_tokens,
    output wire [63:0] live_bytes, physical_payload_bytes, token_metadata_bytes,
    output wire [63:0] controller_bytes,
    input wire write_start_valid,
    output wire write_start_ready,
    input wire [31:0] write_generation, write_token,
    input wire [7:0] write_layer,
    input wire write_valid,
    output wire write_ready,
    input wire [31:0] write_data,
    input wire write_first, write_last,
    output wire write_done_valid,
    input wire write_done_ready,
    output wire [3:0] write_done_error,
    input wire read_valid,
    output wire read_ready,
    input wire [31:0] read_generation, read_token,
    input wire [7:0] read_layer,
    input wire [11:0] read_component,
    output wire read_rsp_valid,
    input wire read_rsp_ready,
    output wire [31:0] read_rsp_data,
    output wire [3:0] read_rsp_error,
    output wire backing_bound,
    input wire backing_valid,
    output wire backing_ready,
    input wire [31:0] backing_generation,
    input wire backing_write,
    input wire [17:0] backing_addr,
    input wire [31:0] backing_wdata,
    output wire backing_rsp_valid,
    input wire backing_rsp_ready,
    output wire [31:0] backing_rsp_data,
    output wire [3:0] backing_rsp_error
);
    generate if (COMPACT != 0 && COMPACT != 1) begin : invalid_parameters
        initial $fatal(1, "PARAMETER ERROR: COMPACT must be 0 or 1");
        assign control_ready = 0;
        assign control_rsp_valid = 0;
        assign control_error = 0;
        assign fallback_needed = 0;
        assign padded_tokens = 0;
        assign live_bytes = 0;
        assign physical_payload_bytes = 0;
        assign token_metadata_bytes = 0;
        assign controller_bytes = 0;
        assign write_start_ready = 0;
        assign write_ready = 0;
        assign write_done_valid = 0;
        assign write_done_error = 0;
        assign read_ready = 0;
        assign read_rsp_valid = 0;
        assign read_rsp_data = 0;
        assign read_rsp_error = 0;
        assign backing_bound = 0;
        assign backing_ready = 0;
        assign backing_rsp_valid = 0;
        assign backing_rsp_data = 0;
        assign backing_rsp_error = 0;
    end else begin : frontier
        localparam integer ORDINARY_BACKING_BASE = COMPACT ? 2048 : 786432;
        localparam integer WORD_COUNT = COMPACT ? 208896 : 1017856;
        localparam integer ADDRESS_WIDTH = $clog2(WORD_COUNT);
        localparam integer MAX_TOKENS = COMPACT ? 512 : 1024;
        localparam [31:0] CAPACITY_BYTES = COMPACT ? 32'd8192 : 32'd3145728;
        localparam integer BACKING_WORDS = COMPACT ? 206848 : 231424;
        localparam [4:0] IDLE = 0, CONTROL_VALIDATE = 1, CONTROL_EXTENT = 2,
            CONTROL_PUBLISH = 3, CONTROL_RESPONSE = 4, TAG_READ = 5,
            VECTOR_CHECK = 6, WRITING = 7, WRITE_COMMIT = 8,
            WRITE_PUBLISH = 9, WRITE_RESPONSE = 10, RAM_READ = 11,
            READ_PUBLISH = 12, READ_RESPONSE = 13, BACKING_VALIDATE = 14,
            BACKING_ACCESS = 15, BACKING_PUBLISH = 16, BACKING_RESPONSE = 17;
        reg [4:0] state;
        reg [1:0] op_hold, control_model_hold, model_hold;
        reg [31:0] control_generation_hold, control_tokens_hold;
        reg [31:0] generation_hold, tokens_hold, padded_hold, allocation_hold;
        reg [31:0] token_hold, request_generation, vector_base, pair_index, word_address;
        reg [11:0] component_hold, hidden_hold, pair_count;
        reg [7:0] layer_hold, owners_hold;
        reg [3:0] error_hold;
        reg active, frozen, fallback_hold, is_write, token_valid_hold;
        reg [MAX_TOKENS-1:0] occupied;
        reg [31:0] read_hold;
        reg bound_hold, backing_write_hold;
        reg [17:0] backing_address_hold;
        reg [31:0] backing_generation_hold, backing_data_hold;
        reg [7:0] layer_q;
        reg [31:0] payload_q;
        (* ramstyle = "M20K", nomem2reg *)
        reg [31:0] payload [0:WORD_COUNT-1];
        (* ramstyle = "MLAB", nomem2reg *)
        reg [7:0] layer_tags [0:MAX_TOKENS-1];
        localparam integer CONTROLLER_BITS = $bits(state) + $bits(op_hold) +
            $bits(control_model_hold) + $bits(model_hold) +
            $bits(control_generation_hold) + $bits(control_tokens_hold) +
            $bits(generation_hold) + $bits(tokens_hold) + $bits(padded_hold) +
            $bits(allocation_hold) + $bits(token_hold) + $bits(request_generation) +
            $bits(vector_base) + $bits(pair_index) + $bits(word_address) +
            $bits(component_hold) + $bits(hidden_hold) + $bits(pair_count) +
            $bits(layer_hold) + $bits(owners_hold) + $bits(error_hold) +
            $bits(active) + $bits(frozen) + $bits(fallback_hold) +
            $bits(is_write) + $bits(token_valid_hold) + $bits(read_hold) +
            $bits(bound_hold) + $bits(backing_write_hold) +
            $bits(backing_address_hold) + $bits(backing_generation_hold) +
            $bits(backing_data_hold) + $bits(layer_q) + $bits(payload_q);
        assign controller_bytes = rst_n ? 64'((CONTROLLER_BITS+7) >> 3) : 64'd0;
        wire control_native;
        wire [7:0] selected_owners;
        wire [11:0] selected_hidden;
        anvil_en1_geometry geometry (
            .rst_n(rst_n), .model(control_model_hold), .layer(8'd0),
            .is_native(control_native), .layers(), .owners(selected_owners),
            .owner(), .is_global(), .hidden(selected_hidden), .intermediate()
        );
        wire [31:0] rounded_tokens = (control_tokens_hold + 32'd15) & 32'hfffffff0;
        wire [31:0] required_bytes = COMPACT ? padded_hold << 4 :
            (model_hold == 1 ? (padded_hold << 11) + (padded_hold << 10) :
            (padded_hold << 12) + (padded_hold << 10));
        wire [31:0] selected_base = COMPACT ? token_hold << 2 :
            (model_hold == 1 ? (token_hold << 9) + (token_hold << 8) :
            (token_hold << 10) + (token_hold << 8));
        wire request_in_range = active && token_hold < tokens_hold &&
            token_hold < MAX_TOKENS && request_generation == generation_hold;
        wire beat_flags_valid = write_first == (pair_index == 0) &&
            write_last == (pair_index == {20'd0, pair_count} - 1'b1);
        wire payload_write = rst_n && state == WRITING &&
            write_valid && write_ready && beat_flags_valid;
        wire [31:0] write_address = vector_base + pair_index;
        wire backing_access_valid = (bound_hold || active) &&
            backing_generation_hold == generation_hold &&
            backing_address_hold < BACKING_WORDS;
        wire [31:0] backing_word_address = {14'd0, backing_address_hold} +
            (active ? 32'(ORDINARY_BACKING_BASE) : 32'd0);

        assign control_ready = rst_n && state == IDLE;
        assign control_rsp_valid = rst_n && state == CONTROL_RESPONSE;
        assign control_error = rst_n ? error_hold : 4'd0;
        assign fallback_needed = rst_n && fallback_hold;
        assign padded_tokens = rst_n ? padded_hold : 32'd0;
        assign live_bytes = rst_n ? {32'd0, allocation_hold} : 64'd0;
        assign physical_payload_bytes = rst_n ? 64'(WORD_COUNT * 4) : 64'd0;
        assign token_metadata_bytes = rst_n ? 64'(MAX_TOKENS + (MAX_TOKENS >> 3)) : 64'd0;
        assign write_start_ready = rst_n && state == IDLE && !control_valid;
        assign write_ready = rst_n && state == WRITING;
        assign write_done_valid = rst_n && state == WRITE_RESPONSE;
        assign write_done_error = rst_n ? error_hold : 4'd0;
        assign read_ready = rst_n && state == IDLE && !control_valid && !write_start_valid;
        assign read_rsp_valid = rst_n && state == READ_RESPONSE;
        assign read_rsp_data = rst_n ? read_hold : 32'd0;
        assign read_rsp_error = rst_n ? error_hold : 4'd0;
        assign backing_bound = rst_n && (bound_hold || active);
        assign backing_ready = rst_n && state == IDLE && (bound_hold || active) &&
            !control_valid && !write_start_valid && !read_valid;
        assign backing_rsp_valid = rst_n && state == BACKING_RESPONSE;
        assign backing_rsp_data = rst_n ? read_hold : 32'd0;
        assign backing_rsp_error = rst_n ? error_hold : 4'd0;

        always @(posedge clk) begin
            if (payload_write)
                payload[write_address[ADDRESS_WIDTH-1:0]] <= write_data;
            else if (rst_n && state == BACKING_ACCESS && backing_access_valid &&
                backing_write_hold)
                payload[backing_word_address[ADDRESS_WIDTH-1:0]] <= backing_data_hold;
            if (rst_n && state == RAM_READ)
                payload_q <= payload[word_address[ADDRESS_WIDTH-1:0]];
            else if (rst_n && state == BACKING_ACCESS && backing_access_valid &&
                !backing_write_hold)
                payload_q <= payload[backing_word_address[ADDRESS_WIDTH-1:0]];
            if (rst_n && state == TAG_READ && request_in_range)
                layer_q <= layer_tags[token_hold];
            if (rst_n && state == WRITE_COMMIT)
                layer_tags[token_hold] <= layer_hold;
        end

        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                state <= IDLE;
                op_hold <= 0;
                control_model_hold <= 0;
                model_hold <= 0;
                control_generation_hold <= 0;
                control_tokens_hold <= 0;
                generation_hold <= 0;
                tokens_hold <= 0;
                padded_hold <= 0;
                allocation_hold <= 0;
                token_hold <= 0;
                request_generation <= 0;
                vector_base <= 0;
                pair_index <= 0;
                word_address <= 0;
                component_hold <= 0;
                hidden_hold <= 0;
                pair_count <= 0;
                layer_hold <= 0;
                owners_hold <= 0;
                error_hold <= 0;
                active <= 0;
                frozen <= 0;
                fallback_hold <= 0;
                is_write <= 0;
                token_valid_hold <= 0;
                occupied <= 0;
                read_hold <= 0;
                bound_hold <= 0;
                backing_write_hold <= 0;
                backing_address_hold <= 0;
                backing_generation_hold <= 0;
                backing_data_hold <= 0;
            end else begin
                case (state)
                    IDLE: begin
                        if (control_valid && control_ready) begin
                            op_hold <= control_op;
                            control_model_hold <= control_model;
                            control_generation_hold <= control_generation;
                            control_tokens_hold <= control_tokens;
                            error_hold <= 0;
                            state <= CONTROL_VALIDATE;
                        end else if (write_start_valid && write_start_ready) begin
                            request_generation <= write_generation;
                            token_hold <= write_token;
                            layer_hold <= write_layer;
                            component_hold <= 0;
                            pair_index <= 0;
                            is_write <= 1;
                            error_hold <= 0;
                            state <= TAG_READ;
                        end else if (read_valid && read_ready) begin
                            request_generation <= read_generation;
                            token_hold <= read_token;
                            layer_hold <= read_layer;
                            component_hold <= read_component;
                            is_write <= 0;
                            read_hold <= 0;
                            error_hold <= 0;
                            state <= TAG_READ;
                        end else if (backing_valid && backing_ready) begin
                            backing_address_hold <= backing_addr;
                            backing_write_hold <= backing_write;
                            backing_data_hold <= backing_wdata;
                            backing_generation_hold <= backing_generation;
                            read_hold <= 0;
                            error_hold <= 0;
                            state <= BACKING_VALIDATE;
                        end
                    end
                    CONTROL_VALIDATE: begin
                        if (op_hold == 3) begin
                            if (active || bound_hold)
                                error_hold <= 7;
                            else if (!control_native)
                                error_hold <= 6;
                            else if (control_tokens_hold == 0 ||
                                control_tokens_hold > 131072)
                                error_hold <= 5;
                            else begin
                                occupied <= 0;
                                frozen <= 0;
                                allocation_hold <= 0;
                                padded_hold <= 0;
                                tokens_hold <= 0;
                                fallback_hold <= 1;
                                model_hold <= control_model_hold;
                                generation_hold <= control_generation_hold;
                                bound_hold <= 1;
                            end
                            state <= CONTROL_PUBLISH;
                        end else if (op_hold == 1) begin
                            occupied <= 0;
                            active <= 0;
                            frozen <= 0;
                            allocation_hold <= 0;
                            padded_hold <= 0;
                            tokens_hold <= 0;
                            fallback_hold <= 0;
                            bound_hold <= 0;
                            state <= CONTROL_PUBLISH;
                        end else if (op_hold == 2) begin
                            if (!active || control_generation_hold != generation_hold ||
                                control_model_hold != model_hold)
                                error_hold <= 7;
                            else
                                frozen <= 1;
                            state <= CONTROL_PUBLISH;
                        end else if (bound_hold) begin
                            error_hold <= 7;
                            state <= CONTROL_PUBLISH;
                        end else begin
                            occupied <= 0;
                            active <= 0;
                            frozen <= 0;
                            allocation_hold <= 0;
                            fallback_hold <= 0;
                            padded_hold <= 0;
                            tokens_hold <= 0;
                            if (!control_native) begin
                                error_hold <= 6;
                                state <= CONTROL_PUBLISH;
                            end else if (control_tokens_hold == 0 ||
                                control_tokens_hold > 131072) begin
                                error_hold <= 5;
                                state <= CONTROL_PUBLISH;
                            end else begin
                                model_hold <= control_model_hold;
                                generation_hold <= control_generation_hold;
                                tokens_hold <= control_tokens_hold;
                                padded_hold <= rounded_tokens;
                                hidden_hold <= COMPACT ? 12'd8 : selected_hidden;
                                pair_count <= COMPACT ? 12'd4 : selected_hidden >> 1;
                                owners_hold <= selected_owners;
                                state <= CONTROL_EXTENT;
                            end
                        end
                    end
                    CONTROL_EXTENT: begin
                        if (required_bytes > CAPACITY_BYTES) begin
                            fallback_hold <= 1;
                            allocation_hold <= 0;
                        end else begin
                            allocation_hold <= required_bytes;
                            active <= 1;
                        end
                        state <= CONTROL_PUBLISH;
                    end
                    CONTROL_PUBLISH: state <= CONTROL_RESPONSE;
                    CONTROL_RESPONSE: if (control_rsp_ready)
                        state <= IDLE;
                    TAG_READ: begin
                        token_valid_hold <= request_in_range ? occupied[token_hold] : 1'b0;
                        state <= VECTOR_CHECK;
                    end
                    VECTOR_CHECK: begin
                        if (!request_in_range) begin
                            error_hold <= 7;
                            if (is_write)
                                state <= WRITE_PUBLISH;
                            else
                                state <= READ_RESPONSE;
                        end else if (is_write) begin
                            if (frozen || layer_hold >= owners_hold ||
                                (!token_valid_hold && layer_hold != 0) ||
                                (token_valid_hold && {1'b0, layer_hold} !=
                                {1'b0, layer_q} + 9'd1)) begin
                                error_hold <= 7;
                                state <= WRITE_PUBLISH;
                            end else begin
                                occupied[token_hold] <= 0;
                                vector_base <= selected_base;
                                state <= WRITING;
                            end
                        end else if (component_hold >= hidden_hold || component_hold[0]) begin
                            error_hold <= 5;
                            state <= READ_RESPONSE;
                        end else if (!token_valid_hold || layer_hold != layer_q) begin
                            error_hold <= 7;
                            state <= READ_RESPONSE;
                        end else begin
                            word_address <= selected_base + {21'd0, component_hold[11:1]};
                            state <= RAM_READ;
                        end
                    end
                    WRITING: if (write_valid && write_ready) begin
                        if (!beat_flags_valid) begin
                            error_hold <= 7;
                            state <= WRITE_PUBLISH;
                        end else if (write_last)
                            state <= WRITE_COMMIT;
                        else
                            pair_index <= pair_index + 1'b1;
                    end
                    WRITE_COMMIT: begin
                        occupied[token_hold] <= 1;
                        state <= WRITE_PUBLISH;
                    end
                    WRITE_PUBLISH: state <= WRITE_RESPONSE;
                    WRITE_RESPONSE: if (write_done_ready)
                        state <= IDLE;
                    RAM_READ: state <= READ_PUBLISH;
                    READ_PUBLISH: begin
                        read_hold <= payload_q;
                        state <= READ_RESPONSE;
                    end
                    READ_RESPONSE: if (read_rsp_ready)
                        state <= IDLE;
                    BACKING_VALIDATE: begin
                        if (!backing_access_valid) begin
                            error_hold <= 7;
                            state <= BACKING_RESPONSE;
                        end else
                            state <= BACKING_ACCESS;
                    end
                    BACKING_ACCESS: state <= BACKING_PUBLISH;
                    BACKING_PUBLISH: begin
                        read_hold <= backing_write_hold ? 32'd0 : payload_q;
                        state <= BACKING_RESPONSE;
                    end
                    BACKING_RESPONSE: if (backing_rsp_ready)
                        state <= IDLE;
                    default: begin
                        active <= 0;
                        bound_hold <= 0;
                        occupied <= 0;
                        allocation_hold <= 0;
                        read_hold <= 0;
                        error_hold <= 7;
                        state <= CONTROL_PUBLISH;
                    end
                endcase
            end
        end
    endgenerate
endmodule
