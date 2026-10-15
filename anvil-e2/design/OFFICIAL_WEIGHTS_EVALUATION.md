# Phase 2 bounded official-weight evaluation

## Scope and authority

The current work order authorizes the mounted 55-tensor slice as the bounded
official checkpoint subset. Both this document and `ARCHITECTURE.md` replace
the earlier full-checkpoint missing-coordinate gate with explicit bounded-slice
remapping; this does not establish native full-model
equivalence. The independently admitted amendment now adds a consistently
propagated elaboration-time RMS epsilon parameter. Public pins, memory ABI,
all other arithmetic and synthetic regression fixtures remain unchanged.
Implementation is not a claim that the amended numerical comparisons pass.

`tests/official_weights.py` parses the actual BF16 safetensors payload using
Python standard-library facilities. It validates the complete file digest,
manifest/header agreement, tensor hashes, bounds, shapes, contiguous payload
intervals, original-file range lengths and finite decoded values. The validated
file SHA-256 in the retained diagnostic is
`3a310d7733a28f533b611eb7525f597303980c2ab2f890487a9a1fcbf0366bfb`.
All 55 tensors and 2,566,786 BF16 elements were decoded. Every supplied
FP32/Q8.24 JSON slice is compared with coordinates in that directly decoded
payload; JSON is never the source of forward-pass weights.

Matching these supplied hashes proves consistency with the supplied provenance,
not independently downloaded or pinned remote checkpoint authentication.

## Explicit slice remapping

This is a scaled subnetwork, including explicitly repurposed coordinates. Its
results must not be described as embeddings from the native HuggingFace model.

| Destination | Source selection |
|---|---|
| Vision patch projection | Leading output channels; RGB source columns `channel*256 + dy*16 + dx`, preserving the original patch stride |
| Vision layer engine | Official vision layer 0, reused for each configured iteration |
| Bridge | Leading language output and vision input channels |
| Ordinary token embeddings | Original rows 7, 19 and 31, leading hidden channels |
| BOI / EOI public IDs | Slice embedding rows 0 / 1, respectively; these are **not** the unavailable native special-token rows |
| IMAGE slots | Computed bridge vectors, never an embedding-table substitution |
| Text local / full layers | Official layer 0 / 5, selected by destination layer modulo 6 |
| PLE model projection | Available rows `destination_layer*scaled_PLE_DIM + channel`; not native layer-stride selection |
| Q/K/V and attention O | Leading available projection rows/columns, packed into scaled heads; not distinct native checkpoint heads |
| Final projection and norms | Selected leading channels, retaining actual output rows |

For each consumed value, the comparison artifact records its tensor name and
digest, original/loaded/destination shapes, loaded coordinate, destination row,
base and word offset, original-file byte offset, and original coordinate under
the contiguous-prefix interpretation of the supplied extraction ranges. Each
destination address is `base + 4*(word_offset + row*destination_columns + col)`.
Quantization is signed32-saturating nearest-even `round(value*2^24)`, with
saturation counts recorded per mapping. Source strides are not replaced by
destination strides.

The position payload is loaded as `[2,256,768]`, while its one supplied
original-file range is contiguous. Original shape is `[2,10240,768]`.
Consequently loaded `[1,p,c]` corresponds, under the contiguous-prefix
interpretation, to original `[0,256+p,c]`, **not** original `[1,p,c]`.
The scaled destination column-position axis explicitly uses those available
rows. This remapping is not proof that native column-axis positions were
extracted. The JSON position slice `[16,16]` is checked as leading rows/channels
of the flattened loaded position table. Original tensor base offsets and a
remote extraction operation were not independently authenticated.

## Independent software and RTL execution

`OfficialFixture` supplies two distinct weight representations to the existing
independent tensor-graph interpreter: exact decoded BF16 values for software,
and quantized memory words for the integer oracle and RTL. `OfficialFP32`
rounds dense, RMS, L2, GELU, RoPE, attention, mean, scale, residual and product
outputs to binary32 with `struct`. Reductions and nonlinear evaluation use
Python binary64 `sum` and `math`. Software RMS epsilon remains `1e-6`; official
hardware configurations select `RMS_EPSILON_Q80=128'd1208925819614629175`.
Legacy configurations retain epsilon `17/2^24`. BF16 describes checkpoint storage, not a
claim of native BF16 arithmetic. The synthetic mathematical oracle is unchanged.

The required complete functional check retains the existing synthetic behavior
matrix and all 27 existing fixed official-weight cases below, all with seed 17 and
all three operating modes:

| Configuration | Official output dimensions | Computation |
|---|---|---|
| A | 6, 4, 2, 1 | Existing singleton-hidden, one-vision/one-text-layer configuration |
| C | 12 | Existing scaled 16-vision/24-text-layer configuration |
| D | 768, 512, 256, 128 | Existing two-hidden-channel configuration with 768 output rows |

These 27 cases remain mandatory. Each case uses the existing fixed IDs, masks,
positions and mixed-sign image fixture, not a fixture selected after measuring
error. Configuration overrides, inputs and their hashes appear in the artifact.
All layers, projections, attention, fusion, cached PLE, masked mean, truncation
and post-truncation normalization execute; no external embedding computation
replaces the RTL.

### Predetermined official multi-patch extension

Add B/seed17 vision-only (mode1) and joint (mode2), both with EMBED_DIM=12
and output dimension12, without changing existing B inputs or geometry.
The complete official matrix is therefore29 required cases. The two B cases
are implemented in the verification matrix, but complete passing execution
is outstanding. The retained B vision-only execution failed the numerical
limits as detailed below; joint RTL was not reached. The retained27-case execution is
`evidence/verification/functional/1792080927168812449-166504/receipt.json`.
Its successful execution preceded a substantive official-geometry coverage
rejection, not a simulator timeout or RTL mismatch: all its official images
used 1x1 grids and kernel1. Synthetic B results do not fill that official gap.

Use CONFIGS["B"] unchanged: VISION_HIDDEN=8, VISION_HEADS=2,
VISION_HEAD_DIM=4, VISION_FFN=7, one vision layer, PATCH_SIZE=1,
POOL_KERNEL=3, VISION_SOFT_TOKENS=4, TEXT_LAYERS=6, TEXT_HIDDEN=3,
PLE_DIM=3, TEXT_FFN=5, EMBED_DIM=12, TEXT_Q_HEADS=4,
LOCAL_KV_HEADS=2, FULL_KV_HEADS=1, LOCAL_HEAD_DIM=2,
FULL_HEAD_DIM=4 and SLIDING_WINDOW=2; all other B parameters remain unchanged.
Its 4x5 image grid has20 patches, row positions0..3 and column positions0..4.
Each vision query attends bidirectionally to all20 image keys. The four
row-major kernel3 pooling windows have origins (0,0), (0,3), (3,0), (3,3)
and actual participant counts9,6,3,2, respectively. Thus the fixed fixture
includes nonzero positions on both axes, multi-key vision attention, genuine
multi-participant means and partial edge windows.

Retain the existing seed17 mixed-sign RGB CHW image and input generation.
Vision-only supplies zero text tokens; joint retains IDs7/19/31,
positions1/4/8 and masks1/0/1. Four computed bridge vectors lie between
BOI/EOI, producing six frame slots and joint appended positions7/10/14.
The special-token, source-layer reuse, packed-head, PLE and position-axis
remapping limitations above apply equally to B; its multiple destination
heads/positions do not establish native checkpoint head/axis equivalence.

Verifier must assert the exercised distinct patch positions, multiple eligible
vision keys and multi-participant/partial windows, not infer coverage solely
from a configuration label. Use directly parsed official BF16 operands and
the existing independent FP32/integer graph models with actual public-pin
`anvil_e2_top` simulation. Require zero output-word mismatches and exact scratch
write/address histories, with unchanged cosine, component-error and norm
thresholds below. Record geometry, pooling participants, coordinate mappings,
fixed input hashes, metrics, transcript/receipt links and measured first/final/
completion cycles at10ns. Do not change inputs after observing errors.

The generated public-pin bench compiles all implementation files using
`iverilog -g2012 -Wall` and executes `vvp`. Every output word and every scratch
address/write history must match the Q24-external/Q40-local integer oracle.
Unprovisioned host reads and uninitialized scratch reads fail explicitly.
The official latency benchmark is unstalled: request, embedding and completion
readiness are asserted, and each memory response arrives one cycle after its
request. The separate synthetic regression retains independent backpressure,
reset, error and protocol coverage.

The clock period is 10 ns. Descriptor acceptance to first embedding, final
embedding and completion handshake are measured separately. Reported
nanoseconds equal measured cycles times 10; these are simulated latency, not
physical timing or default-model throughput.

Acceptance retains cosine similarity at least 0.999, maximum absolute component
error at most 0.002, and nonzero-vector L2-norm error at most 0.002. Absolute
software/RTL norm difference must also be at most 0.002. MAE, RMSE, vector
L2-distance and both vector norms are recorded. Required official outputs must
be finite and nonzero. Vector L2-distance is reported separately and is not
misrepresented as the L2-norm error threshold.

