module anvil_edge_memory_subsystem #(
  parameter NUM_LAYERS=24, HIDDEN_SIZE=896, INTERMEDIATE_SIZE=4864,
  NUM_Q_HEADS=14, NUM_KV_HEADS=2, HEAD_DIM=64, GROUP_SIZE=128,
  AWQ_BITS=4, VOCAB_SIZE=151936, MAX_SEQ_LEN=32768,
  parameter [63:0] DDR_BASE=0, DDR_BYTES=64'h0000000100000000
) (
  input wire clk, rst_n,
  input wire config_valid, boot_enable,
  input wire [63:0] cfg_directory_base,
  input wire [31:0] cfg_directory_count,
  input wire [63:0] cfg_immutable_base, cfg_immutable_bytes,
  input wire [63:0] cfg_writable_base, cfg_writable_bytes,
  input wire [1023:0] cfg_table_bases, cfg_table_bytes,
  input wire core_mem_req_valid,
  output wire core_mem_req_ready,
  input wire core_mem_req_write,
  input wire [3:0] core_mem_req_kind,
  input wire [31:0] core_mem_req_layer,
  input wire [2:0] core_mem_req_proj,
  input wire [31:0] core_mem_req_row, core_mem_req_col, core_mem_req_wdata,
  output wire core_mem_rsp_valid,
  input wire core_mem_rsp_ready,
  output wire [31:0] core_mem_rsp_rdata,
  output wire core_mem_rsp_error,
  input wire tokenizer_tbl_req_valid,
  output wire tokenizer_tbl_req_ready,
  input wire [63:0] tokenizer_tbl_req_addr,
  output wire tokenizer_tbl_rsp_valid,
  input wire tokenizer_tbl_rsp_ready,
  output wire [31:0] tokenizer_tbl_rsp_data,
  output wire tokenizer_tbl_rsp_error,
  input wire detokenizer_tbl_req_valid,
  output wire detokenizer_tbl_req_ready,
  input wire [63:0] detokenizer_tbl_req_addr,
  output wire detokenizer_tbl_rsp_valid,
  input wire detokenizer_tbl_rsp_ready,
  output wire [31:0] detokenizer_tbl_rsp_data,
  output wire detokenizer_tbl_rsp_error,
  input wire boot_req_valid,
  output wire boot_req_ready,
  input wire boot_req_write,
  input wire [63:0] boot_req_addr,
  input wire [31:0] boot_req_wdata,
  input wire [3:0] boot_req_wstrb,
  output wire boot_rsp_valid,
  input wire boot_rsp_ready,
  output wire [31:0] boot_rsp_rdata,
  output wire boot_rsp_error,
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
  output wire idle,
  input tri0 abort_inference
);
  localparam [3:0] IDLE=0, TABLE_RANGE=1, TABLE_END=2, TABLE_CHECK=3,
    REQUEST=4, RESPONSE=5, RETURN=6;
  localparam [1:0] CORE=0, TOKENIZER=1, DETOKENIZER=2, BOOT=3;
  localparam [64:0] DDR_END={1'b0,DDR_BASE}+{1'b0,DDR_BYTES};
  reg [3:0] state;
  reg [1:0] owner, priority_owner;
  reg selected_valid;
  reg [1:0] selected_owner;
  reg request_write;
  reg [63:0] request_address;
  reg [31:0] request_data;
  reg [3:0] request_strobes;
  reg [31:0] response_data;
  reg response_error;
  reg [1023:0] table_bases, table_bytes;
  reg [3:0] table_index;
  reg [63:0] table_base, table_length;
  reg [64:0] table_end;
  reg [64:0] request_end;
  wire mapper_req_valid, mapper_req_ready, mapper_req_write;
  wire mapper_core_ready;
  wire [63:0] mapper_req_addr;
  wire [31:0] mapper_req_wdata;
  wire [3:0] mapper_req_wstrb;
  wire mapper_rsp_valid, mapper_rsp_ready, mapper_rsp_error, mapper_idle;
  wire [31:0] mapper_rsp_rdata;
  wire response_accept=(abort_inference && owner!=BOOT) ||
    (owner==CORE && mapper_rsp_ready) ||
    (owner==TOKENIZER && tokenizer_tbl_rsp_ready) ||
    (owner==DETOKENIZER && detokenizer_tbl_rsp_ready) ||
    (owner==BOOT && boot_rsp_ready);
  wire [64:0] allowed_table_end=
    table_index==2 ? ((table_end+65'd3) & ~65'd3) : table_end;

  anvil_edge_tensor_mapper #(
    NUM_LAYERS,HIDDEN_SIZE,INTERMEDIATE_SIZE,NUM_Q_HEADS,NUM_KV_HEADS,
    HEAD_DIM,GROUP_SIZE,AWQ_BITS,VOCAB_SIZE,MAX_SEQ_LEN,DDR_BASE,DDR_BYTES
  ) tensor_mapper (
    .clk(clk),.rst_n(rst_n),.config_valid(config_valid),
    .cfg_directory_base(cfg_directory_base),.cfg_directory_count(cfg_directory_count),
    .cfg_immutable_base(cfg_immutable_base),.cfg_immutable_bytes(cfg_immutable_bytes),
    .cfg_writable_base(cfg_writable_base),.cfg_writable_bytes(cfg_writable_bytes),
    .mem_req_valid(core_mem_req_valid && !abort_inference),.mem_req_ready(mapper_core_ready),
    .mem_req_write(core_mem_req_write),.mem_req_kind(core_mem_req_kind),
    .mem_req_layer(core_mem_req_layer),.mem_req_proj(core_mem_req_proj),
    .mem_req_row(core_mem_req_row),.mem_req_col(core_mem_req_col),
    .mem_req_wdata(core_mem_req_wdata),.mem_rsp_valid(core_mem_rsp_valid),
    .mem_rsp_ready(core_mem_rsp_ready || abort_inference),.mem_rsp_rdata(core_mem_rsp_rdata),
    .mem_rsp_error(core_mem_rsp_error),
    .ddr_req_valid(mapper_req_valid),.ddr_req_ready(mapper_req_ready),
    .ddr_req_write(mapper_req_write),.ddr_req_addr(mapper_req_addr),
    .ddr_req_wdata(mapper_req_wdata),.ddr_req_wstrb(mapper_req_wstrb),
    .ddr_rsp_valid(mapper_rsp_valid),.ddr_rsp_ready(mapper_rsp_ready),
    .ddr_rsp_rdata(mapper_rsp_rdata),.ddr_rsp_error(mapper_rsp_error),.idle(mapper_idle)
  );

  always @* begin
    selected_valid=0;
    selected_owner=CORE;
    if (rst_n && state==IDLE) begin
      if (!config_valid) begin
        if (boot_enable && boot_req_valid && mapper_idle) begin
          selected_valid=1;
          selected_owner=BOOT;
        end
      end else if (abort_inference) begin
        if (mapper_req_valid) begin selected_valid=1; selected_owner=CORE; end
      end else begin
        case (priority_owner)
          CORE: begin
            if (mapper_req_valid) begin selected_valid=1; selected_owner=CORE; end
            else if (tokenizer_tbl_req_valid) begin selected_valid=1; selected_owner=TOKENIZER; end
            else if (detokenizer_tbl_req_valid) begin selected_valid=1; selected_owner=DETOKENIZER; end
          end
          TOKENIZER: begin
            if (tokenizer_tbl_req_valid) begin selected_valid=1; selected_owner=TOKENIZER; end
            else if (detokenizer_tbl_req_valid) begin selected_valid=1; selected_owner=DETOKENIZER; end
            else if (mapper_req_valid) begin selected_valid=1; selected_owner=CORE; end
          end
          default: begin
            if (detokenizer_tbl_req_valid) begin selected_valid=1; selected_owner=DETOKENIZER; end
            else if (mapper_req_valid) begin selected_valid=1; selected_owner=CORE; end
            else if (tokenizer_tbl_req_valid) begin selected_valid=1; selected_owner=TOKENIZER; end
          end
        endcase
      end
    end
  end

  assign mapper_req_ready=selected_valid && selected_owner==CORE;
  assign core_mem_req_ready=rst_n && !abort_inference && mapper_core_ready;
  assign tokenizer_tbl_req_ready=selected_valid && selected_owner==TOKENIZER;
  assign detokenizer_tbl_req_ready=selected_valid && selected_owner==DETOKENIZER;
  assign boot_req_ready=selected_valid && selected_owner==BOOT;
  assign mapper_rsp_valid=rst_n && state==RETURN && owner==CORE;
  assign tokenizer_tbl_rsp_valid=rst_n && state==RETURN && owner==TOKENIZER;
  assign detokenizer_tbl_rsp_valid=rst_n && state==RETURN && owner==DETOKENIZER;
  assign boot_rsp_valid=rst_n && state==RETURN && owner==BOOT;
  assign mapper_rsp_rdata=mapper_rsp_valid ? response_data : 0;
  assign tokenizer_tbl_rsp_data=tokenizer_tbl_rsp_valid ? response_data : 0;
  assign detokenizer_tbl_rsp_data=detokenizer_tbl_rsp_valid ? response_data : 0;
  assign boot_rsp_rdata=boot_rsp_valid ? response_data : 0;
  assign mapper_rsp_error=mapper_rsp_valid && response_error;
  assign tokenizer_tbl_rsp_error=tokenizer_tbl_rsp_valid && response_error;
  assign detokenizer_tbl_rsp_error=detokenizer_tbl_rsp_valid && response_error;
  assign boot_rsp_error=boot_rsp_valid && response_error;
  assign ddr_req_valid=rst_n && state==REQUEST;
  assign ddr_req_write=rst_n && request_write;
  assign ddr_req_addr=rst_n ? request_address : 0;
  assign ddr_req_wdata=rst_n ? request_data : 0;
  assign ddr_req_wstrb=rst_n ? request_strobes : 0;
  assign ddr_rsp_ready=rst_n && state==RESPONSE;
  assign idle=rst_n && state==IDLE && mapper_idle;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state<=IDLE; owner<=CORE; priority_owner<=CORE;
      request_write<=0; request_address<=0; request_data<=0; request_strobes<=0;
      response_data<=0; response_error<=0;
      table_bases<=0; table_bytes<=0; table_index<=0;
      table_base<=0; table_length<=0; table_end<=0; request_end<=0;
    end else case (state)
      IDLE: if (selected_valid) begin
        owner<=selected_owner;
        response_data<=0;
        response_error<=0;
        case (selected_owner)
          CORE: begin
            request_write<=mapper_req_write;
            request_address<=mapper_req_addr;
            request_data<=mapper_req_wdata;
            request_strobes<=mapper_req_wstrb;
            state<=REQUEST;
          end
          BOOT: begin
            request_write<=boot_req_write;
            request_address<=boot_req_addr;
            request_data<=boot_req_wdata;
            request_strobes<=boot_req_wstrb;
            state<=REQUEST;
          end
          default: begin
            request_write<=0;
            request_address<=selected_owner==TOKENIZER ?
              tokenizer_tbl_req_addr : detokenizer_tbl_req_addr;
            request_data<=0;
            request_strobes<=0;
            table_bases<=cfg_table_bases;
            table_bytes<=cfg_table_bytes;
            table_index<=0;
            state<=TABLE_RANGE;
          end
        endcase
      end
      TABLE_RANGE: begin
        table_base<=table_bases[table_index*64+:64];
        table_length<=table_bytes[table_index*64+:64];
        request_end<={1'b0,request_address}+65'd4;
        state<=TABLE_END;
      end
      TABLE_END: begin
        table_end<={1'b0,table_base}+{1'b0,table_length};
        state<=TABLE_CHECK;
      end
      TABLE_CHECK: begin
        if (request_address[1:0]!=0 || request_end[64] ||
            request_address<DDR_BASE || request_end>DDR_END) begin
          response_error<=1; state<=RETURN;
        end else if (table_length!=0 && table_base[1:0]==0 &&
                     !table_end[64] && !allowed_table_end[64] &&
                     table_base>=DDR_BASE && allowed_table_end<=DDR_END &&
                     request_address>=table_base && request_end<=allowed_table_end) begin
          state<=REQUEST;
        end else if (table_index==15) begin
          response_error<=1; state<=RETURN;
        end else begin
          table_index<=table_index+1'b1;
          state<=TABLE_RANGE;
        end
      end
      REQUEST: if (ddr_req_valid && ddr_req_ready) state<=RESPONSE;
      RESPONSE: if (ddr_rsp_valid && ddr_rsp_ready) begin
        response_data<=ddr_rsp_error ? 0 : ddr_rsp_rdata;
        response_error<=ddr_rsp_error;
        state<=RETURN;
      end
      RETURN: if (response_accept) begin
        case (owner)
          CORE: priority_owner<=TOKENIZER;
          TOKENIZER: priority_owner<=DETOKENIZER;
          default: priority_owner<=CORE;
        endcase
        state<=IDLE;
      end
      default: begin response_data<=0; response_error<=1; state<=RETURN; end
    endcase
  end
endmodule
