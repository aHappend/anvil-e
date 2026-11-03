module anvil_en1_local_ring #(
    parameter integer COMPACT = 0
) (
    input wire clk, rst_n,
    input wire control_valid,
    output wire control_ready,
    input wire control_invalidate,
    input wire [1:0] control_model,
    input wire [31:0] control_generation, control_tokens,
    output wire control_rsp_valid,
    input wire control_rsp_ready,
    output wire [3:0] control_error,
    output wire [63:0] live_bytes, physical_payload_bytes, token_metadata_bytes,
    output wire [63:0] controller_bytes,
    input wire write_start_valid,
    output wire write_start_ready,
    input wire [1:0] write_model,
    input wire [31:0] write_generation, write_token,
    input wire [7:0] write_owner,
    input wire write_is_value,
    input wire [1:0] write_kv_head,
    input wire write_valid,
    output wire write_ready,
    input wire [31:0] write_data,
    input wire write_first, write_last,
    output wire write_done_valid,
    input wire write_done_ready,
    output wire [3:0] write_done_error,
    input wire read_valid,
    output wire read_ready,
    input wire [1:0] read_model,
    input wire [31:0] read_generation, read_token,
    input wire [7:0] read_owner,
    input wire read_is_value,
    input wire [1:0] read_kv_head,
    input wire [9:0] read_component,
    output wire read_rsp_valid,
    input wire read_rsp_ready,
    output wire read_rsp_hit,
    output wire [31:0] read_rsp_data,
    output wire [3:0] read_rsp_error
);
    generate if (COMPACT != 0 && COMPACT != 1) begin : invalid_parameters
        initial $fatal(1, "PARAMETER ERROR: COMPACT must be 0 or 1");
        assign control_ready = 0;
        assign control_rsp_valid = 0;
        assign control_error = 0;
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
        assign read_rsp_hit = 0;
        assign read_rsp_data = 0;
        assign read_rsp_error = 0;
    end else begin : ring
        localparam integer WINDOW = COMPACT ? 4 : 512;
        localparam integer SLOT_BITS = $clog2(WINDOW);
        localparam integer TAG_BITS = 17 - SLOT_BITS;
        localparam integer LANES = COMPACT ? 2 : 4;
        localparam integer PAIRS = COMPACT ? 2 : 128;
        localparam integer WORD_COUNT = WINDOW * LANES * PAIRS;
        localparam integer ADDRESS_WIDTH = $clog2(WORD_COUNT);
        localparam integer SLOT_SHIFT = $clog2(LANES * PAIRS);
        localparam integer SELECTOR_SHIFT = COMPACT ? 1 : 8;
        localparam integer HEAD_SHIFT = COMPACT ? 0 : 7;
        localparam [3:0] IDLE = 0, CONTROL_VALIDATE = 1,
            CONTROL_EXTENT = 2, CONTROL_PUBLISH = 3, CONTROL_RESPONSE = 4,
            TAG_READ = 5, REQUEST_CHECK = 6, WRITE_CLEAR = 7,
            WRITING = 8, WRITE_COMMIT = 9, WRITE_PUBLISH = 10,
            WRITE_RESPONSE = 11, RAM_READ = 12, READ_PUBLISH = 13,
            READ_RESPONSE = 14;
        reg [3:0] state;
        reg control_invalidate_hold, active, is_write, selector_hold, hit_hold;
        reg [1:0] control_model_hold, model_hold, request_model, head_hold;
        reg [31:0] control_generation_hold, control_tokens_hold;
        reg [31:0] generation_hold, padded_window, allocation_hold;
        reg [31:0] token_hold, request_generation, word_address, write_base;
        reg [7:0] owner_hold, anchor_hold, pair_index;
        reg [9:0] component_hold;
        reg [3:0] error_hold;
        reg [WINDOW*LANES-1:0] occupied;
        reg [LANES-1:0] lane_valid_hold;
        reg [TAG_BITS-1:0] tag_q;
        reg [31:0] payload_q, read_hold;
        (* ramstyle = "M20K", nomem2reg *)
        reg [31:0] payload [0:WORD_COUNT-1];
        (* ramstyle = "MLAB", nomem2reg *)
        reg [TAG_BITS-1:0] token_tags [0:WINDOW-1];
        wire [31:0] CONTROLLER_BITS = $bits(state) +
            $bits(control_invalidate_hold) + $bits(active) + $bits(is_write) +
            $bits(selector_hold) + $bits(hit_hold) + $bits(control_model_hold) +
            $bits(model_hold) + $bits(request_model) + $bits(head_hold) +
            $bits(control_generation_hold) + $bits(control_tokens_hold) +
            $bits(generation_hold) + $bits(padded_window) + $bits(allocation_hold) +
            $bits(token_hold) + $bits(request_generation) + $bits(word_address) +
            $bits(write_base) + $bits(owner_hold) + $bits(anchor_hold) +
            $bits(pair_index) + $bits(component_hold) + $bits(error_hold) +
            $bits(lane_valid_hold) + $bits(tag_q) + $bits(payload_q) + $bits(read_hold);
        assign controller_bytes = rst_n ? 64'((CONTROLLER_BITS+7) >> 3) : 64'd0;
        wire selected_native;
        wire [7:0] selected_owners;
        anvil_en1_geometry geometry (
            .rst_n(rst_n), .model(control_model_hold), .layer(8'd0),
            .is_native(selected_native), .layers(), .owners(selected_owners),
            .owner(), .is_global(), .hidden(), .intermediate()
        );
        wire [31:0] rounded_tokens = (control_tokens_hold + 32'd15) & 32'hfffffff0;
        wire [31:0] required_bytes = COMPACT ? padded_window << 4 :
            (model_hold == 1 ? padded_window << 10 : padded_window << 11);
        wire [SLOT_BITS-1:0] slot = token_hold[SLOT_BITS-1:0];
        wire [1:0] lane = COMPACT ? {1'b0, selector_hold} :
            {selector_hold, head_hold[0]};
        wire [31:0] lane_bit_index = (32'(slot) << (COMPACT ? 1 : 2)) + {30'd0, lane};
        wire [31:0] selected_base = (32'(slot) << SLOT_SHIFT) |
            ({31'd0, selector_hold} << SELECTOR_SHIFT) |
            ({30'd0, head_hold} << HEAD_SHIFT);
        wire local_request = active && request_model == model_hold &&
            request_generation == generation_hold && owner_hold == anchor_hold;
        wire valid_head = head_hold < (COMPACT || model_hold == 1 ? 2'd1 : 2'd2);
        wire valid_token = token_hold <= 131071;
        wire tag_read_enable = rst_n && state == TAG_READ && local_request &&
            valid_token && valid_head;
        wire beat_flags_valid = write_first == (pair_index == 0) &&
            write_last == (pair_index == PAIRS - 1);
        wire [31:0] write_address = write_base + {24'd0, pair_index};
        wire payload_write = rst_n && state == WRITING &&
            write_valid && write_ready && beat_flags_valid;
        wire slot_retag = !(|lane_valid_hold) ||
            tag_q != token_hold[16:SLOT_BITS];

        assign control_ready = rst_n && state == IDLE;
        assign control_rsp_valid = rst_n && state == CONTROL_RESPONSE;
        assign control_error = rst_n ? error_hold : 4'd0;
        assign live_bytes = rst_n ? {32'd0, allocation_hold} : 64'd0;
        assign physical_payload_bytes = rst_n ? 64'(WORD_COUNT * 4) : 64'd0;
        assign token_metadata_bytes = rst_n ?
            64'((WINDOW * TAG_BITS + 7) >> 3) +
                64'((WINDOW * LANES + 7) >> 3) : 64'd0;
        assign write_start_ready = rst_n && state == IDLE && !control_valid;
        assign write_ready = rst_n && state == WRITING;
        assign write_done_valid = rst_n && state == WRITE_RESPONSE;
        assign write_done_error = rst_n ? error_hold : 4'd0;
        assign read_ready = rst_n && state == IDLE && !control_valid && !write_start_valid;
        assign read_rsp_valid = rst_n && state == READ_RESPONSE;
        assign read_rsp_hit = rst_n && hit_hold;
        assign read_rsp_data = rst_n ? read_hold : 32'd0;
        assign read_rsp_error = rst_n ? error_hold : 4'd0;

        always @(posedge clk) begin
            if (payload_write)
                payload[write_address[ADDRESS_WIDTH-1:0]] <= write_data;
            if (rst_n && state == RAM_READ)
                payload_q <= payload[word_address[ADDRESS_WIDTH-1:0]];
            if (tag_read_enable)
                tag_q <= token_tags[slot];
            if (rst_n && state == WRITE_CLEAR && slot_retag)
                token_tags[slot] <= token_hold[16:SLOT_BITS];
        end

        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                state <= IDLE;
                control_invalidate_hold <= 0;
                active <= 0;
                is_write <= 0;
                selector_hold <= 0;
                hit_hold <= 0;
                control_model_hold <= 0;
                model_hold <= 0;
                request_model <= 0;
                head_hold <= 0;
                control_generation_hold <= 0;
                control_tokens_hold <= 0;
                generation_hold <= 0;
                padded_window <= 0;
                allocation_hold <= 0;
                token_hold <= 0;
                request_generation <= 0;
                word_address <= 0;
                write_base <= 0;
                owner_hold <= 0;
                anchor_hold <= 0;
                pair_index <= 0;
                component_hold <= 0;
                error_hold <= 0;
                occupied <= 0;
                lane_valid_hold <= 0;
                read_hold <= 0;
            end else begin
                case (state)
                    IDLE: begin
                        if (control_valid && control_ready) begin
                            control_invalidate_hold <= control_invalidate;
                            control_model_hold <= control_model;
                            control_generation_hold <= control_generation;
                            control_tokens_hold <= control_tokens;
                            error_hold <= 0;
                            hit_hold <= 0;
                            state <= CONTROL_VALIDATE;
                        end else if (write_start_valid && write_start_ready) begin
                            request_model <= write_model;
                            request_generation <= write_generation;
                            token_hold <= write_token;
                            owner_hold <= write_owner;
                            selector_hold <= write_is_value;
                            head_hold <= write_kv_head;
                            component_hold <= 0;
                            pair_index <= 0;
                            is_write <= 1;
                            error_hold <= 0;
                            hit_hold <= 0;
                            state <= TAG_READ;
                        end else if (read_valid && read_ready) begin
                            request_model <= read_model;
                            request_generation <= read_generation;
                            token_hold <= read_token;
                            owner_hold <= read_owner;
                            selector_hold <= read_is_value;
                            head_hold <= read_kv_head;
                            component_hold <= read_component;
                            is_write <= 0;
                            error_hold <= 0;
                            hit_hold <= 0;
                            read_hold <= 0;
                            state <= TAG_READ;
                        end
                    end
                    CONTROL_VALIDATE: begin
                        occupied <= 0;
                        active <= 0;
                        allocation_hold <= 0;
                        padded_window <= 0;
                        if (control_invalidate_hold)
                            state <= CONTROL_PUBLISH;
                        else if (!selected_native) begin
                            error_hold <= 6;
                            state <= CONTROL_PUBLISH;
                        end else if (control_tokens_hold == 0 ||
                            control_tokens_hold > 131072) begin
                            error_hold <= 5;
                            state <= CONTROL_PUBLISH;
                        end else begin
                            model_hold <= control_model_hold;
                            generation_hold <= control_generation_hold;
                            anchor_hold <= selected_owners - 8'd2;
                            padded_window <= rounded_tokens > WINDOW ? 32'(WINDOW) : rounded_tokens;
                            state <= CONTROL_EXTENT;
                        end
                    end
                    CONTROL_EXTENT: begin
                        active <= 1;
                        allocation_hold <= required_bytes;
                        state <= CONTROL_PUBLISH;
                    end
                    CONTROL_PUBLISH: state <= CONTROL_RESPONSE;
                    CONTROL_RESPONSE: if (control_rsp_ready)
                        state <= IDLE;
                    TAG_READ: begin
                        lane_valid_hold <= tag_read_enable ?
                            occupied[32'(slot)*LANES +: LANES] : {LANES{1'b0}};
                        state <= REQUEST_CHECK;
                    end
                    REQUEST_CHECK: begin
                        if (request_model != 1 && request_model != 2) begin
                            error_hold <= 6;
                            if (is_write)
                                state <= WRITE_PUBLISH;
                            else
                                state <= READ_RESPONSE;
                        end else if (!valid_token) begin
                            error_hold <= 5;
                            if (is_write)
                                state <= WRITE_PUBLISH;
                            else
                                state <= READ_RESPONSE;
                        end else if (!local_request) begin
                            if (is_write) begin
                                error_hold <= 7;
                                state <= WRITE_PUBLISH;
                            end else
                                state <= READ_RESPONSE;
                        end else if (!valid_head || (!is_write &&
                            (component_hold >= (COMPACT ? 10'd4 : 10'd256) ||
                            component_hold[0]))) begin
                            error_hold <= 5;
                            if (is_write)
                                state <= WRITE_PUBLISH;
                            else
                                state <= READ_RESPONSE;
                        end else if (is_write) begin
                            write_base <= selected_base;
                            state <= WRITE_CLEAR;
                        end else if (!lane_valid_hold[lane] ||
                            tag_q != token_hold[16:SLOT_BITS])
                            state <= READ_RESPONSE;
                        else begin
                            word_address <= selected_base | {23'd0, component_hold[9:1]};
                            state <= RAM_READ;
                        end
                    end
                    WRITE_CLEAR: begin
                        if (slot_retag)
                            occupied[32'(slot)*LANES +: LANES] <= 0;
                        else
                            occupied[lane_bit_index] <= 0;
                        state <= WRITING;
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
                        occupied[lane_bit_index] <= 1;
                        state <= WRITE_PUBLISH;
                    end
                    WRITE_PUBLISH: state <= WRITE_RESPONSE;
                    WRITE_RESPONSE: if (write_done_ready)
                        state <= IDLE;
                    RAM_READ: state <= READ_PUBLISH;
                    READ_PUBLISH: begin
                        read_hold <= payload_q;
                        hit_hold <= 1;
                        state <= READ_RESPONSE;
                    end
                    READ_RESPONSE: if (read_rsp_ready)
                        state <= IDLE;
                    default: begin
                        occupied <= 0;
                        active <= 0;
                        allocation_hold <= 0;
                        read_hold <= 0;
                        hit_hold <= 0;
                        error_hold <= 7;
                        state <= CONTROL_PUBLISH;
                    end
                endcase
            end
        end
    end
    endgenerate
endmodule