## Retained diagnostic observations

### Multi-patch numerical failure and required reconciliation

The subsequent retained Verifier diagnostic is
`evidence/preparation/phase2-official-multipatch-20261015-005/receipt.json`.
B/seed17/mode1/dimension12 completed actual RTL simulation with zero output
word mismatches, 1,118 compared scratch addresses and 1,688 scratch writes
matching the independent integer oracle. Nevertheless, cosine similarity
was 0.9913286747181946 and maximum component error was
0.06919039785861969, failing the unchanged 0.999 and 0.002 limits.
Descriptor-to-first/final/completion intervals were
225074/225085/225088 cycles, respectively, or
2250740/2250850/2250880 ns at the 10 ns simulated clock.
The diagnostic stopped at that failure before joint RTL execution.
This is a numerical acceptance failure, not a timeout or integer/RTL mismatch.

Localization is retained separately in
`evidence/preparation/phase2-official-localization-20261015-006/receipt.json`
and its successor
`evidence/preparation/phase2-official-localization-20261015-007/receipt.json`.
The successor's `localization.json` records matched-input norm call1543:
maximum error 0.03859464247852884 against official software epsilon1e-6,
versus 8.026927389437333e-8 in a diagnostic-only floating counterfactual using
hardware epsilon17/2^24 (1.0132789611816406e-6).
Its input mean square was 1.5529261763884633e-7.
That counterfactual is not the acceptance reference and does not establish
end-to-end success with a changed epsilon. The localization also evaluates
the joint graph in software; it does not supply the missing joint RTL result.

The retained pre-amendment `rtl/anvil_e2_norm.sv` adds
`128'd17 << 56` to the Q80 mean square, exactly as the former arithmetic
legacy ledger required. The supplied `config.json` specifies RMS epsilon1e-6 for
both vision and text. Consequently the retained evidence identifies a
numerical-contract reconciliation requirement, not an established RTL
implementation error that can be repaired while leaving that ledger intact.
Increasing local guard precision alone does not remove a different epsilon.

Independent admission now authorizes the narrow selectable-epsilon amendment
below. Do not change the software epsilon to match legacy hardware, fit a
correction to these outputs, reselect fixtures, relax thresholds or mark the
matrix passed without execution. Preserve all29 required cases and the failed
005/006/007 records, including
`evidence/preparation/phase2-official-localization-20261015-006/receipt.json`.
The amendment addresses the identified definition discrepancy; whether it
repairs the full numerical failure remains independently unverified.

### Admitted selectable RMS epsilon implementation

The top and all participating wrappers/helpers declare the same explicitly
unsigned 128-bit parameter:

```systemverilog
parameter logic [127:0] RMS_EPSILON_Q80 = (128'd17 << 56)
```

The unchanged default is `1224979098644774912`, representing legacy epsilon
`17/2^24`. Official configurations select
`128'd1208925819614629175 = RN(2^80,1000000)`, representing configured
epsilon1e-6 directly at Q80 rather than first quantizing it to an external
Q24 word. This nearest-even conversion is fixed by the admitted model
configuration, not fitted to any output. Selection is made before execution
and never depends on job mode, weight contents, fixture identity or errors.

Only the RMS denominator addition changes:
`D=RN(sum_squares,count)+RMS_EPSILON_Q80`. L2 still uses
`D=sum_squares` with no epsilon. The restoring root
`R=floor(sqrt(D<<64))`, ratio `t=RN(a<<72,R)`, offset-weight multiplication,
rounding, clamping and every Q24 materialization boundary remain unchanged.

| Parameter route | Participating normalization |
|---|---|
| top -> vision_encoder -> shared hybrid engine -> norm | All vision RMS operators, including per-head Q/K |
| top -> text_frontend_ple -> shared hybrid engine -> norm | Initial-vector PLE normalization |
| top -> hybrid_layer -> norm | All text layer and per-head RMS operators |
| top -> pool_norm -> shared hybrid engine -> norm | Final language RMS; final L2 ignores epsilon |

All six corresponding `rtl/anvil_e2_*.sv` files carry the parameter; no RMS
instance relies on an accidental wrapper default when top overrides it.
Patch, spatial bridge and fusion stages contain no RMS. No public port,
memory offset, scratch write, state transition or precision sidecar changes.
Legacy synthetic floating definitions and default integer behavior are
preserved by construction, but fresh regressions must establish preservation.

