module anvil_e3_audio_subsample #(
    parameter integer AUDIO_HIDDEN=1024, AUDIO_SUBSAMPLE_C0=128,
    AUDIO_SUBSAMPLE_C1=32, AUDIO_FREQ_BINS=128
) (
    input wire clk, rst_n, start_valid,
    output wire start_ready,
    input wire [31:0] frames,
    input wire [63:0] weights, input_base, work_base, output_base,
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
    function automatic integer maximum(input integer a,b);
        maximum=a>b ? a:b;
    endfunction
    localparam integer F1=(AUDIO_FREQ_BINS+1)/2, F2=(AUDIO_FREQ_BINS+3)/4;
    localparam integer WIDTH=maximum(maximum(AUDIO_SUBSAMPLE_C0,AUDIO_SUBSAMPLE_C1),
        maximum(AUDIO_HIDDEN,AUDIO_SUBSAMPLE_C1*F2));
    localparam IDLE=0, DISPATCH=1, LAUNCH=2, WAIT=3, DONE=4;
    reg [2:0] state;
    reg [3:0] pc;
    reg [1:0] owner;
    reg [31:0] frame_count;
    reg [63:0] w, src, tmp, dst;
    reg [3:0] error_hold;
    wire [31:0] t1=32'((64'(frame_count)+1)/2);
    wire [31:0] t2=32'((64'(frame_count)+3)/4);
    wire [63:0] n0=64'(t1)*F1*AUDIO_SUBSAMPLE_C0;
    wire [63:0] n1=64'(t2)*F2*AUDIO_SUBSAMPLE_C1;
    wire [63:0] raw0=tmp, norm0=tmp+n0*4;
    wire [63:0] raw1=tmp+2*n0*4, norm1=tmp+(2*n0+n1)*4;
    wire [63:0] flat=tmp+(2*n0+2*n1)*4;
    wire [2:0] starts, readys, valids, writes, replies, results, dones;
    wire [63:0] addrs [0:2];
    wire [31:0] data [0:2];
    wire [3:0] errors [0:2];
    genvar g;
    generate for (g=0;g<3;g=g+1) begin : channels
        assign starts[g]=rst_n && state==LAUNCH && owner==g;
        assign replies[g]=rst_n && state==WAIT && owner==g && cmd_ready;
        assign results[g]=rst_n && state==WAIT && owner==g && result_valid;
    end endgenerate
    wire [63:0] weight_addr;
    reg [5:0] group_index;
    wire layout_error;
    anvil_e3_audio_layout #(
        .AUDIO_HIDDEN(AUDIO_HIDDEN), .AUDIO_SUBSAMPLE_C0(AUDIO_SUBSAMPLE_C0),
        .AUDIO_SUBSAMPLE_C1(AUDIO_SUBSAMPLE_C1), .AUDIO_FREQ_BINS(AUDIO_FREQ_BINS)
    ) layout (
        .weights_base(w), .layer_index(32'd0), .tensor_group(group_index),
        .tensor_addr(weight_addr), .weights_bytes(), .address_error(layout_error)
    );
    wire [2:0] result_readys;
    anvil_e3_audio_conv #(
        .INPUT_CHANNELS(1), .OUTPUT_CHANNELS(AUDIO_SUBSAMPLE_C0),
        .FREQ_BINS(AUDIO_FREQ_BINS)
    ) conv0 (
        .clk(clk), .rst_n(rst_n), .start_valid(starts[0]), .start_ready(readys[0]),
        .start_frames(frame_count), .start_weights(weight_addr),
        .start_input(src), .start_output(raw0),
        .cmd_valid(valids[0]), .cmd_write(writes[0]), .cmd_ready(replies[0]),
        .cmd_addr(addrs[0]), .cmd_wdata(data[0]), .result_valid(results[0]),
        .result_ready(result_readys[0]), .result_data(result_data), .result_error(result_error),
        .done_valid(dones[0]), .done_ready(state==WAIT && owner==0),
        .done_error(errors[0])
    );
    anvil_e3_audio_conv #(
        .INPUT_CHANNELS(AUDIO_SUBSAMPLE_C0), .OUTPUT_CHANNELS(AUDIO_SUBSAMPLE_C1),
        .FREQ_BINS(F1)
    ) conv1 (
        .clk(clk), .rst_n(rst_n), .start_valid(starts[1]), .start_ready(readys[1]),
        .start_frames(t1), .start_weights(weight_addr),
        .start_input(norm0), .start_output(raw1),
        .cmd_valid(valids[1]), .cmd_write(writes[1]), .cmd_ready(replies[1]),
        .cmd_addr(addrs[1]), .cmd_wdata(data[1]), .result_valid(results[1]),
        .result_ready(result_readys[1]), .result_data(result_data), .result_error(result_error),
        .done_valid(dones[1]), .done_ready(state==WAIT && owner==1),
        .done_error(errors[1])
    );
    reg [2:0] vector_op;
    reg [63:0] vector_tokens, vector_input, vector_output;
    reg [31:0] vector_rows, vector_cols;
    always @* begin
        group_index=0; vector_op=1; vector_tokens=64'(t1)*F1;
        vector_input=raw0; vector_output=norm0;
        vector_rows=AUDIO_SUBSAMPLE_C0; vector_cols=1;
        case (pc)
            0: group_index=0;
            1: group_index=1;
            2: begin group_index=1; vector_op=2; vector_input=norm0; end
            3: group_index=2;
            4: begin
                group_index=3; vector_tokens=64'(t2)*F2;
                vector_rows=AUDIO_SUBSAMPLE_C1; vector_input=raw1; vector_output=norm1;
            end
            5: begin
                group_index=3; vector_op=2; vector_tokens=64'(t2)*F2;
                vector_rows=AUDIO_SUBSAMPLE_C1; vector_input=norm1; vector_output=norm1;
            end
            6: begin
                group_index=4; vector_op=5; vector_tokens=t2;
                vector_rows=AUDIO_SUBSAMPLE_C1; vector_cols=F2;
                vector_input=norm1; vector_output=flat;
            end
            7: begin
                group_index=4; vector_op=0; vector_tokens=t2;
                vector_rows=AUDIO_HIDDEN; vector_cols=AUDIO_SUBSAMPLE_C1*F2;
                vector_input=flat; vector_output=dst;
            end
            default: group_index=0;
        endcase
    end
    anvil_e3_audio_vector #(.MAX_WIDTH(WIDTH)) vectors (
        .clk(clk), .rst_n(rst_n), .start_valid(starts[2]), .start_ready(readys[2]),
        .start_op(vector_op), .start_tokens(vector_tokens), .start_rows(vector_rows),
        .start_cols(vector_cols), .start_weights(weight_addr), .start_input(vector_input),
        .start_aux(64'd0), .start_output(vector_output),
        .start_clipped(1'b0), .start_bias(1'b0), .start_half(1'b0),
        .cmd_valid(valids[2]), .cmd_write(writes[2]), .cmd_ready(replies[2]),
        .cmd_addr(addrs[2]), .cmd_wdata(data[2]), .result_valid(results[2]),
        .result_ready(result_readys[2]), .result_data(result_data), .result_error(result_error),
        .done_valid(dones[2]), .done_ready(state==WAIT && owner==2), .done_error(errors[2])
    );
    assign start_ready=rst_n && state==IDLE;
    assign cmd_valid=rst_n && state==WAIT && valids[owner];
    assign cmd_write=rst_n && state==WAIT && writes[owner];
    assign cmd_addr=rst_n && state==WAIT ? addrs[owner]:64'd0;
    assign cmd_wdata=rst_n && state==WAIT ? data[owner]:32'd0;
    assign result_ready=rst_n && state==WAIT && result_readys[owner];
    assign done_valid=rst_n && state==DONE;
    assign done_error=rst_n ? error_hold:4'd0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=IDLE; pc<=0; owner<=0; frame_count<=0;
            w<=0; src<=0; tmp<=0; dst<=0; error_hold<=0;
        end else case (state)
            IDLE: if (start_valid) begin
                frame_count<=frames; w<=weights; src<=input_base; tmp<=work_base;
                dst<=output_base; pc<=0; owner<=0; error_hold<=0; state<=DISPATCH;
            end
            DISPATCH: begin
                if (frame_count==0) begin error_hold<=1; state<=DONE; end
                else if (layout_error) begin error_hold<=5; state<=DONE; end
                else begin
                    if (pc==0) owner<=0;
                    else if (pc==3) owner<=1;
                    else owner<=2;
                    state<=LAUNCH;
                end
            end
            LAUNCH: if (readys[owner]) state<=WAIT;
            WAIT: if (dones[owner]) begin
                if (errors[owner]!=0) begin error_hold<=errors[owner]; state<=DONE; end
                else if (pc==7) state<=DONE;
                else begin pc<=pc+1'b1; state<=DISPATCH; end
            end
            DONE: if (done_ready) state<=IDLE;
            default: begin error_hold<=6; state<=DONE; end
        endcase
    end
endmodule
