module anvil_edge_table_record_reader #(
  parameter integer LOG2_RECORD_BYTES=4
) (
  input wire clk, rst_n,
  input wire in_valid,
  output wire in_ready,
  input wire [63:0] segment_base,
  input wire [31:0] record_count, record_index,
  output wire out_valid,
  input wire out_ready,
  output wire [(8 << ((LOG2_RECORD_BYTES>=2 && LOG2_RECORD_BYTES<=6) ?
                     LOG2_RECORD_BYTES : 2))-1:0] record_data,
  output wire response_error,
  output wire [7:0] response_error_code,
  output wire tbl_req_valid,
  input wire tbl_req_ready,
  output wire [63:0] tbl_req_addr,
  input wire tbl_rsp_valid,
  output wire tbl_rsp_ready,
  input wire [31:0] tbl_rsp_data,
  input wire tbl_rsp_error
);
  generate if (LOG2_RECORD_BYTES<2 || LOG2_RECORD_BYTES>6) begin : invalid_parameters
    initial $fatal(1, "ANVIL_EDGE_RECORD PARAMETER ERROR: log2 record bytes must be 2..6");
    assign in_ready=0; assign out_valid=0; assign record_data=0;
    assign response_error=0; assign response_error_code=0;
    assign tbl_req_valid=0; assign tbl_req_addr=0; assign tbl_rsp_ready=0;
  end else begin : reader
    localparam integer RECORD_WORDS=1 << (LOG2_RECORD_BYTES-2);
    localparam integer WORD_W=RECORD_WORDS>1 ? $clog2(RECORD_WORDS) : 1;
    localparam [3:0] IDLE=0, OFFSET=1, HEADER=2, EXTENT=3, CHECK=4,
      ADDRESS=5, ADDRESS_CHECK=6, REQUEST=7, RESPONSE=8, CONSUME=9,
      RETURN=10;
    reg [3:0] state;
    reg [63:0] base;
    reg [31:0] count, index;
    reg [WORD_W-1:0] word_index;
    reg [65:0] offset_value, data_start, table_end, request_address;
    reg [(8 << LOG2_RECORD_BYTES)-1:0] result_data;
    reg [31:0] read_data;
    reg failed;
    reg [7:0] code;

    assign in_ready=rst_n && state==IDLE;
    assign out_valid=rst_n && state==RETURN;
    assign record_data=out_valid && !failed ? result_data : 0;
    assign response_error=out_valid && failed;
    assign response_error_code=out_valid ? code : 0;
    assign tbl_req_valid=rst_n && state==REQUEST;
    assign tbl_req_addr=rst_n ? request_address[63:0] : 0;
    assign tbl_rsp_ready=rst_n && state==RESPONSE;

    always @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
        state<=IDLE; base<=0; count<=0; index<=0; word_index<=0;
        offset_value<=0; data_start<=0; table_end<=0; request_address<=0;
        result_data<=0; read_data<=0; failed<=0; code<=0;
      end else case (state)
        IDLE: if (in_valid && in_ready) begin
          base<=segment_base; count<=record_count; index<=record_index;
          word_index<=0; result_data<=0; failed<=0; code<=0;
          state<=OFFSET;
        end
        OFFSET: begin
          offset_value<={34'd0,index} << LOG2_RECORD_BYTES;
          state<=HEADER;
        end
        HEADER: begin
          data_start<={2'b0,base}+66'd32;
          state<=EXTENT;
        end
        EXTENT: begin
          table_end<=data_start+({34'd0,count} << LOG2_RECORD_BYTES);
          state<=CHECK;
        end
        CHECK: begin
          if (base[1:0]!=0 || count==0 || index>=count ||
              data_start[65:64]!=0 || table_end[65:64]!=0) begin
            failed<=1; code<=8'h11; state<=RETURN;
          end else state<=ADDRESS;
        end
        ADDRESS: begin
          request_address<=data_start+offset_value;
          state<=ADDRESS_CHECK;
        end
        ADDRESS_CHECK: begin
          if (request_address[65:64]!=0 || request_address>=table_end) begin
            failed<=1; code<=8'h11; state<=RETURN;
          end else state<=REQUEST;
        end
        REQUEST: if (tbl_req_valid && tbl_req_ready) state<=RESPONSE;
        RESPONSE: if (tbl_rsp_valid && tbl_rsp_ready) begin
          if (tbl_rsp_error) begin
            failed<=1; code<=8'h04; state<=RETURN;
          end else begin
            read_data<=tbl_rsp_data;
            state<=CONSUME;
          end
        end
        CONSUME: begin
          result_data[word_index*32+:32]<=read_data;
          if (word_index==RECORD_WORDS-1) state<=RETURN;
          else begin
            word_index<=word_index+1'b1;
            offset_value<=offset_value+66'd4;
            state<=ADDRESS;
          end
        end
        RETURN: if (out_valid && out_ready) state<=IDLE;
        default: begin failed<=1; code<=8'h11; state<=RETURN; end
      endcase
    end
  end endgenerate
endmodule
