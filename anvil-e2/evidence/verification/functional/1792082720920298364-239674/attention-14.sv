
module tb;
reg clk=0,rst_n=0,start_valid=0,cmd_ready=0,result_valid=0,result_error=0;
reg out_ready=0,done_ready=0;
reg [31:0] start_tokens=5,start_query=4,start_head=2,result_data=0;
reg start_full=1;
reg [63:0] qb=64'h123400,kb=64'h133400,vb=64'h143400;
reg [63:0] pb=64'h153400,mb=64'h163400;
wire start_ready,cmd_valid,result_ready,mac_clear,mac_accumulate;
wire [63:0] cmd_addr;
wire signed [47:0] mac_a,mac_b,mac_rounded,out_data;
wire signed [127:0] mac_sum;
wire signed [95:0] mac_product;
wire nonlinear_valid,nonlinear_ready,nonlinear_out_valid,nonlinear_out_ready,nonlinear_out_error;
wire [2:0] nonlinear_op;
wire signed [47:0] nonlinear_data,nonlinear_out_data;
wire out_valid,out_last,done_valid;
wire [31:0] out_index;
wire [3:0] done_error;
anvil_e2_attention #(.NUM_Q_HEADS(4),.LOCAL_KV_HEADS(2),.FULL_KV_HEADS(1),
 .LOCAL_HEAD_DIM(2),.FULL_HEAD_DIM(6),.SLIDING_WINDOW(2),.VISION(1)) dut(
 .clk(clk),.rst_n(rst_n),.start_valid(start_valid),.start_ready(start_ready),
 .start_tokens(start_tokens),.start_query(start_query),.start_head(start_head),
 .start_full(start_full),.start_q_base(qb),.start_k_base(kb),.start_v_base(vb),
 .start_positions_base(pb),.start_mask_base(mb),
 .cmd_valid(cmd_valid),.cmd_ready(cmd_ready),.cmd_addr(cmd_addr),
 .result_valid(result_valid),.result_ready(result_ready),.result_data(result_data),
 .result_error(result_error),.mac_clear(mac_clear),.mac_accumulate(mac_accumulate),
 .mac_a(mac_a),.mac_b(mac_b),.mac_sum(mac_sum),.mac_product(mac_product),
 .nonlinear_valid(nonlinear_valid),.nonlinear_ready(nonlinear_ready),
 .nonlinear_op(nonlinear_op),.nonlinear_data(nonlinear_data),
 .nonlinear_out_valid(nonlinear_out_valid),.nonlinear_out_ready(nonlinear_out_ready),
 .nonlinear_out_data(nonlinear_out_data),.nonlinear_out_error(nonlinear_out_error),
 .out_valid(out_valid),.out_ready(out_ready),.out_data(out_data),
 .out_index(out_index),.out_last(out_last),.done_valid(done_valid),
 .done_ready(done_ready),.done_error(done_error));
anvil_e2_mac mac(.clk(clk),.rst_n(rst_n),.clear(mac_clear),.accumulate(mac_accumulate),
 .a(mac_a),.b(mac_b),.sum(mac_sum),.rounded(mac_rounded),.product(mac_product));
anvil_e2_nonlinear nonlinear(.clk(clk),.rst_n(rst_n),
 .in_valid(nonlinear_valid),.in_ready(nonlinear_ready),.in_op(nonlinear_op),
 .in_data(nonlinear_data),.out_valid(nonlinear_out_valid),
 .out_ready(nonlinear_out_ready),.out_data(nonlinear_out_data),.out_error(nonlinear_out_error));
