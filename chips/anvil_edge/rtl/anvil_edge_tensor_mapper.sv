module anvil_edge_tensor_mapper #(
  parameter NUM_LAYERS=24, HIDDEN_SIZE=896, INTERMEDIATE_SIZE=4864,
  NUM_Q_HEADS=14, NUM_KV_HEADS=2, HEAD_DIM=64, GROUP_SIZE=128,
  AWQ_BITS=4, VOCAB_SIZE=151936, MAX_SEQ_LEN=32768,
  parameter [63:0] DDR_BASE=0, DDR_BYTES=64'h0000000100000000
) (
  input wire clk, rst_n,
  input wire config_valid,
  input wire [63:0] cfg_directory_base,
  input wire [31:0] cfg_directory_count,
  input wire [63:0] cfg_immutable_base, cfg_immutable_bytes,
  input wire [63:0] cfg_writable_base, cfg_writable_bytes,
  input wire mem_req_valid,
  output wire mem_req_ready,
  input wire mem_req_write,
  input wire [3:0] mem_req_kind,
  input wire [31:0] mem_req_layer,
  input wire [2:0] mem_req_proj,
  input wire [31:0] mem_req_row, mem_req_col, mem_req_wdata,
  output wire mem_rsp_valid,
  input wire mem_rsp_ready,
  output wire [31:0] mem_rsp_rdata,
  output wire mem_rsp_error,
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
  output wire idle
);
  localparam integer SAFE_G=GROUP_SIZE>0 ? GROUP_SIZE : 1;
  localparam [31:0] H_GROUPS=HIDDEN_SIZE/SAFE_G;
  localparam [31:0] I_GROUPS=INTERMEDIATE_SIZE/SAFE_G;
  localparam [63:0] DIRECTORY_COUNT=64'd28*NUM_LAYERS+64'd4;
  localparam [64:0] DDR_END={1'b0,DDR_BASE}+{1'b0,DDR_BYTES};
  localparam [4:0] IDLE=0, CONFIG_CHECK=1, DIR_OFFSET=2, DIR_ADDRESS=3,
    READ_REQUEST=4, READ_RESPONSE=5, READ_CONSUME=6, KEY_CHECK=7,
    REGION_CHECK=8, EXTENT_MULTIPLY=9, EXTENT_WAIT=10, EXTENT_CHECK=11,
    INDEX_MULTIPLY=12, INDEX_WAIT=13, INDEX_ADD=14, OFFSET_ADD=15,
    SEGMENT_CHECK=16, PHYSICAL_ADD=17, PHYSICAL_CHECK=18,
    DATA_REQUEST=19, DATA_RESPONSE=20, RETURN=21, CACHE_LOOKUP=22;
  reg [4:0] state;
  reg request_write;
  reg [3:0] request_kind;
  reg [2:0] request_projection;
  reg [31:0] request_layer, request_row, request_column, request_data;
  reg [63:0] directory_base, immutable_base, immutable_bytes;
  reg [63:0] writable_base, writable_bytes;
  reg [31:0] directory_count, record_index;
  reg [3:0] record_word;
  reg [31:0] key_kind, key_layer, key_projection, storage_kind;
  reg [63:0] region_offset, region_extent;
  reg [31:0] region_rows, region_columns, region_format, region_permissions;
  reg [64:0] directory_offset, directory_address, extent_value;
  reg [64:0] element_index, element_offset, segment_offset, physical_address;
  reg [63:0] segment_base, segment_bytes;
  reg [31:0] read_data, response_data;
  reg response_error;
  reg [31:0] expected_rows, expected_columns, expected_format;
  reg [31:0] legal_columns;
  reg legal_key, writable_key;
  reg [31:0] projection_inputs, projection_outputs, projection_groups;
  reg [1:0] cache_valid;
  reg cache_victim, descriptor_cached, transaction_cacheable;
  reg [3:0] cache_kind [0:1];
  reg [31:0] cache_layer [0:1];
  reg [2:0] cache_projection [0:1];
  reg [31:0] cache_storage_kind [0:1];
  reg [63:0] cache_offset [0:1], cache_extent [0:1];
  reg [31:0] cache_rows [0:1], cache_columns [0:1];
  reg [31:0] cache_format [0:1], cache_permissions [0:1];
  reg [1:0] cache_row_valid;
  reg [31:0] cache_row [0:1];
  reg [63:0] cache_row_base [0:1];
  reg descriptor_cache_index;
  integer cache_reset_index;
  wire cache_context_matches=cfg_directory_base==directory_base &&
    cfg_directory_count==directory_count &&
    cfg_immutable_base==immutable_base && cfg_immutable_bytes==immutable_bytes &&
    cfg_writable_base==writable_base && cfg_writable_bytes==writable_bytes;
  wire cache_hit_0=cache_valid[0] && cache_kind[0]==request_kind &&
    cache_layer[0]==request_layer && cache_projection[0]==request_projection;
  wire cache_hit_1=cache_valid[1] && cache_kind[1]==request_kind &&
    cache_layer[1]==request_layer && cache_projection[1]==request_projection;
  wire cache_hit_index=!cache_hit_0 && cache_hit_1;
  wire row_base_hit=config_valid && cache_context_matches &&
    transaction_cacheable && cache_valid[descriptor_cache_index] &&
    cache_row_valid[descriptor_cache_index] &&
    cache_row[descriptor_cache_index]==request_row;
  wire multiply_ready, multiply_valid;
  wire signed [127:0] multiply_product;
  wire multiply_extent=state==EXTENT_MULTIPLY || state==EXTENT_WAIT;
  wire signed [63:0] multiply_a=
    multiply_extent ? $signed({32'd0,region_rows}) : $signed({32'd0,request_row});
  wire signed [63:0] multiply_b=$signed({32'd0,region_columns});
  wire [64:0] directory_size=({33'd0,directory_count} << 5)+
                              ({33'd0,directory_count} << 4)+65'd32;
  wire [65:0] directory_end={2'b0,directory_base}+{1'b0,directory_size};
  wire [64:0] immutable_end={1'b0,immutable_base}+{1'b0,immutable_bytes};
  wire [64:0] writable_end={1'b0,writable_base}+{1'b0,writable_bytes};
  wire [65:0] region_end={2'b0,region_offset}+{2'b0,region_extent};
  wire descriptor_extent_valid=extent_value=={1'b0,region_extent} &&
    region_end[65:64]==0 && region_end<={2'b0,segment_bytes};
  wire key_equal=key_kind=={28'd0,request_kind} &&
    key_layer==request_layer && key_projection=={29'd0,request_projection};
  wire key_later=key_kind>{28'd0,request_kind} ||
    (key_kind=={28'd0,request_kind} && key_layer>request_layer) ||
    (key_kind=={28'd0,request_kind} && key_layer==request_layer &&
     key_projection>{29'd0,request_projection});

  anvil_edge_parameters #(
    NUM_LAYERS,HIDDEN_SIZE,INTERMEDIATE_SIZE,NUM_Q_HEADS,NUM_KV_HEADS,
    HEAD_DIM,GROUP_SIZE,AWQ_BITS,VOCAB_SIZE,MAX_SEQ_LEN
  ) parameters_ok();
  generate if (DDR_BYTES==0 || DDR_BASE[1:0]!=0 ||
               DDR_BYTES[1:0]!=0 || DDR_END[64]) begin : invalid_window
    initial $fatal(1, "ANVIL_EDGE_MAPPER PARAMETER ERROR: invalid DDR window");
  end endgenerate

  anvil_edge_signed_multiplier #(.WIDTH(64)) index_multiplier(
    .clk(clk),.rst_n(rst_n),
    .in_valid(state==EXTENT_MULTIPLY || state==INDEX_MULTIPLY),
    .in_ready(multiply_ready),.operand_a(multiply_a),.operand_b(multiply_b),
    .out_valid(multiply_valid),
    .out_ready(state==EXTENT_WAIT || state==INDEX_WAIT),
    .product(multiply_product)
  );

  assign mem_req_ready=rst_n && config_valid && state==IDLE;
  assign mem_rsp_valid=rst_n && state==RETURN;
  assign mem_rsp_rdata=rst_n ? response_data : 0;
  assign mem_rsp_error=rst_n && response_error;
  assign idle=rst_n && state==IDLE;
  assign ddr_req_valid=rst_n && (state==READ_REQUEST || state==DATA_REQUEST);
  assign ddr_req_write=rst_n && state==DATA_REQUEST && request_write;
  assign ddr_req_addr=!rst_n ? 0 :
    (state==READ_REQUEST ? directory_address[63:0] : physical_address[63:0]);
  assign ddr_req_wdata=rst_n && state==DATA_REQUEST ? request_data : 0;
  assign ddr_req_wstrb=rst_n && state==DATA_REQUEST && request_write ? 4'hf : 0;
  assign ddr_rsp_ready=rst_n && (state==READ_RESPONSE || state==DATA_RESPONSE);

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cache_valid<=0;
      cache_row_valid<=0;
      cache_victim<=0;
      transaction_cacheable<=0;
      for (cache_reset_index=0; cache_reset_index<2;
           cache_reset_index=cache_reset_index+1) begin
        cache_kind[cache_reset_index]<=0;
        cache_layer[cache_reset_index]<=0;
        cache_projection[cache_reset_index]<=0;
        cache_storage_kind[cache_reset_index]<=0;
        cache_offset[cache_reset_index]<=0;
        cache_extent[cache_reset_index]<=0;
        cache_rows[cache_reset_index]<=0;
        cache_columns[cache_reset_index]<=0;
        cache_format[cache_reset_index]<=0;
        cache_permissions[cache_reset_index]<=0;
        cache_row[cache_reset_index]<=0;
        cache_row_base[cache_reset_index]<=0;
      end
    end else begin
      if (mem_req_valid && mem_req_ready) transaction_cacheable<=1;
      else if (!config_valid || !cache_context_matches) transaction_cacheable<=0;

      // Epoch withdrawal wins over a simultaneous completed descriptor fill.
      if (!config_valid || !cache_context_matches) begin
        cache_valid<=0;
        cache_row_valid<=0;
        cache_victim<=0;
      end else if (state==EXTENT_CHECK && descriptor_extent_valid &&
                   transaction_cacheable) begin
        cache_kind[cache_victim]<=request_kind;
        cache_layer[cache_victim]<=request_layer;
        cache_projection[cache_victim]<=request_projection;
        cache_storage_kind[cache_victim]<=storage_kind;
        cache_offset[cache_victim]<=region_offset;
        cache_extent[cache_victim]<=region_extent;
        cache_rows[cache_victim]<=region_rows;
        cache_columns[cache_victim]<=region_columns;
        cache_format[cache_victim]<=region_format;
        cache_permissions[cache_victim]<=region_permissions;
        cache_valid[cache_victim]<=1;
        cache_row_valid[cache_victim]<=0;
        cache_victim<=!cache_victim;
      end else if (state==INDEX_WAIT && multiply_valid &&
                   multiply_product[127:64]==0 && transaction_cacheable &&
                   cache_valid[descriptor_cache_index] &&
                   cache_kind[descriptor_cache_index]==request_kind &&
                   cache_layer[descriptor_cache_index]==request_layer &&
                   cache_projection[descriptor_cache_index]==request_projection) begin
        cache_row[descriptor_cache_index]<=request_row;
        cache_row_base[descriptor_cache_index]<=multiply_product[63:0];
        cache_row_valid[descriptor_cache_index]<=1;
      end
    end
  end

  always @* begin
    expected_rows=0;
    expected_columns=0;
    expected_format=0;
    legal_columns=0;
    legal_key=0;
    writable_key=0;
    projection_inputs=HIDDEN_SIZE;
    projection_outputs=HIDDEN_SIZE;
    projection_groups=H_GROUPS;
    case (request_projection)
      1,2: projection_outputs=NUM_KV_HEADS*HEAD_DIM;
      4,5: projection_outputs=INTERMEDIATE_SIZE;
      6: begin
        projection_inputs=INTERMEDIATE_SIZE;
        projection_groups=I_GROUPS;
      end
      default: begin end
    endcase
    if (rst_n) begin
      case (request_kind)
        0: begin
          legal_key=request_layer==0 && request_projection==0;
          expected_rows=VOCAB_SIZE;
          expected_columns=HIDDEN_SIZE;
          expected_format=1;
        end
        1,2,3: begin
          legal_key=request_layer<NUM_LAYERS && request_projection<=6;
          expected_rows=request_kind==1 ? projection_inputs : projection_groups;
          expected_columns=request_kind==3 ? projection_outputs : projection_outputs>>3;
          expected_format=request_kind==3 ? 1 : 2;
        end
        4: begin
          legal_key=request_layer<NUM_LAYERS && request_projection<=2;
          expected_rows=1;
          expected_columns=projection_outputs;
          expected_format=1;
        end
        5,6: begin
          legal_key=request_layer<NUM_LAYERS && request_projection==0;
          expected_rows=1;
          expected_columns=HIDDEN_SIZE;
          expected_format=1;
        end
        7: begin
          legal_key=request_layer==0 && request_projection==0;
          expected_rows=1;
          expected_columns=HIDDEN_SIZE;
          expected_format=1;
        end
        8: begin
          legal_key=request_layer==0 && request_projection==0 &&
            request_row<15 && request_row!=13;
          expected_rows=15;
          expected_columns=HIDDEN_SIZE>INTERMEDIATE_SIZE ? HIDDEN_SIZE : INTERMEDIATE_SIZE;
          expected_format=3;
          writable_key=1;
        end
        9,10: begin
          legal_key=request_layer<NUM_LAYERS && request_projection==0;
          expected_rows=MAX_SEQ_LEN;
          expected_columns=NUM_KV_HEADS*HEAD_DIM;
          expected_format=3;
          writable_key=1;
        end
        11: begin
          legal_key=request_layer==0 && request_projection==0;
          expected_rows=MAX_SEQ_LEN;
          expected_columns=HEAD_DIM;
          expected_format=4;
        end
        default: begin end
      endcase
      legal_columns=expected_columns;
      if (request_kind==8) begin
        case (request_row)
          3,4: legal_columns=NUM_KV_HEADS*HEAD_DIM;
          9,10,11: legal_columns=INTERMEDIATE_SIZE;
          13: legal_columns=0;
          default: legal_columns=HIDDEN_SIZE;
        endcase
      end
    end
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state<=IDLE;
      request_write<=0; request_kind<=0; request_projection<=0;
      request_layer<=0; request_row<=0; request_column<=0; request_data<=0;
      directory_base<=0; directory_count<=0;
      immutable_base<=0; immutable_bytes<=0; writable_base<=0; writable_bytes<=0;
      record_index<=0; record_word<=0;
      key_kind<=0; key_layer<=0; key_projection<=0; storage_kind<=0;
      region_offset<=0; region_extent<=0; region_rows<=0; region_columns<=0;
      region_format<=0; region_permissions<=0;
      directory_offset<=0; directory_address<=0; extent_value<=0;
      element_index<=0; element_offset<=0; segment_offset<=0;
      physical_address<=0; segment_base<=0; segment_bytes<=0;
      read_data<=0; response_data<=0; response_error<=0;
      descriptor_cached<=0;
      descriptor_cache_index<=0;
    end else case (state)
      IDLE: if (mem_req_valid && mem_req_ready) begin
        request_write<=mem_req_write;
        request_kind<=mem_req_kind;
        request_layer<=mem_req_layer;
        request_projection<=mem_req_proj;
        request_row<=mem_req_row;
        request_column<=mem_req_col;
        request_data<=mem_req_wdata;
        directory_base<=cfg_directory_base;
        directory_count<=cfg_directory_count;
        immutable_base<=cfg_immutable_base;
        immutable_bytes<=cfg_immutable_bytes;
        writable_base<=cfg_writable_base;
        writable_bytes<=cfg_writable_bytes;
        record_index<=0; record_word<=0;
        descriptor_cached<=0;
        response_error<=0; response_data<=0;
        state<=CONFIG_CHECK;
      end
      CONFIG_CHECK: begin
        if (!legal_key || request_row>=expected_rows ||
            request_column>=legal_columns || (request_write && !writable_key) ||
            DIRECTORY_COUNT>64'hffffffff || directory_count!=DIRECTORY_COUNT ||
            directory_base[1:0]!=0 || directory_base<DDR_BASE ||
            directory_end[65:64]!=0 || directory_end>{1'b0,DDR_END} ||
            immutable_base[1:0]!=0 || immutable_bytes[1:0]!=0 ||
            writable_base[1:0]!=0 || writable_bytes[1:0]!=0 ||
            immutable_bytes==0 || writable_bytes==0 ||
            immutable_base<DDR_BASE || writable_base<DDR_BASE ||
            immutable_end[64] || writable_end[64] ||
            immutable_end>DDR_END || writable_end>DDR_END ||
            !((immutable_end<={1'b0,writable_base}) ||
              (writable_end<={1'b0,immutable_base})) ||
            !((directory_end<={2'b0,immutable_base}) ||
              ({1'b0,immutable_end}<={2'b0,directory_base})) ||
            !((directory_end<={2'b0,writable_base}) ||
              ({1'b0,writable_end}<={2'b0,directory_base}))) begin
          response_error<=1; state<=RETURN;
        end else state<=CACHE_LOOKUP;
      end
      CACHE_LOOKUP: begin
        if (config_valid && cache_context_matches && transaction_cacheable &&
            (cache_hit_0 || cache_hit_1)) begin
          key_kind<={28'd0,cache_kind[cache_hit_index]};
          key_layer<=cache_layer[cache_hit_index];
          key_projection<={29'd0,cache_projection[cache_hit_index]};
          storage_kind<=cache_storage_kind[cache_hit_index];
          region_offset<=cache_offset[cache_hit_index];
          region_extent<=cache_extent[cache_hit_index];
          region_rows<=cache_rows[cache_hit_index];
          region_columns<=cache_columns[cache_hit_index];
          region_format<=cache_format[cache_hit_index];
          region_permissions<=cache_permissions[cache_hit_index];
          descriptor_cached<=1;
          descriptor_cache_index<=cache_hit_index;
          state<=REGION_CHECK;
        end else state<=DIR_OFFSET;
      end
      DIR_OFFSET: begin
        directory_offset<=({33'd0,record_index} << 5)+
                          ({33'd0,record_index} << 4)+65'd32;
        state<=DIR_ADDRESS;
      end
      DIR_ADDRESS: begin
        directory_address<={1'b0,directory_base}+directory_offset;
        state<=READ_REQUEST;
      end
      READ_REQUEST: if (ddr_req_valid && ddr_req_ready) state<=READ_RESPONSE;
      READ_RESPONSE: if (ddr_rsp_valid && ddr_rsp_ready) begin
        if (ddr_rsp_error) begin
          response_error<=1; state<=RETURN;
        end else begin
          read_data<=ddr_rsp_rdata; state<=READ_CONSUME;
        end
      end
      READ_CONSUME: begin
        case (record_word)
          0: key_kind<=read_data;
          1: key_layer<=read_data;
          2: key_projection<=read_data;
          3: storage_kind<=read_data;
          4: region_offset[31:0]<=read_data;
          5: region_offset[63:32]<=read_data;
          6: region_rows<=read_data;
          7: region_columns<=read_data;
          8: region_format<=read_data;
          9: region_permissions<=read_data;
          10: region_extent[31:0]<=read_data;
          11: region_extent[63:32]<=read_data;
          default: begin end
        endcase
        if (record_word==2) state<=KEY_CHECK;
        else if (record_word==11) state<=REGION_CHECK;
        else begin
          record_word<=record_word+1'b1;
          directory_address<=directory_address+65'd4;
          state<=READ_REQUEST;
        end
      end
      KEY_CHECK: begin
        if (key_equal) begin
          record_word<=3;
          directory_address<=directory_address+65'd4;
          state<=READ_REQUEST;
        end else if (key_later || record_index+1>=directory_count) begin
          response_error<=1; state<=RETURN;
        end else begin
          record_index<=record_index+1;
          record_word<=0;
          state<=DIR_OFFSET;
        end
      end
      REGION_CHECK: begin
        if (region_rows!=expected_rows || region_columns!=expected_columns ||
            region_format!=expected_format || region_offset[1:0]!=0 ||
            region_extent[1:0]!=0 ||
            region_permissions!=(writable_key ? 32'd3 : 32'd1) ||
            storage_kind!=(writable_key ? 32'h103 : 32'h102)) begin
          response_error<=1; state<=RETURN;
        end else begin
          segment_base<=writable_key ? writable_base : immutable_base;
          segment_bytes<=writable_key ? writable_bytes : immutable_bytes;
          if (descriptor_cached && row_base_hit) begin
            element_index<={1'b0,cache_row_base[descriptor_cache_index]};
            state<=INDEX_ADD;
          end else if (descriptor_cached) state<=INDEX_MULTIPLY;
          else state<=EXTENT_MULTIPLY;
        end
      end
      EXTENT_MULTIPLY: if (multiply_ready) state<=EXTENT_WAIT;
      EXTENT_WAIT: if (multiply_valid) begin
        if (multiply_product[127:62]!=0) begin
          response_error<=1; state<=RETURN;
        end else begin
          extent_value<={multiply_product[62:0],2'b00};
          state<=EXTENT_CHECK;
        end
      end
      EXTENT_CHECK: begin
        if (!descriptor_extent_valid) begin
          response_error<=1; state<=RETURN;
        end else begin
          descriptor_cache_index<=cache_victim;
          state<=INDEX_MULTIPLY;
        end
      end
      INDEX_MULTIPLY: if (multiply_ready) state<=INDEX_WAIT;
      INDEX_WAIT: if (multiply_valid) begin
        if (multiply_product[127:64]!=0) begin
          response_error<=1; state<=RETURN;
        end else begin
          element_index<={1'b0,multiply_product[63:0]};
          state<=INDEX_ADD;
        end
      end
      INDEX_ADD: begin
        element_index<=element_index+{33'd0,request_column};
        state<=OFFSET_ADD;
      end
      OFFSET_ADD: begin
        if (element_index[64:62]!=0 || element_index>=({1'b0,region_extent} >> 2)) begin
          response_error<=1; state<=RETURN;
        end else begin
          element_offset<=element_index << 2;
          state<=SEGMENT_CHECK;
        end
      end
      SEGMENT_CHECK: begin
        segment_offset<={1'b0,region_offset}+element_offset;
        state<=PHYSICAL_ADD;
      end
      PHYSICAL_ADD: begin
        if (segment_offset[64] || segment_offset>({1'b0,segment_bytes}-65'd4)) begin
          response_error<=1; state<=RETURN;
        end else begin
          physical_address<={1'b0,segment_base}+segment_offset;
          state<=PHYSICAL_CHECK;
        end
      end
      PHYSICAL_CHECK: begin
        if (physical_address[64] || physical_address<{1'b0,DDR_BASE} ||
            physical_address>DDR_END-65'd4 || physical_address[1:0]!=0) begin
          response_error<=1; state<=RETURN;
        end else state<=DATA_REQUEST;
      end
      DATA_REQUEST: if (ddr_req_valid && ddr_req_ready) state<=DATA_RESPONSE;
      DATA_RESPONSE: if (ddr_rsp_valid && ddr_rsp_ready) begin
        response_data<=ddr_rsp_error ? 0 : ddr_rsp_rdata;
        response_error<=ddr_rsp_error;
        state<=RETURN;
      end
      RETURN: if (mem_rsp_valid && mem_rsp_ready) state<=IDLE;
      default: begin response_error<=1; response_data<=0; state<=RETURN; end
    endcase
  end
endmodule
