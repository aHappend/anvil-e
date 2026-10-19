
module tb;
reg clk=0;
reg rst_n=0;
always #5 clk=~clk;
reg job_valid=0;
reg [1:0] job_mode=1;
reg [31:0] job_tokens=0,job_patch_rows=1,job_patch_cols=1;
reg [15:0] job_output_dim=2;
reg [63:0] weights_base=64'h10000000;
reg [63:0] vision_weights_base=64'h20000000;
reg [63:0] image_base=64'h30000000;
reg [63:0] tokens_base=64'h40000000;
reg [63:0] positions_base=64'h50000000;
reg [63:0] mask_base=64'h60000000;
reg [63:0] scratch_base=64'h70000000;
reg mem_req_ready=0,mem_rsp_valid=0,mem_rsp_error=0,emb_ready=0,done_ready=0;
reg [31:0] mem_rsp_rdata=0;
wire job_ready,mem_req_valid,mem_req_write,mem_rsp_ready,emb_valid,emb_last,done_valid,busy;
wire [63:0] mem_req_addr;
wire [31:0] mem_req_wdata;
wire signed [31:0] emb_data;
wire [15:0] emb_index;
wire [3:0] done_error;
anvil_e2_top #(.VISION_LAYERS(1), .VISION_HIDDEN(4), .VISION_FFN(1), .VISION_HEADS(1), .VISION_HEAD_DIM(4), .PATCH_SIZE(1), .POOL_KERNEL(1), .VISION_SOFT_TOKENS(1), .TEXT_LAYERS(1), .TEXT_HIDDEN(1), .PLE_DIM(1), .TEXT_FFN(1), .EMBED_DIM(6), .VOCAB_SIZE(262144), .POSITION_EMBEDDING_SIZE(10240), .TEXT_Q_HEADS(4), .LOCAL_KV_HEADS(2), .FULL_KV_HEADS(1), .LOCAL_HEAD_DIM(2), .FULL_HEAD_DIM(4), .SLIDING_WINDOW(1), .MAX_SEQ_LEN(262144)) dut (.clk(clk),.rst_n(rst_n),.job_valid(job_valid),.job_mode(job_mode),.job_tokens(job_tokens),.job_patch_rows(job_patch_rows),.job_patch_cols(job_patch_cols),.job_output_dim(job_output_dim),.weights_base(weights_base),.vision_weights_base(vision_weights_base),.image_base(image_base),.tokens_base(tokens_base),.positions_base(positions_base),.mask_base(mask_base),.scratch_base(scratch_base),.mem_req_ready(mem_req_ready),.mem_rsp_valid(mem_rsp_valid),.mem_rsp_rdata(mem_rsp_rdata),.mem_rsp_error(mem_rsp_error),.emb_ready(emb_ready),.done_ready(done_ready),.job_ready(job_ready),.mem_req_valid(mem_req_valid),.mem_req_write(mem_req_write),.mem_req_addr(mem_req_addr),.mem_req_wdata(mem_req_wdata),.mem_rsp_ready(mem_rsp_ready),.emb_valid(emb_valid),.emb_data(emb_data),.emb_index(emb_index),.emb_last(emb_last),.done_valid(done_valid),.done_error(done_error),.busy(busy));
localparam WORDS=135;
reg [31:0] scratch [0:WORDS-1];
reg initialized [0:WORDS-1];
reg [63:0] addresses [0:176];
reg [31:0] values [0:176];
integer fd,rc,i,lo,hi,mid,entry,count=0,cycles=0;
integer requests=0,responses=0,beats=0,reqstalls=0,rspstalls=0,embstalls=0,donestalls=0;
integer accept_cycle=-1,final_cycle=-1,completion_cycle=-1,response_at=0,completed_jobs=0;
integer first_output=-1,first_done=-1;
integer first_embedding_cycle=-1;
reg pending=0,stalled_request=0,stalled_embedding=0,stalled_done=0;
reg [96:0] held_request;
reg [48:0] held_embedding;
reg [3:0] held_error;
reg active=0, reset_done=0, injected=0, error_retired=0;
reg [31:0] read_value;
task automatic known;
begin
 if ((^{job_ready,mem_req_valid,mem_req_write,mem_req_addr,mem_req_wdata,mem_rsp_ready,emb_valid,emb_data,emb_index,emb_last,done_valid,done_error,busy})===1'bx) $fatal(1,"UNKNOWN_PUBLIC cycle=%0d",cycles);
 if (!rst_n && {job_ready,mem_req_valid,mem_req_write,mem_req_addr,mem_req_wdata,mem_rsp_ready,emb_valid,emb_data,emb_index,emb_last,done_valid,done_error,busy} !== '0) $fatal(1,"RESET_OUTPUT cycle=%0d",cycles);
end
endtask
initial begin
 for(i=0;i<WORDS;i=i+1) initialized[i]=0;
 fd=$fopen("/data/sufeng/anvil-e2-line4/workspace_phase2/project/evidence/verification/functional/1792408168716575019-1542535/A-s17-m1-d2.mem","r");
 if(fd==0) $fatal(1,"MEMORY_FILE");
 while(!$feof(fd)) begin
  rc=$fscanf(fd,"%h %h\n",addresses[count],values[count]);
  if(rc==2) count=count+1;
 end
 $fclose(fd);
 if(count!=177) $fatal(1,"MEMORY_LENGTH");
 #0; known(); #1; known();
 #11; rst_n=1;
end
always @(negedge clk) begin
 known();
 if(rst_n) begin
  cycles=cycles+1;
  if(cycles>3000000) $fatal(1,"INCOMPLETE_TRANSCRIPT");
  if(!active && !reset_done && cycles>3) job_valid=1;
  if(cycles<=3 && (job_ready!==1 || busy!==0 || mem_req_valid!==0 || done_valid!==0))
    $fatal(1,"AUTONOMOUS_JOB");
  if(active && job_ready) $fatal(1,"READY_WHILE_BUSY");
  mem_req_ready=0 || (cycles%7!=0 && cycles%7!=1 && cycles%7!=2);
  if(emb_valid && first_output<0) first_output=cycles;
  if(done_valid && first_done<0) first_done=cycles;
  emb_ready=0 || (first_output>=0 && cycles>first_output+25 && cycles%41>=17);
  done_ready=0 || (first_done>=0 && cycles>first_done+25 && cycles%43>=19);
  mem_rsp_valid=pending && cycles>=response_at;
  if(0 && !reset_done) begin
   rst_n=0; job_valid=0; mem_rsp_valid=0; pending=0; reset_done=1;
   #1; known();
   $display("RESET_OBSERVED None"); #11;
   rst_n=1; #10;
   if(job_ready!==1 || busy!==0 || emb_valid!==0 || done_valid!==0 || mem_req_valid!==0)
     $fatal(1,"CANCELED_JOB_RESUMED");
   $display("RESET_COMPLETE"); $finish;
  end
 end
end
always @(posedge clk) begin
 known();
 if(rst_n) begin
  if(stalled_request && (!mem_req_valid ||
     {mem_req_write,mem_req_addr,mem_req_wdata}!==held_request))
    $fatal(1,"REQUEST_STABILITY");
  if(stalled_embedding && (!emb_valid ||
     {emb_data,emb_index,emb_last}!==held_embedding))
    $fatal(1,"EMBEDDING_STABILITY");
  if(stalled_done && (!done_valid || done_error!==held_error))
    $fatal(1,"COMPLETION_STABILITY");
  stalled_request=mem_req_valid && !mem_req_ready;
  held_request={mem_req_write,mem_req_addr,mem_req_wdata};
  stalled_embedding=emb_valid && !emb_ready;
  held_embedding={emb_data,emb_index,emb_last};
  stalled_done=done_valid && !done_ready; held_error=done_error;
  if(stalled_request) reqstalls=reqstalls+1;
  if(stalled_embedding) embstalls=embstalls+1;
  if(stalled_done) donestalls=donestalls+1;
  if(mem_rsp_valid && !mem_rsp_ready) rspstalls=rspstalls+1;
  if(job_valid && job_ready) begin
   if(active) $fatal(1,"DUPLICATE_JOB");
   accept_cycle=cycles; active=1;
  end
  if(mem_req_valid && cycles<=accept_cycle+1) $fatal(1,"EARLY_REQUEST");
  if(mem_rsp_valid && mem_rsp_ready) begin
   if(!pending || cycles<response_at) $fatal(1,"RESPONSE_PROTOCOL");
   pending=0; responses=responses+1;
   if(mem_rsp_error) error_retired=1;
  end
  if(error_retired && mem_req_valid) $fatal(1,"REQUEST_AFTER_ERROR");
  if(mem_req_valid && mem_req_ready) begin
   if(pending) $fatal(1,"MULTIPLE_OUTSTANDING");
   if(mem_req_addr[1:0]!==0) $fatal(1,"UNALIGNED");
   pending=1; response_at=cycles+(2+(requests%3)); requests=requests+1;
   mem_rsp_error=0; read_value=0;
   if(0 && !injected) begin
    mem_rsp_error=1; injected=1;
    $display("I %h",mem_req_addr);
   end
   if(mem_req_write) begin
    if(mem_req_addr<64'h70000000 ||
       mem_req_addr>=64'h7000021c) $fatal(1,"UNEXPECTED_WRITE");
    entry=(mem_req_addr-64'h70000000)/4;
    if(!mem_rsp_error) begin
     scratch[entry]=mem_req_wdata; initialized[entry]=1;
     $display("W %h %h",mem_req_addr,mem_req_wdata);
    end
   end else if(mem_req_addr>=64'h70000000 &&
               mem_req_addr<64'h7000021c) begin
    entry=(mem_req_addr-64'h70000000)/4;
    if(!initialized[entry]) $fatal(1,"UNINITIALIZED_READ %h",mem_req_addr);
    read_value=scratch[entry];
   end else begin
    lo=0; hi=count-1; entry=-1;
    while(lo<=hi) begin
     mid=(lo+hi)/2;
     if(addresses[mid]==mem_req_addr) begin entry=mid; lo=hi+1; end
     else if(addresses[mid]<mem_req_addr) lo=mid+1;
     else hi=mid-1;
    end
    if(entry<0) $fatal(1,"UNEXPECTED_READ %h",mem_req_addr);
    read_value=values[entry];
   end
   mem_rsp_rdata=read_value;
  end
  if(emb_valid && emb_ready) begin
   if(!active || done_valid || pending) $fatal(1,"OUTPUT_PHASE");
   if(emb_index!==beats || emb_last!==(beats==2-1)) $fatal(1,"OUTPUT_SHAPE");
   $display("E %0d %h %0d",emb_index,emb_data,emb_last);
   if(beats==0) first_embedding_cycle=cycles;
   beats=beats+1;
   if(emb_last) final_cycle=cycles;
  end
  if(done_valid && done_ready) begin
   if(!active || pending || done_error!==4'd0) $fatal(1,"DONE_ERROR %d",done_error);
   if(0 && (!injected || !error_retired))
     $fatal(1,"MISSING_ERROR_INJECTION");
   if(0==0 && (beats!=2 || cycles<=final_cycle)) $fatal(1,"COMPLETION_ORDER");
   if(0!=0 && beats!=0) $fatal(1,"ERROR_EMBEDDING");
   if(requests!=responses) $fatal(1,"UNRETIRED_TRANSACTION");
   $display("C %0d %0d %0d %0d %0d %0d %0d %0d",
     done_error,requests,responses,beats,reqstalls,rspstalls,embstalls,donestalls);
   completion_cycle=cycles;
   $display("T %0d %0d %0d %0d",accept_cycle,first_embedding_cycle,final_cycle,completion_cycle);
   completed_jobs=completed_jobs+1;
   #1;
   if(job_ready!==1 || busy!==0 || done_valid!==0) $fatal(1,"DONE_IDLE");
   if(completed_jobs==1) begin
    $display("TRANSCRIPT_COMPLETE"); $finish;
   end
   active=0; beats=0; final_cycle=-1;
   first_output=-1; first_done=-1; first_embedding_cycle=-1;
   stalled_done=0;
  end
  #1;
  if(active) job_valid=0;
  if(cycles==accept_cycle && (busy!==1 || job_ready!==0 || mem_req_valid!==0))
    $fatal(1,"POST_ACCEPT");
 end
end
endmodule
