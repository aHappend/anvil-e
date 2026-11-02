module anvil_en1_replay_workspace #(
    parameter integer COMPACT = 0
) (
    input wire clk, rst_n,
    input wire control_valid,
    output wire control_ready,
    input wire control_invalidate,
    input wire [1:0] control_model,
    input wire [31:0] control_generation,
    output wire control_rsp_valid,
    input wire control_rsp_ready,
    output wire [3:0] control_error,
    input wire req_valid,
    output wire req_ready,
    input wire [2:0] req_op,
    input wire [1:0] req_model, req_domain, req_target,
    input wire [31:0] req_generation, req_token,
    input wire [7:0] req_layer,
    input wire [11:0] req_length, req_component,
    input wire [5:0] req_slot,
    input wire req_bank,
    input wire [7:0] req_scalar_index,
    input wire [31:0] req_data,
    input wire [255:0] req_continuation,
    input wire write_valid,
    output wire write_ready,
    input wire [31:0] write_data,
    input wire write_first, write_last,
    input wire write_abort,
    output wire rsp_valid,
    input wire rsp_ready,
    output wire [3:0] rsp_error,
    output wire rsp_hit,
    output wire [5:0] rsp_slot,
    output wire [31:0] rsp_data,
    output wire [255:0] rsp_continuation,
    output wire [1:0] rsp_model, rsp_domain,
    output wire [31:0] rsp_generation, rsp_token,
    output wire [7:0] rsp_layer,
    output wire [11:0] rsp_length,
    output wire [6:0] frame_depth,
    output wire [63:0] live_payload_bytes, production_shadow_bytes,
    output wire [63:0] backing_reserved_bytes, visibility_metadata_bytes,
    output wire memo_hit_event, memo_eviction_event,
    output wire backing_valid,
    input wire backing_ready,
    output wire [31:0] backing_generation,
    output wire backing_write,
    output wire [17:0] backing_addr,
    output wire [31:0] backing_wdata,
    input wire backing_rsp_valid,
    output wire backing_rsp_ready,
    input wire [31:0] backing_rsp_data,
    input wire [3:0] backing_rsp_error
);
    generate if (COMPACT != 0 && COMPACT != 1) begin : invalid_parameters
        initial $fatal(1, "PARAMETER ERROR: COMPACT must be 0 or 1");
        assign control_ready = 0;
        assign control_rsp_valid = 0;
        assign control_error = 0;
        assign req_ready = 0;
        assign write_ready = 0;
        assign rsp_valid = 0;
        assign rsp_error = 0;
        assign rsp_hit = 0;
        assign rsp_slot = 0;
        assign rsp_data = 0;
        assign rsp_continuation = 0;
        assign rsp_model = 0;
        assign rsp_domain = 0;
        assign rsp_generation = 0;
        assign rsp_token = 0;
        assign rsp_layer = 0;
        assign rsp_length = 0;
        assign frame_depth = 0;
        assign live_payload_bytes = 0;
        assign production_shadow_bytes = 0;
        assign backing_reserved_bytes = 0;
        assign visibility_metadata_bytes = 0;
        assign memo_hit_event = 0;
        assign memo_eviction_event = 0;
        assign backing_valid = 0;
        assign backing_generation = 0;
        assign backing_write = 0;
        assign backing_addr = 0;
        assign backing_wdata = 0;
        assign backing_rsp_ready = 0;
    end else begin : workspace
        localparam integer BANK_WORDS = COMPACT ? 4 : 1536;
        localparam integer FRAME_WORDS = 2 * BANK_WORDS;
        localparam integer MEMO_WORDS = COMPACT ? 4 : 2048;
        localparam integer SCALAR_WORDS = COMPACT ? 16 : 256;
        localparam integer MEMO_BASE = 64 * FRAME_WORDS;
        localparam integer SCALAR_BASE = MEMO_BASE + 16 * MEMO_WORDS;
        localparam integer TOTAL_WORDS = SCALAR_BASE + 64 * SCALAR_WORDS;
        localparam integer TAG_BITS = 73;
        localparam [5:0] IDLE = 0, CONTROL_VALIDATE = 1,
            CONTROL_PUBLISH = 2, CONTROL_RESPONSE = 3, VALIDATE = 4,
            TAG_READ = 5, TAG_CHECK = 6, PUSH_SETUP = 7,
            CONT_WRITE = 8, CONT_ADVANCE = 9, PUSH_COMMIT = 10,
            POP_SETUP = 11, CONT_READ = 12, CONT_CAPTURE = 13,
            POP_COMMIT = 14, UPDATE_SETUP = 15, VECTOR_SETUP = 16,
            STREAM = 17, STREAM_ADVANCE = 18, VECTOR_COMMIT = 19,
            READ_SETUP = 20, READ_FINISH = 21, MEMO_SCAN = 22,
            MEMO_CHECK = 23, SCALAR_SETUP = 24, SCALAR_FINISH = 25,
            BACKING_SEND = 26, BACKING_WAIT = 27, PUBLISH = 28,
            RESPONSE = 29, COPY_READ = 30, COPY_CAPTURE = 31,
            COPY_WRITE = 32;
        reg [5:0] state, backing_return;
        reg active, invalidate_hold, bank_hold, pending_push, pending_memo;
        reg hit_hold, hit_pulse, eviction_pulse, new_memo;
        reg [1:0] model_hold, control_model_hold, domain_hold, target_hold;
        reg [31:0] generation_hold, control_generation_hold, request_generation;
        reg [31:0] token_hold, request_data, data_hold;
        reg [7:0] layer_hold, scalar_index_hold;
        reg [11:0] length_hold, component_hold, pair_index;
        reg [2:0] op_hold;
        reg [5:0] slot_hold, response_slot;
        reg [5:0] copy_source_slot;
        reg [6:0] depth;
        reg [4:0] memo_count;
        reg [3:0] cursor, scan_index, error_hold;
        reg [2:0] continuation_index;
        reg [255:0] continuation_hold, continuation_result;
        reg [TAG_BITS-1:0] request_tag, response_tag, frame_tag_q, memo_tag_q;
        reg [17:0] backing_address_hold;
        reg backing_write_hold;
        reg [31:0] backing_data_hold, backing_result;
        reg [31:0] copy_data;
        reg [63:0] frame_occupied;
        reg [127:0] vector_occupied;
        reg [15:0] memo_occupied;
        reg [64*SCALAR_WORDS-1:0] scalar_occupied;
        (* ramstyle = "MLAB", nomem2reg *)
        reg [TAG_BITS-1:0] frame_tags [0:63];
        (* ramstyle = "MLAB", nomem2reg *)
        reg [TAG_BITS-1:0] memo_tags [0:15];

        wire [TAG_BITS-1:0] incoming_tag = {req_model, req_generation,
            req_domain, req_layer, req_token[16:0], req_length};
        wire native_model = model_hold == 1 || model_hold == 2;
        wire [7:0] layer_limit = model_hold == 1 ? 8'd35 : 8'd42;
        wire [11:0] expected_length = COMPACT ? 12'd8 :
            (domain_hold == 0 ? (model_hold == 1 ? 12'd1536 : 12'd2560) :
            (domain_hold == 1 ? 12'd768 : 12'd1024));
        wire descriptor_valid = domain_hold != 3 && token_hold <= 131071 &&
            length_hold == expected_length &&
            (domain_hold == 0 ? layer_hold <= layer_limit :
            (domain_hold == 1 ? layer_hold <= 16 : layer_hold <= 12));
        wire [6:0] request_rank = domain_hold == 0 ?
            {1'b0, layer_hold[5:0]} + 7'd18 : {1'b0, layer_hold[5:0]} + 7'd1;
        wire [6:0] parent_rank = frame_tag_q[38:37] == 0 ?
            {1'b0, frame_tag_q[34:29]} + 7'd18 :
            {1'b0, frame_tag_q[34:29]} + 7'd1;
        wire request_session_valid = active && native_model &&
            request_generation == generation_hold;
        wire [5:0] top_slot = depth[5:0] - 6'd1;
        wire [5:0] tag_frame_slot = op_hold <= 2 ? top_slot : slot_hold;
        wire [31:0] frame_base = COMPACT ? {26'd0, slot_hold} << 3 :
            ({26'd0, slot_hold} << 11) + ({26'd0, slot_hold} << 10);
        wire [31:0] vector_base = frame_base +
            (bank_hold ? 32'(BANK_WORDS) : 32'd0);
        wire [31:0] memo_base = 32'(MEMO_BASE) +
            ({28'd0, slot_hold[3:0]} << (COMPACT ? 2 : 11));
        wire [31:0] scalar_base = 32'(SCALAR_BASE) +
            ({26'd0, slot_hold} << (COMPACT ? 4 : 8));
        wire [31:0] scalar_bit_index = ({26'd0, slot_hold} <<
            (COMPACT ? 4 : 8)) + {24'd0, scalar_index_hold};
        wire [6:0] vector_bit_index = {slot_hold, bank_hold};
        wire [31:0] selected_vector_base = target_hold == 0 ? vector_base : memo_base;
        wire [31:0] copy_frame_base = COMPACT ?
            {26'd0, copy_source_slot} << 3 :
            ({26'd0, copy_source_slot} << 11) +
                ({26'd0, copy_source_slot} << 10);
        wire [31:0] copy_source_base = target_hold == 3 ?
            32'(MEMO_BASE) + ({26'd0, copy_source_slot} << (COMPACT ? 2 : 11)) :
            copy_frame_base + (bank_hold ? 32'(BANK_WORDS) : 32'd0);
        wire [31:0] copy_destination_base = target_hold == 3 ? vector_base : memo_base;
        wire [TAG_BITS-1:0] copy_memo_tag = {model_hold, generation_hold,
            domain_hold, request_data[25:18], request_data[16:0], length_hold};
        wire copy_descriptor_valid = copy_source_slot < 16 &&
            !request_data[17] && request_data[25:18] < layer_hold;
        wire flags_valid = write_first == (pair_index == 0) &&
            write_last == (pair_index == (length_hold >> 1) - 1'b1);
        wire [7:0] allocated_frames = {1'b0, depth} + {7'd0, pending_push};
        wire [5:0] allocated_memos = {1'b0, memo_count} + {5'd0, pending_memo};
        wire [63:0] live_frames = COMPACT ?
            {56'd0, allocated_frames} << 5 :
            ({56'd0, allocated_frames} << 13) + ({56'd0, allocated_frames} << 12);
        wire [63:0] live_scalars = {56'd0, allocated_frames} << (COMPACT ? 6 : 10);
        wire [63:0] live_memos = {58'd0, allocated_memos} << (COMPACT ? 4 : 13);
        wire [63:0] shadow_frames = ({56'd0, allocated_frames} << 13) +
            ({56'd0, allocated_frames} << 12) + ({56'd0, allocated_frames} << 10);
        wire [63:0] shadow_memos = {58'd0, allocated_memos} << 13;
        wire [31:0] continuation_word =
            continuation_hold[32*continuation_index+:32];

        assign control_ready = rst_n && state == IDLE;
        assign control_rsp_valid = rst_n && state == CONTROL_RESPONSE;
        assign control_error = rst_n ? error_hold : 4'd0;
        assign req_ready = rst_n && state == IDLE && !control_valid;
        assign write_ready = rst_n && state == STREAM;
        assign rsp_valid = rst_n && state == RESPONSE;
        assign rsp_error = rst_n ? error_hold : 4'd0;
        assign rsp_hit = rst_n && hit_hold;
        assign rsp_slot = rst_n ? response_slot : 6'd0;
        assign rsp_data = rst_n ? data_hold : 32'd0;
        assign rsp_continuation = rst_n ? continuation_result : 256'd0;
        assign rsp_model = rst_n ? response_tag[72:71] : 2'd0;
        assign rsp_generation = rst_n ? response_tag[70:39] : 32'd0;
        assign rsp_domain = rst_n ? response_tag[38:37] : 2'd0;
        assign rsp_layer = rst_n ? response_tag[36:29] : 8'd0;
        assign rsp_token = rst_n ? {15'd0, response_tag[28:12]} : 32'd0;
        assign rsp_length = rst_n ? response_tag[11:0] : 12'd0;
        assign frame_depth = rst_n ? depth : 7'd0;
        assign live_payload_bytes = rst_n ? live_frames + live_scalars + live_memos : 64'd0;
        assign production_shadow_bytes = rst_n ? shadow_frames + shadow_memos : 64'd0;
        assign backing_reserved_bytes = rst_n ? 64'(TOTAL_WORDS * 4) : 64'd0;
        assign visibility_metadata_bytes = rst_n ?
            64'((80*TAG_BITS + 64 + 128 + 16 + 64*SCALAR_WORDS + 7) >> 3) : 64'd0;
        assign memo_hit_event = rst_n && hit_pulse;
        assign memo_eviction_event = rst_n && eviction_pulse;
        assign backing_valid = rst_n && state == BACKING_SEND;
        assign backing_generation = rst_n ? generation_hold : 32'd0;
        assign backing_write = rst_n && backing_write_hold;
        assign backing_addr = rst_n ? backing_address_hold : 18'd0;
        assign backing_wdata = rst_n ? backing_data_hold : 32'd0;
        assign backing_rsp_ready = rst_n && state == BACKING_WAIT;

        always @(posedge clk) begin
            if (rst_n && state == TAG_READ && depth != 0)
                frame_tag_q <= frame_tags[tag_frame_slot];
            if (rst_n && state == MEMO_SCAN)
                memo_tag_q <= memo_tags[scan_index];
            if (rst_n && state == PUSH_COMMIT)
                frame_tags[slot_hold] <= request_tag;
            if (rst_n && state == VECTOR_COMMIT &&
                (target_hold == 1 || target_hold == 2))
                memo_tags[slot_hold[3:0]] <= request_tag;
        end

        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                state <= IDLE;
                backing_return <= 0;
                active <= 0;
                invalidate_hold <= 0;
                bank_hold <= 0;
                pending_push <= 0;
                pending_memo <= 0;
                hit_hold <= 0;
                hit_pulse <= 0;
                eviction_pulse <= 0;
                new_memo <= 0;
                model_hold <= 0;
                control_model_hold <= 0;
                domain_hold <= 0;
                target_hold <= 0;
                generation_hold <= 0;
                control_generation_hold <= 0;
                request_generation <= 0;
                token_hold <= 0;
                request_data <= 0;
                data_hold <= 0;
                layer_hold <= 0;
                scalar_index_hold <= 0;
                length_hold <= 0;
                component_hold <= 0;
                pair_index <= 0;
                op_hold <= 0;
                slot_hold <= 0;
                response_slot <= 0;
                copy_source_slot <= 0;
                depth <= 0;
                memo_count <= 0;
                cursor <= 0;
                scan_index <= 0;
                error_hold <= 0;
                continuation_index <= 0;
                continuation_hold <= 0;
                continuation_result <= 0;
                request_tag <= 0;
                response_tag <= 0;
                backing_address_hold <= 0;
                backing_write_hold <= 0;
                backing_data_hold <= 0;
                backing_result <= 0;
                copy_data <= 0;
                frame_occupied <= 0;
                vector_occupied <= 0;
                memo_occupied <= 0;
                scalar_occupied <= 0;
            end else begin
                hit_pulse <= 0;
                eviction_pulse <= 0;
                case (state)
                    IDLE: begin
                        if (control_valid && control_ready) begin
                            invalidate_hold <= control_invalidate;
                            control_model_hold <= control_model;
                            control_generation_hold <= control_generation;
                            error_hold <= 0;
                            state <= CONTROL_VALIDATE;
                        end else if (req_valid && req_ready) begin
                            op_hold <= req_op;
                            request_generation <= req_generation;
                            domain_hold <= req_domain;
                            target_hold <= req_target;
                            token_hold <= req_token;
                            layer_hold <= req_layer;
                            length_hold <= req_length;
                            component_hold <= req_component;
                            slot_hold <= req_slot;
                            copy_source_slot <= req_op == 3 && req_target == 3 ?
                                req_data[31:26] : req_slot;
                            bank_hold <= req_bank;
                            scalar_index_hold <= req_scalar_index;
                            request_data <= req_data;
                            request_tag <= incoming_tag;
                            response_tag <= incoming_tag;
                            continuation_hold <= req_continuation;
                            continuation_result <= 0;
                            pair_index <= 0;
                            data_hold <= 0;
                            response_slot <= 0;
                            error_hold <= 0;
                            hit_hold <= 0;
                            new_memo <= 0;
                            state <= VALIDATE;
                        end
                    end
                    CONTROL_VALIDATE: begin
                        if (!invalidate_hold && control_model_hold != 1 &&
                            control_model_hold != 2)
                            error_hold <= 6;
                        else begin
                            active <= !invalidate_hold;
                            model_hold <= control_model_hold;
                            generation_hold <= control_generation_hold;
                            depth <= 0;
                            memo_count <= 0;
                            cursor <= 0;
                            pending_push <= 0;
                            pending_memo <= 0;
                            frame_occupied <= 0;
                            vector_occupied <= 0;
                            memo_occupied <= 0;
                            scalar_occupied <= 0;
                        end
                        state <= CONTROL_PUBLISH;
                    end
                    CONTROL_PUBLISH: state <= CONTROL_RESPONSE;
                    CONTROL_RESPONSE: if (control_rsp_ready)
                        state <= IDLE;
                    VALIDATE: begin
                        if (request_tag[72:71] != 1 && request_tag[72:71] != 2) begin
                            error_hold <= 6;
                            state <= PUBLISH;
                        end else if (request_tag[72:71] != model_hold ||
                            !request_session_valid) begin
                            error_hold <= 7;
                            state <= PUBLISH;
                        end else if (op_hold != 1 && !descriptor_valid) begin
                            error_hold <= 5;
                            state <= PUBLISH;
                        end else if (op_hold == 0 && depth == 64) begin
                            error_hold <= 7;
                            state <= PUBLISH;
                        end else if ((op_hold == 1 || op_hold == 2) && depth == 0) begin
                            error_hold <= 7;
                            state <= PUBLISH;
                        end else if (op_hold == 4 && target_hold > 1) begin
                            error_hold <= 5;
                            state <= PUBLISH;
                        end else if (op_hold == 4 && (component_hold[0] ||
                            component_hold >= length_hold)) begin
                            error_hold <= 5;
                            state <= PUBLISH;
                        end else if ((op_hold == 6 || op_hold == 7) &&
                            scalar_index_hold >= SCALAR_WORDS) begin
                            error_hold <= 5;
                            state <= PUBLISH;
                        end else if (op_hold == 5 || (op_hold == 3 && target_hold == 1)) begin
                            scan_index <= 0;
                            state <= MEMO_SCAN;
                        end else if (op_hold == 4 && target_hold == 1) begin
                            if (slot_hold >= 16 || !memo_occupied[slot_hold[3:0]]) begin
                                error_hold <= 7;
                                state <= PUBLISH;
                            end else begin
                                scan_index <= slot_hold[3:0];
                                state <= MEMO_SCAN;
                            end
                        end else
                            state <= TAG_READ;
                    end
                    TAG_READ: state <= TAG_CHECK;
                    TAG_CHECK: begin
                        if (op_hold == 0) begin
                            if (depth != 0 && request_rank >= parent_rank) begin
                                error_hold <= 7;
                                state <= PUBLISH;
                            end else
                                state <= PUSH_SETUP;
                        end else if (op_hold == 1) begin
                            slot_hold <= top_slot;
                            response_slot <= top_slot;
                            response_tag <= frame_tag_q;
                            state <= POP_SETUP;
                        end else if (op_hold == 2 && slot_hold != top_slot) begin
                            error_hold <= 7;
                            state <= PUBLISH;
                        end else if (slot_hold >= depth || !frame_occupied[slot_hold]) begin
                            error_hold <= 7;
                            state <= PUBLISH;
                        end else if (op_hold != 1 &&
                            frame_tag_q != request_tag) begin
                            error_hold <= 7;
                            state <= PUBLISH;
                        end else if (op_hold == 2)
                            state <= UPDATE_SETUP;
                        else if (op_hold == 3) begin
                            if (target_hold == 2) begin
                                if (!vector_occupied[vector_bit_index]) begin
                                    error_hold <= 7;
                                    state <= PUBLISH;
                                end else begin
                                    scan_index <= 0;
                                    state <= MEMO_SCAN;
                                end
                            end else if (target_hold == 3) begin
                                if (!copy_descriptor_valid ||
                                    !memo_occupied[copy_source_slot[3:0]]) begin
                                    error_hold <= 7;
                                    state <= PUBLISH;
                                end else begin
                                    scan_index <= copy_source_slot[3:0];
                                    state <= MEMO_SCAN;
                                end
                            end else
                                state <= VECTOR_SETUP;
                        end
                        else if (op_hold == 4) begin
                            if (!vector_occupied[vector_bit_index]) begin
                                error_hold <= 7;
                                state <= PUBLISH;
                            end else
                                state <= READ_SETUP;
                        end else
                            state <= SCALAR_SETUP;
                    end
                    PUSH_SETUP: begin
                        slot_hold <= depth[5:0];
                        response_slot <= depth[5:0];
                        pending_push <= 1;
                        continuation_index <= 0;
                        vector_occupied[{depth[5:0], 1'b0}+:2] <= 0;
                        scalar_occupied[32'(depth[5:0])*SCALAR_WORDS+:SCALAR_WORDS] <= 0;
                        state <= CONT_WRITE;
                    end
                    UPDATE_SETUP: begin
                        continuation_index <= 0;
                        scalar_occupied[32'(slot_hold)*SCALAR_WORDS+:8] <= 0;
                        response_slot <= slot_hold;
                        state <= CONT_WRITE;
                    end
                    CONT_WRITE: begin
                        backing_address_hold <= 18'(scalar_base + continuation_index);
                        backing_write_hold <= 1;
                        backing_data_hold <= continuation_word;
                        backing_return <= CONT_ADVANCE;
                        state <= BACKING_SEND;
                    end
                    CONT_ADVANCE: begin
                        if (continuation_index == 7) begin
                            scalar_occupied[32'(slot_hold)*SCALAR_WORDS+:8] <= 8'hff;
                            if (op_hold == 0)
                                state <= PUSH_COMMIT;
                            else
                                state <= PUBLISH;
                        end else begin
                            continuation_index <= continuation_index + 1'b1;
                            state <= CONT_WRITE;
                        end
                    end
                    PUSH_COMMIT: begin
                        frame_occupied[slot_hold] <= 1;
                        depth <= depth + 1'b1;
                        pending_push <= 0;
                        state <= PUBLISH;
                    end
                    POP_SETUP: begin
                        if (scalar_occupied[32'(slot_hold)*SCALAR_WORDS+:8] != 8'hff) begin
                            error_hold <= 7;
                            state <= PUBLISH;
                        end else begin
                            continuation_index <= 0;
                            state <= CONT_READ;
                        end
                    end
                    CONT_READ: begin
                        backing_address_hold <= 18'(scalar_base + continuation_index);
                        backing_write_hold <= 0;
                        backing_data_hold <= 0;
                        backing_return <= CONT_CAPTURE;
                        state <= BACKING_SEND;
                    end
                    CONT_CAPTURE: begin
                        continuation_result[32*continuation_index+:32] <= backing_result;
                        if (continuation_index == 7)
                            state <= POP_COMMIT;
                        else begin
                            continuation_index <= continuation_index + 1'b1;
                            state <= CONT_READ;
                        end
                    end
                    POP_COMMIT: begin
                        frame_occupied[slot_hold] <= 0;
                        vector_occupied[{slot_hold, 1'b0}+:2] <= 0;
                        scalar_occupied[32'(slot_hold)*SCALAR_WORDS+:SCALAR_WORDS] <= 0;
                        depth <= depth - 1'b1;
                        state <= PUBLISH;
                    end
                    MEMO_SCAN: state <= MEMO_CHECK;
                    MEMO_CHECK: begin
                        if (op_hold == 3 && target_hold == 3) begin
                            if (!memo_occupied[scan_index] ||
                                memo_tag_q != copy_memo_tag) begin
                                error_hold <= 7;
                                state <= PUBLISH;
                            end else begin
                                hit_hold <= 1;
                                hit_pulse <= 1;
                                state <= VECTOR_SETUP;
                            end
                        end else if (memo_occupied[scan_index] &&
                            memo_tag_q == request_tag) begin
                            response_slot <= {2'd0, scan_index};
                            if (op_hold == 5) begin
                                hit_hold <= 1;
                                hit_pulse <= 1;
                                state <= PUBLISH;
                            end else if (op_hold == 4)
                                state <= READ_SETUP;
                            else begin
                                slot_hold <= {2'd0, scan_index};
                                new_memo <= 0;
                                state <= VECTOR_SETUP;
                            end
                        end else if (op_hold == 4) begin
                            error_hold <= 7;
                            state <= PUBLISH;
                        end else if (scan_index == 15) begin
                            if (op_hold == 5)
                                state <= PUBLISH;
                            else begin
                                slot_hold <= {2'd0, cursor};
                                response_slot <= {2'd0, cursor};
                                new_memo <= 1;
                                state <= VECTOR_SETUP;
                            end
                        end else begin
                            scan_index <= scan_index + 1'b1;
                            state <= MEMO_SCAN;
                        end
                    end
                    VECTOR_SETUP: begin
                        pair_index <= 0;
                        response_slot <= slot_hold;
                        if (target_hold == 0 || target_hold == 3)
                            vector_occupied[vector_bit_index] <= 0;
                        else begin
                            pending_memo <= 1;
                            if (memo_occupied[slot_hold[3:0]]) begin
                                memo_count <= memo_count - 1'b1;
                                eviction_pulse <= new_memo;
                            end
                            memo_occupied[slot_hold[3:0]] <= 0;
                        end
                        if (target_hold == 2 || target_hold == 3)
                            state <= COPY_READ;
                        else
                            state <= STREAM;
                    end
                    STREAM: if (write_valid && write_ready) begin
                        if (write_abort || !flags_valid) begin
                            pending_memo <= 0;
                            error_hold <= 7;
                            state <= PUBLISH;
                        end else begin
                            backing_address_hold <= 18'(selected_vector_base + pair_index);
                            backing_write_hold <= 1;
                            backing_data_hold <= write_data;
                            backing_return <= STREAM_ADVANCE;
                            state <= BACKING_SEND;
                        end
                    end
                    STREAM_ADVANCE: begin
                        if (pair_index == (length_hold >> 1) - 1'b1)
                            state <= VECTOR_COMMIT;
                        else begin
                            pair_index <= pair_index + 1'b1;
                            if (target_hold == 2 || target_hold == 3)
                                state <= COPY_READ;
                            else
                                state <= STREAM;
                        end
                    end
                    COPY_READ: begin
                        backing_address_hold <= 18'(copy_source_base + pair_index);
                        backing_write_hold <= 0;
                        backing_data_hold <= 0;
                        backing_return <= COPY_CAPTURE;
                        state <= BACKING_SEND;
                    end
                    COPY_CAPTURE: begin
                        copy_data <= backing_result;
                        state <= COPY_WRITE;
                    end
                    COPY_WRITE: begin
                        backing_address_hold <= 18'(copy_destination_base + pair_index);
                        backing_write_hold <= 1;
                        backing_data_hold <= copy_data;
                        backing_return <= STREAM_ADVANCE;
                        state <= BACKING_SEND;
                    end
                    VECTOR_COMMIT: begin
                        if (target_hold == 0 || target_hold == 3)
                            vector_occupied[vector_bit_index] <= 1;
                        else begin
                            memo_occupied[slot_hold[3:0]] <= 1;
                            memo_count <= memo_count + 1'b1;
                            pending_memo <= 0;
                            if (new_memo) begin
                                if (cursor == 15)
                                    cursor <= 0;
                                else
                                    cursor <= cursor + 1'b1;
                            end
                        end
                        state <= PUBLISH;
                    end
                    READ_SETUP: begin
                        response_slot <= slot_hold;
                        backing_address_hold <= 18'(selected_vector_base +
                            {21'd0, component_hold[11:1]});
                        backing_write_hold <= 0;
                        backing_data_hold <= 0;
                        backing_return <= READ_FINISH;
                        state <= BACKING_SEND;
                    end
                    READ_FINISH: begin
                        data_hold <= backing_result;
                        state <= PUBLISH;
                    end
                    SCALAR_SETUP: begin
                        response_slot <= slot_hold;
                        if (op_hold == 7 && !scalar_occupied[scalar_bit_index]) begin
                            error_hold <= 7;
                            state <= PUBLISH;
                        end else begin
                            if (op_hold == 6)
                                scalar_occupied[scalar_bit_index] <= 0;
                            backing_address_hold <= 18'(scalar_base + scalar_index_hold);
                            backing_write_hold <= op_hold == 6;
                            backing_data_hold <= op_hold == 6 ? request_data : 32'd0;
                            backing_return <= SCALAR_FINISH;
                            state <= BACKING_SEND;
                        end
                    end
                    SCALAR_FINISH: begin
                        if (op_hold == 6)
                            scalar_occupied[scalar_bit_index] <= 1;
                        else
                            data_hold <= backing_result;
                        state <= PUBLISH;
                    end
                    BACKING_SEND: if (backing_ready)
                        state <= BACKING_WAIT;
                    BACKING_WAIT: if (backing_rsp_valid && backing_rsp_ready) begin
                        if (backing_rsp_error != 0) begin
                            error_hold <= backing_rsp_error;
                            pending_push <= 0;
                            pending_memo <= 0;
                            continuation_result <= 0;
                            data_hold <= 0;
                            state <= PUBLISH;
                        end else begin
                            backing_result <= backing_rsp_data;
                            state <= backing_return;
                        end
                    end
                    PUBLISH: state <= RESPONSE;
                    RESPONSE: if (rsp_ready)
                        state <= IDLE;
                    default: begin
                        error_hold <= 7;
                        active <= 0;
                        pending_push <= 0;
                        pending_memo <= 0;
                        state <= PUBLISH;
                    end
                endcase
            end
        end
    end endgenerate
endmodule
