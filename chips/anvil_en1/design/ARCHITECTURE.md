# Anvil-EN1 architecture and implementation status

The admitted representation combines zero-copy owner aliases with exact on-chip
owner rematerialization. Aliasing alone is insufficient for the E4B reduction.
`SPEC.md` freezes the geometry, tensor-image ABI, BF16 operation boundaries,
registered protocols, storage accounting, and unchanged acceptance criteria.

## Current saved increment: connected durable vision replay

`rtl/anvil_en1_replay_vision_layer.sv` connects real immutable patch
reconstruction, all 12 vision attention heads, clipped output projection
and the existing complete post-attention/residual/MLP engine to the
bounded continuation workspace. Layer zero emits real patch embeddings
into its frame. Later layers acquire the same patch's completed
predecessor through the memo pool, preserve it in frame bank 0, and
collect attention in bank 1 without overwriting bidirectional inputs.
Historical dependencies yield strictly lower vision layers; query
reads use the retained frame and historical reads use the actual tagged
memo result. No host feature/KV answer or external activation archive
enters this path.

The saved head wrapper writes its 512-bit arithmetic continuation at
scalar words 8..23; this worker additionally saves output count and
unpaired low BF16 at 24/25 before returning the yield. Resume validates
the descriptor, restores those words and checks the next output index
against actual saved head word 17. Pair writes stall child acceptance
until the workspace response retires. Predecessor continuations have a
distinct magic and authorize only the same patch's previous layer.

After all 768 head outputs complete, each actual clipped output row
reads the completed frame vector and collects into one additional
1536-byte synchronous bank. Only the complete projection replaces
bank 1. The post layer first loads complete raw/projected vectors,
then produces actual final layer pairs into bank 1. Ordered counts,
last, concrete child/workspace errors and accepted done guard each
visibility boundary. Partial/error banks remain charged through done;
successful projection storage releases before post allocation.

`rtl/anvil_en1_replay_frame_input.sv` now supports explicit compile-time
domains 0/1/2 with their actual layer limits and vector lengths. Default
domain 0 preserves its previous text behavior. It validates same-domain
immediately preceding layers and actual completed memo copies. Its
controller report now derives from declared registers rather than the
previous fixed byte estimate.

`rtl/anvil_en1_replay_execute.sv` dispatches domain-1 tasks to that worker
using the existing frame/memo scheduler and registered external/backing
ownership. Root image geometry and immutable image/vision-weight bases
are captured on root start; worker generation comes from each registered
task. This makes the saved native vision path accessible through the
real replay start/output/done and backing interfaces, not only leaves.
New outputs separate native input/projection/intermediate events and
connected vector/controller allocation categories from text owner work.
Arithmetic leaf state still needs the final whole-system overlay.

Remaining integration dependencies: audio relative attention and full
conformer/replay worker; text modality yields and native soft-token/
placeholder/session mapping; owner-replay binding to ordinary frontier
and fallback execution; complete arithmetic/controller live and physical
overlays; parent-compatible top, session, cache, arbiter and CSR wiring.
The native vision root is implemented but not independently verified.
The complete design is not ready for Verifier.

Tools used: glob, view, rg, web_fetch and apply_patch. No commands,
installation, static elaboration, simulation, synthesis or experiments
ran; the reserved static check remains unused and no preparation
receipt exists. Parent, tests and runtime-owned files remain untouched.
The original ownership-guard interruption at
`.vulcan/engineering/run-0001/attempt-0003` remains preserved with no
claimed repair or acceptance.

## Prior increment: causal audio light convolution and output features

`rtl/anvil_en1_audio_glu_component.sv` computes one genuine
light-convolution GLU input channel from the attention-residual vector.
It executes the learned 1024-channel pre_layer_norm, collects the complete
successful BF16 vector in synchronous RAM, computes both actual clipped
linear_start rows, and uses the saved sigmoid/product arithmetic with the
second half as gate and first half as multiplicand. There is no pre-norm
gradient clamp, GeGLU substitution or host-generated GLU source.

`rtl/anvil_en1_audio_depthwise_row.sv` executes all five actual causal
depthwise OIW terms in ascending kernel order, with the same channel
at token-4+j. A registered distance check distinguishes left padding
before subtraction; padding still participates in weight multiplication
and reduction. The native BF16/Q4 reader preserves five-column partial
row boundaries. Actual historical GLU callbacks, directory validation
and successful external responses supply the result; no mask, bias,
clipped depthwise weight or generated-feature write is inserted.

`rtl/anvil_en1_audio_lightconv.sv` connects those leaves into the full
light-convolution sublayer. It preserves the unclipped attention residual,
computes all depthwise channels, applies the pinned stability clamp,
learned conv_norm, BF16 SiLU and clipped linear_end, then emits the actual
unweighted residual sum. Historical dependencies dispatch real complete
GLU computation and retain the first concrete child error. Parent memory
ownership pauses only after its weight response has retired and returns
after the GLU child completes. RAM reads, response creation and response
acceptance are separate edges; no partially filled bank becomes readable.
All 1024 outputs must retire before successful completion. Two outer
2048-byte banks and the child's 2048-byte bank give a 6144-byte physical
vector reservation and up to 6144 live vector bytes, with scalar/numerical
state additional.

