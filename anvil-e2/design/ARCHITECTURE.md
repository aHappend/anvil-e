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
Norm, attention and nonlinear each instantiate one `anvil_e2_divide` helper,
reusing it across their guarded divisions without changing any stage memory
interface.
Seven `anvil_e2_clock_gate` instances isolate inactive stage clocks. The top
controller and single-outstanding bridge retain the ungated input clock.
Only the selected stage in START/WAIT requests clock enable; during WAIT it
may sleep while the bridge owns a pending request/response, as specified in
the bridge-wait isolation table below. start_valid is
additionally qualified by the registered enable, so a disabled stage cannot
accept ownership before its first real clock edge.
Inside each hybrid engine, the matvec and norm helpers also have registered
clock ownership. The layer specialization additionally gates attention, rotary
and nonlinear helpers. These gates use the same high-while-disabled primitive,
direct asynchronous reset and active-qualified input handshake as the stage
gates. The MAC remains on the engine clock because memory-result acceptance
can enable it on that very edge.
The combinational `anvil_e2_series` helper supplies four exact recurrence steps
to the nonlinear and rotary controllers; only their existing SERIES edge
captures its outputs. It adds no storage or handshake channel.

## Pre-edge / post-edge cycle table

| Edge/phase | Pre-edge inputs and outputs | Accepted event | Post-edge outputs/state |
|---|---|---|---|
| Reset asserted | rst_n=0 | asynchronous reset | All public outputs zero; idle state |
| First clock after release | no job_valid; job_ready=1, busy=0 | none | Idle unchanged |
| J | job_valid=1, job_ready=1 | descriptor | busy=1, ready=0; VALIDATE; no request |
| J+1 valid | VALIDATE | descriptor validation | stage START; no early request |
| J+1 invalid | VALIDATE | descriptor rejection | done_valid=1, error held; no request |
| Stage clock wake | START with selected registered clock enable zero | no stage start handshake | Enable registers one; remain START; stage clock stays high until next input falling edge |
| Internal command C | cmd_valid && cmd_ready | command capture | bridge REQUEST with registered payload |
| R stalled | mem_req_valid=1, ready=0 | none | Request and payload unchanged |
| R accepted | mem_req_valid && mem_req_ready | request | RESPONSE; earliest response acceptance R+1 |
| Response | mem_rsp_valid && mem_rsp_ready | response | bridge RESULT; data cannot affect pre-edge signals |
| Bridge wait sleep | WAIT; bridge neither idle nor holding a result; no response handshake | Clock-enable may clear | Stage and nested helpers hold; bridge remains clocked |
| Bridge response wake | mem_rsp_valid && mem_rsp_ready; selected stage inactive | Response capture and clock-enable capture, not stage result consumption | Bridge RESULT and stage active; next input falling edge enables the following stage rising edge |
| Internal result | result_valid && result_ready | result retirement | bridge idle; owning stage advances |
| Stage start | start_valid && start_ready | ownership transfer | stage executing; top WAIT |
| Helper wake | Local START/request with helper active=0 | no helper input handshake | Enable registers one; controller retains START/request |
| Helper start | Local START/request, active=1 and helper ready | helper input/ownership acceptance | Original LOAD/run/wait phase; operands captured only on this edge |
| Helper retirement | Held helper output/completion accepted | release helper ownership | Helper IDLE; controller advances; gate may sleep on a later edge |
| Stage completion | done_valid && done_ready | owner release | next START or error completion |
| Embedding stalled | emb_valid=1, emb_ready=0 | none | data/index/last unchanged |
| Nonfinal embedding | emb_valid && emb_ready | output beat | next registered beat may appear |
| Final embedding | emb_valid && emb_ready && emb_last | final output beat | separate completion phase; no same-edge done handshake |
| D | done_valid && done_ready; job_ready=0 | completion | idle, job_ready=1, busy=0 |
| D+1 | next descriptor valid and ready | new descriptor | VALIDATE, busy=1 |

Reset has priority over every synchronous event. No valid input causes an
autonomous job transition. Whole-model latency is data/geometry dependent.
The first START edge for a newly selected stage wakes its clock; a subsequent
START edge accepts ownership. This extra registered wake edge does not merge
validation, stage handoff or memory bridge phases.

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
| Guarded division | Exact signed magnitude division, nearest-even for either sign; zero divisor or signed quotient overflow reports helper error |
| Divider quotient-digit boundaries | Exact 16-bit digits grouped up to four per RUN edge; divisor lengths 48/49/128, normalized 64-bit numerator, a 17-bit estimate of 65536, and one-step overestimate correction; full 128-bit residue retained; no digit after count eight |
| Two-pass attention | First pass finds the maximum; second accumulates both exact reductions in ascending key order; empty eligibility never issues a zero-denominator divide |
| Attention final response | Successful K response clocks the dot MAC before SCORE; successful V response adds the exact shared product directly to the weighted component and enters VREQ or NEXTKEY; stalled/error responses never accumulate |
| Attention address cursors | Capture query/head origins at start; successful nonfinal Q/K/V responses advance their component cursor by four; NEXTKEY advances fixed-stride K/V origins and metadata even for skipped keys, or rewinds all key cursors at the final key; no new FSM edge |
| Series group/final term | Four ordered terms per clock; evaluate term 18 once, never term 19; exact-zero tails contribute zero |
| Repeated rotary angle | Reuse only a complete successful sine/cosine pair matching all 48 angle bits in either of two scalar entries; reset invalidates both entries |
| Singleton matvec row | First successful weight response clears and accumulates; separate PREPARE captures the updated MAC before held output |
| Matvec weight cursor | Capture base at accepted start; advance four bytes only on each successful weight-result retirement, including row-final and matrix-final elements; stalls/errors never advance |
| Nonlinear non-series division | RECIP, RSQRT and GELU ratio use full signed-128 numerator/unsigned-128 divisor channels; no narrowed ratio or premature saturation |
| Rotary angle product width transition | Use unsigned 64-bit modulus only when the entire product fits; otherwise preserve the signed 96-bit modulus |
| Series bounded division | Divisors 1..18 and the actual sine/cosine quadratic divisors through term 18; exact unsigned-64 quotient, reconstructed residue and signed ties; reachable numerators strictly below 64*G |
| Bit-length search | Zero returns zero; every 2^k boundary through k=127 returns the exact length; no change to divider/root grouping |
| Exact zero nonlinear / rotary pair zero | Results appear only after input acceptance; held output/reset behavior unchanged; pair-zero frequency still passes through registered ANGLE |
| Nonlinear multiply width | Every reachable argument is signed-64 representable; the exact signed 128-bit product retains the original low-40-bit tie test and signed-96 result |
| Rotary two-entry replacement | A hit in either entry performs no fill; a successful miss pushes the newest entry into the previous entry; a failed response never changes either entry |
| Divider edge-local work | RUN computes one digit from pre-edge operands once; ROUND computes nearest-even from the final registered quotient/residue, never from a partly updated digit |
| MAC clear/accumulate | Accumulate samples both operands on that edge; clear selects replacement rather than addition; clear alone zeros the sum; neither holds the sum |
| MAC exact product tap | Combinational signed 48x48 -> 96-bit product, zero unless reset is released and accumulate is asserted; attention captures its signed-128 extension only on successful V-result retirement, never the stale registered sum |
| Operand isolation | Bank operands are selected throughout their consuming state, including stalls; registered helpers capture only on their existing valid/ready edge |
| Norm root remainder width | All 96 restoring steps remain exact with a 98-bit shifted remainder/trial and a 96-bit root, including the largest 192-bit radicand |
| Trig series divisor width | Terms 1..18 use exact unsigned 12-bit divisors: sine max 1332, cosine max 1260; zero-extend to unsigned 64 bits for magnitude division |
| Stage clock wake / sleep | Gate enable changes only on input rising edges; disabled clock is high; no start_valid until registered active; completed owner retires before its clock sleeps |
| Reset with stopped stage clock | Asynchronous rst_n reaches every stage/helper directly; high inactive clock is not a substitute for reset; every later job reloads consumed banks |
| Reset with stopped local helper clock | The same asynchronous reset and FLUSH cancellation reach every gated helper and its divider; no canceled HOLD/result can survive into another operation |
| Bridge-wait clock isolation | Wake on actual response acceptance, not request acceptance; both sides of command/result handshakes require active; minimum-latency response and arbitrary stalls preserve single consumption |
| Combinational series boundary | Input registers remain Q40; bounded signed-64 recurrence and total are sign-extended on the existing SERIES edge; term 18, zero tail and each signed tie are unchanged |

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
| RMS/L2 root | 192-bit D<<64; 98-bit restoring remainder/trial, 96-bit root; 96 radix-4 digit steps, with leading-zero steps omitted and eight remaining steps per clock | R=floor(sqrt(D<<64)), no rounding |
| Norm ratio | Signed 128-bit a<<72, magnitude/division/remainder and ratio t | t=RN(a<<72,R), no premature saturation |
| Shared divider digit | Unsigned 128-bit operands/residue/quotient; 144-bit trial, 64-bit normalized estimate operands, 17-bit candidate digit and explicit 145-bit candidate product; up to four ordered digits per RUN edge | Exact quotient/residue before the separate unchanged signed nearest-even ROUND edge |
| RMS weight | Signed Q24 w; 128-bit (W+w), product t*(W+w) | C(RN(t*(W+w),W)), Q40 |
| L2 output | Same ratio (multiplication by W followed by /W is exact) | C(t), Q40; zero if R=0 |
| Nonlinear/rotary series multiply | Bounded signed-64 Q40 operands, explicit signed 64x64 -> 128-bit exact product (bound proved below) | RN(product,G) into signed-64 recurrence; sign-extend at controller register capture; same low-40-bit tie test |
| Nonlinear/rotary series divide | Reachable signed-64 numerator has magnitude below 64*G; exact unsigned-64 magnitude/divisor/quotient/residue; q=floor(m/d), r=m-q*d | RN(n,d), signed-64 recurrence, sign-extend into controller registers; no Q24 conversion |
| Nonlinear RECIP / RSQRT / GELU ratio | Signed-128 numerator, unsigned-128 positive divisor through the shared registered divider; successful quotient fits signed 96 bits before existing saturation/GELU use | Identical RN(n,d), no intermediate saturation of the GELU ratio |
| Rotary frequency division | Initial logarithmic ratio retains the full signed-96 direct/two-limb/fallback calculation; frequency-series division uses exact bounded unsigned-64 quotient and reconstructed residue | Same original nearest-even result and sign |
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
budget compliance: wider division and grouped root arithmetic need actual bounded
Verifier execution.

