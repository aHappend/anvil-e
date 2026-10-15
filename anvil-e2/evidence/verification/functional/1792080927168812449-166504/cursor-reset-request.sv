
module tb;
reg clk=0,rst_n=0,start_valid=0,in_valid=0,cmd_ready=0,result_valid=0;
reg result_error=0,out_ready=0,done_ready=0;
reg [31:0] start_rows=3,start_cols=3,result_data=0;
reg [63:0] start_weights=64'h12340;
reg signed [47:0] in_data=0;
wire start_ready,in_ready,cmd_valid,result_ready,mac_clear,mac_accumulate;
wire out_valid,out_last,done_valid;
wire [63:0] cmd_addr;
wire signed [47:0] mac_a,mac_b,mac_rounded,out_data;
wire [31:0] out_index;
wire [3:0] done_error;
wire signed [127:0] sum;
wire signed [95:0] product;
anvil_e2_matvec #(.MAX_INPUT(3)) dut(
 .clk(clk),.rst_n(rst_n),.start_valid(start_valid),.start_ready(start_ready),
 .start_rows(start_rows),.start_cols(start_cols),.start_weights(start_weights),
 .in_valid(in_valid),.in_ready(in_ready),.in_data(in_data),
 .cmd_valid(cmd_valid),.cmd_ready(cmd_ready),.cmd_addr(cmd_addr),
 .result_valid(result_valid),.result_ready(result_ready),.result_data(result_data),
 .result_error(result_error),.mac_clear(mac_clear),.mac_accumulate(mac_accumulate),
 .mac_a(mac_a),.mac_b(mac_b),.mac_rounded(mac_rounded),
 .out_valid(out_valid),.out_ready(out_ready),.out_data(out_data),
 .out_index(out_index),.out_last(out_last),.done_valid(done_valid),
 .done_ready(done_ready),.done_error(done_error));
anvil_e2_mac mac(.clk(clk),.rst_n(rst_n),.clear(mac_clear),
 .accumulate(mac_accumulate),.a(mac_a),.b(mac_b),.sum(sum),
 .rounded(mac_rounded),.product(product));