`rtl/anvil_en1_audio_output.sv` validates the actual 1536x1024 output
matrix and independent BF16 bias vector, performs each genuine matrix row,
then reads/adds its actual bias and materializes BF16. It streams all
1536 native output components with held backpressure and no extra norm,
clipping, activation or residual weighting.

`rtl/anvil_en1_audio_feature.sv` captures the complete successful native
output in a 3072-byte synchronous bank before connecting the saved real
unscaled modality RMSNorm and H projection. It validates ordered indices,
last, native completion and source tags before visibility. It checks every
H output, including compact H=8 while retaining native encoder widths.
Both collection and normalized banks can be live (6144 vector bytes);
all scalar/arithmetic state remains additional. Its public source is the
actual layer-12 audio vector, not a finished host modality feature.

SPEC freezes these numerical boundaries, public descriptors, causal
padding, allocation lifetimes and registered ownership rules. Actual
accepted directory/matrix/bias transfers are reported as weight bytes;
GLU reconstruction is additional owner/native work, never avoided
projection traffic. These paths have deliberately high recomputation
cost and establish neither practical throughput nor reduced total DDR.

Remaining: native audio relative attention and complete conformer dispatch;
durable native text/vision/audio replay continuations and frame dispatch;
original-token ordinal/placeholder/session validation; linear single-token
text replay; complete arithmetic/control liveness and allocation overlays;
parent-compatible top/session/cache/replay/arbiter/CSR integration. The
design is not ready for independent Verifier.

Tools used in this increment: glob, view, rg, web_fetch and apply_patch.
Pinned public model inspection confirmed light-convolution RMSNorm,
linear_start/GLU half order, causal padding, depthwise groups/no bias,
clamp/conv_norm/SiLU/linear_end and unweighted residual semantics.
No command, installation, static elaboration, functional simulation,
synthesis or experiment ran. The reserved static check remains unused;
no preparation receipt exists. Parent, tests and runtime-owned sources
remain untouched. The original ownership-guard interruption at
`.vulcan/engineering/run-0001/attempt-0003` remains preserved without an
interruption repair or acceptance claim.

## Prior increment: valid image ordinals and connected audio subsampling

`rtl/anvil_en1_vision_bins.sv` derives the actual true-bin map from the
immutable coordinate tensor. It performs the same max-x/floor mapping as
the pinned pool, including clamped padding in bin zero, stores presence in
a bounded 456-word synchronous bitmap, and enumerates physical bins in
ascending order. Repeated coordinates set one bit. Selecting an ordinal
does not stop validation: complete enumeration must match the expected
placeholder count before a usable bin is returned. Every new task clears
the entire 1824-byte allocation before reading it; reset invalidates its
visibility rather than resetting RAM payload.

`rtl/anvil_en1_vision_soft_token.sv` connects that selected bin to the saved
real pool/normalization/modality projection. It checks the true numerical
mask and all H ordered output components before completion. Mapping RAM
is released before numerical vector allocation starts; physical reserved
RAM remains 6432 bytes, while the separate live peaks are 1824 bytes for
mapping and 3072 bytes for numerical vectors, plus all scalar/child state.
Native session token scanning still must derive the requested ordinal and
expected placeholder count. No host-generated feature map is accepted.

`rtl/anvil_en1_audio_conv_row.sv` executes native stage-0/1 stride-2 padded
3x3 convolutions using the actual BF16/Q4 OIHW matrices. Sequential divide
by 9 and 3 preserves input-channel/kernel traversal, and registered
coordinate checks distinguish padding from real sources. Padding still
participates in actual weight arithmetic; in-domain masked sources still
execute source-times-mask with BF16 materialization. No lossy zero shortcut,
host convolution answer, bias, clipping or per-channel RMSNorm is inserted.

`rtl/anvil_en1_audio_subsample_point.sv` gathers all 128/32 real convolution
channels before learned channel LayerNorm and ReLU. One 256-byte synchronous
bank preserves all channel inputs through reductions and output. Source
reads, normalized-output capture, ReLU classification and public acceptance
occupy distinct edges. Final completion waits for every actual channel to
retire. The original mask is sampled at frame 2*time or 4*time as prescribed
by the two mask-striding operations, including odd frame counts.

`rtl/anvil_en1_audio_input.sv` reads actual immutable BF16 input features
and 0/1 validity words through the versioned tensor directory, registered
aligned-address/bounds checks and real external responses. It returns
exact BF16 lane encodings and preserves memory error 2 and malformed-mask/
descriptor error 5. All accepted directory/payload bytes, including failures,
remain original-input traffic; no generated-feature write path exists.

`rtl/anvil_en1_audio_subsample_execute.sv` connects raw sources and masks to
that original-input service, forwarding only preceding-point generated
components to its native callback. It holds memory ownership through actual
response retirement and retains original callback failures rather than
flattening them into a success or a generic error.

