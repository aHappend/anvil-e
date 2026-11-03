module anvil_q1_rope #(
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
  localparam [4:0] IDLE=0, COORDINATE_X=1, COORDINATE_Y=2,
    READ_X=3, WAIT_X=4, READ_Y=5, WAIT_Y=6,
    READ_COS=7, WAIT_COS=8, READ_SIN=9, WAIT_SIN=10,
    MULTIPLY=11, MULTIPLY_WAIT=12, ROTATE=13, ROUND=14,
    WRITE_X=15, WRITE_X_WAIT=16, WRITE_Y=17, WRITE_Y_WAIT=18,
    ADVANCE=19, FINISH=20, INVALID_COMMAND=21;
  reg [4:0] state;
  reg failed, key_vector;
  reg [31:0] position, head, head_base, pair_index, coordinate_x, coordinate_y;
  reg signed [31:0] x, y, cosine, sine, output_x, output_y;
  reg [1:0] product_index;
  reg signed [63:0] x_cos, y_sin, y_cos, x_sin;
  reg signed [64:0] rotated_x, rotated_y;
  reg signed [31:0] operand_a, operand_b;
  wire multiply_ready, multiply_valid;
  wire signed [63:0] product;
  wire port_idle, complete, fault;
  wire [31:0] read_data;
  reg issue, write_request;
  reg [3:0] kind;
  reg [31:0] row, col, write_data;
  anvil_edge_parameters #(
    NUM_LAYERS,HIDDEN_SIZE,HIDDEN_SIZE,NUM_Q_HEADS,NUM_KV_HEADS,
    HEAD_DIM,1,4,1,MAX_SEQ_LEN
  ) parameters_ok();
  anvil_q1_mem_port memory_port(
    .clk(clk),.rst_n(rst_n),.issue(issue),.write(write_request),.kind(kind),
    .layer(32'd0),.proj(3'd0),.row(row),.col(col),.wdata(write_data),
    .idle(port_idle),.complete(complete),.rdata(read_data),.fault(fault),
    .mem_req_valid(mem_req_valid),.mem_req_ready(mem_req_ready),
    .mem_req_write(mem_req_write),.mem_req_kind(mem_req_kind),
    .mem_req_layer(mem_req_layer),.mem_req_proj(mem_req_proj),
    .mem_req_row(mem_req_row),.mem_req_col(mem_req_col),.mem_req_wdata(mem_req_wdata),
    .mem_rsp_valid(mem_rsp_valid),.mem_rsp_ready(mem_rsp_ready),
    .mem_rsp_rdata(mem_rsp_rdata),.mem_rsp_error(mem_rsp_error)
  );
  anvil_edge_signed_multiplier #(.WIDTH(32)) multiplier(
    .clk(clk),.rst_n(rst_n),.in_valid(state==MULTIPLY),.in_ready(multiply_ready),
    .operand_a(operand_a),.operand_b(operand_b),.out_valid(multiply_valid),
    .out_ready(state==MULTIPLY_WAIT),.product(product)
  );
  assign cmd_ready=rst_n && state==IDLE;
  assign done=rst_n && state==FINISH;
  assign error=done && failed;
  always @* begin
    operand_a=0; operand_b=0;
    if (rst_n) case (product_index)
      0: begin operand_a=x; operand_b=cosine; end
      1: begin operand_a=y; operand_b=sine; end
      2: begin operand_a=y; operand_b=cosine; end
      3: begin operand_a=x; operand_b=sine; end
    endcase
  end
  always @* begin
    issue=0; write_request=0; kind=0; row=0; col=0; write_data=0;
    if (rst_n && port_idle) case (state)
      READ_X,READ_Y,WRITE_X,WRITE_Y: begin
        issue=1; kind=8; row=key_vector ? 3 : 2;
        col=(state==READ_Y || state==WRITE_Y) ? coordinate_y : coordinate_x;
        write_request=state==WRITE_X || state==WRITE_Y;
        write_data=state==WRITE_Y ? output_y : output_x;
      end
      READ_COS,READ_SIN: begin
        issue=1; kind=11; row=position;
        col=(pair_index << 1)+(state==READ_SIN ? 32'd1 : 32'd0);
      end
      default: begin end
    endcase
  end
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state<=IDLE; failed<=0; key_vector<=0; position<=0; head<=0;
      head_base<=0; pair_index<=0; coordinate_x<=0; coordinate_y<=0;
      x<=0; y<=0; cosine<=0; sine<=0; output_x<=0; output_y<=0; product_index<=0;
      x_cos<=0; y_sin<=0; y_cos<=0; x_sin<=0; rotated_x<=0; rotated_y<=0;
    end else if (fault) begin failed<=1; state<=FINISH; end
    else case (state)
      IDLE: if (cmd_valid && cmd_ready) begin
        failed<=0; position<=cmd_pos; head<=0; head_base<=0; pair_index<=0; key_vector<=0;
        if (cmd_layer>=NUM_LAYERS || cmd_pos>=MAX_SEQ_LEN) begin
          failed<=1; state<=INVALID_COMMAND;
        end else state<=COORDINATE_X;
      end
      COORDINATE_X: begin coordinate_x<=head_base+pair_index; state<=COORDINATE_Y; end
      COORDINATE_Y: begin coordinate_y<=coordinate_x+(HEAD_DIM >> 1); state<=READ_X; end
      READ_X: if (issue) state<=WAIT_X;
      WAIT_X: if (complete) begin x<=read_data; state<=READ_Y; end
      READ_Y: if (issue) state<=WAIT_Y;
      WAIT_Y: if (complete) begin y<=read_data; state<=READ_COS; end
      READ_COS: if (issue) state<=WAIT_COS;
      WAIT_COS: if (complete) begin cosine<=read_data; state<=READ_SIN; end
      READ_SIN: if (issue) state<=WAIT_SIN;
      WAIT_SIN: if (complete) begin sine<=read_data; product_index<=0; state<=MULTIPLY; end
      MULTIPLY: if (multiply_ready) state<=MULTIPLY_WAIT;
      MULTIPLY_WAIT: if (multiply_valid) begin
        case (product_index)
          0: x_cos<=product;
          1: y_sin<=product;
          2: y_cos<=product;
          3: x_sin<=product;
        endcase
        if (product_index==3) state<=ROTATE;
        else begin product_index<=product_index+1'b1; state<=MULTIPLY; end
      end
      ROTATE: begin
        rotated_x<=$signed({x_cos[63],x_cos})-$signed({y_sin[63],y_sin});
        rotated_y<=$signed({y_cos[63],y_cos})+$signed({x_sin[63],x_sin});
        state<=ROUND;
      end
      ROUND: begin
        output_x<=anvil_edge_numeric_pkg::sat32(anvil_edge_numeric_pkg::round_shift(
          {{63{rotated_x[64]}},rotated_x},30));
        output_y<=anvil_edge_numeric_pkg::sat32(anvil_edge_numeric_pkg::round_shift(
          {{63{rotated_y[64]}},rotated_y},30));
        state<=WRITE_X;
      end
      WRITE_X: if (issue) state<=WRITE_X_WAIT;
      WRITE_X_WAIT: if (complete) state<=WRITE_Y;
      WRITE_Y: if (issue) state<=WRITE_Y_WAIT;
      WRITE_Y_WAIT: if (complete) state<=ADVANCE;
      ADVANCE: begin
        if (pair_index+1<(HEAD_DIM >> 1)) begin
          pair_index<=pair_index+1; state<=COORDINATE_X;
        end else if (head+1<(key_vector ? NUM_KV_HEADS : NUM_Q_HEADS)) begin
          pair_index<=0; head<=head+1; head_base<=head_base+HEAD_DIM; state<=COORDINATE_X;
        end else if (!key_vector) begin
          key_vector<=1; head<=0; head_base<=0; pair_index<=0; state<=COORDINATE_X;
        end else state<=FINISH;
      end
      INVALID_COMMAND: state<=FINISH;
      FINISH: state<=IDLE;
      default: begin failed<=1; state<=FINISH; end
    endcase
  end
endmodule