always #5 clk=~clk;
reg signed [47:0] x[0:2],y[0:2];
reg signed [31:0] w[0:8];
integer cycles=0,loaded=0,requests=0,responses=0,outputs=0,accumulations=0;
integer response_cycle=-1,request_cycle=-1,first_cmd=-1,first_out=-1,first_done=-1;
integer reqstalls=0,rspwait=0,outstalls=0,donestalls=0;
reg active=0,pending=0,retired_error=0,held_cmd=0,held_out=0,held_done=0;
reg [63:0] held_addr;
reg [80:0] held_output;
task automatic known;
begin
 if((^{start_ready,in_ready,cmd_valid,cmd_addr,result_ready,
   mac_clear,mac_accumulate,mac_a,mac_b,out_valid,out_data,out_index,out_last,
   done_valid,done_error})===1'bx) $fatal(1,"CURSOR_XZ");
 if(!rst_n && {start_ready,in_ready,cmd_valid,cmd_addr,result_ready,
   mac_clear,mac_accumulate,mac_a,mac_b,out_valid,out_data,out_index,out_last,
   done_valid,done_error}!=='0) $fatal(1,"CURSOR_RESET");
end
endtask
initial begin x[0]=48'h008000003039;
x[1]=48'hffaaaaaa7a72;
x[2]=48'h004000003039;
w[0]=32'h0055559c;
w[1]=32'hffbfffb9;
w[2]=32'hffcccc86;
w[3]=32'h002aaaf1;
w[4]=32'hffdb6d70;
w[5]=32'hffdfffb9;
w[6]=32'h001c720e;
w[7]=32'hffe66620;
w[8]=32'hffe8b9e8;
y[0]=48'h0033335c927c;
y[1]=48'h001986417391;
y[2]=48'h0010f02105cc;
 #1; known(); #11; rst_n=1;
end
always @(negedge clk) begin
 known();
 if(rst_n) begin
  cycles=cycles+1; if(cycles>1000) $fatal(1,"CURSOR_TIMEOUT");
  start_valid=!active && cycles>2;
  in_valid=active && loaded<3 && cycles%3!=0;
  in_data=loaded<3 ? x[loaded]:48'sd0;
  if(cmd_valid && first_cmd<0) first_cmd=cycles;
  cmd_ready=first_cmd>=0 && cycles>first_cmd+4 && cycles%7>=3;
  result_valid=pending && cycles>=response_cycle;
  if(out_valid && first_out<0) first_out=cycles;
  out_ready=first_out>=0 && cycles>first_out+7 && cycles%3==0;
  if(done_valid && first_done<0) first_done=cycles;
  done_ready=first_done>=0 && cycles>first_done+8;
  if(cmd_valid && !cmd_ready) begin
   rst_n=0; start_valid=0; in_valid=0; result_valid=0; pending=0;
   #1; known(); #11; rst_n=1;
   #10; if(start_ready!==1 || cmd_valid!==0 || out_valid!==0 || done_valid!==0)
     $fatal(1,"CURSOR_RESET_RESUMED");
   $display("CURSOR_RESET_COMPLETE request"); $finish;
  end
 end
end
always @(posedge clk) begin
 known();
 $display("P %0d %h",cycles,{start_ready,in_ready,cmd_valid,cmd_addr,result_ready,
   mac_clear,mac_accumulate,mac_a,mac_b,out_valid,out_data,out_index,out_last,
   done_valid,done_error});
 if(rst_n) begin
  if(held_cmd && (!cmd_valid || cmd_addr!==held_addr)) $fatal(1,"CURSOR_REQUEST_STALL");
  if(held_out && (!out_valid || {out_data,out_index,out_last}!==held_output))
   $fatal(1,"CURSOR_OUTPUT_STALL");
  if(held_done && (!done_valid || done_error!==4'd0))
   $fatal(1,"CURSOR_DONE_STALL");
  held_cmd=cmd_valid && !cmd_ready; held_addr=cmd_addr;
  held_out=out_valid && !out_ready; held_output={out_data,out_index,out_last};
  held_done=done_valid && !done_ready;
  if(held_cmd) reqstalls=reqstalls+1;
  if(pending && !result_valid) rspwait=rspwait+1;
  if(held_out) outstalls=outstalls+1;
  if(held_done) donestalls=donestalls+1;
  if(start_valid && start_ready) begin
   if(active) $fatal(1,"CURSOR_DUPLICATE"); active=1;
  end
  if(in_valid && in_ready) loaded=loaded+1;
  if(mac_accumulate) begin
   if(!(result_valid && result_ready) || result_error ||
      mac_a!==x[responses%3] || mac_b!=={w[responses],16'd0} ||
      mac_clear!==(responses%3==0)) $fatal(1,"CURSOR_MAC");
   accumulations=accumulations+1;
  end
  if(result_valid && result_ready) begin
   if(!pending || cycles<=request_cycle) $fatal(1,"CURSOR_RESPONSE");
   pending=0; responses=responses+1;
   if(result_error) retired_error=1;
  end
  if(retired_error && cmd_valid) $fatal(1,"CURSOR_REQUEST_AFTER_ERROR");
  if(cmd_valid && cmd_ready) begin
   if(!active || pending || requests>=9 ||
      cmd_addr!==64'h12340+64'd4*requests) $fatal(1,"CURSOR_ORDER");
   pending=1; request_cycle=cycles; response_cycle=cycles+4+requests%3;
   result_data=w[requests]; result_error=(requests==-1);
   requests=requests+1;
  end
  if(out_valid && out_ready) begin
   if(outputs>=3 || out_index!==outputs ||
      out_last!==(outputs==2) || out_data!==y[outputs])
     $fatal(1,"CURSOR_DENSE_RESULT");
   outputs=outputs+1;
  end
  if(done_valid && done_ready) begin
   if(pending || requests!=responses || requests!=9 ||
      outputs!=3 ||
      accumulations!=9 ||
      done_error!==4'd0 || reqstalls==0 || rspwait==0 ||
      donestalls<8 || (1 && outstalls<7))
     $fatal(1,"CURSOR_COMPLETION");
   $display("CURSOR_COMPLETE %0d %0d %0d %0d",requests,responses,outputs,accumulations);
   $finish;
  end
  #1; if(active) begin start_rows=99; start_cols=99; start_weights=64'hbad; end
 end
end
endmodule
