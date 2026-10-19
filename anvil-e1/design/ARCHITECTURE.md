# Anvil-E1 implementation contract

## Status and authority

This file defines the intended integration contract, not verification results.
The retained foundations and executors are integrated by
`rtl/anvil_e1_sequencer.sv` and `rtl/anvil_e1_top.sv`. The hardwired sequencer
implements embedding initialization, distinct per-layer PLE inputs, all
transformer branches, Q/K/V production, attention, final projection and pooling.
These are design sources, not accepted functional results. No verified
embedding inference, primitive accuracy, synthesis, performance or
official-checkpoint parity is claimed.

The immutable `hf_embeddinggemma2_spec/` files establish geometry, tensor shapes
and Transformer -> masked mean Pooling -> Normalize. They do not supply
executable forward code. The forward equations below are the adopted work-order
Gemma-family conventions, not recovered official implementation evidence.
Vision and audio are excluded.

Phase 2 adds `rtl/anvil_e_top.sv` as the official-weight integration root.
It contains only the parameter-forwarding instance `core` of `anvil_e1_top`,
with identical ports/defaults and zero additional stages. Direct use of
`anvil_e1_top` remains supported; its twelve-module implementation is retained.
[Official weight evaluation](OFFICIAL_WEIGHTS_EVALUATION.md) defines the
supplied checkpoint-slice scope, deterministic mapping, independent FP32 and
integer comparisons, cycle accounting and current verification handoff.
Historical diagnostics below are not current Phase 2 acceptance.

## Geometry and tensor packing

The implemented controller/address module defaults are V=262144, H=512, P=512, I=2048, E=768,
L=24, Q=4, local KV=2, full KV=1, local D=256, full D=512,
window=512 and max sequence=262144. These are also actual top-level parameter
defaults. Layer index modulo six equal to five
selects full attention, including 5,11,17,23 at default.

`design/pack_model.py` expands the supplied two layer templates and five globals
into 413 tensors. It accepts only authoritative default shapes and BF16
language-model tensors. Packing order is lexical global name, then ascending
numeric layer index and lexical suffix. Every element occupies four bytes,
little-endian signed Q8.24; matrices are row-major. Inventory offsets are byte
offsets relative to `weights_base`. Layer tensor order is:

1. `input_layernorm.weight`
2. `layer_scalar`
3. `mlp.down_proj.weight`
4. `mlp.gate_proj.weight`
5. `mlp.up_proj.weight`
6. `ple_block.per_layer_input_gate.weight`
7. `ple_block.per_layer_projection.weight`
8. `ple_block.post_per_layer_input_norm.weight`
9. `post_attention_layernorm.weight`
10. `post_feedforward_layernorm.weight`
11. `pre_feedforward_layernorm.weight`
12. `self_attn.k_norm.weight`
13. `self_attn.k_proj.weight`
14. `self_attn.o_proj.weight`
15. `self_attn.q_norm.weight`
16. `self_attn.q_proj.weight`
17. `self_attn.v_proj.weight`

Global order is embed_tokens, embedding_projection, norm,
ple.per_layer_model_projection, ple.per_layer_projection_norm (all with
`language_model.` prefix and `.weight` suffix). For reduced parameters,
the global PLE matrix has shape [L*P,H], PLE gate [P,H], PLE output [H,P].
Local q/k/v/o shapes are [Q*D,H], [KV*D,H], [KV*D,H], [H,Q*D];
the full layers use their independent D and KV values. Never collapse
attention width to H before o projection.

CLI from the project root:

```
python3 design/pack_model.py --input /supplied/model.safetensors \
  --output weights.q24.bin --inventory weights.inventory.json
```

The supplied Phase 2 official slice is present, but is not a complete default
checkpoint and must be rejected by this strict complete-checkpoint CLI.
No checkpoint is downloaded. Parent output directories must exist.
The packer validates header keys, dtype, shapes, data extents, complete
nonoverlapping payload layout and finite pure-text weights. Unrelated
non-language-model tensors are explicitly excluded and listed in inventory;
their file extents are still validated. Duplicate JSON keys are rejected.
Temporary output files are removed on conversion failure. After complete
conversion the image and inventory are individually replaced; the pair is not
a transactional filesystem update, so submit jobs only after CLI success.

BF16 conversion is exact integer conversion with nearest/ties-even rounding
and saturation to [-128,128-2^-24]. NaN and infinity are errors, not zeros.

## Forward equations and tensor bindings

Let `R(x,w) = x * rsqrt(mean(x*x)+epsilon) * (1+w)`, with
hardware epsilon represented directly at Q48 as `281474977/2^48`
(nearest/ties-even representation of 1e-6) and norm weights using a unit
offset everywhere. The raw-weight FP32 software comparison uses floating
epsilon 1e-6 rounded at its FP32 boundary, not the hardware constant.
Matrix multiplication uses row-major output rows. For token t:

```
e[t] = embed_tokens[id[t]] * sqrt(H)
p[t] = reshape(ple.per_layer_model_projection @ e[t] / sqrt(H), [L,P])
p[t,l] = R(p[t,l], ple.per_layer_projection_norm)
x[t] = e[t]
```

Each layer computes:

```
u[t] = R(x[t], input_layernorm)
q[t], k[t], v[t] = q_proj @ u[t], k_proj @ u[t], v_proj @ u[t]
q[t,head] = R(q[t,head], q_norm)
k[t,head] = R(k[t,head], k_norm)
q[t], k[t] = RoPE(q[t], position[t]), RoPE(k[t], position[t])
a[t] = grouped_query_attention(q[t], k, v, mask, position)
x[t] += R(o_proj @ a[t], post_attention_layernorm)
u[t] = R(x[t], pre_feedforward_layernorm)
x[t] += R(down_proj @ (GELU(gate_proj @ u[t]) * (up_proj @ u[t])),
          post_feedforward_layernorm)
x[t] += R(per_layer_projection @
          (GELU(per_layer_input_gate @ x[t]) * p[t,l]),
          post_per_layer_input_norm)
x[t] *= layer_scalar
```

RoPE uses split-half rotation within each head: for i in [0,D/2),
angle=position*theta^(-2*i/D), rotate (x[i],x[i+D/2]).
Theta is 10000 for local and 1000000 for full attention. The implementation
must calculate arbitrary absolute positions, not use token indices instead.
Each contiguous group of Q/KV query heads maps to one KV head.
Scores are complete head dot products divided by sqrt(D). Softmax subtracts
the maximum. Full attention sees all explicitly valid keys; local attention
also requires absolute position difference strictly below window.
Attention is bidirectional. Invalid queries may be skipped entirely, but
their hidden states must not enter pooling. An empty key reduction is zero,
never reciprocal of zero.

Final token output is `embedding_projection @ R(x[t], norm)`.
Pool only mask=1 tokens with mean, select leading requested channels, then
L2-normalize that selected vector. Prompt tokens are included when valid.
All-masked jobs error without output; a nonempty pooled zero vector succeeds
with all-zero output. Default legal dimensions are 768,512,256,128; reduced
E must be divisible by six and supports E,2E/3,E/3,E/6.

## External storage and intended scratch layout

Host input arrays are separate little-endian 32-bit words for token IDs,
absolute positions and masks. No implicit BOS/EOS insertion or PAD masking.
The host supplies nonoverlapping, four-byte-aligned regions and must not modify
them while a job is active. The controller checks descriptor dimensions,
alignment and all region-end address additions before requesting memory.
It then reads every ID, position and mask, including masked token entries,
and rejects invalid values before granting the engine a start handshake.
Region nonoverlap is a host obligation; it is not checked by hardware.

All scratch entries are four-byte Q8.24 words. With N=job_tokens,
DM=max(localD,fullD), KM=max(localKV,fullKV), assign consecutive regions:

| Region | Words | Use |
|---|---:|---|
| X | N*H | Current hidden states |
| PLE | N*L*P | Distinct projected per-layer inputs |
| Q | N*Q*DM | Per-token query heads, padded stride |
| K | N*KM*DM | Per-token key heads, padded stride |
| V | N*KM*DM | Per-token value heads, padded stride |
| next X | N*H | Separate layer result to avoid read/write mixing |

Total scratch bytes are `4*N*(2*H+L*P+(Q+2*KM)*DM)`.
`anvil_e1_address` evaluates all counts, offsets and byte sizes with unsigned
128-bit arithmetic. Its tensor IDs 0..4 select the global order above; IDs
5..21 select the 17 layer suffixes above in order, with an independent numeric
`layer_index`. `element_index` is a flattened row-major word index. Shape
outputs describe matrices as rows/columns and vectors as [length,1].
The output `tensor_error` flags an invalid tensor/layer/element selection or
overflow of the selected byte address.

The tensor decoder derives the five global byte offsets and the 17 suffix
prefixes for each local/full geometry as elaboration-time constants. The
prefix-building loop is evaluated only for these constants; no runtime process
walks the checkpoint or its layers. If G is the combined global byte extent,
Blocal/Bfull are the two layer byte extents and l is a valid zero-based layer,
its start is `G + (l-floor(l/6))*Blocal + floor(l/6)*Bfull`.
The selected suffix prefix is added using that layer's geometry. Total weights
bytes are `G + (L-floor(L/6))*Blocal + floor(L/6)*Bfull`, including for layer
counts not divisible by six. Global selection remains independent of l.
Invalid selections still raise `tensor_error`; invalid layer or tensor
selection retains the zero offset before element/base addition. All prefix,
extent, layer-count and address calculations retain unsigned 128-bit
intermediates and the existing high-half overflow checks.

The runtime unsigned 32-bit layer quotient uses the exact constant-reciprocal
identity `floor(l/6) = (uint64(l)*2863311531) >> 34`. The product fits 64 bits
for every 32-bit input; the remainder is `l-6*floor(l/6)`. This replaces both
runtime division and modulo in shape/prefix selection without adding address
latency. The sequencer instead tracks a three-bit phase counter 0..5 alongside
the layer index, resetting both together and wrapping phase after five.
Grouped-query head selection uses comparisons against elaboration-constant
group boundaries, supporting non-power-of-two legal head group sizes.

