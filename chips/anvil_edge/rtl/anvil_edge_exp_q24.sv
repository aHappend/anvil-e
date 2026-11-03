module anvil_edge_exp_q24 (
  input wire clk, rst_n,
  input wire in_valid,
  output wire in_ready,
  input wire signed [63:0] x,
  output wire out_valid,
  input wire out_ready,
  output wire [31:0] value,
  output wire arithmetic_error
);
  localparam [3:0] IDLE=0, REDUCE=1, REDUCE_WAIT=2, MULTIPLY=3,
    MULTIPLY_WAIT=4, TERM_DIVIDE=5, TERM_WAIT=6, RESULT=7, RETURN=8;
  reg [3:0] state;
  reg [63:0] reduced_input, exponent, remainder_value, division_magnitude;
  reg signed [63:0] term, total;
  reg [2:0] order;
  reg term_negative;
  reg [31:0] result;
  reg failed;
  wire divider_ready, divider_valid, divide_by_zero;
  wire [63:0] quotient, remainder;
  wire multiplier_ready, multiplier_valid;
  wire signed [127:0] product;
  wire signed [63:0] low_product=product[63:0];
  wire signed [63:0] signed_quotient=term_negative ?
    -$signed(quotient) : $signed(quotient);
  wire [63:0] divisor=state==REDUCE ? 64'd11629080 : {37'd0,order,24'd0};
  wire [63:0] numerator=state==REDUCE ? reduced_input : division_magnitude;

  anvil_edge_unsigned_divider #(.WIDTH(64)) divider(
    .clk(clk),.rst_n(rst_n),.in_valid(state==REDUCE || state==TERM_DIVIDE),
    .in_ready(divider_ready),.numerator(numerator),.denominator(divisor),
    .out_valid(divider_valid),.out_ready(state==REDUCE_WAIT || state==TERM_WAIT),
    .quotient(quotient),.remainder(remainder),.divide_by_zero(divide_by_zero)
  );
  anvil_edge_signed_multiplier #(.WIDTH(64)) multiplier(
    .clk(clk),.rst_n(rst_n),.in_valid(state==MULTIPLY),.in_ready(multiplier_ready),
    .operand_a(-term),.operand_b($signed(remainder_value)),
    .out_valid(multiplier_valid),.out_ready(state==MULTIPLY_WAIT),.product(product)
  );
  assign in_ready=rst_n && state==IDLE;
  assign out_valid=rst_n && state==RETURN;
  assign value=rst_n ? result : 0;
  assign arithmetic_error=rst_n && failed;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state<=IDLE; reduced_input<=0; exponent<=0; remainder_value<=0;
      division_magnitude<=0; term<=0; total<=0; order<=0;
      term_negative<=0; result<=0; failed<=0;
    end else case (state)
      IDLE: if (in_valid && in_ready) begin
        failed<=0;
        result<=0;
        if (x< -64'sd1048576) state<=RETURN;
        else if (x>=0) begin result<=32'd16777216; state<=RETURN; end
        else begin
          reduced_input<=(-x) << 8;
          state<=REDUCE;
        end
      end
      REDUCE: if (divider_ready) state<=REDUCE_WAIT;
      REDUCE_WAIT: if (divider_valid) begin
        if (divide_by_zero) begin failed<=1; state<=RETURN; end
        else begin
          exponent<=quotient;
          remainder_value<=remainder;
          term<=64'sd16777216;
          total<=64'sd16777216;
          order<=1;
          state<=MULTIPLY;
        end
      end
      MULTIPLY: if (multiplier_ready) state<=MULTIPLY_WAIT;
      MULTIPLY_WAIT: if (multiplier_valid) begin
        term_negative<=low_product[63];
        division_magnitude<=low_product[63] ? -low_product : low_product;
        state<=TERM_DIVIDE;
      end
      TERM_DIVIDE: if (divider_ready) state<=TERM_WAIT;
      TERM_WAIT: if (divider_valid) begin
        if (divide_by_zero) begin failed<=1; state<=RETURN; end
        else begin
          term<=signed_quotient;
          total<=total+signed_quotient;
          if (order==6) state<=RESULT;
          else begin order<=order+1'b1; state<=MULTIPLY; end
        end
      end
      RESULT: begin
        result<=total<0 ? 0 : total >> exponent;
        state<=RETURN;
      end
      RETURN: if (out_valid && out_ready) state<=IDLE;
      default: begin failed<=1; result<=0; state<=RETURN; end
    endcase
  end
endmodule
