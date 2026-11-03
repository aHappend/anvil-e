module anvil_q1_mem_port (
  input wire clk, rst_n,
  input wire issue, write,
  input wire [3:0] kind,
  input wire [31:0] layer,
  input wire [2:0] proj,
  input wire [31:0] row, col, wdata,
  output wire idle, complete,
  output wire [31:0] rdata,
  output wire fault,
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
  reg [1:0] state;
  reg wr;
  reg [3:0] kd;
  reg [2:0] pj;
  reg [31:0] ly, rw, cl, wd;
  assign idle=rst_n && state==0;
  assign complete=rst_n && state==2 && mem_rsp_valid;
  assign fault=complete && mem_rsp_error;
  assign rdata=complete ? mem_rsp_rdata : 0;
  assign mem_req_valid=rst_n && state==1;
  assign mem_rsp_ready=rst_n && state==2;
  assign mem_req_write=rst_n ? wr : 0;
  assign mem_req_kind=rst_n ? kd : 0;
  assign mem_req_layer=rst_n ? ly : 0;
  assign mem_req_proj=rst_n ? pj : 0;
  assign mem_req_row=rst_n ? rw : 0;
  assign mem_req_col=rst_n ? cl : 0;
  assign mem_req_wdata=rst_n ? wd : 0;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state<=0; wr<=0; kd<=0; pj<=0; ly<=0; rw<=0; cl<=0; wd<=0;
    end else case (state)
      0: if (issue) begin
        wr<=write; kd<=kind; pj<=proj; ly<=layer; rw<=row; cl<=col; wd<=wdata;
        state<=1;
      end
      1: if (mem_req_valid && mem_req_ready) state<=2;
      2: if (mem_rsp_valid && mem_rsp_ready) state<=0;
      default: state<=0;
    endcase
  end
endmodule
