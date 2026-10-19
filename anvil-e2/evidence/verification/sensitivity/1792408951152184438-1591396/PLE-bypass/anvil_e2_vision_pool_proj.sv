module anvil_e2_vision_pool_proj #(
    parameter integer VISION_HIDDEN=768, TEXT_HIDDEN=512,
    POOL_KERNEL=3, VISION_SOFT_TOKENS=280
) (
    input wire clk, rst_n, start_valid,
    output wire start_ready,
    input wire [31:0] patch_rows, patch_cols,
    input wire [63:0] weights, input_base, output_base,
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
    localparam IDLE=0, READ_REQ=1, READ_RSP=2, MEAN=3,
        WEIGHT_REQ=4, WEIGHT_RSP=5, MAC=6, WRITE_REQ=7, WRITE_RSP=8, DONE=9,
        MEAN_WAIT=10;
    reg [3:0] state, error_hold;
    reg [31:0] soft_token, channel, dy, dx, output_channel;
    reg signed [47:0] pooled [0:VISION_HIDDEN-1];
    reg signed [31:0] weight;
    reg signed [47:0] value;
    reg signed [127:0] sum, accumulator;
    wire signed [79:0] product=pooled[channel]*weight;
    wire [63:0] pooled_cols, pooled_rows;
    reg [63:0] r0, c0;
    anvil_e2_const_divide #(.DIVISOR(POOL_KERNEL)) column_count (
        .numerator(64'(patch_cols)+POOL_KERNEL-1),
        .quotient(pooled_cols), .remainder()
    );
    anvil_e2_const_divide #(.DIVISOR(POOL_KERNEL)) row_count (
        .numerator(64'(patch_rows)+POOL_KERNEL-1),
        .quotient(pooled_rows), .remainder()
    );
    wire [63:0] nr=(64'(patch_rows)-r0)<POOL_KERNEL ? 64'(patch_rows)-r0:POOL_KERNEL;
    wire [63:0] nc=(64'(patch_cols)-c0)<POOL_KERNEL ? 64'(patch_cols)-c0:POOL_KERNEL;
    function automatic signed [47:0] sat(input signed [127:0] x);
        if (x>128'sd140737488289792) sat=48'sh7fffffff0000;
        else if (x< -128'sd140737488355328) sat=48'sh800000000000;
        else sat=x[47:0];
    endfunction
    wire divide_ready, divide_valid, divide_error;
    wire signed [127:0] divide_data;
    anvil_e2_divide divider (
        .clk(clk), .rst_n(rst_n), .in_valid(state==MEAN),
        .in_ready(divide_ready), .in_numerator(sum),
        .in_denominator(128'(nr)*nc), .out_valid(divide_valid),
        .out_ready(state==MEAN_WAIT), .out_data(divide_data),
        .out_error(divide_error)
    );
    function automatic signed [47:0] rounded(input signed [127:0] x);
        reg signed [127:0] q;
        begin
            q=x>>>24;
            if (x[23:0]>24'h800000 || (x[23:0]==24'h800000 && q[0])) q=q+1;
            rounded=sat(q);
        end
    endfunction
    function automatic signed [31:0] materialize(input signed [47:0] x);
        reg signed [48:0] q;
        begin
            q=$signed({x[47],x})>>>16;
            if (x[15:0]>16'h8000 || (x[15:0]==16'h8000 && q[0])) q=q+49'sd1;
            if (q>49'sd2147483647) materialize=32'sh7fffffff;
            else if (q< -49'sd2147483648) materialize=32'sh80000000;
            else materialize=q[31:0];
        end
    endfunction
    assign start_ready=rst_n && state==IDLE;
    assign cmd_valid=rst_n && (state==READ_REQ || state==WEIGHT_REQ || state==WRITE_REQ);
    assign cmd_write=rst_n && state==WRITE_REQ;
    assign cmd_addr=!rst_n ? 64'd0:
        state==READ_REQ ? input_base+(((r0+dy)*patch_cols+c0+dx)*VISION_HIDDEN+channel)*4:
        state==WEIGHT_REQ ? weights+(64'(output_channel)*VISION_HIDDEN+channel)*4:
        state==WRITE_REQ ? output_base+(64'(soft_token)*TEXT_HIDDEN+output_channel)*4:64'd0;
    assign cmd_wdata=rst_n && state==WRITE_REQ ? materialize(value):32'd0;
    assign result_ready=rst_n && (state==READ_RSP || state==WEIGHT_RSP || state==WRITE_RSP);
    assign done_valid=rst_n && state==DONE;
    assign done_error=rst_n ? error_hold:4'd0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=IDLE; error_hold<=0; soft_token<=0; channel<=0; dy<=0; dx<=0;
            output_channel<=0; weight<=0; value<=0; sum<=0; accumulator<=0;
            r0<=0; c0<=0;
        end else if (result_valid && result_ready && result_error) begin
            error_hold<=3; state<=DONE;
        end else case (state)
            IDLE: if (start_valid) begin
                soft_token<=0; channel<=0; dy<=0; dx<=0; output_channel<=0;
                sum<=0; accumulator<=0; error_hold<=0;
                r0<=0; c0<=0;
                if (patch_rows==0 || patch_cols==0 ||
                    128'(pooled_rows)*pooled_cols!=VISION_SOFT_TOKENS) begin
                    error_hold<=1; state<=DONE;
                end else state<=READ_REQ;
            end
            READ_REQ: if (cmd_ready) state<=READ_RSP;
            READ_RSP: if (result_valid) begin
                sum<=sum+{{80{result_data[31]}},result_data,16'd0};
                if (64'(dx)==nc-1) begin
                    dx<=0;
                    if (64'(dy)==nr-1) begin dy<=0; state<=MEAN; end
                    else begin dy<=dy+1; state<=READ_REQ; end
                end else begin dx<=dx+1; state<=READ_REQ; end
            end
            MEAN: if (divide_ready) state<=MEAN_WAIT;
            MEAN_WAIT: if (divide_valid) begin
                if (divide_error) begin error_hold<=6; state<=DONE; end
                else begin
                    pooled[channel]<=sat(divide_data); sum<=0;
                    if (channel==VISION_HIDDEN-1) begin channel<=0; state<=WEIGHT_REQ; end
                    else begin channel<=channel+1; state<=READ_REQ; end
                end
            end
            WEIGHT_REQ: if (cmd_ready) state<=WEIGHT_RSP;
            WEIGHT_RSP: if (result_valid) begin weight<=result_data; state<=MAC; end
            MAC: begin
                accumulator<=accumulator+{{48{product[79]}},product};
                if (channel==VISION_HIDDEN-1) begin
                    value<=rounded(accumulator+{{48{product[79]}},product});
                    channel<=0; state<=WRITE_REQ;
                end else begin channel<=channel+1; state<=WEIGHT_REQ; end
            end
            WRITE_REQ: if (cmd_ready) state<=WRITE_RSP;
            WRITE_RSP: if (result_valid) begin
                accumulator<=0;
                if (output_channel==TEXT_HIDDEN-1) begin
                    output_channel<=0;
                    if (soft_token==VISION_SOFT_TOKENS-1) state<=DONE;
                    else begin
                        soft_token<=soft_token+1; state<=READ_REQ;
                        if (c0+POOL_KERNEL>=64'(patch_cols)) begin
                            c0<=0; r0<=r0+POOL_KERNEL;
                        end else c0<=c0+POOL_KERNEL;
                    end
                end else begin output_channel<=output_channel+1; state<=WEIGHT_REQ; end
            end
            DONE: if (done_ready) state<=IDLE;
            default: begin error_hold<=6; state<=DONE; end
        endcase
    end
endmodule
