# Phase 2 official-weight integration contract

## Scope, ownership and source authority

This document specifies integration and independent verification, not measured
results. Phase 2 preserves the twelve inherited `anvil_e1_*.sv` modules and
`design/pack_model.py`. The only new RTL is `rtl/anvil_e_top.sv`: one
synthesizable `anvil_e1_top` instance named `core`, forwarding every parameter
and public port without arithmetic, buffering, state or extra latency.
Both top names retain the defaults, errors, precision, scratch layout and
forward equations in [ARCHITECTURE.md](ARCHITECTURE.md).
The narrow RMS-epsilon revision below changes only the denominator constant
in the shared `rtl/anvil_e1_norm.sv`; it adds no interface, mode or latency.

The explicit revision and parent contract require the complete adopted
transformer equation sequence, including every tensor family. Supplied shape
manifests are not executable evidence of the upstream forward implementation.
Repository provenance and historical parent results do not certify this
changed product. No linked repository-intake source index was supplied.
Independent current-source checks are required.

The immutable supplied inputs are:

* `hf_embeddinggemma2_spec/official_weights/google_embeddinggemma2_official_slice.safetensors`
* `hf_embeddinggemma2_spec/official_weights/official_weights_manifest.json`
* `hf_embeddinggemma2_spec/official_weights/official_hardware_slices_fp32_q824.json`

The manifest declares 55 extracted tensors: five text globals, seventeen
tensors each for text layers 0 and 5, and sixteen unrelated vision tensors.
Only those 39 text tensors supply inference coefficients. Vision tensors
(including `embed_vision.*`) are explicitly excluded from execution; audio
execution is also excluded. The report must list actual exclusions.
Several tensors are partial: embeddings load only [256,512], global PLE loads
[256,512], and several matrices load only 64 output rows. This is not a
complete 24-layer checkpoint, original-geometry inference, application-level
embedding-quality assessment or parity with an executable upstream model.

No weights are downloaded, synthesized, rescaled or selected by achieved
accuracy. Missing source coordinates or inconsistent provenance are failed
prerequisites, not permission to fabricate coefficients or drop a test.

## Deterministic reduced mapping

Use inherited configuration A, in the existing field order:

```
V=16,H=4,P=4,I=8,E=6,L=6,Q=2,
localKV=1,fullKV=1,localD=2,fullD=4,window=2,maxSeq=8
```

Hardware layers 0,1,2,3,4 each use the entire tensor family from official
text layer 0; hardware layer 5 uses official text layer 5. The first five
are deliberate repetitions of one supplied trained layer, not independently
supplied layers. Hardware layer 5 is full attention; the others are sliding.
All reduced matrix coordinates are leading rows and columns. For destination
matrix element `[r,c]`, read source BF16 element
`r*loaded_shape[1]+c`, never a contiguous flattened prefix of the source.
The source tensor starts at `8+header_length+data_offsets[0]` in the local
safetensors file, with two bytes per BF16 element. The following ranges
are half-open and completely determine the mapping.

For globals, prepend `language_model.` to each suffix:

| Suffix | Original shape | Loaded shape | Reduced shape and source selection |
|---|---|---|---|
| `embed_tokens.weight` | [262144,512] | [256,512] | [16,4], rows [0,16), columns [0,4) |
| `embedding_projection.weight` | [768,512] | [768,512] | [6,4], rows [0,6), columns [0,4) |
| `norm.weight` | [512] | [512] | [4], coordinates [0,4) |
| `ple.per_layer_model_projection.weight` | [12288,512] | [256,512] | [24,4], rows [0,24), columns [0,4) |
| `ple.per_layer_projection_norm.weight` | [512] | [512] | [4], coordinates [0,4) |

Reduced PLE rows `[l*4,(l+1)*4)` belong to hardware layer `l`.
In particular hardware layer 5 uses original global PLE rows [20,24),
not original full-model layer-5 rows [2560,3072), which are unavailable.
The global PLE matrix is not remapped using the layer-family repetition.
Every layer retains its distinct projected PLE input.

For layers prepend `language_model.layers.s.` with `s=0` for hardware
layers 0..4 and `s=5` for hardware layer 5. Below, paired shapes mean
source layer 0 / source layer 5. Matrices select leading destination-sized
rows/columns; vectors select the indicated leading coordinates.

