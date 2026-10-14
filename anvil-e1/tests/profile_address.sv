module profile_address;
    parameter VOCAB_SIZE=16, HIDDEN_SIZE=4, PER_LAYER_INPUT_SIZE=4,
        INTERMEDIATE_SIZE=8, EMBEDDING_DIM=6, NUM_LAYERS=24,
        NUM_Q_HEADS=4, LOCAL_KV_HEADS=2, FULL_KV_HEADS=1,
        LOCAL_HEAD_DIM=2, FULL_HEAD_DIM=4, EVALUATE=1;
    reg [63:0] weights_base, scratch_base, element_index=0, scratch_word=0;
    reg [31:0] job_tokens, layer_index;
    reg [4:0] tensor_id;
    reg [2:0] scratch_region;
    wire [63:0] tensor_addr, scratch_addr;
    wire [31:0] tensor_rows, tensor_cols;
    wire [127:0] weights_bytes, scratch_bytes;
    wire tensor_error, scratch_error;
    generate if (EVALUATE) begin
    anvil_e1_address #(
        .VOCAB_SIZE(VOCAB_SIZE), .HIDDEN_SIZE(HIDDEN_SIZE),
        .PER_LAYER_INPUT_SIZE(PER_LAYER_INPUT_SIZE),
        .INTERMEDIATE_SIZE(INTERMEDIATE_SIZE), .EMBEDDING_DIM(EMBEDDING_DIM),
        .NUM_LAYERS(NUM_LAYERS), .NUM_Q_HEADS(NUM_Q_HEADS),
        .LOCAL_KV_HEADS(LOCAL_KV_HEADS), .FULL_KV_HEADS(FULL_KV_HEADS),
        .LOCAL_HEAD_DIM(LOCAL_HEAD_DIM), .FULL_HEAD_DIM(FULL_HEAD_DIM)
    ) dut(.*);
    end else begin
        assign tensor_addr=0;
        assign scratch_addr=0;
        assign tensor_rows=0;
        assign tensor_cols=0;
        assign weights_bytes=0;
        assign scratch_bytes=0;
        assign tensor_error=0;
        assign scratch_error=0;
    end endgenerate
    reg [1023:0] input_path;
    integer fd, count=0, scanned;
    initial begin
        if (!$value$plusargs("input=%s",input_path)) $fatal(1,"MISSING_INPUT");
        fd=$fopen(input_path,"r");
        if (!fd) $fatal(1,"OPEN_INPUT");
        scanned=$fscanf(fd,"%h %h %d %d %d %d\n",
            weights_base,scratch_base,job_tokens,tensor_id,layer_index,scratch_region);
        while (scanned==6) begin
            #10;
            if ((^{tensor_addr,scratch_addr,weights_bytes,scratch_bytes})===1'bx)
                $fatal(1,"ADDRESS_XZ");
            count=count+1;
            scanned=$fscanf(fd,"%h %h %d %d %d %d\n",
                weights_base,scratch_base,job_tokens,tensor_id,layer_index,scratch_region);
        end
        if (scanned!=-1 || count!=100000) $fatal(1,"INCOMPLETE_PROFILE %d",count);
        $display("PROFILE_ADDRESS_COMPLETE %0d",count);
        $finish;
    end
endmodule
