module anvil_e1_sequencer #(
    parameter integer VOCAB_SIZE=262144, HIDDEN_SIZE=512,
    PER_LAYER_INPUT_SIZE=512, INTERMEDIATE_SIZE=2048, EMBEDDING_DIM=768,
    NUM_LAYERS=24, NUM_Q_HEADS=4, LOCAL_KV_HEADS=2, FULL_KV_HEADS=1,
    LOCAL_HEAD_DIM=256, FULL_HEAD_DIM=512, SLIDING_WINDOW=512
) (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [31:0] tokens, valid_tokens,
    input wire [15:0] output_dim,
    input wire [63:0] weights, token_ids, positions, masks, scratch,
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
    localparam integer WIDTH=maximum(maximum(HIDDEN_SIZE,PER_LAYER_INPUT_SIZE),
        maximum(maximum(INTERMEDIATE_SIZE,EMBEDDING_DIM),NUM_Q_HEADS*DM));
    localparam IDLE=0, BASES=1, DISPATCH=2, READ_REQ=3, READ_RSP=4,
        WRITE_REQ=5, WRITE_RSP=6, MAT_START=7, MAT_LOAD=8, MAT_RUN=9,
        NORM_START=10, NORM_REQ=11, NORM_RSP=12, NORM_FEED=13, NORM_OUT=14,
        VECTOR=15, VPRODUCT=16, VSAVE=17, VGELU_REQ=18, VGELU_RSP=19,
        ROPE_START=20, ROPE_RUN=21, ATT_START=22, ATT_RUN=23,
        POOL_START=24, POOL_FEED=25, POOL_WAIT=26, FLUSH=27, DONE=28,
        DIVIDE=29, PROJECTION_SAVE=30, DIV_DONE=31;
    reg [4:0] state;
    reg [7:0] pc, return_pc;
    reg [31:0] token, layer, head, pair_index, index, count, columns;
    reg [2:0] layer_phase;
    reg [31:0] token_id, position, token_mask;
    reg signed [31:0] scalar, norm_weight;
    reg [2:0] base_index, read_target, source_a, source_b, destination, vector_mode;
    reg [31:0] source_offset, destination_offset;
    reg [63:0] op_base;
    reg [63:0] bases [0:5];
    reg current_x;
    reg [3:0] error_hold;
    reg signed [31:0] xvec [0:WIDTH-1];
    reg signed [31:0] work [0:WIDTH-1];
    reg signed [31:0] temporary [0:WIDTH-1];
    reg signed [31:0] gate [0:WIDTH-1];
    reg signed [31:0] auxiliary [0:WIDTH-1];
    wire full_mode=layer_phase==3'd5;
    wire [31:0] dim=full_mode ? FULL_HEAD_DIM:LOCAL_HEAD_DIM;
    wire [31:0] kv_heads=full_mode ? FULL_KV_HEADS:LOCAL_KV_HEADS;
    wire [63:0] x_base=current_x ? bases[5]:bases[0];
    wire [63:0] next_x_base=current_x ? bases[0]:bases[5];
    // Abort only after the held memory result has been retired.
    wire unit_rst_n=rst_n && state!=FLUSH;

    function automatic signed [31:0] bank_read;
        input [2:0] bank;
        input [31:0] element;
        begin
            case (bank)
                0: bank_read=xvec[element];
                1: bank_read=work[element];
                2: bank_read=temporary[element];
                3: bank_read=gate[element];
                4: bank_read=auxiliary[element];
                default: bank_read=0;
            endcase
        end
    endfunction
    function automatic signed [31:0] saturate;
        input signed [95:0] value;
        begin
            if (value>96'sd2147483647) saturate=32'sh7fffffff;
            else if (value< -96'sd2147483648) saturate=32'sh80000000;
            else saturate=value[31:0];
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
    function automatic signed [31:0] embedding_scale;
        input signed [31:0] value;
        reg signed [95:0] product, quotient;
        begin
            product={{64{value[31]}},value}*$signed({32'd0,H_ROOT});
            quotient=product>>>40;
            if (product[39:0]>40'h8000000000 ||
                (product[39:0]==40'h8000000000 && quotient[0]))
                quotient=quotient+96'sd1;
            embedding_scale=saturate(quotient);
        end
    endfunction
    reg [95:0] div_quotient;
    reg [96:0] div_remainder;
    reg div_negative;
    reg [5:0] div_iteration;
    reg signed [31:0] div_sat_reg;
    reg [95:0] div_next_quotient;
    reg [96:0] div_next_remainder;
    integer div_bit;
    always @* begin
        div_next_quotient=div_quotient;
        div_next_remainder=div_remainder;
        if (state==DIVIDE) begin
            for (div_bit=0; div_bit<2; div_bit=div_bit+1) begin
                div_next_remainder={div_next_remainder[95:0],div_next_quotient[95]};
                div_next_quotient=div_next_quotient<<1;
                if (div_next_remainder>={33'd0,H_ROOT}) begin
                    div_next_remainder=div_next_remainder-{33'd0,H_ROOT};
                    div_next_quotient[0]=1'b1;
                end
            end
        end
    end
    wire [95:0] div_rounded_magnitude=div_quotient+
        ((div_remainder>{33'd0,H_ROOT}-div_remainder ||
          (div_remainder=={33'd0,H_ROOT}-div_remainder && div_quotient[0]))
         ? 96'd1:96'd0);
    wire signed [95:0] div_result=div_negative ?
        -$signed(div_rounded_magnitude):$signed(div_rounded_magnitude);
    wire signed [31:0] projection_input=bank_read(source_a,index);
    wire signed [95:0] projection_numerator=
        $signed({{64{projection_input[31]}},projection_input})<<<40;
    function automatic signed [31:0] add_values;
        input signed [31:0] a,b;
        begin
            add_values=saturate({{64{a[31]}},a}+{{64{b[31]}},b});
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
    task automatic load_vector;
        input [63:0] address;
        input [31:0] length;
        input [2:0] bank;
        input [7:0] next_pc;
        begin
            op_base<=address; count<=length; destination<=bank;
            destination_offset<=0; index<=0; read_target<=0;
            return_pc<=next_pc; state<=READ_REQ;
        end
    endtask
    task automatic read_scalar;
        input [63:0] address;
        input [2:0] target;
        input [7:0] next_pc;
        begin
            op_base<=address; count<=1; index<=0; read_target<=target;
            return_pc<=next_pc; state<=READ_REQ;
        end
    endtask
    task automatic write_vector;
        input [63:0] address;
        input [31:0] length;
        input [2:0] bank;
        input [7:0] next_pc;
        begin
            op_base<=address; count<=length; source_a<=bank;
            source_offset<=0; index<=0; return_pc<=next_pc; state<=WRITE_REQ;
        end
    endtask
    task automatic matrix;
        input [63:0] address;
        input [31:0] rows, cols;
        input [2:0] src,dst;
        input [7:0] next_pc;
        begin
            op_base<=address; count<=rows; columns<=cols;
            source_a<=src; destination<=dst; source_offset<=0;
            destination_offset<=0; index<=0; return_pc<=next_pc; state<=MAT_START;
        end
    endtask
    task automatic normalize;
        input [63:0] address;
        input [31:0] length, offset;
        input [2:0] src,dst;
        input [7:0] next_pc;
        begin
            op_base<=address; count<=length; source_offset<=offset;
            destination_offset<=offset; source_a<=src; destination<=dst;
            index<=0; return_pc<=next_pc; state<=NORM_START;
        end
    endtask
    task automatic vector_operation;
        input [2:0] mode,src_a,src_b,dst;
        input [31:0] length;
        input [7:0] next_pc;
        begin
            vector_mode<=mode; source_a<=src_a; source_b<=src_b;
            destination<=dst; source_offset<=0; destination_offset<=0;
            count<=length; index<=0; return_pc<=next_pc; state<=VECTOR;
        end
    endtask

    reg [4:0] tensor_id;
    wire [63:0] tensor_addr, scratch_addr;
    wire [31:0] tensor_rows, tensor_cols;
    wire [127:0] weights_bytes, scratch_bytes;
    wire tensor_error, scratch_error;
    always @* begin
        case (pc)
            1: tensor_id=0;
            4: tensor_id=3;
            6: tensor_id=4;
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
            44: tensor_id=10;
            48: tensor_id=11;
            49: tensor_id=12;
            51: tensor_id=6;
            61: tensor_id=2;
            62: tensor_id=1;
            default: tensor_id=0;
        endcase
    end
    anvil_e1_address #(
        .VOCAB_SIZE(VOCAB_SIZE), .HIDDEN_SIZE(HIDDEN_SIZE),
        .PER_LAYER_INPUT_SIZE(PER_LAYER_INPUT_SIZE), .INTERMEDIATE_SIZE(INTERMEDIATE_SIZE),
        .EMBEDDING_DIM(EMBEDDING_DIM), .NUM_LAYERS(NUM_LAYERS),
        .NUM_Q_HEADS(NUM_Q_HEADS), .LOCAL_KV_HEADS(LOCAL_KV_HEADS),
        .FULL_KV_HEADS(FULL_KV_HEADS), .LOCAL_HEAD_DIM(LOCAL_HEAD_DIM),
        .FULL_HEAD_DIM(FULL_HEAD_DIM)
    ) address_generator (
        .weights_base(weights), .scratch_base(scratch), .job_tokens(tokens),
        .tensor_id(tensor_id), .layer_index(layer), .element_index(64'd0),
        .scratch_region(base_index), .scratch_word(64'd0),
        .tensor_addr(tensor_addr), .scratch_addr(scratch_addr),
        .tensor_rows(tensor_rows), .tensor_cols(tensor_cols),
        .weights_bytes(weights_bytes), .scratch_bytes(scratch_bytes),
        .tensor_error(tensor_error), .scratch_error(scratch_error)
    );

    wire signed [95:0] mac_sum;
    wire signed [31:0] mac_rounded;
    wire nready, nout_valid, nout_error;
    wire signed [31:0] nout_data;

    wire mat_start_ready, mat_in_ready, mat_cmd_valid, mat_result_ready;
    wire [63:0] mat_cmd_addr;
    wire mat_clear, mat_accumulate, mat_out_valid, mat_out_last, mat_done_valid;
    wire signed [31:0] mat_a, mat_b, mat_out_data;
    wire [31:0] mat_out_index;
    wire [3:0] mat_error;
    anvil_e1_matvec #(.MAX_INPUT(WIDTH)) matvec (
        .clk(clk), .rst_n(unit_rst_n), .start_valid(state==MAT_START),
        .start_ready(mat_start_ready), .start_rows(count), .start_cols(columns),
        .start_weights(op_base), .in_valid(state==MAT_LOAD), .in_ready(mat_in_ready),
        .in_data(bank_read(source_a,index)), .cmd_valid(mat_cmd_valid),
        .cmd_ready(cmd_ready && state==MAT_RUN), .cmd_addr(mat_cmd_addr),
        .result_valid(result_valid && state==MAT_RUN), .result_ready(mat_result_ready),
        .result_data(result_data), .result_error(result_error),
        .mac_clear(mat_clear), .mac_accumulate(mat_accumulate),
        .mac_a(mat_a), .mac_b(mat_b), .mac_rounded(mac_rounded),
        .out_valid(mat_out_valid), .out_ready(state==MAT_RUN),
        .out_data(mat_out_data), .out_index(mat_out_index), .out_last(mat_out_last),
        .done_valid(mat_done_valid), .done_ready(state==MAT_RUN), .done_error(mat_error)
    );

    wire att_start_ready, att_cmd_valid, att_result_ready;
    wire [63:0] att_cmd_addr;
    wire att_clear, att_accumulate, att_nvalid, att_nout_ready;
    wire [2:0] att_nop;
    wire signed [31:0] att_a, att_b, att_ndata, att_out_data;
    wire att_out_valid, att_out_last, att_done_valid;
    wire [31:0] att_out_index;
    wire [3:0] att_error;
    anvil_e1_attention #(
        .NUM_Q_HEADS(NUM_Q_HEADS), .LOCAL_KV_HEADS(LOCAL_KV_HEADS),
        .FULL_KV_HEADS(FULL_KV_HEADS), .LOCAL_HEAD_DIM(LOCAL_HEAD_DIM),
        .FULL_HEAD_DIM(FULL_HEAD_DIM), .SLIDING_WINDOW(SLIDING_WINDOW)
    ) attention (
        .clk(clk), .rst_n(unit_rst_n), .start_valid(state==ATT_START),
        .start_ready(att_start_ready), .start_tokens(tokens), .start_query(token),
        .start_head(head), .start_full(full_mode), .start_q_base(bases[2]),
        .start_k_base(bases[3]), .start_v_base(bases[4]),
        .start_positions_base(positions), .start_mask_base(masks),
        .cmd_valid(att_cmd_valid), .cmd_ready(cmd_ready && state==ATT_RUN),
        .cmd_addr(att_cmd_addr), .result_valid(result_valid && state==ATT_RUN),
        .result_ready(att_result_ready), .result_data(result_data),
        .result_error(result_error), .mac_clear(att_clear), .mac_accumulate(att_accumulate),
        .mac_a(att_a), .mac_b(att_b), .mac_sum(mac_sum),
        .nonlinear_valid(att_nvalid), .nonlinear_ready(nready && state==ATT_RUN),
        .nonlinear_op(att_nop), .nonlinear_data(att_ndata),
        .nonlinear_out_valid(nout_valid && state==ATT_RUN),
        .nonlinear_out_ready(att_nout_ready), .nonlinear_out_data(nout_data),
        .nonlinear_out_error(nout_error), .out_valid(att_out_valid),
        .out_ready(state==ATT_RUN), .out_data(att_out_data),
        .out_index(att_out_index), .out_last(att_out_last),
        .done_valid(att_done_valid), .done_ready(state==ATT_RUN), .done_error(att_error)
    );

    wire rope_start_ready, rope_clear, rope_accumulate, rope_nvalid, rope_nout_ready;
    wire [2:0] rope_nop;
    wire signed [31:0] rope_a, rope_b, rope_ndata, rope_lo, rope_hi;
    wire rope_out_valid, rope_error;
    anvil_e1_rope rope (
        .clk(clk), .rst_n(unit_rst_n), .start_valid(state==ROPE_START),
        .start_ready(rope_start_ready), .start_full(full_mode),
        .start_position(position), .start_pair(pair_index), .start_dim(dim),
        .start_lo(temporary[head*dim+pair_index]),
        .start_hi(temporary[head*dim+pair_index+(dim>>1)]),
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

    wire mac_clear=state==MAT_RUN ? mat_clear:
        state==ATT_RUN ? att_clear:state==ROPE_RUN ? rope_clear:state==VPRODUCT;
    wire mac_accumulate=state==MAT_RUN ? mat_accumulate:
        state==ATT_RUN ? att_accumulate:state==ROPE_RUN ? rope_accumulate:state==VPRODUCT;
    wire signed [31:0] mac_a=state==MAT_RUN ? mat_a:
        state==ATT_RUN ? att_a:state==ROPE_RUN ? rope_a:bank_read(source_a,index);
    wire signed [31:0] mac_b=state==MAT_RUN ? mat_b:
        state==ATT_RUN ? att_b:state==ROPE_RUN ? rope_b:
        vector_mode==5 ? scalar:bank_read(source_b,index);
    anvil_e1_mac mac (
        .clk(clk), .rst_n(unit_rst_n), .clear(mac_clear), .accumulate(mac_accumulate),
        .a(mac_a), .b(mac_b), .sum(mac_sum), .rounded(mac_rounded)
    );
    wire nvalid=state==ATT_RUN ? att_nvalid:
        state==ROPE_RUN ? rope_nvalid:state==VGELU_REQ;
    wire [2:0] nop=state==ATT_RUN ? att_nop:state==ROPE_RUN ? rope_nop:3'd5;
    wire signed [31:0] ndata=state==ATT_RUN ? att_ndata:
        state==ROPE_RUN ? rope_ndata:bank_read(source_a,index);
    wire nout_ready=state==ATT_RUN ? att_nout_ready:
        state==ROPE_RUN ? rope_nout_ready:state==VGELU_RSP;
    anvil_e1_nonlinear nonlinear (
        .clk(clk), .rst_n(unit_rst_n), .in_valid(nvalid), .in_ready(nready),
        .in_op(nop), .in_data(ndata), .out_valid(nout_valid), .out_ready(nout_ready),
        .out_data(nout_data), .out_error(nout_error)
    );

    wire pool_start_ready, pool_token_ready, pool_nsvalid, pool_nsl2, pool_nivalid;
    wire [31:0] pool_nscount;
    wire signed [31:0] pool_nidata, pool_niweight;
    wire pool_noready, pool_out_valid, pool_out_last, pool_done_valid;
    wire signed [31:0] pool_out_data;
    wire [15:0] pool_out_index;
    wire [3:0] pool_error;
    wire norm_start_ready, norm_in_ready, norm_out_valid, norm_out_last, norm_out_error;
    wire signed [31:0] norm_out_data;
    wire [31:0] norm_out_index;
    wire pool_owns_norm=state==POOL_WAIT;
    anvil_e1_norm #(.MAX_WIDTH(WIDTH)) norm (
        .clk(clk), .rst_n(unit_rst_n),
        .start_valid(pool_owns_norm ? pool_nsvalid:state==NORM_START),
        .start_ready(norm_start_ready),
        .start_count(pool_owns_norm ? pool_nscount:count),
        .start_l2(pool_owns_norm && pool_nsl2),
        .in_valid(pool_owns_norm ? pool_nivalid:state==NORM_FEED),
        .in_ready(norm_in_ready),
        .in_data(pool_owns_norm ? pool_nidata:bank_read(source_a,source_offset+index)),
        .in_weight(pool_owns_norm ? pool_niweight:norm_weight),
        .out_valid(norm_out_valid),
        .out_ready(pool_owns_norm ? pool_noready:state==NORM_OUT),
        .out_data(norm_out_data), .out_index(norm_out_index),
        .out_last(norm_out_last), .out_error(norm_out_error)
    );
    anvil_e1_pool #(.EMBEDDING_DIM(EMBEDDING_DIM)) pool (
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
                    cmd_wdata=bank_read(source_a,source_offset+index);
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
    reg signed [31:0] bank_write_data, temporary_hi_data;
    wire [4:0] bank_write_enable;
    assign bank_write_enable[0]=rst_n && bank_write_valid && bank_write_select==0;
    assign bank_write_enable[1]=rst_n && bank_write_valid && bank_write_select==1;
    assign bank_write_enable[2]=rst_n && bank_write_valid && bank_write_select==2;
    assign bank_write_enable[3]=rst_n && bank_write_valid && bank_write_select==3;
    assign bank_write_enable[4]=rst_n && bank_write_valid && bank_write_select==4;

    always @* begin
        bank_write_valid=0; bank_write_select=destination;
        bank_write_index=index; bank_write_data=0;
        temporary_hi_valid=0; temporary_hi_index=0; temporary_hi_data=0;
        if (rst_n) begin
            case (state)
                READ_RSP: if (result_valid && !result_error && read_target==0) begin
                    bank_write_valid=1;
                    bank_write_index=destination_offset+index;
                    bank_write_data=result_data;
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
                        0: begin
                            bank_write_valid=1;
                            bank_write_data=embedding_scale(bank_read(source_a,index));
                        end
                        2: begin
                            bank_write_valid=1;
                            bank_write_data=add_values(bank_read(source_a,index),
                                                       bank_read(source_b,index));
                        end
                    endcase
                end
                VSAVE: begin
                    bank_write_valid=1; bank_write_data=mac_rounded;
                end
                PROJECTION_SAVE: begin
                    bank_write_valid=1; bank_write_data=div_sat_reg;
                end
                VGELU_RSP: if (nout_valid && !nout_error) begin
                    bank_write_valid=1; bank_write_data=nout_data;
                end
                ROPE_RUN: if (rope_out_valid && !rope_error) begin
                    bank_write_valid=1; bank_write_select=2;
                    bank_write_index=head*dim+pair_index;
                    bank_write_data=rope_lo;
                    temporary_hi_valid=1;
                    temporary_hi_index=head*dim+pair_index+(dim>>1);
                    temporary_hi_data=rope_hi;
                end
                ATT_RUN: if (att_out_valid && att_out_index==index &&
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
            layer_phase<=0;
            div_quotient<=0; div_remainder<=0; div_negative<=0; div_iteration<=0; div_sat_reg<=0;
            pair_index<=0; index<=0; count<=0; columns<=0; token_id<=0;
            position<=0; token_mask<=0; scalar<=0; norm_weight<=0;
            base_index<=0; read_target<=0; source_a<=0; source_b<=0;
            destination<=0; vector_mode<=0; source_offset<=0; destination_offset<=0;
            op_base<=0; current_x<=0; error_hold<=0;
            bases[0]<=0; bases[1]<=0; bases[2]<=0;
            bases[3]<=0; bases[4]<=0; bases[5]<=0;
        end else begin
            case (state)
                IDLE: if (start_valid) begin
                    token<=0; layer<=0; layer_phase<=0; head<=0; base_index<=0; current_x<=0;
                    error_hold<=0; pc<=0; state<=BASES;
                end
                BASES: begin
                    if (scratch_error) abort_job(5);
                    else begin
                        bases[base_index]<=scratch_addr;
                        if (base_index==5) state<=DISPATCH;
                        else base_index<=base_index+1'b1;
                    end
                end
                DISPATCH: begin
                    if (tensor_error) abort_job(5);
                    else case (pc)
                        0: read_scalar(token_ids+64'(token)*4,1,1);
                        1: load_vector(tensor_addr+64'(token_id)*HIDDEN_SIZE*4,
                                       HIDDEN_SIZE,0,2);
                        2: vector_operation(0,0,0,0,HIDDEN_SIZE,3);
                        3: write_vector(bases[0]+64'(token)*HIDDEN_SIZE*4,
                                        HIDDEN_SIZE,0,4);
                        4: matrix(tensor_addr+64'(layer)*PER_LAYER_INPUT_SIZE*HIDDEN_SIZE*4,
                                  PER_LAYER_INPUT_SIZE,HIDDEN_SIZE,0,2,5);
                        5: vector_operation(1,2,0,2,PER_LAYER_INPUT_SIZE,6);
                        6: normalize(tensor_addr,PER_LAYER_INPUT_SIZE,0,2,2,7);
                        7: write_vector(bases[1]+
                            (64'(token)*NUM_LAYERS+layer)*PER_LAYER_INPUT_SIZE*4,
                            PER_LAYER_INPUT_SIZE,2,8);
                        8: begin
                            if (layer==NUM_LAYERS-1) begin
                                layer<=0; layer_phase<=0;
                                if (token==tokens-1) begin token<=0; pc<=9; end
                                else begin token<=token+1'b1; pc<=0; end
                            end else begin
                                layer<=layer+1'b1;
                                layer_phase<=layer_phase==3'd5 ? 3'd0:layer_phase+1'b1;
                                pc<=4;
                            end
                        end
                        9: read_scalar(positions+64'(token)*4,2,10);
                        10: load_vector(x_base+64'(token)*HIDDEN_SIZE*4,HIDDEN_SIZE,0,11);
                        11: normalize(tensor_addr,HIDDEN_SIZE,0,0,1,12);
                        12: begin
                            head<=0;
                            matrix(tensor_addr,NUM_Q_HEADS*dim,HIDDEN_SIZE,1,2,13);
                        end
                        13: normalize(tensor_addr,dim,head*dim,2,2,14);
                        14: begin pair_index<=0; return_pc<=15; state<=ROPE_START; end
                        15: begin
                            if (head==NUM_Q_HEADS-1) pc<=16;
                            else begin head<=head+1'b1; pc<=13; end
                        end
                        16: write_vector(bases[2]+64'(token)*NUM_Q_HEADS*DM*4,
                                         NUM_Q_HEADS*dim,2,17);
                        17: begin
                            head<=0; matrix(tensor_addr,kv_heads*dim,HIDDEN_SIZE,1,2,18);
                        end
                        18: normalize(tensor_addr,dim,head*dim,2,2,19);
                        19: begin pair_index<=0; return_pc<=20; state<=ROPE_START; end
                        20: begin
                            if (head==kv_heads-1) pc<=21;
                            else begin head<=head+1'b1; pc<=18; end
                        end
                        21: write_vector(bases[3]+64'(token)*KM*DM*4,
                                         kv_heads*dim,2,22);
                        22: matrix(tensor_addr,kv_heads*dim,HIDDEN_SIZE,1,2,23);
                        23: write_vector(bases[4]+64'(token)*KM*DM*4,kv_heads*dim,2,24);
                        24: begin
                            if (token==tokens-1) begin token<=0; pc<=30; end
                            else begin token<=token+1'b1; pc<=9; end
                        end
                        30: begin
                            head<=0;
                            load_vector(x_base+64'(token)*HIDDEN_SIZE*4,HIDDEN_SIZE,0,31);
                        end
                        31: begin index<=0; state<=ATT_START; end
                        32: begin
                            if (head==NUM_Q_HEADS-1) pc<=33;
                            else begin head<=head+1'b1; pc<=31; end
                        end
                        33: matrix(tensor_addr,HIDDEN_SIZE,NUM_Q_HEADS*dim,4,2,34);
                        34: normalize(tensor_addr,HIDDEN_SIZE,0,2,2,35);
                        35: vector_operation(2,0,2,0,HIDDEN_SIZE,36);
                        36: normalize(tensor_addr,HIDDEN_SIZE,0,0,1,37);
                        37: matrix(tensor_addr,INTERMEDIATE_SIZE,HIDDEN_SIZE,1,3,38);
                        38: vector_operation(4,3,0,3,INTERMEDIATE_SIZE,39);
                        39: matrix(tensor_addr,INTERMEDIATE_SIZE,HIDDEN_SIZE,1,4,40);
                        40: vector_operation(3,3,4,4,INTERMEDIATE_SIZE,41);
                        41: matrix(tensor_addr,HIDDEN_SIZE,INTERMEDIATE_SIZE,4,2,42);
                        42: normalize(tensor_addr,HIDDEN_SIZE,0,2,2,43);
                        43: vector_operation(2,0,2,0,HIDDEN_SIZE,44);
                        44: matrix(tensor_addr,PER_LAYER_INPUT_SIZE,HIDDEN_SIZE,0,3,45);
                        45: vector_operation(4,3,0,3,PER_LAYER_INPUT_SIZE,46);
                        46: load_vector(bases[1]+
                            (64'(token)*NUM_LAYERS+layer)*PER_LAYER_INPUT_SIZE*4,
                            PER_LAYER_INPUT_SIZE,4,47);
                        47: vector_operation(3,3,4,4,PER_LAYER_INPUT_SIZE,48);
                        48: matrix(tensor_addr,HIDDEN_SIZE,PER_LAYER_INPUT_SIZE,4,2,49);
                        49: normalize(tensor_addr,HIDDEN_SIZE,0,2,2,50);
                        50: vector_operation(2,0,2,0,HIDDEN_SIZE,51);
                        51: read_scalar(tensor_addr,4,52);
                        52: vector_operation(5,0,0,0,HIDDEN_SIZE,53);
                        53: write_vector(next_x_base+64'(token)*HIDDEN_SIZE*4,
                                         HIDDEN_SIZE,0,54);
                        54: begin
                            if (token==tokens-1) begin
                                token<=0; current_x<=!current_x;
                                if (layer==NUM_LAYERS-1) begin layer<=0; layer_phase<=0; pc<=58; end
                                else begin
                                    layer<=layer+1'b1;
                                    layer_phase<=layer_phase==3'd5 ? 3'd0:layer_phase+1'b1;
                                    pc<=9;
                                end
                            end else begin token<=token+1'b1; pc<=30; end
                        end
                        58: state<=POOL_START;
                        60: load_vector(x_base+64'(token)*HIDDEN_SIZE*4,HIDDEN_SIZE,0,61);
                        61: normalize(tensor_addr,HIDDEN_SIZE,0,0,1,62);
                        62: matrix(tensor_addr,EMBEDDING_DIM,HIDDEN_SIZE,1,2,63);
                        63: read_scalar(masks+64'(token)*4,3,64);
                        64: begin index<=0; state<=POOL_FEED; end
                        65: begin
                            if (token==tokens-1) state<=POOL_WAIT;
                            else begin token<=token+1'b1; pc<=60; end
                        end
                        default: abort_job(1);
                    endcase
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
                            abort_job(1);
                        else index<=index+1'b1;
                    end
                    if (mat_done_valid) begin
                        if (mat_error!=0) abort_job(mat_error);
                        else if (index!=count) abort_job(1);
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
                        norm_out_last!=(index==count-1)) abort_job(1);
                    else begin
                        if (index==count-1) begin index<=0; pc<=return_pc; state<=DISPATCH; end
                        else index<=index+1'b1;
                    end
                end
                VECTOR: begin
                    case (vector_mode)
                        0,2: finish_element;
                        1: begin
                            div_quotient<=projection_numerator<0 ?
                                -projection_numerator:projection_numerator;
                            div_negative<=projection_numerator<0;
                            div_remainder<=0; div_iteration<=0; state<=DIVIDE;
                        end
                        3,5: state<=VPRODUCT;
                        4: state<=VGELU_REQ;
                        default: abort_job(1);
                    endcase
                end
                DIVIDE: begin
                    div_quotient<=div_next_quotient; div_remainder<=div_next_remainder;
                    if (div_iteration==47) state<=DIV_DONE;
                    else div_iteration<=div_iteration+1'b1;
                end
                DIV_DONE: begin
                    div_sat_reg<=saturate(div_result);
                    state<=PROJECTION_SAVE;
                end
                PROJECTION_SAVE: finish_element;
                VPRODUCT: state<=VSAVE;
                VSAVE: finish_element;
                VGELU_REQ: if (nready) state<=VGELU_RSP;
                VGELU_RSP: if (nout_valid) begin
                    if (nout_error) abort_job(1);
                    else finish_element;
                end
                ROPE_START: if (rope_start_ready) state<=ROPE_RUN;
                ROPE_RUN: if (rope_out_valid) begin
                    if (rope_error) abort_job(1);
                    else begin
                        if (pair_index==(dim>>1)-1) begin pc<=return_pc; state<=DISPATCH; end
                        else begin pair_index<=pair_index+1'b1; state<=ROPE_START; end
                    end
                end
                ATT_START: if (att_start_ready) state<=ATT_RUN;
                ATT_RUN: begin
                    if (att_out_valid) begin
                        if (att_out_index!=index || att_out_last!=(index==dim-1))
                            abort_job(1);
                        else index<=index+1'b1;
                    end
                    if (att_done_valid) begin
                        if (att_error!=0) abort_job(att_error);
                        else if (index!=dim) abort_job(1);
                        else begin index<=0; pc<=32; state<=DISPATCH; end
                    end
                end
                POOL_START: if (pool_start_ready) begin token<=0; pc<=60; state<=DISPATCH; end
                POOL_FEED: if (pool_token_ready) begin
                    if (index==EMBEDDING_DIM-1) begin index<=0; pc<=65; state<=DISPATCH; end
                    else index<=index+1'b1;
                end
                POOL_WAIT: if (pool_done_valid) begin
                    if (pool_error!=0) abort_job(pool_error);
                    else begin error_hold<=0; state<=DONE; end
                end
                FLUSH: state<=DONE;
                DONE: if (done_ready) state<=IDLE;
                default: abort_job(1);
            endcase
        end
    end
endmodule
