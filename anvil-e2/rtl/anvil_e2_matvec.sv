module anvil_e2_matvec #(
    parameter integer MAX_INPUT=2048
) (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [31:0] start_rows, start_cols,
    input wire [63:0] start_weights,
    input wire in_valid,
    output wire in_ready,
    input wire signed [47:0] in_data,
    output wire cmd_valid,
    input wire cmd_ready,
    output wire [63:0] cmd_addr,
    input wire result_valid,
    output wire result_ready,
    input wire signed [31:0] result_data,
    input wire result_error,
    output wire mac_clear, mac_accumulate,
    output wire signed [47:0] mac_a, mac_b,
    input wire signed [47:0] mac_rounded,
    output wire out_valid,
    input wire out_ready,
    output wire signed [47:0] out_data,
    output wire [31:0] out_index,
    output wire out_last,
    output wire done_valid,
    input wire done_ready,
    output wire [3:0] done_error
);
    localparam IDLE=0, LOAD=1, REQUEST=2, RESPONSE=3,
        PRODUCT=4, PREPARE=5, OUTPUT=6, DONE=7;
    reg [2:0] state;
    reg [31:0] rows, cols, row, col;
    reg [63:0] base;
    reg signed [47:0] inputs [0:MAX_INPUT-1];
    reg signed [31:0] weight_hold;
    reg signed [47:0] result_hold;
    reg [3:0] error_hold;
    wire [127:0] byte_size={96'd0,start_rows}*{96'd0,start_cols}*128'd4;
    initial begin
        if (MAX_INPUT<=0 || MAX_INPUT>65535)
            $fatal(1,"PARAMETER ERROR: matvec MAX_INPUT must be 1..65535");
    end
    assign start_ready=rst_n && state==IDLE;
    assign in_ready=rst_n && state==LOAD;
    assign cmd_valid=rst_n && state==REQUEST;
    assign cmd_addr=rst_n ? base+(64'(row)*cols+col)*64'd4:64'd0;
    assign result_ready=rst_n && state==RESPONSE;
    assign mac_clear=rst_n && state==PRODUCT && col==0;
    assign mac_accumulate=rst_n && state==PRODUCT;
    assign mac_a=rst_n && state==PRODUCT ? inputs[col]:48'sd0;
    assign mac_b=rst_n ? {weight_hold,16'd0}:48'sd0;
    assign out_valid=rst_n && state==OUTPUT;
    assign out_data=rst_n ? result_hold:48'sd0;
    assign out_index=rst_n ? row:32'd0;
    assign out_last=rst_n && row==rows-1;
    assign done_valid=rst_n && state==DONE;
    assign done_error=rst_n ? error_hold:4'd0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=IDLE; rows<=0; cols<=0; row<=0; col<=0; base<=0;
            weight_hold<=0; result_hold<=0; error_hold<=0;
        end else begin
            case (state)
                IDLE: if (start_valid) begin
                    rows<=start_rows; cols<=start_cols; base<=start_weights;
                    row<=0; col<=0; error_hold<=0;
                    if (start_rows==0 || start_cols==0 || start_cols>MAX_INPUT ||
                        |start_weights[1:0]) begin
                        error_hold<=1; state<=DONE;
                    end else if ({64'd0,start_weights}+byte_size>128'hffffffffffffffff) begin
                        error_hold<=5; state<=DONE;
                    end else state<=LOAD;
                end
                LOAD: if (in_valid) begin
                    inputs[col]<=in_data;
                    if (col==cols-1) begin col<=0; state<=REQUEST; end
                    else col<=col+1'b1;
                end
                REQUEST: if (cmd_ready) state<=RESPONSE;
                RESPONSE: if (result_valid) begin
                    if (result_error) begin error_hold<=3; state<=DONE; end
                    else begin weight_hold<=result_data; state<=PRODUCT; end
                end
                PRODUCT: begin
                    if (col==cols-1) state<=PREPARE;
                    else begin col<=col+1'b1; state<=REQUEST; end
                end
                PREPARE: begin result_hold<=mac_rounded; state<=OUTPUT; end
                OUTPUT: if (out_ready) begin
                    if (row==rows-1) state<=DONE;
                    else begin row<=row+1'b1; col<=0; state<=REQUEST; end
                end
                DONE: if (done_ready) state<=IDLE;
                default: begin error_hold<=1; state<=DONE; end
            endcase
        end
    end
endmodule
