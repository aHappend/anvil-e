
module tb #(parameter logic [127:0] RMS_EPSILON_Q80 = (128'd17 << 56));
reg clk=0,rst_n=0,start_valid=0,in_valid=0,out_ready=0;
always #5 clk=~clk;
wire start_ready,in_ready,out_valid,out_last,out_error;
wire signed [47:0] out_data;
wire [31:0] out_index;
reg signed [47:0] in_data=0;
reg signed [31:0] in_weight=0;
reg signed [47:0] values[0:3],expected[0:3];
reg signed [31:0] weights[0:3];
integer cycles=0,loaded=0,beats=0,stalls=0,output_wait=0;
reg started=0,held=0;
reg [81:0] payload;
anvil_e2_norm #(.MAX_WIDTH(4),.RMS_EPSILON_Q80(RMS_EPSILON_Q80)) dut(
 .clk(clk),.rst_n(rst_n),.start_valid(start_valid),.start_ready(start_ready),
 .start_count(32'd3),.start_l2(1'b1),.in_valid(in_valid),.in_ready(in_ready),
 .in_data(in_data),.in_weight(in_weight),.out_valid(out_valid),.out_ready(out_ready),
 .out_data(out_data),.out_index(out_index),.out_last(out_last),.out_error(out_error));
task automatic known;
begin
 if ((^{start_ready,in_ready,out_valid,out_data,out_index,out_last,out_error})===1'bx)
  $fatal(1,"NORM_UNKNOWN");
 if (!rst_n && {start_ready,in_ready,out_valid,out_data,out_index,out_last,out_error}!=='0)
  $fatal(1,"NORM_RESET");
end
endtask
initial begin
 values[0]=48'hffffffffff80; weights[0]=32'h00000000; expected[0]=48'hff4a4664d820;
values[1]=48'h000000000001; weights[1]=32'h00000000; expected[1]=48'h00016b733650;
values[2]=48'h00000000007f; weights[2]=32'h00000000; expected[2]=48'h00b44e27f191;
 #0;known();#1;known();#11;rst_n=1;
end
always @(negedge clk) begin
 known();
 if(rst_n) begin
  cycles=cycles+1; if(cycles>1000) $fatal(1,"NORM_TIMEOUT");
  start_valid=!started;
  in_valid=started && loaded<3;
  if(loaded<3) begin in_data=values[loaded];in_weight=weights[loaded];end
  if(out_valid && output_wait<4) output_wait=output_wait+1;
  out_ready=output_wait>=4 && cycles%5==0;
 end
end
always @(posedge clk) begin
 known();
 if(rst_n) begin
  if(start_valid && start_ready) started=1;
  if(in_valid && in_ready) loaded=loaded+1;
  if(held && (!out_valid || {out_data,out_index,out_last,out_error}!==payload))
   $fatal(1,"NORM_STABILITY");
  held=out_valid && !out_ready;
  payload={out_data,out_index,out_last,out_error};
  if(held) stalls=stalls+1;
  if(out_valid && out_ready) begin
   if(beats>=3 || out_index!==32'(beats) || out_data!==expected[beats] ||
      out_last!==(beats==2) || out_error!==0) $fatal(1,"NORM_MISMATCH");
   $display("N %0d %h",out_index,out_data); beats=beats+1;
   if(beats==3) begin
    if(loaded!=3 || stalls==0) $fatal(1,"NORM_COVERAGE");
    $display("NORM_COMPLETE 3 %0d",stalls);$finish;
   end
  end
 end
end
endmodule
