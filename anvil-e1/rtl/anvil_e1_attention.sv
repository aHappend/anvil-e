module anvil_e1_attention #(
    parameter integer NUM_Q_HEADS=4, LOCAL_KV_HEADS=2, FULL_KV_HEADS=1,
    LOCAL_HEAD_DIM=256, FULL_HEAD_DIM=512, SLIDING_WINDOW=512
) (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [31:0] start_tokens, start_query, start_head,
    input wire start_full,
    input wire [63:0] start_q_base, start_k_base, start_v_base,
    input wire [63:0] start_positions_base, start_mask_base,
    output wire cmd_valid,
    input wire cmd_ready,
    output wire [63:0] cmd_addr,
    input wire result_valid,
    output wire result_ready,
    input wire signed [31:0] result_data,
    input wire result_error,
    output wire mac_clear, mac_accumulate,
    output wire signed [31:0] mac_a, mac_b,
    input wire signed [95:0] mac_sum,
    output wire nonlinear_valid,
    input wire nonlinear_ready,
    output wire [2:0] nonlinear_op,
    output wire signed [31:0] nonlinear_data,
    input wire nonlinear_out_valid,
    output wire nonlinear_out_ready,
    input wire signed [31:0] nonlinear_out_data,
    input wire nonlinear_out_error,
    output wire out_valid,
    input wire out_ready,
    output wire signed [31:0] out_data,
    output wire [31:0] out_index,
    output wire out_last,
    output wire done_valid,
    input wire done_ready,
    output wire [3:0] done_error
);
    localparam integer DM=LOCAL_HEAD_DIM>FULL_HEAD_DIM ? LOCAL_HEAD_DIM:FULL_HEAD_DIM;
    localparam integer KM=LOCAL_KV_HEADS>FULL_KV_HEADS ? LOCAL_KV_HEADS:FULL_KV_HEADS;
    localparam IDLE=0, QREQ=1, QRSP=2, POSREQ=3, POSRSP=4,
        MASKREQ=5, MASKRSP=6, KPOSREQ=7, KPOSRSP=8, KREQ=9, KRSP=10,
        DOT=11, SCORE=12, EXPREQ=13, EXPRSP=14, VREQ=15, VRSP=16,
        PRODUCT=17, WEIGHT=18, NEXTKEY=19, FINISH=20, OUTPUT=21, DONE=22,
        DIVIDE=23, SCORE_SAVE=24, FINISH_SAVE=25;
    reg [4:0] state;
    reg [31:0] tokens, query, head, kv_head, dim, key, component, channel;
    reg [31:0] query_position;
    reg full_mode, found_key;
    reg [1:0] pass;
    reg [63:0] q_base, k_base, v_base, position_base, mask_base;
    reg signed [31:0] q_values [0:DM-1];
    reg signed [95:0] weighted [0:DM-1];
    reg signed [31:0] values [0:DM-1];
    reg signed [31:0] operand, score_max, score_value, exponential;
    reg signed [95:0] denominator;
    reg [3:0] error_hold;
    reg signed [31:0] data_hold;
    reg [31:0] index_hold;
    reg last_hold;
    wire [32:0] position_difference={1'b0,result_data}>{1'b0,query_position} ?
        {1'b0,result_data}-{1'b0,query_position}:
        {1'b0,query_position}-{1'b0,result_data};
    reg [95:0] div_quotient, div_divisor;
    reg [96:0] div_remainder;
    reg div_negative;
    reg [4:0] div_iteration, div_return;
    reg [95:0] div_next_quotient;
    reg [96:0] div_next_remainder;
    integer div_bit;
    always @* begin
        div_next_quotient=div_quotient;
        div_next_remainder=div_remainder;
        if (state==DIVIDE) begin
            for (div_bit=0; div_bit<4; div_bit=div_bit+1) begin
                div_next_remainder={div_next_remainder[95:0],div_next_quotient[95]};
                div_next_quotient=div_next_quotient<<1;
                if (div_next_remainder>={1'b0,div_divisor}) begin
                    div_next_remainder=div_next_remainder-{1'b0,div_divisor};
                    div_next_quotient[0]=1'b1;
                end
            end
        end
    end
    wire [95:0] div_rounded_magnitude=div_quotient+
        ((div_remainder>{1'b0,div_divisor}-div_remainder ||
          (div_remainder=={1'b0,div_divisor}-div_remainder && div_quotient[0]))
         ? 96'd1:96'd0);
    wire signed [95:0] div_result=div_negative ?
        -$signed(div_rounded_magnitude):$signed(div_rounded_magnitude);
    task automatic begin_divide;
        input signed [95:0] numerator, denominator_value;
        input [4:0] next_state;
        begin
            div_quotient<=numerator<0 ? -numerator:numerator;
            div_divisor<=denominator_value<0 ? -denominator_value:denominator_value;
            div_remainder<=0; div_iteration<=0;
            div_negative<=(numerator<0)!=(denominator_value<0);
            div_return<=next_state; state<=DIVIDE;
        end
    endtask

    function automatic [63:0] dimension_root;
        input integer dimension;
        reg [127:0] radicand, residue, trial_value, root;
        integer i;
        begin
            radicand=128'(dimension)<<80;
            residue=0; root=0;
            for (i=0;i<64;i=i+1) begin
                residue=(residue<<2)|{126'd0,radicand[127:126]};
                trial_value=(root<<2)|128'd1;
                if (residue>=trial_value) begin
                    residue=residue-trial_value; root=(root<<1)|128'd1;
                end else root=root<<1;
                radicand=radicand<<2;
            end
            dimension_root=root[63:0];
        end
    endfunction
    localparam [63:0] LOCAL_ROOT=dimension_root(LOCAL_HEAD_DIM);
    localparam [63:0] FULL_ROOT=dimension_root(FULL_HEAD_DIM);

    function automatic signed [31:0] saturate;
        input signed [95:0] value;
        begin
            if (value>96'sd2147483647) saturate=32'sh7fffffff;
            else if (value< -96'sd2147483648) saturate=32'sh80000000;
            else saturate=value[31:0];
        end
    endfunction
    localparam integer LOCAL_GROUP=LOCAL_KV_HEADS>0 ? NUM_Q_HEADS/LOCAL_KV_HEADS:1;
    localparam integer FULL_GROUP=FULL_KV_HEADS>0 ? NUM_Q_HEADS/FULL_KV_HEADS:1;
    function automatic [31:0] grouped_head;
        input [31:0] query_head;
        input full_layer;
        integer group_index;
        begin
            grouped_head=0;
            if (full_layer) begin
                for (group_index=0; group_index<FULL_KV_HEADS; group_index=group_index+1)
                    if (query_head>=group_index*FULL_GROUP) grouped_head=group_index;
            end else begin
                for (group_index=0; group_index<LOCAL_KV_HEADS; group_index=group_index+1)
                    if (query_head>=group_index*LOCAL_GROUP) grouped_head=group_index;
            end
        end
    endfunction
    wire signed [31:0] saturated_score=saturate(div_result);
    wire signed [95:0] difference={{64{saturated_score[31]}},saturated_score}-
        {{64{score_max[31]}},score_max};
    task automatic finish_channel;
        input signed [31:0] value;
        begin
            values[channel]<=value;
            if (channel==dim-1) begin
                channel<=0; index_hold<=0; last_hold<=dim==1;
                data_hold<=dim==1 ? value:values[0];
                state<=OUTPUT;
            end else begin channel<=channel+1'b1; state<=FINISH; end
        end
    endtask
    initial begin
        if (NUM_Q_HEADS<=0 || LOCAL_KV_HEADS<=0 || FULL_KV_HEADS<=0 ||
            LOCAL_HEAD_DIM<=0 || FULL_HEAD_DIM<=0 || DM>65535 ||
            LOCAL_HEAD_DIM%2!=0 || FULL_HEAD_DIM%2!=0 || SLIDING_WINDOW<=0)
            $fatal(1,"PARAMETER ERROR: attention dimensions must be positive and bounded");
        if (LOCAL_KV_HEADS>0 && FULL_KV_HEADS>0)
            if (NUM_Q_HEADS%LOCAL_KV_HEADS!=0 || NUM_Q_HEADS%FULL_KV_HEADS!=0)
                $fatal(1,"PARAMETER ERROR: query heads must divide into contiguous KV groups");
    end
    assign start_ready=rst_n && state==IDLE;
    assign cmd_valid=rst_n && (state==QREQ || state==POSREQ || state==MASKREQ ||
                               state==KPOSREQ || state==KREQ || state==VREQ);
    assign cmd_addr=!rst_n ? 64'd0 :
        state==QREQ ? q_base+(64'(query)*NUM_Q_HEADS*DM+64'(head)*dim+component)*64'd4:
        state==POSREQ ? position_base+64'(query)*64'd4:
        state==MASKREQ ? mask_base+64'(key)*64'd4:
        state==KPOSREQ ? position_base+64'(key)*64'd4:
        state==KREQ ? k_base+(64'(key)*KM*DM+64'(kv_head)*dim+component)*64'd4:
        state==VREQ ? v_base+(64'(key)*KM*DM+64'(kv_head)*dim+channel)*64'd4:64'd0;
    assign result_ready=rst_n && (state==QRSP || state==POSRSP || state==MASKRSP ||
                                  state==KPOSRSP || state==KRSP || state==VRSP);
    assign mac_clear=rst_n && ((state==DOT && component==0) || state==PRODUCT);
    assign mac_accumulate=rst_n && (state==DOT || state==PRODUCT);
    assign mac_a=!rst_n ? 32'sd0 : state==DOT ? q_values[component]:
                 state==PRODUCT ? exponential:32'sd0;
    assign mac_b=rst_n ? operand:32'sd0;
    assign nonlinear_valid=rst_n && state==EXPREQ;
    assign nonlinear_op=3'd0;
    assign nonlinear_data=rst_n && state==EXPREQ ? score_value:32'sd0;
    assign nonlinear_out_ready=rst_n && state==EXPRSP;
    assign out_valid=rst_n && state==OUTPUT;
    assign out_data=rst_n ? data_hold:32'sd0;
    assign out_index=rst_n ? index_hold:32'd0;
    assign out_last=rst_n && last_hold;
    assign done_valid=rst_n && state==DONE;
    assign done_error=rst_n ? error_hold:4'd0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=IDLE; tokens<=0; query<=0; head<=0; kv_head<=0; dim<=0;
            key<=0; component<=0; channel<=0; query_position<=0;
            full_mode<=0; found_key<=0; pass<=0;
            q_base<=0; k_base<=0; v_base<=0; position_base<=0; mask_base<=0;
            operand<=0; score_max<=0; score_value<=0; exponential<=0;
            denominator<=0; error_hold<=0; data_hold<=0; index_hold<=0; last_hold<=0;
            div_quotient<=0; div_divisor<=0; div_remainder<=0;
            div_negative<=0; div_iteration<=0; div_return<=IDLE;
        end else begin
            case (state)
                IDLE: if (start_valid) begin
                    tokens<=start_tokens; query<=start_query; head<=start_head;
                    full_mode<=start_full;
                    dim<=start_full ? FULL_HEAD_DIM:LOCAL_HEAD_DIM;
                    kv_head<=grouped_head(start_head,start_full);
                    q_base<=start_q_base; k_base<=start_k_base; v_base<=start_v_base;
                    position_base<=start_positions_base; mask_base<=start_mask_base;
                    component<=0; channel<=0; key<=0; pass<=0; found_key<=0;
                    denominator<=0; error_hold<=0;
                    if (start_tokens==0 || start_query>=start_tokens || start_head>=NUM_Q_HEADS) begin
                        error_hold<=1; state<=DONE;
                    end else state<=QREQ;
                end
                QREQ: if (cmd_ready) state<=QRSP;
                QRSP: if (result_valid) begin
                    if (result_error) begin error_hold<=3; state<=DONE; end
                    else begin
                        q_values[component]<=result_data;
                        weighted[component]<=0;
                        if (component==dim-1) begin component<=0; state<=POSREQ; end
                        else begin component<=component+1'b1; state<=QREQ; end
                    end
                end
                POSREQ: if (cmd_ready) state<=POSRSP;
                POSRSP: if (result_valid) begin
                    if (result_error) begin error_hold<=3; state<=DONE; end
                    else begin query_position<=result_data; state<=MASKREQ; end
                end
                MASKREQ: if (cmd_ready) state<=MASKRSP;
                MASKRSP: if (result_valid) begin
                    if (result_error) begin error_hold<=3; state<=DONE; end
                    else if (result_data==0) state<=NEXTKEY;
                    else if (result_data!=1) begin error_hold<=2; state<=DONE; end
                    else if (full_mode) begin component<=0; state<=KREQ; end
                    else state<=KPOSREQ;
                end
                KPOSREQ: if (cmd_ready) state<=KPOSRSP;
                KPOSRSP: if (result_valid) begin
                    if (result_error) begin error_hold<=3; state<=DONE; end
                    else begin
                        if (position_difference>=SLIDING_WINDOW) state<=NEXTKEY;
                        else begin component<=0; state<=KREQ; end
                    end
                end
                KREQ: if (cmd_ready) state<=KRSP;
                KRSP: if (result_valid) begin
                    if (result_error) begin error_hold<=3; state<=DONE; end
                    else begin operand<=result_data; state<=DOT; end
                end
                DOT: begin
                    if (component==dim-1) state<=SCORE;
                    else begin component<=component+1'b1; state<=KREQ; end
                end
                SCORE: begin
                    begin_divide(mac_sum<<<16,
                        {32'd0,full_mode ? FULL_ROOT:LOCAL_ROOT},SCORE_SAVE);
                end
                DIVIDE: begin
                    div_quotient<=div_next_quotient; div_remainder<=div_next_remainder;
                    if (div_iteration==23) state<=div_return;
                    else div_iteration<=div_iteration+1'b1;
                end
                SCORE_SAVE: begin
                    score_value<=saturated_score;
                    if (pass==0) begin
                        if (!found_key || saturated_score>score_max)
                            score_max<=saturated_score;
                        found_key<=1; state<=NEXTKEY;
                    end else begin
                        if (difference< -96'sd268435456) begin
                            exponential<=0; state<=NEXTKEY;
                        end else begin
                            score_value<=difference[31:0]; state<=EXPREQ;
                        end
                    end
                end
                EXPREQ: if (nonlinear_ready) state<=EXPRSP;
                EXPRSP: if (nonlinear_out_valid) begin
                    if (nonlinear_out_error) begin error_hold<=1; state<=DONE; end
                    else begin
                        exponential<=nonlinear_out_data;
                        if (pass==1) begin
                            denominator<=denominator+{{64{nonlinear_out_data[31]}},nonlinear_out_data};
                            state<=NEXTKEY;
                        end else begin channel<=0; state<=VREQ; end
                    end
                end
                VREQ: if (cmd_ready) state<=VRSP;
                VRSP: if (result_valid) begin
                    if (result_error) begin error_hold<=3; state<=DONE; end
                    else begin operand<=result_data; state<=PRODUCT; end
                end
                PRODUCT: state<=WEIGHT;
                WEIGHT: begin
                    weighted[channel]<=weighted[channel]+mac_sum;
                    if (channel==dim-1) begin channel<=0; state<=NEXTKEY; end
                    else begin channel<=channel+1'b1; state<=VREQ; end
                end
                NEXTKEY: begin
                    if (key==tokens-1) begin
                        key<=0;
                        if (pass==0 && !found_key) begin channel<=0; state<=FINISH; end
                        else if (pass==2) begin channel<=0; state<=FINISH; end
                        else begin pass<=pass+1'b1; state<=MASKREQ; end
                    end else begin key<=key+1'b1; state<=MASKREQ; end
                end
                FINISH: begin
                    if (denominator==0) finish_channel(32'sd0);
                    else begin_divide(weighted[channel],denominator,FINISH_SAVE);
                end
                FINISH_SAVE: finish_channel(saturate(div_result));
                OUTPUT: if (out_ready) begin
                    if (channel==dim-1) state<=DONE;
                    else begin
                        channel<=channel+1'b1; data_hold<=values[channel+1'b1];
                        index_hold<=channel+1'b1; last_hold<=channel+1'b1==dim-1;
                    end
                end
                DONE: if (done_ready) state<=IDLE;
                default: begin error_hold<=1; state<=DONE; end
            endcase
        end
    end
endmodule
