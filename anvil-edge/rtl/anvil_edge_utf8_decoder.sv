module anvil_edge_utf8_decoder #(
  parameter integer MAX_BYTES=4096
) (
  input wire clk, rst_n, start,
  input wire in_valid,
  output wire in_ready,
  input wire [7:0] in_data,
  input wire in_last,
  output wire out_valid,
  input wire out_ready,
  output wire [31:0] out_scalar, out_start, out_end,
  output wire out_last,
  output wire busy, done, error,
  output wire [7:0] error_code
);
  generate if (MAX_BYTES<1) begin : invalid_parameters
    initial $fatal(1, "ANVIL_EDGE_UTF8_DECODER PARAMETER ERROR: MAX_BYTES must be positive");
    assign in_ready=0; assign out_valid=0;
    assign out_scalar=0; assign out_start=0; assign out_end=0; assign out_last=0;
    assign busy=0; assign done=0; assign error=0; assign error_code=0;
  end else begin : decoder
    localparam [2:0] IDLE=0, RECEIVE=1, EMIT=2, CLOSED=3, FAILED=4;
    reg [2:0] state, remaining;
    reg [31:0] scalar, minimum_scalar, byte_count, scalar_start, scalar_end;
    reg final_scalar, done_r;
    reg [7:0] code;
    wire [31:0] continued_scalar=(scalar << 6) | {26'd0,in_data[5:0]};
    wire continued_invalid=in_data[7:6]!=2'b10 ||
      (remaining==1 && (continued_scalar<minimum_scalar ||
                       continued_scalar>32'h10ffff ||
                       (continued_scalar>=32'hd800 && continued_scalar<=32'hdfff)));

    assign in_ready=rst_n && state==RECEIVE;
    assign out_valid=rst_n && state==EMIT;
    assign out_scalar=out_valid ? scalar : 0;
    assign out_start=out_valid ? scalar_start : 0;
    assign out_end=out_valid ? scalar_end : 0;
    assign out_last=out_valid && final_scalar;
    assign busy=rst_n && state!=IDLE && state!=CLOSED && state!=FAILED;
    assign done=rst_n && done_r;
    assign error=rst_n && state==FAILED;
    assign error_code=rst_n ? code : 0;

    always @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
        state<=IDLE; remaining<=0; scalar<=0; minimum_scalar<=0;
        byte_count<=0; scalar_start<=0; scalar_end<=0;
        final_scalar<=0; done_r<=0; code<=0;
      end else begin
        done_r<=0;
        case (state)
          IDLE, CLOSED: if (start) begin
            remaining<=0; scalar<=0; minimum_scalar<=0; byte_count<=0;
            scalar_start<=0; scalar_end<=0; final_scalar<=0; code<=0;
            state<=RECEIVE;
          end
          RECEIVE: if (in_valid && in_ready) begin
            if (byte_count>=MAX_BYTES) begin code<=8'h30; state<=FAILED; end
            else begin
              byte_count<=byte_count+1;
              scalar_end<=byte_count+1;
              final_scalar<=in_last;
              if (remaining==0) begin
                scalar_start<=byte_count;
                if (in_data<8'h80) begin
                  scalar<={24'd0,in_data}; state<=EMIT;
                end else if (in_data>=8'hc2 && in_data<=8'hdf) begin
                  scalar<={27'd0,in_data[4:0]}; minimum_scalar<=32'h80;
                  remaining<=1;
                  if (in_last) begin code<=8'h10; state<=FAILED; end
                end else if (in_data>=8'he0 && in_data<=8'hef) begin
                  scalar<={28'd0,in_data[3:0]}; minimum_scalar<=32'h800;
                  remaining<=2;
                  if (in_last) begin code<=8'h10; state<=FAILED; end
                end else if (in_data>=8'hf0 && in_data<=8'hf4) begin
                  scalar<={29'd0,in_data[2:0]}; minimum_scalar<=32'h10000;
                  remaining<=3;
                  if (in_last) begin code<=8'h10; state<=FAILED; end
                end else begin code<=8'h10; state<=FAILED; end
                if (!in_last && byte_count+1==MAX_BYTES &&
                    (in_data<8'h80 || (in_data>=8'hc2 && in_data<=8'hf4))) begin
                  code<=8'h30; state<=FAILED;
                end
              end else if (continued_invalid || (in_last && remaining!=1)) begin
                code<=8'h10; state<=FAILED;
              end else if (!in_last && byte_count+1==MAX_BYTES) begin
                code<=8'h30; state<=FAILED;
              end else begin
                scalar<=continued_scalar; remaining<=remaining-1'b1;
                if (remaining==1) state<=EMIT;
              end
            end
          end
          EMIT: if (out_valid && out_ready) begin
            if (final_scalar) begin done_r<=1; state<=CLOSED; end
            else state<=RECEIVE;
          end
          FAILED: state<=FAILED;
          default: begin code<=8'h10; state<=FAILED; end
        endcase
      end
    end
  end endgenerate
endmodule