`rtl/anvil_en1_audio_subsample.sv` completes the two-stage input projection:
each requested flattened [frequency,channel] stage-1 component executes a
real complete 32-channel point; its preceding-point dependency executes a
real complete 128-channel stage-0 point. Only requested components are
retained after complete output/done checks. The fixed two-level FSM nesting
has no combinational recursion or spatial tensor archive. Actual 1024x1024
input projection rows stream in ascending order with complete masking/error/
backpressure handling. Both 256-byte point banks can be live concurrently;
their 512-byte reservation and every scalar/controller/numerical state
remain additional to the text/native workspace ledger. Repeated point
execution has very high input/weight cost; no practical throughput or
total-DDR reduction is claimed.

SPEC records the public descriptors, degenerate/registered cycle tables,
native tensor order, mask/exceptional rules, storage lifetimes and nested
memory ownership before implementation. These connected subsampling and
valid-bin paths are not complete native inference. Remaining: durable
vision/text/modality replay continuations and frame dispatch; original-token
ordinal/placeholder/session validation; audio relative attention, causal
light convolution, complete layers and final projection; linear single-token
text replay; whole-system allocation overlays and parent-compatible
top/session/cache/replay/arbiter/CSR integration. The design is not ready
for independent Verifier.

Tools used in this increment: glob, view, rg, web_fetch and apply_patch.
Pinned public model reads confirmed pool weight-presence stripping, OIHW
subsampling, channel LayerNorm/ReLU, mask striding and frequency/channel
flattening. No command, installation, static elaboration, functional
simulation, synthesis or experiment ran. The reserved static check remains
unused and no preparation receipts exist. Parent, tests and runtime-owned
files remain untouched; the ownership-guard failure at
`.vulcan/engineering/run-0001/attempt-0003` remains preserved with no new
diagnosis, interruption repair or acceptance claim.

## Prior increment: native pooling, modality projection and audio FF

`rtl/anvil_en1_vision_pool.sv` executes actual pinned 3x3 coordinate pooling
over immutable original-input coordinates and real layer-16 vision sources.
It validates the input directory/grid, scans clamped coordinates to obtain
the actual pooled-row stride, and traverses patches in ascending order for
every component. Padding contributes zero without an encoder read; nonpadding
nonmatching patches still execute zero-weight multiplication, preserving
exceptional floating-point behavior. Weight-presence masks include clamped
padding, as in the pinned one-hot map. BF16 pooled materialization precedes
binary32 sqrt(768) scaling and a second BF16 materialization. No full patch
tensor, coordinate archive or external feature buffer is allocated.

`rtl/anvil_en1_uint_div.sv` supplies the pool's exact floor quotients with
32 explicit restoring digits, separate compare/subtract edges, and held
results/errors. Real binary32 division and square root provide 1/9 and
sqrt(768). This is iterative registered arithmetic, not a hidden combinational
division or precomputed feature shortcut.

`rtl/anvil_en1_modality_projection.sv` validates the immutable native
vision/audio projection directory, executes unscaled RMSNorm, commits the
complete native-width normalized vector, and computes every actual H
projection row in BF16 or Q4 mode. Native source widths remain 768/1536,
including compact text builds. The one synchronous bank reserves 3072
physical bytes and charges 1536/3072 live bytes during its native task.
The existing tensor ABI uses type 0 BF16 and type 1 Q4; both are checked
against the registered precision. There is no clipped modality matrix,
learned norm scale, projection bias or extra embedding scaling.

`rtl/anvil_en1_vision_feature.sv` connects that pool to the vision norm and
projection. It retains one complete 1536-byte pooled vector, checks ordering,
last, stable mask and actual child completion before visibility, and services
normalization through acknowledged synchronous reads. False physical bins
complete with an explicit false mask and no projected output. True bins
stream all H actual projected components before completion. Peak vector live
payload is 3072 bytes; physical reservation is 4608 bytes, with numerical,
directory, decoder, divider and controller state additional. The source
still must be generated by native Eval; this wrapper does not implement
valid-bin ordinal mapping or certify placeholder counts.

`rtl/anvil_en1_native_norm.sv` now also admits the pinned audio subsampling
LayerNorms (128/32 channels, learned scale/no bias) and the nine 1024-channel
audio layer RMSNorm kinds. Existing vision descriptors and arithmetic stay
unchanged. Invalid kind/length/layer tuples reject before scale accesses;
audio per_dim_scale is deliberately not treated as a norm.

`rtl/anvil_en1_audio_feedforward.sv` connects actual audio FF1/FF2 pre/post
RMSNorms to the saved clipped FF/SiLU/down-row engine. It preserves the
unclipped input residual, applies the pinned BF16 gradient-clipping bounds
on the branch before each norm, materializes the 0.5 branch multiplication,
then adds the untouched residual and materializes BF16. Three synchronous
1024-component banks reserve and conservatively charge 6144 bytes from
start through completion acceptance, including partial/failed receives.
No audio up projection, attention result, convolution or host feature is
substituted. Bank reads and source responses occupy separate registered
stages, and errors retire child responses before stopping work.

These are saved downstream numerical increments, not complete native
multimodal inference. Still required: durable vision row/outer-layer replay
continuations and domain/frame input dispatch; physical-bin/valid-ordinal
mapping; audio subsampling, relative attention, causal light convolution,
layer/output projection and durable replay; linear single-token replay;
whole-system allocation/phase-overlay accounting; and parent-compatible
top/session/cache/replay/arbiter/CSR integration. Do not hand the incomplete
design to Verifier as ready.

