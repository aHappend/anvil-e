module anvil_e1_memory (
    input wire clk,
    input wire rst_n,
    input wire cmd_valid,
    output wire cmd_ready,
    input wire cmd_write,
    input wire [63:0] cmd_addr,
    input wire [31:0] cmd_wdata,
    output wire result_valid,
    input wire result_ready,
    output wire [31:0] result_data,
    output wire result_error,
    output wire mem_req_valid,
    input wire mem_req_ready,
    output wire mem_req_write,
    output wire [63:0] mem_req_addr,
    output wire [31:0] mem_req_wdata,
    input wire mem_rsp_valid,
    output wire mem_rsp_ready,
    input wire [31:0] mem_rsp_rdata,
    input wire mem_rsp_error
);
    localparam IDLE=2'd0, REQUEST=2'd1, RESPONSE=2'd2, RESULT=2'd3;
    reg [1:0] state;
    reg write_hold;
    reg [63:0] addr_hold;
    reg [31:0] data_hold, response_hold;
    reg error_hold;
    assign cmd_ready = rst_n && state == IDLE;
    assign mem_req_valid = rst_n && state == REQUEST;
    assign mem_req_write = rst_n ? write_hold : 1'b0;
    assign mem_req_addr = rst_n ? addr_hold : 64'd0;
    assign mem_req_wdata = rst_n ? data_hold : 32'd0;
    assign mem_rsp_ready = rst_n && state == RESPONSE;
    assign result_valid = rst_n && state == RESULT;
    assign result_data = rst_n ? response_hold : 32'd0;
    assign result_error = rst_n && error_hold;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            write_hold <= 1'b0;
            addr_hold <= 64'd0;
            data_hold <= 32'd0;
            response_hold <= 32'd0;
            error_hold <= 1'b0;
        end else begin
            case (state)
                IDLE: if (cmd_valid) begin
                    write_hold <= cmd_write;
                    addr_hold <= cmd_addr;
                    data_hold <= cmd_wdata;
                    state <= REQUEST;
                end
                REQUEST: if (mem_req_ready) state <= RESPONSE;
                RESPONSE: if (mem_rsp_valid) begin
                    response_hold <= mem_rsp_rdata;
                    error_hold <= mem_rsp_error;
                    state <= RESULT;
                end
                RESULT: if (result_ready) state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end
endmodule