### Bounded guarded divider and registered arithmetic ownership

RMS mean-square division, RMS/L2 ratio division, attention score scaling and
attention weighted-value division use `anvil_e2_divide`, rather than native
128-bit `/` and `%`. Each instance accepts a signed 128-bit numerator and an
unsigned positive 128-bit denominator. Legal callers have positive signed-range
denominators and numerator magnitudes below 2^127; norm square sums fit 110
significant magnitude bits. No numerator, divisor or quotient is narrowed.

The helper captures the sign and unsigned magnitude on input acceptance.
It preserves the exact quotient and remainder while avoiding restoring work
whose quotient bits are known to be zero. For a power-of-two divisor 2^s,
it captures quotient `magnitude>>s` and residue `magnitude&(divisor-1)`,
then enters ROUND directly. This includes divisor one and divisor 2^127;
signed overflow is still detected after rounding. For a non-power-of-two
divisor larger than the magnitude, it captures quotient zero and residue
equal to the magnitude, then enters ROUND; a nonzero rounded quotient is
still possible and uses the same tie rule.

Otherwise let `b=bit_length(magnitude)-bit_length(divisor)+1` and
`g=ceil(b/16)`, with `1<=g<=8`. Initialize quotient zero, residue
`magnitude>>(16*g)` and dividend `magnitude<<(128-16*g)`, all unsigned 128-bit.
The omitted high prefix is strictly less than the divisor: it has at most
`bit_length(divisor)-1` significant bits. Therefore its omitted quotient bits
are exactly zero, and it is the exact residue obtained by processing that
prefix. Consume the remaining `16*g` bits MSB first, up to four exact
base-65536 quotient digits per clock. A shift by 128 yields zero, so `g=8` covers the
full-width case without a reversed select or a narrowed operand.

For divisor D, capture `s=max(bit_length(D)-48,0)` and `d=D>>s`.
Each digit forms the unsigned 144-bit `T=residue*65536+next_16_bits`,
then computes the candidate `qhat=floor((T>>s)/d)` using explicitly unsigned
64-bit operands. For s=0 this is already the exact digit: D fits 48 bits,
residue<D, and T fits 64 bits. For s>0, `2^47<=d<2^48` and
`T<D*65536`, so `T>>s<2^64`; the selected 64-bit numerator is lossless.
The exact digit q is below 65536. Since T>=q*D, qhat>=q.
Also `T<(q+1)*D` and `D<(d+1)*2^s` imply
`qhat<(q+1)*(1+1/d)<q+2`; thus qhat is at most q+1.
The candidate can be 65536 and is retained in 17 bits, not prematurely
truncated to a digit. Form `P=qhat*D` explicitly in 145 unsigned bits.
If P>T, subtract D from P and decrement qhat once. This yields the exact
digit and residue T-P, with `0<=T-P<D`. Append the corrected low 16 digit
bits to the 128-bit quotient, retain the exact 128-bit residue, and shift
the dividend by 16. Only exact prefix bits are skipped; no reciprocal
approximation, floating arithmetic or precision reduction is used.

Each RUN edge initializes private working dividend, quotient, residue and digit
count from the pre-edge registers, then executes four ordered digit steps,
guarding each step with count<8. Each step consumes the working values from its
predecessor, including that predecessor's correction; no step uses a stale
registered residue. Count starts at 8-g. After ceil(g/4) RUN clocks, quotient
and residue are the exact unsigned division result. Partial final groups never
consume an extra digit. Only the final working values are registered.
A separate rounding clock increments the 129-bit
extended quotient exactly when `residue > divisor-residue`, or on equality
with an odd quotient, then restores the sign. This comparison avoids overflow
from doubling a 128-bit residue. The divider does not saturate: zero divisor
or a rounded result outside signed-128 range produces held `out_error`.
Owning stages apply the unchanged Q40 saturation only at the ledger's sites.
Zero L2 roots and empty attention denominators retain their explicit exact-zero
owner paths and do not issue an invalid divide.

| Helper edge | Pre-edge condition / accepted event | Post-edge state |
|---|---|---|
| Reset | rst_n=0, asynchronously | IDLE; ready, valid, data and error outputs zero |
| I | in_valid && in_ready | Capture operands/prefix; RUN for ceil(g/4) clocks, directly ROUND for exact shortcut, or held error for zero divisor |
| I+1 through I+ceil(g/4) | RUN, only for non-shortcut division | Up to four exact ordered 16-bit digits, each with at most one correction; final edge registers all digits and enters ROUND |
| I+ceil(g/4)+1, or I+1 for shortcut | ROUND | Register signed nearest-even result/error; HOLD and out_valid |
| Held result | out_valid && !out_ready | Result/error unchanged; no new input accepted |
| H | out_valid && out_ready | IDLE post-edge; no same-edge input acceptance |
| H+1 | Next in_valid && in_ready | Next operation may start |

Norm follows LOAD -> SETUP -> MEAN_WAIT -> ROOT_SETUP -> grouped ROOT
execution for RMS; L2 skips MEAN_WAIT. Each nonzero-root component follows
PREPARE (divider start) -> RATIO_WAIT (registered result acceptance) -> APPLY
(norm weight and original Q24 weight rounding) -> held output. Zero-root
components go directly from PREPARE to held zero. The next component cannot
start until the previous output retires.
Attention follows successful KRSP (dot MAC acceptance) -> SCORE (divider start)
-> SCORE_WAIT (result acceptance and original score/max processing).
After both key passes, each component
follows FINISH (divider start) -> FINISH_WAIT (result acceptance and capture).
The empty-denominator path uses FINISH_WAIT without a divider request.
Only after all component captures does OUTPUT present its registered first
beat. Helper errors propagate through the existing arithmetic-error channels.
Reset cancels helper work along with its owning stage.

### Exact grouped-root and divider execution-cost repair

The continuing C/seed17/joint timeout is retained at
`evidence/preparation/q40-short-divider-c-joint-001/receipt.json`.
The public-pin observation at
`evidence/preparation/q40-short-divider-c-progress-001/receipt.json`
reaches 300,000 cycles and matches 1,382 scratch-write history entries, but
does not complete the fixture. It establishes progress, not a deadlock,
numerical mismatch or successful bounded execution. The following changes
target arithmetic clock count without changing any operator equation.

For the norm root, let `D` be the exact unsigned 128-bit denominator square.
If D is zero, ROOT_SETUP sets the root and residue to zero and enters
PREPARE directly. Otherwise define `g=ceil((bit_length(D)+64)/16)`,
with `1<=g<=12`. ROOT_SETUP initializes the 192-bit radicand to
`(D<<64)<<(192-16*g)` and the 96-bit root and 98-bit residue to zero.
The omitted `192-16*g` high radicand bits are all zero; processing those
radix-4 digits would leave both root and residue zero. Each ROOT edge
processes eight consecutive two-bit digits in the original MSB-first order:
form `shifted=4*residue+next_digit`, compare with `trial=4*root+1`,
subtract trial and append root bit one when eligible, otherwise append zero.
The original 194-bit residue was subsequently reduced losslessly to 98 bits
as proved in the operand-isolation repair below. After g ROOT clocks the registered root
is exactly `floor(sqrt(D<<64))`, including perfect squares, nonsquares and
the full-width case g=12. This is the same 96-step restoring calculation,
not an approximate root or a changed denominator.

| Norm root edge | Pre-edge condition / accepted event | Post-edge state |
|---|---|---|
| S | ROOT_SETUP, D nonzero | Zero root/residue; aligned radicand; ROOT for g clocks |
| S | ROOT_SETUP, D zero | Zero root/residue; PREPARE, no division issued |
| S+1 through S+g | ROOT | Eight exact radix-4 steps per edge; final edge registers root and enters PREPARE |
| P | PREPARE, nonzero root and divider ready | Ratio operands accepted; RATIO_WAIT, no early result use |
| P | PREPARE, zero root | Registered zero output in HOLD |

At that earlier repair the divider grouped eight, rather than four, exact
restoring steps per RUN clock. The current grouped 16-bit quotient-digit
implementation above supersedes that restoring chain; the norm's eight-step
root grouping is unchanged. Divider shortcuts, separate ROUND edge, signed
overflow/zero-divisor errors and held output semantics remain unchanged.
Digit arithmetic is enabled only in RUN, and the rounding increment only
in ROUND; inactive arithmetic cannot affect registered operands or outputs.

These changes add no vector/frame storage, memory traffic, scratch boundaries,
precision conversion or public pins. They preserve all 128-/192-bit operands
and the exact intermediate recurrence values. Grouping increases combinational
arithmetic depth; no clock-frequency, area or wall-time improvement is claimed.
Verifier must rerun exact divider boundaries, RMS/L2 including root group
transitions and zero denominators, the retained C fixture, the full unchanged
behavior/mutation matrix and A/C synthesis under the existing budgets.
Designer performed no functional or synthesis execution for this repair.

The exact shortcuts target repeated attention score scaling in the incomplete
B execution retained at
`evidence/preparation/q40-public-cost-b17-001/receipt.json` and
`evidence/preparation/q40-public-host-cost-b17-002/receipt.json`, which link
the earlier B watchdog failure. With head dimension four, the score divisor
is exactly 2^41; dimension 64 likewise gives 2^43. Those divisions now enter
ROUND without a digit pass. Non-power-of-two roots and weighted-value
division use the prefix reduction when applicable. The shared helper also
retains identical norm results while permitting fewer arithmetic clocks.
That earlier shortcut repair changed no attention scans or reads; the
subsequent two-pass repair below removes one redundant attention scan.
Neither repair changes scratch writes, external transaction semantics or
materialization boundaries. No key/score cache or additional local vector
bank is introduced.
The empty-key path and registered SCORE/SCORE_WAIT and FINISH/FINISH_WAIT
ownership remain unchanged. This is an exact arithmetic execution-cost
repair, not a numerical mismatch or deadlock diagnosis. The retained
diagnostics are incomplete; reduced restoring work does not establish
whole-fixture or aggregate-suite runtime compliance. Verifier must measure
the unchanged mandatory matrix, including B/C, and recheck divider boundary,
reset, stalled-output, mathematical, mutation and synthesis requirements.

