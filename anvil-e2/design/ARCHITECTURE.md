# Anvil-E2 implementation contract

## Scope and provenance

The supplied configuration, both tensor manifests, modules.json, pooling
configuration and sentence_bert_config.json are the architectural inputs.
The Gen-1 RTL is arithmetic and sequencing prior art, not a passing E2 baseline.
Audio is excluded. Q8.24 provisioning, Q8.40 local arithmetic, offset-scale RMS weights, image grid
pooling and rotary pairing below are autonomous implementation assumptions,
not independently established HuggingFace executable behavior. Pretrained
weights and modeling source are not supplied. No pretrained accuracy, BF16
equivalence, timing, area or physical-signoff claim is made.

## Ownership and interfaces frozen before implementation

The top is `anvil_e2_top`, with the following architectural defaults:

| Parameters | Defaults, in the same order |
|---|---|
| VISION_LAYERS, VISION_HIDDEN, VISION_FFN | 16, 768, 3072 |
| VISION_HEADS, VISION_HEAD_DIM, PATCH_SIZE | 12, 64, 16 |
| POOL_KERNEL, VISION_SOFT_TOKENS | 3, 280 |
| TEXT_LAYERS, TEXT_HIDDEN, PLE_DIM, TEXT_FFN, EMBED_DIM | 24, 512, 512, 2048, 768 |
| VOCAB_SIZE, POSITION_EMBEDDING_SIZE | 262144, 10240 |
| TEXT_Q_HEADS, LOCAL_KV_HEADS, FULL_KV_HEADS | 4, 2, 1 |
| LOCAL_HEAD_DIM, FULL_HEAD_DIM, SLIDING_WINDOW, MAX_SEQ_LEN | 256, 512, 512, 262144 |

All parameters are positive. Layer counts, hidden/PLE/FFN/vector extents are
bounded by 65535; the text Q-head times either head dimension must also fit.
VISION_HIDDEN equals VISION_HEADS*VISION_HEAD_DIM, with vision head dimension
divisible by four. Both text head dimensions are even, and each positive KV
head count divides TEXT_Q_HEADS. EMBED_DIM is at least six, divisible by six and
at most 65535. Flattened patch extent 3*PATCH_SIZE*PATCH_SIZE must fit 65535.
Sequence and patch counts fit unsigned 32-bit counters. MAX_SEQ_LEN additionally
limits the descriptor's sequence length and fetched/generated positions.
Illegal top configurations select a guarded diagnostic branch rather than
elaborating invalid banks or rotary divisions.

Public pins retain their work-order widths: 32-bit numerical memory/embedding
words, 64-bit byte addresses, 32-bit token/grid counts, 16-bit output dimension
and index, 2-bit mode and 4-bit completion error. Mode 0 is text-only, 1 is
vision-only (zero supplied text), 2 is joint (positive supplied text), and 3 is
invalid. Numerical words are signed; IDs, positions and masks are unsigned.

| Direction | Pins | Width per pin |
|---|---|---|
| Input | clk, rst_n, job_valid, mem_req_ready, mem_rsp_valid, mem_rsp_error, emb_ready, done_ready | 1 |
| Input | job_mode | 2 |
| Input | job_tokens, job_patch_rows, job_patch_cols, mem_rsp_rdata | 32 |
| Input | job_output_dim | 16 |
| Input | weights_base, vision_weights_base, image_base, tokens_base, positions_base, mask_base, scratch_base | 64 |
| Output | job_ready, mem_req_valid, mem_req_write, mem_rsp_ready, emb_valid, emb_last, done_valid, busy | 1 |
| Output | mem_req_addr | 64 |
| Output | mem_req_wdata, signed emb_data | 32 |
| Output | emb_index | 16 |
| Output | done_error | 4 |

One descriptor is captured on job_valid && job_ready. Only the registered owner
can issue memory commands. Required stages are patch embedding, reusable vision
encoder layer, spatial pooling/projection, multimodal fusion, text frontend/PLE,
reusable hybrid layer and pooling/normalization. All stage start and completion
channels are held valid/ready; command channels are cmd_valid, cmd_ready,
cmd_write, cmd_addr[63:0], cmd_wdata[31:0]; returned channels are result_valid,
result_ready, result_data[31:0], result_error. Descriptor and arena addresses
remain stable throughout an owned stage. A stage finishes only after its final
memory result has retired. Handoffs use distinct START and WAIT states: START
acceptance registers the new stage's ownership, WAIT accepts held completion,
then a separate START phase presents the next stage. Errors skip all later
stages. No stage emits an embedding before complete normalization.

