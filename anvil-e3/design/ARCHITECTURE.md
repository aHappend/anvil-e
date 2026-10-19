# Anvil-E3 implementation contract

## Status and authority

This is the implementation contract, not verification evidence. In particular,
a source inventory or a copied Gen-2 module is
not a passing baseline. The immutable inputs are
`hf_embeddinggemma2_trimodal_spec/` and `anvil_e2_reference/rtl/`. There was no
repository-intake index or accepted execution baseline in this work order.
Only `rtl/*.sv` and `design/*.md` are Designer-owned deliverables.
Independent verification inputs are exactly `tests/*.py`.

The target is `google/embeddinggemma-2`, with the complete audio, vision and
text operations in the admitted specification. External words are signed
Q8.24, converted by the host from the supplied BF16 tensor format. This is not
raw BF16 execution, a pretrained-model quality certification or a physical
implementation claim. Audio input is a host-precomputed time-major log-mel
matrix. Image preprocessing, audio feature extraction and tokenization remain
host responsibilities. All computation after those input boundaries is RTL.

## Cycle & Degenerate-Boundary Table

All transfers sample **pre-edge** valid and ready on a rising edge. Register
changes and output observations below are **post-edge**, after nonblocking
assignments settle. There is one job and at most one memory transaction in
flight. New logic uses `clk` and asynchronous active-low `rst_n`, without a new
gated clock. Reset wins over all simultaneous transfers.

| Event | Pre-edge condition | Post-edge effect |
|---|---|---|
| Active reset | `rst_n=0` | All external outputs, including payload fields, `job_ready` and `busy`, are immediately zero; no transfer. |
| Reset release | Idle, `rst_n=1` | `job_ready=1`, `busy=0`, before the first accepting edge. |
| Descriptor edge E | `job_valid && job_ready` | Capture every descriptor pin once; `job_ready=0`, `busy=1`; no request, embedding or completion. |
| Validation E+1 | Captured descriptor | Descriptor errors become held completion, with no memory access. Descriptor errors precede extent errors. A legal job enters stage start. |
| Stage start A | `start_valid && start_ready` | Capture stage command; leave idle. No command is combinationally accepted through the stage start. |
| Audio vector dispatch A+1 | Valid captured command | Select clipping-load, input-load or element-read state. First internal memory command may be valid after this edge, not before A+1. |
| Convolution start A | Accepted start | Initialize counters; validate after A+1; select the first tap after A+2. Padding taps skip the read. |
| Memory command C | `cmd_valid && cmd_ready` | Bridge captures command; external held request is valid after C. |
| External request R | `mem_req_valid && mem_req_ready` | Request deasserts; response-ready asserts after R. An early response must be held by memory until accepted. |
| External response S | `mem_rsp_valid && mem_rsp_ready` | Bridge holds internal result after S; no combinational request-to-result bypass. |
| Internal result U | `result_valid && result_ready` | Bridge becomes command-ready after U. Memory error takes priority over payload interpretation. |
| Audio load response | Accepted successful result | Captures one operand. A dependent multiply/activation or feed is in a subsequent state/edge. |
| Audio matrix last product | Final reduction edge | Round the entire wide dot product once; then bias, clipping, and eventual Q8.24 materialization in distinct states. |
| Audio normalization | All channels fed | Mean-square division, root and per-channel ratio/gamma stages complete before each held output. Latency is data dependent through the reused divider/root implementation. |
| Audio activation | Input accepted | Request range-reduced exponential on a later edge; consume it, divide, then apply SiLU/sigmoid/cap or the bounded log series. Hold result until consumed. |
| Audio stage result | `done_valid && done_ready` | Stage returns idle; next stage starts on a separate edge. |
| Held request/result/output | Valid, not ready | Payload and valid remain stable through every stalled edge. |
| Last embedding F | `emb_valid && emb_ready && emb_last` | Success completion may assert at or after post-F, never before F. |
| Completion D | `done_valid && done_ready` | Idle/job-ready after D. A continuously asserted job-valid cannot accept the next job until D+1. |
| Any memory error | Accepted erroneous response | Retire that accepted transaction, issue no further command and finish with error 3. |
| Reset with pending transaction | Any state | Abort job and transaction. Memory environment discards corresponding pre-reset responses. |

Counters use explicit terminal comparisons and resets, never implicit binary
wrap. No power-of-two sequence capacity is assumed. There is no fixed total
job latency: each scalar read/write costs one internal command acceptance, one
external request acceptance, one external response acceptance and one internal
result acceptance, plus stage arithmetic/dispatch edges and arbitrary stalls.
Matrix work is `tokens*rows*cols` multiply-accumulates; spatial convolution work
is `Tout*Fout*Cout*Cin*9` taps, with padding taps omitted. Depthwise work is
`tokens*channels*kernel` taps, also omitting padding. Stage serialization makes
the number of accepted memory beats independently computable from these loops.

The new modules have the following exact staging; arrows each denote one
rising-edge state transition, except states explicitly waiting for a handshake.
No result is combinationally bypassed to a caller.

