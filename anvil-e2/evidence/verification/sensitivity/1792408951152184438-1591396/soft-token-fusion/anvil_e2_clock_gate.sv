module anvil_e2_clock_gate (
    input wire clk, rst_n,
    input wire enable,
    output reg active,
    output wire gated_clk
);
    // Hold disabled clocks high; the enable changes only during the high phase.
    assign gated_clk = clk | !active;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) active <= 1'b0;
        else active <= enable;
    end
endmodule
