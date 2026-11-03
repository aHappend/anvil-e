module anvil_edge_round_div (
  input wire clk, rst_n,
  input wire in_valid,
  output wire in_ready,
  input wire signed [127:0] numerator,
  input wire [63:0] divisor,
  output wire out_valid,
  input wire out_ready,
  output wire signed [127:0] value,
  output wire divide_by_zero
);
  localparam [2:0] IDLE=0, ROUND=1, DIVIDE=2, WAIT_RESULT=3, RETURN=4;
  reg [2:0] state;
  reg negative, failed;
  reg [128:0] magnitude;
  reg [63:0] denominator;
  reg signed [127:0] result;
  wire divider_ready, divider_valid, divider_error;
  wire [128:0] quotient, remainder;
  wire signed [128:0] signed_quotient=negative ? -$signed(quotient) : $signed(quotient);
  anvil_edge_unsigned_divider #(.WIDTH(129)) divider(
    .clk(clk),.rst_n(rst_n),.in_valid(state==DIVIDE),.in_ready(divider_ready),
    .numerator(magnitude),.denominator({65'd0,denominator}),
    .out_valid(divider_valid),.out_ready(state==WAIT_RESULT),
    .quotient(quotient),.remainder(remainder),.divide_by_zero(divider_error)
  );
  assign in_ready=rst_n && state==IDLE;
  assign out_valid=rst_n && state==RETURN;
  assign value=rst_n ? result : 0;
  assign divide_by_zero=rst_n && failed;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state<=IDLE; negative<=0; failed<=0; magnitude<=0; denominator<=0; result<=0;
    end else case (state)
      IDLE: if (in_valid && in_ready) begin
        negative<=numerator[127];
        magnitude<=numerator[127] ? -$signed({numerator[127],numerator}) : {1'b0,numerator};
        denominator<=divisor;
        failed<=0;
        result<=0;
        state<=ROUND;
      end
      ROUND: begin magnitude<=magnitude+({65'd0,denominator} >> 1); state<=DIVIDE; end
      DIVIDE: if (divider_ready) state<=WAIT_RESULT;
      WAIT_RESULT: if (divider_valid) begin
        result<=divider_error ? 0 : signed_quotient[127:0];
        failed<=divider_error;
        state<=RETURN;
      end
      RETURN: if (out_valid && out_ready) state<=IDLE;
      default: begin failed<=1; result<=0; state<=RETURN; end
    endcase
  end
endmodule