| Module | Accepted-start to first operation | Result/retirement |
|---|---|---|
| `audio_subsample` | A: capture -> DISPATCH; A+1: select child -> LAUNCH; A+2: child accepts. | Each child DONE is accepted in WAIT; DISPATCH/LAUNCH separate successive operations. Parent DONE follows final projection DONE acceptance. |
| `audio_conformer` | Same two-edge child launch as subsample. | 29 operations in published order; DONE follows norm-out's child DONE acceptance. |
| `audio_bridge` | A: capture -> LAUNCH; A+1: vector engine accepts. | First projection DONE -> LAUNCH; second starts next edge. Second DONE -> parent DONE. |
| `audio_vector` | A: capture -> DISPATCH; A+1: extent check then BOUND_REQ, NORM_START or LOAD_REQ. | Each write request waits for its response. The last write-response acceptance makes DONE valid post-edge. Errors enter FLUSH for one edge, resetting active arithmetic, then DONE. |
| `audio_conv` | A -> VALIDATE -> SELECT -> INPUT_REQ (or NEXT for padding). | INPUT_RSP -> WEIGHT_REQ -> WEIGHT_RSP -> MAC -> NEXT. NEXT advances tap or latches final sum into WRITE_REQ. Last write response -> DONE. |
| `audio_norm` | A: capture -> LOAD; each input transfer stores one value/gamma and adds its square; last -> SETUP. | Mean division -> ROOT_SETUP -> ROOT -> PREPARE -> ratio division -> APPLY -> HOLD. Each accepted output advances to PREPARE or, for last, IDLE. |
| `audio_activation` | A: capture -> EXP_START; exponential accepts at A+1. | EXP_WAIT -> DIV_START -> DIV_WAIT -> APPLY -> HOLD; softplus replaces APPLY with exactly 15 LOG_TERM edges. HOLD remains until accepted. |
| `audio_relative` | A: capture -> ANGLE for pair zero, otherwise FREQUENCY_START. | Frequency exp result -> ANGLE -> TRIG_START -> TRIG_WAIT -> HOLD. Pair zero omits the frequency exponential, not sine/cosine. |
| `audio_attention` | A: capture -> SETUP; A+1: latch chunk bounds -> QREQ. | Scale each query component before score work; compute every key twice (maximum, then stable weighted pass); divide each value channel -> WRITE_REQ -> WRITE_RSP. Last query/head/channel write response -> DONE. |
| `trimodal_fusion` | A: capture -> VALIDATE; A+1 -> SELECT; A+2 -> ID_REQ or generated ID_WRITE. | ID/position/mask write responses precede vector reads/writes. Last vector write response -> DONE. |

For RMSNorm, let `b=bit_length(mean_square_Q80+17*2^56)` and
`g=ceil((b+64)/16)`. ROOT performs exactly g edges, eight root bits per
edge, before PREPARE. The zero L2 denominator skips ROOT. The reused divider
returns after one ROUND edge for powers of two or a smaller numerator;
otherwise it uses `ceil(ceil((bit_length(abs(n))-bit_length(d)+1)/16)/4)`
RUN edges followed by one ROUND edge. Output is held in HOLD in either case.
The inherited exponential/trigonometric series evaluates four terms per edge,
at most 18 terms, terminating early on a zero next term; its result passes
through FINISH and HOLD (with divider stages for reciprocal/GELU).

For successful jobs, accepted memory-beat counts of new operations are:

| Operation | Read-plus-write responses (one per accepted request) |
|---|---|
| Matrix, T vectors, R rows, C columns | `(clipped?4:0)+T*(C+R*C+R*(1+(bias?1:0)))` |
| Channel RMSNorm, T vectors of R channels | `3*T*R` |
| SiLU / copy | `2*T*R` |
| Residual add / GLU | `3*T*R` |
| Reorder, T vectors of R-by-C entries | `2*T*R*C` |
| Spatial or depthwise convolution | One write per output plus two reads per nonpadding input-channel/kernel tap |
| Audio attention | `3*T*H+H*(2*H+3)*sum_t(eligible_key_count(t))` |
| Audio bridge | `T*(H+O*H+3*O+TH*O+TH)` |
| Fusion | `N*(3+2*TH)+3*text_tokens` |

The 29 Conformer operations each incur parent DISPATCH/LAUNCH/WAIT result
edges as listed above. Combine their operator counts with each operator's
published state path and arithmetic iteration count to determine unstalled
latency; add the actual wait edges of each ready/valid channel. A bridge
transaction alone needs four distinct accepting edges C/R/S/U, so no
transaction is modeled as a zero-time host call. Arithmetic can progress
while a result/write is stalled, as prescribed by those separate state paths.
There is deliberately no dimension-independent or memory-independent job
latency claim.

