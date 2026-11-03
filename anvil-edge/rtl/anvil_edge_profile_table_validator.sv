module anvil_edge_profile_table_validator #(
  parameter integer MAX_TAG_REGISTERS=32,
  parameter [63:0] DDR_BASE=0,
  parameter [63:0] DDR_BYTES=64'h0000000100000000
) (
  input wire clk, rst_n, start, manifest_valid,
  input wire [1279:0] staged_segment_bases, staged_segment_bytes,
  input wire [1023:0] staged_metadata,
  input wire [511:0] staged_table_counts,
  output wire busy, done, valid_profile_tables, error,
  output wire [7:0] error_code,
  output wire ddr_req_valid,
  input wire ddr_req_ready,
  output wire [63:0] ddr_req_addr,
  input wire ddr_rsp_valid,
  output wire ddr_rsp_ready,
  input wire [31:0] ddr_rsp_rdata,
  input wire ddr_rsp_error
);
  localparam [4:0] IDLE=0, CONFIG_CHECK=1, SELECT_TABLE=2, RECORD_SETUP=3,
    READ_ISSUE=4, READ_WAIT=5, RECORD_EXTENTS=6, RECORD_CHECK=7,
    POLICY_SETUP=8, POLICY_CHECK=9, RECORD_NEXT=10, TABLE_NEXT=11,
    COMPLETE=12, FAILED=13;
  reg [4:0] state, after_read;
  reg [1279:0] bases, lengths;
  reg [511:0] counts;
  reg [31:0] class_count, tag_count, dead_state;
  reg [31:0] dead_first_transition;
  reg [31:0] record_index, policy_index, record_count, next_scalar;
  reg [4:0] segment_index, read_segment;
  reg [127:0] record_data;
  reg [63:0] previous_key;
  reg previous_valid;
  reg [64:0] first_end, second_end;
  reg [31:0] accept_priority, accept_policy;
  reg [63:0] read_offset;
  reg [5:0] read_words;
  reg [7:0] code;
  reg done_r;
  wire [31:0] w0=record_data[0+:32];
  wire [31:0] w1=record_data[32+:32];
  wire [31:0] w2=record_data[64+:32];
  wire [31:0] w3=record_data[96+:32];
  wire [31:0] transition_count=counts[288+:32];
  wire [31:0] accept_count=counts[384+:32];
  wire [31:0] operation_count=counts[352+:32];
  wire [31:0] state_count=counts[256+:32];
  wire [31:0] pool_count=counts[448+:32];
  wire [63:0] key=segment_index==19 ? {w0,w1} : {32'd0,w0};
  wire scalar0_valid=w0<=32'h10ffff && !(w0>=32'hd800 && w0<=32'hdfff);
  wire scalar1_valid=w1<=32'h10ffff && !(w1>=32'hd800 && w1<=32'hdfff);
  wire scalar2_valid=w2<=32'h10ffff && !(w2>=32'hd800 && w2<=32'hdfff);
  wire [64:0] dead_transition_end={33'd0,dead_first_transition}+
    {33'd0,class_count}+65'd1;
  wire reader_in_ready, reader_out_valid, reader_error;
  wire [1023:0] reader_data;
  wire [7:0] reader_code;
  reg record_legal;
  reg [31:0] selected_count;

  generate if (MAX_TAG_REGISTERS<32) begin : invalid_parameters
    initial $fatal(1, "ANVIL_EDGE_PROFILE_TABLE PARAMETER ERROR: at least 32 tags required");
  end endgenerate
  anvil_edge_boot_segment_reader #(.DDR_BASE(DDR_BASE),.DDR_BYTES(DDR_BYTES)) reader(
    .clk(clk),.rst_n(rst_n),.in_valid(rst_n && state==READ_ISSUE),
    .in_ready(reader_in_ready),.segment_base(bases[read_segment*64+:64]),
    .segment_bytes(lengths[read_segment*64+:64]),
    .byte_offset(read_offset),.word_count(read_words),
    .out_valid(reader_out_valid),.out_ready(rst_n && state==READ_WAIT),
    .data(reader_data),.response_error(reader_error),.error_code(reader_code),
    .ddr_req_valid(ddr_req_valid),.ddr_req_ready(ddr_req_ready),
    .ddr_req_addr(ddr_req_addr),.ddr_rsp_valid(ddr_rsp_valid),
    .ddr_rsp_ready(ddr_rsp_ready),.ddr_rsp_rdata(ddr_rsp_rdata),
    .ddr_rsp_error(ddr_rsp_error)
  );
  assign busy=rst_n && state!=IDLE && state!=COMPLETE && state!=FAILED;
  assign done=rst_n && done_r;
  assign valid_profile_tables=rst_n && state==COMPLETE;
  assign error=rst_n && state==FAILED;
  assign error_code=rst_n ? code : 0;

  always @* begin
    selected_count=0;
    if (segment_index>=11 && segment_index<=19)
      selected_count=counts[(segment_index-4)*32+:32];
    record_legal=0;
    case (segment_index)
      11: record_legal=scalar0_valid && scalar1_valid && w0<=w1 &&
        !(w0<32'hd800 && w1>=32'hd800) &&
        w0==next_scalar && w2<class_count && w3[31:10]==0;
      12: record_legal=w3==0 && first_end<={33'd0,transition_count} &&
        second_end<={33'd0,accept_count} && (record_index!=dead_state || w2==0);
      13: record_legal=w0<state_count && w3==0 &&
        first_end<={33'd0,operation_count} &&
        !({33'd0,record_index}>={33'd0,dead_first_transition} &&
          {33'd0,record_index}<dead_transition_end && (w0!=dead_state || w2!=0));
      15: record_legal=w0<=3 && w1<tag_count && w3==0 &&
        ((w0==3 && w2<tag_count) || (w0!=3 && w2==0));
      16: record_legal=w1<tag_count && w2<=1 && w3==0;
      17: record_legal=scalar0_valid && (!previous_valid || key>previous_key) &&
        w2!=0 && w3<=1 && first_end<={33'd0,pool_count};
      18: record_legal=scalar0_valid;
      19: record_legal=scalar0_valid && scalar1_valid && scalar2_valid &&
        w3==0 && (!previous_valid || key>previous_key);
      default: record_legal=0;
    endcase
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state<=IDLE; after_read<=IDLE; bases<=0; lengths<=0; counts<=0;
      class_count<=0; tag_count<=0; dead_state<=0; dead_first_transition<=0;
      record_index<=0; policy_index<=0; record_count<=0; next_scalar<=0;
      segment_index<=0; read_segment<=0; record_data<=0;
      previous_key<=0; previous_valid<=0; first_end<=0; second_end<=0;
      accept_priority<=0; accept_policy<=0; read_offset<=0; read_words<=0;
      code<=0; done_r<=0;
    end else begin
      done_r<=0;
      case (state)
        IDLE, COMPLETE: if (start) begin
          if (!manifest_valid) begin code<=8'h06; state<=FAILED; end
          else begin
            bases<=staged_segment_bases; lengths<=staged_segment_bytes;
            counts<=staged_table_counts;
            class_count<=staged_metadata[288+:32];
            tag_count<=staged_metadata[384+:32];
            dead_state<=staged_metadata[352+:32];
            dead_first_transition<=0; code<=0; state<=CONFIG_CHECK;
          end
        end
        CONFIG_CHECK: begin
          if (class_count==0 || tag_count==0 || tag_count>MAX_TAG_REGISTERS ||
              dead_state>=state_count || counts[224+:32]==0 ||
              transition_count==0) begin code<=8'h06; state<=FAILED; end
          else begin segment_index<=11; next_scalar<=0; state<=SELECT_TABLE; end
        end
        SELECT_TABLE: begin
          record_count<=selected_count; record_index<=0; previous_valid<=0;
          if (selected_count==0) state<=TABLE_NEXT;
          else state<=RECORD_SETUP;
        end
        RECORD_SETUP: begin
          read_segment<=segment_index;
          if (segment_index==18) begin
            read_offset<=64'd32+({32'd0,record_index} << 2); read_words<=1;
          end else begin
            read_offset<=64'd32+({32'd0,record_index} << 4); read_words<=4;
          end
          after_read<=RECORD_EXTENTS; state<=READ_ISSUE;
        end
        READ_ISSUE: if (reader_in_ready) state<=READ_WAIT;
        READ_WAIT: if (reader_out_valid) begin
          if (reader_error) begin code<=reader_code; state<=FAILED; end
          else begin record_data<=reader_data[127:0]; state<=after_read; end
        end
        RECORD_EXTENTS: begin
          if (segment_index==12) begin
            first_end<={33'd0,w0}+{33'd0,class_count}+65'd1;
            second_end<={33'd0,w1}+{33'd0,w2};
          end else first_end<={33'd0,w1}+{33'd0,w2};
          state<=RECORD_CHECK;
        end
        RECORD_CHECK: begin
          if (!record_legal) begin code<=8'h06; state<=FAILED; end
          else begin
            previous_key<=key; previous_valid<=1;
            if (segment_index==11) begin
              if (w1==32'hd7ff) next_scalar<=32'he000;
              else next_scalar<=w1+1'b1;
            end
            if (segment_index==12 && record_index==dead_state)
              dead_first_transition<=w0;
            if (segment_index==16 && record_index!=0) begin
              accept_priority<=w0; accept_policy<=w2; policy_index<=0; state<=POLICY_SETUP;
            end else state<=RECORD_NEXT;
          end
        end
        POLICY_SETUP: begin
          read_segment<=16; read_offset<=64'd32+({32'd0,policy_index} << 4);
          read_words<=4; after_read<=POLICY_CHECK; state<=READ_ISSUE;
        end
        POLICY_CHECK: begin
          if (w0==accept_priority && w2!=accept_policy) begin code<=8'h06; state<=FAILED; end
          else if (policy_index+1==record_index) state<=RECORD_NEXT;
          else begin policy_index<=policy_index+1'b1; state<=POLICY_SETUP; end
        end
        RECORD_NEXT: begin
          if (record_index+1==record_count) state<=TABLE_NEXT;
          else begin record_index<=record_index+1'b1; state<=RECORD_SETUP; end
        end
        TABLE_NEXT: begin
          if (segment_index==11 && next_scalar!=32'h110000) begin
            code<=8'h06; state<=FAILED;
          end else if (segment_index==19) begin done_r<=1; state<=COMPLETE; end
          else begin
            if (segment_index==13) segment_index<=15;
            else segment_index<=segment_index+1'b1;
            state<=SELECT_TABLE;
          end
        end
        FAILED: state<=FAILED;
        default: begin code<=8'h06; state<=FAILED; end
      endcase
    end
  end
endmodule
