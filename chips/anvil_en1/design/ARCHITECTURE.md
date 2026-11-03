# Anvil-EN1 architecture and implementation status

The admitted representation combines zero-copy owner aliases with exact on-chip
owner rematerialization. Aliasing alone is insufficient for the E4B reduction.
`SPEC.md` freezes the geometry, tensor-image ABI, BF16 operation boundaries,
registered protocols, storage accounting, and unchanged acceptance criteria.

## Current handoff: audio fold wiring repair and unresolved text error

`rtl/anvil_en1_replay_audio_history.sv` separates the fold work-request payload
from its completion result. `fold_work_data` feeds the work mux;
`fold_done_data` feeds the completion register on the existing handshake.
This removes the dual-output connection responsible for the 32 conflicting
drivers in
`evidence/preparation/synthesis-lifetime-production-20261103T060319Z-cb39904a/receipt.json`.
That run reached Yosys `check -assert`; it was not a timeout. Independent
whole-top synthesis and affected audio functional checks remain necessary.

The text-only E2B/BF16/seed17/C3 failure remains retained at
`evidence/preparation/top-lifetime-completion-20261103T060319Z-d4ab0218/receipt.json`:
error 7 at cycle 2860065, 54765 reads, zero logits, exit 1 without timeout.
Static tracing finds distinct error-7 routes through denied allocation grants,
reservation/source/cache errors, native protocol faults and top's allocation
guard. The aggregate layer-3 heartbeat does not discriminate among them or
establish that first-global-layer dispatch failed. No speculative text change
or assertion relaxation is made. SPEC's current repair section gives the
bounded first-origin observation request for independent Verifier; an unchanged
completion rerun cannot supply the missing attribution.

## Retained handoff: job-scoped descriptor reuse and slot-local bookkeeping

The repeated-validation failure is retained at
`evidence/preparation/top-repaired-completion-20261103T045853Z-895deeba/receipt.json`.
Its real simulation duration is approximately 2400 seconds despite the shorter
exception text; its last public heartbeat has 1,079,199 directory reads, 2064
payload reads and zero logits. This is not a numerical mismatch.

`rtl/anvil_en1_tensor_image.sv` now optionally retains a complete-image
certificate and eight round-robin descriptor entries. A complete first
validation is still mandatory. A certified hit returns metadata only; a
certified miss scans keys and validates the entire selected entry, inheriting
the previous whole-directory duplicate/overlap proof only while immutable.
Arbitrary directory ordering and all malformed-image and read-error checks
remain. Optional wire inputs require an explicit one to activate a lifetime
control; omission preserves full validation on every standalone mutable-image
lookup without introducing pull-net drivers.

The other reader-ancestry RTL changes forward these two controls through the
native text, owner, replay, image and audio paths. `anvil_en1_top` retains its
external ABI and invalidates on every job acceptance; `anvil_en1_native`
additionally invalidates on its own start. Frontier/binding/owner session
controls invalidate descendants as well. A changed image/configuration key,
reset, loss of immutable mode, explicit invalidation or directory error clears
reuse. Native external memory remains read-only; active original inputs and
weights are immutable as already required. Mutating a same-address image
requires a drained lifetime and invalidation/new job. Revocation during work
cannot publish a new stale successful descriptor; already offered stalled
responses remain stable until retired. SPEC freezes the cycle table.

The reader's reconciled complete retained state is 3743 bits / 468 rounded
bytes, including all lookaside payloads and the registered read. Current
pre-addition registers total 1384 bits / 173 bytes, not the previously stated
1606 bits / 201 bytes. The 2359 added bits increase the rounded charge by
295 bytes per reader. Existing summed
controller reports charge every connected instance in both live/shadow and
physical reporting, regardless of occupancy. Static production elaboration
contains 49 readers (three frontier, 46 replay-binding), an additional 14,455
rounded bytes and 22,932 total reader bytes; a literal traversal incorrectly counts mutually exclusive
generate alternatives as well. Final source-matched reporting remains an
independent verification task. There is no
uncounted directory archive or numerical-result cache.

`rtl/anvil_en1_replay_workspace.sv` replaces wide variable-select metadata
writes with statically indexed slot-local updates: 64 scalar visibility banks
of 34 bits, and six vector cells per slot, each with three flags and an 11-bit
pair index. The former packed buses are read-only views. The original reset,
session validation, push/pop, continuation, reservation, pair completion,
failed-write, release and allocation-transfer edges are preserved. No payload,
frame, memo or controller capacity is reduced, and the 9664-bit visibility
metadata census is unchanged. This targets the synthesis-expanding updates
seen at the end of
`evidence/preparation/synthesis-native-production-20261103T045127Z-a32dd679/receipt.json`;
it does not establish a synthesis speedup or physical RAM mapping.

All retained receipts, tests, immutable parent sources and runtime state remain
unchanged. The parent-expansion timeout at
`evidence/preparation/synthesis-workspace-declarations-20261103T044320Z-9fc6ab27/receipt.json`
is not concealed by a parent edit or smaller native geometry. Independent
Verifier must run fresh bounded directory/workspace checks and measured top
progress first, then completion and affected synthesis without increasing the
failed budgets. `tests/verify.py`, full six-suite closure and native hardware
gates remain independent work; this is a design repair handoff, not acceptance.

The single static check is retained at
`evidence/preparation/static-image-lifetime-workspace-20261103T055106Z-0c0909f9/receipt.json`.
Icarus exited zero and emitted a hierarchy dump in 15.65 seconds, but the
wrapper failed on 262 lifetime-input coercion warnings. The saved repair
replaces propagated `tri0` ports with wire inputs and explicit-one
qualification; no second compile, functional simulation or synthesis ran.
The failed receipt predates that wire-only repair and is not a final-source
pass. Independent Verifier must re-elaborate before bounded directory/workspace
and top-progress execution. No old receipt or timeout was changed.

## Historical handoff: workspace declarations and directory traversal repair

`rtl/anvil_en1_replay_workspace.sv` relocates five existing typed wires
before their first use, repairing the next whole-top width-resolution failure
retained at
`evidence/preparation/synthesis-declaration-repair-20261103T043019Z-8fceeaee/receipt.json`.
No expression, width, accounting rule or registered behavior changes there.

`rtl/anvil_en1_tensor_image.sv` removes the quadratic prior-reread path
for entries whose normalized layer/kind keys and disjoint payload ranges
form an increasing prefix. It reuses the existing prior-entry register;
one additional certification bit is included in `controller_bytes`, with
no rounded-byte increase. Every entry still undergoes complete validation.
Any ordering failure switches permanently to the original exhaustive scan
for the rest of that lookup, preserving arbitrary-order image compatibility,
duplicate detection and nonadjacent overlap rejection. SPEC records the
proof, exact cycle boundaries, counts and required independent cases.
There is no cross-lookup validation cache or stale-image assumption.

The retained source-matched top progress receipt,
`evidence/preparation/top-public-progress-20261103T043245Z-b1b56db9/receipt.json`,
failed incomplete before any tensor payload read or logit. Its 177735 directory
reads motivated this traversal repair, not a change to the workload or budget.
The source-derived linear certified-path read counts do not prove top-level
completion, numerical correctness, synthesis or timing. Independent Verifier
must rebuild and recheck those outcomes. Tests, immutable references, runtime
metadata and all prior receipts remain untouched.

One fast static Icarus 12.0 whole-top elaboration passed with exit zero,
empty stderr and a hierarchy dump in 14.705 seconds, without timeout:
`evidence/preparation/static-workspace-directory-repair-20261103T044222Z-7c18f486/receipt.json`.
The existing project retention helper records exact argv, hashes, tool version,
raw streams and a link to the retained workspace synthesis failure. Its RTL
hashes include both repairs; document hashes precede this outcome annotation.
Only `-t null` ran, not functional simulation or synthesis. Independent
whole-top synthesis and bounded progress rechecks remain required, as do
all six mandatory suites and the native timing/STA/HIL gates.

## Retained handoff: attention generate-scope declaration-order repair

Both retained whole-top Yosys attempts failed to resolve the width of
`engine.attention_component_data` in the output-conversion concatenation:
`evidence/preparation/synthesis-top-initial-20261103T035403Z-aabb1589/receipt.json`
and
`evidence/preparation/synthesis-top-deferred-20261103T035515Z-7be8d9c4/receipt.json`.
Those receipts and raw diagnostics remain unchanged.

In `rtl/anvil_en1_asym_attn_ple.sv`, the existing 16-bit
`attention_component_data` declaration now precedes its first use.
Inspection of the same generate scope also found `head_offset` used in
the weight-reader column expression before declaration; its existing
32-bit declaration and unchanged expression now precede that use.
These are declaration relocations only: arithmetic, connectivity,
registered behavior, report widths and allocation charges are unchanged.
No verification sources, parent sources or runtime metadata were edited.

This repair was inspected with file reads and source search; no compiler,
simulation or synthesis command ran in this handoff. Earlier static
receipts below predate these relocations and are not current-source
acceptance. Independent Verifier must recheck the affected whole-top
synthesis and rebuild a source-matched bounded progress diagnostic linked
to the retained simulation timeout at
`evidence/preparation/top-parent-geometry-repair-20261103T034532Z-05aaa34c/receipt.json`.
Do not repeat the unchanged timed-out workload or increase its timeout.
All six mandatory suites and fresh native timing-lint, Quartus STA and
HIL gates remain pending; this is a design repair handoff, not acceptance.

## Retained handoff: report-sizing repairs statically elaborate

The saved RTL is ready for independent Verifier handoff. One newly
authorized Icarus 12.0 static elaboration of the report-sizing repairs
exited zero in 15.405 seconds, emitted no stderr diagnostics, did not
time out and produced a complete hierarchy dump:
`evidence/preparation/static-report-sizing-20261103T033622Z/receipt.json`.
That receipt retains exact expanded argv, source hashes, tool identity,
timestamps, the 180-second watchdog, raw streams and a repair link to
the preceding receipt. It used `-t null`, not simulation or synthesis.
Its RTL hashes describe the current implementation; document hashes
precede this status update.

Read-only source/dump reconciliation covers all 95 repaired size
declarations in their 471 connected instances. The 468 directly
constant-driven sizes match the declared operand widths and parameter
adjustments, with zero mismatches and no nonpositive/wrapped sizes.
The other three retain static expression nodes: dispatcher 1142 bits,
full ledger 3450 bits and prospective ledger 2946 bits. The two ledger
reports correspond to 142 and 121 generated 24-bit reduction registers
plus 42 control bits, producing the documented 432/369-byte charges.
No additional RTL change was needed.

The two original failed static diagnostics and subsequent successful
binding receipt remain unchanged. The retained generate-scope and
reserved-keyword repairs, 95 report-net conversions and cache metadata
rounding repair remain in place. Only design documentation changes in
this continuation; tests, parent sources and runtime metadata remain
untouched.

Tools used here were view/glob/rg, read-only Python source/dump
inspection, the one Icarus static invocation with its receipt, and
apply_patch for these documentation updates. Independent Verifier owns
all functional/numerical/reference, mutation, benchmark and synthesis
execution. Actual liveness, allocation success, traffic reductions,
resource fit and timing are not established by this handoff. All six
mandatory suites and shared-runtime timing/STA/HIL gates remain pending.
Historical unfinished-state statements below are superseded only for
static binding and declaration-size reconciliation, not acceptance.

## Retained diagnostic: resolved binding and report-sizing repair

A newly authorized static elaboration of the saved generate/name repairs
succeeded with Icarus 12.0 in 15.707 seconds, exit zero and no stderr.
The exact command, tool identity, source hashes and hierarchy dump are
retained at
`evidence/preparation/static-binding-20261103T033046Z/receipt.json`,
linked to the preceding failure. It used `-t null`; no simulation or
synthesis ran. Both original failed receipts remain unchanged.

The dump exposed an allocation-report bug, not a functional pass:
register-dependent `$bits` report localparams resolved prematurely to
zero (459 instances) or negative sizes (five instances). All 95 such
declarations in 93 RTL files now use continuous constant nets. Their
operand lists and report equations are retained; only evaluation context
changes. No datapath/state/storage geometry changes. Cache tags and its
occupied bitmap now also round separately, fixing a one-byte metadata
undercount for capacities such as C=1 without lowering any charge.
These repairs postdate that earlier static receipt; their later static
elaboration is recorded in the current handoff above.

SPEC now contains a disjoint per-instance array/backing census: 43 native
arrays, 5206835 declared bytes at production C=3; two CSR arrays already
charged in integration add 928 bytes; 58 immutable-parent arrays reserve
451008 more bytes. The native payload table accounts for all 38 payload
arrays and five metadata arrays, including shared text/native banks.
Replay frame/memo/scalar backing is part of the one frontier array,
not another physical allocation. Compact sizes are source-derived,
not separately elaborated. These totals exclude scalar registers and
are not live peaks or inferred-M20K measurements.

Used view/glob/rg, Python source/dump inspection and a narrowly scoped
bulk report-declaration refactor, apply_patch, and the one retained
Icarus static invocation. Tests, parent sources and runtime metadata
remain untouched. The current handoff above resolves the then-remaining
static elaboration and declaration-sized-report obligations. Independent
Verifier owns all functional, numerical, mutation and synthesis checks.

## Retained preceding diagnostic: static parse failure and saved scope repair

The one reserved fast static elaboration ran with Icarus 12.0. Its
unchanged receipt is
`evidence/preparation/static-elaboration-20261103T032650Z/receipt.json`;
argv/source hashes, raw stdout/stderr and tool identity are retained there.
It did not produce an elaborated hierarchy. The first syntax error points
at the attention head's `endgenerate`: the legal generate branch was missing
the `end` after its sequential process. Following module definitions then
generated cascading scope/declaration errors.

The attention-head missing `end` repair remains saved. One fresh bounded
static continuation is retained at
`evidence/preparation/static-repair-20261103T032829Z/receipt.json`,
linked to the original failure. It exited 210 in 0.415 seconds and
produced no elaboration dump. Its first error is now the frontier's
`endgenerate`, not the repaired attention head. The original compiler's
zero exit despite syntax diagnostics remains a failure, not a static pass.
Both receipts and all raw logs are preserved unchanged.

Source inspection found two more missing legal-generate-branch closures:
`rtl/anvil_en1_frontier.sv` and `rtl/anvil_en1_local_ring.sv` now close
their legal branches after the sequential processes. In
`rtl/anvil_en1_vision_bins.sv`, the bitmap identifier `bins` is a reserved
SystemVerilog keyword; it and its three accesses are now `bin_payload`.
No datapath, RAM extent, state, report expression or protocol changes.
The three latest repairs have not been elaborated. A read-only source
delimiter scan finds balanced paired delimiters in all 95 RTL files,
which does not establish legal HDL or resolved connections.

SPEC adds scoped physical declaration/report reconciliation for the
frontier payload/tags/occupancy, local ring payload/tags/occupancy and
vision bitmap. Their payload reservation subtotal is 5122336 production
bytes and 837984 compact bytes; frontier/ring metadata is 1536/393 bytes.
Both ordinary backing ranges end exactly at their frontier array's last
declared word. Native bitmap storage is unchanged at 1824 bytes. These
are source-derived physical reservations, not live peaks, synthesized RAM
use or a whole-hierarchy declaration census.

Only view/glob/rg, apply_patch, read-only Python source/integer inspection
and the single Icarus static command ran in this continuation. No
functional simulation or synthesis ran; tests, immutable parent sources
and runtime metadata were not edited.

Remaining: obtain an authorized fresh static diagnostic or independent
Verifier diagnostic on the saved repairs, resolve any remaining binding
errors, and finish whole-hierarchy per-instance declaration/backing
reconciliation. Neither failed receipt is acceptance evidence. The
reserved attempt and fresh continuation diagnostic are consumed; older
statements that the reserved check is unused are historical.
This is not a ready design handoff.

## Current closure: finite small-context replay liveness

The scheduler's decreasing rank bounds scalar slots, but not every text
ancestor owns two full vectors. `replay_frame_input` yields an absent
predecessor before issuing any frame-copy request. After a successful
binding, historical attention requests descend to the actual nonshared
owner's input. A vector-retaining chain can contain one upper shared
consumer, at most 15/24 nonshared layers and the text input frame.
Conservatively charging two H-wide vectors to every one of these frames
gives `2*(owners+2)*H_bytes`; empty initial-predecessor ancestors retain
their full scalar charge. Native dependencies cannot reenter text.

SPEC records a uniform fallback envelope covering those text banks, all
61 scalar slots, all sixteen memo payloads, native suspended/active state,
private arithmetic, outer consumers, resident words, metadata and every
connected controller report. It deliberately counts native scalars and
the protected native memo twice rather than relying on an eviction to
remove a live reference. Totals are 282462/487262 bytes for E2B/E4B,
below 45% of even the minimum padded baselines, 688128/1605632 bytes.
They are context-independent upper bounds while the baselines increase.
The single-token linear path stays implemented but is not used as a
substitute for a two-/17-token replay execution in this argument.

Native feature/embedding phases outside encoder descent have a conservative
59549-byte necessary envelope, including an outer destination, both feature
frame banks, embedding/PLE storage, protected source and all native
controllers. Encoder descent remains bounded by the 85229-byte cut.
Ordinary feature evaluation has no suspended text replay stack and releases
its memo on scheduler completion. Both necessary native envelopes fit the
minimum 86016-byte E2B M allowance after unpinned eviction. Ordinary text
workspace and the separate fallback working partition retain their
30710/38902-byte and 58587-byte envelopes, respectively.

These are source-derived feasibility bounds, not measured peaks,
successful grants, numerical execution, physical RAM inference or timing.
No live/shadow report, grant threshold, RTL schedule, required check or
acceptance condition changes in this increment. The independent Verifier
must exercise real misses and evictions and observe all those allocations.
Read-only Python recomputed the integer bounds; it ran no HDL. The later
reserved static attempt and its failed parse are recorded above. The
remaining design closure is successful static elaboration and per-instance
declaration/physical-backing reconciliation before Verifier handoff.
Older unfinished-state assessments below are retained chronologically and
are superseded only for this small-context liveness obligation.

## Current increment: replay-result lifetime and partition reconciliation

Both fallback result consumers now delay their full empty destination until
the first real evaluator output. The frontier executor starts fallback replay
without component 2; owner replay starts fallback owner-input evaluation
without component 6. Each holds the first output stalled through its existing
registered allocation request/response, then accepts/writes data only after
the successful grant. Frontier counting and RAM writes now explicitly require
the result handshake. The ordinary owner path still grants its normalized
source bank before its owner tile starts; local-ring hits are unchanged.

Grant denial retains error 7 and drains/discards the active evaluator's
remaining output and actual completion without RAM writes, successful counts
or commit. It cannot strand a live evaluator behind an error response.
Pre-output evaluator failures need no destination grant. Existing state widths
and registers suffice, so controller and physical RAM reports do not shrink.
Reset and stalled-payload rules retain their original contract.

This lifetime change follows the actual scheduler: root output starts only
after completed-vector memoization, frame pop and return-stack retirement.
Thus no unfilled outer result reservation is needed during text/native
descent. The completed memo and scalar readback remain charged while output
is stalled. There is no host answer, hidden vector or numerical change.

SPEC now reconciles current byte-rounded source report equations, rather than
reusing the older connected counts. Complete replay is 31121 bytes; binding's
reported subtree 32290; its native subset 26085; ordinary executor 4140.
The current fallback-aware observation/admission ledgers are 432/369 bytes,
not the earlier 408/345. Replay visibility metadata is 1208 bytes, not 1192.
Counting each term once gives 15861 fixed non-native workspace bytes at C=64;
the conservative compact/production envelope is 15862.

Ordinary E2B/E4B global coexistence envelopes, including retained vectors and
owner source/head, become 30710/38902 bytes against 32768/65536. Fallback's
fixed working envelope including native controllers and resident words is
42203; the largest replay-post envelope is 58587 bytes against 65536.
The new output scheduling removes an otherwise simultaneous empty 5120-byte
destination from that post phase. Native feature and final owner-tile phases
have smaller working envelopes. These are source-derived bounds, not measured
allocation peaks or independent declaration-coverage results.

Rank at most 61 bounds the generic frame payload by 749568 bytes, scalar
slots by 8296, and sixteen live memo vectors by 81920. Together with the
working envelope the coarse fallback bound is 898371 bytes, below 1 MiB.
The bound alone does not establish strict savings for all small test-forced
fallback contexts; reachable frame allocations and the linear single-token
path still require their own smaller-context/shadow reconciliation.
The 926208-byte replay backing layout and its ordinary/fallback remapping
are unchanged. Full physical frontier reservation remains 4071936 bytes;
idle backing, separate worker RAM and the ring are not removed FPGA memory.

Saved `frontier_execute`, `owner_replay` and both design documents. Used
view/rg/glob/apply_patch and read-only Python source arithmetic; no HDL,
functional/synthesis harness, preparation receipt or reserved static
elaboration. No verification, parent or runtime-owned file was edited.
Remaining before ready: finish the reachable small-context fallback/native
and production-shadow allocation ledger, reconcile all per-instance
declarations/physical backing, then use the reserved static elaboration and
hand off immediately to independent Verifier. Actual grant/eviction,
first-output backpressure, denied-grant drain, reset and numerical behavior
remain independent verification obligations. No acceptance threshold changes.

## Prior increment: bounded readers and demand-granted feature output

Native normalization now reads its schema-fixed BF16 scales directly with a
registered address/read/response FSM. It validates the complete vector extent
from the real tensor directory before starting normalization, rejects an
out-of-range scale index before memory, selects the aligned little-endian lane,
and preserves the former canonical-NaN conversion. Signed zero, subnormals and
infinities retain their bits. This applies to BF16 and Q4 matrix modes because
both retain BF16 normalization scales. Normalization arithmetic and reduction
order are unchanged; its unused matrix/Q4 reader and scale FP arbitration are
gone, not replaced with a computed answer.

Both general weight and tensor-image readers now use one registered 16x16
partial product and a separate registered 64-bit accumulate step for exact
unsigned row/stride calculations. Four partials produce each 32x32 product;
the general weight reader serializes row offset and total extent. Existing
dimension/range/overflow checks and actual BF16/Q4 reads remain. This exchanges
setup cycles for bounded controller state, not numerical accuracy or traffic.

SPEC reconciles per-instance byte rounding and connected multiplicities:
10 native norms save 175 bytes each (including removal of their old scale
reader), 41 remaining directories save 28 each, and 27 remaining general
weight readers save 59 each. The complete reported native-reconstruction
controller becomes **26085 bytes**, superseding 30576. No changed report is a
measured allocation, elaborated declaration-coverage result or synthesized
resource claim.

Tracing the outer lifetime exposed a separate real obstruction: the ordinary
frontier preallocated its full model-width feature destination before invoking
the recursive encoders. Even after the controller reduction, the conservative
vision set plus that E2B destination required `85229+3072=88301` bytes, above
the minimum 86016-byte native allowance. The executor now starts native feature
evaluation without that reservation. When its first real output appears, keep
the output stalled, perform the existing component-3 grant, then accept/write
the first beat only after grant success. The original complete vector and
embedding-consumption release still apply. Physical destination RAM remains;
there is no hidden staging register/vector or speculative write. Errors before
output do not allocate a destination. A denied first-output grant retains error
7 and drains/discards the already started evaluator's remaining output and real
completion, without writes or successful counts, before reporting failure.
This prevents the new deferred-grant error path from leaving a stalled root
that would block session drain. The added state fits the existing six-bit FSM.

