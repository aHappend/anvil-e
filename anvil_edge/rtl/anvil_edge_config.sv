module anvil_edge_config #(
  parameter integer VOCAB_SIZE=151936,
  parameter integer MAX_SEQ_LEN=32768
) (
  input wire clk, rst_n,
  input wire cfg_valid,
  output wire cfg_ready,
  input wire cfg_write,
  input wire [31:0] cfg_addr, cfg_wdata,
  output wire cfg_rsp_valid,
  input wire cfg_rsp_ready,
  output wire [31:0] cfg_rdata,
  output wire cfg_rsp_error,
  input wire [3:0] status,
  input wire [7:0] transaction_error_code,
  input wire write_allowed, reload_allowed, publish,
  input wire [223:0] committed_config_words,
  output wire reload_request, publish_error, serial_update,
  output wire [31:0] uart_divisor, eos_token_id, max_new_tokens,
    transport, profile_id, vocab_size, uart_frame_bytes
);
  reg response_valid, response_error, reload_r, publish_failed;
  reg serial_update_r;
  reg [31:0] response_data;
  reg [31:0] divisor_r, eos_r, max_r, transport_r, profile_r, vocab_r, frame_r;
  reg [31:0] staged_profile, staged_vocab;
  reg profile_pending, vocab_pending;
  reg address_known, value_legal, writable;
  reg [31:0] read_value;
  wire staged_match=(!profile_pending ||
    staged_profile==committed_config_words[128+:32]) &&
    (!vocab_pending || staged_vocab==committed_config_words[160+:32]);
  wire bundle_legal=committed_config_words[0+:32]>=4 &&
    committed_config_words[96+:32]<=1 &&
    committed_config_words[128+:32]>=1 && committed_config_words[128+:32]<=4 &&
    committed_config_words[160+:32]>=256 && committed_config_words[160+:32]<=262144 &&
    committed_config_words[160+:32]<=VOCAB_SIZE &&
    committed_config_words[32+:32]<committed_config_words[160+:32] &&
    committed_config_words[64+:32]<=MAX_SEQ_LEN;

  assign cfg_ready=rst_n && !response_valid && !publish;
  assign cfg_rsp_valid=rst_n && response_valid;
  assign cfg_rdata=cfg_rsp_valid ? response_data : 0;
  assign cfg_rsp_error=cfg_rsp_valid && response_error;
  assign reload_request=rst_n && reload_r;
  assign publish_error=rst_n && publish_failed;
  assign serial_update=rst_n && serial_update_r;
  assign uart_divisor=rst_n ? divisor_r : 0;
  assign eos_token_id=rst_n ? eos_r : 0;
  assign max_new_tokens=rst_n ? max_r : 0;
  assign transport=rst_n ? transport_r : 0;
  assign profile_id=rst_n ? profile_r : 0;
  assign vocab_size=rst_n ? vocab_r : 0;
  assign uart_frame_bytes=rst_n ? frame_r : 0;

  always @* begin
    address_known=1; writable=1; value_legal=1; read_value=0;
    case (cfg_addr)
      32'h00: begin writable=0; read_value={28'd0,status}; end
      32'h04: begin read_value=divisor_r; value_legal=cfg_wdata>=4; end
      32'h08: begin read_value=eos_r; value_legal=cfg_wdata<vocab_r; end
      32'h0c: begin read_value=max_r; value_legal=cfg_wdata<=MAX_SEQ_LEN; end
      32'h10: begin read_value=transport_r; value_legal=cfg_wdata<=1; end
      32'h14: begin
        read_value=staged_profile; value_legal=cfg_wdata>=1 && cfg_wdata<=4;
      end
      32'h18: begin
        read_value=staged_vocab;
        value_legal=cfg_wdata>=256 && cfg_wdata<=262144 && cfg_wdata<=VOCAB_SIZE;
      end
      32'h1c: value_legal=cfg_wdata==1;
      32'h20: begin writable=0; read_value={24'd0,transaction_error_code}; end
      32'h24: read_value=frame_r;
      default: begin address_known=0; writable=0; value_legal=0; end
    endcase
  end
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      response_valid<=0; response_error<=0; response_data<=0; reload_r<=0;
      publish_failed<=0; divisor_r<=868; eos_r<=0; max_r<=0;
      transport_r<=0; profile_r<=0; vocab_r<=0; frame_r<=0;
      staged_profile<=0; staged_vocab<=0; profile_pending<=0; vocab_pending<=0;
      serial_update_r<=0;
    end else begin
      reload_r<=0;
      serial_update_r<=0;
      if (response_valid && cfg_rsp_ready) response_valid<=0;
      if (publish) begin
        if (!staged_match || !bundle_legal) publish_failed<=1;
        else begin
          divisor_r<=committed_config_words[0+:32];
          eos_r<=committed_config_words[32+:32];
          max_r<=committed_config_words[64+:32];
          transport_r<=committed_config_words[96+:32];
          profile_r<=committed_config_words[128+:32];
          vocab_r<=committed_config_words[160+:32];
          frame_r<=committed_config_words[192+:32];
          staged_profile<=committed_config_words[128+:32];
          staged_vocab<=committed_config_words[160+:32];
          profile_pending<=0; vocab_pending<=0; publish_failed<=0;
        end
      end else if (cfg_valid && cfg_ready) begin
        response_valid<=1; response_data<=0; response_error<=0;
        if (!address_known || (cfg_write &&
            (!writable || !value_legal ||
             (cfg_addr==32'h1c ? !reload_allowed : !write_allowed))))
          response_error<=1;
        else if (!cfg_write) response_data<=read_value;
        else case (cfg_addr)
          32'h04: begin divisor_r<=cfg_wdata; serial_update_r<=1; end
          32'h08: eos_r<=cfg_wdata;
          32'h0c: max_r<=cfg_wdata;
          32'h10: begin transport_r<=cfg_wdata; serial_update_r<=1; end
          32'h14: begin staged_profile<=cfg_wdata; profile_pending<=1; end
          32'h18: begin staged_vocab<=cfg_wdata; vocab_pending<=1; end
          32'h1c: begin reload_r<=1; publish_failed<=0; end
          32'h24: begin frame_r<=cfg_wdata; serial_update_r<=1; end
          default: begin end
        endcase
      end
    end
  end
endmodule
