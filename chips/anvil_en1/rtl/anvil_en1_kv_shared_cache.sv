module anvil_en1_kv_shared_cache #(
    parameter integer RESIDENT_ENTRIES = 3,
    parameter integer COMPACT = 0
) (
    input wire clk, rst_n,
    input wire req_valid,
    output wire req_ready,
    input wire [2:0] req_op,
    input wire [1:0] req_model,
    input wire [7:0] req_layer,
    input wire [31:0] req_token,
    input wire req_is_value,
    input wire [1:0] req_kv_head,
    input wire [9:0] req_component,
    input wire [63:0] req_base,
    output wire rsp_valid,
    input wire rsp_ready,
    output wire [63:0] rsp_addr,
    output wire [7:0] rsp_owner,
    output wire rsp_alias,
    output wire [3:0] rsp_error,
    output wire [1:0] rsp_space,
    input wire fetch_valid,
    output wire fetch_ready,
    input wire [1:0] fetch_model,
    input wire [7:0] fetch_owner,
    input wire [31:0] fetch_token,
    input wire fetch_is_value,
    input wire [1:0] fetch_kv_head,
    input wire [9:0] fetch_component,
    output wire fetch_rsp_valid,
    input wire fetch_rsp_ready,
    output wire [15:0] fetch_rsp_data,
    output wire [3:0] fetch_rsp_error,
    output wire regen_valid,
    input wire regen_ready,
    output wire [1:0] regen_model,
    output wire [7:0] regen_owner,
    output wire [31:0] regen_token,
    output wire regen_is_value,
    output wire [1:0] regen_kv_head,
    output wire [9:0] regen_component,
    input wire regen_rsp_valid,
    output wire regen_rsp_ready,
    input wire [31:0] regen_rsp_data,
    input wire [3:0] regen_rsp_error
);
    localparam integer LEGAL = RESIDENT_ENTRIES >= 1 &&
        RESIDENT_ENTRIES <= 64 && (COMPACT == 0 || COMPACT == 1);

    generate if (!LEGAL) begin : invalid_parameters
        initial $fatal(1, "PARAMETER ERROR: RESIDENT_ENTRIES must be 1..64; COMPACT must be 0 or 1");
        assign req_ready = 0;
        assign rsp_valid = 0;
        assign rsp_addr = 0;
        assign rsp_owner = 0;
        assign rsp_alias = 0;
        assign rsp_error = 0;
        assign rsp_space = 0;
        assign fetch_ready = 0;
        assign fetch_rsp_valid = 0;
        assign fetch_rsp_data = 0;
        assign fetch_rsp_error = 0;
        assign regen_valid = 0;
        assign regen_model = 0;
        assign regen_owner = 0;
        assign regen_token = 0;
        assign regen_is_value = 0;
        assign regen_kv_head = 0;
        assign regen_component = 0;
        assign regen_rsp_ready = 0;
    end else begin : cache
        localparam [2:0] META_IDLE = 0, META_MAP = 1, META_PUBLISH = 2,
            META_RESPONSE = 3, META_DRAIN = 4;
        localparam [3:0] FETCH_IDLE = 0, FETCH_READ = 1, FETCH_LOOKUP = 2,
            FETCH_REGEN = 3, FETCH_WAIT = 4, FETCH_REGISTER = 5,
            FETCH_RESPONSE = 6;
        localparam integer TAG_WIDTH = 70;
        reg [2:0] meta_state;
        reg [3:0] fetch_state;
        reg [31:0] generation;
        reg [RESIDENT_ENTRIES-1:0] occupied;
        reg [5:0] replace_index;
        reg [2:0] op_hold;
        reg [1:0] model_hold;
        reg [7:0] layer_hold;
        reg [31:0] token_hold;
        reg selector_hold;
        reg [1:0] head_hold;
        reg [9:0] component_hold;
        reg [63:0] base_hold, addr_hold;
        reg [7:0] owner_hold;
        reg alias_hold;
        reg [3:0] meta_error;
        reg [1:0] space_hold;
        reg [1:0] data_model;
        reg [7:0] data_owner;
        reg [31:0] data_token;
        reg data_selector;
        reg [1:0] data_head;
        reg [9:0] data_component;
        reg [TAG_WIDTH-1:0] data_tag;
        reg [15:0] data_response;
        reg [3:0] data_error;
        reg [31:0] pair_hold;
        reg pair_cancelled;
        reg [3:0] pair_error;
        reg hit_hold;
        reg [31:0] payload_q;
        reg [TAG_WIDTH-1:0] tags [0:RESIDENT_ENTRIES-1];
        (* ramstyle = "MLAB", nomem2reg *)
        reg [31:0] payload [0:RESIDENT_ENTRIES-1];

        wire invalidate_accept = req_valid && req_ready && req_op == 2 &&
            req_model != 3;
        wire invalidating = invalidate_accept || meta_state == META_DRAIN ||
            (meta_state == META_MAP && op_hold == 2 && model_hold != 3) ||
            (meta_state == META_PUBLISH && op_hold == 2 && model_hold != 3);
        wire [7:0] mapped_owner, mapped_layers, mapped_owners;
        wire mapped_global;
        anvil_en1_geometry metadata_geometry (
            .rst_n(rst_n), .model(model_hold), .layer(layer_hold),
            .is_native(), .layers(mapped_layers), .owners(mapped_owners),
            .owner(mapped_owner), .is_global(mapped_global), .hidden(), .intermediate()
        );
        wire [9:0] mapped_dimension = COMPACT ?
            (mapped_global ? 10'd8 : 10'd4) :
            (mapped_global ? 10'd512 : 10'd256);
        wire [2:0] mapped_heads = COMPACT || model_hold == 1 ? 3'd1 : 3'd2;
        wire [63:0] virtual_address =
            ({62'd0, model_hold} << 44) |
            ({56'd0, mapped_owner} << 36) |
            ({47'd0, token_hold[16:0]} << 19) |
            ({63'd0, selector_hold} << 18) |
            ({62'd0, head_hold} << 16) |
            ({55'd0, component_hold[9:1]} << 2);
        wire data_global, data_native;
        wire [7:0] data_owners;
        anvil_en1_geometry fetch_geometry (
            .rst_n(rst_n), .model(data_model), .layer(data_owner),
            .is_native(data_native), .layers(), .owners(data_owners),
            .owner(), .is_global(data_global), .hidden(), .intermediate()
        );
        wire [9:0] data_dimension = COMPACT ?
            (data_global ? 10'd8 : 10'd4) :
            (data_global ? 10'd512 : 10'd256);
        wire [2:0] data_heads = COMPACT || data_model == 1 ? 3'd1 : 3'd2;
        wire [TAG_WIDTH-1:0] incoming_tag = {
            fetch_model, generation, fetch_owner, fetch_token[16:0],
            fetch_is_value, fetch_kv_head, fetch_component[8:1]
        };
        wire insert_word = fetch_state == FETCH_WAIT && regen_rsp_valid &&
            regen_rsp_ready && regen_rsp_error == 0 && !invalidating;

        wire tree_hit [1:127];
        wire [5:0] tree_index [1:127];
        genvar leaf, branch;
        for (leaf = 0; leaf < 64; leaf = leaf + 1) begin : compare_tags
            if (leaf < RESIDENT_ENTRIES) begin : present
                assign tree_hit[64+leaf] = occupied[leaf] && tags[leaf] == data_tag;
            end else begin : absent
                assign tree_hit[64+leaf] = 0;
            end
            assign tree_index[64+leaf] = 6'(leaf);
        end
        for (branch = 1; branch < 64; branch = branch + 1) begin : select_hit
            assign tree_hit[branch] = tree_hit[2*branch] || tree_hit[2*branch+1];
            assign tree_index[branch] = tree_hit[2*branch] ?
                tree_index[2*branch] : tree_index[2*branch+1];
        end

        assign req_ready = rst_n && meta_state == META_IDLE;
        assign rsp_valid = rst_n && meta_state == META_RESPONSE;
        assign rsp_addr = rst_n ? addr_hold : 64'd0;
        assign rsp_owner = rst_n ? owner_hold : 8'd0;
        assign rsp_alias = rst_n && alias_hold;
        assign rsp_error = rst_n ? meta_error : 4'd0;
        assign rsp_space = rst_n ? space_hold : 2'd0;
        assign fetch_ready = rst_n && fetch_state == FETCH_IDLE && !invalidating;
        assign fetch_rsp_valid = rst_n && fetch_state == FETCH_RESPONSE;
        assign fetch_rsp_data = rst_n ? data_response : 16'd0;
        assign fetch_rsp_error = rst_n ? data_error : 4'd0;
        assign regen_valid = rst_n && fetch_state == FETCH_REGEN;
        assign regen_model = rst_n ? data_model : 2'd0;
        assign regen_owner = rst_n ? data_owner : 8'd0;
        assign regen_token = rst_n ? data_token : 32'd0;
        assign regen_is_value = rst_n && data_selector;
        assign regen_kv_head = rst_n ? data_head : 2'd0;
        assign regen_component = rst_n ? {data_component[9:1], 1'b0} : 10'd0;
        assign regen_rsp_ready = rst_n && fetch_state == FETCH_WAIT;

        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                meta_state <= META_IDLE;
                generation <= 0;
                op_hold <= 0;
                model_hold <= 0;
                layer_hold <= 0;
                token_hold <= 0;
                selector_hold <= 0;
                head_hold <= 0;
                component_hold <= 0;
                base_hold <= 0;
                addr_hold <= 0;
                owner_hold <= 0;
                alias_hold <= 0;
                meta_error <= 0;
                space_hold <= 0;
            end else begin
                case (meta_state)
                    META_IDLE: if (req_valid && req_ready) begin
                        op_hold <= req_op;
                        model_hold <= req_model;
                        layer_hold <= req_layer;
                        token_hold <= req_token;
                        selector_hold <= req_is_value;
                        head_hold <= req_kv_head;
                        component_hold <= req_component;
                        base_hold <= req_base;
                        meta_state <= META_MAP;
                    end
                    META_MAP: begin
                        addr_hold <= 0;
                        owner_hold <= 0;
                        alias_hold <= 0;
                        meta_error <= 0;
                        space_hold <= 3;
                        meta_state <= META_PUBLISH;
                        if (model_hold == 3)
                            meta_error <= 6;
                        else if (op_hold > 2)
                            meta_error <= 1;
                        else if (op_hold == 2)
                            meta_state <= META_DRAIN;
                        else if (model_hold == 0) begin
                            if (base_hold[1:0] != 0)
                                meta_error <= 2;
                            else begin
                                addr_hold <= base_hold;
                                owner_hold <= layer_hold;
                                space_hold <= 0;
                            end
                        end else if (layer_hold >= mapped_layers ||
                            token_hold > 131071 || head_hold >= mapped_heads ||
                            component_hold >= mapped_dimension)
                            meta_error <= 2;
                        else if (op_hold == 1 && layer_hold >= mapped_owners)
                            meta_error <= 7;
                        else begin
                            addr_hold <= virtual_address;
                            owner_hold <= mapped_owner;
                            alias_hold <= layer_hold != mapped_owner;
                            space_hold <= 2;
                        end
                    end
                    META_PUBLISH: meta_state <= META_RESPONSE;
                    META_DRAIN: if (fetch_state == FETCH_IDLE) begin
                        generation <= generation + 1'b1;
                        meta_state <= META_RESPONSE;
                    end
                    META_RESPONSE: if (rsp_ready) meta_state <= META_IDLE;
                    default: begin
                        addr_hold <= 0;
                        owner_hold <= 0;
                        alias_hold <= 0;
                        meta_error <= 7;
                        space_hold <= 3;
                        meta_state <= META_RESPONSE;
                    end
                endcase
            end
        end

        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                occupied <= 0;
                replace_index <= 0;
            end else if (meta_state == META_DRAIN && fetch_state == FETCH_IDLE) begin
                occupied <= 0;
                replace_index <= 0;
            end else if (insert_word) begin
                occupied[replace_index] <= 1;
                if (replace_index == RESIDENT_ENTRIES-1)
                    replace_index <= 0;
                else
                    replace_index <= replace_index + 1'b1;
            end
        end

        always @(posedge clk) begin
            if (rst_n && fetch_state == FETCH_READ) begin
                if (tree_hit[1])
                    payload_q <= payload[tree_index[1]];
            end
            if (rst_n && insert_word) begin
                payload[replace_index] <= regen_rsp_data;
                tags[replace_index] <= data_tag;
            end
        end

        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                fetch_state <= FETCH_IDLE;
                data_model <= 0;
                data_owner <= 0;
                data_token <= 0;
                data_selector <= 0;
                data_head <= 0;
                data_component <= 0;
                data_tag <= 0;
                data_response <= 0;
                data_error <= 0;
                pair_hold <= 0;
                pair_error <= 0;
                pair_cancelled <= 0;
                hit_hold <= 0;
            end else begin
                case (fetch_state)
                    FETCH_IDLE: if (fetch_valid && fetch_ready) begin
                        data_model <= fetch_model;
                        data_owner <= fetch_owner;
                        data_token <= fetch_token;
                        data_selector <= fetch_is_value;
                        data_head <= fetch_kv_head;
                        data_component <= fetch_component;
                        data_tag <= incoming_tag;
                        data_response <= 0;
                        data_error <= 0;
                        pair_cancelled <= 0;
                        fetch_state <= FETCH_READ;
                    end
                    FETCH_READ: begin
                        hit_hold <= tree_hit[1];
                        if (!data_native) begin
                            data_error <= 6;
                            hit_hold <= 0;
                        end else if (data_owner >= data_owners) begin
                            data_error <= 7;
                            hit_hold <= 0;
                        end else if (data_token > 131071 ||
                            data_head >= data_heads || data_component >= data_dimension) begin
                            data_error <= 2;
                            hit_hold <= 0;
                        end
                        fetch_state <= FETCH_LOOKUP;
                    end
                    FETCH_LOOKUP: begin
                        if (invalidating) begin
                            data_error <= 7;
                            data_response <= 0;
                            fetch_state <= FETCH_RESPONSE;
                        end else if (data_error != 0)
                            fetch_state <= FETCH_RESPONSE;
                        else if (hit_hold) begin
                            data_response <= data_component[0] ?
                                payload_q[31:16] : payload_q[15:0];
                            fetch_state <= FETCH_RESPONSE;
                        end else
                            fetch_state <= FETCH_REGEN;
                    end
                    FETCH_REGEN: begin
                        if (invalidating)
                            pair_cancelled <= 1;
                        if (regen_ready)
                            fetch_state <= FETCH_WAIT;
                    end
                    FETCH_WAIT: begin
                        if (invalidating)
                            pair_cancelled <= 1;
                        if (regen_rsp_valid && regen_rsp_ready) begin
                            pair_hold <= regen_rsp_data;
                            if (invalidating || pair_cancelled)
                                pair_error <= 7;
                            else
                                pair_error <= regen_rsp_error;
                            fetch_state <= FETCH_REGISTER;
                        end
                    end
                    FETCH_REGISTER: begin
                        if (invalidating || pair_error != 0) begin
                            data_error <= invalidating ? 4'd7 : pair_error;
                            data_response <= 0;
                        end else begin
                            data_error <= 0;
                            data_response <= data_component[0] ?
                                pair_hold[31:16] : pair_hold[15:0];
                        end
                        fetch_state <= FETCH_RESPONSE;
                    end
                    FETCH_RESPONSE: if (fetch_rsp_ready)
                        fetch_state <= FETCH_IDLE;
                    default: begin
                        data_error <= 7;
                        data_response <= 0;
                        fetch_state <= FETCH_RESPONSE;
                    end
                endcase
            end
        end
    end endgenerate
endmodule
