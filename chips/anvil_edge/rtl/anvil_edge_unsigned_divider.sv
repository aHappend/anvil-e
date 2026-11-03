module anvil_edge_unsigned_divider #(
  parameter integer WIDTH = 128
) (
  input wire clk, rst_n,
  input wire in_valid,
  output wire in_ready,
  input wire [(WIDTH > 0 ? WIDTH : 1)-1:0] numerator, denominator,
  output wire out_valid,
  input wire out_ready,
  output wire [(WIDTH > 0 ? WIDTH : 1)-1:0] quotient, remainder,
  output wire divide_by_zero
);
  generate
    if (WIDTH < 1) begin : invalid_parameters
      initial $fatal(1, "ANVIL_EDGE_DIVIDER PARAMETER ERROR: WIDTH must be positive");
      assign in_ready = 0;
      assign out_valid = 0;
      assign quotient = 0;
      assign remainder = 0;
      assign divide_by_zero = 0;
    end else begin : divider
      localparam [1:0] IDLE=0, ITERATE=1, PUBLISH=2, HOLD=3;
      localparam integer COUNT_W = WIDTH > 1 ? $clog2(WIDTH+1) : 1;
      reg [1:0] state;
      reg [WIDTH-1:0] dividend_shift, divisor, quotient_work;
      reg [WIDTH:0] remainder_work;
      reg [WIDTH-1:0] quotient_result, remainder_result;
      reg [COUNT_W-1:0] iterations;
      reg zero_divisor;
      wire [WIDTH:0] shifted_remainder =
        (remainder_work << 1) | {{WIDTH{1'b0}}, dividend_shift[WIDTH-1]};
      wire subtract = shifted_remainder >= {1'b0, divisor};
      assign in_ready = rst_n && state == IDLE;
      assign out_valid = rst_n && state == HOLD;
      assign quotient = rst_n ? quotient_result : 0;
      assign remainder = rst_n ? remainder_result : 0;
      assign divide_by_zero = rst_n && state == HOLD && zero_divisor;

      always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
          state <= IDLE;
          dividend_shift <= 0;
          divisor <= 0;
          quotient_work <= 0;
          remainder_work <= 0;
          quotient_result <= 0;
          remainder_result <= 0;
          iterations <= 0;
          zero_divisor <= 0;
        end else case (state)
          IDLE: if (in_valid && in_ready) begin
            dividend_shift <= numerator;
            divisor <= denominator;
            quotient_work <= 0;
            remainder_work <= 0;
            iterations <= 0;
            zero_divisor <= denominator == 0;
            state <= ITERATE;
          end
          ITERATE: begin
            dividend_shift <= dividend_shift << 1;
            if (subtract) begin
              remainder_work <= shifted_remainder - {1'b0, divisor};
              quotient_work <= (quotient_work << 1) | 1'b1;
            end else begin
              remainder_work <= shifted_remainder;
              quotient_work <= quotient_work << 1;
            end
            if (iterations == WIDTH-1) state <= PUBLISH;
            else iterations <= iterations + 1'b1;
          end
          PUBLISH: begin
            quotient_result <= zero_divisor ? 0 : quotient_work;
            remainder_result <= zero_divisor ? 0 : remainder_work[WIDTH-1:0];
            state <= HOLD;
          end
          HOLD: if (out_valid && out_ready) state <= IDLE;
          default: state <= IDLE;
        endcase
      end
    end
  endgenerate
endmodule
