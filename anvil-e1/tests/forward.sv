module forward;
    parameter VOCAB_SIZE=16, HIDDEN_SIZE=4, PER_LAYER_INPUT_SIZE=4,
        INTERMEDIATE_SIZE=8, EMBEDDING_DIM=6, NUM_LAYERS=6, NUM_Q_HEADS=2,
        LOCAL_KV_HEADS=1, FULL_KV_HEADS=1, LOCAL_HEAD_DIM=2,
        FULL_HEAD_DIM=4, SLIDING_WINDOW=2, MAX_SEQ_LEN=8;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n;
    reg job_valid=0, mem_req_ready=0, mem_rsp_valid=0;
    reg emb_ready=0, done_ready=0, mem_rsp_error=0;
    reg [31:0] job_tokens=0, mem_rsp_rdata=0;
    reg [15:0] job_output_dim=0;
    reg [63:0] weights_base=0, tokens_base=0, positions_base=0,
        mask_base=0, scratch_base=0;
    wire job_ready, mem_req_valid, mem_req_write, mem_rsp_ready,
        emb_valid, emb_last, done_valid, busy;
    wire [63:0] mem_req_addr;
    wire [31:0] mem_req_wdata;
    wire signed [31:0] emb_data;
    wire [15:0] emb_index;
    wire [3:0] done_error;
`ifdef OFFICIAL_WRAPPER
    anvil_e_top #(
`else
    anvil_e1_top #(
