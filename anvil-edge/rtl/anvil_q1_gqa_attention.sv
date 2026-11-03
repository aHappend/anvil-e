module anvil_q1_gqa_attention #(
  parameter NUM_LAYERS=24, HIDDEN_SIZE=896, NUM_Q_HEADS=14,
  NUM_KV_HEADS=2, HEAD_DIM=64, MAX_SEQ_LEN=32768
) (
  input wire clk, rst_n, cmd_valid,
  output wire cmd_ready,
  input wire [31:0] cmd_layer, cmd_pos,
  output wire done, error,
  output wire mem_req_valid,
  input wire mem_req_ready,
  output wire mem_req_write,
  output wire [3:0] mem_req_kind,
  output wire [31:0] mem_req_layer,
  output wire [2:0] mem_req_proj,
  output wire [31:0] mem_req_row, mem_req_col, mem_req_wdata,
  input wire mem_rsp_valid,
  output wire mem_rsp_ready,
  input wire [31:0] mem_rsp_rdata,
  input wire mem_rsp_error
);
  localparam SAFE_K=NUM_KV_HEADS>0 ? NUM_KV_HEADS : 1;
  localparam [31:0] RATIO=NUM_Q_HEADS/SAFE_K;
  localparam [63:0] KV_SIZE=64'(NUM_KV_HEADS)*64'(HEAD_DIM);
  localparam [5:0] IDLE=0, ROOT=1, ROOT_WAIT=2, CACHE_READ=3, CACHE_READ_WAIT=4,
    CACHE_WRITE=5, CACHE_WRITE_WAIT=6, COORDINATES=7, READ_Q=8, WAIT_Q=9,
    READ_KEY=10, WAIT_KEY=11, DOT_MULTIPLY=12, DOT_WAIT=13, DOT_ADD=14,
    SCORE_DIVIDE=15, SCORE_WAIT=16, SCORE_CHECK=17, DIFFERENCE=18,
    CLAMP=19, EXP=20, EXP_WAIT=21, DENOMINATOR_ADD=22, READ_VALUE=23,
    WAIT_VALUE=24, WEIGHT_MULTIPLY=25, WEIGHT_WAIT=26, WEIGHT_ADD=27,
    NEXT_TIME=28, OUTPUT_DIVIDE=29, OUTPUT_WAIT=30, SATURATE=31,
    WRITE_CONTEXT=32, WRITE_CONTEXT_WAIT=33, ADVANCE=34, FINISH=35,
    INVALID_COMMAND=36;
  reg [5:0] state;
  reg failed, value_cache, context_pass;
  reg [31:0] layer, position, index, head, head_base, kv_base, group_head;
  reg [31:0] time_index, dim, component, q_column, k_column, exponential;
  reg signed [31:0] q, cache_data, output_value;
  reg signed [63:0] dot_product, exp_argument;
  reg signed [64:0] weighted_product;
  reg signed [95:0] dot, max_score, current_score, weighted;
  reg signed [96:0] score_difference;
  reg signed [127:0] divided_output;
  reg [63:0] denominator, sqrt_dimension;
  wire root_ready, root_valid;
  wire [63:0] root_value;
  wire multiply_ready, multiply_valid;
  wire signed [127:0] product;
  wire divide_ready, divide_valid, divide_error;
  wire signed [127:0] division_result;
  wire exp_ready, exp_valid, exp_error;
  wire [31:0] exp_result;
  wire port_idle, complete, fault;
  wire [31:0] read_data;
  reg issue, write_request;
  reg [3:0] kind;
  reg [31:0] row, col, write_data, memory_layer;
  wire weighted_operation=state==WEIGHT_MULTIPLY || state==WEIGHT_WAIT;
  wire signed [63:0] multiply_a=weighted_operation ?
    $signed({{32{cache_data[31]}},cache_data}) : $signed({{32{q[31]}},q});
  wire signed [63:0] multiply_b=weighted_operation ?
    $signed({32'd0,exponential}) : $signed({{32{cache_data[31]}},cache_data});
  anvil_edge_parameters #(
    NUM_LAYERS,HIDDEN_SIZE,HIDDEN_SIZE,NUM_Q_HEADS,NUM_KV_HEADS,
    HEAD_DIM,1,4,1,MAX_SEQ_LEN
  ) parameters_ok();
  anvil_q1_mem_port memory_port(
    .clk(clk),.rst_n(rst_n),.issue(issue),.write(write_request),.kind(kind),
    .layer(memory_layer),.proj(3'd0),.row(row),.col(col),.wdata(write_data),
    .idle(port_idle),.complete(complete),.rdata(read_data),.fault(fault),
    .mem_req_valid(mem_req_valid),.mem_req_ready(mem_req_ready),
    .mem_req_write(mem_req_write),.mem_req_kind(mem_req_kind),
    .mem_req_layer(mem_req_layer),.mem_req_proj(mem_req_proj),
    .mem_req_row(mem_req_row),.mem_req_col(mem_req_col),.mem_req_wdata(mem_req_wdata),
    .mem_rsp_valid(mem_rsp_valid),.mem_rsp_ready(mem_rsp_ready),
    .mem_rsp_rdata(mem_rsp_rdata),.mem_rsp_error(mem_rsp_error)
  );
  anvil_edge_isqrt128 root_unit(
    .clk(clk),.rst_n(rst_n),.in_valid(state==ROOT),.in_ready(root_ready),
    .radicand(128'(HEAD_DIM) << 32),.out_valid(root_valid),
    .out_ready(state==ROOT_WAIT),.root(root_value)
  );
  anvil_edge_signed_multiplier #(.WIDTH(64)) multiplier(
    .clk(clk),.rst_n(rst_n),
    .in_valid(state==DOT_MULTIPLY || state==WEIGHT_MULTIPLY),.in_ready(multiply_ready),
    .operand_a(multiply_a),.operand_b(multiply_b),.out_valid(multiply_valid),
    .out_ready(state==DOT_WAIT || state==WEIGHT_WAIT),.product(product)
  );
  anvil_edge_round_div rounded_divider(
    .clk(clk),.rst_n(rst_n),
    .in_valid(state==SCORE_DIVIDE || state==OUTPUT_DIVIDE),.in_ready(divide_ready),
    .numerator(state==SCORE_DIVIDE ? {{32{dot[95]}},dot} : {{32{weighted[95]}},weighted}),
    .divisor(state==SCORE_DIVIDE ? sqrt_dimension : denominator),
    .out_valid(divide_valid),.out_ready(state==SCORE_WAIT || state==OUTPUT_WAIT),
    .value(division_result),.divide_by_zero(divide_error)
  );
  anvil_edge_exp_q24 exponential_unit(
    .clk(clk),.rst_n(rst_n),.in_valid(state==EXP),.in_ready(exp_ready),
    .x(exp_argument),.out_valid(exp_valid),.out_ready(state==EXP_WAIT),
    .value(exp_result),.arithmetic_error(exp_error)
  );
  assign cmd_ready=rst_n && state==IDLE;
  assign done=rst_n && state==FINISH;
  assign error=done && failed;
  always @* begin
    issue=0; write_request=0; kind=0; row=0; col=0; write_data=0; memory_layer=0;
    if (rst_n && port_idle) case (state)
      CACHE_READ: begin issue=1; kind=8; row=value_cache ? 4 : 3; col=index; end
      CACHE_WRITE: begin
        issue=1; write_request=1; kind=value_cache ? 10 : 9;
        memory_layer=layer; row=position; col=index; write_data=cache_data;
      end
      READ_Q: begin issue=1; kind=8; row=2; col=q_column; end
      READ_KEY: begin issue=1; kind=9; memory_layer=layer; row=time_index; col=k_column; end
      READ_VALUE: begin
        issue=1; kind=10; memory_layer=layer; row=time_index; col=kv_base+component;
      end
      WRITE_CONTEXT: begin
        issue=1; write_request=1; kind=8; row=5; col=head_base+component; write_data=output_value;
      end
      default: begin end
    endcase
  end
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state<=IDLE; failed<=0; value_cache<=0; context_pass<=0;
      layer<=0; position<=0; index<=0; head<=0; head_base<=0; kv_base<=0; group_head<=0;
      time_index<=0; dim<=0; component<=0; q_column<=0; k_column<=0; exponential<=0;
      q<=0; cache_data<=0; output_value<=0; dot_product<=0; exp_argument<=0;
      weighted_product<=0; dot<=0; max_score<=0; current_score<=0; weighted<=0;
      score_difference<=0; divided_output<=0; denominator<=0; sqrt_dimension<=0;
    end else if (fault) begin failed<=1; state<=FINISH; end
    else case (state)
      IDLE: if (cmd_valid && cmd_ready) begin
        failed<=0; layer<=cmd_layer; position<=cmd_pos; index<=0; value_cache<=0;
        head<=0; head_base<=0; kv_base<=0; group_head<=0;
        time_index<=0; dim<=0; component<=0; context_pass<=0;
        dot<=0; max_score<={1'b1,95'd0}; weighted<=0; denominator<=0;
        if (cmd_layer>=NUM_LAYERS || cmd_pos>=MAX_SEQ_LEN) begin
          failed<=1; state<=INVALID_COMMAND;
        end else state<=ROOT;
      end
      ROOT: if (root_ready) state<=ROOT_WAIT;
      ROOT_WAIT: if (root_valid) begin
        if (root_value==0) begin failed<=1; state<=FINISH; end
        else begin sqrt_dimension<=root_value; state<=CACHE_READ; end
      end
      CACHE_READ: if (issue) state<=CACHE_READ_WAIT;
      CACHE_READ_WAIT: if (complete) begin cache_data<=read_data; state<=CACHE_WRITE; end
      CACHE_WRITE: if (issue) state<=CACHE_WRITE_WAIT;
      CACHE_WRITE_WAIT: if (complete) begin
        if (index+1<KV_SIZE) begin index<=index+1; state<=CACHE_READ; end
        else if (!value_cache) begin value_cache<=1; index<=0; state<=CACHE_READ; end
        else state<=COORDINATES;
      end
      COORDINATES: begin q_column<=head_base+dim; k_column<=kv_base+dim; state<=READ_Q; end
      READ_Q: if (issue) state<=WAIT_Q;
      WAIT_Q: if (complete) begin q<=read_data; state<=READ_KEY; end
      READ_KEY: if (issue) state<=WAIT_KEY;
      WAIT_KEY: if (complete) begin cache_data<=read_data; state<=DOT_MULTIPLY; end
      DOT_MULTIPLY: if (multiply_ready) state<=DOT_WAIT;
      DOT_WAIT: if (multiply_valid) begin dot_product<=product[63:0]; state<=DOT_ADD; end
      DOT_ADD: begin
        dot<=dot+{{32{dot_product[63]}},dot_product};
        if (dim+1<HEAD_DIM) begin dim<=dim+1; state<=COORDINATES; end
        else state<=SCORE_DIVIDE;
      end
      SCORE_DIVIDE: if (divide_ready) state<=SCORE_WAIT;
      SCORE_WAIT: if (divide_valid) begin
        if (divide_error) begin failed<=1; state<=FINISH; end
        else begin current_score<=division_result[95:0]; state<=SCORE_CHECK; end
      end
      SCORE_CHECK: begin
        if (!context_pass) begin
          if (current_score>max_score) max_score<=current_score;
          time_index<=time_index<position ? time_index+1 : 0;
          if (time_index==position) context_pass<=1;
          dim<=0; dot<=0; state<=COORDINATES;
        end else state<=DIFFERENCE;
      end
      DIFFERENCE: begin
        score_difference<=$signed({current_score[95],current_score})-
                          $signed({max_score[95],max_score});
        state<=CLAMP;
      end
      CLAMP: begin
        if (score_difference< -97'sd1048576) exp_argument<= -64'sd1048577;
        else if (score_difference>0) exp_argument<=0;
        else exp_argument<=score_difference[63:0];
        state<=EXP;
      end
      EXP: if (exp_ready) state<=EXP_WAIT;
      EXP_WAIT: if (exp_valid) begin
        if (exp_error) begin failed<=1; state<=FINISH; end
        else begin exponential<=exp_result; state<=DENOMINATOR_ADD; end
      end
      DENOMINATOR_ADD: begin denominator<=denominator+{32'd0,exponential}; state<=READ_VALUE; end
      READ_VALUE: if (issue) state<=WAIT_VALUE;
      WAIT_VALUE: if (complete) begin cache_data<=read_data; state<=WEIGHT_MULTIPLY; end
      WEIGHT_MULTIPLY: if (multiply_ready) state<=WEIGHT_WAIT;
      WEIGHT_WAIT: if (multiply_valid) begin weighted_product<=product[64:0]; state<=WEIGHT_ADD; end
      WEIGHT_ADD: begin
        weighted<=weighted+{{31{weighted_product[64]}},weighted_product}; state<=NEXT_TIME;
      end
      NEXT_TIME: begin
        if (time_index<position) begin
          time_index<=time_index+1; dim<=0; dot<=0; state<=COORDINATES;
        end else if (denominator==0) begin failed<=1; state<=FINISH; end
        else state<=OUTPUT_DIVIDE;
      end
      OUTPUT_DIVIDE: if (divide_ready) state<=OUTPUT_WAIT;
      OUTPUT_WAIT: if (divide_valid) begin
        if (divide_error) begin failed<=1; state<=FINISH; end
        else begin divided_output<=division_result; state<=SATURATE; end
      end
      SATURATE: begin output_value<=anvil_edge_numeric_pkg::sat32(divided_output); state<=WRITE_CONTEXT; end
      WRITE_CONTEXT: if (issue) state<=WRITE_CONTEXT_WAIT;
      WRITE_CONTEXT_WAIT: if (complete) state<=ADVANCE;
      ADVANCE: begin
        time_index<=0; dim<=0; dot<=0; weighted<=0; denominator<=0;
        if (component+1<HEAD_DIM) begin component<=component+1; state<=COORDINATES; end
        else if (head+1<NUM_Q_HEADS) begin
          head<=head+1; head_base<=head_base+HEAD_DIM; component<=0; context_pass<=0;
          if (group_head+1==RATIO) begin
            group_head<=0; kv_base<=kv_base+HEAD_DIM;
          end else group_head<=group_head+1;
          max_score<={1'b1,95'd0}; state<=COORDINATES;
        end else state<=FINISH;
      end
      INVALID_COMMAND: state<=FINISH;
      FINISH: state<=IDLE;
      default: begin failed<=1; state<=FINISH; end
    endcase
  end
endmodule
