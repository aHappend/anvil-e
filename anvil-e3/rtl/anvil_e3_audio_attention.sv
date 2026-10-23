module anvil_e3_audio_attention #(
    parameter integer AUDIO_HIDDEN=1024, AUDIO_HEADS=8, AUDIO_HEAD_DIM=128,
    AUDIO_CHUNK_SIZE=12, AUDIO_CONTEXT_LEFT=13, AUDIO_CONTEXT_RIGHT=0
) (
    input wire clk, rst_n, start_valid,
    output wire start_ready,
    input wire [31:0] tokens,
    input wire [63:0] q_base, k_base, v_base, relative_weights, scale_weights, output_base,
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
    localparam IDLE=0, SETUP=1, QREQ=2, QRSP=3, SCALE_REQ=4, SCALE_RSP=5,
        SCALE_ACT=6, SCALE_WAIT=7, SCALE_DIV=8, SCALE_DIV_WAIT=9,
        REL_START=10, REL_WAIT=11, REL_WEIGHT_REQ=12, REL_WEIGHT_RSP=13,
        REL_MAC=14, KREQ=15, KRSP=16, SCORE=17, SCORE_FINISH=18,
        CAP_START=19, CAP_WAIT=20, EXP_START=21, EXP_WAIT=22,
        VREQ=23, VRSP=24, NEXTKEY=25, VALUE_DIV=26, VALUE_WAIT=27,
        WRITE_REQ=28, WRITE_RSP=29, FLUSH=30, DONE=31,
        SCALE_ROUND=32, REL_MUL=33, REL_ROUND=34, SCORE_MUL=35, VMAC=36;
    localparam signed [127:0] ONE=128'sd1099511627776;
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
    function automatic signed [127:0] round40(input signed [127:0] x);
        reg signed [127:0] q;
        begin
            q=x>>>40;
            if (x[39:0]>40'h8000000000 ||
                (x[39:0]==40'h8000000000 && q[0])) q=q+1;
            round40=q;
        end
    endfunction
    function automatic signed [31:0] materialize(input signed [127:0] x);
        reg signed [127:0] q;
        begin
            q=x>>>16;
            if (x[15:0]>16'h8000 || (x[15:0]==16'h8000 && q[0])) q=q+1;
            if (q>128'sd2147483647) materialize=32'sh7fffffff;
            else if (q< -128'sd2147483648) materialize=32'sh80000000;
            else materialize=q[31:0];
        end
    endfunction
    localparam [127:0] SCALE_DENOM=round40(
        128'sd762123384786*$signed({64'd0,root(AUDIO_HEAD_DIM)}));
    reg [5:0] state;
    reg [31:0] count, query, head, component, key, rel_index, rel_col, channel;
    reg [63:0] qb, kb, vb, rw, sw, dst, key_begin, key_end;
    reg weighted_pass;
    reg signed [47:0] query_value, scale_value, relative_weight, content_key;
    reg signed [47:0] rel_vec_reg;
    reg signed [47:0] score_max, score_value, exponential;
    reg signed [63:0] relative_value, cap_argument, scaled_q_reg, combined_key_reg;
    reg signed [95:0] rel_prod_reg, v_prod_reg;
    reg signed [127:0] mul_prod_reg, weighted_cur_reg;
    reg signed [63:0] scaled_query [0:AUDIO_HEAD_DIM-1];
    reg signed [47:0] relative_vector [0:AUDIO_HEAD_DIM*AUDIO_HEADS-1];
    reg signed [127:0] weighted [0:AUDIO_HEAD_DIM-1];
    reg signed [127:0] relative_accumulator, score_accumulator, denominator, value;
    reg signed [127:0] work;
    reg [3:0] error_hold;
    wire unit_rst_n=rst_n && state!=FLUSH;
    reg [63:0] chunk_start;
    reg [31:0] chunk_offset;
    wire [63:0] chunk_end=chunk_start+AUDIO_CHUNK_SIZE+64'(AUDIO_CONTEXT_RIGHT);
    wire signed [127:0] relative_sum=relative_accumulator+
        {{32{rel_prod_reg[95]}},rel_prod_reg};
    wire signed [47:0] memory_value={result_data,16'd0};
    wire signed [95:0] weighted_product=exponential*memory_value;
    wire rel_ready, rel_valid, rel_error;
    wire signed [47:0] rel_data;
    anvil_e3_audio_relative #(.AUDIO_HIDDEN(AUDIO_HIDDEN)) relative_position (
        .clk(clk), .rst_n(unit_rst_n), .start_valid(state==REL_START),
        .start_ready(rel_ready), .start_query(query), .start_key(key),
        .start_channel(rel_index), .out_valid(rel_valid), .out_ready(state==REL_WAIT),
        .out_data(rel_data), .out_error(rel_error)
    );
    wire act_ready, act_valid, act_error;
    wire signed [47:0] act_data;
    anvil_e3_audio_activation activation (
        .clk(clk), .rst_n(unit_rst_n),
        .in_valid(state==SCALE_ACT || state==CAP_START), .in_ready(act_ready),
        .in_op(state==SCALE_ACT ? 2'd2:2'd3),
        .in_data(state==SCALE_ACT ? {{16{scale_value[47]}},scale_value}:cap_argument),
        .out_valid(act_valid), .out_ready(state==SCALE_WAIT || state==CAP_WAIT),
        .out_data(act_data), .out_error(act_error)
    );
    wire exp_ready, exp_valid, exp_error;
    wire signed [47:0] exp_data;
    anvil_e2_nonlinear exponential_unit (
        .clk(clk), .rst_n(unit_rst_n), .in_valid(state==EXP_START),
        .in_ready(exp_ready), .in_op(3'd0), .in_data(score_value),
        .out_valid(exp_valid), .out_ready(state==EXP_WAIT),
        .out_data(exp_data), .out_error(exp_error)
    );
    reg signed [127:0] divide_numerator;
    reg [127:0] divide_denominator;
    wire divide_ready, divide_valid, divide_error;
    wire signed [127:0] divide_data;
    always @* begin
        divide_numerator=0; divide_denominator=1;
        if (state==SCALE_DIV || state==SCALE_DIV_WAIT) begin
            divide_numerator=$signed({{80{scale_value[47]}},scale_value})<<<40;
            divide_denominator=SCALE_DENOM;
        end else if (state==VALUE_DIV || state==VALUE_WAIT) begin
            divide_numerator=weighted[channel];
            divide_denominator=$unsigned(denominator);
        end
    end
    anvil_e2_divide divider (
        .clk(clk), .rst_n(unit_rst_n),
        .in_valid(state==SCALE_DIV || state==VALUE_DIV), .in_ready(divide_ready),
        .in_numerator(divide_numerator), .in_denominator(divide_denominator),
        .out_valid(divide_valid), .out_ready(state==SCALE_DIV_WAIT || state==VALUE_WAIT),
        .out_data(divide_data), .out_error(divide_error)
    );
    initial begin
        if (AUDIO_HIDDEN<=0 || AUDIO_HIDDEN>65535 || AUDIO_HEADS<=0 ||
            AUDIO_HEAD_DIM<=0 || AUDIO_HEAD_DIM>65535 ||
            64'(AUDIO_HEADS)*AUDIO_HEAD_DIM!=AUDIO_HIDDEN ||
            AUDIO_CHUNK_SIZE<=0 || AUDIO_CONTEXT_LEFT<0 || AUDIO_CONTEXT_RIGHT<0)
            $fatal(1,"PARAMETER ERROR: audio attention geometry");
    end
    assign start_ready=rst_n && state==IDLE;
    assign cmd_valid=rst_n && (state==QREQ || state==SCALE_REQ ||
        state==REL_WEIGHT_REQ || state==KREQ || state==VREQ || state==WRITE_REQ);
    assign cmd_write=rst_n && state==WRITE_REQ;
    assign cmd_addr=!rst_n ? 64'd0:
        state==QREQ ? qb+(64'(query)*AUDIO_HIDDEN+64'(head)*AUDIO_HEAD_DIM+component)*4:
        state==SCALE_REQ ? sw+64'(component)*4:
        state==REL_WEIGHT_REQ ? rw+
            ((64'(head)*AUDIO_HEAD_DIM+component)*AUDIO_HIDDEN+rel_col)*4:
        state==KREQ ? kb+(64'(key)*AUDIO_HIDDEN+64'(head)*AUDIO_HEAD_DIM+component)*4:
        state==VREQ ? vb+(64'(key)*AUDIO_HIDDEN+64'(head)*AUDIO_HEAD_DIM+channel)*4:
        state==WRITE_REQ ? dst+
            (64'(query)*AUDIO_HIDDEN+64'(head)*AUDIO_HEAD_DIM+channel)*4:64'd0;
    assign cmd_wdata=rst_n && state==WRITE_REQ ? materialize(value):32'd0;
    assign result_ready=rst_n && (state==QRSP || state==SCALE_RSP ||
        state==REL_WEIGHT_RSP || state==KRSP || state==VRSP || state==WRITE_RSP);
    assign done_valid=rst_n && state==DONE;
    assign done_error=rst_n ? error_hold:4'd0;
    always @* begin
        if (state==SCALE_ROUND)
            work=round40(mul_prod_reg);
        else if (state==REL_ROUND) work=round40(relative_accumulator);
        else work=round40(score_accumulator);
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=IDLE; count<=0; query<=0; head<=0; component<=0; key<=0;
            rel_index<=0; rel_col<=0; channel<=0; qb<=0; kb<=0; vb<=0;
            rw<=0; sw<=0; dst<=0; key_begin<=0; key_end<=0; weighted_pass<=0;
            query_value<=0; scale_value<=0; relative_weight<=0; content_key<=0;
            rel_vec_reg<=0; score_max<=0; score_value<=0; exponential<=0;
            relative_value<=0; cap_argument<=0; scaled_q_reg<=0; combined_key_reg<=0;
            rel_prod_reg<=0; v_prod_reg<=0; mul_prod_reg<=0; weighted_cur_reg<=0;
            relative_accumulator<=0; score_accumulator<=0;
            denominator<=0; value<=0; error_hold<=0; chunk_start<=0; chunk_offset<=0;
        end else if (result_valid && result_ready && result_error) begin
            error_hold<=3; state<=FLUSH;
        end else case (state)
            IDLE: if (start_valid) begin
                count<=tokens; qb<=q_base; kb<=k_base; vb<=v_base;
                rw<=relative_weights; sw<=scale_weights; dst<=output_base;
                query<=0; head<=0; component<=0; channel<=0;
                chunk_start<=0; chunk_offset<=0;
                error_hold<=0; state<=SETUP;
            end
            SETUP: begin
                if (count==0) begin error_hold<=1; state<=FLUSH; end
                else begin
                    key_begin<=chunk_start>AUDIO_CONTEXT_LEFT ?
                        chunk_start-AUDIO_CONTEXT_LEFT:64'd0;
                    key_end<=chunk_end<count ? chunk_end:{32'd0,count};
                    component<=0; state<=QREQ;
                end
            end
            QREQ: if (cmd_ready) state<=QRSP;
            QRSP: if (result_valid) begin query_value<={result_data,16'd0}; state<=SCALE_REQ; end
            SCALE_REQ: if (cmd_ready) state<=SCALE_RSP;
            SCALE_RSP: if (result_valid) begin scale_value<={result_data,16'd0}; state<=SCALE_ACT; end
            SCALE_ACT: if (act_ready) state<=SCALE_WAIT;
            SCALE_WAIT: if (act_valid) begin
                if (act_error) begin error_hold<=6; state<=FLUSH; end
                else begin scale_value<=act_data; state<=SCALE_DIV; end
            end
            SCALE_DIV: if (divide_ready) state<=SCALE_DIV_WAIT;
            SCALE_DIV_WAIT: if (divide_valid) begin
                if (divide_error || divide_data>128'sh7fffffffffffffff ||
                    divide_data< -128'sh8000000000000000) begin
                    error_hold<=6; state<=FLUSH;
                end else begin
                    mul_prod_reg<=$signed(query_value)*$signed(divide_data[63:0]);
                    state<=SCALE_ROUND;
                end
            end
            SCALE_ROUND: begin
                if (work>128'sh7fffffffffffffff || work< -128'sh8000000000000000) begin
                    error_hold<=6; state<=FLUSH;
                end else begin
                    scaled_query[component]<=work[63:0];
                    if (component==AUDIO_HEAD_DIM-1) begin
                        component<=0; key<=32'(key_begin); rel_index<=0; rel_col<=0;
                        relative_accumulator<=0; score_accumulator<=0;
                        weighted_pass<=0; denominator<=0; state<=REL_START;
                    end else begin component<=component+1'b1; state<=QREQ; end
                end
            end
            REL_START: if (rel_ready) state<=REL_WAIT;
            REL_WAIT: if (rel_valid) begin
                if (rel_error) begin error_hold<=6; state<=FLUSH; end
                else begin
                    relative_vector[rel_index]<=rel_data;
                    if (rel_index==AUDIO_HIDDEN-1) begin
                        component<=0; rel_col<=0; relative_accumulator<=0;
                        score_accumulator<=0; state<=REL_WEIGHT_REQ;
                    end else begin rel_index<=rel_index+1'b1; state<=REL_START; end
                end
            end
            REL_WEIGHT_REQ: if (cmd_ready) state<=REL_WEIGHT_RSP;
            REL_WEIGHT_RSP: if (result_valid) begin
                rel_vec_reg<=relative_vector[rel_col];
                relative_weight<={result_data,16'd0}; state<=REL_MUL;
            end
            REL_MUL: begin
                rel_prod_reg<=rel_vec_reg*relative_weight;
                state<=REL_MAC;
            end
            REL_MAC: begin
                relative_accumulator<=relative_sum;
                if (rel_col==AUDIO_HIDDEN-1) state<=REL_ROUND;
                else begin rel_col<=rel_col+1'b1; state<=REL_WEIGHT_REQ; end
            end
            REL_ROUND: begin
                if (work>128'sh7fffffffffffffff || work< -128'sh8000000000000000) begin
                    error_hold<=6; state<=FLUSH;
                end else begin relative_value<=work[63:0]; state<=KREQ; end
            end
            KREQ: if (cmd_ready) state<=KRSP;
            KRSP: if (result_valid) begin
                content_key<={result_data,16'd0};
                scaled_q_reg<=scaled_query[component];
                combined_key_reg<=$signed({{16{result_data[31]}},result_data,16'd0})+relative_value;
                state<=SCORE_MUL;
            end
            SCORE_MUL: begin
                mul_prod_reg<=scaled_q_reg*combined_key_reg;
                state<=SCORE;
            end
            SCORE: begin
                score_accumulator<=score_accumulator+mul_prod_reg;
                if (component==AUDIO_HEAD_DIM-1) state<=SCORE_FINISH;
                else begin
                    component<=component+1'b1; rel_col<=0; relative_accumulator<=0;
                    state<=REL_WEIGHT_REQ;
                end
            end
            SCORE_FINISH: begin
                if (work>600*ONE) cap_argument<=64'sd659706976665600;
                else if (work< -600*ONE) cap_argument<= -64'sd659706976665600;
                else cap_argument<=work[63:0];
                state<=CAP_START;
            end
            CAP_START: if (act_ready) state<=CAP_WAIT;
            CAP_WAIT: if (act_valid) begin
                if (act_error) begin error_hold<=6; state<=FLUSH; end
                else if (!weighted_pass) begin
                    if (64'(key)==key_begin || act_data>score_max) score_max<=act_data;
                    state<=NEXTKEY;
                end else begin
                    score_value<=act_data-score_max; state<=EXP_START;
                end
            end
            EXP_START: if (exp_ready) state<=EXP_WAIT;
            EXP_WAIT: if (exp_valid) begin
                if (exp_error) begin error_hold<=6; state<=FLUSH; end
                else begin
                    exponential<=exp_data;
                    denominator<=denominator+$signed({{80{exp_data[47]}},exp_data});
                    channel<=0; state<=VREQ;
                end
            end
            VREQ: if (cmd_ready) state<=VRSP;
            VRSP: if (result_valid) begin
                v_prod_reg<=weighted_product;
                weighted_cur_reg<=weighted[channel];
                state<=VMAC;
            end
            VMAC: begin
                if (64'(key)==key_begin)
                    weighted[channel]<={{32{v_prod_reg[95]}},v_prod_reg};
                else weighted[channel]<=weighted_cur_reg+
                    {{32{v_prod_reg[95]}},v_prod_reg};
                if (channel==AUDIO_HEAD_DIM-1) state<=NEXTKEY;
                else begin channel<=channel+1'b1; state<=VREQ; end
            end
            NEXTKEY: begin
                rel_index<=0;
                if (64'(key)+1==key_end) begin
                    if (!weighted_pass) begin
                        weighted_pass<=1; key<=32'(key_begin); denominator<=0; state<=REL_START;
                    end else begin
                        channel<=0;
                        if (denominator==0) begin error_hold<=6; state<=FLUSH; end
                        else state<=VALUE_DIV;
                    end
                end else begin key<=key+1'b1; state<=REL_START; end
            end
            VALUE_DIV: if (divide_ready) state<=VALUE_WAIT;
            VALUE_WAIT: if (divide_valid) begin
                if (divide_error) begin error_hold<=6; state<=FLUSH; end
                else begin value<=divide_data; state<=WRITE_REQ; end
            end
            WRITE_REQ: if (cmd_ready) state<=WRITE_RSP;
            WRITE_RSP: if (result_valid) begin
                if (channel!=AUDIO_HEAD_DIM-1) begin channel<=channel+1'b1; state<=VALUE_DIV; end
                else if (head!=AUDIO_HEADS-1) begin
                    head<=head+1'b1; component<=0; state<=QREQ;
                end else if (query!=count-1) begin
                    if (chunk_offset==AUDIO_CHUNK_SIZE-1) begin
                        chunk_offset<=0; chunk_start<=chunk_start+AUDIO_CHUNK_SIZE;
                    end else chunk_offset<=chunk_offset+1'b1;
                    query<=query+1'b1; head<=0; state<=SETUP;
                end else state<=DONE;
            end
            FLUSH: state<=DONE;
            DONE: if (done_ready) state<=IDLE;
            default: begin error_hold<=6; state<=FLUSH; end
        endcase
    end
endmodule