`endif
        .VOCAB_SIZE(VOCAB_SIZE), .HIDDEN_SIZE(HIDDEN_SIZE),
        .PER_LAYER_INPUT_SIZE(PER_LAYER_INPUT_SIZE),
        .INTERMEDIATE_SIZE(INTERMEDIATE_SIZE), .EMBEDDING_DIM(EMBEDDING_DIM),
        .NUM_LAYERS(NUM_LAYERS), .NUM_Q_HEADS(NUM_Q_HEADS),
        .LOCAL_KV_HEADS(LOCAL_KV_HEADS), .FULL_KV_HEADS(FULL_KV_HEADS),
        .LOCAL_HEAD_DIM(LOCAL_HEAD_DIM), .FULL_HEAD_DIM(FULL_HEAD_DIM),
        .SLIDING_WINDOW(SLIDING_WINDOW), .MAX_SEQ_LEN(MAX_SEQ_LEN)
    ) dut(.*);
    reg [31:0] memory [0:262143];
    integer cycle=0, jobid=-1, jobs=0, requests=0, pending=0, delay_left=0;
    integer fault_request=-1, reset_mode=0, job_start=0, random_seed=17;
    integer fd, scanned, jn, jd, fault, reset, n;
    reg [63:0] wb, tb, pb, mb, sb;
    string image_path, jobs_path;
    reg req_held=0, emb_held=0, done_held=0;
    reg [96:0] held_request;
    reg [48:0] held_embedding;
    reg [3:0] held_completion;
    reg active=0;
    integer coverage [0:15];
    integer ci;
    integer profile_cycles=0, profile_quiet=0, profile_fd=0, profile_capture=1;
    integer profile_state_changes=0, profile_address_changes=0;
    reg [4:0] profile_last_state;
    reg [199:0] profile_last_address;
    string profile_path;
    wire [155:0] outputs={job_ready,mem_req_valid,mem_req_write,mem_req_addr,
        mem_req_wdata,mem_rsp_ready,emb_valid,emb_data,emb_index,emb_last,
        done_valid,done_error,busy};
    always @(posedge clk or negedge clk) begin
        if (!rst_n && outputs !== 156'd0) $fatal(1,"RESET_OUTPUT");
        if (rst_n && (^outputs) === 1'bx) $fatal(1,"ACTIVE_XZ");
    end
    always @(posedge clk) begin
        cycle=cycle+1;
        if(cycle>12000000) $fatal(1,"WATCHDOG");
        if(rst_n) begin
            if(active && (!busy || job_ready)) $fatal(1,"JOB_LIFETIME");
            if(!active && busy) $fatal(1,"IDLE_BUSY");
            if(job_valid && job_ready) begin
                if(active) $fatal(1,"DESCRIPTOR_OVERLAP");
                active=1;
                $display("JOB %0d %0d",jobid,cycle);
            end
            if(mem_req_valid && !mem_req_ready) coverage[0]=coverage[0]+1;
            if(pending && !mem_rsp_valid) coverage[1]=coverage[1]+1;
            if(emb_valid && !emb_ready) coverage[2]=coverage[2]+1;
            if(done_valid && !done_ready) coverage[3]=coverage[3]+1;
            if(job_valid && !job_ready) coverage[4]=coverage[4]+1;
            if(mem_req_valid && mem_req_ready && !mem_req_write) coverage[5]=coverage[5]+1;
            if(mem_req_valid && mem_req_ready && mem_req_write) coverage[6]=coverage[6]+1;
            if(mem_rsp_valid && mem_rsp_ready && !mem_rsp_error) coverage[7]=coverage[7]+1;
            if(mem_rsp_valid && mem_rsp_ready && mem_rsp_error) coverage[8]=coverage[8]+1;
            if(emb_valid && emb_ready) coverage[9]=coverage[9]+1;
            if(emb_valid && emb_ready && emb_last) coverage[10]=coverage[10]+1;
            if(done_valid && done_ready && done_error==0) coverage[11]=coverage[11]+1;
            if(done_valid && done_ready && done_error!=0) coverage[12]=coverage[12]+1;
            if(req_held && (!mem_req_valid ||
                {mem_req_write,mem_req_addr,mem_req_wdata} !== held_request))
                $fatal(1,"REQUEST_STABILITY");
            if(emb_held && (!emb_valid ||
                {emb_data,emb_index,emb_last} !== held_embedding))
                $fatal(1,"EMBEDDING_STABILITY");
            if(done_held && (!done_valid || done_error !== held_completion))
                $fatal(1,"COMPLETION_STABILITY");
            req_held=mem_req_valid && !mem_req_ready;
            emb_held=emb_valid && !emb_ready;
            done_held=done_valid && !done_ready;
            held_request={mem_req_write,mem_req_addr,mem_req_wdata};
            held_embedding={emb_data,emb_index,emb_last};
            held_completion=done_error;
            if(mem_rsp_ready && !pending) $fatal(1,"RESPONSE_WITHOUT_REQUEST");
            if(mem_rsp_valid && mem_rsp_ready) begin
                if (!profile_quiet)
                    $display("RSP %0d %0d %0d %0d",jobid,cycle,mem_rsp_rdata,mem_rsp_error);
                pending=0;
            end
            if(mem_req_valid && mem_req_ready) begin
                if(pending) $fatal(1,"MULTIPLE_OUTSTANDING");
                if(mem_rsp_ready) $fatal(1,"EARLY_RESPONSE_READY");
                if(mem_req_addr[1:0]!=0 || mem_req_addr>=1048576)
                    $fatal(1,"UNMAPPED_ADDRESS %h",mem_req_addr);
                pending=1; delay_left=(cycle+random_seed)%4+1;
                mem_rsp_error=requests==fault_request;
                mem_rsp_rdata=mem_req_write ? 0:memory[mem_req_addr>>2];
                if(mem_req_write && !mem_rsp_error)
                    memory[mem_req_addr>>2]=mem_req_wdata;
                if (!profile_quiet) $display("REQ %0d %0d %0d %0d %0d",jobid,cycle,
                    mem_req_write,mem_req_addr,mem_req_wdata);
                requests=requests+1;
            end
            if(emb_valid && emb_ready)
                $display("EMB %0d %0d %0d %0d %0d",jobid,cycle,
                    emb_index,$signed(emb_data),emb_last);
            if(done_valid && done_ready) begin
                $display("DONE %0d %0d %0d",jobid,cycle,done_error);
                active=0;
            end
        end
    end
    always @(negedge clk) begin
`ifdef INTERNAL_PROFILE
        if (profile_cycles>0) begin
            if (profile_capture) $fdisplay(profile_fd,"%h %h %0d %0d %0d %0d",
                dut.legal_datapath.sequencer.weights,
                dut.legal_datapath.sequencer.scratch,
                dut.legal_datapath.sequencer.tokens,
                dut.legal_datapath.sequencer.tensor_id,
                dut.legal_datapath.sequencer.layer,
                dut.legal_datapath.sequencer.base_index);
            if (dut.legal_datapath.sequencer.state !== profile_last_state)
                profile_state_changes=profile_state_changes+1;
            profile_last_state=dut.legal_datapath.sequencer.state;
            if ({dut.legal_datapath.sequencer.weights,
                 dut.legal_datapath.sequencer.scratch,
                 dut.legal_datapath.sequencer.tokens,
                 dut.legal_datapath.sequencer.tensor_id,
                 dut.legal_datapath.sequencer.layer,
                 dut.legal_datapath.sequencer.base_index} !== profile_last_address)
                profile_address_changes=profile_address_changes+1;
            profile_last_address={dut.legal_datapath.sequencer.weights,
                dut.legal_datapath.sequencer.scratch,
                dut.legal_datapath.sequencer.tokens,
                dut.legal_datapath.sequencer.tensor_id,
                dut.legal_datapath.sequencer.layer,
                dut.legal_datapath.sequencer.base_index};
            if (cycle==profile_cycles) begin
                $display("PROFILE_COMPLETE cycles=%0d state_changes=%0d address_changes=%0d",
                    cycle,profile_state_changes,profile_address_changes);
                $fclose(profile_fd);
                $finish;
            end
        end
