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

## Preserved source increments

The saved first increment remains intact: canonical geometry helpers,
resident/metadata cache, binary32 add/multiply/format primitive, and CSR.
The saved second increment also remains intact:

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

## Saved third increment

This continuation freezes the new scalar, attention, gated-row and ordinary
storage interfaces/stages in SPEC and adds these design-owned leaves:

| Source | Implemented role |
| --- | --- |
| `rtl/anvil_en1_rope_frequency.sv` | Bounded descending-bit theta root/product/reciprocal evaluation, proportional global zero-frequency selection |
| `rtl/anvil_en1_sincos.sv` | Q44 range reduction, quadrant selection, iterative RNE conversion and separately rounded sine/cosine Horner arithmetic |
| `rtl/anvil_en1_rotary_pair.sv` | Connected frequency/position/trigonometric computation and separately materialized BF16 rotary pair |
| `rtl/anvil_en1_geglu_pair.sv` | Connected GELU_tanh/SiLU/sigmoid, BF16 activation materialization, gated multiply and BF16 product |
| `rtl/anvil_en1_softcap.sv` | Actual divide/tanh/multiply for cap 30/50, selectable BF16 or binary32 boundaries |
| `rtl/anvil_en1_attention_head.sv` | Full permitted-key maximum/sum/value passes, real canonical metadata/fetch channels, stable softmax and streamed BF16 head output |
| `rtl/anvil_en1_gated_projection.sv` | Full gate/up and down-row traversal with streamed regenerated intermediates; matrix/vector/unit up for GeGLU/PLE/audio FFN |
| `rtl/anvil_en1_frontier.sv` | Ordinary padded token-major RAM, complete-vector write commits, entering-layer validity, freeze and explicit capacity-selection response |
| `rtl/anvil_en1_local_ring.sv` | Normalized/rotated local-owner head storage with token/generation visibility, wrapped-slot invalidation and real hit/miss data |

Rotary pair computation consumes actual position and vector inputs, not supplied
trigonometric answers. Global proportional pairs select the prescribed separate
half-head components. The sine/cosine polynomial and finite frequency evaluation
order are documented for independent comparison. In particular, repeated-root
frequency generation is not claimed bit-exact to a host power-library result;
the unchanged production-width rotary comparisons remain mandatory.

The text attention leaf does not allocate a score or probability array.
It scans legal keys for a maximum, recomputes scores for the exponential sum,
then recomputes scores/probabilities per output component before actual V
fetches. Both K and V use the cache's response owner and native address space;
the leaf never reconstructs the logical owner alias map or issues external KV
transactions. Q and masks come from caller-owned immutable on-chip vectors.
Masked keys issue no K/V reads. Child numerical/cache errors retire their
response and stop the head. Completion waits for the accepted final component.
The increased work is deliberately exposed, not counted as avoided computation.

Gated projection recomputes every j intermediate for each down output row.
Its single projection instance executes complete gate/up rows, its GeGLU leaf
materializes the activation/product, and its reader decodes the actual down
weight. PLE uses the same gate/product path with the combined PLE vector rather
than an ungated additive embedding. Construction of that combined PLE vector
and the layer's post norms/residuals remain controller work. Audio's unit-up
SiLU mode is an arithmetic building block, not an implemented audio encoder.

The frontier physically reserves 3 MiB in production. It counts the full
padded occupied allocation, accepts only complete ordered vector writes,
and keeps padding/stale/unfilled vectors unreadable. Layer-tag advancement
stops at the preserved final-global-owner input. A frozen frontier remains
readable and cannot be overwritten. Capacity selection first releases ordinary
visibility/allocation before reporting fallback_needed. That flag is not a
fallback job or a numerical completion.

The local ring reserves 1 MiB in production and accounts E2B/E4B live head
payload separately. A slot wrap clears all its lane visibility before retagging;
each K/V/head lane commits only after a complete ordered head write. Invalid,
stale or unfilled data never turns into a successful payload: legal ring misses
return hit=0 and require actual owner replay. Neither storage leaf has external
memory commands. Their dedicated synchronous RAM processes do not reset payload
words. Per-token visibility/tag storage and physical reservation are separately
disclosed; returned words and arithmetic temporaries still belong in the
complete controller's future workspace ledger.

These leaves are connected internally but not yet a complete accelerator.
Remaining work is owner K/V projection plus learned/unscaled normalization and
rotary tile integration, original embedding/combined PLE reconstruction,
the full attention/PLE/layer controller, frontier/ring scheduling, the explicit
continuation stack and bounded memo/eviction engine, ordinary/fallback RAM
overlay, native vision/audio execution, actual complete allocation accounting,
generation-safe shared memory arbitration, and parent-compatible top integration.
The required literal `anvil_en1_asym_attn_ple`, `anvil_en1_owner_replay`, and
`anvil_en1_top` are not present yet.

