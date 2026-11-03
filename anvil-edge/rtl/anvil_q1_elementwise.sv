module anvil_q1_elementwise #(
  parameter NUM_LAYERS=24, HIDDEN_SIZE=896, INTERMEDIATE_SIZE=4864,
  MAX_SEQ_LEN=32768
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
  localparam [3:0] IDLE=0, READ_A=1, WAIT_A=2, READ_B=3, WAIT_B=4,
    ADD=5, SILU=6, SILU_WAIT=7, MULTIPLY=8, MULTIPLY_WAIT=9,
    ROUND=10, WRITE=11, WRITE_WAIT=12, FINISH=13, INVALID_COMMAND=14;
  reg [3:0] state;
  reg [1:0] mode;
  reg failed;
  reg [31:0] index;
  reg signed [31:0] a, b, silu_value, output_value;
  reg signed [32:0] sum;
  reg signed [63:0] product_value;
  wire port_idle, complete, fault;
  wire [31:0] read_data;
  reg issue, write_request;
  reg [31:0] row, write_data;
  wire silu_ready, silu_valid, silu_error;
  wire signed [31:0] silu_result;
  wire multiply_ready, multiply_valid;
  wire signed [63:0] product;
  generate if (NUM_LAYERS<=0 || HIDDEN_SIZE<=0 || INTERMEDIATE_SIZE<=0 ||
               MAX_SEQ_LEN<=0 || MAX_SEQ_LEN>16777215 ||
               HIDDEN_SIZE%8!=0 || INTERMEDIATE_SIZE%8!=0 ||
               128'(NUM_LAYERS)>128'd4294967295 ||
               128'(HIDDEN_SIZE)*15>128'd4294967295 ||
               128'(INTERMEDIATE_SIZE)*15>128'd4294967295) begin : invalid_parameters
    initial $fatal(1, "ANVIL_Q1 PARAMETER ERROR: elementwise dimensions");
  end endgenerate
  anvil_q1_mem_port memory_port(
    .clk(clk),.rst_n(rst_n),.issue(issue),.write(write_request),.kind(4'd8),
    .layer(32'd0),.proj(3'd0),.row(row),.col(index),.wdata(write_data),
    .idle(port_idle),.complete(complete),.rdata(read_data),.fault(fault),
    .mem_req_valid(mem_req_valid),.mem_req_ready(mem_req_ready),
    .mem_req_write(mem_req_write),.mem_req_kind(mem_req_kind),
    .mem_req_layer(mem_req_layer),.mem_req_proj(mem_req_proj),
    .mem_req_row(mem_req_row),.mem_req_col(mem_req_col),.mem_req_wdata(mem_req_wdata),
    .mem_rsp_valid(mem_rsp_valid),.mem_rsp_ready(mem_rsp_ready),
    .mem_rsp_rdata(mem_rsp_rdata),.mem_rsp_error(mem_rsp_error)
  );
  anvil_edge_silu_q16 silu_unit(
    .clk(clk),.rst_n(rst_n),.in_valid(state==SILU),.in_ready(silu_ready),.x(a),
    .out_valid(silu_valid),.out_ready(state==SILU_WAIT),.value(silu_result),
    .arithmetic_error(silu_error)
  );
  anvil_edge_signed_multiplier #(.WIDTH(32)) multiplier(
    .clk(clk),.rst_n(rst_n),.in_valid(state==MULTIPLY),.in_ready(multiply_ready),
    .operand_a(silu_value),.operand_b(b),.out_valid(multiply_valid),
    .out_ready(state==MULTIPLY_WAIT),.product(product)
  );
  assign cmd_ready=rst_n && state==IDLE;
  assign done=rst_n && state==FINISH;
  assign error=done && failed;
  always @* begin
    issue=0; write_request=0; row=0; write_data=0;
    if (rst_n && port_idle) case (state)
      READ_A: begin issue=1; row=mode==0 ? 0 : (mode==1 ? 7 : 9); end
      READ_B: begin issue=1; row=mode==0 ? 6 : (mode==1 ? 12 : 10); end
      WRITE: begin
        issue=1; write_request=1; row=mode==0 ? 7 : (mode==1 ? 0 : 11);
        write_data=output_value;
      end
      default: begin end
    endcase
  end
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state<=IDLE; mode<=0; failed<=0; index<=0; a<=0; b<=0;
      silu_value<=0; output_value<=0; sum<=0; product_value<=0;
    end else if (fault) begin failed<=1; state<=FINISH; end
    else case (state)
      IDLE: if (cmd_valid && cmd_ready) begin
        failed<=0; mode<=cmd_mode; index<=0;
        if (cmd_mode>2 || cmd_layer>=NUM_LAYERS || cmd_pos>=MAX_SEQ_LEN) begin
          failed<=1; state<=INVALID_COMMAND;
        end else state<=READ_A;
      end
      READ_A: if (issue) state<=WAIT_A;
      WAIT_A: if (complete) begin a<=read_data; state<=READ_B; end
      READ_B: if (issue) state<=WAIT_B;
      WAIT_B: if (complete) begin
        b<=read_data;
        if (mode==2) state<=SILU;
        else state<=ADD;
      end
      ADD: begin sum<=$signed({a[31],a})+$signed({b[31],b}); state<=ROUND; end
      SILU: if (silu_ready) state<=SILU_WAIT;
      SILU_WAIT: if (silu_valid) begin
        if (silu_error) begin failed<=1; state<=FINISH; end
        else begin silu_value<=silu_result; state<=MULTIPLY; end
      end
      MULTIPLY: if (multiply_ready) state<=MULTIPLY_WAIT;
      MULTIPLY_WAIT: if (multiply_valid) begin product_value<=product; state<=ROUND; end
      ROUND: begin
        if (mode==2) output_value<=anvil_edge_numeric_pkg::sat32(
          anvil_edge_numeric_pkg::round_shift({{64{product_value[63]}},product_value},16));
        else output_value<=anvil_edge_numeric_pkg::sat32({{95{sum[32]}},sum});
        state<=WRITE;
      end
      WRITE: if (issue) state<=WRITE_WAIT;
      WRITE_WAIT: if (complete) begin
        if (index+1<(mode==2 ? INTERMEDIATE_SIZE : HIDDEN_SIZE)) begin
          index<=index+1; state<=READ_A;
        end else state<=FINISH;
      end
      INVALID_COMMAND: state<=FINISH;
      FINISH: state<=IDLE;
      default: begin failed<=1; state<=FINISH; end
    endcase
  end
endmodule
