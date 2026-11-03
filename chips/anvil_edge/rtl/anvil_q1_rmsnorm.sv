module anvil_q1_rmsnorm #(
  parameter NUM_LAYERS=24, HIDDEN_SIZE=896, MAX_SEQ_LEN=32768
) (
  input wire clk, rst_n, cmd_valid,
  output wire cmd_ready,
  input wire [31:0] cmd_layer, cmd_pos,
  input wire [1:0] cmd_mode,
  output wire done, error,
  output wire mem_req_valid,
  input wire mem_req_ready,
  output wire mem_req_write,
  output wire [3:0] mem_req_kind,
  output wire [31:0] mem_req_layer,
  output wire [2:0] mem_req_proj,
  output wire [31:0] mem_req_row, mem_req_col, mem_req_wdata,
  input wire mem_rsp_valid,
  output wire mem_rsp_ready,
  input wire [31:0] mem_rsp_rdata,
  input wire mem_rsp_error
);
  localparam [4:0] IDLE=0, READ_SQUARE=1, WAIT_SQUARE=2,
    SQUARE=3, SQUARE_WAIT=4, SQUARE_ACCUMULATE=5, MEAN_DIVIDE=6,
    MEAN_WAIT=7, MEAN_ADD=8, ROOT=9, ROOT_WAIT=10,
    RECIPROCAL_DIVIDE=11, RECIPROCAL_WAIT=12, READ_X=13, WAIT_X=14,
    READ_GAMMA=15, WAIT_GAMMA=16, NORMALIZE=17, NORMALIZE_WAIT=18,
    SCALE=19, SCALE_WAIT=20, ROUND=21, WRITE=22, WRITE_WAIT=23,
    FINISH=24, INVALID_COMMAND=25;
  localparam [31:0] SAFE_H=HIDDEN_SIZE>0 ? HIDDEN_SIZE : 1;
  reg [4:0] state;
  reg failed;
  reg [31:0] layer, index, source_slot, target_slot;
  reg [3:0] norm_kind;
  reg [95:0] sum;
  reg [63:0] square_value, reciprocal, denominator;
  reg [127:0] mean;
  reg signed [31:0] x, gamma, output_value;
  reg signed [63:0] norm_product;
  reg signed [127:0] scale_product;
  wire port_idle, complete, fault;
  wire [31:0] read_data;
  reg issue, write_request;
  reg [3:0] kind;
  reg [31:0] memory_layer, row, write_data;
  wire multiply_ready, multiply_valid;
  wire signed [255:0] product;
  reg signed [127:0] operand_a, operand_b;
  wire divide_ready, divide_valid, divide_by_zero;
  wire [127:0] quotient, remainder;
  wire root_ready, root_valid;
  wire [63:0] root_value;
  generate if (NUM_LAYERS<=0 || HIDDEN_SIZE<=0 || HIDDEN_SIZE%8!=0 ||
               MAX_SEQ_LEN<=0 || MAX_SEQ_LEN>16777215 ||
               128'(HIDDEN_SIZE)*15>128'd4294967295 ||
               128'(NUM_LAYERS)>128'd4294967295) begin : invalid_parameters
    initial $fatal(1, "ANVIL_Q1 PARAMETER ERROR: RMSNorm dimensions");
  end endgenerate

  anvil_q1_mem_port memory_port(
    .clk(clk),.rst_n(rst_n),.issue(issue),.write(write_request),
    .kind(kind),.layer(memory_layer),.proj(3'd0),.row(row),.col(index),
    .wdata(write_data),.idle(port_idle),.complete(complete),.rdata(read_data),.fault(fault),
    .mem_req_valid(mem_req_valid),.mem_req_ready(mem_req_ready),
    .mem_req_write(mem_req_write),.mem_req_kind(mem_req_kind),
    .mem_req_layer(mem_req_layer),.mem_req_proj(mem_req_proj),
    .mem_req_row(mem_req_row),.mem_req_col(mem_req_col),.mem_req_wdata(mem_req_wdata),
    .mem_rsp_valid(mem_rsp_valid),.mem_rsp_ready(mem_rsp_ready),
    .mem_rsp_rdata(mem_rsp_rdata),.mem_rsp_error(mem_rsp_error)
  );
  anvil_edge_signed_multiplier #(.WIDTH(128)) multiplier(
    .clk(clk),.rst_n(rst_n),
    .in_valid(state==SQUARE || state==NORMALIZE || state==SCALE),
    .in_ready(multiply_ready),.operand_a(operand_a),.operand_b(operand_b),
    .out_valid(multiply_valid),
    .out_ready(state==SQUARE_WAIT || state==NORMALIZE_WAIT || state==SCALE_WAIT),
    .product(product)
  );
  anvil_edge_unsigned_divider #(.WIDTH(128)) divider(
    .clk(clk),.rst_n(rst_n),
    .in_valid(state==MEAN_DIVIDE || state==RECIPROCAL_DIVIDE),.in_ready(divide_ready),
    .numerator(state==MEAN_DIVIDE ? {sum,32'd0} : 128'd18446744073709551616),
    .denominator(state==MEAN_DIVIDE ? {96'd0,SAFE_H} : {64'd0,denominator}),
    .out_valid(divide_valid),.out_ready(state==MEAN_WAIT || state==RECIPROCAL_WAIT),
    .quotient(quotient),.remainder(remainder),.divide_by_zero(divide_by_zero)
  );
  anvil_edge_isqrt128 root_unit(
    .clk(clk),.rst_n(rst_n),.in_valid(state==ROOT),.in_ready(root_ready),
    .radicand(mean),.out_valid(root_valid),.out_ready(state==ROOT_WAIT),.root(root_value)
  );
  assign cmd_ready=rst_n && state==IDLE;
  assign done=rst_n && state==FINISH;
  assign error=done && failed;

  always @* begin
    operand_a=0; operand_b=0;
    issue=0; write_request=0; kind=0; memory_layer=0; row=0; write_data=0;
    if (rst_n) begin
      case (state)
        SQUARE: begin
          operand_a={{96{x[31]}},x}; operand_b={{96{x[31]}},x};
        end
        NORMALIZE: begin
          operand_a={{96{x[31]}},x}; operand_b={{96{gamma[31]}},gamma};
        end
        SCALE: begin
          operand_a={{64{norm_product[63]}},norm_product};
          operand_b={64'd0,reciprocal};
        end
        default: begin end
      endcase
      if (port_idle) case (state)
        READ_SQUARE,READ_X: begin issue=1; kind=8; row=source_slot; end
        READ_GAMMA: begin
          issue=1; kind=norm_kind; memory_layer=norm_kind==7 ? 0 : layer;
        end
        WRITE: begin
          issue=1; write_request=1; kind=8; row=target_slot; write_data=output_value;
        end
        default: begin end
      endcase
    end
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state<=IDLE; failed<=0; layer<=0; index<=0; source_slot<=0; target_slot<=0;
      norm_kind<=0; sum<=0; square_value<=0; reciprocal<=0; denominator<=0;
      mean<=0; x<=0; gamma<=0; output_value<=0; norm_product<=0; scale_product<=0;
    end else if (fault) begin failed<=1; state<=FINISH; end
    else case (state)
      IDLE: if (cmd_valid && cmd_ready) begin
        failed<=0; layer<=cmd_layer; index<=0; sum<=0;
        if (cmd_mode>2 || cmd_layer>=NUM_LAYERS || cmd_pos>=MAX_SEQ_LEN) begin
          failed<=1; state<=INVALID_COMMAND;
        end else begin
          source_slot<=cmd_mode==1 ? 7 : 0;
          target_slot<=cmd_mode==0 ? 1 : (cmd_mode==1 ? 8 : 14);
          norm_kind<=cmd_mode==0 ? 5 : (cmd_mode==1 ? 6 : 7);
          state<=READ_SQUARE;
        end
      end
      READ_SQUARE: if (issue) state<=WAIT_SQUARE;
      WAIT_SQUARE: if (complete) begin x<=read_data; state<=SQUARE; end
      SQUARE: if (multiply_ready) state<=SQUARE_WAIT;
      SQUARE_WAIT: if (multiply_valid) begin square_value<=product[63:0]; state<=SQUARE_ACCUMULATE; end
      SQUARE_ACCUMULATE: begin
        sum<=sum+{32'd0,square_value};
        if (index+1<HIDDEN_SIZE) begin index<=index+1; state<=READ_SQUARE; end
        else state<=MEAN_DIVIDE;
      end
      MEAN_DIVIDE: if (divide_ready) state<=MEAN_WAIT;
      MEAN_WAIT: if (divide_valid) begin
        if (divide_by_zero) begin failed<=1; state<=FINISH; end
        else begin mean<=quotient; state<=MEAN_ADD; end
      end
      MEAN_ADD: begin mean<=mean+128'd18446744073710; state<=ROOT; end
      ROOT: if (root_ready) state<=ROOT_WAIT;
      ROOT_WAIT: if (root_valid) begin
        if (root_value==0) begin failed<=1; state<=FINISH; end
        else begin denominator<=root_value; state<=RECIPROCAL_DIVIDE; end
      end
      RECIPROCAL_DIVIDE: if (divide_ready) state<=RECIPROCAL_WAIT;
      RECIPROCAL_WAIT: if (divide_valid) begin
        if (divide_by_zero) begin failed<=1; state<=FINISH; end
        else begin reciprocal<=quotient[63:0]; index<=0; state<=READ_X; end
      end
      READ_X: if (issue) state<=WAIT_X;
      WAIT_X: if (complete) begin x<=read_data; state<=READ_GAMMA; end
      READ_GAMMA: if (issue) state<=WAIT_GAMMA;
      WAIT_GAMMA: if (complete) begin
        if (anvil_edge_numeric_pkg::f16_invalid(read_data[15:0])) begin
          failed<=1; state<=FINISH;
        end else begin
          gamma<=anvil_edge_numeric_pkg::f16_q16(read_data[15:0]);
          state<=NORMALIZE;
        end
      end
      NORMALIZE: if (multiply_ready) state<=NORMALIZE_WAIT;
      NORMALIZE_WAIT: if (multiply_valid) begin norm_product<=product[63:0]; state<=SCALE; end
      SCALE: if (multiply_ready) state<=SCALE_WAIT;
      SCALE_WAIT: if (multiply_valid) begin scale_product<=product[127:0]; state<=ROUND; end
      ROUND: begin
        output_value<=anvil_edge_numeric_pkg::sat32(
          anvil_edge_numeric_pkg::round_shift(scale_product,48));
        state<=WRITE;
      end
      WRITE: if (issue) state<=WRITE_WAIT;
      WRITE_WAIT: if (complete) begin
        if (index+1<HIDDEN_SIZE) begin index<=index+1; state<=READ_X; end
        else state<=FINISH;
      end
      INVALID_COMMAND: state<=FINISH;
      FINISH: state<=IDLE;
      default: begin failed<=1; state<=FINISH; end
    endcase
  end
endmodule