| Boundary | Legal case / required behavior |
|---|---|
| Minimum audio | hidden=FFN=heads=head-dim=out-dim=C0=C1=freq-bins=kernel=1; no zero-width counters. |
| Short audio | Input lengths 1,2,3,4,5 produce lengths 1,1,1,1,2; centered padding works even for fewer than five output frames. |
| Ragged sizes | Non-power-of-two dimensions/counts terminate at `count-1`, not at counter wrap. |
| Chunk boundary | Output lengths 11,12,13 exercise key bounds at chunk transitions; left-context exclusion must be observable. |
| Layer counts | Audio 1/2/12, vision 16, text 5/6/7/24; layer index `%6==5` alone selects text full attention. |
| Minimum retained geometry | Vision head-dim=4, hidden=4; text hidden=PLE=FFN=Q-heads=KV-heads=1, local/full head-dim=2. |
| Minimum output | EMBED_DIM=6 permits prefixes 6,4,2,1; dimension-one output has first and last simultaneously. |
| Special IDs | Modality modes require a vocabulary containing the literal IDs; never modulo-remap IDs for small widths. |
| Simultaneous actions | Reset > error response > normal state action. Reads and writes cannot be accepted simultaneously on the single command channel. |
| All-masked / zero prefix | No valid pooled tokens is error 4; an exactly zero selected prefix successfully emits zero. |
| Illegal geometry | Explicit parameter failure, not an identity/stub datapath. Only legal geometry is a synthesis target. |

## Public job interface

The top entry is `anvil_e3_top` in `rtl/anvil_e3_top.sv`. Preserve the Gen-2
ports, widen `job_mode` to three bits, and add `job_audio_frames[31:0]`,
`audio_weights_base[63:0]`, `audio_base[63:0]`. Other widths, directions and
signedness follow the admitted interface: only `emb_data[31:0]` is signed;
memory words are bit containers. Embedding indices are increasing from zero.

| Direction | Ports | Width |
|---|---|---|
| Input | `clk`, `rst_n`, `job_valid`, `mem_req_ready`, `mem_rsp_valid`, `mem_rsp_error`, `emb_ready`, `done_ready` | 1 |
| Input | `job_mode` | 3 |
| Input | `job_tokens`, `job_patch_rows`, `job_patch_cols`, `job_audio_frames`, `mem_rsp_rdata` | 32 |
| Input | `job_output_dim` | 16 |
| Input | `weights_base`, `vision_weights_base`, `audio_weights_base`, `image_base`, `audio_base`, `tokens_base`, `positions_base`, `mask_base`, `scratch_base` | 64 |
| Output | `job_ready`, `mem_req_valid`, `mem_req_write`, `mem_rsp_ready`, `emb_valid`, `emb_last`, `done_valid`, `busy` | 1 |
| Output | `mem_req_addr` | 64 |
| Output | `mem_req_wdata`, signed `emb_data` | 32 |
| Output | `emb_index` | 16 |
| Output | `done_error` | 4 |

| Mode | Audio | Vision | Text |
|---|---|---|---|
| 0 | no | no | yes |
| 1 | no | yes | no |
| 2 | no | yes | yes |
| 3 | yes | no | no |
| 4 | yes | no | yes |
| 5 | yes | yes | no |
| 6 | yes | yes | yes |
| 7 | invalid | invalid | invalid |

Text modes require positive `job_tokens`; nontext modes require zero.
Present audio requires positive frames. Present vision requires positive patch
rows/columns, within POSITION_EMBEDDING_SIZE, with
`ceil(rows/POOL_KERNEL)*ceil(cols/POOL_KERNEL)=VISION_SOFT_TOKENS`.
Absent modality descriptors and bases are ignored, with no corresponding
access. Active ranges must be disjoint, four-byte aligned and sufficiently
allocated by the host. RTL checks alignment and computable extents before
transactions, using widened calculations.

| Error | Meaning |
|---|---|
| 0 | Success |
| 1 | Invalid descriptor |
| 2 | Invalid token, shifted position, mask or loaded clipping bounds |
| 3 | Memory response error |
| 4 | No valid pooled tokens |
| 5 | Address/extent overflow |
| 6 | Internal arithmetic/control failure |

Every accepted write, like every read, has exactly one response. Write response
data are ignored. Responses can appear as early as the request-acceptance
cycle, but must remain valid until response-ready; the bridge deliberately
does not accept that response on the request edge. Completion is held until
accepted. No output is emitted after an error, although accepted earlier beats
cannot be retracted.

## Parameter defaults and legality

| Parameter | Default |
|---|---|
| AUDIO_LAYERS / AUDIO_HIDDEN / AUDIO_FFN | 12 / 1024 / 4096 |
| AUDIO_HEADS / AUDIO_HEAD_DIM / AUDIO_OUT_DIM | 8 / 128 / 1536 |
| AUDIO_CONV_KERNEL / AUDIO_SUBSAMPLE_C0 / AUDIO_SUBSAMPLE_C1 / AUDIO_FREQ_BINS | 5 / 128 / 32 / 128 |
| AUDIO_CHUNK_SIZE / AUDIO_CONTEXT_LEFT / AUDIO_CONTEXT_RIGHT | 12 / 13 / 0 |
| VISION_LAYERS / VISION_HIDDEN / VISION_FFN | 16 / 768 / 3072 |
| VISION_HEADS / VISION_HEAD_DIM / PATCH_SIZE / POOL_KERNEL / VISION_SOFT_TOKENS | 12 / 64 / 16 / 3 / 280 |
| TEXT_LAYERS / TEXT_HIDDEN / PLE_DIM / TEXT_FFN / EMBED_DIM | 24 / 512 / 512 / 2048 / 768 |
| VOCAB_SIZE / POSITION_EMBEDDING_SIZE | 262144 / 10240 |
| TEXT_Q_HEADS / LOCAL_KV_HEADS / FULL_KV_HEADS | 4 / 2 / 1 |
| LOCAL_HEAD_DIM / FULL_HEAD_DIM / SLIDING_WINDOW / MAX_SEQ_LEN | 256 / 512 / 512 / 262144 |

