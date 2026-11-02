# Anvil-EN1 architecture and implementation status

The admitted representation combines zero-copy owner aliases with exact on-chip
owner rematerialization. Aliasing alone is insufficient for the E4B reduction.
`SPEC.md` freezes the geometry, tensor-image ABI, BF16 operation boundaries,
registered protocols, storage accounting, and unchanged acceptance criteria.

## Current saved increment: owner transport and ordinary ordering

`rtl/anvil_en1_owner_replay.sv` now connects the genuine owner-projection tile
to cache regen, local-ring reads and tagged ordinary frontier reads. It
validates the actual owner/session/component, selects the correct BF16 lane
of a frontier pair, preserves held requests/responses, and returns only a
real ring hit or numerical tile completion. It never emits an external KV
command or invents a logical alias map.

For fallback, the transport requests an internal Eval producer and receives
its full raw H-vector into a synchronous bank. Both a checked complete
ascending stream and a successful producer completion are required before
any owner-tile source can read the bank. Malformed or failed streams cannot
become KV. The bank is immutable through repeated input-norm passes.
This is implemented transport/visibility control, **not** an implemented
numerical Eval producer. That producer must save/restore real operator
continuations and resolve historical dependencies without recursively
waiting on the occupied root regen channel.

`rtl/anvil_en1_frontier_schedule.sv` implements the ordinary task ordering:
original-input fill, descending tokens for every prefix owner layer,
complete last-local-anchor materialization before its input is overwritten,
frontier freeze entering the final global owner, and last-token-only remaining
layers. Capacity overflow/forced fallback dispatches a real fallback task,
not an error/refusal or fabricated result. Every task requires an actual
engine completion; the worker connections and the fallback executor are
still missing. The schedule itself allocates no hidden tensor.

`rtl/anvil_en1_anchor_materialize.sv` implements real cache metadata and BF16
fetch collection for each local K/V head, followed by complete acknowledged
ring-lane writes. One synchronous lane buffer lets all fetch responses retire
before the single-port ring writer is opened. This prevents ring-reader/regen
deadlock during materialization and never exposes a partially collected lane.
It consumes the cache's canonical owner response rather than sending an
address alias to DDR.

The owner tile now exposes per-successful-projection-row two-byte events.
Completed rows, including work preceding a later failure, are measurable;
starting a tile does not falsely count an entire computed head. Actual
accepted weight/input transactions still require shared-arbiter accounting.
Transport raw H scratch reserves 5120 bytes (16 compact); its tile reserves
6144 (32 compact); materialization adds 512 (8 compact). All actual live
copies plus scalar/control state remain subject to the admitted overlay and
whole-system allocation bounds; these private reservations do not prove fit.

Remaining: connect schedule tasks to input/PLE construction, layer output/
frontier commits, ring/cache arbitration and final-vector retention; implement
numerical continuation-stack/memo Eval and the linear single-token path;
complete fallback release/bind/recompute transitions, native encoders,
full liveness/traffic observations, session/CSR integration and compatible
literal top. No Verifier-ready design or complete inference is claimed.

Only these three new RTL files, the owner tile's projection-event outputs,
and SPEC/ARCHITECTURE were changed in this increment. Tools used were glob,
view, rg and apply_patch. No command, probe, installation, static elaboration,
simulation or synthesis ran; the reserved static check is still unused and
there are no preparation receipts. Parent RTL, tests, runtime metadata and
retained failure/interruption records were not changed. In particular,
failure-0001 and `.vulcan/engineering/run-0001/attempt-0003` are retained and
no new repair of that ownership-guard interruption is claimed.

## Saved sixth increment: overlaid replay storage and tied logits

`rtl/anvil_en1_replay_workspace.sv` implements a bounded 64-slot continuation
stack store and 16-slot complete-vector memo store. Push/pop/update really
transfer continuation words through the on-chip backing channel; rank checks
enforce decreasing dependency depth. Frame banks and memo vectors are invisible
until a complete, flag-checked, acknowledged stream commits. Memo lookup scans
the actual tags, replacement uses a deterministic cursor, and stale handles
require the entire matching generation/vector tag. Failed writes leave targets
unreadable. Scalar words have acknowledged-write visibility, including the
eight continuation words. Live counters include pending frame/memo stores,
full occupied slot padding, and scalar slots, with a separate production-width
shadow ledger. Metadata and remaining arithmetic state are not hidden inside
the payload count.

