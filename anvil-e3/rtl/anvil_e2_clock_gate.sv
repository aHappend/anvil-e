module anvil_e2_clock_gate (
    input wire clk, rst_n,
    input wire enable,
    output reg active,
    output wire gated_clk
);
    // Keep one clock domain; active is a registered launch qualifier, not a clock gate.
    assign gated_clk = clk;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) active <= 1'b0;
        else active <= enable;
    end
endmodule
