module anvil_edge_autoregressive_fsm #(
  parameter integer MAX_PROMPT_TOKENS = 4096
) (
  input wire clk, rst_n,
  input wire start,
  input wire [31:0] eos_token_id, max_new_tokens, vocab_size, seq_limit,
  input wire prompt_valid,
  output wire prompt_ready,
  input wire [31:0] prompt_id,
  input wire prompt_last,
  output wire generated_valid,
  input wire generated_ready,
  output wire [31:0] generated_id,
  output wire generated_last,
  output wire core_token_valid,
  input wire core_token_ready,
  output wire [31:0] core_token_id, core_token_pos,
  output wire core_new_sequence,
  input wire core_logit_valid,
  output wire core_logit_ready,
  input wire [31:0] core_logit_index,
  input wire signed [31:0] core_logit_data,
  input wire core_done, core_error,
  output wire busy, done, error,
  output wire [7:0] error_code,
  output wire finish_valid,
  input wire finish_ready
);
  generate
    if (MAX_PROMPT_TOKENS < 1) begin : invalid_parameters
      initial $fatal(1, "ANVIL_EDGE_CONTROLLER PARAMETER ERROR: MAX_PROMPT_TOKENS must be positive");
      assign prompt_ready = 0;
      assign generated_valid = 0;
      assign generated_id = 0;
      assign generated_last = 0;
      assign core_token_valid = 0;
      assign core_token_id = 0;
      assign core_token_pos = 0;
      assign core_new_sequence = 0;
      assign core_logit_ready = 0;
      assign busy = 0;
      assign done = 0;
      assign error = 0;
      assign error_code = 0;
      assign finish_valid = 0;
    end else begin : controller
      localparam [3:0] IDLE=0, CAPTURE=1, ISSUE=2, LOGITS=3,
                       DECIDE=4, GENERATED=5, FINISH=6, FAILED=7;
      reg [3:0] state;
      reg [31:0] prompt [0:MAX_PROMPT_TOKENS-1];
      reg [31:0] prompt_count, prompt_index;
      reg [31:0] eos, max_tokens, vocabulary, sequence_limit;
      reg [31:0] issue_id, position, logit_count;
      reg [31:0] winner_id, selected_id, selections;
      reg signed [31:0] winner_value;
      reg winner_valid, prefill, selected_last;
      reg done_r;
      reg [7:0] code;
      wire accept_logit = core_logit_valid && core_logit_ready;
      wire final_logit = accept_logit && logit_count == vocabulary-1;
      wire frame_complete = logit_count == vocabulary || final_logit;

      assign prompt_ready = rst_n && state == CAPTURE;
      assign generated_valid = rst_n && state == GENERATED;
      assign generated_id = rst_n ? selected_id : 0;
      assign generated_last = rst_n && selected_last;
      assign core_token_valid = rst_n && state == ISSUE;
      assign core_token_id = rst_n ? issue_id : 0;
      assign core_token_pos = rst_n ? position : 0;
      assign core_new_sequence = rst_n && state == ISSUE && position == 0;
      assign core_logit_ready = rst_n && state == LOGITS && logit_count < vocabulary;
      assign busy = rst_n && state != IDLE && state != FAILED;
      assign done = rst_n && done_r;
      assign error = rst_n && state == FAILED;
      assign error_code = rst_n ? code : 0;
      assign finish_valid = rst_n && state == FINISH;

      always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
          state <= IDLE;
          prompt_count <= 0;
          prompt_index <= 0;
          eos <= 0;
          max_tokens <= 0;
          vocabulary <= 0;
          sequence_limit <= 0;
          issue_id <= 0;
          position <= 0;
          logit_count <= 0;
          winner_id <= 0;
          winner_value <= 0;
          winner_valid <= 0;
          selected_id <= 0;
          selected_last <= 0;
          selections <= 0;
          prefill <= 0;
          done_r <= 0;
          code <= 0;
        end else begin
          done_r <= 0;
          if (state != IDLE && state != FAILED && core_error) begin
            code <= 8'h20;
            state <= FAILED;
          end else if (state != IDLE && state != FAILED && state != LOGITS &&
                       (core_logit_valid || core_done)) begin
            code <= 8'h21;
            state <= FAILED;
          end else case (state)
            IDLE: if (start) begin
              if (vocab_size == 0 || vocab_size > 262144 ||
                  eos_token_id >= vocab_size || seq_limit == 0 ||
                  seq_limit > 16777215 || max_new_tokens > seq_limit) begin
                code <= 8'h32;
                state <= FAILED;
              end else begin
                eos <= eos_token_id;
                max_tokens <= max_new_tokens;
                vocabulary <= vocab_size;
                sequence_limit <= seq_limit;
                prompt_count <= 0;
                prompt_index <= 0;
                position <= 0;
                selections <= 0;
                selected_id <= 0;
                selected_last <= 0;
                prefill <= 1;
                code <= 0;
                state <= CAPTURE;
              end
            end
            CAPTURE: if (prompt_valid && prompt_ready) begin
              if (prompt_id >= vocabulary) begin
                code <= 8'h11;
                state <= FAILED;
              end else if (prompt_count >= sequence_limit) begin
                code <= 8'h31;
                state <= FAILED;
              end else if (prompt_count >= MAX_PROMPT_TOKENS) begin
                code <= 8'h30;
                state <= FAILED;
              end else begin
                prompt[prompt_count] <= prompt_id;
                prompt_count <= prompt_count + 1;
                if (prompt_last) begin
                  if (prompt_count == 0) issue_id <= prompt_id;
                  else issue_id <= prompt[0];
                  logit_count <= 0;
                  winner_valid <= 0;
                  state <= ISSUE;
                end else if (prompt_count+1 >= sequence_limit) begin
                  code <= 8'h31;
                  state <= FAILED;
                end else if (prompt_count+1 >= MAX_PROMPT_TOKENS) begin
                  code <= 8'h30;
                  state <= FAILED;
                end
              end
            end
            ISSUE: if (core_token_valid && core_token_ready) begin
              logit_count <= 0;
              winner_valid <= 0;
              winner_id <= 0;
              winner_value <= 0;
              state <= LOGITS;
            end
            LOGITS: begin
              if (core_logit_valid &&
                  (logit_count >= vocabulary || core_logit_index != logit_count)) begin
                code <= 8'h21;
                state <= FAILED;
              end else if (core_done && !frame_complete) begin
                code <= 8'h21;
                state <= FAILED;
              end else begin
                if (accept_logit) begin
                  logit_count <= logit_count + 1;
                  if (!winner_valid || core_logit_data > winner_value) begin
                    winner_value <= core_logit_data;
                    winner_id <= core_logit_index;
                    winner_valid <= 1;
                  end
                end
                if (core_done) state <= DECIDE;
              end
            end
            DECIDE: begin
              if (!winner_valid || logit_count != vocabulary) begin
                code <= 8'h21;
                state <= FAILED;
              end else if (prefill && prompt_index+1 < prompt_count) begin
                prompt_index <= prompt_index + 1;
                position <= position + 1;
                issue_id <= prompt[prompt_index+1];
                state <= ISSUE;
              end else begin
                prefill <= 0;
                if (max_tokens == 0) state <= FINISH;
                else begin
                  selections <= selections + 1;
                  if (winner_id == eos) state <= FINISH;
                  else begin
                    selected_id <= winner_id;
                    selected_last <= selections+1 >= max_tokens;
                    state <= GENERATED;
                  end
                end
              end
            end
            GENERATED: if (generated_valid && generated_ready) begin
              if (selected_last) state <= FINISH;
              else if (position+1 >= sequence_limit) begin
                code <= 8'h31;
                state <= FAILED;
              end else begin
                position <= position + 1;
                issue_id <= selected_id;
                state <= ISSUE;
              end
            end
            FINISH: if (finish_valid && finish_ready) begin
              done_r <= 1;
              state <= IDLE;
            end
            FAILED: state <= FAILED;
            default: begin
              code <= 8'h21;
              state <= FAILED;
            end
          endcase
        end
      end
    end
  endgenerate
endmodule
