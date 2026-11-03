module anvil_edge_isqrt128 (
  input wire clk, rst_n,
  input wire in_valid,
  output wire in_ready,
  input wire [127:0] radicand,
  output wire out_valid,
  input wire out_ready,
  output wire [63:0] root
);
  localparam [1:0] IDLE=0, ITERATE=1, PUBLISH=2, HOLD=3;
  reg [1:0] state;
  reg [127:0] radicand_shift;
  reg [129:0] remainder_work;
  reg [63:0] root_work, root_result;
  reg [5:0] iteration;
  wire [129:0] shifted_remainder =
    (remainder_work << 2) | {128'd0, radicand_shift[127:126]};
  wire [129:0] trial = {64'd0, root_work, 2'b01};
  wire subtract = shifted_remainder >= trial;
  assign in_ready = rst_n && state == IDLE;
  assign out_valid = rst_n && state == HOLD;
  assign root = rst_n ? root_result : 0;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= IDLE;
      radicand_shift <= 0;
      remainder_work <= 0;
      root_work <= 0;
      root_result <= 0;
      iteration <= 0;
    end else case (state)
      IDLE: if (in_valid && in_ready) begin
        radicand_shift <= radicand;
        remainder_work <= 0;
        root_work <= 0;
        iteration <= 0;
        state <= ITERATE;
      end
      ITERATE: begin
        radicand_shift <= radicand_shift << 2;
        if (subtract) begin
          remainder_work <= shifted_remainder-trial;
          root_work <= (root_work << 1) | 1'b1;
        end else begin
          remainder_work <= shifted_remainder;
          root_work <= root_work << 1;
        end
        if (iteration == 63) state <= PUBLISH;
        else iteration <= iteration+1'b1;
      end
      PUBLISH: begin
        root_result <= root_work;
        state <= HOLD;
      end
      HOLD: if (out_valid && out_ready) state <= IDLE;
      default: state <= IDLE;
    endcase
  end
endmodule