Tools used in this increment: glob, view, rg, web_fetch and apply_patch.
Public reads used the pinned model-operation revision and configuration;
no local source or credentials were sent to an external service. No command,
installation, static elaboration, functional simulation, synthesis or
experiment ran. The reserved static check remains unused; no preparation
receipts exist. Parent, tests and runtime files remain untouched, and the
earlier failure at `.vulcan/engineering/run-0001/attempt-0003` is preserved
without a new diagnosis, interruption repair or acceptance claim.

## Prior increment: complete vision layer leaf and native-width workspace

`rtl/anvil_en1_vision_layer.sv` connects actual bidirectional attention,
clipped output projection, learned post-attention norm/residual,
pre-feedforward norm, clipped GeGLU/down and post-feedforward norm/residual.
`rtl/anvil_en1_vision_attention_row.sv` provides a real output-projection
source through the existing attention executor. It drains complete heads and
selects the actual requested component, preserving ascending-column reduction
and all clipping boundaries. Its substantial repeated work is not advertised
as avoided computation or improved throughput.

`rtl/anvil_en1_native_norm.sv` performs real directory/scale reads and learned
vision RMSNorm, preserving original scale errors. It does not purport to
implement audio affine LayerNorm. `rtl/anvil_en1_vision_post_layer.sv` retains
three separately visible synchronous BF16 vectors, totaling 4608 bytes.
The raw residual remains intact through all MLP rows, and final completion
waits for the last output acceptance. The enclosing layer exposes their
live/reserved bytes together with the existing 1664-byte Q/K/V tile vectors;
all declared controller widths and numerical child state remain additional.
No feature/KV external write path or host encoder result is added.

Compact replay in `rtl/anvil_en1_replay_workspace.sv` and
`rtl/anvil_en1_eval_schedule.sv` now keeps native vision/audio lengths 768/1024,
instead of incorrectly assigning them the compact text length 8. Two
512-word banks per frame, 512-word memo slots and 32-word scalar slots
give collision-safe native strides and a 303104-byte backing reservation.
Live domain-specific reservations include pending frames and memo writes;
pop, replacement and reset update explicit totals. Production layout and
production-width shadow reservations are unchanged. The 96 new domain/total
metadata bits are included in the visibility ledger.

`rtl/anvil_en1_frontier.sv` supplies that backing inside one 524288-byte
compact physical RAM while retaining the ordinary 8192-byte allocation cap.
Unused physical stride holes/capacity are disclosed, not claimed as occupied
payload reduction or measured FPGA savings. Whole-system allocator limits,
actual M20K inference and timing are still unestablished.

The connected vision leaf requires immutable committed entering-layer sources;
it is not yet the bounded replay dispatcher. The saved resumable native head
wrapper remains the basis for drained child dependencies. Next implement the
durable vision output-row/outer-layer continuation, bind native frame sources
and input reconstruction to Eval, then pooling/modality projection and the
complete audio encoder. Single-token linear replay, full liveness overlays
and parent-compatible top/session/cache/replay/arbiter/CSR integration also
remain. The design is **continue**, not ready for Verifier.

Tools used: glob, view, rg and apply_patch. No commands, installations,
static elaboration, functional simulation, synthesis or experiments ran;
the reserved static check remains unused and no preparation receipts exist.
The earlier ownership-guard failure at
`.vulcan/engineering/run-0001/attempt-0003` remains preserved; no repair or
acceptance of that interruption is claimed. Parent, test and runtime-owned
files remain untouched.

## Prior increment: connected bidirectional vision attention and native MLP

`rtl/anvil_en1_vision_attention_head.sv` performs actual native 64-component,
twelve-head-compatible vision attention with bidirectional key traversal,
scaling 1.0, registered pair service, real max-subtracted exponential/sum/
reciprocal, BF16 probabilities and ascending-key value reduction. It repeats
the value pass per component rather than storing scores or another head
vector. Q/K/V requests retain distinct selectors, actual native layer/head
identities and correct aligned low/high BF16 lanes. Padded query patches
are not prematurely replaced with zero; padding keys are masked before
numeric work. An all-masked image explicitly rejects, not successful zero
feature output.

Its optional replay mode yields only before a source service request, after
all prior responses and arithmetic have retired. The held 512-bit continuation
preserves generation, complete descriptor, all traversal indices, current
query/probability and scalar reductions. Resume rejects stale/malformed tags
and reacquires the precise source dependency without restarting an unfinished
reduction. It has no text owner/cache-alias path, causal/window assumption,
host numerical answer or new floating-point approximation. The existing
binary32, exponential and division engines supply the real arithmetic.

`rtl/anvil_en1_vision_attention_execute.sv` literally connects that head to
the saved `anvil_en1_vision_qkv_tile`. It validates the immutable input
directory, rereads original x/y coordinates for every mask/service operation,
checks padding/in-grid semantics and routes the single accepted memory
transaction to coordinate/directory or tile work. Coordinate row start,
row/payload end and comparison occupy separate registered stages; an
unchecked native address never becomes a command. Failed coordinate reads
remain external error 2 after the head retires its actual failed response.
Weight and original-input reads remain distinct accepted traffic, including
repeated reads/errors. Source callbacks identify the captured generation and
entering-layer vector needed by the real norm/projection tile.