All dimensions, layer counts and windows are positive; audio contexts alone
may be zero. Audio head count times head dimension equals hidden size; kernel
is odd. Vision head count times head dimension equals hidden size and vision
head dimension is divisible by four. Text query head count divides into both
KV head counts as contiguous groups; local/full head dimensions are positive
and even. EMBED_DIM is at least six and divisible by six.

All materialized vector/matrix channel dimensions are at most 65535, including
the derived `2*AUDIO_HIDDEN`, `AUDIO_SUBSAMPLE_C1*ceil(AUDIO_FREQ_BINS/4)`,
`3*PATCH_SIZE*PATCH_SIZE` and both text Q-head-count times head-dimension
products. Audio layers, hidden, FFN, heads, head dimension, output dimension,
subsampling channels, frequency bins and kernel are bounded accordingly.
Vision and text layers/hidden/FFN, PLE and embedding dimensions also obey the
inherited 16-bit limits. Runtime sequence/count interfaces are 32-bit, with
widened expressions used before any narrowing or address formation.
There are no DEPTH/MAX_WORDS top parameters. Illegal top geometry selects
an explicit `$fatal` branch in simulation; synthesis must select a legal
configuration, in which that branch is absent. It never selects a successful
fake computation.

## Audio weight blob

Let `H=AUDIO_HIDDEN`, `F=AUDIO_FFN`, `D=AUDIO_HEAD_DIM`,
`O=AUDIO_OUT_DIM`, `K=AUDIO_CONV_KERNEL`, `C0=AUDIO_SUBSAMPLE_C0`,
`C1=AUDIO_SUBSAMPLE_C1`, `B=AUDIO_FREQ_BINS`, `F1=ceil(B/2)`,
`F2=ceil(B/4)`. All offsets below are **words** relative to
`audio_weights_base`; multiply offsets by four for byte addresses. Matrices
are output-row/input-column row-major; conv kernels flatten declared axes.
Scalars occupy one word. There is no alignment padding between tensors.

First pack exactly:

| Relative HF name under `audio_tower.subsample_conv_projection` | Shape | Words |
|---|---|---|
| `layer0.conv.weight` | `[C0,1,3,3]` | `9*C0` |
| `layer0.norm.weight` | `[C0]` | `C0` |
| `layer1.conv.weight` | `[C1,C0,3,3]` | `9*C1*C0` |
| `layer1.norm.weight` | `[C1]` | `C1` |
| `input_proj_linear.weight` | `[H,C1*F2]` | `H*C1*F2` |

Call their total `S=10*C0+9*C1*C0+C1+H*C1*F2`.
Then pack layers in **numeric layer order**, 0 through AUDIO_LAYERS-1.
Within each layer pack the following 62 tensors in complete relative-name
lexicographic order. The compact table expands each clipped block into five
successive entries in the stated order, not an implementation-private layout.

`CLIP(name,R,C)` expands to `name.input_max []`, `name.input_min []`,
`name.linear.weight [R,C]`, `name.output_max []`, `name.output_min []`,
occupying `R*C+4` words. Bounds are loaded signed Q8.24 values and checked
lower <= upper. Every input element is clamped before reduction; each completed
output is clamped after reduction, before storage.

| Order | Relative HF name under `audio_tower.layers.L` | Shape / expansion |
|---|---|---|
| 1 | `feed_forward1.ffw_layer_1` | `CLIP(...,F,H)` |
| 2 | `feed_forward1.ffw_layer_2` | `CLIP(...,H,F)` |
| 3 | `feed_forward1.post_layer_norm.weight` | `[H]` |
| 4 | `feed_forward1.pre_layer_norm.weight` | `[H]` |
| 5 | `feed_forward2.ffw_layer_1` | `CLIP(...,F,H)` |
| 6 | `feed_forward2.ffw_layer_2` | `CLIP(...,H,F)` |
| 7 | `feed_forward2.post_layer_norm.weight` | `[H]` |
| 8 | `feed_forward2.pre_layer_norm.weight` | `[H]` |
| 9 | `lconv1d.conv_norm.weight` | `[H]` |
| 10 | `lconv1d.depthwise_conv1d.weight` | `[H,1,K]` |
| 11 | `lconv1d.linear_end` | `CLIP(...,H,H)` |
| 12 | `lconv1d.linear_start` | `CLIP(...,2*H,H)` |
| 13 | `lconv1d.pre_layer_norm.weight` | `[H]` |
| 14 | `norm_out.weight` | `[H]` |
| 15 | `norm_post_attn.weight` | `[H]` |
| 16 | `norm_pre_attn.weight` | `[H]` |
| 17 | `self_attn.k_proj` | `CLIP(...,H,H)` |
| 18 | `self_attn.per_dim_scale` | `[D]` |
| 19 | `self_attn.post` | `CLIP(...,H,H)` |
| 20 | `self_attn.q_proj` | `CLIP(...,H,H)` |
| 21 | `self_attn.relative_k_proj.weight` | `[H,H]`, no clipping scalars |
| 22 | `self_attn.v_proj` | `CLIP(...,H,H)` |

