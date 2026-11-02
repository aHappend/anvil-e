module anvil_en1_frontier_schedule #(
    parameter integer COMPACT = 0
) (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] model, precision,
    input wire [31:0] generation, tokens,
    input wire force_fallback,
    output wire task_valid,
    input wire task_ready,
    output wire [2:0] task_op,
    output wire [1:0] task_model, task_precision,
    output wire [31:0] task_generation, task_tokens, task_token,
    output wire [7:0] task_layer,
    output wire task_source_frontier,
    input wire task_done_valid,
    output wire task_done_ready,
    input wire [3:0] task_done_error,
    output wire done_valid,
    input wire done_ready,
    output wire [3:0] done_error,
    output wire fallback_active,
    output wire [31:0] padded_tokens,
    output wire [63:0] required_frontier_bytes,
    output wire busy
);
    generate if (COMPACT != 0 && COMPACT != 1) begin : invalid_parameters
        initial $fatal(1, "PARAMETER ERROR: COMPACT must be 0 or 1");
        assign start_ready = 0;
        assign task_valid = 0;
        assign task_op = 0;
        assign task_model = 0;
        assign task_precision = 0;
        assign task_generation = 0;
        assign task_tokens = 0;
        assign task_token = 0;
        assign task_layer = 0;
        assign task_source_frontier = 0;
        assign task_done_ready = 0;
        assign done_valid = 0;
        assign done_error = 0;
        assign fallback_active = 0;
        assign padded_tokens = 0;
        assign required_frontier_bytes = 0;
        assign busy = 0;
    end else begin : schedule
        localparam [2:0] IDLE = 0, VALIDATE = 1, SELECT_MODE = 2,
            TASK_SEND = 3, TASK_WAIT = 4, ADVANCE = 5,
            PUBLISH = 6, RESPONSE = 7;
        localparam [2:0] CONFIGURE = 0, INPUT = 1, LOCAL_ANCHOR = 2,
            PREFIX = 3, FREEZE = 4, LAST_LAYER = 5, OUTPUT = 6, FALLBACK = 7;
        localparam [31:0] WINDOW = COMPACT ? 32'd4 : 32'd512;
        localparam [63:0] CAPACITY = COMPACT ? 64'd8192 : 64'd3145728;
        reg [2:0] state, operation;
        reg [1:0] model_hold, precision_hold;
        reg [31:0] generation_hold, tokens_hold, token_hold, padded_hold;
        reg [7:0] layer_hold, layer_count, owner_count;
        reg forced_hold, fallback_hold;
        reg [3:0] error_hold;

        wire native_model;
        wire [7:0] selected_layers, selected_owners;
        anvil_en1_geometry geometry (
            .rst_n(rst_n), .model(model_hold), .layer(8'd0),
            .is_native(native_model), .layers(selected_layers), .owners(selected_owners),
            .owner(), .is_global(), .hidden(), .intermediate()
        );
        wire [63:0] frontier_bytes = COMPACT ? {32'd0, padded_hold} << 4 :
            (model_hold == 1 ?
                ({32'd0, padded_hold} << 11) + ({32'd0, padded_hold} << 10) :
                ({32'd0, padded_hold} << 12) + ({32'd0, padded_hold} << 10));
        wire [31:0] ring_first = tokens_hold > WINDOW ? tokens_hold - WINDOW : 32'd0;

        assign start_ready = rst_n && state == IDLE;
        assign task_valid = rst_n && state == TASK_SEND;
        assign task_op = rst_n ? operation : 3'd0;
        assign task_model = rst_n ? model_hold : 2'd0;
        assign task_precision = rst_n ? precision_hold : 2'd0;
        assign task_generation = rst_n ? generation_hold : 32'd0;
        assign task_tokens = rst_n ? tokens_hold : 32'd0;
        assign task_token = rst_n ? token_hold : 32'd0;
        assign task_layer = rst_n ? layer_hold : 8'd0;
        assign task_source_frontier = rst_n &&
            (operation == LOCAL_ANCHOR || operation == PREFIX ||
                (operation == LAST_LAYER && layer_hold == owner_count - 8'd1));
        assign task_done_ready = rst_n && state == TASK_WAIT;
        assign done_valid = rst_n && state == RESPONSE;
        assign done_error = rst_n ? error_hold : 4'd0;
        assign fallback_active = rst_n && fallback_hold;
        assign padded_tokens = rst_n ? padded_hold : 32'd0;
        assign required_frontier_bytes = rst_n ? frontier_bytes : 64'd0;
        assign busy = rst_n && state != IDLE;

        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                state <= IDLE;
                operation <= 0;
                model_hold <= 0;
                precision_hold <= 0;
                generation_hold <= 0;
                tokens_hold <= 0;
                token_hold <= 0;
                padded_hold <= 0;
                layer_hold <= 0;
                layer_count <= 0;
                owner_count <= 0;
                forced_hold <= 0;
                fallback_hold <= 0;
                error_hold <= 0;
            end else begin
                case (state)
                    IDLE: if (start_valid && start_ready) begin
                        model_hold <= model;
                        precision_hold <= precision;
                        generation_hold <= generation;
                        tokens_hold <= tokens;
                        forced_hold <= force_fallback;
                        fallback_hold <= 0;
                        padded_hold <= 0;
                        token_hold <= 0;
                        layer_hold <= 0;
                        error_hold <= 0;
                        state <= VALIDATE;
                    end
                    VALIDATE: begin
                        if (!native_model || precision_hold > 1) begin
                            error_hold <= 6;
                            state <= PUBLISH;
                        end else if (tokens_hold == 0 || tokens_hold > 131072) begin
                            error_hold <= 5;
                            state <= PUBLISH;
                        end else begin
                            padded_hold <= (tokens_hold + 32'd15) & 32'hfffffff0;
                            layer_count <= selected_layers;
                            owner_count <= selected_owners;
                            state <= SELECT_MODE;
                        end
                    end
                    SELECT_MODE: begin
                        if (forced_hold || frontier_bytes > CAPACITY) begin
                            fallback_hold <= 1;
                            operation <= FALLBACK;
                            layer_hold <= layer_count;
                            token_hold <= tokens_hold - 1'b1;
                        end else begin
                            operation <= CONFIGURE;
                            layer_hold <= 0;
                            token_hold <= 0;
                        end
                        state <= TASK_SEND;
                    end
                    TASK_SEND: if (task_ready)
                        state <= TASK_WAIT;
                    TASK_WAIT: if (task_done_valid && task_done_ready) begin
                        error_hold <= task_done_error;
                        state <= ADVANCE;
                    end
                    ADVANCE: begin
                        if (error_hold != 0)
                            state <= PUBLISH;
                        else begin
                            state <= TASK_SEND;
                            case (operation)
                                CONFIGURE: begin
                                    operation <= INPUT;
                                    layer_hold <= 0;
                                    token_hold <= 0;
                                end
                                INPUT: begin
                                    if (token_hold == tokens_hold - 1'b1) begin
                                        operation <= PREFIX;
                                        layer_hold <= 0;
                                        token_hold <= tokens_hold - 1'b1;
                                    end else
                                        token_hold <= token_hold + 1'b1;
                                end
                                LOCAL_ANCHOR: begin
                                    if (token_hold == tokens_hold - 1'b1) begin
                                        operation <= PREFIX;
                                        token_hold <= tokens_hold - 1'b1;
                                    end else
                                        token_hold <= token_hold + 1'b1;
                                end
                                PREFIX: begin
                                    if (token_hold != 0)
                                        token_hold <= token_hold - 1'b1;
                                    else if (layer_hold == owner_count - 8'd2) begin
                                        operation <= FREEZE;
                                        layer_hold <= owner_count - 8'd1;
                                        token_hold <= tokens_hold - 1'b1;
                                    end else begin
                                        layer_hold <= layer_hold + 1'b1;
                                        if (layer_hold + 8'd1 == owner_count - 8'd2) begin
                                            operation <= LOCAL_ANCHOR;
                                            token_hold <= ring_first;
                                        end else
                                            token_hold <= tokens_hold - 1'b1;
                                    end
                                end
                                FREEZE: begin
                                    operation <= LAST_LAYER;
                                    layer_hold <= owner_count - 8'd1;
                                    token_hold <= tokens_hold - 1'b1;
                                end
                                LAST_LAYER: begin
                                    if (layer_hold == layer_count - 8'd1)
                                        operation <= OUTPUT;
                                    else
                                        layer_hold <= layer_hold + 1'b1;
                                end
                                FALLBACK: operation <= OUTPUT;
                                OUTPUT: state <= PUBLISH;
                                default: begin
                                    error_hold <= 7;
                                    state <= PUBLISH;
                                end
                            endcase
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
