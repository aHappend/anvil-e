module anvil_edge_image_loader #(
  parameter VOCAB_SIZE=151936,
  parameter MAX_SEQ_LEN=32768,
  parameter integer MAX_SEGMENTS=32,
  parameter integer FLASH_ADDRESS_BYTES=3,
  parameter [63:0] FLASH_CAPACITY_BYTES=64'd16777216,
  parameter integer SPI_CLOCK_HALF_PERIOD=2,
  parameter [63:0] IMAGE_BASE=0,
  parameter [63:0] DDR_BASE=0,
  parameter [63:0] DDR_BYTES=64'h0000000100000000
) (
  input wire clk, rst_n, start,
  input wire spi_miso,
  output wire spi_mosi, spi_sck, spi_cs_n,
  output wire ddr_req_valid,
  input wire ddr_req_ready,
  output wire ddr_req_write,
  output wire [63:0] ddr_req_addr,
  output wire [31:0] ddr_req_wdata,
  output wire [3:0] ddr_req_wstrb,
  input wire ddr_rsp_valid,
  output wire ddr_rsp_ready,
  input wire [31:0] ddr_rsp_rdata,
  input wire ddr_rsp_error,
  output wire image_loaded, busy, done, error,
  output wire [7:0] error_code,
  output wire [223:0] staged_config_words,
  output wire [1279:0] staged_segment_bases, staged_segment_bytes
);
  localparam [64:0] DDR_END={1'b0,DDR_BASE}+{1'b0,DDR_BYTES};
  generate if (VOCAB_SIZE<1 || VOCAB_SIZE>64'd4294967295 ||
               MAX_SEQ_LEN<1 || MAX_SEQ_LEN>16777215 || MAX_SEGMENTS<32 ||
               (FLASH_ADDRESS_BYTES!=3 && FLASH_ADDRESS_BYTES!=4) ||
               FLASH_CAPACITY_BYTES==0 || FLASH_CAPACITY_BYTES>64'd4294967296 ||
               (FLASH_ADDRESS_BYTES==3 && FLASH_CAPACITY_BYTES>64'd16777216) ||
               IMAGE_BASE>=FLASH_CAPACITY_BYTES || IMAGE_BASE[1:0]!=0 ||
               SPI_CLOCK_HALF_PERIOD<1 ||
               DDR_BASE[1:0]!=0 || DDR_BYTES[1:0]!=0 ||
               DDR_BYTES==0 || DDR_END[64]) begin : invalid_parameters
    initial $fatal(1, "ANVIL_EDGE_IMAGE PARAMETER ERROR: capacity, address mode, geometry or window");
    assign spi_mosi=0; assign spi_sck=0; assign spi_cs_n=1;
    assign ddr_req_valid=0; assign ddr_req_write=0; assign ddr_req_addr=0;
    assign ddr_req_wdata=0; assign ddr_req_wstrb=0; assign ddr_rsp_ready=0;
    assign image_loaded=0; assign busy=0; assign done=0;
    assign error=0; assign error_code=0;
    assign staged_config_words=0;
    assign staged_segment_bases=0; assign staged_segment_bytes=0;
  end else begin : loader
    localparam [4:0] IDLE=0, HEADER_REQUEST=1, HEADER_READ=2, HEADER_CHECK=3,
      REST_REQUEST=4, CONFIG_READ=5, CONFIG_RECORD_CHECK=6, CONFIG_CHECK=7,
      DESCRIPTOR_READ=8, DESCRIPTOR_KIND=9, DESCRIPTOR_ENDS=10,
      DESCRIPTOR_FLASH=11, DESCRIPTOR_CHECK=12, DESCRIPTOR_PAIRS=13,
      DESCRIPTOR_SAVE=14, ALL_DESCRIPTORS=15, PAYLOAD_SELECT=16,
      PAYLOAD_SETUP=17, PAYLOAD_REQUEST=18, PAYLOAD_BYTE=19,
      CRC_STEP=20, BYTE_DONE=21, WRITE_REQUEST=22, WRITE_RESPONSE=23,
      CRC_CHECK=24, LOADED=25, FAILED=26;
    reg [4:0] state;
    reg [31:0] header [0:7];
    reg [31:0] config_words [0:6];
    reg [31:0] descriptor [0:9];
    reg [63:0] segment_bases [0:19];
    reg [63:0] segment_lengths [0:19];
    reg [63:0] segment_ends [0:19];
    reg [63:0] flash_offsets [0:19];
    reg [63:0] flash_ends [0:19];
    reg [31:0] payload_crcs [0:19];
    reg [4:0] descriptor_order [0:MAX_SEGMENTS-1];
    reg [31:0] word_buffer, config_offset, config_value;
    reg [1:0] byte_lane;
    reg [2:0] header_word, config_record;
    reg config_value_word;
    reg [6:0] config_seen;
    reg [19:0] segments_seen;
    reg [4:0] descriptor_number, canonical_index, pair_index;
    reg [3:0] descriptor_word;
    reg [64:0] candidate_ddr_end, candidate_flash_end;
    reg [65:0] candidate_absolute_start, candidate_absolute_end;
    reg [4:0] payload_number, payload_kind;
    reg [63:0] flash_address, flash_bytes, payload_bytes_seen;
    reg [63:0] write_address;
    reg [31:0] payload_crc, crc_value;
    reg [2:0] crc_bit;
    reg payload_last_byte;
    reg [3:0] write_strobes;
    reg done_r;
    reg [7:0] code;
    reg config_offset_valid, config_value_legal;
    reg [2:0] config_index;
    reg descriptor_kind_valid;
    reg [4:0] descriptor_kind_index;
    wire [63:0] candidate_base={descriptor[3],descriptor[2]};
    wire [63:0] candidate_length={descriptor[5],descriptor[4]};
    wire [63:0] candidate_offset={descriptor[7],descriptor[6]};
    wire [65:0] absolute_header_end={2'b0,IMAGE_BASE}+{34'd0,header[3]};
    wire [31:0] assembled_word={flash_data,word_buffer[23:0]};
    wire [31:0] next_crc=(crc_value >> 1) ^
      (crc_value[0] ? 32'hedb88320 : 32'd0);
    wire flash_ready, flash_data_valid, flash_data_ready, flash_data_last;
    wire [7:0] flash_data;
    wire flash_error;
    wire flash_request=rst_n &&
      (state==HEADER_REQUEST || state==REST_REQUEST || state==PAYLOAD_REQUEST);
    wire [63:0] request_address=state==HEADER_REQUEST ? IMAGE_BASE : flash_address;
    wire [63:0] request_bytes=state==HEADER_REQUEST ? 64'd32 : flash_bytes;
    wire active=rst_n && state!=IDLE && state!=LOADED && state!=FAILED;

    anvil_edge_spi_reader #(
      .FLASH_ADDRESS_BYTES(FLASH_ADDRESS_BYTES),
      .FLASH_CAPACITY_BYTES(FLASH_CAPACITY_BYTES),
      .CLOCK_HALF_PERIOD(SPI_CLOCK_HALF_PERIOD)
    ) flash_reader(
      .clk(clk),.rst_n(rst_n),.req_valid(flash_request),.req_ready(flash_ready),
      .req_address(request_address),.req_bytes(request_bytes),
      .data_valid(flash_data_valid),.data_ready(flash_data_ready),
      .data(flash_data),.data_last(flash_data_last),
      .busy(),.done(),.error(flash_error),.error_code(),
      .spi_miso(spi_miso),.spi_mosi(spi_mosi),.spi_sck(spi_sck),
      .spi_cs_n(spi_cs_n)
    );
    assign flash_data_ready=rst_n && (state==HEADER_READ || state==CONFIG_READ ||
      state==DESCRIPTOR_READ || state==PAYLOAD_BYTE);
    assign image_loaded=rst_n && state==LOADED;
    assign busy=active;
    assign done=rst_n && done_r;
    assign error=rst_n && state==FAILED;
    assign error_code=rst_n ? code : 0;
    assign ddr_req_valid=rst_n && state==WRITE_REQUEST;
    assign ddr_req_write=ddr_req_valid;
    assign ddr_req_addr=rst_n ? write_address : 0;
    assign ddr_req_wdata=ddr_req_valid ? word_buffer : 0;
    assign ddr_req_wstrb=ddr_req_valid ? write_strobes : 0;
    assign ddr_rsp_ready=rst_n && state==WRITE_RESPONSE;
    for (genvar c=0;c<7;c=c+1) begin : config_outputs
      assign staged_config_words[c*32+:32]=image_loaded ? config_words[c] : 0;
    end
    for (genvar s=0;s<20;s=s+1) begin : segment_outputs
      assign staged_segment_bases[s*64+:64]=image_loaded ? segment_bases[s] : 0;
      assign staged_segment_bytes[s*64+:64]=image_loaded ? segment_lengths[s] : 0;
    end

    always @* begin
      config_offset_valid=1;
      config_value_legal=1;
      config_index=0;
      case (config_offset)
        32'h04: begin config_index=0; config_value_legal=config_value>=4; end
        32'h08: config_index=1;
        32'h0c: begin config_index=2; config_value_legal=config_value<=MAX_SEQ_LEN; end
        32'h10: begin config_index=3; config_value_legal=config_value<=1; end
        32'h14: begin
          config_index=4; config_value_legal=config_value>=1 && config_value<=4;
        end
        32'h18: begin
          config_index=5;
          config_value_legal=config_value>=256 && config_value<=262144 &&
                             config_value<=VOCAB_SIZE;
        end
        32'h24: config_index=6;
        default: begin config_offset_valid=0; config_value_legal=0; end
      endcase
      descriptor_kind_valid=0;
      descriptor_kind_index=0;
      if (descriptor[0]>=32'h100 && descriptor[0]<=32'h103) begin
        descriptor_kind_valid=1;
        descriptor_kind_index=descriptor[0]-32'h100;
      end else if (descriptor[0]>=32'h200 && descriptor[0]<=32'h20f) begin
        descriptor_kind_valid=1;
        descriptor_kind_index=descriptor[0]-32'h200+32'd4;
      end
    end

    always @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
        state<=IDLE; word_buffer<=0; config_offset<=0; config_value<=0;
        byte_lane<=0; header_word<=0; config_record<=0; config_value_word<=0;
        config_seen<=0; segments_seen<=0;
        descriptor_number<=0; canonical_index<=0; pair_index<=0; descriptor_word<=0;
        candidate_ddr_end<=0; candidate_flash_end<=0;
        candidate_absolute_start<=0; candidate_absolute_end<=0;
        payload_number<=0; payload_kind<=0; flash_address<=0; flash_bytes<=0;
        payload_bytes_seen<=0; write_address<=0; payload_crc<=0; crc_value<=0;
        crc_bit<=0; payload_last_byte<=0; write_strobes<=0; done_r<=0; code<=0;
      end else begin
        done_r<=0;
        if (active && flash_error) begin code<=8'h02; state<=FAILED; end
        else case (state)
          IDLE, LOADED: if (start) begin
            word_buffer<=0; byte_lane<=0; header_word<=0;
            config_record<=0; config_value_word<=0; config_seen<=0;
            segments_seen<=0; descriptor_number<=0; descriptor_word<=0;
            payload_number<=0; code<=0; state<=HEADER_REQUEST;
          end
          HEADER_REQUEST: if (flash_ready) state<=HEADER_READ;
          HEADER_READ: if (flash_data_valid && flash_data_ready) begin
            if (flash_data_last!=(header_word==7 && byte_lane==3)) begin
              code<=8'h01; state<=FAILED;
            end else if (byte_lane==3) begin
              header[header_word]<=assembled_word; word_buffer<=0; byte_lane<=0;
              if (header_word==7) state<=HEADER_CHECK;
              else header_word<=header_word+1'b1;
            end else begin
              word_buffer[byte_lane*8+:8]<=flash_data;
              byte_lane<=byte_lane+1'b1;
            end
          end
          HEADER_CHECK: begin
            if (header[0]!=32'h4c564e41 || header[1]!=32'h33474445 ||
                header[2]!=1 || header[3]!=888 || header[4]<1 || header[4]>4 ||
                header[5]!=20 || header[5]>MAX_SEGMENTS || header[6]!=7 ||
                header[7]!=0 || absolute_header_end[65:64]!=0 ||
                absolute_header_end>{2'b0,FLASH_CAPACITY_BYTES}) begin
              code<=8'h01; state<=FAILED;
            end else begin
              flash_address<=IMAGE_BASE+64'd32;
              flash_bytes<=64'd856; state<=REST_REQUEST;
            end
          end
          REST_REQUEST: if (flash_ready) state<=CONFIG_READ;
          CONFIG_READ: if (flash_data_valid && flash_data_ready) begin
            if (flash_data_last) begin code<=8'h01; state<=FAILED; end
            else if (byte_lane==3) begin
              byte_lane<=0; word_buffer<=0;
              if (!config_value_word) begin
                config_offset<=assembled_word; config_value_word<=1;
              end else begin
                config_value<=assembled_word; config_value_word<=0;
                state<=CONFIG_RECORD_CHECK;
              end
            end else begin
              word_buffer[byte_lane*8+:8]<=flash_data; byte_lane<=byte_lane+1'b1;
            end
          end
          CONFIG_RECORD_CHECK: begin
            if (!config_offset_valid || !config_value_legal || config_seen[config_index]) begin
              code<=8'h01; state<=FAILED;
            end else begin
              config_words[config_index]<=config_value;
              config_seen[config_index]<=1;
              if (config_record==6) state<=CONFIG_CHECK;
              else begin config_record<=config_record+1'b1; state<=CONFIG_READ; end
            end
          end
          CONFIG_CHECK: begin
            if (config_seen!=7'h7f || config_words[1]>=config_words[5] ||
                config_words[4]!=header[4]) begin
              code<=8'h01; state<=FAILED;
            end else begin descriptor_word<=0; state<=DESCRIPTOR_READ; end
          end
          DESCRIPTOR_READ: if (flash_data_valid && flash_data_ready) begin
            if (flash_data_last!=(descriptor_number==19 &&
                                 descriptor_word==9 && byte_lane==3)) begin
              code<=8'h02; state<=FAILED;
            end else if (byte_lane==3) begin
              descriptor[descriptor_word]<=assembled_word; word_buffer<=0; byte_lane<=0;
              if (descriptor_word==9) state<=DESCRIPTOR_KIND;
              else descriptor_word<=descriptor_word+1'b1;
            end else begin
              word_buffer[byte_lane*8+:8]<=flash_data; byte_lane<=byte_lane+1'b1;
            end
          end
          DESCRIPTOR_KIND: begin
            if (!descriptor_kind_valid || segments_seen[descriptor_kind_index] ||
                descriptor[1]!=0 || descriptor[9]!=0) begin
              code<=8'h02; state<=FAILED;
            end else begin canonical_index<=descriptor_kind_index; state<=DESCRIPTOR_ENDS; end
          end
          DESCRIPTOR_ENDS: begin
            candidate_ddr_end<={1'b0,candidate_base}+{1'b0,candidate_length};
            candidate_flash_end<={1'b0,candidate_offset}+{1'b0,candidate_length};
            state<=DESCRIPTOR_FLASH;
          end
          DESCRIPTOR_FLASH: begin
            candidate_absolute_start<={2'b0,IMAGE_BASE}+{2'b0,candidate_offset};
            candidate_absolute_end<={2'b0,IMAGE_BASE}+{1'b0,candidate_flash_end};
            state<=DESCRIPTOR_CHECK;
          end
          DESCRIPTOR_CHECK: begin
            if (candidate_length==0 || candidate_base[1:0]!=0 ||
                candidate_offset[1:0]!=0 ||
                (canonical_index!=6 && candidate_length[1:0]!=0) ||
                candidate_ddr_end[64] || candidate_flash_end[64] ||
                candidate_base<DDR_BASE || candidate_ddr_end>DDR_END ||
                candidate_offset<{32'd0,header[3]} ||
                candidate_absolute_start[65:64]!=0 || candidate_absolute_end[65:64]!=0 ||
                candidate_absolute_end>{2'b0,FLASH_CAPACITY_BYTES}) begin
              code<=8'h02; state<=FAILED;
            end else begin pair_index<=0; state<=DESCRIPTOR_PAIRS; end
          end
          DESCRIPTOR_PAIRS: begin
            if (segments_seen[pair_index] &&
                ((candidate_base<segment_ends[pair_index] &&
                  segment_bases[pair_index]<candidate_ddr_end) ||
                 (candidate_offset<flash_ends[pair_index] &&
                  flash_offsets[pair_index]<candidate_flash_end))) begin
              code<=8'h02; state<=FAILED;
            end else if (pair_index==19) state<=DESCRIPTOR_SAVE;
            else pair_index<=pair_index+1'b1;
          end
          DESCRIPTOR_SAVE: begin
            segment_bases[canonical_index]<=candidate_base;
            segment_lengths[canonical_index]<=candidate_length;
            segment_ends[canonical_index]<=candidate_ddr_end[63:0];
            flash_offsets[canonical_index]<=candidate_offset;
            flash_ends[canonical_index]<=candidate_flash_end[63:0];
            payload_crcs[canonical_index]<=descriptor[8];
            descriptor_order[descriptor_number]<=canonical_index;
            segments_seen[canonical_index]<=1;
            if (descriptor_number==19) state<=ALL_DESCRIPTORS;
            else begin
              descriptor_number<=descriptor_number+1'b1;
              descriptor_word<=0; state<=DESCRIPTOR_READ;
            end
          end
          ALL_DESCRIPTORS: begin
            if (segments_seen!=20'hfffff) begin code<=8'h02; state<=FAILED; end
            else begin payload_number<=0; state<=PAYLOAD_SELECT; end
          end
          PAYLOAD_SELECT: begin
            payload_kind<=descriptor_order[payload_number]; state<=PAYLOAD_SETUP;
          end
          PAYLOAD_SETUP: begin
            flash_address<=IMAGE_BASE+flash_offsets[payload_kind];
            flash_bytes<=segment_lengths[payload_kind];
            payload_crc<=payload_crcs[payload_kind];
            write_address<=segment_bases[payload_kind];
            payload_bytes_seen<=0; byte_lane<=0; word_buffer<=0;
            crc_value<=32'hffffffff; crc_bit<=0; write_strobes<=0;
            state<=PAYLOAD_REQUEST;
          end
          PAYLOAD_REQUEST: if (flash_ready) state<=PAYLOAD_BYTE;
          PAYLOAD_BYTE: if (flash_data_valid && flash_data_ready) begin
            if (flash_data_last!=(payload_bytes_seen+1==flash_bytes)) begin
              code<=8'h02; state<=FAILED;
            end else begin
              word_buffer[byte_lane*8+:8]<=flash_data;
              payload_bytes_seen<=payload_bytes_seen+1;
              payload_last_byte<=flash_data_last;
              crc_value<=crc_value^{24'd0,flash_data}; crc_bit<=0; state<=CRC_STEP;
            end
          end
          CRC_STEP: begin
            crc_value<=next_crc;
            if (crc_bit==7) state<=BYTE_DONE;
            else crc_bit<=crc_bit+1'b1;
          end
          BYTE_DONE: begin
            if (byte_lane==3 || payload_last_byte) begin
              case (byte_lane)
                0: write_strobes<=4'b0001;
                1: write_strobes<=4'b0011;
                2: write_strobes<=4'b0111;
                3: write_strobes<=4'b1111;
              endcase
              state<=WRITE_REQUEST;
            end else begin byte_lane<=byte_lane+1'b1; state<=PAYLOAD_BYTE; end
          end
          WRITE_REQUEST: if (ddr_req_valid && ddr_req_ready) state<=WRITE_RESPONSE;
          WRITE_RESPONSE: if (ddr_rsp_valid && ddr_rsp_ready) begin
            if (ddr_rsp_error) begin code<=8'h04; state<=FAILED; end
            else if (payload_last_byte) state<=CRC_CHECK;
            else begin
              write_address<=write_address+64'd4;
              byte_lane<=0; word_buffer<=0; state<=PAYLOAD_BYTE;
            end
          end
          CRC_CHECK: begin
            if ((~crc_value)!=payload_crc) begin code<=8'h03; state<=FAILED; end
            else if (payload_number==19) begin done_r<=1; state<=LOADED; end
            else begin payload_number<=payload_number+1'b1; state<=PAYLOAD_SELECT; end
          end
          FAILED: state<=FAILED;
          default: begin code<=8'h01; state<=FAILED; end
        endcase
      end
    end
  end endgenerate
endmodule
