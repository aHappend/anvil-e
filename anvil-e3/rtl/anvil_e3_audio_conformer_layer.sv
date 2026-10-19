module anvil_e3_audio_conformer_layer #(
    parameter integer AUDIO_LAYERS=12, AUDIO_HIDDEN=1024, AUDIO_FFN=4096,
    AUDIO_HEADS=8, AUDIO_HEAD_DIM=128, AUDIO_OUT_DIM=1536, AUDIO_CONV_KERNEL=5,
    AUDIO_SUBSAMPLE_C0=128, AUDIO_SUBSAMPLE_C1=32, AUDIO_FREQ_BINS=128,
    AUDIO_CHUNK_SIZE=12, AUDIO_CONTEXT_LEFT=13, AUDIO_CONTEXT_RIGHT=0, TEXT_HIDDEN=512
) (
    input wire clk, rst_n, start_valid,
    output wire start_ready,
    input wire [31:0] tokens, layer_index,
    input wire [63:0] weights, x0_base, x1_base, work0_base, work1_base,
    input wire [63:0] q_base, k_base, v_base, attention_base,
    input wire start_current_x,
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
    localparam integer WIDTH=AUDIO_FFN>2*AUDIO_HIDDEN ? AUDIO_FFN:2*AUDIO_HIDDEN;
    localparam IDLE=0, DISPATCH=1, LAUNCH=2, WAIT=3, DONE=4;
    reg [2:0] state;
    reg [4:0] pc;
    reg [1:0] owner;
    reg [31:0] count, layer;
    reg [63:0] w, source_x, next_x, work0, work1, qb, kb, vb, att;
    reg [3:0] error_hold;
    wire [2:0] starts, readys, valids, writes, replies, results, result_readys, dones;
    wire [63:0] addrs [0:2];
    wire [31:0] data [0:2];
    wire [3:0] errors [0:2];
    genvar g;
    generate for (g=0;g<3;g=g+1) begin : channels
        assign starts[g]=rst_n && state==LAUNCH && owner==g;
        assign replies[g]=rst_n && state==WAIT && owner==g && cmd_ready;
        assign results[g]=rst_n && state==WAIT && owner==g && result_valid;
    end endgenerate
    reg [5:0] group_index;
    wire [63:0] weight_addr, scale_addr;
    wire layout_error, scale_layout_error;
`define E3_AUDIO_LAYOUT_PARAMS \
    .AUDIO_LAYERS(AUDIO_LAYERS), .AUDIO_HIDDEN(AUDIO_HIDDEN), .AUDIO_FFN(AUDIO_FFN), \
    .AUDIO_HEAD_DIM(AUDIO_HEAD_DIM), .AUDIO_OUT_DIM(AUDIO_OUT_DIM), \
    .AUDIO_CONV_KERNEL(AUDIO_CONV_KERNEL), .AUDIO_SUBSAMPLE_C0(AUDIO_SUBSAMPLE_C0), \
    .AUDIO_SUBSAMPLE_C1(AUDIO_SUBSAMPLE_C1), .AUDIO_FREQ_BINS(AUDIO_FREQ_BINS), \
    .TEXT_HIDDEN(TEXT_HIDDEN)
    anvil_e3_audio_layout #(`E3_AUDIO_LAYOUT_PARAMS) layout (
        .weights_base(w), .layer_index(layer), .tensor_group(group_index),
        .tensor_addr(weight_addr), .weights_bytes(), .address_error(layout_error)
    );
    anvil_e3_audio_layout #(`E3_AUDIO_LAYOUT_PARAMS) scale_layout (
        .weights_base(w), .layer_index(layer), .tensor_group(6'd22),
        .tensor_addr(scale_addr), .weights_bytes(), .address_error(scale_layout_error)
    );