| Suffix | Original shape | Loaded shape | Reduced local / full shape |
|---|---|---|---|
| `input_layernorm.weight` | [512] | [512] | [4] / [4] |
| `layer_scalar` | [1] | [1] | [1] / [1], unchanged |
| `mlp.down_proj.weight` | [512,2048] | [64,2048] | [4,8] / [4,8] |
| `mlp.gate_proj.weight` | [2048,512] | [64,512] | [8,4] / [8,4] |
| `mlp.up_proj.weight` | [2048,512] | [64,512] | [8,4] / [8,4] |
| `ple_block.per_layer_input_gate.weight` | [512,512] | [64,512] | [4,4] / [4,4] |
| `ple_block.per_layer_projection.weight` | [512,512] | [64,512] | [4,4] / [4,4] |
| `ple_block.post_per_layer_input_norm.weight` | [512] | [512] | [4] / [4] |
| `post_attention_layernorm.weight` | [512] | [512] | [4] / [4] |
| `post_feedforward_layernorm.weight` | [512] | [512] | [4] / [4] |
| `pre_feedforward_layernorm.weight` | [512] | [512] | [4] / [4] |
| `self_attn.k_norm.weight` | [256] / [512] | [256] / [512] | [2] / [4] |
| `self_attn.k_proj.weight` | [512,512] | [64,512] | [2,4] / [4,4] |
| `self_attn.o_proj.weight` | [512,1024] / [512,2048] | [64,1024] / [64,2048] | [4,4] / [4,8] |
| `self_attn.q_norm.weight` | [256] / [512] | [256] / [512] | [2] / [4] |
| `self_attn.q_proj.weight` | [1024,512] / [2048,512] | [64,512] | [4,4] / [8,4] |
| `self_attn.v_proj.weight` | [512,512] | [64,512] | [2,4] / [4,4] |

Per-head q/k norm vectors are shared across the corresponding reduced heads,
as in the parent equations. No neutralized norms, scalars or branch matrices
are allowed. Matrix output widths remain Q*D until `o_proj`.

Verifier records each destination name/shape, source name, original/loaded
shape, row/column or vector ranges, stride, layer map and source hashes.
Hash the mapping serialization, Q8.24 image and address inventory. Pack the
five globals lexically, then destination layers ascending and suffixes
lexically; each selected element is signed little-endian four-byte Q8.24.
This creates 107 destination tensors (5+6*17), not a default 413-tensor
checkpoint. The host supplies only this image, IDs, positions, masks and empty
scratch. It must not initialize hidden states or expected embeddings for RTL.

No new slice mode is needed in the production packer: Verifier independently
constructs the reduced test image/address inventory from this mapping.
`design/pack_model.py` continues to require all 413 original default tensors
and rejects this partial file. Do not weaken its rejection or shape checks.

## Prerequisite validation

Before inference, Verifier streams SHA-256 of the raw file and requires the
manifest's `extracted_safetensors_sha256`, currently
`3a310d7733a28f533b611eb7525f597303980c2ab2f890487a9a1fcbf0366bfb`.
This establishes local consistency with the supplied provenance, not an
independent retrieval from HuggingFace.

Parse the header length, unique JSON keys and raw BF16 payload directly.
Validate every manifest entry, count, dtype, original/loaded shape, local
offset, payload extent and per-tensor SHA-256. Inclusive original HF ranges
must have length `end-start+1` equal to the loaded payload size and lie within
the declared original file. Reject duplicate keys, malformed descriptors,
overlaps, truncated/out-of-range extents and nonfinite text coefficients.
Excluded vision tensor extents and manifest hashes still require validation.
Use loaded strides for local indexing, not original HF file offsets.

Validate every supplied text shape and every FP32/Q8.24 JSON coordinate
against raw BF16 and an independent nearest/ties-even saturated conversion.
The JSON contains further leading-coordinate slices; it is a consistency
cross-check, never an expected-embedding oracle. Required inference coordinates
come from raw BF16. Record exact identities for all supplied inputs and
relevant design/test sources in every check receipt.

## Independent numerical paths