Tensor and scratch address calculations are separate combinational processes
with separate temporaries; scratch input changes do not cause tensor decoding
to reevaluate. The weight extent is a constant continuous output. This adds no
clock cycles, registers or changed handshake boundaries: the controller and
sequencer still latch addresses at their existing operation boundaries.
Independent address-boundary checks and fixed-work replay must assess
correctness and cost reduction; no whole-system speedup or budget feasibility
is presumed from this structural simplification.

Scratch region IDs 0..5 select X, PLE, Q, K, V, next X. `scratch_word`
is relative to that region, not to the whole scratch allocation. The generator
reports `scratch_error` for an invalid region/word or overflow. Q/K/V token
strides are padded to Q*DM or KM*DM; within a token, heads are packed at
the active D stride. The sequencer uses this convention when producing
Q/K/V, and swaps the two X region roles between layers.

The controller rejects any exclusive region end `base+size` greater than
`0xffffffffffffffff` with error 5. Thus even a region whose final word would
fit but whose exclusive end equals 2^64 is rejected explicitly. This conservative
end-address convention is shared by the matrix executor. Input arrays each use
4*N bytes, weights use the entire parameter-derived packed image, and scratch
uses the whole allocation above. Input validation begins only after these
checks. The integrated sequencer obtains tensor starts from this address
generator, derives row-major offsets within the validated tensor extents,
and latches each of the six scratch-region starts before computation.

Internal working buffers may be vector-sized H, P, I, Q*DM and E, but not
sequence-sized arrays or an N*N score matrix. Attention uses repeated external
K/V reads, first for maximum score, then denominator, then weighted values.
Store layer Q/K/V for all valid tokens before consuming attention for any
token. Swap current/next hidden regions only after the entire layer completes.
All weights and intermediates travel over the external interface; repeated
reads trade bandwidth for bounded on-chip storage. No measured traffic,
throughput, timing or physical PPA is claimed.

## Implemented primitive boundaries

### Iterative division and cycle/degenerate boundaries

The timing-hazard repair replaces runtime RTL division/remainder operators
with local, stateful unsigned-magnitude restoring dividers in nonlinear,
norm, RoPE, attention, pool and sequencer. These are contained in the existing
modules, retaining all thirteen RTL files and independently compilable
primitive modules; there is no new include-file or module dependency.
Each divider holds a 96-bit quotient/dividend, 96-bit divisor and 97-bit
remainder. Four radix-two compare/subtract steps execute per DIVIDE edge,
over 24 edges, rather than a combinational 96-stage division. Quotient and
remainder are registered between groups of four steps. A following state
consumes the completed result. All clocked assignments, including task-expanded
register updates and resets, are nonblocking; arithmetic temporaries are
combinational wires, combinational processes or automatic function locals.

The invariant after all 96 steps is `abs(n)=q*abs(d)+r`, with
`0<=r<abs(d)`. Nearest/ties-even increment uses
`r>d-r || (r==d-r && q[0])`, then restores the quotient sign.
Signed remainders restore the dividend's sign. Negative floor quotients
subtract one from the truncated signed quotient only when the remainder is
nonzero; exp/RoPE reduction then adds ln(2) to a negative signed remainder.
No numerical boundary, Q40 constant, saturation rule or Q48 epsilon changes.
GELU's final division by two is an arithmetic shift with ties-even correction.
Divisors are positive/nonzero at their operation entry, except reciprocal's
validated signed nonzero input. Zero L2 and empty attention bypass division.
Remaining RTL `/` and `%` expressions have only elaboration-time parameter
operands (geometry diagnostics, fixed dimensions, constant group sizes and
total layer count); they are not runtime datapaths.

| Boundary | Pre-edge condition | Post-edge state or payload |
|---|---|---|
| Reset | `rst_n=0`, including during DIVIDE | Public outputs/payloads zero; state and divider registers reset; no obsolete result survives |
| First released idle edge | No accepted start | Ready is asserted; no output or memory transaction is created |
| Divider launch E0 | Owning operation/start accepts valid operands | Magnitudes/signs captured, remainder/count zero, state DIVIDE |
| Divider E1..E24 | No new operand acceptance | Four restoring steps commit per edge; E24 enters the result-consumption state |
| Divider E25 | Completed quotient/remainder, same operation owner | Rounded result is captured, or next division launched; public output holds until its normal ready/valid retirement |
| Root step | Registered radicand/root/remainder | Combinational trial is consumed once; new root/remainder use only nonblocking updates |
| One element / E/6=1 | Final vector element or single selected channel | First output is also last; no stale vector-memory read replaces the just-computed scalar |
| Non-power-of-two dimensions/groups | Legal H/P/I/D/count and Q/KV | Counts use equality/wrap; no power-of-two mask or rounded reciprocal approximation |
| Zero/empty/invalid | Zero L2 or empty eligible attention; all masked or illegal geometry | Zero vectors bypass division; existing explicit errors/parameter diagnostics are preserved |
| Reset versus completion/stall | Reset while request, arithmetic or output is active | Reset wins; fabric must share reset/flush old responses; no success completion is fabricated |

