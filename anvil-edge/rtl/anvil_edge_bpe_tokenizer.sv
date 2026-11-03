module anvil_edge_bpe_tokenizer #(
  parameter integer MAX_PROMPT_BYTES=4096,
  parameter integer MAX_PROMPT_TOKENS=4096,
  parameter integer MAX_PRETOKEN_BYTES=4096,
  parameter integer MAX_TAG_REGISTERS=32
) (
  input wire clk, rst_n, start,
  input wire in_valid,
  output wire in_ready,
  input wire [7:0] in_data,
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
  input wire tbl_rsp_error,
  input wire config_valid,
  input wire [1023:0] cfg_table_bases, cfg_metadata,
  input wire [511:0] cfg_table_counts
);
  generate if (MAX_PROMPT_BYTES<1 || MAX_PROMPT_TOKENS<1 ||
               MAX_PRETOKEN_BYTES<1 || MAX_TAG_REGISTERS<32) begin : invalid_parameters
    initial $fatal(1,"ANVIL_EDGE_TOKENIZER PARAMETER ERROR: positive capacities and at least 32 tags required");
    assign in_ready=0; assign out_valid=0; assign out_token_id=0; assign out_last=0;
    assign busy=0; assign done=0; assign error=0; assign error_code=0;
    assign tbl_req_valid=0; assign tbl_req_addr=0; assign tbl_rsp_ready=0;
  end else begin : tokenizer
    localparam [4:0] IDLE=0, DECODE_START=1, DECODE=2,
      FIRST_START=3, FIRST_INPUT=4, FIRST_DISPATCH=5,
      NORMALIZE_START=6, NORMALIZE_INPUT=7, NORMALIZE_OUTPUT=8,
      SECOND_DISPATCH=9, SPAN_START=10, SPAN_INPUT=11, SPAN_OUTPUT=12,
      EMIT=13, CLOSED=14, FAILED=15, EMIT_LOAD=16;
    localparam [1:0] FIRST=0, NORMALIZE=1, SECOND=2, SPAN=3;
    reg [4:0] state;
    reg [31:0] scalars [0:MAX_PROMPT_BYTES-1];
    reg [31:0] tokens [0:MAX_PROMPT_TOKENS-1];
    reg [31:0] scalar_count, scalar_index, token_count, output_index;
    reg outer_last, inner_last, done_r;
    reg [31:0] output_token;
    reg output_last;
    reg [7:0] code;
    reg [1:0] selected;
    wire active=rst_n && state!=IDLE && state!=CLOSED && state!=FAILED;
    wire decode_ready, decode_valid, decode_last, decode_error;
    wire [31:0] decode_scalar;
    wire [7:0] decode_code;
    wire first_ready, first_valid, first_special, first_boundary, first_last;
    wire first_error;
    wire [31:0] first_value;
    wire [7:0] first_code;
    wire normal_ready, normal_valid, normal_last, normal_error;
    wire [31:0] normal_scalar;
    wire [7:0] normal_code;
    wire second_ready, second_valid, second_special, second_boundary, second_last;
    wire second_error;
    wire [31:0] second_value;
    wire [7:0] second_code;
    wire span_ready, span_valid, span_last, span_error;
    wire [31:0] span_token;
    wire [7:0] span_code;
    wire [3:0] requests, responses_ready;
    wire [255:0] addresses;
    wire first_accept=rst_n &&
      ((state==FIRST_DISPATCH && first_special) ||
       (state==NORMALIZE_INPUT && normal_ready));
    wire second_accept=rst_n &&
      ((state==SECOND_DISPATCH && second_special) ||
       (state==SPAN_INPUT && span_ready));

    always @* begin
      selected=FIRST;
      case (state)
        NORMALIZE_START, NORMALIZE_INPUT, NORMALIZE_OUTPUT: selected=NORMALIZE;
        SECOND_DISPATCH: selected=SECOND;
        SPAN_START, SPAN_INPUT, SPAN_OUTPUT: selected=SPAN;
        default: begin end
      endcase
    end
    assign tbl_req_valid=rst_n && requests[selected];
    assign tbl_req_addr=rst_n ? addresses[selected*64+:64] : 0;
    assign tbl_rsp_ready=rst_n && responses_ready[selected];
    assign in_ready=rst_n && state==DECODE && decode_ready;
    assign out_valid=rst_n && state==EMIT;
    assign out_token_id=out_valid ? output_token : 0;
    assign out_last=out_valid && output_last;
    assign busy=active;
    assign done=rst_n && done_r;
    assign error=rst_n && state==FAILED;
    assign error_code=rst_n ? code : 0;

    anvil_edge_utf8_decoder #(.MAX_BYTES(MAX_PROMPT_BYTES)) utf8(
      .clk(clk),.rst_n(rst_n),.start(rst_n && state==DECODE_START),
      .in_valid(rst_n && state==DECODE && in_valid),.in_ready(decode_ready),
      .in_data(in_data),.in_last(in_last),.out_valid(decode_valid),
      .out_ready(rst_n && state==DECODE),.out_scalar(decode_scalar),
      .out_start(),.out_end(),.out_last(decode_last),.busy(),.done(),
      .error(decode_error),.error_code(decode_code)
    );
    anvil_edge_special_splitter #(.MAX_SPAN_BYTES(MAX_PROMPT_BYTES)) raw_specials(
      .clk(clk),.rst_n(rst_n),.start(rst_n && state==FIRST_START),
      .config_valid(config_valid),.normalized_phase(1'b0),
      .cfg_table_bases(cfg_table_bases),.cfg_metadata(cfg_metadata),
      .cfg_table_counts(cfg_table_counts),
      .in_valid(rst_n && state==FIRST_INPUT),.in_ready(first_ready),
      .in_scalar(scalars[scalar_index]),.in_last(scalar_index+1==scalar_count),
      .out_valid(first_valid),.out_ready(first_accept),.out_value(first_value),
      .out_special(first_special),.out_boundary(first_boundary),.out_last(first_last),
      .busy(),.done(),.error(first_error),.error_code(first_code),
      .tbl_req_valid(requests[FIRST]),.tbl_req_ready(selected==FIRST && tbl_req_ready),
      .tbl_req_addr(addresses[FIRST*64+:64]),
      .tbl_rsp_valid(selected==FIRST && tbl_rsp_valid),
      .tbl_rsp_ready(responses_ready[FIRST]),.tbl_rsp_data(tbl_rsp_data),
      .tbl_rsp_error(tbl_rsp_error)
    );
    anvil_edge_normalizer #(.MAX_SCALARS(MAX_PROMPT_BYTES)) normalization(
      .clk(clk),.rst_n(rst_n),.start(rst_n && state==NORMALIZE_START),
      .config_valid(config_valid),.cfg_normalization(cfg_metadata[3*32+:32]),
      .cfg_ranges_base(cfg_table_bases[7*64+:64]),
      .cfg_decomposition_base(cfg_table_bases[13*64+:64]),
      .cfg_scalar_pool_base(cfg_table_bases[14*64+:64]),
      .cfg_composition_base(cfg_table_bases[15*64+:64]),
      .cfg_range_count(cfg_table_counts[7*32+:32]),
      .cfg_class_count(cfg_metadata[9*32+:32]),
      .cfg_decomposition_count(cfg_table_counts[13*32+:32]),
      .cfg_scalar_pool_count(cfg_table_counts[14*32+:32]),
      .cfg_composition_count(cfg_table_counts[15*32+:32]),
      .in_valid(rst_n && state==NORMALIZE_INPUT && first_valid),
      .in_ready(normal_ready),.in_scalar(first_value),.in_last(first_boundary),
      .out_valid(normal_valid),.out_ready(rst_n && state==NORMALIZE_OUTPUT && second_ready),
      .out_scalar(normal_scalar),.out_last(normal_last),.busy(),.done(),
      .error(normal_error),.error_code(normal_code),.tbl_req_valid(requests[NORMALIZE]),
      .tbl_req_ready(selected==NORMALIZE && tbl_req_ready),
      .tbl_req_addr(addresses[NORMALIZE*64+:64]),
      .tbl_rsp_valid(selected==NORMALIZE && tbl_rsp_valid),
      .tbl_rsp_ready(responses_ready[NORMALIZE]),.tbl_rsp_data(tbl_rsp_data),
      .tbl_rsp_error(tbl_rsp_error)
    );
    anvil_edge_special_splitter #(.MAX_SPAN_BYTES(MAX_PROMPT_BYTES)) normalized_specials(
      .clk(clk),.rst_n(rst_n),.start(rst_n && state==NORMALIZE_START),
      .config_valid(config_valid),.normalized_phase(1'b1),
      .cfg_table_bases(cfg_table_bases),.cfg_metadata(cfg_metadata),
      .cfg_table_counts(cfg_table_counts),
      .in_valid(rst_n && state==NORMALIZE_OUTPUT && normal_valid),
      .in_ready(second_ready),.in_scalar(normal_scalar),.in_last(normal_last),
      .out_valid(second_valid),.out_ready(second_accept),.out_value(second_value),
      .out_special(second_special),.out_boundary(second_boundary),.out_last(second_last),
      .busy(),.done(),.error(second_error),.error_code(second_code),
      .tbl_req_valid(requests[SECOND]),.tbl_req_ready(selected==SECOND && tbl_req_ready),
      .tbl_req_addr(addresses[SECOND*64+:64]),
      .tbl_rsp_valid(selected==SECOND && tbl_rsp_valid),
      .tbl_rsp_ready(responses_ready[SECOND]),.tbl_rsp_data(tbl_rsp_data),
      .tbl_rsp_error(tbl_rsp_error)
    );
    anvil_edge_text_bpe_span #(
      .MAX_SPAN_BYTES(MAX_PROMPT_BYTES),.MAX_SPAN_TOKENS(MAX_PROMPT_TOKENS),
      .MAX_PRETOKEN_BYTES(MAX_PRETOKEN_BYTES),.MAX_TAG_REGISTERS(MAX_TAG_REGISTERS)
    ) ordinary_text(
      .clk(clk),.rst_n(rst_n),.start(rst_n && state==SPAN_START),
      .config_valid(config_valid),.cfg_normalization(32'd0),
      .cfg_vocab_size(cfg_metadata[2*32+:32]),
      .cfg_max_pretoken_bytes(cfg_metadata[15*32+:32]),
      .cfg_ranges_base(cfg_table_bases[7*64+:64]),
      .cfg_decomposition_base(cfg_table_bases[13*64+:64]),
      .cfg_scalar_pool_base(cfg_table_bases[14*64+:64]),
      .cfg_composition_base(cfg_table_bases[15*64+:64]),
      .cfg_states_base(cfg_table_bases[8*64+:64]),
      .cfg_transitions_base(cfg_table_bases[9*64+:64]),
      .cfg_tag_ops_base(cfg_table_bases[11*64+:64]),
      .cfg_accepts_base(cfg_table_bases[12*64+:64]),
      .cfg_byte_map_base(cfg_table_bases[3*64+:64]),
      .cfg_merge_base(cfg_table_bases[4*64+:64]),
      .cfg_range_count(cfg_table_counts[7*32+:32]),
      .cfg_class_count(cfg_metadata[9*32+:32]),
      .cfg_decomposition_count(cfg_table_counts[13*32+:32]),
      .cfg_scalar_pool_count(cfg_table_counts[14*32+:32]),
      .cfg_composition_count(cfg_table_counts[15*32+:32]),
      .cfg_state_count(cfg_table_counts[8*32+:32]),
      .cfg_transition_count(cfg_table_counts[9*32+:32]),
      .cfg_tag_op_count(cfg_table_counts[11*32+:32]),
      .cfg_accept_count(cfg_table_counts[12*32+:32]),
      .cfg_start_state(cfg_metadata[10*32+:32]),
      .cfg_dead_state(cfg_metadata[11*32+:32]),
      .cfg_tag_register_count(cfg_metadata[12*32+:32]),
      .cfg_merge_count(cfg_table_counts[4*32+:32]),
      .in_valid(rst_n && state==SPAN_INPUT && second_valid),
      .in_ready(span_ready),.in_scalar(second_value),.in_last(second_boundary),
      .out_valid(span_valid),.out_ready(rst_n && state==SPAN_OUTPUT),
      .out_token_id(span_token),.out_last(span_last),.busy(),.done(),
      .error(span_error),.error_code(span_code),.tbl_req_valid(requests[SPAN]),
      .tbl_req_ready(selected==SPAN && tbl_req_ready),
      .tbl_req_addr(addresses[SPAN*64+:64]),
      .tbl_rsp_valid(selected==SPAN && tbl_rsp_valid),
      .tbl_rsp_ready(responses_ready[SPAN]),.tbl_rsp_data(tbl_rsp_data),
      .tbl_rsp_error(tbl_rsp_error)
    );
    always @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
        state<=IDLE; scalar_count<=0; scalar_index<=0; token_count<=0;
        output_index<=0; outer_last<=0; inner_last<=0; done_r<=0; code<=0;
        output_token<=0; output_last<=0;
      end else begin
        done_r<=0;
        if (active && decode_error) begin code<=decode_code; state<=FAILED; end
        else if (active && first_error) begin code<=first_code; state<=FAILED; end
        else if (active && normal_error) begin code<=normal_code; state<=FAILED; end
        else if (active && second_error) begin code<=second_code; state<=FAILED; end
        else if (active && span_error) begin code<=span_code; state<=FAILED; end
        else case (state)
          IDLE, CLOSED: if (start) begin
            if (!config_valid || cfg_metadata[2*32+:32]<256 ||
                cfg_metadata[2*32+:32]>262144 || cfg_metadata[5*32+:32]>1 ||
                (cfg_metadata[5*32+:32]!=0 &&
                 cfg_metadata[6*32+:32]>=cfg_metadata[2*32+:32])) begin
              code<=8'h06; state<=FAILED;
            end else begin
              scalar_count<=0; scalar_index<=0; output_index<=0;
              token_count<=cfg_metadata[5*32+:32];
              if (cfg_metadata[5*32+:32]!=0) tokens[0]<=cfg_metadata[6*32+:32];
              code<=0; state<=DECODE_START;
            end
          end
          DECODE_START: state<=DECODE;
          DECODE: if (decode_valid) begin
            if (scalar_count>=MAX_PROMPT_BYTES) begin code<=8'h30; state<=FAILED; end
            else begin
              scalars[scalar_count]<=decode_scalar; scalar_count<=scalar_count+1;
              if (decode_last) begin scalar_index<=0; state<=FIRST_START; end
            end
          end
          FIRST_START: state<=FIRST_INPUT;
          FIRST_INPUT: if (first_ready) begin
            if (scalar_index+1==scalar_count) state<=FIRST_DISPATCH;
            else scalar_index<=scalar_index+1;
          end
          FIRST_DISPATCH: if (first_valid) begin
            if (!first_special) state<=NORMALIZE_START;
            else if (token_count>=MAX_PROMPT_TOKENS) begin code<=8'h30; state<=FAILED; end
            else begin
              tokens[token_count]<=first_value; token_count<=token_count+1;
              if (first_last) begin output_index<=0; state<=EMIT_LOAD; end
            end
          end
          NORMALIZE_START: state<=NORMALIZE_INPUT;
          NORMALIZE_INPUT: if (first_valid && normal_ready && first_boundary) begin
            outer_last<=first_last; state<=NORMALIZE_OUTPUT;
          end
          NORMALIZE_OUTPUT: if (normal_valid && second_ready && normal_last)
            state<=SECOND_DISPATCH;
          SECOND_DISPATCH: if (second_valid) begin
            if (!second_special) state<=SPAN_START;
            else if (token_count>=MAX_PROMPT_TOKENS) begin code<=8'h30; state<=FAILED; end
            else begin
              tokens[token_count]<=second_value; token_count<=token_count+1;
              if (second_last) begin
                if (outer_last) begin output_index<=0; state<=EMIT_LOAD; end
                else state<=FIRST_DISPATCH;
              end
            end
          end
          SPAN_START: state<=SPAN_INPUT;
          SPAN_INPUT: if (second_valid && span_ready && second_boundary) begin
            inner_last<=second_last; state<=SPAN_OUTPUT;
          end
          SPAN_OUTPUT: if (span_valid) begin
            if (token_count>=MAX_PROMPT_TOKENS) begin code<=8'h30; state<=FAILED; end
            else begin
              tokens[token_count]<=span_token; token_count<=token_count+1;
              if (span_last) begin
                if (!inner_last) state<=SECOND_DISPATCH;
                else if (!outer_last) state<=FIRST_DISPATCH;
                else begin output_index<=0; state<=EMIT_LOAD; end
              end
            end
          end
          EMIT_LOAD: begin
            output_token<=tokens[output_index];
            output_last<=output_index+1==token_count;
            state<=EMIT;
          end
          EMIT: if (out_valid && out_ready) begin
            if (out_last) begin done_r<=1; state<=CLOSED; end
            else begin output_index<=output_index+1; state<=EMIT_LOAD; end
          end
          FAILED: state<=FAILED;
          default: begin code<=8'h12; state<=FAILED; end
        endcase
      end
    end
  end endgenerate
endmodule
