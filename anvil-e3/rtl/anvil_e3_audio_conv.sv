module anvil_e3_audio_conv #(
    parameter integer INPUT_CHANNELS=1, OUTPUT_CHANNELS=128,
    FREQ_BINS=128, KERNEL=3, STRIDE=2, DEPTHWISE=0
) (
    input wire clk, rst_n, start_valid,
    output wire start_ready,
    input wire [31:0] start_frames,
    input wire [63:0] start_weights, start_input, start_output,
    output wire cmd_valid, cmd_write,
    input wire cmd_ready,
    output wire [63:0] cmd_addr,
    output wire [31:0] cmd_wdata,
    input wire result_valid,
    output wire result_ready,
    input wire [31:0] result_data,
    input wire result_error,
    output wire done_valid,
    input wire done_ready,
    output wire [3:0] done_error
);
    localparam IDLE=0, VALIDATE=1, SELECT=2, INPUT_REQ=3, INPUT_RSP=4,
        WEIGHT_REQ=5, WEIGHT_RSP=6, MAC=7, NEXT=8, WRITE_REQ=9,
        WRITE_RSP=10, DONE=11;
    localparam integer OUT_FREQ=(FREQ_BINS+STRIDE-1)/STRIDE;
    localparam integer KX=DEPTHWISE ? 1:KERNEL;
    localparam [127:0] WEIGHT_WORDS=DEPTHWISE ?
        128'(OUTPUT_CHANNELS)*KERNEL:
        128'(OUTPUT_CHANNELS)*INPUT_CHANNELS*KERNEL*KERNEL;
    reg [3:0] state, error_hold;
    reg [31:0] frames, out_t, out_f, out_c, in_c, ky, kx;
    reg [63:0] weights, input_base, output_base;
    reg signed [47:0] operand, weight, value;
    reg signed [127:0] accumulator;
    wire [63:0] out_frames=(64'(frames)+STRIDE-1)/STRIDE;
    wire signed [63:0] input_t=$signed(64'(out_t)*STRIDE+ky)-(KERNEL-1)/2;
    wire signed [63:0] input_f=DEPTHWISE ? 64'sd0:
        $signed(64'(out_f)*STRIDE+kx)-(KERNEL-1)/2;
    wire padded=input_t<0 || input_t>=$signed({32'd0,frames}) ||
        input_f<0 || input_f>=FREQ_BINS;
    wire [63:0] input_word=($unsigned(input_t)*FREQ_BINS+
        $unsigned(input_f))*INPUT_CHANNELS+(DEPTHWISE ? out_c:in_c);
    wire [63:0] weight_word=DEPTHWISE ? 64'(out_c)*KERNEL+ky:
        ((64'(out_c)*INPUT_CHANNELS+in_c)*KERNEL+ky)*KERNEL+kx;
    wire [63:0] output_word=(64'(out_t)*OUT_FREQ+out_f)*OUTPUT_CHANNELS+out_c;
    wire last_tap=kx==KX-1 && ky==KERNEL-1 &&
        (DEPTHWISE || in_c==INPUT_CHANNELS-1);
    wire signed [95:0] product=operand*weight;
    wire [127:0] input_bytes=128'(frames)*FREQ_BINS*INPUT_CHANNELS*4;
    wire [127:0] output_bytes=128'(out_frames)*OUT_FREQ*OUTPUT_CHANNELS*4;
    function automatic overflow(input [63:0] base, input [127:0] bytes);
        overflow=({64'd0,base}+bytes)>128'hffffffffffffffff;
    endfunction
    function automatic signed [47:0] rounded(input signed [127:0] x);
        reg signed [127:0] q;
        begin
            q=x>>>40;
            if (x[39:0]>40'h8000000000 ||
                (x[39:0]==40'h8000000000 && q[0])) q=q+1;
            if (q>128'sd140737488289792) rounded=48'sh7fffffff0000;
            else if (q< -128'sd140737488355328) rounded=48'sh800000000000;
            else rounded=q[47:0];
        end
    endfunction
    function automatic signed [31:0] materialize(input signed [47:0] x);
        reg signed [48:0] q;
        begin
            q=$signed({x[47],x})>>>16;
            if (x[15:0]>16'h8000 || (x[15:0]==16'h8000 && q[0])) q=q+1;
            if (q>49'sd2147483647) materialize=32'sh7fffffff;
            else if (q< -49'sd2147483648) materialize=32'sh80000000;
            else materialize=q[31:0];
        end
    endfunction
    initial begin
        if (INPUT_CHANNELS<=0 || OUTPUT_CHANNELS<=0 || FREQ_BINS<=0 ||
            INPUT_CHANNELS>65535 || OUTPUT_CHANNELS>65535 || FREQ_BINS>65535 ||
            KERNEL<=0 || KERNEL>65535 || KERNEL%2!=1 || STRIDE<=0 ||
            (DEPTHWISE && (INPUT_CHANNELS!=OUTPUT_CHANNELS || FREQ_BINS!=1)))
            $fatal(1,"PARAMETER ERROR: audio convolution geometry");
    end
    assign start_ready=rst_n && state==IDLE;
    assign cmd_valid=rst_n && (state==INPUT_REQ || state==WEIGHT_REQ || state==WRITE_REQ);
    assign cmd_write=rst_n && state==WRITE_REQ;
    assign cmd_addr=!rst_n ? 64'd0:
        state==INPUT_REQ ? input_base+input_word*4:
        state==WEIGHT_REQ ? weights+weight_word*4:
        state==WRITE_REQ ? output_base+output_word*4:64'd0;
    assign cmd_wdata=rst_n && state==WRITE_REQ ? materialize(value):32'd0;
    assign result_ready=rst_n && (state==INPUT_RSP || state==WEIGHT_RSP || state==WRITE_RSP);
    assign done_valid=rst_n && state==DONE;
    assign done_error=rst_n ? error_hold:4'd0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=IDLE; error_hold<=0; frames<=0; out_t<=0; out_f<=0; out_c<=0;
            in_c<=0; ky<=0; kx<=0; weights<=0; input_base<=0; output_base<=0;
            operand<=0; weight<=0; value<=0; accumulator<=0;
        end else if (result_valid && result_ready && result_error) begin
            error_hold<=3; state<=DONE;
        end else case (state)
            IDLE: if (start_valid) begin
                frames<=start_frames; weights<=start_weights;
                input_base<=start_input; output_base<=start_output;
                out_t<=0; out_f<=0; out_c<=0; in_c<=0; ky<=0; kx<=0;
                accumulator<=0; error_hold<=0; state<=VALIDATE;
            end
            VALIDATE: begin
                if (frames==0 || |weights[1:0] || |input_base[1:0] || |output_base[1:0]) begin
                    error_hold<=1; state<=DONE;
                end else if (overflow(weights,WEIGHT_WORDS*4) ||
                    overflow(input_base,input_bytes) || overflow(output_base,output_bytes)) begin
                    error_hold<=5; state<=DONE;
                end else state<=SELECT;
            end
            SELECT: if (padded) state<=NEXT; else state<=INPUT_REQ;
            INPUT_REQ: if (cmd_ready) state<=INPUT_RSP;
            INPUT_RSP: if (result_valid) begin operand<={result_data,16'd0}; state<=WEIGHT_REQ; end
            WEIGHT_REQ: if (cmd_ready) state<=WEIGHT_RSP;
            WEIGHT_RSP: if (result_valid) begin weight<={result_data,16'd0}; state<=MAC; end
            MAC: begin accumulator<=accumulator+{{32{product[95]}},product}; state<=NEXT; end
            NEXT: begin
                if (last_tap) begin value<=rounded(accumulator); state<=WRITE_REQ; end
                else begin
                    if (kx!=KX-1) kx<=kx+1'b1;
                    else begin
                        kx<=0;
                        if (ky!=KERNEL-1) ky<=ky+1'b1;
                        else begin ky<=0; in_c<=in_c+1'b1; end
                    end
                    state<=SELECT;
                end
            end
            WRITE_REQ: if (cmd_ready) state<=WRITE_RSP;
            WRITE_RSP: if (result_valid) begin
                accumulator<=0; in_c<=0; ky<=0; kx<=0;
                if (out_c!=OUTPUT_CHANNELS-1) begin out_c<=out_c+1'b1; state<=SELECT; end
                else begin
                    out_c<=0;
                    if (out_f!=OUT_FREQ-1) begin out_f<=out_f+1'b1; state<=SELECT; end
                    else begin
                        out_f<=0;
                        if (64'(out_t)==out_frames-1) state<=DONE;
                        else begin out_t<=out_t+1'b1; state<=SELECT; end
                    end
                end
            end
            DONE: if (done_ready) state<=IDLE;
            default: begin error_hold<=6; state<=DONE; end
        endcase
    end
endmodule
