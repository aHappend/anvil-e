module anvil_edge_core_adapter #(
  parameter NUM_LAYERS=24, HIDDEN_SIZE=896, INTERMEDIATE_SIZE=4864,
  NUM_Q_HEADS=14, NUM_KV_HEADS=2, HEAD_DIM=64, GROUP_SIZE=128,
  AWQ_BITS=4, VOCAB_SIZE=151936, MAX_SEQ_LEN=32768
) (
  input wire clk, rst_n,
  input wire token_valid,
  output wire token_ready,
  input wire [31:0] token_id, token_pos,
  input wire new_sequence,
  output wire logit_valid,
  input wire logit_ready,
  output wire [31:0] logit_index,
  output wire signed [31:0] logit_data,
  output wire done, error,
  output wire mem_req_valid,
  input wire mem_req_ready,
  output wire mem_req_write,
  output wire [3:0] mem_req_kind,
  output wire [31:0] mem_req_layer,
  output wire [2:0] mem_req_proj,
  output wire [31:0] mem_req_row, mem_req_col, mem_req_wdata,
  input wire mem_rsp_valid,
  output wire mem_rsp_ready,
  input wire [31:0] mem_rsp_rdata,
  input wire mem_rsp_error,
  input wire config_valid,
  input wire [31:0] cfg_active_vocab_size,
  output wire [7:0] error_code
);
  localparam [2:0] IDLE=0, ISSUE=1, RUN=2, DRAIN=3, FINISH=4;
  reg [2:0] state;
  reg [31:0] active_vocabulary, physical_count, request_token, request_position;
  reg request_new_sequence, holding, failed;
  reg [31:0] buffered_index;
  reg signed [31:0] buffered_logit;
  reg [7:0] code;
  wire physical_token_ready, physical_logit_valid, physical_logit_ready;
  wire physical_done, physical_error;
  wire [31:0] physical_index;
  wire signed [31:0] physical_logit;
  wire physical_transfer=physical_logit_valid && physical_logit_ready;
  wire frame_complete=physical_count==VOCAB_SIZE ||
    (physical_transfer && physical_count==VOCAB_SIZE-1);
  anvil_q1_top #(
    NUM_LAYERS,HIDDEN_SIZE,INTERMEDIATE_SIZE,NUM_Q_HEADS,NUM_KV_HEADS,
    HEAD_DIM,GROUP_SIZE,AWQ_BITS,VOCAB_SIZE,MAX_SEQ_LEN
  ) core (
    .clk(clk),.rst_n(rst_n),.token_valid(rst_n && state==ISSUE),
    .token_ready(physical_token_ready),.token_id(request_token),
    .token_pos(request_position),.new_sequence(request_new_sequence),
    .logit_valid(physical_logit_valid),.logit_ready(physical_logit_ready),
    .logit_index(physical_index),.logit_data(physical_logit),
    .done(physical_done),.error(physical_error),
    .mem_req_valid(mem_req_valid),.mem_req_ready(mem_req_ready),
    .mem_req_write(mem_req_write),.mem_req_kind(mem_req_kind),
    .mem_req_layer(mem_req_layer),.mem_req_proj(mem_req_proj),
    .mem_req_row(mem_req_row),.mem_req_col(mem_req_col),.mem_req_wdata(mem_req_wdata),
    .mem_rsp_valid(mem_rsp_valid),.mem_rsp_ready(mem_rsp_ready),
    .mem_rsp_rdata(mem_rsp_rdata),.mem_rsp_error(mem_rsp_error)
  );
  assign token_ready=rst_n && config_valid && state==IDLE;
  assign logit_valid=rst_n && (state==RUN || state==DRAIN) && holding;
  assign logit_index=rst_n ? buffered_index : 0;
  assign logit_data=rst_n ? buffered_logit : 0;
  assign physical_logit_ready=rst_n && state==RUN &&
    (physical_count>=active_vocabulary || !holding || logit_ready);
  assign done=rst_n && state==FINISH;
  assign error=done && failed;
  assign error_code=rst_n ? code : 0;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state<=IDLE; active_vocabulary<=0; physical_count<=0;
      request_token<=0; request_position<=0; request_new_sequence<=0;
      holding<=0; failed<=0; buffered_index<=0; buffered_logit<=0; code<=0;
    end else begin
      if (logit_valid && logit_ready) holding<=0;
      case (state)
        IDLE: if (token_valid && token_ready) begin
          failed<=0; code<=0; holding<=0; physical_count<=0;
          if (cfg_active_vocab_size<256 || cfg_active_vocab_size>262144 ||
              cfg_active_vocab_size>VOCAB_SIZE) begin
            failed<=1; code<=8'h06; state<=FINISH;
          end else if (token_id>=cfg_active_vocab_size) begin
            failed<=1; code<=8'h20; state<=FINISH;
          end else begin
            active_vocabulary<=cfg_active_vocab_size;
            request_token<=token_id; request_position<=token_pos;
            request_new_sequence<=new_sequence;
            state<=ISSUE;
          end
        end
        ISSUE: begin
          if (physical_error) begin failed<=1; code<=8'h20; state<=FINISH; end
          else if (physical_logit_valid || physical_done) begin
            failed<=1; code<=8'h21; state<=FINISH;
          end else if (physical_token_ready) state<=RUN;
        end
        RUN: begin
          if (physical_error) begin failed<=1; code<=8'h20; holding<=0; state<=FINISH; end
          else if ((physical_logit_valid &&
                    (physical_count>=VOCAB_SIZE || physical_index!=physical_count)) ||
                   (physical_done && !frame_complete)) begin
            failed<=1; code<=8'h21; holding<=0; state<=FINISH;
          end else begin
            if (physical_transfer) begin
              physical_count<=physical_count+1;
              if (physical_count<active_vocabulary) begin
                holding<=1; buffered_index<=physical_index; buffered_logit<=physical_logit;
              end
            end
            if (physical_done) state<=DRAIN;
          end
        end
        DRAIN: begin
          if (physical_error) begin failed<=1; code<=8'h20; holding<=0; state<=FINISH; end
          else if (physical_logit_valid || physical_done) begin
            failed<=1; code<=8'h21; holding<=0; state<=FINISH;
          end else if (!holding) state<=FINISH;
        end
        FINISH: state<=IDLE;
        default: begin failed<=1; code<=8'h21; holding<=0; state<=FINISH; end
      endcase
    end
  end
endmodule
