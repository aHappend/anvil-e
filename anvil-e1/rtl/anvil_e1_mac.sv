module anvil_e1_mac (
    input wire clk,
    input wire rst_n,
    input wire clear,
    input wire accumulate,
    input wire signed [31:0] a,
    input wire signed [31:0] b,
    output reg signed [95:0] sum,
    output wire signed [31:0] rounded
);
    wire signed [63:0] product = a * b;
    reg signed [95:0] quotient;
    reg [23:0] remainder;
    reg signed [95:0] nearest;
    always @* begin
        quotient = sum >>> 24;
        remainder = sum[23:0];
        nearest = quotient;
        if ((remainder > 24'h800000) ||
            ((remainder == 24'h800000) && quotient[0]))
            nearest = quotient + 96'sd1;
    end
    assign rounded = !rst_n ? 32'sd0 :
                     nearest > 96'sd2147483647 ? 32'sh7fffffff :
                     nearest < -96'sd2147483648 ? 32'sh80000000 : nearest[31:0];
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            sum <= 96'sd0;
        else if (clear)
            sum <= accumulate ? {{32{product[63]}}, product} : 96'sd0;
        else if (accumulate)
            sum <= sum + {{32{product[63]}}, product};
    end
endmodule
