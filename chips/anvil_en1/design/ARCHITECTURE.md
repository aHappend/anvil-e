# Anvil-EN1 architecture and implementation status

The admitted representation combines zero-copy owner aliases with exact on-chip
owner rematerialization. Aliasing alone is insufficient for the E4B reduction.
`SPEC.md` freezes the geometry, tensor-image ABI, BF16 operation boundaries,
registered protocols, storage accounting, and unchanged acceptance criteria.

## Connected design target

`anvil_en1_top` must select the immutable parent top for model 0 and the native
descriptor/controller path for models 1/2. A single registered memory arbiter
is the only external master. Native arithmetic consumes read-only tensor images
and original inputs and does not spill generated state.

The required cache instance owns the one canonical owner map and resident tags.
Its actual aligned-pair regen request goes to owner_replay, which either reads
a valid local anchor ring, projects from a preserved ordinary frontier, or
executes bounded Eval continuation/memo replay. The attention/PLE engine
consumes cache fetch responses and performs Q, masks, softmax, values, residual
norms, double-wide E2B GeGLU, gated PLE, scalar, and final softcapped logits.
CSR counters observe accepted work, not intended traffic.

| Producer guarantee | Consumer dependency |
| --- | --- |
| Descriptor immutable after E0 | No engine uses changing job pins |
| Tensor directory validated before payload access | Arithmetic cannot read an absent shared-layer K/V tensor |
| Cache returns true owner identity | Top and replay do not duplicate alias logic |
| Actual regen pair/error completion | Cache cannot fabricate a miss answer |
| Layer input retained through complete output | Descending causal replay preserves historical dependencies |
| Final-global frontier pinned | Upper shared layers regenerate correct-owner KV |
| Ring has generation/token tags | Wrapped/stale local payload cannot hit |
| Old representation drained/freed | Fallback allocation never overlaps ordinary allocation |
| Memory request and response retirement registered | Error/reset cannot leak late work into a new session |
| Actual accepted-transfer accounting | KV traffic savings cannot be inferred from alias counts |

## Storage and physical implementation

Production ordinary frontier reservation is 3 MiB, with only padded occupied
words counted in live payload. The separate local ring reserves enough for
512 tokens, 2 selectors, 2 E4B heads, and 256 BF16 components: 1 MiB.
E2B occupies half that head capacity. Native reconstruction scratch is
phase-limited by M in SPEC, not another unbounded activation archive.

Fallback overlays ordinary frontier/ring storage with at most 1 MiB of frames,
memo, scalar continuations, arithmetic, and resident state. Metadata and
physical RAM reservations are disclosed independently of the live ledger.
Large payload arrays require synchronous registered reads and writes, validity
metadata rather than clearing every word on reset, collision-safe port ownership,
and M20K inference. Physical packing, fragmentation, and fit are future
synthesis/Quartus observations, not established by byte formulas.

The resident cache is deliberately small (4*C live payload bytes, C<=64).
A balanced associative comparison/selection network replaces a linear
priority chain. Tags may be implemented as small metadata registers; the
payload read is registered. Hit lookup is F0/F1/F2. A miss has variable
latency dictated by real replay. Replacement wraps by terminal comparison,
including the non-power-of-two capacity 3.

An invalidate request closes data ingress immediately at its acceptance.
Previously valid stalled payloads cannot change. Outstanding regen descriptors
remain stable until accepted; cancelled completions are drained without
insertion. The barrier acknowledgement follows retirement and tag invalidation.
This prevents generation cancellation from silently breaking ready/valid.

## Numerical implementation target

A folded shared binary32 primitive engine separates multiplication from
accumulation and uses ascending reduction indices. BF16 materialization is
exactly at the SPEC boundaries. Divider, reciprocal/root, transcendental,
projection, and attention loops are bounded FSMs with registered continuations.
Replay control is an explicit stack, not combinational recursion or recursive
module elaboration. Streaming MLP rows avoid a J-wide frame allocation.

Ordinary replay and fallback must be implementations of the same numerical
model. The independent reference must retain all logical-layer states and
schedule differently; it must not reproduce the descending overwrite algorithm
as its sole oracle. Native vision is bidirectional and reconstructs rather than
overwriting causal-style; native audio preserves pinned chunk/conv boundaries.