SPEC now enumerates finite post-eviction necessary encoder sets, including
136-byte scalar slots, the one protected source memo, active audio final binding
and the outer image pool vector: 85197/81749 bytes for positive/layer-zero audio
and 85229/82293 for positive/patch-input vision. These are conservative
source-derived necessary sets after unpinned memo eviction, not executed peaks.
The maximum leaves 787 bytes at minimum-context E2B; minimum E4B's allowance is
200704 bytes. No additional frame-count assumption is introduced: audio allows
twelve positive layers plus input; vision allows sixteen plus input. The outer
feature destination's later grant follows root completion/pop, when its retired
6144/6432-byte private reservation exceeds either model's new destination.

This retires the previous coarse encoder-depth and premature outer-destination
obstruction, not whole-system storage acceptance. The ordinary text, remaining
embedding/feature and fallback partitions, complete declaration coverage and
physical backing still require joint reconciliation. Existing grant thresholds,
all acceptance obligations and independent allocation/traffic observations are
unchanged. No legal-work capacity error is authorized.

Saved four RTL files (`native_norm`, `weight_read`, `tensor_image`,
`frontier_execute`) and both design documents. Used view/rg/glob/apply_patch and
read-only Python source accounting; a mismatched patch hunk was repaired after
rereading the exact setup code. No HDL execution, preparation receipt,
functional/synthesis harness or reserved static elaboration. Tests, parent
sources, runtime metadata and retained failures remain untouched. Independent
Verifier must exercise exact scale encodings/errors, all partial-product stages,
first-output backpressure/grant ordering and denial draining, final binding, memo/pool lifetimes and
the unchanged numerical results. Design is not yet a ready handoff.

## Prior increment: native MLP specialization and controller reconciliation

The connected native MLP row has a default-preserving `IMAGE_CLASS`
specialization: mixed (0), vision (1), or audio (2). Vision post-attention
selects 1; both audio feed-forward modes select 2. Validation rejects a
class/mode mismatch before external accesses. Vision retains its actual
GELU GeGLU but omits the separate audio SiLU subtree. Audio retains SiLU
but omits the unused vision GeGLU subtree. Absent branches issue neither
arithmetic requests nor fabricated completions. No payload array,
materialization boundary, legal production job or numerical operation
is removed.

The preceding shared-final-FF1 change removes 2193 declared controller
bytes from the supplied-raw post subtree and two bytes from its raw RAM
read register. Its three added mode bits do not change their individually
rounded byte counts. Therefore its reconciled native report is 31048,
not the older 33243. The current specialization additionally removes
165 bytes from each of the two connected audio MLP reports and 142 bytes
from the vision MLP report: **30576 bytes** in the full nonoverlapping
native-reconstruction report. SPEC enumerates every term, primitive
subtree and rounding boundary. This is declared source-expression
accounting, not an elaborated register census or measured allocation.
Physical payload RAM and the suspended-vector ceilings are unchanged.

Whole-system capacity is still **not closed**. The incomplete comparison
`30576+4096+12*(4096+136)=85456` leaves only 560 bytes of minimum-context
E2B's native allowance; it omits protected memo, active final-binding
extra slice and outer native continuations. Neither this arithmetic nor
the twelve-layer depth bound establishes reachable fit. Next reconcile
the layer-zero versus active-positive cases, final-binding and memo
lifetimes, outer consumers and ordinary/fallback/physical partitions.
Further genuine sharing/rematerialization is necessary unless the full
reachable-case proof fits without denying legal work.

Saved three RTL files (`native_mlp_row`, `audio_feedforward`,
`vision_post_layer`) and both design documents. Used view, rg, glob,
apply_patch and read-only Python source-expression arithmetic. Initial
arithmetic helper parsing failures supplied no bound; corrected literal
sums and traced report connections support the table. No HDL execution,
functional/synthesis harness, preparation receipt or reserved static
elaboration. Tests, parent sources, runtime metadata and retained failures
remain untouched. Independent verification must cover mixed/specialized
workers, both audio modes and precisions, vision, class rejection before
accesses, reset/stalls/errors and exact controller/traffic/allocation
accounting. This is a partial design increment, not a ready handoff.

## Prior increment: shared final audio FF1 reconstruction

The packed history residual now uses the numerical-head preprocessor's
existing real FF1 datapath for its final unnormalized residual, rather
than instantiating a second FF1 inside post-attention. New registered
`raw_only` inputs in `audio_pre_attention` and `replay_audio_attention`
stream the actual FF1 outputs with backpressure and successful child
completion, omitting only the subsequent attention-input clamp-copy and
normalization passes. Q/K/V reconstruction retains those original passes.

The default-off `FINAL_FEEDFORWARD` specialization in `replay_audio_heads`
requires deferred binding and is enabled only by the packed residual.
After heads complete it demands the real pinned query memo, yielding
the existing fully tagged final-binding continuation on a miss before
starting FF1. Raw-only FF1 then writes bank 0/slice 0 in ascending pairs;
no private query copy or host-supplied result is used. It cannot change
dependencies mid-job. Existing partial heads, depthwise output, scalar
checkpoints and the protected memo remain charged.

The default-off `PRECOMPUTED_RAW` post-attention specialization removes
the second FF1 subtree and its private working/branch RAM at elaboration.
It also omits its raw residual RAM: after output projection/norm it reads
the actual frame-backed FF1 component through the existing kind-0 source
channel, registers it, then executes the unchanged FP32 add/BF16 narrow.
Only the exact current output cursor may be read. Both components are
consumed before their aligned output pair overwrites the original values.
Head reads remain restricted to the pre-output phase. A failed raw source
response drains the active normalization before error completion.

Source-defined connected payload RAM falls by 6144 bytes: the absent 4096-byte
callback FF1 working/branch store plus the absent 2048-byte raw store.
No numerical-head RAM, dispatcher shared bank or workspace frame is
claimed as removed. Packed post private live payload is now limited to
2048 bytes; the overall positive-audio private reservation stays 4096
because other phases still need it. Existing default standalone paths
and the 136-byte scalar slots are retained.
These are source-defined storage extents, not measured M20K/resource
reductions or synthesis results.

The prior 33243-byte native controller census is superseded, not a current
measurement. Its update removes the duplicate FF1's eight reported
controller terms and raw read register, while adding the three new mode
bits to their byte-rounded local reports. SPEC enumerates the exact
terms and cycle/lifetime obligations. A new complete connected numeric
census and the reachable whole-system bound are still pending. In
particular, the 4096-byte suspended-vector ceiling per positive audio
frame is unchanged; memo/outer lifetimes and both models' native/fallback
partitions still need closure.

Saved `audio_pre_attention`, `replay_audio_attention`, `replay_audio_heads`,
`audio_attention_residual`, `replay_audio_residual` and both design
documents using view/rg/glob/apply_patch. No HDL execution, simulation,
synthesis or preparation receipt. Tests, immutable parent sources, runtime
metadata and retained failures remain untouched. Design is not ready;
the reserved static elaboration remains for the completed design handoff.

## Prior increment: active audio residual source lifetimes

The replay layer now obtains lightconv's residual through a default-off
`RAW_SOURCE_CALLBACK` specialization, rather than copying the raw frame
into a private bank. Validation enters depthwise work directly. Each
successful clipped projection requests its real raw component, registers
the response/error, then performs the unchanged FP32 add and BF16 narrow.
The default path retains its original initial raw-copy pass.

Lightconv reads raw bank 0 in ascending output order while its output
replaces that bank in aligned pairs. Both source reads complete before
the corresponding pair write, and the caller awaits the write response.
Its source validator now permits nonzero output cursors only when the
requested raw index equals that cursor and is below 1024. Supplied
depthwise reads still precede all outputs. No overwritten raw component
can be revisited by this schedule.

FF2 also enables the existing raw callback. It rereads unchanged bank 0
for its input and final residual passes, while writing separate bank 1.
The original bank release occurs only after successful FF2 completion.
This keeps every original input live until its actual last read, without
a private duplicate or off-chip activation spill.

The active private maxima are now 4096 bytes for numerical-head
preprocessing, frame-backed post-attention and FF2, and 2048 bytes for
supplied-depthwise lightconv and the channel fold. Final norm/clamp has
no private vector RAM. Dispatcher admission, workspace descriptor
validation and child range guards agree on the new serialized 4096-byte
positive-layer maximum. Existing mutual-exclusion guards remain.

The shared replay payload backing stays physically 6144 bytes. Callback
lightconv removes a local raw RAM only in its standalone local-RAM
elaboration; the connected external-RAM variant adds no scalar registers.
Thus the preceding source-derived native controller report stays 33243
bytes, not an experimentally observed or elaborated census.

Whole-system capacity is **not closed**. The conservative comparison is
`33243+4096+12*(4096+136)=88123`, still above minimum-context E2B's
86016-byte native allowance before memo/outer state. A full-depth
suspension uses the smaller layer-zero active worker, but no complete
reachable-case proof follows from that fact. Remaining work is to close
suspended-vector and pinned-memo/outer lifetimes, reconcile both models'
ordinary/fallback and physical partitions, and then run the reserved
static elaboration before independent Verifier handoff.

Saved `audio_lightconv`, `replay_audio_layer`, `replay_execute`,
`replay_workspace` and both design documents. Used view/rg/glob and
apply_patch only; no HDL execution, functional/synthesis harness or
preparation receipt. Tests, parent sources, runtime metadata and original
failures remain untouched. SPEC freezes the changed cycle/lifetime table
and independent checks, including source indices around pair and channel
boundaries, both callback/depthwise settings, read-before-overwrite,
partial-output errors, reset/stalls and actual/shadow allocation.

## Prior increment: frame-backed FF raw-source rematerialization

Frame-backed post-attention needs the raw first-feed-forward residual,
not the additional normalized query stream produced by the standalone
pre-attention wrapper. Connect its real feed-forward engine directly,
leaving attention's separate Q/K preprocessing intact. The specialized
FF reads its immutable raw input frame through the existing callback
both for input clipping and for final residual addition, instead of
keeping a duplicate raw vector. No scalar result or hidden vector is
provided by software.

The callback setting defaults off. Both modes retain the same numerical
operations and registered request/response behavior; a second raw-input
read adds real reconstruction traffic. During MLP the child owns working
and branch (4096 bytes). During output it owns branch (2048) while the
caller fills raw residual storage (2048). The frame-backed post-attention
private peak is therefore 4096 rather than 6144 bytes. The local raw
payload RAM is absent in this specialization, saving 2048 physical
payload bytes. Unchanged external/shared physical banks are not claimed
as removed.

The numerical-head preprocessing wrapper also forwards the default-off
callback option, enabled only for the pinned-memo replay instance. Its
shared bank 0 becomes the clipped raw-output bank, rather than a duplicate
raw-input copy. The ledger now sums its partially filled output allocation
with the child's branch allocation during output. The subsequent
normalized cache is allocated only on actual normalized output, as
before. Head preprocessing's private phase ceiling falls to 4096 bytes;
its shared 6144-byte physical RAM remains disclosed.

This closes redundant raw retention and unused query-normalization work
in the frame-backed post phase, not whole-system storage feasibility.
Suspended audio heads/depthwise outputs, other active phases, memos,
outer consumers and fallback partitions still require reconciliation.
The source-derived controller report is now **33243 bytes**, 771 fewer
than before: remove the unused 45-byte wrapper, 10-byte clamp and
720-byte complete native norm; add four bytes for the now-local FF
RAM read registers. SPEC records the nonoverlapping derivation. The
explicitly removed supplied-head arithmetic subtree previously reported
zero and supplies no further claimed reduction. These are source report
counts, not an elaborated census, allocation observation or synthesis.

The frame-backed post's physical payload becomes 8192 instead of 10240
bytes (4096 caller raw/working plus 4096 child working/branch). Head
preprocessing's shared physical payload remains 6144. Its two private
child ceilings are now enforced at 4096 bytes by the existing residual
wrapper, with the original mutual-exclusion guard retained.

The conservative aggregate `33243+6144+12*(4096+136) = 90171`
still exceeds minimum-context E2B's 86016-byte allowance before memo/outer
state; whole-system fit remains unresolved. SPEC records cycle and
independent verification obligations. Also repaired a duplicate `fold_data`
wire declaration retained by the preceding history increment. No static
elaboration, simulation, synthesis or preparation receipt is claimed.

Saved `audio_feedforward`, `audio_pre_attention`,
`audio_attention_residual`, `replay_audio_attention`,
`replay_audio_residual`, `replay_audio_history` and both design documents.
Used view/rg/glob/apply_patch only. Tests, immutable parent sources,
runtime metadata and retained failures remain untouched. Next reconcile
the other active audio phases (lightconv/FF2), reachable suspended frames,
pinned memo/outer consumers and both native/fallback partitions, then
run the reserved static elaboration before independent Verifier handoff.

## Prior increment: channel-serial audio history

The connected history/fold path no longer keeps two complete FP32
convolution-accumulator slices across recursive dependencies. History
now evaluates one depthwise channel through all five taps, reconstructing
the actual full residual for each real tap. The existing fold executes
that channel's real GLU, weight read, separately rounded multiply/add,
and final BF16 narrowing. Leading padding still performs the real
zero-times-weight operations in ascending kernel order, including
exceptional arithmetic. Default vector-fold behavior is retained.

Two completed channels form one aligned output pair; no unfilled high
half is committed. A partial depthwise output occupies bank 1/slice 0,
while packed heads use bank 0/slice 1. Consumed residuals and heads
are released through the existing registered workspace operations.
The last channel retains the final query residual for lightconv, whose
source mapping remains unchanged. Each output-pair response completes
before advancement or successful history completion.

History saves its real channel/low-half state and FP32 partial sum at
scalar indices 32/33 before yielding. On resume it restores and validates
them before restarting the suspended child. Existing scheduler,
numerical-head and head-wrapper checkpoints retain indices 0..31.
All scalar slots now reserve 34 words/136 bytes, including unused words,
in live, shadow and prospective grants; bitmap strides and synchronous
backing extents match. Production/compact backing totals become
926208/827904 bytes. Physical combined frontier/backing grows by exactly
512 bytes in both builds, rather than adding an undisclosed payload bank.
Reset/visibility, tag checking and registered error retirement remain.

The source-derived suspended-vector ceiling falls from 6144 to 4096
bytes per positive-layer audio frame. The local history controller adds
156 bits (109 to 128 byte-rounded bytes), changing the preceding
native controller sum to **34014 bytes**. Scalar visibility metadata
grows separately by 16 bytes. These counts are not observed allocations,
elaboration coverage or synthesis measurements.

Twelve maximal suspended frames and their complete scalar slots have
a conservative `12*(4096+136)=50784`-byte ceiling, 24480 fewer bytes
than before. Simply adding all current native controllers and active
private state still gives `34014+6144+50784=90942`, exceeding the
minimum E2B allowance of 86016 even before memo/outer state. This does
not prove that all maxima coincide; neither does it establish legal
fit. Complete reachable native/fallback liveness and physical partition
reconciliation remain open. No legal-work capacity error is authorized.
The channel schedule greatly increases residual reconstruction and
weight/input reads; no total traffic or latency improvement is claimed.

SPEC freezes the updated cycle/checkpoint/layout table and independent
verification obligations, including channel 511/512, snapshot faults,
partial outputs, final residual retention, grants and actual absence
of accumulator-slice requests. Saved four RTL files and both design
documents using view/rg/glob/apply_patch only. No HDL execution,
simulation/synthesis harness, experiment or preparation receipt.
Tests, parent sources, runtime metadata and original failures remain
unchanged. Next reduce remaining retained head/output state or prove
reachable fit, reconcile all partitions, then use the reserved static
elaboration and hand off to independent Verifier. Design is not ready.

## Prior increment: deferred audio-query binding

Packed-history residuals now select `DEFER_QUERY_BINDING=1` in
`replay_audio_heads`; default zero preserves standalone eager binding.
Attention reads query inputs through the same pinned-memo dependency
path as historical inputs, instead of keeping a second, copied raw
query vector in each suspended frame. A query miss saves the existing
numerical checkpoint and genuinely evaluates its lower encoder layer.
Normalized-source reconstruction, head arithmetic and output pair
materialization remain unchanged.

Only after all eight heads are committed does the existing binder copy
the raw query for post-attention residual execution. If its last memo
dependency names another token, it yields the actual query without
allocating raw storage. The new, fully tagged internal continuation
`0x454e3150` resumes only that final copy, preserving completed heads
and convolution accumulators. History validates and forwards this
marker alongside the existing head continuation. No head result,
source input or completion is fabricated; real rematerialization may
increase work and weight/input reads.

This retires **raw-query retention across packed-head suspension**:
the initial-descent suspended-vector ceiling falls from 4096 to 2048
bytes and the later-tap suspended ceiling from 8192 to 6144 bytes.
The four-slice active final-binding/post-residual phase remains charged,
as do memo slots, partial-head/scalar checkpoints, all accumulators and
every outer consumer. No register or RAM was added, so the preceding
33995-byte declared native controller report is unchanged.

Six suspended frames plus scalar slots now require a conservative
37632 bytes, not 49920, against the same 45877-byte remainder. This
does not establish that six is the reachable maximum or close storage:
twelve suspended positive layers can still retain 73728 vector bytes
before other state. Further genuine scheduling/backing changes or a
complete reachable liveness argument, and native/fallback/physical
partition reconciliation, are still required before the reserved static
elaboration and independent Verifier handoff.

Saved `rtl/anvil_en1_replay_audio_heads.sv`,
`rtl/anvil_en1_replay_audio_residual.sv`,
`rtl/anvil_en1_replay_audio_history.sv` and both design documents.
Used source view/rg/glob and apply_patch only; no HDL check, experiment,
simulation, synthesis, preparation harness or receipt. Tests, parent
sources, original failures and runtime metadata remain unchanged.

## Prior increment: supplied-depthwise specialization and current native census

The tap-streamed replay path already obtains its actual depthwise vector
from `audio_history_fold`. `audio_lightconv` now elaborates its original
depthwise-row and GLU children only in default
`PRECOMPUTED_DEPTHWISE=0`. In the connected supplied-depthwise
configuration those children are physically absent and their interfaces
and reports are explicitly zero, not success-shaped replies. The real
workspace callback, normalization, SiLU, clipped projection, residual and
all wrapper state/accounting remain unchanged. The shared dispatcher RAM
is still fully disclosed; other workers still use its third bank.

Read-only evaluation of connected native-controller report expressions
gives **33995 bytes**, replacing the stale 33221-byte figure. SPEC records
the complete nonoverlapping ten-term sum and production parameter
assumptions. In particular, audio input/layer nested reports contribute
21792 bytes; the new fold's 94 local + 1995 nested bytes remain charged.
With external vector RAM, lightconv's own report stays 355 bytes and its
nested report changes from 3278 to 1222 bytes. Removing the absent
subtrees saves 2056 declared bytes relative to this increment's unpruned
36051-byte native report. This is source accounting, not an elaborated
declaration audit, observed allocation or synthesis measurement.

The corresponding minimum-context E2B remainder is now
`86016-33995-6144 = 45877` bytes for every suspended native frame,
scalar slot, memo and retained feature. Six four-slice audio frames and
their scalar slots alone have a conservative 49920-byte ceiling.
This does not prove that simultaneous occupancy is reachable, nor that
five frames establish legal-workload fit. Mixed-token suspension,
outer consumers and the complete native/fallback partitions remain
unclosed. No memo-hit assumption, active-worker-only ledger or legal-work
capacity error is introduced.

This retires **unreachable supplied-depthwise child retention** and the
stale native report sum, not storage feasibility. Next: close reachable
mixed-token liveness or make a further genuine storage change, reconcile
all actual/shadow/physical partitions and transitions, then use the
reserved static elaboration and hand off to independent Verifier.

Saved `rtl/anvil_en1_audio_lightconv.sv` and both design documents.
Used view/rg/glob/apply_patch and read-only Python source inspection through
bash. Preliminary census helpers had unresolved parsing and yielded no
accepted count; the completed calculation follows actual child reports.
No experiment, elaboration, simulation, synthesis, preparation harness or
receipt was produced. Tests, immutable parent sources, original failures
and runtime metadata remain unchanged.

## Prior increment: committed audio accumulator slice replacement

The connected fold/workspace trace exposed a descriptor mismatch:
`audio_history_fold` replaces committed FP32 accumulator words using
`op=6,target=3`, but the workspace allowed a nonzero audio slice only for
`target=2` initialization. On a later nonfinal tap, channel 512 therefore
reached the valid second slice and was rejected before its backing write.
This is a source-derived diagnosis, not an executed failing test.

`replay_workspace` now accepts replacement on the same legal native-audio
slices 0..2. Exact frame tags, reserved/present consistency and the
existing committed-destination check still apply. Other domains and slice
indices >=3 remain rejected. No allocation, numerical reduction,
publication, counter or physical-storage rule changes. SPEC records the
edge conditions and independent integration cases, including the
511/512 boundary and failure/stall behavior.

This retires the **nonzero-slice replacement descriptor mismatch**, not
the unresolved storage bound. Demand-first descent and consuming final
output remain saved. Later-tap yields still retain up to four slices;
whole-system native/fallback fit and the updated connected controller
census remain required before the reserved static elaboration and
independent Verifier handoff.

Saved `rtl/anvil_en1_replay_workspace.sv` and both design documents.
Only view/rg/glob/apply_patch were used; no experiment, elaboration,
simulation, synthesis, preparation harness or receipt was produced.
Tests, parent sources, original failures and runtime metadata are unchanged.

## Prior increment: demand-first initial audio tap

`replay_audio_history` now evaluates the oldest nonpadding residual before
starting any convolution accumulation. `audio_history_fold`'s new
`FUSE_LEADING_PADDING=1` configuration then evaluates all leading zero taps
and that actual tap per channel, in ascending kernel order, with the
existing separately rounded multiply/add engines and real weight reads.
Its default zero retains standalone single-tap operation. Padding still
executes positive-zero times the actual weight, including exceptional
encodings; there is no arithmetic omission or numerical shortcut.

The first nonfinal fold initializes the committed accumulator slices;
later folds keep their existing pair replacements. For query token zero
the only fold reduces all five taps in scalar registers and narrows
directly into the depthwise output, without any accumulator workspace
operation or phantom accumulator release.

Final BF16 outputs now consume bank 1/slice 0's dead FP32 accumulator
prefix. Output pair `j` replaces old word `j` only after channels `2*j`
and `2*j+1` have consumed their old words and finished arithmetic. Before
the accumulator-slice crossover the destination is strictly behind
unread words; afterward the remaining reads use slice 1. This is serialized
committed-pair replacement, not a simultaneous RAM collision. Query zero
initializes the same slice with the ordinary ordered pair stream because
there is no old accumulator.