The workspace does not infer another fallback payload RAM. The changed
`rtl/anvil_en1_frontier.sv` exposes a bounded, generation-checked raw backing
word channel over its existing synchronous payload array. Control op 3 can
bind only released RAM; ordinary allocation cannot reacquire a bound backing
without explicit release. The production backing partition is 983040 bytes,
leaving 65536 bytes of the admitted 1 MiB ceiling for all arithmetic/control/
resident state. Compact backing occupies 6400 of the existing 8192 bytes.
The enclosing scheduler must first drain work and invalidate the separate
ring. A leaf binding is not yet an implemented system-wide mode transition
or proof that all connected state fits.

`rtl/anvil_en1_final_logits.sv` connects final learned RMS normalization,
one synchronous normalized H-bank, the actual tied embedding-row projection
and 30*tanh softcap. It streams vocabulary rows in ascending order with a
single held logit, propagates actual source/tensor/weight errors, and finishes
only after final output acceptance. It has no external activation command or
vocabulary-sized result allocation. Its bank and child state remain subject
to the final arithmetic phase overlay/liveness integration.

This increment updates the matching interfaces, partition addresses,
registered stages and degenerate/error boundaries in SPEC. The supplied
GENERATIONAL_HANDOFF was read; its N/A fields establish no historical STA/PPA.
No static elaboration, simulation, synthesis, mutation, timing or HIL command
has run in this increment. The reserved static elaboration remains unused.
No preparation receipt was created; no acceptance result or repair of
failure-0001 is claimed. Parent RTL, tests and runtime metadata are unchanged.

Still required: the substantive `anvil_en1_owner_replay` evaluator and its
ordinary descending-token schedule, local-anchor materialization, preserved
global frontier, numerical continuation save/restore, memo regeneration,
linear single-token path, real fallback transition and complete allocator;
native vision/audio encoders and placeholder mapping; session/CSR/arbitration
and compatible literal top integration. The storage stack is not a substitute
for neural Eval execution, and the final-logit leaf is not a complete inference
job. This is a saved partial continuation, not a ready Verifier handoff.

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
At this saved third increment, the required literal `anvil_en1_asym_attn_ple`,
`anvil_en1_owner_replay` and `anvil_en1_top` were not present. The subsequent
increments below distinguish newly implemented modules from remaining work.

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

## Saved fourth recovery continuation increment

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

## Saved fifth continuation increment: layer execution and memory transport

`rtl/anvil_en1_asym_attn_ple.sv` now implements the full single-text-layer
controller, connecting the saved image validator, projection, norm, rotary,
attention, gated-projection, weight-read and binary32 leaves. It copies the
entering hidden and original-input-derived combined PLE vectors, runs input
norm and every Q head's projection/norm/RoPE, consumes actual canonical cache
metadata/fetch responses through the attention leaf, projects the concatenated
heads, and executes the specified post norms, three residuals, double-wide
E2B shared GeGLU, gated PLE and final layer scalar. Output is a complete BF16
hidden vector, not logits or a job completion. The layer does not compute
another owner alias map and has no external KV read/write path.

Three H-banks preserve residual, normalized source and branch lifetimes.
One D-bank retains the current Q head, one Q*D bank retains accepted attention
outputs and one P-bank retains combined PLE. Matrix/down rows cannot overwrite
their source vector. Norm reductions precede accepted in-place branch/Q
writes. Rotary pairs use two serialized writes to the actual half-head
components. Internal source reads have capture/read/publish/response stages;
external command ownership switches only at completed child boundaries.
The complete H output holds through backpressure and finishes only after the
last component is accepted. Errors stop numerical progress and publish an
explicit failed completion.

Layer vector payload is `6H+2D+2Q*D+2P`, at most 18944 bytes for E2B global
and 25088 bytes for E4B global. Production physical banks reserve 25088 bytes;
compact banks reserve 104 bytes. These figures exclude scalar/child state,
which must still be measured and counted. The final phase overlay and
whole-system live ledger are not implemented by these private banks.

`rtl/anvil_en1_memory_arbiter.sv` supplies the registered single-outstanding
cmd/result transport needed to share the external port between suspended
layer work, real owner projection and the remaining native engines.
CLIENTS=1..8 use an explicitly wrapped round-robin scan, including 3.
Captured commands hold to the actual external handshake; actual responses
are registered and routed only to the captured client, including errors.
No client may consume a response on the edge that first creates its valid.
Its drain barrier closes ingress and waits for both external response and
original-client retirement before acknowledging. It does not itself cancel
an engine or replace session invalidation. An impossible FSM encoding raises
an explicit protocol error instead of manufacturing a successful drain.