The memory bridge captures a command, holds its external request until accepted,
waits for the response, then holds its internal result until consumed. Writes
also receive one response. Reset cancels the owner and transaction; the host
must discard canceled responses. Host memory regions must not overlap.
At most one external request is outstanding, and its response cannot retire
on the edge accepting that request. Independent request and response delays
do not change stage ownership.

Each module has its own equally named `rtl/<module>.sv`. The top literally
instantiates `anvil_e2_vision_patch_embed`, `anvil_e2_vision_encoder_layer`,
`anvil_e2_vision_pool_proj`, `anvil_e2_multimodal_fusion`,
`anvil_e2_text_frontend_ple`, `anvil_e2_hybrid_layer` and
`anvil_e2_pool_norm`, alongside the single-outstanding memory bridge.
The vision wrapper, PLE wrapper and output wrapper specialize the shared
hybrid engine; there is one reusable vision-layer instance and one reusable
text-layer instance, sequenced across their configured layer counts.
Stage-local matvec, MAC, norm, nonlinear, attention, rotary and pool helpers
are connected arithmetic operators, not disconnected demonstration blocks.

## Pre-edge / post-edge cycle table

| Edge/phase | Pre-edge inputs and outputs | Accepted event | Post-edge outputs/state |
|---|---|---|---|
| Reset asserted | rst_n=0 | asynchronous reset | All public outputs zero; idle state |
| First clock after release | no job_valid; job_ready=1, busy=0 | none | Idle unchanged |
| J | job_valid=1, job_ready=1 | descriptor | busy=1, ready=0; VALIDATE; no request |
| J+1 valid | VALIDATE | descriptor validation | stage START; no early request |
| J+1 invalid | VALIDATE | descriptor rejection | done_valid=1, error held; no request |
| Internal command C | cmd_valid && cmd_ready | command capture | bridge REQUEST with registered payload |
| R stalled | mem_req_valid=1, ready=0 | none | Request and payload unchanged |
| R accepted | mem_req_valid && mem_req_ready | request | RESPONSE; earliest response acceptance R+1 |
| Response | mem_rsp_valid && mem_rsp_ready | response | bridge RESULT; data cannot affect pre-edge signals |
| Internal result | result_valid && result_ready | result retirement | bridge idle; owning stage advances |
| Stage start | start_valid && start_ready | ownership transfer | stage executing; top WAIT |
| Stage completion | done_valid && done_ready | owner release | next START or error completion |
| Embedding stalled | emb_valid=1, emb_ready=0 | none | data/index/last unchanged |
| Nonfinal embedding | emb_valid && emb_ready | output beat | next registered beat may appear |
| Final embedding | emb_valid && emb_ready && emb_last | final output beat | separate completion phase; no same-edge done handshake |
| D | done_valid && done_ready; job_ready=0 | completion | idle, job_ready=1, busy=0 |
| D+1 | next descriptor valid and ready | new descriptor | VALIDATE, busy=1 |

Reset has priority over every synchronous event. No valid input causes an
autonomous job transition. Whole-model latency is data/geometry dependent.

## Degenerate boundary matrix

