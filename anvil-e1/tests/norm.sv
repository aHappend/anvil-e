module norm;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n;
    reg start_valid=0, start_l2=0, in_valid=0, out_ready=0;
    reg [31:0] start_count=0;
    reg signed [31:0] in_data=0, in_weight=0;
    wire start_ready, in_ready, out_valid, out_last, out_error;
    wire signed [31:0] out_data;
    wire [31:0] out_index;
    anvil_e1_norm #(.MAX_WIDTH(16)) dut(.*);
    integer input_file, scan, tag, mode, count, value, weight;
    integer i, jobs=0, cycles=0;
    reg [1023:0] input_path;
    reg [66:0] held;
    always @(posedge clk or negedge clk) begin
        if (!rst_n &&
            {start_ready,in_ready,out_valid,out_data,out_index,out_last,out_error} !== 69'd0)
            $fatal(1,"NORM_RESET_XZ_OR_NONZERO");
        if (rst_n &&
            (^{start_ready,in_ready,out_valid,out_data,out_index,out_last,out_error}) === 1'bx)
            $fatal(1,"NORM_ACTIVE_XZ");
    end
    always @(posedge clk) begin
        cycles=cycles+1;
        if(cycles>100000) $fatal(1,"NORM_WATCHDOG");
    end
    initial begin
        rst_n=0;
        #1;
        if ({start_ready,in_ready,out_valid,out_data,out_index,out_last,out_error} !== 69'd0)
            $fatal(1,"NORM_TIME_ZERO_RESET");
        repeat(3) @(negedge clk);
        rst_n=1;
        if(!$value$plusargs("input=%s",input_path)) $fatal(1,"NORM_MISSING_INPUT");
        input_file=$fopen(input_path,"r");
        if(!input_file) $fatal(1,"NORM_OPEN_INPUT");
        scan=$fscanf(input_file,"%d %d %d\n",tag,mode,count);
        while(scan==3) begin
            while(start_ready!==1'b1) @(negedge clk);
            start_valid=1; start_count=count; start_l2=mode;
            @(posedge clk);
            @(negedge clk); start_valid=0;
            if(count>0 && count<=16) begin
                for(i=0;i<count;i=i+1) begin
                    if($fscanf(input_file,"%d %d\n",value,weight)!=2)
                        $fatal(1,"NORM_MALFORMED_VECTOR");
                    repeat(i%3) @(negedge clk);
                    while(in_ready!==1'b1) @(negedge clk);
                    in_valid=1; in_data=value; in_weight=weight;
                    @(posedge clk);
                    @(negedge clk); in_valid=0;
                end
            end
            for(i=0;i<((count>0 && count<=16)?count:1);i=i+1) begin
                while(out_valid!==1'b1) @(negedge clk);
                held={out_data,out_index,out_last,out_error,out_valid};
                repeat(3) begin
                    @(posedge clk);
                    if({out_data,out_index,out_last,out_error,out_valid}!==held)
                        $fatal(1,"NORM_OUTPUT_STABILITY");
                    @(negedge clk);
                end
                $display("NORM %0d %0d %0d %0d %0d",tag,out_index,
                         $signed(out_data),out_last,out_error);
                out_ready=1;
                @(posedge clk);
                @(negedge clk); out_ready=0;
            end
            jobs=jobs+1;
            scan=$fscanf(input_file,"%d %d %d\n",tag,mode,count);
        end
        if(scan!=-1 || jobs==0) $fatal(1,"NORM_INCOMPLETE_INPUT");
        $display("COMPLETE %0d",jobs);
        $finish;
    end
endmodule