The executor forwards drained source-dependency and full-checkpoint channels;
neither head nor executor fabricates successful completion on a yield.
`rtl/anvil_en1_replay_vision_attention.sv` connects these to actual workspace
scalar reads/writes: all 16 checkpoint words at native-frame slots 8..23
are acknowledged before publishing a yielded dependency. Resume restores
every occupied word and validates the generation/frame/query/layer/head
outer continuation before starting the numerical executor. Failed saves/
restores retire their actual work responses and cannot produce a usable
continuation. Grid products and extent checks are registered before any
workspace access. The pending dependency strictly decreases encoder layer.

The enclosing native replay layer dispatcher still must bind committed
source vectors, save its outer branch state and execute the smaller-rank
child. This is not yet that dispatcher or a completed bidirectional encoder.
At that increment the compact workspace allocated only 8-component native
vectors; the new wrapper deliberately requested real 768-component vision
frames. The current increment corrects that layout, while native frame/worker
binding and whole-system accounting remain required.
The head/executor/wrapper allocate
no new vector bank. Both held resume copies and all descriptor/scalar state
are charged by their declared register-width observations, with all three
held checkpoint copies and 64 acknowledged workspace scalar bytes explicitly
additional. Existing tile
live/reserved 1664-byte vectors and its controller/clamp observations are
forwarded separately; numerical/directory child registers remain additional.

`rtl/anvil_en1_native_mlp_row.sv` executes the real vision clipped gate/up,
BF16 GELU_tanh GeGLU and clipped down row, or either audio clipped FF/SiLU/
clipped down row. It serially regenerates each intermediate through the outer
down projection's actual ascending-column source callback, not an
unclipped down weight reader. Audio has no fictitious up projection/multiply.
All clipping buffers, matrix words, activations and reductions are read/
computed in RTL. Temporary memory ownership changes only while the outer
projection waits for its source and its previous weight response is retired.
Original child errors propagate through the real outer failure before done.
No 3072/4096-component intermediate RAM or external feature spill is allocated.
Repeated intermediate work and its considerable weight traffic are not
claimed as savings.

SPEC freezes these descriptors, continuation bits, native geometry,
materialization, errors, reset/stalls and registered stages. Existing text,
cache, replay, parent and numerical leaves are retained unchanged by this
increment. Native vision layer output projection/residual/GeGLU/norm execution
and durable replay-frame binding, pooling/modality projection, the full audio
encoder, complete liveness/resource overlay and parent-compatible literal
top/session/cache/replay/arbiter/CSR integration still remain. The design is
**continue**, not ready for independent Verifier.

Tools used in this increment: glob, view, rg, web_fetch and apply_patch.
Pinned public source inspection confirmed vision scaling, bidirectional mask,
Q/K learned and V unscaled normalization, axial rotation, layer residual order
and audio FF activation. No command, installation, static elaboration,
simulation, synthesis or experiment ran; the reserved static check remains
unused and no preparation receipts exist. Parent/test/runtime sources and
failure-0001 in `.vulcan/engineering/run-0001/attempt-0003` were preserved.
No interruption repair, engineering acceptance, FPGA resource/timing result
or product report is claimed.

## Prior increment: native clipped linears and vision input/QKV

`rtl/anvil_en1_bf16_clamp.sv` implements registered sign/magnitude comparison
and clamp selection, including signed zero, subnormals, infinities, canonical
value NaNs and explicit rejection of malformed bounds. Its declared scalar
state is 75 bits / 10 byte-rounded bytes. It stores no vector or weight image.

`rtl/anvil_en1_clipped_projection.sv` validates the real native clipped-matrix
schema and the four immutable clipping-buffer entries, reads their actual
BF16 values, and executes the existing projection through individually
acknowledged, input-clamped source components. The BF16 completed row is
output-clamped. The controller has 648 declared bits / 81 byte-rounded bytes,
with its scalar clamp, directory reader, projection/weight decoder and
floating-point child state additional. This path is common to vision/audio
clipped linears, not a text-precision or Q4-packing change. It revalidates the
directory for each tensor; its considerable repeated weight traffic and
latency are not claimed as savings.

`rtl/anvil_en1_vision_patch.sv` computes a native 768-component patch from
actual immutable preprocessed BF16 pixels, signed coordinates and the pinned
patch/position tensors. It validates the captured grid extent before input
access, preserves input row order, preprocesses pixels with the prescribed
BF16 boundaries, executes genuine ascending-column projection, and combines
the learned x/y position rows. Padding suppresses only position addition here,
not patch projection; later encoder/pool masking remains required. There is
no input/output vector bank or feature archive. Its declared controller state
is 1799 bits / 225 byte-rounded bytes, including pending read words, source
operands, projection result and held output. The directory, projection,
position weight reader and floating-point child registers are additional.
Failed original pixel reads propagate external error 2 after retirement.

`rtl/anvil_en1_vision_qkv_tile.sv` connects the real learned input RMSNorm,
clipped native Q/K/V projection, learned Q/K or unscaled V head RMSNorm,
and theta-100 axial rotation. It computes one aligned adjacent BF16 pair for
one of the twelve native heads; no text owner alias or projection is used.
Q/K rotation pairs within separate x/y 32-component partitions, not across
the complete 64-component head. `rtl/anvil_en1_rotary_pair.sv` adds the
default-off SIGNED_POSITION capability; unsigned text behavior is retained,
while native negative padding coordinates are converted and rotated as -1,
never silently clamped to zero.

