module anvil_edge_text_bpe_span #(
  parameter integer MAX_SPAN_BYTES=4096,
  parameter integer MAX_SPAN_TOKENS=4096,
  parameter integer MAX_PRETOKEN_BYTES=4096,
  parameter integer MAX_TAG_REGISTERS=32
) (
  input wire clk, rst_n, start,
  input wire config_valid,
  input wire [31:0] cfg_normalization, cfg_vocab_size, cfg_max_pretoken_bytes,
  input wire [63:0] cfg_ranges_base, cfg_decomposition_base,
    cfg_scalar_pool_base, cfg_composition_base, cfg_states_base,
    cfg_transitions_base, cfg_tag_ops_base, cfg_accepts_base,
    cfg_byte_map_base, cfg_merge_base,
  input wire [31:0] cfg_range_count, cfg_class_count, cfg_decomposition_count,
    cfg_scalar_pool_count, cfg_composition_count, cfg_state_count,
    cfg_transition_count, cfg_tag_op_count, cfg_accept_count,
    cfg_start_state, cfg_dead_state, cfg_tag_register_count, cfg_merge_count,
  input wire in_valid,
  output wire in_ready,
  input wire [31:0] in_scalar,
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
  generate if (MAX_SPAN_BYTES<1 || MAX_SPAN_TOKENS<1 ||
               MAX_PRETOKEN_BYTES<1 || MAX_TAG_REGISTERS<32) begin : invalid_parameters
    initial $fatal(1, "ANVIL_EDGE_TEXT_BPE PARAMETER ERROR: positive capacities and at least 32 tags required");
    assign in_ready=0; assign out_valid=0; assign out_token_id=0; assign out_last=0;
    assign busy=0; assign done=0; assign error=0; assign error_code=0;
    assign tbl_req_valid=0; assign tbl_req_addr=0; assign tbl_rsp_ready=0;
  end else begin : span
    localparam [4:0] IDLE=0, NORMALIZER_START=1, NORMALIZER_CAPTURE=2,
      NORMALIZER_OUTPUT=3, ENCODER_START=4, ENCODER_INPUT=5,
      ENCODER_BYTES=6, DFA_START=7, DFA_INPUT=8, DFA_BOUNDARY=9,
      BPE_START=10, BASE_SELECT=11, BASE_ISSUE=12, BASE_WAIT=13,
      BASE_SEND=14, BPE_OUTPUT=15, BOUNDARY_ACK=16, EMIT=17,
      CLOSED=18, FAILED=19;
    reg [4:0] state;
    reg [31:0] scalars [0:MAX_SPAN_BYTES-1];
    reg [7:0] bytes_memory [0:MAX_SPAN_BYTES-1];
    reg [31:0] tokens [0:MAX_SPAN_TOKENS-1];
    reg [31:0] scalar_count, scalar_index, byte_count, token_count, output_index;
    reg [2:0] scalar_bytes_left;
    reg [31:0] consumed_bytes, byte_cursor, boundary_end, base_id;
    reg [7:0] base_byte;
    reg boundary_last, done_r;
    reg [7:0] code;
    wire normalize_selected=state==NORMALIZER_START || state==NORMALIZER_CAPTURE ||
      state==NORMALIZER_OUTPUT;
    wire dfa_selected=state==DFA_START || state==DFA_INPUT ||
      state==DFA_BOUNDARY || state==BOUNDARY_ACK;
    wire base_selected=state==BASE_SELECT || state==BASE_ISSUE ||
      state==BASE_WAIT || state==BASE_SEND;
    wire normalize_in_ready, normalize_out_valid, normalize_last, normalize_error;
    wire [31:0] normalize_scalar;
    wire [7:0] normalize_code;
    wire normalize_tbl_valid, normalize_tbl_ready;
    wire [63:0] normalize_tbl_address;
    wire encoder_in_ready, encoder_valid, encoder_last, encoder_error;
    wire [7:0] encoder_data, encoder_code;
    wire dfa_in_ready, dfa_valid, dfa_last, dfa_error;
    wire [31:0] dfa_start_byte, dfa_end_byte;
    wire [7:0] dfa_code;
    wire dfa_tbl_valid, dfa_tbl_ready;
    wire [63:0] dfa_tbl_address;
    wire bpe_in_ready, bpe_valid, bpe_last, bpe_error;
    wire [31:0] bpe_id;
    wire [7:0] bpe_code;
    wire bpe_tbl_valid, bpe_tbl_ready;
    wire [63:0] bpe_tbl_address;
    wire base_ready, base_valid, base_error, base_tbl_valid, base_tbl_ready;
    wire [31:0] base_data;
    wire [7:0] base_code;
    wire [63:0] base_tbl_address;
    wire [31:0] selected_scalar=scalars[scalar_index];
    wire active=rst_n && state!=IDLE && state!=CLOSED && state!=FAILED;

    anvil_edge_normalizer #(.MAX_SCALARS(MAX_SPAN_BYTES)) normalization(
      .clk(clk),.rst_n(rst_n),.start(rst_n && state==NORMALIZER_START),
      .config_valid(config_valid),.cfg_normalization(cfg_normalization),
      .cfg_ranges_base(cfg_ranges_base),.cfg_decomposition_base(cfg_decomposition_base),
      .cfg_scalar_pool_base(cfg_scalar_pool_base),
      .cfg_composition_base(cfg_composition_base),.cfg_range_count(cfg_range_count),
      .cfg_class_count(cfg_class_count),.cfg_decomposition_count(cfg_decomposition_count),
      .cfg_scalar_pool_count(cfg_scalar_pool_count),
      .cfg_composition_count(cfg_composition_count),
      .in_valid(rst_n && state==NORMALIZER_CAPTURE && in_valid),
      .in_ready(normalize_in_ready),.in_scalar(in_scalar),.in_last(in_last),
      .out_valid(normalize_out_valid),
      .out_ready(rst_n && state==NORMALIZER_OUTPUT),.out_scalar(normalize_scalar),
      .out_last(normalize_last),.busy(),.done(),.error(normalize_error),
      .error_code(normalize_code),.tbl_req_valid(normalize_tbl_valid),
      .tbl_req_ready(normalize_selected && tbl_req_ready),
      .tbl_req_addr(normalize_tbl_address),
      .tbl_rsp_valid(normalize_selected && tbl_rsp_valid),
      .tbl_rsp_ready(normalize_tbl_ready),.tbl_rsp_data(tbl_rsp_data),
      .tbl_rsp_error(tbl_rsp_error)
    );
    anvil_edge_utf8_encoder encoding(
      .clk(clk),.rst_n(rst_n),.start(rst_n && state==ENCODER_START),
      .in_valid(rst_n && state==ENCODER_INPUT),.in_ready(encoder_in_ready),
      .in_scalar(selected_scalar),.in_last(scalar_index+1==scalar_count),
      .out_valid(encoder_valid),.out_ready(rst_n && state==ENCODER_BYTES),
      .out_data(encoder_data),.out_last(encoder_last),.busy(),.done(),
      .error(encoder_error),.error_code(encoder_code)
    );
    anvil_edge_tagged_dfa #(
      .MAX_SPAN_BYTES(MAX_SPAN_BYTES),.MAX_TAG_REGISTERS(MAX_TAG_REGISTERS)
    ) pretokenization(
      .clk(clk),.rst_n(rst_n),.start(rst_n && state==DFA_START),
      .config_valid(config_valid),.cfg_ranges_base(cfg_ranges_base),
      .cfg_states_base(cfg_states_base),.cfg_transitions_base(cfg_transitions_base),
      .cfg_tag_ops_base(cfg_tag_ops_base),.cfg_accepts_base(cfg_accepts_base),
      .cfg_range_count(cfg_range_count),.cfg_class_count(cfg_class_count),
      .cfg_state_count(cfg_state_count),.cfg_transition_count(cfg_transition_count),
      .cfg_tag_op_count(cfg_tag_op_count),.cfg_accept_count(cfg_accept_count),
      .cfg_start_state(cfg_start_state),.cfg_dead_state(cfg_dead_state),
      .cfg_tag_register_count(cfg_tag_register_count),
      .in_valid(rst_n && state==DFA_INPUT),.in_ready(dfa_in_ready),
      .in_scalar(selected_scalar),.in_last(scalar_index+1==scalar_count),
      .out_valid(dfa_valid),.out_ready(rst_n && state==BOUNDARY_ACK),
      .out_start(dfa_start_byte),.out_end(dfa_end_byte),.out_last(dfa_last),
      .busy(),.done(),.error(dfa_error),.error_code(dfa_code),
      .tbl_req_valid(dfa_tbl_valid),.tbl_req_ready(dfa_selected && tbl_req_ready),
      .tbl_req_addr(dfa_tbl_address),.tbl_rsp_valid(dfa_selected && tbl_rsp_valid),
      .tbl_rsp_ready(dfa_tbl_ready),.tbl_rsp_data(tbl_rsp_data),
      .tbl_rsp_error(tbl_rsp_error)
    );
    anvil_edge_table_record_reader #(.LOG2_RECORD_BYTES(2)) byte_map(
      .clk(clk),.rst_n(rst_n),.in_valid(rst_n && state==BASE_ISSUE),
      .in_ready(base_ready),.segment_base(cfg_byte_map_base),
      .record_count(32'd256),.record_index({24'd0,base_byte}),
      .out_valid(base_valid),.out_ready(rst_n && state==BASE_WAIT),
      .record_data(base_data),.response_error(base_error),
      .response_error_code(base_code),.tbl_req_valid(base_tbl_valid),
      .tbl_req_ready(base_selected && tbl_req_ready),.tbl_req_addr(base_tbl_address),
      .tbl_rsp_valid(base_selected && tbl_rsp_valid),.tbl_rsp_ready(base_tbl_ready),
      .tbl_rsp_data(tbl_rsp_data),.tbl_rsp_error(tbl_rsp_error)
    );
    anvil_edge_ranked_bpe #(.MAX_PRETOKEN_BYTES(MAX_PRETOKEN_BYTES)) ranked_merges(
      .clk(clk),.rst_n(rst_n),.start(rst_n && state==BPE_START),
      .config_valid(config_valid),.cfg_vocab_size(cfg_vocab_size),
      .cfg_merge_base(cfg_merge_base),.cfg_merge_count(cfg_merge_count),
      .in_valid(rst_n && state==BASE_SEND),.in_ready(bpe_in_ready),
      .in_token_id(base_id),.in_last(byte_cursor+1==boundary_end),
      .out_valid(bpe_valid),.out_ready(rst_n && state==BPE_OUTPUT),
      .out_token_id(bpe_id),.out_last(bpe_last),.busy(),.done(),
      .error(bpe_error),.error_code(bpe_code),.tbl_req_valid(bpe_tbl_valid),
      .tbl_req_ready(!normalize_selected && !dfa_selected &&
                    !base_selected && tbl_req_ready),
      .tbl_req_addr(bpe_tbl_address),
      .tbl_rsp_valid(!normalize_selected && !dfa_selected &&
                    !base_selected && tbl_rsp_valid),
      .tbl_rsp_ready(bpe_tbl_ready),.tbl_rsp_data(tbl_rsp_data),
      .tbl_rsp_error(tbl_rsp_error)
    );

    assign tbl_req_valid=normalize_selected ? normalize_tbl_valid :
      (dfa_selected ? dfa_tbl_valid : (base_selected ? base_tbl_valid : bpe_tbl_valid));
    assign tbl_req_addr=normalize_selected ? normalize_tbl_address :
      (dfa_selected ? dfa_tbl_address :
       (base_selected ? base_tbl_address : bpe_tbl_address));
    assign tbl_rsp_ready=normalize_selected ? normalize_tbl_ready :
      (dfa_selected ? dfa_tbl_ready : (base_selected ? base_tbl_ready : bpe_tbl_ready));
    assign in_ready=rst_n && state==NORMALIZER_CAPTURE && normalize_in_ready;
    assign out_valid=rst_n && state==EMIT;
    assign out_token_id=out_valid ? tokens[output_index] : 0;
    assign out_last=out_valid && output_index+1==token_count;
    assign busy=active;
    assign done=rst_n && done_r;
    assign error=rst_n && state==FAILED;
    assign error_code=rst_n ? code : 0;

    always @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
        state<=IDLE; scalar_count<=0; scalar_index<=0; byte_count<=0;
        token_count<=0; output_index<=0; scalar_bytes_left<=0;
        consumed_bytes<=0; byte_cursor<=0; boundary_end<=0; base_id<=0;
        base_byte<=0; boundary_last<=0; done_r<=0; code<=0;
      end else begin
        done_r<=0;
        if (active && normalize_error) begin code<=normalize_code; state<=FAILED; end
        else if (active && encoder_error) begin code<=encoder_code; state<=FAILED; end
        else if (active && dfa_error) begin code<=dfa_code; state<=FAILED; end
        else if (active && bpe_error) begin code<=bpe_code; state<=FAILED; end
        else case (state)
          IDLE, CLOSED: if (start) begin
            if (!config_valid || cfg_vocab_size<256 || cfg_vocab_size>262144 ||
                cfg_max_pretoken_bytes==0 || cfg_max_pretoken_bytes>MAX_PRETOKEN_BYTES ||
                cfg_byte_map_base[1:0]!=0) begin
              code<=8'h06; state<=FAILED;
            end else begin
              scalar_count<=0; scalar_index<=0; byte_count<=0; token_count<=0;
              output_index<=0; consumed_bytes<=0; code<=0;
              state<=NORMALIZER_START;
            end
          end
          NORMALIZER_START: state<=NORMALIZER_CAPTURE;
          NORMALIZER_CAPTURE: if (in_valid && in_ready && in_last)
            state<=NORMALIZER_OUTPUT;
          NORMALIZER_OUTPUT: if (normalize_out_valid) begin
            if (scalar_count>=MAX_SPAN_BYTES) begin code<=8'h30; state<=FAILED; end
            else begin
              scalars[scalar_count]<=normalize_scalar; scalar_count<=scalar_count+1;
              if (normalize_last) begin scalar_index<=0; state<=ENCODER_START; end
            end
          end
          ENCODER_START: state<=ENCODER_INPUT;
          ENCODER_INPUT: if (encoder_in_ready) begin
            if (selected_scalar<32'h80) scalar_bytes_left<=1;
            else if (selected_scalar<32'h800) scalar_bytes_left<=2;
            else if (selected_scalar<32'h10000) scalar_bytes_left<=3;
            else scalar_bytes_left<=4;
            state<=ENCODER_BYTES;
          end
          ENCODER_BYTES: if (encoder_valid) begin
            if (byte_count>=MAX_SPAN_BYTES) begin code<=8'h30; state<=FAILED; end
            else begin
              bytes_memory[byte_count]<=encoder_data; byte_count<=byte_count+1;
              scalar_bytes_left<=scalar_bytes_left-1'b1;
              if (encoder_last) begin scalar_index<=0; state<=DFA_START; end
              else if (scalar_bytes_left==1) begin
                scalar_index<=scalar_index+1; state<=ENCODER_INPUT;
              end
            end
          end
          DFA_START: state<=DFA_INPUT;
          DFA_INPUT: if (dfa_in_ready) begin
            if (scalar_index+1==scalar_count) state<=DFA_BOUNDARY;
            else scalar_index<=scalar_index+1;
          end
          DFA_BOUNDARY: if (dfa_valid) begin
            if (dfa_start_byte!=consumed_bytes || dfa_end_byte<=dfa_start_byte ||
                dfa_end_byte>byte_count || (dfa_last && dfa_end_byte!=byte_count)) begin
              code<=8'h12; state<=FAILED;
            end else if (dfa_end_byte-dfa_start_byte>cfg_max_pretoken_bytes) begin
              code<=8'h30; state<=FAILED;
            end else begin
              byte_cursor<=dfa_start_byte; boundary_end<=dfa_end_byte;
              boundary_last<=dfa_last; state<=BPE_START;
            end
          end
          BPE_START: state<=BASE_SELECT;
          BASE_SELECT: begin base_byte<=bytes_memory[byte_cursor]; state<=BASE_ISSUE; end
          BASE_ISSUE: if (base_ready) state<=BASE_WAIT;
          BASE_WAIT: if (base_valid) begin
            if (base_error) begin code<=base_code; state<=FAILED; end
            else if (base_data>=cfg_vocab_size) begin code<=8'h11; state<=FAILED; end
            else begin base_id<=base_data; state<=BASE_SEND; end
          end
          BASE_SEND: if (bpe_in_ready) begin
            if (byte_cursor+1==boundary_end) state<=BPE_OUTPUT;
            else begin byte_cursor<=byte_cursor+1; state<=BASE_SELECT; end
          end
          BPE_OUTPUT: if (bpe_valid) begin
            if (token_count>=MAX_SPAN_TOKENS) begin code<=8'h30; state<=FAILED; end
            else begin
              tokens[token_count]<=bpe_id; token_count<=token_count+1;
              if (bpe_last) state<=BOUNDARY_ACK;
            end
          end
          BOUNDARY_ACK: if (dfa_valid) begin
            consumed_bytes<=boundary_end;
            if (boundary_last) begin output_index<=0; state<=EMIT; end
            else state<=DFA_BOUNDARY;
          end
          EMIT: if (out_valid && out_ready) begin
            if (out_last) begin done_r<=1; state<=CLOSED; end
            else output_index<=output_index+1;
          end
          FAILED: state<=FAILED;
          default: begin code<=8'h12; state<=FAILED; end
        endcase
      end
    end
  end endgenerate
endmodule