This implementation targets the native wide-division timeout retained in
`evidence/preparation/q40-division-001/receipt.json`, linked to the four-element
RMS stall in `evidence/preparation/q40-norm-002/receipt.json` and integrated
startup stall in `evidence/preparation/q40-startup-004/receipt.json`.
Those diagnostics demonstrate failure of the old execution path, not a precise
simulator-internal cause. Reusing the sequential divider also removes duplicated
native wide quotient/remainder operators from norm and attention; it does not
establish synthesis budget compliance. The retained 45-second singleton timeout
is `evidence/preparation/q40-synthesis-a-001/receipt.json`. All functional,
numerical, sensitivity and A/C synthesis checks remain Verifier-owned and must
actually rerun within unchanged budgets. No simulation or synthesis was run
by Designer for this repair, and no existing evidence was overwritten.

### Exact series, rotary reuse and matvec execution-cost repair

The grouped-root C fixture completes with exact embeddings and scratch histories
in `evidence/preparation/q40-grouped-root-c-joint-001/receipt.json`, but the
reported four-fixture subset already consumes 128.607 simulation seconds.
The other three retained receipts are
`evidence/preparation/q40-grouped-root-c-text-001/receipt.json`,
`evidence/preparation/q40-grouped-root-b-joint-001/receipt.json` and
`evidence/preparation/q40-grouped-root-c89-joint-001/receipt.json`.
These are individual advisory passes, not passing aggregate acceptance.
This subsequent RTL repair targets repeated local work and clock count,
without changing external requests, their order or the numerical contract.

The nonlinear EXP, SIN, COS and GELU series, and RoPE frequency series, now
perform up to four successive original recurrence steps on each SERIES edge.
The working term and sum remain signed 96-bit Q40; each multiply/divide
still rounds at its original site before
the next recurrence uses its result. The iteration counter names the next
term, initially one. Each executed term increments it; the final group
evaluates only terms 17 and 18 and exits with next-term index 19. There is
no reassociation, combined division, extra saturation or new rounding.
If the initial or newly computed recurrence term is exactly zero, all
remaining terms through 18 are provably zero: multiplication of zero and
nearest-even division by each positive series divisor both return zero.
Those zero tail steps are omitted, not approximated or tested against a
tolerance. FINISH still uses the registered sum on a separate edge and
retains the original exponent shift, GELU finishing equations and clamping.
RECIP and RSQRT equations are unchanged; their current registered divider
phases are specified in the nonlinear specialization below.

RoPE retains two scalar cache entries, each consisting of the complete Q40 angle
and its successful Q40 sine/cosine results, plus a validity bit. It is not
a token, score, weight or tensor cache. Frequency generation, theta selection,
position multiplication and angle reduction still execute for every pair.
ANGLE compares all 48 reduced-angle bits in both entries. On a hit it registers the cached
pair and enters LO0; on a miss it performs the original SINREQ/SINRSP then
COSREQ/COSRSP handshakes. The newest entry is populated only by a successful cosine
response following the successful sine response for that angle. Trig is a
pure function of the reduced angle, so identical angles can reuse these
results across heads, layers or jobs without dependence on weights, operands,
position interpretation or full/local mode. Reset/abort invalidates the
entries through the existing helper reset. Failed trig results are never cached.
The four MAC rotation steps and both separately registered pair results are
unchanged; no unrounded tensor crosses a materialization boundary.

Matvec now drives its existing shared MAC directly from the already registered
successful weight result while in RESPONSE. On the result-acceptance edge
it clears/accumulates for column zero, or accumulates for later columns, and
advances the column or enters PREPARE. This removes the redundant weight-hold
register and PRODUCT clock, not a memory response phase. A stalled or erroneous
result never accumulates. The final successful response updates the MAC;
only the following PREPARE edge captures its rounded result into the held
OUTPUT register. The exact product order, 128-bit sum, Q40 rounding and row
output ordering remain unchanged, including a one-column row. Memory bridge
request, response and result ownership remain separate registered phases.

| Local helper edge | Pre-edge event/condition | Post-edge state/result |
|---|---|---|
| Nonlinear I | in_valid && in_ready | Zero EXP/COS: held G; zero SIN/GELU: held zero; otherwise original argument reduction, SERIES with next term 1, or original immediate/root branch |
| Rotary pair zero | start_valid && start_ready, valid descriptor and pair=0 | Register frequency G and shift zero; ANGLE on the next edge |
| Series edge | SERIES, next term <=18 | Up to four ordered exact terms; register term/sum/next index |
| Last series edge | Term 18 evaluated, or term exactly zero | FINISH (nonlinear) or ANGLE (frequency); no accepting-edge output |
| Nonlinear finish | FINISH | SIN/COS/EXP register result and HOLD; RSQRT/GELU prepare the registered divider operation described below |
| Rotary angle hit | ANGLE and valid complete-angle match | Register cached sine/cosine; LO0, no nonlinear request |
| Rotary angle miss | ANGLE without match | SINREQ; original separate request/response phases |
| Rotary cache fill | COSRSP and successful accepted response | Register cosine and complete cache entry; LO0 |
| Matvec R | RESPONSE and result_valid && result_ready, no error | MAC captures product; next REQUEST or PREPARE |
| Matvec R error | RESPONSE and accepted erroneous result | DONE/error 3; no MAC accumulation |
| Matvec R+1 final | PREPARE, final product already registered | Capture rounded MAC; held OUTPUT |
| Matvec output | out_valid && out_ready | Next row REQUEST or separate DONE |

The changes add only bounded scalar temporaries and two trig cache entries;
there are no extra vector banks, scratch words, provisioning changes or
transactions. They may increase combinational depth and generic synthesis
work; no wall-time, area or clock-frequency improvement is established by
source inspection or static elaboration. Verifier must measure the retained
fixtures and unchanged full aggregate checks, and independently cover series
zero tails/final groups, rotary hit/miss/reset behavior, nonzero/axial angles,
single-/multi-column matvec responses, stalls/errors, exact scratch histories,
mathematical thresholds, all mutations and A/C zero-latch synthesis. No
functional simulation, oracle or synthesis execution was performed by Designer
for this repair.

### Dense-projection sequential weight-address cursor

`anvil_e2_matvec` uses a registered 64-bit `weight_addr` for its REQUEST and
RESPONSE address path instead of reevaluating
`base + 4*(row*cols + col)` there. At `start_valid && start_ready`, it captures
`start_weights` alongside the existing descriptor. Let `n` be the number of
successfully retired weight results since that start. The cursor invariant is
`weight_addr = start_weights + 4*n`. At every REQUEST and RESPONSE,
`n = row*cols + col`, so the command address is identical to the former
row-major expression. The original widened 128-bit byte-extent validation,
alignment checks and descriptor-error priority remain unchanged.

| Matvec edge/phase | Pre-edge event | Post-edge cursor and control |
|---|---|---|
| Reset | rst_n=0 asynchronously | Cursor zero; original reset outputs and IDLE |
| Start | start_valid && start_ready | Cursor captures start_weights; original validation and LOAD/DONE decision |
| Input load | in_valid && in_ready | Cursor holds; original input bank and column updates |
| Request stall/acceptance | REQUEST, with either cmd_ready value | Cursor holds; original REQUEST/RESPONSE transition |
| Response stall | RESPONSE, result_valid=0 | Cursor holds; no MAC accumulation |
| Successful weight retirement | result_valid && result_ready && !result_error | Cursor adds four; original MAC clear/accumulate and column/phase update |
| Erroneous weight retirement | result_valid && result_ready && result_error | Cursor holds; original held DONE/error 3; no MAC accumulation |
| Row result and output stall | PREPARE or OUTPUT | Cursor holds at next row's first weight; original registered MAC capture and held output |
| Nonfinal row output acceptance | out_valid && out_ready && !out_last | Cursor holds; increment row, reset column, enter REQUEST |
| Final row output/completion | Final output or completion accepted | Cursor holds at validated one-past-matrix address; no additional request |

Advancing on the row-final successful response prepares the next row without
a second increment on output acceptance. This also handles one-column and
one-row matrices without wrap-based terminal logic. The final successful
matrix response advances once to the validated end address, which is never
requested. A new accepted start replaces the cursor; reset cancels it.
The cursor is not used while cmd_valid is inactive outside RESPONSE: the
original base/row/column expression remains selected in LOAD, PREPARE,
OUTPUT, DONE and IDLE to preserve existing inactive address values exactly,
including after errors and completion. Reset still forces cmd_addr to zero.

This change adds one scalar register, not prefetch, caching, transactions or
storage precision. Request count/order, all accepting edges, MAC sequencing
and Q40/Q24 arithmetic are unchanged. The inactive-address compatibility
expression and descriptor extent multiplication are deliberately retained;
only the active weight-address path is strength-reduced. Runtime benefit
remains unproven: source inspection does not establish that this multiplication
dominates simulator CPU cost or that aggregate checks fit their budgets.

The retained aggregate failure is
`evidence/preparation/q40-response-edge-aggregate-cost-001/receipt.json`.
The failed concurrent candidate in
`evidence/preparation/q40-two-worker-paired-001/receipt.json` remains
unadopted; neither concurrency nor longer budgets is part of this change.
Verifier must first perform bounded serial before/after comparisons of the
unchanged B/seed17/joint and C/seed89/joint fixtures, retaining exact embeddings,
complete scratch histories, mathematical tolerances, request ordering and
actual timings. Singleton/final-row behavior, independent request/response
stalls, reset and memory-error retirement require independent coverage.
Aggregate closure remains pending until measured useful headroom supports
an attempt within the unchanged budgets. Designer performs no functional
simulation or synthesis for this candidate.

### Historical bounded-operand division execution-cost repair

The nonlinear general-purpose division paths described in this historical
repair are superseded by the current series/non-series specialization below.
RoPE retains the general divider only for its initial logarithmic ratio;
its recurrence uses the bounded series specialization. The current operator
ledger, not these former path-selection guards, defines the implementation.

The next retained four-fixture subset still requires 114.426 simulation
seconds, before compilation, references or other mandatory coverage:
`evidence/preparation/q40-series-c-joint-001/receipt.json`,
`evidence/preparation/q40-series-b-joint-001/receipt.json`,
`evidence/preparation/q40-series-c89-joint-001/receipt.json` and
`evidence/preparation/q40-series-c-text-001/receipt.json`.
Those fixtures pass their exact embeddings and scratch histories individually;
the aggregate budget failure is not a numerical mismatch. This repair targets
native wide division in the nonlinear and rotary helpers without changing
their recurrence count, cycle table, operator order or memory transactions.
It does not establish aggregate budget compliance.

At this repair both helpers retained signed 96-bit division operands, quotient and residue.
For positive magnitude m and divisor d, explicitly unsigned 64-bit temporaries
implement these exact paths:

