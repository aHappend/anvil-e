module anvil_edge_fifo #(
  parameter integer WIDTH = 9,
  parameter integer DEPTH = 16
) (
  input wire clk, rst_n,
  input wire in_valid,
  output wire in_ready,
  input wire [(WIDTH > 0 ? WIDTH : 1)-1:0] in_data,
  output wire out_valid,
  input wire out_ready,
  output wire [(WIDTH > 0 ? WIDTH : 1)-1:0] out_data,
  output wire empty, full
);
  generate
    if (WIDTH < 1 || DEPTH < 1) begin : invalid_parameters
      initial $fatal(1, "ANVIL_EDGE_FIFO PARAMETER ERROR: WIDTH and DEPTH must be positive");
      assign in_ready = 1'b0;
      assign out_valid = 1'b0;
      assign out_data = 0;
      assign empty = 1'b0;
      assign full = 1'b0;
    end else begin : storage
      localparam integer PTR_W = DEPTH > 1 ? $clog2(DEPTH) : 1;
      localparam integer COUNT_W = $clog2(DEPTH + 1);
      reg [WIDTH-1:0] data [0:DEPTH-1];
      reg [PTR_W-1:0] read_ptr, write_ptr;
      reg [COUNT_W-1:0] count;
      wire pop = out_valid && out_ready;
      wire push = in_valid && in_ready;
      assign out_valid = rst_n && count != 0;
      assign in_ready = rst_n && (count < DEPTH || pop);
      assign out_data = out_valid ? data[read_ptr] : {WIDTH{1'b0}};
      assign empty = rst_n && count == 0;
      assign full = rst_n && count == DEPTH;

      always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
          read_ptr <= 0;
          write_ptr <= 0;
          count <= 0;
        end else begin
          case ({push, pop})
            2'b10: count <= count + 1'b1;
            2'b01: count <= count - 1'b1;
            default: count <= count;
          endcase
          if (push) begin
            data[write_ptr] <= in_data;
            if (write_ptr == DEPTH-1) write_ptr <= 0;
            else write_ptr <= write_ptr + 1'b1;
          end
          if (pop) begin
            if (read_ptr == DEPTH-1) read_ptr <= 0;
            else read_ptr <= read_ptr + 1'b1;
          end
        end
      end
    end
  endgenerate
endmodule
