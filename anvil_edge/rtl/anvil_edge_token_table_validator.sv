module anvil_edge_token_table_validator #(
  parameter VOCAB_SIZE=151936,
  parameter [63:0] DDR_BASE=0,
  parameter [63:0] DDR_BYTES=64'h0000000100000000
) (
  input wire clk, rst_n, start, manifest_valid,
  input wire [223:0] staged_config_words,
  input wire [1279:0] staged_segment_bases, staged_segment_bytes,
  input wire [1023:0] staged_metadata,
  input wire [511:0] staged_table_counts,
  output wire busy, done, valid_tokens, error,
  output wire [7:0] error_code,
  output wire ddr_req_valid,
  input wire ddr_req_ready,
  output wire [63:0] ddr_req_addr,
  input wire ddr_rsp_valid,
  output wire ddr_rsp_ready,
  input wire [31:0] ddr_rsp_rdata,
  input wire ddr_rsp_error
);
  localparam [5:0] IDLE=0, CONFIG_CHECK=1, TOKEN_SETUP=2, READ_ISSUE=3,
    READ_WAIT=4, TOKEN_EXTENT=5, TOKEN_CHECK=6, MAP_SETUP=7,
    MAP_ID=8, MAP_TOKEN_SETUP=9, MAP_TOKEN_CHECK=10, RAW_ADDRESS=11,
    RAW_CHECK=12, MAP_BYTE=13, MERGE_SETUP=14, MERGE_CHECK=15,
    PIECE_SETUP=16, PIECE_CHECK=17, MERGE_LENGTH=18, MERGE_LENGTH_CHECK=19,
    SOURCE_BYTE_SETUP=20, SOURCE_BYTE=21, RESULT_BYTE_SETUP=22,
    COMPARE_BYTE=23, COMPLETE=24, FAILED=25;
  reg [5:0] state, after_read, after_raw;
  reg [1279:0] bases, lengths;
  reg [31:0] vocab_size, maximum_length, raw_count, merge_count;
  reg [31:0] token_index, map_index, merge_index;
  reg [127:0] record_data;
  reg [64:0] token_end, merge_length;
  reg [31:0] map_token;
  reg [63:0] previous_pair;
  reg previous_pair_valid;
  reg [31:0] left_id, right_id, result_id;
  reg [1:0] piece_index;
  reg [63:0] piece_offsets [0:2];
  reg [31:0] piece_lengths [0:2];
  reg [31:0] byte_index;
  reg [64:0] raw_offset, raw_address;
  reg [1:0] raw_lane;
  reg [7:0] source_byte;
  reg [4:0] read_segment;
  reg [63:0] read_offset;
  reg [5:0] read_words;
  reg raw_read;
  reg done_r;
  reg [7:0] code;
  wire reader_in_ready, reader_out_valid, reader_error;
  wire [1023:0] reader_data;
  wire [7:0] reader_code;
  wire [63:0] selected_length=lengths[read_segment*64+:64];
  wire [64:0] rounded_length=({1'b0,selected_length}+65'd3) & ~65'd3;
  wire [63:0] read_length=raw_read ? rounded_length[63:0] : selected_length;
  wire [63:0] token_offset=record_data[0+:64];
  wire [31:0] token_length=record_data[64+:32];
  wire [31:0] token_flags=record_data[96+:32];
  wire [31:0] piece_id=piece_index==0 ? left_id :
    (piece_index==1 ? right_id : result_id);
  wire [63:0] pair_key={record_data[0+:32],record_data[32+:32]};
  wire [7:0] raw_byte=record_data[raw_lane*8+:8];
  wire [31:0] source_index=byte_index<piece_lengths[0] ?
    byte_index : byte_index-piece_lengths[0];
  wire [63:0] source_offset=byte_index<piece_lengths[0] ?
    piece_offsets[0] : piece_offsets[1];
  wire [64:0] token_segment_bytes=65'd32+({33'd0,vocab_size} << 4);
  wire [64:0] raw_segment_bytes=65'd32+{33'd0,raw_count};

  generate if (VOCAB_SIZE<1 || VOCAB_SIZE>64'hffffffff) begin : invalid_parameters
    initial $fatal(1, "ANVIL_EDGE_TOKEN_TABLE PARAMETER ERROR: invalid physical vocabulary");
  end endgenerate

  anvil_edge_boot_segment_reader #(.DDR_BASE(DDR_BASE),.DDR_BYTES(DDR_BYTES)) reader(
    .clk(clk),.rst_n(rst_n),.in_valid(rst_n && state==READ_ISSUE),
    .in_ready(reader_in_ready),.segment_base(bases[read_segment*64+:64]),
    .segment_bytes(read_length),.byte_offset(read_offset),.word_count(read_words),
    .out_valid(reader_out_valid),.out_ready(rst_n && state==READ_WAIT),
    .data(reader_data),.response_error(reader_error),.error_code(reader_code),
    .ddr_req_valid(ddr_req_valid),.ddr_req_ready(ddr_req_ready),
    .ddr_req_addr(ddr_req_addr),.ddr_rsp_valid(ddr_rsp_valid),
    .ddr_rsp_ready(ddr_rsp_ready),.ddr_rsp_rdata(ddr_rsp_rdata),
    .ddr_rsp_error(ddr_rsp_error)
  );
  assign busy=rst_n && state!=IDLE && state!=COMPLETE && state!=FAILED;
  assign done=rst_n && done_r;
  assign valid_tokens=rst_n && state==COMPLETE;
  assign error=rst_n && state==FAILED;
  assign error_code=rst_n ? code : 0;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state<=IDLE; after_read<=IDLE; after_raw<=IDLE;
      bases<=0; lengths<=0; vocab_size<=0; maximum_length<=0;
      raw_count<=0; merge_count<=0; token_index<=0; map_index<=0; merge_index<=0;
      record_data<=0; token_end<=0; merge_length<=0; map_token<=0;
      previous_pair<=0; previous_pair_valid<=0;
      left_id<=0; right_id<=0; result_id<=0; piece_index<=0;
      piece_offsets[0]<=0; piece_offsets[1]<=0; piece_offsets[2]<=0;
      piece_lengths[0]<=0; piece_lengths[1]<=0; piece_lengths[2]<=0;
      byte_index<=0; raw_offset<=0; raw_address<=0; raw_lane<=0;
      source_byte<=0; read_segment<=0; read_offset<=0; read_words<=0;
      raw_read<=0; done_r<=0; code<=0;
    end else begin
      done_r<=0;
      case (state)
        IDLE, COMPLETE: if (start) begin
          if (!manifest_valid) begin code<=8'h06; state<=FAILED; end
          else begin
            bases<=staged_segment_bases; lengths<=staged_segment_bytes;
            vocab_size<=staged_config_words[160+:32];
            maximum_length<=staged_metadata[448+:32];
            raw_count<=staged_table_counts[64+:32];
            merge_count<=staged_table_counts[128+:32];
            token_index<=0; map_index<=0; merge_index<=0;
            previous_pair_valid<=0; code<=0; state<=CONFIG_CHECK;
          end
        end
        CONFIG_CHECK: begin
          if (vocab_size<256 || vocab_size>262144 || vocab_size>VOCAB_SIZE ||
              maximum_length==0 || raw_count==0 ||
              {1'b0,lengths[320+:64]}!=token_segment_bytes ||
              {1'b0,lengths[384+:64]}!=raw_segment_bytes) begin
            code<=8'h06; state<=FAILED;
          end else state<=TOKEN_SETUP;
        end
        TOKEN_SETUP: begin
          read_segment<=5; read_offset<=64'd32+({32'd0,token_index} << 4);
          read_words<=4; raw_read<=0; after_read<=TOKEN_EXTENT; state<=READ_ISSUE;
        end
        READ_ISSUE: if (reader_in_ready) state<=READ_WAIT;
        READ_WAIT: if (reader_out_valid) begin
          if (reader_error) begin code<=reader_code; state<=FAILED; end
          else begin record_data<=reader_data[127:0]; state<=after_read; end
        end
        TOKEN_EXTENT: begin
          token_end<={1'b0,token_offset}+{33'd0,token_length}; state<=TOKEN_CHECK;
        end
        TOKEN_CHECK: begin
          if (token_flags==0 || token_flags[31:2]!=0 ||
              (token_flags[0] && token_length==0) ||
              token_length>maximum_length || token_end[64] ||
              token_end>{33'd0,raw_count}) begin
            code<=8'h06; state<=FAILED;
          end else if (token_index+1==vocab_size) state<=MAP_SETUP;
          else begin token_index<=token_index+1'b1; state<=TOKEN_SETUP; end
        end
        MAP_SETUP: begin
          read_segment<=7; read_offset<=64'd32+({32'd0,map_index} << 2);
          read_words<=1; raw_read<=0; after_read<=MAP_ID; state<=READ_ISSUE;
        end
        MAP_ID: begin
          if (record_data[31:0]>=vocab_size) begin code<=8'h06; state<=FAILED; end
          else begin map_token<=record_data[31:0]; state<=MAP_TOKEN_SETUP; end
        end
        MAP_TOKEN_SETUP: begin
          read_segment<=5; read_offset<=64'd32+({32'd0,map_token} << 4);
          read_words<=4; raw_read<=0; after_read<=MAP_TOKEN_CHECK; state<=READ_ISSUE;
        end
        MAP_TOKEN_CHECK: begin
          if (!token_flags[0] || token_length!=1 || token_offset>={32'd0,raw_count}) begin
            code<=8'h06; state<=FAILED;
          end else begin
            raw_offset<={1'b0,token_offset}; after_raw<=MAP_BYTE; state<=RAW_ADDRESS;
          end
        end
        RAW_ADDRESS: begin
          raw_address<=65'd32+raw_offset; raw_lane<=raw_offset[1:0]; state<=RAW_CHECK;
        end
        RAW_CHECK: begin
          if (raw_offset[64] || raw_offset>={33'd0,raw_count} || raw_address[64]) begin
            code<=8'h06; state<=FAILED;
          end else begin
            read_segment<=6; read_offset<=raw_address[63:0] & ~64'd3;
            read_words<=1; raw_read<=1; after_read<=after_raw; state<=READ_ISSUE;
          end
        end
        MAP_BYTE: begin
          if ({24'd0,raw_byte}!=map_index) begin code<=8'h06; state<=FAILED; end
          else if (map_index==255) begin
            if (merge_count==0) begin done_r<=1; state<=COMPLETE; end
            else state<=MERGE_SETUP;
          end else begin map_index<=map_index+1'b1; state<=MAP_SETUP; end
        end
        MERGE_SETUP: begin
          read_segment<=8; read_offset<=64'd32+({32'd0,merge_index} << 4);
          read_words<=4; raw_read<=0; after_read<=MERGE_CHECK; state<=READ_ISSUE;
        end
        MERGE_CHECK: begin
          if ((previous_pair_valid && pair_key<=previous_pair) ||
              record_data[0+:32]>=vocab_size || record_data[32+:32]>=vocab_size ||
              record_data[64+:32]>=vocab_size) begin
            code<=8'h06; state<=FAILED;
          end else begin
            previous_pair<=pair_key; previous_pair_valid<=1;
            left_id<=record_data[0+:32]; right_id<=record_data[32+:32];
            result_id<=record_data[64+:32]; piece_index<=0; state<=PIECE_SETUP;
          end
        end
        PIECE_SETUP: begin
          read_segment<=5; read_offset<=64'd32+({32'd0,piece_id} << 4);
          read_words<=4; raw_read<=0; after_read<=PIECE_CHECK; state<=READ_ISSUE;
        end
        PIECE_CHECK: begin
          if (!token_flags[0] || token_length==0) begin code<=8'h06; state<=FAILED; end
          else begin
            piece_offsets[piece_index]<=token_offset; piece_lengths[piece_index]<=token_length;
            if (piece_index==2) state<=MERGE_LENGTH;
            else begin piece_index<=piece_index+1'b1; state<=PIECE_SETUP; end
          end
        end
        MERGE_LENGTH: begin
          merge_length<={33'd0,piece_lengths[0]}+{33'd0,piece_lengths[1]};
          state<=MERGE_LENGTH_CHECK;
        end
        MERGE_LENGTH_CHECK: begin
          if (merge_length>{33'd0,maximum_length} ||
              merge_length!={33'd0,piece_lengths[2]}) begin
            code<=8'h06; state<=FAILED;
          end else begin byte_index<=0; state<=SOURCE_BYTE_SETUP; end
        end
        SOURCE_BYTE_SETUP: begin
          raw_offset<={1'b0,source_offset}+{33'd0,source_index};
          after_raw<=SOURCE_BYTE; state<=RAW_ADDRESS;
        end
        SOURCE_BYTE: begin source_byte<=raw_byte; state<=RESULT_BYTE_SETUP; end
        RESULT_BYTE_SETUP: begin
          raw_offset<={1'b0,piece_offsets[2]}+{33'd0,byte_index};
          after_raw<=COMPARE_BYTE; state<=RAW_ADDRESS;
        end
        COMPARE_BYTE: begin
          if (source_byte!=raw_byte) begin code<=8'h06; state<=FAILED; end
          else if (byte_index+1==piece_lengths[2]) begin
            if (merge_index+1==merge_count) begin done_r<=1; state<=COMPLETE; end
            else begin merge_index<=merge_index+1'b1; state<=MERGE_SETUP; end
          end else begin byte_index<=byte_index+1'b1; state<=SOURCE_BYTE_SETUP; end
        end
        FAILED: state<=FAILED;
        default: begin code<=8'h06; state<=FAILED; end
      endcase
    end
  end
endmodule