| Guard | Quotient and residue before the original nearest-even rounding |
|---|---|
| d=1 | q=m, r=0, with no native division |
| m<2^64 and d is a tabulated series divisor | Exact reciprocal-estimate/correction path specified below, then original nearest-even rounding |
| m<2^64 and 0<d<2^64, otherwise | q=floor(m/d), r=m-q*d, using 64-bit operands |
| m<2^80 and 0<d<2^48, when the first guard does not hold | h=floor(m/2^16), l=m mod 2^16; qh=floor(h/d), rh=h mod d; u=rh*2^16+l; q=qh*2^16+floor(u/d), r=u mod d |
| Otherwise | Original signed 96-bit quotient and residue |

In the two-limb path h fits 64 bits and rh<d<2^48, so u fits 64 bits.
The low quotient is less than 2^16. The assembled quotient fits 80 bits;
it is retained in 96 bits, with no discarded carry or sign bit. This is
Euclidean division, not an approximate result: m=q*d+r and 0<=r<d
hold before the unchanged comparison with d-r, tie-parity increment and
sign restoration. Numerical scale, saturation and zero-divisor handling are
unchanged. In particular, denominator guards exclude zero; unsupported
operand sizes fall back rather than truncate. The exp/trig recurrence
divisions use the exact constant-reciprocal path; the Q80 GELU tanh numerator can use the
two-limb path. Auxiliary reciprocal/root cases retain a full-width fallback.

Argument reduction also uses explicitly signed 64-bit quotient/remainder
temporaries where the original operands provably fit. Nonlinear sin/cos
inputs have only 48 bits. Exp arguments are nonpositive and clamped at
-16*G; GELU reaches its series only for -8*G<x<8*G, with its transformed
nonpositive argument also clamped at -16*G. RoPE's initial logarithmic
argument has magnitude no greater than ln(theta)*G plus rounding because
2*pair<dimension; this is below 2^44 for every supported theta.
Thus each LN2 quotient and remainder has exactly the old signed result,
including negative remainders and the floor-quotient decrement.

RoPE still forms the complete frequency-times-position product in 96 bits
before modulo TWO_PI. Only a product with all upper 32 bits zero selects
an unsigned 64-bit modulus; the positive TWO_PI remainder is below 2^43
and is exactly representable in the signed 64-bit temporary. Other products
retain the original signed 96-bit modulus, including large 32-bit positions.
The subsequent [-PI,PI] reductions, angle cache and trig handshakes are
unchanged.

These paths introduce only bounded scalar working temporaries; no new
register phase, vector bank, cache entry, precision boundary or interface
is added. All work remains inside the original accepting IDLE, SERIES,
ANGLE and FINISH edges. No output becomes visible before its original
registered HOLD phase, and stalls/reset retain their existing semantics.
Generic arithmetic selection may increase synthesis work; source inspection
does not establish a simulator speedup or synthesis budget compliance.
Verifier must independently exercise direct/two-limb/fallback transitions,
signed rounding ties, the GELU branches and tanh ratio, series zero tails,
positive/negative angle reductions and large positions, then execute the
unchanged full behavioral, sensitivity and A/C synthesis acceptance checks.
Designer performed no functional, mathematical or synthesis experiments.

### Historical quotient-digit and current two-pass attention repair

The following retained individual fixtures pass exact embeddings and complete
scratch-write histories, with mathematical component errors below 0.002, but
their simulation times alone total 113.213 seconds:
`evidence/preparation/q40-narrow-series-c-joint-001/receipt.json` (35.745 s),
`evidence/preparation/q40-narrow-series-b-joint-001/receipt.json` (29.283 s),
`evidence/preparation/q40-narrow-series-c89-joint-001/receipt.json` (36.645 s)
and `evidence/preparation/q40-narrow-series-c-text-001/receipt.json` (11.540 s).
This exceeds the unchanged 110-second aggregate runner budget before any
compilation, reference calculations or remaining coverage. The retained
failures are not evidence of a numerical mismatch or deadlock.

At that repair the shared divider executed the exact 16-bit quotient-digit algorithm
specified above instead of eight bitwise restoring steps per RUN edge. Its
single 64-bit estimate division and 145-bit exact correction product replace
the repeated 129-bit shift/compare/subtract chain. Only the leading estimate
operands are normalized; the original 128-bit divisor, complete candidate
product and remainder determine the exact result. The number of RUN clocks
is now ceil(quotient_bits/16), at most eight. Power-of-two, small-magnitude,
zero-divisor, nearest-even, signed-overflow and held-result behavior are
unchanged. No helper output is consumed on its input-acceptance edge.

Attention previously scanned eligible keys three times: maximum selection,
exponent-denominator accumulation, then weighted-value accumulation. It now
uses two passes. The first pass is unchanged and establishes the maximum
of clamped Q40 scaled scores before any exponent evaluation. During the
second pass, each eligible key recomputes the same scaled score, performs
the same widened maximum subtraction and strict below-minus-sixteen test,
and obtains the same Q40 exponent. The successful exponent response adds
that weight to the exact 128-bit denominator and registers it for that
key's V products. The engine then reads the materialized V components and
adds their exact Q80 products to the existing weighted vector. Only after
the last eligible key's products have accumulated does it divide each
weighted component by the completed denominator.

Each individual denominator and weighted-component reduction still consumes
eligible keys in ascending order, at full original width, with no added
rounding or saturation. Interleaving these independent exact reductions
does not alter either sum. Q/K/V and eligibility metadata were materialized
before attention starts and are not modified during either pass. Therefore
the removed denominator-only scan and duplicate score/exp computations
cannot change numerical operands. Q is loaded once as before; K and metadata
are read in both remaining passes; V is read once per eligible key in the
weighted pass as before. Strict-tail keys contribute zero and do not read V,
and empty eligibility completes with the original zero vector. No score,
key, weight, token or frame cache is added. Existing scratch writes, tensor
strides and Q24 materialization boundaries remain unchanged. The external
read transcript is intentionally shorter; public transaction and ownership
semantics are unchanged, not a fixed read-count or fixed-latency guarantee.

The attention MAC now accepts a product directly on a successful registered
K or V result retirement, following the existing matvec response-folding
pattern. K component zero clears/accumulates the dot product; subsequent
components accumulate. A successful final K response enters SCORE, whose
following edge starts division using the already registered dot sum.
Every V response clears/accumulates its one product; the separate WEIGHT
edge has now been removed as described below: that response edge also adds
the exact combinational product to the appropriate weighted component.
Removed DOT/PRODUCT/WEIGHT edges and the operand-hold register did not introduce
rounding boundaries. A stalled or erroneous result never enables the MAC;
accepted errors retire before held stage completion as before.

| Attention edge | Pre-edge event / condition | Post-edge state / result |
|---|---|---|
| K | KRSP, result_valid && result_ready, no error | Register dot MAC; next KREQ or SCORE |
| K+1 final | SCORE and divider ready | Accept registered dot sum; SCORE_WAIT |
| Maximum response | SCORE_WAIT, divider output accepted, first pass | Update maximum/found flag; NEXTKEY |
| Maximum end | NEXTKEY after final key | Empty: FINISH; otherwise weighted pass, first key |
| Weighted score response | SCORE_WAIT, second pass | Strict-tail skip or EXPREQ with original Q40 difference |
| Exponent response | EXPRSP, successful response | Add weight to denominator; latch weight; VREQ at component zero |
| V stalled | VRSP, result_valid=0 | Hold weighted bank/channel/state; no MAC update |
| V | VRSP, result_valid && result_ready, no error | Sign-extend exact shared 96-bit product and add to weighted[channel]; increment channel and enter VREQ, or reset channel and enter NEXTKEY after the final component |
| Weighted end | NEXTKEY after final key | FINISH, then separate FINISH_WAIT for each division |
| K/V error | Accepted erroneous result | DONE/error 3; no MAC update or new request |
| Reset or held output | Original reset/stall conditions | Original cancellation or stable held-output semantics |

### Attention descriptor-hoisted address cursors

`anvil_e2_attention` now captures the invariant query and grouped-KV head
address terms on its existing accepted descriptor edge. Its command-address
mux selects registered cursors instead of recomputing products involving the
runtime head dimension for each request. The FSM, accepting edges, command
ordering and arithmetic datapath are unchanged; this is separate from the
earlier V-response transfer-edge removal below.

Let `d` be the selected head dimension, `D=max(LOCAL_HEAD_DIM,FULL_HEAD_DIM)`,
`K=max(LOCAL_KV_HEADS,FULL_KV_HEADS)`, `Q=NUM_Q_HEADS`, and
`hkv=start_head/(Q/selected_KV_heads)`. All following byte-address expressions
use unsigned 64-bit arithmetic, retaining the old modulo-2^64 expression
semantics; top-level extent validation is unchanged.
The accepted descriptor establishes:

| Register/origin | Captured value |
|---|---|
| Query component cursor | start_q_base + 4*(start_query*Q*D + start_head*d) |
| Query position address | start_positions_base + 4*start_query |
| K/V head origins | start_k_base/start_v_base + 4*hkv*d |
| K/V key origins and component cursors | Corresponding K/V head origin, for key zero |
| Key position/mask cursors | start_positions_base/start_mask_base |

At each KREQ/VREQ the key origin equals its head origin plus
`key*(4*K*D)`. The K component cursor equals that key origin plus
`4*component`; the V cursor equals its own key origin plus `4*channel`.
At QREQ the query cursor equals its captured origin plus `4*component`.
The token stride is the compile-time maximum-head padded stride, not `d`;
only the active head offset and component traversal use `d`.

| Attention edge/phase | Pre-edge event | Post-edge address/control behavior |
|---|---|---|
| Reset | rst_n=0 asynchronously | All cursor/origin registers zero; original reset outputs and IDLE |
| Descriptor acceptance | start_valid && start_ready | Capture all origins/cursors and original descriptor; original QREQ or error-DONE decision |
| Q/K/V request stall or acceptance | Existing request state, either cmd_ready value | Cursors hold; original request/response transition |
| Response stall or error | result_valid=0, or accepted result_error | Cursors hold; original wait or DONE/error 3; no added request |
| Successful nonfinal Q/K/V response | Existing response retirement, component/channel not final | Corresponding component cursor adds four alongside original counter increment |
| Successful final Q/K/V response | Existing final response retirement | Corresponding cursor holds; original phase transition and counter behavior |
| Mask/position/score/exp processing | Existing eligibility or arithmetic phase | Cursors hold; original eligibility, reductions and transitions |
| NEXTKEY, nonfinal key | Existing unconditional NEXTKEY edge | K/V key origins add 4*K*D, component cursors capture those next origins, metadata adds four; original key increment and next phase |
| NEXTKEY, final key | Existing unconditional NEXTKEY edge | Key origins/component cursors rewind to captured head origins; metadata rewinds to captured bases; original pass restart or FINISH decision |
| Output/completion stall or retirement | Original output/done handshake | Address registers hold; original held outputs and completion |

