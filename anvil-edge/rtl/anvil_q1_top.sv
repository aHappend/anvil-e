module anvil_q1_top #(
  parameter NUM_LAYERS=24, HIDDEN_SIZE=896, INTERMEDIATE_SIZE=4864,
  NUM_Q_HEADS=14, NUM_KV_HEADS=2, HEAD_DIM=64, GROUP_SIZE=128,
  AWQ_BITS=4, VOCAB_SIZE=151936, MAX_SEQ_LEN=32768
) (
  input wire clk, rst_n,
  input wire token_valid,
  output wire token_ready,
  input wire [31:0] token_id, token_pos,
  input wire new_sequence,
  output wire logit_valid,
  input wire logit_ready,
  output wire [31:0] logit_index,
  output wire signed [31:0] logit_data,
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
  localparam [4:0] IDLE=0, EMBEDDING_READ=1, EMBEDDING_WAIT=2,
    EMBEDDING_CONVERT=3, EMBEDDING_WRITE=4, EMBEDDING_WRITE_WAIT=5,
    LAYER=6, LAYER_WAIT=7, FINAL_NORM=8, FINAL_NORM_WAIT=9,
    READ_ACTIVATION=10, WAIT_ACTIVATION=11, READ_WEIGHT=12, WAIT_WEIGHT=13,
    CONVERT_WEIGHT=14, MULTIPLY=15, MULTIPLY_WAIT=16,
    ACCUMULATE=17, NEXT_COMPONENT=18, ROUND=19, LOGIT=20,
    INVALID_COMMAND=21, FINISH=22, REUSE_ACTIVATION=23;
  reg [4:0] state;
  reg failed, sequence_valid;
  reg [31:0] token, position, next_position, component, vocabulary, layer;
  reg [15:0] tensor_f16;
  reg signed [31:0] activation, weight_value, result;
  reg signed [63:0] logit_product;
  reg signed [95:0] logit_sum;
  reg activation_reuse_valid;
  (* ramstyle = "M20K", nomem2reg *)
  reg [31:0] head_activations [0:HIDDEN_SIZE-1];
  reg [31:0] head_activation_q;
  wire multiply_ready, multiply_valid;
  wire signed [63:0] product;
  wire [1:0] ready, finished, faults;
  wire [2:0] reqv, reqr, reqw, rspv, rspr, rspe;
  wire [11:0] reqk;
  wire [8:0] reqp;
  wire [95:0] reql, reqrow, reqcol, reqwd, rsprd;
  wire [31:0] selected=(state==LAYER || state==LAYER_WAIT) ? 1 :
    ((state==FINAL_NORM || state==FINAL_NORM_WAIT) ? 2 : 0);
  wire port_idle, complete, fault;
  wire [31:0] read_data;
  reg issue, write_request;
  reg [3:0] kind;
  reg [31:0] row, col, write_data;
  anvil_edge_parameters #(
    NUM_LAYERS,HIDDEN_SIZE,INTERMEDIATE_SIZE,NUM_Q_HEADS,NUM_KV_HEADS,
    HEAD_DIM,GROUP_SIZE,AWQ_BITS,VOCAB_SIZE,MAX_SEQ_LEN
  ) parameters_ok();
  anvil_q1_mem_port memory_port(
    .clk(clk),.rst_n(rst_n),.issue(issue),.write(write_request),.kind(kind),
    .layer(32'd0),.proj(3'd0),.row(row),.col(col),.wdata(write_data),
    .idle(port_idle),.complete(complete),.rdata(read_data),.fault(fault),
    .mem_req_valid(reqv[0]),.mem_req_ready(reqr[0]),.mem_req_write(reqw[0]),
    .mem_req_kind(reqk[0+:4]),.mem_req_layer(reql[0+:32]),.mem_req_proj(reqp[0+:3]),
    .mem_req_row(reqrow[0+:32]),.mem_req_col(reqcol[0+:32]),.mem_req_wdata(reqwd[0+:32]),
    .mem_rsp_valid(rspv[0]),.mem_rsp_ready(rspr[0]),.mem_rsp_rdata(rsprd[0+:32]),
    .mem_rsp_error(rspe[0])
  );
  anvil_q1_decoder_layer #(
    NUM_LAYERS,HIDDEN_SIZE,INTERMEDIATE_SIZE,NUM_Q_HEADS,NUM_KV_HEADS,
    HEAD_DIM,GROUP_SIZE,AWQ_BITS,MAX_SEQ_LEN
  ) decoder(
    clk,rst_n,state==LAYER,ready[0],layer,position,finished[0],faults[0],
    reqv[1],reqr[1],reqw[1],reqk[4+:4],reql[32+:32],reqp[3+:3],
    reqrow[32+:32],reqcol[32+:32],reqwd[32+:32],rspv[1],rspr[1],rsprd[32+:32],rspe[1]
  );
  anvil_q1_rmsnorm #(NUM_LAYERS,HIDDEN_SIZE,MAX_SEQ_LEN) final_norm(
    clk,rst_n,state==FINAL_NORM,ready[1],32'd0,position,2'd2,finished[1],faults[1],
    reqv[2],reqr[2],reqw[2],reqk[8+:4],reql[64+:32],reqp[6+:3],
    reqrow[64+:32],reqcol[64+:32],reqwd[64+:32],rspv[2],rspr[2],rsprd[64+:32],rspe[2]
  );
  anvil_q1_bus_mux #(3) bus(
    rst_n,selected,reqv,reqr,reqw,reqk,reql,reqp,reqrow,reqcol,reqwd,
    rspv,rspr,rsprd,rspe,mem_req_valid,mem_req_ready,mem_req_write,mem_req_kind,
    mem_req_layer,mem_req_proj,mem_req_row,mem_req_col,mem_req_wdata,
    mem_rsp_valid,mem_rsp_ready,mem_rsp_rdata,mem_rsp_error
  );
  anvil_edge_signed_multiplier #(.WIDTH(32)) output_multiplier(
    .clk(clk),.rst_n(rst_n),.in_valid(state==MULTIPLY),.in_ready(multiply_ready),
    .operand_a(activation),.operand_b(weight_value),.out_valid(multiply_valid),
    .out_ready(state==MULTIPLY_WAIT),.product(product)
  );
  assign token_ready=rst_n && state==IDLE;
  assign logit_valid=rst_n && state==LOGIT;
  assign logit_index=rst_n ? vocabulary : 0;
  assign logit_data=rst_n ? result : 0;
  assign done=rst_n && state==FINISH;
  assign error=done && failed;
  always @* begin
    issue=0; write_request=0; kind=0; row=0; col=0; write_data=0;
    if (rst_n && port_idle) case (state)
      EMBEDDING_READ: begin issue=1; kind=0; row=token; col=component; end
      EMBEDDING_WRITE: begin issue=1; write_request=1; kind=8; col=component; write_data=activation; end
      READ_ACTIVATION: if (!activation_reuse_valid) begin
        issue=1; kind=8; row=14; col=component;
      end
      READ_WEIGHT: begin issue=1; kind=0; row=vocabulary; col=component; end
      default: begin end
    endcase
  end
  always @(posedge clk) begin
    if (rst_n && !fault) begin
      if (state==WAIT_ACTIVATION && complete)
        head_activations[component]<=read_data;
      if (state==READ_ACTIVATION && activation_reuse_valid)
        head_activation_q<=head_activations[component];
    end
  end
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state<=IDLE; failed<=0; sequence_valid<=1; token<=0; position<=0;
      next_position<=0; component<=0; vocabulary<=0; layer<=0; tensor_f16<=0;
      activation<=0; weight_value<=0; result<=0; logit_product<=0; logit_sum<=0;
      activation_reuse_valid<=0;
    end else if (fault) begin
      failed<=1; sequence_valid<=0; activation_reuse_valid<=0; state<=FINISH;
    end
    else case (state)
      IDLE: if (token_valid && token_ready) begin
        failed<=0;
        activation_reuse_valid<=0;
        if (token_id>=VOCAB_SIZE || token_pos>=MAX_SEQ_LEN ||
            (new_sequence && token_pos!=0) ||
            (!new_sequence && (!sequence_valid || token_pos!=next_position))) begin
          failed<=1; state<=INVALID_COMMAND;
        end else begin
          token<=token_id; position<=token_pos; component<=0; vocabulary<=0;
          layer<=0; logit_sum<=0; state<=EMBEDDING_READ;
        end
      end
      EMBEDDING_READ: if (issue) state<=EMBEDDING_WAIT;
      EMBEDDING_WAIT: if (complete) begin
        if (anvil_edge_numeric_pkg::f16_invalid(read_data[15:0])) begin
          failed<=1; sequence_valid<=0; activation_reuse_valid<=0; state<=FINISH;
        end else begin tensor_f16<=read_data[15:0]; state<=EMBEDDING_CONVERT; end
      end
      EMBEDDING_CONVERT: begin activation<=anvil_edge_numeric_pkg::f16_q16(tensor_f16); state<=EMBEDDING_WRITE; end
      EMBEDDING_WRITE: if (issue) state<=EMBEDDING_WRITE_WAIT;
      EMBEDDING_WRITE_WAIT: if (complete) begin
        if (component+1<HIDDEN_SIZE) begin component<=component+1; state<=EMBEDDING_READ; end
        else state<=LAYER;
      end
      LAYER: if (ready[0]) state<=LAYER_WAIT;
      LAYER_WAIT: if (finished[0]) begin
        if (faults[0]) begin
          failed<=1; sequence_valid<=0; activation_reuse_valid<=0; state<=FINISH;
        end
        else if (layer+1<NUM_LAYERS) begin layer<=layer+1; state<=LAYER; end
        else state<=FINAL_NORM;
      end
      FINAL_NORM: if (ready[1]) state<=FINAL_NORM_WAIT;
      FINAL_NORM_WAIT: if (finished[1]) begin
        if (faults[1]) begin
          failed<=1; sequence_valid<=0; activation_reuse_valid<=0; state<=FINISH;
        end
        else begin component<=0; vocabulary<=0; logit_sum<=0; state<=READ_ACTIVATION; end
      end
      READ_ACTIVATION: begin
        if (activation_reuse_valid) state<=REUSE_ACTIVATION;
        else if (issue) state<=WAIT_ACTIVATION;
      end
      WAIT_ACTIVATION: if (complete) begin
        activation<=read_data;
        if (component==HIDDEN_SIZE-1) activation_reuse_valid<=1;
        state<=READ_WEIGHT;
      end
      REUSE_ACTIVATION: begin activation<=head_activation_q; state<=READ_WEIGHT; end
      READ_WEIGHT: if (issue) state<=WAIT_WEIGHT;
      WAIT_WEIGHT: if (complete) begin
        if (anvil_edge_numeric_pkg::f16_invalid(read_data[15:0])) begin
          failed<=1; sequence_valid<=0; activation_reuse_valid<=0; state<=FINISH;
        end else begin tensor_f16<=read_data[15:0]; state<=CONVERT_WEIGHT; end
      end
      CONVERT_WEIGHT: begin weight_value<=anvil_edge_numeric_pkg::f16_q16(tensor_f16); state<=MULTIPLY; end
      MULTIPLY: if (multiply_ready) state<=MULTIPLY_WAIT;
      MULTIPLY_WAIT: if (multiply_valid) begin logit_product<=product; state<=ACCUMULATE; end
      ACCUMULATE: begin logit_sum<=logit_sum+{{32{logit_product[63]}},logit_product}; state<=NEXT_COMPONENT; end
      NEXT_COMPONENT: begin
        if (component+1<HIDDEN_SIZE) begin component<=component+1; state<=READ_ACTIVATION; end
        else state<=ROUND;
      end
      ROUND: begin
        result<=anvil_edge_numeric_pkg::sat32(anvil_edge_numeric_pkg::round_shift(
          {{32{logit_sum[95]}},logit_sum},16));
        state<=LOGIT;
      end
      LOGIT: if (logit_valid && logit_ready) begin
        if (vocabulary+1<VOCAB_SIZE) begin
          vocabulary<=vocabulary+1; component<=0; logit_sum<=0; state<=READ_ACTIVATION;
        end else begin next_position<=position+1; sequence_valid<=1; state<=FINISH; end
      end
      INVALID_COMMAND: state<=FINISH;
      FINISH: begin activation_reuse_valid<=0; state<=IDLE; end
      default: begin
        failed<=1; sequence_valid<=0; activation_reuse_valid<=0; state<=FINISH;
      end
    endcase
  end
endmodule