The per-layer total is `Lw=4*F*H+8*H*H+9*H+H*K+D+40`.
Its base is `S+layer_index*Lw`; each row's offset is the sum of the preceding
rows' word counts. These formulas, not lexical sorting of decimal layer
numbers, define the layout. There are ten clipped blocks (40 scalars), 12
matrix/kernel tensors and 10 other vector tensors per layer, totaling 62.
The layout module's public group numbers 0..4 correspond to the five initial
subsampling rows, 5..26 to the 22 layer groups above, and 27..29 to the three
final tensors below. These are group selectors, not additional tensor words.

After all layers, pack `audio_tower.output_proj.weight [O,H]`, then
`audio_tower.output_proj.bias [O]`, then
`embed_audio.embedding_projection.weight [TEXT_HIDDEN,O]`. The total audio
weight extent is `4*(S+AUDIO_LAYERS*Lw+O*H+O+TEXT_HIDDEN*O)` bytes.
At default layer count the tensor count is `5+12*62+3=752`.

## Audio operations and explicit assumptions

Both subsampling convolutions use stride (2,2), centered one-element
zero-padding, no bias; channel RMSNorm and SiLU follow each convolution.
Spatial storage is `[time,frequency,channel]` for convolution and channel
normalization. Flatten into projection inputs in **channel-major,
frequency-minor** order. Thus T1=ceil(T/2), T2=ceil(T/4); retain all T2 outputs.

Each Conformer layer executes FF1 pre-norm, clipped F-by-H matrix, SiLU,
clipped H-by-F matrix, post-norm, half residual; attention pre-norm, Q/K/V,
relative attention, post projection/post-norm, residual; lconv pre-norm,
clipped 2H-by-H start, first-half value times second-half sigmoid, centered
per-channel K-tap temporal convolution, conv-norm, SiLU, clipped end, residual;
FF2 using its own weights and half residual; norm-out.
Audio gamma multiplies directly; retained text/vision gamma retains 1+weight.

For query t, chunk start `b=floor(t/AUDIO_CHUNK_SIZE)*AUDIO_CHUNK_SIZE`;
keys range from `max(0,b-AUDIO_CONTEXT_LEFT)` inclusive to
`min(T2,b+AUDIO_CHUNK_SIZE+AUDIO_CONTEXT_RIGHT)` exclusive. Same-chunk
future keys remain eligible when right context is zero. Relative channels
alternate sin/cos of `(t-j)/10000^(2*i/H)` with incomplete final pairs
truncated. Project the relative vector through its own H-by-H matrix.
Scale Q channel d by
`softplus(per_dim_scale[d])/(ln(2)*sqrt(AUDIO_HEAD_DIM))`.
Score content and relative key together; cap with `50*tanh(score/50)`,
then stable softmax over eligible keys, weighted V, and post projection.
Padding, direct gamma, relative formulas and query scaling are
`no_operator_assumption` choices resolving absent modeling code, not formulas
claimed to be in the JSON.

Audio bridge is H->O with the supplied output bias, then O->TEXT_HIDDEN
without an invented bridge bias.

## Numeric boundaries

Internal audio operands and reused arithmetic use Q40 in signed 48-bit
containers where representable; products/reductions use at least signed
128-bit accumulators. Convolution and linear reductions round once on the
complete reduction. All narrowing is round-to-nearest, ties-to-even, with
saturation to external signed Q8.24 range rather than wrapping. Scratch is
32-bit Q8.24, so writing an intermediate explicitly quantizes it.
Half residuals first round the half in Q40 ties-to-even, then saturate the sum.
Retained norm epsilon is `(17 << 56)` in the Q80 mean-square domain,
equivalent to `17/2^24` in real units (Q40 value `17<<16`).
Audio norms use that same stored effective epsilon and direct gamma.
Stable sigmoid/SiLU use exp(-abs(x)); softplus uses
`max(x,0)+log(1+exp(-abs(x)))`. The logarithm uses the bounded atanh series
with argument at most 1/3. No real-number RTL or host numerical fallback is
permitted.
Negative exponential arguments are floored at -16 by the retained bounded
exponential implementation. Softplus's log series has 16 terms total
(initial term plus 15 iterations); sine/cosine and exp reuse the retained
range-reduced 18-term series. Attention uses wider signed 64-bit Q40 query
scales and relative projections, and a 128-bit dot reduction. Logits outside
+/-600 are bounded there before tanh evaluation, well into tanh saturation;
this does not replace the required 50*tanh cap with an identity or a clip.
Relative vectors and projected relative keys remain Q40 internally; Q/K/V,
operator outputs and every external scratch write are Q8.24. The biased
output projection retains its wide rounded dot value until bias addition,
then materializes; it does not prematurely saturate a dot before adding bias.
Quantization occurs at each published scratch-producing operator boundary,
including norm, SiLU, GLU and residual operators. Relative sine frequencies
are computed in Q40 from the real-form exponent, with no real-number RTL.

