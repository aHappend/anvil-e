module anvil_edge_special_trie_validator #(
  parameter integer MAX_TRIE_NODES=1048576,
  parameter integer MAX_SPECIAL_RECORDS=262144,
  parameter integer MAX_TOKEN_BYTES=4096,
  parameter [63:0] DDR_BASE=0,
  parameter [63:0] DDR_BYTES=64'h0000000100000000
) (
  input wire clk, rst_n, start, manifest_valid, tokens_valid,
  input wire [1279:0] staged_segment_bases, staged_segment_bytes,
  input wire [1023:0] staged_metadata,
  input wire [511:0] staged_table_counts,
  output wire busy, done, valid_special_trie, error,
  output wire [7:0] error_code,
  output wire ddr_req_valid,
  input wire ddr_req_ready,
  output wire [63:0] ddr_req_addr,
  input wire ddr_rsp_valid,
  output wire ddr_rsp_ready,
  input wire [31:0] ddr_rsp_rdata,
  input wire ddr_rsp_error
);
  generate if (MAX_TRIE_NODES<1 || MAX_SPECIAL_RECORDS<1 || MAX_TOKEN_BYTES<1) begin : invalid_parameters
    initial $fatal(1, "ANVIL_EDGE_SPECIAL_TRIE PARAMETER ERROR: positive capacities required");
    assign busy=0; assign done=0; assign valid_special_trie=0;
    assign error=0; assign error_code=0;
    assign ddr_req_valid=0; assign ddr_req_addr=0; assign ddr_rsp_ready=0;
  end else begin : validator
    localparam [5:0] IDLE=0, CONFIG_CHECK=1, CLEAR_VISITED=2,
      SPECIAL_SETUP=3, READ_ISSUE=4, READ_WAIT=5, SPECIAL_CHECK=6,
      SPECIAL_TOKEN_SETUP=7, SPECIAL_TOKEN_CHECK=8, DUPLICATE_SETUP=9,
      DUPLICATE_CHECK=10, SPECIAL_NEXT=11, DFS_START=12, VISIT_READ=13,
      VISIT_CHECK=14, NODE_SETUP=15, NODE_EXTENT=16, NODE_CHECK=17,
      TERMINAL_SETUP=18, TERMINAL_SPECIAL=19, TERMINAL_TOKEN_SETUP=20,
      TERMINAL_TOKEN=21, PATH_ADDRESS=22, PATH_BYTE=23,
      EDGE_SELECT=24, EDGE_SETUP=25, EDGE_CHECK=26, COMPLETE=27, FAILED=28;
    reg [5:0] state, after_read;
    reg [1279:0] bases, lengths;
    reg [31:0] node_count, edge_count, special_count, token_count, raw_count;
    reg [31:0] root, maximum_length, clear_index;
    reg visited [0:MAX_TRIE_NODES-1];
    reg [31:0] stack_node [0:MAX_TOKEN_BYTES];
    reg [31:0] stack_first [0:MAX_TOKEN_BYTES];
    reg [31:0] stack_count [0:MAX_TOKEN_BYTES];
    reg [31:0] stack_cursor [0:MAX_TOKEN_BYTES];
    reg [7:0] stack_previous_byte [0:MAX_TOKEN_BYTES];
    reg stack_previous_valid [0:MAX_TOKEN_BYTES];
    reg [7:0] path_bytes [0:MAX_TOKEN_BYTES-1];
    reg [31:0] depth, visited_nodes, visited_edges;
    reg seen_node;
    reg [31:0] special_index, duplicate_index, special_token_id, terminal_index;
    reg [31:0] terminal_token_id, path_index;
    reg [63:0] terminal_byte_offset;
    reg [127:0] record_data;
    reg [64:0] edge_interval_end, raw_address, terminal_end;
    reg [1:0] raw_lane;
    reg [4:0] read_segment;
    reg [63:0] read_offset;
    reg [5:0] read_words;
    reg raw_read, done_r;
    reg [7:0] code;
    wire [31:0] w0=record_data[0+:32];
    wire [31:0] w1=record_data[32+:32];
    wire [31:0] w2=record_data[64+:32];
    wire [31:0] w3=record_data[96+:32];
    wire [31:0] selected_node=stack_node[depth];
    wire [64:0] selected_edge={33'd0,stack_first[depth]}+{33'd0,stack_cursor[depth]};
    wire [63:0] selected_length=lengths[read_segment*64+:64];
    wire [64:0] rounded_length=({1'b0,selected_length}+65'd3) & ~65'd3;
    wire [63:0] read_length=raw_read ? rounded_length[63:0] : selected_length;
    wire [64:0] raw_byte_index={1'b0,terminal_byte_offset}+{33'd0,path_index};
    wire reader_in_ready, reader_out_valid, reader_error;
    wire [1023:0] reader_data;
    wire [7:0] reader_code;

    anvil_edge_boot_segment_reader #(.DDR_BASE(DDR_BASE),.DDR_BYTES(DDR_BYTES)) reader(
      .clk(clk),.rst_n(rst_n),.in_valid(rst_n && state==READ_ISSUE),
      .in_ready(reader_in_ready),.segment_base(bases[read_segment*64+:64]),
      .segment_bytes(read_length),.byte_offset(read_offset),.word_count(read_words),
      .out_valid(reader_out_valid),.out_ready(rst_n && state==READ_WAIT),
      .data(reader_data),.response_error(reader_error),.error_code(reader_code),
      .ddr_req_valid(ddr_req_valid),.ddr_req_ready(ddr_req_ready),
      .ddr_req_addr(ddr_req_addr),.ddr_rsp_valid(ddr_rsp_valid),
      .ddr_rsp_ready(ddr_rsp_ready),.ddr_rsp_rdata(ddr_rsp_rdata),
      .ddr_rsp_error(ddr_rsp_error)
    );
    assign busy=rst_n && state!=IDLE && state!=COMPLETE && state!=FAILED;
    assign done=rst_n && done_r;
    assign valid_special_trie=rst_n && state==COMPLETE;
    assign error=rst_n && state==FAILED;
    assign error_code=rst_n ? code : 0;

    always @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
        state<=IDLE; after_read<=IDLE; bases<=0; lengths<=0;
        node_count<=0; edge_count<=0; special_count<=0; token_count<=0; raw_count<=0;
        root<=0; maximum_length<=0; clear_index<=0;
        depth<=0; visited_nodes<=0; visited_edges<=0; seen_node<=0;
        special_index<=0; duplicate_index<=0; special_token_id<=0;
        terminal_index<=0; terminal_token_id<=0; path_index<=0;
        terminal_byte_offset<=0; record_data<=0; edge_interval_end<=0;
        raw_address<=0; terminal_end<=0; raw_lane<=0;
        read_segment<=0; read_offset<=0; read_words<=0; raw_read<=0;
        done_r<=0; code<=0;
      end else begin
        done_r<=0;
        case (state)
          IDLE, COMPLETE: if (start) begin
            if (!manifest_valid || !tokens_valid) begin code<=8'h06; state<=FAILED; end
            else begin
              bases<=staged_segment_bases; lengths<=staged_segment_bytes;
              node_count<=staged_table_counts[160+:32];
              edge_count<=staged_table_counts[192+:32];
              special_count<=staged_table_counts[320+:32];
              token_count<=staged_metadata[64+:32];
              raw_count<=staged_table_counts[64+:32];
              root<=staged_metadata[416+:32];
              maximum_length<=staged_metadata[448+:32];
              clear_index<=0; special_index<=0; visited_nodes<=0; visited_edges<=0;
              code<=0; state<=CONFIG_CHECK;
            end
          end
          CONFIG_CHECK: begin
            if (node_count==0 || node_count>MAX_TRIE_NODES ||
                special_count>MAX_SPECIAL_RECORDS || root>=node_count ||
                {1'b0,edge_count}+33'd1!={1'b0,node_count} ||
                maximum_length==0 || maximum_length>MAX_TOKEN_BYTES ||
                token_count<256 || token_count>262144 || raw_count==0) begin
              code<=8'h06; state<=FAILED;
            end else state<=CLEAR_VISITED;
          end
          CLEAR_VISITED: begin
            visited[clear_index]<=0;
            if (clear_index+1==node_count) begin
              if (special_count==0) state<=DFS_START;
              else state<=SPECIAL_SETUP;
            end else clear_index<=clear_index+1'b1;
          end
          SPECIAL_SETUP: begin
            read_segment<=14; read_offset<=64'd32+({32'd0,special_index} << 4);
            read_words<=4; raw_read<=0; after_read<=SPECIAL_CHECK; state<=READ_ISSUE;
          end
          READ_ISSUE: if (reader_in_ready) state<=READ_WAIT;
          READ_WAIT: if (reader_out_valid) begin
            if (reader_error) begin code<=reader_code; state<=FAILED; end
            else begin record_data<=reader_data[127:0]; state<=after_read; end
          end
          SPECIAL_CHECK: begin
            if (w0>=token_count || w1[31:5]!=0 || w2!=0 || w3!=0) begin
              code<=8'h06; state<=FAILED;
            end else begin special_token_id<=w0; state<=SPECIAL_TOKEN_SETUP; end
          end
          SPECIAL_TOKEN_SETUP: begin
            read_segment<=5; read_offset<=64'd32+({32'd0,special_token_id} << 4);
            read_words<=4; raw_read<=0; after_read<=SPECIAL_TOKEN_CHECK; state<=READ_ISSUE;
          end
          SPECIAL_TOKEN_CHECK: begin
            if (!w3[1]) begin code<=8'h06; state<=FAILED; end
            else if (special_index==0) state<=SPECIAL_NEXT;
            else begin duplicate_index<=0; state<=DUPLICATE_SETUP; end
          end
          DUPLICATE_SETUP: begin
            read_segment<=14; read_offset<=64'd32+({32'd0,duplicate_index} << 4);
            read_words<=4; raw_read<=0; after_read<=DUPLICATE_CHECK; state<=READ_ISSUE;
          end
          DUPLICATE_CHECK: begin
            if (w0==special_token_id) begin code<=8'h06; state<=FAILED; end
            else if (duplicate_index+1==special_index) state<=SPECIAL_NEXT;
            else begin duplicate_index<=duplicate_index+1'b1; state<=DUPLICATE_SETUP; end
          end
          SPECIAL_NEXT: begin
            if (special_index+1==special_count) state<=DFS_START;
            else begin special_index<=special_index+1'b1; state<=SPECIAL_SETUP; end
          end
          DFS_START: begin depth<=0; stack_node[0]<=root; state<=VISIT_READ; end
          VISIT_READ: begin seen_node<=visited[selected_node]; state<=VISIT_CHECK; end
          VISIT_CHECK: begin
            if (seen_node) begin code<=8'h06; state<=FAILED; end
            else begin
              visited[selected_node]<=1; visited_nodes<=visited_nodes+1'b1;
              state<=NODE_SETUP;
            end
          end
          NODE_SETUP: begin
            read_segment<=9; read_offset<=64'd32+({32'd0,selected_node} << 4);
            read_words<=4; raw_read<=0; after_read<=NODE_EXTENT; state<=READ_ISSUE;
          end
          NODE_EXTENT: begin
            edge_interval_end<={33'd0,w0}+{33'd0,w1}; state<=NODE_CHECK;
          end
          NODE_CHECK: begin
            if (w3!=0 || edge_interval_end>{33'd0,edge_count} ||
                (w2!=32'hffffffff && w2>=special_count)) begin
              code<=8'h06; state<=FAILED;
            end else begin
              stack_first[depth]<=w0; stack_count[depth]<=w1; stack_cursor[depth]<=0;
              stack_previous_valid[depth]<=0; terminal_index<=w2;
              if (w2==32'hffffffff) state<=EDGE_SELECT;
              else state<=TERMINAL_SETUP;
            end
          end
          TERMINAL_SETUP: begin
            read_segment<=14; read_offset<=64'd32+({32'd0,terminal_index} << 4);
            read_words<=4; raw_read<=0; after_read<=TERMINAL_SPECIAL; state<=READ_ISSUE;
          end
          TERMINAL_SPECIAL: begin terminal_token_id<=w0; state<=TERMINAL_TOKEN_SETUP; end
          TERMINAL_TOKEN_SETUP: begin
            read_segment<=5; read_offset<=64'd32+({32'd0,terminal_token_id} << 4);
            read_words<=4; raw_read<=0; after_read<=TERMINAL_TOKEN; state<=READ_ISSUE;
          end
          TERMINAL_TOKEN: begin
            if (!w3[1] || w2!=depth) begin code<=8'h06; state<=FAILED; end
            else if (depth==0) state<=EDGE_SELECT;
            else begin
              terminal_byte_offset<=record_data[0+:64];
              terminal_end<={1'b0,record_data[0+:64]}+{33'd0,w2};
              path_index<=0; state<=PATH_ADDRESS;
            end
          end
          PATH_ADDRESS: begin
            if (terminal_end>{33'd0,raw_count} || raw_byte_index[64]) begin
              code<=8'h06; state<=FAILED;
            end else begin
              raw_address<=65'd32+raw_byte_index;
              raw_lane<=raw_byte_index[1:0];
              read_segment<=6; raw_read<=1; read_words<=1;
              state<=EDGE_SETUP;
            end
          end
          EDGE_SETUP: begin
            if (raw_read) begin
              read_offset<=raw_address[63:0] & ~64'd3;
              after_read<=PATH_BYTE;
            end else begin
              read_segment<=10;
              read_offset<=64'd32+(selected_edge[63:0] << 3);
              read_words<=2; after_read<=EDGE_CHECK;
            end
            state<=READ_ISSUE;
          end
          PATH_BYTE: begin
            if (record_data[raw_lane*8+:8]!=path_bytes[path_index]) begin
              code<=8'h06; state<=FAILED;
            end else if (path_index+1==depth) state<=EDGE_SELECT;
            else begin path_index<=path_index+1'b1; state<=PATH_ADDRESS; end
          end
          EDGE_SELECT: begin
            if (stack_cursor[depth]==stack_count[depth]) begin
              if (depth==0) begin
                if (visited_nodes!=node_count || visited_edges!=edge_count) begin
                  code<=8'h06; state<=FAILED;
                end else begin done_r<=1; state<=COMPLETE; end
              end else begin depth<=depth-1'b1; state<=EDGE_SELECT; end
            end else begin raw_read<=0; state<=EDGE_SETUP; end
          end
          EDGE_CHECK: begin
            if (w0>255 || w1>=node_count ||
                (stack_previous_valid[depth] && w0<={24'd0,stack_previous_byte[depth]}) ||
                depth>=MAX_TOKEN_BYTES || depth>=maximum_length) begin
              code<=8'h06; state<=FAILED;
            end else begin
              stack_cursor[depth]<=stack_cursor[depth]+1'b1;
              stack_previous_byte[depth]<=w0[7:0]; stack_previous_valid[depth]<=1;
              path_bytes[depth]<=w0[7:0]; stack_node[depth+1'b1]<=w1;
              visited_edges<=visited_edges+1'b1; depth<=depth+1'b1; state<=VISIT_READ;
            end
          end
          FAILED: state<=FAILED;
          default: begin code<=8'h06; state<=FAILED; end
        endcase
      end
    end
  end endgenerate
endmodule
