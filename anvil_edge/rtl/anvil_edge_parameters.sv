module anvil_edge_parameters #(
  parameter NUM_LAYERS=24, HIDDEN_SIZE=896, INTERMEDIATE_SIZE=4864,
  NUM_Q_HEADS=14, NUM_KV_HEADS=2, HEAD_DIM=64, GROUP_SIZE=128,
  AWQ_BITS=4, VOCAB_SIZE=151936, MAX_SEQ_LEN=32768
) ();
  localparam [127:0] L=NUM_LAYERS, H=HIDDEN_SIZE, I=INTERMEDIATE_SIZE;
  localparam [127:0] Q=NUM_Q_HEADS, K=NUM_KV_HEADS, D=HEAD_DIM;
  localparam [127:0] G=GROUP_SIZE, V=VOCAB_SIZE, S=MAX_SEQ_LEN;
  localparam [127:0] LIMIT=128'd4294967295;
  localparam SAFE_G=GROUP_SIZE>0 ? GROUP_SIZE : 1;
  localparam SAFE_K=NUM_KV_HEADS>0 ? NUM_KV_HEADS : 1;
  localparam VALID =
    NUM_LAYERS>0 && HIDDEN_SIZE>0 && INTERMEDIATE_SIZE>0 &&
    NUM_Q_HEADS>0 && NUM_KV_HEADS>0 && HEAD_DIM>0 && GROUP_SIZE>0 &&
    VOCAB_SIZE>0 && MAX_SEQ_LEN>0 && AWQ_BITS==4 &&
    L<=LIMIT && H<=LIMIT && I<=LIMIT && Q<=LIMIT && K<=LIMIT &&
    D<=LIMIT && G<=LIMIT && V<=LIMIT && S<=128'd16777215 &&
    H==Q*D && NUM_Q_HEADS%SAFE_K==0 && HEAD_DIM%2==0 &&
    HIDDEN_SIZE%SAFE_G==0 && INTERMEDIATE_SIZE%SAFE_G==0 &&
    HIDDEN_SIZE%8==0 && INTERMEDIATE_SIZE%8==0 && (K*D)%8==0 &&
    V*H<=LIMIT && H*H<=LIMIT && H*I<=LIMIT && H*K*D<=LIMIT &&
    L*S*K*D<=LIMIT && S*D<=LIMIT && 2*D<=LIMIT &&
    15*H<=LIMIT && 15*I<=LIMIT;
  generate if (!VALID) begin : invalid_parameters
    initial $fatal(1, "ANVIL_EDGE PARAMETER ERROR: unsupported geometry or address bounds");
  end endgenerate
endmodule
