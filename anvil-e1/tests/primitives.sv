module primitives;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n;
    reg in_valid=0, out_ready=0;
    reg [2:0] in_op=0;
    reg signed [31:0] in_data=0;
    wire in_ready, out_valid, out_error;
    wire signed [31:0] out_data;
    anvil_e1_nonlinear dut(.*);
    integer input_file, scan, op, value, tag, count=0, cycles=0;
    integer expected_error;
    reg [1023:0] input_path;
    reg signed [31:0] held;
    reg held_error;
    always @(posedge clk or negedge clk) begin
        if (!rst_n && {in_ready,out_valid,out_data,out_error} !== 35'd0)
            $fatal(1,"RESET_XZ_OR_NONZERO");
        if (rst_n && (^ {in_ready,out_valid,out_data,out_error}) === 1'bx)
            $fatal(1,"ACTIVE_XZ");
    end
    always @(posedge clk) begin
        cycles=cycles+1;
        if(cycles>2000000) $fatal(1,"WATCHDOG");
    end
    initial begin
        rst_n=0;
        #1;
        if ({in_ready,out_valid,out_data,out_error} !== 35'd0)
            $fatal(1,"TIME_ZERO_RESET");
        repeat(3) @(negedge clk);
        rst_n=1;
        if(!$value$plusargs("input=%s",input_path)) $fatal(1,"MISSING_INPUT");
        input_file=$fopen(input_path,"r");
        if(!input_file) $fatal(1,"OPEN_INPUT");
        scan=$fscanf(input_file,"%d %d %d %d\n",tag,op,value,expected_error);
        while(scan==4) begin
            while(in_ready!==1'b1) @(negedge clk);
            in_valid=1; in_op=op; in_data=value;
            @(posedge clk);
            @(negedge clk); in_valid=0;
            while(out_valid!==1'b1) @(negedge clk);
            held=out_data; held_error=out_error;
            repeat(3) begin
                @(posedge clk);
                if(out_valid!==1'b1 || out_data!==held || out_error!==held_error)
                    $fatal(1,"OUTPUT_STABILITY");
                @(negedge clk);
            end
            if(out_error!==expected_error[0]) $fatal(1,"ERROR_STATUS tag=%d",tag);
            $display("RESULT %0d %0d %0d",tag,$signed(out_data),out_error);
            out_ready=1;
            @(posedge clk);
            @(negedge clk); out_ready=0;
            count=count+1;
            scan=$fscanf(input_file,"%d %d %d %d\n",tag,op,value,expected_error);
        end
        if(scan!=-1 || count==0) $fatal(1,"INCOMPLETE_INPUT");
        $display("COMPLETE %0d",count);
        $finish;
    end
endmodule
