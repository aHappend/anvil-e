module anvil_edge_silu_q16 (
  input wire clk, rst_n,
  input wire in_valid,
  output wire in_ready,
  input wire signed [31:0] x,
  output wire out_valid,
  input wire out_ready,
  output wire signed [31:0] value,
  output wire arithmetic_error
);
  localparam [3:0] IDLE=0, EXP=1, EXP_WAIT=2, DIVIDE=3, DIVIDE_WAIT=4,
    MULTIPLY=5, MULTIPLY_WAIT=6, ROUND=7, RETURN=8;
  reg [3:0] state;
  reg signed [31:0] operand, result;
  reg [63:0] magnitude, numerator, denominator, sigmoid;
  reg signed [64:0] truncated_product;
  reg failed;
  wire exp_ready, exp_valid, exp_error;
  wire [31:0] exponential;
  wire divider_ready, divider_valid, divide_by_zero;
  wire [63:0] quotient, remainder;
  wire multiplier_ready, multiplier_valid;
  wire signed [127:0] product;
  anvil_edge_exp_q24 exp_unit(
    .clk(clk),.rst_n(rst_n),.in_valid(state==EXP),.in_ready(exp_ready),
    .x(-$signed(magnitude)),.out_valid(exp_valid),.out_ready(state==EXP_WAIT),
    .value(exponential),.arithmetic_error(exp_error)
  );
  anvil_edge_unsigned_divider #(.WIDTH(64)) divider(
    .clk(clk),.rst_n(rst_n),.in_valid(state==DIVIDE),.in_ready(divider_ready),
    .numerator(numerator),.denominator(denominator),.out_valid(divider_valid),
    .out_ready(state==DIVIDE_WAIT),.quotient(quotient),.remainder(remainder),
    .divide_by_zero(divide_by_zero)
  );
  anvil_edge_signed_multiplier #(.WIDTH(64)) multiplier(
    .clk(clk),.rst_n(rst_n),.in_valid(state==MULTIPLY),.in_ready(multiplier_ready),
    .operand_a($signed({{32{operand[31]}},operand})),.operand_b($signed(sigmoid)),
    .out_valid(multiplier_valid),.out_ready(state==MULTIPLY_WAIT),.product(product)
  );
  assign in_ready=rst_n && state==IDLE;
  assign out_valid=rst_n && state==RETURN;
  assign value=rst_n ? result : 0;
  assign arithmetic_error=rst_n && failed;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state<=IDLE; operand<=0; result<=0; magnitude<=0; numerator<=0;
      denominator<=0; sigmoid<=0; truncated_product<=0; failed<=0;
    end else case (state)
      IDLE: if (in_valid && in_ready) begin
        operand<=x;
        magnitude<=x<0 ? -$signed({{32{x[31]}},x}) : {32'd0,x};
        result<=0;
        failed<=0;
        state<=EXP;
      end
      EXP: if (exp_ready) state<=EXP_WAIT;
      EXP_WAIT: if (exp_valid) begin
        if (exp_error) begin failed<=1; state<=RETURN; end
        else begin
          numerator<=operand>=0 ? 64'd281474976710656 : {8'd0,exponential,24'd0};
          denominator<=64'd16777216+{32'd0,exponential};
          state<=DIVIDE;
        end
      end
      DIVIDE: if (divider_ready) state<=DIVIDE_WAIT;
      DIVIDE_WAIT: if (divider_valid) begin
        if (divide_by_zero) begin failed<=1; state<=RETURN; end
        else begin sigmoid<=quotient; state<=MULTIPLY; end
      end
      MULTIPLY: if (multiplier_ready) state<=MULTIPLY_WAIT;
      MULTIPLY_WAIT: if (multiplier_valid) begin
        truncated_product<=product[64:0];
        state<=ROUND;
      end
      ROUND: begin
        result<=anvil_edge_numeric_pkg::sat32(anvil_edge_numeric_pkg::round_shift(
          {{63{truncated_product[64]}},truncated_product},24));
        state<=RETURN;
      end
      RETURN: if (out_valid && out_ready) state<=IDLE;
      default: begin failed<=1; result<=0; state<=RETURN; end
    endcase
  end
endmodule
