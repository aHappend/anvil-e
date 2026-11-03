module anvil_edge_manifest_validator #(
  parameter NUM_LAYERS=24, HIDDEN_SIZE=896, INTERMEDIATE_SIZE=4864,
  NUM_Q_HEADS=14, NUM_KV_HEADS=2, HEAD_DIM=64, GROUP_SIZE=128,
  AWQ_BITS=4, VOCAB_SIZE=151936, MAX_SEQ_LEN=32768,
  parameter integer MAX_TOKEN_BYTES=4096,
  parameter integer MAX_PRETOKEN_BYTES=4096,
  parameter integer MAX_TAG_REGISTERS=32,
  parameter integer MAX_DFA_CLASSES=4096,
  parameter [63:0] DDR_BASE=0,
  parameter [63:0] DDR_BYTES=64'h0000000100000000
) (
  input wire clk, rst_n, start,
  input wire [223:0] staged_config_words,
  input wire [1279:0] staged_segment_bases, staged_segment_bytes,
  output wire busy, done, valid_manifest, error,
  output wire [7:0] error_code,
  output wire [1023:0] staged_metadata,
  output wire [511:0] staged_table_counts,
  output wire ddr_req_valid,
  input wire ddr_req_ready,
  output wire [63:0] ddr_req_addr,
  input wire ddr_rsp_valid,
  output wire ddr_rsp_ready,
  input wire [31:0] ddr_rsp_rdata,
  input wire ddr_rsp_error
);
  localparam [63:0] DIRECTORY_COUNT=64'd28*NUM_LAYERS+64'd4;
  localparam [31:0] ACTIVATION_STRIDE=
    HIDDEN_SIZE>INTERMEDIATE_SIZE ? HIDDEN_SIZE : INTERMEDIATE_SIZE;
  anvil_edge_parameters #(
    NUM_LAYERS,HIDDEN_SIZE,INTERMEDIATE_SIZE,NUM_Q_HEADS,NUM_KV_HEADS,
    HEAD_DIM,GROUP_SIZE,AWQ_BITS,VOCAB_SIZE,MAX_SEQ_LEN
  ) parameters_ok();
  generate if (MAX_TOKEN_BYTES<1 || MAX_PRETOKEN_BYTES<1 ||
               MAX_TAG_REGISTERS<32 || MAX_DFA_CLASSES<1 ||
               DIRECTORY_COUNT>64'hffffffff) begin : invalid_parameters
    initial $fatal(1, "ANVIL_EDGE_MANIFEST PARAMETER ERROR: invalid table capacity");
    assign busy=0; assign done=0; assign valid_manifest=0;
    assign error=0; assign error_code=0;
    assign staged_metadata=0; assign staged_table_counts=0;
    assign ddr_req_valid=0; assign ddr_req_addr=0; assign ddr_rsp_ready=0;
  end else begin : validator
    localparam [3:0] IDLE=0, CONFIG=1, GEOMETRY_ISSUE=2, GEOMETRY_WAIT=3,
      GEOMETRY_CHECK=4, METADATA_ISSUE=5, METADATA_WAIT=6, METADATA_CHECK=7,
      HEADER_SELECT=8, HEADER_ISSUE=9, HEADER_WAIT=10, HEADER_EXTENT=11,
      HEADER_CHECK=12, FINAL_CHECK=13, COMPLETE=14, FAILED=15;
    reg [3:0] state;
    reg [1279:0] bases, lengths;
    reg [223:0] configuration;
    reg [1023:0] metadata;
    reg [511:0] table_counts;
    reg [511:0] geometry;
    reg [255:0] header;
    reg [4:0] segment_index;
    reg [31:0] expected_record_bytes;
    reg [2:0] record_shift;
    reg [63:0] data_bytes;
    reg [64:0] expected_length;
    reg done_r;
    reg [7:0] code;
    wire reader_in_ready, reader_out_valid, reader_error;
    wire [1023:0] reader_data;
    wire [7:0] reader_code;
    wire issue=rst_n && (state==GEOMETRY_ISSUE ||
      state==METADATA_ISSUE || state==HEADER_ISSUE);
    wire waiting=state==GEOMETRY_WAIT || state==METADATA_WAIT || state==HEADER_WAIT;
    wire [4:0] read_segment=state==GEOMETRY_ISSUE ? 5'd0 :
      (state==METADATA_ISSUE ? 5'd4 : segment_index);
    wire [5:0] read_words=state==GEOMETRY_ISSUE ? 6'd16 :
      (state==METADATA_ISSUE ? 6'd32 : 6'd8);
    wire [31:0] active_vocab=configuration[160+:32];
    wire [31:0] eos_id=configuration[32+:32];
    wire [31:0] profile_id=configuration[128+:32];
    wire [31:0] header_record_count=header[96+:32];
    wire [63:0] header_data_bytes=header[128+:64];
    wire [63:0] selected_length=lengths[segment_index*64+:64];
    wire geometry_ok=
      geometry[0+:32]==1 && geometry[32+:32]==NUM_LAYERS &&
      geometry[64+:32]==HIDDEN_SIZE && geometry[96+:32]==INTERMEDIATE_SIZE &&
      geometry[128+:32]==NUM_Q_HEADS && geometry[160+:32]==NUM_KV_HEADS &&
      geometry[192+:32]==HEAD_DIM && geometry[224+:32]==GROUP_SIZE &&
      geometry[256+:32]==4 && geometry[288+:32]==VOCAB_SIZE &&
      geometry[320+:32]==MAX_SEQ_LEN && geometry[352+:32]==ACTIVATION_STRIDE &&
      geometry[384+:32]==profile_id && geometry[416+:96]==0;

    anvil_edge_boot_segment_reader #(.DDR_BASE(DDR_BASE),.DDR_BYTES(DDR_BYTES)) reader(
      .clk(clk),.rst_n(rst_n),.in_valid(issue),.in_ready(reader_in_ready),
      .segment_base(bases[read_segment*64+:64]),
      .segment_bytes(lengths[read_segment*64+:64]),
      .byte_offset(64'd0),.word_count(read_words),
      .out_valid(reader_out_valid),.out_ready(rst_n && waiting),
      .data(reader_data),.response_error(reader_error),.error_code(reader_code),
      .ddr_req_valid(ddr_req_valid),.ddr_req_ready(ddr_req_ready),
      .ddr_req_addr(ddr_req_addr),.ddr_rsp_valid(ddr_rsp_valid),
      .ddr_rsp_ready(ddr_rsp_ready),.ddr_rsp_rdata(ddr_rsp_rdata),
      .ddr_rsp_error(ddr_rsp_error)
    );
    assign busy=rst_n && state!=IDLE && state!=COMPLETE && state!=FAILED;
    assign done=rst_n && done_r;
    assign valid_manifest=rst_n && state==COMPLETE;
    assign error=rst_n && state==FAILED;
    assign error_code=rst_n ? code : 0;
    assign staged_metadata=valid_manifest ? metadata : 0;
    assign staged_table_counts=valid_manifest ? table_counts : 0;

    always @* begin
      expected_record_bytes=16;
      record_shift=4;
      case (segment_index)
        1: begin expected_record_bytes=48; record_shift=0; end
        6: begin expected_record_bytes=1; record_shift=0; end
        7,18: begin expected_record_bytes=4; record_shift=2; end
        10: begin expected_record_bytes=8; record_shift=3; end
        default: begin end
      endcase
    end

    always @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
        state<=IDLE; bases<=0; lengths<=0; configuration<=0; metadata<=0;
        table_counts<=0; geometry<=0; header<=0; segment_index<=0;
        data_bytes<=0; expected_length<=0; done_r<=0; code<=0;
      end else begin
        done_r<=0;
        if (waiting && reader_out_valid && reader_error) begin
          code<=reader_code; state<=FAILED;
        end else case (state)
          IDLE, COMPLETE: if (start) begin
            bases<=staged_segment_bases; lengths<=staged_segment_bytes;
            configuration<=staged_config_words; metadata<=0; table_counts<=0;
            code<=0; state<=CONFIG;
          end
          CONFIG: begin
            if (configuration[0+:32]<4 ||
                configuration[64+:32]>MAX_SEQ_LEN || configuration[96+:32]>1 ||
                profile_id<1 || profile_id>4 ||
                active_vocab<256 || active_vocab>262144 ||
                active_vocab>VOCAB_SIZE || eos_id>=active_vocab) begin
              code<=8'h01; state<=FAILED;
            end else if (lengths[0+:64]!=64 || lengths[256+:64]!=128) begin
              code<=8'h05; state<=FAILED;
            end else state<=GEOMETRY_ISSUE;
          end
          GEOMETRY_ISSUE: if (reader_in_ready) state<=GEOMETRY_WAIT;
          GEOMETRY_WAIT: if (reader_out_valid) begin
            geometry<=reader_data[511:0]; state<=GEOMETRY_CHECK;
          end
          GEOMETRY_CHECK: begin
            if (!geometry_ok) begin code<=8'h05; state<=FAILED; end
            else state<=METADATA_ISSUE;
          end
          METADATA_ISSUE: if (reader_in_ready) state<=METADATA_WAIT;
          METADATA_WAIT: if (reader_out_valid) begin
            metadata<=reader_data; state<=METADATA_CHECK;
          end
          METADATA_CHECK: begin
            if ((metadata[0+:32]!=1 && metadata[0+:32]!=2) ||
                metadata[32+:32]<1 ||
                metadata[32+:32]>3 || metadata[64+:32]!=active_vocab ||
                metadata[96+:32]>4 || metadata[128+:32]>2 ||
                metadata[160+:32]>1 ||
                (metadata[160+:32]==0 && metadata[192+:32]!=0) ||
                (metadata[160+:32]==1 && metadata[192+:32]>=active_vocab) ||
                metadata[224+:32]!=eos_id ||
                metadata[288+:32]==0 || metadata[288+:32]>MAX_DFA_CLASSES ||
                metadata[384+:32]==0 || metadata[384+:32]>MAX_TAG_REGISTERS ||
                metadata[448+:32]==0 || metadata[448+:32]>MAX_TOKEN_BYTES ||
                metadata[480+:32]==0 || metadata[480+:32]>MAX_PRETOKEN_BYTES ||
                (metadata[0+:32]==1 && metadata[768+:64]!=0) ||
                metadata[832+:192]!=0) begin
              code<=8'h06; state<=FAILED;
            end else begin segment_index<=1; state<=HEADER_SELECT; end
          end
          HEADER_SELECT: begin
            if (segment_index==2) begin segment_index<=5; state<=HEADER_SELECT; end
            else state<=HEADER_ISSUE;
          end
          HEADER_ISSUE: if (reader_in_ready) state<=HEADER_WAIT;
          HEADER_WAIT: if (reader_out_valid) begin
            header<=reader_data[255:0]; state<=HEADER_EXTENT;
          end
          HEADER_EXTENT: begin
            if (segment_index==1)
              data_bytes<=({32'd0,header_record_count} << 5)+
                          ({32'd0,header_record_count} << 4);
            else data_bytes<={32'd0,header_record_count} << record_shift;
            expected_length<=65'd32+{1'b0,header_data_bytes};
            state<=HEADER_CHECK;
          end
          HEADER_CHECK: begin
            if (header[0+:32]!=32'h334c4254 || header[32+:32]!=1 ||
                header[64+:32]!=expected_record_bytes ||
                header[192+:64]!=0 || header_data_bytes!=data_bytes ||
                expected_length[64] || expected_length!={1'b0,selected_length} ||
                (segment_index==1 && header_record_count!=DIRECTORY_COUNT) ||
                (segment_index==5 && header_record_count!=active_vocab) ||
                (segment_index==6 && header_record_count==0) ||
                (segment_index==7 && header_record_count!=256)) begin
              if (segment_index==1) code<=8'h05;
              else code<=8'h06;
              state<=FAILED;
            end else begin
              if (segment_index>=5)
                table_counts[(segment_index-4)*32+:32]<=header_record_count;
              if (segment_index==19) state<=FINAL_CHECK;
              else begin segment_index<=segment_index+1'b1; state<=HEADER_SELECT; end
            end
          end
          FINAL_CHECK: begin
            if (table_counts[160+:32]==0 ||
                metadata[416+:32]>=table_counts[160+:32] ||
                table_counts[224+:32]==0 || table_counts[256+:32]==0 ||
                metadata[320+:32]>=table_counts[256+:32] ||
                metadata[352+:32]>=table_counts[256+:32]) begin
              code<=8'h06; state<=FAILED;
            end else begin done_r<=1; state<=COMPLETE; end
          end
          FAILED: state<=FAILED;
          default: begin code<=8'h06; state<=FAILED; end
        endcase
      end
    end
  end endgenerate
endmodule
