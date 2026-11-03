module anvil_en1_replay_workspace #(
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
    output wire [63:0] native_payload_bytes, native_production_shadow_bytes,
    output wire [63:0] backing_reserved_bytes, visibility_metadata_bytes,
    output wire [63:0] controller_bytes,
    output wire grant_valid,
    input wire grant_ready,
    output wire [4:0] grant_component,
    output wire [63:0] grant_payload_bytes, grant_shadow_bytes,
    output wire [63:0] grant_native_bytes, grant_native_shadow_bytes,
    input wire grant_rsp_valid,
    output wire grant_rsp_ready,
    input wire grant_allowed,
    input wire memo_pin_valid,
    input wire [3:0] memo_pin_slot,
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
        assign native_payload_bytes = 0;
        assign native_production_shadow_bytes = 0;
        assign backing_reserved_bytes = 0;
        assign visibility_metadata_bytes = 0;
        assign controller_bytes = 0;
        assign grant_valid = 0;
        assign grant_component = 0;
        assign grant_payload_bytes = 0;
        assign grant_shadow_bytes = 0;
        assign grant_native_bytes = 0;
        assign grant_native_shadow_bytes = 0;
        assign grant_rsp_ready = 0;
        assign memo_hit_event = 0;
        assign memo_eviction_event = 0;
        assign backing_valid = 0;
        assign backing_generation = 0;
        assign backing_write = 0;
        assign backing_addr = 0;
        assign backing_wdata = 0;
        assign backing_rsp_ready = 0;
    end else begin : workspace
        localparam integer BANK_WORDS = 1536;
        localparam integer FRAME_WORDS = 2 * BANK_WORDS;
        localparam integer MEMO_WORDS = COMPACT ? 512 : 2048;
        localparam integer SCALAR_WORDS = 32;
        localparam integer MEMO_BASE = 64 * FRAME_WORDS;
        localparam integer SCALAR_BASE = MEMO_BASE + 16 * MEMO_WORDS;
        localparam integer TOTAL_WORDS = SCALAR_BASE + 64 * SCALAR_WORDS;
        localparam integer TAG_BITS = 73;
        localparam integer KEY_BITS = 25;
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
            COPY_WRITE = 32, PAIR_SETUP = 33, PAIR_FINISH = 34,
            FRAME_RESERVE = 35, MEMO_RESERVE = 36, MEMO_VALIDATE = 37,
            CONTROL_BUDGET_TERMS = 38, CONTROL_BUDGET_SUM = 39,
            CONTROL_BUDGET_COMMIT = 40, MEMO_BUDGET_SCAN = 41,
            MEMO_BUDGET_EVICT = 42, MEMO_BUDGET_CHECK = 43,
            FRAME_VECTOR_RESERVE = 44, FRAME_VECTOR_GRANT = 45,
            POP_ACCOUNT = 46, POP_SIZE = 47,
            GRANT_TERMS = 48, GRANT_SUM = 49,
            GRANT_TOTAL = 50, GRANT_SEND = 51,
            GRANT_WAIT = 52, MEMO_GRANT_COMMIT = 53,
            FRAME_PUSH_COMMIT = 54, FRAME_VECTOR_COMMIT = 55,
            GRANT_NATIVE_ADJUST = 56, GRANT_MOVE_ADJUST = 57;
        reg [5:0] state, backing_return, vector_reserve_return;
        reg active, invalidate_hold, bank_hold, pending_push, pending_memo;
        reg hit_hold, hit_pulse, eviction_pulse, new_memo;
        reg [1:0] model_hold, control_model_hold, domain_hold, target_hold;
        reg [31:0] generation_hold, control_generation_hold, request_generation;
        reg [31:0] control_tokens_hold, tokens_hold;
        reg [31:0] memo_local_units, memo_global_units, memo_budget_units;
        reg [31:0] memo_budget_bytes;
        reg [3:0] budget_index;
        reg [4:0] budget_visits;
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
        reg [TAG_BITS-1:0] request_tag, response_tag;
        reg [KEY_BITS-1:0] frame_key_q, memo_key_q;
        function automatic [11:0] domain_length(
            input [1:0] domain, selected_model
        );
            begin
                if (domain == 0 || domain == 3)
                    domain_length = COMPACT ? 12'd8 :
                        (selected_model == 1 ? 12'd1536 : 12'd2560);
                else
                    domain_length = domain == 1 ? 12'd768 : 12'd1024;
            end
        endfunction
        wire [11:0] frame_length = domain_length(frame_key_q[24:23], model_hold);
        wire [11:0] memo_length = domain_length(memo_key_q[24:23], model_hold);
        wire [TAG_BITS-1:0] frame_tag_q = {model_hold, generation_hold,
            frame_key_q[24:23], 2'd0, frame_key_q[22:17],
            frame_key_q[16:0], frame_length};
        wire [TAG_BITS-1:0] memo_tag_q = {model_hold, generation_hold,
            memo_key_q[24:23], 2'd0, memo_key_q[22:17],
            memo_key_q[16:0], memo_length};
        reg [17:0] backing_address_hold;
        reg backing_write_hold;
        reg [31:0] backing_data_hold, backing_result;
        reg [31:0] copy_data;
        reg [63:0] frame_occupied;
        reg [383:0] vector_reserved;
        reg [383:0] vector_occupied;
        reg [383:0] pair_progress_valid;
        reg [4223:0] pair_next_index;
        reg [8:0] vector_index_hold;
        reg vector_present_q, vector_reserved_q, pair_active_q;
        reg [5:0] frame_reserved_q;
        reg [2:0] popped_count_hold;
        reg [31:0] popped_payload_hold, popped_shadow_hold;
        reg [10:0] pair_index_q;
        reg [15:0] memo_occupied;
        reg [31:0] memo_domains;
        reg [31:0] frame_payload_bytes, memo_payload_bytes;
        reg [31:0] shadow_frame_payload_bytes, shadow_memo_payload_bytes;
        reg [31:0] native_frame_payload_bytes, native_memo_payload_bytes;
        reg [31:0] native_shadow_frame_bytes, native_shadow_memo_bytes;
        reg [6:0] native_depth;
        reg [32:0] allocation_candidate, shadow_candidate;
        reg [63:0] grant_payload_hold, grant_shadow_hold;
        reg [63:0] grant_native_hold, grant_native_shadow_hold;
        reg [31:0] grant_native_memo, grant_native_shadow_memo;
        reg [1:0] grant_kind;
        reg grant_pin_valid;
        reg [3:0] grant_pin_slot;
        reg [64*SCALAR_WORDS-1:0] scalar_occupied;
        (* ramstyle = "MLAB", nomem2reg *)
        reg [KEY_BITS-1:0] frame_tags [0:63];
        (* ramstyle = "MLAB", nomem2reg *)
        reg [KEY_BITS-1:0] memo_tags [0:15];
        localparam integer METADATA_BITS = 80*KEY_BITS +
            $bits(frame_occupied) + $bits(vector_reserved) + $bits(vector_occupied) +
            $bits(pair_progress_valid) + $bits(pair_next_index) +
            $bits(memo_occupied) + $bits(memo_domains) + $bits(scalar_occupied);
        localparam integer CONTROLLER_BITS =
            $bits(state) + $bits(backing_return) + $bits(vector_reserve_return) +
            $bits(active) +
            $bits(invalidate_hold) + $bits(bank_hold) + $bits(pending_push) +
            $bits(pending_memo) + $bits(hit_hold) + $bits(hit_pulse) +
            $bits(eviction_pulse) + $bits(new_memo) + $bits(model_hold) +
            $bits(control_model_hold) + $bits(domain_hold) + $bits(target_hold) +
            $bits(generation_hold) + $bits(control_generation_hold) +
            $bits(control_tokens_hold) + $bits(tokens_hold) + $bits(memo_local_units) +
            $bits(memo_global_units) + $bits(memo_budget_units) +
            $bits(memo_budget_bytes) + $bits(budget_index) + $bits(budget_visits) +
            $bits(request_generation) + $bits(token_hold) + $bits(request_data) +
            $bits(data_hold) + $bits(layer_hold) + $bits(scalar_index_hold) +
            $bits(length_hold) + $bits(component_hold) + $bits(pair_index) +
            $bits(op_hold) + $bits(slot_hold) + $bits(response_slot) +
            $bits(copy_source_slot) + $bits(depth) + $bits(memo_count) +
            $bits(cursor) + $bits(scan_index) + $bits(error_hold) +
            $bits(continuation_index) + $bits(continuation_hold) +
            $bits(continuation_result) + $bits(request_tag) + $bits(response_tag) +
            $bits(frame_key_q) + $bits(memo_key_q) + $bits(backing_address_hold) +
            $bits(backing_write_hold) + $bits(backing_data_hold) +
            $bits(backing_result) + $bits(copy_data) + $bits(vector_index_hold) +
            $bits(vector_present_q) + $bits(vector_reserved_q) +
            $bits(frame_reserved_q) + $bits(popped_count_hold) +
            $bits(popped_payload_hold) +
            $bits(popped_shadow_hold) + $bits(pair_active_q) + $bits(pair_index_q) +
            $bits(frame_payload_bytes) + $bits(memo_payload_bytes) +
            $bits(shadow_frame_payload_bytes) + $bits(shadow_memo_payload_bytes) +
            $bits(native_frame_payload_bytes) + $bits(native_memo_payload_bytes) +
            $bits(native_shadow_frame_bytes) + $bits(native_shadow_memo_bytes) +
            $bits(native_depth) +
            $bits(allocation_candidate) + $bits(shadow_candidate) +
            $bits(grant_payload_hold) + $bits(grant_shadow_hold) +
            $bits(grant_native_hold) + $bits(grant_native_shadow_hold) +
            $bits(grant_native_memo) + $bits(grant_native_shadow_memo) +
            $bits(grant_kind) + $bits(grant_pin_valid) + $bits(grant_pin_slot);

        wire [TAG_BITS-1:0] incoming_tag = {req_model, req_generation,
            req_domain, req_layer, req_token[16:0], req_length};
        wire native_model = model_hold == 1 || model_hold == 2;
        wire [7:0] layer_limit = model_hold == 1 ? 8'd35 : 8'd42;
        wire [11:0] expected_length = domain_length(domain_hold, model_hold);
        wire descriptor_valid = token_hold <= 131071 &&
            ((domain_hold != 0 && domain_hold != 3) || token_hold < tokens_hold) &&
            length_hold == expected_length &&
            (domain_hold == 3 ? (layer_hold == 1 || layer_hold == 2) :
            (domain_hold == 0 ? layer_hold <= layer_limit :
            (domain_hold == 1 ? layer_hold <= 16 : layer_hold <= 12)));
        wire [6:0] request_rank = domain_hold == 0 ?
            {1'b0, layer_hold[5:0]} + 7'd19 :
            (domain_hold == 3 ? 7'd18 : {1'b0, layer_hold[5:0]} + 7'd1);
        wire [6:0] parent_rank = frame_tag_q[38:37] == 0 ?
            {1'b0, frame_tag_q[34:29]} + 7'd19 :
            (frame_tag_q[38:37] == 3 ? 7'd18 : {1'b0, frame_tag_q[34:29]} + 7'd1);
        wire request_session_valid = active && native_model &&
            request_generation == generation_hold;
        wire private_request = op_hold == 7 && target_hold == 1;
        wire move_to_memo = op_hold == 3 && target_hold == 2 && request_data == 1;
        wire move_account_valid = vector_reserved[vector_bit_index] &&
            vector_occupied[vector_bit_index] &&
            !pair_progress_valid[vector_bit_index] &&
            frame_payload_bytes >= request_vector_bytes &&
            shadow_frame_payload_bytes >= request_shadow_vector_bytes &&
            (!native_request ||
                (native_frame_payload_bytes >= request_vector_bytes &&
                 native_shadow_frame_bytes >= request_shadow_vector_bytes));
        wire private_global_layer;
        anvil_en1_geometry private_geometry (
            .rst_n(rst_n), .model(model_hold), .layer(layer_hold - 8'd1),
            .is_native(), .layers(), .owners(), .owner(),
            .is_global(private_global_layer), .hidden(), .intermediate()
        );
        wire [15:0] private_shadow_head = private_global_layer ? 16'd1024 : 16'd512;
        wire [15:0] private_actual_head = COMPACT ?
            (private_global_layer ? 16'd16 : 16'd8) : private_shadow_head;
        wire [15:0] private_ple_bytes = COMPACT ? 16'd8 : 16'd512;
        wire [15:0] private_actual_bytes = scalar_index_hold == 8 ?
            request_vector_bytes[15:0] + private_actual_head :
            (scalar_index_hold == 9 ? private_ple_bytes :
            (scalar_index_hold == 10 ?
                request_vector_bytes[15:0] + private_ple_bytes :
                (request_vector_bytes[15:0] << 1) +
                    request_vector_bytes[15:0] + private_ple_bytes));
        wire [15:0] private_shadow_bytes = scalar_index_hold == 8 ?
            production_text_vector_bytes[15:0] + private_shadow_head :
            (scalar_index_hold == 9 ? 16'd512 :
            (scalar_index_hold == 10 ?
                production_text_vector_bytes[15:0] + 16'd512 :
                (production_text_vector_bytes[15:0] << 1) +
                    production_text_vector_bytes[15:0] + 16'd512));
        wire text_private_descriptor_valid = domain_hold == 0 &&
            (layer_hold != 0 || scalar_index_hold == 10) &&
            (scalar_index_hold == 8 || scalar_index_hold == 9 ||
                scalar_index_hold == 10 || scalar_index_hold == 11) &&
            component_hold == 0 && !bank_hold &&
            request_data == {private_shadow_bytes, private_actual_bytes};
        wire [15:0] native_private_bytes = domain_hold == 1 ?
            (layer_hold == 0 ? 16'd0 : 16'd4608) :
            (domain_hold == 2 ? (layer_hold == 0 ? 16'd512 : 16'd16384) :
                (layer_hold == 1 ? 16'd6432 : 16'd6144));
        wire native_private_descriptor_valid =
            ((domain_hold == 1 && layer_hold <= 16 && scalar_index_hold == 12) ||
             (domain_hold == 2 && layer_hold <= 12 && scalar_index_hold == 13) ||
             (domain_hold == 3 && layer_hold == 2 && scalar_index_hold == 14) ||
             (domain_hold == 3 && layer_hold == 1 && scalar_index_hold == 15)) &&
            component_hold == 0 && !bank_hold &&
            request_data == {native_private_bytes, native_private_bytes};
        wire private_descriptor_valid = text_private_descriptor_valid ||
            native_private_descriptor_valid;
        wire [5:0] top_slot = depth[5:0] - 6'd1;
        wire [5:0] tag_frame_slot = op_hold <= 2 ? top_slot : slot_hold;
        wire [31:0] frame_base =
            ({26'd0, slot_hold} << 11) + ({26'd0, slot_hold} << 10);
        wire vector_operation = op_hold == 3 || op_hold == 4 ||
            (op_hold == 6 && target_hold >= 2) ||
            (op_hold == 7 && target_hold == 2);
        wire [1:0] vector_slice = domain_hold == 2 && vector_operation ?
            scalar_index_hold[1:0] : 2'd0;
        wire slice_valid = scalar_index_hold == 0 ||
            (domain_hold == 2 && scalar_index_hold < 3 &&
                ((op_hold == 4 && target_hold == 0) ||
                 (op_hold == 6 && target_hold == 2) ||
                 (op_hold == 7 && target_hold == 2)));
        wire release_descriptor_valid = component_hold == 0 && request_data == 0;
        wire [31:0] vector_base = frame_base +
            (bank_hold ? 32'(BANK_WORDS) : 32'd0) +
            ({30'd0, vector_slice} << 9);
        wire [31:0] memo_base = 32'(MEMO_BASE) +
            ({28'd0, slot_hold[3:0]} << (COMPACT ? 9 : 11));
        wire [31:0] scalar_base = 32'(SCALAR_BASE) +
            ({26'd0, slot_hold} << 5);
        wire [31:0] scalar_bit_index = ({26'd0, slot_hold} << 5) +
            {24'd0, scalar_index_hold};
        wire [8:0] selected_vector_index = ({3'd0, slot_hold} << 2) +
            ({3'd0, slot_hold} << 1) + (bank_hold ? 9'd3 : 9'd0) +
            {7'd0, vector_slice};
        wire [8:0] vector_bit_index = vector_index_hold;
        wire [11:0] expected_pair_component = {pair_index_q, 1'b0};
        wire [31:0] selected_vector_base = target_hold == 0 ? vector_base : memo_base;
        wire [31:0] copy_frame_base =
            ({26'd0, copy_source_slot} << 11) +
                ({26'd0, copy_source_slot} << 10);
        wire [31:0] copy_source_base = target_hold == 3 ?
            32'(MEMO_BASE) + ({26'd0, copy_source_slot} << (COMPACT ? 9 : 11)) :
            copy_frame_base + (bank_hold ? 32'(BANK_WORDS) : 32'd0);
        wire [31:0] copy_destination_base = target_hold == 3 ? vector_base : memo_base;
        wire [TAG_BITS-1:0] copy_memo_tag = {model_hold, generation_hold,
            domain_hold, request_data[25:18], request_data[16:0], length_hold};
        wire copy_descriptor_valid = copy_source_slot < 16 &&
            !request_data[17] && request_data[25:18] < layer_hold;
        wire flags_valid = write_first == (pair_index == 0) &&
            write_last == (pair_index == (length_hold >> 1) - 1'b1);
        wire [7:0] allocated_frames = {1'b0, depth} + {7'd0, pending_push};
        wire [31:0] production_text_vector_bytes = model_hold == 1 ? 32'd3072 : 32'd5120;
        wire [31:0] request_shadow_vector_bytes = domain_hold == 0 || domain_hold == 3 ?
            production_text_vector_bytes : (domain_hold == 1 ? 32'd1536 : 32'd2048);
        wire [31:0] request_vector_bytes = COMPACT &&
            (domain_hold == 0 || domain_hold == 3) ? 32'd16 : request_shadow_vector_bytes;
        wire [31:0] request_frame_bytes = domain_hold == 2 ? 32'd12288 :
            request_vector_bytes << 1;
        wire [31:0] request_shadow_frame_bytes = domain_hold == 2 ? 32'd12288 :
            request_shadow_vector_bytes << 1;
        wire [31:0] popped_shadow_vector_bytes =
            response_tag[38:37] == 0 || response_tag[38:37] == 3 ?
                production_text_vector_bytes :
                (response_tag[38:37] == 1 ? 32'd1536 : 32'd2048);
        wire [31:0] popped_vector_bytes = COMPACT &&
            (response_tag[38:37] == 0 || response_tag[38:37] == 3) ?
                32'd16 : popped_shadow_vector_bytes;
        wire [2:0] popped_vector_count =
            ({2'd0, frame_reserved_q[0]} + {2'd0, frame_reserved_q[1]}) +
            ({2'd0, frame_reserved_q[2]} + {2'd0, frame_reserved_q[3]}) +
            ({2'd0, frame_reserved_q[4]} + {2'd0, frame_reserved_q[5]});
        wire [31:0] popped_payload =
            (popped_count_hold[0] ? popped_vector_bytes : 32'd0) +
            (popped_count_hold[1] ? popped_vector_bytes << 1 : 32'd0) +
            (popped_count_hold[2] ? popped_vector_bytes << 2 : 32'd0);
        wire [31:0] popped_shadow_payload =
            (popped_count_hold[0] ? popped_shadow_vector_bytes : 32'd0) +
            (popped_count_hold[1] ? popped_shadow_vector_bytes << 1 : 32'd0) +
            (popped_count_hold[2] ? popped_shadow_vector_bytes << 2 : 32'd0);
        wire [1:0] replaced_memo_domain = memo_domains[2*slot_hold[3:0]+:2];
        wire [31:0] replaced_shadow_memo_bytes =
            replaced_memo_domain == 0 || replaced_memo_domain == 3 ?
                production_text_vector_bytes :
                (replaced_memo_domain == 1 ? 32'd1536 : 32'd2048);
        wire [31:0] replaced_memo_bytes = COMPACT &&
            (replaced_memo_domain == 0 || replaced_memo_domain == 3) ?
                32'd16 : replaced_shadow_memo_bytes;
        wire [63:0] live_frames = {32'd0, frame_payload_bytes};
        wire [63:0] live_scalars = {56'd0, allocated_frames} << 7;
        wire [63:0] live_memos = {32'd0, memo_payload_bytes} +
            (pending_memo ? {32'd0, request_vector_bytes} : 64'd0);
        wire [63:0] shadow_frames = {32'd0, shadow_frame_payload_bytes};
        wire [63:0] shadow_scalars = {56'd0, allocated_frames} << 7;
        wire [63:0] shadow_memos = {32'd0, shadow_memo_payload_bytes} +
            (pending_memo ? {32'd0, request_shadow_vector_bytes} : 64'd0);
        wire native_request = domain_hold != 0;
        wire native_pop = response_tag[38:37] != 0;
        wire native_victim = memo_occupied[slot_hold[3:0]] &&
            replaced_memo_domain != 0;
        wire [7:0] native_allocated_frames = {1'b0, native_depth} +
            {7'd0, pending_push && native_request};
        wire [63:0] native_scalars = {56'd0, native_allocated_frames} << 7;
        wire [63:0] native_frames = {32'd0, native_frame_payload_bytes};
        wire [63:0] native_shadow_frames = {32'd0, native_shadow_frame_bytes};
        wire [63:0] native_memos = {32'd0, native_memo_payload_bytes} +
            (pending_memo && native_request ? {32'd0, request_vector_bytes} : 64'd0);
        wire [63:0] native_shadow_memos = {32'd0, native_shadow_memo_bytes} +
            (pending_memo && native_request ?
                {32'd0, request_shadow_vector_bytes} : 64'd0);
        wire native_pop_valid = !native_pop ||
            (native_depth != 0 && native_frame_payload_bytes >= popped_payload_hold &&
                native_shadow_frame_bytes >= popped_shadow_hold);
        wire native_victim_valid = !native_victim ||
            (native_memo_payload_bytes >= replaced_memo_bytes &&
                native_shadow_memo_bytes >= replaced_shadow_memo_bytes);
        wire [31:0] continuation_word =
            continuation_hold[32*continuation_index+:32];
        wire [31:0] replaced_live_bytes = memo_occupied[slot_hold[3:0]] ?
            replaced_memo_bytes : 32'd0;
        wire [31:0] replaced_shadow_bytes = memo_occupied[slot_hold[3:0]] ?
            replaced_shadow_memo_bytes : 32'd0;
        wire frame_capacity_ok = allocation_candidate <= 33'(MEMO_BASE*4) &&
            shadow_candidate <= 33'(MEMO_BASE*4) && allocated_frames < 64;
        wire vector_capacity_ok = allocation_candidate <= 33'(MEMO_BASE*4) &&
            shadow_candidate <= 33'(MEMO_BASE*4);
        wire vector_grant_ok = vector_capacity_ok && slot_hold < depth &&
            frame_occupied[slot_hold] && !vector_reserved[vector_bit_index];
        wire memo_capacity_ok = allocation_candidate <= 33'(16*MEMO_WORDS*4) &&
            shadow_candidate <= 33'd131072;
        wire memo_budget_ok = allocation_candidate <= {1'b0, memo_budget_bytes} &&
            shadow_candidate <= {1'b0, memo_budget_bytes};
        wire [31:0] budget_padded = (tokens_hold + 32'd15) & 32'hfffffff0;
        wire [31:0] budget_window = budget_padded > 512 ? 32'd512 : budget_padded;
        wire [31:0] budget_bytes = memo_budget_units << (model_hold == 1 ? 4 : 5);
        wire [1:0] budget_victim_domain = memo_domains[2*budget_index+:2];
        wire [31:0] budget_victim_shadow =
            budget_victim_domain == 0 || budget_victim_domain == 3 ?
                production_text_vector_bytes :
                (budget_victim_domain == 1 ? 32'd1536 : 32'd2048);
        wire [31:0] budget_victim_bytes = COMPACT &&
            (budget_victim_domain == 0 || budget_victim_domain == 3) ?
                32'd16 : budget_victim_shadow;
        wire budget_victim_native = budget_victim_domain != 0;
        wire budget_victim_valid = memo_payload_bytes >= budget_victim_bytes &&
            shadow_memo_payload_bytes >= budget_victim_shadow &&
            (grant_kind != 0 ||
                (allocation_candidate >= {1'b0, budget_victim_bytes} &&
                 shadow_candidate >= {1'b0, budget_victim_shadow})) &&
            memo_count != 0 &&
            (!budget_victim_native ||
                (native_memo_payload_bytes >= budget_victim_bytes &&
                    native_shadow_memo_bytes >= budget_victim_shadow));

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
        assign production_shadow_bytes = rst_n ?
            shadow_frames + shadow_scalars + shadow_memos : 64'd0;
        assign native_payload_bytes = rst_n ?
            native_frames + native_scalars + native_memos : 64'd0;
        assign native_production_shadow_bytes = rst_n ?
            native_shadow_frames + native_scalars + native_shadow_memos : 64'd0;
        assign backing_reserved_bytes = rst_n ? 64'(TOTAL_WORDS * 4) : 64'd0;
        assign visibility_metadata_bytes = rst_n ?
            64'((METADATA_BITS + 7) >> 3) : 64'd0;
        assign controller_bytes = rst_n ? 64'((CONTROLLER_BITS + 7) >> 3) : 64'd0;
        assign grant_valid = rst_n && state == GRANT_SEND;
        assign grant_component = !rst_n ? 5'd0 :
            (grant_kind == 3 ? scalar_index_hold[4:0] : 5'd5);
        assign grant_payload_bytes = !rst_n ? 64'd0 :
            (grant_kind == 3 ? {48'd0, request_data[15:0]} : grant_payload_hold);
        assign grant_shadow_bytes = !rst_n ? 64'd0 :
            (grant_kind == 3 ? {48'd0, request_data[31:16]} : grant_shadow_hold);
        assign grant_native_bytes = rst_n ? grant_native_hold : 64'd0;
        assign grant_native_shadow_bytes = rst_n ? grant_native_shadow_hold : 64'd0;
        assign grant_rsp_ready = rst_n && state == GRANT_WAIT;
        assign memo_hit_event = rst_n && hit_pulse;
        assign memo_eviction_event = rst_n && eviction_pulse;
        wire backing_in_range = {14'd0, backing_address_hold} < TOTAL_WORDS;
        assign backing_valid = rst_n && state == BACKING_SEND && backing_in_range;
        assign backing_generation = rst_n ? generation_hold : 32'd0;
        assign backing_write = rst_n && backing_write_hold;
        assign backing_addr = rst_n ? backing_address_hold : 18'd0;
        assign backing_wdata = rst_n ? backing_data_hold : 32'd0;
        assign backing_rsp_ready = rst_n && state == BACKING_WAIT;

        always @(posedge clk) begin
            if (rst_n && state == TAG_READ) begin
                vector_present_q <= vector_occupied[vector_index_hold];
                vector_reserved_q <= vector_reserved[vector_index_hold];
                pair_active_q <= pair_progress_valid[vector_index_hold];
                pair_index_q <= pair_next_index[11*vector_index_hold+:11];
            end
            if (rst_n && state == FRAME_VECTOR_COMMIT && vector_grant_ok)
                vector_reserved_q <= 1;
            if (rst_n && state == TAG_READ && depth != 0) begin
                frame_key_q <= frame_tags[tag_frame_slot];
                frame_reserved_q <= vector_reserved[6*tag_frame_slot+:6];
            end
            if (rst_n && state == MEMO_SCAN)
                memo_key_q <= memo_tags[scan_index];
            if (rst_n && state == PUSH_COMMIT)
                frame_tags[slot_hold] <=
                    {request_tag[38:37], request_tag[34:29], request_tag[28:12]};
            if (rst_n && state == VECTOR_COMMIT &&
                (target_hold == 1 || target_hold == 2))
                memo_tags[slot_hold[3:0]] <=
                    {request_tag[38:37], request_tag[34:29], request_tag[28:12]};
        end

        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                state <= IDLE;
                backing_return <= 0;
                vector_reserve_return <= 0;
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
                control_tokens_hold <= 0;
                tokens_hold <= 0;
                memo_local_units <= 0;
                memo_global_units <= 0;
                memo_budget_units <= 0;
                memo_budget_bytes <= 0;
                budget_index <= 0;
                budget_visits <= 0;
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
                vector_reserved <= 0;
                vector_occupied <= 0;
                pair_progress_valid <= 0;
                pair_next_index <= 0;
                vector_index_hold <= 0;
                memo_occupied <= 0;
                memo_domains <= 0;
                frame_payload_bytes <= 0;
                memo_payload_bytes <= 0;
                shadow_frame_payload_bytes <= 0;
                shadow_memo_payload_bytes <= 0;
                native_frame_payload_bytes <= 0;
                native_memo_payload_bytes <= 0;
                native_shadow_frame_bytes <= 0;
                native_shadow_memo_bytes <= 0;
                native_depth <= 0;
                allocation_candidate <= 0;
                shadow_candidate <= 0;
                grant_payload_hold <= 0;
                grant_shadow_hold <= 0;
                grant_native_hold <= 0;
                grant_native_shadow_hold <= 0;
                grant_native_memo <= 0;
                grant_native_shadow_memo <= 0;
                grant_kind <= 0;
                grant_pin_valid <= 0;
                grant_pin_slot <= 0;
                popped_count_hold <= 0;
                popped_payload_hold <= 0;
                popped_shadow_hold <= 0;
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
                            control_tokens_hold <= control_tokens;
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
                            control_model_hold != 2) begin
                            error_hold <= 6;
                            state <= CONTROL_PUBLISH;
                        end else if (!invalidate_hold &&
                            (control_tokens_hold == 0 || control_tokens_hold > 131072)) begin
                            error_hold <= 5;
                            state <= CONTROL_PUBLISH;
                        end else begin
                            active <= !invalidate_hold;
                            model_hold <= control_model_hold;
                            generation_hold <= control_generation_hold;
                            tokens_hold <= invalidate_hold ? 32'd0 : control_tokens_hold;
                            depth <= 0;
                            memo_count <= 0;
                            cursor <= 0;
                            pending_push <= 0;
                            pending_memo <= 0;
                            frame_occupied <= 0;
                            vector_reserved <= 0;
                            vector_occupied <= 0;
                            pair_progress_valid <= 0;
                            pair_next_index <= 0;
                            memo_occupied <= 0;
                            memo_domains <= 0;
                            frame_payload_bytes <= 0;
                            memo_payload_bytes <= 0;
                            shadow_frame_payload_bytes <= 0;
                            shadow_memo_payload_bytes <= 0;
                            native_frame_payload_bytes <= 0;
                            native_memo_payload_bytes <= 0;
                            native_shadow_frame_bytes <= 0;
                            native_shadow_memo_bytes <= 0;
                            native_depth <= 0;
                            scalar_occupied <= 0;
                            memo_budget_bytes <= 0;
                            budget_index <= 0;
                            budget_visits <= 0;
                            if (invalidate_hold)
                                state <= CONTROL_PUBLISH;
                            else
                                state <= CONTROL_BUDGET_TERMS;
                        end
                    end
                    CONTROL_BUDGET_TERMS: begin
                        memo_local_units <= model_hold == 1 ?
                            (budget_window << 5) - (budget_window << 2) :
                            (budget_window << 5) + (budget_window << 1) + budget_window;
                        memo_global_units <= (budget_padded << 4) - (budget_padded << 1);
                        state <= CONTROL_BUDGET_SUM;
                    end
                    CONTROL_BUDGET_SUM: begin
                        memo_budget_units <= memo_local_units + memo_global_units;
                        state <= CONTROL_BUDGET_COMMIT;
                    end
                    CONTROL_BUDGET_COMMIT: begin
                        memo_budget_bytes <= budget_bytes > 131072 ? 32'd131072 : budget_bytes;
                        state <= CONTROL_PUBLISH;
                    end
                    CONTROL_PUBLISH: state <= CONTROL_RESPONSE;
                    CONTROL_RESPONSE: if (control_rsp_ready)
                        state <= IDLE;
                    VALIDATE: begin
                        vector_index_hold <= selected_vector_index;
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
                        end else if (vector_operation && !slice_valid) begin
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
                        end else if ((op_hold == 6 &&
                            target_hold != 0 && target_hold != 2 && target_hold != 3) ||
                            (op_hold == 7 && target_hold > 2)) begin
                            error_hold <= 5;
                            state <= PUBLISH;
                        end else if (op_hold == 7 && target_hold == 2 &&
                            !release_descriptor_valid) begin
                            error_hold <= 5;
                            state <= PUBLISH;
                        end else if (private_request && !private_descriptor_valid) begin
                            error_hold <= 5;
                            state <= PUBLISH;
                        end else if ((op_hold == 6 || op_hold == 7) &&
                            target_hold == 0 && scalar_index_hold >= SCALAR_WORDS) begin
                            error_hold <= 5;
                            state <= PUBLISH;
                        end else if (op_hold == 6 && target_hold >= 2 &&
                            (component_hold[0] || component_hold >= length_hold)) begin
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
                        end else if (vector_operation &&
                            (vector_present_q || pair_active_q) && !vector_reserved_q) begin
                            error_hold <= 7;
                            state <= PUBLISH;
                        end else if (op_hold == 2)
                            state <= UPDATE_SETUP;
                        else if (op_hold == 3) begin
                            if (target_hold == 2) begin
                                if (!vector_present_q || request_data > 1 ||
                                    (move_to_memo &&
                                        (slot_hold != top_slot || !move_account_valid))) begin
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
                            if (!vector_present_q) begin
                                error_hold <= 7;
                                state <= PUBLISH;
                            end else
                                state <= READ_SETUP;
                        end else if (op_hold == 6 && target_hold >= 2)
                            state <= PAIR_SETUP;
                        else if (op_hold == 7 && target_hold == 2) begin
                            if (!vector_reserved_q || !vector_present_q || pair_active_q ||
                                frame_payload_bytes < request_vector_bytes ||
                                shadow_frame_payload_bytes < request_shadow_vector_bytes ||
                                (native_request &&
                                    (native_frame_payload_bytes < request_vector_bytes ||
                                     native_shadow_frame_bytes < request_shadow_vector_bytes))) begin
                                error_hold <= 7;
                            end else begin
                                vector_reserved[vector_bit_index] <= 0;
                                vector_occupied[vector_bit_index] <= 0;
                                pair_progress_valid[vector_bit_index] <= 0;
                                pair_next_index[11*vector_bit_index+:11] <= 0;
                                frame_payload_bytes <= frame_payload_bytes - request_vector_bytes;
                                shadow_frame_payload_bytes <= shadow_frame_payload_bytes -
                                    request_shadow_vector_bytes;
                                if (native_request) begin
                                    native_frame_payload_bytes <= native_frame_payload_bytes -
                                        request_vector_bytes;
                                    native_shadow_frame_bytes <= native_shadow_frame_bytes -
                                        request_shadow_vector_bytes;
                                end
                            end
                            state <= PUBLISH;
                        end
                        else if (private_request) begin
                            grant_kind <= 3;
                            grant_pin_valid <= memo_pin_valid;
                            grant_pin_slot <= memo_pin_slot;
                            state <= GRANT_TERMS;
                        end else
                            state <= SCALAR_SETUP;
                    end
                    PUSH_SETUP: begin
                        allocation_candidate <= {1'b0, frame_payload_bytes} +
                            {1'b0, request_frame_bytes};
                        shadow_candidate <= {1'b0, shadow_frame_payload_bytes} +
                            {1'b0, request_shadow_frame_bytes};
                        state <= FRAME_RESERVE;
                    end
                    FRAME_RESERVE: begin
                        if (!frame_capacity_ok) begin
                            error_hold <= 7;
                            state <= PUBLISH;
                        end else begin
                            grant_kind <= 1;
                            grant_pin_valid <= memo_pin_valid;
                            grant_pin_slot <= memo_pin_slot;
                            state <= GRANT_TERMS;
                        end
                    end
                    FRAME_PUSH_COMMIT: begin
                        slot_hold <= depth[5:0];
                        response_slot <= depth[5:0];
                        pending_push <= 1;
                        continuation_index <= 0;
                        vector_reserved[6*depth[5:0]+:6] <= 0;
                        vector_occupied[6*depth[5:0]+:6] <= 0;
                        pair_progress_valid[6*depth[5:0]+:6] <= 0;
                        pair_next_index[66*depth[5:0]+:66] <= 0;
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
                        if (native_request) begin
                            native_depth <= native_depth + 1'b1;
                        end
                        pending_push <= 0;
                        state <= PUBLISH;
                    end
                    POP_SETUP: begin
                        popped_count_hold <= popped_vector_count;
                        state <= POP_SIZE;
                    end
                    POP_SIZE: begin
                        popped_payload_hold <= popped_payload;
                        popped_shadow_hold <= popped_shadow_payload;
                        state <= POP_ACCOUNT;
                    end
                    POP_ACCOUNT: begin
                        if (scalar_occupied[32'(slot_hold)*SCALAR_WORDS+:8] != 8'hff ||
                            frame_payload_bytes < popped_payload_hold ||
                            shadow_frame_payload_bytes < popped_shadow_hold ||
                            !native_pop_valid || native_depth > depth) begin
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
                        vector_reserved[6*slot_hold+:6] <= 0;
                        vector_occupied[6*slot_hold+:6] <= 0;
                        pair_progress_valid[6*slot_hold+:6] <= 0;
                        pair_next_index[66*slot_hold+:66] <= 0;
                        scalar_occupied[32'(slot_hold)*SCALAR_WORDS+:SCALAR_WORDS] <= 0;
                        depth <= depth - 1'b1;
                        frame_payload_bytes <= frame_payload_bytes - popped_payload_hold;
                        shadow_frame_payload_bytes <= shadow_frame_payload_bytes -
                            popped_shadow_hold;
                        if (native_pop) begin
                            native_frame_payload_bytes <= native_frame_payload_bytes -
                                popped_payload_hold;
                            native_shadow_frame_bytes <= native_shadow_frame_bytes -
                                popped_shadow_hold;
                            native_depth <= native_depth - 1'b1;
                        end
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
                        if (target_hold == 0 || target_hold == 3) begin
                            if (!vector_reserved_q) begin
                                vector_reserve_return <= VECTOR_SETUP;
                                state <= FRAME_VECTOR_RESERVE;
                            end else begin
                                vector_occupied[vector_bit_index] <= 0;
                                pair_progress_valid[vector_bit_index] <= 0;
                                pair_next_index[11*vector_bit_index+:11] <= 0;
                                if (target_hold == 3)
                                    state <= COPY_READ;
                                else
                                    state <= STREAM;
                            end
                        end else if (memo_payload_bytes < replaced_live_bytes ||
                            shadow_memo_payload_bytes < replaced_shadow_bytes ||
                            !native_victim_valid) begin
                            error_hold <= 7;
                            state <= PUBLISH;
                        end else begin
                            allocation_candidate <= {1'b0, memo_payload_bytes} -
                                {1'b0, replaced_live_bytes};
                            shadow_candidate <= {1'b0, shadow_memo_payload_bytes} -
                                {1'b0, replaced_shadow_bytes};
                            state <= MEMO_RESERVE;
                        end
                    end
                    FRAME_VECTOR_RESERVE: begin
                        allocation_candidate <= {1'b0, frame_payload_bytes} +
                            {1'b0, request_vector_bytes};
                        shadow_candidate <= {1'b0, shadow_frame_payload_bytes} +
                            {1'b0, request_shadow_vector_bytes};
                        state <= FRAME_VECTOR_GRANT;
                    end
                    FRAME_VECTOR_GRANT: begin
                        if (!vector_grant_ok) begin
                            error_hold <= 7;
                            state <= PUBLISH;
                        end else begin
                            grant_kind <= 2;
                            grant_pin_valid <= memo_pin_valid ||
                                (op_hold == 3 && target_hold == 3);
                            grant_pin_slot <= op_hold == 3 && target_hold == 3 ?
                                copy_source_slot[3:0] : memo_pin_slot;
                            state <= GRANT_TERMS;
                        end
                    end
                    FRAME_VECTOR_COMMIT: begin
                        frame_payload_bytes <= allocation_candidate[31:0];
                        shadow_frame_payload_bytes <= shadow_candidate[31:0];
                        if (native_request) begin
                            native_frame_payload_bytes <= native_frame_payload_bytes +
                                request_vector_bytes;
                            native_shadow_frame_bytes <= native_shadow_frame_bytes +
                                request_shadow_vector_bytes;
                        end
                        vector_reserved[vector_bit_index] <= 1;
                        state <= vector_reserve_return;
                    end
                    MEMO_RESERVE: begin
                        grant_kind <= 0;
                        grant_pin_valid <= 0;
                        grant_pin_slot <= 0;
                        allocation_candidate <= allocation_candidate +
                            {1'b0, request_vector_bytes};
                        shadow_candidate <= shadow_candidate +
                            {1'b0, request_shadow_vector_bytes};
                        state <= MEMO_VALIDATE;
                    end
                    MEMO_VALIDATE: begin
                        if (!memo_capacity_ok) begin
                            error_hold <= 7;
                            state <= PUBLISH;
                        end else if (!memo_budget_ok) begin
                            budget_index <= cursor;
                            budget_visits <= 0;
                            state <= MEMO_BUDGET_SCAN;
                        end else
                            state <= GRANT_TERMS;
                    end
                    GRANT_TERMS: begin
                        grant_payload_hold <=
                            (grant_kind == 2 ? {31'd0, allocation_candidate} : live_frames) +
                            live_scalars;
                        grant_shadow_hold <=
                            (grant_kind == 2 ? {31'd0, shadow_candidate} : shadow_frames) +
                            shadow_scalars;
                        grant_native_hold <= native_frames + native_scalars;
                        grant_native_shadow_hold <= native_shadow_frames + native_scalars;
                        grant_native_memo <= native_memo_payload_bytes -
                            (grant_kind == 0 && native_victim ? replaced_memo_bytes : 32'd0);
                        grant_native_shadow_memo <= native_shadow_memo_bytes -
                            (grant_kind == 0 && native_victim ?
                                replaced_shadow_memo_bytes : 32'd0);
                        state <= GRANT_SUM;
                    end
                    GRANT_SUM: begin
                        grant_payload_hold <= grant_payload_hold +
                            (grant_kind == 0 ? {31'd0, allocation_candidate} :
                                {32'd0, memo_payload_bytes});
                        grant_shadow_hold <= grant_shadow_hold +
                            (grant_kind == 0 ? {31'd0, shadow_candidate} :
                                {32'd0, shadow_memo_payload_bytes});
                        grant_native_memo <= grant_native_memo +
                            (grant_kind == 0 && native_request ? request_vector_bytes : 32'd0);
                        grant_native_shadow_memo <= grant_native_shadow_memo +
                            (grant_kind == 0 && native_request ?
                                request_shadow_vector_bytes : 32'd0);
                        state <= GRANT_TOTAL;
                    end
                    GRANT_TOTAL: begin
                        grant_payload_hold <= grant_payload_hold +
                            (grant_kind == 1 ? 64'd128 : 64'd0);
                        grant_shadow_hold <= grant_shadow_hold +
                            (grant_kind == 1 ? 64'd128 : 64'd0);
                        grant_native_hold <= grant_native_hold + {32'd0, grant_native_memo};
                        grant_native_shadow_hold <= grant_native_shadow_hold +
                            {32'd0, grant_native_shadow_memo};
                        state <= GRANT_NATIVE_ADJUST;
                    end
                    GRANT_NATIVE_ADJUST: begin
                        grant_native_hold <= grant_native_hold +
                            (!native_request ? 64'd0 :
                            (grant_kind == 1 ? 64'd128 :
                            (grant_kind == 2 ? {32'd0, request_vector_bytes} : 64'd0)));
                        grant_native_shadow_hold <= grant_native_shadow_hold +
                            (!native_request ? 64'd0 :
                            (grant_kind == 1 ? 64'd128 :
                            (grant_kind == 2 ? {32'd0, request_shadow_vector_bytes} : 64'd0)));
                        if (move_to_memo && grant_kind == 0)
                            state <= GRANT_MOVE_ADJUST;
                        else
                            state <= GRANT_SEND;
                    end
                    GRANT_MOVE_ADJUST: begin
                        grant_payload_hold <= grant_payload_hold -
                            {32'd0, request_vector_bytes};
                        grant_shadow_hold <= grant_shadow_hold -
                            {32'd0, request_shadow_vector_bytes};
                        if (native_request) begin
                            grant_native_hold <= grant_native_hold -
                                {32'd0, request_vector_bytes};
                            grant_native_shadow_hold <= grant_native_shadow_hold -
                                {32'd0, request_shadow_vector_bytes};
                        end
                        state <= GRANT_SEND;
                    end
                    GRANT_SEND: if (grant_ready)
                        state <= GRANT_WAIT;
                    GRANT_WAIT: if (grant_rsp_valid) begin
                        if (grant_allowed) begin
                            if (grant_kind == 1)
                                state <= FRAME_PUSH_COMMIT;
                            else if (grant_kind == 2)
                                state <= FRAME_VECTOR_COMMIT;
                            else if (grant_kind == 3)
                                state <= PUBLISH;
                            else
                                state <= MEMO_GRANT_COMMIT;
                        end else begin
                            budget_index <= cursor;
                            budget_visits <= 0;
                            state <= MEMO_BUDGET_SCAN;
                        end
                    end
                    MEMO_GRANT_COMMIT: begin
                        if (move_to_memo && !move_account_valid) begin
                            error_hold <= 7;
                            state <= PUBLISH;
                        end else begin
                            pending_memo <= 1;
                            if (move_to_memo) begin
                                vector_reserved[vector_bit_index] <= 0;
                                vector_occupied[vector_bit_index] <= 0;
                                pair_progress_valid[vector_bit_index] <= 0;
                                pair_next_index[11*vector_bit_index+:11] <= 0;
                                frame_payload_bytes <= frame_payload_bytes -
                                    request_vector_bytes;
                                shadow_frame_payload_bytes <= shadow_frame_payload_bytes -
                                    request_shadow_vector_bytes;
                                if (native_request) begin
                                    native_frame_payload_bytes <= native_frame_payload_bytes -
                                        request_vector_bytes;
                                    native_shadow_frame_bytes <= native_shadow_frame_bytes -
                                        request_shadow_vector_bytes;
                                end
                            end
                            if (memo_occupied[slot_hold[3:0]]) begin
                                memo_count <= memo_count - 1'b1;
                                memo_payload_bytes <= memo_payload_bytes - replaced_memo_bytes;
                                shadow_memo_payload_bytes <= shadow_memo_payload_bytes -
                                    replaced_shadow_memo_bytes;
                                if (native_victim) begin
                                    native_memo_payload_bytes <= native_memo_payload_bytes -
                                        replaced_memo_bytes;
                                    native_shadow_memo_bytes <= native_shadow_memo_bytes -
                                        replaced_shadow_memo_bytes;
                                end
                                eviction_pulse <= new_memo;
                            end
                            memo_occupied[slot_hold[3:0]] <= 0;
                            if (target_hold == 2)
                                state <= COPY_READ;
                            else
                                state <= STREAM;
                        end
                    end
                    MEMO_BUDGET_SCAN: begin
                        if (budget_visits == 16) begin
                            error_hold <= 7;
                            state <= PUBLISH;
                        end else if ((grant_kind != 0 || budget_index != slot_hold[3:0]) &&
                            (!grant_pin_valid || budget_index != grant_pin_slot) &&
                            memo_occupied[budget_index])
                            state <= MEMO_BUDGET_EVICT;
                        else begin
                            budget_index <= budget_index + 1'b1;
                            budget_visits <= budget_visits + 1'b1;
                        end
                    end
                    MEMO_BUDGET_EVICT: begin
                        if (!budget_victim_valid) begin
                            error_hold <= 7;
                            state <= PUBLISH;
                        end else begin
                            memo_occupied[budget_index] <= 0;
                            memo_count <= memo_count - 1'b1;
                            memo_payload_bytes <= memo_payload_bytes - budget_victim_bytes;
                            shadow_memo_payload_bytes <= shadow_memo_payload_bytes -
                                budget_victim_shadow;
                            if (grant_kind == 0) begin
                                allocation_candidate <= allocation_candidate -
                                    {1'b0, budget_victim_bytes};
                                shadow_candidate <= shadow_candidate -
                                    {1'b0, budget_victim_shadow};
                            end
                            if (budget_victim_native) begin
                                native_memo_payload_bytes <= native_memo_payload_bytes -
                                    budget_victim_bytes;
                                native_shadow_memo_bytes <= native_shadow_memo_bytes -
                                    budget_victim_shadow;
                            end
                            eviction_pulse <= 1;
                            budget_index <= budget_index + 1'b1;
                            budget_visits <= budget_visits + 1'b1;
                            state <= MEMO_BUDGET_CHECK;
                        end
                    end
                    MEMO_BUDGET_CHECK: begin
                        if (grant_kind != 0)
                            state <= GRANT_TERMS;
                        else if (memo_budget_ok)
                            state <= MEMO_VALIDATE;
                        else
                            state <= MEMO_BUDGET_SCAN;
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
                            memo_payload_bytes <= memo_payload_bytes + request_vector_bytes;
                            shadow_memo_payload_bytes <= shadow_memo_payload_bytes +
                                request_shadow_vector_bytes;
                            if (native_request) begin
                                native_memo_payload_bytes <= native_memo_payload_bytes +
                                    request_vector_bytes;
                                native_shadow_memo_bytes <= native_shadow_memo_bytes +
                                    request_shadow_vector_bytes;
                            end
                            memo_domains[2*slot_hold[3:0]+:2] <= domain_hold;
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
                    PAIR_SETUP: begin
                        response_slot <= slot_hold;
                        if ((target_hold == 3 && !vector_present_q) ||
                            (target_hold == 2 && component_hold != 0 &&
                                (!pair_active_q ||
                                 component_hold != expected_pair_component))) begin
                            error_hold <= 7;
                            state <= PUBLISH;
                        end else if (!vector_reserved_q) begin
                            vector_reserve_return <= PAIR_SETUP;
                            state <= FRAME_VECTOR_RESERVE;
                        end else begin
                            if (target_hold == 2 && component_hold == 0) begin
                                vector_occupied[vector_bit_index] <= 0;
                                pair_progress_valid[vector_bit_index] <= 0;
                                pair_next_index[11*vector_bit_index+:11] <= 0;
                            end
                            backing_address_hold <= 18'(vector_base +
                                {21'd0, component_hold[11:1]});
                            backing_write_hold <= 1;
                            backing_data_hold <= request_data;
                            backing_return <= PAIR_FINISH;
                            state <= BACKING_SEND;
                        end
                    end
                    PAIR_FINISH: begin
                        if (target_hold == 2) begin
                            if ({1'b0, component_hold} + 13'd2 == {1'b0, length_hold}) begin
                                pair_progress_valid[vector_bit_index] <= 0;
                                pair_next_index[11*vector_bit_index+:11] <= 0;
                                vector_occupied[vector_bit_index] <= 1;
                            end else begin
                                pair_progress_valid[vector_bit_index] <= 1;
                                pair_next_index[11*vector_bit_index+:11] <=
                                    component_hold[11:1] + 11'd1;
                            end
                        end
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
                    BACKING_SEND: begin
                        if (!backing_in_range) begin
                            error_hold <= 7;
                            pending_push <= 0;
                            pending_memo <= 0;
                            state <= PUBLISH;
                        end else if (backing_ready)
                            state <= BACKING_WAIT;
                    end
                    BACKING_WAIT: if (backing_rsp_valid && backing_rsp_ready) begin
                        if (backing_rsp_error != 0) begin
                            error_hold <= backing_rsp_error;
                            pending_push <= 0;
                            pending_memo <= 0;
                            continuation_result <= 0;
                            data_hold <= 0;
                            if (op_hold == 6 && target_hold >= 2) begin
                                vector_occupied[vector_bit_index] <= 0;
                                pair_progress_valid[vector_bit_index] <= 0;
                                pair_next_index[11*vector_bit_index+:11] <= 0;
                            end
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