## Performance claims and evidence boundary

There is no throughput or long-context latency guarantee. Replay may cause
enormous owner computation and increased weight/input traffic. Report those
costs, memo evictions/hits, fallback jobs, and actual live allocation. Zero
native external KV bytes is a requirement, not a current measurement. Strict
<45% live and accepted-traffic ratios are independently required for each model.

The five domains remain text, image+text, audio+text, combined image/audio/text,
and long-context shared-KV. Synthetic fixtures measure hardware behavior, not
checkpoint quality. No timing, synthesis, hardware, functional, numerical,
mutation, benchmark, or engineering-acceptance result is presently claimed.

## Current source increment

The saved first increment remains intact: canonical geometry helpers,
resident/metadata cache, binary32 add/multiply/format primitive, and CSR.
This continuation adds these design-owned leaves:

| Source | Implemented role |
| --- | --- |
| `rtl/anvil_en1_fp32_divsqrt.sv` | Restoring binary32 division, digit square root, once-rounded reciprocal square root, exceptional-value handling |
| `rtl/anvil_en1_uint_to_fp32.sv` | Iterative unsigned32 normalization and RNE conversion |
| `rtl/anvil_en1_exp.sv` | Registered range reduction and folded degree-8 exponential polynomial |
| `rtl/anvil_en1_activation.sv` | Exponential/divider-connected tanh, GELU_tanh, SiLU and sigmoid |
| `rtl/anvil_en1_norm.sv` | Ascending streamed RMSNorm/LayerNorm, optional learned scale, accepted BF16 output stream |
| `rtl/anvil_en1_weight_read.sv` | Bounded aligned BF16/Q4 row addressing, FP16 scale/nibble decoding and real memory-error retirement |
| `rtl/anvil_en1_projection.sv` | On-chip-source-connected folded multiply/add reduction and final BF16 materialization |
| `rtl/anvil_en1_tensor_shape.sv` | Complete text/vision/audio/original-input directory geometry and clipping-scalar membership |
| `rtl/anvil_en1_tensor_image.sv` | Full image/schema validation, exact tensor extents, pairwise duplicate/overlap checks, validated lookup descriptor |

The projection connects its weight reader and arithmetic primitive. The norm
connects its length converter, arithmetic primitive and reciprocal-root
engine. Activation connects real exponential, add/multiply and divider
engines. Tensor lookup connects the complete geometry schema. These are
substantive leaf hierarchies, not a connected accelerator top.

Reciprocal root rounds the mathematical reciprocal root once rather than
composing two rounded primitive results. The implementation reduces its
normalized rational radicand by 78 restoring steps before 27 root digits,
retaining both remainder classes for the final RNE decision. Exponential and
activation coefficients remain subject to independent numerical comparisons;
their presence is not a threshold pass.

Projection/norm request source components from a caller-owned immutable on-chip
vector. Neither allocates a private vector or writes it externally. The tensor
lookup holds only a header, current entry, six prior-entry words and bounded
scalar control. Its pairwise rereads avoid a directory-sized private archive,
but introduce quadratic immutable-input/weight work. The weight reader also
rereads Q4 scales/packed words. Count every accepted read; no total-traffic or
latency improvement is asserted.

The remaining sin/cos and frequency/rotary arithmetic, stable attention,
GeGLU/PLE/layer controller, owner replay/frontier/ring/continuation-stack/memo
allocator, native vision/audio execution, generation-safe memory arbitration,
actual allocation accounting, and parent-compatible top remain to be
implemented and connected. The pinned global proportional and vision
multidimensional RoPE formulas are frozen in SPEC before their RTL.

The parent RTL remains unchanged. No verification source exists in this
increment and none was authored by Designer. Independent Verifier owns
`tests/*`, including all six unchanged suites. The single optional Designer
static elaboration check has not been used. There are no preparation probes,
receipts, functional execution, numerical comparisons, simulation results,
or synthesis results from either design increment. The new leaves have not
yet been statically elaborated; the optional single check is reserved for
the complete design handoff. There are no retained diagnostic failures to
repair in this continuation, and no physical timing/resource result.

Do not hand this increment to verification as a ready design. Continue from
these saved sources under an independently admitted continuation; never
replace it with an older checkout or treat this status as a waiver.
