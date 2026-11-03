module anvil_edge_normalizer #(
  parameter integer MAX_SCALARS=4096
) (
  input wire clk, rst_n, start,
  input wire config_valid,
  input wire [31:0] cfg_normalization,
  input wire [63:0] cfg_ranges_base, cfg_decomposition_base,
    cfg_scalar_pool_base, cfg_composition_base,
  input wire [31:0] cfg_range_count, cfg_class_count, cfg_decomposition_count,
    cfg_scalar_pool_count, cfg_composition_count,
  input wire in_valid,
  output wire in_ready,
  input wire [31:0] in_scalar,
  input wire in_last,
  output wire out_valid,
  input wire out_ready,
  output wire [31:0] out_scalar,
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
  generate if (MAX_SCALARS<1) begin : invalid_parameters
    initial $fatal(1, "ANVIL_EDGE_NORMALIZER PARAMETER ERROR: MAX_SCALARS must be positive");
    assign in_ready=0; assign out_valid=0; assign out_scalar=0; assign out_last=0;
    assign busy=0; assign done=0; assign error=0; assign error_code=0;
    assign tbl_req_valid=0; assign tbl_req_addr=0; assign tbl_rsp_ready=0;
  end else begin : normalizer
    localparam [5:0] IDLE=0, CAPTURE=1, DECOMP_START=2, DECOMP_SEARCH=3,
      RECORD_ISSUE=4, RECORD_WAIT=5, DECOMP_COMPARE=6,
      POOL_ISSUE=7, POOL_WAIT=8, APPEND_CHECK=9,
      CLASSIFY_ISSUE=10, CLASSIFY_WAIT=11, INSERT_FETCH=12,
      INSERT_COMPARE=13, INSERT_WRITE=14, APPEND_NEXT=15, INPUT_DONE=16,
      HANGUL_L_ISSUE=17, HANGUL_L_WAIT=18, HANGUL_V_ISSUE=19,
      HANGUL_V_WAIT=20, COMPOSE_START=21, COMPOSE_READ=22,
      COMPOSE_TRY=23, COMPOSE_SEARCH_START=24, COMPOSE_SEARCH=25,
      COMPOSE_COMPARE=26, COMPOSE_APPEND=27, COMPOSE_REPLACE=28,
      HANGUL_MUL1=29, HANGUL_MUL2=30, HANGUL_MUL3=31,
      HANGUL_MUL4=32, HANGUL_MUL5=33, HANGUL_TEST_ISSUE=34,
      HANGUL_TEST_WAIT=35, EMIT=36, CLOSED=37, FAILED=38;
    localparam [1:0] ORIGINAL=0, POOL=1, HANGUL=2;
    reg [5:0] state;
    reg [31:0] scalars [0:MAX_SCALARS-1];
    reg [7:0] combining_classes [0:MAX_SCALARS-1];
    reg [31:0] mode, scalar_count, input_scalar, append_scalar, insert_position;
    reg input_last;
    reg [1:0] append_source, hangul_part;
    reg [7:0] append_ccc, previous_ccc;
    reg [31:0] previous_scalar;
    reg [63:0] ranges_base, decomposition_base, scalar_pool_base, composition_base;
    reg [31:0] range_count, class_count, decomposition_count, scalar_pool_count;
    reg [31:0] composition_count, search_low, search_high, search_middle;
    reg [31:0] pool_cursor, pool_remaining;
    reg reading_composition;
    reg [127:0] record_value;
    reg [31:0] hangul_index, hangul_l, hangul_v, hangul_t;
    reg [31:0] hangul_l_index, hangul_v_index, hangul_product;
    reg [31:0] read_index, write_index, output_index;
    reg [31:0] current_scalar, starter_scalar, starter_position, composite_scalar;
    reg [7:0] current_ccc, last_ccc;
    reg starter_valid, done_r;
    reg [7:0] code;
    wire classify_selected=state==CLASSIFY_ISSUE || state==CLASSIFY_WAIT;
    wire pool_selected=state==POOL_ISSUE || state==POOL_WAIT;
    wire record_ready, record_valid, record_error, record_tbl_valid, record_tbl_ready;
    wire [7:0] record_code;
    wire [127:0] record_data;
    wire [63:0] record_tbl_address;
    wire pool_ready, pool_valid, pool_error, pool_tbl_valid, pool_tbl_ready;
    wire [7:0] pool_code;
    wire [31:0] pool_data;
    wire [63:0] pool_tbl_address;
    wire class_ready, class_valid, class_error, class_tbl_valid, class_tbl_ready;
    wire [7:0] class_code;
    wire [31:0] class_properties;
    wire [63:0] class_tbl_address;
    wire divider_ready, divider_valid, divider_zero;
    wire [31:0] quotient, remainder_value;
    wire division_issue=state==HANGUL_L_ISSUE || state==HANGUL_V_ISSUE ||
      state==HANGUL_TEST_ISSUE;
    wire division_wait=state==HANGUL_L_WAIT || state==HANGUL_V_WAIT ||
      state==HANGUL_TEST_WAIT;
    wire [31:0] division_numerator=state==HANGUL_TEST_ISSUE ?
      starter_scalar-32'hac00 : hangul_index;
    wire [31:0] division_denominator=state==HANGUL_L_ISSUE ? 32'd588 : 32'd28;
    wire [32:0] pool_end={1'b0,record_value[63:32]}+
                         {1'b0,record_value[95:64]};
    wire record_scalar_valid=record_value[31:0]<=32'h10ffff &&
      !(record_value[31:0]>=32'hd800 && record_value[31:0]<=32'hdfff);
    wire composition_before=record_value[31:0]<starter_scalar ||
      (record_value[31:0]==starter_scalar && record_value[63:32]<current_scalar);
    wire composition_equal=record_value[31:0]==starter_scalar &&
      record_value[63:32]==current_scalar;

    anvil_edge_table_record_reader #(.LOG2_RECORD_BYTES(4)) records(
      .clk(clk),.rst_n(rst_n),.in_valid(rst_n && state==RECORD_ISSUE),
      .in_ready(record_ready),
      .segment_base(reading_composition ? composition_base : decomposition_base),
      .record_count(reading_composition ? composition_count : decomposition_count),
      .record_index(search_middle),.out_valid(record_valid),
      .out_ready(rst_n && state==RECORD_WAIT),.record_data(record_data),
      .response_error(record_error),.response_error_code(record_code),
      .tbl_req_valid(record_tbl_valid),
      .tbl_req_ready(!classify_selected && !pool_selected && tbl_req_ready),
      .tbl_req_addr(record_tbl_address),
      .tbl_rsp_valid(!classify_selected && !pool_selected && tbl_rsp_valid),
      .tbl_rsp_ready(record_tbl_ready),.tbl_rsp_data(tbl_rsp_data),
      .tbl_rsp_error(tbl_rsp_error)
    );
    anvil_edge_table_record_reader #(.LOG2_RECORD_BYTES(2)) scalar_pool(
      .clk(clk),.rst_n(rst_n),.in_valid(rst_n && state==POOL_ISSUE),
      .in_ready(pool_ready),.segment_base(scalar_pool_base),
      .record_count(scalar_pool_count),.record_index(pool_cursor),
      .out_valid(pool_valid),.out_ready(rst_n && state==POOL_WAIT),
      .record_data(pool_data),.response_error(pool_error),
      .response_error_code(pool_code),.tbl_req_valid(pool_tbl_valid),
      .tbl_req_ready(pool_selected && tbl_req_ready),.tbl_req_addr(pool_tbl_address),
      .tbl_rsp_valid(pool_selected && tbl_rsp_valid),.tbl_rsp_ready(pool_tbl_ready),
      .tbl_rsp_data(tbl_rsp_data),.tbl_rsp_error(tbl_rsp_error)
    );
    anvil_edge_unicode_lookup classification(
      .clk(clk),.rst_n(rst_n),.in_valid(rst_n && state==CLASSIFY_ISSUE),
      .in_ready(class_ready),.in_scalar(append_scalar),.config_valid(1'b1),
      .cfg_ranges_base(ranges_base),.cfg_range_count(range_count),
      .cfg_class_count(class_count),.out_valid(class_valid),
      .out_ready(rst_n && state==CLASSIFY_WAIT),.out_class_id(),
      .out_properties(class_properties),.response_error(class_error),
      .response_error_code(class_code),.tbl_req_valid(class_tbl_valid),
      .tbl_req_ready(classify_selected && tbl_req_ready),
      .tbl_req_addr(class_tbl_address),
      .tbl_rsp_valid(classify_selected && tbl_rsp_valid),
      .tbl_rsp_ready(class_tbl_ready),.tbl_rsp_data(tbl_rsp_data),
      .tbl_rsp_error(tbl_rsp_error)
    );
    anvil_edge_unsigned_divider #(.WIDTH(32)) hangul_divider(
      .clk(clk),.rst_n(rst_n),.in_valid(rst_n && division_issue),
      .in_ready(divider_ready),.numerator(division_numerator),
      .denominator(division_denominator),.out_valid(divider_valid),
      .out_ready(rst_n && division_wait),.quotient(quotient),
      .remainder(remainder_value),.divide_by_zero(divider_zero)
    );

    assign tbl_req_valid=classify_selected ? class_tbl_valid :
      (pool_selected ? pool_tbl_valid : record_tbl_valid);
    assign tbl_req_addr=classify_selected ? class_tbl_address :
      (pool_selected ? pool_tbl_address : record_tbl_address);
    assign tbl_rsp_ready=classify_selected ? class_tbl_ready :
      (pool_selected ? pool_tbl_ready : record_tbl_ready);
    assign in_ready=rst_n && state==CAPTURE;
    assign out_valid=rst_n && state==EMIT;
    assign out_scalar=out_valid ? scalars[output_index] : 0;
    assign out_last=out_valid && output_index+1==scalar_count;
    assign busy=rst_n && state!=IDLE && state!=CLOSED && state!=FAILED;
    assign done=rst_n && done_r;
    assign error=rst_n && state==FAILED;
    assign error_code=rst_n ? code : 0;

    always @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
        state<=IDLE; mode<=0; scalar_count<=0; input_scalar<=0;
        append_scalar<=0; insert_position<=0; input_last<=0;
        append_source<=ORIGINAL; hangul_part<=0; append_ccc<=0;
        previous_ccc<=0; previous_scalar<=0;
        ranges_base<=0; decomposition_base<=0; scalar_pool_base<=0;
        composition_base<=0; range_count<=0; class_count<=0;
        decomposition_count<=0; scalar_pool_count<=0; composition_count<=0;
        search_low<=0; search_high<=0; search_middle<=0;
        pool_cursor<=0; pool_remaining<=0; reading_composition<=0;
        record_value<=0; hangul_index<=0; hangul_l<=0; hangul_v<=0; hangul_t<=0;
        hangul_l_index<=0; hangul_v_index<=0; hangul_product<=0;
        read_index<=0; write_index<=0; output_index<=0;
        current_scalar<=0; starter_scalar<=0; starter_position<=0;
        composite_scalar<=0; current_ccc<=0; last_ccc<=0;
        starter_valid<=0; done_r<=0; code<=0;
      end else begin
        done_r<=0;
        case (state)
          IDLE, CLOSED: if (start) begin
            if (!config_valid || cfg_normalization>4 ||
                (cfg_normalization!=0 &&
                 (cfg_range_count==0 || cfg_class_count==0 ||
                  cfg_ranges_base[1:0]!=0 || cfg_decomposition_base[1:0]!=0 ||
                  cfg_scalar_pool_base[1:0]!=0 || cfg_composition_base[1:0]!=0))) begin
              code<=8'h06; state<=FAILED;
            end else begin
              mode<=cfg_normalization; ranges_base<=cfg_ranges_base;
              decomposition_base<=cfg_decomposition_base;
              scalar_pool_base<=cfg_scalar_pool_base;
              composition_base<=cfg_composition_base;
              range_count<=cfg_range_count; class_count<=cfg_class_count;
              decomposition_count<=cfg_decomposition_count;
              scalar_pool_count<=cfg_scalar_pool_count;
              composition_count<=cfg_composition_count;
              scalar_count<=0; output_index<=0; code<=0; state<=CAPTURE;
            end
          end
          CAPTURE: if (in_valid && in_ready) begin
            if (in_scalar>32'h10ffff ||
                (in_scalar>=32'hd800 && in_scalar<=32'hdfff)) begin
              code<=8'h10; state<=FAILED;
            end else begin
              input_scalar<=in_scalar; input_last<=in_last;
              append_source<=ORIGINAL; append_scalar<=in_scalar;
              if (mode==0) state<=APPEND_CHECK;
              else if (in_scalar>=32'hac00 && in_scalar<=32'hd7a3) begin
                hangul_index<=in_scalar-32'hac00;
                state<=HANGUL_L_ISSUE;
              end else state<=DECOMP_START;
            end
          end
          DECOMP_START: begin
            search_low<=0; search_high<=decomposition_count;
            reading_composition<=0; state<=DECOMP_SEARCH;
          end
          DECOMP_SEARCH: begin
            if (search_low>=search_high) begin
              append_scalar<=input_scalar; append_source<=ORIGINAL;
              state<=APPEND_CHECK;
            end else begin
              search_middle<=search_low+((search_high-search_low) >> 1);
              state<=RECORD_ISSUE;
            end
          end
          RECORD_ISSUE: if (record_ready) state<=RECORD_WAIT;
          RECORD_WAIT: if (record_valid) begin
            if (record_error) begin code<=record_code; state<=FAILED; end
            else begin
              record_value<=record_data;
              if (reading_composition) state<=COMPOSE_COMPARE;
              else state<=DECOMP_COMPARE;
            end
          end
          DECOMP_COMPARE: begin
            if (!record_scalar_valid || record_value[127:97]!=0 ||
                record_value[95:64]==0 || pool_end[32] ||
                pool_end>{1'b0,scalar_pool_count}) begin
              code<=8'h12; state<=FAILED;
            end else if (record_value[31:0]<input_scalar) begin
              search_low<=search_middle+1; state<=DECOMP_SEARCH;
            end else if (record_value[31:0]>input_scalar) begin
              search_high<=search_middle; state<=DECOMP_SEARCH;
            end else if (record_value[96] && (mode==1 || mode==3)) begin
              append_scalar<=input_scalar; append_source<=ORIGINAL;
              state<=APPEND_CHECK;
            end else begin
              pool_cursor<=record_value[63:32]; pool_remaining<=record_value[95:64];
              append_source<=POOL; state<=POOL_ISSUE;
            end
          end
          POOL_ISSUE: if (pool_ready) state<=POOL_WAIT;
          POOL_WAIT: if (pool_valid) begin
            if (pool_error) begin code<=pool_code; state<=FAILED; end
            else begin append_scalar<=pool_data; state<=APPEND_CHECK; end
          end
          HANGUL_L_ISSUE: if (divider_ready) state<=HANGUL_L_WAIT;
          HANGUL_L_WAIT: if (divider_valid) begin
            if (divider_zero) begin code<=8'h12; state<=FAILED; end
            else begin
              hangul_l<=32'h1100+quotient; hangul_index<=remainder_value;
              state<=HANGUL_V_ISSUE;
            end
          end
          HANGUL_V_ISSUE: if (divider_ready) state<=HANGUL_V_WAIT;
          HANGUL_V_WAIT: if (divider_valid) begin
            if (divider_zero) begin code<=8'h12; state<=FAILED; end
            else begin
              hangul_v<=32'h1161+quotient;
              hangul_t<=32'h11a7+remainder_value;
              append_scalar<=hangul_l; append_source<=HANGUL; hangul_part<=0;
              state<=APPEND_CHECK;
            end
          end
          APPEND_CHECK: begin
            if (append_scalar>32'h10ffff ||
                (append_scalar>=32'hd800 && append_scalar<=32'hdfff)) begin
              code<=8'h12; state<=FAILED;
            end else if (scalar_count>=MAX_SCALARS) begin
              code<=8'h30; state<=FAILED;
            end else if (mode==0) begin
              append_ccc<=0; insert_position<=scalar_count;
              scalar_count<=scalar_count+1; state<=INSERT_WRITE;
            end else state<=CLASSIFY_ISSUE;
          end
          CLASSIFY_ISSUE: if (class_ready) state<=CLASSIFY_WAIT;
          CLASSIFY_WAIT: if (class_valid) begin
            if (class_error) begin code<=class_code; state<=FAILED; end
            else begin
              append_ccc<=class_properties[7:0]; insert_position<=scalar_count;
              scalar_count<=scalar_count+1;
              if (scalar_count==0 || class_properties[7:0]==0) state<=INSERT_WRITE;
              else state<=INSERT_FETCH;
            end
          end
          INSERT_FETCH: begin
            previous_scalar<=scalars[insert_position-1];
            previous_ccc<=combining_classes[insert_position-1];
            state<=INSERT_COMPARE;
          end
          INSERT_COMPARE: begin
            if (previous_ccc>append_ccc) begin
              scalars[insert_position]<=previous_scalar;
              combining_classes[insert_position]<=previous_ccc;
              insert_position<=insert_position-1;
              if (insert_position==1) state<=INSERT_WRITE;
              else state<=INSERT_FETCH;
            end else state<=INSERT_WRITE;
          end
          INSERT_WRITE: begin
            scalars[insert_position]<=append_scalar;
            combining_classes[insert_position]<=append_ccc;
            state<=APPEND_NEXT;
          end
          APPEND_NEXT: begin
            if (append_source==POOL && pool_remaining>1) begin
              pool_cursor<=pool_cursor+1; pool_remaining<=pool_remaining-1;
              state<=POOL_ISSUE;
            end else if (append_source==HANGUL && hangul_part==0) begin
              append_scalar<=hangul_v; hangul_part<=1; state<=APPEND_CHECK;
            end else if (append_source==HANGUL && hangul_part==1 && hangul_t!=32'h11a7) begin
              append_scalar<=hangul_t; hangul_part<=2; state<=APPEND_CHECK;
            end else state<=INPUT_DONE;
          end
          INPUT_DONE: begin
            if (!input_last) state<=CAPTURE;
            else if (mode==1 || mode==2) state<=COMPOSE_START;
            else begin output_index<=0; state<=EMIT; end
          end
          COMPOSE_START: begin
            read_index<=0; write_index<=0; starter_valid<=0; last_ccc<=0;
            state<=COMPOSE_READ;
          end
          COMPOSE_READ: begin
            if (read_index==scalar_count) begin
              scalar_count<=write_index; output_index<=0; state<=EMIT;
            end else begin
              current_scalar<=scalars[read_index];
              current_ccc<=combining_classes[read_index];
              state<=COMPOSE_TRY;
            end
          end
          COMPOSE_TRY: begin
            if (!starter_valid || !(last_ccc==0 || last_ccc<current_ccc))
              state<=COMPOSE_APPEND;
            else if (starter_scalar>=32'h1100 && starter_scalar<=32'h1112 &&
                     current_scalar>=32'h1161 && current_scalar<=32'h1175) begin
              hangul_l_index<=starter_scalar-32'h1100;
              hangul_v_index<=current_scalar-32'h1161;
              state<=HANGUL_MUL1;
            end else if (starter_scalar>=32'hac00 && starter_scalar<=32'hd7a3 &&
                         current_scalar>32'h11a7 && current_scalar<=32'h11c2)
              state<=HANGUL_TEST_ISSUE;
            else state<=COMPOSE_SEARCH_START;
          end
          HANGUL_MUL1: begin
            hangul_product<=(hangul_l_index << 4)+(hangul_l_index << 2);
            state<=HANGUL_MUL2;
          end
          HANGUL_MUL2: begin
            hangul_product<=hangul_product+hangul_l_index;
            state<=HANGUL_MUL3;
          end
          HANGUL_MUL3: begin
            hangul_product<=hangul_product+hangul_v_index;
            state<=HANGUL_MUL4;
          end
          HANGUL_MUL4: begin
            hangul_product<=(hangul_product << 5)-(hangul_product << 2);
            state<=HANGUL_MUL5;
          end
          HANGUL_MUL5: begin
            composite_scalar<=32'hac00+hangul_product; state<=COMPOSE_REPLACE;
          end
          HANGUL_TEST_ISSUE: if (divider_ready) state<=HANGUL_TEST_WAIT;
          HANGUL_TEST_WAIT: if (divider_valid) begin
            if (divider_zero) begin code<=8'h12; state<=FAILED; end
            else if (remainder_value==0) begin
              composite_scalar<=starter_scalar+(current_scalar-32'h11a7);
              state<=COMPOSE_REPLACE;
            end else state<=COMPOSE_SEARCH_START;
          end
          COMPOSE_SEARCH_START: begin
            search_low<=0; search_high<=composition_count;
            reading_composition<=1; state<=COMPOSE_SEARCH;
          end
          COMPOSE_SEARCH: begin
            if (search_low>=search_high) state<=COMPOSE_APPEND;
            else begin
              search_middle<=search_low+((search_high-search_low) >> 1);
              state<=RECORD_ISSUE;
            end
          end
          COMPOSE_COMPARE: begin
            if (!record_scalar_valid ||
                record_value[63:32]>32'h10ffff ||
                (record_value[63:32]>=32'hd800 && record_value[63:32]<=32'hdfff) ||
                record_value[95:64]>32'h10ffff ||
                (record_value[95:64]>=32'hd800 && record_value[95:64]<=32'hdfff) ||
                record_value[127:96]!=0) begin
              code<=8'h12; state<=FAILED;
            end else if (composition_equal) begin
              composite_scalar<=record_value[95:64]; state<=COMPOSE_REPLACE;
            end else begin
              if (composition_before) search_low<=search_middle+1;
              else search_high<=search_middle;
              state<=COMPOSE_SEARCH;
            end
          end
          COMPOSE_APPEND: begin
            scalars[write_index]<=current_scalar;
            combining_classes[write_index]<=current_ccc;
            if (current_ccc==0) begin
              starter_valid<=1; starter_scalar<=current_scalar;
              starter_position<=write_index;
            end
            last_ccc<=current_ccc;
            write_index<=write_index+1; read_index<=read_index+1;
            state<=COMPOSE_READ;
          end
          COMPOSE_REPLACE: begin
            scalars[starter_position]<=composite_scalar;
            starter_scalar<=composite_scalar;
            read_index<=read_index+1;
            state<=COMPOSE_READ;
          end
          EMIT: if (out_valid && out_ready) begin
            if (out_last) begin done_r<=1; state<=CLOSED; end
            else output_index<=output_index+1;
          end
          FAILED: state<=FAILED;
          default: begin code<=8'h12; state<=FAILED; end
        endcase
      end
    end
  end endgenerate
endmodule