NEXTKEY updates every traversal cursor even when a key was masked, outside
the local window, omitted from V reads in the maximum pass, or assigned a
zero tail weight in the weighted pass. It never derives a next-key address
from a partly consumed component cursor. The final-key rewind occurs before
the second pass's first request, including a singleton token. Vision begins
directly at KREQ after query loading; text retains its query-position,
mask and optional key-position reads. Final-key completion also rewinds
internally but exposes no request. No cursor advances on an erroneous
response, and reset cancels all traversal state.

`cmd_addr` remains exactly zero in every nonrequest state, including response,
output, error completion and idle, and while reset is asserted. Request
payloads remain stable across stalls. No precision boundary, tensor cache,
external transaction, stage interface or ownership edge is added or removed.
The accepted matvec cursor implementation remains unchanged.

The pre-change attention source is retained byte-for-byte at
`evidence/preparation/q40-cursor-serial-paired-001/before-rtl/anvil_e2_attention.sv`
(SHA-256 `628391f3c0f69d8d4ebaf2e1176718ef30bd0f6a84e430b5024e733d47baa575`).
Verifier must use a disposable current-source copy with only this pre-change
attention file substituted, thereby retaining the accepted matvec cursor and
all other current sources. Fresh project-local receipts must link
`evidence/preparation/q40-cursor-serial-paired-001/receipt.json` and
`evidence/preparation/q40-projection-attention-b17-001/receipt.json`.
Compare complete unchanged B/seed17/joint and C/seed89/joint runs, including
public request/response cycles and payloads, embeddings and scratch writes,
against independent oracles. Targeted public-pin boundaries must cover both
passes, vision/text and local/full dimensions, every KV head group, masked
and skipped keys, tail-zero weights, singleton/final-key rewind, last
component, descriptor capture, request/response/output stalls, error retirement,
reset and inactive output values.

This targets repeated address computation, not a proven dominant CPU cost
or numerical defect. Only static elaboration is Designer-owned; functional
comparison, serial cost measurements, sensitivity and synthesis are pending
Verifier work. One timing pair does not establish useful aggregate headroom.
The retained aggregate deadline failure and failed two-worker candidate remain
unresolved; concurrency stays unadopted. Demonstrated sufficient headroom is
required before another aggregate attempt. All mandatory coverage,
mathematical 0.002 thresholds and admitted 120-second budgets are unchanged.

### Attention V-response transfer-edge removal

The localized scheduling candidate follows
`evidence/preparation/q40-projection-attention-b17-001/receipt.json`,
linked to
`evidence/preparation/q40-lookup-gap-analysis-b17-001/receipt.json`.
Those Verifier diagnostics observed an incomplete B/seed17/joint prefix,
not completed inference or aggregate acceptance. The eight complete observed
vision-attention windows contained 1280 V reads, each previously followed by
one WEIGHT edge solely transferring the registered MAC product.

`anvil_e2_mac` now exposes its existing signed 48-by-48 multiplication as a
signed 96-bit combinational product alongside its unchanged registered sum
and rounded result. The product is isolated to zero unless reset is released
and accumulate is asserted. The hybrid engine connects that exact product to
attention without an extra multiplier, numerical bank, memory transaction or
public pin. It is an operand tap, not an independently valid arithmetic-result
channel; no consumer presents it as a held result before an accepting edge.
On a successful VRSP result retirement, the pre-edge operands are the held
Q40 exponent and exactly promoted Q24 V word. That same edge sign-extends
the complete 96-bit Q80 product by 32 bits, adds it to the existing signed
128-bit weighted component, and advances the channel/state. It does not use
the pre-edge registered MAC sum, which still belongs to the previous
operation. The MAC continues its original clear/product capture on that edge;
the K-response dot reduction and its following SCORE divider-start edge are
unchanged. Ascending-key reduction order, all saturation/rounding sites and
Q24 materialization boundaries are unchanged.

No V response means no weighted update or channel advance. An erroneous
accepted V response retires into held error 3 without enabling the product
or writing the weighted bank. Reset retains priority, including when the
stage/helper clock is stopped. The final component still enters NEXTKEY
before FINISH; there is no same-edge divider start or new command acceptance.
Only the redundant transfer edge is removed. Request addresses/order are
unchanged, but request cycles and cycle-dependent host stalls may differ;
the old prefix's exact cycle transcript is not an expected new waveform.

This is not a demonstrated aggregate-budget remedy or a functional
verification result. The combinational product tap changes inference and
event scheduling and needs independent bounded validation. Verifier must
immediately check exact integer embeddings and scratch writes, unchanged
mathematical thresholds, K/V stalls and errors, signed/extreme products,
final-component transitions, reset, all existing MAC consumers, sensitivity
and A/C synthesis, then establish actual aggregate budget compliance.
No functional simulation or synthesis was run by Designer for this change.

These changes are exact arithmetic/sequencing repairs, not a revised numerical
contract. They introduce only scalar estimator registers and temporaries,
not additional vector storage or external provisioning. The 64-bit native
division and correction multiplier may alter generic synthesis cost and
combinational depth. No runtime speedup, budget compliance, clock rate or
area result follows from source inspection or static elaboration.
Verifier must first independently cover digit normalization at divisor
lengths 48/49/128, zero/one-correction cases, candidate 65536, full-width
prefix shifts, signed ties, signed-128 endpoints, zero divisor and held
results. It must also check unequal-score attention, every head group,
local/full eligibility, empty keys, tail-zero weights, K/V response stalls
and errors, exact scratch-write histories and the unchanged mathematical
thresholds. All retained fixtures, full aggregate behavior/sensitivity checks
and A/C zero-latch synthesis remain required under unchanged budgets.
Designer ran no simulation, reference-model or synthesis experiments for
this repair; all earlier evidence and verification sources are preserved.

### Historical constant-reciprocal and retained width-search repair

The reciprocal implementation described in this historical subsection is
superseded by the exact bounded-native series division below. Its proof and
retained evidence explain the previous implementation, not the current divider.
Width search, zero shortcuts and residue reconstruction remain in use.

The quotient-digit/two-pass subset still exceeds the aggregate budget:
`evidence/preparation/q40-two-pass-c-joint-001/receipt.json`,
`evidence/preparation/q40-two-pass-b-joint-001/receipt.json`,
`evidence/preparation/q40-two-pass-c89-joint-001/receipt.json`,
`evidence/preparation/q40-two-pass-c-text-001/receipt.json` and
`evidence/preparation/q40-two-pass-b89-joint-001/receipt.json` retain five
individual passes but 124.668 seconds of simulation alone. They do not
establish passing aggregate execution. The retained divider boundary pass
is `evidence/preparation/q40-digit-divider-boundaries-001/receipt.json`;
it predates this repair and is not evidence for the changed sources.

The earlier nonlinear helper tabulated the exact integer constants
`R(d)=floor(2^64/d)` for d=2..18 and d=n*(n+1), n=1..36.
These cover every exp, sine and cosine recurrence divisor. RoPE needs only
the 2..18 subset for its frequency recurrence. The divisions in these tables
have literal constant operands and are elaboration-time constants, not
new runtime divisions or provisioned coefficients. The current specialized
series call sites supply only these exact positive divisors. The earlier
general-purpose full-width guard is no longer instantiated at each series step.
Divisor one directly gives q=m and r=0 at the original operator site.

For a tabulated d>=2 and unsigned magnitude m<2^64, form the exact unsigned
128-bit product m*R(d), and take its upper 64 bits as q0. Since
`0<=1/d-R(d)/2^64<1/2^64`, q0 is either floor(m/d) or one less.
The unsigned 64-bit product q0*d fits because q0*d<=m<2^64.
Compute r0=m-q0*d; it is nonnegative and less than 2*d (d<=1332 here).
If r0>=d, increment q0 once and subtract d once. The resulting q and r
satisfy m=q*d+r and 0<=r<d exactly. The original nearest-even comparison
with d-r and sign restoration then execute unchanged in 96 bits.
No approximate quotient, new rounding or tolerance enters the operator.
The current nonlinear non-series paths use the shared registered divider
instead. RoPE's initial logarithmic ratio retains its direct/two-limb/full-width
paths; recurrence magnitudes cannot reach 2^64.

All native quotient/remainder pairs in nonlinear division, rotary frequency
division, PLE dimension scaling, spatial pooling and sentence pooling now
compute the quotient once and reconstruct the exact residue m-q*d instead
of executing a second native modulus. Each product fits its existing
magnitude width because q*d<=m. In the two-limb paths this identity is applied
separately to the high dividend and to the appended low dividend, each in
64 bits; quotient assembly remains 96-bit. LN2 argument reduction likewise
reconstructs the signed truncated-division remainder x-q*LN2 in signed
64 bits before the original negative-remainder floor correction. Its inputs
and products fit the already documented argument bounds. Rounding,
saturation, epsilon, root calculation and every materialization remain
unchanged.

Divider and norm bit-length helpers now search successive 64/32/16/8/4/2/1
bit partitions instead of scanning 128 individual bits. A nonzero upper
partition shifts the remaining operand and adds that partition's width.
The final low bit distinguishes zero from one. This yields exactly the same
0..128 result, including zero and 2^127, so prefix skipping, quotient digit
counts and root groups do not change.

Exact constant cases omit only work with a proven constant result.
Accepted EXP(0) and COS(0) register G; SIN(0) and GELU(0) register zero,
then hold the original valid/data/error channel until accepted. RoPE pair
zero, after the unchanged dimension/pair validation, registers total=G and
exponent_shift=0 and enters ANGLE directly: its original logarithmic
argument, reduced argument and every recurrence term after the initial G
are exactly zero. ANGLE still consumes the registered position on a
separate edge, performs its original range reduction/cache lookup, and
executes the existing trig and MAC ownership transitions. These shortcuts
change internal latency only. They never expose a result before acceptance
or alter stalled-output, reset, error or external transaction behavior.

Only bounded scalar temporaries and constant selection logic are added.
No vector/frame cache, external transaction, scratch word, tensor boundary,
public pin or numerical equation changes. Reciprocals trade division for
generic multiplication/selection and may affect synthesis cost; neither
runtime benefit nor budget compliance has been measured by Designer.
Verifier must independently check the reachable series divisors, exact and
one-correction estimates, both signs/ties, the retained rotary initial-ratio
width boundaries, zero nonlinear handshakes and pair-zero/nonzero rotary paths.
The retained fixtures, exact scratch histories, unchanged mathematical
thresholds, full aggregate behavior/sensitivity and A/C zero-latch synthesis
remain outstanding for these sources, under unchanged budgets.
Designer ran no simulation, oracle, mutation or synthesis experiment.

