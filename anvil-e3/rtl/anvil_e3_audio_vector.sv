module anvil_e3_audio_vector #(
    parameter integer MAX_WIDTH=4096
) (
    input wire clk, rst_n, start_valid,
    output wire start_ready,
    input wire [2:0] start_op,
    input wire [63:0] start_tokens,
    input wire [31:0] start_rows, start_cols,
    input wire [63:0] start_weights, start_input, start_aux, start_output,
    input wire start_clipped, start_bias, start_half,
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
    localparam MATRIX=0, NORM=1, SILU=2, ADD=3, GLU=4, REORDER=5, COPY=6;
    localparam IDLE=0, DISPATCH=1, BOUND_REQ=2, BOUND_RSP=3, BOUND_CHECK=4,
        LOAD_REQ=5, LOAD_RSP=6, WEIGHT_REQ=7, WEIGHT_RSP=8, MAC=9,
        BIAS_REQ=10, BIAS_RSP=11, CLAMP=12, WRITE_REQ=13, WRITE_RSP=14,
        NORM_START=15, NORM_WEIGHT_REQ=16, NORM_WEIGHT_RSP=17,
        NORM_FEED=18, NORM_OUT=19, AUX_REQ=20, AUX_RSP=21,
        ACT_START=22, ACT_WAIT=23, COMBINE=24, FLUSH=25, DONE=26;
    reg [4:0] state;
    reg [2:0] operation;
    reg [63:0] tokens, token, weights, input_base, aux_base, output_base;
    reg [31:0] rows, cols, index, row, col;
    reg clipped, bias, half_weight, last_norm;
    reg [1:0] bound_index;
    reg signed [31:0] input_max, input_min, output_max, output_min, gamma;
    reg signed [47:0] inputs [0:MAX_WIDTH-1];
    reg signed [47:0] operand, auxiliary, value, weight;
    reg signed [127:0] accumulator, matrix_value;
    reg [3:0] error_hold;
    reg signed [127:0] work, rounded_work;
    wire signed [95:0] product=inputs[col]*weight;
    wire signed [127:0] accumulated=accumulator+{{32{product[95]}},product};
    wire [63:0] element_count=operation==REORDER ? 64'(rows)*cols:64'(rows);
    wire [63:0] source_stride=operation==MATRIX ? 64'(cols):
        operation==GLU ? 64'(rows)*2:element_count;
    wire [63:0] source_index=operation==REORDER ?
        64'(index%cols)*rows+index/cols:64'(index);
    wire [63:0] matrix_base=weights+(clipped ? 64'd8:64'd0);
    wire [63:0] bound_word=bound_index<2 ? 64'(bound_index):
        64'(rows)*cols+bound_index;
    wire unit_rst_n=rst_n && state!=FLUSH;
    wire [127:0] input_words=128'(tokens)*(operation==MATRIX ? 128'(cols):
        operation==GLU ? 128'(rows)*2:operation==REORDER ? 128'(rows)*cols:128'(rows));
    wire [127:0] output_words=128'(tokens)*
        (operation==REORDER ? 128'(rows)*cols:128'(rows));
    wire [127:0] weight_words=operation==MATRIX ?
        128'(rows)*cols+(clipped ? 128'd4:128'd0):128'(rows);
    wire [127:0] aux_words=operation==MATRIX ? 128'(rows):128'(tokens)*rows;
    function automatic overflow(input [63:0] base, input [127:0] words);
        overflow=({64'd0,base}+words*4)>128'hffffffffffffffff;
    endfunction
    wire address_bad=overflow(input_base,input_words) || overflow(output_base,output_words) ||
        ((operation==MATRIX || operation==NORM) && overflow(weights,weight_words)) ||
        ((operation==ADD || (operation==MATRIX && bias)) && overflow(aux_base,aux_words));
    wire norm_start_ready, norm_in_ready, norm_valid, norm_last, norm_error;
    wire signed [47:0] norm_data;
    wire [31:0] norm_index;
    wire act_ready, act_valid, act_error;
    wire signed [47:0] act_data;
    function automatic signed [47:0] saturate(input signed [127:0] x);
        begin
            if (x>128'sd140737488289792) saturate=48'sh7fffffff0000;
            else if (x< -128'sd140737488355328) saturate=48'sh800000000000;
            else saturate=x[47:0];
        end
    endfunction
    function automatic signed [47:0] round_q80(input signed [127:0] x);
        reg signed [127:0] q;
        begin
            q=x>>>40;
            if (x[39:0]>40'h8000000000 ||
                (x[39:0]==40'h8000000000 && q[0])) q=q+1;
            round_q80=saturate(q);
        end
    endfunction
    function automatic signed [127:0] round_wide(input signed [127:0] x);
        reg signed [127:0] q;
        begin
            q=x>>>40;
            if (x[39:0]>40'h8000000000 ||
                (x[39:0]==40'h8000000000 && q[0])) q=q+1;
            round_wide=q;
        end
    endfunction
    function automatic signed [31:0] materialize(input signed [47:0] x);
        reg signed [48:0] q;
        begin
            q=$signed({x[47],x})>>>16;
            if (x[15:0]>16'h8000 || (x[15:0]==16'h8000 && q[0])) q=q+1;
            if (q>49'sd2147483647) materialize=32'sh7fffffff;
            else if (q< -49'sd2147483648) materialize=32'sh80000000;
            else materialize=q[31:0];
        end
    endfunction
    anvil_e3_audio_norm #(.MAX_WIDTH(MAX_WIDTH)) normalization (
        .clk(clk), .rst_n(unit_rst_n), .start_valid(state==NORM_START),
        .start_ready(norm_start_ready), .start_count(rows), .start_l2(1'b0),
        .in_valid(state==NORM_FEED), .in_ready(norm_in_ready),
        .in_data(operand), .in_weight(gamma),
        .out_valid(norm_valid), .out_ready(state==NORM_OUT),
        .out_data(norm_data), .out_index(norm_index), .out_last(norm_last),
        .out_error(norm_error)
    );
    anvil_e3_audio_activation activation (
        .clk(clk), .rst_n(unit_rst_n), .in_valid(state==ACT_START),
        .in_ready(act_ready), .in_op(operation==GLU ? 2'd1:2'd0),
        .in_data(operation==GLU ? {{16{auxiliary[47]}},auxiliary}:
            {{16{operand[47]}},operand}),
        .out_valid(act_valid), .out_ready(state==ACT_WAIT),
        .out_data(act_data), .out_error(act_error)
    );
    initial begin
        if (MAX_WIDTH<=0 || MAX_WIDTH>65535)
            $fatal(1,"PARAMETER ERROR: audio vector width must be 1..65535");
    end
    assign start_ready=rst_n && state==IDLE;
    assign cmd_valid=rst_n && (state==BOUND_REQ || state==LOAD_REQ ||
        state==WEIGHT_REQ || state==BIAS_REQ || state==WRITE_REQ ||
        state==NORM_WEIGHT_REQ || state==AUX_REQ);
    assign cmd_write=rst_n && state==WRITE_REQ;
    assign cmd_addr=!rst_n ? 64'd0:
        state==BOUND_REQ ? weights+bound_word*4:
        state==LOAD_REQ ? input_base+(token*source_stride+source_index)*4:
        state==WEIGHT_REQ ? matrix_base+(64'(row)*cols+col)*4:
        state==BIAS_REQ ? aux_base+64'(row)*4:
        state==WRITE_REQ ? output_base+
            (token*element_count+(operation==MATRIX ? 64'(row):64'(index)))*4:
        state==NORM_WEIGHT_REQ ? weights+64'(index)*4:
        state==AUX_REQ ? (operation==GLU ?
            input_base+(token*source_stride+rows+index)*4:
            aux_base+(token*element_count+index)*4):64'd0;
    assign cmd_wdata=rst_n && state==WRITE_REQ ? materialize(value):32'd0;
    assign result_ready=rst_n && (state==BOUND_RSP || state==LOAD_RSP ||
        state==WEIGHT_RSP || state==BIAS_RSP || state==WRITE_RSP ||
        state==NORM_WEIGHT_RSP || state==AUX_RSP);
    assign done_valid=rst_n && state==DONE;
    assign done_error=rst_n ? error_hold:4'd0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=IDLE; operation<=0; tokens<=0; token<=0; weights<=0;
            input_base<=0; aux_base<=0; output_base<=0; rows<=0; cols<=0;
            index<=0; row<=0; col<=0; clipped<=0; bias<=0; half_weight<=0;
            last_norm<=0; bound_index<=0; input_max<=0; input_min<=0;
            output_max<=0; output_min<=0; gamma<=0; operand<=0; auxiliary<=0;
            value<=0; weight<=0; accumulator<=0; matrix_value<=0; error_hold<=0;
            work=0; rounded_work=0;
        end else if (result_valid && result_ready && result_error) begin
            error_hold<=3; state<=FLUSH;
        end else case (state)
            IDLE: if (start_valid) begin
                operation<=start_op; tokens<=start_tokens; token<=0;
                rows<=start_rows; cols<=start_cols; weights<=start_weights;
                input_base<=start_input; aux_base<=start_aux; output_base<=start_output;
                clipped<=start_clipped; bias<=start_bias; half_weight<=start_half;
                index<=0; row<=0; col<=0; bound_index<=0; accumulator<=0;
                error_hold<=0; last_norm<=0;
                if (start_tokens==0 || start_rows==0 || start_rows>65535 ||
                    start_op>6 || |start_input[1:0] || |start_output[1:0] ||
                    ((start_op==MATRIX || start_op==NORM) && |start_weights[1:0]) ||
                    ((start_op==ADD || (start_op==MATRIX && start_bias)) && |start_aux[1:0]) ||
                    (start_op==MATRIX && (start_cols==0 || start_cols>MAX_WIDTH)) ||
                    (start_op==NORM && start_rows>MAX_WIDTH) ||
                    (start_op==REORDER && (start_cols==0 ||
                        64'(start_rows)*start_cols>32'hffffffff))) begin
                    error_hold<=1; state<=FLUSH;
                end else state<=DISPATCH;
            end
            DISPATCH: begin
                index<=0; row<=0; col<=0; accumulator<=0;
                if (address_bad) begin error_hold<=5; state<=FLUSH; end
                else if (operation==MATRIX && clipped) state<=BOUND_REQ;
                else if (operation==NORM) state<=NORM_START;
                else state<=LOAD_REQ;
            end
            BOUND_REQ: if (cmd_ready) state<=BOUND_RSP;
            BOUND_RSP: if (result_valid) begin
                case (bound_index)
                    0: input_max<=result_data;
                    1: input_min<=result_data;
                    2: output_max<=result_data;
                    3: output_min<=result_data;
                endcase
                if (bound_index==3) state<=BOUND_CHECK;
                else begin bound_index<=bound_index+1'b1; state<=BOUND_REQ; end
            end
            BOUND_CHECK: begin
                if (input_min>input_max || output_min>output_max) begin
                    error_hold<=2; state<=FLUSH;
                end else state<=LOAD_REQ;
            end
            LOAD_REQ: if (cmd_ready) state<=LOAD_RSP;
            LOAD_RSP: if (result_valid) begin
                work=$signed({{80{result_data[31]}},result_data,16'd0});
                if (operation==MATRIX) begin
                    if (clipped && $signed(result_data)<input_min)
                        work=$signed({{80{input_min[31]}},input_min,16'd0});
                    else if (clipped && $signed(result_data)>input_max)
                        work=$signed({{80{input_max[31]}},input_max,16'd0});
                    inputs[index]<=work[47:0];
                    if (index==cols-1) begin index<=0; state<=WEIGHT_REQ; end
                    else begin index<=index+1'b1; state<=LOAD_REQ; end
                end else begin
                    operand<=work[47:0];
                    case (operation)
                        NORM: state<=NORM_WEIGHT_REQ;
                        SILU: state<=ACT_START;
                        ADD,GLU: state<=AUX_REQ;
                        REORDER,COPY: begin value<=work[47:0]; state<=WRITE_REQ; end
                        default: begin error_hold<=6; state<=FLUSH; end
                    endcase
                end
            end
            WEIGHT_REQ: if (cmd_ready) state<=WEIGHT_RSP;
            WEIGHT_RSP: if (result_valid) begin
                weight<={result_data,16'd0}; state<=MAC;
            end
            MAC: begin
                accumulator<=accumulated;
                if (col==cols-1) begin
                    matrix_value<=round_wide(accumulated);
                    if (bias) state<=BIAS_REQ; else state<=CLAMP;
                end else begin col<=col+1'b1; state<=WEIGHT_REQ; end
            end
            BIAS_REQ: if (cmd_ready) state<=BIAS_RSP;
            BIAS_RSP: if (result_valid) begin
                matrix_value<=matrix_value+
                    $signed({{80{result_data[31]}},result_data,16'd0});
                state<=CLAMP;
            end
            CLAMP: begin
                if (clipped && matrix_value<$signed({{80{output_min[31]}},output_min,16'd0}))
                    value<={output_min,16'd0};
                else if (clipped && matrix_value>$signed({{80{output_max[31]}},output_max,16'd0}))
                    value<={output_max,16'd0};
                else value<=saturate(matrix_value);
                state<=WRITE_REQ;
            end
            NORM_START: if (norm_start_ready) begin index<=0; state<=LOAD_REQ; end
            NORM_WEIGHT_REQ: if (cmd_ready) state<=NORM_WEIGHT_RSP;
            NORM_WEIGHT_RSP: if (result_valid) begin gamma<=result_data; state<=NORM_FEED; end
            NORM_FEED: if (norm_in_ready) begin
                if (index==rows-1) begin index<=0; state<=NORM_OUT; end
                else begin index<=index+1'b1; state<=LOAD_REQ; end
            end
            NORM_OUT: if (norm_valid) begin
                if (norm_error) begin error_hold<=6; state<=FLUSH; end
                else begin
                    value<=norm_data; index<=norm_index; last_norm<=norm_last;
                    state<=WRITE_REQ;
                end
            end
            AUX_REQ: if (cmd_ready) state<=AUX_RSP;
            AUX_RSP: if (result_valid) begin
                auxiliary<={result_data,16'd0};
                if (operation==GLU) state<=ACT_START; else state<=COMBINE;
            end
            ACT_START: if (act_ready) state<=ACT_WAIT;
            ACT_WAIT: if (act_valid) begin
                if (act_error) begin error_hold<=6; state<=FLUSH; end
                else if (operation==GLU) begin auxiliary<=act_data; state<=COMBINE; end
                else begin value<=act_data; state<=WRITE_REQ; end
            end
            COMBINE: begin
                if (operation==GLU) begin
                    work=$signed(operand)*$signed(auxiliary);
                    value<=round_q80(work);
                end else begin
                    work=$signed({{80{auxiliary[47]}},auxiliary});
                    if (half_weight) begin
                        rounded_work=work>>>1;
                        if (work[0] && rounded_work[0]) rounded_work=rounded_work+1;
                        work=rounded_work;
                    end
                    value<=saturate($signed({{80{operand[47]}},operand})+work);
                end
                state<=WRITE_REQ;
            end
            WRITE_REQ: if (cmd_ready) state<=WRITE_RSP;
            WRITE_RSP: if (result_valid) begin
                if (operation==MATRIX && row!=rows-1) begin
                    row<=row+1'b1; col<=0; accumulator<=0; state<=WEIGHT_REQ;
                end else if (operation==NORM && !last_norm) state<=NORM_OUT;
                else if (operation!=MATRIX && operation!=NORM && 64'(index)!=element_count-1) begin
                    index<=index+1'b1; state<=LOAD_REQ;
                end else if (token==tokens-1) state<=DONE;
                else begin
                    token<=token+1'b1; index<=0; row<=0; col<=0; accumulator<=0;
                    if (operation==NORM) state<=NORM_START;
                    else state<=LOAD_REQ;
                end
            end
            FLUSH: state<=DONE;
            DONE: if (done_ready) state<=IDLE;
            default: begin error_hold<=6; state<=FLUSH; end
        endcase
    end
endmodule
