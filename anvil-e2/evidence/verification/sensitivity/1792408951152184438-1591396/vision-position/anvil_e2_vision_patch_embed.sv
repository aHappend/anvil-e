module anvil_e2_vision_patch_embed #(
    parameter integer VISION_HIDDEN=768, PATCH_SIZE=16, POSITION_EMBEDDING_SIZE=10240
) (
    input wire clk, rst_n, start_valid,
    output wire start_ready,
    input wire [31:0] patch_rows, patch_cols,
    input wire [63:0] weights, image, output_base,
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
    localparam IDLE=0, IMAGE_REQ=1, IMAGE_RSP=2, WEIGHT_REQ=3, WEIGHT_RSP=4,
        MAC=5, ROW_REQ=6, ROW_RSP=7, COL_REQ=8, COL_RSP=9, WRITE_REQ=10,
        WRITE_RSP=11, DONE=12;
    localparam [63:0] PATCH_WORDS=64'd3*PATCH_SIZE*PATCH_SIZE;
    reg [3:0] state, error_hold;
    reg [31:0] patch, channel, element;
    reg signed [47:0] pixel, value;
    reg signed [31:0] weight;
    reg signed [127:0] accumulator;
    wire signed [79:0] product=pixel*weight;
    reg [31:0] pr, pc, c, dy, dx;
    wire [63:0] height=64'(patch_rows)*PATCH_SIZE, width=64'(patch_cols)*PATCH_SIZE;
    wire [63:0] image_word=c*height*width+(pr*PATCH_SIZE+dy)*width+pc*PATCH_SIZE+dx;
    wire [63:0] pos_base=weights+PATCH_WORDS*VISION_HIDDEN*4;
    function automatic signed [47:0] sat(input signed [127:0] x);
        if (x>128'sd140737488289792) sat=48'sh7fffffff0000;
        else if (x< -128'sd140737488355328) sat=48'sh800000000000;
        else sat=x[47:0];
    endfunction
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
    assign cmd_valid=rst_n && (state==IMAGE_REQ || state==WEIGHT_REQ ||
        state==ROW_REQ || state==COL_REQ || state==WRITE_REQ);
    assign cmd_write=rst_n && state==WRITE_REQ;
    assign cmd_addr=!rst_n ? 64'd0:
        state==IMAGE_REQ ? image+image_word*4:
        state==WEIGHT_REQ ? weights+(64'(channel)*PATCH_WORDS+element)*4:
        state==ROW_REQ ? pos_base+(pr*VISION_HIDDEN+channel)*4:
        state==COL_REQ ? pos_base+((64'(POSITION_EMBEDDING_SIZE)+pc)*VISION_HIDDEN+channel)*4:
        state==WRITE_REQ ? output_base+(64'(patch)*VISION_HIDDEN+channel)*4:64'd0;
    assign cmd_wdata=rst_n && state==WRITE_REQ ? materialize(value):32'd0;
    assign result_ready=rst_n && (state==IMAGE_RSP || state==WEIGHT_RSP ||
        state==ROW_RSP || state==COL_RSP || state==WRITE_RSP);
    assign done_valid=rst_n && state==DONE;
    assign done_error=rst_n ? error_hold:4'd0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=IDLE; error_hold<=0; patch<=0; channel<=0; element<=0;
            pixel<=0; weight<=0; value<=0; accumulator<=0;
            pr<=0; pc<=0; c<=0; dy<=0; dx<=0;
        end else if (result_valid && result_ready && result_error) begin
            error_hold<=3; state<=DONE;
        end else case (state)
            IDLE: if (start_valid) begin
                patch<=0; channel<=0; element<=0; accumulator<=0; error_hold<=0;
                pr<=0; pc<=0; c<=0; dy<=0; dx<=0;
                if (patch_rows==0 || patch_cols==0 ||
                    patch_rows>POSITION_EMBEDDING_SIZE || patch_cols>POSITION_EMBEDDING_SIZE) begin
                    error_hold<=1; state<=DONE;
                end else state<=IMAGE_REQ;
            end
            IMAGE_REQ: if (cmd_ready) state<=IMAGE_RSP;
            IMAGE_RSP: if (result_valid) begin pixel<={result_data,16'd0}; state<=WEIGHT_REQ; end
            WEIGHT_REQ: if (cmd_ready) state<=WEIGHT_RSP;
            WEIGHT_RSP: if (result_valid) begin weight<=result_data; state<=MAC; end
            MAC: begin
                accumulator<=accumulator+{{48{product[79]}},product};
                if (element==PATCH_WORDS-1) begin
                    value<=rounded(accumulator+{{48{product[79]}},product});
                    element<=0; state<=ROW_REQ;
                    c<=0; dy<=0; dx<=0;
                end else begin
                    element<=element+1; state<=IMAGE_REQ;
                    if (dx==PATCH_SIZE-1) begin
                        dx<=0;
                        if (dy==PATCH_SIZE-1) begin dy<=0; c<=c+1'b1; end
                        else dy<=dy+1'b1;
                    end else dx<=dx+1'b1;
                end
            end
            ROW_REQ: if (cmd_ready) state<=ROW_RSP;
            ROW_RSP: if (result_valid) begin
                value<=value;
                state<=COL_REQ;
            end
            COL_REQ: if (cmd_ready) state<=COL_RSP;
            COL_RSP: if (result_valid) begin
                value<=value;
                state<=WRITE_REQ;
            end
            WRITE_REQ: if (cmd_ready) state<=WRITE_RSP;
            WRITE_RSP: if (result_valid) begin
                accumulator<=0;
                if (channel==VISION_HIDDEN-1) begin
                    channel<=0;
                    if (64'(patch)==64'(patch_rows)*patch_cols-1) state<=DONE;
                    else begin
                        patch<=patch+1; state<=IMAGE_REQ;
                        if (pc==patch_cols-1) begin pc<=0; pr<=pr+1'b1; end
                        else pc<=pc+1'b1;
                    end
                end else begin channel<=channel+1; state<=IMAGE_REQ; end
            end
            DONE: if (done_ready) state<=IDLE;
            default: begin error_hold<=6; state<=DONE; end
        endcase
    end
endmodule