The tile charges complete 1536-byte input and 128-byte head banks from their
allocation until final result acceptance. Both arrays have one serialized
synchronous write/read port, no asynchronous payload reset, and explicit
committed visibility. Head-norm output overwrites only its already consumed
input component. Its declared controller state is 682 bits / 86 byte-rounded
bytes, with all numerical child state additional. The bank reservation of
1664 bytes is logical payload capacity, **not** measured FPGA M20K utilization
or a claim that only those physical bits are used. Physical block rounding,
unused capacity, connected hierarchy, whole-system liveness and <=10 ns
timing require the future source-matched independent/tool-execution evidence.

Pinned upstream operation inspection was limited to clipping, patch
preprocessing/positions, axial vision attention/norm semantics and surrounding
encoder/pooling ordering. It is not inspection of production checkpoints or a
numerical result. Source additions are saved, but native bidirectional layer
dispatch and continuations, complete vision GeGLU/residual/pooling/modality
projection, the full audio encoder, whole-system liveness/resource overlay and
parent-compatible literal top/session/cache/replay/arbiter/CSR integration
remain required. The design is **continue**, not ready for independent Verifier.

Tools used in this increment: glob, view, rg, web_fetch and apply_patch.
No command, installation, static elaboration, simulation, synthesis or
experiment ran. The reserved fast static check remains unused and there are
no preparation receipts. Parent RTL, verification sources, runtime-owned
metadata and the retained earlier ownership-guard interruption were preserved;
no repair of that interruption or hardware acceptance is claimed.

## Prior increment: connected resumable text Eval execution

`rtl/anvil_en1_replay_execute.sv` connects the bounded Eval scheduler/workspace
to genuine input reconstruction and the new
`rtl/anvil_en1_replay_text_layer.sv`. Registered task descriptors select Eval(0,t)
input reconstruction or positive-layer numerical execution. Root results still
come from committed memo reads; the scheduler owns dependency lookup, smaller-
rank child execution, memo eviction/regeneration, copy and frame release.
Neither dispatcher supplies a synthetic worker completion or hidden-vector
answer. Native modality feature production and external/backing integration
remain missing, so this is not a complete fallback/top implementation.

`rtl/anvil_en1_replay_attention_projection.sv` executes the real output
projection in ascending head/component reduction order. It recomputes attention
heads for each H output row instead of allocating another global attention
tensor. Its unfinished output pairs live in the actual parent frame; the row
sum, pending low BF16 value and traversal indices survive child work through
the scheduler's outer continuation. The inner head's lower checkpoint is
acknowledged into scalar words 15..19 before yield, supplementing the existing
8..14 words. Resume restores the checkpoint and real arithmetic, not a fresh
sum or a precomputed answer. Actual additional owner/Q projections and weight
transactions remain genuine work, not avoided traffic.

The workspace's operation-6 pair assembly/patch additions are guarded by the
current frame tag. An unfinished assembled bank is unreadable until its final
acknowledged pair. Inter-pair transaction release permits raw-input reads and
child replay without the deadlock of an open streamed destination. Explicit
per-bank progress checks reject missing/out-of-order pairs. Failed writes
invalidate destination visibility. The added progress metadata is 208 bytes,
not another vector RAM. Compact scalar slots increase to 32 words; production
slots stay 256 words and production-width shadow accounting is unchanged.
At that increment compact text-only backing was 10496 bytes within one
16384-byte physical frontier RAM. The current native-width layout supersedes
its physical strides; its ordinary frontier cap remains 8192 bytes/512 tokens. No production
payload reservation or threshold is changed.

The text dispatcher binds the exact predecessor into raw bank 0, commits the
real attention branch into bank 1, and reconstructs the actual layer's combined
PLE from immutable original inputs. A checked PLE bank adds 512 production
bytes / 8 compact bytes. `anvil_en1_asym_attn_ple` adds default-disabled
`POST_ONLY`, using the existing post-attention norm/residual/FF/GeGLU/gated-PLE/
scalar stages without duplicating their mathematics. It reads committed
raw/branch pairs and the reconstructed PLE, then its complete output overwrites
bank 1 through acknowledged pair assembly. Completion waits for the final
pair response. The ordinary frontier instance retains POST_ONLY=0.

The head executor adds default-disabled PAUSABLE at the drained component
boundary. The folded output-weight callback completes before the next head
request can be accepted. A failed callback rejects subsequent source/owner
requests without starting a new tile, then retires the actual head failure.
This is not cancellation of an already outstanding tile or a general-purpose
withdrawal of stalled valid.

Controller widths for the new dispatchers/projection are derived from the
declared register widths, and vector live/reserved observations distinguish
frame, PLE, reconstruction, projection tile and post-only scratch. Complete
child arithmetic/control accounting, collision-safe physical phase overlay,
native vision/audio encoders, native session/mask handling and parent-compatible
literal top/cache/replay/arbiter/CSR integration remain unfinished. The design
is **continue**, not ready for independent Verifier.