## Retained text/vision layouts

Copied `anvil_e2_*` leaf modules in `rtl/` retain their names and algorithms.
Their source originals are read-only. Text global tensors in order are
`language_model.embed_tokens.weight [VOCAB_SIZE,TEXT_HIDDEN]`,
`embedding_projection.weight [EMBED_DIM,TEXT_HIDDEN]`,
`norm.weight [TEXT_HIDDEN]`,
`ple.per_layer_model_projection.weight [TEXT_LAYERS*PLE_DIM,TEXT_HIDDEN]`,
`ple.per_layer_projection_norm.weight [PLE_DIM]`, all under
`language_model.`. Each subsequent layer packs:

| ID | Relative tensor | Shape |
|---|---|---|
| 5 | `input_layernorm.weight` | `[H]` |
| 6 | `layer_scalar` | `[1]` |
| 7 | `mlp.down_proj.weight` | `[H,F]` |
| 8 | `mlp.gate_proj.weight` | `[F,H]` |
| 9 | `mlp.up_proj.weight` | `[F,H]` |
| 10 | `ple_block.per_layer_input_gate.weight` | `[P,H]` |
| 11 | `ple_block.per_layer_projection.weight` | `[H,P]` |
| 12 | `ple_block.post_per_layer_input_norm.weight` | `[H]` |
| 13 | `post_attention_layernorm.weight` | `[H]` |
| 14 | `post_feedforward_layernorm.weight` | `[H]` |
| 15 | `pre_feedforward_layernorm.weight` | `[H]` |
| 16 | `self_attn.k_norm.weight` | `[d]` |
| 17 | `self_attn.k_proj.weight` | `[kv*d,H]` |
| 18 | `self_attn.o_proj.weight` | `[H,q*d]` |
| 19 | `self_attn.q_norm.weight` | `[d]` |
| 20 | `self_attn.q_proj.weight` | `[q*d,H]` |
| 21 | `self_attn.v_proj.weight` | `[kv*d,H]` |

Here H=TEXT_HIDDEN, F=TEXT_FFN, P=PLE_DIM, q=TEXT_Q_HEADS; d and kv select
full settings only when layer%6==5. Tensor bases are cumulative word counts,
with numeric layer order and the listed order within each layer.
At default 24-layer count the full layers are exactly 5,11,17,23. The retained
backbone uses contiguous GQA groups, local sliding window 512 by default,
RoPE theta 10000 for local and 1000000 for full attention, GELU-tanh gated
FFN, PLE gates/projections/norms and learned layer scalars. Vision retains
axial RoPE theta 100, GELU-tanh FFN and pool kernel 3. These operations are
not replaced by routing/signature-only approximations.

Vision packs `vision_tower.patch_embedder.input_proj.weight`
`[VISION_HIDDEN,3*PATCH_SIZE*PATCH_SIZE]`,
row positions `[POSITION_EMBEDDING_SIZE,VISION_HIDDEN]`, column positions
of the same shape, all vision layers, then bridge `[TEXT_HIDDEN,VISION_HIDDEN]`.
Positions are the two planes of
`vision_tower.patch_embedder.position_embedding_table [2,POSITION_EMBEDDING_SIZE,H]`;
the bridge is `embed_vision.embedding_projection.weight`.
Per-layer order is input norm H, q H-by-H, k H-by-H, v H-by-H, o H-by-H,
q norm D, k norm D, post-attention norm H, pre-FF norm H, gate F-by-H,
up F-by-H, down H-by-F, post-FF norm H. This occupies
`4*H+4*H*H+2*D+3*H*F` words. The image layout is channel-major
`[3,patch_rows*PATCH_SIZE,patch_cols*PATCH_SIZE]`.
Layer names are under `vision_tower.encoder.layers.L.`:
`input_layernorm.weight`, `self_attn.{q,k,v,o}_proj.linear.weight`,
`self_attn.{q,k}_norm.weight`, `post_attention_layernorm.weight`,
`pre_feedforward_layernorm.weight`, `mlp.{gate,up,down}_proj.linear.weight`,
and `post_feedforward_layernorm.weight`, in the just-specified packing order.

## Scratch ownership and framing

All following offsets are words from `scratch_base`, packed without gaps.
No private on-chip array is used as an undeclared full-sequence buffer.

Let `P=rows*cols` when vision is present, otherwise zero;
`S=VISION_SOFT_TOKENS` when vision is present, otherwise zero; T1/T2 are
zero when audio is absent. `N=text_tokens+(audio?T2+2:0)+(vision?S+2:0)`.
Let `VH=VISION_HIDDEN`, `TH=TEXT_HIDDEN`,
`DM=max(LOCAL_HEAD_DIM,FULL_HEAD_DIM)`, `KM=max(LOCAL_KV_HEADS,FULL_KV_HEADS)`,
`AW=max(AUDIO_FFN,2*AUDIO_HIDDEN)`.

