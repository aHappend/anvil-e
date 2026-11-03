module anvil_edge_signed_multiplier #(
  parameter integer WIDTH = 128
) (
  input wire clk, rst_n,
  input wire in_valid,
  output wire in_ready,
  input wire signed [(WIDTH > 0 ? WIDTH : 1)-1:0] operand_a, operand_b,
  output wire out_valid,
  input wire out_ready,
  output wire signed [(WIDTH > 0 ? 2*WIDTH : 2)-1:0] product
);
  generate
    if (WIDTH < 1) begin : invalid_parameters
      initial $fatal(1, "ANVIL_EDGE_MULTIPLIER PARAMETER ERROR: WIDTH must be positive");
      assign in_ready = 0;
      assign out_valid = 0;
      assign product = 0;
    end else begin : multiplier
      localparam integer LIMBS = (WIDTH+15) >> 4;
      localparam integer PAIRS = LIMBS*LIMBS;
      localparam integer LEVELS = $clog2(PAIRS);
      localparam integer LEAVES = 1 << LEVELS;
      localparam integer RESULT_W = WIDTH*2;
      reg [WIDTH-1:0] magnitude_a, magnitude_b;
      reg negative, busy, valid_result;
      reg [LEVELS+1:0] valid_pipe;
      reg signed [RESULT_W-1:0] result;
      wire [LIMBS*16-1:0] padded_a = magnitude_a;
      wire [LIMBS*16-1:0] padded_b = magnitude_b;
      wire [RESULT_W-1:0] tree [0:LEVELS][0:LEAVES-1];
      assign in_ready = rst_n && !busy;
      assign out_valid = rst_n && valid_result;
      assign product = rst_n ? result : 0;

      for (genvar a=0; a<LIMBS; a=a+1) begin : a_limb
        for (genvar b=0; b<LIMBS; b=b+1) begin : b_limb
          localparam integer INDEX = a*LIMBS+b;
          wire [31:0] partial_product =
            padded_a[a*16+:16] * padded_b[b*16+:16];
          reg [RESULT_W-1:0] partial_registered;
          assign tree[0][INDEX] = partial_registered;
          always @(posedge clk or negedge rst_n) begin
            if (!rst_n) partial_registered <= 0;
            else if (busy)
              partial_registered <=
                {{(RESULT_W > 32 ? RESULT_W-32 : 0){1'b0}}, partial_product}
                << ((a+b)*16);
          end
        end
      end
      for (genvar pad=PAIRS; pad<LEAVES; pad=pad+1) begin : padding
        assign tree[0][pad] = 0;
      end
      for (genvar level=1; level<=LEVELS; level=level+1) begin : adder_level
        for (genvar node=0; node<(LEAVES >> level); node=node+1) begin : adder
          reg [RESULT_W-1:0] sum;
          assign tree[level][node] = sum;
          always @(posedge clk or negedge rst_n) begin
            if (!rst_n) sum <= 0;
            else if (busy) sum <= tree[level-1][node*2] + tree[level-1][node*2+1];
          end
        end
        for (genvar unused_node=(LEAVES >> level);
             unused_node<LEAVES; unused_node=unused_node+1) begin : unused_nodes
          assign tree[level][unused_node] = 0;
        end
      end

      always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
          magnitude_a <= 0;
          magnitude_b <= 0;
          negative <= 0;
          busy <= 0;
          valid_result <= 0;
          valid_pipe <= 0;
          result <= 0;
        end else begin
          valid_pipe <= valid_pipe << 1;
          if (in_valid && in_ready) begin
            magnitude_a <= operand_a[WIDTH-1] ? -operand_a : operand_a;
            magnitude_b <= operand_b[WIDTH-1] ? -operand_b : operand_b;
            negative <= operand_a[WIDTH-1] ^ operand_b[WIDTH-1];
            busy <= 1;
            valid_pipe[0] <= 1;
          end
          if (valid_pipe[LEVELS+1]) begin
            if (negative) result <= -$signed(tree[LEVELS][0]);
            else result <= $signed(tree[LEVELS][0]);
            valid_result <= 1;
          end
          if (out_valid && out_ready) begin
            valid_result <= 0;
            busy <= 0;
          end
        end
      end
    end
  endgenerate
endmodule