`undef E3_AUDIO_LAYOUT_PARAMS
    reg [2:0] vector_op;
    reg [31:0] vector_rows, vector_cols;
    reg [63:0] vector_input, vector_aux, vector_output;
    reg vector_clipped, vector_half;
    always @* begin
        group_index=8; vector_op=1; vector_rows=AUDIO_HIDDEN; vector_cols=1;
        vector_input=source_x; vector_aux=work1; vector_output=work0;
        vector_clipped=0; vector_half=0;
        case (pc)
            0: group_index=8;
            1: begin
                group_index=5; vector_op=0; vector_rows=AUDIO_FFN;
                vector_cols=AUDIO_HIDDEN; vector_input=work0; vector_output=work1;
                vector_clipped=1;
            end
            2: begin
                vector_op=2; vector_rows=AUDIO_FFN; vector_input=work1; vector_output=work1;
            end
            3: begin
                group_index=6; vector_op=0; vector_cols=AUDIO_FFN;
                vector_input=work1; vector_output=work0; vector_clipped=1;
            end
            4: begin group_index=7; vector_input=work0; vector_output=work1; end
            5: begin vector_op=3; vector_half=1; vector_output=next_x; end
            6: begin group_index=20; vector_input=next_x; end
            7,8,9: begin
                if (pc==7) begin group_index=24; vector_output=qb; end
                else if (pc==8) begin group_index=21; vector_output=kb; end
                else begin group_index=26; vector_output=vb; end
                vector_op=0; vector_cols=AUDIO_HIDDEN; vector_input=work0;
                vector_clipped=1;
            end
            10: group_index=25;
            11: begin
                group_index=23; vector_op=0; vector_cols=AUDIO_HIDDEN;
                vector_input=att; vector_output=work0; vector_clipped=1;
            end
            12: begin group_index=19; vector_input=work0; vector_output=work1; end
            13: begin vector_op=3; vector_input=next_x; vector_output=next_x; end
            14: begin group_index=17; vector_input=next_x; end
            15: begin
                group_index=16; vector_op=0; vector_rows=2*AUDIO_HIDDEN;
                vector_cols=AUDIO_HIDDEN; vector_input=work0; vector_output=work1;
                vector_clipped=1;
            end
            16: begin vector_op=4; vector_input=work1; vector_output=work0; end
            17: group_index=14;
            18: begin group_index=13; vector_input=work1; vector_output=work0; end
            19: begin vector_op=2; vector_input=work0; vector_output=work0; end
            20: begin
                group_index=15; vector_op=0; vector_cols=AUDIO_HIDDEN;
                vector_input=work0; vector_output=work1; vector_clipped=1;
            end
            21: begin vector_op=3; vector_input=next_x; vector_output=next_x; end
            22: begin group_index=12; vector_input=next_x; end
            23: begin
                group_index=9; vector_op=0; vector_rows=AUDIO_FFN;
                vector_cols=AUDIO_HIDDEN; vector_input=work0; vector_output=work1;
                vector_clipped=1;
            end
            24: begin
                vector_op=2; vector_rows=AUDIO_FFN; vector_input=work1; vector_output=work1;
            end
            25: begin
                group_index=10; vector_op=0; vector_cols=AUDIO_FFN;
                vector_input=work1; vector_output=work0; vector_clipped=1;
            end
            26: begin group_index=11; vector_input=work0; vector_output=work1; end
            27: begin
                vector_op=3; vector_input=next_x; vector_output=next_x; vector_half=1;
            end
            28: begin group_index=18; vector_input=next_x; vector_output=next_x; end
            default: group_index=8;
        endcase
    end
    anvil_e3_audio_vector #(.MAX_WIDTH(WIDTH)) vectors (
        .clk(clk), .rst_n(rst_n), .start_valid(starts[0]), .start_ready(readys[0]),
        .start_op(vector_op), .start_tokens({32'd0,count}),
        .start_rows(vector_rows), .start_cols(vector_cols), .start_weights(weight_addr),
        .start_input(vector_input), .start_aux(vector_aux), .start_output(vector_output),
        .start_clipped(vector_clipped), .start_bias(1'b0), .start_half(vector_half),
        .cmd_valid(valids[0]), .cmd_write(writes[0]), .cmd_ready(replies[0]),
        .cmd_addr(addrs[0]), .cmd_wdata(data[0]), .result_valid(results[0]),
        .result_ready(result_readys[0]), .result_data(result_data), .result_error(result_error),
        .done_valid(dones[0]), .done_ready(state==WAIT && owner==0), .done_error(errors[0])
    );
    anvil_e3_audio_attention #(
        .AUDIO_HIDDEN(AUDIO_HIDDEN), .AUDIO_HEADS(AUDIO_HEADS),
        .AUDIO_HEAD_DIM(AUDIO_HEAD_DIM), .AUDIO_CHUNK_SIZE(AUDIO_CHUNK_SIZE),
        .AUDIO_CONTEXT_LEFT(AUDIO_CONTEXT_LEFT), .AUDIO_CONTEXT_RIGHT(AUDIO_CONTEXT_RIGHT)
    ) attention (
        .clk(clk), .rst_n(rst_n), .start_valid(starts[1]), .start_ready(readys[1]),
        .tokens(count), .q_base(qb), .k_base(kb), .v_base(vb),
        .relative_weights(weight_addr), .scale_weights(scale_addr), .output_base(att),
        .cmd_valid(valids[1]), .cmd_write(writes[1]), .cmd_ready(replies[1]),
        .cmd_addr(addrs[1]), .cmd_wdata(data[1]), .result_valid(results[1]),
        .result_ready(result_readys[1]), .result_data(result_data), .result_error(result_error),
        .done_valid(dones[1]), .done_ready(state==WAIT && owner==1), .done_error(errors[1])
    );
    anvil_e3_audio_conv #(
        .INPUT_CHANNELS(AUDIO_HIDDEN), .OUTPUT_CHANNELS(AUDIO_HIDDEN), .FREQ_BINS(1),
        .KERNEL(AUDIO_CONV_KERNEL), .STRIDE(1), .DEPTHWISE(1)
    ) depthwise (
        .clk(clk), .rst_n(rst_n), .start_valid(starts[2]), .start_ready(readys[2]),
        .start_frames(count), .start_weights(weight_addr), .start_input(work0),
        .start_output(work1), .cmd_valid(valids[2]), .cmd_write(writes[2]),
        .cmd_ready(replies[2]), .cmd_addr(addrs[2]), .cmd_wdata(data[2]),
        .result_valid(results[2]), .result_ready(result_readys[2]),
        .result_data(result_data), .result_error(result_error), .done_valid(dones[2]),
        .done_ready(state==WAIT && owner==2), .done_error(errors[2])
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
            state<=IDLE; pc<=0; owner<=0; count<=0; layer<=0;
            w<=0; source_x<=0; next_x<=0; work0<=0; work1<=0;
            qb<=0; kb<=0; vb<=0; att<=0; error_hold<=0;
        end else case (state)
            IDLE: if (start_valid) begin
                count<=tokens; layer<=layer_index; w<=weights;
                source_x<=start_current_x ? x1_base:x0_base;
                next_x<=start_current_x ? x0_base:x1_base;
                work0<=work0_base; work1<=work1_base;
                qb<=q_base; kb<=k_base; vb<=v_base; att<=attention_base;
                pc<=0; owner<=0; error_hold<=0; state<=DISPATCH;
            end
            DISPATCH: begin
                if (count==0 || layer>=AUDIO_LAYERS) begin error_hold<=1; state<=DONE; end
                else if (layout_error || scale_layout_error) begin error_hold<=5; state<=DONE; end
                else begin
                    if (pc==10) owner<=1;
                    else if (pc==17) owner<=2;
                    else owner<=0;
                    state<=LAUNCH;
                end
            end
            LAUNCH: if (readys[owner]) state<=WAIT;
            WAIT: if (dones[owner]) begin
                if (errors[owner]!=0) begin error_hold<=errors[owner]; state<=DONE; end
                else if (pc==28) state<=DONE;
                else begin pc<=pc+1'b1; state<=DISPATCH; end
            end
            DONE: if (done_ready) state<=IDLE;
            default: begin error_hold<=6; state<=DONE; end
        endcase
    end
endmodule
