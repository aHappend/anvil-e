module anvil_en1_anchor_materialize #(
    parameter integer COMPACT = 0
) (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] model,
    input wire [7:0] owner,
    input wire [31:0] generation, token,
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
    output wire write_start_valid,
    input wire write_start_ready,
    output wire [1:0] write_model,
    output wire [31:0] write_generation, write_token,
    output wire [7:0] write_owner,
    output wire write_is_value,
    output wire [1:0] write_kv_head,
    output wire write_valid,
    input wire write_ready,
    output wire [31:0] write_data,
    output wire write_first, write_last,
    input wire write_done_valid,
    output wire write_done_ready,
    input wire [3:0] write_done_error,
    output wire done_valid,
    input wire done_ready,
    output wire [3:0] done_error,
    output wire [63:0] live_payload_bytes, physical_payload_bytes,
    output wire [63:0] controller_bytes
);
    generate if (COMPACT != 0 && COMPACT != 1) begin : invalid_parameters
        initial $fatal(1, "PARAMETER ERROR: COMPACT must be 0 or 1");
        assign start_ready = 0;
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
        assign write_start_valid = 0;
        assign write_model = 0;
        assign write_generation = 0;
        assign write_token = 0;
        assign write_owner = 0;
        assign write_is_value = 0;
        assign write_kv_head = 0;
        assign write_valid = 0;
        assign write_data = 0;
        assign write_first = 0;
        assign write_last = 0;
        assign write_done_ready = 0;
        assign done_valid = 0;
        assign done_error = 0;
        assign live_payload_bytes = 0;
        assign physical_payload_bytes = 0;
        assign controller_bytes = 0;
    end else begin : materialize
        localparam integer PAIRS = COMPACT ? 2 : 128;
        localparam integer PAIR_BITS = $clog2(PAIRS);
        localparam [4:0] IDLE = 0, VALIDATE = 1,
            META_SEND = 2, META_WAIT = 3, META_CHECK = 4,
            FETCH_SEND = 5, FETCH_WAIT = 6, FETCH_CHECK = 7,
            BUFFER_WRITE = 8, COLLECT_ADVANCE = 9,
            RING_START = 10, BUFFER_READ = 11, BUFFER_CAPTURE = 12,
            RING_SEND = 13, RING_WAIT = 14, LANE_ADVANCE = 15,
            PUBLISH = 16, RESPONSE = 17;
        reg [4:0] state;
        reg [1:0] model_hold, head_hold, head_count;
        reg [7:0] owner_hold, canonical_owner;
        reg [31:0] generation_hold, token_hold;
        reg selector_hold, high_component, buffer_live, lane_complete;
        reg [7:0] pair_index;
        reg [3:0] error_hold, metadata_error, fetch_error_hold;
        reg metadata_alias;
        reg [1:0] metadata_space;
        reg [15:0] fetched_component, low_component;
        reg [31:0] pair_hold, buffer_q;
        wire [31:0] CONTROLLER_BITS = $bits({
            state, model_hold, head_hold, head_count, owner_hold, canonical_owner,
            generation_hold, token_hold, selector_hold, high_component, buffer_live,
            lane_complete, pair_index, error_hold, metadata_error, fetch_error_hold,
            metadata_alias, metadata_space, fetched_component, low_component,
            pair_hold, buffer_q
        });
        assign controller_bytes = rst_n ? 64'((CONTROLLER_BITS+7) >> 3) : 64'd0;
        (* ramstyle = "M20K", nomem2reg *)
        reg [31:0] payload [0:PAIRS-1];

        wire native_model;
        wire [7:0] owner_count;
        anvil_en1_geometry geometry (
            .rst_n(rst_n), .model(model_hold), .layer(owner_hold),
            .is_native(native_model), .layers(), .owners(owner_count), .owner(),
            .is_global(), .hidden(), .intermediate()
        );
        wire [9:0] component_index = {1'b0, pair_index, high_component};

        assign start_ready = rst_n && state == IDLE;
        assign req_valid = rst_n && state == META_SEND;
        assign req_op = 0;
        assign req_model = rst_n ? model_hold : 2'd0;
        assign req_layer = rst_n ? owner_hold : 8'd0;
        assign req_token = rst_n ? token_hold : 32'd0;
        assign req_is_value = rst_n && selector_hold;
        assign req_kv_head = rst_n ? head_hold : 2'd0;
        assign req_component = rst_n ? component_index : 10'd0;
        assign req_base = 0;
        assign rsp_ready = rst_n && state == META_WAIT;
        assign fetch_valid = rst_n && state == FETCH_SEND;
        assign fetch_model = rst_n ? model_hold : 2'd0;
        assign fetch_owner = rst_n ? canonical_owner : 8'd0;
        assign fetch_token = rst_n ? token_hold : 32'd0;
        assign fetch_is_value = rst_n && selector_hold;
        assign fetch_kv_head = rst_n ? head_hold : 2'd0;
        assign fetch_component = rst_n ? component_index : 10'd0;
        assign fetch_rsp_ready = rst_n && state == FETCH_WAIT;
        assign write_start_valid = rst_n && state == RING_START;
        assign write_model = rst_n ? model_hold : 2'd0;
        assign write_generation = rst_n ? generation_hold : 32'd0;
        assign write_token = rst_n ? token_hold : 32'd0;
        assign write_owner = rst_n ? owner_hold : 8'd0;
        assign write_is_value = rst_n && selector_hold;
        assign write_kv_head = rst_n ? head_hold : 2'd0;
        assign write_valid = rst_n && state == RING_SEND && lane_complete;
        assign write_data = rst_n ? pair_hold : 32'd0;
        assign write_first = rst_n && pair_index == 0;
        assign write_last = rst_n && pair_index == PAIRS - 1;
        assign write_done_ready = rst_n && state == RING_WAIT;
        assign done_valid = rst_n && state == RESPONSE;
        assign done_error = rst_n ? error_hold : 4'd0;
        assign live_payload_bytes = rst_n && buffer_live ? 64'(4*PAIRS) : 64'd0;
        assign physical_payload_bytes = rst_n ? 64'(4*PAIRS) : 64'd0;

        always @(posedge clk) begin
            if (rst_n && state == BUFFER_WRITE)
                payload[pair_index[PAIR_BITS-1:0]] <= pair_hold;
            if (rst_n && state == BUFFER_READ)
                buffer_q <= payload[pair_index[PAIR_BITS-1:0]];
        end

        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                state <= IDLE;
                model_hold <= 0;
                head_hold <= 0;
                head_count <= 0;
                owner_hold <= 0;
                canonical_owner <= 0;
                generation_hold <= 0;
                token_hold <= 0;
                selector_hold <= 0;
                high_component <= 0;
                buffer_live <= 0;
                lane_complete <= 0;
                pair_index <= 0;
                error_hold <= 0;
                metadata_error <= 0;
                fetch_error_hold <= 0;
                metadata_alias <= 0;
                metadata_space <= 0;
                fetched_component <= 0;
                low_component <= 0;
                pair_hold <= 0;
            end else begin
                case (state)
                    IDLE: if (start_valid && start_ready) begin
                        model_hold <= model;
                        owner_hold <= owner;
                        generation_hold <= generation;
                        token_hold <= token;
                        head_hold <= 0;
                        selector_hold <= 0;
                        high_component <= 0;
                        pair_index <= 0;
                        error_hold <= 0;
                        lane_complete <= 0;
                        state <= VALIDATE;
                    end
                    VALIDATE: begin
                        head_count <= COMPACT || model_hold == 1 ? 2'd1 : 2'd2;
                        if (!native_model) begin
                            error_hold <= 6;
                            state <= PUBLISH;
                        end else if (owner_hold != owner_count - 8'd2) begin
                            error_hold <= 7;
                            state <= PUBLISH;
                        end else if (token_hold > 131071) begin
                            error_hold <= 5;
                            state <= PUBLISH;
                        end else begin
                            buffer_live <= 1;
                            state <= META_SEND;
                        end
                    end
                    META_SEND: if (req_ready)
                        state <= META_WAIT;
                    META_WAIT: if (rsp_valid && rsp_ready) begin
                        canonical_owner <= rsp_owner;
                        metadata_alias <= rsp_alias;
                        metadata_error <= rsp_error;
                        metadata_space <= rsp_space;
                        state <= META_CHECK;
                    end
                    META_CHECK: begin
                        if (metadata_error != 0) begin
                            error_hold <= metadata_error;
                            state <= PUBLISH;
                        end else if (canonical_owner != owner_hold || metadata_alias ||
                            (metadata_space != 1 && metadata_space != 2)) begin
                            error_hold <= 7;
                            state <= PUBLISH;
                        end else
                            state <= FETCH_SEND;
                    end
                    FETCH_SEND: if (fetch_ready)
                        state <= FETCH_WAIT;
                    FETCH_WAIT: if (fetch_rsp_valid && fetch_rsp_ready) begin
                        fetched_component <= fetch_rsp_data;
                        fetch_error_hold <= fetch_rsp_error;
                        state <= FETCH_CHECK;
                    end
                    FETCH_CHECK: begin
                        if (fetch_error_hold != 0) begin
                            error_hold <= fetch_error_hold;
                            state <= PUBLISH;
                        end else if (!high_component) begin
                            low_component <= fetched_component;
                            high_component <= 1;
                            state <= META_SEND;
                        end else begin
                            pair_hold <= {fetched_component, low_component};
                            state <= BUFFER_WRITE;
                        end
                    end
                    BUFFER_WRITE: state <= COLLECT_ADVANCE;
                    COLLECT_ADVANCE: begin
                        high_component <= 0;
                        if (pair_index == PAIRS - 1) begin
                            lane_complete <= 1;
                            pair_index <= 0;
                            state <= RING_START;
                        end else begin
                            pair_index <= pair_index + 1'b1;
                            state <= META_SEND;
                        end
                    end
                    RING_START: if (write_start_ready)
                        state <= BUFFER_READ;
                    BUFFER_READ: state <= BUFFER_CAPTURE;
                    BUFFER_CAPTURE: begin
                        pair_hold <= buffer_q;
                        state <= RING_SEND;
                    end
                    RING_SEND: if (write_valid && write_ready) begin
                        if (pair_index == PAIRS - 1)
                            state <= RING_WAIT;
                        else begin
                            pair_index <= pair_index + 1'b1;
                            state <= BUFFER_READ;
                        end
                    end
                    RING_WAIT: if (write_done_valid && write_done_ready) begin
                        error_hold <= write_done_error;
                        state <= LANE_ADVANCE;
                    end
                    LANE_ADVANCE: begin
                        lane_complete <= 0;
                        if (error_hold != 0)
                            state <= PUBLISH;
                        else if (head_hold + 2'd1 < head_count) begin
                            head_hold <= head_hold + 1'b1;
                            pair_index <= 0;
                            state <= META_SEND;
                        end else if (!selector_hold) begin
                            head_hold <= 0;
                            selector_hold <= 1;
                            pair_index <= 0;
                            state <= META_SEND;
                        end else
                            state <= PUBLISH;
                    end
                    PUBLISH: state <= RESPONSE;
                    RESPONSE: if (done_ready) begin
                        buffer_live <= 0;
                        lane_complete <= 0;
                        state <= IDLE;
                    end
                    default: begin
                        error_hold <= 7;
                        lane_complete <= 0;
                        state <= PUBLISH;
                    end
                endcase
            end
        end
    end endgenerate
endmodule
