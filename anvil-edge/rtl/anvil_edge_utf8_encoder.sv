module anvil_edge_utf8_encoder (
  input wire clk, rst_n, start,
  input wire in_valid,
  output wire in_ready,
  input wire [31:0] in_scalar,
  input wire in_last,
  output wire out_valid,
  input wire out_ready,
  output wire [7:0] out_data,
  output wire out_last,
  output wire busy, done, error,
  output wire [7:0] error_code
);
  localparam [2:0] IDLE=0, RECEIVE=1, EMIT=2, CLOSED=3, FAILED=4;
  reg [2:0] state, remaining;
  reg [31:0] encoded;
  reg final_scalar, done_r;
  reg [7:0] code;

  assign in_ready=rst_n && state==RECEIVE;
  assign out_valid=rst_n && state==EMIT;
  assign out_data=out_valid ? encoded[7:0] : 0;
  assign out_last=out_valid && final_scalar && remaining==1;
  assign busy=rst_n && state!=IDLE && state!=CLOSED && state!=FAILED;
  assign done=rst_n && done_r;
  assign error=rst_n && state==FAILED;
  assign error_code=rst_n ? code : 0;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state<=IDLE; remaining<=0; encoded<=0;
      final_scalar<=0; done_r<=0; code<=0;
    end else begin
      done_r<=0;
      case (state)
        IDLE, CLOSED: if (start) begin
          remaining<=0; encoded<=0; final_scalar<=0; code<=0; state<=RECEIVE;
        end
        RECEIVE: if (in_valid && in_ready) begin
          if (in_scalar>32'h10ffff ||
              (in_scalar>=32'hd800 && in_scalar<=32'hdfff)) begin
            code<=8'h10; state<=FAILED;
          end else begin
            final_scalar<=in_last;
            state<=EMIT;
            if (in_scalar<32'h80) begin
              encoded<={24'd0,in_scalar[7:0]}; remaining<=1;
            end else if (in_scalar<32'h800) begin
              encoded<={16'd0,2'b10,in_scalar[5:0],3'b110,in_scalar[10:6]};
              remaining<=2;
            end else if (in_scalar<32'h10000) begin
              encoded<={8'd0,2'b10,in_scalar[5:0],2'b10,in_scalar[11:6],
                        4'b1110,in_scalar[15:12]};
              remaining<=3;
            end else begin
              encoded<={2'b10,in_scalar[5:0],2'b10,in_scalar[11:6],
                        2'b10,in_scalar[17:12],5'b11110,in_scalar[20:18]};
              remaining<=4;
            end
          end
        end
        EMIT: if (out_valid && out_ready) begin
          if (remaining==1) begin
            if (final_scalar) begin done_r<=1; state<=CLOSED; end
            else state<=RECEIVE;
          end else begin encoded<=encoded >> 8; remaining<=remaining-1'b1; end
        end
        FAILED: state<=FAILED;
        default: begin code<=8'h10; state<=FAILED; end
      endcase
    end
  end
endmodule