History releases only the consumed suffix slice after final completion.
The layer reads the depthwise vector from bank 1/slice 0 and releases it
after successful lightconv, before FF2 reuses that bank. The separate
bank-0 head/output slice is no longer reallocated for depthwise output.
The final-fold frame peak is therefore three slices (6144 bytes), or two
(4096 bytes) at token zero; partial contents remain fully charged and are
never published as a complete vector before successful completion.

This retires eager leading-padding allocation: a frame's first residual
dependency descent has at most its entering and partial-head vectors
(4096 bytes), not those vectors plus padding accumulators (8192 bytes).
No completed real tap is dropped or restarted on a miss, so this is not
restart-after-miss speculation under eviction. The added registers appear
in the fold's local controller census; no array or external spill is added.
SPEC records the exact cycle/materialization boundaries and pending
independent-verification obligations.

Later-tap suspension still permits four slices. Whole-system reachable
mixed-token suspension, outer consumers, private/controller state, memo
pins, scalar slots, production shadows and physical reservations remain
unclosed. Recompute the complete connected census, establish legal native
and fallback fit without erroring legal work, then use the reserved static
elaboration and hand off to independent Verifier.

Saved three RTL files (`audio_history_fold`, `replay_audio_history`,
`replay_audio_layer`) and
both design documents. Used view/rg/glob/apply_patch only; no experiments,
elaboration, simulation, synthesis or receipts. Tests, parent sources,
original failures and runtime metadata remain unchanged.

## Prior increment: tap-streamed audio histories

The connected `replay_audio_history` now consumes one computed residual
history at a time through `audio_history_fold`, instead of retaining five
residual vectors for the later convolution. The new leaf executes the
existing GLU, tensor-directory and BF16/Q4 weight readers, binary32
multiply/add, and final BF16 narrowing. Kernel taps execute oldest to newest
(`0..4`, distance `4..0`); each channel keeps exactly its original ascending
tap reduction. Missing causal taps still execute zero times weight and
addition, preserving exceptional/signed-zero behavior rather than skipping
arithmetic. No software feature, compression or external activation spill
is introduced.

Two existing bank-1 frame slices hold all 1024 FP32 accumulators.
Kernel zero fills them with ordered committed pair streams; later taps
read/replace a committed pair in place. The residual uses bank-0 raw/head
slices. Its head slice releases before folding, and its raw slice releases
after a nonfinal fold. The final tap reuses the dead head slice for the
complete BF16 depthwise vector, then releases both accumulator slices.
The frame therefore retains only the raw query residual and computed
depthwise vector at history completion. SPEC records the exact layout,
handshake/release table and materialization rules.

Only residual evaluation yields. The real continuation and all accumulator
state survive it; on resume the interrupted residual finishes before the
fold runs. Completed taps are never restarted, so this does not rely on
restart-after-miss progress under memo eviction. Each fold and every
release must actually return before advancing to the next tap.

Replay lightconv selects its new `PRECOMPUTED_DEPTHWISE=1` configuration:
source indices below 1024 read raw query residuals, and 1024..2047 read
the RTL-computed depthwise vector. The parent validates model/layer/
generation/token/range and accesses the registered workspace response.
The original clamp, norm, SiLU, projection and residual stages remain
connected. Default zero preserves the standalone configuration. The
depthwise vector releases after successful lightconv completion, before FF2.

The new GLU bank and all nested controllers are summed into the connected
physical/live reports, and actual weight, source, projection and GLU replay
events propagate through history/layer telemetry. No reservation or
reported private controller is removed merely because another phase runs.
Physical private RAM grows by the new GLU bank; an eventual physical
overlay is distinct from this live-state improvement.

This retires the six-slice retention milestone: the new source-derived
per-frame ceiling is four slices (8192 bytes), not six (12288 bytes).
It does **not** close native/deep-frame/fallback feasibility.
Twelve conservative maximal frames plus their scalar slots still need
99840 bytes before private/control/outer state. The earlier native
controller census is no longer current after adding the fold subtree.
Next: prove a sufficiently tighter reachable bound or further reduce
suspended state, reconcile every connected actual/shadow/physical partition,
then use the reserved static elaboration and hand off to independent Verifier.

Saved four RTL files: new `audio_history_fold`, changed
`replay_audio_history`, `audio_lightconv` and `replay_audio_layer`
(`rtl/anvil_en1_*.sv`), plus SPEC and this document.
Only glob/view/rg/apply_patch were used. No experiments, elaboration,
simulation, synthesis or receipts were produced. Tests, immutable parent
sources, original failures and runtime metadata remain unchanged.

## Prior increment: consuming pre-attention raw/output overlay

Pre-attention no longer owns a fourth BF16 vector bank. It instantiates
feed-forward with external vector RAM and owns its three synchronous banks.
Each raw residual word is overwritten by the clamped output only after
feed-forward has accepted the registered result derived from that word.
Strictly ascending outputs make the raw prefix dead; a prefetched next
element uses a different address. The subsequent norm starts only after
the entire transformed vector and child completion have retired.
SPEC records the exact edge/ownership table.

Live accounting is the union of the shared bank: include the entire child
report, and charge the wrapper's bank-0 reservation separately only after
the child releases its raw/branch pair. This has no release/reallocation
gap and retains partial data on errors. Physical storage falls from four
to three 2048-byte banks for each pre-attention instance. Three registered
read ports and the new sticky range/collision fault are included in its
controller census; the external child no longer has local RAM/read registers.
Conflicting ports suppress the offending access and retire explicit error 7;
they never select an unreported fallback buffer.

The replay-head normalized-source cache is invalidated and released before
each rebuild, then reserved on its first successful normalized write.
It is not a live input to the rebuilding worker. Keeping its reservation
through FF1 was unnecessary; partially rebuilt data is still retained and
charged through failure completion.

Together these changes reduce the connected positive-audio private envelope
from 8192 to 6144 bytes. Replay-head phases peak at FF 6144, raw output
4096, or normalization/cache output 4096. Frame-backed post-attention peaks
at outer raw 2048 plus FF raw/branch 4096; later projection uses 4096.
Convolution/GLU and FF2 remain 6144. Residual/layer guards, dispatcher
preflight and workspace descriptor validation all enforce the new envelope.
Layer-zero and every suspended frame, memo, scalar slot, production shadow,
complete child sum and fallback working-state limit are unchanged.

This is not whole-system storage closure. Against the earlier conservative
native controller census, minimum-context E2B leaves 46651 bytes for the
remaining native state; four maximal audio frames plus scalars alone are
49664. Six-slice suspension and complete native/fallback allocation
reconciliation remain unresolved. The reserved static elaboration is still
unused, and independent functional/synthesis verification remains pending.

Saved six RTL files: `audio_pre_attention`, `replay_audio_attention`,
`replay_audio_residual`, `replay_audio_layer`, `replay_execute` and
`replay_workspace` (all `rtl/anvil_en1_*.sv`), plus SPEC and this document.
Only view/glob/rg/apply_patch were used; no probes or receipts were created.
Tests, parent sources, retained failures and runtime metadata are unchanged.

## Prior increment: audio private-vector last-use release

Feed-forward's normalized entering vector is dead once the final MLP row
has retired successfully and its branch write has committed. Its working
reservation/visibility now clear at that edge, before post-normalization
and residual streaming. The raw and branch banks stay charged through
completion, including stalls/errors. The new independent flag is included
in the controller census; its added bit does not cross the rounded-byte
boundary in either RAM configuration. Physical RAM sizes are unchanged.

Pre-attention no longer reserves its output working bank during the
feed-forward input/MLP phases. It reserves it on the first accepted raw
output before the clamp/store. The outer attention residual likewise
reserves raw on its first valid raw write, not job acceptance. These are
real first-write/last-use boundaries: no live payload is elided, no output
is precomputed, and partial buffers remain charged after failure until
the existing response retirement.

The connected replay-head maximum falls from 10240 to 8192 bytes:
cache 2048 + FF 6144 before output, or cache 2048 + pre-attention working
2048 + FF raw/branch 4096 during output. Frame-backed post-attention has
FF 6144 before output, then outer raw 2048 + pre-attention working 2048 +
FF raw/branch 4096. Its later projection/residual phase remains 4096.
Convolution/GLU and FF2 remain bounded by 6144. Consequently the residual
and layer overrun guards, dispatcher preflight and workspace's independently
validated audio private descriptor now all enforce 8192 bytes. Layer-zero
subsampling stays 512 bytes.

SPEC records the exact cycle/ownership table and pending independent cases.
Arithmetic, operation/reduction order, memory channels and external
top-level interfaces are unchanged. The full actual child sums, frame
and memo/scalar charges, production shadows, controller census and strict
savings comparisons remain independent of the smaller admission envelope.
The existing fallback 64 KiB working-state check is not weakened.

This retires an overlong private-vector lifetime and reduces required
private admission by 2048 bytes. It does **not** solve suspended histories:
the six-slice frame bound is unchanged. With the earlier native census,
minimum E2B scratch now has 44603 bytes left before all other native state,
still less than four maximal history frames plus scalars (49664).
Complete deep-native and fallback partition reconciliation remains open.

Saved sources: `rtl/anvil_en1_audio_feedforward.sv`,
`rtl/anvil_en1_audio_pre_attention.sv`,
`rtl/anvil_en1_audio_attention_residual.sv`,
`rtl/anvil_en1_replay_audio_residual.sv`,
`rtl/anvil_en1_replay_audio_layer.sv`,
`rtl/anvil_en1_replay_execute.sv`, `rtl/anvil_en1_replay_workspace.sv`,
SPEC and this document. Tools used: glob, view, rg and apply_patch.
No elaboration, functional/synthesis probe, preparation harness or receipt.
Tests, parent sources, failures and runtime metadata are unchanged.
Next: genuinely reduce retained native suspension state or establish its
reachable fit, reconcile all allocations, then use the reserved static
elaboration and hand off to independent Verifier.

## Prior increment: fallback arithmetic/control/resident enforcement

The previous allocation paths enforced the complete fallback 1 MiB ceiling
but did not separately enforce the admitted 64 KiB working-state partition.
Both prospective admission and observed completion now enforce the latter
for actual and production-shadow allocations, without changing either
the total ceiling or the strict 45% matched-baseline comparison.

The ledger reuses its two workspace reduction trees, conditioned on the
sampled representation. Ordinary samples retain their existing envelope
and checked native-scratch subtraction. Fallback samples instead sum all
equivalent terms except field 5, the separately charged frame/memo/scalar
payload. They do not subtract native scratch. Resident words, private
vectors, arithmetic, descriptor/progress/visibility metadata, all reported
controllers and integration state therefore remain in the working sum.
Field 5 remains in the complete equivalent total. No representation is
freed, hidden or moved to an uncounted buffer by this change.

New leaf outputs `fallback_working_bytes` and
`fallback_working_shadow_bytes` are wired to the top's observation guard
and the admission engine. They are zero for ordinary samples; ordinary
text-workspace outputs are zero for fallback samples. Both follow the
existing sixth-register sample/model/mode tags. Mode-conditioned reduction
leaves have distinct sharing identities, and all added registered nodes
remain in each ledger's automatic controller census. No top-level interface,
numerical operation, external traffic class or pipeline latency changes.
The earlier <=32200-byte ordinary-text estimate is historical, not a
certificate for the changed controller census.

This retires the missing fallback working-partition enforcement milestone,
not the feasibility milestone. The six-slice suspended audio issue below
is unchanged; complete native/deep-frame/fallback fit and per-instance
accounting remain unfinished. An allocation denial still identifies a
design failure, not an accepted implementation for legal work.

Saved files: `rtl/anvil_en1_allocation_ledger.sv`,
`rtl/anvil_en1_allocation_admission.sv`,
`rtl/anvil_en1_allocation_guard.sv`, `rtl/anvil_en1_top.sv`, SPEC and this
document. Actual tools: glob, view, rg and apply_patch. No commands,
elaboration, simulation, synthesis, preparation harness or receipt ran.
Tests, parent sources, existing failures and runtime metadata are unchanged.
Next: genuinely reduce suspended native state or prove its reachable fit,
reconcile all partitions, then use the reserved static elaboration and
hand off immediately to independent Verifier.

## Retained closure assessment: suspended-audio liveness

The suspension-state enumeration is now explicit in SPEC. At history
distance D, the frame retains D completed histories. A dependency yield
can additionally retain its entering vector and a partial head-output
slice, for D+2 slices and a maximum of six. Consuming relocation removed
copy overlap, not those distinct live values. Neither a yield nor memo
eviction releases them.

Predecessor-first audio scheduling bounds a single chain's redundant
ancestors, not nested historical consumers. Every nested consumer decreases
encoder layer, giving at most twelve positive-layer audio frames and one
active layer-zero frame per audio descent, before outer text/feature
consumers. The conservative positive-layer vector bound is therefore
147456 bytes, not one 12288-byte frame. Compact builds preserve native
audio width, so their production-shadow ledger cannot elide this issue.
This is a finite source-derived upper bound, not an observed reachable
maximum or a simulated failure.

At minimum E2B context, B=688128 and the native allowance is 86016 bytes.
The current native controllers (33221) and active audio private envelope
(10240) leave 42555 bytes for all other native state. Four maximally
reserved audio frames plus their 128-byte scalar slots would already need
49664 bytes. The current rank/chain proof therefore does not certify fit;
no claim is made that this particular simultaneous state was executed.
The ordinary text allowance is not spare native-scratch capacity.

This retires the ambiguity about what the present suspension bound
includes. It does not retire the fit milestone. Next implementation work
must tighten the reachable-state proof or genuinely stream/rematerialize
retained history/head state while preserving numerical continuations and
finite progress under memo eviction. Clearing reservations, relying on
hits, restarting indefinitely or returning capacity error 7 for legal work
is not an acceptable substitute. Full native/deep-frame/fallback allocation
reconciliation must follow before the reserved static elaboration and
independent-Verifier handoff.

Saved changes in this assessment: SPEC and this document only. Actual
tools: glob, view, rg and apply_patch. No elaboration, functional simulation,
synthesis, preparation harness or receipt ran. RTL, tests, immutable parent
sources, failures and runtime metadata remain unchanged by this assessment.

## Prior saved increment: frame-backed audio private-bank reconciliation

The replay post-attention worker already disables local head/cache RAM
accesses under `FRAME_HEADS=1`, but job acceptance still reserved the unused
normalized cache. Its allocation flag now follows `!FRAME_HEADS`, as the
cache-rebuild path already does. Standalone numerical behavior is unchanged.

The connected frame-backed post worker's live-vector maximum is 10240
bytes: its 2048-byte raw reservation plus the pre-attention working bank
(2048) plus the feed-forward child's three banks (6144). The feed-forward
response retires before pre-attention normalization; pre-attention retires
before the outer working bank is admitted. Projection, output normalization
and residual addition then retain only raw+working, 4096 bytes, through
output and completion stalls. The complete private audio maximum, including
the other serialized children, is max(10240 heads, 10240 post, 6144
convolution/GLU, 6144 feed-forward) = 10240 bytes.

The residual's post-overrun guard, layer's history-overrun guard, dispatcher
admission descriptor and workspace descriptor validator all use this bound.
They still observe the full child sums and reject coexistence; no observed
allocation is replaced by a phase-selected value. Layer-zero admission
remains 512 bytes. All scalar/controller and suspended workspace charges
remain independent. Physical RAM and declared controller counts are
unchanged; the conservative ordinary-text envelope remains <=32200 bytes.

This retires the false frame-backed cache reservation and reconciles this
private subtree's phase maximum, saving 6144 bytes of conservative audio
preflight allowance. The prior minimum-context E2B scratch remainder becomes
42555 bytes before frame/scalar/memo/feature allocations. It is not a
whole-system fit or a reduction of six-slice suspended history.

Saved changes: `rtl/anvil_en1_audio_attention_residual.sv`,
`rtl/anvil_en1_replay_audio_residual.sv`,
`rtl/anvil_en1_replay_audio_layer.sv`,
`rtl/anvil_en1_replay_execute.sv`,
`rtl/anvil_en1_replay_workspace.sv`, SPEC and this document.
Actual tools: glob, view, rg and apply_patch. No elaboration, functional
simulation, synthesis or preparation receipt was produced. Tests, immutable
parent sources, original failures and runtime metadata remain untouched.
Remaining: suspended-history storage and finite legal deep-native/fallback
partition reconciliation, then reserved static elaboration and independent
Verifier handoff.

## Prior saved increment: consuming audio-history relocation

The nonfinal audio residual now uses a connected workspace consuming move,
`op=7,target=3`, instead of the history worker's per-pair read/write loop
followed by source release. The move is restricted to the fully tagged top
audio frame, from committed bank-0/slice-0 scratch to an empty legal history
slice. It transfers reservation ownership atomically, copies actual data
through the existing backing FSM, and commits destination visibility only
after the final successful write response. During transfer, one complete
2048-byte reservation covers the remaining source suffix and completed
destination prefix. On failure both representations are unreadable and the
reservation remains charged until pop/invalidation.

The numerical history traversal and convolution layout are unchanged.
Attention's dead slice 1 still retires first; the final residual still stays
in scratch. Source reads are counted from actual accepted backing reads,
including failed responses, through workspace/scheduler/dispatcher wiring,
not inferred from accepting a complete move. No additional RAM, sequential
workspace state or external transaction is introduced. Removing the history
pair register, component cursor, release flag and one FSM bit removes
46 declared controller bits; physical payload capacity is unchanged.

This retires the nonfinal-history copy overlap milestone: one extra
2048-byte vector is no longer needed while relocating a completed residual.
It does **not** reduce the six-slice suspended audio ceiling, prove the
minimum-context native-scratch budget, or establish complete fallback fit.
The conservative <=32200-byte E2B C=64 text bound remains an upper bound.

Saved changes: `rtl/anvil_en1_replay_audio_history.sv`,
`rtl/anvil_en1_replay_workspace.sv`, `rtl/anvil_en1_eval_schedule.sv`,
`rtl/anvil_en1_replay_execute.sv`, SPEC and this document. Actual tools:
glob, view, rg and apply_patch. No elaboration, functional simulation,
synthesis or preparation receipt was produced. Tests, immutable parent
sources, original failures and runtime metadata remain untouched.
Remaining: suspended-history storage, complete native/deep-frame/fallback
partition feasibility and per-instance accounting, then the reserved fast
static elaboration and independent-Verifier handoff.

## Prior saved increment: predecessor-first audio chains at later tokens

`anvil_en1_eval_schedule.sv` now admits the ascending-layer audio schedule
for every legal audio token, including nested dependency misses. Each chain
reconstructs that token's layer-zero input, moves genuine completed results
to memo, pops their frames, then admits the next layer with its pinned
same-token predecessor. The internal return record retains the requested
target layer and original consumer continuation. Chain return validation now
checks the completed token and layer against the popped audio frame instead
of assuming token zero. No new retained scalar or RAM is introduced.

Later-token attention and convolution are not approximated by this schedule.
The numerical workers still yield for each missing historical lower-layer
vector, retain live slices, and resume their actual continuation after that
dependency completes. Nested historical chains therefore remain possible.
Only the initially unnecessary same-token ancestor descent is retired:
the chain no longer retains empty upper same-token frames while first
reconstructing layer zero. This does not certify a one-frame bound for
later-token execution or solve its six-slice suspended-history requirement.
All controller, frame, memo, private-worker and production-shadow charges
remain; the <=32200-byte E2B C=64 text declaration envelope is unchanged.

Saved changes: `rtl/anvil_en1_eval_schedule.sv`, SPEC and this document.
Actual tools: glob, view, rg and apply_patch. No elaboration, simulation,
synthesis or preparation receipt was produced. Tests, parent sources,
original failures and runtime metadata remain untouched. Remaining design
closure: later-token suspended-history storage, complete native/deep-frame/
fallback allocation feasibility and per-instance reconciliation, then the
reserved static elaboration and independent-Verifier handoff.

## Prior saved increment: bounded first-token audio chain

`anvil_en1_eval_schedule.sv` now evaluates native audio token zero from
layer zero upwards using its real completed predecessor. This works both
for direct audio roots and for a missing token-zero audio dependency
under a suspended consumer. Causal attention at token zero has no other
token and convolution's absent taps remain zeros; bidirectional vision
and later audio tokens retain their original schedules.

A nested miss first looks up its actual requested target. If absent, the
existing 256-bit return record saves that target in its four formerly
reserved bits while preserving the original consumer and numerical
continuation. Each genuine result is transferred to memo and its frame
popped before the next audio layer is pushed. The completed predecessor
is pinned through successor admission stalls and passed through existing
mode 2. At the target layer the scheduler restores the original consumer
with its real memo dependency. Full return-tag checks and existing error/
reset cancellation remain; no software result or direct-memory bypass
supplies a vector.

The retired milestone is token-zero audio ancestor retention: the chain
has at most one active audio frame instead of a layer-deep collection of
suspended audio frames, excluding pre-existing outer consumers. All
actual frame, memo, private-worker and controller charges remain. No new
register, RAM or wider state encoding is added; the source-derived
<=32200-byte E2B C=64 text declaration envelope is unchanged. This is not
proof that all native/deep-frame/fallback workloads fit. Later-token
six-slice audio retention, whole-hierarchy partition reconciliation and
actual memo/regeneration/mode-transition closure remain unfinished.

Saved changes: `rtl/anvil_en1_eval_schedule.sv`, SPEC and this document.
Actual tools: glob, view, rg and apply_patch. No elaboration, simulation,
synthesis or preparation receipt was produced. Tests, parent sources,
original failures and runtime metadata remain untouched. The reserved
static elaboration follows complete design closure, before immediate
independent-Verifier handoff.

## Prior saved increment: consuming completed-result memo handover

The scheduler now sets `req_data=1` on its existing internal frame-to-memo
operation. The workspace preserves `req_data=0` as a nonconsuming copy.
The new consuming variant requires the fully tagged top frame, committed
source visibility, its reservation, no partial write, and valid
actual/native/production-shadow subtraction bounds. Other flags or a
non-top move reject before memo selection or backing traffic.

Prospective admission uses one additional registered subtraction stage,
without increasing the state encoding or adding scalar storage. It removes
the transferring source vector from the already calculated candidate totals.
Only after admission succeeds does the workspace atomically remove source
visibility/reservation and establish the pending-memo charge. The unconsumed
source suffix and written destination prefix remain covered as one full
vector; the existing copy and backing-response registers remain separately
charged. All backing reads and writes still really execute and must succeed
before the memo becomes readable. A failing transfer discards both incomplete
representations and propagates the actual failure; it cannot expose the old
frame vector. The scheduler then invalidates. A successful transfer retires
before frame pop, whose bitmap census no longer includes that result.

This closes the avoidable completed-result double-vector reservation
milestone: the scheduler no longer needs a second complete 3072/5120-byte
text, 1536-byte vision or 2048-byte audio vector during handover. Compact
actual bytes and production-shadow bytes remain distinct. Ordinary copies,
all numerical work, physical RAM disclosure and public top interfaces are
unchanged. This is not a reduction of suspended live frames and does not
establish native/deep-frame or fallback fit.

Read-only declaration inspection reconciled scalar census names, packed
expressions, read-register aliases, generated readback charges and occupancy
metadata. No new scalar omission was identified; this is not elaborated
per-instance or executed liveness evidence. The E2B C=64 conservative text
declaration envelope remains <=32200 bytes. Remaining work is legal
native/deep-frame feasibility (including six-slice suspended audio frames),
whole-hierarchy/partition reconciliation and actual eviction/regeneration/
transition closure. The reserved static elaboration is still pending.

