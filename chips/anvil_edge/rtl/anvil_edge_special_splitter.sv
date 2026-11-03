module anvil_edge_special_splitter #(
  parameter integer MAX_SPAN_BYTES=4096
) (
  input wire clk, rst_n, start, config_valid, normalized_phase,
  input wire [1023:0] cfg_table_bases, cfg_metadata,
  input wire [511:0] cfg_table_counts,
  input wire in_valid,
  output wire in_ready,
  input wire [31:0] in_scalar,
  input wire in_last,
  output wire out_valid,
  input wire out_ready,
  output wire [31:0] out_value,
  output wire out_special, out_boundary, out_last,
  output wire busy, done, error,
  output wire [7:0] error_code,
  output wire tbl_req_valid,
  input wire tbl_req_ready,
  output wire [63:0] tbl_req_addr,
  input wire tbl_rsp_valid,
  output wire tbl_rsp_ready,
  input wire [31:0] tbl_rsp_data,
  input wire tbl_rsp_error
);
  generate if (MAX_SPAN_BYTES<1) begin : invalid_parameters
    initial $fatal(1,"ANVIL_EDGE_SPECIAL_SPLITTER PARAMETER ERROR: positive capacity required");
    assign in_ready=0; assign out_valid=0; assign out_value=0;
    assign out_special=0; assign out_boundary=0; assign out_last=0;
    assign busy=0; assign done=0; assign error=0; assign error_code=0;
    assign tbl_req_valid=0; assign tbl_req_addr=0; assign tbl_rsp_ready=0;
  end else begin : splitter
    localparam [5:0] IDLE=0, CAPTURE=1, CLASS_ISSUE=2, CLASS_WAIT=3,
      ENCODE_START=4, ENCODE_ISSUE=5, ENCODE_WAIT=6, SCAN=7,
      NODE_ISSUE=8, NODE_WAIT=9, NODE_CHECK=10, SPECIAL_ISSUE=11,
      SPECIAL_WAIT=12, SPECIAL_CHECK=13, EDGE_SELECT=14, EDGE_ISSUE=15,
      EDGE_WAIT=16, EDGE_CHECK=17, CHOOSE=18, STRIP_LEFT=19,
      APPEND_SPECIAL=20, STRIP_RIGHT=21, APPEND_SCALAR=22,
      EMIT=23, CLOSED=24, FAILED=25, EMIT_LOAD=26;
    reg [5:0] state;
    reg [31:0] scalars [0:MAX_SPAN_BYTES-1];
    reg [9:0] properties [0:MAX_SPAN_BYTES-1];
    reg [7:0] bytes_memory [0:MAX_SPAN_BYTES-1];
    reg [31:0] scalar_starts [0:MAX_SPAN_BYTES-1];
    reg [31:0] byte_ends [0:MAX_SPAN_BYTES-1];
    reg [31:0] plan_value [0:MAX_SPAN_BYTES-1];
    reg plan_special [0:MAX_SPAN_BYTES-1];
    reg plan_space [0:MAX_SPAN_BYTES-1];
    reg [31:0] scalar_count, scalar_index, byte_count, scan_index, cursor;
    reg [31:0] plan_count, output_index;
    reg [2:0] encoded_remaining;
    reg [31:0] node_index, edge_first, edge_count, edge_cursor, terminal_index;
    reg [31:0] best_end, best_token, best_flags, best_record;
    reg best_valid, phase, done_r;
    reg [31:0] output_value;
    reg output_special, output_boundary, output_last;
    reg [127:0] node_record, special_record;
    reg [63:0] edge_record;
    reg [7:0] code;
    wire classify_selected=state==CLASS_ISSUE || state==CLASS_WAIT;
    wire edge_selected=state==EDGE_ISSUE || state==EDGE_WAIT;
    wire special_selected=state==SPECIAL_ISSUE || state==SPECIAL_WAIT;
    wire class_ready, class_valid, class_error, class_req, class_rsp_ready;
    wire [31:0] class_properties;
    wire [7:0] class_code;
    wire [63:0] class_address;
    wire record_ready, record_valid, record_error, record_req, record_rsp_ready;
    wire [127:0] record_data;
    wire [7:0] record_code;
    wire [63:0] record_address;
    wire edge_ready, edge_valid, edge_error, edge_req, edge_rsp_ready;
    wire [63:0] edge_data, edge_address;
    wire [7:0] edge_code;
    wire encoder_ready, encoder_valid, encoder_error;
    wire [7:0] encoder_data, encoder_code;
    wire [32:0] edge_end={1'b0,edge_first}+{1'b0,edge_count};
    wire [32:0] edge_index={1'b0,edge_first}+{1'b0,edge_cursor};
    wire [31:0] terminal_end=cursor==0 ? 0 : byte_ends[cursor-1];
    wire left_word=scan_index!=0 && properties[scan_index-1][9];
    wire right_word=terminal_end<scalar_count && properties[terminal_end][9];
    wire [31:0] special_flags=special_record[63:32];
    wire eligible=special_flags[0] && special_flags[4]==phase &&
      (!special_flags[3] || (!left_word && !right_word));
    wire active=rst_n && state!=IDLE && state!=CLOSED && state!=FAILED;

    anvil_edge_unicode_lookup classification(
      .clk(clk),.rst_n(rst_n),.in_valid(rst_n && state==CLASS_ISSUE),
      .in_ready(class_ready),.in_scalar(scalars[scalar_index]),
      .config_valid(config_valid),.cfg_ranges_base(cfg_table_bases[7*64+:64]),
      .cfg_range_count(cfg_table_counts[7*32+:32]),
      .cfg_class_count(cfg_metadata[9*32+:32]),.out_valid(class_valid),
      .out_ready(rst_n && state==CLASS_WAIT),.out_class_id(),
      .out_properties(class_properties),.response_error(class_error),
      .response_error_code(class_code),.tbl_req_valid(class_req),
      .tbl_req_ready(classify_selected && tbl_req_ready),
      .tbl_req_addr(class_address),.tbl_rsp_valid(classify_selected && tbl_rsp_valid),
      .tbl_rsp_ready(class_rsp_ready),.tbl_rsp_data(tbl_rsp_data),
      .tbl_rsp_error(tbl_rsp_error)
    );
    anvil_edge_utf8_encoder encoder(
      .clk(clk),.rst_n(rst_n),.start(rst_n && state==ENCODE_START),
      .in_valid(rst_n && state==ENCODE_ISSUE),.in_ready(encoder_ready),
      .in_scalar(scalars[scalar_index]),.in_last(scalar_index+1==scalar_count),
      .out_valid(encoder_valid),.out_ready(rst_n && state==ENCODE_WAIT),
      .out_data(encoder_data),.out_last(),.busy(),.done(),
      .error(encoder_error),.error_code(encoder_code)
    );
    anvil_edge_table_record_reader #(.LOG2_RECORD_BYTES(4)) records(
      .clk(clk),.rst_n(rst_n),
      .in_valid(rst_n && (state==NODE_ISSUE || state==SPECIAL_ISSUE)),
      .in_ready(record_ready),
      .segment_base(special_selected ? cfg_table_bases[10*64+:64] :
                                       cfg_table_bases[5*64+:64]),
      .record_count(special_selected ? cfg_table_counts[10*32+:32] :
                                       cfg_table_counts[5*32+:32]),
      .record_index(special_selected ? terminal_index : node_index),
      .out_valid(record_valid),
      .out_ready(rst_n && (state==NODE_WAIT || state==SPECIAL_WAIT)),
      .record_data(record_data),.response_error(record_error),
      .response_error_code(record_code),.tbl_req_valid(record_req),
      .tbl_req_ready(!classify_selected && !edge_selected && tbl_req_ready),
      .tbl_req_addr(record_address),
      .tbl_rsp_valid(!classify_selected && !edge_selected && tbl_rsp_valid),
      .tbl_rsp_ready(record_rsp_ready),.tbl_rsp_data(tbl_rsp_data),
      .tbl_rsp_error(tbl_rsp_error)
    );
    anvil_edge_table_record_reader #(.LOG2_RECORD_BYTES(3)) edges(
      .clk(clk),.rst_n(rst_n),.in_valid(rst_n && state==EDGE_ISSUE),
      .in_ready(edge_ready),.segment_base(cfg_table_bases[6*64+:64]),
      .record_count(cfg_table_counts[6*32+:32]),.record_index(edge_index[31:0]),
      .out_valid(edge_valid),.out_ready(rst_n && state==EDGE_WAIT),
      .record_data(edge_data),.response_error(edge_error),
      .response_error_code(edge_code),.tbl_req_valid(edge_req),
      .tbl_req_ready(edge_selected && tbl_req_ready),.tbl_req_addr(edge_address),
      .tbl_rsp_valid(edge_selected && tbl_rsp_valid),.tbl_rsp_ready(edge_rsp_ready),
      .tbl_rsp_data(tbl_rsp_data),.tbl_rsp_error(tbl_rsp_error)
    );
    assign tbl_req_valid=classify_selected ? class_req :
      (edge_selected ? edge_req : record_req);
    assign tbl_req_addr=classify_selected ? class_address :
      (edge_selected ? edge_address : record_address);
    assign tbl_rsp_ready=classify_selected ? class_rsp_ready :
      (edge_selected ? edge_rsp_ready : record_rsp_ready);
    assign in_ready=rst_n && state==CAPTURE;
    assign out_valid=rst_n && state==EMIT;
    assign out_value=out_valid ? output_value : 0;
    assign out_special=out_valid && output_special;
    assign out_last=out_valid && output_last;
    assign out_boundary=out_valid && output_boundary;
    assign busy=active;
    assign done=rst_n && done_r;
    assign error=rst_n && state==FAILED;
    assign error_code=rst_n ? code : 0;

    always @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
        state<=IDLE; scalar_count<=0; scalar_index<=0; byte_count<=0;
        scan_index<=0; cursor<=0; plan_count<=0; output_index<=0;
        encoded_remaining<=0; node_index<=0; edge_first<=0; edge_count<=0;
        edge_cursor<=0; terminal_index<=0; best_end<=0; best_token<=0;
        best_flags<=0; best_record<=0; best_valid<=0; phase<=0; done_r<=0;
        node_record<=0; special_record<=0; edge_record<=0; code<=0;
        output_value<=0; output_special<=0; output_boundary<=0; output_last<=0;
      end else begin
        done_r<=0;
        if (active && encoder_error) begin code<=encoder_code; state<=FAILED; end
        else case (state)
          IDLE, CLOSED: if (start) begin
            if (!config_valid || cfg_metadata[4*32+:32]>2 ||
                cfg_metadata[13*32+:32]>=cfg_table_counts[5*32+:32]) begin
              code<=8'h06; state<=FAILED;
            end else begin
              scalar_count<=0; scalar_index<=0; byte_count<=0; scan_index<=0;
              plan_count<=0; output_index<=0; phase<=normalized_phase;
              code<=0; state<=CAPTURE;
            end
          end
          CAPTURE: if (in_valid && in_ready) begin
            if (scalar_count>=MAX_SPAN_BYTES) begin code<=8'h30; state<=FAILED; end
            else begin
              scalars[scalar_count]<=in_scalar; scalar_count<=scalar_count+1;
              if (in_last) begin scalar_index<=0; state<=CLASS_ISSUE; end
              else if (scalar_count+1==MAX_SPAN_BYTES) begin
                code<=8'h30; state<=FAILED;
              end
            end
          end
          CLASS_ISSUE: if (class_ready) state<=CLASS_WAIT;
          CLASS_WAIT: if (class_valid) begin
            if (class_error) begin code<=class_code; state<=FAILED; end
            else begin
              properties[scalar_index]<=class_properties[9:0];
              if (scalar_index+1==scalar_count) begin
                scalar_index<=0; state<=ENCODE_START;
              end else begin scalar_index<=scalar_index+1; state<=CLASS_ISSUE; end
            end
          end
          ENCODE_START: state<=ENCODE_ISSUE;
          ENCODE_ISSUE: if (encoder_ready) begin
            scalar_starts[scalar_index]<=byte_count;
            if (scalars[scalar_index]<32'h80) encoded_remaining<=1;
            else if (scalars[scalar_index]<32'h800) encoded_remaining<=2;
            else if (scalars[scalar_index]<32'h10000) encoded_remaining<=3;
            else encoded_remaining<=4;
            state<=ENCODE_WAIT;
          end
          ENCODE_WAIT: if (encoder_valid) begin
            if (byte_count>=MAX_SPAN_BYTES) begin code<=8'h30; state<=FAILED; end
            else begin
              bytes_memory[byte_count]<=encoder_data;
              byte_ends[byte_count]<=encoded_remaining==1 ? scalar_index+1 : 0;
              byte_count<=byte_count+1; encoded_remaining<=encoded_remaining-1'b1;
              if (encoded_remaining==1) begin
                if (scalar_index+1==scalar_count) state<=SCAN;
                else begin scalar_index<=scalar_index+1; state<=ENCODE_ISSUE; end
              end
            end
          end
          SCAN: begin
            if (scan_index==scalar_count) begin output_index<=0; state<=EMIT_LOAD; end
            else if (cfg_metadata[4*32+:32]==0) state<=APPEND_SCALAR;
            else begin
              node_index<=cfg_metadata[13*32+:32];
              cursor<=scalar_starts[scan_index]; best_valid<=0;
              state<=NODE_ISSUE;
            end
          end
          NODE_ISSUE: if (record_ready) state<=NODE_WAIT;
          NODE_WAIT: if (record_valid) begin
            if (record_error) begin code<=record_code; state<=FAILED; end
            else begin node_record<=record_data; state<=NODE_CHECK; end
          end
          NODE_CHECK: begin
            edge_first<=node_record[31:0]; edge_count<=node_record[63:32];
            edge_cursor<=0; terminal_index<=node_record[95:64];
            if (node_record[127:96]!=0) begin code<=8'h12; state<=FAILED; end
            else if (cursor>scalar_starts[scan_index] && terminal_end!=0 &&
                     node_record[95:64]!=32'hffffffff) state<=SPECIAL_ISSUE;
            else state<=EDGE_SELECT;
          end
          SPECIAL_ISSUE: if (record_ready) state<=SPECIAL_WAIT;
          SPECIAL_WAIT: if (record_valid) begin
            if (record_error) begin code<=record_code; state<=FAILED; end
            else begin special_record<=record_data; state<=SPECIAL_CHECK; end
          end
          SPECIAL_CHECK: begin
            if (special_record[127:64]!=0 || special_flags[31:5]!=0 ||
                special_record[31:0]>=cfg_metadata[2*32+:32]) begin
              code<=8'h12; state<=FAILED;
            end else begin
              if (eligible && (!best_valid || terminal_end>best_end ||
                  (terminal_end==best_end && terminal_index<best_record))) begin
                best_valid<=1; best_end<=terminal_end;
                best_token<=special_record[31:0]; best_flags<=special_flags;
                best_record<=terminal_index;
              end
              state<=EDGE_SELECT;
            end
          end
          EDGE_SELECT: begin
            if (edge_end>{1'b0,cfg_table_counts[6*32+:32]}) begin
              code<=8'h12; state<=FAILED;
            end else if (cursor==byte_count || edge_cursor==edge_count)
              state<=CHOOSE;
            else state<=EDGE_ISSUE;
          end
          EDGE_ISSUE: if (edge_ready) state<=EDGE_WAIT;
          EDGE_WAIT: if (edge_valid) begin
            if (edge_error) begin code<=edge_code; state<=FAILED; end
            else begin edge_record<=edge_data; state<=EDGE_CHECK; end
          end
          EDGE_CHECK: begin
            if (edge_record[31:0]>255 ||
                edge_record[63:32]>=cfg_table_counts[5*32+:32]) begin
              code<=8'h12; state<=FAILED;
            end else if (edge_record[7:0]==bytes_memory[cursor]) begin
              node_index<=edge_record[63:32]; cursor<=cursor+1; state<=NODE_ISSUE;
            end else if (edge_record[7:0]>bytes_memory[cursor]) state<=CHOOSE;
            else begin edge_cursor<=edge_cursor+1; state<=EDGE_SELECT; end
          end
          CHOOSE: begin
            if (!best_valid) state<=APPEND_SCALAR;
            else if (cfg_metadata[4*32+:32]==2) begin code<=8'h13; state<=FAILED; end
            else state<=STRIP_LEFT;
          end
          STRIP_LEFT: begin
            if (best_flags[1] && plan_count!=0 &&
                !plan_special[plan_count-1] && plan_space[plan_count-1])
              plan_count<=plan_count-1;
            else state<=APPEND_SPECIAL;
          end
          APPEND_SPECIAL: begin
            if (plan_count>=MAX_SPAN_BYTES) begin code<=8'h30; state<=FAILED; end
            else begin
              plan_value[plan_count]<=best_token; plan_special[plan_count]<=1;
              plan_space[plan_count]<=0; plan_count<=plan_count+1;
              scan_index<=best_end; state<=STRIP_RIGHT;
            end
          end
          STRIP_RIGHT: begin
            if (best_flags[2] && scan_index<scalar_count && properties[scan_index][8])
              scan_index<=scan_index+1;
            else state<=SCAN;
          end
          APPEND_SCALAR: begin
            if (plan_count>=MAX_SPAN_BYTES) begin code<=8'h30; state<=FAILED; end
            else begin
              plan_value[plan_count]<=scalars[scan_index];
              plan_special[plan_count]<=0;
              plan_space[plan_count]<=properties[scan_index][8];
              plan_count<=plan_count+1; scan_index<=scan_index+1; state<=SCAN;
            end
          end
          EMIT_LOAD: begin
            output_value<=plan_value[output_index];
            output_special<=plan_special[output_index];
            output_last<=output_index+1==plan_count;
            output_boundary<=!plan_special[output_index] &&
              (output_index+1==plan_count || plan_special[output_index+1]);
            state<=EMIT;
          end
          EMIT: if (out_valid && out_ready) begin
            if (output_last) begin done_r<=1; state<=CLOSED; end
            else begin output_index<=output_index+1; state<=EMIT_LOAD; end
          end
          FAILED: state<=FAILED;
          default: begin code<=8'h12; state<=FAILED; end
        endcase
      end
    end
  end endgenerate
endmodule
