module anvil_e2_attention #(
    parameter integer NUM_Q_HEADS=4, LOCAL_KV_HEADS=2, FULL_KV_HEADS=1,
    LOCAL_HEAD_DIM=256, FULL_HEAD_DIM=512, SLIDING_WINDOW=512, VISION=0
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
    output wire signed [47:0] mac_a, mac_b,
    input wire signed [127:0] mac_sum,
    input wire signed [95:0] mac_product,
    output wire nonlinear_valid,
    input wire nonlinear_ready,
    output wire [2:0] nonlinear_op,
    output wire signed [47:0] nonlinear_data,
    input wire nonlinear_out_valid,
    output wire nonlinear_out_ready,
    input wire signed [47:0] nonlinear_out_data,
    input wire nonlinear_out_error,
    output wire out_valid,
    input wire out_ready,
    output wire signed [47:0] out_data,
    output wire [31:0] out_index,
    output wire out_last,
    output wire done_valid,
    input wire done_ready,
    output wire [3:0] done_error
);
    localparam integer DM=LOCAL_HEAD_DIM>FULL_HEAD_DIM ? LOCAL_HEAD_DIM:FULL_HEAD_DIM;
    localparam integer KM=LOCAL_KV_HEADS>FULL_KV_HEADS ? LOCAL_KV_HEADS:FULL_KV_HEADS;
    localparam [63:0] KV_TOKEN_BYTES=64'(KM)*DM*64'd4;
    localparam IDLE=0, QREQ=1, QRSP=2, POSREQ=3, POSRSP=4,
        MASKREQ=5, MASKRSP=6, KPOSREQ=7, KPOSRSP=8, KREQ=9, KRSP=10,
        SCORE=12, EXPREQ=13, EXPRSP=14, VREQ=15, VRSP=16,
        NEXTKEY=19, FINISH=20, OUTPUT=21, DONE=22,
        SCORE_WAIT=23, FINISH_WAIT=24;
    reg [4:0] state;
    reg [31:0] tokens, dim, key, component, channel;
    reg [31:0] query_position;
    reg full_mode, found_key;
    reg weighted_pass;
    reg [63:0] position_base, mask_base;
    reg [63:0] q_addr, query_position_addr, key_position_addr, key_mask_addr;
    reg [63:0] k_head_base, v_head_base, k_key_base, v_key_base, k_addr, v_addr;
    wire [63:0] local_group, full_group;
    anvil_e2_const_divide #(
        .DIVISOR(LOCAL_KV_HEADS>0 ? NUM_Q_HEADS/LOCAL_KV_HEADS:1)
    ) local_group_divide (
        .numerator({32'd0,start_head}), .quotient(local_group), .remainder()
    );
    anvil_e2_const_divide #(
        .DIVISOR(FULL_KV_HEADS>0 ? NUM_Q_HEADS/FULL_KV_HEADS:1)
    ) full_group_divide (
        .numerator({32'd0,start_head}), .quotient(full_group), .remainder()
    );
    wire [63:0] kv_byte_offset=(start_full ? full_group:local_group)*
        64'(start_full ? FULL_HEAD_DIM:LOCAL_HEAD_DIM)*64'd4;
    reg signed [47:0] q_values [0:DM-1];
    reg signed [127:0] weighted [0:DM-1];
    reg signed [47:0] values [0:DM-1];
    reg signed [47:0] score_max, score_value, exponential;
    reg signed [127:0] denominator;
    reg [3:0] error_hold;
    reg signed [47:0] data_hold;
    reg [31:0] index_hold;
    reg last_hold;
    wire signed [127:0] difference=
        {{80{saturated_score[47]}},saturated_score}-
        {{80{score_max[47]}},score_max};
    wire signed [47:0] saturated_score=saturate(divide_result);
    wire [32:0] position_difference={1'b0,result_data}>{1'b0,query_position} ?
        {1'b0,result_data}-{1'b0,query_position}:
        {1'b0,query_position}-{1'b0,result_data};

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

    function automatic signed [47:0] saturate;
        input signed [127:0] value;
        begin
            if (value>128'sd140737488289792) saturate=48'sh7fffffff0000;
            else if (value< -128'sd140737488355328) saturate=48'sh800000000000;
            else saturate=value[47:0];
        end
    endfunction
    wire divide_clk, divide_active;
    wire divide_in_ready_raw, divide_out_valid_raw;
    wire divide_in_ready, divide_out_valid, divide_error;
    wire signed [127:0] divide_result;
    wire signed [47:0] finished_value=denominator==0 ? 48'sd0:saturate(divide_result);
    anvil_e2_clock_gate divide_clock (
        .clk(clk), .rst_n(rst_n),
        .enable(state==SCORE || state==SCORE_WAIT ||
            ((state==FINISH || state==FINISH_WAIT) && denominator!=0)),
        .active(divide_active), .gated_clk(divide_clk)
    );
    assign divide_in_ready=divide_active && divide_in_ready_raw;
    assign divide_out_valid=divide_active && divide_out_valid_raw;
    anvil_e2_divide divider (
        .clk(divide_clk), .rst_n(rst_n),
        .in_valid(rst_n && divide_active &&
            (state==SCORE || (state==FINISH && denominator!=0))),
        .in_ready(divide_in_ready_raw),
        .in_numerator(state==SCORE ? mac_sum:weighted[channel]),
        .in_denominator(state==SCORE ?
            {64'd0,full_mode ? FULL_ROOT:LOCAL_ROOT}:$unsigned(denominator)),
        .out_valid(divide_out_valid_raw),
        .out_ready(rst_n && divide_active &&
            (state==SCORE_WAIT || state==FINISH_WAIT)),
        .out_data(divide_result), .out_error(divide_error)
    );
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
        state==QREQ ? q_addr:
        state==POSREQ ? query_position_addr:
        state==MASKREQ ? key_mask_addr:
        state==KPOSREQ ? key_position_addr:
        state==KREQ ? k_addr:
        state==VREQ ? v_addr:64'd0;
    assign result_ready=rst_n && (state==QRSP || state==POSRSP || state==MASKRSP ||
                                  state==KPOSRSP || state==KRSP || state==VRSP);
    assign mac_clear=mac_accumulate && (state==VRSP || component==0);
    assign mac_accumulate=rst_n && (state==KRSP || state==VRSP) &&
                          result_valid && !result_error;
    assign mac_a=!mac_accumulate ? 48'sd0 :
                 state==KRSP ? q_values[component]:exponential;
    assign mac_b=mac_accumulate ? {result_data,16'd0}:48'sd0;
    assign nonlinear_valid=rst_n && state==EXPREQ;
    assign nonlinear_op=3'd0;
    assign nonlinear_data=rst_n && state==EXPREQ ? score_value:48'sd0;
    assign nonlinear_out_ready=rst_n && state==EXPRSP;
    assign out_valid=rst_n && state==OUTPUT;
    assign out_data=rst_n ? data_hold:48'sd0;
    assign out_index=rst_n ? index_hold:32'd0;
    assign out_last=rst_n && last_hold;
    assign done_valid=rst_n && state==DONE;
    assign done_error=rst_n ? error_hold:4'd0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=IDLE; tokens<=0; dim<=0;
            key<=0; component<=0; channel<=0; query_position<=0;
            full_mode<=0; found_key<=0; weighted_pass<=0;
            position_base<=0; mask_base<=0;
            q_addr<=0; query_position_addr<=0; key_position_addr<=0; key_mask_addr<=0;
            k_head_base<=0; v_head_base<=0; k_key_base<=0; v_key_base<=0;
            k_addr<=0; v_addr<=0;
            score_max<=0; score_value<=0; exponential<=0;
            denominator<=0; error_hold<=0; data_hold<=0; index_hold<=0; last_hold<=0;
        end else begin
            case (state)
                IDLE: if (start_valid) begin
                    tokens<=start_tokens;
                    full_mode<=start_full;
                    dim<=start_full ? FULL_HEAD_DIM:LOCAL_HEAD_DIM;
                    q_addr<=start_q_base+(64'(start_query)*NUM_Q_HEADS*DM+
                        64'(start_head)*64'(start_full ? FULL_HEAD_DIM:LOCAL_HEAD_DIM))*64'd4;
                    k_head_base<=start_k_base+kv_byte_offset;
                    v_head_base<=start_v_base+kv_byte_offset;
                    k_key_base<=start_k_base+kv_byte_offset;
                    v_key_base<=start_v_base+kv_byte_offset;
                    k_addr<=start_k_base+kv_byte_offset;
                    v_addr<=start_v_base+kv_byte_offset;
                    position_base<=start_positions_base; mask_base<=start_mask_base;
                    query_position_addr<=start_positions_base+64'(start_query)*64'd4;
                    key_position_addr<=start_positions_base; key_mask_addr<=start_mask_base;
                    component<=0; channel<=0; key<=0; weighted_pass<=0; found_key<=0;
                    denominator<=0; error_hold<=0;
                    if (start_tokens==0 || start_query>=start_tokens || start_head>=NUM_Q_HEADS) begin
                        error_hold<=1; state<=DONE;
                    end else state<=QREQ;
                end
                QREQ: if (cmd_ready) state<=QRSP;
                QRSP: if (result_valid) begin
                    if (result_error) begin error_hold<=3; state<=DONE; end
                    else begin
                        q_values[component]<={result_data,16'd0};
                        weighted[component]<=0;
                        if (component==dim-1) begin
                            component<=0;
                            if (VISION) state<=KREQ;
                            else state<=POSREQ;
                        end
                        else begin
                            component<=component+1'b1; q_addr<=q_addr+64'd4;
                            state<=QREQ;
                        end
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
                    else if (component==dim-1) state<=SCORE;
                    else begin
                        component<=component+1'b1; k_addr<=k_addr+64'd4;
                        state<=KREQ;
                    end
                end
                SCORE: if (divide_in_ready) state<=SCORE_WAIT;
                SCORE_WAIT: if (divide_out_valid) begin
                    if (divide_error) begin error_hold<=6; state<=DONE; end
                    else begin
                        score_value<=saturated_score;
                        if (!weighted_pass) begin
                            if (!found_key || saturated_score>score_max)
                                score_max<=saturated_score;
                            found_key<=1; state<=NEXTKEY;
                        end else begin
                            if (difference< -128'sd17592186044416) begin
                                exponential<=0; state<=NEXTKEY;
                            end else begin
                                score_value<=difference[47:0]; state<=EXPREQ;
                            end
                        end
                    end
                end
                EXPREQ: if (nonlinear_ready) state<=EXPRSP;
                EXPRSP: if (nonlinear_out_valid) begin
                    if (nonlinear_out_error) begin error_hold<=1; state<=DONE; end
                    else begin
                        exponential<=nonlinear_out_data;
                        denominator<=denominator+{{80{nonlinear_out_data[47]}},nonlinear_out_data};
                        channel<=0; state<=VREQ;
                    end
                end
                VREQ: if (cmd_ready) state<=VRSP;
                VRSP: if (result_valid) begin
                    if (result_error) begin error_hold<=3; state<=DONE; end
                    else begin
                        weighted[channel]<=weighted[channel]+
                                           {{32{mac_product[95]}},mac_product};
                        if (channel==dim-1) begin channel<=0; state<=NEXTKEY; end
                        else begin
                            channel<=channel+1'b1; v_addr<=v_addr+64'd4;
                            state<=VREQ;
                        end
                    end
                end
                NEXTKEY: begin
                    if (key==tokens-1) begin
                        key<=0;
                        k_key_base<=k_head_base; v_key_base<=v_head_base;
                        k_addr<=k_head_base; v_addr<=v_head_base;
                        key_position_addr<=position_base; key_mask_addr<=mask_base;
                        if (weighted_pass || !found_key) begin
                            channel<=0; state<=FINISH;
                        end
                        else begin
                            weighted_pass<=1;
                            if (VISION) begin component<=0; state<=KREQ; end
                            else state<=MASKREQ;
                        end
                    end else begin
                        key<=key+1'b1;
                        k_key_base<=k_key_base+KV_TOKEN_BYTES;
                        v_key_base<=v_key_base+KV_TOKEN_BYTES;
                        k_addr<=k_key_base+KV_TOKEN_BYTES;
                        v_addr<=v_key_base+KV_TOKEN_BYTES;
                        key_position_addr<=key_position_addr+64'd4;
                        key_mask_addr<=key_mask_addr+64'd4;
                        if (VISION) begin component<=0; state<=KREQ; end
                        else state<=MASKREQ;
                    end
                end
                FINISH: begin
                    if (denominator==0 || divide_in_ready) state<=FINISH_WAIT;
                end
                FINISH_WAIT: if (denominator==0 || divide_out_valid) begin
                    if (denominator!=0 && divide_error) begin error_hold<=6; state<=DONE; end
                    else begin
                        values[channel]<=finished_value;
                        if (channel==dim-1) begin
                            channel<=0; index_hold<=0; last_hold<=dim==1;
                            data_hold<=dim==1 ? finished_value:values[0];
                            state<=OUTPUT;
                        end else begin channel<=channel+1'b1; state<=FINISH; end
                    end
                end
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