Saved changes: `rtl/anvil_en1_eval_schedule.sv`,
`rtl/anvil_en1_replay_workspace.sv`, SPEC and this document.
Actual tools: glob, view, rg, apply_patch and read-only Bash/Python source
inspection. No functional simulation, synthesis, elaboration or preparation
receipt was produced. Original failures, runtime metadata, tests and parent
sources remain untouched.

## Prior saved increment: completed-layer dead-input retirement

The text, vision and audio replay layer workers now retire dead frame inputs
through the existing checked workspace release protocol before publishing
successful completion or starting a successor phase. Text and vision release
bank 0 after their complete post-worker output has reached bank 1. Audio
releases the actually retained convolution histories, then releases convolution
output after feed-forward and feed-forward output after final normalization.
Its final normalized result remains in bank 0. No result or continuation is
provided by a release, and no new external transaction is introduced.

Audio reuses its validated history count as a descending release cursor.
For five histories it releases bank-1 slices 2,1,0 and bank-0 slice 2;
shorter histories release exactly the populated suffix of that sequence.
A one-history job has no copied-history slice and skips that loop.
The convolution result overwrote bank-0 slice 0 only after all historical
callbacks had retired, so that result is deliberately excluded. Subsequent
feed-forward/final-norm input releases each occur after the last output pair
and numerical done response. Text's private PLE live flag also retires when
its final numerical consumer is done, before release-response stalls.

All three workers hold descriptor fields through release stalls, capture the
real workspace response, check its error on a separate edge, and do not advance
after a failed release. They preserve live/partially filled vectors on child
error or dependency yield. No new retained scalar register or wider state
encoding is needed. The workspace still invalidates visibility and subtracts
actual/native/production-shadow vector charges atomically; reuse must obtain
a fresh grant. This is a live-storage lifetime change, not physical RAM removal.

The retired milestone is completed-layer liveness: a successful layer retains
only its result vector for the scheduler's memo-copy/pop sequence. Native
deep-suspension fit is **not** closed: a yielding audio history can still retain
six live slices. The conservative E2B C=64 text declaration envelope remains
<=32200 bytes. Remaining work is the finite per-instance/phase reconciliation
and legal native/deep-frame/fallback fit, including real memo
eviction/regeneration and mode transitions, followed by the reserved static
elaboration and immediate independent-Verifier handoff.

Saved changes: `rtl/anvil_en1_replay_audio_layer.sv`,
`rtl/anvil_en1_replay_vision_layer.sv`,
`rtl/anvil_en1_replay_text_layer.sv`, SPEC and this document.
Actual tools: glob, view, rg, apply_patch and read-only Bash/Python source
inspection. The source inventory still has 94 modules and 52 array declarations;
no functional simulation, synthesis, elaboration or preparation receipt was
produced. Tests, parent sources and original failure/runtime records are unchanged.

## Prior saved increment: directory state reduction and dead-vector retirement

The tensor-image reader retains only the header's image length, directory count
and offset, the current entry's eleven meaningful words, and the prior entry's
identity/offset/length. Two sticky flags validate every discarded constant or
reserved header/current-entry word at its original final validation boundary.
All external reads, full-directory/overlap checks and memory-error priority
remain. Its complete local census falls from 269 to 201 bytes. A literal
hierarchy traversal finds 56 connected directory readers, saving 3808 controller
bytes: 3264 native-reconstruction bytes and 544 non-native text bytes.
SPEC records the nonoverlapping per-instance subtrees. The corresponding
conservative E2B C=64 ordinary-text bound is now <=32200 bytes, not a measured fit.

Vision private preflight now reserves 4608 bytes instead of the serialized
7808-byte sum. The existing sticky RAM-fault monitor observes real child
allocations, rejects tile/O/post overlap and enforces the phase bounds.
Workspace validation and dispatcher admission agree. Physical storage,
suspended frame state and controller accounting are not removed.

The workspace now supports registered release of one complete dead frame
vector. It validates the full frame tag and visibility, checks actual/native/
shadow underflow, then clears visibility and subtracts the matching reservation
atomically. Reuse requires a fresh prospective grant; no RAM initialization or
external spill supplies a value. The scheduler permits release only for its
current frame. Packed audio history uses this operation to retire attention
after a residual consumes it, and to retire a copied residual before starting
the next historical token. Failed/yielded children retain their live vectors.
Two added history-controller bits do not change its 114-byte rounded census.

This retires the directory representation audit, vision private-phase envelope,
and explicit audio dead-vector release milestones. It does **not** close native
deep-frame feasibility: a suspended audio frame can still need six slices.
Minimum-context E2B scratch has 36411 bytes left after native controllers and
the audio envelope, before all other native state; vision leaves 48187 bytes.
Whole-hierarchy accounting, legal suspension/memo capacity, fallback partition
fit and mode-transition liveness remain unfinished. Continue with those exact
bounds and genuine scheduling/backing reductions, not an error return for legal
work. Then use the reserved static elaboration and hand off to independent
Verifier.

Saved six RTL files (`tensor_image`, `replay_vision_layer`, `replay_execute`,
`replay_workspace`, `eval_schedule`, `replay_audio_history`) and the two design
documents. Actual tools: view, rg, glob, apply_patch and read-only Bash/Python
source inspection. No elaboration, functional/synthesis probe or preparation
receipt exists for this increment. Original failures, tests, immutable parent
sources and runtime-owned records remain untouched.

## Current saved increment: guarded audio phase maximum and scalar reuse

Native audio private admission now reserves 16384 bytes rather than the
38912-byte sum of mutually exclusive heads/post-attention/convolution/
feed-forward phases. Both the dispatcher and workspace validate the same
envelope. Connected nested monitors retain the actual child sums, check
phase exclusion and bounds, and latch allocation error 7 on a violation.
Every suspended frame, memo entry, controller and retained feature is still
charged separately. No physical RAM report or numerical operation changes.
The release boundary is child publication before its held response is
accepted; successors start only after that acceptance and parent check.

The streamed ordinary O projection now reuses the already-retired RoPE
result register for its converted component/product, and the not-yet-loaded
layer-scalar register for its fetched weight. Successful result writes remain
in the existing main sequential controller. A model-bounded 12-bit production
row register replaces the 32-bit private row counter; external indices remain
32 bits. The two connected full/post workers save eleven rounded controller
bytes each in production, giving a conservative E2B C=64 ordinary-global
upper envelope of 32744 bytes (24 bytes of margin). This is not a measured fit.

SPEC now reconciles all 39 lexical declaration-name exceptions with generated
ledger counts, conditional RAM-read aliases, visibility metadata and
combinational non-storage temporaries. The updated lexical inventory is
3013 scalar occurrences and 52 arrays across 94 files. It does not replace
literal/generate per-instance reconciliation, independent liveness observation
or FPGA RAM inference. At minimum context, E2B native scratch leaves only
33147 bytes after the prior native-controller census and the revised private
audio envelope, before other native state. Deep-frame/memo feasibility remains
an explicit unresolved design milestone, not permission to deny legal work.

Saved RTL changes are in `asym_attn_ple`, `replay_execute`,
`replay_workspace`, `replay_audio_layer` and `replay_audio_residual`, plus
SPEC and this document. Tools used were view, rg, apply_patch and read-only
Bash/Python source inspection. No static elaboration, simulation, synthesis,
preparation harness or receipt ran. Tests, parent sources and runtime state
were not edited. Remaining: complete per-instance accounting and legal
native/deep-frame/fallback partition feasibility, including actual
eviction/regeneration and mode transitions; repair any overruns, use the
reserved static elaboration, then hand off to independent Verifier.

## Current saved increment: row-streamed attention and exact ledger sharing

The ordinary full-text engine no longer retains the concatenated eight-head
attention tile. It evaluates one O-projection row at a time, replaying the
unchanged Q/normalization/RoPE/attention path for each row. Each emitted BF16
attention component is held under backpressure while the existing weight
reader and shared FP32 service convert, multiply and accumulate that column.
Only after the registered accumulator update is the component acknowledged.
Head/component traversal preserves ascending-column reduction, separate
binary32 rounding and the original final BF16 boundary.

An H-element BF16 output bank retains completed rows independently of the
reused query bank. Post-attention normalization starts only after the final
row write, reads this complete vector and writes the branch bank. The normalized
input remains live through the last head of the final row. O tensor metadata
temporarily reuses the gate descriptor registers; the later real gate lookup
replaces it. A weight/arithmetic error stops new weight reads and drains the
attention child before error completion. Reset invalidates visibility without
initializing RAM. POST_ONLY still consumes its supplied branch normally.

The integrated E2B local/global layer envelopes are 6656/7168 bytes instead of
7680/12288. E4B becomes 10752/11264; compact actual becomes 40/48.
The production output bank reserves 5120 rather than 8192 physical bytes.
This intentionally increases Q/attention recomputation, possible owner
regeneration, weight traffic and latency; their actual counters/transactions
must remain visible. There is no total-bandwidth or throughput claim.

Both allocation ledgers now use elaboration-time identities of their ordered
input leaves to share identical registered sum subtrees. Absent zero subtrees
have no registers. The observed ledger retains all eight metrics; prospective
admission omits only its two unused breakdown metrics with
`REPORT_BREAKDOWN=0`. All admission decisions, actual/shadow accounting, overflow
and subset checks remain. Five registered sum levels and the sixth output/
partition level preserve the existing cycle contract.

Legal allocations total less than 2^23 bytes: ordinary frontier, ring, native
scratch, complete text workspace and resident words total at most 5,308,672
bytes, and fallback at most 1 MiB. Each sum node therefore uses 23 value bits
plus sticky overflow, checking all discarded 64-bit input bits and carry.
Invalid/overflowed sums saturate and reject, not wrap into an admission.
The explicit observation/admission register censuses become 408/345 bytes
from 1062 each. Physical resource fit and timing still require fresh synthesis
and Quartus evidence; register-source counts are not that evidence.

Resident entries now store the independent 34-bit model/owner/token/selector/
head/component-pair key plus visibility. Generation is qualified by the full
generation captured with each fetch and the current registered epoch.
Invalidation drains/cancels old work, clears every occupied bit and only then
advances the epoch. Full-width validation still guards insertion. Thus epoch
bits need not be duplicated per resident entry, and metadata becomes
ceil(35*C/8) bytes. The separately counted cache controller is 464 bits/58 bytes.

Using the preceding connected census and conservatively adding both text
workers' new controller registers gives E2B global complete-text upper envelopes
32239/32256/32766 bytes for C=1/3/64. This is a source-derived estimate,
not a completed allocation run; C=64 has only two bytes of conservative margin.
The whole-hierarchy declaration audit, genuine native/fallback legal-case
partition feasibility, eviction/regeneration and transition liveness still
need closure. Any omitted state or denied legal workload remains a failure.
The finite 94-file lexical inventory records 3015 internal scalar declaration
occurrences and 52 arrays; SPEC identifies the 39 direct-census-reference
exceptions. Port state, aliases and generate multiplicities still need
per-instance reconciliation, so this is not a completed byte census.

Changed `asym_attn_ple`, `frontier_execute`, `allocation_ledger`,
`allocation_admission`, `kv_shared_cache` and the two design documents.
Tools were view, rg, glob, apply_patch and read-only Bash/Python source/count
inspection. No static elaboration, functional/synthesis probe or preparation
receipt exists for this increment. The reserved static elaboration remains
unused; design is not ready for independent Verifier handoff.

## Prior saved increment: exact metadata keys and scoped declaration audit

Frontier layer tags now hold five bits, sufficient for every admitted owner
input layer. The full public eight-bit layer is still validated before a
write and compared against the zero-extended tag on reads. The local ring
stores only the legal token's quotient above its slot bits: eight bits for
the production 512-token ring, fifteen for compact window 4. Model,
generation, owner, token-range, per-lane visibility and retag checks remain
connected. No KV payload or precision changes.

The bounded workspace stores 25-bit domain/layer/token frame and memo keys.
The complete 73-bit request/response descriptors remain. All stored entries
have already passed full-width session, token, layer and exact-length
validation, so their model/generation/length are reconstructed from the
registered session and domain geometry. Narrow synchronous key-read
registers preserve the existing read/response schedule. Successful rebind
or invalidate clears visibility before accepting another request; stale
payload/key contents are never initialized into readable entries.

Pair-progress storage now holds eleven-bit pair indices; the expected
twelve-bit even component is reconstructed without arithmetic.
All six-vector frame slices, individual vector slices and error/reset/
completion paths use the new strides. Full component validation remains.

A read-only scalar-declaration audit of these three modules found no scalar
declaration omitted from their controller/metadata expressions and no
duplicated controller term. Production controller counts are 577/419/2103
bits and metadata counts are 6144/6144/9536 bits for frontier/ring/workspace.
SPEC records their rounded bytes and separately charged RAM arrays.
Both production-shadow metadata consumers in native admission and top
observation now use 768/768 frontier/ring bytes, while actual compact
counts remain 384/8. This does not substitute compact storage for production
shadow allocation.

The connected fixed-text count decreases by 2463 bytes, including 2448
metadata bytes and fifteen rounded controller bytes. At C=3, field 24 is
4893, field 22 is 43753 with unchanged native subset 36485, and total
metadata is 2755. Fixed non-native text terms are 18758. The conservative
global coexistence envelope decreases from 41189 to 38726 bytes, still
5958 above the E2B ceiling. This retires the three scoped metadata declaration
audits, not whole-system fit, native scratch/deep-frame feasibility or
fallback eviction/regeneration closure. Further genuine backing/scheduling
reductions remain necessary; error-7 denial is not accepted legal execution.

Tools used were view, rg, glob, apply_patch and read-only Bash/Python source
inspection. No static elaboration, simulation, synthesis, preparation probe
or receipt was produced. The reserved static elaboration remains pending
complete design closure and independent Verifier handoff is not yet ready.
Tests, immutable parent sources and runtime-owned records remain untouched.

## Prior saved increment: connected census and retained PLE backing

The connected native full-text path now uses the executor's retained PLE
backing instead of copying it into the replay/embedding text-phase PLE bank.
`frontier_execute.SHARED_PLE=1` routes worker vector port 3 to the existing
`feature_payload` bank and returns its enabled synchronous read register.
The outward phase-bank port 3 is disabled for this worker only; replay and
embedding keep their separate backing. `asym_attn_ple.SHARED_PLE=1`
removes the duplicate live/shadow charge, not the numerical PLE path.
Both parameters default off, diagnose illegal values, and require external
vector RAM.

The original embedding stream must commit the complete retained PLE before
text starts. The text load callback then writes back the identical component.
The executor keeps its PLE visibility/allocation until vector commit, rather
than releasing it after the last initial-load callback. Every worker bank
access checks registered layer ownership/reservation, retained visibility,
native-feature exclusion and the complete component address. Conflicting
worker/executor accesses suppress RAM enables and latch the existing
allocation fault for error-7 completion. Reset does not initialize payload.
There is no new scalar register, numerical approximation or external access.

SPEC freezes the complete ownership/boundary table. Field 2 charges the one
retained PLE; field 20 excludes the worker's duplicate PLE. Integrated E2B
local/global reservations fall from 8192/12800 to 7680/12288 bytes, E4B
from 10752/14848 to 10240/14336, and compact actual from 48/72 to 40/64.
The executor feature bank and the replay/embedding phase PLE bank remain
physically present and disclosed in their existing fields. This is a
connected live-backing alias, not removal of physical FPGA RAM.

A finite read-only source census now resolves the connected production
controller-report hierarchy, rather than extrapolating from isolated leaf
reductions. At C=3, field 22 is 43765 bytes, of which 36485 is the existing
native-reconstruction subset. Field 24 is 4896, field 23 is 1195, binding
own state is 139, native own state is 162, metadata totals 5203, and top
integration is 2346. SPEC records the nonoverlapping subtotals and the
source-accounting qualification: these numbers evaluate existing report
expressions; they neither audit every RTL declaration independently nor
observe a workload.

The resulting fixed non-native text terms are 21221 bytes. With global
full-text, retained hidden/PLE and owner-source/head reservations, the
source-derived coexistence envelope was 41701 bytes and is now 41189.
Both exceed the E2B 32768-byte text ceiling. This retires the ambiguity
about whether the prior local reductions alone established fit: they do
not. It is not a measured runtime failure, permission to weaken the ceiling,
or justification for denying required legal work.

Remaining design closure is concrete: reduce that simultaneous ordinary
text envelope with genuine backing/scheduling overlays; independently
audit declaration-to-report coverage; establish native scratch and suspended
frame bounds and actual/production-shadow fallback feasibility, including
memo eviction/regeneration and mode transitions. The reserved static
elaboration remains pending until closure, then independent Verifier follows
immediately. The design is not ready.

Tools used: glob, view, rg, apply_patch and read-only Bash/Python source
inspection. The first simple source inspector rejected a multiline Python
expression, and a later focused inspector could not resolve a parameterized
tag width; the connected expression inspector resolved the reported
subtrees. These were source-reading helpers, not RTL diagnostic probes.
No HDL elaboration, simulation, synthesis, preparation harness or receipt
was produced. Test/parent sources and runtime-owned records, including the
original failure and attempt-0003, remain untouched.

## Prior saved increment: allocation arithmetic and ordinary residual alias

Both allocation ledgers retain all eight metrics, all input fields, their
six-edge observation tags and the existing prospective/completion failure
paths. Their physical reduction registers now hold checked 32-bit byte counts
plus sticky overflow, rather than full 64-bit sums. Full input high halves and
every addition carry are checked. Faulty metrics saturate visibly and assert
the partition-error output, so narrowing cannot turn a large malformed
reservation into an admissible small one. Legal ordinary allocations are below
6 MiB and fallback allocations below 1 MiB; nonnegative partial sums therefore
fit without loss. Public addresses, output widths, baseline and strict-ratio
products, and all 64-bit performance counters are unchanged.

The ledger declaration is 8490 bits / 1062 bytes, down from 16426 bits /
2054 bytes. Two connected instances save 1984 declared bytes together.
All fault bits, final totals and model/mode/check tags are included.
The separate prospective controller remains 276 bits / 35 bytes.
These are declaration counts, not executed synthesis or FPGA measurements.

The ordinary full-text grant now reserves the phase maximum
`max(3*h+e, 2*h+e+(Q+1)*q)`, with h/e/q the selected hidden/PLE/head byte
widths. It includes residual/work/query/attention coexistence and the later
three-hidden-bank feed-forward phase without summing mutually exclusive
lifetimes. The final attention completion releases normalized work and query
before branch output projection starts; its stalls cannot bypass that edge.
Actual child liveness remains independently observed and overrides the grant
envelope if larger. Default standalone E2B local/global reservations are
11264/15872 bytes; E4B 15872/19968; compact actual 64/88.

The connected native assembly now wires ordinary full-text residual to the
executor's retained-hidden backing bank instead of copying it into phase
bank 0. `frontier_execute.EXTERNAL_HIDDEN_RAM=1` exposes the original enabled
read/write timing; the full worker's validated `SHARED_RESIDUAL=1` leaves
residual arithmetic and RAM requests intact but assigns its unique payload
charge to field 2. Field 20 therefore excludes exactly one hidden vector:
integrated E2B reservations are 8192/12800, E4B 10752/14848, compact 48/72.
The native mux rejects competing executor/worker accesses, missing registered
full-text ownership, insufficient hidden reservation and full-width invalid
addresses before indexing. Protocol faults remain explicit error 7.

Replay residual and embedding keep the original phase bank 0: a native
feature Eval may overlap a retained ordinary input, so it cannot use the
new hidden alias. Ordinary initial source loading finishes before residual
updates, and output writeback writes the same completed component to the
same bank. No numerical boundary or callback latency changes. Default
standalone callers retain local hidden storage and separate residual charges.
The hidden read register is still charged once by the executor's existing
`hidden_q` census term; phase-bank read registers retain their separate charge.
Field 2 discloses the native-declared physical hidden bank once, while field
20 still discloses every separately needed phase bank and full attention
buffer. No physical SRAM-capacity reduction is claimed for this alias.
Owner tiles, frames, metadata and all other retained scalar/vector state
remain charged.

Read-only Python source inspection was advisory, not an HDL execution or a
settled whole-system census. Early source-reading helpers did not correctly
handle all declaration initializers/expressions; their intermediate numbers
are not design evidence. The checked ledger counts and phase envelope above
follow directly from the declarations and allocation transitions. Remaining
work is the complete hierarchy/liveness census and additional overlays needed
for every legal actual/production-shadow ordinary-text, native-scratch and
fallback case. In particular, local declaration reductions do not prove the
32768-byte E2B workspace can fit all concurrently charged controllers and
vectors. Required-workload denial still fails the contract.

Tools used in this increment: glob, view, rg, apply_patch and Bash/Python for
read-only source inspection. No RTL experiment, static elaboration, simulation,
synthesis or new preparation receipt was produced. The reserved static check
remains pending until design closure, followed immediately by independent
Verifier handoff. Parent/test sources and runtime-owned records, including the
original failure and attempt-0003, remain untouched. The design is not ready.

## Prior saved increment: native feed-forward arithmetic overlay

`anvil_en1_clipped_projection`, `anvil_en1_native_norm` and
`anvil_en1_native_mlp_row` expose the validated, default-off `EXTERNAL_FP`
service already used by the text primitives. Default standalone callers keep
real local arithmetic. Clipped projection forwards its projection's service;
its comparison-only interval clamps do not take arithmetic ownership.
Native norm forwards its existing norm/scale phase selection without changing
scale callbacks or normalized-output materialization.

The native MLP row now shares one binary32 unit across down projection, nested
gate/up projection, GeGLU, audio activation and final BF16 narrowing. Nested
ownership follows complete registered source start/wait phases, not request
validity. The down projection's weight/partial sum remain held while a source
callback executes the inner projection and activation. Its arithmetic response
has retired before the nested owner starts. Nested scalar completion retires
before the down callback is answered. Source, weight, result and output stalls
cannot redirect a pending arithmetic operation.

`anvil_en1_audio_feedforward` and `anvil_en1_vision_post_layer` select external
mode in their native norm and MLP children and reuse their existing residual
unit across those serialized phases. No additional operands, ownership queue,
arithmetic registers, numerical approximation or vector store is introduced.
The existing primitive byte reports drop only the physically omitted units;
directories, clamps, converters, dividers, child accumulators, enclosing
controllers and suspended frame data all retain their charges.

SPEC freezes the complete ownership/boundary table and scoped declaration
census. Native MLP arithmetic descendants fall from 1111 to 839 bytes
standalone, or 771 external. Audio feed-forward and vision post each retain
1141 rather than 1549 bytes in their arithmetic descendants. The 408-byte
reduction includes the nested row reduction and must not be added twice.
The row's own 337 bits / 43 bytes are unchanged. Existing ordinary and replay
instances consume the same child implementation and reports. Audio retains
its SiLU-plus-narrowing path, not a numerically substituted GeGLU operation.