Execute the complete forward equations in ARCHITECTURE.md on both paths:
embedding times sqrt(H); global PLE projection divided by sqrt(H), reshape and
unit-offset RMSNorm; all six transformer layers with input norm, q/k/v,
per-head q/k norms, split-half absolute-position RoPE, grouped hybrid
bidirectional attention, o projection, post-attention norm and residual;
pre-feedforward norm, GELU(gate)*up, down, post-feedforward norm and residual;
GELU(PLE input gate)*projected PLE input, PLE projection, post-PLE norm and
residual; layer scalar; final norm and embedding projection; explicit masked
mean; output prefix selection followed by that prefix's L2 normalization.
Local eligibility is strictly `abs(key_position-query_position)<2`;
full attention sees all valid keys. Local/full RoPE bases remain
10000/1000000 and contiguous grouped-query mapping is unchanged.

The required software path decodes exact BF16 values by placing each raw
16-bit word in the upper half of an IEEE-754 binary32 word, using `struct`.
Define FP32 rounding as `unpack("<f", pack("<f", value))`. Round scalar
multiply/add/divide results, sequential reductions in increasing coordinate
order, nonlinear results and emitted tensor elements to FP32. Dot products
round each product and each accumulator addition, without fused multiply-add.
Apply the same explicit FP32 boundaries to squares, mean reductions,
unit-offset weights, residuals, element products, pooling and L2 reductions.
Round sqrt(H), sqrt(D), RoPE frequencies/angles and other scalar constants
at their software-operation boundaries. Use floating epsilon 1e-6 rounded
to FP32; do not substitute the hardware epsilon. Mathematical sqrt, exp,
sin, cos and tanh may use Python math internally with results rounded to
FP32. GELU uses the documented tanh formula, with FP32 arithmetic boundaries,
not the hardware polynomial/iteration/exp cutoff. Softmax subtracts the
floating maximum and evaluates mathematical exp without the hardware -16
cutoff. No fixed-point input reconstruction, saturation, clipping or
hardware nonlinear emulation is permitted in this path.

A separately labeled binary64 diagnostic or optional BF16-activation
experiment may supplement but never replace that genuine FP32 path.
The inherited `model.py` `fixed=False` mode starts from quantized integers
and remains the inherited quantized-input accuracy reference, not the Phase 2
raw-weight FP32 comparison. Its current-contract mathematical epsilon must be
`281474977/2^48`; Verifier independently updates that default. Retained
epsilon-isolation diagnostics using 17/2^24 remain explicitly historical,
not current-contract reference results.

The independent integer oracle uses the same mapped raw weights, rounded
nearest/ties-even into signed Q8.24 with saturation to
[-128,128-2^-24]. Preserve all documented hardware operation boundaries,
full signed 64-bit products, at least 96-bit complete reductions, Q40
constants, iterative nonlinearities and positive high-precision norm
denominators. Represent epsilon directly at the Q48 mean-square boundary:

```
EPSILON_Q48 = round_ties_even(1e-6 * 2^48) = 281474977
denominator_square = round_ties_even(sum(x_q24[i]^2)/count) + EPSILON_Q48
```

This explicitly replaces quantizing epsilon first to Q8.24 as 17/2^24
(Q48 addition 285212672), without a selectable legacy mode. The shared
normalizer applies the new constant to global PLE projection normalization,
all input/residual-path norms, per-head q/k norms and final RMSNorm.
Complete reduction precision, positive denominator, square-root scaling,
division, unit-offset weighting, rounding and saturation are otherwise
unchanged. Weights, activations and outputs remain signed Q8.24. L2
normalization remains epsilon-free, including successful all-zero output
for a nonempty pooled zero vector without division by zero.

The retained failed official matrix at
`evidence/preparation/phase2-official-matrix/attempt-20261015T081502322745Z/receipt.json`
completed sixteen jobs with exact integer agreement but failed the FP32
maximum-error gate for jobs 12-14. The retained
`evidence/preparation/phase2-epsilon-isolation/attempt-20261015T081805523129Z/diagnosis.json`
isolates the historical epsilon discrepancy using retained outputs, not a
fresh repaired DUT execution. Neither result certifies the revised RTL.
Fresh checks must link to the failed matrix with `--repair-of`, retain all
jobs and thresholds, and independently exercise zero/small RMS denominators
that distinguish the two constants while preserving epsilon-free L2 behavior.
No historical receipt or diagnostic is rewritten by this revision.

