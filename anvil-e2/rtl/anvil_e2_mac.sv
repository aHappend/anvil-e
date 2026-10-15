module anvil_e2_mac (
    input wire clk,
    input wire rst_n,
    input wire clear,
    input wire accumulate,
    input wire signed [47:0] a,
    input wire signed [47:0] b,
    output reg signed [127:0] sum,
    output wire signed [47:0] rounded,
    output wire signed [95:0] product
);
    function automatic signed [47:0] round_sum;
        input signed [127:0] value;
        reg signed [127:0] nearest;
        begin
            nearest = value >>> 40;
            if ((value[39:0] > 40'h8000000000) ||
                ((value[39:0] == 40'h8000000000) && nearest[0]))
                nearest = nearest + 128'sd1;
            if (nearest > 128'sd140737488289792) round_sum = 48'sh7fffffff0000;
            else if (nearest < -128'sd140737488355328) round_sum = 48'sh800000000000;
            else round_sum = nearest[47:0];
        end
    endfunction
    assign product = rst_n && accumulate ? a * b : 96'sd0;
    assign rounded = !rst_n ? 48'sd0 : round_sum(sum);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sum <= 128'sd0;
        end else if (accumulate) begin
            if (clear) sum <= {{32{product[95]}}, product};
            else sum <= sum + {{32{product[95]}}, product};
        end else if (clear) sum <= 128'sd0;
    end
endmodule