Designer performs at most one fast static elaboration, not simulation,
reference-model execution or synthesis:

```text
iverilog -g2012 -Wall -t null -s anvil_e2_top rtl/*.sv
```

Verifier must independently implement
parameter-aware integer expectations and compile-parameter conversion, assert
the exact official conversion and unchanged default, exercise every route,
and prove L2 independence. Fresh functional (including all29 official rows),
sensitivity and synthesis checks remain required; synthesis must exercise
parameter propagation rather than discard the override. Preserve failed
receipts and explicitly link the fresh repair execution to them.
No passing amended comparison or engineering acceptance is claimed here.

### Historical singleton-grid diagnostic

`evidence/preparation/phase2-official-benchmark-20261015-003/receipt.json`
records a completed, 51.06-second diagnostic using Python 3.12.3 and
Icarus Verilog/vvp 12.0. Its nine cases cover full output width for each
configuration/mode; prefix cases were not part of that diagnostic.
Its immutable `official_weights_comparison.json` contains all vectors,
coordinate mappings, metrics and transcript links.

| Configuration/mode | Max absolute error | Cosine similarity | Completion cycles |
|---|---:|---:|---:|
| A/text | 2.98023e-8 | 0.9999999999999991 | 4059 |
| A/vision | 5.96046e-8 | 0.9999999999999962 | 5619 |
| A/joint | 5.96046e-8 | 0.9999999999999963 | 10687 |
| C/text | 0.000747561 | 0.999999058824 | 122595 |
| C/vision | 0.000864707 | 0.999998526153 | 165131 |
| C/joint | 0.001997423 | 0.999994639238 | 327410 |
| D/text | 0.000272823 | 0.999998315804 | 37310 |
| D/vision | 0.0000480113 | 0.999999904553 | 39708 |
| D/joint | 0.0000935979 | 0.999999775390 | 71167 |

All nine diagnostic cases had zero output-word mismatches and exact scratch
write agreement. The C/joint component-error margin is narrow; neither its
fixture nor the 0.002 limit was changed. These are preparation observations,
not admission of the complete functional, sensitivity or synthesis checks.
The earlier failed diagnostics in
`evidence/preparation/phase2-official-inputs-20261015-001/receipt.json` and
`evidence/preparation/phase2-official-inputs-20261015-002/receipt.json` are
preserved. Their full-model coverage rejection is superseded by the explicit
bounded-slice authorization; missing native coordinates have not appeared.

## Commands and artifacts

The shared runtime executes `python3 tests/verify.py --check functional`,
`--check sensitivity` and `--check synthesis`; no arguments run all three.
`--check behavior` remains a compatibility alias for complete functional
verification, including official weights. This role does not replace those
checks with preparation results. Interpreted simulations use a 3600-second
child watchdog within the runner's shared execution deadline; an execution
timeout remains a failure, not a numerical rejection or a sensitivity detection.
The current work order grants86400 seconds per complete check, with a1048576-byte
output limit. Historical120-second check budgets and110-second aggregate
watchdogs do not apply to current execution. The larger time allowance changes
neither numerical acceptance nor the admitted fixed pre-execution epsilon
selection. All child work and cleanup consume the same shared deadline.

A focused, retained official-only diagnostic uses:

```text
python3 tests/verify.py --probe official-benchmark --output evidence/preparation/<new-directory>
```

New comparison results must be execution-local beside a fresh receipt from
the existing bounded retention helper. Preserve all existing evidence,
including `evidence/verification/official_weights_comparison.json` and
`evidence/verification/functional/official_weights_comparison.json`; do not
overwrite occupied fixed paths or treat their historical27-case contents as
the new result. Run the material addition through
`python3 tests/verify.py --check functional`, retaining the synthetic matrix
and all27 original official cases plus both B cases. Fresh sensitivity and
synthesis are also mandatory for the amended RTL, including the new parameter.
Top-level `status=passed`
means all listed official cases passed, not that all engineering checks passed.
The complete-matrix field must require all29 cases, including B/mode1 and
B/mode2 at dimension12, rather than only the original A/C/D configurations.
Failed executions retain their failure and any completed rows separately.
Each fresh comparison must record RMS_EPSILON_Q80 with the other parameter
overrides. Its fresh execution receipt and Verifier handoff must identify the
exact execution-local `official_weights_comparison.json`; association with
canonical paths is owned by the shared runtime. Historical comparisons never
certify the amended sources.
The shared runtime owns subsequent independent acceptance and product reporting.
