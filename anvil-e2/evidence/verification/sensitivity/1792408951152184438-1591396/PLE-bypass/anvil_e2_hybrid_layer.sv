module anvil_e2_hybrid_layer #(
    parameter integer VOCAB_SIZE=262144, HIDDEN_SIZE=512,
    PER_LAYER_INPUT_SIZE=512, INTERMEDIATE_SIZE=2048, EMBEDDING_DIM=768,
    NUM_LAYERS=24, NUM_Q_HEADS=4, LOCAL_KV_HEADS=2, FULL_KV_HEADS=1,
    LOCAL_HEAD_DIM=256, FULL_HEAD_DIM=512, SLIDING_WINDOW=512,
    STAGE=1, VISION=0, POSITION_EMBEDDING_SIZE=10240, PATCH_SIZE=16,
    parameter logic [127:0] RMS_EPSILON_Q80 = (128'd17 << 56)
) (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [31:0] tokens, valid_tokens,
    input wire [15:0] output_dim,
    input wire [63:0] weights, token_ids, positions, masks, scratch,
    input wire [63:0] x0_base, x1_base, ple_base, q_base, k_base, v_base,
    input wire [31:0] layer_index, patch_cols,
    input wire start_current_x,
    output reg cmd_valid, cmd_write,
    input wire cmd_ready,
    output reg [63:0] cmd_addr,
    output reg [31:0] cmd_wdata,
    input wire result_valid,
    output reg result_ready,
    input wire [31:0] result_data,
    input wire result_error,
    output wire emb_valid,
    input wire emb_ready,
    output wire signed [31:0] emb_data,
    output wire [15:0] emb_index,
    output wire emb_last,
    output wire done_valid,
    input wire done_ready,
    output wire [3:0] done_error
);
    function automatic integer maximum;
        input integer a,b;
        begin maximum=a>b ? a:b; end
    endfunction
    localparam integer DM=maximum(LOCAL_HEAD_DIM,FULL_HEAD_DIM);
    localparam integer KM=maximum(LOCAL_KV_HEADS,FULL_KV_HEADS);
    localparam integer WIDTH=STAGE==0 ? maximum(HIDDEN_SIZE,PER_LAYER_INPUT_SIZE):
        STAGE==2 ? maximum(HIDDEN_SIZE,EMBEDDING_DIM):
        maximum(maximum(HIDDEN_SIZE,VISION ? 1:PER_LAYER_INPUT_SIZE),
                maximum(INTERMEDIATE_SIZE,NUM_Q_HEADS*DM));
    localparam IDLE=0, DISPATCH=2, READ_REQ=3, READ_RSP=4,
        WRITE_REQ=5, WRITE_RSP=6, MAT_START=7, MAT_LOAD=8, MAT_RUN=9,
        NORM_START=10, NORM_REQ=11, NORM_RSP=12, NORM_FEED=13, NORM_OUT=14,
        VECTOR=15, VPRODUCT=16, VSAVE=17, VGELU_REQ=18, VGELU_RSP=19,
        ROPE_START=20, ROPE_RUN=21, ATT_START=22, ATT_RUN=23,
        POOL_START=24, POOL_FEED=25, POOL_WAIT=26, FLUSH=27, DONE=28,
        SCALE_START=29, SCALE_WAIT=30;
    reg [4:0] state;
    reg [7:0] pc, return_pc;
    reg [31:0] token, layer, head, pair_index, index, count, columns;
    reg [31:0] token_row, token_col;
    reg [31:0] token_id, position, token_mask;
    reg signed [31:0] scalar, norm_weight;
    reg [2:0] read_target, source_a, source_b, destination, vector_mode;
    reg [31:0] source_offset, destination_offset;
    reg [63:0] op_base;
    reg [63:0] bases [0:5];
    reg current_x;
    reg [3:0] error_hold;
    reg signed [47:0] xvec [0:WIDTH-1];
    reg signed [47:0] work [0:WIDTH-1];
    reg signed [47:0] temporary [0:WIDTH-1];
    reg signed [47:0] gate [0:WIDTH-1];
    reg signed [47:0] auxiliary [0:WIDTH-1];
    wire [63:0] layer_product={32'd0,layer}*64'd2863311531;
    wire [31:0] preceding_full=32'(layer_product>>34);
    wire full_mode=VISION || layer-preceding_full*6==5;
    wire [31:0] dim=full_mode ? FULL_HEAD_DIM:LOCAL_HEAD_DIM;
    wire [31:0] kv_heads=full_mode ? FULL_KV_HEADS:LOCAL_KV_HEADS;
    wire [63:0] x_base=current_x ? bases[5]:bases[0];
    wire [63:0] next_x_base=current_x ? bases[0]:bases[5];
    // Abort only after the held memory result has been retired.
    wire unit_rst_n=rst_n && state!=FLUSH;
    wire [31:0] rotary_dim=VISION ? dim>>1:dim;
    wire [31:0] rotary_pair=VISION && pair_index>=(dim>>2) ?
        pair_index-(dim>>2):pair_index;
    wire [31:0] rotary_offset=VISION && pair_index>=(dim>>2) ? dim>>1:0;
    wire [31:0] rotary_position=VISION ?
        (pair_index<(dim>>2) ? token_row:token_col):position;

    reg signed [47:0] source_a_data, source_b_data, source_offset_data;
    // Explicit array reads keep bank writes in each operand mux's sensitivity.
    always @* begin
        source_a_data=0;
        source_b_data=0;
        source_offset_data=0;
        if (rst_n) begin
            if (state==MAT_LOAD || state==VECTOR || state==VPRODUCT ||
                state==VGELU_REQ || state==SCALE_START) begin
                case (source_a)
                    0: source_a_data=xvec[index];
                    1: source_a_data=STAGE==0 ? 48'sd0:work[index];
                    2: source_a_data=temporary[index];
                    3: source_a_data=STAGE==1 ? gate[index]:48'sd0;
                    4: source_a_data=STAGE==1 ? auxiliary[index]:48'sd0;
                    default: source_a_data=0;
                endcase
            end
            if ((state==VECTOR && vector_mode==2) || state==VPRODUCT) begin
                case (source_b)
                    0: source_b_data=xvec[index];
                    1: source_b_data=STAGE==0 ? 48'sd0:work[index];
                    2: source_b_data=temporary[index];
                    3: source_b_data=STAGE==1 ? gate[index]:48'sd0;
                    4: source_b_data=STAGE==1 ? auxiliary[index]:48'sd0;
                    default: source_b_data=0;
                endcase
            end
            if (state==WRITE_REQ || state==NORM_FEED) begin
                case (source_a)
                    0: source_offset_data=xvec[source_offset+index];
                    1: source_offset_data=STAGE==0 ? 48'sd0:work[source_offset+index];
                    2: source_offset_data=temporary[source_offset+index];
                    3: source_offset_data=STAGE==1 ? gate[source_offset+index]:48'sd0;
                    4: source_offset_data=STAGE==1 ? auxiliary[source_offset+index]:48'sd0;
                    default: source_offset_data=0;
                endcase
            end
        end
    end
    function automatic signed [47:0] saturate;
        input signed [127:0] value;
        begin
            if (value>128'sd140737488289792) saturate=48'sh7fffffff0000;
            else if (value< -128'sd140737488355328) saturate=48'sh800000000000;
            else saturate=value[47:0];
        end
    endfunction
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
    function automatic [63:0] hidden_root;
        input integer width;
        reg [127:0] radicand, remainder, trial, root;
        integer i;
        begin
            radicand=128'(width)<<80; remainder=0; root=0;
            for (i=0;i<64;i=i+1) begin
                remainder=(remainder<<2)|{126'd0,radicand[127:126]};
                trial=(root<<2)|128'd1;
                if (remainder>=trial) begin
                    remainder=remainder-trial; root=(root<<1)|128'd1;
                end else root=root<<1;
                radicand=radicand<<2;
            end
            hidden_root=root[63:0];
        end
    endfunction
    localparam [63:0] H_ROOT=hidden_root(HIDDEN_SIZE);
    wire scale_ready, scale_valid, scale_error;
    wire signed [127:0] scale_data;
    generate if (STAGE==0) begin : projection_scaling
        anvil_e2_divide divider (
            .clk(clk), .rst_n(unit_rst_n), .in_valid(state==SCALE_START),
            .in_ready(scale_ready),
            .in_numerator($signed({{80{source_a_data[47]}},source_a_data})<<<40),
            .in_denominator({64'd0,H_ROOT}), .out_valid(scale_valid),
            .out_ready(state==SCALE_WAIT), .out_data(scale_data),
            .out_error(scale_error)
        );
    end else begin : no_projection_scaling
        assign scale_ready=0;
        assign scale_valid=0;
        assign scale_error=0;
        assign scale_data=0;
    end endgenerate
    function automatic signed [47:0] add_values;
        input signed [47:0] a,b;
        begin
            add_values=saturate({{80{a[47]}},a}+{{80{b[47]}},b});
        end
    endfunction
    task automatic abort_job;
        input [3:0] code;
        begin error_hold<=code; state<=FLUSH; end
    endtask
    task automatic finish_element;
        begin
            if (index==count-1) begin index<=0; pc<=return_pc; state<=DISPATCH; end
            else begin index<=index+1'b1; state<=VECTOR; end
        end
    endtask
    // Expand launches directly: clocked automatic-task inputs otherwise become
    // call-specific held signals and duplicate the synthesis process decoder.
`define E2_LOAD(address,length,bank,next_pc) \
    begin \
        op_base<=(address); count<=(length); destination<=(bank); \
        destination_offset<=0; index<=0; read_target<=0; \
        return_pc<=(next_pc); state<=READ_REQ; \
    end
`define E2_READ(address,target,next_pc) \
    begin \
        op_base<=(address); count<=1; index<=0; read_target<=(target); \
        return_pc<=(next_pc); state<=READ_REQ; \
    end
`define E2_WRITE(address,length,bank,next_pc) \
    begin \
        op_base<=(address); count<=(length); source_a<=(bank); \
        source_offset<=0; index<=0; return_pc<=(next_pc); state<=WRITE_REQ; \
    end
`define E2_MATRIX(address,rows,cols,src,dst,next_pc) \
    begin \
        op_base<=(address); count<=(rows); columns<=(cols); \
        source_a<=(src); destination<=(dst); source_offset<=0; \
        destination_offset<=0; index<=0; return_pc<=(next_pc); state<=MAT_START; \
    end
`define E2_NORM(address,length,offset,src,dst,next_pc) \
    begin \
        op_base<=(address); count<=(length); source_offset<=(offset); \
        destination_offset<=(offset); source_a<=(src); destination<=(dst); \
        index<=0; return_pc<=(next_pc); state<=NORM_START; \
    end
`define E2_VECTOR(mode,src_a,src_b,dst,length,next_pc) \
    begin \
        vector_mode<=(mode); source_a<=(src_a); source_b<=(src_b); \
        destination<=(dst); source_offset<=0; destination_offset<=0; \
        count<=(length); index<=0; return_pc<=(next_pc); state<=VECTOR; \
    end

    reg [4:0] tensor_id;
    wire [63:0] text_tensor_addr, vision_tensor_addr;
    wire [63:0] tensor_addr=VISION ? vision_tensor_addr:text_tensor_addr;
    wire text_tensor_error;
    wire tensor_error=!VISION && text_tensor_error;
    localparam [127:0] VH=HIDDEN_SIZE, VF=INTERMEDIATE_SIZE;
    localparam [127:0] VISION_LAYER_WORDS=4*VH+4*VH*VH+
        2*FULL_HEAD_DIM+3*VH*VF;
    generate if (VISION) begin : vision_addressing
    reg [127:0] vision_offset;
    always @* begin
        vision_offset=VH*3*PATCH_SIZE*PATCH_SIZE+
            2*POSITION_EMBEDDING_SIZE*VH+128'(layer)*VISION_LAYER_WORDS;
        case (tensor_id)
            5: vision_offset=vision_offset;
            20: vision_offset=vision_offset+VH;
            17: vision_offset=vision_offset+VH+VH*VH;
            21: vision_offset=vision_offset+VH+2*VH*VH;
            18: vision_offset=vision_offset+VH+3*VH*VH;
            19: vision_offset=vision_offset+VH+4*VH*VH;
            16: vision_offset=vision_offset+VH+4*VH*VH+FULL_HEAD_DIM;
            13: vision_offset=vision_offset+VH+4*VH*VH+2*FULL_HEAD_DIM;
            15: vision_offset=vision_offset+2*VH+4*VH*VH+2*FULL_HEAD_DIM;
            8: vision_offset=vision_offset+3*VH+4*VH*VH+2*FULL_HEAD_DIM;
            9: vision_offset=vision_offset+3*VH+4*VH*VH+2*FULL_HEAD_DIM+VH*VF;
            7: vision_offset=vision_offset+3*VH+4*VH*VH+2*FULL_HEAD_DIM+2*VH*VF;
            14: vision_offset=vision_offset+3*VH+4*VH*VH+2*FULL_HEAD_DIM+3*VH*VF;
            default: vision_offset=vision_offset;
        endcase
    end
    assign vision_tensor_addr=weights+64'(vision_offset*4);
    assign text_tensor_addr=0;
    assign text_tensor_error=0;
    end else begin : text_addressing
    assign vision_tensor_addr=0;
    anvil_e2_address #(
        .VOCAB_SIZE(VOCAB_SIZE), .HIDDEN_SIZE(HIDDEN_SIZE),
        .PER_LAYER_INPUT_SIZE(PER_LAYER_INPUT_SIZE), .INTERMEDIATE_SIZE(INTERMEDIATE_SIZE),
        .EMBEDDING_DIM(EMBEDDING_DIM), .NUM_LAYERS(NUM_LAYERS),
        .NUM_Q_HEADS(NUM_Q_HEADS), .LOCAL_KV_HEADS(LOCAL_KV_HEADS),
        .FULL_KV_HEADS(FULL_KV_HEADS), .LOCAL_HEAD_DIM(LOCAL_HEAD_DIM),
        .FULL_HEAD_DIM(FULL_HEAD_DIM)
    ) address_generator (
        .weights_base(weights), .scratch_base(scratch), .job_tokens(tokens),
        .tensor_id(tensor_id), .layer_index(layer), .element_index(64'd0),
        .scratch_region(3'd0), .scratch_word(64'd0),
        .tensor_addr(text_tensor_addr), .scratch_addr(),
        .tensor_rows(), .tensor_cols(),
        .weights_bytes(), .scratch_bytes(),
        .tensor_error(text_tensor_error), .scratch_error()
    );
    end endgenerate
    always @* begin
        if (STAGE==0) begin
            case (pc)
            4: tensor_id=3;
            6: tensor_id=4;
            default: tensor_id=0;
            endcase
        end else if (STAGE==2) begin
            case (pc)
            61: tensor_id=2;
            62: tensor_id=1;
            default: tensor_id=0;
            endcase
        end else begin
            case (pc)
            11: tensor_id=5;
            12: tensor_id=20;
            13: tensor_id=19;
            17: tensor_id=17;
            18: tensor_id=16;
            22: tensor_id=21;
            33: tensor_id=18;
            34: tensor_id=13;
            36: tensor_id=15;
            37: tensor_id=8;
            39: tensor_id=9;
            41: tensor_id=7;
            42: tensor_id=14;
            44: tensor_id=VISION ? 0:10;
            48: tensor_id=VISION ? 0:11;
            49: tensor_id=VISION ? 0:12;
            51: tensor_id=VISION ? 0:6;
            default: tensor_id=0;
            endcase
        end
    end

    wire signed [127:0] mac_sum;
    wire signed [47:0] mac_rounded;
    wire signed [95:0] mac_product;
    wire nready, nout_valid, nout_error;
    wire nready_raw;
    wire mat_clk, mat_active, norm_clk, norm_active;
    wire att_clk, att_active, rope_clk, rope_active, nonlinear_clk, nonlinear_active;
    wire mat_start_ready_raw, norm_start_ready_raw;
    wire att_start_ready_raw, rope_start_ready_raw;
    wire mat_start_ready, norm_start_ready, att_start_ready, rope_start_ready;
    wire pool_owns_norm=STAGE==2 && state==POOL_WAIT;
    anvil_e2_clock_gate mat_clock (
        .clk(clk), .rst_n(unit_rst_n),
        .enable(state==MAT_START || state==MAT_LOAD || state==MAT_RUN),
        .active(mat_active), .gated_clk(mat_clk)
    );
    anvil_e2_clock_gate norm_clock (
        .clk(clk), .rst_n(unit_rst_n),
        .enable((state>=NORM_START && state<=NORM_OUT) || pool_owns_norm),
        .active(norm_active), .gated_clk(norm_clk)
    );
    assign mat_start_ready=mat_active && mat_start_ready_raw;
    assign norm_start_ready=norm_active && norm_start_ready_raw;
    assign att_start_ready=att_active && att_start_ready_raw;
    assign rope_start_ready=rope_active && rope_start_ready_raw;
    assign nready=nonlinear_active && nready_raw;
    wire signed [47:0] nout_data;
    wire mat_in_ready, mat_cmd_valid, mat_result_ready;
    wire [63:0] mat_cmd_addr;
    wire mat_clear, mat_accumulate, mat_out_valid, mat_out_last, mat_done_valid;
    wire signed [47:0] mat_a, mat_b, mat_out_data;
    wire [31:0] mat_out_index;
    wire [3:0] mat_error;
    anvil_e2_matvec #(.MAX_INPUT(WIDTH)) matvec (
        .clk(mat_clk), .rst_n(unit_rst_n), .start_valid(state==MAT_START && mat_active),
        .start_ready(mat_start_ready_raw), .start_rows(count), .start_cols(columns),
        .start_weights(op_base), .in_valid(state==MAT_LOAD), .in_ready(mat_in_ready),
        .in_data(source_a_data), .cmd_valid(mat_cmd_valid),
        .cmd_ready(cmd_ready && state==MAT_RUN), .cmd_addr(mat_cmd_addr),
        .result_valid(result_valid && state==MAT_RUN), .result_ready(mat_result_ready),
        .result_data(result_data), .result_error(result_error),
        .mac_clear(mat_clear), .mac_accumulate(mat_accumulate),
        .mac_a(mat_a), .mac_b(mat_b), .mac_rounded(mac_rounded),
        .out_valid(mat_out_valid), .out_ready(state==MAT_RUN),
        .out_data(mat_out_data), .out_index(mat_out_index), .out_last(mat_out_last),
        .done_valid(mat_done_valid), .done_ready(state==MAT_RUN), .done_error(mat_error)
    );

    wire att_cmd_valid, att_result_ready;
    wire [63:0] att_cmd_addr;
    wire att_clear, att_accumulate, att_nvalid, att_nout_ready;
    wire [2:0] att_nop;
    wire signed [47:0] att_a, att_b, att_ndata, att_out_data;
    wire att_out_valid, att_out_last, att_done_valid;
    wire [31:0] att_out_index;
    wire [3:0] att_error;
    generate if (STAGE==1) begin : attention_stage
    anvil_e2_clock_gate attention_clock (
        .clk(clk), .rst_n(unit_rst_n), .enable(state==ATT_START || state==ATT_RUN),
        .active(att_active), .gated_clk(att_clk)
    );
    anvil_e2_attention #(
        .NUM_Q_HEADS(NUM_Q_HEADS), .LOCAL_KV_HEADS(LOCAL_KV_HEADS),
        .FULL_KV_HEADS(FULL_KV_HEADS), .LOCAL_HEAD_DIM(LOCAL_HEAD_DIM),
        .FULL_HEAD_DIM(FULL_HEAD_DIM), .SLIDING_WINDOW(SLIDING_WINDOW), .VISION(VISION)
    ) attention (
        .clk(att_clk), .rst_n(unit_rst_n), .start_valid(state==ATT_START && att_active),
        .start_ready(att_start_ready_raw), .start_tokens(tokens), .start_query(token),
        .start_head(head), .start_full(full_mode), .start_q_base(bases[2]),
        .start_k_base(bases[3]), .start_v_base(bases[4]),
        .start_positions_base(positions), .start_mask_base(masks),
        .cmd_valid(att_cmd_valid), .cmd_ready(cmd_ready && state==ATT_RUN),
        .cmd_addr(att_cmd_addr), .result_valid(result_valid && state==ATT_RUN),
        .result_ready(att_result_ready), .result_data(result_data),
        .result_error(result_error), .mac_clear(att_clear), .mac_accumulate(att_accumulate),
        .mac_a(att_a), .mac_b(att_b), .mac_sum(mac_sum), .mac_product(mac_product),
        .nonlinear_valid(att_nvalid), .nonlinear_ready(nready && state==ATT_RUN),
        .nonlinear_op(att_nop), .nonlinear_data(att_ndata),
        .nonlinear_out_valid(nout_valid && state==ATT_RUN),
        .nonlinear_out_ready(att_nout_ready), .nonlinear_out_data(nout_data),
        .nonlinear_out_error(nout_error), .out_valid(att_out_valid),
        .out_ready(state==ATT_RUN), .out_data(att_out_data),
        .out_index(att_out_index), .out_last(att_out_last),
        .done_valid(att_done_valid), .done_ready(state==ATT_RUN), .done_error(att_error)
    );
    end else begin : no_attention
        assign att_start_ready_raw=0;
        assign att_active=0;
        assign att_clk=1;
        assign att_cmd_valid=0;
        assign att_result_ready=0;
        assign att_cmd_addr=0;
        assign att_clear=0;
        assign att_accumulate=0;
        assign att_nvalid=0;
        assign att_nout_ready=0;
        assign att_nop=0;
        assign att_a=0;
        assign att_b=0;
        assign att_ndata=0;
        assign att_out_data=0;
        assign att_out_valid=0;
        assign att_out_last=0;
        assign att_done_valid=0;
        assign att_out_index=0;
        assign att_error=0;
    end endgenerate

    wire rope_clear, rope_accumulate, rope_nvalid, rope_nout_ready;
    wire [2:0] rope_nop;
    wire signed [47:0] rope_a, rope_b, rope_ndata, rope_lo, rope_hi;
    wire rope_out_valid, rope_error;
    generate if (STAGE==1) begin : rotary_stage
    anvil_e2_clock_gate rotary_clock (
        .clk(clk), .rst_n(unit_rst_n), .enable(state==ROPE_START || state==ROPE_RUN),
        .active(rope_active), .gated_clk(rope_clk)
    );
    anvil_e2_rope #(.VISION(VISION)) rope (
        .clk(rope_clk), .rst_n(unit_rst_n), .start_valid(state==ROPE_START && rope_active),
        .start_ready(rope_start_ready_raw), .start_full(full_mode),
        .start_position(rotary_position), .start_pair(rotary_pair), .start_dim(rotary_dim),
        .start_lo(temporary[head*dim+rotary_offset+rotary_pair]),
        .start_hi(temporary[head*dim+rotary_offset+rotary_pair+(rotary_dim>>1)]),
        .nonlinear_valid(rope_nvalid), .nonlinear_ready(nready && state==ROPE_RUN),
        .nonlinear_op(rope_nop), .nonlinear_data(rope_ndata),
        .nonlinear_out_valid(nout_valid && state==ROPE_RUN),
        .nonlinear_out_ready(rope_nout_ready), .nonlinear_out_data(nout_data),
        .nonlinear_out_error(nout_error), .mac_clear(rope_clear),
        .mac_accumulate(rope_accumulate), .mac_a(rope_a), .mac_b(rope_b),
        .mac_rounded(mac_rounded), .out_valid(rope_out_valid),
        .out_ready(state==ROPE_RUN), .out_lo(rope_lo), .out_hi(rope_hi),
        .out_error(rope_error)
    );
    end else begin : no_rotary
        assign rope_start_ready_raw=0;
        assign rope_active=0;
        assign rope_clk=1;
        assign rope_clear=0;
        assign rope_accumulate=0;
        assign rope_nvalid=0;
        assign rope_nout_ready=0;
        assign rope_nop=0;
        assign rope_a=0;
        assign rope_b=0;
        assign rope_ndata=0;
        assign rope_lo=0;
        assign rope_hi=0;
        assign rope_out_valid=0;
        assign rope_error=0;
    end endgenerate

    wire mac_clear=state==MAT_RUN ? mat_clear:
        state==ATT_RUN ? att_clear:state==ROPE_RUN ? rope_clear:state==VPRODUCT;
    wire mac_accumulate=state==MAT_RUN ? mat_accumulate:
        state==ATT_RUN ? att_accumulate:state==ROPE_RUN ? rope_accumulate:state==VPRODUCT;
    wire signed [47:0] mac_a=state==MAT_RUN ? mat_a:
        state==ATT_RUN ? att_a:state==ROPE_RUN ? rope_a:source_a_data;
    wire signed [47:0] mac_b=state==MAT_RUN ? mat_b:
        state==ATT_RUN ? att_b:state==ROPE_RUN ? rope_b:
        vector_mode==5 ? $signed({scalar,16'd0}):source_b_data;
    anvil_e2_mac mac (
        .clk(clk), .rst_n(unit_rst_n), .clear(mac_clear), .accumulate(mac_accumulate),
        .a(mac_a), .b(mac_b), .sum(mac_sum), .rounded(mac_rounded),
        .product(mac_product)
    );
    wire nvalid=state==ATT_RUN ? att_nvalid:
        state==ROPE_RUN ? rope_nvalid:state==VGELU_REQ;
    wire [2:0] nop=state==ATT_RUN ? att_nop:state==ROPE_RUN ? rope_nop:3'd5;
    wire signed [47:0] ndata=state==ATT_RUN ? att_ndata:
        state==ROPE_RUN ? rope_ndata:source_a_data;
    wire nout_ready=state==ATT_RUN ? att_nout_ready:
        state==ROPE_RUN ? rope_nout_ready:state==VGELU_RSP;
    generate if (STAGE==1) begin : nonlinear_stage
    anvil_e2_clock_gate nonlinear_clock (
        .clk(clk), .rst_n(unit_rst_n), .enable(nvalid || !nready_raw),
        .active(nonlinear_active), .gated_clk(nonlinear_clk)
    );
    anvil_e2_nonlinear nonlinear (
        .clk(nonlinear_clk), .rst_n(unit_rst_n),
        .in_valid(nvalid && nonlinear_active), .in_ready(nready_raw),
        .in_op(nop), .in_data(ndata), .out_valid(nout_valid), .out_ready(nout_ready),
        .out_data(nout_data), .out_error(nout_error)
    );
    end else begin : no_nonlinear
        assign nready_raw=0;
        assign nonlinear_active=0;
        assign nonlinear_clk=1;
        assign nout_valid=0;
        assign nout_error=0;
        assign nout_data=0;
    end endgenerate

    wire pool_start_ready, pool_token_ready, pool_nsvalid, pool_nsl2, pool_nivalid;
    wire [31:0] pool_nscount;
    wire signed [47:0] pool_nidata;
    wire signed [31:0] pool_niweight;
    wire pool_noready, pool_out_valid, pool_out_last, pool_done_valid;
    wire signed [31:0] pool_out_data;
    wire [15:0] pool_out_index;
    wire [3:0] pool_error;
    wire norm_in_ready, norm_out_valid, norm_out_last, norm_out_error;
    wire signed [47:0] norm_out_data;
    wire [31:0] norm_out_index;
    anvil_e2_norm #(
        .MAX_WIDTH(WIDTH), .RMS_EPSILON_Q80(RMS_EPSILON_Q80)
    ) norm (
        .clk(norm_clk), .rst_n(unit_rst_n),
        .start_valid(norm_active && (pool_owns_norm ? pool_nsvalid:state==NORM_START)),
        .start_ready(norm_start_ready_raw),
        .start_count(pool_owns_norm ? pool_nscount:count),
        .start_l2(pool_owns_norm && pool_nsl2),
        .in_valid(pool_owns_norm ? pool_nivalid:state==NORM_FEED),
        .in_ready(norm_in_ready),
        .in_data(pool_owns_norm ? pool_nidata:source_offset_data),
        .in_weight(pool_owns_norm ? pool_niweight:norm_weight),
        .out_valid(norm_out_valid),
        .out_ready(pool_owns_norm ? pool_noready:state==NORM_OUT),
        .out_data(norm_out_data), .out_index(norm_out_index),
        .out_last(norm_out_last), .out_error(norm_out_error)
    );
    generate if (STAGE==2) begin : pooling_stage
    anvil_e2_pool #(.EMBEDDING_DIM(EMBEDDING_DIM)) pool (
        .clk(clk), .rst_n(unit_rst_n), .start_valid(state==POOL_START),
        .start_ready(pool_start_ready), .start_tokens(tokens),
        .start_valid_tokens(valid_tokens), .start_output_dim(output_dim),
        .token_valid(state==POOL_FEED), .token_ready(pool_token_ready),
        .token_mask(token_mask[0]), .token_data(temporary[index]),
        .norm_start_valid(pool_nsvalid),
        .norm_start_ready(norm_start_ready && pool_owns_norm),
        .norm_start_count(pool_nscount), .norm_start_l2(pool_nsl2),
        .norm_in_valid(pool_nivalid), .norm_in_ready(norm_in_ready && pool_owns_norm),
        .norm_in_data(pool_nidata), .norm_in_weight(pool_niweight),
        .norm_out_valid(norm_out_valid && pool_owns_norm), .norm_out_ready(pool_noready),
        .norm_out_data(norm_out_data), .norm_out_index(norm_out_index),
        .norm_out_last(norm_out_last), .norm_out_error(norm_out_error),
        .out_valid(pool_out_valid), .out_ready(emb_ready && state==POOL_WAIT),
        .out_data(pool_out_data), .out_index(pool_out_index), .out_last(pool_out_last),
        .done_valid(pool_done_valid), .done_ready(state==POOL_WAIT), .done_error(pool_error)
    );
    end else begin : no_pooling
        assign pool_start_ready=0;
        assign pool_token_ready=0;
        assign pool_nsvalid=0;
        assign pool_nsl2=0;
        assign pool_nivalid=0;
        assign pool_nscount=0;
        assign pool_nidata=0;
        assign pool_niweight=0;
        assign pool_noready=0;
        assign pool_out_valid=0;
        assign pool_out_last=0;
        assign pool_done_valid=0;
        assign pool_out_data=0;
        assign pool_out_index=0;
        assign pool_error=0;
    end endgenerate

    assign start_ready=rst_n && state==IDLE;
    assign emb_valid=rst_n && state==POOL_WAIT && pool_out_valid;
    assign emb_data=rst_n ? pool_out_data:32'sd0;
    assign emb_index=rst_n ? pool_out_index:16'd0;
    assign emb_last=rst_n && state==POOL_WAIT && pool_out_last;
    assign done_valid=rst_n && state==DONE;
    assign done_error=rst_n ? error_hold:4'd0;
    always @* begin
        cmd_valid=0; cmd_write=0; cmd_addr=0; cmd_wdata=0; result_ready=0;
        if (rst_n) begin
            case (state)
                READ_REQ, NORM_REQ: begin
                    cmd_valid=1; cmd_addr=op_base+64'(index)*64'd4;
                end
                WRITE_REQ: begin
                    cmd_valid=1; cmd_write=1; cmd_addr=op_base+64'(index)*64'd4;
                    cmd_wdata=materialize(source_offset_data);
                end
                READ_RSP, WRITE_RSP, NORM_RSP: result_ready=1;
                MAT_RUN: begin
                    cmd_valid=mat_cmd_valid; cmd_addr=mat_cmd_addr;
                    result_ready=mat_result_ready;
                end
                ATT_RUN: begin
                    cmd_valid=att_cmd_valid; cmd_addr=att_cmd_addr;
                    result_ready=att_result_ready;
                end
            endcase
        end
    end

    reg bank_write_valid, temporary_hi_valid;
    reg [2:0] bank_write_select;
    reg [31:0] bank_write_index, temporary_hi_index;
    reg signed [47:0] bank_write_data, temporary_hi_data;
    wire [4:0] bank_write_enable;
    assign bank_write_enable[0]=rst_n && bank_write_valid && bank_write_select==0;
    assign bank_write_enable[1]=STAGE!=0 && rst_n && bank_write_valid && bank_write_select==1;
    assign bank_write_enable[2]=rst_n && bank_write_valid && bank_write_select==2;
    assign bank_write_enable[3]=STAGE==1 && rst_n && bank_write_valid && bank_write_select==3;
    assign bank_write_enable[4]=STAGE==1 && rst_n && bank_write_valid && bank_write_select==4;

    always @* begin
        bank_write_valid=0; bank_write_select=destination;
        bank_write_index=index; bank_write_data=0;
        temporary_hi_valid=0; temporary_hi_index=0; temporary_hi_data=0;
        if (rst_n) begin
            case (state)
                READ_RSP: if (result_valid && !result_error && read_target==0) begin
                    bank_write_valid=1;
                    bank_write_index=destination_offset+index;
                    bank_write_data={result_data,16'd0};
                end
                MAT_RUN: if (mat_out_valid && mat_out_index==index &&
                             mat_out_last==(index==count-1)) begin
                    bank_write_valid=1;
                    bank_write_data=mat_out_data;
                end
                NORM_OUT: if (norm_out_valid && !norm_out_error &&
                              norm_out_index==index &&
                              norm_out_last==(index==count-1)) begin
                    bank_write_valid=1;
                    bank_write_index=destination_offset+index;
                    bank_write_data=norm_out_data;
                end
                VECTOR: begin
                    case (vector_mode)
                        2: if (STAGE==1) begin
                            bank_write_valid=1;
                            bank_write_data=add_values(source_a_data,source_b_data);
                        end
                    endcase
                end
                SCALE_WAIT: if (STAGE==0 && scale_valid && !scale_error) begin
                    bank_write_valid=1;
                    bank_write_data=saturate(scale_data);
                end
                VSAVE: if (STAGE==1) begin
                    bank_write_valid=1; bank_write_data=mac_rounded;
                end
                VGELU_RSP: if (STAGE==1 && nout_valid && !nout_error) begin
                    bank_write_valid=1; bank_write_data=nout_data;
                end
                ROPE_RUN: if (STAGE==1 && rope_out_valid && !rope_error) begin
                    bank_write_valid=1; bank_write_select=2;
                    bank_write_index=head*dim+rotary_offset+rotary_pair;
                    bank_write_data=rope_lo;
                    temporary_hi_valid=1;
                    temporary_hi_index=head*dim+rotary_offset+rotary_pair+(rotary_dim>>1);
                    temporary_hi_data=rope_hi;
                end
                ATT_RUN: if (STAGE==1 && att_out_valid && att_out_index==index &&
                             att_out_last==(index==dim-1)) begin
                    bank_write_valid=1; bank_write_select=4;
                    bank_write_index=head*dim+index;
                    bank_write_data=att_out_data;
                end
            endcase
        end
    end

    // Unreset banks retain contents; the sequencer loads every value before use.
    always @(posedge clk) begin
        if (bank_write_enable[0]) xvec[bank_write_index]<=bank_write_data;
    end
    always @(posedge clk) begin
        if (bank_write_enable[1]) work[bank_write_index]<=bank_write_data;
    end
    always @(posedge clk) begin
        if (bank_write_enable[2]) temporary[bank_write_index]<=bank_write_data;
        // RoPE retires both halves together, with the original second-write priority.
        if (temporary_hi_valid) temporary[temporary_hi_index]<=temporary_hi_data;
    end
    always @(posedge clk) begin
        if (bank_write_enable[3]) gate[bank_write_index]<=bank_write_data;
    end
    always @(posedge clk) begin
        if (bank_write_enable[4]) auxiliary[bank_write_index]<=bank_write_data;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=IDLE; pc<=0; return_pc<=0; token<=0; layer<=0; head<=0;
            token_row<=0; token_col<=0;
            pair_index<=0; index<=0; count<=0; columns<=0; token_id<=0;
            position<=0; token_mask<=0; scalar<=0; norm_weight<=0;
            read_target<=0; source_a<=0; source_b<=0;
            destination<=0; vector_mode<=0; source_offset<=0; destination_offset<=0;
            op_base<=0; current_x<=0; error_hold<=0;
            bases[0]<=0; bases[1]<=0; bases[2]<=0;
            bases[3]<=0; bases[4]<=0; bases[5]<=0;
        end else begin
            case (state)
                IDLE: if (start_valid) begin
                    token<=0; layer<=layer_index; head<=0;
                    token_row<=0; token_col<=0;
                    current_x<=start_current_x;
                    bases[0]<=x0_base; bases[5]<=x1_base; bases[1]<=ple_base;
                    bases[2]<=q_base; bases[3]<=k_base; bases[4]<=v_base;
                    error_hold<=0; state<=DISPATCH;
                    if (STAGE==0) pc<=70;
                    else if (STAGE==1) pc<=9;
                    else pc<=58;
                end
                DISPATCH: begin
                    if (tensor_error) abort_job(5);
                    else if (STAGE==0) begin
                        case (pc)
                        70: `E2_LOAD(bases[0]+64'(token)*HIDDEN_SIZE*4,
                                        HIDDEN_SIZE,0,4)
                        4: `E2_MATRIX(tensor_addr+64'(layer)*PER_LAYER_INPUT_SIZE*HIDDEN_SIZE*4,
                                  PER_LAYER_INPUT_SIZE,HIDDEN_SIZE,0,2,5)
                        5: `E2_VECTOR(1,2,0,2,PER_LAYER_INPUT_SIZE,6)
                        6: `E2_NORM(tensor_addr,PER_LAYER_INPUT_SIZE,0,2,2,7)
                        7: `E2_WRITE(bases[1]+
                            (64'(token)*NUM_LAYERS+layer)*PER_LAYER_INPUT_SIZE*4,
                            PER_LAYER_INPUT_SIZE,2,8)
                        8: begin
                            if (layer==NUM_LAYERS-1) begin
                                layer<=0;
                                if (token==tokens-1) begin token<=0; state<=DONE; end
                                else begin token<=token+1'b1; pc<=70; end
                            end else begin layer<=layer+1'b1; pc<=4; end
                        end
                        default: abort_job(6);
                        endcase
                    end else if (STAGE==1) begin
                        case (pc)
                        9: begin
                            if (VISION) begin position<=0; pc<=10; end
                            else `E2_READ(positions+64'(token)*4,2,10)
                        end
                        10: `E2_LOAD(x_base+64'(token)*HIDDEN_SIZE*4,HIDDEN_SIZE,0,11)
                        11: `E2_NORM(tensor_addr,HIDDEN_SIZE,0,0,1,12)
                        12: begin
                            head<=0;
                            `E2_MATRIX(tensor_addr,NUM_Q_HEADS*dim,HIDDEN_SIZE,1,2,13)
                        end
                        13: `E2_NORM(tensor_addr,dim,head*dim,2,2,14)
                        14: begin pair_index<=0; return_pc<=15; state<=ROPE_START; end
                        15: begin
                            if (head==NUM_Q_HEADS-1) pc<=16;
                            else begin head<=head+1'b1; pc<=13; end
                        end
                        16: `E2_WRITE(bases[2]+64'(token)*NUM_Q_HEADS*DM*4,
                                         NUM_Q_HEADS*dim,2,17)
                        17: begin
                            head<=0; `E2_MATRIX(tensor_addr,kv_heads*dim,HIDDEN_SIZE,1,2,18)
                        end
                        18: `E2_NORM(tensor_addr,dim,head*dim,2,2,19)
                        19: begin pair_index<=0; return_pc<=20; state<=ROPE_START; end
                        20: begin
                            if (head==kv_heads-1) pc<=21;
                            else begin head<=head+1'b1; pc<=18; end
                        end
                        21: `E2_WRITE(bases[3]+64'(token)*KM*DM*4,
                                         kv_heads*dim,2,22)
                        22: `E2_MATRIX(tensor_addr,kv_heads*dim,HIDDEN_SIZE,1,2,23)
                        23: `E2_WRITE(bases[4]+64'(token)*KM*DM*4,kv_heads*dim,2,24)
                        24: begin
                            if (token==tokens-1) begin
                                token<=0; token_row<=0; token_col<=0; pc<=30;
                            end else begin
                                token<=token+1'b1; pc<=9;
                                if (token_col==patch_cols-1) begin
                                    token_col<=0; token_row<=token_row+1'b1;
                                end else token_col<=token_col+1'b1;
                            end
                        end
                        30: begin
                            head<=0;
                            `E2_LOAD(x_base+64'(token)*HIDDEN_SIZE*4,HIDDEN_SIZE,0,31)
                        end
                        31: begin index<=0; state<=ATT_START; end
                        32: begin
                            if (head==NUM_Q_HEADS-1) pc<=33;
                            else begin head<=head+1'b1; pc<=31; end
                        end
                        33: `E2_MATRIX(tensor_addr,HIDDEN_SIZE,NUM_Q_HEADS*dim,4,2,34)
                        34: `E2_NORM(tensor_addr,HIDDEN_SIZE,0,2,2,35)
                        35: `E2_VECTOR(2,0,2,0,HIDDEN_SIZE,36)
                        36: `E2_NORM(tensor_addr,HIDDEN_SIZE,0,0,1,37)
                        37: `E2_MATRIX(tensor_addr,INTERMEDIATE_SIZE,HIDDEN_SIZE,1,3,38)
                        38: `E2_VECTOR(4,3,0,3,INTERMEDIATE_SIZE,39)
                        39: `E2_MATRIX(tensor_addr,INTERMEDIATE_SIZE,HIDDEN_SIZE,1,4,40)
                        40: `E2_VECTOR(3,3,4,4,INTERMEDIATE_SIZE,41)
                        41: `E2_MATRIX(tensor_addr,HIDDEN_SIZE,INTERMEDIATE_SIZE,4,2,42)
                        42: `E2_NORM(tensor_addr,HIDDEN_SIZE,0,2,2,43)
                        43: begin
                            if (VISION) `E2_VECTOR(2,0,2,0,HIDDEN_SIZE,53)
                            else `E2_VECTOR(2,0,2,0,HIDDEN_SIZE,44)
                        end
                        44: if (!VISION)
                            `E2_MATRIX(tensor_addr,PER_LAYER_INPUT_SIZE,HIDDEN_SIZE,0,3,45)
                            else abort_job(6);
                        45: if (!VISION)
                            `E2_VECTOR(4,3,0,3,PER_LAYER_INPUT_SIZE,46)
                            else abort_job(6);
                        46: if (!VISION) `E2_LOAD(bases[1]+
                            (64'(token)*NUM_LAYERS+layer)*PER_LAYER_INPUT_SIZE*4,
                            PER_LAYER_INPUT_SIZE,4,47)
                            else abort_job(6);
                        47: if (!VISION) `E2_VECTOR(3,3,4,4,PER_LAYER_INPUT_SIZE,48)
                            else abort_job(6);
                        48: if (!VISION) `E2_MATRIX(tensor_addr,HIDDEN_SIZE,PER_LAYER_INPUT_SIZE,4,2,49)
                            else abort_job(6);
                        49: if (!VISION) `E2_NORM(tensor_addr,HIDDEN_SIZE,0,2,2,50)
                            else abort_job(6);
                        50: if (!VISION) begin pc<=51; end
                            else abort_job(6);
                        51: if (!VISION) `E2_READ(tensor_addr,4,52)
                            else abort_job(6);
                        52: if (!VISION) `E2_VECTOR(5,0,0,0,HIDDEN_SIZE,53)
                            else abort_job(6);
                        53: `E2_WRITE(next_x_base+64'(token)*HIDDEN_SIZE*4,
                                         HIDDEN_SIZE,0,54)
                        54: begin
                            if (token==tokens-1) begin
                                token<=0; state<=DONE;
                            end else begin token<=token+1'b1; pc<=30; end
                        end
                        default: abort_job(6);
                        endcase
                    end else begin
                        case (pc)
                        58: state<=POOL_START;
                        60: `E2_LOAD(x_base+64'(token)*HIDDEN_SIZE*4,HIDDEN_SIZE,0,61)
                        61: `E2_NORM(tensor_addr,HIDDEN_SIZE,0,0,1,62)
                        62: `E2_MATRIX(tensor_addr,EMBEDDING_DIM,HIDDEN_SIZE,1,2,63)
                        63: `E2_READ(masks+64'(token)*4,3,64)
                        64: begin index<=0; state<=POOL_FEED; end
                        65: begin
                            if (token==tokens-1) state<=POOL_WAIT;
                            else begin token<=token+1'b1; pc<=60; end
                        end
                        default: abort_job(6);
                        endcase
                    end
                end
                READ_REQ: if (cmd_ready) state<=READ_RSP;
                READ_RSP: if (result_valid) begin
                    if (result_error) abort_job(3);
                    else if ((read_target==1 && result_data>=VOCAB_SIZE) ||
                             (read_target==3 && result_data>1)) abort_job(2);
                    else begin
                        case (read_target)
                            1: token_id<=result_data;
                            2: position<=result_data;
                            3: token_mask<=result_data;
                            4: scalar<=result_data;
                        endcase
                        if (index==count-1) begin pc<=return_pc; index<=0; state<=DISPATCH; end
                        else begin index<=index+1'b1; state<=READ_REQ; end
                    end
                end
                WRITE_REQ: if (cmd_ready) state<=WRITE_RSP;
                WRITE_RSP: if (result_valid) begin
                    if (result_error) abort_job(3);
                    else if (index==count-1) begin pc<=return_pc; index<=0; state<=DISPATCH; end
                    else begin index<=index+1'b1; state<=WRITE_REQ; end
                end
                MAT_START: if (mat_start_ready) begin index<=0; state<=MAT_LOAD; end
                MAT_LOAD: if (mat_in_ready) begin
                    if (index==columns-1) begin index<=0; state<=MAT_RUN; end
                    else index<=index+1'b1;
                end
                MAT_RUN: begin
                    if (mat_out_valid) begin
                        if (mat_out_index!=index || mat_out_last!=(index==count-1))
                            abort_job(6);
                        else index<=index+1'b1;
                    end
                    if (mat_done_valid) begin
                        if (mat_error!=0) abort_job(mat_error==1 ? 4'd6:mat_error);
                        else if (index!=count) abort_job(6);
                        else begin index<=0; pc<=return_pc; state<=DISPATCH; end
                    end
                end
                NORM_START: if (norm_start_ready) begin index<=0; state<=NORM_REQ; end
                NORM_REQ: if (cmd_ready) state<=NORM_RSP;
                NORM_RSP: if (result_valid) begin
                    if (result_error) abort_job(3);
                    else begin norm_weight<=result_data; state<=NORM_FEED; end
                end
                NORM_FEED: if (norm_in_ready) begin
                    if (index==count-1) begin index<=0; state<=NORM_OUT; end
                    else begin index<=index+1'b1; state<=NORM_REQ; end
                end
                NORM_OUT: if (norm_out_valid) begin
                    if (norm_out_error || norm_out_index!=index ||
                        norm_out_last!=(index==count-1)) abort_job(6);
                    else begin
                        if (index==count-1) begin index<=0; pc<=return_pc; state<=DISPATCH; end
                        else index<=index+1'b1;
                    end
                end
                VECTOR: begin
                    case (vector_mode)
                        1: if (STAGE==0) state<=SCALE_START; else abort_job(6);
                        2: if (STAGE==1) finish_element; else abort_job(6);
                        3,5: if (STAGE==1) state<=VPRODUCT; else abort_job(6);
                        4: if (STAGE==1) state<=VGELU_REQ; else abort_job(6);
                        default: abort_job(6);
                    endcase
                end
                SCALE_START: if (STAGE!=0) abort_job(6);
                    else if (scale_ready) state<=SCALE_WAIT;
                SCALE_WAIT: if (STAGE!=0) abort_job(6);
                    else if (scale_valid) begin
                        if (scale_error) abort_job(6);
                        else finish_element;
                    end
                VPRODUCT: if (STAGE==1) state<=VSAVE; else abort_job(6);
                VSAVE: if (STAGE==1) finish_element; else abort_job(6);
                VGELU_REQ: if (STAGE!=1) abort_job(6);
                    else if (nready) state<=VGELU_RSP;
                VGELU_RSP: if (STAGE!=1) abort_job(6);
                    else if (nout_valid) begin
                    if (nout_error) abort_job(6);
                    else finish_element;
                end
                ROPE_START: if (STAGE!=1) abort_job(6);
                    else if (rope_start_ready) state<=ROPE_RUN;
                ROPE_RUN: if (STAGE!=1) abort_job(6);
                    else if (rope_out_valid) begin
                    if (rope_error) abort_job(6);
                    else begin
                        if (pair_index==(dim>>1)-1) begin pc<=return_pc; state<=DISPATCH; end
                        else begin pair_index<=pair_index+1'b1; state<=ROPE_START; end
                    end
                end
                ATT_START: if (STAGE!=1) abort_job(6);
                    else if (att_start_ready) state<=ATT_RUN;
                ATT_RUN: if (STAGE!=1) abort_job(6); else begin
                    if (att_out_valid) begin
                        if (att_out_index!=index || att_out_last!=(index==dim-1))
                            abort_job(6);
                        else index<=index+1'b1;
                    end
                    if (att_done_valid) begin
                        if (att_error!=0) abort_job(att_error==1 ? 4'd6:att_error);
                        else if (index!=dim) abort_job(6);
                        else begin index<=0; pc<=32; state<=DISPATCH; end
                    end
                end
                POOL_START: if (STAGE!=2) abort_job(6);
                    else if (pool_start_ready) begin token<=0; pc<=60; state<=DISPATCH; end
                POOL_FEED: if (STAGE!=2) abort_job(6);
                    else if (pool_token_ready) begin
                    if (index==EMBEDDING_DIM-1) begin index<=0; pc<=65; state<=DISPATCH; end
                    else index<=index+1'b1;
                end
                POOL_WAIT: if (STAGE!=2) abort_job(6);
                    else if (pool_done_valid) begin
                    if (pool_error!=0) abort_job(pool_error==1 ? 4'd6:pool_error);
                    else begin error_hold<=0; state<=DONE; end
                end
                FLUSH: state<=DONE;
                DONE: if (done_ready) state<=IDLE;
                default: abort_job(6);
            endcase
        end
    end
endmodule
`undef E2_LOAD
`undef E2_READ
`undef E2_WRITE
`undef E2_MATRIX
`undef E2_NORM
`undef E2_VECTOR