### Exact edge-local arithmetic and two-angle reuse repair

The constant-reciprocal/bit-length repair still fails the aggregate execution
budget. Eight unchanged mandatory fixtures complete and pass exact embeddings,
scratch-write histories and both mathematical thresholds, but consume 132.141
simulation seconds before compilation, references or remaining coverage:
`evidence/preparation/q40-bitsearch-c-joint-001/receipt.json`,
`evidence/preparation/q40-bitsearch-b-joint-001/receipt.json`,
`evidence/preparation/q40-bitsearch-c89-joint-001/receipt.json`,
`evidence/preparation/q40-bitsearch-c-text-001/receipt.json`,
`evidence/preparation/q40-bitsearch-b89-joint-001/receipt.json`,
`evidence/preparation/q40-bitsearch-b-vision-001/receipt.json`,
`evidence/preparation/q40-bitsearch-c89-text-001/receipt.json` and
`evidence/preparation/q40-bitsearch-b89-text-001/receipt.json`.
The prior arithmetic boundary passes are retained separately in
`evidence/preparation/q40-bitsearch-divider-001/receipt.json` and
`evidence/preparation/q40-bitsearch-norm-001/receipt.json`. None certifies
the sources changed by this repair.

The divider's unchanged digit and nearest-even calculations now execute
inside the sequential RUN and ROUND branches, respectively. Blocking working
temporaries are fully computed from the registered pre-edge operands before
the same nonblocking quotient/residue/result assignments. There is no new
pipeline stage or accepting-edge result: RUN still consumes exactly one
16-bit digit, the last RUN still enters ROUND, and ROUND still enters held
output. Computing these private temporaries only on the owning edge avoids
re-evaluating the digit expression as its registered operands settle between
edges. All widths, estimate correction, shortcuts, error checks and helper
latencies remain unchanged. These temporaries have no combinational consumer
or independently observable output.

Nonlinear and RoPE `multiply_q40` keep signed 96-bit arguments and results,
but explicitly form the exact product from signed 64-bit operands into
128 bits instead of multiplying sign-extended operands into 192 bits.
This is lossless for every reachable call, not an alternative numerical
format or a truncating fast path:

| Call site | Conservative bound before multiplication |
|---|---|
| Exp and RoPE frequency recurrence | Reduced argument is in [0,LN2); term magnitude stays below 2*G |
| Sine/cosine recurrence | Reduced angle magnitude is below 4*G; terms stay below 8*G and the first nested product below 32*G |
| GELU cubic path | Executed only for abs(x)<8*G; rounded square is below 65*G and rounded cube below 513*G |
| GELU coefficient products | K<0.045*G and C<0.8*G; cubic argument, coefficient and transformed operands are below 1024*G |
| GELU final product | abs(argument)<8*G; rounded tanh magnitude is at most G, so abs(G+tanh)<=2*G |

For trig, the unrounded Taylor term maxima are less than 6*G
(`PI^3/6` for sine and `PI^2/2` for cosine); the listed 8*G and 32*G
bounds include the finitely many nearest-even perturbations through term 18.
Exp's nonnegative reduced argument is below LN2, so its initial G term
dominates subsequent terms, also with ample rounding margin.
Every operand is consequently below 1024*G=2^50 in magnitude and is
exactly represented by the selected signed low 64 bits. Its signed product
fits 128 bits. The discarded upper product bits from the former 192-bit
representation were only sign extension. Arithmetic shift by 40, the
low-40-bit greater-than-half/tie-parity test, increment, and signed-96
result selection are unchanged. Terms, sums, GELU ratio and division
fallbacks retain their existing 96-bit widths; roots retain all 192 bits.
RECIP and RSQRT do not call this multiplication function.

RoPE's former single complete-angle entry is now two constant-size scalar
entries, allowing a repeated row/column angle pair to reuse both successful
trig results across heads and Q/K. Both tags compare all 48 angle bits;
neither theta, position nor vector values substitute for an angle match.
A hit in either entry registers its sine/cosine and enters the existing
LO0 state. It does not change either entry. A successful miss, and only
the successful COSRSP after its successful SINRSP, shifts the newest complete
entry into the previous entry and installs the new pair. Both validity
bits clear on reset/abort. The extra storage is exactly one validity bit
and three 48-bit scalars, independent of sequence length, layer count and
vector width. This is not a Q/K/V, score, weight, token or frame cache.

| Edge | Pre-edge condition | Post-edge result |
|---|---|---|
| Divider RUN | Registered operands and RUN | One exact digit registered; next RUN or separate ROUND |
| Divider ROUND | Final registered quotient and residue | Original nearest-even result/error held |
| Rotary ANGLE hit | Either valid tag equals complete reduced angle | Matching registered sine/cosine, LO0; no early rotation result |
| Rotary ANGLE miss | Neither valid tag matches | Original SINREQ/SINRSP/COSREQ/COSRSP |
| Rotary successful COSRSP | Successful accepted cosine for this angle | Install new complete entry, preserve prior newest as previous, LO0 |
| Rotary failed SINRSP/COSRSP | Accepted helper error | Original held error; neither entry changes |
| Reset/abort | Existing helper reset asserted | Both entries invalid; all helper outputs retain reset semantics |

No public pins, external transactions or their order, tensor offsets, scratch
writes, saturation sites, Q24 materialization, operator iteration counts or
acceptance thresholds change. Only a successful second-entry rotary hit can
reduce internal latency; the divider and nonlinear multiply retain their
existing edge schedule. No runtime or synthesis-budget compliance is claimed
from these source-level changes. Verifier must measure the retained fixtures
and the full unchanged aggregate checks, and independently recheck divider
boundaries, all norm vectors, nonlinear signed ties and extreme/branch inputs,
two-angle hit/miss/eviction/reset behavior, axial rotations, exact scratch
histories, mathematical thresholds, all mutations and A/C zero-latch synthesis.
Designer runs only static syntax/elaboration, not functional or synthesis
experiments, for this handoff.

### Exact operand-isolation and root working-width repair

The edge-local repair still exceeds aggregate execution: eight unchanged
mandatory fixtures take 135.830 simulation seconds before compilation,
reference work or remaining coverage. The individual retained results are
`evidence/preparation/q40-edgework-c-joint-001/receipt.json`,
`evidence/preparation/q40-edgework-b-joint-001/receipt.json`,
`evidence/preparation/q40-edgework-c89-joint-001/receipt.json`,
`evidence/preparation/q40-edgework-c-text-001/receipt.json`,
`evidence/preparation/q40-edgework-b89-joint-001/receipt.json`,
`evidence/preparation/q40-edgework-b-vision-001/receipt.json`,
`evidence/preparation/q40-edgework-c89-text-001/receipt.json` and
`evidence/preparation/q40-edgework-b89-text-001/receipt.json`.
They complete exact embedding/scratch comparisons and both mathematical
thresholds; they are not timeouts or demonstrated deadlock. The retained
arithmetic comparisons are
`evidence/preparation/q40-edgework-divider-001/receipt.json` and
`evidence/preparation/q40-edgework-norm-001/receipt.json`.
Timing variation between these and earlier receipts does not establish a
causal performance regression.

This repair changes local evaluation and lossless temporary widths, not
transaction count, clock count, numerical equations or materialization.
Top-level response data is routed only to the registered owning stage in
WAIT; nonowners receive zero and still have result_valid zero. The owner
receives the complete original word throughout the held-result handshake.
Hybrid bank read muxes select data only in consuming states: source A in
MAT_LOAD, VECTOR, VPRODUCT and VGELU_REQ; source B in residual VECTOR or
VPRODUCT; offset source A in WRITE_REQ or NORM_FEED. They retain explicit
array sensitivity, including writes at an unchanged address. Bank updates,
operand capture and stalled requests retain their existing edges. No
inactive mux value is captured by an operator.

The MAC forms its exact signed 48x48 product only on an accumulating edge.
Clear with accumulation replaces the sum; accumulation without clear adds
the sign-extended product; clear alone zeros it; neither holds it. The
blocking product is a private same-edge temporary, not a new pipeline
register. Rounding remains a combinational pure function of the registered
128-bit sum with the same low-40-bit tie test and C endpoints. Norm likewise
forms its exact square only when LOAD accepts a value, before adding it to
the existing unsigned 128-bit sum. Neither operator samples an input early
or exposes an accepting-edge result.

Norm retains the entire 192-bit radicand and 96-bit root. Only its restoring
remainder, shifted remainder and trial shrink from 194 to 98 unsigned bits.
For a consumed radicand prefix p with partial root r, the exact invariant is
`p=r*r+e`, `0<=e<2*r+1`. Before step m+1, `0<=m<=95`, r has at most m bits.
Appending a two-bit digit u gives `4*e+u<2^(m+3)<=2^98`; the trial `4*r+1`
also fits 98 bits. The subtraction is conditional on eligibility, so it
never underflows. After the final step the residue is below `2*r+1<2^97`.
Thus no reachable bit is discarded, even for a full unsigned 192-bit
radicand; leading-zero omission and zero denominators are unchanged.
Each eight-step group reads the original registered radicand pairs
`[191-2*j -: 2]`, j=0..7, in order, then shifts the radicand once by sixteen.
This is bit-identical to eight successive two-bit shifts, without repeatedly
assigning a 192-bit working temporary. The root group count and latency
remain unchanged.

SIN and COS construct recurrence divisors in unsigned twelve-bit arithmetic
before zero-extending to the original signed-positive 96-bit denominator.
For terms i=1..18, SIN uses `(2*i)*(2*i+1)<=1332`, and COS uses
`(2*i-1)*(2*i)<=1260`; every factor and product fits twelve bits.
Term order, all eighteen iteration sites, zero-tail handling, rounded
multiplication/division and FINISH remain unchanged.

| Edge/state | Pre-edge condition | Post-edge result |
|---|---|---|
| Owned response | WAIT, registered owner, bridge held result | Only that stage can accept the unchanged word; no nonowner update |
| MAC accumulate | accumulate=1, with either clear value | Exact product replaces/adds to sum; rounded output reflects only registered sum |
| MAC clear-only / hold | accumulate=0 | clear=1 zeros sum; clear=0 holds sum |
| Norm load | LOAD && in_valid && in_ready | Capture value/weight and add the same exact square |
| Norm ROOT | Registered radicand/root/remainder | Eight exact steps in 98-bit working arithmetic; one sixteen-bit radicand shift |
| Trig SERIES | Eligible term in 1..18 | Same exact divisor, recurrence and rounded term/sum |
| Reset or stall | Existing reset/stall condition | Original output zeroing, cancellation and payload stability |