| Region in packing order | Words | Producer -> consumer |
|---|---|---|
| vision x0 | `P*VH` | patch embed / encoder ping-pong -> encoder / pool |
| vision x1 | `P*VH` | encoder ping-pong -> encoder / pool |
| vision q | `P*VISION_HEADS*VISION_HEAD_DIM` | encoder projections -> attention |
| vision k | same | encoder projections -> attention |
| vision v | same | encoder projections -> attention |
| vision soft tokens | `S*TH` | vision pool/projection -> fusion |
| fused IDs | `N` | fusion -> retained frontend/backbone |
| fused positions | `N` | fusion -> backbone |
| fused masks | `N` | fusion -> backbone/pool |
| text x0 | `N*TH` | fusion / backbone ping-pong -> backbone / final pool |
| text x1 | `N*TH` | backbone ping-pong -> backbone / final pool |
| PLE | `N*TEXT_LAYERS*PLE_DIM` | frontend -> every text layer |
| text q | `N*TEXT_Q_HEADS*DM` | backbone -> attention |
| text k | `N*KM*DM` | backbone -> attention |
| text v | `N*KM*DM` | backbone -> attention |
| conv0 raw | `T1*F1*C0` | subsample conv0 -> norm0 |
| conv0 normalized/activated | `T1*F1*C0` | norm0/SiLU -> conv1 |
| conv1 raw | `T2*F2*C1` | subsample conv1 -> norm1 |
| conv1 normalized/activated | `T2*F2*C1` | norm1/SiLU -> reorder |
| audio flatten | `T2*C1*F2` | reorder -> input projection |
| audio x0 | `T2*AUDIO_HIDDEN` | input projection / layer ping-pong -> layer / bridge |
| audio x1 | `T2*AUDIO_HIDDEN` | layer ping-pong -> layer / bridge |
| audio work0 | `T2*AW` | Conformer operators, sequential exclusive ownership |
| audio work1 | `T2*AW` | Conformer operators, sequential exclusive ownership |
| audio q | `T2*AUDIO_HIDDEN` | Q projection -> attention |
| audio k | `T2*AUDIO_HIDDEN` | K projection -> attention |
| audio v | `T2*AUDIO_HIDDEN` | V projection -> attention |
| audio attention result | `T2*AUDIO_HIDDEN` | relative attention -> post projection |
| audio output projection | `T2*AUDIO_OUT_DIM` | biased output projection -> bridge projection |
| audio soft tokens | `T2*TH` | bridge projection -> fusion |

The base of a region is the sum of the word extents of all preceding rows;
total scratch bytes are four times their sum. This preserves the complete
legacy scratch order and offsets in modes 0/1/2, with zero audio extents.
Text Q/K/V token strides always reserve the maximum head dimensions, even
for a local layer. PLE layout is `[token,layer,PLE_channel]`.
Audio work vectors are tightly packed for each operator's actual channel
count, not with an AW stride; the allocation merely reserves the maximum.
Vision/text/audio initial current-x is x0. Each completed layer places its
result in the other x region, then the top atomically toggles ownership.
No toggle occurs on error. Within an audio layer, the initial x is kept until
FF1's residual has been written to next-x. Later residuals and norm-out update
next-x in place. An in-place channel RMSNorm loads the entire channel vector
before writing it; depthwise convolution never aliases its input and output.

The subsample public `work_base` points at conv0 raw; its internal order is
exactly conv0 raw, conv0 normalized, conv1 raw, conv1 normalized, flatten.
The bridge public `work_base` points at audio output projection. The Conformer
has explicit bases for its x0/x1, work0/work1, Q/K/V and attention regions.

| Audio region | Words | Format / ownership |
|---|---|---|
| conv0 raw / normalized | each `T1*F1*C0` | `[time,freq,channel]`, subsample owns until conv1 completes |
| conv1 raw / normalized | each `T2*F2*C1` | `[time,freq,channel]`, subsample owns until input projection completes |
| flatten | `T2*C1*F2` | `[time,channel,freq]`, subsample |
| audio x0 / x1 | each `T2*H` | `[time,channel]`, layer ping-pong, norm-out releases result |
| layer work0 / work1 | each `T2*max(F,2*H)` | temporary operators, never overwrite live residual source |
| q / k / v / attention | each `T2*H` | conformer attention owns |
| output projection | `T2*O` | bridge owns until second projection finishes |
| audio soft tokens | `T2*TEXT_HIDDEN` | bridge produces; fusion reads |

Fusion order is audio, vision, text. Audio IDs are 256000 (BOA), T2 copies
of 258881 (AUDIO), 258883 (EOA); vision IDs are 255999 (BOI),
VISION_SOFT_TOKENS copies of 258880 (IMAGE), 258882 (EOI). Boundary vectors
use learned text token embeddings times sqrt(TEXT_HIDDEN); bridge vectors
replace placeholders without a second scale. Placeholder IDs still feed PLE.
Generated masks are one, positions start at zero and increase across frames.
Text positions are caller positions plus total preceding frame length; masks
must be 0 or 1. IDs, positions, masks and initial hidden vectors are stored in
separate external scratch regions and consumed by the retained frontend.