In particular a PLE matvec rounds/saturates
before division by sqrt(H); a complete MAC reduction rounds only once.
The oracle must not import Designer arithmetic helpers or use DUT internals
as expected results. Retain saturation counts and intermediate diagnostics;
saturation does not authorize clipping the FP32 reference.

## Cycle & Degenerate-Boundary Table

Handshakes use levels immediately **before** a rising edge. The table's
post-edge observations follow registered/nonblocking updates. The wrapper
does not alter any event or add any register.

| Boundary | Pre-edge condition | Post-edge observation / obligation |
|---|---|---|
| Active asynchronous reset | `rst_n=0`, independent of ready/valid inputs | Every public output, including payloads, ready and busy, is zero; work and holding stages are discarded |
| Reset release / first active edge | Reset state is idle; fabric has reset/flushed stale responses | `job_ready=1`; an asserted job may be accepted on the first active edge, otherwise idle persists |
| Descriptor acceptance | `job_valid && job_ready` | Descriptor fields latched, busy asserted, job_ready deasserted; no second acceptance |
| Internal memory command | Internal command valid/ready | Registered public request presented; it was not accepted at this same edge |
| Public request acceptance | `mem_req_valid && mem_req_ready` | Request retires; response readiness becomes eligible; at most one outstanding request |
| Request stall | Request valid, request ready low | Address, write bit and write data unchanged |
| Public response acceptance | Outstanding request and `mem_rsp_valid && mem_rsp_ready` | Data/error captured in registered result stage, not consumed through a zero-latency bypass |
| Internal result retirement | Result valid/ready | Bridge returns idle; writes require responses too |
| Internal embedding capture | Engine embedding valid/ready | Public registered word becomes visible after capture |
| Public embedding stall | `emb_valid && !emb_ready` | Valid/data/index/last stable, busy high, job_ready low |
| Public embedding acceptance | `emb_valid && emb_ready` | That word retires; controller does not replace its holding stage on the same edge |
| Completion hold | `done_valid && !done_ready` | Registered error/status stable; busy high and job_ready low |
| Completion acceptance | `done_valid && done_ready` | Job retires, then idle/job_ready can return; another descriptor was not accepted at this edge |
| Reset with any simultaneous event | Reset asserted during request, compute, output or completion | Reset wins, cancels stages; no completion is manufactured |
| One token / E/6=1 | Valid descriptor, selected prefix length one | One output at index 0 is both first and last; norm output captured on its acceptance edge |
| N=maxSeq, non-power-of-two H/I/E, independent P | Supported geometry and legal bounds | Explicit counters/shape-derived extents; no power-of-two wrapping assumption |
| Local boundary | Position differences window-1 and window | First eligible when key mask=1; second excluded locally but eligible in full attention |
| Zero pooled vector / all masks zero | Nonempty valid population / no valid population | Successful zero vector without reciprocal of zero / error 4 with no embedding |
| Illegal dimensions, odd head width or zero parameter | Invalid geometry or descriptor | Parameter diagnostic or defined descriptor error, never clamping |
| Address end at 2^64 | Exclusive end overflows 64-bit address convention | Error 5, even if the last word alone would fit |
| Simultaneous MAC clear+accumulate | Shared MAC accepts enabled product with clear | New sum contains that product; clear alone produces zero |
| Concurrent bank write intents | Both RoPE pair writes commit | Existing second-write priority retained if addresses coincide |

No input IDs are exempt from validation because they are masked.
MAX_SEQ_LEN bounds both token count and absolute positions; nonzero positions
through maxSeq-1 are legal. Error codes, one-outstanding memory behavior,
descriptor nonoverlap obligations and existing operation latencies are
unchanged. The table introduces no new bypass or pipeline schedule.

## Required execution and comparison artifact

Verifier extends `tests/verify.py` and the existing bounded `Execution`
helper, without moving old acceptance evidence into preparation or overwriting
receipts. Each attempt retains exact argv/cwd, source hashes, actual tool
versions, times, deadlines, exit/timeout/settlement status and raw logs.
Compile actual `rtl/*.sv` with `iverilog -g2012` and simulate `anvil_e_top`
using `vvp`; no host inference callback or result injection is allowed.
Synthesize A and B with `anvil_e_top` as root while retaining substantive
live `anvil_e1_top` descendants. Normalize escaped Yosys hdlname identifiers
without weakening connectivity or hierarchy checks (advisory lesson
exp-0938d18e059b241a4fdfbb2d). Preserve explicit local sibling imports when
needed by the real launcher (exp-6a4baac55d8459da132c8b6a); neither lesson
is current-source evidence.