One division occupies 26 operation edges including launch and result
consumption; an input-acceptance launch at E0 produces a held result after
E25 (25-edge difference). Chained divisions can consume one result and
launch the next on the same edge. The public memory, embedding, completion
and wrapper register stages are unchanged. Internal arithmetic latency and
therefore measured job cycles do change. Historical performance artifacts do
not describe these sources. Independent functional, sensitivity, architecture,
synthesis and timing-lint checks must assess the changed RTL. No FPGA timing
closure, physical frequency, current numerical pass or budget sufficiency
is inferred from removing the operators.

`anvil_e1_mac` multiplies signed Q8.24 inputs into signed 64-bit Q16.48
products, sign-extends and accumulates in 96 bits without per-product rounding.
Clear alone zeros the accumulator; simultaneous clear and accumulate starts
a new sum containing the presented product. Each enabled product updates on
one clock edge. `rounded` is a combinational nearest/ties-even division by
2^24 followed by signed 32-bit saturation. Negative rounding uses a signed
floor quotient and unsigned remainder, including negative halfway cases.
It is zero during reset. A caller must register the rounded result at a
documented operation boundary. Norm sums must not reuse a rounded 32-bit dot
result as an intermediate denominator.

`anvil_e1_memory` accepts one internal command, registers its complete
payload, then presents it until external acceptance. It accepts a response
only in the outstanding-response state, registers response data/error, and
holds that result until its internal consumer accepts it. Writes require
responses too. Even a zero-latency fabric must hold a response until
`mem_rsp_ready`, which asserts after the request-acceptance edge.
Command acceptance -> request presentation -> response acceptance ->
result retirement are distinct register boundaries; stalls add arbitrary
cycles. No payload depends on downstream ready. The bridge does not interpret
addresses or abort jobs. The implemented controller aborts on validation-read
errors; compute executors return memory error 3 to the sequencer,
which aborts and reports that error to the controller.

Both modules use active-low asynchronous reset. Public bridge outputs are
combinationally reset-gated to zero even before a time-zero reset edge;
registers reset to zero. The memory fabric must share reset or flush all old
responses before release. The bridge cannot distinguish an obsolete response
from a new one without that integration obligation.

### Nonlinear engine

`anvil_e1_nonlinear` uses opcodes 0 exp, 1 sin, 2 cos, 3 reciprocal,
4 inverse square root and 5 GELU. Input/output are signed Q8.24, with ready/valid
acceptance and a registered output/error held until retirement. Unsupported
opcodes, positive exp arguments, zero reciprocal arguments and nonpositive
rsqrt arguments return an explicit error with zero data. A caller must abort
on that error, not accept zero as a successful mathematical result.

Series arithmetic uses signed 96-bit Q40, signed 192-bit products rounded
nearest/ties-even to Q40, and nearest/ties-even signed integer divisions.
Final Q40 -> Q24 rounding is nearest/ties-even with 32-bit saturation.
Constants are nearest Q40 representations:

| Constant | Integer |
|---|---:|
| one | 1099511627776 |
| ln(2) | 762123384786 |
| pi | 3454217652358 |
| 2*pi | 6908435304715 |
| sqrt(2/pi) | 877283352226 |
| GELU cubic coefficient 0.044715 | 49164662436 |

For exp, floor-divide by ln(2), leaving remainder in [0,ln(2)), evaluate
sum(r^n/n!, n=0..18) with recurrent rounded terms, then shift by the negative
binary exponent. Inputs below -16 are mapped to -16, yielding about 1.13e-7
rather than zero; softmax can separately clamp scores below -16 to zero.
Sin/cos explicitly cast the sign-extended 96-bit input to signed before
shifting from Q24 to Q40 and taking the signed remainder modulo 2*pi.
The remainder retains the dividend's sign; values above pi subtract 2*pi
and values below -pi add 2*pi, giving [-pi,pi]. They then evaluate 18
recurrent Taylor terms after the initial x/1 term. No position-zero table shortcut is used;
the RoPE frequency/angle generator supplies reduced angles.
Direct Q8.24 angle input cannot represent unreduced default absolute-position
angles, so range reduction must precede this unit at the sequencer boundary.

GELU computes `x/2*(1+tanh(sqrt(2/pi)*(x+0.044715*x^3)))`.
For |x|>=8 it returns x for positive x, zero for negative x.
Otherwise tanh uses sign restoration and `(1-exp(-2*abs(z)))/(1+exp(...))`,
with the same -16 exp floor. This avoids positive exponential overflow.
Reciprocal directly nearest-divides 2^48 by the signed input integer and
saturates. Rsqrt restores an integer square root of `(input_integer<<56)`
in 48 radix-four cycles, yielding Q40; nearest-dividing 2^64 by that root
yields Q24 with saturation.

Domain rejection and GELU's |x|>=8 shortcuts remain visible immediately
after the acceptance edge. A valid reciprocal is held after E25.
Sin/cos/exp use one initial range-reduction division, then 18 series
iterations of launch, 24 divider edges and save, then one finishing edge:
the result is held 494 edges after input acceptance. Interior GELU adds
a finishing tanh-ratio division, giving 519 edges. Its final halving retains
ties-even Q40 rounding before Q24 conversion. Rsqrt uses 48 root edges,
one division-launch finishing edge, 24 divider edges and one save edge:
74 edges after input acceptance.
Output stalls add arbitrary cycles; no new input is accepted until retirement
and return to idle. These counts specify the FSM, not measured physical
throughput. Multiplication remains synthesizable integer logic, and division
is the iterative circuit above, not real arithmetic or host inference.