Tools used in this increment: glob, view, rg and apply_patch. No command,
installation, static elaboration, simulation, synthesis or experiment ran.
The reserved static check remains unused; there are no preparation receipts.
The supplied GENERATIONAL_HANDOFF was read and provides only N/A STA/PPA.
Parent/test/runtime sources and retained failure-0001/attempt-0003 evidence
remain unchanged; no ownership-guard repair or hardware acceptance is claimed.

## Prior increment: real Q/dependency responder and predecessor binding

`rtl/anvil_en1_replay_attention_execute.sv` connects the saved resumable head
to real Q generation and owner projection. One folded workspace tile serves
both operations, rather than allocating separate Q/K/V numerical banks.
Q uses the logical layer's own Q matrix and learned Q RMS, including shared
layers; K/V still uses only the canonical metadata response's actual owner.
The numerical tile's optional query capability defaults off, and root owner
replay explicitly ties it off. The existing input/K/V numerical path is
retained. Actual query rows have separate events from owner reprojection.

The executor authorizes a fetch only from the committed current raw frame
when owner/token exactly match the logical layer/current token, or from
the scheduler's matching completed dependency memo. Other legal requests
yield after the acknowledged attention checkpoint. An allow decision captures
every fetch descriptor field; the following fetch must match. Inner data
comes from the real workspace projection, never recursive root cache regen
or an external generated-state region. A transient Q pair serves adjacent
components and is discarded at descriptor/yield/completion boundaries.
Regeneration can be expensive and is not claimed as avoided owner work.

`rtl/anvil_en1_replay_frame_input.sv` implements the preceding hidden-vector
binding subtask. Missing predecessor data requests the exact smaller-layer
Eval dependency. A returned matching memo is copied to the current raw frame
only through the actual acknowledged workspace transport. The workspace adds
internal memo-to-frame store target 3, with complete source/destination tag
checks, serialized backing reads/writes and final-write-before-visibility.
`rtl/anvil_en1_eval_schedule.sv` permits that request only for its exact
returned dependency and current frame. No second vector RAM, additional frame,
memo eviction or external activation transaction is introduced. Opening an
ordinary stream store and reading memo through the same single-outstanding
workspace would deadlock; the internal copy avoids that unimplemented shortcut.

SPEC freezes this source encoding, registered stage/degenerate/error table
and telemetry. Executor/controller state is 100 bytes, frame-input state
21 bytes, and the extended workspace source adapter 53 bytes. The one H/D
tile-bank reservation is unchanged. Pair bytes are a subset of controller
state, not an extra allocation to count twice. All numerical child registers
still require whole-system accounting; these local figures do not prove
the final live ledger, FPGA fit or timing.

These are implemented numerical subtasks, not a complete layer or system.
Remaining: dispatch reconstruction/predecessor binding, retain partial
attention/layer outputs and exact outer continuations across child work,
complete frame-backed residual/norm/PLE/MLP execution, native vision/audio
encoders, whole-system liveness and compatible literal top/session/arbiter/CSR
integration. The accepted output of a head may precede a later yield; the
whole-layer worker must persist it before yielding, not memo-copy an incomplete
layer. The design is **continue**, not ready for independent Verifier.

Actual tools used were glob, view, rg and apply_patch. No command, installation,
static elaboration, simulation, synthesis or experiment ran. The one reserved
static check remains unused and there are no preparation receipts.
Parent RTL, tests and runtime-owned metadata/evidence were preserved, including
failure-0001 and `.vulcan/engineering/run-0001/attempt-0003`; no repair or
acceptance of the earlier ownership-guard interruption is claimed. The
supplied GENERATIONAL_HANDOFF was read; its N/A entries provide no STA/PPA.

## Prior increment: resumable numerical attention and memo-backed owner tiles

`rtl/anvil_en1_attention_head.sv` adds an optional, default-disabled replay
boundary without changing the ordinary numerical operation/reduction order.
After actual canonical cache metadata retirement, replay requests a registered
allow/yield/error decision before presenting any data fetch. Yield occurs
with every source/cache/arithmetic transaction retired. A 384-bit checkpoint
preserves the actual max/sum/value reductions, BF16 operands and traversal
indices. The released numerical instance can serve a child; resumption
validates its format/descriptor and reobtains canonical metadata rather than
fetching through a stale saved address. Ordinary
`rtl/anvil_en1_asym_attn_ple.sv` explicitly ties this interface off.

`rtl/anvil_en1_replay_attention.sv` connects that real head to acknowledged
frame scalar storage. Seven words at indices 8..14 retain the checkpoint's
upper 224 bits, while its lower 160 bits form the subtask continuation.
The final scalar response must retire before successful yield. Restore reads
all seven visible words before numerical resume. Scalar access failures
retire before failed completion; they do not become successful snapshots.
No additional vector/checkpoint RAM is inferred. Its 590 controller register
bits occupy 74 byte-rounded bytes, including the held checkpoint and response
word. The head's additional 385 resume/checkpoint register bits and all
existing child arithmetic state also count in the final whole-system ledger.