always #5 clk=~clk;
reg [63:0] addresses[0:95];
reg [31:0] words[0:95];
reg signed [47:0] expected[0:5];
integer cycles=0,requests=0,responses=0,outputs=0,request_cycle=-1,response_cycle=-1;
integer first_out=-1,first_done=-1,reqstalls=0,rspwait=0,outstalls=0,donestalls=0;
integer first_cmd=-1;
integer jobs=0;
reg active=0,pending=0,retired_error=0,held_cmd=0,held_out=0,held_done=0;
reg [63:0] held_addr;
reg [80:0] held_output;
task automatic sample;
begin
 if((^{start_ready,cmd_valid,cmd_addr,result_ready,mac_clear,mac_accumulate,mac_a,mac_b,
 nonlinear_valid,nonlinear_op,nonlinear_data,nonlinear_out_ready,
 out_valid,out_data,out_index,out_last,done_valid,done_error})===1'bx)
  $fatal(1,"ATTENTION_XZ");
 if(!rst_n && {start_ready,cmd_valid,cmd_addr,result_ready,mac_clear,mac_accumulate,
 mac_a,mac_b,nonlinear_valid,nonlinear_op,nonlinear_data,nonlinear_out_ready,
 out_valid,out_data,out_index,out_last,done_valid,done_error}!=='0)
  $fatal(1,"ATTENTION_RESET");
 if(!cmd_valid && cmd_addr!==0) $fatal(1,"ATTENTION_INACTIVE_ADDRESS");
 $display("P %0t %h",$time,{start_ready,cmd_valid,cmd_addr,result_ready,
 mac_clear,mac_accumulate,mac_a,mac_b,nonlinear_valid,nonlinear_op,nonlinear_data,
 nonlinear_out_ready,out_valid,out_data,out_index,out_last,done_valid,done_error});
end
endtask
initial begin addresses[0]=64'h1235b0; words[0]=32'h00555555;
addresses[1]=64'h1235b4; words[1]=32'h00aaaaaa;
addresses[2]=64'h1235b8; words[2]=32'h01000000;
addresses[3]=64'h1235bc; words[3]=32'h01555555;
addresses[4]=64'h1235c0; words[4]=32'h01aaaaaa;
addresses[5]=64'h1235c4; words[5]=32'h02000000;
addresses[6]=64'h133400; words[6]=32'h00333333;
addresses[7]=64'h133404; words[7]=32'hff999999;
addresses[8]=64'h133408; words[8]=32'h00999999;
addresses[9]=64'h13340c; words[9]=32'hff333333;
addresses[10]=64'h133410; words[10]=32'h01000000;
addresses[11]=64'h133414; words[11]=32'hfecccccc;
addresses[12]=64'h133430; words[12]=32'hff999999;
addresses[13]=64'h133434; words[13]=32'h00999999;
addresses[14]=64'h133438; words[14]=32'hff333333;
addresses[15]=64'h13343c; words[15]=32'h01000000;
addresses[16]=64'h133440; words[16]=32'hfecccccc;
addresses[17]=64'h133444; words[17]=32'h01666666;
addresses[18]=64'h133460; words[18]=32'h00999999;
addresses[19]=64'h133464; words[19]=32'hff333333;
addresses[20]=64'h133468; words[20]=32'h01000000;
addresses[21]=64'h13346c; words[21]=32'hfecccccc;
addresses[22]=64'h133470; words[22]=32'h01666666;
addresses[23]=64'h133474; words[23]=32'hfe666666;
addresses[24]=64'h133490; words[24]=32'hff333333;
addresses[25]=64'h133494; words[25]=32'h01000000;
addresses[26]=64'h133498; words[26]=32'hfecccccc;
addresses[27]=64'h13349c; words[27]=32'h01666666;
addresses[28]=64'h1334a0; words[28]=32'hfe666666;
addresses[29]=64'h1334a4; words[29]=32'h01cccccc;
addresses[30]=64'h1334c0; words[30]=32'h01000000;
addresses[31]=64'h1334c4; words[31]=32'hfecccccc;
addresses[32]=64'h1334c8; words[32]=32'h01666666;
addresses[33]=64'h1334cc; words[33]=32'hfe666666;
addresses[34]=64'h1334d0; words[34]=32'h01cccccc;
addresses[35]=64'h1334d4; words[35]=32'hfe000000;
addresses[36]=64'h133400; words[36]=32'h00333333;
addresses[37]=64'h133404; words[37]=32'hff999999;
addresses[38]=64'h133408; words[38]=32'h00999999;
addresses[39]=64'h13340c; words[39]=32'hff333333;
addresses[40]=64'h133410; words[40]=32'h01000000;
addresses[41]=64'h133414; words[41]=32'hfecccccc;
addresses[42]=64'h143400; words[42]=32'h00249249;
addresses[43]=64'h143404; words[43]=32'hffb6db6d;
addresses[44]=64'h143408; words[44]=32'hff924924;
addresses[45]=64'h14340c; words[45]=32'h00924924;
addresses[46]=64'h143410; words[46]=32'hff492492;
addresses[47]=64'h143414; words[47]=32'hff249249;
addresses[48]=64'h133430; words[48]=32'hff999999;
addresses[49]=64'h133434; words[49]=32'h00999999;
addresses[50]=64'h133438; words[50]=32'hff333333;
addresses[51]=64'h13343c; words[51]=32'h01000000;
addresses[52]=64'h133440; words[52]=32'hfecccccc;
addresses[53]=64'h133444; words[53]=32'h01666666;
addresses[54]=64'h143430; words[54]=32'hff924924;
addresses[55]=64'h143434; words[55]=32'hff6db6db;
addresses[56]=64'h143438; words[56]=32'h00b6db6d;
addresses[57]=64'h14343c; words[57]=32'hff249249;
addresses[58]=64'h143440; words[58]=32'hff000000;
addresses[59]=64'h143444; words[59]=32'h01249249;
addresses[60]=64'h133460; words[60]=32'h00999999;
addresses[61]=64'h133464; words[61]=32'hff333333;
addresses[62]=64'h133468; words[62]=32'h01000000;
addresses[63]=64'h13346c; words[63]=32'hfecccccc;
addresses[64]=64'h133470; words[64]=32'h01666666;
addresses[65]=64'h133474; words[65]=32'hfe666666;
addresses[66]=64'h143460; words[66]=32'hff492492;
addresses[67]=64'h143464; words[67]=32'h00db6db6;
addresses[68]=64'h143468; words[68]=32'hff000000;
addresses[69]=64'h14346c; words[69]=32'hfedb6db6;
addresses[70]=64'h143470; words[70]=32'h01492492;
addresses[71]=64'h143474; words[71]=32'hfe924924;
addresses[72]=64'h133490; words[72]=32'hff333333;
addresses[73]=64'h133494; words[73]=32'h01000000;
addresses[74]=64'h133498; words[74]=32'hfecccccc;
addresses[75]=64'h13349c; words[75]=32'h01666666;
addresses[76]=64'h1334a0; words[76]=32'hfe666666;
addresses[77]=64'h1334a4; words[77]=32'h01cccccc;
addresses[78]=64'h143490; words[78]=32'h01000000;
addresses[79]=64'h143494; words[79]=32'hfedb6db6;
addresses[80]=64'h143498; words[80]=32'hfeb6db6d;
addresses[81]=64'h14349c; words[81]=32'h016db6db;
addresses[82]=64'h1434a0; words[82]=32'hfe6db6db;
addresses[83]=64'h1434a4; words[83]=32'hfe492492;
addresses[84]=64'h1334c0; words[84]=32'h01000000;
addresses[85]=64'h1334c4; words[85]=32'hfecccccc;
addresses[86]=64'h1334c8; words[86]=32'h01666666;
addresses[87]=64'h1334cc; words[87]=32'hfe666666;
addresses[88]=64'h1334d0; words[88]=32'h01cccccc;
addresses[89]=64'h1334d4; words[89]=32'hfe000000;
addresses[90]=64'h1434c0; words[90]=32'hfeb6db6d;
addresses[91]=64'h1434c4; words[91]=32'hfe924924;
addresses[92]=64'h1434c8; words[92]=32'h01924924;
addresses[93]=64'h1434cc; words[93]=32'hfe492492;
addresses[94]=64'h1434d0; words[94]=32'hfe249249;
addresses[95]=64'h1434d4; words[95]=32'h02000000;
expected[0]=48'h001dadf88c5c;
expected[1]=48'hff49935e3709;
expected[2]=48'hffb68283f78e;
expected[3]=48'h001e0ad396b9;
expected[4]=48'hfeee88a12656;
expected[5]=48'hffa3798b51e6;
 #1; sample(); #11; rst_n=1;
end
always @(negedge clk) begin
 sample();
 if(rst_n) begin
  cycles=cycles+1; if(cycles>20000) $fatal(1,"ATTENTION_TIMEOUT");
  start_valid=!active && cycles>2;
  if(cmd_valid && first_cmd<0) first_cmd=cycles;
  cmd_ready=first_cmd>=0 && cycles>first_cmd+4 && cycles%9>=4;
  result_valid=pending && cycles>=response_cycle;
  if(out_valid && first_out<0) first_out=cycles;
  out_ready=first_out>=0 && cycles>first_out+8 && cycles%3==0;
  if(done_valid && first_done<0) first_done=cycles;
  done_ready=first_done>=0 && cycles>first_done+9;
  if(active) begin
   start_tokens=0; start_query=99; start_head=99; start_full=!1;
   qb=64'hbad; kb=64'hbad; vb=64'hbad; pb=64'hbad; mb=64'hbad;
  end
  if(0) begin
   rst_n=0; start_valid=0; result_valid=0; pending=0;
   #1; sample(); #11; rst_n=1;
   #10; if(start_ready!==1 || cmd_valid!==0 || out_valid!==0 || done_valid!==0)
    $fatal(1,"ATTENTION_RESET_RESUMED");
   $display("ATTENTION_RESET_COMPLETE "); $finish;
  end
 end
end
always @(posedge clk) begin
 sample();
 if(rst_n) begin
  if(held_cmd && (!cmd_valid || cmd_addr!==held_addr)) $fatal(1,"ATTENTION_CMD_STALL");
  if(held_out && (!out_valid || {out_data,out_index,out_last}!==held_output))
   $fatal(1,"ATTENTION_OUT_STALL");
  if(held_done && (!done_valid || done_error!==4'd0))
   $fatal(1,"ATTENTION_DONE_STALL");
  held_cmd=cmd_valid && !cmd_ready; held_addr=cmd_addr;
  held_out=out_valid && !out_ready; held_output={out_data,out_index,out_last};
  held_done=done_valid && !done_ready;
  if(held_cmd) reqstalls=reqstalls+1;
  if(pending && !result_valid) rspwait=rspwait+1;
  if(held_out) outstalls=outstalls+1;
  if(held_done) donestalls=donestalls+1;
  if(start_valid && start_ready) begin
   if(active) $fatal(1,"ATTENTION_DUPLICATE_START"); active=1;
   $display("H START");
  end
  if(result_valid && result_ready) begin
   if(!pending || cycles<=request_cycle) $fatal(1,"ATTENTION_RESPONSE");
   pending=0; responses=responses+1;
   $display("H RESPONSE %h %b",result_data,result_error);
   if(result_error) retired_error=1;
  end
  if(retired_error && cmd_valid) $fatal(1,"ATTENTION_AFTER_ERROR");
  if(cmd_valid && cmd_ready) begin
   if(!active || pending || requests>=96 || cmd_addr!==addresses[requests])
    $fatal(1,"ATTENTION_REQUEST_ORDER %0d %h",requests,cmd_addr);
   request_cycle=cycles; response_cycle=cycles+3+requests%4; pending=1;
   $display("H REQUEST %h",cmd_addr);
   result_data=words[requests]; result_error=requests==-1; requests=requests+1;
  end
  if(out_valid) begin
   if(0 || outputs>=6 || out_index!==outputs ||
      out_last!==(outputs==5) || out_data!==expected[outputs])
    $fatal(1,"ATTENTION_EXPECTED_OUTPUT %0d %h",outputs,out_data);
   if(out_ready) begin
    $display("H OUTPUT %h %0d %b",out_data,out_index,out_last);
    outputs=outputs+1;
   end
  end
  if(done_valid && done_ready) begin
   if(pending || requests!=96 || responses!=requests ||
      outputs!=6 || done_error!==4'd0 ||
      reqstalls==0 || rspwait==0 || donestalls<9 ||
      (1 && outstalls<8))
    $fatal(1,"ATTENTION_COMPLETION");
   $display("H DONE %0d %0d %0d %0d",requests,responses,outputs,done_error);
   jobs=jobs+1;
   if(jobs==1) begin
    $display("ATTENTION_COMPLETE %0d %0d %0d",requests,responses,outputs); $finish;
   end else begin
    active=0; requests=0; responses=0; outputs=0;
    first_cmd=-1; first_out=-1; first_done=-1;
    reqstalls=0; rspwait=0; outstalls=0; donestalls=0;
    held_cmd=0; held_out=0; held_done=0;
    start_tokens=5; start_query=4; start_head=2; start_full=1;
    qb=64'h123400; kb=64'h133400; vb=64'h143400;
    pb=64'h153400; mb=64'h163400;
   end
  end
 end
 #1; sample();
end
endmodule