### Vector normalization

`anvil_e1_norm` accepts a count (1..MAX_WIDTH, parameter default 2048,
legal maximum 65535) and `start_l2`, then exactly count data/weight pairs.
Each accepted pair is buffered in bounded vector storage and its full 64-bit
square is accumulated in 96 unsigned bits. In RMS mode, nearest/ties-even
division by count produces the Q48 mean-square, then adds epsilon in Q48:
`EPSILON_Q48 = round_ties_even(1e-6 * 2^48) = 281474977`.
Thus `denominator_square = round_ties_even(sum(x_q24[i]^2)/count)
+ EPSILON_Q48`. This replaces the historical Q8.24-first epsilon
`17/2^24`, which added `285212672` at Q48; no legacy mode is retained.
The shared RMS path applies this constant uniformly to global PLE projection
normalization, all input/residual-path norms, per-head q/k norms and final
RMSNorm. L2 mode uses the sum without mean, epsilon or weights.
The denominator is not truncated to Q8.24.

The unit restores floor sqrt of `(denominator_Q48 << 64)` using an 80-step
radix-four integer root. The 80-bit root represents Q56. Each scalar is
nearest/ties-even normalized by dividing `(signed input_integer << 56)` by
that positive root, retaining a 96-bit Q24 intermediate. RMS then multiplies
by the signed 96-bit unit-offset weight `(2^24+weight_integer)` without
premature saturation, rounds Q48 to Q24, and saturates only the final output.
L2 uses a unit multiplier. A zero L2 denominator emits all zeros without
division. Invalid counts produce a held error output and no vector loading.

Latency is count input-acceptance edges, one denominator setup edge for L2
or 26 setup/division/save edges for RMS, then 80 root edges.
Each nonzero-root output requires 26 preparation/division/weight-save edges;
a zero-root output needs one preparation edge. Add arbitrary
input/output stalls. Result, index and last are held registered/stable while
stalled. Vector memories are not reset because every selected element must
be loaded before reading; reset discards all previous state.

### Matrix execution and shared resources

`anvil_e1_matvec` loads exactly `start_cols` Q8.24 values into a bounded
MAX_INPUT vector, then reads every row-major weight over the shared memory
command/result interface. Each returned weight is held for a distinct PRODUCT
edge driving the shared MAC. Column zero clears and accumulates concurrently.
After the final product edge, PREPARE captures `mac_rounded` on the next edge;
OUTPUT holds that row's result/index/last until accepted. It then begins the
next row without reloading input. No per-product rounding occurs. Invalid
dimensions/alignment error 1, extent overflow error 5 and memory error 3 lead to
a held completion. Earlier internal row results are provisional; the sequencer
must not treat these as public success embeddings. MAX_INPUT is 1..65535.

There is deliberately no private MAC in the attention, matrix or RoPE executor.
Each has `mac_clear`, `mac_accumulate`, operand and result ports. The
sequencer grants exclusive resource ownership throughout each operation,
multiplexes these ports onto one `anvil_e1_mac`, and similarly arbitrates the one
nonlinear engine, norm unit and memory bridge. A memory command accepted by the
bridge remains outstanding until its held result is retired; ownership must
not change between those handshakes.

### RoPE execution

`anvil_e1_rope` rotates one split-half pair supplied by the sequencer. Its
`start_pair` is i, not the index of a head or token. It rejects zero/odd D and
i>=D/2. It forms the Q40 exponent
`-round_even(ln(theta)_Q40 * 2*i / D)` with ln(10000)=10126876334763 and
ln(1000000)=15190314502144 in Q40. It uses the nonlinear engine's documented
ln(2) constant, floor binary range reduction and 18-term Q40 exponential
recurrence without passing the frequency through Q24. The resulting frequency
is right-shifted by the binary exponent, multiplied by the **absolute** 32-bit
position in 96 bits, and reduced modulo Q40 2*pi to [-pi,pi].
Only then is the angle rounded ties-even to Q24 and submitted to the shared
sin/cos engine. This preserves phase precision for large valid positions.
The final two rotations use two full two-product MAC reductions, each rounded
and saturated once: lo*cos-hi*sin, lo*sin+hi*cos.

Frequency generation starts with two chained divisions (rounded exponent,
then floor ln(2) reduction), followed by 18 series iterations of 26 edges
each and a 26-edge angle-remainder/rounding operation. The angle is
registered 544 edges after pair acceptance. Each sin/cos
transaction follows the nonlinear handshake/latency above. Each rotation
uses two product edges and a separate capture edge. Pair outputs/error remain
registered until accepted. Frequency right-shift is a truncation at Q40,
not an unspecified Q24 frequency-table approximation.

### Attention execution

`anvil_e1_attention` executes one query/head per start. It first reads D query
values and the query's absolute position. Query and K/V bases refer to whole
scratch regions. Contiguous groups map as
`kv_head=head/(Q/KV)`, selecting local or full D/KV independently. Three passes
read key masks and, for local layers, key positions. The unsigned 33-bit
absolute difference must be strictly below SLIDING_WINDOW. Full layers are
bidirectional and impose no causal position constraint.