These are implemented connected sub-engines, not a complete native top.
Next implement `anvil_en1_owner_replay`: ordinary frontier initialization,
descending layer/token scheduling, local-ring materialization and preserved
global frontier, then genuine continuation-stack/memo fallback with historical
dependencies and single-token fast path. The remaining work also includes
workspace overlay/full allocation observations, native vision/audio execution,
final norm/tied softcapped logits, generation-safe session/error handling,
arbiter integration, actual CSR events and parent-compatible `anvil_en1_top`.
The arbiter and layer public channels must be wired, not tied to fabricated
answers. Owner-only rematerialization and all admitted tests remain mandatory.

Only the two new RTL modules and SPEC/ARCHITECTURE were changed in this
increment. Existing arithmetic/storage/embedding/owner leaves, parent RTL,
verification files, acceptance commands and runtime metadata were preserved.
Actual tools were glob, view, rg and apply_patch. No command, diagnostic probe,
installation, static elaboration, simulation, synthesis or numerical experiment
ran. The one reserved fast static elaboration remains unused; no preparation
receipt or verification result exists. The retained failure-0001 and
`.vulcan/engineering/run-0001/attempt-0003` interruption were neither changed
nor claimed repaired. This is a bounded saved continuation, not a ready
handoff or engineering acceptance.

## Saved continuation: connected frontier task execution

`rtl/anvil_en1_frontier_execute.sv` now connects real frontier tasks to the
existing embedding/PLE, asymmetric text layer, local-anchor collector and
final-logit engines. It instantiates the actual frontier and local ring,
arbitrates tagged owner/layer frontier reads, and routes the canonical cache
metadata/fetch interfaces to the active anchor or attention consumer. It
does not duplicate logical owner selection or issue external KV commands.

Original token reads choose each token's native modality from its placeholder
identity within the captured text/image/audio domain. Text tokens in mixed
jobs remain ordinary text; modality placeholders request the internal feature
producer rather than host-generated embeddings. Extra immutable token reads
are real original-input traffic, not reported KV savings. Weight and original
input commands are multiplexed to one enclosing arbiter client; the enclosing
top must still arbitrate this client with owner replay and native encoders.

Input fill and every prefix output are checked as complete ascending H-vectors
and retained before frontier writes. Prefix writes advance the entering layer
tag, while last-token execution keeps the frozen owner frontier untouched.
The retained upper-layer source carries generation/token/layer tags. PLE is
reconstructed from the original input, not from a later hidden state. Final
output executes actual RMS normalization, tied projection and logit softcap,
with task completion after the real final accepted logit.

Session binding/invalidation releases old frontier and ring visibility.
Fallback task execution releases both ordinary allocations before binding the
same frontier RAM to the existing workspace backing channel. It then requests
the real internal numerical Eval producer and checks its entire result stream
plus completion. That producer is still absent; the fallback call boundary
and backing binding do not constitute numerical Eval or a completion claim.
Pending control cannot block owner reads required to finish an accepted task.

The executor adds one Hmax bank and one P bank, reserving 5632 production
bytes or 24 compact bytes. Selected H/P allocations include receive lifetime;
frontier, ring and anchor live/physical/metadata figures are exposed separately.
Private numerical leaf banks and scalar/control state still require whole-
system phase-overlay/liveness integration. No complete payload ratio, inferred
M20K resource fit or physical clock period is established.

Remaining implementation is the explicit numerical continuation-stack/memo
Eval engine (including historical dependencies, eviction/regeneration and the
single-token path), native vision/audio producers, complete workspace overlay
and live ledger, and compatible top/session/sole-arbiter/CSR integration. The
new executor must be connected to those real producers, cache and replay
before a complete design handoff.

Only the new executor and directly related SPEC/ARCHITECTURE documentation
were changed in this increment. Tools used were glob, view, rg and apply_patch.
No command, installation, static elaboration, simulation, synthesis or
numerical probe ran. The one reserved fast Designer elaboration remains
unused; no preparation receipts exist. Parent and verification sources,
acceptance commands, runtime metadata and retained failure-0001/attempt-0003
evidence were preserved. No repair of that ownership-guard interruption or
engineering acceptance is claimed. This increment is **continue**, not ready.