`endif
        if(rst_n) begin
            mem_req_ready=(cycle+random_seed)%5!=0;
            emb_ready=reset_mode==3 ? 0:(cycle+random_seed)%7>=3;
            done_ready=(cycle+random_seed)%9>=4;
            if(pending) begin
                if(delay_left>0) delay_left=delay_left-1;
                mem_rsp_valid=delay_left==0;
            end else begin
                mem_rsp_valid=0; mem_rsp_error=0; mem_rsp_rdata=0;
            end
        end else begin
            pending=0; mem_rsp_valid=0; mem_req_ready=0;
            emb_ready=0; done_ready=0;
            req_held=0; emb_held=0; done_held=0;
            active=0;
        end
    end
    task automatic reset_dut;
        begin
            rst_n=0; job_valid=0;
            #1;
            if(outputs !== 156'd0) $fatal(1,"ASYNC_RESET_OUTPUT");
            repeat(3) @(negedge clk);
            #1; rst_n=1;
        end
    endtask
    initial begin
        rst_n=0;
        for(ci=0;ci<16;ci=ci+1) coverage[ci]=0;
        #1;
        if(outputs !== 156'd0) $fatal(1,"TIME_ZERO_RESET");
        if(!$value$plusargs("image=%s",image_path) ||
           !$value$plusargs("jobs=%s",jobs_path)) $fatal(1,"MISSING_INPUT");
        n=$value$plusargs("seed=%d",random_seed);
        n=$value$plusargs("profile_cycles=%d",profile_cycles);
        n=$value$plusargs("profile_quiet=%d",profile_quiet);
        n=$value$plusargs("profile_capture=%d",profile_capture);
        if (profile_cycles>0) begin
            if (!$value$plusargs("profile_file=%s",profile_path))
                $fatal(1,"MISSING_PROFILE_FILE");
            profile_fd=$fopen(profile_path,"w");
            if (!profile_fd) $fatal(1,"OPEN_PROFILE_FILE");
        end
        for(n=0;n<262144;n=n+1) memory[n]=0;
        $readmemh(image_path,memory);
        fd=$fopen(jobs_path,"r");
        if(!fd) $fatal(1,"OPEN_JOBS");
        reset_dut;
        scanned=$fscanf(fd,"%d %d %d %h %h %h %h %h %d %d\n",
            jobid,jn,jd,wb,tb,pb,mb,sb,fault,reset);
        while(scanned==10) begin
            while(job_ready!==1) @(negedge clk);
            #1;
            job_tokens=jn; job_output_dim=jd; weights_base=wb;
            tokens_base=tb; positions_base=pb; mask_base=mb; scratch_base=sb;
            requests=0; fault_request=fault; reset_mode=reset; job_start=cycle;
            job_valid=1;
            @(posedge clk);
            @(negedge clk); #1; job_valid=0;
            job_tokens=32'hffffffff; job_output_dim=0;
            weights_base=64'hffffffffffffffff; tokens_base=0;
            positions_base=0; mask_base=0; scratch_base=0;
            // A presented second descriptor must not be accepted while busy.
            job_valid=1;
            @(negedge clk); #1; job_valid=0;
            if(reset_mode!=0) begin
                if(reset_mode==1) wait(mem_req_valid);
                else if(reset_mode==2) repeat(120) @(negedge clk);
                else if(reset_mode==3) wait(emb_valid);
                else $fatal(1,"INVALID_RESET_MODE");
                @(negedge clk); #1;
                $display("ABORT %0d %0d",jobid,cycle);
                if(reset_mode==1) begin
                    if(!mem_req_valid && !pending) $fatal(1,"RESET_REQUEST_NOT_OBSERVED");
                    coverage[13]=coverage[13]+1;
                end
                if(reset_mode==2) begin
                    if(!busy || emb_valid || done_valid || requests==0)
                        $fatal(1,"RESET_COMPUTE_NOT_OBSERVED");
                    coverage[14]=coverage[14]+1;
                end
                if(reset_mode==3) begin
                    if(!emb_valid) $fatal(1,"RESET_OUTPUT_NOT_OBSERVED");
                    coverage[15]=coverage[15]+1;
                end
                reset_dut;
            end else begin
                do @(posedge clk); while(!(done_valid && done_ready));
                @(negedge clk); #1;
            end
            jobs=jobs+1;
            scanned=$fscanf(fd,"%d %d %d %h %h %h %h %h %d %d\n",
                jobid,jn,jd,wb,tb,pb,mb,sb,fault,reset);
        end
        if(scanned!=-1 || jobs==0) $fatal(1,"INCOMPLETE_JOBS");
        $write("COVER");
        for(ci=0;ci<16;ci=ci+1) $write(" %0d",coverage[ci]);
        $write("\n");
        $display("COMPLETE %0d",jobs);
        $finish;
    end
endmodule