Pass zero reads each eligible K head, uses the shared MAC for its complete
dot product and finds the maximum scaled Q24 score. Score scaling uses
`floor(sqrt(D*2^80))`, a constant Q40 root computed with 64 radix-four steps at
elaboration; the Q48 MAC sum is shifted left 16, divided by that root with
ties-even rounding, and saturated once to Q24. Pass one recomputes scores,
subtracts the maximum in 96 bits, skips differences strictly below -16, and
sums the shared exp results in signed 96-bit Q24. At -16 exp is evaluated,
not skipped. Pass two again recomputes scores/exp and reads eligible V
components; each exp*V product comes from the shared MAC with clear asserted,
then its unrounded Q48 sum is added to a bounded D-entry array of 96-bit
weighted sums. FINISH divides each weighted sum by the Q24 denominator with
ties-even rounding and signed saturation. This combines softmax division
with weighted reduction without premature rounded probability values.

An empty eligible-key set yields a zero head vector without division. All
head outputs are prepared before output handshakes; memory error 3 or malformed
mask error 2 terminates without head output. Caller-supplied positions, bases
and token ranges must already have passed controller validation. Masks are
rechecked when read. The host's no-mutation obligation is essential.

For K eligible keys and head width D, three passes request 3*K*D K words,
the final pass requests K*D V words, and all three passes request N masks.
Local layers additionally request one key position per valid key per pass.
Initial Q reads cost D words plus one query-position word. There is no N*N
score buffer. Each dot product has one PRODUCT edge per component followed
by a 26-edge SCORE/division/save operation after the last product.
Each nonzero-denominator FINISH channel likewise takes 26 edges, while a
zero-denominator channel takes one edge. Each weighted-V component has a PRODUCT
edge and a distinct WEIGHT accumulation edge. Registered memory bridge
latencies and nonlinear handshakes dominate these variable-duration loops.

### Pool execution

`anvil_e1_pool` consumes all N*E projected token words in token-major,
channel-major order. `token_mask` is sampled at channel zero and retained
for that token; masked words are consumed but not summed. It verifies that
the number of valid tokens equals `start_valid_tokens`. CLEAR zeroes E
96-bit Q24 accumulators one per edge. MEAN divides only the selected leading
channels by that positive count with ties-even rounding and saturation.
It then starts the shared norm unit in L2 mode for exactly the requested
dimension, loads those means and buffers every normalized result before
emitting any output. The unit-offset RMS weights are not used for L2.
The norm unit's zero-denominator behavior implements successful zero pooling.

Legal reduced dimensions include E/6=1; the single-element result is captured
directly from the norm output on its acceptance edge. OUTPUT holds a separate
registered data/index/last word until accepted; DONE holds a completion.
E-word clearing, N*E input transfers, 26 mean/division/save edges per selected
channel, selected-dimension norm load/capture
loops and the norm latency above precede output. Invalid descriptors report
1, zero valid count reports 4, and an inconsistent mask count reports 2.

Required acceptance
remains GELU <=2e-4 on |x|<=8, exp <=2e-6 on [-16,0], sin/cos <=2e-5,
reciprocal/rsqrt relative error <=2e-4 where representable; none is presumed
achieved by this source increment.

## Controller submission and top-level integration

The implemented controller accepts/latches descriptors only on
job_valid && job_ready. Busy spans compute, output retirement and done
retirement. Each embedding word and completion has its own registered holding
stage. No new job precedes completion acceptance. Reset discards active work
and queued outputs. Error codes remain 0 success, 1 descriptor, 2 invalid
token/position/mask, 3 memory, 4 all masked, 5 address overflow. The sequencer finishes all potentially failing memory/computation
before supplying its first embedding word: the controller cannot retract a
word already retired. The pool buffers the final vector for this purpose.
No engine start is issued for invalid descriptors, invalid input entries or
all-masked input. The controller's START handshake carries immutable latched
descriptors and valid-token count, then RUN accepts engine words into a
one-word registered holding stage. It accepts engine completion only when
that holding stage is empty and no new engine embedding is presented.
The engine must not send words with an error completion. Controller validation
has one CHECK edge followed by three ordered memory reads per token.
Its DONE stage keeps the error/status stable until retirement.

Controller parameter diagnostics reject V,H,P,I,L,Q,KV,D,maxSeq <=0,
E not divisible by six or E>65535, odd head D, and Q not divisible by either
KV count. Larger restrictions, if needed by counter widths, must be documented
and rejected rather than clamped. H,P,I,D,L,Q are limited to 65535 by vector
interfaces; Q*localD and Q*fullD must each be <=65535. This bounds a complete
attention vector for matrix input loading. E is 6..65535 and divisible by six.
The attention executor additionally rejects nonpositive window and odd D.
Top-level diagnostics use a legal-datapath generate branch. Illegal combinations
instantiate no compute modules and emit `PARAMETER ERROR` with `$fatal` at
simulation startup; constant outputs in that branch are not an inference mode.
Compile-time rejection is also allowed.
Advisory lesson exp-6d5cc92e6f5a86894eaae275 applies when constructing legal
datapath generate guards; past evidence is not this project's acceptance.

## Ownership and reproduction