That operand-isolation repair introduced no precision sidecar, cache, storage
region, external request, public pin, clock gate or clock-domain crossing.
Reduced inactive evaluation and temporary widths are implementation targets,
not measured runtime improvement or evidence of budget compliance. Verifier
must recheck exact MAC clear/accumulate cases, signed rounding/saturation,
all RMS/L2 vectors and root group boundaries, all trig divisors, bank reuse
and operand capture, held responses and request/output/reset timing. The
retained fixtures, complete scratch histories, unchanged mathematical
thresholds, full aggregate behavior/sensitivity and A/C connected zero-latch
synthesis remain mandatory. Designer performs only static syntax/elaboration;
no new functional, oracle, mutation or synthesis experiment is claimed.

### Registered inactive-stage clock isolation

The narrow-root sources still exceed the aggregate bounded-execution budget:
eight unchanged fixtures consume 131.137 simulation seconds, before compilation,
references or remaining mandatory coverage. The retained individual receipts are
`evidence/preparation/q40-narrow-root-c-joint-001/receipt.json`,
`evidence/preparation/q40-narrow-root-b-joint-001/receipt.json`,
`evidence/preparation/q40-narrow-root-c89-joint-001/receipt.json`,
`evidence/preparation/q40-narrow-root-c-text-001/receipt.json`,
`evidence/preparation/q40-narrow-root-b89-joint-001/receipt.json`,
`evidence/preparation/q40-narrow-root-b-vision-001/receipt.json`,
`evidence/preparation/q40-narrow-root-c89-text-001/receipt.json` and
`evidence/preparation/q40-narrow-root-b89-text-001/receipt.json`.
Their exact embeddings, scratch comparisons and mathematical thresholds pass
individually. They establish neither deadlock nor passing aggregate execution.
The retained 3408 divider comparisons and 33 norm vectors are
`evidence/preparation/q40-narrow-root-divider-001/receipt.json` and
`evidence/preparation/q40-narrow-root-norm-001/receipt.json`; they predate
this clock-isolation change.

`anvil_e2_clock_gate` adds one rising-edge, asynchronously reset enable register
per stage, independent of all model dimensions. Its equation is
`stage_clk = clk | !active`, with `active` sampling the owner's START/WAIT
selection on each ungated rising edge, subject now to the bridge-wait
qualification below. Unlike an AND gate with a rising-edge
enable register, this OR gate holds the stopped clock high. A synchronous enable
change occurs only while clk is high and therefore cannot change stage_clk.
After wake, the next input falling edge lowers stage_clk and the following input
rising edge clocks the stage. During normal operation every stage rising edge is
an input-clock rising edge; no falling-edge state element, latch, local oscillator
or new independent clock domain is introduced.

START holds until active is registered. Both start_valid and the top's START
retirement condition require active, so the wake edge cannot falsely transfer
ownership. Once active, the existing start_valid/start_ready edge registers the
stage's descriptor and the top enters WAIT. The selected stage receives every
input rising edge during arithmetic, held results, embedding and completion.
The current bridge-wait isolation below suppresses otherwise idle stage edges
while external requests/responses are pending. Ownership does not change
until stage completion retires. On that retiring edge the old stage still receives
its clock and done_ready, returning its controller to idle. Its enable may clear
on the subsequent input rising edge; that edge is harmless idle work. A new owner
wakes separately in START. The bridge/controller clocks are never gated, and no
accepted external transaction is suspended or bypassed.

| Input edge/condition | Accepted event | Post-edge behavior |
|---|---|---|
| START, active=0 | Clock-enable capture only; start_valid=0 | active=1, remain START; no stage rising edge on wake |
| Next START, active=1, stage ready | Original stage start handshake | Stage captures inputs, top WAIT; selected clock remains enabled |
| WAIT with arithmetic/output or held bridge result | Original handshakes only | Selected stage receives every rising edge; unchanged payload/ownership |
| WAIT with held stage completion accepted | Original completion retirement | Stage idle; top next START or DONE; no same-edge new owner |
| Old owner no longer selected | Disable capture | Clock stays high after this edge until selected again |
| rst_n=0, any clock phase | Asynchronous cancellation | active=0; every stage/helper also resets directly through rst_n |

If reset clears active during an input low phase, the OR gate can rise while
rst_n is asserted. This is a reset-only edge, not functional work: controllers
take their asynchronous reset branch and all unreset bank write enables are
reset-qualified. Reset release does not itself generate a stage edge. Subsequent
jobs initialize every consumed bank value exactly as before. Gating preserves
all public reset zeroes and does not depend on a clock pulse to reset a stage.

This initial isolation changed only inactive clock activity and added a
registered START wake edge; the current bridge-wait extension is specified below.
All required stage instances remain literal and connected. All numerical
operators, widths, rounding, materialization, memory requests and ordering,
scratch writes and error priorities are unchanged. The generic gate is
synthesizable register/OR logic, not a technology-qualified clock-gating cell;
physical implementation must constrain gated clocks and check enable-to-falling-
edge timing. No physical timing, clock frequency, power, wall-time speedup or
budget compliance is claimed. Designer performs only static elaboration.
Verifier must check first starts, every interstage/layer handoff, back-to-back
jobs, reset in all required phases, delayed requests/responses and held outputs;
then execute the unchanged mandatory fixtures, mathematical/exact comparisons,
mutations and connected zero-latch A/C synthesis under the existing budgets.

### Current nonlinear specialization and local-helper clock ownership

The stage-clock sources still fail bounded execution. Eight mandatory fixtures
individually pass exact embeddings, complete scratch histories and both 0.002
mathematical thresholds, but their sequential simulation alone totals 110.836 s.
The retained receipts are
`evidence/preparation/q40-stageclock-b-joint-001/receipt.json`,
`evidence/preparation/q40-stageclock-b-vision-001/receipt.json`,
`evidence/preparation/q40-stageclock-b89-joint-001/receipt.json`,
`evidence/preparation/q40-stageclock-b89-text-001/receipt.json`,
`evidence/preparation/q40-stageclock-c-joint-001/receipt.json`,
`evidence/preparation/q40-stageclock-c-text-001/receipt.json`,
`evidence/preparation/q40-stageclock-c89-joint-001/receipt.json` and
`evidence/preparation/q40-stageclock-c89-text-001/receipt.json`.
`evidence/preparation/q40-stageclock-synthesis-a-001/receipt.json` and
`evidence/preparation/q40-stageclock-synthesis-c-001/receipt.json` retain actual
Yosys timeouts during PROC_MUX, before netlist/latch assertions. The logs contain
expanded nonlinear division work; this is not proof of its exclusive or dominant
cost. The directed-case pass is retained separately in
`evidence/preparation/q40-stageclock-directed-001/receipt.json`. None certifies
the following changed sources.

The four ordered nonlinear recurrence steps now select their numerator and
divisor before a single specialized series division per step. Sine and cosine
share the identical nested multiplication expression; their divisors remain
`2*i*(2*i+1)` and `(2*i-1)*2*i`, respectively. Exp/GELU use divisor i.
The series division now uses the exact bounded-native quotient and reconstructed
residue described below, with the same signed nearest-even rule.
RoPE's recurrence uses its own bounded series divider;
only its initial logarithmic ratio uses the former general division function.
This removes unreachable general-purpose fallback logic from the unrolled
series without removing any reachable operand case.

The specialization is lossless: with abs(angle)<=PI, the largest mathematical
sine/cosine term is below 6*G. The finite eighteen nearest-even perturbations
remain well inside that bound. Multiplying a term twice by abs(angle)<4*G
gives an intermediate numerator below 64*G (the tighter PI^2<10 bound
gives below 60*G, with ample margin for both multiplication roundings).
Exp and frequency numerators are below 2*G. The final GELU product before
division by two is below 16*G. Thus every specialized numerator has magnitude
below 2^46, safely inside unsigned 64 bits; the full signed-96 input is used
to determine its sign. The exact unsigned-64 quotient/residue,
tie increment and restored signed-96 result preserve every original rounding
site. The series helpers are private functions, not arbitrary-operand public
division interfaces. General 128-bit division remains available through
`anvil_e2_divide` with its original full-width boundary/error contract.

Non-series nonlinear operations now reuse one literal `anvil_e2_divide`.
Its registered operands are signed-128 numerator and unsigned-128 positive
denominator. RECIP uses numerator `sign(x)*2^80` and divisor abs(x).
RSQRT retains its original 64-step root and uses numerator 2^88 and that root
as divisor. Both retain their input-domain errors and original saturation.
For GELU, FINISH forms the same exponential e and requests
`RN((G-e)<<40,G+e)`; the successful result is registered without saturation,
then its sign is adjusted using the captured argument. GELU_APPLY performs
the original rounded Q40 multiplication and nearest-even division by two,
then C. No quotient is materialized to Q24. Every successful non-series
quotient fits signed 96 bits: the largest reciprocal is 2^80, the smallest
positive RSQRT radicand root is 2^28 (so its ratio is at most 2^60), and
the GELU ratio is at most G. Selecting their low 96 bits is exact.

| Nonlinear phase / pre-edge event | Post-edge state and result |
|---|---|
| IDLE input acceptance, nonzero RECIP | Register signed numerator and positive divisor; DIV_START; no output |
| IDLE input acceptance, valid RSQRT | Original ROOT calculation, then FINISH |
| FINISH for RSQRT or GELU | Register division operands; DIV_START; no output |
| DIV_START and divider ready | Divider accepts registered operands; DIV_WAIT |
| DIV_WAIT and successful result | RECIP/RSQRT clamp into held output; GELU registers unsaturated ratio and enters GELU_APPLY |
| DIV_WAIT and divider error | Register zero/error; HOLD, no silently substituted success |
| GELU_APPLY | Original signed tanh/product/half-round/clamp; held output |
| Any HOLD with !out_ready | Preserve data/error and ownership |
| HOLD acceptance | IDLE only post-edge; no same-edge new input acceptance |

The RSQRT radicand is `x<<56`; its smallest positive integer x is one,
giving root 2^28. These auxiliary equations are unchanged; the extra registered
division phases replace the former combinational quotient, not the numerical
definition. Existing zero shortcuts and +/-8 GELU branches still bypass the
series exactly as before.