This retires the native feed-forward/post scalar-sharing milestone in source.
Whole-system declared-state census, any further required physical overlays,
and legal-workload actual/production-shadow feasibility of the ordinary
text, native scratch and fallback partitions remain incomplete. Explicit
error-7 denial is still a failure for required legal work, not a fit result.
Perform the reserved fast static elaboration only after those design
milestones close, then hand off immediately to independent Verifier.

Tools used: glob, view, rg and apply_patch. No commands, experiments, static
elaboration, simulation, synthesis or preparation receipts were produced.
Parent sources, verification sources and runtime-owned records, including
attempt-0003 and the original failure, remain untouched. No repair or
acceptance is claimed. The design is not ready.

## Prior saved increment: text-worker arithmetic and post-only elaboration

`anvil_en1_gated_projection`, `anvil_en1_softcap` and
`anvil_en1_attention_head` now expose validated, default-off `EXTERNAL_FP`
channels. Standalone use retains its local binary32 unit. External mode
removes only that unit; all scalar, activation, exponential, checkpoint,
descriptor, reduction and divider state remains charged.

`anvil_en1_asym_attn_ple` shares one binary32 unit across all six serialized
arithmetic children and its own residual/scalar FSM. `anvil_en1_embedding_ple`
similarly shares one across norm, weight decoding, projection and its own
FSM. `anvil_en1_final_logits` replaces its four child units with one shared
unit across norm, scale decoding, projection and softcap. Complete registered
start/wait phases select the owner, with nested scale-reader phases overriding
normalization only while norm is waiting for its scale callback. Requests,
memory/source stalls and held results cannot reassign ownership. No new queue,
stored operands, numerical stage or reduction-order change is introduced.

The replay post worker (`POST_ONLY=1`) now physically omits its unused direct
projection, rotary and attention subtrees, in addition to its already-absent
attention payload. Its connected replay attention executor still computes the
real branch before the post worker loads it and starts post-attention norm.
Post-attention residual, MLP, gated PLE and scalar processing remain present.
The ordinary full worker retains real projection/rotary/attention instances.
Unused outputs in the post-only generate branches are constant zero; reports
drop only physically absent children, not surviving enclosing scalar state.

SPEC records the exact cycle/degenerate-boundary ownership table and declared
child-subtree reservations. Full text falls from 2247 to 1839 bytes; post-only
from 2247 to 1088; embedding from 806 to 602; final logits from 1037 to 833.
These exclude unchanged enclosing controllers/directories and are per-literal
worker, not additive system totals. No RAM liveness or FPGA-resource reduction
is inferred from these scalar declaration changes.

This closes the local text-worker arithmetic overlay and unused post-only
child-declaration milestones in source. Remaining: whole-system declared-state
census and any additional physical overlays required to fit the ordinary
32768/65536-byte text envelopes, bounded native scratch, fallback partitions,
and production-shadow reservations for all legal cases, including after memo
eviction/regeneration. Then perform the reserved fast static elaboration and
immediately hand off to independent Verifier. Legal-workload denial remains
a failure, not a feasibility result. The design is not ready.

Tools used: glob, view, rg and apply_patch only. No command, experiment,
static elaboration, functional simulation, synthesis or new preparation
receipt. Parent and verification sources and runtime-owned records, including
attempt-0003, are unchanged. No original-failure repair or acceptance claimed.

## Prior saved increment: normalization/rotary arithmetic overlay

`anvil_en1_norm`, `anvil_en1_rope_frequency`, `anvil_en1_sincos`
and `anvil_en1_rotary_pair` now expose the validated, default-off
`EXTERNAL_FP` channel. Standalone callers retain a real local binary32 unit.
Rotary frequency generation and trigonometry select external mode and share
the rotary service with the pair-rotation FSM.

`anvil_en1_owner_kv_tile` selects external mode in its projection,
normalization, scale reader and rotary children, using one physical
binary32 unit instead of six. `anvil_en1_native_norm` similarly shares one
unit between normalization and scale decoding. Phase selection spans
registered start/wait intervals. The nested scale callback takes ownership
only after normalization's previous arithmetic response retired; norm cannot
issue another arithmetic request until the scale result returns. Memory,
source and response stalls cannot switch ownership. No arbitration queue,
new stored state, numerical stage or reduction-order change is introduced.

SPEC freezes the complete cycle/degenerate-boundary table and declared
reservation totals. Norm, frequency and trigonometry retain every scalar,
integer-converter and divider reservation in external mode. A standalone
rotary subtree is now 364 bytes rather than 500; its external mode is 296.
The owner's projection/norm/scale/rotary arithmetic subtree is 898 bytes
rather than 1238. Native normalization removes one 68-byte unit per literal
worker. Nested reductions must not be added again to the owner's total.
Payload banks and enclosing controllers are unchanged and fully charged.

This closes the local normalization/rotary scalar overlay in source, not
whole-system accounting or feasibility. Remaining milestones are the
whole-system declared census, remaining physical overlays and legal-case
actual/production-shadow fit of ordinary text, native scratch and fallback
partitions, including memo eviction/regeneration. Then perform the reserved
fast static elaboration and immediately hand off to independent Verifier.
Explicit denial of required legal work remains a failure. Not ready.

Tools used: glob, view, rg and apply_patch only. No command, experiment,
static elaboration, simulation, synthesis or new preparation receipt.
Parent sources, verification sources and runtime-owned records are
unchanged. Attempt-0003 is preserved; no repair or acceptance is claimed.

## Prior saved increment: serialized projection/activation arithmetic overlay

`anvil_en1_weight_read`, `anvil_en1_projection`, `anvil_en1_activation`
and `anvil_en1_geglu_pair` now expose the same validated, default-off
`EXTERNAL_FP` channel as the exponential FSM. Standalone use retains a real
local binary32 unit. External mode removes only that literal unit; all
descriptor, address/extent, accumulator, polynomial, materialization,
partial-value and held-response registers remain charged.

Projection shares its unit with its weight reader; GeGLU shares its unit
with activation and the already-external exponential child. Gated projection
selects external mode in its projection, GeGLU and down-weight children,
and serves their nested operations with its single existing binary32 unit.
Softcap now shares its unit with its activation/exponential subtree. All
ownership is selected by complete registered child start/wait phases, not
by instantaneous arithmetic valid. Requests and results cannot be reassigned
while a child, memory response, source callback or completion is stalled.
The original FSMs, reduction order, BF16 boundaries and error propagation
remain intact. There is no new queue or stored arbitration state.

The local projection/activation-subtree physical-overlay milestone is now
closed in source. SPEC records the exact default/external reservation table
and reset/start/stall/error/degenerate-boundary ownership rules. Relative to
the preceding source, each default projection removes one binary32 unit,
each default GeGLU pair removes one, each softcap removes one, and each
gated-projection subtree removes five (six units become one). Those nested
figures must not be added together: the gated-projection reduction already
includes its projection and GeGLU reductions. Its declared controller
reservation falls from 1126 to 786 bytes, with no scalar-controller or
division-unit reservation hidden or released. Higher-level reports already
consume these literal child reports. No whole-system byte total, inferred
M20K count, device fit, throughput improvement or timing result is claimed.

Remaining closure milestones: finish whole-system census and remaining
physical overlays; demonstrate legal-case fit of actual and production-shadow
ordinary text/native scratch/fallback partitions, including after memo
eviction; then use the reserved fast static elaboration and immediately
hand off the complete design to independent Verifier. Conservative envelope
denial is not legal-workload feasibility. Design is not ready.

Tools used for this increment: glob, view, rg and apply_patch only. No
commands, static elaboration, simulation, synthesis, experiments or new
preparation receipts. Immutable parent, tests and runtime-owned records,
including attempt-0003, are unchanged; no failure repair or acceptance is
claimed.

## Prior saved increment: exponential scalar-state physical overlay

`anvil_en1_exp.sv` now has an explicitly validated `EXTERNAL_FP` option.
Its default standalone implementation is preserved. In external mode its
unchanged scalar FSM requests a real binary32 operation from the enclosing
worker instead of declaring a duplicate arithmetic unit.

The six literal exponential consumers (`activation`, `softplus`, text,
vision and audio attention heads, and audio relative position) now select
external mode and route their existing binary32 unit to the child during
the complete exponential send/wait phase. Parent arithmetic and exponential
arithmetic never execute concurrently. Each phase boundary already retires
the prior arithmetic response; no queue, new storage, arithmetic stage or
changed reduction/materialization order is introduced. Reset/error/stall
behavior follows the existing registered FSMs. Only the absent child's
68-byte controller contribution is removed; all parent and exponential
scalar state remains charged. This is a declared physical overlay, not a
measured FPGA resource or timing improvement.

SPEC adds a declared-width inventory for 17 arithmetic/format/projection
primitives, their literal child reservations and the complete ownership/
cycle table. Existing arithmetic-controller reservations are unconditional
while reset is released, so arithmetic starts do not grow these reservations
and need no additional dynamic scalar grant. Vector grants remain separate.
The inventory explicitly discloses the conservative 64-bit combinational
quadrant allowance still included by sin/cos. No charge is silently gated
away when a worker becomes idle.

Remaining closure milestones: complete whole-system census and physical
overlays, establish legal-case feasibility of actual and production-shadow
envelopes (including native scratch and fallback partitions after eviction),
then the reserved fast static elaboration and independent Verifier handoff.
Denial of a required legal job remains an implementation failure. Not ready.

Tools used: glob, view, rg and apply_patch only. No command, static check,
experiment, simulation, synthesis or installation ran; no new preparation
receipt exists. Parent, tests and runtime-owned files are untouched.
Attempt-0003 remains preserved without a claimed repair.

## Prior saved increment: ordinary frontier and private-storage admission

`anvil_en1_frontier_execute.sv` now admits the frontier, local ring, retained
hidden/PLE vectors, modality staging, anchor transfer, embedding and full-text
payload before allocating or starting the corresponding child. These replace
existing ledger fields 0/1/2/3/4/19/20, with separate actual and production-shadow
envelopes. Reservations survive command, child and response stalls. A child
exceeding its admitted envelope remains fully reported and causes error 7.
Denials do not start the denied child or spill data.

`anvil_en1_native.sv` registers and serializes ordinary and binding allocation
requests through the existing whole-system admission pipeline. Binding's
owner/workspace/private grants and pinned-memo eviction remain connected.
The field whitelist in `anvil_en1_allocation_admission.sv` includes the new
ordinary request classes. New arbiter/executor state is counted in existing
controller fields; no payload RAM is added.

Frontier/ring grants capture their actual and production-shadow sizes until
successful invalidation, rather than recalculating the old representation
from a new session's model/context. The native shadow ledger now consumes
those owned held values. The previous ordinary representations are invalidated
before the fallback result-vector grant. Embedding and full-text reservations
retire in sequence, preserving the existing physical RAM-owner exclusion.
SPEC records complete envelopes, release rules and registered boundaries.

Remaining closure milestones: arithmetic accounting inventory, remaining physical
overlays and legal-case feasibility of the complete conservative envelopes;
then the reserved fast static elaboration and independent Verifier handoff.
Admission denial is still an implementation failure for a required legal job.
The design is not ready.

Tools used: view, rg and apply_patch (plus the initial glob) only. No command,
static check, experiment, simulation, synthesis or installation ran; no new
preparation receipt exists. Parent, tests and runtime-owned files are untouched.
Attempt-0003 remains preserved without a claimed repair.

## Prior saved increment: owner-source and projection-tile admission

`anvil_en1_owner_replay.sv` now admits the complete existing raw/normalized
source bank before fallback Eval or ordinary owner projection, then admits
the complete local/global head bank before projection start. These replace
existing ledger fields 6/7 through `anvil_en1_allocation_admission.sv`.
Actual compact/production and production-shadow byte totals remain distinct.
The raw reservation survives nested Eval and tile-grant stalls. Projection
retains both banks until its accepted result; returned pair/error state
remains in the existing controller charge. Ring hits allocate neither bank.

`anvil_en1_replay_binding.sv` registers and serializes owner and existing
workspace/private grant descriptors, retaining the selected route until
response acceptance. Owner selection waits for replay idle, so an earlier
Eval retires/invalidate its workspace before the next owner-grant snapshot.
Workspace eviction/retry and its dependency pin are unchanged. The owner
raw bank is already charged while owner-triggered replay executes. Denial
returns explicit error 7 without the denied child start or spill; it is
not proof that all legal workloads fit. Illegal arbiter state latches the
existing binding/native protocol-error path.

All new arbiter/descriptor and wider owner-state bits are counted in
existing controller ledger fields. No payload bank, numerical operation,
tensor format, public top port or alias map changes. SPEC adds the exact
reservation sizes, release rules and cycle/degenerate-boundary table.

Remaining closure milestones: ordinary/frontier grants, arithmetic accounting,
remaining physical overlays and legal-case feasibility (including conservative
native private-bank envelopes); then the reserved static elaboration and
independent Verifier handoff. Not ready.

Tools used: glob, view, rg and apply_patch only. No command, experiment,
static elaboration, simulation, synthesis or installation ran, and no new
preparation receipt exists. Parent, tests and runtime-owned files remain
untouched. Attempt-0003 is preserved without a claimed repair.

## Prior saved increment: native replay private-bank admission

`anvil_en1_replay_execute.sv` now preflights vision, audio and reconstructed
image/audio-feature workers before child start. Requests use the existing
owned-frame operation 7/target 1 protocol and named allocation fields 12..15.
`anvil_en1_replay_workspace.sv` validates the domain, layer, exact envelope
and frame/session before the existing deterministic pinned-memo
eviction/admission path. `anvil_en1_allocation_admission.sv` now permits
these four replacement fields in addition to workspace and replay-text
private fields. No top interface, tensor boundary or numerical rule changes.

Native complete-bank envelopes are 7808 bytes for a vision layer (zero for
streamed patch input), 512 for audio input, 38912 for the conservatively
summed nested audio-layer banks, 6144 for audio-feature reconstruction and
6432 for image-feature reconstruction. Compact text builds still execute
production-width encoders, so these envelopes have identical actual and
production-shadow counts. SPEC records the decomposition and cycle table.
The envelopes deliberately include conservative phase overlap; their size
is not a legal-case feasibility or physical resource-fit result.

The dispatcher reserves only after accepting the successful workspace
response. No native child start or command precedes this reservation.
Reservations remain charged across source/output/child stalls, nested
workspace grants, child completion/yield and a held task response, then
release on accepted task completion. Reports retain the larger of the full
reservation and actual child live totals. An over-envelope child report
also sets the existing dispatcher failure path rather than being hidden
by the reservation. The added reservation state is charged once in the
dispatcher and native-controller subset. No payload RAM is added.

Remaining closure milestones: ordinary execution and owner-projection
grants, remaining arithmetic accounting, physical overlays and legal-case
feasibility (including the conservative native envelopes); then the reserved
static elaboration and independent Verifier handoff. Denial exhaustion is
still explicit error 7 and an implementation failure, never an accepted
fallback or permission to spill. Not ready.

Tools used: view, glob, rg and apply_patch only. No command, experiment,
static check, simulation, synthesis or installation ran; no new preparation
receipt exists. The partial apply_patch failure was a missing edit-context
match, corrected against the unchanged dispatcher source; it is not an RTL
execution result. Parent, tests and runtime-owned files remain untouched.
Attempt-0003 is preserved without a claimed repair.

## Prior saved increment: replay text private-bank admission

The connected admission channel now names its replacement allocation field.
Workspace growth retains field 5; replay text attention tile, retained PLE,
embedding and post banks use existing fields 8..11. All other fields reject.
`anvil_en1_allocation_admission.sv` substitutes exactly one complete
actual/shadow field before the existing full-ledger checks. The selector
travels through `anvil_en1_eval_schedule.sv`, `anvil_en1_replay_execute.sv`,
`anvil_en1_replay_binding.sv` and `anvil_en1_native.sv`; no public top port
changes.

`anvil_en1_replay_workspace.sv` adds validated operation 7/target 1 private
preflight. It checks the complete current frame/session and exact selected-model
bank sizes, then uses the existing admission/denial/memo-eviction path.
Only completed unpinned memos may be evicted. Actual/shadow/native subtotals
are rebuilt after eviction; later misses execute the existing Eval recomputation.
Private preflight never reads scalar RAM, streams data or reserves duplicate
workspace payload. The geometry decoder supplies the actual local/global
projection width, not a second alias-map implementation.

`anvil_en1_replay_text_layer.sv` now admits the full serialized attention
projection tile before initial or resumed attention, retained PLE before
reconstruction, full embedding banks before embedding start, and the complete
POST_ONLY bank set before post start. `anvil_en1_replay_input.sv` also admits
its layer-0 embedding banks before child start. Requests retain the existing
dependency-memo pin, including modality features.

Attention/embedding/post reservations persist through child/source/output
stalls and are released only after accepted child done/yield. Their reported
actual/shadow bytes are at least the full granted envelope, and never less
than the child's own live report. Later frame growth therefore cannot reuse
promised private capacity while it is being filled. The retained PLE copy
remains separate through post completion. Added reservation/selection state
is included in existing controller charges; no new payload RAM is declared.
SPEC records the exact field/byte encodings and acceptance/release cycle table.

Remaining closure milestones: private native encoder/feature workers,
ordinary execution/owner projection and any arithmetic grants not already
covered by complete controller reservations; remaining physical overlays
and legal-case feasibility, including conservative envelope sizes; then the
reserved static elaboration and independent Verifier handoff. Exhausted
denial is still explicit error 7 and an implementation failure, not accepted
bounded fallback. This increment does not establish numerical correctness,
measured savings, M20K inference, resource fit, timing or acceptance.

Tools used: view, glob, rg and apply_patch only. No command, experiment,
static check, simulation, synthesis or installation ran; no new preparation
receipt exists. Parent, tests and runtime-owned files remain untouched.
Attempt-0003 is preserved without a claimed repair. Not ready.

## Prior saved increment: ordinary text-workspace partition

`rtl/anvil_en1_allocation_ledger.sv` now separately reports actual and
production-shadow complete text workspace. Two balanced sums exclude only
frontier, local ring and resident words from complete equivalent allocations;
a sixth registered stage subtracts the coherent native-scratch subset.
Metadata, integration registers, text frames/memos/scalars, transient vectors
and arithmetic/control state remain charged. Explicit native-subset and
subtraction-underflow flags reject an inconsistent partition.

`anvil_en1_allocation_admission.sv` and `anvil_en1_allocation_guard.sv`
both enforce ordinary E2B/E4B text partitions of 32768/65536 bytes and
nondecreasing shadows, alongside unchanged strict 45%, native-scratch and
fallback limits. `anvil_en1_top.sv` connects the new coherent reports.
The existing eight drain edges plus check edge cover six ledger stages and
two guard stages. All added pipeline registers are charged in the same live
and physical controller reports. SPEC updates the admission cycle table.

Prospective workspace denial still evicts eligible completed memos and retries
before granting storage; private-worker/arithmetic reservations remain the
next grant-time closure milestone. Remaining physical overlays and legal-case
feasibility must also close before the reserved static elaboration and
independent Verifier handoff. No command, check, experiment or new receipt
exists for this increment. Tools used: view, glob, rg and apply_patch.
Parent, tests and runtime-owned files remain untouched; attempt-0003 is
preserved without any claimed repair. Not ready.

## Prior saved increment: whole-system admission for workspace growth

New `rtl/anvil_en1_allocation_admission.sv` substitutes prospective workspace
and native-subset totals into the allocation ledger (now five balanced sum
stages plus a coherent partition stage).
It checks complete actual/production-shadow equivalent payload against the
strict 45% production matched-storage baseline, the fallback 1 MiB ceiling,
ordinary context-dependent native scratch, mode overlap and shadow validity.
Top supplies its registered storage baseline and complete integration charge.
This is not measured matched-baseline traffic.

The real workspace now waits for this decision before reserving a new scalar
frame slot, first full vector slice or memo replacement. Denial runs the
existing deterministic completed-memo eviction path, updates actual/shadow/
native subtotals and rebuilds/retries the complete prospective snapshot.
Frame/scalar grants pin the worker dependency memo; memo-to-frame copies
independently pin their source, and the linear one-token path pins its
predecessor across the next push. No live frame, partial vector or original
input is evicted or spilled. Later misses use actual Eval recomputation.
All new candidate/pin/admission/ledger registers are charged, including the
admission module's own reservation in its prospective sum.

The ready/valid path is wired through `anvil_en1_eval_schedule.sv`,
`anvil_en1_replay_execute.sv`, `anvil_en1_replay_binding.sv` and
`anvil_en1_native.sv` to the new module. `anvil_en1_replay_workspace.sv`,
`anvil_en1_top.sv` and both design documents also changed. SPEC records
the new candidate, pin, decision and cycle tables. No top public port or
arithmetic/materialization rule changes.

Remaining closure milestones: private native/text worker and arithmetic
grant-time limits, ordinary total text-workspace partition enforcement,
remaining physical overlays and legal-case feasibility after eviction;
then the reserved fast static elaboration and immediate independent Verifier
handoff. An exhausted denial returns error 7 without the denied allocation:
that is a failure requiring repair, not an accepted replacement for exact
bounded replay. The current delta prevents unadmitted workspace growth;
it does not yet close every allocation-growth path or establish savings,
M20K inference, resource fit, timing or acceptance. Not ready.

Tools used: view, glob, rg and apply_patch only. No command, experiment,
static check, simulation, synthesis or installation ran, and no new preparation
receipt exists. Parent, verification and runtime files remain untouched.
Attempt-0003 remains preserved without a claimed repair.

## Prior saved increment: text/embedding phase overlay

`rtl/anvil_en1_native.sv` now shares the existing full/post text banks
0/3 with the ordinary/replay embedding hidden/PLE payload. The separate
integrated embedding pair and its read registers are removed. A registered
four-client owner is selected from the existing complete-vector reservations
before the first legal access. Only the registered, still-reserved owner
may access RAM. Overlapping reservations and foreign enables suppress
accesses and retain the existing native protocol fault. Selected-model
H/P limits are checked in addition to physical capacity before indexing.

Ordinary embedding retires before full text; ordinary owner projection
uses the preserved frontier/ring without embedding replay. Fallback uses
no ordinary full-text worker, and its embedding/input workers retire before
POST_ONLY starts. Retained frame, feature, hidden, PLE and anchor copies
remain separate. The existing enabled-edge read and subsequent capture
cycles are preserved.

This removes 5632 production / 24 compact declared payload bytes and two
duplicate 16-bit read registers. Physical field 20 counts the four-bank
set once, with its separate full-text attention bank; field 19 no longer
adds an embedding pair. All live/production-shadow charges remain complete.
Native state accounting includes the three-bit owner and four, rather than
six, shared read registers.

Changed that RTL file, `design/SPEC.md` and this document. Tools used:
view, rg and apply_patch only. No command, static check, simulation,
synthesis, installation or experiment ran; there is no new preparation
receipt. Parent, verification and runtime files remain untouched.
Attempt-0003 remains preserved without a claimed repair.

Remaining closure milestones: context-dependent whole-system
frame/native-worker/memo/arithmetic grants with exact eviction/recomputation,
ordinary total-workspace partition enforcement and any remaining physical
overlays; then the reserved fast static elaboration check and immediate
independent Verifier handoff. This local ownership/access partition does
not establish whole-system limiting, live-footprint savings, M20K inference,
resource fit, timing or acceptance. Not ready.