| Boundary | Required behavior |
|---|---|
| TEXT_HIDDEN=1, PLE_DIM=1, FFN=1 | Genuine singleton dense/norm operators, no reversed selects |
| VISION_HEAD_DIM=4 | Smallest axial head; row and column each rotate one pair |
| PATCH_SIZE=1, POOL_KERNEL=1, soft tokens=1 | One actual patch/window, not a bypass |
| Non-power-of-two widths and 4x5 patch grid | Explicit terminal comparisons; no power-of-two masking |
| Partial spatial windows | Divide by actual participating patch count |
| One layer | Layer 0 sliding; no invented full layer |
| Layers 5,11,17,23 | Full attention, full dimensions and KV grouping |
| EMBED_DIM=6, output_dim=1 | Normalize the selected one-element prefix; first beat is last |
| Zero tokens text-only | Descriptor error 1 |
| All-zero text masks | Error 4, no embeddings |
| Zero image geometry or pool-count mismatch | Descriptor error 1 before access |
| Invalid head divisibility, zero parameters | Explicit PARAMETER ERROR; guarded legal datapath |
| Final vector/counter element | Consume exactly once, transition rather than wrap |
| Request and response stalls | Hold payload and ownership until accepted |
| Reset idle/request-stalled/response-pending/output-stalled | All outputs zero; canceled work never resumes |
| Address extent overflow | Error 5 before memory; descriptor error 1 takes priority |
| Q40/Q24 signed ties | Nearest-even on both sides of zero, including negative half ties |
| Q40 saturation endpoints | Clamp at (-2147483648)<<16 and 2147483647<<16, not the entire signed-48 range |
| Exact promotion and scratch round trip | q promotes as q<<16; materialize(promote(q))=q; no guard sidecars |
| RMS epsilon | Add 17<<56 to Q80 mean squares, preserving epsilon 17/2^24 |
| Zero L2 denominator | Exact zero for every selected component |
| Maximum guarded reductions | Explicit products and 128-bit accumulators, no implicit narrow shifts |
| Prefix one / final norm output | Materialize the current normalized beat, not a stale buffer element |

## Numerical contract

This numerical amendment replaces the previous Q24 inter-operator rounding
and 96-bit reduction contract. It does not change tensor shapes, scratch
addresses, external words, fixtures, mathematical acceptance or timing rules.
All external numerical inputs, weights, scratch and embeddings remain signed
Q8.24. Words are little-endian, aligned and byte addressed. Integer metadata
never promotes. Weight conversion remains an external nearest-even conversion
with signed-32 saturation. There is no precision sidecar or added transaction.