`rtl/anvil_en1_replay_kv_tile.sv` connects the same actual normalized/rotated
owner tile used by root replay to tagged, acknowledged workspace vector reads.
It reads either the completed dependency Eval(owner,token) memo or the
committed raw layer input of the current Eval(owner+1,token) frame. It adds
no second H-vector and never invokes the cache's already occupied root regen
channel. Actual owner projection rows and accepted internal source words are
observable, including work preceding a failure. Internal source bytes are
not relabeled as external original-input traffic. Its 414 controller bits
occupy 52 byte-rounded bytes; tile banks still reserve at most 6144 production
bytes (32 compact), with all child numerical state additional.

These are connected numerical subtasks, not a complete text Eval worker.
The enclosing worker must regenerate Q from the committed frame input,
preserve its own operator/output-row continuation, request smaller-rank Eval
dependencies, consume their memo handles through the new owner adapter,
and supply the resulting real pair to the inner attention data responder.
It must not wait recursively on root cache regen or copy an incomplete
attention/layer output to memo. Native encoders, complete arithmetic/metadata
liveness, fallback/session control and parent-compatible literal top/arbiter/
CSR integration also remain incomplete. No complete inference or acceptance
is claimed; this remains **continue**, not ready for Verifier.

Changed sources are the two new replay subtasks, the attention head's optional
checkpoint interface, the ordinary layer's explicit tie-offs, and matching
SPEC/ARCHITECTURE documentation. Tools used were glob, view, rg and apply_patch.
No installation, command, elaboration, simulation, synthesis or experiment
ran, and no preparation receipt exists. The one reserved static check remains
unused. Parent RTL, tests, runtime metadata and retained failure-0001/
attempt-0003 evidence were preserved; no ownership-guard repair is claimed.

## Current saved increment: explicit Eval control and input reconstruction

`rtl/anvil_en1_eval_schedule.sv` owns the existing bounded workspace and
implements registered dependency lookup, child push, completed-frame memo
copy, pop/return, and worker resume. A child stores the exact parent return
descriptor and 160-bit numerical continuation in its actual backing scalar
slot. Worker frame accesses and dependency reads are tag-constrained; workers
cannot allocate frames/memo, overwrite other frames or modify return words.
Nested work requires a smaller dependency rank. Actual worker completion and
committed source visibility are prerequisites for memo copy, not fixed-cycle
success. Its numerical worker remains incomplete and is not tied to a
software-produced answer.

The single-token text residual chain advances linearly from Eval(0,0) through
the requested layer, releasing each frame before the next push and supplying
the real preceding memo handle. Evicted owner dependencies still require real
child work. This implements the controller path, not a claim that a full
single-token or historical-dependency neural job has executed. Root results
stream from acknowledged memo reads, with completion after final BF16
acceptance. Failed work invalidates the workspace before failure completion.
The scheduler exposes its 1398 register bits as 175 byte-rounded state bytes,
in addition to workspace allocations and visibility metadata.

`rtl/anvil_en1_replay_workspace.sv` adds an internal complete-frame-to-memo
copy. A tagged source bank remains live until its destination has received
every actual registered backing read/acknowledged write. A 32-bit copy
register avoids adding a second H-vector to copy between stores. Memo tags,
visibility, replacement and eviction apply equally to internal copies.
An explicit accepted stream-abort beat annuls unfinished storage without a
backing access; it is never a successful partial vector. The scheduler
forwards this abort and waits for its response before accepting worker
failure. These additional copy/control registers still belong in the final
whole-system arithmetic/control ledger.

`rtl/anvil_en1_replay_input.sv` supplies real native text Eval(0,t)
reconstruction using the existing numerical embedding/PLE leaf. It rereads
the immutable token to select text or the correct permitted image/audio
placeholder feature boundary, then pair-packs the complete checked input
stream directly into the assigned frame bank. There is no second H-vector
inside this controller. Input/weight errors, early embedding failure and
malformed streams retire/abort accepted storage before failed completion.
Held commands and store beats are not withdrawn on a late numerical error.
The input controller discloses 445 bits as 56 byte-rounded state bytes and
the embedding leaf's selected/physical H/P banks separately; child numerical
registers remain additional accounting work.

These sources do not complete fallback arithmetic: the resumable text-layer
worker must still save actual reductions/loop state in its frame and resolve
historical owner dependencies without waiting recursively on occupied cache
regen. Native vision/audio Eval and feature production remain absent, as do
the complete phase-overlaid liveness ledger and compatible top/session/
arbiter/CSR integration. The reconstruction subtask is not yet dispatched
by a complete numerical worker. No test-only fabricated task response is
provided. The design remains **continue**, not ready for Verifier.

Only the two new controller/subtask RTL files, the workspace copy/abort
extension and SPEC/ARCHITECTURE were changed in this increment. Actual tools
were glob, view, rg and apply_patch. No command, installation, elaboration,
simulation, synthesis or numerical probe ran; the one reserved static check
remains unused and there are no preparation receipts. Parent RTL,
verification files and runtime metadata/evidence were preserved. In
particular, the retained failure-0001/attempt-0003 ownership interruption
is not changed or claimed repaired by these additions.

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
resident state. The later projection-continuation increment increases compact
text-only backing to 10496 bytes inside one 16384-byte physical RAM (now
superseded by the native-width layout above), while keeping its
ordinary frontier cap at 8192 bytes.
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