## Prior saved increment: cross-domain replay vision/audio scratch overlay

The connected replay dispatcher now declares the three 1024-word synchronous
BF16 scratch banks shared by its audio-layer convolution/feed-forward/GLU
workers. Its mutually exclusive vision-layer task uses bank 0's first 768
words for the already overlaid projected/post-branch representation.
Optional external-RAM parameters in both wrappers retain local storage by
default; the dispatcher enables the external paths.

Registered ownership is acquired at the actual child-start handshake and
released only at accepted child done/yield. Full-address, selected-phase,
concurrent-port and live-overlap checks suppress conflicting accesses and
retain error 7 without hiding earlier child errors. The same enabled-edge
read/write and capture cycles remain; no tensor or arithmetic order changes.
The physical declaration sum drops by 1536 bytes. All original separate
live/shadow charges remain. Shared read/owner/fault registers move to
dispatcher accounting and its native-controller subset.

Changed `rtl/anvil_en1_replay_execute.sv`,
`rtl/anvil_en1_replay_vision_layer.sv`,
`rtl/anvil_en1_replay_audio_layer.sv`, `design/SPEC.md` and this document.
Tools used: glob, view, rg and apply_patch only. No command, static check,
simulation, synthesis, installation or experiment ran; there is no new
preparation receipt. Parent, verification and runtime files remain untouched.
Attempt-0003 remains preserved without a claimed repair.

Remaining closure milestones: context-dependent whole-system
frame/native-worker/memo/arithmetic grants with exact eviction/recomputation,
ordinary workspace partition enforcement and remaining overlays; then the
reserved fast static elaboration check and immediate independent Verifier
handoff. This physical overlay does not establish live-footprint savings,
M20K inference, resource fit, timing or acceptance. Not ready.

## Prior saved increment: replay-frame vector grants and release census

`rtl/anvil_en1_replay_workspace.sv` now separates frame ownership from
whole-vector reservation and completed-vector visibility. Push reserves the
complete scalar slot, not unused vector banks. A first stream, memo-to-frame
copy or ordered pair sequence registers its actual/production-shadow candidates,
checks frame ownership and both physical frame-payload ceilings, then reserves
the complete selected domain-width vector before any backing access. Rewrites
reuse that reservation. Partial writes, stream aborts and backing errors retain
the granted vector charge until pop/invalidation; clearing visibility cannot
hide an incomplete tensor.

Six reservation bits use each frame's existing bank/slice layout. Pop reads
the actual popped frame's mask, registers its slice count and byte amounts,
checks subtotal underflow, then releases precisely those vectors and its scalar
slot. Native subsets follow the same domain-tagged grants/releases, including
suspended parents. The new reservation bitmap is metadata and new readback,
count, candidate and return-state registers enter controller accounting.
Physical backing capacity, legal depths, numerical operations and ports remain
unchanged. This is a real allocation-lifetime change, not a smaller charge for
an already allocated full frame.

Changed that RTL file, `design/SPEC.md` and this document. Tools used:
glob, view, rg and apply_patch only. No command, static check, simulation,
synthesis, installation or experiment ran; there is no new preparation receipt.
Parent, verification and runtime files remain untouched. Attempt-0003 remains
preserved without a claimed repair.

Remaining closure milestones: connect context-dependent whole-system
frame/native-worker/memo/arithmetic grants (with exact eviction/recomputation),
ordinary workspace partition limits and remaining physical overlays; then run
the reserved fast static elaboration check and hand off immediately to the
independent Verifier. Local frame-payload capacity grants do not complete
native-scratch, fallback-total or strict 45%-baseline enforcement. Not ready.

## Prior saved increment: replay audio GLU/branch physical overlay

The existing audio ownership reservation now spans three synchronous BF16
1024-component banks. Residual and working remain banks 0/1; bank 2
serves the nested convolution GLU normalized vector or the subsequent
feed-forward output branch. Each child may need all three banks at once;
the overlay is only across their disjoint complete task lifetimes.

`anvil_en1_audio_glu_component` gains an optional external enabled-edge
RAM port. Lightconv propagates its existing storage parameter to that
child and forwards bank 2. Feed-forward exports its existing branch
accesses on bank 2 of its widened external port. Local defaults preserve
independent payload and the existing synchronous read/capture cycles.
The replay wrapper extends its existing registered ownership, full-address
range checks and conflict suppression to the third bank. It does not
release convolution ownership between nested GLU requests or before
accepted convolution done.

The connected declarations now contain 6144 bytes instead of the prior
8192 (two shared banks and two private banks). Live and production-shadow
reservations are unchanged. The shared read register is counted in the
wrapper, not duplicated in the external GLU/feed-forward children.
This is a physical declaration reduction, not measured live savings,
M20K inference, timing closure or whole-system allocation enforcement.

Changed `rtl/anvil_en1_audio_glu_component.sv`,
`rtl/anvil_en1_audio_lightconv.sv`,
`rtl/anvil_en1_audio_feedforward.sv`,
`rtl/anvil_en1_replay_audio_layer.sv`, `design/SPEC.md` and this document.
Tools used: glob, view, rg and apply_patch only. No command, static check,
simulation, synthesis, installation or experiment ran; there is no new
preparation receipt. Parent, verification and runtime files remain untouched.
Attempt-0003 remains preserved without a claimed repair.

Remaining: whole-system grant-time ordinary/native-scratch/fallback limits,
including forced-short-context production-shadow limits, and remaining
physical phase overlays. Then run the reserved fast static elaboration
check and immediately hand the completed design to independent Verifier.
Not ready.

## Prior saved increment: replay audio residual/working physical overlay

`rtl/anvil_en1_replay_audio_layer.sv` now owns two synchronous BF16
1024-component banks shared by convolution and second feed-forward.
The two children export optional full-address RAM ports through
`EXTERNAL_VECTOR_RAM=0/1`; their standalone default retains local storage.
The registered wrapper owner grants both banks at child start and releases
them only on accepted child done. Convolution outputs reach the replay
frame through acknowledged pair writes before feed-forward reloads them.
Existing arithmetic, BF16 boundaries and callback capture cycles remain
unchanged. Feed-forward's simultaneous output-branch bank and convolution's
GLU-child bank remain separate.

Full-address, phase, owner, concurrent-port and overlapping-live checks
suppress invalid shared accesses and retain error 7 without replacing
earlier concrete child failures. Payload RAM uses enabled-edge synchronous
read/write ports without an initialization sweep. Shared read/owner/fault
registers are included in controller accounting.

This removes 4096 bytes of duplicate physical payload declarations for
this worker pair. Child live/shadow reservations remain complete; sharing
declarations is not claimed as measured live savings, M20K inference,
resource fit or timing closure. The local two-bank grant does not complete
whole-system frame/native-scratch/fallback grant enforcement.

Changed those three RTL files, `design/SPEC.md` and this document.
Tools used: glob, view, rg and apply_patch only. No command, static check,
simulation, synthesis, installation or experiment ran; there is no new
preparation receipt. Parent, verification and runtime files remain untouched.
Attempt-0003 remains preserved without a claimed repair.

Remaining: whole-system grant-time ordinary/native-scratch/fallback limits,
including forced-short-context production-shadow limits, and remaining
physical phase overlays. Then run the reserved fast static elaboration
check and immediately hand the completed design to independent Verifier.
Not ready.

## Prior saved increment: context-bounded memo grants and eviction

`rtl/anvil_en1_replay_workspace.sv` now admits memo replacements against
an explicit `min(128 KiB, B/64)` production-context payload envelope before
charging pending storage or starting any copy/stream. Actual and
production-shadow candidates must both fit. An over-budget request scans
the existing 16 slots from the round-robin cursor, invalidates completed
victims and updates all actual/shadow/native subtotals before rechecking.
It preserves the destination and current frame source. Eviction emits the
real telemetry event and has no dirty writeback; subsequent misses use the
existing exact Eval computation. It does not reject legal replacements
merely because their optional memo pool is full.

The workspace captures/validates the complete text-context length through
the connected Eval scheduler. Three registered budget stages compute the
model's padded local/global baseline terms and scaled/clamped envelope.
Text/reconstructed-feature token descriptors must be inside that context.
The smallest legal envelopes exceed every legal single result-vector size;
exhausted scans or subtotal underflow therefore indicate inconsistent
workspace state, not permission to spill. Added registers are counted.
The physical pool size and numeric operation boundaries are unchanged.

This closes only the opportunistic memo grant/eviction portion, not the
whole-system allocation limiter. Frame and suspended native-worker
reservations still need complete grant-time treatment and, where needed,
further streaming/rematerialization. Existing completion guards remain
failure observers, not storage grants or acceptance.

Changed `rtl/anvil_en1_replay_workspace.sv`,
`rtl/anvil_en1_eval_schedule.sv`, `design/SPEC.md` and this document.
Tools used: glob, view, rg and apply_patch only. No command, static check,
simulation, synthesis, installation or experiment ran; there is no new
preparation receipt. Parent, verification and runtime files remain untouched.
Attempt-0003 remains preserved without a claimed repair.

Remaining: whole-system grant-time ordinary/native-scratch/fallback limits,
including forced-short-context production-shadow limits, and remaining
physical phase overlays. Then run the reserved fast static elaboration
check and immediately hand the completed design to independent Verifier.
Not ready.

## Prior saved increment: replay vision projection/branch physical overlay

`rtl/anvil_en1_replay_vision_layer.sv` now physically reuses its
768-component projection-staging bank as the post worker's branch bank.
Projection staging is copied into the replay frame with real acknowledged
pair writes before post start, so post input still comes from the frame.
The post worker's raw residual and MLP-output banks remain independent;
they are simultaneously needed during MLP execution.

`rtl/anvil_en1_vision_post_layer.sv` exposes an optional
`EXTERNAL_BRANCH_RAM=0/1` port, defaulting to its existing standalone local
storage. The replay wrapper selects external storage and preserves the
original synchronous enabled-edge accesses. Full-address, concurrent-owner,
wrong-phase and overlapping-live-reservation guards suppress invalid
accesses and retain error 7 without overwriting earlier child errors.
The shared read register is counted once in the wrapper.

The connected declaration now reserves 4608 bytes for staging/post storage
rather than 6144, excluding the unchanged tile; actual and shadow live
reservations still use their original separate lifetime flags. This closes
one physical duplication, not grant-time allocation limiting or measured
savings, M20K inference, resource fit or timing.

Changed those two RTL files, `design/SPEC.md` and this document.
Tools used: glob, view, rg and apply_patch only. No command, static check,
simulation, synthesis, installation or experiment ran; there is no new
preparation receipt. Parent, verification and runtime files remain untouched.
Attempt-0003 remains preserved without a claimed repair.

Remaining: whole-system grant-time ordinary/native-scratch/fallback limits
with eviction/recomputation, including forced-short-context production-shadow
limits; remaining physical phase overlays; then the reserved fast static
elaboration check and immediate independent Verifier handoff. Completion-time
allocation guards remain observers, not storage grants. Not ready.

## Prior saved increment: ordinary/replay embedding physical overlay

The native assembly now owns one synchronous hidden/PLE embedding bank pair
shared by the ordinary frontier embedding worker and the replay executor's
serialized input/text embedding workers. The three wrappers
frontier_execute, replay_execute and replay_binding expose an optional
`EXTERNAL_EMBEDDING_RAM=0/1` interface; standalone default storage and timing
are unchanged. Native selects external storage on both paths and performs
the original enabled-edge reads/writes without an arbitration-cycle change.

This sharing follows the connected schedule: native feature reconstruction
completes before ordinary embedding starts, and ordinary text's nested
owner replay does not use the ordinary embedding bank. Simultaneously live
feature, retained text, frontier, frame and anchor payloads remain disjoint.
Full component addresses are checked before array indexing. Concurrent
ordinary/replay port requests suppress the affected access; port/range faults
and overlapping live embedding reservations latch the native protocol fault.
Reset disables access without a payload initialization sweep.

Physical field 19 discloses the single 5632-byte production / 24-byte compact
pair; external children no longer declare duplicate payload arrays. Live
and production-shadow fields 10 and 19 retain their independent original
lifetime flags. Shared read-register accounting moves into native controller
state and is removed from the external replay dispatcher and ordinary child.
This closes that specific physical duplication, not grant-time allocation
limits, measured live savings, M20K inference, resource fit or timing.

Changed `rtl/anvil_en1_frontier_execute.sv`,
`rtl/anvil_en1_replay_execute.sv`, `rtl/anvil_en1_replay_binding.sv`,
`rtl/anvil_en1_native.sv`, `design/SPEC.md` and this document.
Tools used: glob, view, rg and apply_patch only. No command, static
elaboration, simulation, synthesis, installation or experiment ran; there is
no new preparation receipt. Parent, verification and runtime files remain
untouched. Attempt-0003 remains preserved without a claimed repair.

Remaining: whole-system grant-time ordinary/native-scratch/fallback limits
with eviction/recomputation rather than legal-work rejection; remaining
physical phase overlays; then the reserved fast static elaboration check
and immediate independent Verifier handoff. In particular, completion-time
allocation guards remain observers, not storage grants. Not ready.

## Prior saved increment: matched-traffic telemetry and immutable mask scan

`rtl/anvil_en1_top.sv` now connects CSR metric 6 to a registered
nominal matched-unshared traffic calculation. The comparison materializes
distinct correct-owner K/V copies for every logical layer and every padded
token slot. Its masked causal/window read schedule loads each adjacent BF16
pair once per visible source/query/logical layer and KV head, reusing it
across grouped Q heads. Production E2B/E4B and compact geometry use their
actual dimensions and head counts; both weight precisions retain BF16 KV.
`SPEC.md` freezes the exact byte formula and distinguishes cumulative local
ring writes from live ring allocation.

The top interleaves an actual immutable mask read with each existing
position validation. Boolean source visibility drives separately registered
span, layer-count, byte-scale, sum and accumulation stages. Memory errors
return 2 and malformed mask words return 5 before native dispatch. These
extra original-input reads remain included in the real public traffic
census. Native attention still reads its actual masks; no numerical answer
or cached activation enters through the scan. Native generation advances
only after the complete successful scan and final byte accumulation.
The parent path, public ports, CSR offsets and mandatory commands are
unchanged. Added state enters the existing integration reservation.

Metric 6 adds once at accepted successful outer completion and remains
stable through stalls. It is calculated nominal telemetry, **not measured
baseline traffic or an acceptance denominator**. Independent Verifier must
still author and execute its separate public-handshake baseline and
scoreboards. No savings, numerical, FPGA-fit or timing result is claimed.

Changed `rtl/anvil_en1_top.sv`, `design/SPEC.md` and this document.
Tools used: glob, view, rg and apply_patch only. No command, static
elaboration, simulation, synthesis, installation or experiment ran; there
is no new preparation receipt. Parent, verification and runtime files
remain untouched. Attempt-0003 remains preserved without a claimed repair.

Remaining: whole-system grant-time ordinary/native-scratch/fallback limits
with eviction/recomputation rather than legal-work rejection; remaining
physical phase overlays; then the reserved fast static elaboration check
and immediate independent Verifier handoff. The nominal traffic counter
is connected, but independent actual baseline traffic remains a Verifier
obligation. This saved increment is not ready for Verifier.

## Prior saved increment: production shadow observations and replay embedding overlay

The native assembly now provides a complete 25-field production-width
counterpart to its actual live component observations. Hidden/PLE and
residual/work/branch/query/attention mixtures use their owning leaf flags;
no single scaling factor is applied to mixed subtotals. Frontier/ring
shadows use production padded capacity/window allocations. Native encoder
staging and scalar/controller widths remain unchanged. Production metadata
is explicit, including the larger frontier/ring declarations.

Shadow observations propagate through embedding, full-text, replay post,
projection tile and their wrappers. The ledger now has six coherent,
five-stage balanced sums: the previous four actual reports plus equivalent
and native-scratch production shadows. The new registers enter its own
controller reservation. The completion guard independently applies the
strict ratio, scratch ceiling and fallback ceiling to actual and shadow
reports, and rejects a shadow smaller than its corresponding actual total.
This closes the missing compact-width observation/guard connection, not
grant-time whole-system allocation limiting or acceptance.

The replay input and text embedding workers now physically share one
synchronous hidden/PLE bank pair owned by replay_execute. Their optional
external bank interfaces preserve enabled-edge read/write timing and
default standalone local storage. Per-bank port/address conflicts and
overlapping live reservations latch error 7 before dispatcher response,
without replacing an earlier worker error. Physical payload drops from
two declared 5632-byte production (24-byte compact) pairs to one; live
reservations keep the original flags. Shared read registers are charged
once. This is a declared RTL overlay, not measured FPGA resource savings.

Changed `rtl/anvil_en1_embedding_ple.sv`, `rtl/anvil_en1_asym_attn_ple.sv`,
`rtl/anvil_en1_replay_kv_tile.sv`, `rtl/anvil_en1_replay_attention_execute.sv`,
`rtl/anvil_en1_replay_attention_projection.sv`,
`rtl/anvil_en1_replay_text_layer.sv`, `rtl/anvil_en1_replay_input.sv`,
`rtl/anvil_en1_replay_execute.sv`, `rtl/anvil_en1_replay_binding.sv`,
`rtl/anvil_en1_frontier_execute.sv`, `rtl/anvil_en1_native.sv`,
`rtl/anvil_en1_allocation_ledger.sv`, `rtl/anvil_en1_allocation_guard.sv`,
`rtl/anvil_en1_top.sv` and `design/SPEC.md`/this document. Tools used:
glob, view, rg and apply_patch only. No command, static elaboration,
simulation, synthesis, installation or experiment ran; no preparation
receipt exists. A partially applied edit was inspected and completed;
it was not an execution diagnostic. Parent, verification and runtime
sources remain untouched. Attempt-0003 remains preserved without a
claimed repair.

Remaining: grant-time whole-system ordinary/native-scratch/fallback
limits with recomputation/eviction rather than rejecting legal work;
remaining physical phase overlays; matched-baseline traffic metric 6
integration without substituting a computed denominator for independently
handshaken baseline traffic. Then run the reserved static elaboration
check and hand off to independent Verifier. No correctness, measured
savings, FPGA-fit or timing result is claimed. Not ready for Verifier.

## Prior saved increment: native scratch census and allocation failure retirement

The bounded workspace now maintains actual and production-shadow native
frame/memo subtotals independently from text. Pending allocations count
before the first backing write. Frame pop uses the stored popped domain;
memo replacement uses the victim's stored domain. Both banks and the
complete scalar reservation remain charged while dependencies execute.
Commit transfers pending to committed without a gap; abort releases only
pending storage. New cache-state guards prevent unsigned frame/native/memo
subtotal underflow. Reset and invalidation clear the new counters with
existing visibility. Numerical scheduling, memo replacement, tensor
addresses and external traffic are unchanged.

The subsets pass through schedule, replay executor, binding and native
assembly. Replay also reports the continuously reserved native encoder/
feature/input reconstruction controllers. The allocation ledger adds a
fourth five-stage balanced sum for native scratch, with its own coherent
mode/check/overlap tags. Scratch is a subset, never double-counted in
equivalent payload. The new registers and adder-tree stage enter the
existing controller census.

`anvil_en1_allocation_guard` now observes actual allocations against the
strict `20*P < 9*B` production-payload limit, the 1 MiB fallback ceiling,
the ordinary native-scratch ceiling and forbidden fallback/frontier-ring
overlap. Widened registered shift/add operands precede the comparison;
zero B is a failure, not a savings pass. B uses production padding/window/
KV geometry even in compact builds and is not an external-traffic
denominator. Guard checking starts after native configuration releases
the previous representation; allocations made during current execution
and their pipeline tail remain covered.

The top retains the worker error, drains eight edges plus a check edge,
and converts an otherwise successful job to error 7 if the guard failed.
Only that final successful check establishes the decode session. Parent
completion, public ports, CSR offsets and mandatory checks are unchanged.
This is failure visibility, not proof that all legal workloads fit, an
allocator strategy that permits excess storage, or a complete compact
production-shadow guard.

Changed `rtl/anvil_en1_replay_workspace.sv`,
`rtl/anvil_en1_eval_schedule.sv`, `rtl/anvil_en1_replay_execute.sv`,
`rtl/anvil_en1_replay_binding.sv`, `rtl/anvil_en1_native.sv`,
`rtl/anvil_en1_allocation_ledger.sv`, `rtl/anvil_en1_top.sv`;
added `rtl/anvil_en1_allocation_guard.sv`; updated `design/SPEC.md`
and this document. Tools used: glob, view, rg and apply_patch only.
No static elaboration, simulation, synthesis, installation or experiment
ran; no preparation receipt exists. Parent, verification and runtime
sources were not edited. Attempt-0003 remains preserved without a
claimed repair.

Remaining: finish physical phase overlays and grant-time whole-system
limits; complete production-shadow accounting for every compact text/
arithmetic/controller bank (not only workspace frames/memos), connect
that complete shadow to the same guard, and integrate matched-baseline
traffic telemetry without replacing the independent public-handshake
baseline. Then run the reserved static elaboration check and hand off
to independent Verifier. No correctness, savings, FPGA-fit or timing
result is claimed. Not ready for Verifier.

## Prior saved increment: integrated text banks and final-head overlay

The native assembly now owns one synchronous residual/work/branch/PLE
bank set shared by ordinary full text and replay POST_ONLY execution.
EXTERNAL_VECTOR_RAM passes through frontier/replay wrappers, with unchanged
standalone local-RAM defaults. The bank interface preserves the original
enabled-edge read/write timing. The assembly rejects overlapping per-bank
accesses and out-of-range addresses, and latches a protocol fault if both
workers report live vectors concurrently. Payload has no reset sweep.
The physical ledger counts these banks once in field 20; replay post field
11 remains a real live reservation but has no duplicate physical array.
Shared read registers are counted once in native controller state, not as
two external-worker register sets. This removes 15872 production / 56
compact declared bytes in addition to the final-head change below.

The connected final-logit engine now selects EXTERNAL_PAYLOAD_RAM and
physically omits its duplicate normalized H-bank. Its actual BF16 norm
outputs overwrite the executor's retained last-token hidden vector after
the corresponding raw component's final read. The RMS reduction completes
before this ascending output pass; no reduction or rounding is reassociated.
The same registered source channel identifies raw normalization reads and
committed normalized projection reads. Exact independent store count/index/
last and retained-vector tags guard the overwritten prefix and full-vector
visibility. The standalone default keeps its original internal bank.

The existing hidden allocation remains charged through all output stalls;
the connected final-head payload and physical field 21 are zero instead
of counting another copy. This removes 5120 production / 16 compact
declared payload bytes; it is not measured M20K inference, PPA or savings.
The new counter and phase/error state enter the existing controller census.

Changed `rtl/anvil_en1_final_logits.sv`,
`rtl/anvil_en1_asym_attn_ple.sv`, `rtl/anvil_en1_frontier_execute.sv`,
`rtl/anvil_en1_replay_text_layer.sv`, `rtl/anvil_en1_replay_execute.sv`,
`rtl/anvil_en1_replay_binding.sv`, `rtl/anvil_en1_native.sv`,
`design/SPEC.md` and this document.
Tools used: glob, view, rg and apply_patch. No commands, static elaboration,
simulation, synthesis, installations or experiments ran; no preparation
receipts exist. Parent, verification and runtime files remain untouched.
The attempt-0003 ownership-guard interruption remains preserved without
a claimed repair.

