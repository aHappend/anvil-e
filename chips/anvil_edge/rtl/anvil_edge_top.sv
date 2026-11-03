module anvil_edge_top #(
  parameter NUM_LAYERS=24, HIDDEN_SIZE=896, INTERMEDIATE_SIZE=4864,
  NUM_Q_HEADS=14, NUM_KV_HEADS=2, HEAD_DIM=64, GROUP_SIZE=128,
  AWQ_BITS=4, VOCAB_SIZE=151936, MAX_SEQ_LEN=32768,
  parameter integer RX_FIFO_DEPTH=16, TX_FIFO_DEPTH=16,
  parameter integer MAX_PROMPT_BYTES=4096, MAX_PROMPT_TOKENS=4096,
  parameter integer MAX_TOKEN_BYTES=4096, MAX_PRETOKEN_BYTES=4096,
  parameter integer MAX_TAG_REGISTERS=32, MAX_DFA_CLASSES=4096,
  parameter integer MAX_TRIE_NODES=1048576, MAX_SPECIAL_RECORDS=262144,
  parameter integer MAX_SEGMENTS=32, FLASH_ADDRESS_BYTES=3,
  parameter integer SPI_CLOCK_HALF_PERIOD=2,
  parameter [63:0] FLASH_CAPACITY_BYTES=64'd16777216, IMAGE_BASE=0,
  parameter [63:0] DDR_BASE=0, DDR_BYTES=64'h0000000100000000
) (
  input wire clk, rst_n,
  input wire uart_rx,
  output wire uart_tx,
  input wire s_axis_tvalid,
  output wire s_axis_tready,
  input wire [7:0] s_axis_tdata,
  input wire s_axis_tlast,
  output wire m_axis_tvalid,
  input wire m_axis_tready,
  output wire [7:0] m_axis_tdata,
  output wire m_axis_tlast,
  input wire spi_miso,
  output wire spi_mosi, spi_sck, spi_cs_n,
  input wire ddr_cal_done,
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
  input wire cfg_valid,
  output wire cfg_ready,
  input wire cfg_write,
  input wire [31:0] cfg_addr, cfg_wdata,
  output wire cfg_rsp_valid,
  input wire cfg_rsp_ready,
  output wire [31:0] cfg_rdata,
  output wire cfg_rsp_error,
  output wire boot_done, busy, done, error,
  output wire [7:0] error_code
);
  localparam [3:0] BOOT_WAIT=0, PUBLISH=1, CONFIG_CHECK=2, SETTLE=3,
    IDLE=4, ENGINE_START=5, RECEIVE=6, RUN=7, DRAIN=8, FAILED=9,
    TRANSPORT_SETTLE=10;
  reg [3:0] state;
  reg clients_enabled, io_enabled, admitted, abort_r, done_r;
  reg controller_finished, detokenizer_finished;
  reg [7:0] code;
  reg fault;
  reg [7:0] fault_code;
  wire client_rst_n=rst_n && clients_enabled;
  wire io_rst_n=rst_n && io_enabled;
  wire loader_done, loader_busy, loader_error;
  wire [7:0] loader_code;
  wire [223:0] committed_config;
  wire [1279:0] committed_bases, committed_lengths;
  wire [1023:0] committed_metadata;
  wire [511:0] committed_counts;
  wire [1023:0] table_bases=committed_bases[256+:1024];
  wire [1023:0] table_lengths=committed_lengths[256+:1024];
  wire [31:0] divisor, eos_id, maximum_tokens, transport, profile_id;
  wire [31:0] vocabulary, frame_bytes;
  wire reload_request, publish_error, serial_update;
  wire io_rx_valid, io_rx_ready, io_rx_last, io_tx_ready;
  wire [7:0] io_rx_data;
  wire io_rx_idle, io_tx_idle, io_rx_line_idle, framing_error, overflow_error;
  wire receiving=admitted && !abort_r && !reload_request && !serial_update &&
    (state==IDLE || state==ENGINE_START || state==RECEIVE);
  wire engine_start=rst_n && state==ENGINE_START;
  wire token_valid, token_ready, token_last, tokenizer_done, tokenizer_error;
  wire [31:0] token_id;
  wire [7:0] tokenizer_code;
  wire generated_valid, generated_ready, generated_last;
  wire [31:0] generated_id;
  wire finish_valid, finish_ready, controller_done, controller_error;
  wire [7:0] controller_code;
  wire text_valid, text_ready, text_last, detokenizer_done, detokenizer_error;
  wire [7:0] text_data, detokenizer_code;
  wire core_token_valid, core_token_ready, core_new_sequence;
  wire [31:0] core_token_id, core_token_position;
  wire core_logit_valid, core_logit_ready, core_done, core_error;
  wire [31:0] core_logit_index;
  wire signed [31:0] core_logit_data;
  wire [7:0] core_code;
  wire core_mem_req_valid, core_mem_req_ready, core_mem_req_write;
  wire [3:0] core_mem_req_kind;
  wire [31:0] core_mem_req_layer, core_mem_req_row, core_mem_req_col;
  wire [2:0] core_mem_req_proj;
  wire [31:0] core_mem_req_wdata, core_mem_rsp_rdata;
  wire core_mem_rsp_valid, core_mem_rsp_ready, core_mem_rsp_error;
  wire tokenizer_req_valid, tokenizer_req_ready, tokenizer_rsp_valid;
  wire tokenizer_rsp_ready, tokenizer_rsp_error;
  wire [63:0] tokenizer_req_addr;
  wire [31:0] tokenizer_rsp_data;
  wire detokenizer_req_valid, detokenizer_req_ready, detokenizer_rsp_valid;
  wire detokenizer_rsp_ready, detokenizer_rsp_error;
  wire [63:0] detokenizer_req_addr;
  wire [31:0] detokenizer_rsp_data;
  wire boot_req_valid, boot_req_ready, boot_req_write;
  wire [63:0] boot_req_addr;
  wire [31:0] boot_req_wdata, boot_rsp_data;
  wire [3:0] boot_req_wstrb;
  wire boot_rsp_valid, boot_rsp_ready, boot_rsp_error, memory_idle;
  wire write_allowed=rst_n && state==IDLE && admitted && !reload_request && !serial_update &&
    io_rx_idle && io_tx_idle && memory_idle && !io_rx_valid && !s_axis_tvalid;
  wire reload_allowed=rst_n && (state==IDLE || state==FAILED) &&
    !loader_busy && memory_idle && io_tx_idle && io_rx_line_idle &&
    !reload_request && (state==FAILED || io_rx_idle);
  wire live_ddr_error=ddr_rsp_valid && ddr_rsp_ready && ddr_rsp_error;
  wire input_fault=tokenizer_error && tokenizer_code!=8'h30 &&
    tokenizer_code!=8'h31;
  wire output_fault=detokenizer_error && detokenizer_code!=8'h30 &&
    detokenizer_code!=8'h31;

  assign boot_done=rst_n && admitted && loader_done;
  assign busy=rst_n && state!=IDLE && state!=FAILED;
  assign done=rst_n && done_r && state!=FAILED;
  assign error=rst_n && state==FAILED;
  assign error_code=rst_n ? code : 0;
  wire tokenizer_input_ready;
  assign io_rx_ready=client_rst_n && state==RECEIVE && tokenizer_input_ready;
  assign text_ready=client_rst_n && !abort_r && io_tx_ready;

  anvil_edge_config #(.VOCAB_SIZE(VOCAB_SIZE),.MAX_SEQ_LEN(MAX_SEQ_LEN)) configuration(
    .clk(clk),.rst_n(rst_n),.cfg_valid(cfg_valid),.cfg_ready(cfg_ready),
    .cfg_write(cfg_write),.cfg_addr(cfg_addr),.cfg_wdata(cfg_wdata),
    .cfg_rsp_valid(cfg_rsp_valid),.cfg_rsp_ready(cfg_rsp_ready),
    .cfg_rdata(cfg_rdata),.cfg_rsp_error(cfg_rsp_error),
    .status({error,done,busy,boot_done}),.transaction_error_code(code),
    .write_allowed(write_allowed),.reload_allowed(reload_allowed),
    .publish(rst_n && state==PUBLISH),.committed_config_words(committed_config),
    .reload_request(reload_request),.publish_error(publish_error),
    .serial_update(serial_update),
    .uart_divisor(divisor),.eos_token_id(eos_id),.max_new_tokens(maximum_tokens),
    .transport(transport),.profile_id(profile_id),.vocab_size(vocabulary),
    .uart_frame_bytes(frame_bytes)
  );
  anvil_edge_uart_io #(
    .RX_FIFO_DEPTH(RX_FIFO_DEPTH),.TX_FIFO_DEPTH(TX_FIFO_DEPTH),.FRAME_LOCK(1)
  ) edge_io(
    .clk(clk),.rst_n(io_rst_n),.uart_rx(uart_rx),.uart_tx(uart_tx),
    .divisor(divisor),.axis_bypass(transport[0]),.uart_frame_bytes(frame_bytes),
    .s_axis_tvalid(s_axis_tvalid),.s_axis_tready(s_axis_tready),
    .s_axis_tdata(s_axis_tdata),.s_axis_tlast(s_axis_tlast),
    .m_axis_tvalid(m_axis_tvalid),.m_axis_tready(m_axis_tready),
    .m_axis_tdata(m_axis_tdata),.m_axis_tlast(m_axis_tlast),
    .rx_valid(io_rx_valid),.rx_ready(io_rx_ready),.rx_data(io_rx_data),
    .rx_last(io_rx_last),.tx_valid(client_rst_n && !abort_r && text_valid),
    .tx_ready(io_tx_ready),.tx_data(text_data),.tx_last(text_last),
    .framing_error(framing_error),.overflow_error(overflow_error),
    .rx_idle(io_rx_idle),.tx_idle(io_tx_idle),.rx_line_idle(io_rx_line_idle),
    .receive_enable(receiving),.response_complete(done_r)
  );
  anvil_edge_bpe_tokenizer #(
    .MAX_PROMPT_BYTES(MAX_PROMPT_BYTES),.MAX_PROMPT_TOKENS(MAX_PROMPT_TOKENS),
    .MAX_PRETOKEN_BYTES(MAX_PRETOKEN_BYTES),.MAX_TAG_REGISTERS(MAX_TAG_REGISTERS)
  ) tokenizer(
    .clk(clk),.rst_n(client_rst_n),.start(engine_start),
    .in_valid(state==RECEIVE && io_rx_valid),.in_ready(tokenizer_input_ready),
    .in_data(io_rx_data),.in_last(io_rx_last),
    .out_valid(token_valid),.out_ready(token_ready),
    .out_token_id(token_id),.out_last(token_last),.busy(),.done(tokenizer_done),
    .error(tokenizer_error),.error_code(tokenizer_code),
    .tbl_req_valid(tokenizer_req_valid),.tbl_req_ready(tokenizer_req_ready),
    .tbl_req_addr(tokenizer_req_addr),.tbl_rsp_valid(tokenizer_rsp_valid),
    .tbl_rsp_ready(tokenizer_rsp_ready),.tbl_rsp_data(tokenizer_rsp_data),
    .tbl_rsp_error(tokenizer_rsp_error),.config_valid(boot_done),
    .cfg_table_bases(table_bases),.cfg_metadata(committed_metadata),
    .cfg_table_counts(committed_counts)
  );
  anvil_edge_detokenizer detokenizer(
    .clk(clk),.rst_n(client_rst_n),.start(engine_start),
    .in_valid(generated_valid),.in_ready(generated_ready),
    .in_token_id(generated_id),.in_last(generated_last),
    .out_valid(text_valid),.out_ready(text_ready),.out_data(text_data),
    .out_last(text_last),.busy(),.done(detokenizer_done),
    .error(detokenizer_error),.error_code(detokenizer_code),
    .tbl_req_valid(detokenizer_req_valid),.tbl_req_ready(detokenizer_req_ready),
    .tbl_req_addr(detokenizer_req_addr),.tbl_rsp_valid(detokenizer_rsp_valid),
    .tbl_rsp_ready(detokenizer_rsp_ready),.tbl_rsp_data(detokenizer_rsp_data),
    .tbl_rsp_error(detokenizer_rsp_error),.config_valid(boot_done),
    .cfg_vocab_size(vocabulary),.cfg_token_records_base(table_bases[64+:64]),
    .cfg_token_bytes_base(table_bases[128+:64]),
    .cfg_token_bytes_count({32'd0,committed_counts[64+:32]}),
    .cfg_max_token_byte_length(committed_metadata[448+:32]),
    .finish_valid(finish_valid),.finish_ready(finish_ready)
  );
  anvil_edge_autoregressive_fsm #(.MAX_PROMPT_TOKENS(MAX_PROMPT_TOKENS)) controller(
    .clk(clk),.rst_n(client_rst_n),.start(engine_start),
    .eos_token_id(eos_id),.max_new_tokens(maximum_tokens),
    .vocab_size(vocabulary),.seq_limit(MAX_SEQ_LEN),
    .prompt_valid(token_valid),.prompt_ready(token_ready),
    .prompt_id(token_id),.prompt_last(token_last),
    .generated_valid(generated_valid),.generated_ready(generated_ready),
    .generated_id(generated_id),.generated_last(generated_last),
    .core_token_valid(core_token_valid),.core_token_ready(core_token_ready),
    .core_token_id(core_token_id),.core_token_pos(core_token_position),
    .core_new_sequence(core_new_sequence),.core_logit_valid(core_logit_valid),
    .core_logit_ready(core_logit_ready),.core_logit_index(core_logit_index),
    .core_logit_data(core_logit_data),.core_done(core_done),.core_error(core_error),
    .busy(),.done(controller_done),.error(controller_error),
    .error_code(controller_code),.finish_valid(finish_valid),.finish_ready(finish_ready)
  );
  anvil_edge_core_adapter #(
    NUM_LAYERS,HIDDEN_SIZE,INTERMEDIATE_SIZE,NUM_Q_HEADS,NUM_KV_HEADS,
    HEAD_DIM,GROUP_SIZE,AWQ_BITS,VOCAB_SIZE,MAX_SEQ_LEN
  ) core_adapter(
    .clk(clk),.rst_n(client_rst_n),.token_valid(core_token_valid && !abort_r),
    .token_ready(core_token_ready),.token_id(core_token_id),
    .token_pos(core_token_position),.new_sequence(core_new_sequence),
    .logit_valid(core_logit_valid),.logit_ready(core_logit_ready),
    .logit_index(core_logit_index),.logit_data(core_logit_data),
    .done(core_done),.error(core_error),.error_code(core_code),
    .mem_req_valid(core_mem_req_valid),.mem_req_ready(core_mem_req_ready),
    .mem_req_write(core_mem_req_write),.mem_req_kind(core_mem_req_kind),
    .mem_req_layer(core_mem_req_layer),.mem_req_proj(core_mem_req_proj),
    .mem_req_row(core_mem_req_row),.mem_req_col(core_mem_req_col),
    .mem_req_wdata(core_mem_req_wdata),.mem_rsp_valid(core_mem_rsp_valid),
    .mem_rsp_ready(core_mem_rsp_ready),.mem_rsp_rdata(core_mem_rsp_rdata),
    .mem_rsp_error(core_mem_rsp_error),.config_valid(boot_done),
    .cfg_active_vocab_size(vocabulary)
  );
  anvil_edge_ddr4_boot_loader #(
    .NUM_LAYERS(NUM_LAYERS),.HIDDEN_SIZE(HIDDEN_SIZE),
    .INTERMEDIATE_SIZE(INTERMEDIATE_SIZE),.NUM_Q_HEADS(NUM_Q_HEADS),
    .NUM_KV_HEADS(NUM_KV_HEADS),.HEAD_DIM(HEAD_DIM),.GROUP_SIZE(GROUP_SIZE),
    .AWQ_BITS(AWQ_BITS),.VOCAB_SIZE(VOCAB_SIZE),.MAX_SEQ_LEN(MAX_SEQ_LEN),
    .MAX_SEGMENTS(MAX_SEGMENTS),.FLASH_ADDRESS_BYTES(FLASH_ADDRESS_BYTES),
    .FLASH_CAPACITY_BYTES(FLASH_CAPACITY_BYTES),
    .SPI_CLOCK_HALF_PERIOD(SPI_CLOCK_HALF_PERIOD),.IMAGE_BASE(IMAGE_BASE),
    .MAX_TOKEN_BYTES(MAX_TOKEN_BYTES),.MAX_PRETOKEN_BYTES(MAX_PRETOKEN_BYTES),
    .MAX_TAG_REGISTERS(MAX_TAG_REGISTERS),.MAX_DFA_CLASSES(MAX_DFA_CLASSES),
    .MAX_TRIE_NODES(MAX_TRIE_NODES),.MAX_SPECIAL_RECORDS(MAX_SPECIAL_RECORDS),
    .DDR_BASE(DDR_BASE),.DDR_BYTES(DDR_BYTES)
  ) boot_loader(
    .clk(clk),.rst_n(rst_n),.start(reload_request),.ddr_cal_done(ddr_cal_done),
    .spi_miso(spi_miso),.spi_mosi(spi_mosi),.spi_sck(spi_sck),.spi_cs_n(spi_cs_n),
    .ddr_req_valid(boot_req_valid),.ddr_req_ready(boot_req_ready),
    .ddr_req_write(boot_req_write),.ddr_req_addr(boot_req_addr),
    .ddr_req_wdata(boot_req_wdata),.ddr_req_wstrb(boot_req_wstrb),
    .ddr_rsp_valid(boot_rsp_valid),.ddr_rsp_ready(boot_rsp_ready),
    .ddr_rsp_rdata(boot_rsp_data),.ddr_rsp_error(boot_rsp_error),
    .boot_done(loader_done),.busy(loader_busy),.error(loader_error),
    .error_code(loader_code),.committed_config_words(committed_config),
    .committed_segment_bases(committed_bases),.committed_segment_bytes(committed_lengths),
    .committed_metadata(committed_metadata),.committed_table_counts(committed_counts)
  );
  anvil_edge_memory_subsystem #(
    NUM_LAYERS,HIDDEN_SIZE,INTERMEDIATE_SIZE,NUM_Q_HEADS,NUM_KV_HEADS,
    HEAD_DIM,GROUP_SIZE,AWQ_BITS,VOCAB_SIZE,MAX_SEQ_LEN,DDR_BASE,DDR_BYTES
  ) memory_subsystem(
    .clk(clk),.rst_n(rst_n),.config_valid(loader_done),.boot_enable(!loader_done),
    .cfg_directory_base(committed_bases[64+:64]),
    .cfg_directory_count(32'd28*NUM_LAYERS+32'd4),
    .cfg_immutable_base(committed_bases[128+:64]),
    .cfg_immutable_bytes(committed_lengths[128+:64]),
    .cfg_writable_base(committed_bases[192+:64]),
    .cfg_writable_bytes(committed_lengths[192+:64]),
    .cfg_table_bases(table_bases),.cfg_table_bytes(table_lengths),
    .core_mem_req_valid(core_mem_req_valid),.core_mem_req_ready(core_mem_req_ready),
    .core_mem_req_write(core_mem_req_write),.core_mem_req_kind(core_mem_req_kind),
    .core_mem_req_layer(core_mem_req_layer),.core_mem_req_proj(core_mem_req_proj),
    .core_mem_req_row(core_mem_req_row),.core_mem_req_col(core_mem_req_col),
    .core_mem_req_wdata(core_mem_req_wdata),.core_mem_rsp_valid(core_mem_rsp_valid),
    .core_mem_rsp_ready(core_mem_rsp_ready),.core_mem_rsp_rdata(core_mem_rsp_rdata),
    .core_mem_rsp_error(core_mem_rsp_error),
    .tokenizer_tbl_req_valid(tokenizer_req_valid),.tokenizer_tbl_req_ready(tokenizer_req_ready),
    .tokenizer_tbl_req_addr(tokenizer_req_addr),.tokenizer_tbl_rsp_valid(tokenizer_rsp_valid),
    .tokenizer_tbl_rsp_ready(tokenizer_rsp_ready),.tokenizer_tbl_rsp_data(tokenizer_rsp_data),
    .tokenizer_tbl_rsp_error(tokenizer_rsp_error),
    .detokenizer_tbl_req_valid(detokenizer_req_valid),
    .detokenizer_tbl_req_ready(detokenizer_req_ready),
    .detokenizer_tbl_req_addr(detokenizer_req_addr),
    .detokenizer_tbl_rsp_valid(detokenizer_rsp_valid),
    .detokenizer_tbl_rsp_ready(detokenizer_rsp_ready),
    .detokenizer_tbl_rsp_data(detokenizer_rsp_data),
    .detokenizer_tbl_rsp_error(detokenizer_rsp_error),
    .boot_req_valid(boot_req_valid),.boot_req_ready(boot_req_ready),
    .boot_req_write(boot_req_write),.boot_req_addr(boot_req_addr),
    .boot_req_wdata(boot_req_wdata),.boot_req_wstrb(boot_req_wstrb),
    .boot_rsp_valid(boot_rsp_valid),.boot_rsp_ready(boot_rsp_ready),
    .boot_rsp_rdata(boot_rsp_data),.boot_rsp_error(boot_rsp_error),
    .ddr_req_valid(ddr_req_valid),.ddr_req_ready(ddr_req_ready),
    .ddr_req_write(ddr_req_write),.ddr_req_addr(ddr_req_addr),
    .ddr_req_wdata(ddr_req_wdata),.ddr_req_wstrb(ddr_req_wstrb),
    .ddr_rsp_valid(ddr_rsp_valid),.ddr_rsp_ready(ddr_rsp_ready),
    .ddr_rsp_rdata(ddr_rsp_rdata),.ddr_rsp_error(ddr_rsp_error),
    .idle(memory_idle),.abort_inference(abort_r)
  );

  always @* begin
    fault=0; fault_code=0;
    if (rst_n && state!=FAILED && !reload_request) begin
      if (loader_error) begin fault=1; fault_code=loader_code; end
      else if (live_ddr_error) begin fault=1; fault_code=8'h04; end
      else if (publish_error) begin fault=1; fault_code=8'h06; end
      else if (input_fault) begin fault=1; fault_code=tokenizer_code; end
      else if (output_fault) begin fault=1; fault_code=detokenizer_code; end
      else if (core_error) begin fault=1; fault_code=core_code; end
      else if (controller_error && controller_code!=8'h30 && controller_code!=8'h31) begin
        fault=1; fault_code=controller_code;
      end else if (tokenizer_error) begin fault=1; fault_code=tokenizer_code; end
      else if (detokenizer_error) begin fault=1; fault_code=detokenizer_code; end
      else if (controller_error) begin fault=1; fault_code=controller_code; end
      else if (framing_error) begin fault=1; fault_code=8'h40; end
      else if (overflow_error) begin fault=1; fault_code=8'h41; end
    end
  end
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state<=BOOT_WAIT; clients_enabled<=0; io_enabled<=1; admitted<=0;
      abort_r<=0; done_r<=0; controller_finished<=0; detokenizer_finished<=0;
      code<=0;
    end else begin
      done_r<=0;
      if (controller_done) controller_finished<=1;
      if (detokenizer_done) detokenizer_finished<=1;
      if (reload_request) begin
        state<=BOOT_WAIT; clients_enabled<=0; io_enabled<=0; admitted<=0;
        abort_r<=0; controller_finished<=0; detokenizer_finished<=0; code<=0;
      end else if (fault) begin
        code<=fault_code; abort_r<=1; state<=FAILED;
      end else case (state)
        BOOT_WAIT: begin
          io_enabled<=1;
          if (loader_done) state<=PUBLISH;
        end
        PUBLISH: state<=CONFIG_CHECK;
        CONFIG_CHECK: begin admitted<=1; state<=SETTLE; end
        SETTLE: begin clients_enabled<=1; state<=IDLE; end
        IDLE: begin
          if (serial_update) state<=TRANSPORT_SETTLE;
          else if (io_rx_valid) state<=ENGINE_START;
        end
        TRANSPORT_SETTLE: state<=IDLE;
        ENGINE_START: begin
          controller_finished<=0; detokenizer_finished<=0; state<=RECEIVE;
        end
        RECEIVE: if (io_rx_valid && io_rx_ready && io_rx_last) state<=RUN;
        RUN: if (controller_finished) state<=DRAIN;
        DRAIN: if (controller_finished && detokenizer_finished && io_tx_idle) begin
          done_r<=1; state<=IDLE;
        end
        FAILED: clients_enabled<=0;
        default: begin code<=8'h32; abort_r<=1; state<=FAILED; end
      endcase
    end
  end
endmodule
