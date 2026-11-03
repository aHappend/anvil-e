module anvil_q1_swiglu_mlp #(
  parameter NUM_LAYERS=24, HIDDEN_SIZE=896, INTERMEDIATE_SIZE=4864,
  NUM_Q_HEADS=14, NUM_KV_HEADS=2, HEAD_DIM=64, GROUP_SIZE=128,
  AWQ_BITS=4, MAX_SEQ_LEN=32768
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
  reg [3:0] state;
  reg failed;
  reg [31:0] layer, position;
  reg [2:0] projection;
  wire [1:0] ready, finished, faults, reqv, reqr, reqw, rspv, rspr, rspe;
  wire [7:0] reqk;
  wire [5:0] reqp;
  wire [63:0] reql, reqrow, reqcol, reqwd, rsprd;
  wire [31:0] selected=(state==5 || state==6) ? 1 : 0;
  assign cmd_ready=rst_n && state==0;
  assign done=rst_n && state==15;
  assign error=done && failed;
  anvil_q1_w4a16_gemv #(
    NUM_LAYERS,HIDDEN_SIZE,INTERMEDIATE_SIZE,NUM_Q_HEADS,NUM_KV_HEADS,
    HEAD_DIM,GROUP_SIZE,AWQ_BITS,MAX_SEQ_LEN
  ) gemv(
    clk,rst_n,(state==1 || state==3 || state==7),ready[0],layer,position,projection,
    finished[0],faults[0],reqv[0],reqr[0],reqw[0],reqk[0+:4],reql[0+:32],
    reqp[0+:3],reqrow[0+:32],reqcol[0+:32],reqwd[0+:32],
    rspv[0],rspr[0],rsprd[0+:32],rspe[0]
  );
  anvil_q1_elementwise #(NUM_LAYERS,HIDDEN_SIZE,INTERMEDIATE_SIZE,MAX_SEQ_LEN) silu_product(
    clk,rst_n,state==5,ready[1],layer,position,2'd2,finished[1],faults[1],
    reqv[1],reqr[1],reqw[1],reqk[4+:4],reql[32+:32],reqp[3+:3],
    reqrow[32+:32],reqcol[32+:32],reqwd[32+:32],rspv[1],rspr[1],rsprd[32+:32],rspe[1]
  );
  anvil_q1_bus_mux #(2) bus(
    rst_n,selected,reqv,reqr,reqw,reqk,reql,reqp,reqrow,reqcol,reqwd,
    rspv,rspr,rsprd,rspe,mem_req_valid,mem_req_ready,mem_req_write,mem_req_kind,
    mem_req_layer,mem_req_proj,mem_req_row,mem_req_col,mem_req_wdata,
    mem_rsp_valid,mem_rsp_ready,mem_rsp_rdata,mem_rsp_error
  );
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin state<=0; failed<=0; layer<=0; position<=0; projection<=0; end
    else case (state)
      0: if (cmd_valid && cmd_ready) begin
        failed<=0; layer<=cmd_layer; position<=cmd_pos; projection<=4;
        if (cmd_layer>=NUM_LAYERS || cmd_pos>=MAX_SEQ_LEN) begin failed<=1; state<=14; end
        else state<=1;
      end
      1: if (ready[0]) state<=2;
      2: if (finished[0]) begin
        if (faults[0]) begin failed<=1; state<=15; end
        else begin projection<=5; state<=3; end
      end
      3: if (ready[0]) state<=4;
      4: if (finished[0]) begin
        if (faults[0]) begin failed<=1; state<=15; end
        else state<=5;
      end
      5: if (ready[1]) state<=6;
      6: if (finished[1]) begin
        if (faults[1]) begin failed<=1; state<=15; end
        else begin projection<=6; state<=7; end
      end
      7: if (ready[0]) state<=8;
      8: if (finished[0]) begin failed<=faults[0]; state<=15; end
      14: state<=15;
      15: state<=0;
      default: begin failed<=1; state<=15; end
    endcase
  end
endmodule