Remaining: whole-system physical phase overlays, ordinary/native-scratch/
fallback allocation-limit enforcement including forced-short-context
production shadows, matched-baseline traffic integration, then the
reserved static elaboration check and independent Verifier handoff.
No correctness, savings, FPGA-fit or timing result is claimed.
Not ready for Verifier.

## Prior saved increment: physical feature/PLE and owner-source overlays

The ordinary executor now physically shares its Hmax feature RAM with the
later PLE transport prefix, preserving the separate retained hidden vector
needed by upper shared layers. The final successful feature callback
releases feature visibility and reserves PLE before embedding can emit it.
Feature fill/callback and PLE fill/source phases use one synchronous write
port and one registered read port. Physical accounting counts this array
once, removing 512 production / 8 compact declared payload bytes.

The owner rematerializer now selects the tile's explicit
EXTERNAL_INPUT_RAM mode. Its source RAM holds the fallback entering vector,
then input RMS outputs overwrite only already-consumed components in
ascending order. Ordinary execution reads original components from the
tagged frontier and writes normalized components to that same source RAM,
never to the frontier. Subsequent projection callbacks read the completed
normalized source. Exact store indices/count and registered raw/normalized
callback identity reject incomplete or malformed materialization.
The numerical tile physically omits its duplicate Hmax input array;
the nested replay/query default mode is unchanged. Combined owner source/
tile reservation falls from 11264 to 6144 production bytes (48 to 32
compact), with shared-bank and head-bank live fields kept disjoint.
These are declared storage changes, not measured M20K inference or PPA.

Changed `rtl/anvil_en1_frontier_execute.sv`,
`rtl/anvil_en1_owner_kv_tile.sv`, `rtl/anvil_en1_owner_replay.sv`,
`rtl/anvil_en1_replay_kv_tile.sv` (explicit unused default-mode ports),
`design/SPEC.md` and this document. Tools used: glob, view, rg and
apply_patch. No commands, static elaboration, simulation, synthesis,
installations or experiments ran; no preparation receipts exist.
Parent, verification and runtime files remain untouched. The attempt-0003
ownership-guard interruption is preserved without a claimed repair.

Remaining: whole-system physical phase overlays, ordinary/native-scratch/
fallback allocation-limit enforcement including forced-short-context
production shadows, matched-baseline traffic integration, then the
reserved static elaboration check and immediate independent Verifier
handoff. No correctness, savings, FPGA-fit or timing result is claimed.
Not ready for Verifier.

## Prior saved increment: scalar RAM reduction, partition guards and traffic census

The production continuation slot now physically contains the same 32 words
used by the compact implementation. Actual connected checkpoint accesses
fit indices 0..31, including the 22-word audio checkpoint and its two head
reduction words. No checkpoint is truncated. Each live/pending frame and
its production shadow reserve the complete 128 bytes. Production backing
is now 231424 words / 925696 bytes; the combined ordinary-frontier/backing
array is 1017856 words / 4071424 bytes. This removes 57344 declared payload
bytes and 1792 visibility-metadata bytes; it is not measured M20K inference
or FPGA PPA. Compact physical backing is unchanged.

Workspace push and memo replacement now register prospective actual and
shadow allocation totals before checking their partition ceilings and
starting writes. Subtraction, addition and comparison occur in separate
FSM stages. Rejected memo admission leaves the old slot intact. Out-of-range
backing commands cannot assert valid. These are bounded partition guards,
not the still-required whole-system ordinary/native-scratch/fallback limits.

Both native memory arbiters now use READ_ONLY=1. A captured write retires
through a registered client error response without an external command;
drain still waits for its acceptance. Default arbiter read/write behavior
and the immutable parent path are unchanged. Public accepted requests feed
a dedicated model-tagged traffic census, including failed responses.
Retained KV read/write metrics receive cache-equivalent classification;
four appended atomic pairs separately report original-input, immutable-weight,
non-KV-output and total external bytes. Any accepted native write is charged
as cache-equivalent rather than mislabeled output. No normal native DDR
output producer exists. The increased CSR reservation enters the ledger.
Independent address scoreboards and an actual-handshake baseline remain
mandatory; matched-baseline traffic metric 6 is still not integrated.

Changed `rtl/anvil_en1_replay_workspace.sv`, `rtl/anvil_en1_frontier.sv`,
`rtl/anvil_en1_memory_arbiter.sv`, `rtl/anvil_en1_native.sv`,
`rtl/anvil_en1_replay_binding.sv`, `rtl/anvil_en1_csr_perf.sv`,
`rtl/anvil_en1_top.sv` and the two design documents.
Tools used: glob, view, rg and apply_patch. No commands, static elaboration,
simulation, synthesis, installations or experiments ran; no preparation
receipts exist. Parent, verification and runtime files remain untouched.
The attempt-0003 ownership-guard interruption is preserved, without a
claimed repair.

Remaining: whole-system physical phase overlays and ordinary/native-scratch/
fallback allocation-limit enforcement, including production-shadow limits
for forced short contexts; matched-baseline traffic telemetry; then the
reserved static elaboration check and independent Verifier handoff.
No correctness, storage/traffic savings, FPGA-fit or timing result is claimed.
Not ready for Verifier.

## Prior saved increment: text-bank overlay and continuous vector lifetimes

The asymmetric text engine now physically reuses one synchronous H-wide
RAM for successive query heads and the later attention-output/MLP branch.
POST_ONLY no longer declares an unused attention-output array. The RAM
read/write schedule and operation order are unchanged; separate lifetime
bits charge each occupied bank before writes and through its last consumer.
Production full/post reservations are 24064/15872 bytes, compact 88/56;
these declared capacities are not measured M20K use or a fit result.

Replay PLE allocation now survives the child-done/EMBED_REGISTER boundary;
the prior state-selected report omitted its completed vector for that cycle.
Ordinary hidden/PLE transport reserves only at embedding start, retains
PLE until the leaf's last source handshake, and releases failed-task banks
after child retirement. Owner raw-source/tile banks release at tile-result
acceptance, not after a later stalled cache response; held scalar pairs
remain in the controller census. Embedding input/PLE banks have separate
last-consumer release events.

Workspace frame/memo live and production-shadow counters now charge full
domain-specific occupied prefixes, rather than production stride holes:
two text/feature H-vectors, two vision vectors, six audio vectors and one
vector per memo. Pending writes/copies remain charged; scalar slots remain
fully reserved. Physical strides, partition bounds and RAM capacity have
not changed. SPEC contains the exact byte and lifetime tables.

Changed `rtl/anvil_en1_asym_attn_ple.sv`,
`rtl/anvil_en1_embedding_ple.sv`, `rtl/anvil_en1_frontier_execute.sv`,
`rtl/anvil_en1_owner_replay.sv`, `rtl/anvil_en1_replay_text_layer.sv`,
`rtl/anvil_en1_replay_workspace.sv` and the two design documents.
Tools used: glob, view, rg and apply_patch. No commands, static elaboration,
functional/synthesis probes or experiments ran; no preparation receipts
exist. Parent, verification and runtime files remain untouched.
The attempt-0003 interruption remains preserved, without a claimed repair.

Remaining: complete whole-system physical phase overlays and ordinary/
native-scratch/fallback limit enforcement, including production-shadow
limits for forced short contexts; connect KV-equivalent/matched-baseline
traffic telemetry. Then run the reserved static elaboration check and
hand off to independent Verifier. No correctness, savings, FPGA-fit or
timing result is claimed. Not ready for Verifier.

## Prior saved increment: arithmetic accounting and execution/allocation telemetry

Scalar/numerical state is now charged from declared register widths through
the common arithmetic, tensor-directory, text, owner, vision and audio
hierarchies. Common primitives include their literal arithmetic children;
native wrappers add these to their existing controller reports without
adding already separately exposed native-child subtotals twice. Ordinary
embedding, full text, anchor and final-head control enters field 24;
owner/replay input, text/post, attention and K/V state enters field 22.
The fixed 74/100/53-byte replay checkpoint/executor/tile estimates are
replaced by explicit register censuses. Payload/tag arrays remain in
their own existing fields, while returned and partial-word copies count
as additional scalar state.

The top connects a new `anvil_en1_allocation_ledger.sv`: three balanced,
five-stage registered trees preserve per-cycle allocation coherence
and model identity. They drive the current payload gauge and replay/
whole-equivalent maxima (CSR 15/20/24). Whole-equivalent accounting adds
all component and metadata fields plus top, immutable native bridge,
CSR counter/snapshot/control and ledger-pipeline reservations. Separate
CSR allocation-event delivery preserves late reports across job/model
transitions without misattributing a native tail to parent work. Existing
clear-over-event and pre-update snapshot semantics remain explicit.
These reports do not enforce the required storage limits or prove fit.

Text attention now reports real accepted Q*K/probability*V scalar
multiply issues and lane-available cycles separately for local/global
heads. Events propagate through ordinary and replay paths, and simultaneous
contributors are summed, not ORed, into CSR 10..13. Successful shared-layer
completion adds only its omitted private BF16 K/V output bytes to CSR 7;
real owner regeneration remains a separate nonzero metric. Neither
counter measures weight traffic or claims improved inference throughput.
`SPEC.md` freezes the precise pre-edge event and report-cycle definitions.

Changed design sources are the new allocation ledger, top/CSR/native
assembly, ordinary and replay text/owner wrappers, common numerical/
directory primitives and their native vision/audio parents in `rtl/`;
the two design documents record their integration and limits.
Tools used: glob, view, rg and apply_patch. No commands, static checks,
functional/synthesis probes or experiments ran; no preparation receipts
exist. Parent, verification and runtime files remain untouched. The
attempt-0003 ownership-guard interruption is preserved, not repaired
or reclassified.

Remaining: close transient-vector reservation lifetimes and actual
physical phase overlays; enforce ordinary/native-scratch and fallback
allocation limits (including forced short-context production-width
shadow accounting); connect missing KV-equivalent/matched-baseline
traffic telemetry. Then use the reserved static elaboration check and
hand off immediately to independent Verifier. No correctness, savings,
FPGA-fit or timing result is claimed. Not ready for Verifier.

## Prior saved increment: connected controller reservations and payload baseline

The native component vector now has 25 fields. New fields 22..24 carry
previously disconnected controller reservations through the real replay
binding and native assembly: all reported replay workers (not just the
selected worker), Eval scheduler, workspace, owner-source control, both
memory arbiters, cache control, frontier schedule, ordinary executor,
frontier RAM control and local-ring control. Binding/native own registers
remain in their existing fields. The same register reservation is
disclosed physically; idle controllers are not advertised as removed RAM.

New leaf censuses use declared register widths and exclude payload/tag
arrays already accounted elsewhere. Workspace metadata and controller
state now have disjoint explicit partitions, including partial-copy and
stalled-return registers. Eval scheduling no longer reports a fixed
175-byte size. Existing nested worker reports remain subtotals: unreported
primitive and child state must still be added before claiming complete
allocation accounting.

The top now registers the matched-unshared BF16 payload calculation and
updates CSR metric 16 only at actual validated native-job dispatch.
Production formulas retain the admitted padding, window, per-model KV
heads and complete logical-layer copies. COMPACT reports its own geometry,
not a production savings result. Rejected descriptors/position scans do
not update the gauge. This is an analytical payload denominator only;
metric 6 and independent external-handshake baseline execution are not
replaced by it.

Changed RTL: `anvil_en1_memory_arbiter.sv`,
`anvil_en1_replay_workspace.sv`, `anvil_en1_eval_schedule.sv`,
`anvil_en1_replay_execute.sv`, `anvil_en1_owner_replay.sv`,
`anvil_en1_replay_binding.sv`, `anvil_en1_frontier_schedule.sv`,
`anvil_en1_kv_shared_cache.sv`, `anvil_en1_frontier.sv`,
`anvil_en1_local_ring.sv`, `anvil_en1_frontier_execute.sv`,
`anvil_en1_native.sv` and `anvil_en1_top.sv`; updated `SPEC.md`
and this document. Tools used: glob, view, rg and apply_patch.
No commands, static checks, simulation, synthesis, installations or
experiments ran, and no preparation receipts exist. Parent, verification
and runtime files remain untouched. The original attempt-0003
ownership-guard interruption is preserved without a claimed repair.

Remaining: finish unreported numerical/child/top register and transient
allocation accounting, physical phase overlays and short-context
native-scratch/full fallback enforcement; connect remaining actual
traffic, avoided work, local/global utilization and complete live/peak
events. Then run the reserved static elaboration check and hand off to
independent Verifier. No correctness, savings, FPGA-fit or timing result
is claimed. Not ready for Verifier.

## Prior saved increment: accepted replay traffic and owned payload reports

The registered arbiters now capture original-input versus weight-image
provenance and replay-path identity with real accepted commands. These
attributes survive arbitration and public memory stalls. The top retains
them through the literal memory bridge and updates replay input/weight
CSRs only on accepted public DDR requests, including requests whose
responses subsequently fail. Internal source callbacks and projected
result bytes are not external traffic.

Original-input classification now includes both callers' token-ID reads
and embedding reconstruction's actual repeated token reads, native
placeholder mappings, vision input directories/pixels/coordinates and
audio input directories/values/masks. Vision layer-zero patch input
events, previously omitted from the replay vision event aggregation,
are connected. Owner and Eval weight images/directories remain weight
traffic. Ordinary text and position scanning are not relabeled replay;
the shared text-mask client retains its actual requesting path. No
numerical datapath or public top port changes were made for these tags.

The embedding, asymmetric text and final-logit workers now own explicit
payload reservations from legal validation to accepted completion.
The native allocation observation vector has 22 fields: fields 19..21
add the ordinary embedding, full attention/PLE/MLP and final normalized
vector copies that the earlier component subtotal omitted. Replay
embedding/post reports now come from the same real worker reservations;
the dispatcher sums both embedding children instead of hiding one by
selection. Reports include failures and output stalls, with physical
declared banks separately disclosed. They do not yet include all
arithmetic/controller state or implement the required physical overlays.

Changed RTL: `anvil_en1_memory_arbiter.sv`, `anvil_en1_embedding_ple.sv`,
`anvil_en1_vision_patch.sv`, `anvil_en1_replay_vision_layer.sv`,
`anvil_en1_replay_input.sv`, `anvil_en1_replay_text_layer.sv`,
`anvil_en1_replay_execute.sv`, `anvil_en1_replay_binding.sv`,
`anvil_en1_asym_attn_ple.sv`, `anvil_en1_final_logits.sv`,
`anvil_en1_frontier_execute.sv`, `anvil_en1_native.sv` and
`anvil_en1_top.sv`; updated `SPEC.md` and this document.
Tools used: glob, view, rg and apply_patch. No commands, static checks,
simulation, synthesis, installations or diagnostic experiments ran;
no preparation receipts exist. Parent, verification and runtime sources
remain untouched. The original
`.vulcan/engineering/run-0001/attempt-0003` interruption is preserved,
without a claimed repair.

Remaining: complete primitive/controller and transient allocation
accounting, actual phase overlays and short-context/native-scratch/full
fallback limit enforcement; connect remaining matched-baseline,
avoided-work, local/global utilization and complete live/peak metrics.
Then use the reserved static elaboration check before independent
Verifier handoff. No savings, functional correctness, FPGA fit or timing
result is claimed. Not ready for Verifier.

## Prior saved increment: parent-compatible top/session/CSR boundary

`rtl/anvil_en1_top.sv` now connects the immutable parent top, the real native
assembly, a registered native memory bridge and the literal CSR engine.
Every parent named parameter/port is retained, including signed embedding
data. Native geometry is not changed by compatibility parameters. The
wrapper captures every parent/native descriptor field, selects exactly one
memory owner and holds outer completion until public acceptance.

Native session validation requires prefill at position zero or a one-token
append to the complete unchanged-prefix input arrays. Decode compares the
successful prior session's model, precision, modality, input/weight bases
and encoder geometry. It checks full context/range/alignment bounds before
issuing real positions-array reads and requires position[t]=t. Every read
passes through the registered bridge, including errors. Position memory
errors return 2, malformed positions 5, stale/invalid appends 7 and invalid
native model/precision 6. No native start follows a rejected scan.

The native descriptor is stable through acceptance. The generation skips
zero on wrap; the native assembly still completes its actual cache/
frontier/ring/replay invalidation barriers before work. Successful
completion records the next expected append position; execution failures,
accepted prefills and accepted parent jobs invalidate the old session.
Native decode recomputes from immutable original inputs rather than
retaining an external hidden-state archive. Only native logits or parent
embeddings can be valid, never both. Child completion is registered before
the public held completion, and memory ownership cannot switch during it.

CSR wiring currently records busy cycles, successful jobs, all accepted
public read/write bytes (also failed transactions), aliases, resident hits,
errors, actual owner/replay-owner reprojection bytes, memo hits/evictions
and completed fallback jobs. Atomic pairs, snapshots, saturation and
clear priority use the existing CSR implementation. Owner reprojection is
not counted as avoided computation. Remaining metric slots are **not
measured zeroes**: KV-equivalent traffic classification, matched-baseline
traffic/payload, avoided work, local/global component utilization, replay
input/weight traffic and aggregate live/peak storage events still need
connection to their real sources. Projection result-byte events are not
weight traffic and are deliberately not mislabeled.

Complete component/primitive/controller storage accounting and actual
phase overlay/limit enforcement remain unfinished, notably the ordinary
short-context native scratch allowance and the complete 1 MiB fallback
ceiling. The top's current named component reports are not a complete
ledger and cannot establish either savings threshold or FPGA fit. These
are remaining implementation tasks, not waived acceptance criteria.

Saved changes in this increment: new `rtl/anvil_en1_top.sv`, updated
`design/SPEC.md` and this document. Tools used: glob, view, rg and
apply_patch. No commands, static elaboration, simulation, synthesis,
installation or diagnostic experiments ran; no preparation receipts exist.
The single reserved static check remains unused. Parent, verification and
runtime sources remain untouched, and the original
`.vulcan/engineering/run-0001/attempt-0003` interruption remains preserved
without a claimed repair.

Next: finish complete allocation overlays/limit enforcement and the
remaining real telemetry sources; then run the reserved static elaboration
check and hand off to independent Verifier. Not ready for Verifier.

## Prior saved increment: connected native execution assembly

`rtl/anvil_en1_native.sv` connects the literal frontier scheduler/executor,
cache, real owner/replay binding and three-client memory arbiter. The
binding's owner-source/ring callbacks, frontier Eval stream and actual
backing channel now close onto the executor. Ordinary resident misses
regenerate through the real owner worker; recursive replay shares cache
metadata but does not reenter the blocked resident fetch channel.

Registered metadata arbitration retains full commands and response owners.
Replay metadata can progress while ordinary attention waits for owner
regeneration. Registered mask arbitration rereads real immutable unsigned32
0/1 masks through the shared memory arbiter, checking token bounds, full
byte-address sums, memory failures and malformed data. It does not replace
the mask with a constant or permit host-produced hidden/KV answers.

The assembly captures a complete native context, validates it, acknowledges
cache invalidation, releases/configures the old frontier/ring, configures
the actual replay binding and only then starts the schedule. The same
padded capacity rule selects binding and scheduler fallback modes.
Completion waits for schedule/output completion, idle workers and routers,
and an acknowledged memory drain. The arbiter drain request is gated by
that same idle condition so it cannot block a worker's remaining accesses.
Parent compatibility and public decode/session/position handling belong
to the enclosing top described above.

`kv_shared_cache` now reports actual occupied resident-pair bytes,
physical payload, tag metadata and one-shot validated hit/miss/accepted
alias events. Its existing metadata/fetch datapath and latencies are
unchanged. The native assembly carries 19 separate live/physical component
fields, four metadata fields and the existing workspace shadow/reservation
reports. Shared workspace RAM is physically charged once, not as a second
allocation. Its own controller/register bits are reported explicitly.
These reports remain incomplete subtotals: not all primitive/controller
state is counted, and short-context native scratch/full fallback overlay
limits are not enforced. No measured reduction, resource fit or timing
claim is made.

Saved changes: new `rtl/anvil_en1_native.sv`; updated
`rtl/anvil_en1_kv_shared_cache.sv`, `design/SPEC.md` and this document.
Tools used: glob, view, rg and apply_patch. No commands, static elaboration,
simulation, synthesis, installations or experiments ran; no preparation
receipts exist. The reserved static check remains unused. Parent,
verification and runtime files remain untouched; the original
`.vulcan/engineering/run-0001/attempt-0003` interruption remains preserved
without a claimed repair.

The enclosing top/session/positions/memory routing now exists as described
above; complete telemetry, live/physical overlays and storage-limit
enforcement, including short-context native scratch and the fallback
arithmetic/controller allowance, remain required before the reserved
static check and independent Verifier handoff.

## Prior saved increment: shared owner/frontier replay binding

`rtl/anvil_en1_replay_binding.sv` now connects literal owner projection,
real continuation/memo execution and a registered two-client memory
arbiter. A registered session binds original text/image/audio descriptors.
Owner and frontier Eval starts share one actual scheduler; owner wins
simultaneous offers, with no preemption after acceptance. The complete
selected descriptor and response owner are retained through scheduler
stalls, output backpressure and actual completion. Invalid native
model/precision and stale/session-mismatched descriptors fail before
scheduler/backing access.

The cache remains the only regeneration producer. Ordinary projections
use the exposed tagged frontier/ring callbacks; fallback owner projections
consume the real Eval hidden vector. The frontier requester also accepts
domain-3 feature jobs. Both use the same backing channel and numerical
implementation, never a second replay engine or host-produced KV/features.
Owner and replay immutable-memory commands pass through the literal
registered arbiter; its local owner IDs remain separate from tensor-map
traffic classes. Workspace and individual vector live/physical reports
remain separate, and the binding's own 105-byte controller is counted.
Child/primitive/top accounting is not complete.

`eval_schedule` now acknowledges workspace invalidation after its last
accepted output before publishing successful root completion. Memos still
serve all dependencies within the root; no cross-root reuse is lost
because roots already rebound the workspace. The retained image worker
also cancels on accepted root completion, not just next-root acceptance,
so a failed suspended continuation cannot retain visibility across the
next representation switch. Normal dependency yields remain durable.

Saved changes in this increment:
`rtl/anvil_en1_replay_binding.sv`, `rtl/anvil_en1_frontier.sv`,
`rtl/anvil_en1_frontier_execute.sv`, `rtl/anvil_en1_eval_schedule.sv`,
`rtl/anvil_en1_replay_execute.sv`, `design/SPEC.md` and this document.
The ordinary native feature and disjoint backing changes are described
below. `design/GENERATIONAL_HANDOFF.md` was read; its parent STA/PPA/HIL
entries are N/A, not evidence of timing closure.

Tools used: glob, view, rg and apply_patch. No commands, static elaboration,
simulation, synthesis, installations or experiments ran; no preparation
receipts exist. The reserved static check remains unused. Parent,
verification and runtime files remain untouched; the original
`.vulcan/engineering/run-0001/attempt-0003` ownership interruption remains
preserved without a claimed repair.