The final embedding prefix is independently L2-normalized after masked mean
pooling with prompt inclusion. Legal prefixes are EMBED_DIM, 2*EMBED_DIM/3,
EMBED_DIM/3 and EMBED_DIM/6, exactly 768/512/256/128 at defaults.

## Integration examples and source selection

Compile only delivered `rtl/*.sv`, with `anvil_e3_top` explicitly selected:
`iverilog -g2012 -t null -s anvil_e3_top rtl/*.sv`. All files define modules;
there are no include-path or package-order dependencies. The ordered expanded
source list and actual tool version belong in execution evidence. Do not
include reference duplicates in the same compilation; reference comparison
runs use a separate top/executable. Never select `.vulcan/`, `.git/`,
`.tooling/` or `VULCAN/` as deliverable sources.

For a minimum integrated geometry set AUDIO_LAYERS/HIDDEN/FFN/HEADS/HEAD_DIM/
OUT_DIM/SUBSAMPLE_C0/SUBSAMPLE_C1/FREQ_BINS/CONV_KERNEL to 1,
VISION_LAYERS=1, VISION_HIDDEN=4, VISION_FFN=1, VISION_HEADS=1,
VISION_HEAD_DIM=4, PATCH_SIZE=1, POOL_KERNEL=1, VISION_SOFT_TOKENS=1,
TEXT_LAYERS=1, TEXT_HIDDEN=PLE_DIM=TEXT_FFN=TEXT_Q_HEADS=LOCAL_KV_HEADS=
FULL_KV_HEADS=1, LOCAL_HEAD_DIM=FULL_HEAD_DIM=2 and EMBED_DIM=6.
Keep VOCAB_SIZE=262144 for modality jobs. POSITION_EMBEDDING_SIZE,
SLIDING_WINDOW and MAX_SEQ_LEN remain positive and large enough for the job.
With mode 6, five input audio frames, one patch row/column and one text token,
T2=2 and N=8. Selecting output dimension 1 is legal and emits one beat.
This example is an integration geometry, not a claimed functional test.

At production defaults an example shape is audio frames=48, patch rows=42,
patch columns=60 and text tokens=1, mode 6: T2=12, vision pool grid=14*20=280,
and N=297. Pack weights with the tables above, allocate disjoint input and
scratch extents, assert reset, release it, then present the complete descriptor
with job-valid until edge E. Descriptor pins may change after E. Respond once
to every accepted memory read/write, obey all backpressure, consume each
embedding beat, and finally accept completion. No host-side audio projection,
expected-result injection or test-only arithmetic port is required or allowed.

Tool prerequisites for independent checks are Python 3, Icarus Verilog/vvp
with SystemVerilog 2012 support and Yosys. No tool/package/model download is a
runtime requirement of the RTL. Supplied official weight slices remain
independent data inputs, not a claim that complete pretrained audio weights
are available. Functional/synthesis tool versions and results must be recorded
by Verifier; the Designer's null-target compiler result certifies syntax only.

## Claim-to-check ownership

| Claim | Independent Verifier check |
|---|---|
| Default parameters and complete hierarchy | Default static elaboration, geometry rejection and source/hierarchy inventory |
| Audio numerical completeness | Quantized mathematical oracle for every tensor class, layer index and operator; nontrivial nonzero weights/signals |
| Retained vision/text behavior | Independent oracle plus side-by-side Gen-2 regression, official supplied slices where applicable |
| Framing and prefix normalization | All seven modes at two geometries; literal IDs; actual 768/512/256/128 output cases |
| Protocol/reset/error behavior | Pre-edge transfer scoreboard, post-edge assertions, independent/simultaneous stalls, errors and resets |
| Defect sensitivity | Executable numerical/protocol-rejected isolated mutants, never edits to accepted sources |
| Synthesizability/no latches | Whole-top Yosys at two legal geometries, structural assertions after lowering and synthesis |

The numerical acceptance remains component absolute error <=0.002 and
nonzero-vector cosine similarity >=0.999 against an independent quantized
mathematical oracle on bounded nonsaturating vectors. Every nonzero selected
prefix must satisfy `abs(sum(y_i*y_i)-1)<=0.002`. Exact integer checks cover
rounding ties, saturation, clipping, addressing, framing and zero handling
separately. These are required independent checks, not results asserted by
this document. All modes 0..6 at two distinct legal scaled geometries, complete
12/16/24 layer counts at small widths, and actual 768/512/256/128 prefix
emission are mandatory; minimum-width smoke cases cannot replace them.

Verifier owns `tests/verify.py` and all functional, oracle, mutation and synthesis
execution. Designer may only run a final static null-target elaboration.
No performance, power, area, clock frequency, tapeout, board or pretrained
quality claim follows from those checks. The shared runtime produces any
product report only after independent engineering acceptance.