Designer owns `rtl/*.sv`, `design/*.md` and `design/pack_model.py`.
Verifier owns all tests, independent references, functional simulation,
primitive sweeps, the nine-run matrix, scoreboard negative control and real
Yosys checks. No such checks have been authored or run by Designer.
Dependencies are the existing Python3, Icarus/vvp and Yosys tools; do not
install missing tools. Final reproduction commands and exact dependency
versions must be documented from the actual independent results, not invented.

## Integrated sequencer and operation traceability

`anvil_e1_top` connects the controller, the single registered external-memory
bridge and the hardwired sequencer. The sequencer instantiates the live matrix,
attention, RoPE, norm, nonlinear, MAC and pool executors. These twelve RTL
files each define exactly one module. Phase 2 adds the thirteenth file,
`anvil_e_top.sv`, containing only the wrapper module. All `rtl/*.sv` files are required.
There is no host-computed operation callback, external arithmetic service,
inference bypass, real-valued RTL arithmetic or checkpoint-sized internal array.

The controller owns memory during descriptor/input validation. A registered
`engine_owner` changes only at engine-start acceptance and engine-completion
acceptance. Within the sequencer, the operation FSM owns memory, MAC and
nonlinear resources for the full matrix, attention or RoPE transaction.
Its scalar read/write FSM owns memory for vector transfers and RMS weights.
The norm resource belongs to the sequencer for transformer norms; only the
final `POOL_WAIT` state grants it to pooling. Pooling can remain in LOAD while
final token norms/projections are computed, but cannot start normalization
until all tokens are consumed. Thus no norm transaction overlaps another owner.

The hardwired `pc` labels are sequencing state, not externally supplied code.
The bindings below cover all five globals and all seventeen layer suffixes:

| Sequencer PC | Operation and tensor binding |
|---|---|
| 0..3 | Read ID, `embed_tokens`, sqrt(H) scale, store initial X |
| 4..8 | Each layer's rows of `ple.per_layer_model_projection`, divide by sqrt(H), `ple.per_layer_projection_norm`, store token/layer PLE |
| 9..11 | Read absolute position, load X, `input_layernorm` |
| 12..16 | `q_proj`, each head's `q_norm`, split-half RoPE, store Q |
| 17..21 | `k_proj`, each head's `k_norm`, split-half RoPE, store K |
| 22..24 | `v_proj`, store V; finish all tokens before attention |
| 30..35 | Load residual X, every query head's attention, `o_proj`, `post_attention_layernorm`, saturated residual addition |
| 36..43 | `pre_feedforward_layernorm`, `mlp.gate_proj`, GELU, `mlp.up_proj`, element product, `mlp.down_proj`, `post_feedforward_layernorm`, residual |
| 44..50 | `ple_block.per_layer_input_gate`, GELU, load distinct PLE vector, element product, `per_layer_projection`, `post_per_layer_input_norm`, residual |
| 51..54 | Read/apply `layer_scalar`, store next X; swap X regions after all tokens |
| 58..65 | Start pool, load final X, global `norm`, `embedding_projection`, read explicit mask, feed all E channels |

All tokens, including masked queries, execute the transformer. Keys remain
mask-selected, and masked tokens never enter the pooling sum. This avoids
storing an on-chip sequence mask. A masked query with no eligible valid keys
gets the attention executor's defined zero vector. The initial global PLE
projection is computed P rows at a time for each token/layer, avoiding an
L*P internal vector and preserving the independently configurable P width.

Five bounded working banks hold residual X, normalized input, matrix output,
GELU gate and attention/up/PLE operands. Each bank has
`max(H,P,I,E,Q*max(localD,fullD))` signed 32-bit entries. The address-generator
loop has compile-time layer bounds, not sequence-sized storage. Working banks
are written before use; reset invalidates sequencing instead of clearing them.

Bank writes use one shared combinational address/data/destination intent,
decoded into five per-bank enables and consumed by dedicated positive-edge
storage processes. State-specific operations no longer expand bank-storage
assignments inside the clocked controller. Read functions remain combinational;
writes remain nonblocking at their operation-retirement edge with no extra
bank holding stage. Projection scaling now retires in PROJECTION_SAVE after
its iterative divider, rather than in VECTOR. RoPE additionally drives a second temporary
bank write intent: both split-half results commit on the same edge, retaining
second-write priority if the addresses coincide. Reset suppresses all write
intents without clearing bank contents. Arithmetic, error checks, operation
boundaries and resource ownership are unchanged. This restructuring addresses
the task-expanded bank-write paths identified in
`evidence/preparation/verifier-process-subset-repair-20261014T2255/receipt.json`;
it is not a demonstrated functional-defect repair or a measured speedup.
Independent functional and synthesis checks remain required.

Embedding scaling uses `floor(sqrt(H*2^80))` (Q40), a 96-bit product,
ties-even Q40 shift and Q24 saturation. Global PLE matvec first finishes its
complete dot with the matrix unit's Q24 rounding/saturation, then divides that
Q24 result by the same Q40 root using a 96-bit numerator shifted by 40 and
ties-even division. This is an explicit operation boundary, not algebraically
fused scaling. Residual additions use signed 96-bit addition and Q24 saturation
without an extra rounding step. Element products and layer-scalar products use
the shared MAC for one full product and capture its rounded result on the
following edge. Each GELU element uses the shared nonlinear transaction.
The independent fixed-point reference must retain these operation boundaries.

