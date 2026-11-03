module anvil_q1_bus_mux #(parameter integer N=2) (
  input wire rst_n,
  input wire [31:0] select,
  input wire [(N>0 ? N : 1)-1:0] c_req_valid,
  output wire [(N>0 ? N : 1)-1:0] c_req_ready,
  input wire [(N>0 ? N : 1)-1:0] c_req_write,
  input wire [(N>0 ? N : 1)*4-1:0] c_req_kind,
  input wire [(N>0 ? N : 1)*32-1:0] c_req_layer,
  input wire [(N>0 ? N : 1)*3-1:0] c_req_proj,
  input wire [(N>0 ? N : 1)*32-1:0] c_req_row, c_req_col, c_req_wdata,
  output wire [(N>0 ? N : 1)-1:0] c_rsp_valid,
  input wire [(N>0 ? N : 1)-1:0] c_rsp_ready,
  output wire [(N>0 ? N : 1)*32-1:0] c_rsp_rdata,
  output wire [(N>0 ? N : 1)-1:0] c_rsp_error,
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
  generate if (N<1) begin : invalid_parameters
    initial $fatal(1, "ANVIL_Q1 PARAMETER ERROR: bus client count must be positive");
    assign c_req_ready=0; assign c_rsp_valid=0; assign c_rsp_rdata=0; assign c_rsp_error=0;
    assign mem_req_valid=0; assign mem_req_write=0; assign mem_req_kind=0;
    assign mem_req_layer=0; assign mem_req_proj=0; assign mem_req_row=0;
    assign mem_req_col=0; assign mem_req_wdata=0; assign mem_rsp_ready=0;
  end else begin : mux
    wire active=rst_n && select<N;
    wire [N*137-1:0] requests;
    wire [136:0] request=active ? requests[select*137+:137] : 137'd0;
    assign {mem_req_valid,mem_req_write,mem_req_kind,mem_req_layer,
      mem_req_proj,mem_req_row,mem_req_col,mem_req_wdata}=request;
    assign mem_rsp_ready=active ? c_rsp_ready[select] : 0;
    for (genvar g=0;g<N;g=g+1) begin : routes
      assign requests[g*137+:137]=
        {c_req_valid[g],c_req_write[g],c_req_kind[g*4+:4],c_req_layer[g*32+:32],
         c_req_proj[g*3+:3],c_req_row[g*32+:32],c_req_col[g*32+:32],c_req_wdata[g*32+:32]};
      assign c_req_ready[g]=active && select==g && mem_req_ready;
      assign c_rsp_valid[g]=active && select==g && mem_rsp_valid;
      assign c_rsp_rdata[g*32+:32]=active && select==g ? mem_rsp_rdata : 0;
      assign c_rsp_error[g]=active && select==g && mem_rsp_error;
    end
  end endgenerate
endmodule
