module anvil_edge_unicode_lookup (
  input wire clk, rst_n,
  input wire in_valid,
  output wire in_ready,
  input wire [31:0] in_scalar,
  input wire config_valid,
  input wire [63:0] cfg_ranges_base,
  input wire [31:0] cfg_range_count, cfg_class_count,
  output wire out_valid,
  input wire out_ready,
  output wire [31:0] out_class_id, out_properties,
  output wire response_error,
  output wire [7:0] response_error_code,
  output wire tbl_req_valid,
  input wire tbl_req_ready,
  output wire [63:0] tbl_req_addr,
  input wire tbl_rsp_valid,
  output wire tbl_rsp_ready,
  input wire [31:0] tbl_rsp_data,
  input wire tbl_rsp_error
);
  localparam [3:0] IDLE=0, CHECK=1, SEARCH=2, ISSUE=3, WAIT_RECORD=4,
    COMPARE=5, RETURN=6;
  reg [3:0] state;
  reg admitted, failed;
  reg [7:0] code;
  reg [63:0] base;
  reg [31:0] scalar, range_count, class_count, low_index, high_index, middle;
  reg [31:0] first_scalar, last_scalar, class_value, property_value;
  wire reader_ready, reader_valid, reader_error;
  wire [7:0] reader_code;
  wire [127:0] reader_data;

  anvil_edge_table_record_reader #(.LOG2_RECORD_BYTES(4)) record_reader(
    .clk(clk),.rst_n(rst_n),.in_valid(rst_n && state==ISSUE),
    .in_ready(reader_ready),.segment_base(base),.record_count(range_count),
    .record_index(middle),.out_valid(reader_valid),
    .out_ready(rst_n && state==WAIT_RECORD),.record_data(reader_data),
    .response_error(reader_error),.response_error_code(reader_code),
    .tbl_req_valid(tbl_req_valid),.tbl_req_ready(tbl_req_ready),
    .tbl_req_addr(tbl_req_addr),.tbl_rsp_valid(tbl_rsp_valid),
    .tbl_rsp_ready(tbl_rsp_ready),.tbl_rsp_data(tbl_rsp_data),
    .tbl_rsp_error(tbl_rsp_error)
  );

  assign in_ready=rst_n && state==IDLE;
  assign out_valid=rst_n && state==RETURN;
  assign out_class_id=out_valid && !failed ? class_value : 0;
  assign out_properties=out_valid && !failed ? property_value : 0;
  assign response_error=out_valid && failed;
  assign response_error_code=out_valid ? code : 0;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state<=IDLE; admitted<=0; failed<=0; code<=0; base<=0;
      scalar<=0; range_count<=0; class_count<=0;
      low_index<=0; high_index<=0; middle<=0;
      first_scalar<=0; last_scalar<=0; class_value<=0; property_value<=0;
    end else case (state)
      IDLE: if (in_valid && in_ready) begin
        admitted<=config_valid; base<=cfg_ranges_base;
        range_count<=cfg_range_count; class_count<=cfg_class_count;
        scalar<=in_scalar;
        low_index<=0; high_index<=cfg_range_count;
        failed<=0; code<=0; class_value<=0; property_value<=0;
        state<=CHECK;
      end
      CHECK: begin
        if (scalar>32'h10ffff || (scalar>=32'hd800 && scalar<=32'hdfff)) begin
          failed<=1; code<=8'h10; state<=RETURN;
        end else if (!admitted || range_count==0 || class_count==0 ||
                     base[1:0]!=0) begin
          failed<=1; code<=8'h06; state<=RETURN;
        end else state<=SEARCH;
      end
      SEARCH: begin
        if (low_index>=high_index) begin
          failed<=1; code<=8'h12; state<=RETURN;
        end else begin
          middle<=low_index+((high_index-low_index) >> 1);
          state<=ISSUE;
        end
      end
      ISSUE: if (reader_ready) state<=WAIT_RECORD;
      WAIT_RECORD: if (reader_valid) begin
        if (reader_error) begin
          failed<=1; code<=reader_code; state<=RETURN;
        end else begin
          first_scalar<=reader_data[31:0]; last_scalar<=reader_data[63:32];
          class_value<=reader_data[95:64]; property_value<=reader_data[127:96];
          state<=COMPARE;
        end
      end
      COMPARE: begin
        if (first_scalar>last_scalar || last_scalar>32'h10ffff ||
            (first_scalar<=32'hdfff && last_scalar>=32'hd800) ||
            class_value>=class_count || property_value[31:10]!=0) begin
          failed<=1; code<=8'h12; state<=RETURN;
        end else if (scalar<first_scalar) begin high_index<=middle; state<=SEARCH; end
        else if (scalar>last_scalar) begin low_index<=middle+1; state<=SEARCH; end
        else state<=RETURN;
      end
      RETURN: if (out_valid && out_ready) state<=IDLE;
      default: begin failed<=1; code<=8'h12; state<=RETURN; end
    endcase
  end
endmodule