Each dispatch consumes one edge to latch an operation descriptor. Scalar
memory transfers have separate REQUEST and RESPONSE states, in addition to
the bridge's registered request/result stages. Norm feeds each value only
after its weight read retires. Matrix input loading has one accepted element
per edge, then its documented weight/product/output loop. Embedding scaling
and residual addition take one VECTOR edge per element. PLE projection
division takes VECTOR launch, 24 DIVIDE edges and PROJECTION_SAVE, 26 edges
per element. Pointwise
multiply takes VECTOR selection, PRODUCT, then SAVE, three edges per element.
GELU takes a VECTOR selection edge plus its request/response handshake and
documented series latency. RoPE pairs and attention heads start on separate
acceptance edges, and their outputs are checked/captured before the next
operation is dispatched. Loop transitions and scratch-base latching add edges.
Stalls affect every handshake; there is no fixed overall inference latency.

Every read and write error aborts before final output. Internal row/head results
are provisional and never directly become public embeddings. After an error
result is consumed, the sequencer enters one FLUSH edge, asynchronously resets
its executors to discard incomplete work, then holds DONE with the original
error. The external bridge is not locally reset: its outstanding request has
already retired. This also releases a pool interrupted during final projection,
so subsequent jobs do not inherit a partial pool or norm transaction. Only a
fully buffered successful pool vector can assert public embedding validity.
There are no memory requests after output begins. The controller additionally
holds each word and defers completion until its last held output retires.

From an integration host: assert reset and flush/reset the fabric, deassert
reset, wait for job_ready, hold all descriptor fields stable through the
job_valid/job_ready acceptance edge, then service ordered memory requests
and responses. Keep weights, IDs, positions and masks immutable until done
retirement. Accept indexed embedding words only on emb_valid/emb_ready;
accept completion on done_valid/done_ready. A reset discards the job, output
and completion rather than producing an error completion.

Static syntax/elaboration command from the delivered root:

```
iverilog -g2012 -t null -s anvil_e_top rtl/*.sv
```

Independent reproduction entrypoints remain:

```
python3 tests/verify.py --check architecture --output evidence/verification/architecture --timeout-s 50
python3 tests/verify.py --check functional --seeds 17,89,203 --configs A,B,C --output evidence/verification/functional --timeout-s 200
python3 tests/verify.py --check sensitivity --output evidence/behavior/negative_control --timeout-s 20
python3 tests/verify.py --check synthesis --configs A,B --output evidence/verification/synthesis --timeout-s 120
```

These Phase 2 commands are the admitted Verifier contract, not
Designer-executed results or a claim that the new Verifier-owned functional
and sensitivity entrypoints already exist. The original behavior runner and
its coverage must be retained within the functional check. Check-level outer
timeouts are respectively 70,220,40,140 seconds; the inner allowances above
are phase-wide, including every child, and must not be renewed per job.

## Retained static diagnostics

The initial four-module diagnostic remains at
`evidence/preparation/static-foundations-20261014T214217/receipt.json`.
The continuation ran one additional bounded `iverilog -g2012 -t null`
command over the ten currently retained RTL files, including the controller's
address-generator instance. It exited 0 without a timeout or compiler
diagnostic. Exact argv/cwd, compiled-source SHA256 identities, start/end times,
15-second watchdog and raw tool-version/stdout/stderr paths are retained at
`evidence/preparation/static-executors-20261014T215139/receipt.json`.
There was no failed probe or demonstrated hardware defect in this continuation.
That historical ten-module diagnostic did not elaborate a top, which was absent
at that time. The integration continuation saved the sequencer and top but did
not run a fresh static check: its budget preflight refused to start because the
watchdog, cleanup and handoff reserve no longer fit. No probe directory or
receipt was created, and no compiler failure or success is claimed for these
new sources.

Verifier subsequently retained default-top elaboration at
`evidence/preparation/verifier-default-20261014T2206/receipt.json` and a
2,106-case primitive diagnostic at
`evidence/preparation/verifier-primitives-parser-repair-20261014T2208/receipt.json`.
The latter reported 512 sin/cos accuracy failures caused by unsigned
concatenation arithmetic in negative-angle modulo reduction. The Designer
repair makes that operand explicitly signed; constants, rounding, recurrence,
latency and interfaces are unchanged. The original parser failure remains at
`evidence/preparation/verifier-primitives-20261014T2208/receipt.json`.

One bounded default-top `iverilog -g2012 -t null` elaboration after this RTL
repair exited 0. The existing execution helper retained exact argv/cwd,
source hashes, tool versions, timing, timeout/exit status and raw logs at
`evidence/preparation/static-signed-angle-repair-20261014T2209/receipt.json`,
linked to the failing primitive diagnostic. This is static evidence only;
the repaired primitive's numerical accuracy has not been rerun by Designer.
No functional simulation, reference, scoreboard, synthesis or accuracy check
was authored or executed by Designer. Primitive accuracy, all nine
functional runs, negative control, packer rejection tests and synthesis remain
independent acceptance gates, not conclusions from compilation.