Next concrete dependency: wire this binding's Eval, owner-read/ring and
backing ports to the frontier executor, arbitrate its cache metadata/mask
requests with ordinary execution, and connect session/schedule/cache,
parent-compatible top and CSR paths. Complete actual live/physical
phase overlays, including native scratch at short contexts and the
complete fallback ceiling. None of the current subtotal reports
establishes those bounds. Not ready for Verifier.

## Same increment: ordinary native features and disjoint backing

`frontier_execute` now dispatches ordinary image/audio placeholders through
the real Eval domain-3 feature route before embedding or per-layer PLE.
A separate synchronous feature bank preserves the existing hidden vector
and frontier. Exact ordered reception and actual successful completion
precede visibility. Registered callbacks validate generation, token,
kind, model and index; stale/partial features fail explicitly. Native
feature values no longer come from the outward modality-response port.
The new bank's live and physical reports are additive to existing H/P
storage.

`frontier` now provides ordinary replay backing in a physically disjoint
tail of its one payload RAM. Production ordinary backing starts at word
786432; compact backing starts at word 2048. Fallback still requires
release/drain and explicit binding, then uses base zero. Generation and
range checks precede synchronous payload access; one acknowledged RAM
operation is outstanding. Physical reservations increase to 4128768 bytes
production and 835584 bytes compact, disclosed separately from live bytes.
Neither the ordinary frontier cap nor the admitted live-payload limits
change.

Whole-system live/physical overlays remain necessary, including the
ordinary native scratch limit `min(1 MiB,floor(B/8))` and the complete
fallback 1 MiB ceiling. Current frame-slot accounting does not establish
these bounds; physical partitioning is not acceptance. Not ready for
Verifier.

## Prior saved increment: durable image placeholder-to-feature replay

`rtl/anvil_en1_replay_image_feature.sv` connects immutable image-placeholder
ordinal/count mapping to the real `vision_soft_token` bin mapper, pool,
normalization and modality projection. A sequential divider checks the
physical patches/9 pool extent. The bin mapper independently retains the
coordinate-derived valid-bin ordering and count checks.

The genuine pool's layer-16 source callbacks now yield domain-1 encoder
dependencies through `replay_execute`. While that separate lower-rank
worker runs, the image worker retains its literal numerical FSM, scalar
reduction and pooled RAM. Resume validates the full retained descriptor,
generation/position/patch/component continuation and actual completed
768-component memo before issuing acknowledged pair reads. It neither
restarts a partial reduction nor accepts host-produced features.
Same-rank feature nesting is excluded by the existing rank check.

The image worker emits no external or workspace request while suspended.
Its live storage remains charged while the vision replay worker executes.
The 6432-byte physical bin/pooled/normalized reservation is disclosed
separately from frame/memo storage; its own and reported nested controllers
remain separate. Actual H feature outputs are ordered and paired into
frame bank 0, with one acknowledgment before further pair progress.
Failures reject/drain the actual numerical child. A new accepted scheduler
root cancels any abandoned source-stalled continuation before new dispatch.

`replay_input` and `replay_text_layer` bind both image and audio callbacks
to the matching domain-3 completed feature memo, including the immutable
token-kind check on resumed per-layer PLE work. Image callbacks no longer
request a host feature through the outward modality port. Real embedding,
gated PLE, post-attention and MLP arithmetic remain connected.

Saved changes: new `replay_image_feature`; updated `replay_execute`,
`replay_input`, `replay_text_layer`, `SPEC.md` and this document.
Tools used: glob, view, rg and apply_patch. No commands, static elaboration,
simulation, synthesis, installations or experiments ran; no preparation
receipts exist. The reserved fast static check remains unused. Parent,
verification and runtime files are untouched, and
`.vulcan/engineering/run-0001/attempt-0003` remains preserved without a
claimed repair.

Next concrete dependency: ordinary frontier/native-feature routing and
its real bounded backing allocation, then shared owner/fallback execution
arbitration, complete live/physical overlays and compatible top/cache/CSR
integration. In particular, ordinary modality replay cannot silently use
RAM still occupied by the live text frontier. Primitive-state accounting,
resource fit and timing remain unproven. Current design is not ready for
Verifier.

## Prior saved increment: native audio placeholder-to-feature replay

`rtl/anvil_en1_native_token_map.sv` derives a real placeholder ordinal and
count by scanning the entire immutable text stream. Audio mapping then
reads the actual original validity mask at every fourth frame, selects
the requested true-mask ordinal and checks that the full valid-token
count matches audio placeholders. Invalid identities, forbidden modality
placeholders, malformed masks, memory failures and count mismatches return
explicit errors. Every accepted scan/mask/directory read is original-input
traffic, including failures; there is no feature map supplied by the host.
The image ordinal/count output is available for the existing vision-bin
mapper, but its complete replay binding is still pending.

`rtl/anvil_en1_replay_audio_feature.sv` connects that mapping to the real
bounded scheduler. It yields for the exact mapped domain-2 layer-12
vector, resumes only with the matching completed memo, and supplies its
acknowledged BF16 pairs to the existing native output/norm/modality
projection engine. Actual H outputs are ordered, paired and acknowledged
into the current feature frame. Source failures drain the real numerical
worker; partial output never becomes a completed feature.

The scheduler/workspace now carry domain-3 completed features at text H,
with rank 18 below text rank 19+l and above native encoder ranks 1+l.
Feature frame/memo live and production-shadow charges are connected.
The literal feature engine's scratch/controller reservations are separately
reported through `replay_execute`, not relabeled as shared frame RAM.
Domain-3 layer 2 is connected audio; image layer 1 remains an explicit
dispatcher error until its durable pooling worker is implemented.

The domain-0 `replay_input` now yields for that actual audio feature before
starting embedding. Its resumed audio callbacks read the feature memo,
not the outward modality port. Opening its frame streaming store waits
for a real embedding input valid, avoiding a store reservation that would
deadlock earlier feature memo reads. `replay_text_layer` likewise retains
its genuine entering/attention frame banks while yielding for the feature,
then executes the existing real per-layer embedding, gated PLE and
post-attention/MLP path. Its distinct continuation skips only already
completed attention, never the numerical PLE. Existing image callbacks
remain pending native routing; no complete five-domain execution is claimed.

Saved changes: the two new RTL modules above; `replay_input`,
`replay_text_layer`, `replay_execute`, `eval_schedule`, `replay_workspace`,
`SPEC.md` and this document. Tools used: glob, view, rg and apply_patch.
No commands, elaboration, simulation, synthesis, installations or experiments
ran, and no preparation receipt exists. The reserved fast static check
remains unused. Immutable parent, verification and runtime files are
untouched; `.vulcan/engineering/run-0001/attempt-0003` remains preserved
without a claimed repair.

Next concrete dependency: durable image pooling/feature replay and native
image-placeholder binding, followed by ordinary owner/frontier execution,
fallback/cache/arbiter binding, whole-system live/physical overlays and
parent-compatible top/CSR integration. Complete the design before the
independent Verifier handoff; current sources are not ready.

## Prior saved increment: connected durable full audio-layer replay

`rtl/anvil_en1_replay_audio_history.sv` reconstructs actual attention
residuals for the query and its at most four causal lightconv predecessors.
The literal residual worker retains genuine lower-layer head continuations.
Completed histories survive those yields in four frame slices; scratch
entering/residual and heads use the remaining two. The last history remains
in scratch. Six native 1024-component BF16 vectors total exactly 12 KiB,
not an additional hidden-state archive or same-rank Eval stack.

`rtl/anvil_en1_replay_audio_layer.sv` connects those genuine histories to
the existing lightconv, FF2, final stability clamp and learned norm_out.
Source callbacks read actual acknowledged frame pairs with checked
generation/layer/token/index and causal distance. Lightconv emits only
after its historical reads; its outputs may then replace scratch.
FF2's real half-weighted residual passes through the clamp into a distinct
source bank. Norm_out reads that bank and writes the final bank-0 vector.
Every phase requires actual completion, exactly 1024 ordered values,
correct last and all pair acknowledgments. Source callbacks have priority
over simultaneous output/completion so no outstanding read is stranded.
Errors drain the selected numerical engine and workspace response.

`rtl/anvil_en1_replay_execute.sv` now dispatches domain-2 layers 1..12
through this complete conformer worker, retaining its layer-zero native
input worker. Yield descriptors return to the existing bounded scheduler;
only final norm_out returns a completed encoder Eval vector. Audio
history/GLU events and connected live/physical/controller reports are
exposed alongside the earlier input/vision/text observations.

`replay_workspace` has independent visibility and ordered pair progress
for three audio slices per bank. Slice-zero interfaces remain compatible;
nonzero slices reject other domains/operations. Its compact frame stride
now matches production because native encoder widths are not compacted.
Audio compact live frames charge all 12 KiB plus scalar storage. The
compact backing and the frontier's reused payload RAM both reserve
206848 words / 827392 bytes; ordinary compact capacity remains 8192 bytes.
Production reservations and the 3 MiB frontier cap are unchanged.
`replay_audio_residual` redirects only head-vector traffic with its
default-preserving PACKED_FRAME option. There is no second backing RAM.

These are saved source changes, not executed correctness, M20K inference,
resource fit or timing results. All literal workers' physical reservations
remain additive. Whole-system primitive/controller accounting and scratch
overlays are still required to meet the complete fallback ceiling.
Next concrete dependency: connect completed audio-feature production to
the domain-2 replay result and native modality/session placeholder routing,
then owner/frontier/fallback binding and top/cache/arbiter/CSR integration.
The design is not ready for Verifier.

Tools used: glob, view, rg and apply_patch. No commands, static elaboration,
simulation, synthesis, installation or experiments ran; no preparation
receipt exists and the reserved static check remains unused. Parent,
verification and runtime metadata remain untouched. The original
`.vulcan/engineering/run-0001/attempt-0003` interruption remains preserved
without a claimed repair.

## Prior saved increment: connected durable audio attention residual

`rtl/anvil_en1_replay_audio_residual.sv` now connects the literal durable
eight-head worker to the genuine post-attention residual execution. The
existing `audio_attention_residual` gains a default-preserving
`FRAME_HEADS=1` option: reconstruct real query FF1 from the entering frame,
read real committed head components for the clipped post projection, apply
the existing clamp/learned post norm and BF16 residual addition. Its new
tagged source-kind output separates entering-vector and head-vector reads.
Default `FRAME_HEADS=0` still computes heads itself.

The compound worker reads frame bank 0/1 through acknowledged workspace
callbacks, not host attention answers. Actual post outputs replace bank 0
only after query FF1 and all head projections finish. Every output pair
waits for its concrete workspace acknowledgment before another output
is accepted. Head yields retain the existing tagged checkpoints and
partial bank-1 outputs; post work starts only after actual successful
head-stage completion. Errors drain active post/source responses before
failure completion. A successful result is the attention residual in bank
0, not norm_out or a completed encoder layer.

Both literal workers' live/physical vector reports and reported controllers
remain connected. Their separate physical banks are summed rather than
claimed as shared storage; durable frame vectors remain in the existing
workspace ledger. Accepted immutable-weight commands and on-chip source
callbacks are separately counted, including commands whose responses fail.
Whole-system scratch overlays, primitive-state accounting and actual M20K
inference remain unproven.

Next concrete dependency: durable historical attention-residual reconstruction
inside causal light convolution, preserving the query residual and partial
convolution output across lower-layer dependency yields without same-rank
Eval or uncounted retained banks. Then connect real FF2/clamp/norm_out and
higher-layer audio replay. Modality/session routing, owner/frontier/fallback
binding, whole-system allocation overlays and parent-compatible
top/cache/arbiter/CSR integration still remain. Not ready for Verifier.

Tools used: glob, view, rg and apply_patch. No commands, static elaboration,
simulation, synthesis, installation or experiments ran; no preparation
receipt exists and the reserved static check remains unused. Parent,
verification and runtime metadata remain untouched. The original
`.vulcan/engineering/run-0001/attempt-0003` interruption remains preserved
without a claimed repair.

## Prior saved increment: durable audio heads with actual frame/memo inputs

`rtl/anvil_en1_replay_audio_attention.sv` now connects its real
REPLAY=1 executor to the literal FF1/clamp/learned pre-attention norm,
instead of accepting normalized hidden vectors from its outward source.
An available-token miss holds the original numerical need pending,
executes actual pre-attention reconstruction and checks both full
1024-component streams before committing a tagged synchronous normalized
cache. The head reads that cache with registered tag/read/capture/response
stages. Hits and native relative-position K bypass outward dependencies.
Unavailable historical inputs retain the existing acknowledged checkpoint
and executor-drain path. Partial/error caches stay unreadable and charged;
failed reconstruction rejects the waiting head need and retires the
numerical executor before failure completion.

`rtl/anvil_en1_replay_audio_heads.sv` adds the compound eight-head/frame
stage. The query predecessor is copied by the existing domain-2 binding
worker into immutable frame bank 0. Actual FF1 source callbacks read that
frame or the matching lower-layer memo slot through acknowledged workspace
reads; no source-vector or attention answer is manufactured. All eight
native numerical heads write their actual concatenated outputs to frame
bank 1 using ordered acknowledged BF16 pairs. A dependency yield saves
the numerical checkpoint plus accepted global component count/unpaired
lane in scalar words 30/31. Resume validates those scalars and restarts
the tagged unfinished head, not the whole attention stage. Earlier head
outputs and partial-pair visibility/progress survive in the existing
workspace, with no additional durable vector archive.

The normalized cache/pre-attention vector live/physical reports, all
reported numerical and binding controllers, accepted on-chip source reads,
immutable weight commands, original-mask reads and actual intermediate
events are connected through this stage. These declarations are not
measured allocation, traffic, numerical correctness, M20K inference or
timing evidence.

This stage is deliberately not dispatched as a completed encoder Eval:
its bank-1 result is head concatenation, not norm_out. The next concrete
integration dependency is the enclosing durable conformer dispatcher:
retain the entering vector and head outputs, execute clipped post
projection/post norm and the genuine FF1 residual, then suspend/resume
historical causal-lightconv reconstruction before FF2/clamp/norm_out.
Only that complete dispatcher may publish a higher domain-2 layer result
through `replay_execute`. Modality/session routing, owner/frontier/fallback
binding, whole-system allocation overlays and parent-compatible
top/cache/arbiter/CSR integration still remain. Not ready for Verifier.

Tools used for this increment: glob, view, rg and apply_patch. No command,
static elaboration, simulation, synthesis, installation or experiment ran;
the reserved static check remains unused and no preparation receipt exists.
Verification, immutable parent and runtime-owned metadata remain untouched.
The original interruption at `.vulcan/engineering/run-0001/attempt-0003`
remains preserved without a claimed repair.

## Prior saved increment: complete connected native conformer

`rtl/anvil_en1_audio_layer.sv` connects the saved genuine FF1/relative
attention residual to causal light convolution, genuine FF2, final BF16
stability clamp and learned norm_out. Historical light-convolution inputs
are produced by rerunning the same attention-residual engine from actual
layer-entry callbacks, not by accepting host attention/GLU answers.
The completed query attention residual remains immutable while that
single tagged historical cache refills. Memory ownership passes to
attention only while the lightconv/GLU source request is waiting after
its preceding external response retired.

Three 2048-byte outer banks use explicit complete-vector visibility and
phase reuse: FF2 reuses the former query bank only after convolution
completion, and its source convolution bank releases only after FF2.
The connected physical vector reservation is 34816 bytes; scheduled
peak live vector allocation is bounded by 26624 bytes. Both figures
exclude additional primitive/controller state and are implementation
accounting, not measured liveness, inferred M20Ks or proven resource fit.

`rtl/anvil_en1_replay_audio_attention.sv` connects the real REPLAY=1
audio head executor to acknowledged frame scalar operations. It saves
the 22 live checkpoint words at indices 8..29, retaining 30/31 for the
enclosing worker. Restore validates the complete tagged 160-bit outer
descriptor and recreates reserved head words as zero. An actual accepted
need/yield decision supplies the dependency token. The wrapper drains
the executor's real done_yield before storing/publishing a continuation,
so the numerical executor is idle before another resume. Relative K
uses locally generated position inputs and cannot push historical Eval.

`rtl/anvil_en1_replay_audio_input.sv` connects genuine layer-zero
subsampling/input projection to domain-2 frame bank 0. Ordered actual
BF16 pairs wait for acknowledged workspace writes; child completion and
all 1024 components are required. Workspace errors drain the still-live
subsampler rather than returning while it owns a response.
`rtl/anvil_en1_replay_execute.sv` now captures immutable native audio
bases/frame count at root acceptance and dispatches that layer-zero
worker through its existing scheduler, external memory and backing
interfaces. Input/projection/point-replay events and audio vector/
controller allocation reports are connected. The existing text/vision
selection remains separate.

Full domain-2 conformer/frame dispatch remains unfinished: higher audio
layers still reject explicitly, and the non-resumable conformer has not
yet been connected to the durable head/memo flow. This is not complete
native audio inference or a ready handoff to Verifier.

Remaining integration: durable audio-layer continuations and memo dispatch,
completed audio-feature binding, modality/session
mapping, owner/frontier/fallback binding, complete allocation overlays
and parent-compatible top/cache/arbiter/CSR integration. Not ready for
Verifier. Next connect the audio layer's lower-layer input dependencies
to real memo/frame reads, save the numerical head checkpoint and partial
outer vector/index state before every dependency yield, and resume the
actual FF1/attention/convolution/FF2 sequence without same-rank Eval
or uncounted retained scratch.

Tools used: glob, view, rg, web_fetch and apply_patch. The pinned model
read established the final clamp/norm_out ordering. No commands,
installation, static elaboration, simulation, synthesis or experiments
ran; the reserved static check remains unused and no preparation receipt
exists. Parent, verification and runtime-owned files remain untouched.
The original ownership-guard interruption at
`.vulcan/engineering/run-0001/attempt-0003` remains preserved without a
claimed repair or acceptance.

## Prior increment: connected native audio attention residual

`rtl/anvil_en1_audio_attention_residual.sv` now connects the actual
feed_forward1, attention-input clamp/RMSNorm, all eight native attention
heads, clipped post projection, output clamp/RMSNorm and unweighted
query residual. Its external source callback supplies actual layer-entry
hidden components for requested tokens; it does not supply FF1, Q/K/V or
attention answers. Historical source vectors are recomputed by the same
real pre-attention worker and retained in one tagged synchronous on-chip
cache. The query's FF1 residual stays immutable during those refills.
Source/memory ownership changes only after the preceding projection
reader has retired its response and is waiting for its source callback.
Complete stream counts, tags, last and concrete completions precede
vector visibility. There is no generated-feature external write port.

`rtl/anvil_en1_audio_pre_attention.sv` connects the saved complete FF1
to its pinned clamp and learned norm_pre_attn. Kind 0 emits the genuine
unclipped FF1 residual; kind 1 emits the genuine normalized attention
input. Raw acceptance precedes the registered clamp and synchronous
working-bank write. FF1 remains stalled through each clamp/write.
The complete successful bank is required before normalization.

`rtl/anvil_en1_audio_attention_execute.sv` connects the attention head
to actual immutable stride-4 original masks and the Q/K/V/relative pair
service. It preserves the first specific input/tile error, validates
every output and explicitly distinguishes replay yield from completed
attention. The pair source callback is the pre-attention boundary above.
Only its selected mask or projection reader owns external cmd/result.

`rtl/anvil_en1_audio_qkv_tile.sv` executes two actual clipped Q/K/V rows
or two actual unclipped relative-K rows. Matrix outputs materialize BF16.
Q then uses the genuine BF16 softplus of the learned per_dim_scale
and binary32 query scale; K uses the pinned binary32 constant. V and
relative K are widened without invented RMSNorm or rotation.
The 64-bit pair response contains two binary32 scaled components;
narrowing it to a BF16 cache word would lose the pinned attention
semantics and is not performed.

`rtl/anvil_en1_audio_relative_position.sv` generates all 1024 actual
concatenated sine/cosine source components with 512 timescales, using
sequential conversion/division, exp and range-reduced trigonometry.
`rtl/anvil_en1_softplus.sv` implements the stable bounded log1p series,
the positive threshold and exceptional-value handling. Both retain
the existing arithmetic/format boundaries; their approximation accuracy
has not been independently established.

`rtl/anvil_en1_audio_attention_head.sv` executes native 24-column
blocked attention with strict causal distance <12. Content and relative
dot reductions are separate; the blocked relative shift selects the
actual distance for unmasked keys. The sum receives softcap 50 before
the real mask. Masked logits are finite -1e9, so all-masked rows still
execute the entire softmax and value reduction, including real masked
values and padded +0 values. Probabilities and accumulation stay
binary32 until each of the 128 final outputs narrows to BF16.
Its tagged 1024-bit continuation yields only before projection service,
after previous arithmetic/memory retirement. Only words 0..21 are live;
the intended durable binding uses scalar words 8..29, leaving 30/31
for output count and unpaired BF16 within the existing compact frame.
That durable audio binding is not yet implemented.

The attention-residual worker physically reserves four 2048-byte banks;
the pre-attention worker reserves another 2048 bytes and its connected
FF1 reserves 6144. Thus the connected physical vector reservation is
16384 bytes. The scheduled vector-live maximum is 14336 bytes during
historical reconstruction with query residual/head/cache allocations
retained; this is an RTL allocation bound, not a measured result.
Cache releases before post projection; head storage releases before
post normalization. Concrete partial refills remain charged through
error completion. All controller, directory/decoder and primitive
arithmetic state remains additional; whole-system overlays and the
native scratch/fallback ceilings still require complete integration.

Remaining integration dependencies: full conformer sequencing around
this worker, causal light convolution with real historical attention
residual reconstruction, FF2 and final norm; durable domain-2
continuation/memo dispatch, subsampling layer-zero reconstruction and
completed audio output binding; text modality/placeholder/session
mapping; owner/frontier/fallback binding; whole-system live/physical
allocation overlays and parent-compatible top/cache/arbiter/CSR wiring.
The attention head's replay interface exists, but the residual worker
currently uses its non-replay mode. This is not complete native audio
inference or a ready handoff to Verifier.

Tools used: glob, view, rg, web_fetch and apply_patch. Pinned public
model/configuration reads established the audio operation order,
relative layout/shift, scalar scaling, finite invalid logits and mask
stride. No commands, installation, static elaboration, simulation,
synthesis or experiments ran. The reserved static check remains unused;
no preparation receipt exists. Parent, verification and runtime-owned
files remain untouched. The original ownership-guard interruption at
`.vulcan/engineering/run-0001/attempt-0003` remains preserved without
a claimed repair or acceptance.

## Prior increment: connected durable vision replay

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

The current query/branch overlay removes the separate D-bank. Its conservative
full-bank bound is `6H+2Q*D+2P`, at most 17920 bytes for E2B global
and 24064 bytes for E4B global. Production physical banks reserve 24064 bytes;
compact banks reserve 88 bytes. These figures exclude scalar/child state,
which remains additional. The leaf overlay and its current lifetimes are
specified at the start of this document; they do not prove the full-system bound.

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
