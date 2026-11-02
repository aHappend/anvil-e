module anvil_en1_memory_arbiter #(
    parameter integer CLIENTS = 3
) (
    input wire clk, rst_n,
    input wire [(CLIENTS > 0 ? CLIENTS : 1)-1:0] client_cmd_valid,
    output wire [(CLIENTS > 0 ? CLIENTS : 1)-1:0] client_cmd_ready,
    input wire [(CLIENTS > 0 ? CLIENTS : 1)-1:0] client_cmd_write,
    input wire [64*(CLIENTS > 0 ? CLIENTS : 1)-1:0] client_cmd_addr,
    input wire [32*(CLIENTS > 0 ? CLIENTS : 1)-1:0] client_cmd_wdata,
    output wire [(CLIENTS > 0 ? CLIENTS : 1)-1:0] client_result_valid,
    input wire [(CLIENTS > 0 ? CLIENTS : 1)-1:0] client_result_ready,
    output wire [32*(CLIENTS > 0 ? CLIENTS : 1)-1:0] client_result_data,
    output wire [(CLIENTS > 0 ? CLIENTS : 1)-1:0] client_result_error,
    output wire cmd_valid,
    input wire cmd_ready,
    output wire cmd_write,
    output wire [63:0] cmd_addr,
    output wire [31:0] cmd_wdata,
    output wire [2:0] cmd_owner,
    input wire result_valid,
    output wire result_ready,
    input wire [31:0] result_data,
    input wire result_error,
    input wire drain_valid,
    output wire drain_ready,
    output wire drain_done_valid,
    input wire drain_done_ready
);
    generate if (CLIENTS < 1 || CLIENTS > 8) begin : invalid_parameters
        initial $fatal(1, "PARAMETER ERROR: CLIENTS must be 1..8");
        assign client_cmd_ready = 0;
        assign client_result_valid = 0;
        assign client_result_data = 0;
        assign client_result_error = 0;
        assign cmd_valid = 0;
        assign cmd_write = 0;
        assign cmd_addr = 0;
        assign cmd_wdata = 0;
        assign cmd_owner = 0;
        assign result_ready = 0;
        assign drain_ready = 0;
        assign drain_done_valid = 0;
    end else begin : arbiter
        localparam [2:0] IDLE = 0, SEND = 1, WAIT_RESULT = 2,
            CLIENT_RESPONSE = 3, DRAIN_RESPONSE = 4;
        reg [2:0] state, cursor, owner_hold;
        reg draining, write_hold, error_hold;
        reg [63:0] address_hold;
        reg [31:0] write_data_hold, read_data_hold;
        wire drain_accept = drain_valid && drain_ready;
        wire ingress_open = rst_n && state == IDLE && !draining && !drain_valid;
        wire [CLIENTS-1:0] cursor_mask = {{(CLIENTS-1){1'b0}}, 1'b1} << cursor;
        assign client_cmd_ready = ingress_open ? cursor_mask : {CLIENTS{1'b0}};
        assign cmd_valid = rst_n && state == SEND;
        assign cmd_write = rst_n && write_hold;
        assign cmd_addr = rst_n ? address_hold : 64'd0;
        assign cmd_wdata = rst_n ? write_data_hold : 32'd0;
        assign cmd_owner = rst_n ? owner_hold : 3'd0;
        assign result_ready = rst_n && state == WAIT_RESULT;
        assign drain_ready = rst_n && !draining && state != DRAIN_RESPONSE;
        assign drain_done_valid = rst_n && state == DRAIN_RESPONSE;
        genvar client;
        for (client = 0; client < CLIENTS; client = client + 1) begin : responses
            wire selected = rst_n && state == CLIENT_RESPONSE && owner_hold == client;
            assign client_result_valid[client] = selected;
            assign client_result_data[32*client+:32] = selected ? read_data_hold : 32'd0;
            assign client_result_error[client] = selected && error_hold;
        end

        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                state <= IDLE;
                cursor <= 0;
                owner_hold <= 0;
                draining <= 0;
                write_hold <= 0;
                error_hold <= 0;
                address_hold <= 0;
                write_data_hold <= 0;
                read_data_hold <= 0;
            end else begin
                if (drain_accept)
                    draining <= 1;
                case (state)
                    IDLE: begin
                        if (draining || drain_accept)
                            state <= DRAIN_RESPONSE;
                        else if (ingress_open && client_cmd_valid[cursor]) begin
                            owner_hold <= cursor;
                            write_hold <= client_cmd_write[cursor];
                            address_hold <= client_cmd_addr[64*cursor+:64];
                            write_data_hold <= client_cmd_wdata[32*cursor+:32];
                            read_data_hold <= 0;
                            error_hold <= 0;
                            state <= SEND;
                        end else begin
                            if (cursor == CLIENTS - 1)
                                cursor <= 0;
                            else
                                cursor <= cursor + 1'b1;
                        end
                    end
                    SEND: if (cmd_ready)
                        state <= WAIT_RESULT;
                    WAIT_RESULT: if (result_valid) begin
                        read_data_hold <= result_data;
                        error_hold <= result_error;
                        state <= CLIENT_RESPONSE;
                    end
                    CLIENT_RESPONSE: if (client_result_ready[owner_hold]) begin
                        if (owner_hold == CLIENTS - 1)
                            cursor <= 0;
                        else
                            cursor <= owner_hold + 1'b1;
                        if (draining || drain_accept)
                            state <= DRAIN_RESPONSE;
                        else
                            state <= IDLE;
                    end
                    DRAIN_RESPONSE: if (drain_done_ready) begin
                        draining <= 0;
                        state <= IDLE;
                    end
                    default: begin
                        draining <= 1;
                        state <= DRAIN_RESPONSE;
                    end
                endcase
            end
        end
    end endgenerate
endmodule
