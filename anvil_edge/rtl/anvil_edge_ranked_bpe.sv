module anvil_edge_ranked_bpe #(
  parameter integer MAX_PRETOKEN_BYTES=4096
) (
  input wire clk, rst_n, start,
  input wire config_valid,
  input wire [31:0] cfg_vocab_size,
  input wire [63:0] cfg_merge_base,
  input wire [31:0] cfg_merge_count,
  input wire in_valid,
  output wire in_ready,
  input wire [31:0] in_token_id,
  input wire in_last,
  output wire out_valid,
  input wire out_ready,
  output wire [31:0] out_token_id,
  output wire out_last,
  output wire busy, done, error,
  output wire [7:0] error_code,
  output wire tbl_req_valid,
  input wire tbl_req_ready,
  output wire [63:0] tbl_req_addr,
  input wire tbl_rsp_valid,
  output wire tbl_rsp_ready,
  input wire [31:0] tbl_rsp_data,
  input wire tbl_rsp_error
);
  generate if (MAX_PRETOKEN_BYTES<1) begin : invalid_parameters
    initial $fatal(1, "ANVIL_EDGE_BPE PARAMETER ERROR: MAX_PRETOKEN_BYTES must be positive");
    assign in_ready=0;
    assign out_valid=0; assign out_token_id=0; assign out_last=0;
    assign busy=0; assign done=0; assign error=0; assign error_code=0;
    assign tbl_req_valid=0; assign tbl_req_addr=0; assign tbl_rsp_ready=0;
  end else begin : bpe
    localparam [4:0] IDLE=0, CAPTURE=1, SCAN_START=2, PAIR_START=3,
      SEARCH=4, ADDRESS=5, REQUEST=6, RESPONSE=7, CONSUME=8,
      COMPARE=9, NEXT_PAIR=10, SCAN_END=11, APPLY=12,
      SHIFT=13, EMIT=14, FAILED=15;
    reg [4:0] state;
    reg [31:0] tokens [0:MAX_PRETOKEN_BYTES-1];
    reg [31:0] vocabulary, merge_count, token_count, pair_index, output_index;
    reg [63:0] merge_base;
    reg [31:0] left_id, right_id, search_low, search_high, search_middle;
    reg [31:0] record_left, record_right, record_result, record_rank;
    reg [1:0] record_word;
    reg [31:0] response_data;
    reg [64:0] request_address;
    reg best_valid;
    reg [31:0] best_rank, best_position, best_result, shift_index;
    reg done_r;
    reg [7:0] code;
    wire [65:0] merge_end={2'b0,cfg_merge_base}+66'd32+
      ({34'd0,cfg_merge_count} << 4);
    wire [65:0] record_address={2'b0,merge_base}+66'd32+
      ({34'd0,search_middle} << 4)+{62'd0,record_word,2'b00};
    wire record_equal=record_left==left_id && record_right==right_id;
    wire record_before=record_left<left_id ||
      (record_left==left_id && record_right<right_id);

    assign in_ready=rst_n && state==CAPTURE;
    assign out_valid=rst_n && state==EMIT;
    assign out_token_id=out_valid ? tokens[output_index] : 0;
    assign out_last=out_valid && output_index+1==token_count;
    assign busy=rst_n && state!=IDLE && state!=FAILED;
    assign done=rst_n && done_r;
    assign error=rst_n && state==FAILED;
    assign error_code=rst_n ? code : 0;
    assign tbl_req_valid=rst_n && state==REQUEST;
    assign tbl_req_addr=rst_n ? request_address[63:0] : 0;
    assign tbl_rsp_ready=rst_n && state==RESPONSE;

    always @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
        state<=IDLE;
        vocabulary<=0; merge_count<=0; merge_base<=0; token_count<=0;
        pair_index<=0; output_index<=0; left_id<=0; right_id<=0;
        search_low<=0; search_high<=0; search_middle<=0;
        record_left<=0; record_right<=0; record_result<=0; record_rank<=0;
        record_word<=0; response_data<=0; request_address<=0;
        best_valid<=0; best_rank<=0; best_position<=0; best_result<=0;
        shift_index<=0; done_r<=0; code<=0;
      end else begin
        done_r<=0;
        case (state)
          IDLE: if (start) begin
            if (!config_valid || cfg_vocab_size<256 || cfg_vocab_size>262144 ||
                cfg_merge_base[1:0]!=0 || merge_end[65:64]!=0) begin
              code<=8'h06; state<=FAILED;
            end else begin
              vocabulary<=cfg_vocab_size;
              merge_count<=cfg_merge_count;
              merge_base<=cfg_merge_base;
              token_count<=0;
              output_index<=0;
              code<=0;
              state<=CAPTURE;
            end
          end
          CAPTURE: if (in_valid && in_ready) begin
            if (in_token_id>=vocabulary) begin
              code<=8'h11; state<=FAILED;
            end else if (token_count>=MAX_PRETOKEN_BYTES) begin
              code<=8'h30; state<=FAILED;
            end else begin
              tokens[token_count]<=in_token_id;
              token_count<=token_count+1;
              if (in_last) state<=SCAN_START;
              else if (token_count+1>=MAX_PRETOKEN_BYTES) begin
                code<=8'h30; state<=FAILED;
              end
            end
          end
          SCAN_START: begin
            best_valid<=0;
            best_rank<=0; best_position<=0; best_result<=0;
            pair_index<=0;
            if (token_count<2 || merge_count==0) begin
              output_index<=0; state<=EMIT;
            end else state<=PAIR_START;
          end
          PAIR_START: begin
            left_id<=tokens[pair_index];
            right_id<=tokens[pair_index+1];
            search_low<=0;
            search_high<=merge_count;
            state<=SEARCH;
          end
          SEARCH: begin
            if (search_low>=search_high) state<=NEXT_PAIR;
            else begin
              search_middle<=search_low+((search_high-search_low) >> 1);
              record_word<=0;
              state<=ADDRESS;
            end
          end
          ADDRESS: begin
            if (record_address[65:64]!=0 || search_middle>=merge_count) begin
              code<=8'h11; state<=FAILED;
            end else begin
              request_address<=record_address[64:0]; state<=REQUEST;
            end
          end
          REQUEST: if (tbl_req_valid && tbl_req_ready) state<=RESPONSE;
          RESPONSE: if (tbl_rsp_valid && tbl_rsp_ready) begin
            if (tbl_rsp_error) begin code<=8'h04; state<=FAILED; end
            else begin response_data<=tbl_rsp_data; state<=CONSUME; end
          end
          CONSUME: begin
            case (record_word)
              0: record_left<=response_data;
              1: record_right<=response_data;
              2: record_result<=response_data;
              3: record_rank<=response_data;
            endcase
            if (record_word==3) state<=COMPARE;
            else begin record_word<=record_word+1'b1; state<=ADDRESS; end
          end
          COMPARE: begin
            if (record_left>=vocabulary || record_right>=vocabulary ||
                record_result>=vocabulary) begin
              code<=8'h11; state<=FAILED;
            end else if (record_equal) begin
              if (!best_valid || record_rank<best_rank) begin
                best_valid<=1;
                best_rank<=record_rank;
                best_position<=pair_index;
                best_result<=record_result;
              end
              state<=NEXT_PAIR;
            end else begin
              if (record_before) search_low<=search_middle+1;
              else search_high<=search_middle;
              state<=SEARCH;
            end
          end
          NEXT_PAIR: begin
            if (pair_index+2<token_count) begin
              pair_index<=pair_index+1; state<=PAIR_START;
            end else state<=SCAN_END;
          end
          SCAN_END: begin
            if (best_valid) state<=APPLY;
            else begin output_index<=0; state<=EMIT; end
          end
          APPLY: begin
            tokens[best_position]<=best_result;
            shift_index<=best_position+1;
            state<=SHIFT;
          end
          SHIFT: begin
            if (shift_index+1<token_count) begin
              tokens[shift_index]<=tokens[shift_index+1];
              shift_index<=shift_index+1;
            end else begin
              token_count<=token_count-1;
              state<=SCAN_START;
            end
          end
          EMIT: if (out_valid && out_ready) begin
            if (out_last) begin done_r<=1; state<=IDLE; end
            else output_index<=output_index+1;
          end
          FAILED: state<=FAILED;
          default: begin code<=8'h12; state<=FAILED; end
        endcase
      end
    end
  end endgenerate
endmodule
