module anvil_e2_multimodal_fusion #(
    parameter integer TEXT_HIDDEN=512, VISION_SOFT_TOKENS=280,
    VOCAB_SIZE=262144, MAX_SEQ_LEN=262144
) (
    input wire clk, rst_n, start_valid,
    output wire start_ready,
    input wire [1:0] mode,
    input wire [31:0] text_tokens,
    input wire [63:0] weights, token_ids, positions, masks, soft_base,
    input wire [63:0] fused_ids, fused_positions, fused_masks, x0_base,
    output wire [31:0] valid_tokens,
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
    localparam IDLE=0, SELECT=1, ID_REQ=2, ID_RSP=3, POS_REQ=4, POS_RSP=5,
        MASK_REQ=6, MASK_RSP=7, ID_WRITE=8, ID_ACK=9, POS_WRITE=10, POS_ACK=11,
        MASK_WRITE=12, MASK_ACK=13, VECTOR_REQ=14, VECTOR_RSP=15,
        VECTOR_WRITE=16, VECTOR_ACK=17, DONE=18;
    reg [4:0] state;
    reg [3:0] error_hold;
    reg [31:0] token, channel, id_hold, position_hold, mask_hold, count_valid;
    reg signed [31:0] value;
    wire image_mode=mode!=0;
    wire [31:0] frame_count=image_mode ? VISION_SOFT_TOKENS+2:0;
    wire [31:0] total=text_tokens+frame_count;
    wire image_slot=image_mode && token>0 && token<=VISION_SOFT_TOKENS;
    wire supplied=token>=frame_count;
    function automatic [63:0] root(input integer d);
        reg [127:0] a,r,t,q;
        integer i;
        begin
            a=128'(d)<<80; r=0; q=0;
            for (i=0;i<64;i=i+1) begin
                r=(r<<2)|{126'd0,a[127:126]}; t=(q<<2)|1;
                if (r>=t) begin r=r-t; q=(q<<1)|1; end else q=q<<1;
                a=a<<2;
            end
            root=q[63:0];
        end
    endfunction
    localparam [63:0] H_ROOT=root(TEXT_HIDDEN);
    function automatic signed [31:0] scale(input signed [31:0] x);
        reg signed [95:0] p,q;
        begin
            p={{64{x[31]}},x}*$signed({32'd0,H_ROOT}); q=p>>>40;
            if (p[39:0]>40'h8000000000 || (p[39:0]==40'h8000000000 && q[0])) q=q+1;
            if (q>96'sd2147483647) scale=32'sh7fffffff;
            else if (q< -96'sd2147483648) scale=32'sh80000000;
            else scale=q[31:0];
        end
    endfunction
    assign start_ready=rst_n && state==IDLE;
    assign valid_tokens=rst_n ? count_valid:32'd0;
    assign cmd_valid=rst_n && (state==ID_REQ || state==POS_REQ || state==MASK_REQ ||
        state==ID_WRITE || state==POS_WRITE || state==MASK_WRITE ||
        state==VECTOR_REQ || state==VECTOR_WRITE);
    assign cmd_write=rst_n && (state==ID_WRITE || state==POS_WRITE ||
        state==MASK_WRITE || state==VECTOR_WRITE);
    assign cmd_addr=!rst_n ? 64'd0:
        state==ID_REQ ? token_ids+64'(token-frame_count)*4:
        state==POS_REQ ? positions+64'(token-frame_count)*4:
        state==MASK_REQ ? masks+64'(token-frame_count)*4:
        state==ID_WRITE ? fused_ids+64'(token)*4:
        state==POS_WRITE ? fused_positions+64'(token)*4:
        state==MASK_WRITE ? fused_masks+64'(token)*4:
        state==VECTOR_REQ ? (image_slot ?
            soft_base+(64'(token-1)*TEXT_HIDDEN+channel)*4:
            weights+(64'(id_hold)*TEXT_HIDDEN+channel)*4):
        state==VECTOR_WRITE ? x0_base+(64'(token)*TEXT_HIDDEN+channel)*4:64'd0;
    assign cmd_wdata=!rst_n ? 32'd0:
        state==ID_WRITE ? id_hold:state==POS_WRITE ? position_hold:
        state==MASK_WRITE ? mask_hold:state==VECTOR_WRITE ? value:32'd0;
    assign result_ready=rst_n && (state==ID_RSP || state==POS_RSP || state==MASK_RSP ||
        state==ID_ACK || state==POS_ACK || state==MASK_ACK ||
        state==VECTOR_RSP || state==VECTOR_ACK);
    assign done_valid=rst_n && state==DONE;
    assign done_error=rst_n ? error_hold:4'd0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=IDLE; error_hold<=0; token<=0; channel<=0; id_hold<=0;
            position_hold<=0; mask_hold<=0; count_valid<=0; value<=0;
        end else if (result_valid && result_ready && result_error) begin
            error_hold<=3; state<=DONE;
        end else case (state)
            IDLE: if (start_valid) begin
                token<=0; channel<=0; count_valid<=0; error_hold<=0; state<=SELECT;
            end
            SELECT: begin
                if (supplied) state<=ID_REQ;
                else begin
                    if (token==0) id_hold<=255999;
                    else if (token==VISION_SOFT_TOKENS+1) id_hold<=258882;
                    else id_hold<=258880;
                    position_hold<=token; mask_hold<=1;
                    count_valid<=count_valid+1; state<=ID_WRITE;
                end
            end
            ID_REQ: if (cmd_ready) state<=ID_RSP;
            ID_RSP: if (result_valid) begin
                if (result_data>=VOCAB_SIZE) begin error_hold<=2; state<=DONE; end
                else begin id_hold<=result_data; state<=POS_REQ; end
            end
            POS_REQ: if (cmd_ready) state<=POS_RSP;
            POS_RSP: if (result_valid) begin
                if (64'(result_data)+frame_count>=MAX_SEQ_LEN) begin
                    error_hold<=2; state<=DONE;
                end else begin position_hold<=result_data+frame_count; state<=MASK_REQ; end
            end
            MASK_REQ: if (cmd_ready) state<=MASK_RSP;
            MASK_RSP: if (result_valid) begin
                if (result_data>1) begin error_hold<=2; state<=DONE; end
                else begin
                    mask_hold<=result_data; count_valid<=count_valid+result_data; state<=ID_WRITE;
                end
            end
            ID_WRITE: if (cmd_ready) state<=ID_ACK;
            ID_ACK: if (result_valid) state<=POS_WRITE;
            POS_WRITE: if (cmd_ready) state<=POS_ACK;
            POS_ACK: if (result_valid) state<=MASK_WRITE;
            MASK_WRITE: if (cmd_ready) state<=MASK_ACK;
            MASK_ACK: if (result_valid) state<=VECTOR_REQ;
            VECTOR_REQ: if (cmd_ready) state<=VECTOR_RSP;
            VECTOR_RSP: if (result_valid) begin
                value<=image_slot ? $signed(result_data):scale(result_data); state<=VECTOR_WRITE;
            end
            VECTOR_WRITE: if (cmd_ready) state<=VECTOR_ACK;
            VECTOR_ACK: if (result_valid) begin
                if (channel==TEXT_HIDDEN-1) begin
                    channel<=0;
                    if (token==total-1) begin
                        if (count_valid==0) error_hold<=4;
                        state<=DONE;
                    end else begin token<=token+1; state<=SELECT; end
                end else begin channel<=channel+1; state<=VECTOR_REQ; end
            end
            DONE: if (done_ready) state<=IDLE;
            default: begin error_hold<=6; state<=DONE; end
        endcase
    end
endmodule