Official jobs include [2], [2,3], [2,4,7] and
[2,3,4,5,6,7,8,1], each at output dimensions 6,4,2,1. Pair these with legal
nonzero positions, all-valid, mixed and trailing masks. Include window-1,
window and a longer-range valid key distinguished by local/full attention.
Keep back-to-back submissions and memory/output/completion stalls.
No failing job, dimension or channel may be removed from aggregation.

Require complete public trace parsing, exact descriptors/output/completion
counts, ordered indices/last markers, no active X/Z or protocol violations,
and zero signed-word mismatches against the integer oracle. Compare actual
observed RTL words divided by 2^24 with the raw-weight FP32 vectors, not
just integer-oracle vectors. For each job, with FP32 vector f and RTL vector r:

```
cosine = sum(f[i]*r[i]) / (sqrt(sum(f[i]**2))*sqrt(sum(r[i]**2)))
max_abs_error = max(abs(r[i]-f[i]))
mean_abs_error = sum(abs(r[i]-f[i])) / output_dim
rmse = sqrt(sum((r[i]-f[i])**2) / output_dim)
l2_norm_error = abs(sqrt(sum(r[i]**2))-sqrt(sum(f[i]**2)))
```

Every official job requires defined cosine >=0.999 and max_abs_error <=0.002;
nonzero output additionally requires norm error <=0.002. Report both norms
and absolute RTL deviation from unit norm as well as the L2-norm difference.
The inherited 0.02 bound and conditional-cosine exemption do not apply here.
Retain full actual FP32, observed RTL and integer-oracle vectors and exact
mismatch counts.

Let c_job, c_first, c_last and c_done be monotonically numbered accepted
rising edges. Define elapsed cycles through each event as
`c_event-c_job` (accepting descriptor edge excluded, destination edge
included). If reporting inclusive counts too, label them separately as
`c_event-c_job+1`. Total completion cycles C include all memory, output
and completion stalls. Record N tokens, M valid tokens, C/N cycles/token,
C/M cycles/valid-token, N/C tokens/cycle and 1/C jobs/cycle. Record first/last
embedding latencies separately, stall convention and simulation wall time.
A 10 ns clock period, if used, is only a simulation convention:
tokens/second=N/C*100000000 assumes 100 MHz and is not a measured silicon
frequency, throughput guarantee or timing-closure result.

Successful verification generates
`evidence/verification/functional/official_weights_comparison.json`.
Record schema version, producing attempt/receipt identity, input/mapping/image/
inventory hashes, geometry, source coordinate mapping, exclusions, per-job
IDs/positions/masks/dimension, vectors, metrics, thresholds, saturation,
cycle counts and aggregate worst cases across all jobs. Use exact labels
`Software Layer (Official HuggingFace FP32/BF16 Weights)` and
`Hardware RTL Output (Official HuggingFace Quantized Weights)`.
State reduced mapped-slice scope and no full-checkpoint quality or physical
speed claim. This file is generated output, not an input prerequisite or
a Designer-authored passing result.

Keep all nine inherited A/B/C runs at seeds 17,89,203, primitive accuracy
gates, geometry/address/packer rejection tests, reset/error cases and inherited
negative control. Sensitivity freshly executes a successful official DUT job,
passes its unmodified complete trace through the same public parser/scoreboard,
then privately changes exactly one accepted legal embedding word by one LSB.
Only the same scoreboard's `ExactMismatch` at that transaction satisfies the
negative control; parser errors, timeouts or other exceptions fail. Retain the
original identity, altered trace, location and raw rejection diagnostics.

Current design handoff does not implement or execute these Verifier-owned
references, simulations, benchmarks, sensitivity or synthesis checks.
The inherited entrypoint needs functional/sensitivity integration and official
source identities; its historical behavior mode alone is not Phase 2
acceptance. Any new failure requires fresh retained diagnostics and
independent diagnosis, not an unsupported pre-existing-failure label.
