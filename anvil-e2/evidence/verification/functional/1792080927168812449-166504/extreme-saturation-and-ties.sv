
module tb;
reg clk=0,rst_n=0,start_valid=0,cmd_ready=0,result_valid=0,result_error=0,done_ready=0;
always #5 clk=~clk;
reg [31:0] result_data=0;
wire start_ready,cmd_valid,cmd_write,result_ready,done_valid;
wire [63:0] cmd_addr;
wire [31:0] cmd_wdata;
wire [3:0] done_error;
anvil_e2_vision_patch_embed #(.VISION_HIDDEN(4),.PATCH_SIZE(1),.POSITION_EMBEDDING_SIZE(1)) dut (.clk(clk),.rst_n(rst_n),.start_valid(start_valid),.start_ready(start_ready),.cmd_valid(cmd_valid),.cmd_ready(cmd_ready),.cmd_write(cmd_write),.cmd_addr(cmd_addr),.cmd_wdata(cmd_wdata),.result_valid(result_valid),.result_ready(result_ready),.result_data(result_data),.result_error(result_error),.done_valid(done_valid),.done_ready(done_ready),.done_error(done_error),.patch_rows(32'd1),.patch_cols(32'd1),.weights(64'h20000000),.image(64'h30000000),.output_base(64'h70000000));
reg [63:0] addresses[0:22];
reg [31:0] values[0:22];
reg [63:0] write_addresses[0:3];
reg [31:0] write_values[0:3];
integer fd,rc,n=0,cycles=0,lo,hi,mid,entry,i,j,wcount=0,reads=0,responses=0;
integer request_cycle=-1,response_cycle=-1,done_cycle=-1;
reg pending=0,active=0,held=0,held_done=0;
reg [96:0] payload;
task automatic known;
begin
 if ((^{start_ready,cmd_valid,cmd_write,cmd_addr,cmd_wdata,result_ready,done_valid,done_error})===1'bx)
  $fatal(1,"STAGE_UNKNOWN");
 if(!rst_n && {start_ready,cmd_valid,cmd_write,cmd_addr,cmd_wdata,result_ready,done_valid,done_error}!=='0)
  $fatal(1,"STAGE_RESET");
end
endtask
initial begin
 fd=$fopen("/data/sufeng/anvil-e2-line4/workspace_phase2/project/evidence/verification/functional/1792080927168812449-166504/extreme-saturation-and-ties.mem","r"); if(fd==0) $fatal(1,"STAGE_INPUT");
 while(!$feof(fd)) begin
  rc=$fscanf(fd,"%h %h\n",addresses[n],values[n]);
  if(rc==2) n=n+1;
  else if(!(rc==0 && $feof(fd)) && rc!=-1) $fatal(1,"STAGE_INPUT_FORMAT");
 end
 $fclose(fd); if(n!=23) $fatal(1,"STAGE_INPUT_COUNT");
 fd=$fopen("/data/sufeng/anvil-e2-line4/workspace_phase2/project/evidence/verification/functional/1792080927168812449-166504/extreme-saturation-and-ties.expected","r"); if(fd==0) $fatal(1,"STAGE_EXPECTED_FILE");
 for(i=0;i<4;i=i+1) begin
  rc=$fscanf(fd,"%h %h\n",write_addresses[i],write_values[i]);
  if(rc!=2) $fatal(1,"STAGE_EXPECTED_FORMAT");
 end
 $fclose(fd);
 #1; known(); #11; rst_n=1;
end
always @(negedge clk) begin
 known();
 if(rst_n) begin
  cycles=cycles+1; if(cycles>4000000) $fatal(1,"STAGE_TIMEOUT");
  start_valid=!active;
  cmd_ready=cycles%7>=3;
  result_valid=pending && cycles>=response_cycle;
  if(done_valid && done_cycle<0) done_cycle=cycles;
  done_ready=done_cycle>=0 && cycles>done_cycle+20;
 end
end
always @(posedge clk) begin
 known();
 if(rst_n) begin
  if(held && (!cmd_valid || {cmd_write,cmd_addr,cmd_wdata}!==payload)) $fatal(1,"STAGE_STALL");
  held=cmd_valid && !cmd_ready; payload={cmd_write,cmd_addr,cmd_wdata};
  if(held_done && (!done_valid || done_error!==0)) $fatal(1,"STAGE_DONE_STALL");
  held_done=done_valid && !done_ready;
  if(start_valid && start_ready) begin if(active) $fatal(1,"STAGE_DUPLICATE"); active=1; end
  if(result_valid && result_ready) begin
   if(!pending || cycles<=request_cycle) $fatal(1,"STAGE_RESPONSE");
   pending=0; responses=responses+1;
  end
  if(cmd_valid && cmd_ready) begin
   if(pending || !active || cmd_addr[1:0]!==0) $fatal(1,"STAGE_REQUEST");
   pending=1; request_cycle=cycles; response_cycle=cycles+2+reads%3; result_data=0;
   if(cmd_write) begin
    if(wcount>=4) $fatal(1,"STAGE_EXCESS_WRITE");
    if(cmd_addr!==write_addresses[wcount] || cmd_wdata!==write_values[wcount])
     $fatal(1,"STAGE_WRITE_VALUE %h %h",cmd_addr,cmd_wdata);
    wcount=wcount+1;
    $display("W %h %h",cmd_addr,cmd_wdata);
   end else begin
    lo=0; hi=n-1; entry=-1;
    while(lo<=hi) begin
     mid=(lo+hi)/2;
     if(addresses[mid]==cmd_addr) begin entry=mid; lo=hi+1; end
     else if(addresses[mid]<cmd_addr) lo=mid+1;
     else hi=mid-1;
    end
    if(entry<0) $fatal(1,"STAGE_READ_ADDRESS %h",cmd_addr);
    result_data=values[entry]; reads=reads+1;
    $display("R %h",cmd_addr);
   end
  end
  if(done_valid && done_ready) begin
   if(done_error!==0 || pending || wcount!=4 || reads==0 ||
      responses!=reads+wcount || cycles<=done_cycle+20) $fatal(1,"STAGE_COMPLETION");
   $display("STAGE_COMPLETE %0d %0d %0d",reads,wcount,responses); $finish;
  end
 end
end
endmodule
