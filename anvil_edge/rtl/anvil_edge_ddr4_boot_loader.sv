module anvil_edge_ddr4_boot_loader #(
  parameter NUM_LAYERS=24, HIDDEN_SIZE=896, INTERMEDIATE_SIZE=4864,
  NUM_Q_HEADS=14, NUM_KV_HEADS=2, HEAD_DIM=64, GROUP_SIZE=128,
  AWQ_BITS=4, VOCAB_SIZE=151936, MAX_SEQ_LEN=32768,
  parameter integer MAX_SEGMENTS=32,
  parameter integer FLASH_ADDRESS_BYTES=3,
  parameter [63:0] FLASH_CAPACITY_BYTES=64'd16777216,
  parameter integer SPI_CLOCK_HALF_PERIOD=2,
  parameter [63:0] IMAGE_BASE=0,
  parameter integer MAX_TOKEN_BYTES=4096,
  parameter integer MAX_PRETOKEN_BYTES=4096,
  parameter integer MAX_TAG_REGISTERS=32,
  parameter integer MAX_DFA_CLASSES=4096,
  parameter integer MAX_TRIE_NODES=1048576,
  parameter integer MAX_SPECIAL_RECORDS=262144,
  parameter [63:0] DDR_BASE=0,
  parameter [63:0] DDR_BYTES=64'h0000000100000000
) (
  input wire clk, rst_n, start, ddr_cal_done,
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
  output wire boot_done, busy, error,
  output wire [7:0] error_code,
  output wire [223:0] committed_config_words,
  output wire [1279:0] committed_segment_bases, committed_segment_bytes,
  output wire [1023:0] committed_metadata,
  output wire [511:0] committed_table_counts
);
  localparam [3:0] RESET_EPOCH=0, CALIBRATION=1, LOAD_START=2, LOAD_WAIT=3,
    MANIFEST_START=4, MANIFEST_WAIT=5, DIRECTORY_START=6, DIRECTORY_WAIT=7,
    TOKENS_START=8, TOKENS_WAIT=9, PROFILE_START=10, PROFILE_WAIT=11,
    TRIE_START=12, TRIE_WAIT=13, READY=14, FAILED=15;
  localparam integer LOADER=0, MANIFEST=1, DIRECTORY=2, TOKENS=3, PROFILE=4, TRIE=5;
  reg [3:0] state;
  reg epoch_enabled;
  (* async_reg="true" *) reg calibration_meta, calibration_sync;
  reg [7:0] code;
  reg [223:0] active_config;
  reg [1279:0] active_bases, active_lengths;
  reg [1023:0] active_metadata;
  reg [511:0] active_counts;
  reg [2:0] selected;
  wire epoch_rst_n=rst_n && epoch_enabled;
  wire [5:0] requests, response_ready, stage_error;
  wire [383:0] addresses;
  wire [47:0] stage_codes;
  wire [223:0] staged_config;
  wire [1279:0] staged_bases, staged_lengths;
  wire [1023:0] staged_metadata;
  wire [511:0] staged_counts;
  wire loaded, manifest_valid, directory_valid, tokens_valid, profile_valid, trie_valid;
  wire loader_write;
  wire [31:0] loader_wdata;
  wire [3:0] loader_wstrb;
  wire active_stage=rst_n && state!=RESET_EPOCH && state!=CALIBRATION &&
    state!=READY && state!=FAILED;
  wire [5:0] stage_ready, stage_rsp_valid;

  for (genvar i=0;i<6;i=i+1) begin : stage_channels
    assign stage_ready[i]=active_stage && selected==i && ddr_req_ready;
    assign stage_rsp_valid[i]=active_stage && selected==i && ddr_rsp_valid;
  end
  assign boot_done=rst_n && state==READY;
  assign busy=rst_n && state!=READY && state!=FAILED;
  assign error=rst_n && state==FAILED;
  assign error_code=rst_n ? code : 0;
  assign committed_config_words=boot_done ? active_config : 0;
  assign committed_segment_bases=boot_done ? active_bases : 0;
  assign committed_segment_bytes=boot_done ? active_lengths : 0;
  assign committed_metadata=boot_done ? active_metadata : 0;
  assign committed_table_counts=boot_done ? active_counts : 0;
  assign ddr_req_valid=active_stage && requests[selected];
  assign ddr_req_write=active_stage && selected==LOADER && loader_write;
  assign ddr_req_addr=active_stage ? addresses[selected*64+:64] : 0;
  assign ddr_req_wdata=active_stage && selected==LOADER ? loader_wdata : 0;
  assign ddr_req_wstrb=active_stage && selected==LOADER ? loader_wstrb : 0;
  assign ddr_rsp_ready=active_stage && response_ready[selected];

  always @* begin
    selected=LOADER;
    case (state)
      MANIFEST_START, MANIFEST_WAIT: selected=MANIFEST;
      DIRECTORY_START, DIRECTORY_WAIT: selected=DIRECTORY;
      TOKENS_START, TOKENS_WAIT: selected=TOKENS;
      PROFILE_START, PROFILE_WAIT: selected=PROFILE;
      TRIE_START, TRIE_WAIT: selected=TRIE;
      default: begin end
    endcase
  end

  anvil_edge_image_loader #(
    .VOCAB_SIZE(VOCAB_SIZE),.MAX_SEQ_LEN(MAX_SEQ_LEN),.MAX_SEGMENTS(MAX_SEGMENTS),
    .FLASH_ADDRESS_BYTES(FLASH_ADDRESS_BYTES),.FLASH_CAPACITY_BYTES(FLASH_CAPACITY_BYTES),
    .SPI_CLOCK_HALF_PERIOD(SPI_CLOCK_HALF_PERIOD),.IMAGE_BASE(IMAGE_BASE),
    .DDR_BASE(DDR_BASE),.DDR_BYTES(DDR_BYTES)
  ) image_loader(
    .clk(clk),.rst_n(epoch_rst_n),.start(rst_n && state==LOAD_START),
    .spi_miso(spi_miso),.spi_mosi(spi_mosi),.spi_sck(spi_sck),.spi_cs_n(spi_cs_n),
    .ddr_req_valid(requests[LOADER]),.ddr_req_ready(stage_ready[LOADER]),
    .ddr_req_write(loader_write),.ddr_req_addr(addresses[LOADER*64+:64]),
    .ddr_req_wdata(loader_wdata),.ddr_req_wstrb(loader_wstrb),
    .ddr_rsp_valid(stage_rsp_valid[LOADER]),.ddr_rsp_ready(response_ready[LOADER]),
    .ddr_rsp_rdata(ddr_rsp_rdata),.ddr_rsp_error(ddr_rsp_error),
    .image_loaded(loaded),.busy(),.done(),.error(stage_error[LOADER]),
    .error_code(stage_codes[LOADER*8+:8]),.staged_config_words(staged_config),
    .staged_segment_bases(staged_bases),.staged_segment_bytes(staged_lengths)
  );
  anvil_edge_manifest_validator #(
    NUM_LAYERS,HIDDEN_SIZE,INTERMEDIATE_SIZE,NUM_Q_HEADS,NUM_KV_HEADS,
    HEAD_DIM,GROUP_SIZE,AWQ_BITS,VOCAB_SIZE,MAX_SEQ_LEN,
    MAX_TOKEN_BYTES,MAX_PRETOKEN_BYTES,MAX_TAG_REGISTERS,MAX_DFA_CLASSES,
    DDR_BASE,DDR_BYTES
  ) manifest(
    .clk(clk),.rst_n(epoch_rst_n),.start(rst_n && state==MANIFEST_START),
    .staged_config_words(staged_config),.staged_segment_bases(staged_bases),
    .staged_segment_bytes(staged_lengths),.busy(),.done(),
    .valid_manifest(manifest_valid),.error(stage_error[MANIFEST]),
    .error_code(stage_codes[MANIFEST*8+:8]),.staged_metadata(staged_metadata),
    .staged_table_counts(staged_counts),
    .ddr_req_valid(requests[MANIFEST]),.ddr_req_ready(stage_ready[MANIFEST]),
    .ddr_req_addr(addresses[MANIFEST*64+:64]),
    .ddr_rsp_valid(stage_rsp_valid[MANIFEST]),.ddr_rsp_ready(response_ready[MANIFEST]),
    .ddr_rsp_rdata(ddr_rsp_rdata),.ddr_rsp_error(ddr_rsp_error)
  );
  anvil_edge_directory_validator #(
    NUM_LAYERS,HIDDEN_SIZE,INTERMEDIATE_SIZE,NUM_Q_HEADS,NUM_KV_HEADS,
    HEAD_DIM,GROUP_SIZE,AWQ_BITS,VOCAB_SIZE,MAX_SEQ_LEN,DDR_BASE,DDR_BYTES
  ) directory(
    .clk(clk),.rst_n(epoch_rst_n),.start(rst_n && state==DIRECTORY_START),
    .staged_config_words(staged_config),.staged_segment_bases(staged_bases),
    .staged_segment_bytes(staged_lengths),.busy(),.done(),
    .valid_directory(directory_valid),.error(stage_error[DIRECTORY]),
    .error_code(stage_codes[DIRECTORY*8+:8]),
    .ddr_req_valid(requests[DIRECTORY]),.ddr_req_ready(stage_ready[DIRECTORY]),
    .ddr_req_addr(addresses[DIRECTORY*64+:64]),
    .ddr_rsp_valid(stage_rsp_valid[DIRECTORY]),.ddr_rsp_ready(response_ready[DIRECTORY]),
    .ddr_rsp_rdata(ddr_rsp_rdata),.ddr_rsp_error(ddr_rsp_error)
  );
  anvil_edge_token_table_validator #(
    .VOCAB_SIZE(VOCAB_SIZE),.DDR_BASE(DDR_BASE),.DDR_BYTES(DDR_BYTES)
  ) tokens(
    .clk(clk),.rst_n(epoch_rst_n),.start(rst_n && state==TOKENS_START),
    .manifest_valid(manifest_valid),.staged_config_words(staged_config),
    .staged_segment_bases(staged_bases),.staged_segment_bytes(staged_lengths),
    .staged_metadata(staged_metadata),.staged_table_counts(staged_counts),
    .busy(),.done(),.valid_tokens(tokens_valid),.error(stage_error[TOKENS]),
    .error_code(stage_codes[TOKENS*8+:8]),
    .ddr_req_valid(requests[TOKENS]),.ddr_req_ready(stage_ready[TOKENS]),
    .ddr_req_addr(addresses[TOKENS*64+:64]),
    .ddr_rsp_valid(stage_rsp_valid[TOKENS]),.ddr_rsp_ready(response_ready[TOKENS]),
    .ddr_rsp_rdata(ddr_rsp_rdata),.ddr_rsp_error(ddr_rsp_error)
  );
  anvil_edge_profile_table_validator #(
    .MAX_TAG_REGISTERS(MAX_TAG_REGISTERS),.DDR_BASE(DDR_BASE),.DDR_BYTES(DDR_BYTES)
  ) profile(
    .clk(clk),.rst_n(epoch_rst_n),.start(rst_n && state==PROFILE_START),
    .manifest_valid(manifest_valid),.staged_segment_bases(staged_bases),
    .staged_segment_bytes(staged_lengths),.staged_metadata(staged_metadata),
    .staged_table_counts(staged_counts),.busy(),.done(),
    .valid_profile_tables(profile_valid),.error(stage_error[PROFILE]),
    .error_code(stage_codes[PROFILE*8+:8]),
    .ddr_req_valid(requests[PROFILE]),.ddr_req_ready(stage_ready[PROFILE]),
    .ddr_req_addr(addresses[PROFILE*64+:64]),
    .ddr_rsp_valid(stage_rsp_valid[PROFILE]),.ddr_rsp_ready(response_ready[PROFILE]),
    .ddr_rsp_rdata(ddr_rsp_rdata),.ddr_rsp_error(ddr_rsp_error)
  );
  anvil_edge_special_trie_validator #(
    .MAX_TRIE_NODES(MAX_TRIE_NODES),.MAX_SPECIAL_RECORDS(MAX_SPECIAL_RECORDS),
    .MAX_TOKEN_BYTES(MAX_TOKEN_BYTES),.DDR_BASE(DDR_BASE),.DDR_BYTES(DDR_BYTES)
  ) special_trie(
    .clk(clk),.rst_n(epoch_rst_n),.start(rst_n && state==TRIE_START),
    .manifest_valid(manifest_valid),.tokens_valid(tokens_valid),
    .staged_segment_bases(staged_bases),.staged_segment_bytes(staged_lengths),
    .staged_metadata(staged_metadata),.staged_table_counts(staged_counts),
    .busy(),.done(),.valid_special_trie(trie_valid),.error(stage_error[TRIE]),
    .error_code(stage_codes[TRIE*8+:8]),
    .ddr_req_valid(requests[TRIE]),.ddr_req_ready(stage_ready[TRIE]),
    .ddr_req_addr(addresses[TRIE*64+:64]),
    .ddr_rsp_valid(stage_rsp_valid[TRIE]),.ddr_rsp_ready(response_ready[TRIE]),
    .ddr_rsp_rdata(ddr_rsp_rdata),.ddr_rsp_error(ddr_rsp_error)
  );

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin calibration_meta<=0; calibration_sync<=0; end
    else begin calibration_meta<=ddr_cal_done; calibration_sync<=calibration_meta; end
  end
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state<=RESET_EPOCH; epoch_enabled<=0; code<=0; active_config<=0;
      active_bases<=0; active_lengths<=0; active_metadata<=0; active_counts<=0;
    end else if (active_stage && stage_error[selected]) begin
      code<=stage_codes[selected*8+:8]; epoch_enabled<=0; state<=FAILED;
    end else case (state)
      RESET_EPOCH: begin epoch_enabled<=1; state<=CALIBRATION; end
      CALIBRATION: if (calibration_sync) state<=LOAD_START;
      LOAD_START: state<=LOAD_WAIT;
      LOAD_WAIT: if (loaded) state<=MANIFEST_START;
      MANIFEST_START: state<=MANIFEST_WAIT;
      MANIFEST_WAIT: if (manifest_valid) state<=DIRECTORY_START;
      DIRECTORY_START: state<=DIRECTORY_WAIT;
      DIRECTORY_WAIT: if (directory_valid) state<=TOKENS_START;
      TOKENS_START: state<=TOKENS_WAIT;
      TOKENS_WAIT: if (tokens_valid) state<=PROFILE_START;
      PROFILE_START: state<=PROFILE_WAIT;
      PROFILE_WAIT: if (profile_valid) state<=TRIE_START;
      TRIE_START: state<=TRIE_WAIT;
      TRIE_WAIT: if (trie_valid) begin
        if (!loaded || !manifest_valid || !directory_valid || !tokens_valid || !profile_valid) begin
          code<=8'h06; epoch_enabled<=0; state<=FAILED;
        end else begin
          active_config<=staged_config; active_bases<=staged_bases;
          active_lengths<=staged_lengths; active_metadata<=staged_metadata;
          active_counts<=staged_counts; state<=READY;
        end
      end
      READY, FAILED: if (start) begin
        active_config<=0; active_bases<=0; active_lengths<=0;
        active_metadata<=0; active_counts<=0; code<=0;
        epoch_enabled<=0; state<=RESET_EPOCH;
      end
      default: begin code<=8'h01; epoch_enabled<=0; state<=FAILED; end
    endcase
  end
endmodule
