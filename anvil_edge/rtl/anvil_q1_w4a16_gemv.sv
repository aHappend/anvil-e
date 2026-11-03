module anvil_q1_w4a16_gemv #(
  parameter NUM_LAYERS=24, HIDDEN_SIZE=896, INTERMEDIATE_SIZE=4864,
  NUM_Q_HEADS=14, NUM_KV_HEADS=2, HEAD_DIM=64, GROUP_SIZE=128,
  AWQ_BITS=4, MAX_SEQ_LEN=32768
) (
  input wire clk, rst_n, cmd_valid,
  output wire cmd_ready,
  input wire [31:0] cmd_layer, cmd_pos,
  input wire [2:0] cmd_proj,
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
  localparam [4:0] IDLE=0, TILE=1, READ_ZERO=2, WAIT_ZERO=3,
    READ_SCALE=4, WAIT_SCALE=5, READ_X=6, WAIT_X=7,
    READ_WEIGHT=8, WAIT_WEIGHT=9, DEQUANT=10,
    DEQUANT_MULTIPLY=11, DEQUANT_WAIT=12,
    PRODUCT_MULTIPLY=13, PRODUCT_WAIT=14, ACCUMULATE=15, NEXT_INPUT=16,
    READ_BIAS=17, WAIT_BIAS=18, ADD_BIAS=19, ROUND=20,
    WRITE=21, WRITE_WAIT=22, FINISH=23, INVALID_COMMAND=24;
  reg [4:0] state;
  reg failed;
  reg [31:0] layer, k, c, inputs, outputs, source_slot, target_slot;
  reg [31:0] group_index, group_offset;
  reg [2:0] projection, lane;
  reg [31:0] qw, qz;
  reg [15:0] scales [0:7];
  reg signed [127:0] accumulators [0:7];
  reg signed [31:0] activation, bias_value, output_value;
  reg signed [4:0] delta;
  reg [31:0] scale_integer;
  reg signed [36:0] dequantized_weight;
  reg signed [68:0] product_value;
  integer i;
  reg [4:0] lane_shift;
  wire [3:0] weight_nibble=qw >> lane_shift;
  wire [3:0] zero_nibble=qz >> lane_shift;
  wire multiply_ready, multiply_valid;
  wire signed [127:0] product;
  reg signed [63:0] operand_a, operand_b;
  wire port_idle, complete, fault;
  wire [31:0] read_data;
  reg issue, write_request;
  reg [3:0] kind;
  reg [31:0] row, col, write_data, memory_layer;
  reg [2:0] memory_projection;
  anvil_edge_parameters #(
    NUM_LAYERS,HIDDEN_SIZE,INTERMEDIATE_SIZE,NUM_Q_HEADS,NUM_KV_HEADS,
    HEAD_DIM,GROUP_SIZE,AWQ_BITS,1,MAX_SEQ_LEN
  ) parameters_ok();
  anvil_q1_mem_port memory_port(
    .clk(clk),.rst_n(rst_n),.issue(issue),.write(write_request),.kind(kind),
    .layer(memory_layer),.proj(memory_projection),.row(row),.col(col),.wdata(write_data),
    .idle(port_idle),.complete(complete),.rdata(read_data),.fault(fault),
    .mem_req_valid(mem_req_valid),.mem_req_ready(mem_req_ready),
    .mem_req_write(mem_req_write),.mem_req_kind(mem_req_kind),
    .mem_req_layer(mem_req_layer),.mem_req_proj(mem_req_proj),
    .mem_req_row(mem_req_row),.mem_req_col(mem_req_col),.mem_req_wdata(mem_req_wdata),
    .mem_rsp_valid(mem_rsp_valid),.mem_rsp_ready(mem_rsp_ready),
    .mem_rsp_rdata(mem_rsp_rdata),.mem_rsp_error(mem_rsp_error)
  );
  anvil_edge_signed_multiplier #(.WIDTH(64)) multiplier(
    .clk(clk),.rst_n(rst_n),
    .in_valid(state==DEQUANT_MULTIPLY || state==PRODUCT_MULTIPLY),
    .in_ready(multiply_ready),.operand_a(operand_a),.operand_b(operand_b),
    .out_valid(multiply_valid),.out_ready(state==DEQUANT_WAIT || state==PRODUCT_WAIT),
    .product(product)
  );
  assign cmd_ready=rst_n && state==IDLE;
  assign done=rst_n && state==FINISH;
  assign error=done && failed;
  always @* begin
    case (lane)
      0: lane_shift=0;
      1: lane_shift=16;
      2: lane_shift=4;
      3: lane_shift=20;
      4: lane_shift=8;
      5: lane_shift=24;
      6: lane_shift=12;
      default: lane_shift=28;
    endcase
  end
  always @* begin
    operand_a=0; operand_b=0;
    if (rst_n) begin
      if (state==DEQUANT_MULTIPLY) begin
        operand_a={{59{delta[4]}},delta};
        operand_b={32'd0,scale_integer};
      end else if (state==PRODUCT_MULTIPLY) begin
        operand_a={{32{activation[31]}},activation};
        operand_b={{27{dequantized_weight[36]}},dequantized_weight};
      end
    end
  end
  always @* begin
    issue=0; write_request=0; kind=0; row=0; col=0; write_data=0;
    memory_layer=0; memory_projection=0;
    if (rst_n && port_idle) case (state)
      READ_ZERO: begin
        issue=1; kind=2; memory_layer=layer; memory_projection=projection;
        row=group_index; col=c >> 3;
      end
      READ_SCALE: begin
        issue=1; kind=3; memory_layer=layer; memory_projection=projection;
        row=group_index; col=c+{29'd0,lane};
      end
      READ_X: begin issue=1; kind=8; row=source_slot; col=k; end
      READ_WEIGHT: begin
        issue=1; kind=1; memory_layer=layer; memory_projection=projection;
        row=k; col=c >> 3;
      end
      READ_BIAS: begin
        issue=1; kind=4; memory_layer=layer; memory_projection=projection;
        col=c+{29'd0,lane};
      end
      WRITE: begin
        issue=1; write_request=1; kind=8; row=target_slot;
        col=c+{29'd0,lane}; write_data=output_value;
      end
      default: begin end
    endcase
  end
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state<=IDLE; failed<=0; layer<=0; k<=0; c<=0; inputs<=0; outputs<=0;
      source_slot<=0; target_slot<=0; group_index<=0; group_offset<=0;
      projection<=0; lane<=0; qw<=0; qz<=0; activation<=0;
      bias_value<=0; output_value<=0; delta<=0; scale_integer<=0;
      dequantized_weight<=0; product_value<=0;
      for (i=0;i<8;i=i+1) begin scales[i]<=0; accumulators[i]<=0; end
    end else if (fault) begin failed<=1; state<=FINISH; end
    else case (state)
      IDLE: if (cmd_valid && cmd_ready) begin
        failed<=0; layer<=cmd_layer; projection<=cmd_proj; c<=0;
        if (cmd_layer>=NUM_LAYERS || cmd_pos>=MAX_SEQ_LEN || cmd_proj>6) begin
          failed<=1; state<=INVALID_COMMAND;
        end else begin
          inputs<=cmd_proj==6 ? INTERMEDIATE_SIZE : HIDDEN_SIZE;
          case (cmd_proj)
            0: begin outputs<=HIDDEN_SIZE; source_slot<=1; target_slot<=2; end
            1: begin outputs<=NUM_KV_HEADS*HEAD_DIM; source_slot<=1; target_slot<=3; end
            2: begin outputs<=NUM_KV_HEADS*HEAD_DIM; source_slot<=1; target_slot<=4; end
            3: begin outputs<=HIDDEN_SIZE; source_slot<=5; target_slot<=6; end
            4: begin outputs<=INTERMEDIATE_SIZE; source_slot<=8; target_slot<=9; end
            5: begin outputs<=INTERMEDIATE_SIZE; source_slot<=8; target_slot<=10; end
            default: begin outputs<=HIDDEN_SIZE; source_slot<=11; target_slot<=12; end
          endcase
          state<=TILE;
        end
      end
      TILE: begin
        k<=0; lane<=0; group_index<=0; group_offset<=0;
        qw<=0; qz<=0; activation<=0;
        for (i=0;i<8;i=i+1) begin scales[i]<=0; accumulators[i]<=0; end
        state<=READ_ZERO;
      end
      READ_ZERO: if (issue) state<=WAIT_ZERO;
      WAIT_ZERO: if (complete) begin qz<=read_data; lane<=0; state<=READ_SCALE; end
      READ_SCALE: if (issue) state<=WAIT_SCALE;
      WAIT_SCALE: if (complete) begin
        if (anvil_edge_numeric_pkg::f16_invalid(read_data[15:0]) ||
            (read_data[15] && read_data[14:0]!=0)) begin failed<=1; state<=FINISH; end
        else begin
          scales[lane]<=read_data[15:0];
          if (lane==7) begin lane<=0; state<=READ_X; end
          else begin lane<=lane+1'b1; state<=READ_SCALE; end
        end
      end
      READ_X: if (issue) state<=WAIT_X;
      WAIT_X: if (complete) begin activation<=read_data; state<=READ_WEIGHT; end
      READ_WEIGHT: if (issue) state<=WAIT_WEIGHT;
      WAIT_WEIGHT: if (complete) begin qw<=read_data; lane<=0; state<=DEQUANT; end
      DEQUANT: begin
        delta<=$signed({1'b0,weight_nibble})-$signed({1'b0,zero_nibble});
        scale_integer<=anvil_edge_numeric_pkg::f16_scale(scales[lane]);
        state<=DEQUANT_MULTIPLY;
      end
      DEQUANT_MULTIPLY: if (multiply_ready) state<=DEQUANT_WAIT;
      DEQUANT_WAIT: if (multiply_valid) begin
        dequantized_weight<=product[36:0]; state<=PRODUCT_MULTIPLY;
      end
      PRODUCT_MULTIPLY: if (multiply_ready) state<=PRODUCT_WAIT;
      PRODUCT_WAIT: if (multiply_valid) begin product_value<=product[68:0]; state<=ACCUMULATE; end
      ACCUMULATE: begin
        accumulators[lane]<=accumulators[lane]+{{59{product_value[68]}},product_value};
        if (lane==7) begin lane<=0; state<=NEXT_INPUT; end
        else begin lane<=lane+1'b1; state<=DEQUANT; end
      end
      NEXT_INPUT: begin
        if (k+1<inputs) begin
          k<=k+1;
          if (group_offset+1==GROUP_SIZE) begin
            group_offset<=0; group_index<=group_index+1; state<=READ_ZERO;
          end else begin group_offset<=group_offset+1; state<=READ_X; end
        end else if (projection<3) state<=READ_BIAS;
        else state<=ROUND;
      end
      READ_BIAS: if (issue) state<=WAIT_BIAS;
      WAIT_BIAS: if (complete) begin
        if (anvil_edge_numeric_pkg::f16_invalid(read_data[15:0])) begin
          failed<=1; state<=FINISH;
        end else begin
          bias_value<=anvil_edge_numeric_pkg::f16_q16(read_data[15:0]); state<=ADD_BIAS;
        end
      end
      ADD_BIAS: begin
        accumulators[lane]<=accumulators[lane]+
          ($signed({{96{bias_value[31]}},bias_value}) <<< 16);
        if (lane==7) begin lane<=0; state<=ROUND; end
        else begin lane<=lane+1'b1; state<=READ_BIAS; end
      end
      ROUND: begin
        output_value<=anvil_edge_numeric_pkg::sat32(
          anvil_edge_numeric_pkg::round_shift(accumulators[lane],16));
        state<=WRITE;
      end
      WRITE: if (issue) state<=WRITE_WAIT;
      WRITE_WAIT: if (complete) begin
        if (lane<7) begin lane<=lane+1'b1; state<=ROUND; end
        else if (c+8<outputs) begin c<=c+8; state<=TILE; end
        else state<=FINISH;
      end
      INVALID_COMMAND: state<=FINISH;
      FINISH: begin
        qw<=0; qz<=0; activation<=0; lane<=0;
        for (i=0;i<8;i=i+1) begin scales[i]<=0; accumulators[i]<=0; end
        state<=IDLE;
      end
      default: begin failed<=1; state<=FINISH; end
    endcase
  end
endmodule
