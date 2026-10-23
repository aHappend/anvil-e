module anvil_e2_divide (
    input wire clk, rst_n,
    input wire in_valid,
    output wire in_ready,
    input wire signed [127:0] in_numerator,
    input wire [127:0] in_denominator,
    output wire out_valid,
    input wire out_ready,
    output wire signed [127:0] out_data,
    output wire out_error
);
    localparam IDLE=0, START=1, WAIT=2, ROUND=3, HOLD=4;
    reg [2:0] state;
    reg negative, error;
    reg [127:0] magnitude, divisor, quotient, residue;
    reg signed [127:0] result;
    wire ready, valid, divide_error;
    wire [127:0] q, r;
    wire round_up=({r,1'b0}>{1'b0,divisor}) ||
        (({r,1'b0}=={1'b0,divisor}) && q[0]);
    reg [128:0] rounded;
    anvil_e3_unsigned_divide #(.WIDTH(128)) unsigned_divider (
        .clk(clk), .rst_n(rst_n), .in_valid(state==START), .in_ready(ready),
        .in_numerator(magnitude), .in_denominator(divisor),
        .out_valid(valid), .out_ready(state==WAIT),
        .out_quotient(q), .out_remainder(r), .out_error(divide_error)
    );
    assign in_ready=rst_n && state==IDLE;
    assign out_valid=rst_n && state==HOLD;
    assign out_data=rst_n ? result:128'sd0;
    assign out_error=rst_n && error;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=IDLE; negative<=0; error<=0; magnitude<=0;
            divisor<=0; quotient<=0; residue<=0; rounded<=0; result<=0;
        end else case (state)
            IDLE: if (in_valid) begin
                negative<=in_numerator[127];
                magnitude<=in_numerator[127] ? -$unsigned(in_numerator):
                    $unsigned(in_numerator);
                divisor<=in_denominator; error<=0; rounded<=0; result<=0; state<=START;
            end
            START: if (ready) state<=WAIT;
            WAIT: if (valid) begin
                if (divide_error) begin error<=1; state<=HOLD; end
                else begin
                    quotient<=q; residue<=r;
                    rounded<={1'b0,q}+129'(round_up);
                    state<=ROUND;
                end
            end
            ROUND: begin
                if (rounded[128] || (!negative && rounded[127]) ||
                    (negative && rounded>{2'b01,127'd0})) begin
                    error<=1; result<=0;
                end else result<=negative ? -$signed(rounded[127:0]):
                    $signed(rounded[127:0]);
                state<=HOLD;
            end
            HOLD: if (out_ready) state<=IDLE;
            default: begin error<=1; result<=0; state<=HOLD; end
        endcase
    end
endmodule
