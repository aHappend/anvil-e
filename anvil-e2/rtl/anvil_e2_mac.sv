module anvil_e2_mac (
    input wire clk,
    input wire rst_n,
    input wire clear,
    input wire accumulate,
    input wire signed [47:0] a,
    input wire signed [47:0] b,
    output reg signed [127:0] sum,
    output wire signed [47:0] rounded
);
    wire signed [95:0] product = a * b;
    reg signed [127:0] quotient;
    reg [39:0] remainder;
    reg signed [127:0] nearest;
    always @* begin
        quotient = sum >>> 40;
        remainder = sum[39:0];
        nearest = quotient;
        if ((remainder > 40'h8000000000) ||
            ((remainder == 40'h8000000000) && quotient[0]))
            nearest = quotient + 128'sd1;
    end
    assign rounded = !rst_n ? 48'sd0 :
                     nearest > 128'sd140737488289792 ? 48'sh7fffffff0000 :
                     nearest < -128'sd140737488355328 ? 48'sh800000000000 : nearest[47:0];
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            sum <= 128'sd0;
        else if (clear)
            sum <= accumulate ? {{32{product[95]}}, product} : 128'sd0;
        else if (accumulate)
            sum <= sum + {{32{product[95]}}, product};
    end
endmodule
