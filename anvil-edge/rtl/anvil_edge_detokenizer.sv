module anvil_edge_detokenizer (
  input wire clk, rst_n,
  input wire start,
  input wire in_valid,
  output wire in_ready,
  input wire [31:0] in_token_id,
  input wire in_last,
  output wire out_valid,
  input wire out_ready,
  output wire [7:0] out_data,
  output wire out_last,
  output wire busy, done, error,
  output wire [7:0] error_code,
  output wire tbl_req_valid,
  input wire tbl_req_ready,
  output wire [63:0] tbl_req_addr,
  input wire tbl_rsp_valid,
  output wire tbl_rsp_ready,
  input wire [31:0] tbl_rsp_data,
  input wire tbl_rsp_error,
  input wire config_valid,
  input wire [31:0] cfg_vocab_size,
  input wire [63:0] cfg_token_records_base, cfg_token_bytes_base,
  input wire [63:0] cfg_token_bytes_count,
  input wire [31:0] cfg_max_token_byte_length,
  input wire finish_valid,
  output wire finish_ready
);
  localparam [4:0] IDLE=0, TOKEN=1, RECORD_ADDRESS=2, REQUEST=3,
    RESPONSE=4, RECORD_CONSUME=5, RECORD_CHECK=6, BYTE_ADDRESS=7,
    BYTE_CONSUME=8, BYTE_NEXT=9, EMIT=10, TOKEN_END=11,
    FINAL_CHECK=12, FINAL_BYTE=13, CLOSED=14, FAILED=15;
  reg [4:0] state;
  reg [31:0] vocabulary, maximum_length, token_id;
  reg [63:0] records_base, bytes_base, bytes_count;
  reg token_last;
  reg [1:0] record_word;
  reg [63:0] token_offset;
  reg [31:0] token_length, token_flags;
  reg [63:0] cursor;
  reg [31:0] remaining_bytes;
  reg [63:0] request_address;
  reg [31:0] response_data;
  reg reading_record;
  reg [1:0] byte_lane;
  reg [2:0] utf_remaining, scalar_length, emit_index;
  reg [20:0] scalar_value, minimum_scalar;
  reg [7:0] scalar_bytes [0:3];
  reg tail_valid;
  reg [7:0] tail_byte;
  reg done_r;
  reg [7:0] code;
  wire [64:0] records_data_start = {1'b0, records_base}+65'd32;
  wire [64:0] bytes_data_start = {1'b0, bytes_base}+65'd32;
  wire [64:0] record_address_wide =
    records_data_start+({33'd0, token_id} << 4)+{61'd0, record_word, 2'b00};
  wire [64:0] token_end = {1'b0, token_offset}+{33'd0, token_length};
  wire [64:0] byte_address_wide = bytes_data_start+{1'b0, cursor};
  wire [7:0] next_byte = response_data >> {byte_lane, 3'b000};
  wire [20:0] continued_scalar = (scalar_value << 6) | {15'd0, next_byte[5:0]};
  wire emit_has_older_byte = state == EMIT && tail_valid;

  assign in_ready = rst_n && state == TOKEN;
  assign finish_ready = rst_n && ((state == TOKEN && !in_valid) || state == CLOSED);
  assign out_valid = rst_n && (emit_has_older_byte || state == FINAL_BYTE);
  assign out_data = out_valid ? tail_byte : 0;
  assign out_last = rst_n && state == FINAL_BYTE;
  assign busy = rst_n && state != IDLE && state != CLOSED && state != FAILED;
  assign done = rst_n && done_r;
  assign error = rst_n && state == FAILED;
  assign error_code = rst_n ? code : 0;
  assign tbl_req_valid = rst_n && state == REQUEST;
  assign tbl_req_addr = rst_n ? request_address : 0;
  assign tbl_rsp_ready = rst_n && state == RESPONSE;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= IDLE;
      vocabulary <= 0;
      maximum_length <= 0;
      token_id <= 0;
      records_base <= 0;
      bytes_base <= 0;
      bytes_count <= 0;
      token_last <= 0;
      record_word <= 0;
      token_offset <= 0;
      token_length <= 0;
      token_flags <= 0;
      cursor <= 0;
      remaining_bytes <= 0;
      request_address <= 0;
      response_data <= 0;
      reading_record <= 0;
      byte_lane <= 0;
      utf_remaining <= 0;
      scalar_length <= 0;
      emit_index <= 0;
      scalar_value <= 0;
      minimum_scalar <= 0;
      scalar_bytes[0] <= 0;
      scalar_bytes[1] <= 0;
      scalar_bytes[2] <= 0;
      scalar_bytes[3] <= 0;
      tail_valid <= 0;
      tail_byte <= 0;
      done_r <= 0;
      code <= 0;
    end else begin
      done_r <= 0;
      case (state)
        IDLE, CLOSED: if (start) begin
          if (!config_valid || cfg_vocab_size < 256 || cfg_vocab_size > 262144 ||
              cfg_max_token_byte_length == 0 ||
              cfg_token_records_base[1:0] != 0 || cfg_token_bytes_base[1:0] != 0 ||
              ({2'b0, cfg_token_records_base}+66'd32+
                ({34'd0, cfg_vocab_size} << 4)) > 66'h0ffffffffffffffff ||
              ({2'b0, cfg_token_bytes_base}+66'd32+
                {2'b0, cfg_token_bytes_count}) > 66'h0ffffffffffffffff) begin
            code <= 8'h06;
            state <= FAILED;
          end else begin
            vocabulary <= cfg_vocab_size;
            maximum_length <= cfg_max_token_byte_length;
            records_base <= cfg_token_records_base;
            bytes_base <= cfg_token_bytes_base;
            bytes_count <= cfg_token_bytes_count;
            utf_remaining <= 0;
            scalar_length <= 0;
            scalar_value <= 0;
            tail_valid <= 0;
            tail_byte <= 0;
            code <= 0;
            state <= TOKEN;
          end
        end
        TOKEN: if (in_valid && in_ready) begin
          if (in_token_id >= vocabulary) begin
            code <= 8'h11;
            state <= FAILED;
          end else begin
            token_id <= in_token_id;
            token_last <= in_last;
            record_word <= 0;
            token_offset <= 0;
            token_length <= 0;
            token_flags <= 0;
            state <= RECORD_ADDRESS;
          end
        end else if (finish_valid && finish_ready) state <= FINAL_CHECK;
        RECORD_ADDRESS: begin
          if (record_address_wide[64]) begin
            code <= 8'h11;
            state <= FAILED;
          end else begin
            request_address <= record_address_wide[63:0];
            reading_record <= 1;
            state <= REQUEST;
          end
        end
        REQUEST: if (tbl_req_valid && tbl_req_ready) state <= RESPONSE;
        RESPONSE: if (tbl_rsp_valid && tbl_rsp_ready) begin
          if (tbl_rsp_error) begin
            code <= 8'h04;
            state <= FAILED;
          end else begin
            response_data <= tbl_rsp_data;
            if (reading_record) state <= RECORD_CONSUME;
            else state <= BYTE_CONSUME;
          end
        end
        RECORD_CONSUME: begin
          case (record_word)
            0: token_offset[31:0] <= response_data;
            1: token_offset[63:32] <= response_data;
            2: token_length <= response_data;
            3: token_flags <= response_data;
          endcase
          if (record_word == 3) state <= RECORD_CHECK;
          else begin
            record_word <= record_word+1'b1;
            state <= RECORD_ADDRESS;
          end
        end
        RECORD_CHECK: begin
          if (token_flags[31:2] != 0 || token_flags[1:0] == 0 ||
              (token_flags[0] && token_length == 0) ||
              token_length > maximum_length ||
              token_end[64] || token_end > {1'b0, bytes_count}) begin
            code <= 8'h11;
            state <= FAILED;
          end else begin
            cursor <= token_offset;
            remaining_bytes <= token_length;
            if (token_length == 0) state <= TOKEN_END;
            else state <= BYTE_ADDRESS;
          end
        end
        BYTE_ADDRESS: begin
          if (byte_address_wide[64]) begin
            code <= 8'h11;
            state <= FAILED;
          end else begin
            request_address <= {byte_address_wide[63:2], 2'b00};
            byte_lane <= byte_address_wide[1:0];
            reading_record <= 0;
            state <= REQUEST;
          end
        end
        BYTE_CONSUME: begin
          cursor <= cursor+1;
          remaining_bytes <= remaining_bytes-1;
          if (utf_remaining == 0) begin
            scalar_bytes[0] <= next_byte;
            scalar_length <= 1;
            emit_index <= 0;
            if (next_byte < 8'h80) begin
              scalar_value <= {13'd0, next_byte};
              state <= EMIT;
            end else if (next_byte >= 8'hc2 && next_byte <= 8'hdf) begin
              scalar_value <= {16'd0, next_byte[4:0]};
              minimum_scalar <= 21'h80;
              utf_remaining <= 1;
              state <= BYTE_NEXT;
            end else if (next_byte >= 8'he0 && next_byte <= 8'hef) begin
              scalar_value <= {17'd0, next_byte[3:0]};
              minimum_scalar <= 21'h800;
              utf_remaining <= 2;
              state <= BYTE_NEXT;
            end else if (next_byte >= 8'hf0 && next_byte <= 8'hf4) begin
              scalar_value <= {18'd0, next_byte[2:0]};
              minimum_scalar <= 21'h10000;
              utf_remaining <= 3;
              state <= BYTE_NEXT;
            end else begin
              code <= 8'h10;
              state <= FAILED;
            end
          end else if (next_byte[7:6] != 2'b10) begin
            code <= 8'h10;
            state <= FAILED;
          end else begin
            scalar_bytes[scalar_length] <= next_byte;
            scalar_length <= scalar_length+1'b1;
            scalar_value <= continued_scalar;
            utf_remaining <= utf_remaining-1'b1;
            if (utf_remaining == 1) begin
              if (continued_scalar < minimum_scalar ||
                  continued_scalar > 21'h10ffff ||
                  (continued_scalar >= 21'hd800 && continued_scalar <= 21'hdfff)) begin
                code <= 8'h10;
                state <= FAILED;
              end else begin
                emit_index <= 0;
                state <= EMIT;
              end
            end else state <= BYTE_NEXT;
          end
        end
        BYTE_NEXT: if (remaining_bytes == 0) state <= TOKEN_END;
          else state <= BYTE_ADDRESS;
        EMIT: if (!tail_valid || (out_valid && out_ready)) begin
          tail_byte <= scalar_bytes[emit_index];
          tail_valid <= 1;
          if (emit_index+1 == scalar_length) state <= BYTE_NEXT;
          else emit_index <= emit_index+1'b1;
        end
        TOKEN_END: if (token_last) state <= FINAL_CHECK;
          else state <= TOKEN;
        FINAL_CHECK: begin
          if (utf_remaining != 0) begin
            code <= 8'h10;
            state <= FAILED;
          end else if (tail_valid) state <= FINAL_BYTE;
          else begin
            done_r <= 1;
            state <= CLOSED;
          end
        end
        FINAL_BYTE: if (out_valid && out_ready) begin
          tail_valid <= 0;
          done_r <= 1;
          state <= CLOSED;
        end
        FAILED: state <= FAILED;
        default: begin
          code <= 8'h12;
          state <= FAILED;
        end
      endcase
    end
  end
endmodule
