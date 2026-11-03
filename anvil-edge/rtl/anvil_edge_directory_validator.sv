module anvil_edge_directory_validator #(
  parameter NUM_LAYERS=24, HIDDEN_SIZE=896, INTERMEDIATE_SIZE=4864,
  NUM_Q_HEADS=14, NUM_KV_HEADS=2, HEAD_DIM=64, GROUP_SIZE=128,
  AWQ_BITS=4, VOCAB_SIZE=151936, MAX_SEQ_LEN=32768,
  parameter [63:0] DDR_BASE=0,
  parameter [63:0] DDR_BYTES=64'h0000000100000000
) (
  input wire clk, rst_n, start,
  input wire [223:0] staged_config_words,
  input wire [1279:0] staged_segment_bases, staged_segment_bytes,
  output wire busy, done, valid_directory, error,
  output wire [7:0] error_code,
  output wire ddr_req_valid,
  input wire ddr_req_ready,
  output wire [63:0] ddr_req_addr,
  input wire ddr_rsp_valid,
  output wire ddr_rsp_ready,
  input wire [31:0] ddr_rsp_rdata,
  input wire ddr_rsp_error
);
  localparam [63:0] DIRECTORY_COUNT=64'd28*NUM_LAYERS+64'd4;
  localparam integer SAFE_G=GROUP_SIZE>0 ? GROUP_SIZE : 1;
  localparam [31:0] H_GROUPS=HIDDEN_SIZE/SAFE_G;
  localparam [31:0] I_GROUPS=INTERMEDIATE_SIZE/SAFE_G;
  localparam [31:0] T=NUM_KV_HEADS*HEAD_DIM;
  localparam [31:0] A=HIDDEN_SIZE>INTERMEDIATE_SIZE ?
    HIDDEN_SIZE : INTERMEDIATE_SIZE;
  localparam [64:0] DIRECTORY_BYTES=65'd32+65'd48*DIRECTORY_COUNT;
  anvil_edge_parameters #(
    NUM_LAYERS,HIDDEN_SIZE,INTERMEDIATE_SIZE,NUM_Q_HEADS,NUM_KV_HEADS,
    HEAD_DIM,GROUP_SIZE,AWQ_BITS,VOCAB_SIZE,MAX_SEQ_LEN
  ) parameters_ok();
  generate if (DIRECTORY_COUNT>64'hffffffff) begin : invalid_parameters
    initial $fatal(1, "ANVIL_EDGE_DIRECTORY PARAMETER ERROR: directory count overflows u32");
    assign busy=0; assign done=0; assign valid_directory=0;
    assign error=0; assign error_code=0;
    assign ddr_req_valid=0; assign ddr_req_addr=0; assign ddr_rsp_ready=0;
  end else begin : validator
    localparam [5:0] IDLE=0, CONFIG_CHECK=1, ACTIVE_MULTIPLY=2,
      ACTIVE_WAIT=3, HEADER_ISSUE=4, HEADER_WAIT=5, HEADER_CHECK=6,
      RECORD_ADDRESS=7, RECORD_ISSUE=8, RECORD_WAIT=9, RECORD_CHECK=10,
      EXTENT_MULTIPLY=11, EXTENT_WAIT=12, REGION_END=13, REGION_CHECK=14,
      PAIR_ADDRESS=15, PAIR_ISSUE=16, PAIR_WAIT=17, PAIR_END=18,
      PAIR_CHECK=19, TENSOR_SETUP=20, TENSOR_ISSUE=21, TENSOR_WAIT=22,
      TENSOR_CHECK=23, RECORD_NEXT=24, WRITABLE_SETUP=25,
      ZERO_ISSUE=26, ZERO_WAIT=27, ZERO_CHECK=28,
      HOLE_SETUP=29, HOLE_ADDRESS=30, HOLE_ISSUE=31,
      HOLE_WAIT=32, HOLE_END=33, HOLE_CHECK=34, HOLE_DECIDE=35,
      HOLE_NEXT=36, COMPLETE=37, FAILED=38;
    reg [5:0] state;
    reg [63:0] directory_base, directory_bytes;
    reg [63:0] immutable_base, immutable_bytes, writable_base, writable_bytes;
    reg [31:0] active_vocab;
    reg [31:0] record_index, other_index;
    reg [383:0] current_record, other_record;
    reg [255:0] header;
    reg [95:0] previous_key;
    reg previous_valid;
    reg [64:0] record_address, region_end, other_end;
    reg [64:0] expected_extent, active_embedding_bytes;
    reg [63:0] scan_offset, scan_end, scan_base, scan_bytes;
    reg [63:0] hole_cursor, next_region_start, next_region_end;
    reg zero_writable;
    reg [31:0] read_word;
    reg done_r;
    reg [7:0] code;
    reg legal_key, writable_key;
    reg [31:0] expected_rows, expected_columns, expected_format;
    reg [31:0] projection_inputs, projection_outputs, projection_groups;
    wire [31:0] kind=current_record[0+:32];
    wire [31:0] layer=current_record[32+:32];
    wire [31:0] projection=current_record[64+:32];
    wire [31:0] storage_kind=current_record[96+:32];
    wire [63:0] region_offset=current_record[128+:64];
    wire [31:0] rows=current_record[192+:32];
    wire [31:0] columns=current_record[224+:32];
    wire [31:0] format=current_record[256+:32];
    wire [31:0] permissions=current_record[288+:32];
    wire [63:0] extent=current_record[320+:64];
    wire [95:0] current_key={kind,layer,projection};
    wire [63:0] other_offset=other_record[128+:64];
    wire [63:0] other_extent=other_record[320+:64];
    wire same_storage=other_record[96+:32]==storage_kind;
    wire reader_in_ready, reader_out_valid, reader_error;
    wire [1023:0] reader_data;
    wire [7:0] reader_code;
    wire issue=rst_n && (state==HEADER_ISSUE || state==RECORD_ISSUE ||
      state==PAIR_ISSUE || state==TENSOR_ISSUE || state==ZERO_ISSUE ||
      state==HOLE_ISSUE);
    wire waiting=state==HEADER_WAIT || state==RECORD_WAIT ||
      state==PAIR_WAIT || state==TENSOR_WAIT || state==ZERO_WAIT ||
      state==HOLE_WAIT;
    wire data_read=state==TENSOR_ISSUE || state==ZERO_ISSUE;
    wire [63:0] reader_base=data_read ? scan_base : directory_base;
    wire [63:0] reader_bytes=data_read ? scan_bytes : directory_bytes;
    wire [63:0] reader_offset=data_read ? scan_offset :
      (state==HEADER_ISSUE ? 64'd0 : record_address[63:0]);
    wire [5:0] reader_words=data_read ? 6'd1 :
      (state==HEADER_ISSUE ? 6'd8 : 6'd12);
    wire multiply_ready, multiply_valid;
    wire signed [127:0] multiply_product;
    wire active_multiply=state==ACTIVE_MULTIPLY || state==ACTIVE_WAIT;
    wire signed [63:0] multiply_a=active_multiply ?
      $signed({32'd0,active_vocab}) : $signed({32'd0,rows});
    wire signed [63:0] multiply_b=active_multiply ?
      HIDDEN_SIZE : $signed({32'd0,columns});

    anvil_edge_boot_segment_reader #(.DDR_BASE(DDR_BASE),.DDR_BYTES(DDR_BYTES)) reader(
      .clk(clk),.rst_n(rst_n),.in_valid(issue),.in_ready(reader_in_ready),
      .segment_base(reader_base),.segment_bytes(reader_bytes),
      .byte_offset(reader_offset),.word_count(reader_words),
      .out_valid(reader_out_valid),.out_ready(rst_n && waiting),
      .data(reader_data),.response_error(reader_error),.error_code(reader_code),
      .ddr_req_valid(ddr_req_valid),.ddr_req_ready(ddr_req_ready),
      .ddr_req_addr(ddr_req_addr),.ddr_rsp_valid(ddr_rsp_valid),
      .ddr_rsp_ready(ddr_rsp_ready),.ddr_rsp_rdata(ddr_rsp_rdata),
      .ddr_rsp_error(ddr_rsp_error)
    );
    anvil_edge_signed_multiplier #(.WIDTH(64)) multiply(
      .clk(clk),.rst_n(rst_n),
      .in_valid(rst_n && (state==ACTIVE_MULTIPLY || state==EXTENT_MULTIPLY)),
      .in_ready(multiply_ready),.operand_a(multiply_a),.operand_b(multiply_b),
      .out_valid(multiply_valid),
      .out_ready(rst_n && (state==ACTIVE_WAIT || state==EXTENT_WAIT)),
      .product(multiply_product)
    );
    assign busy=rst_n && state!=IDLE && state!=COMPLETE && state!=FAILED;
    assign done=rst_n && done_r;
    assign valid_directory=rst_n && state==COMPLETE;
    assign error=rst_n && state==FAILED;
    assign error_code=rst_n ? code : 0;

    always @* begin
      legal_key=0; writable_key=0;
      expected_rows=0; expected_columns=0; expected_format=0;
      projection_inputs=HIDDEN_SIZE; projection_outputs=HIDDEN_SIZE;
      projection_groups=H_GROUPS;
      case (projection)
        1,2: projection_outputs=T;
        4,5: projection_outputs=INTERMEDIATE_SIZE;
        6: begin projection_inputs=INTERMEDIATE_SIZE; projection_groups=I_GROUPS; end
        default: begin end
      endcase
      case (kind)
        0: begin
          legal_key=layer==0 && projection==0;
          expected_rows=VOCAB_SIZE; expected_columns=HIDDEN_SIZE; expected_format=1;
        end
        1,2,3: begin
          legal_key=layer<NUM_LAYERS && projection<=6;
          expected_rows=kind==1 ? projection_inputs : projection_groups;
          expected_columns=kind==3 ? projection_outputs : projection_outputs>>3;
          expected_format=kind==3 ? 1 : 2;
        end
        4: begin
          legal_key=layer<NUM_LAYERS && projection<=2;
          expected_rows=1; expected_columns=projection_outputs; expected_format=1;
        end
        5,6: begin
          legal_key=layer<NUM_LAYERS && projection==0;
          expected_rows=1; expected_columns=HIDDEN_SIZE; expected_format=1;
        end
        7: begin
          legal_key=layer==0 && projection==0;
          expected_rows=1; expected_columns=HIDDEN_SIZE; expected_format=1;
        end
        8: begin
          legal_key=layer==0 && projection==0; writable_key=1;
          expected_rows=15; expected_columns=A; expected_format=3;
        end
        9,10: begin
          legal_key=layer<NUM_LAYERS && projection==0; writable_key=1;
          expected_rows=MAX_SEQ_LEN; expected_columns=T; expected_format=3;
        end
        11: begin
          legal_key=layer==0 && projection==0;
          expected_rows=MAX_SEQ_LEN; expected_columns=HEAD_DIM; expected_format=4;
        end
        default: begin end
      endcase
    end

    always @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
        state<=IDLE; directory_base<=0; directory_bytes<=0;
        immutable_base<=0; immutable_bytes<=0; writable_base<=0; writable_bytes<=0;
        active_vocab<=0; record_index<=0; other_index<=0;
        current_record<=0; other_record<=0; header<=0;
        previous_key<=0; previous_valid<=0;
        record_address<=0; region_end<=0; other_end<=0; expected_extent<=0;
        active_embedding_bytes<=0; scan_offset<=0; scan_end<=0;
        scan_base<=0; scan_bytes<=0; hole_cursor<=0;
        next_region_start<=0; next_region_end<=0; zero_writable<=0;
        read_word<=0; done_r<=0; code<=0;
      end else begin
        done_r<=0;
        if (waiting && reader_out_valid && reader_error) begin
          if (reader_code==8'h04) code<=8'h04;
          else code<=8'h05;
          state<=FAILED;
        end else case (state)
          IDLE, COMPLETE: if (start) begin
            directory_base<=staged_segment_bases[64+:64];
            directory_bytes<=staged_segment_bytes[64+:64];
            immutable_base<=staged_segment_bases[128+:64];
            immutable_bytes<=staged_segment_bytes[128+:64];
            writable_base<=staged_segment_bases[192+:64];
            writable_bytes<=staged_segment_bytes[192+:64];
            active_vocab<=staged_config_words[160+:32];
            previous_valid<=0; record_index<=0; code<=0;
            state<=CONFIG_CHECK;
          end
          CONFIG_CHECK: begin
            if (active_vocab<256 || active_vocab>262144 || active_vocab>VOCAB_SIZE ||
                {1'b0,directory_bytes}!=DIRECTORY_BYTES ||
                immutable_bytes==0 || immutable_bytes[1:0]!=0 ||
                writable_bytes==0 || writable_bytes[1:0]!=0) begin
              code<=8'h05; state<=FAILED;
            end else state<=ACTIVE_MULTIPLY;
          end
          ACTIVE_MULTIPLY: if (multiply_ready) state<=ACTIVE_WAIT;
          ACTIVE_WAIT: if (multiply_valid) begin
            if (multiply_product[127:63]!=0) begin code<=8'h05; state<=FAILED; end
            else begin
              active_embedding_bytes<={multiply_product[62:0],2'b00};
              state<=HEADER_ISSUE;
            end
          end
          HEADER_ISSUE: if (reader_in_ready) state<=HEADER_WAIT;
          HEADER_WAIT: if (reader_out_valid) begin
            header<=reader_data[255:0]; state<=HEADER_CHECK;
          end
          HEADER_CHECK: begin
            if (header[0+:32]!=32'h334c4254 || header[32+:32]!=1 ||
                header[64+:32]!=48 || header[96+:32]!=DIRECTORY_COUNT ||
                {1'b0,header[128+:64]}!=DIRECTORY_BYTES-65'd32 ||
                header[192+:64]!=0) begin code<=8'h05; state<=FAILED; end
            else state<=RECORD_ADDRESS;
          end
          RECORD_ADDRESS: begin
            record_address<=65'd32+({33'd0,record_index} << 5)+
              ({33'd0,record_index} << 4);
            state<=RECORD_ISSUE;
          end
          RECORD_ISSUE: if (reader_in_ready) state<=RECORD_WAIT;
          RECORD_WAIT: if (reader_out_valid) begin
            current_record<=reader_data[383:0]; state<=RECORD_CHECK;
          end
          RECORD_CHECK: begin
            if (!legal_key || (previous_valid && current_key<=previous_key) ||
                rows!=expected_rows || columns!=expected_columns ||
                format!=expected_format || region_offset[1:0]!=0 || extent==0 ||
                storage_kind!=(writable_key ? 32'h103 : 32'h102) ||
                permissions!=(writable_key ? 32'd3 : 32'd1)) begin
              code<=8'h05; state<=FAILED;
            end else state<=EXTENT_MULTIPLY;
          end
          EXTENT_MULTIPLY: if (multiply_ready) state<=EXTENT_WAIT;
          EXTENT_WAIT: if (multiply_valid) begin
            if (multiply_product[127:63]!=0) begin code<=8'h05; state<=FAILED; end
            else begin
              expected_extent<={multiply_product[62:0],2'b00};
              state<=REGION_END;
            end
          end
          REGION_END: begin
            region_end<={1'b0,region_offset}+{1'b0,extent}; state<=REGION_CHECK;
          end
          REGION_CHECK: begin
            if (expected_extent!={1'b0,extent} || region_end[64] ||
                region_end>{1'b0,(writable_key ? writable_bytes : immutable_bytes)}) begin
              code<=8'h05; state<=FAILED;
            end else begin
              other_index<=0;
              if (record_index==0) state<=TENSOR_SETUP;
              else state<=PAIR_ADDRESS;
            end
          end
          PAIR_ADDRESS: begin
            record_address<=65'd32+({33'd0,other_index} << 5)+
              ({33'd0,other_index} << 4);
            state<=PAIR_ISSUE;
          end
          PAIR_ISSUE: if (reader_in_ready) state<=PAIR_WAIT;
          PAIR_WAIT: if (reader_out_valid) begin
            other_record<=reader_data[383:0]; state<=PAIR_END;
          end
          PAIR_END: begin
            other_end<={1'b0,other_offset}+{1'b0,other_extent};
            state<=PAIR_CHECK;
          end
          PAIR_CHECK: begin
            if (same_storage && ({1'b0,region_offset}<other_end) &&
                ({1'b0,other_offset}<region_end)) begin
              code<=8'h05; state<=FAILED;
            end else if (other_index+1==record_index) state<=TENSOR_SETUP;
            else begin other_index<=other_index+1'b1; state<=PAIR_ADDRESS; end
          end
          TENSOR_SETUP: begin
            if (format!=1) state<=RECORD_NEXT;
            else begin
              scan_base<=immutable_base; scan_bytes<=immutable_bytes;
              scan_offset<=region_offset; scan_end<=region_end[63:0];
              state<=TENSOR_ISSUE;
            end
          end
          TENSOR_ISSUE: if (reader_in_ready) state<=TENSOR_WAIT;
          TENSOR_WAIT: if (reader_out_valid) begin
            read_word<=reader_data[31:0]; state<=TENSOR_CHECK;
          end
          TENSOR_CHECK: begin
            if (read_word[31:16]!=0 || read_word[14:10]==5'b11111 ||
                (kind==3 && read_word[15] && read_word[14:0]!=0) ||
                (kind==0 &&
                 {1'b0,(scan_offset-region_offset)}>=active_embedding_bytes &&
                 read_word!=0)) begin
              code<=8'h05; state<=FAILED;
            end else if (scan_offset+64'd4==scan_end) state<=RECORD_NEXT;
            else begin scan_offset<=scan_offset+64'd4; state<=TENSOR_ISSUE; end
          end
          RECORD_NEXT: begin
            previous_key<=current_key; previous_valid<=1;
            if ({32'd0,record_index}+64'd1==DIRECTORY_COUNT) state<=WRITABLE_SETUP;
            else begin record_index<=record_index+1'b1; state<=RECORD_ADDRESS; end
          end
          WRITABLE_SETUP: begin
            scan_base<=writable_base; scan_bytes<=writable_bytes;
            scan_offset<=0; scan_end<=writable_bytes; zero_writable<=1;
            state<=ZERO_ISSUE;
          end
          ZERO_ISSUE: if (reader_in_ready) state<=ZERO_WAIT;
          ZERO_WAIT: if (reader_out_valid) begin
            read_word<=reader_data[31:0]; state<=ZERO_CHECK;
          end
          ZERO_CHECK: begin
            if (read_word!=0) begin code<=8'h05; state<=FAILED; end
            else if (scan_offset+64'd4==scan_end) begin
              if (zero_writable) begin hole_cursor<=0; state<=HOLE_SETUP; end
              else state<=HOLE_NEXT;
            end else begin scan_offset<=scan_offset+64'd4; state<=ZERO_ISSUE; end
          end
          HOLE_SETUP: begin
            if (hole_cursor==immutable_bytes) begin done_r<=1; state<=COMPLETE; end
            else begin
              other_index<=0; next_region_start<=immutable_bytes;
              next_region_end<=immutable_bytes; state<=HOLE_ADDRESS;
            end
          end
          HOLE_ADDRESS: begin
            record_address<=65'd32+({33'd0,other_index} << 5)+
              ({33'd0,other_index} << 4);
            state<=HOLE_ISSUE;
          end
          HOLE_ISSUE: if (reader_in_ready) state<=HOLE_WAIT;
          HOLE_WAIT: if (reader_out_valid) begin
            other_record<=reader_data[383:0]; state<=HOLE_END;
          end
          HOLE_END: begin
            other_end<={1'b0,other_offset}+{1'b0,other_extent}; state<=HOLE_CHECK;
          end
          HOLE_CHECK: begin
            if (other_record[96+:32]==32'h102 && other_offset>=hole_cursor &&
                other_offset<next_region_start) begin
              next_region_start<=other_offset; next_region_end<=other_end[63:0];
            end
            if ({32'd0,other_index}+64'd1==DIRECTORY_COUNT) state<=HOLE_DECIDE;
            else begin other_index<=other_index+1'b1; state<=HOLE_ADDRESS; end
          end
          HOLE_DECIDE: begin
            if (next_region_start==hole_cursor) state<=HOLE_NEXT;
            else begin
              scan_base<=immutable_base; scan_bytes<=immutable_bytes;
              scan_offset<=hole_cursor; scan_end<=next_region_start;
              zero_writable<=0; state<=ZERO_ISSUE;
            end
          end
          HOLE_NEXT: begin hole_cursor<=next_region_end; state<=HOLE_SETUP; end
          FAILED: state<=FAILED;
          default: begin code<=8'h05; state<=FAILED; end
        endcase
      end
    end
  end endgenerate
endmodule
