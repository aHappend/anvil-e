module anvil_e2_pool #(
    parameter integer EMBEDDING_DIM=768
) (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [31:0] start_tokens, start_valid_tokens,
    input wire [15:0] start_output_dim,
    input wire token_valid,
    output wire token_ready,
    input wire token_mask,
    input wire signed [47:0] token_data,
    output wire norm_start_valid,
    input wire norm_start_ready,
    output wire [31:0] norm_start_count,
    output wire norm_start_l2,
    output wire norm_in_valid,
    input wire norm_in_ready,
    output wire signed [47:0] norm_in_data,
    output wire signed [31:0] norm_in_weight,
    input wire norm_out_valid,
    output wire norm_out_ready,
    input wire signed [47:0] norm_out_data,
    input wire [31:0] norm_out_index,
    input wire norm_out_last, norm_out_error,
    output wire out_valid,
    input wire out_ready,
    output wire signed [31:0] out_data,
    output wire [15:0] out_index,
    output wire out_last,
    output wire done_valid,
    input wire done_ready,
    output wire [3:0] done_error
);
    localparam IDLE=0, CLEAR=1, LOAD=2, MEAN=3, NSTART=4,
               NLOAD=5, NOUTPUT=6, OUTPUT=7, DONE=8;
    reg [3:0] state;
    reg [31:0] tokens, valid_tokens, token_index, channel;
    reg [15:0] dimension;
    reg [31:0] seen_valid;
    reg mask_hold;
    reg signed [127:0] sums [0:EMBEDDING_DIM-1];
    reg signed [47:0] pooled [0:EMBEDDING_DIM-1];
    reg signed [31:0] normalized [0:EMBEDDING_DIM-1];
    reg [3:0] error_hold;
    reg signed [127:0] magnitude, quotient, remainder, divisor;
    reg signed [31:0] data_hold;
    reg [15:0] index_hold;
    reg last_hold;
    function automatic signed [31:0] materialize;
        input signed [47:0] value;
        reg signed [48:0] q;
        begin
            q=$signed({value[47],value})>>>16;
            if (value[15:0]>16'h8000 || (value[15:0]==16'h8000 && q[0]))
                q=q+49'sd1;
            if (q>49'sd2147483647) materialize=32'sh7fffffff;
            else if (q< -49'sd2147483648) materialize=32'sh80000000;
            else materialize=q[31:0];
        end
    endfunction
    initial begin
        if (EMBEDDING_DIM<6 || EMBEDDING_DIM>65535 || EMBEDDING_DIM%6!=0)
            $fatal(1,"PARAMETER ERROR: pool E must be divisible by six and <=65535");
    end
    assign start_ready=rst_n && state==IDLE;
    assign token_ready=rst_n && state==LOAD;
    assign norm_start_valid=rst_n && state==NSTART;
    assign norm_start_count=rst_n ? {16'd0,dimension}:32'd0;
    assign norm_start_l2=rst_n;
    assign norm_in_valid=rst_n && state==NLOAD;
    assign norm_in_data=rst_n && state==NLOAD ? pooled[channel]:48'sd0;
    assign norm_in_weight=32'sd0;
    assign norm_out_ready=rst_n && state==NOUTPUT;
    assign out_valid=rst_n && state==OUTPUT;
    assign out_data=rst_n ? data_hold:32'sd0;
    assign out_index=rst_n ? index_hold:16'd0;
    assign out_last=rst_n && last_hold;
    assign done_valid=rst_n && state==DONE;
    assign done_error=rst_n ? error_hold:4'd0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=IDLE; tokens<=0; valid_tokens<=0; token_index<=0;
            channel<=0; dimension<=0; seen_valid<=0; mask_hold<=0;
            error_hold<=0; data_hold<=0; index_hold<=0; last_hold<=0;
            magnitude=0; quotient=0; remainder=0; divisor=0;
        end else begin
            case (state)
                IDLE: if (start_valid) begin
                    tokens<=start_tokens; valid_tokens<=start_valid_tokens;
                    dimension<=start_output_dim; channel<=0; token_index<=0;
                    seen_valid<=0; error_hold<=0;
                    if (start_tokens==0 || start_valid_tokens>start_tokens ||
                        !(start_output_dim==EMBEDDING_DIM ||
                          start_output_dim==2*EMBEDDING_DIM/3 ||
                          start_output_dim==EMBEDDING_DIM/3 ||
                          start_output_dim==EMBEDDING_DIM/6)) begin
                        error_hold<=1; state<=DONE;
                    end else if (start_valid_tokens==0) begin
                        error_hold<=4; state<=DONE;
                    end else state<=CLEAR;
                end
                CLEAR: begin
                    sums[channel]<=0;
                    if (channel==EMBEDDING_DIM-1) begin channel<=0; state<=LOAD; end
                    else channel<=channel+1'b1;
                end
                LOAD: if (token_valid) begin
                    if (channel==0) begin
                        mask_hold<=token_mask;
                        if (token_mask) seen_valid<=seen_valid+1'b1;
                    end
                    if (channel==0 ? token_mask:mask_hold)
                        sums[channel]<=sums[channel]+{{80{token_data[47]}},token_data};
                    if (channel==EMBEDDING_DIM-1) begin
                        channel<=0;
                        if (token_index==tokens-1) state<=MEAN;
                        else token_index<=token_index+1'b1;
                    end else channel<=channel+1'b1;
                end
                MEAN: begin
                    if (seen_valid!=valid_tokens) begin
                        error_hold<=2; state<=DONE;
                    end else begin
                        divisor={96'd0,valid_tokens};
                        magnitude=sums[channel]<0 ? -sums[channel]:sums[channel];
                        quotient=magnitude/divisor;
                        remainder=magnitude%divisor;
                        if (remainder>divisor-remainder ||
                            (remainder==divisor-remainder && quotient[0]))
                            quotient=quotient+128'sd1;
                        if (sums[channel]<0) quotient=-quotient;
                        if (quotient>128'sd140737488289792) pooled[channel]<=48'sh7fffffff0000;
                        else if (quotient< -128'sd140737488355328) pooled[channel]<=48'sh800000000000;
                        else pooled[channel]<=quotient[47:0];
                        if (channel==dimension-1) begin channel<=0; state<=NSTART; end
                        else channel<=channel+1'b1;
                    end
                end
                NSTART: if (norm_start_ready) state<=NLOAD;
                NLOAD: if (norm_in_ready) begin
                    if (channel==dimension-1) begin channel<=0; state<=NOUTPUT; end
                    else channel<=channel+1'b1;
                end
                NOUTPUT: if (norm_out_valid) begin
                    if (norm_out_error || norm_out_index!=channel ||
                        norm_out_last!=(channel==dimension-1)) begin
                        error_hold<=1; state<=DONE;
                    end else begin
                        normalized[channel]<=materialize(norm_out_data);
                        if (channel==dimension-1) begin
                            channel<=0;
                            data_hold<=dimension==1 ? materialize(norm_out_data):normalized[0];
                            index_hold<=0;
                            last_hold<=dimension==1;
                            state<=OUTPUT;
                        end else channel<=channel+1'b1;
                    end
                end
                OUTPUT: if (out_ready) begin
                    if (channel==dimension-1) state<=DONE;
                    else begin
                        channel<=channel+1'b1;
                        data_hold<=normalized[channel+1'b1];
                        index_hold<=channel+1'b1;
                        last_hold<=channel+1'b1==dimension-1;
                    end
                end
                DONE: if (done_ready) state<=IDLE;
                default: begin error_hold<=1; state<=DONE; end
            endcase
        end
    end
endmodule
