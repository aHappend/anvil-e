module anvil_edge_boot_segment_reader #(
  parameter [63:0] DDR_BASE=0,
  parameter [63:0] DDR_BYTES=64'h0000000100000000
) (
  input wire clk, rst_n,
  input wire in_valid,
  output wire in_ready,
  input wire [63:0] segment_base, segment_bytes, byte_offset,
  input wire [5:0] word_count,
  output wire out_valid,
  input wire out_ready,
  output wire [1023:0] data,
  output wire response_error,
  output wire [7:0] error_code,
  output wire ddr_req_valid,
  input wire ddr_req_ready,
  output wire [63:0] ddr_req_addr,
  input wire ddr_rsp_valid,
  output wire ddr_rsp_ready,
  input wire [31:0] ddr_rsp_rdata,
  input wire ddr_rsp_error
);
  localparam [64:0] DDR_END={1'b0,DDR_BASE}+{1'b0,DDR_BYTES};
  generate if (DDR_BYTES==0 || DDR_BASE[1:0]!=0 ||
               DDR_BYTES[1:0]!=0 || DDR_END[64]) begin : invalid_parameters
    initial $fatal(1, "ANVIL_EDGE_BOOT_READER PARAMETER ERROR: invalid DDR window");
    assign in_ready=0; assign out_valid=0; assign data=0;
    assign response_error=0; assign error_code=0;
    assign ddr_req_valid=0; assign ddr_req_addr=0; assign ddr_rsp_ready=0;
  end else begin : reader
    localparam [3:0] IDLE=0, EXTENTS=1, CHECK=2, REQUEST=3,
      RESPONSE=4, CONSUME=5, RETURN=6;
    reg [3:0] state;
    reg [63:0] base, length, offset_value;
    reg [5:0] count, word_index;
    reg [64:0] segment_end, offset_end, physical_address;
    reg [1023:0] result;
    reg [31:0] read_data;
    reg failed;
    reg [7:0] code;

    assign in_ready=rst_n && state==IDLE;
    assign out_valid=rst_n && state==RETURN;
    assign data=out_valid && !failed ? result : 0;
    assign response_error=out_valid && failed;
    assign error_code=out_valid ? code : 0;
    assign ddr_req_valid=rst_n && state==REQUEST;
    assign ddr_req_addr=rst_n ? physical_address[63:0] : 0;
    assign ddr_rsp_ready=rst_n && state==RESPONSE;

    always @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
        state<=IDLE; base<=0; length<=0; offset_value<=0;
        count<=0; word_index<=0; segment_end<=0; offset_end<=0;
        physical_address<=0; result<=0; read_data<=0; failed<=0; code<=0;
      end else case (state)
        IDLE: if (in_valid && in_ready) begin
          base<=segment_base; length<=segment_bytes; offset_value<=byte_offset;
          count<=word_count; word_index<=0; result<=0; failed<=0; code<=0;
          state<=EXTENTS;
        end
        EXTENTS: begin
          segment_end<={1'b0,base}+{1'b0,length};
          offset_end<={1'b0,offset_value}+({59'd0,count} << 2);
          physical_address<={1'b0,base}+{1'b0,offset_value};
          state<=CHECK;
        end
        CHECK: begin
          if (base[1:0]!=0 || offset_value[1:0]!=0 || count==0 || count>32 ||
              length==0 || segment_end[64] || offset_end[64] ||
              physical_address[64] || base<DDR_BASE || segment_end>DDR_END ||
              offset_end>{1'b0,length}) begin
            failed<=1; code<=8'h06; state<=RETURN;
          end else state<=REQUEST;
        end
        REQUEST: if (ddr_req_valid && ddr_req_ready) state<=RESPONSE;
        RESPONSE: if (ddr_rsp_valid && ddr_rsp_ready) begin
          if (ddr_rsp_error) begin failed<=1; code<=8'h04; state<=RETURN; end
          else begin read_data<=ddr_rsp_rdata; state<=CONSUME; end
        end
        CONSUME: begin
          result[word_index*32+:32]<=read_data;
          if (word_index+1==count) state<=RETURN;
          else begin
            word_index<=word_index+1'b1;
            physical_address<=physical_address+65'd4;
            state<=REQUEST;
          end
        end
        RETURN: if (out_valid && out_ready) state<=IDLE;
        default: begin failed<=1; code<=8'h06; state<=RETURN; end
      endcase
    end
  end endgenerate
endmodule
