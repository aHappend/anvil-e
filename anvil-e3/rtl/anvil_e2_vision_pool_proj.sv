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
        MEAN_WAIT=10, EXTENT_CHECK=11, ADDR_PREP0=12, ADDR_PREP1=13,
        MAC_MUL=14, MAC_ROUND=15;
    reg [3:0] state, error_hold;
    reg [31:0] soft_token, channel, dy, dx, output_channel;
    reg signed [47:0] pooled [0:VISION_HIDDEN-1];
    reg signed [47:0] pooled_val_reg, value;
    reg signed [31:0] weight;
    reg signed [79:0] prod_reg;
    reg signed [127:0] sum, accumulator;
    wire [32:0] pooled_cols_w, pooled_rows_w, cols_remainder, rows_remainder;
    anvil_e3_constant_divide #(.WIDTH(33), .DIVISOR(33'(POOL_KERNEL)))
        column_extent (.numerator(33'(patch_cols)+POOL_KERNEL-1),
            .quotient(pooled_cols_w), .remainder(cols_remainder));
    anvil_e3_constant_divide #(.WIDTH(33), .DIVISOR(33'(POOL_KERNEL)))
        row_extent (.numerator(33'(patch_rows)+POOL_KERNEL-1),
            .quotient(pooled_rows_w), .remainder(rows_remainder));
    reg [63:0] pooled_cols, pooled_rows;
    reg [63:0] r0, c0, pooled_column, row_col_idx_reg, read_word_reg;
    wire [63:0] nr=(64'(patch_rows)-r0)<POOL_KERNEL ? 64'(patch_rows)-r0:POOL_KERNEL;
    wire [63:0] nc=(64'(patch_cols)-c0)<POOL_KERNEL ? 64'(patch_cols)-c0:POOL_KERNEL;
    function automatic signed [47:0] sat(input signed [127:0] x);
        if (x>128'sd140737488289792) sat=48'sh7fffffff0000;
        else if (x< -128'sd140737488355328) sat=48'sh800000000000;
        else sat=x[47:0];
    endfunction
    wire mean_ready, mean_valid, mean_error;
    wire signed [127:0] mean_data;
    anvil_e2_divide mean_divider (
        .clk(clk), .rst_n(rst_n), .in_valid(state==MEAN),
        .in_ready(mean_ready), .in_numerator(sum), .in_denominator(128'(nr)*nc),
        .out_valid(mean_valid), .out_ready(state==MEAN_WAIT),
        .out_data(mean_data), .out_error(mean_error)
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
        state==READ_REQ ? input_base+read_word_reg*4:
        state==WEIGHT_REQ ? weights+(64'(output_channel)*VISION_HIDDEN+channel)*4:
        state==WRITE_REQ ? output_base+(64'(soft_token)*TEXT_HIDDEN+output_channel)*4:64'd0;
    assign cmd_wdata=rst_n && state==WRITE_REQ ? materialize(value):32'd0;
    assign result_ready=rst_n && (state==READ_RSP || state==WEIGHT_RSP || state==WRITE_RSP);
    assign done_valid=rst_n && state==DONE;
    assign done_error=rst_n ? error_hold:4'd0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=IDLE; error_hold<=0; soft_token<=0; channel<=0; dy<=0; dx<=0;
            output_channel<=0; pooled_val_reg<=0; weight<=0; prod_reg<=0;
            value<=0; sum<=0; accumulator<=0; pooled_cols<=0; pooled_rows<=0;
            r0<=0; c0<=0; pooled_column<=0; row_col_idx_reg<=0; read_word_reg<=0;
        end else if (result_valid && result_ready && result_error) begin
            error_hold<=3; state<=DONE;
        end else case (state)
            IDLE: if (start_valid) begin
                soft_token<=0; channel<=0; dy<=0; dx<=0; output_channel<=0;
                sum<=0; accumulator<=0; error_hold<=0;
                r0<=0; c0<=0; pooled_column<=0;
                pooled_cols<={31'd0,pooled_cols_w};
                pooled_rows<={31'd0,pooled_rows_w};
                if (patch_rows==0 || patch_cols==0) begin
                    error_hold<=1; state<=DONE;
                end else state<=EXTENT_CHECK;
            end
            EXTENT_CHECK: begin
                if (pooled_rows*pooled_cols!=VISION_SOFT_TOKENS) begin
                    error_hold<=1; state<=DONE;
                end else state<=ADDR_PREP0;
            end
            ADDR_PREP0: begin
                row_col_idx_reg<=(r0+dy)*patch_cols+c0+dx;
                state<=ADDR_PREP1;
            end
            ADDR_PREP1: begin
                read_word_reg<=row_col_idx_reg*VISION_HIDDEN+channel;
                state<=READ_REQ;
            end
            READ_REQ: if (cmd_ready) state<=READ_RSP;
            READ_RSP: if (result_valid) begin
                sum<=sum+{{80{result_data[31]}},result_data,16'd0};
                if (64'(dx)==nc-1) begin
                    dx<=0;
                    if (64'(dy)==nr-1) begin dy<=0; state<=MEAN; end
                    else begin dy<=dy+1; state<=ADDR_PREP0; end
                end else begin dx<=dx+1; state<=ADDR_PREP0; end
            end
            MEAN: if (mean_ready) state<=MEAN_WAIT;
            MEAN_WAIT: if (mean_valid) begin
                if (mean_error) begin error_hold<=6; state<=DONE; end
                else begin
                    pooled[channel]<=sat(mean_data); sum<=0;
                    if (channel==VISION_HIDDEN-1) begin channel<=0; state<=WEIGHT_REQ; end
                    else begin channel<=channel+1; state<=ADDR_PREP0; end
                end
            end
            WEIGHT_REQ: if (cmd_ready) state<=WEIGHT_RSP;
            WEIGHT_RSP: if (result_valid) begin
                pooled_val_reg<=pooled[channel];
                weight<=result_data; state<=MAC_MUL;
            end
            MAC_MUL: begin
                prod_reg<=pooled_val_reg*weight;
                state<=MAC;
            end
            MAC: begin
                accumulator<=accumulator+{{48{prod_reg[79]}},prod_reg};
                if (channel==VISION_HIDDEN-1) state<=MAC_ROUND;
                else begin channel<=channel+1; state<=WEIGHT_REQ; end
            end
            MAC_ROUND: begin
                value<=rounded(accumulator);
                channel<=0; state<=WRITE_REQ;
            end
            WRITE_REQ: if (cmd_ready) state<=WRITE_RSP;
            WRITE_RSP: if (result_valid) begin
                accumulator<=0;
                if (output_channel==TEXT_HIDDEN-1) begin
                    output_channel<=0;
                    if (soft_token==VISION_SOFT_TOKENS-1) state<=DONE;
                    else begin
                        if (pooled_column==pooled_cols-1) begin
                            pooled_column<=0; c0<=0; r0<=r0+POOL_KERNEL;
                        end else begin
                            pooled_column<=pooled_column+1'b1; c0<=c0+POOL_KERNEL;
                        end
                        soft_token<=soft_token+1; state<=ADDR_PREP0;
                    end
                end else begin output_channel<=output_channel+1; state<=WEIGHT_REQ; end
            end
            DONE: if (done_ready) state<=IDLE;
            default: begin error_hold<=6; state<=DONE; end
        endcase
    end
endmodule
