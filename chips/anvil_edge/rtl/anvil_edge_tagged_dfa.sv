module anvil_edge_tagged_dfa #(
  parameter integer MAX_SPAN_BYTES=4096,
  parameter integer MAX_TAG_REGISTERS=32
) (
  input wire clk, rst_n, start,
  input wire config_valid,
  input wire [63:0] cfg_ranges_base, cfg_states_base, cfg_transitions_base,
    cfg_tag_ops_base, cfg_accepts_base,
  input wire [31:0] cfg_range_count, cfg_class_count, cfg_state_count,
    cfg_transition_count, cfg_tag_op_count, cfg_accept_count,
    cfg_start_state, cfg_dead_state, cfg_tag_register_count,
  input wire in_valid,
  output wire in_ready,
  input wire [31:0] in_scalar,
  input wire in_last,
  output wire out_valid,
  input wire out_ready,
  output wire [31:0] out_start, out_end,
  output wire out_last,
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
  generate if (MAX_SPAN_BYTES<1 || MAX_TAG_REGISTERS<32) begin : invalid_parameters
    initial $fatal(1, "ANVIL_EDGE_DFA PARAMETER ERROR: positive span bytes and at least 32 tags required");
    assign in_ready=0; assign out_valid=0; assign out_start=0;
    assign out_end=0; assign out_last=0;
    assign busy=0; assign done=0; assign error=0; assign error_code=0;
    assign tbl_req_valid=0; assign tbl_req_addr=0; assign tbl_rsp_ready=0;
  end else begin : dfa
    localparam [4:0] IDLE=0, CAPTURE=1, CLASSIFY_ISSUE=2, CLASSIFY_WAIT=3,
      CLEAR_TAGS=4, ANCHOR_START=5, READ_ISSUE=6, READ_WAIT=7,
      STATE_CHECK=8, TRANSITION_SELECT=9, TRANSITION_CHECK=10,
      OP_CHECK=11, ACCEPT_CHECK=12, AFTER_ACCEPTS=13, SCAN_FINISH=14,
      EMIT=15, CLOSED=16, FAILED=17;
    localparam [1:0] STATE_RECORD=0, TRANSITION_RECORD=1, OP_RECORD=2,
      ACCEPT_RECORD=3;
    reg [4:0] state;
    reg [31:0] classes [0:MAX_SPAN_BYTES-1];
    reg [31:0] scalar_ends [0:MAX_SPAN_BYTES-1];
    reg tag_valid [0:MAX_TAG_REGISTERS-1];
    reg [31:0] tag_bytes [0:MAX_TAG_REGISTERS-1];
    reg [31:0] tag_scalars [0:MAX_TAG_REGISTERS-1];
    reg [63:0] ranges_base, states_base, transitions_base, tag_ops_base, accepts_base;
    reg [31:0] range_count, class_count, state_count, transition_count;
    reg [31:0] tag_op_count, accept_count, start_state, dead_state, tag_count;
    reg [31:0] scalar_count, byte_count, pending_scalar, pending_end;
    reg pending_last;
    reg [31:0] anchor_index, anchor_byte, cursor_index, cursor_byte, clear_index;
    reg [31:0] current_state, state_first_transition;
    reg [31:0] step_before_index, step_before_byte, step_after_index, step_after_byte;
    reg step_end_symbol, end_consumed, evaluate_state;
    reg [31:0] op_cursor, op_remaining, accept_cursor, accept_remaining;
    reg [1:0] read_kind;
    reg [31:0] read_index;
    reg [127:0] read_value;
    reg best_valid, best_shortest;
    reg [31:0] best_priority, best_end_byte, best_end_index;
    reg done_r;
    reg [7:0] code;
    reg [63:0] record_base;
    reg [31:0] record_count;
    wire classify_selected=state==CLASSIFY_ISSUE || state==CLASSIFY_WAIT;
    wire [32:0] scalar_bytes=in_scalar<32'h80 ? 33'd1 :
      (in_scalar<32'h800 ? 33'd2 : (in_scalar<32'h10000 ? 33'd3 : 33'd4));
    wire [32:0] input_end={1'b0,byte_count}+scalar_bytes;
    wire [32:0] state_transition_end={1'b0,read_value[31:0]}+
      {1'b0,class_count}+33'd1;
    wire [32:0] state_accept_end={1'b0,read_value[63:32]}+
      {1'b0,read_value[95:64]};
    wire [32:0] transition_op_end={1'b0,read_value[63:32]}+
      {1'b0,read_value[95:64]};
    wire record_ready, record_valid, record_error, record_tbl_valid, record_tbl_ready;
    wire [7:0] record_code;
    wire [127:0] record_data;
    wire [63:0] record_tbl_address;
    wire class_ready, class_valid, class_error, class_tbl_valid, class_tbl_ready;
    wire [7:0] class_code;
    wire [31:0] class_value;
    wire [63:0] class_tbl_address;

    always @* begin
      record_base=0;
      record_count=0;
      case (read_kind)
        STATE_RECORD: begin record_base=states_base; record_count=state_count; end
        TRANSITION_RECORD: begin
          record_base=transitions_base; record_count=transition_count;
        end
        OP_RECORD: begin record_base=tag_ops_base; record_count=tag_op_count; end
        ACCEPT_RECORD: begin record_base=accepts_base; record_count=accept_count; end
      endcase
    end
    anvil_edge_table_record_reader #(.LOG2_RECORD_BYTES(4)) records(
      .clk(clk),.rst_n(rst_n),.in_valid(rst_n && state==READ_ISSUE),
      .in_ready(record_ready),.segment_base(record_base),.record_count(record_count),
      .record_index(read_index),.out_valid(record_valid),
      .out_ready(rst_n && state==READ_WAIT),.record_data(record_data),
      .response_error(record_error),.response_error_code(record_code),
      .tbl_req_valid(record_tbl_valid),
      .tbl_req_ready(!classify_selected && tbl_req_ready),
      .tbl_req_addr(record_tbl_address),
      .tbl_rsp_valid(!classify_selected && tbl_rsp_valid),
      .tbl_rsp_ready(record_tbl_ready),.tbl_rsp_data(tbl_rsp_data),
      .tbl_rsp_error(tbl_rsp_error)
    );
    anvil_edge_unicode_lookup classification(
      .clk(clk),.rst_n(rst_n),.in_valid(rst_n && state==CLASSIFY_ISSUE),
      .in_ready(class_ready),.in_scalar(pending_scalar),.config_valid(1'b1),
      .cfg_ranges_base(ranges_base),.cfg_range_count(range_count),
      .cfg_class_count(class_count),.out_valid(class_valid),
      .out_ready(rst_n && state==CLASSIFY_WAIT),.out_class_id(class_value),
      .out_properties(),.response_error(class_error),.response_error_code(class_code),
      .tbl_req_valid(class_tbl_valid),
      .tbl_req_ready(classify_selected && tbl_req_ready),
      .tbl_req_addr(class_tbl_address),
      .tbl_rsp_valid(classify_selected && tbl_rsp_valid),
      .tbl_rsp_ready(class_tbl_ready),.tbl_rsp_data(tbl_rsp_data),
      .tbl_rsp_error(tbl_rsp_error)
    );

    assign tbl_req_valid=classify_selected ? class_tbl_valid : record_tbl_valid;
    assign tbl_req_addr=classify_selected ? class_tbl_address : record_tbl_address;
    assign tbl_rsp_ready=classify_selected ? class_tbl_ready : record_tbl_ready;
    assign in_ready=rst_n && state==CAPTURE;
    assign out_valid=rst_n && state==EMIT;
    assign out_start=out_valid ? anchor_byte : 0;
    assign out_end=out_valid ? best_end_byte : 0;
    assign out_last=out_valid && best_end_index==scalar_count;
    assign busy=rst_n && state!=IDLE && state!=CLOSED && state!=FAILED;
    assign done=rst_n && done_r;
    assign error=rst_n && state==FAILED;
    assign error_code=rst_n ? code : 0;

    always @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
        state<=IDLE; ranges_base<=0; states_base<=0; transitions_base<=0;
        tag_ops_base<=0; accepts_base<=0;
        range_count<=0; class_count<=0; state_count<=0; transition_count<=0;
        tag_op_count<=0; accept_count<=0; start_state<=0; dead_state<=0; tag_count<=0;
        scalar_count<=0; byte_count<=0; pending_scalar<=0; pending_end<=0;
        pending_last<=0; anchor_index<=0; anchor_byte<=0;
        cursor_index<=0; cursor_byte<=0; clear_index<=0;
        current_state<=0; state_first_transition<=0;
        step_before_index<=0; step_before_byte<=0; step_after_index<=0;
        step_after_byte<=0; step_end_symbol<=0; end_consumed<=0; evaluate_state<=0;
        op_cursor<=0; op_remaining<=0; accept_cursor<=0; accept_remaining<=0;
        read_kind<=STATE_RECORD; read_index<=0; read_value<=0;
        best_valid<=0; best_shortest<=0; best_priority<=0;
        best_end_byte<=0; best_end_index<=0; done_r<=0; code<=0;
      end else begin
        done_r<=0;
        case (state)
          IDLE, CLOSED: if (start) begin
            if (!config_valid || cfg_range_count==0 || cfg_class_count==0 ||
                cfg_state_count==0 || cfg_start_state>=cfg_state_count ||
                cfg_dead_state>=cfg_state_count || cfg_tag_register_count==0 ||
                cfg_tag_register_count>MAX_TAG_REGISTERS ||
                cfg_ranges_base[1:0]!=0 || cfg_states_base[1:0]!=0 ||
                cfg_transitions_base[1:0]!=0 || cfg_tag_ops_base[1:0]!=0 ||
                cfg_accepts_base[1:0]!=0) begin
              code<=8'h06; state<=FAILED;
            end else begin
              ranges_base<=cfg_ranges_base; states_base<=cfg_states_base;
              transitions_base<=cfg_transitions_base;
              tag_ops_base<=cfg_tag_ops_base; accepts_base<=cfg_accepts_base;
              range_count<=cfg_range_count; class_count<=cfg_class_count;
              state_count<=cfg_state_count; transition_count<=cfg_transition_count;
              tag_op_count<=cfg_tag_op_count; accept_count<=cfg_accept_count;
              start_state<=cfg_start_state; dead_state<=cfg_dead_state;
              tag_count<=cfg_tag_register_count;
              scalar_count<=0; byte_count<=0; anchor_index<=0; anchor_byte<=0;
              best_valid<=0; clear_index<=0; code<=0; state<=CAPTURE;
            end
          end
          CAPTURE: if (in_valid && in_ready) begin
            if (in_scalar>32'h10ffff ||
                (in_scalar>=32'hd800 && in_scalar<=32'hdfff)) begin
              code<=8'h10; state<=FAILED;
            end else if (scalar_count>=MAX_SPAN_BYTES || input_end>MAX_SPAN_BYTES ||
                         input_end[32]) begin
              code<=8'h30; state<=FAILED;
            end else begin
              pending_scalar<=in_scalar; pending_last<=in_last;
              pending_end<=input_end[31:0]; byte_count<=input_end[31:0];
              state<=CLASSIFY_ISSUE;
            end
          end
          CLASSIFY_ISSUE: if (class_ready) state<=CLASSIFY_WAIT;
          CLASSIFY_WAIT: if (class_valid) begin
            if (class_error) begin code<=class_code; state<=FAILED; end
            else begin
              classes[scalar_count]<=class_value;
              scalar_ends[scalar_count]<=pending_end;
              scalar_count<=scalar_count+1;
              if (pending_last) begin
                clear_index<=0; state<=CLEAR_TAGS;
              end else state<=CAPTURE;
            end
          end
          CLEAR_TAGS: begin
            tag_valid[clear_index]<=0; tag_bytes[clear_index]<=0;
            tag_scalars[clear_index]<=0;
            if (clear_index+1==tag_count) state<=ANCHOR_START;
            else clear_index<=clear_index+1;
          end
          ANCHOR_START: begin
            best_valid<=0; best_priority<=0; best_shortest<=0;
            best_end_byte<=0; best_end_index<=0;
            cursor_index<=anchor_index; cursor_byte<=anchor_byte;
            current_state<=start_state; end_consumed<=0; evaluate_state<=0;
            read_kind<=STATE_RECORD; read_index<=start_state;
            state<=READ_ISSUE;
          end
          READ_ISSUE: if (record_ready) state<=READ_WAIT;
          READ_WAIT: if (record_valid) begin
            if (record_error) begin code<=record_code; state<=FAILED; end
            else begin
              read_value<=record_data;
              case (read_kind)
                STATE_RECORD: state<=STATE_CHECK;
                TRANSITION_RECORD: state<=TRANSITION_CHECK;
                OP_RECORD: state<=OP_CHECK;
                ACCEPT_RECORD: state<=ACCEPT_CHECK;
              endcase
            end
          end
          STATE_CHECK: begin
            if (read_value[127:96]!=0 ||
                state_transition_end>{1'b0,transition_count} ||
                state_accept_end>{1'b0,accept_count} ||
                (current_state==dead_state && read_value[95:64]!=0)) begin
              code<=8'h12; state<=FAILED;
            end else begin
              state_first_transition<=read_value[31:0];
              if (!evaluate_state) begin
                if (current_state==dead_state) state<=SCAN_FINISH;
                else state<=TRANSITION_SELECT;
              end else if (read_value[95:64]==0) state<=AFTER_ACCEPTS;
              else begin
                accept_cursor<=read_value[63:32]; accept_remaining<=read_value[95:64];
                read_kind<=ACCEPT_RECORD; read_index<=read_value[63:32];
                state<=READ_ISSUE;
              end
            end
          end
          TRANSITION_SELECT: begin
            step_before_index<=cursor_index; step_before_byte<=cursor_byte;
            read_kind<=TRANSITION_RECORD;
            if (cursor_index<scalar_count) begin
              read_index<=state_first_transition+classes[cursor_index];
              step_after_index<=cursor_index+1;
              step_after_byte<=scalar_ends[cursor_index]; step_end_symbol<=0;
              state<=READ_ISSUE;
            end else if (cursor_index==scalar_count && !end_consumed) begin
              read_index<=state_first_transition+class_count;
              step_after_index<=cursor_index; step_after_byte<=cursor_byte;
              step_end_symbol<=1; state<=READ_ISSUE;
            end else begin code<=8'h12; state<=FAILED; end
          end
          TRANSITION_CHECK: begin
            if (read_value[31:0]>=state_count || read_value[127:96]!=0 ||
                transition_op_end>{1'b0,tag_op_count}) begin
              code<=8'h12; state<=FAILED;
            end else begin
              current_state<=read_value[31:0];
              cursor_index<=step_after_index; cursor_byte<=step_after_byte;
              end_consumed<=step_end_symbol;
              if (read_value[95:64]==0) begin
                evaluate_state<=1; read_kind<=STATE_RECORD;
                read_index<=read_value[31:0]; state<=READ_ISSUE;
              end else begin
                op_cursor<=read_value[63:32]; op_remaining<=read_value[95:64];
                read_kind<=OP_RECORD; read_index<=read_value[63:32];
                state<=READ_ISSUE;
              end
            end
          end
          OP_CHECK: begin
            if (read_value[31:0]>3 || read_value[63:32]>=tag_count ||
                read_value[127:96]!=0 ||
                (read_value[31:0]!=3 && read_value[95:64]!=0) ||
                (read_value[31:0]==3 && read_value[95:64]>=tag_count)) begin
              code<=8'h12; state<=FAILED;
            end else begin
              case (read_value[31:0])
                0: begin
                  tag_valid[read_value[63:32]]<=0;
                  tag_bytes[read_value[63:32]]<=0;
                  tag_scalars[read_value[63:32]]<=0;
                end
                1: begin
                  tag_valid[read_value[63:32]]<=1;
                  tag_bytes[read_value[63:32]]<=step_before_byte;
                  tag_scalars[read_value[63:32]]<=step_before_index;
                end
                2: begin
                  tag_valid[read_value[63:32]]<=1;
                  tag_bytes[read_value[63:32]]<=step_after_byte;
                  tag_scalars[read_value[63:32]]<=step_after_index;
                end
                3: begin
                  tag_valid[read_value[63:32]]<=tag_valid[read_value[95:64]];
                  tag_bytes[read_value[63:32]]<=tag_bytes[read_value[95:64]];
                  tag_scalars[read_value[63:32]]<=tag_scalars[read_value[95:64]];
                end
              endcase
              if (op_remaining>1) begin
                op_cursor<=op_cursor+1; op_remaining<=op_remaining-1;
                read_index<=op_cursor+1; state<=READ_ISSUE;
              end else begin
                evaluate_state<=1; read_kind<=STATE_RECORD;
                read_index<=current_state; state<=READ_ISSUE;
              end
            end
          end
          ACCEPT_CHECK: begin
            if (read_value[63:32]>=tag_count || read_value[95:64]>1 ||
                read_value[127:96]!=0 ||
                (best_valid && read_value[31:0]==best_priority &&
                 read_value[64]!=best_shortest)) begin
              code<=8'h12; state<=FAILED;
            end else begin
              if (tag_valid[read_value[63:32]] &&
                  tag_bytes[read_value[63:32]]>anchor_byte &&
                  tag_bytes[read_value[63:32]]<=cursor_byte &&
                  tag_scalars[read_value[63:32]]>anchor_index &&
                  tag_scalars[read_value[63:32]]<=cursor_index) begin
                if (!best_valid || read_value[31:0]<best_priority ||
                    (read_value[31:0]==best_priority &&
                     ((!best_shortest && tag_bytes[read_value[63:32]]>best_end_byte) ||
                      (best_shortest && tag_bytes[read_value[63:32]]<best_end_byte)))) begin
                  best_valid<=1; best_priority<=read_value[31:0];
                  best_shortest<=read_value[64];
                  best_end_byte<=tag_bytes[read_value[63:32]];
                  best_end_index<=tag_scalars[read_value[63:32]];
                end
              end
              if (accept_remaining>1) begin
                accept_cursor<=accept_cursor+1; accept_remaining<=accept_remaining-1;
                read_index<=accept_cursor+1; state<=READ_ISSUE;
              end else state<=AFTER_ACCEPTS;
            end
          end
          AFTER_ACCEPTS: begin
            if (current_state==dead_state || end_consumed) state<=SCAN_FINISH;
            else state<=TRANSITION_SELECT;
          end
          SCAN_FINISH: begin
            if (!best_valid || best_end_index>scalar_count ||
                best_end_byte>byte_count || best_end_index<=anchor_index) begin
              code<=8'h12; state<=FAILED;
            end else state<=EMIT;
          end
          EMIT: if (out_valid && out_ready) begin
            if (out_last) begin done_r<=1; state<=CLOSED; end
            else begin
              anchor_index<=best_end_index; anchor_byte<=best_end_byte;
              clear_index<=0; state<=CLEAR_TAGS;
            end
          end
          FAILED: state<=FAILED;
          default: begin code<=8'h12; state<=FAILED; end
        endcase
      end
    end
  end endgenerate
endmodule
