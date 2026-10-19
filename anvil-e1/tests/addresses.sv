module addresses;
    parameter VOCAB_SIZE=16, HIDDEN_SIZE=4, PER_LAYER_INPUT_SIZE=4,
        INTERMEDIATE_SIZE=8, EMBEDDING_DIM=6, NUM_LAYERS=6, NUM_Q_HEADS=2,
        LOCAL_KV_HEADS=1, FULL_KV_HEADS=1, LOCAL_HEAD_DIM=2, FULL_HEAD_DIM=4;
    reg [63:0] weights_base, scratch_base, element_index, scratch_word;
    reg [31:0] job_tokens, layer_index;
    reg [4:0] tensor_id;
    reg [2:0] scratch_region;
    wire [63:0] tensor_addr, scratch_addr;
    wire [31:0] tensor_rows, tensor_cols;
    wire [127:0] weights_bytes, scratch_bytes;
    wire tensor_error, scratch_error;
    anvil_e1_address #(
        .VOCAB_SIZE(VOCAB_SIZE), .HIDDEN_SIZE(HIDDEN_SIZE),
        .PER_LAYER_INPUT_SIZE(PER_LAYER_INPUT_SIZE),
        .INTERMEDIATE_SIZE(INTERMEDIATE_SIZE), .EMBEDDING_DIM(EMBEDDING_DIM),
        .NUM_LAYERS(NUM_LAYERS), .NUM_Q_HEADS(NUM_Q_HEADS),
        .LOCAL_KV_HEADS(LOCAL_KV_HEADS), .FULL_KV_HEADS(FULL_KV_HEADS),
        .LOCAL_HEAD_DIM(LOCAL_HEAD_DIM), .FULL_HEAD_DIM(FULL_HEAD_DIM)
    ) dut(.*);
    integer fd, scanned, tag, count=0;
    string path;
    initial begin
        if (!$value$plusargs("input=%s",path)) $fatal(1,"MISSING_INPUT");
        fd=$fopen(path,"r");
        if(!fd) $fatal(1,"OPEN_INPUT");
        scanned=$fscanf(fd,"%d %h %h %d %d %d %h %d %h\n",
            tag,weights_base,scratch_base,job_tokens,tensor_id,layer_index,
            element_index,scratch_region,scratch_word);
        while(scanned==9) begin
            #1;
            if ((^{tensor_addr,scratch_addr,tensor_rows,tensor_cols,
                weights_bytes,scratch_bytes,tensor_error,scratch_error}) === 1'bx)
                $fatal(1,"ADDRESS_XZ");
            $display("ADDRESS %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d",
                tag,tensor_addr,tensor_rows,tensor_cols,tensor_error,
                scratch_addr,scratch_error,weights_bytes,scratch_bytes,count);
            count=count+1;
            scanned=$fscanf(fd,"%d %h %h %d %d %d %h %d %h\n",
                tag,weights_base,scratch_base,job_tokens,tensor_id,layer_index,
                element_index,scratch_region,scratch_word);
        end
        if(scanned!=-1 || count==0) $fatal(1,"INCOMPLETE_INPUT");
        $display("COMPLETE %0d",count);
        $finish;
    end
endmodule