Let W=2^24, G=2^40 and RN(n,d) denote nearest-even signed division for positive
d: divide abs(n), increment on greater-than-half or a half tie with odd
quotient, then restore the sign. Arithmetic right shifts implement the
equivalent floor-plus-remainder rule, including negative ties.
Local numerical values and arithmetic channels are signed 48-bit Q8.40.
Define C(z)=clamp(z, -140737488355328, 140737488289792).
These limits are exactly the old signed-32 endpoints shifted sixteen places;
the unused upper 65535 signed-48 codes are not additional dynamic range.
Promotion is the exact signed concatenation {q24,16'b0}.
Materialization is signed-32 saturation of RN(q40,2^16), not truncation.

### Operator, rounding, saturation and temporary-width ledger

Every row below describes an operator boundary, not a new memory boundary.
Only the subsequent materialization table discards the sixteen guard bits.

| Operator/site | Exact input/reduction and temporary width | Output boundary |
|---|---|---|
| Patch dense | Signed 48-bit promoted pixel times signed 32-bit Q24 weight gives explicit signed 80-bit Q64 product; sign-extend into signed 128-bit sum | C(RN(sum,W)), Q40 |
| All other dense projections | Promote each Q24 weight to Q40; explicit signed 48x48 -> 96-bit Q80 product, signed 128-bit sum | C(RN(sum,G)), Q40 |
| Dense equivalence | Promoted-weight sum is exactly Q40-activation by Q24-weight sum times 2^16 | RN(sum_promoted,G)=RN(sum_Q64,W), including ties |
| Residual / patch row and column adds | Sign-extend each operand to 128 bits; table weights promote first | C(a+b) at each original addition site |
| Elementwise gate/up and gate/PLE | Signed 48x48 -> 96-bit product, sign-extend to 128 bits | C(RN(a*b,G)) |
| layer_scalar | Provisioned signed-32 scalar promotes exactly, same guarded MAC | C(RN(a*w,W)) |
| PLE scaling | Signed 128-bit numerator a<<40; positive Q40 floor sqrt(H<<80) divisor | C(RN(a*G,root_H)) |
| Fusion embedding scaling | Unchanged signed Q24 input times Q40 root_H in 96 bits | Signed-32 saturation of RN(product,G), directly Q24 at X0 write |
| RMS square reduction | Explicit signed 48x48 -> nonnegative 96-bit square; zero-extend into 128-bit sum | D=RN(sum,count)+(17<<56), unsigned 128-bit Q80 |
| L2 square reduction | Same exact square/sum, selected prefix only | D=sum, no epsilon |
| RMS/L2 root | 192-bit D<<64; 194-bit restoring remainder/trial, 96-bit root, 96 iterations | R=floor(sqrt(D<<64)), no rounding |
| Norm ratio | Signed 128-bit a<<72, magnitude/division/remainder and ratio t | t=RN(a<<72,R), no premature saturation |
| RMS weight | Signed Q24 w; 128-bit (W+w), product t*(W+w) | C(RN(t*(W+w),W)), Q40 |
| L2 output | Same ratio (multiplication by W followed by /W is exact) | C(t), Q40; zero if R=0 |
| Nonlinear series multiply | Retained signed 96-bit Q40 terms, explicit 192-bit product | RN(product,G) into 96-bit series temporary |
| Nonlinear divide | Signed 96-bit magnitude/quotient/remainder | RN(n,d), restored sign, no Q24 conversion |
| GELU / exp / sin / cos result | Retained Q40 series/constants/iteration counts | C(result), Q40 |
| RoPE angle | Retained 96-bit Q40 frequency times unsigned position, modulo TWO_PI | Q40 angle, no Q24 rounding |
| RoPE rotated pair | Two explicit 48x48 products in 128-bit signed Q80 sum per component | C(RN(a*cos-b*sin,G)), C(RN(a*sin+b*cos,G)) |
| Attention score | Promoted materialized Q/K, exact 128-bit Q80 dot; Q40 floor sqrt(d<<80) divisor | C(RN(dot,root_d)), Q40 before maximum selection |
| Attention difference | Sign-extend score and maximum to 128 bits before subtraction | Strictly below -16*G: zero weight; otherwise Q40 exp |
| Attention weight/value | Q40 exp weight times promoted scratch V, explicit 96-bit product; signed 128-bit weighted sum and exponent sum | C(RN(weighted_sum,exponent_sum)), Q40; empty denominator gives zero |
| Spatial mean | Promote scratch patch words, signed 128-bit sum over actual window participants | C(RN(sum,actual_count)), Q40, then dense bridge |
| Sentence mean | Signed 128-bit sum of masked Q40 projected vectors | C(RN(sum,actual_unmasked_count)), Q40 |
| Output prefix / L2 | Select prefix of Q40 mean, then Q40 L2 | Materialize only normalized results into signed-32 output buffer |

Every dense patch, vision Q/K/V/O, vision MLP, bridge, frontend PLE, text
Q/K/V/O, text MLP, PLE injection projection and final embedding projection
uses the dense rule above. Provisioned norm weights and scalar registers stay
Q24. Local five-bank engine vectors, matvec inputs/results, norm values/results,
attention queries/scores/weights/values, rotary operands/results and spatial/
sentence means are Q40. Pool's final normalized buffer alone is Q24.

Legal 16-bit vector extents require at most 110 significant magnitude bits
for Q80 square/dot reductions (products bounded by 2^94, at most 65535 terms).
Even an unrestricted 32-bit participant count would require fewer than 127
magnitude bits for bounded Q40 products. Attention weights are at most G:
weighted-value reductions need fewer than 120 bits for a 32-bit token count;
exponent sums need at most 72. Pooled vector sums need at most 79.
The norm numerator needs at most 120 signed bits; its unsaturated ratio and
Q24 weight multiplication fit 128 bits. Radicands occupy 192 bits without
discarding any accumulator bits. No width estimate establishes execution
budget compliance: wider division and 96 root cycles need actual bounded
Verifier execution.

### Mandatory materialization ledger

| Tensor/output | Q40 computation before boundary | Published boundary / later consumption |
|---|---|---|
| Patch V0 | Dense, row addition, column addition each clamp in Q40 | One Q24 word per existing V0 address |
| Vision/text Q and K | Projection, per-head RMS and RoPE in Q40 | Q24 at existing Q/K writes; attention promotes memory reads |
| Vision/text V | Dense projection in Q40 | Q24 at existing V writes; attention promotes memory reads |
| Vision layer result | Attention/MLP norms and residuals in Q40 | Q24 V0/V1 write; next layer promotes its scratch read |
| Bridge soft tokens | Actual-participant Q40 spatial mean then dense bridge | Q24 soft write; fusion consumes that published word |
| Fusion X0 | Direct Q24 embedding scaling or unchanged Q24 soft word | Existing Q24 X0 write, no double rounding |
| Cached PLE | Dense, dimension scaling and RMS in Q40 | Q24 PLE write; injection promotes its cache read |
| Text layer result | All attention/MLP/PLE residuals and layer_scalar in Q40 | Q24 X0/X1 write; subsequent consumers promote memory reads |
| Final embeddings | Language norm, projection, masked mean, prefix and L2 stay Q40 | Q24 normalized-buffer capture, before any embedding beat |
| IDs / positions / masks | Integer-only processing | Existing unsigned words, bit-for-bit unchanged |

This list is exhaustive. No local unrounded value bypasses a published tensor:
the layer sequencer reloads X at each token/layer, attention reads Q/K/V from
scratch, and PLE injection reads the cache. Local bank values not crossing a
listed boundary keep their guard bits; no additional arena words or traffic
are introduced.

Nonlinear arithmetic retains Gen-1 Q40 constants:
ONE=1099511627776, LN2=762123384786, PI=3454217652358,
TWO_PI=6908435304715, GELU_C=877283352226,
GELU_K=49164662436. Q40 products round nearest-even after shift 40.
Signed division rounds magnitude nearest-even and restores sign.
Exp reduces using floor(x/LN2), evaluates terms 1..18 with Q40 rounded
multiplication and division, then shifts by the binary exponent. Its argument
is clamped below -16. GELU implements x/2*(1+tanh(C*(x+K*x^3))),
returns x at x>=8 and zero at x<=-8, and computes tanh through exp(-2*abs(z)).
Sin/cos reduce modulo TWO_PI into [-PI,PI], use terms 1..18, then clamp to C
without Q24 conversion. GELU likewise accepts and returns Q40, retaining its
branches at +/-8*G. Exp's final binary exponent right shift retains its existing
arithmetic-shift rule, rather than adding a new rounding site.

RoPE frequencies use exp(-2*i*ln(theta)/dimension), the same 18-term Q40
series, floor argument reduction and Q40 angle reduction before Q40 trig.
Text theta is 10000 or 1000000. Vision theta is 100, with independent row
and column half-head rotations and split-half pairs inside each axis.
Q40 log constants are LN_LOCAL=10126876334763, LN_FULL=15190314502144 and
LN_VISION=5063438167381.
Dimension roots are floor(sqrt(dimension << 80)); embedding scaling multiplies
by that Q40 root and PLE scaling divides by it.
Auxiliary nonlinear RECIP uses C(RN(2^80,a)); RSQRT forms a 128-bit a<<56
radicand, uses 64 restoring iterations and returns C(RN(2^88,root)).
Zero reciprocal / nonpositive reciprocal-root operands report helper error.
These helpers are not substituted for the dedicated RMS/L2 datapath.
These integer approximations require independent mathematical accuracy checks;
no such checks have yet been run by Designer.

## Integration and pending verification

Compile only rtl/*.sv; reference RTL is not an implementation dependency.
Designer may run only `iverilog -g2012 -Wall -t null -s anvil_e2_top rtl/*.sv`.
Verifier owns tests/*.py, functional/reference/mutation checks and actual Yosys
synthesis. Preparation diagnostics are advisory and never acceptance.
The accepted advisory parameter lesson exp-6d5cc92e6f5a86894eaae275 informs
the guarded invalid-parameter branch. Reset and stall lessons
exp-27d8629432f1196d886cbd13 and exp-b7f85aea8b668c87905c6e46 inform
independent stimulus, not a Designer verification claim.

## Memory arena and strides

Let P=rows*cols and S=VISION_SOFT_TOKENS for image jobs, otherwise P=S=0.
N=text_tokens for text-only, otherwise S+2+text_tokens. Let H=TEXT_HIDDEN,
V=VISION_HIDDEN, L=TEXT_LAYERS, E=PLE_DIM,
D=max(LOCAL_HEAD_DIM,FULL_HEAD_DIM), K=max(LOCAL_KV_HEADS,FULL_KV_HEADS),
Q=TEXT_Q_HEADS, A=VISION_HEADS*VISION_HEAD_DIM.
All offsets below are **words**, relative to scratch_base; multiply by four
for byte addresses. Allocation follows the specified order with no reuse.

| Region | Offset | Words | Token/vector stride |
|---|---|---|---|
| V0 | 0 | P*V | V |
| V1 | P*V | P*V | V |
| vision Q | 2*P*V | P*A | A |
| vision K | 2*P*V+P*A | P*A | A |
| vision V | 2*P*V+2*P*A | P*A | A |
| soft | 2*P*V+3*P*A | S*H | H |
| fused IDs | soft offset+S*H | N | 1 |
| fused positions | IDs offset+N | N | 1 |
| fused masks | positions offset+N | N | 1 |
| X0 | masks offset+N | N*H | H |
| X1 | X0 offset+N*H | N*H | H |
| PLE | X1 offset+N*H | N*L*E | L*E; layer stride E |
| text Q | PLE offset+N*L*E | N*Q*D | Q*D |
| text K | Q offset+N*Q*D | N*K*D | K*D |
| text V | K offset+N*K*D | N*K*D | K*D |

Total bytes are four times (text V offset+N*K*D).
For a particular layer with head dimension d, active head h starts at h*d
inside the fixed token stride; unused padding is neither read nor initialized.
128-bit arithmetic validates all active memory extents before issuing requests.
Model-sized arrays are external; only bounded vectors, norm operands and
embedding accumulators live inside the RTL.

## Weight mapping

Tensors are row-major tightly concatenated Q24 words, without padding.
For any tensor with R rows and C columns, its element (r,c) is
base+4*(tensor_word_offset+r*C+c).
Text ordering is preserved from the supplied Gen-1 address generator.
In the table H=TEXT_HIDDEN, E=PLE_DIM, F=TEXT_FFN, B=EMBED_DIM;
d and k are selected by zero-based layer%6==5 (full) versus sliding.

| ID | language_model suffix | Shape |
|---|---|---|
| 0 | embed_tokens.weight | VOCAB_SIZE,H |
| 1 | embedding_projection.weight | B,H |
| 2 | norm.weight | H |
| 3 | ple.per_layer_model_projection.weight | L*E,H |
| 4 | ple.per_layer_projection_norm.weight | E |
| 5 | layers.i.input_layernorm.weight | H |
| 6 | layers.i.layer_scalar | 1 |
| 7 | layers.i.mlp.down_proj.weight | H,F |
| 8 | layers.i.mlp.gate_proj.weight | F,H |
| 9 | layers.i.mlp.up_proj.weight | F,H |
| 10 | layers.i.ple_block.per_layer_input_gate.weight | E,H |
| 11 | layers.i.ple_block.per_layer_projection.weight | H,E |
| 12 | layers.i.ple_block.post_per_layer_input_norm.weight | H |
| 13 | layers.i.post_attention_layernorm.weight | H |
| 14 | layers.i.post_feedforward_layernorm.weight | H |
| 15 | layers.i.pre_feedforward_layernorm.weight | H |
| 16 | layers.i.self_attn.k_norm.weight | d |
| 17 | layers.i.self_attn.k_proj.weight | k*d,H |
| 18 | layers.i.self_attn.o_proj.weight | H,Q*d |
| 19 | layers.i.self_attn.q_norm.weight | d |
| 20 | layers.i.self_attn.q_proj.weight | Q*d,H |
| 21 | layers.i.self_attn.v_proj.weight | k*d,H |

Globals 0..4 precede all ascending layers, each containing 5..21.
The global word extent is VOCAB_SIZE*H+B*H+H+L*E*H+E.
Let Tlocal/Tfull be the sums of rows*columns of IDs 5..21 under their
respective d,k. Layer i starts at globals+(i-floor(i/6))*Tlocal+
floor(i/6)*Tfull. Tensor offsets within a layer are the preceding shape products.
The total is globals+(L-floor(L/6))*Tlocal+floor(L/6)*Tfull.

Vision ordering begins with
vision_tower.patch_embedder.input_proj.weight [V,3*PATCH_SIZE*PATCH_SIZE],
then position_embedding_table [2,POSITION_EMBEDDING_SIZE,V].
Each ascending vision_tower.encoder.layers.i contains, in order:
input_layernorm [V], self_attn.q_proj.linear.weight [V,V],
k_proj.linear.weight [V,V], v_proj.linear.weight [V,V],
o_proj.linear.weight [V,V], q_norm.weight [VISION_HEAD_DIM],
k_norm.weight [VISION_HEAD_DIM], post_attention_layernorm [V],
pre_feedforward_layernorm [V], mlp.gate_proj.linear.weight [VISION_FFN,V],
up_proj.linear.weight [VISION_FFN,V], down_proj.linear.weight [V,VISION_FFN],
post_feedforward_layernorm [V]. All norm names end in .weight.
The layer extent is 4*V+4*V*V+2*VISION_HEAD_DIM+3*V*VISION_FFN.
Finally embed_vision.embedding_projection.weight [H,V] follows all layers.
Tensor word offsets are prefix sums of these shape products.
The supplied manifest uses .linear.weight for encoder linears, while
patch input_proj.weight does not use that suffix.
The objective's descriptive clipping-scalar list differs from actual inputs:
use_clipped_linears=false and no scalar entries exist in the manifest, so the
implementation does not invent or fetch clipping operands.

## Image, fusion and operator ordering

Supply one already numerically preprocessed signed-Q24 RGB CHW image:
height=rows*PATCH_SIZE, width=cols*PATCH_SIZE. No extra standardization occurs.
Patch element c*PATCH_SIZE^2+dy*PATCH_SIZE+dx addresses
c*height*width+(patch_row*PATCH_SIZE+dy)*width+patch_col*PATCH_SIZE+dx.
Dense input projection is followed by saturated row-factor addition and
saturated column-factor addition. The row table starts at position-table word
zero and the column table at POSITION_EMBEDDING_SIZE*V.

Each vision layer performs input RMS; Q/K/V dense projection; per-head Q/K RMS;
axial RoPE; bidirectional unmasked softmax; O projection; post-attention RMS and
residual; pre-FF RMS; GELU(gate)*up; down projection; post-FF RMS and residual.
Nonoverlapping POOL_KERNEL windows are traversed row-major and partial windows
use their actual sample count. The grid's ceiling-divided window count must
equal S (42x60 at defaults gives 280). The pooled vector is densely projected
from V to H with genuine bridge weights.

Fusion writes IDs, positions, masks and initial hidden vectors. Image jobs
contain boi=255999, S slots tagged 258880, eoi=258882, then supplied text.
Only image-slot vectors come from soft memory; they never look up ID258880.
Frame and text embeddings multiply by sqrt(H); image vectors do not.
Generated positions are 0..S+1 with mask one; supplied positions add S+2.
Text-only positions and masks are preserved. IDs must be below VOCAB_SIZE,
masks exactly zero/one, and shifted positions below MAX_SEQ_LEN.

PLE is precomputed from the initial fused X0 for every token and layer:
dense per-layer slice, divide by sqrt(H), offset-scale RMS, external PLE write.
The shared layer engine reads its five vector banks through explicit
combinational muxes sensitive to bank contents as well as bank/index selection.
An accepted vector load writes the bank on that edge; the updated operand is
visible post-edge even when the selected bank and index remain unchanged.
After the last load response, DISPATCH sets up MAT_START; its start handshake
advances to MAT_LOAD, where each input is accepted before MAT_RUN. Norm follows
NORM_START, weight request/response, NORM_FEED, then NORM_OUT; in-place bank
writes occur only as normalized outputs retire, after all inputs were captured.
These transitions also apply to singleton vectors and first-element reads.

### Stage-specialized inference

The shared engine's STAGE is an elaboration parameter, not a runtime bypass:
0 executes only frontend PLE, 1 executes one complete vision/text layer, and
2 executes final language norm, embedding projection and masked pooling/L2.
The top still instantiates every required stage and iterates the layer engines
over the configured layer counts. Each specialization retains dense matvec,
MAC and normalization. Attention, RoPE and GELU units are generated only for
STAGE=1; the masked pool unit is generated only for STAGE=2. The vision layer
uses the vision tensor address generator rather than also elaborating an unused
text generator. Its PLE-only instruction branches are removed at elaboration.

Internal vector depth is max(H,E) for frontend PLE, max(H,B) for output pooling,
and max(H,E,F,Q*D) for text layers (vision uses max(V,VISION_FFN,
VISION_HEADS*VISION_HEAD_DIM)). Frontend uses only X and temporary banks;
output pooling additionally uses work; layer engines use all five banks.
Unused banks have neither active read operands nor write enables. External
scratch offsets, active tensor shapes, arithmetic boundaries and all public
ports remain unchanged. Inactive specializations drive unused helper results
to zero; no active operator substitutes such a value for a computed result.

Launch templates expand to assignments to the existing operation registers,
without automatic-task argument storage. At a DISPATCH edge the address,
count, bank selections, offsets and return PC are captured together, and the
post-edge state becomes READ_REQ, WRITE_REQ, MAT_START, NORM_START or VECTOR.
Arguments are evaluated from the same pre-edge registers as before. The next
edge performs the existing operator handshake; no operator starts earlier.
Unused embedding-lookup instructions and the unreachable legacy BASES state
are removed: fusion owns embedding lookup and the top supplies all six arena
bases on the stage-start handshake.

This inference repair follows the retained Yosys PROC-decoder timeout in
`evidence/preparation/synthesis-a-004/receipt.json`; the preceding direct
hierarchy assertion is retained in
`evidence/preparation/synthesis-a-003/receipt.json`. It does not establish a
synthesis speedup or netlist acceptance. Verifier must rerun bounded A/C
synthesis with all passes and structural assertions intact. The unresolved
integer/floating discrepancy in
`evidence/preparation/numerical-localization-001/receipt.json` is unchanged;
that control/inference repair changed no numerical approximation or tolerance.
The present Q40 amendment separately changes the numerical boundaries listed
above. The retained B/seed89 failure is
`evidence/preparation/b89-text-numerical-001/receipt.json`: mathematical maximum
component error 0.0023715018597183155 exceeded 0.002 despite integer agreement.
`evidence/preparation/b89-paired-traces-002/receipt.json` retains agreement on
12 outputs and 153 scratch addresses, while
`evidence/preparation/b89-matched-norm-002/receipt.json` distinguishes approximately
4.70e-8 local norm error from 0.003288 propagated input error.
These are old-contract diagnostics, not a repaired-design acceptance result.
The amendment's adequacy remains unproven until the unchanged floating oracle,
fixtures (including B/seed89), both 0.002 thresholds, mutations and bounded
generic synthesis checks pass independently.

Every text layer performs input RMS; Q/K/V projections and Q/K head RMS;
split-half RoPE; grouped softmax attention; O projection and post-attention RMS
plus residual; pre-FF RMS; GELU(gate)*up; down projection and post-FF RMS plus
residual; GELU(PLE input gate(hidden))*cached PLE; PLE projection and RMS plus
residual; layer_scalar multiplication. Contiguous Q-head groups share KV heads.
Local keys require mask one and abs(position difference)<SLIDING_WINDOW;
full keys require only mask one. Queries are not removed by their own mask.
Final language norm and embedding projection run per token, then masked mean,
selected prefix truncation and L2. Prompt/frame/image masks participate, matching
include_prompt=true. The selected dimensions are B,2*B/3,B/3,B/6.

## Errors and provisioning

done_error: 0 success, 1 descriptor/mode/dimension/geometry/alignment,
2 input ID/position/mask, 3 memory response, 4 no unmasked tokens,
5 extent overflow, 6 internal arithmetic/protocol.
Descriptor error 1 precedes extent error 5. Later errors are first detected.
Each accepted memory transaction retires before abort completion. No error
emits embeddings; all output vectors are buffered through full normalization.
Hold descriptors under job backpressure and done_ready/emb_ready according to
the public handshake contract. The environment must retain active input and
weight regions, provide responses to writes, and never alias them with scratch.
Bring reset low, discard canceled transactions, release reset, then present
the descriptor when ready. All tools and tests are external integration
dependencies; no software installation is part of delivery.