The parent RTL remains unchanged. No verification source was authored or
modified by Designer. Independent Verifier owns `tests/*`, including all six
unchanged suites. Actual tools in this increment were view, glob and apply_patch;
no tool installation or execution probe occurred. The single optional Designer
static elaboration check has not been used and remains reserved for the complete
connected design. There are no preparation receipts, functional executions,
numerical comparisons, simulation/synthesis results, or physical timing/resource
results from this continuation. Newly added leaves have not been statically
elaborated. No retained diagnostic failure was overwritten or repaired.

Do not hand this increment to verification as a ready design. Continue from
these saved sources under an independently admitted continuation; never
replace it with an older checkout or treat this status as a waiver.

## Current recovery continuation increment

The saved earlier RTL was retained, not rebuilt from an older checkout. This
increment freezes the owner-tile and embedding/PLE interfaces, numerical
boundaries, cycle tables and scratch lifetimes in SPEC before implementation.
It adds two connected numerical leaves:

| Source | Implemented behavior |
| --- | --- |
| `rtl/anvil_en1_owner_kv_tile.sv` | Actual owner input norm, distinct K/V projections, learned K/unscaled V head normalization, half-head rotary pairing and aligned adjacent BF16 completion |
| `rtl/anvil_en1_embedding_ple.sv` | Actual original token reads, scaled token embedding, internal native-feature ingress, scaled/normalized context PLE and combined identity/context PLE |

The owner tile rejects shared-layer descriptors before directory accesses;
it accepts the actual owner supplied by the cache/controller, not a logical
consumer. It connects the image validator, projection, norm, scale reader and
rotary modules. It normalizes the entering H vector, projects every component
of the selected owner KV head, normalizes the complete D vector and returns
the requested adjacent component pair. V has a distinct projection and no
learned head-scale or rotary operation. K applies the owner's learned scale
and uses two real half-head rotary calls to obtain an adjacent resident pair.
No nonexistent shared-layer projection tensor is read.

The embedding/PLE leaf connects the image validator, matrix reader,
projection, norm, root and primitive FP modules. It rereads an actual original
token ID, validates vocabulary/placeholder selection, and constructs ordinary
text input and the layer's combined PLE from real weights. Modality placeholders
request internal generated native features; the leaf does **not** implement
the required native encoder or permit the host to supply generated features.
Those producers remain necessary above the leaf. Its combined P vector is
the up-vector for the existing GELU-gated PLE projection, not an ungated
embedding residual.

Both leaves use bounded FSMs and synchronous scratch RAM reads/writes.
Their norm output phases overwrite head/P scratch only after complete scalar
reductions. The internal source transactors capture an index, read RAM on the
next edge, then register a held response on the following edge. External
memory-owner selection changes only after the active child's response has
retired. Completion streams obey backpressure and do not complete when their
last beat is merely created. Each leaf has one external transaction outstanding
and emits only read commands.

Production owner-tile payload reservation is 6144 bytes (2560+512 BF16
components); production embedding/PLE reservation is 5632 bytes (2560+256
BF16 components). Compact reservations are 32 and 24 bytes. These are actual
private banks in the saved leaves, not a claim that final top-level RAM has
already been overlaid. The future controller must integrate or refactor these
scratch banks into the admitted phase-overlaid workspace, count all scalar
child/control registers and concurrently streamed copies, and expose complete
allocation/liveness events. Instantiating every leaf's private reservation
alongside a separately allocated full workspace would be a ledger violation.
No complete allocation ratio, M20K mapping, physical fit or timing is established.

The current generational handoff file is now present and reports historical
STA/PPA/HIL as N/A. SPEC distinguishes this from numerical parent signoff
evidence; no historical results were manufactured. Its parent source locator
was made project-relative without changing any N/A quantity.

Remaining implementation starts with the actual complete text-layer
attention/PLE/residual/scalar controller (`anvil_en1_asym_attn_ple`) and the
generation-aware owner-replay scheduler (`anvil_en1_owner_replay`), wiring the
new leaves to correct tagged frontier/local-ring reads and writes. It must
then complete explicit continuation-stack Eval, bounded memo eviction and
regeneration, linear single-token replay, RAM overlay and complete liveness,
native vision/audio encoders and placeholder mapping, sole registered memory
arbitration, session/error/cancellation handling and the parent-compatible
literal `anvil_en1_top`. No required top/replay/layer module or functional
fallback is claimed present by adding these leaves.

Designer changed only the two new RTL leaves and directly related design
documents; the parent reference RTL and verification sources were not edited.
Actual tools were glob, view and apply_patch. No command, installation,
simulation, synthesis, numerical experiment or static elaboration ran.
The one reserved fast static elaboration remains unused for the complete
connected design. There are no preparation receipts to cite.

The earlier ownership-guard interruption and failure-0001 remain unchanged;
this source increment does not diagnose or claim to repair the shared runtime's
guard. No original failing command, output path, acceptance command, threshold
or runtime metadata was changed. Independent Verifier must follow only after
the full design handoff; engineering acceptance and the product PDF remain
future shared-runtime work. This is a saved **continue**, not ready or accepted.