Hybrid-engine local helper gates use the existing registered high-idle clock
primitive. Matvec is enabled throughout MAT_START/LOAD/RUN; norm throughout
NORM_START/REQ/RSP/FEED/OUT or pool ownership. Layer-only attention and rotary
are enabled throughout their respective START/RUN phases. Their start_valid
and the parent's ready observation both require the corresponding active bit,
so waking cannot falsely retire START. Nonlinear wakes on a pending input,
then stays enabled until its raw input-ready returns high after output
retirement. Its input valid and the callers' ready observation are likewise
active-qualified. Therefore an idle helper need not execute on unrelated
memory/arithmetic clocks, while a pending or stalled operation receives every
required clock. The MAC is intentionally not gated: it can accept a memory
result on the first successful result edge without a prior wake cycle.

All local gate enables are scalar and independent of model dimensions.
Parent START/request holds during the extra wake edge. Original helper LOAD,
run, held-output and completion phases remain distinct; output retirement
clocks the helper back to IDLE before sleeping. Direct asynchronous unit reset,
including FLUSH cancellation, reaches gates, helpers and nested dividers even
when their clocks are stopped. No banks, precision sidecars, external words,
scratch offsets, memory accesses, materialization boundaries, pins, operator
equations, fixtures or acceptance limits change.

This targets process-expansion and inactive-helper execution cost, but adds
registered wake/division clocks. Static reasoning cannot establish a net
simulation or synthesis improvement, nor budget compliance. Designer runs
only fast static elaboration, not simulation, synthesis or a preparation
harness. Verifier must measure the unchanged aggregate checks, first rechecking
nonlinear exact results/domain errors, series terms/ties, GELU branch and ratio
boundaries, helper wake/sleep/reset and held-output behavior, followed by all
mandatory fixtures, scratch histories, mathematical thresholds, mutations and
connected zero-latch A/C synthesis. The original failures remain preserved.

### Exact bounded-native series and grouped-digit execution repair

The local-helper-clock implementation still exceeds the unchanged aggregate
behavior budget: eight passing mandatory B/C fixtures total 110.283 seconds
of simulation before other required work. The original receipts remain at
`evidence/preparation/q40-localclock-b-joint-001/receipt.json`,
`evidence/preparation/q40-localclock-b-vision-001/receipt.json`,
`evidence/preparation/q40-localclock-b89-joint-001/receipt.json`,
`evidence/preparation/q40-localclock-b89-text-001/receipt.json`,
`evidence/preparation/q40-localclock-c-joint-001/receipt.json`,
`evidence/preparation/q40-localclock-c-text-001/receipt.json`,
`evidence/preparation/q40-localclock-c89-joint-001/receipt.json` and
`evidence/preparation/q40-localclock-c89-text-001/receipt.json`.
Actual Yosys failures are preserved at
`evidence/preparation/q40-localclock-synthesis-a-001/receipt.json` and
`evidence/preparation/q40-localclock-synthesis-c-001/receipt.json`.
Reading the existing A timestamped stdout shows approximately 35.231 seconds
between decoder creation for the nonlinear process and the following process,
and 6.569/6.452 seconds for the two rotary processes. This localizes substantial
PROC_MUX work in that retained execution; it is not a measured repair speedup
or a claim about exclusive whole-check cost.

The private nonlinear and rotary series functions now compute unsigned
`q=floor(m/d)` directly in 64 bits and `r=m-q*d` in 64 bits, then apply the
unchanged `r>d-r || (r==d-r && q is odd)` increment and restore the original
signed-96 numerator's sign. The existing bounds above establish m<64*G<2^64;
all reachable divisors are positive and at most 1332. Thus q*d<=m, the product
and subtraction are lossless, and this is the same quotient and residue
formerly obtained through the reciprocal table and correction. Division by
one and the GELU final division by two remain exact under this general rule.
No Taylor term, intermediate multiplication rounding, tail, argument
reduction, constant, saturation or materialization changes. Removing the
repeated reciprocal cases also removes their per-call process selection work.
These are bounded unsigned-64 divisions, not the earlier failing native
signed-128 division in `evidence/preparation/q40-division-001/receipt.json`.
The public full-width helper retains normalized 64-bit estimate division;
it does not reintroduce native 128-bit division.

The full-width helper now groups at most four existing exact quotient digits
in each RUN edge, as specified in its updated table above. It preserves the
same prefix, normalization, 17-bit estimate, 145-bit correction product,
128-bit quotient/residue, separate ROUND edge and errors. There are still at
most eight digits, now taking at most two RUN edges. This replaces only
internal latency; no result appears before its accepting edge or bypasses
registered owner/result acceptance. The norm's root algorithm and cycle
grouping are unchanged.

No test, oracle, assertion, evidence file, authoritative input, public pin,
external transaction, vector storage, scratch offset or Q24/Q40 boundary is
changed. Wider combinational digit chains and native bounded division may
affect generic synthesis and critical-path cost. No physical performance,
wall-time improvement or budget compliance is inferred from source inspection.
Designer performs only static syntax/elaboration. Verifier must re-execute
exact nonlinear and divider boundary cases (including partial digit groups
g=1..8), RMS/L2, reset/cancellation/held outputs, all unchanged mandatory
fixtures, scratch histories, mathematical thresholds, mutations and real
connected zero-latch A/C synthesis within the existing budgets.

### Current series process separation and bridge-wait clock isolation

The preceding bounded-native/grouped-digit repair did not meet execution
budgets. The unchanged eight B/C simulations total 115.312259 seconds, already
over the 110-second aggregate runner before other required work. Their receipts
remain at `evidence/preparation/q40-nativegroup-b-joint-001/receipt.json`,
`evidence/preparation/q40-nativegroup-b-vision-001/receipt.json`,
`evidence/preparation/q40-nativegroup-b89-joint-001/receipt.json`,
`evidence/preparation/q40-nativegroup-b89-text-001/receipt.json`,
`evidence/preparation/q40-nativegroup-c-joint-001/receipt.json`,
`evidence/preparation/q40-nativegroup-c-text-001/receipt.json`,
`evidence/preparation/q40-nativegroup-c89-joint-001/receipt.json` and
`evidence/preparation/q40-nativegroup-c89-text-001/receipt.json`.
The A/C Yosys timeouts are retained at
`evidence/preparation/q40-nativegroup-synthesis-a-001/receipt.json` and
`evidence/preparation/q40-nativegroup-synthesis-c-001/receipt.json`.
Their timestamped logs localize substantial nonlinear PROC_MUX work; they do
not identify an exclusive whole-check cause.

`anvil_e2_series` now separates the four-step combinational recurrence from
the nonlinear/rotary clocked FSMs. Its work variables have complete assignments
on every evaluation, rather than sharing conditionally retained temporaries
with argument reduction, root, GELU and result states. TRIG=1 retains the
operation-selected exp/sine/cosine recurrence; TRIG=0 specializes rotary
frequency generation to exp. It evaluates only while SERIES is enabled.
The existing registers still capture one four-step group per SERIES edge.
There is no additional register, cycle, result handshake or arithmetic
rounding boundary.

The recurrence uses signed-64 Q40 work values. As established above, each
rounded trig numerator is below 64*G in magnitude; each term is below 6*G.
The absolute sum of the unrounded trig terms is bounded by exp(PI)*G<24*G,
and the eighteen bounded rounding perturbations remain far below the
40*G margin to 64*G. Exp/frequency totals stay below 2*G with rounding margin
well below G. Reduced arguments are bounded by PI or LN2. Thus every
recurrence operand, product rounded back to Q40, sum and division result is
signed-64 representable. Products remain exact signed-128; their original
low-40-bit nearest-even test is unchanged. Division still uses exact
unsigned-64 magnitude/quotient/reconstructed residue and restores the sign.
Controller captures sign-extend these results into the existing signed-96
registers. This is a working-width specialization, not a precision change.
GELU preprocessing, its final half division, all non-series ratios, constants,
root work, terms 1..18, exact-zero tails and saturation are unchanged.

The top now enables a selected WAIT stage when the bridge is idle, holds a
result, or accepts an external response on that input rising edge:
`bridge_wake = bridge_ready || bridge_result_valid ||
(mem_rsp_valid && mem_rsp_ready)`. START still wakes unconditionally.
The bridge and top always receive the ungated input clock. When a command is
accepted, every stage's serialized memory caller enters its response-wait
phase: no independent arithmetic or bank write is scheduled until its result.
Sleeping during this wait therefore suppresses only idle controller/helper
edges, not model work. Nested helper clocks retain their current enables and
direct asynchronous reset while their parent clock is stopped.

| Pre-edge bridge/stage condition | Event at input edge | Post-edge condition |
|---|---|---|
| Idle bridge, selected stage active with command valid | Both command sides handshake | Bridge REQUEST; caller response-wait; stage still active on this edge |
| REQUEST/RESPONSE, no response accepted | No stage command/result handshake | Gate may disable; bridge request payload and response ownership remain live |
| RESPONSE and response valid, stage inactive | Bridge captures response; gate registers enable | Bridge RESULT; no stage edge or accepting-edge consumption |
| Following edge, RESULT and stage active | Both result sides handshake | Caller consumes exactly once; bridge idle; active remains enabled |
| RESULT without stage result-ready | No result retirement | Bridge holds result and gate remains enabled |
| Stage arithmetic/embedding/completion, bridge idle | Existing stage events | Clock remains enabled; all previous phase/stall semantics retained |
| Reset in any wait/wake phase | Asynchronous cancellation | Gate, stage, nested helpers and bridge reset directly; no canceled work resumes |

Both sides of the top's command/result channels are qualified by the selected
stage's registered active bit. A stopped caller cannot cause the bridge to
accept a command or discard a result without its own edge. Waking on response
acceptance ensures the stage is active on the first edge that can consume the
registered RESULT, even for the earliest legal response; request acceptance
alone never wakes a result consumer. This introduces no response bypass or
additional outstanding transaction. External request/response phases, word
values, addresses/order, scratch history, stage ownership, output stalls and
error priority are unchanged.

The changes target synthesis process construction and idle simulation work.
Neither their net runtime benefit nor budget compliance is established by
inspection or static elaboration. Wider combinational recurrences remain
generic arithmetic, not timing-qualified hardware. Designer runs only fast
static elaboration. Verifier must immediately rerun exact nonlinear/divider/
norm boundaries, partial series groups and zero tails, minimum/delayed
responses, request stalls, reset/cancellation and held outputs, then the
unchanged complete A-D fixture matrix, scratch histories, both mathematical
thresholds, five mutations and connected zero-latch A/C Yosys checks.
No acceptance command, fixture, reference model, threshold, source ownership,
external tensor shape or materialization boundary is changed.

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
