# Anvil-EN1 implementation contract

Product: `v1.0.0-gemma4-kvshare-e2b-e4b`. Target top: `anvil_en1_top`.
Target device: Intel Arria 10 GX `10AX115N2F45E1SG`, synchronous clock period
at most 10 ns. This document freezes implementation choices; it is not an
engineering acceptance or a claim that every described engine exists.

### Current repair: overlay certified-hit staging with directory scratch

The first-origin diagnostic is retained at
`evidence/preparation/top-first-origin-20261103T062331Z-3cbf5c57/receipt.json`.
At cycle 2860033, the layer-4 owner rematerialization grant for component 7
has prospective production-shadow text workspace 32799 bytes, exceeding the
unchanged E2B limit of 32768 bytes. The grant is denied and error 7 propagates
to completion; scratch and footprint comparisons pass. This is not an audio
failure or permission to enlarge the text partition.

`anvil_en1_tensor_image` removes the independent 232-bit `descriptor_q`
register. A certified hit instead registers its descriptor into `entry[231:0]`
at CACHE_SEARCH, then copies that slice into the existing output registers at
CACHE_CAPTURE. Directory parsing and hit staging are mutually exclusive:
a hit never visits ENTRY_VALIDATE/ENTRY_FINISH; a miss overwrites every entry
word before validation. The live directory-entry buffer has no surviving
directory consumer on the hit branch. No descriptor-cache capacity, validity,
replacement, error check, numerical state or external transaction changes.
The existing reset of `entry` also clears the overlaid staging.

| Boundary (sampled pre-edge) | Post-edge behavior |
| --- | --- |
| Active reset | Existing entry/output resets and validity clearing remain |
| Certified hit E2 | Register selected descriptor in the entry scratch slice |
| Hit E3 | Copy scratch slice into descriptor output registers |
| Hit E4 / E5 | Publish / earliest acceptance, unchanged |
| Miss, including eviction | Use the original key scan and complete entry-validation path |
| Invalidation during hit staging | Existing lifetime revocation rejects publication; a stalled published response remains stable |

This removes actual storage rather than discounting live registers. The
controller census drops by 232 bits / 29 bytes per reader, from 3743/468 to
3511/439 bits/rounded bytes. Parent sums automatically propagate that reduction
to live, production-shadow and physical reporting. With the previously
elaborated unchanged 49-reader hierarchy, the source-derived total reduction
is 1421 bytes, not all of which belongs to the text partition: native
reconstruction state retains its existing scratch classification. Independent
Verifier must measure the exact partition reduction, repeat lifetime/error/
stall checks, and execute top completion with the original numerical oracle.
The denied receipt remains immutable; neither the later peak nor completed
logits are established by this source repair.

### Retained repair: separate audio fold request and completion payloads

The production-native synthesis failure is retained at
`evidence/preparation/synthesis-lifetime-production-20261103T060319Z-cb39904a/receipt.json`.
Yosys reached `check -assert` and rejected 32 conflicting drivers; it did not
time out. `anvil_en1_replay_audio_history` now connects the fold's
`work_req_data` to `fold_work_data` and its `done_data` to `fold_done_data`.
Only the request net feeds the work-request mux. Only the completion net is
captured into `fold_data_hold` on the existing completion handshake.
No FSM, arithmetic, allocation or protocol edge changes.

The earlier separate text-only failure is retained:
`evidence/preparation/top-lifetime-completion-20261103T060319Z-d4ab0218/receipt.json`.
E2B/BF16/seed17/C3 exited 1 without timeout, with error 7 at cycle 2860065,
54765 accepted reads and zero logits. The last aggregate sample names layer-3
tensors, but does not locate the first error or prove a layer-4 transition
failure. The audio repair is not an explanation for that text failure.

The subsequent first-origin diagnostic above supplies the previously missing
allocation attribution. The original observation request was to capture the first error event:
completion run: record native/schedule/task error handshakes and the active
task operation/layer/token; denied allocation responses with candidate
component/bytes/shadow bytes and the prospective ledger's limit/ratio results;
frontier `admission_fault`, `reservation_overrun` and their individual predicates;
and the first source/cache/frontier response error with its descriptor.
Also record `native_fault` and `allocation_failed`, since top converts either
to error 7 independently of a native numerical error. Stop after the originating
event and its completion propagation, using bounded aggregate diagnostics.
Preserve all allocation and numerical assertions. The retained aggregate log
alone did not justify a text-path RTL repair.

### Retained repair: immutable-job tensor reuse and narrow workspace updates

The retained completion failure is
`evidence/preparation/top-repaired-completion-20261103T045853Z-895deeba/receipt.json`.
Its simulation command ran for approximately 2400 seconds, not the 29.98 seconds
in the wrapper exception. Its child exit is unrecorded. The final heartbeat
reports 15,564,800 cycles, 1,079,199 directory reads, 2064 payload reads and no
logits. This is incomplete execution, not a numerical mismatch. The previous
ordered-prefix repair reduced work within one lookup but did not amortize
certification across lookups.

`anvil_en1_tensor_image` now has two optional wire inputs:
`image_immutable` and `image_invalidate`. Only an explicit logic one activates
either control; an omitted input is inactive. This preserves standalone
mutable-image behavior: every lookup reads and validates the whole directory,
including the existing arbitrary-order all-prior duplicate/overlap scan.
Opting into reuse requires an immutable header, directory and payload until
the lifetime is drained and invalidated. Neither input authorizes mutation
while a response or memory transaction is outstanding.

The connected native path opts in only under the existing immutable-job input
contract. The top broadcasts invalidation on **every** accepted job, including
parent and rejected jobs. Native start acceptance invalidates again, so a
standalone native invocation has the same lifetime boundary. Session-control
acceptance at frontier, replay binding and owner replay also invalidates their
reader descendants. Lifetime controls are forwarded through the text, owner,
replay, vision and audio hierarchies, not just the first text projection.
Native memory arbitration remains read-only. There is no native write or
permitted host mutation of an active job's image; to update an image at the
same address, drain the job and submit a new one. Standalone mutable engines
need no new controls and retain their original validation behavior.

A reader retains one certificate keyed by its already registered image base,
model, precision, image class, audio selector and input-item count. A change to
any key field invalidates the certificate and every descriptor before reuse.
Reset, explicit invalidation, dropping immutable mode, and a directory error
also invalidate them. No generation-counter wrap can resurrect a certificate.
The first lookup in a lifetime still validates **all** header and directory
words before returning a descriptor, even if the requested entry was first.
All shape/type/stride/length/reserved-word/address/memory checks and the ordered
proof plus exhaustive unordered fallback are retained. Only successful complete
validation certifies the image.

The bounded lookaside has eight fully associative round-robin entries. Each
entry holds a 32-bit tensor key and a 232-bit descriptor: absolute base, bytes,
rows, columns, stride and type. Hits return those certified metadata only, never
tensor data or numerical answers. A miss in a certified image scans one key word
per entry, then rereads and validates all 16 words of the matching entry.
Unchanged immutable directory contents inherit their already completed global
duplicate/overlap certification. Arbitrary ordering remains legal. With a
matching entry at zero-based index `j`, this path reads `j+17` words; a lookaside
hit reads none. These are source-derived work bounds, not measured speedups.
Replacement changes no image or tensor contents.

| Boundary (handshakes sampled pre-edge) | Post-edge behavior |
| --- | --- |
| Active reset | Clear certificate/validity and existing public outputs; unreset descriptor payloads are inaccessible |
| Invalidation while idle | Clear all reuse state; `start_ready=0` for that cycle, with invalidation priority |
| Lookup accepted E0 | Capture descriptor and image key; select reuse only for a matching, certified immutable lifetime |
| E1 | Validate the requested tensor identity, model/precision and base alignment/overflow before cache search or memory access |
| Certified hit E2 / E3 | Register selected descriptor payload / copy into output registers |
| Hit E4 / E5 | Publish response after E4; earliest acceptance E5, never on the creating edge |
| Certified miss | Registered key scan followed by complete matching-entry validation; ordinary memory response stages are unchanged |
| No certificate | Complete original header/directory validation before any successful descriptor response |
| Lifetime revoked during work | Clear retained metadata immediately, retire any accepted read, and publish error 7 with zero descriptor instead of stale success; an existing memory/format error retains priority |
| Revocation with an already stalled done response | Invalidate retained metadata without changing that response's stable payload; drain it before mutation or another lifetime |
| New job, changed image/configuration, or permitted between-job mutation | Force full certification again, even if the numeric base address is unchanged |

Before the current staging overlay, each reader charged
**3743 bits / 468 rounded bytes**. Reconciling the
current register declarations gives 1384 bits / 173 bytes before lookaside and
lifetime additions; the earlier 1606-bit / 201-byte base census was incorrect
for this source. Added storage is 2112 descriptor bits, 232 read-register
bits, eight validity bits, a three-bit replacement cursor and four lifetime
bits: 2359 bits, or 295 additional rounded bytes per connected reader. The
current overlay removes the separate 232-bit read register, leaving 2127 added
bits / 266 added rounded bytes and 439 total rounded bytes per reader. The
charge includes invalid entries and unused payload registers, not just hits.
All parents retain their existing summed controller reports; the extra storage
therefore enters both the live/shadow ledger and physical-reservation report
through the connected controller terms. The single static production
elaboration contains 49 readers: three frontier and 46 replay-binding, adding
14,455 rounded bytes (22,932 bytes total reader state) before the overlay;
the same hierarchy now has source-derived totals of 13,034 added bytes and
21,511 total reader bytes. A literal source traversal overcounts mutually exclusive
generate alternatives (62 readers); it is not the physical census. The
subsequent wire-only control repair does not change module multiplicity or
retained storage, but final source-matched reporting remains for Verifier.
There is no descriptor RAM hidden outside those terms.

The second retained failure is
`evidence/preparation/synthesis-native-production-20261103T045127Z-a32dd679/receipt.json`:
Yosys timed out at 2400 seconds with child exit -9 while emitting 4224-bit
variable-select workspace updates among 1133 decoder outputs. This localizes
the repair, not a proved dominant cost or a Quartus resource/timing failure.
`anvil_en1_replay_workspace` now drives the existing packed metadata buses from
64 statically indexed slot banks. Each bank owns its 34-bit scalar visibility
word and six vector cells; a vector cell owns three flags and one 11-bit
next-pair index. There are no variable-select writes to the former 4224-bit
progress container or 384-bit vector containers. Scalar writes select only
within one 34-bit bank. Registered read timing and packed read views remain.

| Workspace boundary | Visibility update on the original edge |
| --- | --- |
| Reset or accepted valid session control | Clear every slot; invalid session control does not clear an existing session |
| Granted frame push / completed pop | Clear only that frame's six vector cells and 34 scalar bits |
| Continuation update / eighth successful write | Clear / set only the frame's low eight scalar validity bits |
| Granted vector reservation | Set only the selected cell's reservation; allocation arithmetic and grant acceptance are unchanged |
| Stream/pair-write start | Hide the selected incomplete vector and clear old progress, retaining its allocation |
| Nonfinal / final successful pair | Record the next pair / expose the completed vector and clear progress |
| Scalar write start / completion | Clear / set the selected scalar's visibility bit |
| Frame-to-memo or history move | Transfer the same reservation at the original commit edge; no duplicate live allocation |
| Release or failed backing write | Preserve original release accounting; failed writes hide incomplete data without granting visibility |

This changes register organization, not capacities, frame depth, eviction,
allocation grants, release arithmetic or the byte census. Workspace visibility
metadata remains `80*25+64+3*384+4224+16+32+64*34 = 9664` bits (1208 bytes);
the new enables are combinational and introduce no retained state. No parent
RTL or native production geometry is changed. Preserve also
`evidence/preparation/synthesis-workspace-declarations-20261103T044320Z-9fc6ab27/receipt.json`,
whose timeout ended in immutable-parent matvec expansion.

Independent Verifier must first rebuild bounded source-matched directory and
workspace checks, including lifetime changes at the same address, malformed
trailing/unordered entries, nonadjacent duplicates/overlaps, descriptor eviction,
stalls/reset/error retirement, vector pair visibility and allocation moves.
Then measure top progress before another completion run and recheck affected
synthesis under the existing budgets. All six mandatory suites and native
timing-lint, actual Quartus mapping/STA and board gates remain required.
No new functional, synthesis, timing or acceptance result is claimed here.

The reserved static elaboration ran once, with exact expanded argv, source
hashes, tool version and raw logs retained at
`evidence/preparation/static-image-lifetime-workspace-20261103T055106Z-0c0909f9/receipt.json`.
`iverilog -g2012 -t null -s anvil_en1_top -N <fresh-output>/elaboration.txt`
followed by all sorted native and immutable-parent RTL exited zero in 15.65
seconds and produced its hierarchy dump. The wrapper deliberately marked the
receipt **failed**, because stderr contained 262 input-to-inout coercion
warnings, all on the added pull-net lifetime controls. No simulation ran.
The repair replaces those `tri0` ports with unidirectional wire inputs and
explicit-one qualification at forwarding/reader boundaries, preserving
inactive omitted controls without propagating pull-net drivers. That later
source repair is not covered by the retained hashes or a second compilation.
The one-check allowance is exhausted; Verifier must re-elaborate the saved
sources before behavioral execution. The failed receipt is unchanged.

### Historical repair: workspace widths and bounded directory validation

The retained whole-top failure at `replay_workspace.sv:288` is in
`evidence/preparation/synthesis-declaration-repair-20261103T043019Z-8fceeaee/receipt.json`.
The existing typed declarations of `vector_bit_index`, `native_request`,
`production_text_vector_bytes`, `request_shadow_vector_bytes` and
`request_vector_bytes` now precede their first uses in that generate scope.
Their widths, expressions, accounting and arithmetic are unchanged.

The source-matched bounded top diagnostic at
`evidence/preparation/top-public-progress-20261103T043245Z-b1b56db9/receipt.json`
stopped incomplete after 2,000,000 cycles: 177755 accepted reads/responses,
177735 directory reads, no payload reads and no logits. This is not a
numerical pass or evidence of neural computation.

`tensor_image` now certifies an ordered prefix while still reading and
validating every header and complete directory entry on every lookup.
Its bijective comparison key is `{uint16(layer+1), kind}`: global layer
`0xffff` precedes layer zero without changing the external tensor ID.
If keys strictly increase and each payload begins at or after the previous
payload end, transitivity proves all prior identities distinct and all prior
payloads disjoint. The existing 160-bit `prior_entry` stores the preceding
key, offset and length in this mode. Once either condition fails, certification
is permanently disabled for that lookup and the original all-prior external
scan validates this and every remaining entry. Arbitrary directory and payload
orderings remain legal; no ordering requirement is added to the image ABI.

| Boundary | Registered behavior |
| --- | --- |
| Active reset | Clear certification and all existing public valid outputs |
| Accepted lookup | Start a new certification; never reuse an earlier image's validation |
| First fully validated entry | Store its key/offset/length at `ENTRY_FINISH` |
| Certified successor | Check all existing shape, length, reserved-word, bounds and directory-overlap rules first; advance to `ENTRY_FINISH` without redundant prior rereads |
| Non-successor | Clear certification before entering the unchanged `PAIR_START`/`PAIR_VALIDATE` scan from prior index zero |
| Duplicate or overlapping entry | Cannot pass the ordered proof; original scan rejects with error 5 |
| Memory error or stalled response | Retain registered error-2 retirement and stable response payload; issue no replacement successful result |
| Last entry and completion | Preserve `FINISH`, `PUBLISH`, `RESPONSE`; no early payload access or early successful response |

This adds one counted controller bit, from 1605 to 1606 bits per reader;
the rounded charge remains 201 bytes. No RAM, validation cache, tensor copy
or numerical shortcut is added. For a completely certified directory, the
address-level read count is `16+16*n`, instead of
`16+16*n+3*n*(n-1)`: 8656 versus 881836 reads for E2B and 10656 versus
1335336 for E4B. These are source-derived counts, not measured speedups.
Repeated lookups still validate the full directory, and unordered images
retain quadratic worst-case work. End-to-end completion within the existing
budget remains an independent verification requirement, not a claim here.

Independent Verifier must recheck whole-top synthesis, certified and unordered
valid directories, duplicate identities with disjoint payloads, nonadjacent
overlaps, reserved words and length/address faults, reset/stalls/errors, then
rebuild the source-matched bounded top progress run. No timeout or acceptance
threshold is changed. Original receipts, tests and parent sources are unchanged.

The single fast static check for these repairs passed: Icarus 12.0
`-g2012 -t null -s anvil_en1_top`, all native and immutable-parent RTL,
exit zero, empty stderr and retained hierarchy dump, 14.705 seconds,
180-second watchdog not reached. Exact expanded command, source hashes,
version, raw streams and repair provenance are retained at
`evidence/preparation/static-workspace-directory-repair-20261103T044222Z-7c18f486/receipt.json`.
RTL hashes cover the saved repairs; document hashes precede this status
annotation. No functional simulation or synthesis was run by Designer.

### Retained static diagnostics and repairs

The reserved static command ran once with Icarus 12.0:
`iverilog -g2012 -t null -s anvil_en1_top -N <fresh-output>/elaboration.txt`
followed by every `rtl/*.sv` and immutable parent `rtl/*.sv` source, in
sorted order. Its exact expanded argv, source SHA256 inventory, timestamps,
120-second limit and raw streams are retained at
`evidence/preparation/static-elaboration-20261103T032650Z/receipt.json`.
No functional simulation or synthesis ran.

This diagnostic **failed to establish elaboration**. The first error is
`rtl/anvil_en1_attention_head.sv:725: syntax error`, at `endgenerate`.
The legal `attention` generate branch lacked its closing `end` after the
sequential process. The parser then treated following module bodies as
part of that scope, producing cascading duplicate-declaration/module-item
errors. The repair adds only that missing scope closure; no arithmetic,
register, allocation expression, state encoding or protocol changes.
The original raw stderr and receipt are unmodified. In particular the
recorded compiler exit code is zero despite its emitted syntax errors,
and no elaboration dump was produced: neither that exit code nor the
wrapper's completion is a passing result.

The continuation ran one fresh bounded static command with the same
source selectors and top, retaining its exact argv, hashes, tool version,
raw streams and repair link at
`evidence/preparation/static-repair-20261103T032829Z/receipt.json`.
It exited 210 in 0.415 seconds without an elaboration dump. Its first
diagnostic is `rtl/anvil_en1_frontier.sv:425: syntax error`, followed by
cascading cross-module declarations. This is another failed static
diagnostic, not functional execution or a passing compilation.

Source inspection found the same missing legal-generate-branch closure
in both `anvil_en1_frontier` and `anvil_en1_local_ring`. Both now have the
missing `end` between their sequential process and `endgenerate`.
Separately, `anvil_en1_vision_bins` declared a RAM named `bins`, a reserved
SystemVerilog coverage keyword. That RAM and its three accesses are now
named `bin_payload`. These repairs change no storage dimensions, controller
bits, arithmetic, read/write enables or handshake timing. The previous
attention-head closure repair remains intact.

One newly authorized static elaboration of those repairs succeeded:
`evidence/preparation/static-binding-20261103T033046Z/receipt.json`.
Icarus 12.0 exited zero in 15.707 seconds, emitted no stderr diagnostics,
and produced the retained `elaboration.txt` hierarchy dump. This was
`-t null`, not functional simulation or synthesis. The 180-second
watchdog did not expire. Both preceding failed receipts and their raw
logs remain unchanged. The original receipt still hashes to
`908b15cc6ade4a0b23c771e7fdeb2cc78940f6c561ab99d039a2c5bb8858a249`.

The resolved dump exposed a separate real accounting defect: Icarus
evaluated register-dependent `$bits` inside report localparams before
the referenced registers acquired their declared widths. Among the
native/integration report parameters, 459 became zero; five became
negative (`-32` three times, `-64`, `-48`) because their external-RAM
subtractions remained. A clean elaboration therefore did not establish
correct allocation reporting.

All 95 register-dependent report-size declarations in 93 owned RTL
files now use continuously assigned 32-bit constant nets instead of
localparams. Their `$bits` operands, parameter branches, rounding and
downstream controller/metadata equations are unchanged. These values
are used only in byte reports, never array widths, generate choices,
state encodings or parameter validation. Moving evaluation to the
continuous expressions preserves declaration-derived sizing without
hardcoded substitute byte totals. It creates no clocked state. The
cache metadata report also byte-rounds the tag array and occupied bitmap
separately: `ceil(34*C/8)+ceil(C/8)`; this corrects a one-byte
undercount at capacities such as C=1 and leaves C=3/64 unchanged.
No datapath, numerical operation, ownership schedule, legal parameter
range or acceptance threshold is changed.

One fresh authorized static elaboration of the saved report repairs
succeeded with Icarus 12.0: exit zero, 15.405 seconds, no stderr
diagnostics, no timeout, and a complete hierarchy dump. Exact expanded
argv, RTL/parent/document SHA256 inventory, tool identity, timestamps,
180-second watchdog and raw streams are retained at
`evidence/preparation/static-report-sizing-20261103T033622Z/receipt.json`.
Its repair link preserves the preceding binding receipt and both earlier
failed diagnostics. The invocation used `-t null`; it ran no simulation
or synthesis. RTL hashes match the saved report repairs; document hashes
precede this diagnostic-status update.

Read-only Python inspection reconciled the 95 source report declarations
against the resolved default production hierarchy (COMPACT=0, C=3).
They appear in 471 connected instances. All 468 directly constant-driven
instances match the sums of their resolved operand widths and declared
parameter adjustments, with zero mismatches and no zero/wrapped sizes.
Three reports retain static expression nodes rather than a single
constant driver: dispatcher 1090+52=1142 bits, full allocation ledger
142*24+42=3450 bits, and prospective ledger 121*24+42=2946 bits.
The ledger node counts agree with the generated register declarations;
their byte reports are 432 and 369 respectively. This is static
declaration/expression reconciliation, not evaluation of live grants.

The design is ready for independent Verifier handoff. No further RTL
repair was required by this diagnostic. Functional behavior, numerical
agreement, actual allocation/traffic savings, compact/production coverage,
synthesis, inferred RAM resources, timing and hardware operation remain
unverified. Tests, immutable parent sources and runtime metadata were not
edited. All six mandatory suites and native hardware gates remain required.

### Resolved physical array census and backing ownership

The successful static dump resolves the default production top with
COMPACT=0 and C=3. It contains 906 module instances: 736 outside
`parent`, including the native external-memory bridge, and 170 in the
immutable compatibility subtree. The following disjoint table covers
every native payload array. Fields refer to the 25-element
`native.allocation_physical_bytes` bus; every row excludes scalar
readback registers, tags and occupied bitmaps. These are physical
declaration reservations, not live allocation peaks.

| Field | Declared array instances (paths below `native`) | Production bytes | Compact bytes |
| --- | --- | ---: | ---: |
| 0 | `frontier.frontier.frontier.payload` | 4071936 | 836096 |
| 1 | `frontier.ring.ring.payload` | 1048576 | 64 |
| 2 | `ordinary_hidden_payload` | 5120 | 16 |
| 3 | `frontier.feature_payload` | 5120 | 16 |
| 4 | `frontier.anchor.materialize.payload` | 512 | 8 |
| 6 | `binding.owner_replay.replay.raw_payload` | 5120 | 16 |
| 7 | `binding.owner_replay.replay.owner_tile.tile.head_payload` | 1024 | 16 |
| 8 | `binding.replay.text_layer.attention_branch.executor.tile.owner_tile.tile`: `head_payload`, `internal_input_ram.input_payload` | 6144 | 32 |
| 9 | `binding.replay.text_layer.ple_payload` | 512 | 8 |
| 12 | `binding.replay.vision_layer.attention.executor.tile`: `input_payload`, `head_payload`; `binding.replay.vision_layer.post`: `raw_payload`, `mlp_payload` | 4736 | 4736 |
| 13 | `binding.replay.audio_input.immutable_input.stage_{zero,one}.point.convolved`; `binding.replay.audio_layer.histories.fold.gated_input.local_vector.normalized`; `binding.replay.audio_layer.histories.residual.heads.attention.normalized`; its `pre_attention.shared_vectors[0..2].payload`; `binding.replay.audio_layer.histories.residual.post_attention`: `heads`, `normalized_source`, `working`; `binding.replay.native_vectors[0..2].payload` | 23040 | 23040 |
| 14 | `binding.replay.audio_feature.feature.projected`, its `modality.normalized` | 6144 | 6144 |
| 15 | `binding.replay.image_feature.feature.feature.pooled`, its `projection.normalized`; `binding.replay.image_feature.feature.mapping.bin_payload` | 6432 | 6432 |
| 18 | `cache.cache.payload` at C=3 | 12 | 12 |
| 20 | `frontier.text_layer.engine.full_attention_payload.payload`; `text_banks[0..3].payload` | 20992 | 72 |
| **Total** | **38 payload array instances** | **5205420** | **876708** |

Production columns follow the resolved declarations; compact columns
are derived from their explicit COMPACT branches, not a second
elaboration. Native encoder dimensions and the shared native-vector
banks do not compact. Both model selections share the same physical
reservations; only occupied lengths and production shadows differ.
For other C, replace the resident row with `4*C`.

The five remaining native arrays are metadata: frontier `layer_tags`
(640/320 bytes), ring `token_tags` (512/8), replay workspace
`frame_tags` (200/200) and `memo_tags` (50/50), and cache `tags`
(`ceil(34*C/8)`, 13 bytes at C=3). Their production/compact subtotals
are 1415/591 bytes at C=3. Separately declared occupied vectors remain
in the existing metadata reports: frontier 128/64 bytes, ring 256/1,
resident `ceil(C/8)`, and the replay visibility vectors. They are not
silently treated as RAM payload or omitted controller state.

Thus all 43 native arrays reserve 5206835 production bytes at C=3.
The two `performance` arrays, `counters` and `snapshots`, add 464
bytes each and are already included in the CSR controller report
within integration, not in native payload. These 45 non-parent arrays
total 5207763 separately rounded bytes. The parent subtree has 58
arrays totaling 451008 bytes; they remain disclosed physical
compatibility storage, not native live cache savings. Scalar registers,
combinational declarations and tool-generated nets are not included in
these array-only totals. No M20K block count is inferred from them.

The backing has one physical owner: field 0. Field 5 reports live
frame/memo/scalar allocations mapped into that owner's RAM and reports
zero additional physical payload. Its `workspace_reserved_bytes`
describes that mapped subrange, not a second array. Production replay
word ranges are frames `[0,196607]`, memo `[196608,229375]`, scalars
`[229376,231551]`; compact uses the same frames, memo
`[196608,204799]`, scalars `[204800,206975]`. Each scalar slot is 34
words. The ordinary mapping adds 786432/2048 words and ends exactly
at the physical frontier array's final word; the fallback mapping
adds zero only after ordinary frontier/ring invalidation.

The native shared banks are physically charged in field 13 even when
vision borrows bank 0. The four text banks are charged once in field 20
even when replay or embedding borrows them. Fields 10, 11, 19 and 21
have no private connected payload arrays under the current external-RAM
parameters. This physical attribution does not replace the per-phase
live reports: each borrower must hold its actual grant, and sharing
must never conceal a simultaneous allocation. The retained shadow and
liveness bounds below still require independent execution.

The scalar declaration audit found the report operands cover sequential
state except explicit generated readback banks and metadata. Generated
readback widths are already charged by the existing conditional
16/32/48/64-bit terms or their aliased read-data operands; allocation
ledger reduction registers use `registered_nodes()*NODE_BITS`.
`tensor_shape` and the public descriptor/checkpoint packing outputs
are combinational, not additional retained storage. This audit is
source/declaration reconciliation, not proof of no latches, actual
grant success, numerical behavior or timing. In particular the
continuous report-sizing implementation now has the static binding and
declaration-width reconciliation recorded above; its live behavior still
requires independent verification.

### Scoped physical declaration reconciliation after the parse repair

The following source-level paths start below `anvil_en1_top`. They are
literal connected instances, not resolved-hierarchy or inferred-M20K
measurements. Byte-round each metadata array separately.

| Instance / declaration | Production bytes | COMPACT=1 bytes | Accounting surface |
| --- | ---: | ---: | --- |
| `native.frontier.frontier.frontier.payload` | 4071936 | 836096 | `physical_payload_bytes`; includes ordinary frontier and phase-remapped replay backing, not two copies |
| Same instance, `layer_tags` | 640 | 320 | `token_metadata_bytes` |
| Same instance, `occupied` | 128 | 64 | Remainder of `token_metadata_bytes`; excluded from `controller_bytes` |
| `native.frontier.ring.ring.payload` | 1048576 | 64 | `physical_payload_bytes`; both models share the production maximum reservation |
| Same instance, `token_tags` | 512 | 8 | First separately rounded term of `token_metadata_bytes` |
| Same instance, `occupied` | 256 | 1 | Second separately rounded term of `token_metadata_bytes`; excluded from `controller_bytes` |
| `native.binding.replay.image_feature.feature.mapping.bin_payload` | 1824 | 1824 | `mask_physical_bytes`; native vision stays uncompacted |

Thus the scoped payload subtotal is 5122336/837984 bytes and its frontier/
ring metadata subtotal is 1536/393 bytes for production/compact. These
are reserved physical declarations, not simultaneously live payload.
Each RAM's registered read data is included in its existing controller
expression, not charged again as RAM depth. The frontier physical depth
is `1017984/209024` 32-bit words. Its production backing range ends at
word `786432+231552-1=1017983`, exactly the last declared word; compact
ends at `2048+206976-1=209023`. Fallback remaps that backing to zero only
after ordinary invalidation; the physical declaration does not shrink.
The ring is `512*4*128` production words or `4*2*2` compact words.
The vision bitmap remains 456 words; renaming its identifier removes no
storage and changes no controller report.

This retires the declaration-size/report correspondence for these seven
source declarations only. Per-instance whole-hierarchy declaration and
physical-backing reconciliation remains incomplete because no resolved
hierarchy was obtained. The source-level liveness analysis below is not
invalidated by the scope/name repairs, but is still not measured evidence.

### Current closure: reachable replay storage, including small contexts

The full-depth `61*12288` frame estimate below is a partition bound, not a
reachable simultaneous-payload estimate. In particular it must not be used
to reject a small-context forced fallback. The connected scheduler and text
worker give the following tighter bound without assuming a memo hit:

1. A text frame awaiting its initial predecessor has not filled either
   vector bank. `replay_text_layer.BIND_WAIT` yields the predecessor before
   the attention private grant. Such a frame still owns its complete
   136-byte scalar slot.
2. After that binding, a text frame can retain its two H-wide banks while
   yielding an owner-input request or a native-feature request. An
   owner-input request descends to an actual nonshared owner, not to the
   shared consumer's logical layer. All subsequent vector-retaining text
   ancestors on that dependency chain have strictly decreasing owner
   layers. There can therefore be at most one upper shared consumer, O
   nonshared positive-layer frames, and the layer-zero input frame. Use
   the conservative bound `2*(O+2)*H_bytes` for their combined vectors:
   O is 15/24 and H_bytes is 3072/5120 for E2B/E4B. This even charges two
   vectors to layer zero. It does not erase the empty ancestors' scalars.
3. Native dependencies cannot reenter text. Once a text frame yields a
   feature, the native subtree has exactly one feature ancestor and a
   strictly decreasing vision/audio layer chain. The four encoder cuts
   recorded below include its native controllers, suspended and active
   native vectors, all scalar slots, private worker storage, pooled
   image state and the protected predecessor. Their largest necessary
   subtotal is 85229 bytes, below 86016. Unpinned memo entries are treated
   separately, not assumed absent from a live observation.
4. Outside encoder descent, a deliberately overlapping feature/embedding
   envelope is `26085 + 2*5120 + 5120 + 6432 + 5632 + 512 + 5120 +
   3*136 = 59549` bytes. Its terms are native controllers, both feature
   frame banks, an outer feature destination, the largest feature worker,
   one H/PLE embedding workspace, the separately retained PLE, one
   protected H-wide memo and three scalar slots. Some terms are mutually
   exclusive in RTL; keeping them all only enlarges the bound. This
   covers the original-input embedding and resumed higher-layer PLE
   phases as well as native feature output. During encoder descent the
   empty outer feature destination is absent by the first-output grant
   rule, not by an accounting exemption.

The following source-derived fallback envelope intentionally double-counts
some mutually exclusive storage to give a simple uniform bound. Unlike a
necessary-working-set cut, it includes **all sixteen** resident memo vectors,
even though the native subtotal already includes its protected memo. It is
valid for actual and production-shadow allocations; native widths remain
uncompacted and all compact text vectors are no larger than their shadows.

| Nonoverlapping allocation class before conservative enlargement | Uniform bound |
| --- | --- |
| Non-native controllers, visibility metadata and integration | 15862 bytes |
| Native controllers, native frames/scalars, active native worker and protected native source | 86016 bytes |
| All text/native scalar slots, counted again conservatively | `61*136 = 8296` bytes |
| All memo payloads, including native memos again conservatively | `16*H_bytes` |
| Text frame vector banks, including partially written/reserved banks | `2*(O+2)*H_bytes` |
| Active text private work, including separately retained PLE | `3*H_bytes+1024` |
| Outer frontier/owner source, head tile and retained PLE envelope | `2*H_bytes+2048` |
| All resident KV words at C=64 | 256 bytes |

This gives 282462 bytes for E2B and 487262 for E4B. Their respective
minimum padded matched baselines are 688128 and 1605632 bytes, so
`20*282462 < 9*688128` and `20*487262 < 9*1605632`. The baseline formulas
are nondecreasing for every legal context and these envelope numerators do
not grow with token count. Thus small-context forced fallback does not need
the first-production-fallback baseline to meet the strict ratio. The linear
single-token scheduler remains implemented and reduces work; this bound
does not depend on replacing the real multi-token evaluator with that path.
Both envelopes are also below the complete 1 MiB fallback ceiling.

This total bound is distinct from the 64 KiB fallback working partition:
frame/scalar/memo payloads belong to field 5, while the connected working
envelope remains 58587 bytes. It is also distinct from ordinary M: ordinary
execution invokes this scheduler only for native feature reconstruction;
it has no suspended text replay stack or surviving text memo. Its necessary
native cuts are at most 85229/59549 bytes, below the minimum E2B allowance
86016, and the grant FSM can evict unpinned entries before retrying. The
ordinary non-native text bounds remain 30710/38902 bytes. This is a finite
source-level feasibility argument, not permission to accept error 7 for a
legal job, nor an observed allocation or resource/timing result. Verifier
must observe every actual/shadow grant, eviction, transition and peak,
including empty scalar-only ancestors and the real two-token and 17-token
fallback cases.

Read-only Python integer arithmetic recomputed the four encoder cuts and
the E2B/E4B bounds from these expressions. It executed no HDL, wrote no
evidence, and did not calculate expected DUT numerical outputs. Physical
declaration/backing reconciliation and a successful independently executed
or newly authorized static elaboration remain outstanding; the reserved
attempt and its failure are recorded above.

### Current increment: replay-result lifetime and connected partition census

The frontier fallback result and fallback owner-source result now follow the
same demand-grant rule as the ordinary native-feature destination. Do not
reserve an empty destination while its evaluator descends. This applies to
the connected fallback path, not just a leaf accounting output.

| Pre-edge boundary | Registered ownership / action |
| --- | --- |
| Frontier has drained/inactivated ordinary frontier and ring and bound replay backing | Start the actual evaluator without a component-2 destination reservation or hidden allocation |
| Fallback owner request passes validation | Start its actual owner-input evaluator without a component-6 raw-source reservation |
| First real result becomes valid | Leave output ready low; enter the existing allocation request/wait states for the complete destination |
| Grant succeeds | Register the reservation, return to the result-wait state, then permit the first data handshake on a later edge |
| Accepted frontier result beat | Only a handshake may write hidden RAM or advance the count; establish hidden allocation at the first accepted beat |
| Accepted owner result beat | Preserve the existing ordered-index/last checks, actual RAM write, count and full-vector commit |
| Error completion before any output | Consume the actual completion without allocating a destination; preserve the concrete evaluator error |
| First-output grant denied | Preserve error 7; accept/discard all remaining result beats without RAM writes, counts or successful commit, then consume actual evaluator completion before returning failure |
| Result stall / grant stall | The evaluator retains its valid payload; neither consumer fabricates data or acknowledges an ungranted beat |
| Reset | Disable readiness, memory enables and validity through the existing asynchronous control resets; invalidate unfilled payload |

`frontier_execute.EVAL_OUTPUT_DRAIN` and `owner_replay.EVAL_DRAIN` use unused
encodings in the existing six-/five-bit controllers. No destination RAM,
holding vector, scalar register or controller-byte reduction is introduced.
The ordinary owner's component-6 grant remains before owner-tile execution:
that bank is required for its normalized source even though its raw input
comes from the preserved frontier. Ring-hit behavior is unchanged.

The result lifetime follows the connected scheduler, not a prediction about
when replay ought to finish: `eval_schedule` copies a completed result to
memo, pops its frame, walks `AFTER_POP` until the root is complete, and only
then enters `OUTPUT_SETUP`/`OUTPUT_LOW`. Hence every suspended frame and
active worker has retired before a real root output triggers either new
destination grant. Output still reads the actual completed memo. Memo and
its readback/pair registers remain charged until the existing invalidate and
response retirement. A full destination is conservatively reserved throughout
output; no disappearing-prefix accounting is used.

The following reconciles current nonoverlapping report expressions at
production geometry and connected external-vector settings. Primitive
external-FP reports exclude only their absent local FP32 service; the owning
service remains counted. All values are per-instance byte-rounded source
counts, **not elaborated, simulated or synthesized measurements**.

| Connected report | Bytes |
| --- | ---: |
| Norm / projection / rotary, each with external FP | 135 / 173 / 296 |
| Ordinary full text / replay post-only text | 2014 / 1320 |
| Embedding / final logits | 841 / 960 |
| Owner tile / complete owner replay | 1074 / 1151 |
| Replay original input, including its embedding | 936 |
| Replay text worker and all separately reported text descendants, including original input | 5398 |
| Complete replay executor, including scheduler, dispatcher, workspace controller and native descendants | 31121 |
| Binding reported subtree, field 22 | 32290 |
| Native-reconstruction subset of field 22, counted once in M | 26085 |
| Ordinary frontier executor, field 24 | 4140 |
| Binding own / native assembly own, fields 16 / 17 | 139 / 162 |
| Scheduler + memory arbiter + cache + prospective admission, field 23, C=64 | 501 |
| Top own + memory bridge + CSR + observation ledger + guard | 1690 |
| Frontier / ring / replay visibility metadata | 768 / 768 / 1208 |
| Resident metadata, C=64 | 280 |

Both ledger counts must use the current mode-conditioned fallback leaves:
observation has 142 retained nodes including outputs, admission 121. With
24 bits per node and 42 tag/error bits, their reports are 432 and 369
bytes. Admission adds its own 35 bytes; top integration includes observation
only. The older 408/345-byte ledger figures predate the fallback split.
Replay metadata is `80*25+64+3*384+4224+16+32+64*34 = 9664` bits,
or 1208 bytes; the older 1192-byte figure is not the current expression.
These corrections increase, rather than hide, their respective charges.

At C=64 the fixed non-native workspace subtotal, including all metadata and
integration, is 15861 bytes. It is
`(32290-26085)+4140+139+162+501+1690+768+768+1208+280`.
Use the conservative 15862-byte envelope for both compact actual and
production-shadow analysis: the compact ring can add one rounded controller
byte, while other connected compact declarations do not grow. Smaller C
does not enlarge either resident metadata or its fixed-width controller.

| Necessary phase envelope, excluding evictable memo payload | Conservative bytes / derivation |
| --- | --- |
| Ordinary E2B text with global owner miss | `15862+7168+3584+3072+1024 = 30710`, below 32768 |
| Ordinary E4B equivalent | `15862+11264+5632+5120+1024 = 38902`, below 65536 |
| Fallback fixed working state, including native controllers and all 64 resident words | `15862+26085+256 = 42203` |
| Fallback replay post maximum, either model | `42203+(3*5120+512)+512 = 58587`, below 65536 |
| Fallback active native feature maximum | `42203+6432 = 48635` |
| Fallback root output / subsequent owner tile | `42203+5120+1024 = 48347` |

The post bound counts its independently retained PLE in addition to the
worker's full three-vector/PLE reservation; it does not assume that those
copies alias. The new demand grants remove the otherwise concurrent empty
5120-byte outer result from that phase. Native encoder frame vectors,
scalar continuations and memo payload remain in field 5, not in this
fallback working subtotal. Ordinary owner misses use the frontier/ring,
not the fallback evaluator, so their source and head tile are explicitly
included in the ordinary rows. Ordinary feature evaluators have no text
ancestor frames; their native frames/memos remain part of M.

The strictly decreasing scheduler rank is at most 61 (E4B text layer 42).
Consequently at most 61 live frames, each at most 12288 vector bytes, occupy
749568 bytes, below the 786432-byte frame partition. Their complete scalar
slots require at most `61*136=8296` bytes, below 65536. Sixteen memo vectors
need at most `16*5120=81920` live bytes, below 131072. Including the
58587-byte working envelope gives a coarse full-depth fallback upper bound
of 898371 bytes, below 1 MiB. This bound does not certify the strict savings
ratio for arbitrary test-forced fallback at minimum contexts: the linear
single-token path and the actual reachable partially allocated text/native
stack must be reconciled against their smaller baseline as well.

The backing layout remains 786432 frame bytes, 131072 reserved memo bytes
and 8704 scalar bytes, totaling 926208 bytes. Ordinary execution maps this
store after the 3 MiB frontier; fallback maps it at zero only after ordinary
payload invalidation and replay binding. The physical frontier array still
reserves 4071936 bytes. Do not claim that idle physical RAM, separate worker
banks, or the local ring disappeared from FPGA resource cost.

This closes the empty replay-result lifetime obstruction and supersedes the
old connected text/controller census. It is not complete capacity or hardware
acceptance. Remaining design work is a complete reachable small-context
fallback/shadow ledger (including native input/feature and restored text
continuations), per-instance declaration/physical-backing reconciliation,
then the reserved fast static elaboration and independent Verifier handoff.
Unpinned memo eviction and all legal-work allocation grants still need actual
independent observation; no denied legal request is authorized.

Independent verification must cover both changed consumers, both models and
precisions, real replay/memo misses, stalled first output through the grant,
no pre-grant RAM write/count/allocation, exactly one destination grant,
ordered complete output and commit, pre-output memory failure, denied-grant
draining, reset on each stalled channel and the following usable session.
Native numerical rules, public interfaces, six mandatory commands and
allocation/traffic thresholds are unchanged.

Saved `rtl/anvil_en1_frontier_execute.sv`,
`rtl/anvil_en1_owner_replay.sv` and both design documents. Used view, rg,
glob, apply_patch and read-only Python source-expression arithmetic. Early
read-only census expressions were corrected to exclude initialized-wire
expression commas and to normalize whitespace; none ran HDL or produced
acceptance evidence. No static elaboration, simulation, synthesis,
preparation harness or receipt ran. Tests, parent sources, runtime metadata
and retained failures remain untouched.

### Prior increment: bounded readers and demand-granted feature output

Native normalization reads its schema-fixed BF16 scale vector
with a dedicated registered word-read FSM, not the general matrix/Q4 reader.
This specialization applies in both weight precisions: native normalization
scales remain BF16 in the tensor-image ABI.

| Scale boundary | Frozen behavior |
| --- | --- |
| Directory completion | Require one BF16 row of exactly the accepted vector length, aligned base, stride and byte length equal to twice that length, and no 64-bit end-address overflow |
| Scale request acceptance | Register the full 32-bit component index; clear the preceding scale/error |
| Address stage | Reject an index outside the validated vector before issuing memory; otherwise register `base + 4*(index >> 1)` with overflow checking |
| Word request stall | Hold the registered aligned address and read-valid until acceptance |
| Word response acceptance | Register the selected little-endian BF16 lane and error; canonicalize every BF16 NaN to `0x7fc0`, preserving other bits including signed zero/subnormals/infinities |
| Following edge | Register response availability; do not consume a newly created response on its creation edge |
| Error | Return error 2 for an accepted failed read or 5 for invalid addressing, and let the existing normalization drain/complete path retire it |
| Reset | Existing asynchronous validity reset and zero public outputs; no scale result survives reset |

No scale response comes from the Q4 decoder or an FP operation. The
normalization's own arithmetic, reduction order, epsilon and materialization
boundaries remain unchanged. The source-derived size reconciliation and
whole-system liveness analysis below are not replaced by this local change.

The tensor-image and general weight readers also serialize their exact
unsigned row/stride extent products. A registered 16x16 partial product is
followed by a separate registered 64-bit accumulation. Tensor-image traversal
uses four partial products for `rows*stride`. General weight traversal uses
four for `row*stride`, then four for `rows*stride`, retaining both completed
64-bit results until descriptor validation. These are address calculations,
not FP reductions. No descriptor validation, overflow/range test, byte
transfer or BF16/Q4 decoding boundary is omitted.

| Product stage | Registered action |
| --- | --- |
| Setup | Clear completed product(s), set partial index zero |
| Capture | Multiply the selected 16-bit halves into the one 32-bit product register |
| Accumulate | Add its exact zero-extended, 0/16/32-bit-shifted value into the selected 64-bit result |
| Nonfinal partial | Increment the bounded index and return to capture |
| Final partial | Advance to the existing descriptor validation on the following edge |
| Reset | Clear index, partial product and completed products with the existing controller reset |

The ordinary frontier executor's native-feature destination is demand-granted.
Starting a feature evaluation does not reserve its model-width destination.
`FEATURE_WAIT` keeps `eval_output_ready=0` until the existing component-3
grant succeeds. On the first real `eval_output_valid`, it requests that grant,
holding the producer's output stalled through the existing allocation FSM.
Only after the registered successful grant may the first output handshake,
RAM write or received-count update occur. All subsequent feature beats retain
the same reservation until the existing embedding-consumption release.
An error before the first output needs no destination allocation. If that
first-output grant fails, retain error 7 and enter `FEATURE_DRAIN`: accept
and discard the already started evaluator's remaining output without RAM
writes or successful counts, retire its actual done response, then publish
the failure. Do not leave a stalled root evaluator blocking session drain.
Reset, error retirement and stalled-payload stability remain unchanged.
No new output bank, hidden buffer or controller register is introduced;
physical feature RAM is still disclosed at its full original extent.

The three changed reader declarations reconcile as follows. Byte rounding
is per instance before summing child reports; the FP primitive is external
in the removed normalization scale reader.

| Local report | Previous bits / bytes | Current bits / bytes | Reduction |
| --- | ---: | ---: | ---: |
| General weight reader, excluding separately reported FP | 1335 / 167 | 858 / 108 | 59 bytes |
| Tensor-image reader | 1605 / 201 | 1383 / 173 | 28 bytes |
| Native norm own controller | 389 / 49 | 325 / 41 | 8 bytes |
| Native norm's removed BF16-only use of general weight reader | 1335 / 167 | absent | 167 bytes |

Thus a native norm saves 175 bytes apart from the separately counted
28-byte directory reduction. Literal connected-reader traversal, excluding
the absent packed-post FF1 and supplied-depthwise subtrees, gives:

| Native report subtree | Native norm instances | Remaining directory instances | Remaining general weight readers | New reported bytes |
| --- | ---: | ---: | ---: | ---: |
| Original-input reconstruction | 0 | 1 | 2 | 936 |
| Vision replay | 1 | 8 | 7 | 5545 |
| Audio input/layer nested controllers | 9 | 25 | 14 | 15414 |
| Audio feature nested controllers | 0 | 3 | 3 | 1796 |
| Image feature nested controllers | 0 | 4 | 1 | 1998 |
| Unchanged audio-input/audio-layer/audio-feature/image-feature wrappers and native read/ownership state | 0 | 0 | 0 | 396 |
| Total | 10 | 41 | 27 | 26085 |

The previous 30576-byte report is superseded by
`30576 - 10*175 - 41*28 - 27*59 = 26085` bytes. The frontier executor
uses the same registers and report after demand-grant scheduling.
These are source-expression counts, not HDL elaboration, declaration-
coverage certification, measured allocations or synthesized resource use.

The following finite encoder cuts include active final binding, the protected
memo and an outer feature continuation. They bound the necessary working set
**after evicting unpinned memo entries**, not the peak including whatever
evictable entries still fit. The existing grant/eviction FSM must still be
observed independently. Every frame, including a frame with no vector yet,
is charged its full 136-byte scalar slot.

| Encoder cut | Conservative necessary native bytes |
| --- | ---: |
| Positive audio layer: 11 suspended frames at `4096+136`, active frame at `6144+136`, 4096 private bytes, one 2048-byte source memo and one 136-byte feature continuation, plus controllers | 85197 |
| Audio layer zero: 12 suspended frames at `4096+136`, active `2048+136`, 512 private bytes, one 2048-byte memo and one 136-byte feature continuation, plus controllers | 81749 |
| Positive vision layer: 15 suspended frames at `3072+136`, active `3072+136`, 4608 private bytes, one 1536-byte memo, one 136-byte feature continuation and its retained 1536-byte pooled vector, plus controllers | 85229 |
| Vision patch input: 16 suspended frames at `3072+136`, active `1536+136`, one 1536-byte memo, one 136-byte feature continuation and its retained 1536-byte pooled vector, plus controllers | 82293 |

Audio suspension retains at most the partial head slice and partial folded
output slice; the additional raw FF1 slice is allocated only after its
final predecessor binding succeeds, when that worker can no longer yield.
Its full active slice is charged in the first cut, not silently omitted.
Lower-layer chains cannot raise the number of positive layers above twelve:
their successor stops below the suspended consumer's layer. The corresponding
vision depth is sixteen. Vision pool source misses retain the partial pooled
vector, but modality projection has not started yet; its output vector is
not simultaneously allocated. Audio feature mapping yields before starting
its native output/projection child, so it retains no such vector.

Only the currently dispatched worker can pin a predecessor; a yielding task
clears that pin before descending. Existing frame-to-memo consuming transfers
charge their source suffix, destination prefix and separately reported pair
registers without discarding live data. The ordinary frontier's output-feature
bank is now unreserved throughout these cuts. Before this scheduling repair,
its E2B 3072-byte destination made even the revised vision cut
`85229+3072=88301`, above the 86016-byte minimum native allowance. It is
removed from that cut by the actual first-output grant, not by relabeling it.
At the later outer grant, the feature root has finished and popped: its
6144-byte audio or 6432-byte image private reservation has retired, exceeding
the newly needed 3072/5120-byte destination in either model. No encoder
descent or new memo allocation occurs between root completion and that grant.
Physical backing remains reserved and separately disclosed.

The minimum native allowances are 86016 bytes (E2B) and 200704 bytes (E4B);
they are nondecreasing with padded context. The largest listed necessary
encoder set leaves 787 bytes at E2B's minimum. This retires the previous
coarse encoder-depth/outer-destination obstruction, not whole-product
storage acceptance. Whole-system ordinary text grants, fallback partitions,
remaining feature/embedding phases, declaration coverage and physical backing
still need a complete joint reconciliation. In particular these cuts cannot
certify a legal global grant if another partition fails. Do not lower any
ledger threshold or accept an allocation error for legal work.

Independent verification must cover both external/internal-FP norm settings;
all legal native norm kinds/lengths and both precisions; BF16 signed zeros,
subnormals, infinities and all NaN classes; adjacent low/high word lanes and
the last vector component; scale/address/read errors, stalls and reset.
Exercise all eight/four partial-product positions, high halves, carry
propagation, malformed extents and overflowing descriptors without offending
accesses. For outer features, require no destination allocation or RAM write
while encoders descend, a held real first output through the grant, exactly
one grant before its first acceptance, and the unchanged complete output and
embedding-release protocol. Deny the first-output grant and require no writes,
full evaluator retirement, preserved error 7 and a usable following session.
Observe actual pinned memo lifetimes, retained
pool vectors, final-binding slices and native production shadows.

Saved four RTL files (`native_norm`, `weight_read`, `tensor_image`,
`frontier_execute`) and both design documents. Used view/rg/glob/apply_patch
and read-only Python source-count/arithmetic inspection. One patch initially
failed to match the weight reader's additional setup assignments; the exact
source was reread and those assignments preserved in the applied repair.
No HDL execution, simulation/synthesis harness, preparation receipt or reserved
static elaboration. Tests, parent sources, runtime metadata and retained failures
remain untouched. This is a partial design increment, not a ready handoff.

### Prior increment: native MLP class specialization and controller reconciliation

Freeze `native_mlp_row.IMAGE_CLASS`: 0 retains the original mixed native
worker, 1 permits only vision mode 0, and 2 permits only audio modes 1/2.
Other parameter values receive an explicit parameter diagnostic. A job
whose mode conflicts with the specialization returns error 6 during
descriptor validation, before source or weight accesses. Production
`vision_post_layer` selects 1; `audio_feedforward` selects 2 for both FF1
and FF2. Model, precision, tensor IDs, clipping and BF16 boundaries are
unchanged.

The audio specialization elaborates away the unused GeGLU subtree, not
its required SiLU. Vision elaborates away the separate audio SiLU subtree,
not the GELU inside its real GeGLU. Each absent branch drives its command
and arithmetic-valid/readiness/accounting outputs to zero; it supplies no
manufactured completion. Both original numerical paths remain in the
default mixed specialization.

| Pre-edge boundary | Registered action / ownership |
| --- | --- |
| Accepted start | Capture mode, model, precision and the existing descriptor |
| Descriptor validation | Reject class/mode mismatch before either projection starts |
| Audio gate projection completes | Execute the original SiLU and BF16 narrowing; no up projection or GeGLU start |
| Vision gate projection completes | Execute the original up projection and GeGLU; no separate SiLU start |
| Arithmetic response / output stall | Preserve the existing registered capture, consumer ownership and held completion |
| Error / reset | Retain existing error draining, reset validity and zero-output behavior |

Reconcile the preceding shared-FF1 increment using the literal declared
report expressions, with production geometry and connected external-RAM/
external-FP settings:

| Removed supplied-raw post term | Bytes |
| --- | ---: |
| Callback FF1 own controller including its private FP primitive | 133 |
| FF1 native norm including directory, external-FP norm, conversion, div/sqrt and scale reader | 552 |
| FF1 output clamp | 10 |
| MLP row including its original GeGLU and SiLU descendants | 350 |
| Down projection / clamp | 514 / 10 |
| Inner projection / clamp | 514 / 10 |
| Complete absent FF1 subtree | 2193 |
| Absent raw RAM read register in post controller | 2 |

The three captured mode bits added in that increment do not cross their
local rounded-byte boundaries: preprocessor 353->354 bits remains 45
bytes, replay-attention 1765->1766 remains 221 bytes, and replay-heads
962->963 remains 121 bytes. Thus the previous 33243-byte report becomes
`33243-2193-2 = 31048`, before the current class specialization.

External-FP activation reports 51 local bytes, 28 exponential-controller
bytes and 63 div/sqrt bytes, or 142 bytes. External-FP GeGLU adds 23 local
bytes around that activation, or 165 bytes. Two connected audio MLPs omit
165 bytes each; the vision MLP omits 142 bytes. Their wrapper register
widths are unchanged. The resulting nonoverlapping native report is:

| Term in `native_reconstruction_controller_bytes` | Bytes |
| --- | ---: |
| Original-input reconstruction and embedding descendants | 1082 |
| Vision replay and reported descendants | 6357 |
| Audio input wrapper | 48 |
| Audio layer wrapper | 119 |
| Audio input/layer nested controllers | 18515 |
| Audio feature wrapper / nested controllers | 101 / 2057 |
| Image feature wrapper / nested controllers | 121 / 2169 |
| Native vector ownership/read state | 7 |
| Complete declared report | 30576 |

This is source-expression accounting, not elaboration, declaration
coverage, observed liveness, synthesis or FPGA resource measurement.
Physical RAM extents and suspended frame allocations are unchanged.
Unused physical controller capacity is not advertised as removed SRAM.
The source-reading arithmetic helper initially failed to resolve widths
and multiline sums; only the subsequently resolved literal sums and
manually traced child-report additions support the table. No HDL probe,
functional/synthesis harness or preparation receipt was produced.

Capacity remains unresolved. Even the incomplete comparison
`30576+4096+12*(4096+136) = 85456` leaves only 560 bytes of minimum-context
E2B's 86016-byte native allowance, before protected dependency memo,
active final-binding extra slice and outer native continuation charges.
It is not a fit certificate. At most twelve positive audio layers is a
depth bound, not permission to assume six live frames. A complete bound
must distinguish the twelve-suspended/layer-zero case from positive-layer
execution, include the final-binding peak and source memo, and reconcile
all native/text/fallback partitions and physical reservations. Do not
change the ledger's limits or accept error 7 for legal work.

Independent verification must cover all three settings, explicit illegal
parameters and class/mode mismatch before accesses; both audio modes,
both precisions and unchanged vision/audio numerical results; reset,
stalls, source/weight errors, exact surviving tensor traffic and summed
controller/vector/shadow allocations. Class specialization is not
verification or timing acceptance.

### Prior increment: shared final audio FF1 reconstruction

The packed history residual needs the first feed-forward result twice:
normalized for Q/K/V reconstruction, and unnormalized for its
post-attention residual. Previously these paths instantiated separate
FF1 engines. Reuse the existing numerical-head preprocessor after all
eight attention heads have committed, instead of retaining a second
FF1 arithmetic/controller subtree.

`audio_pre_attention.raw_only` is captured at start. Zero preserves the
raw-then-normalized output protocol. One streams the same actual FF1
BF16 outputs, validates all 1024 indices/last bits, then completes without
the subsequent clamp-copy/attention-input normalization passes. It is
not a normalization bypass for Q/K/V: their reconstruction always uses
zero. The omitted operations were never part of the unnormalized FF1
residual in the replaced frame-backed post engine.

`replay_audio_attention.raw_only` is likewise registered. Its raw-only
job invokes that existing preprocessor at the requested query token,
forwards each accepted raw output with backpressure, then checks the
real child completion. It neither starts the numerical attention engine
nor reports a checkpoint yield. Raw-only plus numerical resume rejects
with error 7. The default numerical path and its checkpoint format remain.

`replay_audio_heads.FINAL_FEEDFORWARD` defaults to zero and requires
`DEFER_QUERY_BINDING=1` when enabled. The packed history residual enables
it. Final binding first requires the real pinned memo for the current
query input. If another token is pinned, yield the existing fully tagged
`0x454e3150` continuation before starting any FF1 work or allocating raw
output. Resumption repeats the full model/generation/layer/slot/token
checks. Once the query memo is available, run raw-only FF1 reconstruction
and write its 1024 real BF16 components to bank 0/slice 0 in ascending
aligned pairs. Partial-head outputs in bank 0/slice 1 and partial
depthwise outputs in bank 1/slice 0 remain live and charged. No private
copy of the query input is made. The scheduler's existing single-memo
pin remains asserted throughout this worker; no dependency switch or
recursive yield occurs during raw-only FF1.

`audio_attention_residual.PRECOMPUTED_RAW`, default zero, requires
`FRAME_HEADS=1`. At one, elaborate away the duplicate FF1 subtree, its
private working/branch RAM and the post engine's raw residual RAM.
After descriptor validation, compute the original attention output
projection/clamp/norm. For each normalized output, read the matching
real FF1 residual through the existing kind-0 source callback before the
unchanged FP32 residual add and BF16 narrow. Source kind 1 still reads
the actual attention heads. A failed residual callback is registered,
stops further raw requests and drains the already running normalization
before failure completion; it does not leave a child outstanding.

The packed residual wrapper permits kind-0 reads only at its current
output cursor, including cursors 1..1023. Head reads remain legal only
before output begins. Both raw components are consumed before their
aligned output pair overwrites bank 0/slice 0; the next component cannot
be requested until that pair's write response retires. The nonpacked
default retains its original eager source restriction.

| Pre-edge boundary | Registered action / lifetime |
| --- | --- |
| Numerical preprocessing start, `raw_only=0` | Original FF1 raw, clamp-copy and normalized streams |
| Final binding with wrong/missing query memo | Yield tagged dependency; no FF1/raw-output allocation |
| Final binding with valid query memo | Capture raw-only descriptor; retain the pin until worker completion |
| Raw-only output stalled | Child output/index/data/last remain held; neither wrapper advances its received count |
| Raw-only pair write | Store bank 0/slice 0; await the real workspace response before further output |
| Raw-only completion | Require exactly 1024 outputs, no unmatched half, no yield and successful child completion |
| Supplied-raw post start | No FF1 or local raw bank; reserve only the 2048-byte projection working vector |
| Post residual component | Request kind 0 at the exact output cursor; register source response before FP add |
| Post residual error | Drain normalization, retain failure, emit no successful completion |
| Reset / invalidation / stalled channels | Existing validity, generation cancellation, registered retirement and stable-payload rules |

The source-defined connected residual omits **6144 bytes of payload RAM**:
4096 bytes of callback FF1 working/branch RAM and 2048 bytes of raw
residual RAM. The numerical-head preprocessor's physical RAM is unchanged;
its reuse adds no vector RAM. The packed post private ceiling is now
2048 bytes, enforced by its parent range guard. Other active phases still
require up to 4096 bytes, so neither the dispatcher reservation nor its
workspace validation is reduced.

The complete 33243-byte native-controller sum above the prior increment
is now historical, not the current census. The new sum removes all eight
reported FF1 terms (`ff_control`, `ff_norm_control`, `ff_clamp_control`,
`mlp_control`, `down_control`, `down_clamp_control`, `inner_control`,
`inner_clamp_control`) from the supplied-raw post branch and its 16-bit
raw RAM read register. It adds captured `raw_only` bits in the preprocessor
and replay wrapper, plus `raw_binding` in the heads wrapper, each included
in the existing byte-rounded local census. Recompute the nonoverlapping
connected report before asserting a new numeric bound. Do not retain
the old 88123-byte comparison as a current measurement or infer closure
by subtracting physical RAM from the live ledger.

The twelve-positive-layer suspended-vector ceiling remains 4096 bytes
per frame plus 136 scalar bytes. This increment retires the **duplicate
post FF1 controller/backing** obligation, not the entire native capacity
proof. Reachable suspended frames, at most one protected dependency memo,
evictable memo entries, retained feature/outer consumers, controller
partitions and the fallback working limit still require reconciliation.
No legal-work capacity error or reduced acceptance threshold is authorized.

Independent verification must cover raw-only and normalized operation,
both final-binding settings and precisions, exact equivalence to the
independently scheduled FF1/post residual reference, final-binding misses
and restored tags, all pair boundaries and indices 511/512/513/1023,
stalls, reset and input/weight/source errors. Observe actual memo pin
lifetime, raw writes, read-before-overwrite, normalization drain and
summed live/shadow/physical allocations. No HDL execution or preparation
receipt exists for this increment; no functional or synthesis result is
claimed.

### Prior increment: active audio residual source lifetimes

`audio_lightconv.RAW_SOURCE_CALLBACK`, default zero, permits the caller
to retain the raw residual instead of copying it into the lightconv.
At one, validation advances directly to depthwise execution. After each
clipped projection completes, request that output component's original
raw BF16 value through the existing registered source channel. Capture
the response/error before the original FP32 residual add and BF16 narrow.
The default retained-raw path and both depthwise configurations remain.
No new arithmetic, weight interpretation or materialization boundary is
introduced.

The connected replay layer selects the callback for lightconv and for
mode-2 feed-forward. Its workspace retains raw values in bank 0 until
their last read. Lightconv's output replaces bank 0 in ascending aligned
pairs: both old raw components have been accepted by the child before
the pair write can commit. Subsequent raw reads address only the next,
not-yet-overwritten output component. During FF2 the complete bank-0
input remains unchanged; FF2 writes bank 1, and bank 0 is released only
after FF2's successful completion. Depthwise bank 1 is released after
lightconv completion, before FF2 starts. Returned workspace pairs and
partial output pairs remain included in their existing controller census.

| Pre-edge boundary | Registered action / ownership |
| --- | --- |
| Callback lightconv accepts start | Capture descriptor and reserve only its working vector; validate before any source/weight access |
| Supplied depthwise request | Read source indices 1024..2047 before any output; preserve the existing query-token and component checks |
| Successful projection | Request raw source index equal to the current output index, then register response/error before arithmetic |
| Nonzero replay output cursor | Permit a source callback only at that exact cursor and below 1024; no historical or overwritten raw read is permitted |
| First output component of a pair | Keep its scalar low half; do not overwrite workspace raw data yet |
| Second output component | Both raw reads precede the accepted pair write; await the workspace write response before further output work |
| FF2 input / final residual passes | Read retained bank 0 through the same callback; output goes to separate bank 1 |
| Child completion | Keep the source workspace alive until all output writes and child completion checks succeed |
| Source failure, stalled source/output, reset | Preserve registered error retirement and stalled payloads; reset clears public outputs and validity |

| Connected phase | Private live payload ceiling |
| --- | ---: |
| Attention-head preprocessing | 4096 bytes |
| Frame-backed post-attention | 4096 bytes |
| Channel history fold | Existing one-vector GLU working bank, 2048 bytes |
| Supplied-depthwise lightconv with raw callback | 2048 bytes |
| FF2 with raw callback | 4096 bytes; working allocation is released before final residual output |
| Final norm/clamp | No private vector bank |
| Serialized positive-layer maximum | 4096 bytes |

The dispatcher admission descriptor, workspace validation and connected
child range guards now enforce the same 4096-byte positive-layer maximum,
with lightconv separately limited to 2048. History/conv/FF mutual-exclusion
guards remain. This is a genuine payload-lifetime reduction, not a smaller
grant in front of an unchanged 6144-byte child.

Standalone callback lightconv physically omits its raw 2048-byte RAM and
16-bit read register. Its local-RAM configuration reports the resulting
two-byte controller reduction. The connected external-RAM configuration
adds no register, so the preceding 33243-byte report is unchanged.
The shared three-bank replay RAM remains physically 6144 bytes because
FF2 still uses banks 1/2 and its other users retain their address mapping.
No physical reduction of that shared store is claimed.

This closes the remaining active positive-audio private-phase envelope,
not the complete reachable storage bound. A conservative comparison is
now `33243+4096+12*(4096+136) = 88123` bytes, still 2107 above the
minimum-context E2B allowance even before memo/outer allocations.
Twelve suspended positive layers imply a layer-zero active worker rather
than the maximal positive-layer private phase; that observation is not a
certificate that all legal combinations fit. All reachable suspended
frames, pinned memos, outer consumers and native/fallback partitions must
still be reconciled without a legal-work capacity failure.

Independent verification must cover callback on/off, both depthwise
settings and precisions, exact numerical equivalence, raw indices
0/1/511/512/513/1023, request/output stalls, source errors after partial
output, reset, and actual read-before-overwrite workspace handshakes.
Require no callback-mode raw-bank accesses, proper FF2 input retention,
the lower admission value and measured summed actual/shadow allocations.
No compiler, simulation, synthesis or preparation probe ran for this
increment; the reserved static elaboration remains pending design closure.

### Prior increment: channel-serial audio history

The connected history worker now evaluates depthwise channels in ascending
order, visiting each channel's five taps in ascending kernel order. It
reconstructs the real full residual for each nonpadding tap, then computes
only that channel's GLU and depthwise product. Multiply/add rounding,
leading-padding operations and final BF16 narrowing remain unchanged.
Recomputation increases weight/input work; it is not avoided computation.

The fold's default vector mode remains available. Its `SINGLE_CHANNEL=1`
configuration captures `channel` and `prior_accumulator` at start and
returns the actual FP32 partial sum, or final narrowed BF16 in low bits,
through `done_data`. It never issues accumulator or output workspace
transactions in this configuration. The history worker owns output packing.

| Pre-edge boundary | Registered consequence |
| --- | --- |
| Fresh history task | Channel zero, zero scalar accumulator, empty low-half register; evaluate oldest nonpadding tap first |
| Nonfinal fold completes | Capture real FP32 sum, release consumed residual and advance to next tap |
| Final fold completes, even channel | Capture BF16 low half; do not publish an incomplete pair |
| Final fold completes, odd channel | Commit the complete aligned BF16 pair in depthwise bank 1/slice 0, waiting for its actual response |
| Next channel | Release dead residual, reset tap index/accumulator, reconstruct that channel's tap sources |
| Final channel completes | Keep the final query residual for lightconv; publish only after the final output-pair response |
| Child dependency yield | Save channel/low-half and FP32 accumulator in frame scalar words 32/33 before publishing the yield |
| Resumed history task | Restore and validate both extra words before restarting the suspended child; numerical checkpoint words 8..29 and head wrapper words 30/31 are not overwritten |
| Reset/error/backpressure | Preserve cancellation, response retirement, stable descriptors and existing tag checks; never substitute a partial or software-produced answer |

Scalar backing becomes 34 words (136 bytes) per frame, including all
reserved words in live/shadow/grant accounting. Production/compact backing
reservations grow by 512 bytes, not an uncounted side RAM. The eliminated
two FP32 accumulator slices are replaced by at most one partially filled
depthwise output slice. Suspended packed-history vectors therefore have
a 4096-byte ceiling (head + output), rather than 6144. Active final
binding/post-attention and every private/controller/memo/outer allocation
remain charged. This is a connected storage reduction, not whole-system
capacity acceptance; all reachable native/fallback and physical partitions
still need reconciliation before the reserved static check.

Frame scalar word 32 is `{6'b0, pending_low_bf16[15:0], channel[9:0]}`;
word 33 is the FP32 partial sum. Restore rejects nonzero reserved bits,
a pending low half at an even channel, and a nonzero accumulator at the
first real tap. Generation/frame validation precedes these accesses.
Snapshot write errors suppress a pending yield and retire as errors.
No numerical head checkpoint is shortened or overlapped.

The history wrapper's declared local controller report grows from 866
bits/109 bytes to 1022 bits/128 bytes. The fold adds no registers:
it captures the selected channel and prior accumulator into its existing
registers. Thus the preceding source-derived native controller sum
becomes **34014 bytes** (+19); workspace scalar visibility metadata grows
by 128 bits/16 bytes separately. These are source-expression counts, not
elaboration, observed allocation or synthesis results.

The conservative twelve-frame comparison is now
`12*(4096+136) = 50784` bytes, a 24480-byte reduction from
`12*(6144+128) = 75264`. It still does not fit the minimum E2B allowance
when simply added to all current native controllers and active private
state: `34014+6144+50784 = 90942 > 86016`, before memo/outer state.
This upper-bound comparison is not proof of reachable simultaneous
occupancy or permission to reject legal work. Further connected reductions
or a complete reachable-liveness proof remain required.

Independent verification must cover both fold configurations and
precisions, channels 0/1/511/512/513/1023, all leading-padding lengths,
FP32 accumulation and BF16 packing, yields at every tap and head phase,
snapshot restore/tag corruption, final-query-residual retention,
partial-output eviction/regeneration, reset and all stalled/error paths.
Observe actual absence of accumulator-slice requests, scalar indices
31/32/33/34, adjacent frame separation, full 136-byte grants and
production shadows, not just status bits. The extra residual
reconstruction per channel can be extremely expensive; no latency or
total-traffic improvement is claimed.

Saved `audio_history_fold`, `replay_audio_history`, `replay_workspace`,
`frontier` and both design documents. Used view/rg/glob/apply_patch only.
No HDL execution, functional/synthesis probe or preparation receipt;
the reserved static elaboration remains unused. Tests, immutable parent
sources, runtime metadata and original failure records remain unchanged.

### Prior increment: memo-backed audio queries and deferred residual binding

The connected packed-history residual selects
`replay_audio_heads.DEFER_QUERY_BINDING=1`. Default zero preserves the
standalone eager-binding behavior. Deferred mode does not copy an entering
1024-component audio vector into bank 0 before attention. Query, key and
value source needs all use the existing exact predecessor dependency
interface and its pinned memo slot. A query token is no longer treated as
an unconditional frame hit. A matching dependency permits the actual
pre-attention reconstruction; a missing dependency checkpoints and yields
to the lower encoder layer, including for the query itself.

The attention engine's normalized-source cache, numerical checkpoint,
head ordering, reductions and materialization boundaries are unchanged.
Every completed head pair still commits to bank 0/slice 1 after the
history wrapper's existing packed-frame mapping. A suspended attention
consumer retains that partial head vector and its scalar checkpoint,
but no separate entering/raw vector. Matching query reads use memo
`target=1`, never an unfilled frame bank. The normal memo allocation,
pinning, eviction and traffic accounting remain in force; this is not
an uncounted source vector or a software-produced answer.

After all eight heads and their pair responses complete, the same
predecessor-binding engine copies the query input into bank 0/slice 0
for post-attention residual execution. A currently held historical-token
dependency is not supplied as though it matched this query. Instead,
the binder yields a query dependency without reserving the raw slice.
The new internal 160-bit continuation has magic `0x454e3150`, followed
by the existing generation, historical query, frame layer/slot,
model/precision and logical layer fields; bits 37:0 are zero. The history
wrapper validates the tag, token range, zero head field and requested
dependency identity, and resumes this final binding rather than replaying
or overwriting the completed head vector.

| Pre-edge boundary | Registered consequence / ownership |
| --- | --- |
| Deferred fresh task, including mode 2 | Start head zero without a frame-input copy; any supplied predecessor stays a separately counted, pinned memo entry |
| Query or historical source need, matching dependency absent | Save the real numerical checkpoint and yield the exact lower-layer token; no raw slice allocation |
| Matching source read | Read the registered memo response with the same tag/range/error checks used for other predecessor tokens |
| Head pair write accepted | Retain the existing ordered pair protocol and partial-head reservation |
| Head seven completes, all 1024 outputs committed | Start final query binding; no further attention operation can yield from this phase |
| Final binding misses | Keep all heads and convolution accumulators; yield with `0x454e3150`, without allocating the missing input |
| Final-binding continuation resumes | Validate the complete descriptor and perform only the real predecessor copy; do not restore an unrelated head checkpoint or reinitialize head output |
| Copy response completes successfully | Publish head completion, then run unchanged post-attention residual using the now-complete raw and head vectors |
| Copy/source error or backpressure | Retire the existing registered response/error path; preserve reservations and stable payloads |
| Reset / generation invalidation | Retain the existing cancellation/visibility rules; no old continuation authorizes a new-session word |

This removes **2048 bytes per suspended packed-audio head consumer**.
Before the first fold, a suspension retains at most its head slice,
2048 bytes instead of 4096. During later taps it retains at most that
slice plus two FP32 accumulator slices, 6144 instead of 8192 bytes.
Final binding/post-attention can still have four slices while active,
but cannot start a recursive dependency after the raw copy begins.
The final-fold consuming overlay and release protocol are unchanged.
No new register or RAM is declared: the existing five-bit head-wrapper
state accommodates two final-binding states, and the marker is assembled
from existing registered fields. Thus the preceding declared-controller
report remains 33995 bytes; physical frame-bank reservation is unchanged.

The minimum-context E2B remainder after that report and the conservative
6144-byte active private envelope is still 45877 bytes. Six suspended
three-slice frames plus scalar slots now need
`6*(6144+128) = 37632` bytes, rather than 49920, before memo/outer state.
This is **not** a proof that six is the reachable maximum or that the
whole system fits. Twelve suspended positive-layer frames alone have a
73728-byte vector ceiling, and an active positive-layer frame may add
2048 bytes relative to its suspension. Complete native/fallback fit,
outer consumers, memo/scalar/controller reconciliation, production
shadows and physical partitions remain unresolved. No legal-work
capacity error or weakened allowance is authorized.

Independent verification must cover both parameter settings, both
precisions, query misses before the first head, alternating query/history
memo dependencies, head checkpoints after partial pair output, final
binding with matching and nonmatching last dependencies, eviction before
final binding, all tag corruption cases, reset/stalls/errors, and exact
source/head/residual values. Observe the actual workspace reservations
and memo pins; a mode bit or leaf responder is not storage evidence.

Saved three RTL files (`replay_audio_heads`, `replay_audio_residual`,
`replay_audio_history`) and both design documents. Only source
view/rg/glob and apply_patch were used. No HDL execution, simulation,
synthesis, preparation harness or receipt was produced. The reserved
static elaboration remains pending complete design closure. Tests,
immutable parent sources, original failures and runtime metadata remain
unchanged.

### Current increment: frame-backed raw-source feed-forward

The frame-backed post-attention path consumes only the raw FF1 residual
stream from `audio_pre_attention`; its second, normalized stream was
discarded. Specialize `audio_attention_residual.FRAME_HEADS=1` to connect
the actual mode-1 `audio_feedforward` directly. This removes only the
unused attention-input normalization/clamping and its controller subtree.
Attention's real query/key preprocessing in `replay_audio_attention`
remains unchanged. The default standalone path retains both streams.

Add `audio_feedforward.RAW_SOURCE_CALLBACK`, default zero. At one, the
immutable source supplies raw components twice: once before input clipping,
and again for the final residual addition. Do not retain a private raw
vector. In connected frame-backed post-attention, those reads use the
already retained raw input frame, not host-computed values or a new spill.
Both feed-forward modes and precisions retain their clipping, normalization,
MLP, BF16 half-residual rounding and ascending traversal.

| Boundary | Required action |
| --- | --- |
| Start/validation | Capture the descriptor; reject illegal parameters with the existing explicit diagnostic |
| Initial source acceptance | Register response and error, then clip the actual raw BF16 component into working RAM; no raw-bank write |
| Initial component advance | Request the next raw component; expose working visibility only after all 1024 clipped words are stored |
| Post-normalization completion | Reread raw component zero through the registered source channel before the existing branch-read/multiply sequence |
| Final residual component | Register raw response before branch read; preserve the original multiply, BF16 narrowing/widening, addition and final narrowing order |
| Final output acceptance | Advance only after ready/valid acceptance; reread the next raw component |
| Source failure | Retire the accepted response and publish error 7 without a new source/weight request |
| Active reset/stall | Zero public outputs during reset; retain source descriptor and output payload while stalled |
| Frame-backed FF output | Count raw outputs only; no normalized output is expected or manufactured |
| Ownership | Keep caller raw-output allocation charged while filling it; sum it with the child's branch/working allocations, not their maximum |

With the callback, FF working+branch peak at 4096 bytes; during FF output
only its 2048-byte branch remains, alongside the caller's 2048-byte raw
output. Thus this frame-backed post-attention phase falls from 6144 to
4096 private bytes. Later raw+projection-working still use 4096 bytes.
The child physically removes its private 2048-byte raw bank. Existing
external-vector-RAM users retain their physical backing unless separately
changed. This is not a reduction of suspended history/head/output vectors.
The source-derived native-controller report is now **33243 bytes**,
771 fewer than the preceding 34014-byte hierarchy. This is report-expression
accounting, not an elaborated declaration audit or observed allocation.
Complete native/fallback and physical-partition fit remain open.

The same default-off callback parameter is forwarded by
`audio_pre_attention`, and enabled by `replay_audio_attention`. Its
original source remains the pinned memo dependency throughout the whole
pre-attention task. Keep the existing shared three-bank physical store:
bank 0 now holds only the emitted, clipped FF residual, while FF uses
banks 1/2 for working/branch. Charge bank 0 concurrently with FF as soon
as its first output is accepted; unlike the retained-raw configuration,
FF no longer includes that bank in its own report. The resulting phases
are working+branch 4096, branch+pre-output 4096, then pre-output+normalized
cache 4096 bytes. Do not retain or claim the old 6144-byte head-preprocessing
private peak. Physical shared RAM remains 6144 bytes. Full-hierarchy
envelopes stay conservative until every other active phase is reconciled.
The connected residual wrapper now diagnoses either private child exceeding
4096 bytes; its original mutual-exclusion check remains.

| Removed / changed declared controller term | Bits / bytes |
| --- | ---: |
| Unused `audio_pre_attention` wrapper | 353 / 45 |
| Unused output clamp | 75 / 10 |
| Unused native norm wrapper | 389 / 49 |
| Its tensor directory | 1605 / 201 |
| Its external-FP norm, length converter and div/sqrt | 490/62 + 79/10 + 500/63 = 135 bytes |
| Its external-FP scale reader | 1335 / 167 |
| Its private FP arithmetic | 542 / 68 |
| New local FF RAM read registers versus old external-RAM FF | +32 / +4 |
| Net removed report bytes | 45+10+49+201+135+167+68-4 = 771 |

The audio input/layer nested term is `21792+19-771 = 21040`
bytes (the +19 is the preceding channel-history scalar controller change).
The unchanged remaining nine terms sum to 12203 bytes, giving
`21040+12203 = 33243`. Explicitly absent supplied-head arithmetic is no
longer instantiated; its already-zero report contributes no additional
claimed saving. Physical frame-backed post payload falls from 10240 to
8192 bytes: caller raw/working 4096 plus callback FF working/branch 4096.
The shared numerical-head pre-attention RAM remains 6144 bytes.

This still does not close capacity: even the deliberately conservative
comparison `33243+6144+12*(4096+136) = 90171` exceeds the smallest
86016-byte E2B native allowance before memo/outer state. Not all these
maxima are proved simultaneous, but no reachable-fit certificate follows.
The reserved static elaboration remains unused pending design closure.

Independent verification must cover both callback settings, both modes
and precisions, exact output equivalence, the second raw read of every
component, first/last component, source errors in both passes, reset and
stalls, absence of raw-bank accesses in callback mode, and actual summed
allocations. No functional or synthesis execution is claimed here.

### Prior increment: supplied-depthwise specialization and native controller census

The connected replay lightconv selects `PRECOMPUTED_DEPTHWISE=1`: its
depthwise input is already produced by `audio_history_fold` in the
workspace. The lightconv's original depthwise-row and GLU subtrees could
never receive a start in this configuration, but remained instantiated
and charged by their controller reports. They are now elaboration-time
branches, present only for `PRECOMPUTED_DEPTHWISE=0`. The supplied-depthwise
branch has no such arithmetic, tensor readers or GLU payload RAM. Its
absent child command, source, result, event, vector-RAM and accounting
outputs are explicitly zero; it does not fabricate a completed operation.
The wrapper's existing scalar registers and complete local census remain.

| Configuration / boundary | Preserved behavior |
| --- | --- |
| Default `PRECOMPUTED_DEPTHWISE=0` | Instantiate the original depthwise row and GLU; retain their source/weight operations, arithmetic and accounting |
| Connected `PRECOMPUTED_DEPTHWISE=1` | Read actual RTL-computed depthwise components through source indices 1024..2047; never start the absent children |
| Supplied source response | Keep existing descriptor validation, registered response/error capture and BF16 materialization |
| Norm, SiLU, clipped projection and raw residual | Keep the existing connected operators and operation order in both configurations |
| External vector RAM, supplied mode | Third (GLU) port is zero; raw/working ports are unchanged |
| Reset or stalled response | Preserve the wrapper's reset, response retirement, stable payload and error rules |
| Physical reporting | Remove only physically absent child RAM; retain the shared dispatcher bank's full reservation for its other users |

A read-only source-expression calculation now resolves the connected
**native-reconstruction report**, rather than continuing to use the old
33221-byte figure. It propagates production `COMPACT=0`, external embedding
and connected worker vector-RAM settings; evaluates `$bits`, local
constants and byte rounding; and follows each named child report once.
Shared/external primitive arithmetic contributes zero only where the
corresponding arithmetic unit is physically absent. The native subset is
the same for E2B and E4B because these controllers use their declared
maximum geometry; it does not depend on resident capacity C.

| Nonoverlapping term in `native_reconstruction_controller_bytes` | Bytes |
| --- | ---: |
| Original-input reconstruction, including embedding descendants | 1082 |
| Vision replay controllers and all reported descendants | 6499 |
| Audio input wrapper | 48 |
| Audio layer wrapper | 119 |
| Audio input/layer nested controllers | 21792 |
| Audio feature wrapper | 101 |
| Audio feature nested controllers | 2057 |
| Image feature wrapper | 121 |
| Image feature nested controllers | 2169 |
| Native vector ownership/read state, 52 bits rounded once | 7 |
| Complete native-reconstruction report | 33995 |

Within the lightconv with external vector RAM, the unchanged local census
is 614 bits. Its full own-controller report, including activation and
primitive FP arithmetic, is 355 bytes. The computed-depthwise nested
report is 3278 bytes; the supplied-depthwise nested report is 1222 bytes.
The absent subtrees therefore remove 2056 bytes from the connected native
controller report, from 36051 to 33995 bytes on these sources. The real
new history fold remains fully charged: 750 local bits, 94 local bytes
plus 1995 nested bytes. It is not replaced by the absent lightconv child.

These are evaluated **declared report expressions**, not an elaborated
register census, declaration-coverage proof, allocation observation,
synthesis result or hardware measurement. Preliminary source-reading
helpers did not resolve the module-header/instance boundary; those
unresolved calculations are not included as numerical results. No HDL
compiler or simulator was invoked, and the reserved static check remains
unused.

For minimum-context E2B, the current native allowance still leaves only
`86016-33995-6144 = 45877` bytes after this controller sum and the existing
active-audio private envelope. That remainder must cover **all** native
frames, continuations/scalars, memo entries and retained features, not
just the selected worker. Six four-slice frames plus their 128-byte scalar
slots would require `6*(8192+128) = 49920` bytes even before outer
consumers. This is a conservative comparison, not a claim that six such
frames were observed or proved simultaneously reachable. The full
twelve-positive-layer ceiling remains 98304 vector bytes; demand-first
initial descent and token-zero specialization do not justify substituting
their smaller phase bound for later-tap mixed-token suspension.

This retires the **unreachable supplied-depthwise child retention** and
updates the complete connected native-controller report. It does not
close legal-workload native capacity, reconcile the remaining text/
fallback controller and physical partitions, or authorize error 7 for a
legal capacity request. Establish a tighter reachable liveness bound or
implement genuine further streaming/rematerialization, then reconcile
actual/shadow allocations and transitions before static elaboration and
independent Verifier handoff. Independent checks must cover both leaf
configurations, real supplied source data, both precisions, source/weight
errors, stalls, reset, controller-report sums and absence of child commands
and third-port accesses in supplied mode.

Saved `rtl/anvil_en1_audio_lightconv.sv` and both design documents.
Tools used: view, rg, glob, apply_patch and read-only Python source
inspection via bash. No functional/synthesis harness, HDL execution,
experiment or preparation receipt was produced. Tests, parent sources,
original failure records and runtime metadata remain unchanged.

### Prior increment: committed audio accumulator slice replacement

The workspace now admits `op=6,target=3` for native-audio slice indices
1 and 2, alongside the existing ordered initialization operation
`op=6,target=2`. This repairs a connected descriptor mismatch introduced
by the tap-streamed history implementation. The fold writes 1024 FP32
accumulators as two 2048-byte slices; each later nonfinal tap replaces
the committed words, rather than starting a new vector stream. Previously
the common slice validator rejected that replacement as error 5 on
channel 512, the first word of slice 1. This is a source-derived defect;
no functional failure receipt or executed repair result is claimed.

| Workspace boundary | Required behavior after repair |
| --- | --- |
| Audio slice 1/2, `op=6,target=2` | Retain ordered first-pair allocation, partial-stream accounting and last-pair publication |
| Audio slice 1/2, `op=6,target=3` | Admit the slice descriptor, then require the exact occupied frame tag and an already committed destination |
| Replacement of an absent or partial slice | Retain error 7; never allocate, publish or initialize it implicitly |
| Other domains, nonzero slice index | Retain descriptor rejection |
| Audio slice index >=3 | Retain descriptor rejection |
| Replacement stalls or backing error | Retain registered request stability, backing-response retirement and the existing reservation |

The correction changes only descriptor eligibility. The selected slice
address, tag check, reserved/present consistency check, `PAIR_SETUP`
committed-destination guard and synchronous backing access remain
unchanged. Replacement does not change any vector occupancy, allocation
counter, physical reservation, memo policy or numerical boundary.
Slice 2 is admitted consistently with the existing three-slice audio
frame interface; the current fold uses only slices 0 and 1.

Independent verification must execute a successful initial fold, at least
one later nonfinal fold, and the consuming final fold through the real
workspace. Cover channels 511,512,513,1023, both precisions, exact FP32
word comparison, absent/partial/stale destinations, nonaudio and out-of-range
slice rejection, stalls and failed backing responses. A leaf-only fold
test with an unconstrained workspace responder cannot detect this defect.

No experiment, elaboration, simulation or synthesis was run for this
repair. Whole-system native/fallback capacity is still unclosed; the
reserved static elaboration remains pending complete design closure.

### Prior increment: demand-first initial audio tap

The connected history schedule now starts with the oldest **nonpadding**
residual, at distance `min(query_token,4)`, before allocating convolution
accumulators. It no longer executes padding-only frame-wide folds before
that residual can request its dependencies. The fold leaf adds legal
parameter `FUSE_LEADING_PADDING=0|1`, default zero; the history instance
selects one. Default zero preserves standalone single-tap arithmetic,
including explicitly requested padding taps.

With fusion enabled, the first nonpadding tap reduces its leading
padding and current tap **per channel** in scalar registers. It reads
kernel weights in ascending column order `0..first_kernel`, multiplies
each missing input's BF16 positive zero by its actual weight, and performs
each separately rounded binary32 addition starting at positive zero.
Only the real tap invokes GLU. No zero multiplication, exceptional value,
weight response or rounding boundary is skipped. Independent channels can
be interleaved differently because they do not share reductions.

For tokens 0..3, `first_kernel=4-token`; for tokens >=4 it is zero.
Subsequent real residuals retain the existing oldest-to-newest schedule.
The first completed nonfinal fold initializes the two accumulator slices
with ordered pair streams even when its kernel is not zero. Later real
taps read/replace those committed words. For query token zero, all five
taps reduce per channel during the only fold and narrow directly into
the depthwise output: **no bank-1 accumulator slice is ever requested,
reserved, read, written or released**.

| Pre-edge boundary | Registered work / live-frame consequence |
| --- | --- |
| New history task | Start distance `min(query,4)`, not an unconditional four |
| First residual binding or head yield | Save the real unchanged continuation; this history has not started an accumulator stream |
| First residual succeeds and its head slice release retires | Start the first actual fold; only now may accumulators be initialized |
| Leading-padding arithmetic completion | Retain its exact FP32 scalar sum, advance one kernel, issue the next real weight read |
| First real tap's addition completes | Initialize its accumulator pair, or narrow directly when it is also the final tap |
| Next channel | Restart at kernel zero only for the fused first fold; restart the scalar reduction at positive zero |
| Token-zero fold completes | Publish raw residual and depthwise output without issuing fictitious releases for absent accumulator slices |
| Later-tap dependency yield | Preserve already materialized accumulators and the real residual/head continuation exactly as before |
| Error, reset or response stall | Preserve existing retirement, generation, error and charged-live-state rules; no success or readable vector is manufactured |

This closes the **eager leading-padding allocation** issue and establishes
a sharper initial-descent bound: before a frame's first successful real
fold, its suspension retains at most entering and partial-head vectors,
4096 bytes, rather than also retaining 4096 bytes of padding accumulators.
For token zero no accumulator allocation occurs anywhere in that frame's
execution. Completed real taps are never discarded or restarted following
a dependency miss; progress therefore does not depend on retaining them
in the evictable memo. The extra scalar control is included in the fold's
explicit local census; no RAM is added.

The final fold also **consumes** the old accumulators instead of allocating
a separate BF16 output slice. All configurations of the fold leaf now write
their final depthwise vector into bank 1/slice 0. For a final fold with
existing accumulators, the output uses committed-pair replacement
(`op=6,target=3`). After channels `2*j` and `2*j+1` have each read their old
FP32 accumulator, completed their fifth addition and narrowed, their packed
BF16 outputs overwrite word `j` of slice 0. Before channel 512, the old
accumulator word for channel `c` is word `c` of that slice. Thus at the
write for odd `c`, destination `(c-1)>>1` is strictly behind every unread
old word. From channel 512 onward, old accumulators come from the distinct
slice 1 and all overwritten slice-0 words are already dead.

Every accumulator read response and arithmetic result retires before its
consuming output write. There is only one workspace transaction outstanding;
no same-address read-during-write RAM behavior, partial-vector publication
or hidden vector copy is required. After channel 1023 the complete slice
contains the BF16 depthwise vector; history releases **only** bank 1/slice 1
and retains slice 0. In the token-zero fused case no old accumulator exists,
so output instead uses the normal ordered pair stream (`target=2`) to
initialize and commit slice 0. Its first partial output reservation is
counted normally.

| Final-fold frame region | Live contents / retirement |
| --- | --- |
| Bank 0, slice 0 | Raw query residual, retained for lightconv |
| Bank 0, slice 1 | Head output already successfully released; no final-fold write |
| Bank 1, slice 0 | Consumed old FP32 prefix / unread FP32 suffix and completed BF16 output prefix in the same 2048-byte reservation |
| Bank 1, slice 1 | Unread old FP32 accumulator suffix; release only after successful final fold |
| Token-zero specialization | Only raw query and the ordered BF16 output stream are reserved; neither accumulator slice is separately allocated |

`replay_audio_layer` now reads the computed depthwise components from
bank 1/slice 0 and releases that exact slice after successful lightconv,
before FF2 can initialize its own bank-1 output. Its raw query source
remains bank 0/slice 0. Source tags, range checks and registered responses
are unchanged. Errors retain the shared reservation until unwind; a
partially transformed accumulator never starts lightconv. This removes
the separate 2048-byte final-output reservation, lowering the final-fold
frame peak from four slices to three (6144 bytes), or two slices
(4096 bytes) at query zero. Residual suspension after earlier real folds
still has the unchanged four-slice ceiling; this active-phase overlay is
not a claim that the worst suspended-frame bound fell.

This is not whole-system capacity closure. Later-tap yields can still
retain four slices, and mixed-token descendants, suspended outer consumers,
memo pins, scalar slots, private state and the updated complete controller
census still require reconciliation against both native and fallback
partitions. Neither a hypothetical memo hit nor a grant-denial error for
legal work is a capacity solution.

Independent verification must cover query tokens 0,1,2,3,4 and later
tokens, both precisions, exceptional/signed-zero padding weights, default
and fused leaf configurations, every ascending-column intermediate
comparison, first-tap pair-stream commit, later replacements, both
accumulator-slice boundaries, and source/weight/workspace stalls and errors.
It must observe no accumulator request at token zero and no accumulator
reservation before the first real fold, including repeated dependency
resume, without weakening any existing numerical or allocation check.
Final-output checks must additionally cover the consuming reads/writes at
channels 0/1, 510/511, 512/513 and 1022/1023, stable payload under stalls,
failure during a committed-pair replacement, delayed suffix release, and
the depthwise-to-FF2 ownership transfer. No extra output-slice allocation
may be hidden by a counter decrement.

Saved changes: `rtl/anvil_en1_audio_history_fold.sv`,
`rtl/anvil_en1_replay_audio_history.sv`,
`rtl/anvil_en1_replay_audio_layer.sv`, SPEC and ARCHITECTURE.
Only source reads/searches and edits were performed. No experiment,
elaboration, simulation, synthesis or preparation receipt is claimed.
The reserved static check remains unused; tests, immutable parent sources,
original failures and runtime metadata are unchanged.

### Prior increment: tap-streamed audio history folding

The connected audio replay path no longer saves five complete residual
histories for convolution. `replay_audio_history` evaluates one residual
at a time, invokes the new `audio_history_fold` leaf, waits for its real
completion, releases the consumed residual and then evaluates the next
history. All tap products and reductions still execute in RTL. There is
no host-generated convolution, cached numerical answer or external spill.

At this prior increment the traversal was kernel column `0..4`, equivalently history distance
`4..0`. Each tap visits channels `0..1023`. For each channel the leaf uses
the existing normalized/clipped GLU component engine and the existing
weight reader for tensor `0x210e`, row channel, column kernel. It widens
the BF16 GLU result, performs a separately rounded binary32 multiply,
and adds that product to the channel's binary32 accumulator. Thus
interleaving independent channels changes neither the ascending-column
reduction nor any per-channel materialization boundary.

Negative historical positions supply BF16 positive zero **to the
multiply**, just as the existing depthwise row source does. They do not
skip the weight read, multiply or addition: `0*infinity`, NaNs and signed
zero must retain the admitted primitive semantics. These padding taps do
not invoke a residual encoder or GLU. Kernel zero starts each accumulator
at binary32 positive zero. The final kernel narrows only after the fifth
addition. Both precision modes retain their existing weight decoding and
row-boundary validation; directory type, row count and column count are
checked before weight access.

| Frame region | Contents / lifetime |
| --- | --- |
| Bank 0, slice 0 | Current residual's entering/input storage, then its complete post-attention residual; nonfinal histories release after successful fold completion |
| Bank 0, slice 1 | Current residual's partial/full head output; release after successful residual completion, before folding; the final tap reuses it for the BF16 depthwise vector |
| Bank 1, slices 0 and 1 | 1024 binary32 accumulators, 512 aligned 32-bit words per slice; survive residual yields and all intervening taps |
| Bank 0, slice 2 and bank 1, slice 2 | Not allocated by the new history schedule |

Accumulator word channel `c` has slice `c[9]` and BF16-pair component
`{c[8:0],1'b0}`. The first tap uses the existing ordered pair-stream write
operation (`op=6,target=2`) to fill and commit each entire slice. Later
taps read the committed old word and use the existing committed-pair
replacement (`op=6,target=3`). They do not invalidate unread suffixes or
pretend a partially filled first-tap vector is readable. There is no
additional accumulator array or temporary copy. Successful final output
publication releases both accumulator slices before returning the two
surviving vectors.

| Pre-edge handshake / boundary | Registered consequence |
| --- | --- |
| Reset or new task acceptance | Clear private control and validity; accepted workspace operations retain the workspace's generation/response rules |
| Normal task setup | Start distance 4; select a supplied predecessor only when its complete descriptor matches this historical token |
| Residual dependency yield | Preserve the two accumulator slices and the current residual's real vector/scalar continuation; issue no fold or next-tap work |
| Successful residual completion and head-slice release response | Start that tap's GLU/weight/accumulator work; no old head slice remains live |
| First-tap pair write response | Retire that actual write; a slice becomes readable only after its complete ordered stream |
| Later-tap read response | Register the old accumulator before the FP32 addition; write only after arithmetic completion |
| Final-tap pair write response | Retire two narrowed BF16 components in the formerly dead head slice |
| Nonfinal fold completion | Release the consumed raw residual only after successful registered completion, then decrement distance |
| Final fold completion | Release bank 1 slices 0 and 1 through separate successful responses; retain raw query residual and depthwise output |
| Error or any stalled response | Keep live reservations; stop new dependent work, retire the current response and propagate its concrete error |

Only residual evaluation can yield. A fold completes its finite 1024-channel
loop without yielding, and a next tap cannot start before the preceding
fold and release have retired. On resume, the validated history/head
continuation identifies exactly the interrupted residual; completed taps
are neither restarted nor accumulated twice. Existing scheduler dependency
pins, generation checks, frame tags and scalar continuations remain in use.

`audio_lightconv` adds legal parameter `PRECOMPUTED_DEPTHWISE=0|1`, default
zero. The default retains its existing connected depthwise/GLU path.
`replay_audio_layer` selects one and supplies the **computed RTL** depthwise
vector from its frame. In this mode a source index `0..1023` requests the
query residual, and `1024..2047` requests depthwise component `index-1024`,
with the same model/layer/generation/query-token tags. The parent validates
the range and tags before the registered workspace read. Clamp, learned
normalization, SiLU, pointwise projection and residual addition remain in
the original light-convolution engine. It does not rerun or double-narrow
the depthwise result. After its successful completion the parent releases
the depthwise slice before FF2; the existing FF2/final-norm releases remain.

The fold's local normalized GLU vector is 2048 physical/live bytes and is
included in history's summed child reports. It does not coexist with an
active residual private worker. Its descriptor, source response, arithmetic,
directory, weight-reader and GLU controller state are included in the
connected nested controller report. All new weight handshakes contribute
to the existing weight-traffic events; source, projection and GLU replay
events are forwarded rather than replaced by the precomputed-path status.
The history completion count is now one retained raw residual, not the
old number of materialized histories.

This retires the **six-slice history-retention implementation**, replacing
its 12288-byte per-frame ceiling with a conservative four-slice,
8192-byte ceiling. During suspension those slices cover the complete
4096-byte accumulator plus at most the entering and partial-head vectors.
During the final fold the same four-slice ceiling instead covers the
accumulator, raw residual and partial BF16 depthwise vector. All scalar
slots, memo entries, retained outer features and private/controller state
remain separately charged. The fold adds private physical RAM/controller
state; this is not a claim that total FPGA reservation decreased.

Whole-system native/fallback capacity is **not closed**. Twelve maximal
four-slice frames plus 128-byte scalar slots conservatively require
`12*(8192+128)=99840` bytes, before private state or outer consumers.
The earlier 33221-byte native controller census predates the new connected
leaf and must be recomputed, not reused as a passing bound. A tighter
reachable-state proof or further genuine streaming/rematerialization is
still required. The actual and production-shadow ledger, strict savings
thresholds, native-scratch ceiling and fallback partitions are unchanged.

Independent verification must compare all channels against its separate
depthwise reference for every tap, both precisions, padding and exceptional
weights; cover kernel-zero commit, later committed-pair replacement,
511/512 accumulator-slice crossover, final BF16 packing, interruption at
each residual/head boundary, repeated resume, private/actual/shadow
allocations, all release stalls/errors, reset and failed weight responses.
It must also verify the unchanged default lightconv configuration.
These are pending obligations, not executed results.

Saved design sources are `rtl/anvil_en1_audio_history_fold.sv`,
`rtl/anvil_en1_replay_audio_history.sv`, `rtl/anvil_en1_audio_lightconv.sv`
and `rtl/anvil_en1_replay_audio_layer.sv`, plus this document and
ARCHITECTURE. Only source reads/searches and edits were performed.
The reserved static elaboration remains unused; no experiment, simulation,
synthesis, preparation receipt or acceptance result is claimed. Earlier
failure records, tests, parent references and runtime state are untouched.

### Prior increment: consuming raw/output RAM overlay

`audio_pre_attention` now owns three synchronous 1024-word BF16 banks and
uses `audio_feedforward`'s existing external-vector-RAM configuration.
Bank 0 contains feed-forward's raw residual, bank 1 its normalized entering
vector, and bank 2 its branch. The pre-attention clamp overwrites bank 0
one accepted output element at a time; it no longer allocates a fourth
working bank. This is a consuming storage transformation, not a copy or
an arithmetic change.

Feed-forward's output order is strictly ascending. Before exposing element
`i`, `FINAL_READ`/`FINAL_CAPTURE` have consumed its raw word and branch word,
and the complete residual result has been registered. Feed-forward never
reads raw element `i` again. After accepting that output, the wrapper runs
clamp and writes the clamped value to the same bank/address in `STORE`.
Feed-forward may already read element `i+1` while the wrapper clamps `i`;
these are different addresses on independent synchronous read/write ports.
Its next output remains stalled until the wrapper returns to `FF_WAIT`.
The wrapper starts normalization only after all 1024 stores and successful
feed-forward completion/retirement. Norm reads the transformed bank 0.
No same-address read-during-write RAM behavior is required.

| Pre-edge event | Post-edge ownership / visibility |
| --- | --- |
| Active reset or new task acceptance | Wrapper output visibility/reservation and sticky RAM fault clear; feed-forward independently clears its state on reset |
| Feed-forward input/MLP phase | Three banks charged by the child, 6144 bytes; wrapper has not written output |
| First accepted raw output | Wrapper retains output ownership; bank 0 is shared with the child's not-yet-consumed suffix, not an additional vector |
| Successful output clamp/store for element `i` | Consume raw word `i`, retain clamped word `i`; write only a well-formed in-range stream |
| Feed-forward post phase/output stalls | Child raw+branch remain charged, 4096 bytes; wrapper's bank-0 reservation is already included |
| Feed-forward completion acceptance | Child releases raw+branch; wrapper continues charging bank 0, 2048 bytes, without an uncharged edge |
| Successful `FF_CHECK` | Make the complete transformed vector visible and permit normalization |
| Error or output/completion stall | Keep live bank ownership; no partially transformed bank becomes readable as a complete vector |
| Wrapper completion acceptance | Release bank 0 and visibility; physical banks remain reserved |

The wrapper always includes the full child live report. It adds its
2048-byte output reservation only after the child has released its own
raw-bank reservation (`ff_live == 0`). Whenever the child report is
nonzero, it includes the complete raw and branch banks; its working-bank
release is independent. This union of the identical bank-0 storage does
not omit another child's state or subtract unrelated payload. The wrapper
reports all 6144 physical bytes; the external-RAM child reports zero
physical vector bytes. All three 16-bit read registers and the sticky
RAM fault enter the wrapper's controller census; the child's corresponding
local-RAM read registers are absent and not charged twice.

Connected range/port guards reject out-of-range child accesses, two writers
or two readers on bank 0, a norm read concurrent with a child write, and a
clamp write colliding with a child read of the same word. A fault suppresses
the conflicting access, is retained through response stalls, drains
feed-forward output without publishing it, prevents normalization and
returns error 7. There is no silent alternate RAM source.

`replay_audio_attention` now also releases the old normalized-source cache
when invalidating it for a rebuild. No engine callback can read that
invalidated cache while the pre-attention worker runs. Its reservation is
reacquired on the first well-formed normalized output write, not before
feed-forward computation. Partial rebuilt cache data stays charged on
failure, but becomes visible only after complete successful reconstruction.

The source-derived connected replay-head peak is now 6144 bytes during
feed-forward, 4096 during raw output, and 4096 during normalized-cache
output. Frame-backed post-attention peaks at 6144 during raw output
(outer raw 2048 plus shared raw/branch 4096); its earlier FF phase is
6144 and later projection/residual phase 4096. Convolution/GLU and FF2
remain bounded by 6144. The residual/layer coexistence guards, dispatcher
preflight and independently validated workspace field-13 descriptor all
therefore use 6144 for positive audio layers; layer-zero remains 512.
Actual sums, production shadows, suspended frames and all other partitions
are still accounted separately.

Independent verification must cover every raw-word last-use/store boundary,
including concurrent different-address reads, first/last output stalls,
partial/error drain, reset, held completion, cache rebuild after a previous
hit, both precisions, complete numerical comparisons and actual/shadow
allocation reports. These are required tests, not executed results.

This closes the duplicate private raw/output bank and early cache-reservation
milestones, not suspended-history feasibility. Using the earlier conservative
33221-byte native controller census gives
`86016-33221-6144 = 46651` bytes before native frames, scalar slots, memo
and retained features. Four six-slice frames plus scalars still require
49664 bytes. Full native/fallback reconciliation and a genuine solution
to suspended history remain necessary before the reserved static check
and independent-Verifier handoff. No command, elaboration, simulation,
synthesis, preparation harness or receipt ran for this increment.

### Prior increment: audio feed-forward last-use release

The normalized entering vector in `audio_feedforward.working` is needed
through the last MLP row, not through post-MLP normalization or residual
output. The worker now clears both its working reservation and visibility
at the successful final `MLP_ADVANCE` edge. That edge follows the last row's
accepted result, error check and branch write. Its source-response FSM is
idle before the result is accepted. Post-phase callbacks use the distinct
branch bank, and final residual reads use only raw and branch banks.
No numerical boundary, row order or stored result changes.

The raw and branch reservations remain a conservative 4096 bytes for the
whole accepted task; the extra 2048-byte working reservation is independent.
Errors before its last-use edge keep it charged until done-response
retirement. Errors after that edge do not resurrect a dead vector. The
new flag participates in `CONTROLLER_BITS`; its addition changes the
feed-forward census from 481 to 482 bits with external vector RAM and
529 to 530 bits with local RAM, retaining the existing 61/67 rounded
controller bytes before the separately reported FP primitive.

Parent reservations now follow their actual first writes instead of task
acceptance. `audio_pre_attention` reserves its working bank on the first
accepted feed-forward output, before the later clamp/store stages.
`audio_attention_residual` reserves raw residual storage when the first
well-formed raw pre-attention beat is written in `PRE_WAIT`. Standalone
cache rebuilds do not overwrite or newly reserve the raw residual.
Neither change releases partially written buffers on an error or stall.
Prospective admission still covers the full private envelope before any
child starts; a deferred live flag is not an unadmitted allocation.

| Pre-edge event / phase | Post-edge live-vector consequence |
| --- | --- |
| Feed-forward job acceptance | Reserve raw, branch and working, 6144 bytes; reset clears all reservations and validity |
| Final successful MLP advance | Branch is complete; release working and invalidate its visibility; keep raw+branch, 4096 bytes |
| First feed-forward output acceptance | Pre-attention reserves its 2048-byte working bank before its first write; this cannot precede working's release |
| First valid raw pre-attention beat in `PRE_WAIT` | Outer residual reserves and writes raw, 2048 bytes, on that edge |
| Output or child completion stalled | Keep all remaining reservations and stable numerical response payloads |
| Feed-forward or parent failure | Retain every still-live reservation through the existing child drain and held completion; do not zero reports merely on error |
| Done-response retirement | Clear the corresponding reservations and visibility; physical RAM remains separately disclosed |

This gives the following source-derived connected private-vector bounds:

| Connected subtree / phase | Bound in bytes |
| --- | --- |
| Replay heads, before feed-forward output | Normalized-source cache 2048 + feed-forward 6144 = 8192; pre-attention's working bank has no live data/reservation yet |
| Replay heads, during feed-forward output | Cache 2048 + pre-attention working 2048 + feed-forward raw/branch 4096 = 8192 |
| Frame-backed post-attention, before output | Feed-forward 6144; pre-attention working and outer raw are not yet reserved |
| Frame-backed post-attention, during output | Outer raw 2048 + pre-attention working 2048 + feed-forward raw/branch 4096 = 8192 |
| Post-attention projection, normalization and residual output | Outer raw+working, 4096; pre-attention has retired before outer working allocation |
| Convolution/GLU and feed-forward2 | Existing conservative 6144-byte bounds remain |

Replay residual/layer overrun guards, dispatcher audio-layer preflight and
the workspace's independently validated field-13 descriptor all now use
8192 bytes rather than 10240. Audio layer zero remains 512 bytes. Full
child-sum observations, coexistence guards, actual/shadow admission,
workspace frames, memo, scalar slots and controller accounting remain
separate; no phase-selected child report hides a suspended consumer.
Physical array sizes and the six-slice suspended-history bound are unchanged.

With the previously enumerated native controller census of 33221 bytes,
minimum-context E2B leaves `86016-33221-8192 = 44603` bytes before native
frames, scalar slots, memo and retained features. This is a private-storage
improvement, not proof of native fit: four six-slice frames plus scalar
slots still require 49664 bytes. The changed allocation-ledger census
also still needs whole-system reconciliation for the fallback 64 KiB
working partition. Neither strict savings threshold is changed.

Independent verification must cover both RAM configurations, FF1/FF2,
both precisions, the last-MLP/source-response boundary, before/after-release
errors, first and last output stalls, malformed streams, cache rebuild,
reset and held completions. It must compare the complete arithmetic and
child-sum reports, including the 6144-to-4096 release and the 8192-byte
envelope; lower reports alone do not prove numerical correctness.

Saved RTL changes: `anvil_en1_audio_feedforward.sv`,
`anvil_en1_audio_pre_attention.sv`, `anvil_en1_audio_attention_residual.sv`,
`anvil_en1_replay_audio_residual.sv`, `anvil_en1_replay_audio_layer.sv`,
`anvil_en1_replay_execute.sv` and `anvil_en1_replay_workspace.sv`.
Source inspection/editing only; no elaboration, simulation, synthesis,
preparation harness or receipt ran. Suspended-history feasibility and
complete allocation reconciliation remain open before static elaboration
and independent-Verifier handoff.

### Prior increment: explicit fallback working-state partition

The admitted fallback ceiling has separate frame, memo, scalar-continuation
and arithmetic/control/resident partitions. The previous connected allocation
guard checked the complete 1 MiB ceiling but did not separately enforce the
last partition's 65536-byte ceiling. Unused scalar-partition space must not
silently enlarge that working-state allowance.

The two phase-dependent workspace reductions in `allocation_ledger` now
classify the same coherent actual/shadow sample as follows:

| Sample mode | Reduction before the sixth register | Sixth-register operation and public result |
| --- | --- | --- |
| Ordinary | Complete equivalent terms except frontier field 0, ring field 1 and resident field 18 | Subtract the independently summed native scratch with checked underflow; expose `text_workspace_bytes` and `text_workspace_shadow_bytes` |
| Fallback | Complete equivalent terms except workspace payload field 5 | No native-scratch subtraction; expose `fallback_working_bytes` and `fallback_working_shadow_bytes` |

Field 5 is only the workspace's separately charged live frame-vector,
memo-vector and complete scalar-slot payload. Its descriptor registers,
visibility/progress masks and other metadata are **not** field 5 and remain
in the fallback working sum. The latter also retains resident words, native
private vectors, every reported controller, arithmetic state and integration
state. Any unexpectedly retained frontier/ring bytes remain included,
in addition to the existing overlap/total checks. The complete equivalent
sum still contains field 5 in both modes; nothing is removed from the total
or reclassified as free capacity.

The ordinary-only outputs are zero for a fallback sample and the
fallback-only outputs zero for an ordinary sample. Both output pairs retain
the six-register sample latency and the same model/mode/error tags. Native
subset consistency and all reduction overflow checks remain active in both
modes; native-subtotal subtraction/underflow apply only in ordinary mode.
The elaboration-time reduction-sharing identities distinguish each
mode-conditioned leaf from unconditional payload leaves, so an optimized
node cannot reuse a differently classified sum. Added registered nodes are
included automatically by each ledger's existing `registered_nodes()` census.
The older <=32200-byte ordinary-text estimate below predates this census
change and is not a current full-hierarchy capacity certificate.

The prospective admission engine and the top's independent observation
guard consume both new outputs. In fallback they require actual and
production-shadow working bytes <=65536, shadow >=actual, the unchanged
complete ceiling <=1048576, and the unchanged strict `20*P < 9*B`.
Admission still precedes the requested allocation and uses the existing
bounded unpinned-memo eviction/retry mechanism. Denial or an observed
overrun remains an implementation failure; these checks do not authorize
returning a capacity error for legal work. Ordinary model-specific text
limits and native scratch limits are unchanged.

Independent verification must cover 65535/65536/65537 working bytes in
both actual and shadow reports, a complete total below 1 MiB with an
overlarge working partition, field-5 exclusion with its metadata retained,
native private/controller and resident inclusion, alternating sampled modes,
stalls/clear/reset, arithmetic overflow and shadow inconsistency. It must
also continue independently checking the frame, memo and scalar partitions;
this working-state classification does not replace those checks.

Saved RTL changes: `anvil_en1_allocation_ledger.sv`,
`anvil_en1_allocation_admission.sv`, `anvil_en1_allocation_guard.sv` and
`anvil_en1_top.sv`. Source inspection and editing only; no elaboration,
functional experiment, synthesis, preparation harness or receipt ran.
This closes a missing enforcement surface, not legal-workload feasibility.
Suspended audio storage, complete per-instance accounting and ordinary/
fallback fit still require closure before the reserved static check and
independent-Verifier handoff.

### Retained closure assessment: finite suspended-audio storage bound

The following is a source-derived upper-bound analysis, not a simulated
allocation trace or a claim that every maximum is simultaneously reachable.
It closes the enumeration of the current audio suspension states, but does
not close their feasibility. In particular, predecessor-first scheduling
does not establish a one-frame bound for historical dependencies.

Let `D` be `replay_audio_history.distance_hold`, with
`0 <= D <= min(query_token,4)`. Histories numbered `0..D-1` have already
completed, and their consuming moves have committed. They occupy `D`
different retained slices: bank 0/slice 2, then bank 1/slices 0,1,2.
The current residual uses bank 0/slice 0 for its entering vector and bank
0/slice 1 for its attention output. These regions are disjoint.

| Successful yield boundary | Potentially reserved audio vector slices in that frame | What permits release |
| --- | --- | --- |
| Predecessor binding, before its copy starts | `D` retained histories | Histories still feed this frame's convolution; no existing release boundary applies |
| Attention dependency, before any output pair | `D+1`: retained histories plus entering vector | The entering vector is still read by query/source reconstruction and the post-attention residual |
| Attention dependency, after an output pair | `D+2`: retained histories, entering vector and partial head output | The numerical continuation resumes that output, rather than restarting or reconstructing it |
| Completed residual, before attention-slice release retires | At most `D+2` | Only the successful registered release response makes the head-output slice reusable |
| Nonfinal history relocation | `D+1` | The consuming move transfers, rather than duplicates, the current residual reservation |
| Final completed history | At most five residual slices after head-output release | The convolution must consume the retained histories before their existing release loop |

Partial output is not necessarily publicly readable, but its reservation
and continuation remain live. A yield is not a vector-pop, generation
invalidation or permission to clear that reservation. A failed operation
retains its charged reservations until the existing unwind/invalidation.
The raw/head yields above come from `replay_audio_heads`; the history
wrapper translates their frame token to its own query token without
changing the corresponding backing slice or reservation.

The scheduler's nested audio return record stores a target layer 1..12.
On a historical miss it pushes a layer-zero chain, retaining the consumer.
That chain pops each completed predecessor before pushing its successor,
but a successor can itself yield. Every such additional suspended consumer
has a strictly lower encoder layer than its parent. Thus one audio descent
has at most twelve positive-layer audio frames and one active layer-zero
frame, excluding already suspended text/feature consumers. It does not have
only one live audio frame. The twelve positive-layer frames alone have a
conservative vector ceiling of
`12 * 6 * 2048 = 147456` bytes, plus their scalar slots. Actual and
production-shadow audio widths are both 1024 BF16 elements, including in
the compact build; compact text geometry cannot shrink this amount.

For comparison, the matched E2B minimum-context baseline is
`1024*(28*16+14*16) = 688128` bytes. Its native allowance is
`min(1048576,688128>>3) = 86016` bytes. Subtracting the current
33221-byte native controller census and 10240-byte active-audio private
allowance leaves 42555 bytes for **all** native frames, scalar slots,
memoized vectors and retained features. Four six-slice frames alone would
need `4*(12288+128) = 49664` bytes. This comparison does not assert that
four such frames were observed, or prove that the entire conservative
ceiling is reachable. It does establish that the current per-frame bound
and rank/chain argument do not prove the admitted minimum-context fit.
Memo eviction can remove memo entries, not these suspended frame slices.
The separate 32768-byte text workspace allowance is not extra native
scratch and cannot be borrowed without retaining its actual classification.

Consequently, do not hand this source version off as a completed design,
reduce the frame ledger to a selected active worker, assume memo hits, or
turn a prospective grant denial into error 7 for otherwise legal work.
A real repair must either establish a tighter reachable-state bound for
the connected schedule or reduce retained state with connected streaming/
rematerialization. Simply reversing history traversal, discarding completed
histories on yield, or restarting a parent after every miss is not such a
repair: the former supplies no nested-state proof, and the latter changes
the continuation or needs a separate finite-progress proof under eviction.
Any replacement must preserve ascending reduction order, BF16
materialization, the live partial head, original-input reconstruction,
backing-response retirement and all actual/shadow allocation charges.

This assessment used source reads/searches only; no functional probe,
allocation measurement, elaboration, synthesis or receipt was produced.
The reserved static elaboration remains unused. Native minimum-context
feasibility, whole-system deep-frame/fallback partition reconciliation and
independent verification remain open.

### Prior increment: frame-backed audio private-bank reconciliation

The connected replay residual instantiates `audio_attention_residual` with
`FRAME_HEADS=1`. In that mode the head projection reads the real workspace
head vector. The worker never writes or reads its local `heads` or
`normalized_source` arrays: both accesses are guarded by `!FRAME_HEADS`.
Its job-acceptance assignment nevertheless marked the unused normalized
cache allocated. That assignment now matches the existing cache-rebuild
assignment, `cache_allocated <= !FRAME_HEADS`. Standalone mode retains its
original allocation and numerical behavior.

The complete source-derived live-vector envelope for this connected instance
is 10240 bytes, rather than the previous conservative 16384-byte envelope:

| Phase / transition | Live private storage, excluding separately charged workspace |
| --- | --- |
| Job acceptance / pre-attention start | One 2048-byte raw-residual reservation; no local head/cache reservation |
| Pre-attention feed-forward | Outer raw 2048 + pre-attention working 2048 + feed-forward's three 2048-byte banks = 10240 bytes |
| Pre-attention normalization / held completion | Outer raw 2048 + pre-attention working 2048 = 4096 bytes; feed-forward releases its banks when its done response is accepted, before normalization starts |
| Successful pre-check / output projection | Pre-attention has retired; outer raw 2048 + output working 2048 = 4096 bytes |
| Output norm / residual addition / held completion | The same raw and working banks stay charged through output stalls and the held done response |
| Failure | Keep all still-allocated banks charged through the existing child drain and response retirement; no early release or success-shaped fallback |
| Active reset | Allocation/visibility flags and public reports clear through existing reset behavior |

`audio_pre_attention` reports its own working reservation **plus**
`audio_feedforward.vector_live_bytes`; the latter charges all three banks
until its response retires. `audio_attention_residual` adds that whole
child report to every live outer allocation flag. No selected-child mux or
inferred phase value replaces these independent observations. Native MLP,
norm, projection and clamp descendants in this branch contain scalar
arithmetic/controller state, already reported separately, not additional
unreported vector banks.

The replay residual's post-phase overrun guard and audio layer's history
overrun guard now both enforce 10240 bytes, while preserving their
pairwise-coexistence checks. Replay dispatcher field-13 admission and the
workspace's independently validated field-13 descriptor both use 10240
bytes for audio layers 1..12. The complete audio private maximum is thus
max(10240 replay heads, 10240 post-attention, 6144 convolution/GLU,
6144 feed-forward) = 10240 bytes. Layer-zero subsampling stays 512 bytes.
Prospective admission and the actual child-sum observer remain separate;
an observed overrun is still error 7, never a silently clipped report.

This removes a false 2048-byte live-bank reservation and tightens the
conservative admission envelope by 6144 bytes. It does not remove physical
RAM, controller declarations, frame slices, scalar continuations, memo
entries or preserved modality features. Applying only this admission delta
to the previously documented 36411-byte minimum-context E2B remainder
leaves 42555 bytes before those other live native allocations. Neither
remainder establishes that legal deep replay fits.

Independent verification must compare both FRAME_HEADS configurations,
both precisions, pre-attention raw/normalized stream ordering, child
completion and output stalls, failures in each private phase, and reset.
It must check the actual child sum against the grant and account every
suspended history slice separately. The six-slice suspended-history
ceiling, native/deep-frame/fallback feasibility and final per-instance
reconciliation remain open. No diagnostic, simulation or synthesis was
run; the reserved static elaboration remains pending design closure.

### Prior increment: consuming audio-history relocation

The packed audio-history worker now moves each nonfinal completed residual
from scratch bank 0/slice 0 to its existing retained-history destination.
It no longer reserves a second complete vector while copying the first.
The numerical residual, history order, history destinations, final scratch
residual and subsequent convolution callbacks are unchanged. This removes
the copy-phase duplicate, not the six-slice worst-case suspension envelope.

The internal workspace operation is `op=7,target=3`. It requires the complete
current top-frame descriptor, domain 2, layer 1..12, component/data zero, and
destination bank 0/slice 2 or bank 1/slice 0..2. The source is always that
frame's bank 0/slice 0. No new top-level port, vector bank, continuation
field, external-memory request class or model operation is introduced.

| Pre-edge / post-edge boundary | Relocation behavior |
| --- | --- |
| Request acceptance | Register the descriptor through the existing workspace request path; no backing access occurs on acceptance |
| Validation | Reject malformed fields with error 5; reject a stale/non-top frame, uncommitted/partial source, occupied/reserved/partial destination or invalid actual/native/shadow accounting with error 7 |
| Registered tag check / ownership transfer | Atomically clear source reservation/visibility/progress and reserve the destination without committing its visibility; preserve all four frame payload subtotals |
| Copy read / capture / write | Reuse the existing serialized backing FSM and its registered pair temporaries for all 512 pairs; the one 2048-byte reservation covers the unread source suffix and acknowledged destination prefix |
| Final successful write response | Commit destination visibility only through the existing `VECTOR_COMMIT` stage, then publish the held workspace response |
| Backing failure | Retire the actual response and return its error; neither source nor incomplete destination is readable; the destination reservation remains charged until frame pop or invalidation |
| History continuation | Advance distance only after the successful relocation response; do not issue a separate source release or admit a successor while the move is outstanding |
| Reset / invalidation | Preserve existing backing-generation cancellation and drain semantics; reset clears both source and destination validity |

Source and destination are disjoint 512-word regions. Source contents become
private to the move FSM as soon as the ownership transfer commits; public
frame reads cannot access them. Already copied source pairs are dead rather
than a second live representation. The destination's full reservation remains
charged throughout copy stalls and failures. Scalar `copy_data`,
`backing_result` and response registers retain their existing controller
charges. Since no aggregate payload grows, relocation needs no new capacity
grant and does not evict a memo or bypass a previously required growth grant.
Physical backing capacity is unchanged.

The history worker still releases dead attention output slice 1 before this
move, or before publishing the final residual. Its old pair-data register,
component cursor and release-selection flag are removed; the smaller FSM
encoding removes one more bit, for 46 fewer declared controller bits.
Workspace, scheduler and dispatcher add only wires. The conservative
<=32200-byte E2B C=64 text envelope is retained as an upper bound, not a new
measured allocation claim.

The workspace reports each **accepted backing read** of a history move to
the dispatcher through `history_move_read_event`. The dispatcher adds exactly
four internal source-read bytes per event, including a read whose later
response fails. It does not infer a 2048-byte read from move acceptance.
The history worker no longer reports the eliminated per-pair workspace-read
requests, avoiding double counting. These are internal transfers, not DDR
reads or reduced total external traffic.

Independent verification must cover every destination, full data equality,
source unreadability after transfer, destination unreadability before final
commit, rejected live/partial/stale destinations and sources, non-top moves,
every read/write error and stall boundary, source-read event counts, frame
pop, reset/invalidation, and unchanged yield/resume and convolution results.
Whole-system native/deep-frame/fallback feasibility and the six-slice
suspended-history bound remain open. No elaboration, simulation, synthesis
or preparation receipt was produced in this increment; the reserved static
elaboration remains pending complete design closure.

### Prior increment: predecessor-first replay for every native audio token

The scheduler now uses its ascending-layer audio chain for every legal audio
token, not only token zero. Direct audio roots and missed nested audio
dependencies begin at layer zero of the requested token, then supply each
genuine completed predecessor to the next layer in mode 2. A completed layer
is transferred to memo and popped before its successor is pushed. Text and
bidirectional vision scheduling are unchanged.

This is a dependency-order optimization, not a claim that later audio layers
have no historical dependencies. `replay_audio_history` still evaluates all
present convolution histories. Each attention head still requests its actual
permitted lower-layer tokens through the existing continuation/yield path.
Those dependencies may suspend the active audio frame and enter other audio
chains. On return, the unchanged numerical continuation resumes that frame
before its own result can complete; no historical input is replaced by the
same-token predecessor. Layer-zero work still reconstructs immutable inputs.
Every descent reduces the encoder layer, and every chain successor is bounded
by the saved target layer 1..12.

| Boundary | Later-token chain behavior |
| --- | --- |
| Direct root | Preserve the requested root token and layer limit; start that token at layer zero |
| Nested memo miss | Preserve the original consumer and continuation; store the requested audio layer in return-record bits 163:160 and start the requested dependency token at layer zero |
| Supplied predecessor | Existing input binding validates domain 2, the exact preceding layer, the same query token, length 1024 and a genuine memo slot before copying |
| Historical miss within a successor | Preserve all still-live frame slices and the real head/history continuation; evaluate the requested lower-layer token normally |
| Chain result pop | Validate the returned frame's full metadata, return magic and parent slot; require the completed audio token/layer to match the currently popped frame and not exceed the saved target |
| Intermediate successor | Preserve the consumer return record; pin the completed predecessor during successor admission, then enter mode 2 |
| Target completion | Restore the saved consumer with the actual completed dependency token/layer/slot in mode 1 |
| Backpressure, failure, reset | Keep the existing registered request, drain, error and generation-invalidation paths; no completed vector is inferred from a mode bit |

This retires the initially avoidable same-token ancestor descent for later
audio tokens: a layer-12 request no longer pushes twelve empty same-token
ancestors before reconstructing its layer-zero input. Only one frame of that
particular chain is retained between completed layers. Nested historical
evaluations and their suspended consumers remain fully charged; their total
depth and six-slice storage ceiling have **not** been reduced to one frame.
No new registers, RAM, continuation width or physical-memory saving is claimed;
the conservative <=32200-byte E2B C=64 text declaration envelope is unchanged.

Independent verification must cover direct and nested tokens 0,1,4,5 and
chunk boundaries, layers 0,1,12, both precisions, target memo hits/misses,
real historical yields/resumes during a successor, nested chain return tokens,
memo eviction, stalls, reset and failed backing/input/weight responses. Compare
all numerical outputs and observe actual frame/slice allocations. Whole-system
native/deep-frame/fallback fit and later-token suspended-history storage remain
open; this schedule change alone is not allocation or termination evidence.
No diagnostic was executed and the reserved static elaboration remains pending.

### Prior increment: linear first-token native audio replay

Audio token zero has no historical text/encoder-token dependency: causal
attention sees only token zero and the four absent convolution taps are
positive BF16 zero. Its layer-zero subsampling reconstructs original inputs;
each later audio layer needs only its completed predecessor at token zero.
This property does not apply to bidirectional vision or later audio tokens.
The scheduler now exploits this exact chain for direct domain-2/token-0
roots and for missed domain-2/token-0 dependencies nested beneath another
evaluation. Numerical workers, traversal/reduction order and model geometry
are unchanged.

| Scheduler boundary | First-token audio behavior |
| --- | --- |
| Root validation | Begin at audio layer zero, retaining the requested layer as the existing root limit; ordinary single-token text roots retain their existing linear path |
| Dependency lookup | Look up the originally requested audio layer first; a memo hit resumes its consumer normally |
| Miss / first push | Save the real consumer return record, put the requested audio layer 1..12 in bits 163:160, and push audio layer zero instead of the requested upper layer |
| Completed layer | Perform the existing consuming result-to-memo transfer, retire its actual backing responses, and pop its frame before any successor frame is admitted |
| Intermediate pop | Validate return magic, consumer frame slot, target 1..12, and completed audio domain/token/length/layer; preserve the consumer record and push the next layer in supplied-predecessor mode 2 |
| Successor push | Pin the genuine completed predecessor memo throughout push setup and workspace request/response stalls, as for the existing root-linear path |
| Target pop | Restore the original consumer and its unchanged 160-bit numerical continuation, supplying exactly the requested target memo in resume mode 1 |
| Failure/reset | Use existing error, drain, generation invalidation and cancellation paths; no incomplete layer result or manufactured predecessor can resume a consumer |

Bits 163:160 of the internal 256-bit scheduler return record are now an
audio-chain target (zero means the existing ordinary return). This is not a
change to a worker's public 160-bit continuation. `push_kind=3` denotes
the nested linear successor; its existing two-bit register is sufficient.
The existing workspace-request continuation register carries the original
consumer record to each successor push. No new retained scalar, frame
field, RAM, arithmetic worker or external transaction class is introduced.
The complete descriptor and admission checks remain in force for every
actual frame/memo allocation. Owner/native input and weight traffic still
reflect all real recomputation.

For one direct audio root, this removes up to twelve simultaneously
suspended ancestor frames from the naive layer-12-to-layer-0 descent:
at most one audio evaluation frame is live during the linear chain.
For a nested audio-token-zero miss the already suspended consumer frames
remain charged, but there is at most one additional audio-chain frame.
Each active layer still reserves its actual vectors, scalar slot and
private numerical scratch; completed memos remain charged and evictable,
except for the explicitly pinned predecessor. No reduction of physical
backing capacity or complete-system minimum-context fit is inferred.
The controller declaration census and its <=32200-byte E2B C=64 text
envelope are unchanged because the new conditions use only wires.

Independent verification must cover direct and nested token-zero audio
requests at layers 0,1,12, target memo hits/misses, both precisions, real
intermediate pop/push and memo eviction, backpressure and reset/error at
every transfer, and unchanged numerical outputs. It must observe bounded
audio frame depth rather than accepting a mode bit. Later-token six-slice
audio suspension, whole-hierarchy native/fallback partition feasibility
and actual mode-transition liveness remain open design milestones. No
functional/synthesis probe or preparation receipt was created; the one
reserved static elaboration remains pending design closure.

### Prior increment: consuming completed-result memo transfer

The scheduler's completed-result handover now uses an explicit consuming
variant of the existing workspace `op=3,target=2` frame-to-memo operation.
`req_data=0` retains the ordinary nonconsuming copy below. `req_data=1`
transfers the committed result from the top frame to memo; other values
reject with error 7 before selecting/replacing a destination or issuing
backing traffic. The complete source descriptor, current top slot,
reservation, completed visibility, absent partial-pair progress and
actual/native/production-shadow subtraction bounds must all validate.
No numerical worker, tensor format, top-level port or external-memory
protocol changes.

| Consuming-transfer boundary | Registered ownership and accounting |
| --- | --- |
| Source validation | Preserve its existing full-vector reservation and visibility throughout memo selection, eviction retries and prospective admission stalls |
| Prospective total | After the existing registered grant sums, subtract exactly the source vector from whole-workspace actual/shadow totals and, for native domains only, native actual/shadow totals in a separate `GRANT_MOVE_ADJUST` stage |
| Accepted grant commit | Recheck source accounting; atomically remove source vector reservation/visibility/progress and its frame subtotal while establishing the full pending-memo charge |
| Pair read/capture/write | Keep the uncopied source suffix and acknowledged destination prefix as one live vector under that pending charge; consumed source pairs are dead and cannot be read through the frame interface |
| Scalar temporaries | Existing `backing_result`, `copy_data` and request/response registers remain separately charged by the controller census; no uncounted copy register or vector is added |
| Last acknowledged pair | Commit destination tag/visibility and move the pending charge to committed memo bytes without changing total live bytes |
| Copy failure | Retire the actual failing backing response, discard the pending representation, leave both source vector and incomplete memo unreadable, and return the actual error; the scheduler invalidates rather than resuming from discarded data |
| Scheduler continuation | Pop the consumed frame only after the successful memo response; pop counts its remaining reservation bits and therefore cannot subtract the moved result twice |

This is a destructive logical transfer with real backing reads/writes, not
an address alias or an early successful result. While a pair is in flight,
the source suffix and destination prefix are disjoint logical components;
their complete padded vector size remains reserved. The physical source
and destination RAM capacities are still disclosed unchanged. Requests
cannot interleave with the transfer. Failed admission can evict ordinary
eligible memo entries but never removes source visibility before the
successful grant commit. Reset/invalidation retain their existing drain
and generation rules.

Compared with retaining a complete source plus a complete pending
destination, this removes one dead/transferring-vector overlap from the
scheduler path: 3072/5120 production text bytes, 1536 vision bytes or
2048 audio bytes, with the corresponding compact and production-shadow
charges kept distinct. It does not remove live suspended inputs or claim
that legal deep replay fits. No register or state-width increase is needed;
the conservative ordinary-text declaration envelope remains <=32200 bytes
for E2B C=64.

A read-only scalar declaration scan found no additional unaccounted
sequential scalar after tracing packed `$bits` census expressions,
read-register wire aliases, generated RAM readback charges and the
separate occupancy metadata reports. The apparent `tensor_shape.rank_hold`
hit is combinational comparison logic, not a sequential assignment.
This lexical reconciliation is not an elaborated per-instance census,
memory-liveness execution or proof of native/deep-frame feasibility.

Independent Verifier must distinguish both transfer variants, exercise
every backing-read/write failure and stall boundary, reject malformed or
non-top moves without source consumption, verify source unreadability
after a move, preserve source readability after a nonconsuming copy,
compare every destination component, and observe actual/native/shadow
charges through pending/commit/failure/pop and memo eviction/regeneration.
No functional/synthesis probe or preparation receipt was created.
The reserved static elaboration remains pending whole-design closure.

### Prior increment: completed-layer frame liveness

The existing checked `op=7,target=2` workspace release is now wired to the
last-consumer boundaries in all three nonzero-layer replay workers. Numerical
operations, head order, continuation layout, output-bank selection and private
admission envelopes are unchanged. Release requests use the current frame's
complete descriptor, component/data zero, and slice zero except for the packed
audio history slices below. They do not address or evict a dependency memo.

| Worker / last successful consumer | Dead frame slices released | Surviving result |
| --- | --- | --- |
| Text post-attention/MLP/PLE worker | Bank 0, slice 0, entering layer hidden vector | Bank 1, slice 0 |
| Vision post-attention/MLP worker | Bank 0, slice 0, entering encoder-layer vector | Bank 1, slice 0 |
| Audio convolution, after its complete output has been acknowledged | All retained historical residual slices, but not the convolution result | Bank 0, slice 0 |
| Audio feed-forward, after its complete output has been acknowledged | Bank 0, slice 0, convolution result | Bank 1, slice 0 |
| Audio final normalization, after its complete output has been acknowledged | Bank 1, slice 0, feed-forward result | Bank 0, slice 0 |

For audio, let `D=min(query_token,4)` and let the existing history count be
`D+1` at convolution completion. For `D=0` there is no history release.
Otherwise the count is reused as a descending release cursor: count 5/4/3
selects bank 1 slice 2/1/0, and count 2 selects bank 0 slice 2. Thus only the
`D` slices actually copied by the history worker are released. Count decrements
only after each successful registered release response. The final historical
residual in bank 0 slice 0 has already been consumed and overwritten by the
convolution output, so that slice must not be released at this boundary.

Each worker retires the numerical child's done and every output pair-write
response before requesting a release. It then uses send, response-capture and
registered-error-check states. A stalled request keeps its complete descriptor
stable; a stalled workspace response prevents further release or successor
start. A failing release stops advancement and propagates the actual workspace
error. Successful text/vision completion is not published until release has
retired. Audio starts its next numerical phase only after its preceding
releases have retired. Reset follows the existing workspace generation/visibility
invalidation rules. No error or dependency-yield path releases live or partial
vectors. The text PLE bank is also marked dead at successful-child retirement
(or terminal child error), when that child can no longer read it, rather than
retaining its live charge through the subsequent workspace release handshake.

Consequently each successfully completed layer frame now retains just its
actual result vector before the scheduler copies it into memo and pops it.
This removes a dead 3072/5120-byte production text input, a dead 1536-byte vision
input, and the dead audio histories/interphase input at their actual lifetime
boundaries. Fresh reuse still obtains the workspace's prospective whole-vector
grant. None of these removed charges is physical RAM removal or permission to
omit still-live suspended inputs. Existing state widths and captured error/count
registers accommodate the release sequencing without additional scalar storage.
The conservative ordinary-text declaration envelope remains <=32200 bytes at
E2B C=64; no new reduction to that envelope is claimed.

This closes the completed-layer dead-input lifetime milestone, not native
deep-suspension feasibility. A yielding audio history can still retain six
live slices. The minimum-context native-scratch, full fallback partition,
memo eviction/regeneration and mode-transition obligations remain open.
Read-only declaration inspection reconfirmed 94 module files (92 with clocked
processes) and 52 array declarations in 31 files. This is a lexical inventory,
not per-instance elaboration, allocation execution or a new proof of fit.
No functional/synthesis harness or preparation receipt was created. Static
elaboration remains reserved until complete design closure. Independent
Verifier must cover successful release/regrant, each release-error position,
request/response stalls and reset, audio `D=0..4`, final-bank preservation,
and unchanged numerical/reference, allocation and traffic requirements.

### Prior increment: compact directory validation and explicit dead-vector release

The tensor-image ABI and external reader schedule are unchanged. Each directory
reader still accepts all sixteen header words, all sixteen current-entry words,
and six words per prior-entry comparison. Memory-error retirement, full-directory
validation, duplicate/overlap detection and response holding remain unchanged.
Only the retained representation of those words changes:

| Reader state | Retained bits | Validation of discarded words |
| --- | --- | --- |
| Header | Image bytes 64, directory count 32, directory offset 64 | Sticky `header_word_error` checks magic, version, model, precision, 64-byte entry size and all six reserved words as each registered word retires |
| Current entry | First eleven words, 352 bits | Sticky `entry_word_error` checks all five reserved words |
| Prior entry | Identity 32, offset 64, length 64 | The reread format word was not used by the prior-pair comparison; the original full entry validation remains mandatory |

Both sticky flags reset for a new job; the entry flag additionally resets at
each `ENTRY_START`. They are checked at the original final validation states,
not as early exits. Thus a later accepted failing memory response retains its
original error priority. All retained fields are overwritten by the complete
corresponding read before validation; reset contents cannot certify an entry.
No payload, tensor directory or numerical result is supplied by initialization.

The directory's complete local census decreases from 2147 to 1605 bits,
269 to 201 rounded bytes: 542 removed bits and 68 removed bytes per instance.
A read-only literal-instance traversal found 56 directory readers below the
native top. This subtree contains no generated directory replication.

| Nonoverlapping instance subtree | Directory readers | Connected controller reduction, bytes |
| --- | --- | --- |
| Ordinary frontier executor | 3 | 204 |
| Owner replay, inside binding | 1 | 68 |
| Replay original input | 1 | 68 |
| Replay text worker | 4 | 272 |
| Replay vision worker | 8 | 544 |
| Replay original audio input | 7 | 476 |
| Replay audio layer | 25 | 1700 |
| Replay audio feature | 3 | 204 |
| Replay image feature | 4 | 272 |
| Total | 56 | 3808 |

The replay dispatcher contains 52 of these instances; binding contains 53.
The native-reconstruction subset contains 48 and therefore decreases by
3264 bytes, from the preceding 36485-byte census to 33221 bytes.
The remaining eight instances decrease the non-native text partition by
544 bytes. Applied to the preceding conservative E2B ordinary-global bounds,
this gives <=31673/31690/32200 bytes for C=1/3/64, respectively.
These are connected source-derived deltas, not observed legal-case fits.
The local directory declaration audit found no omitted or duplicate scalar
census term. A separate literal connection scan found 266 child declarations
across the 94 module types. Its 32 unconnected controller-detail outputs all
belong to `replay_binding.replay`: the binding consumes that child's complete
`reported_controller_bytes` and native subset instead. Detail outputs and
the selected-worker alias must not be added again to that aggregate.
This scoped reconciliation does not close every other module's accounting.

Vision private admission now uses a guarded 4608-byte maximum, replacing
the 7808-byte sum of its serialized 1664-byte QKV tile, 1536-byte O output
and 4608-byte post-attention phases. `replay_vision_layer` observes their
actual sum, rejects pairwise coexistence and checks the tile/post bounds
through its existing sticky branch-RAM fault. Tile results retire before
head completion; only then can O storage become allocated. `POST_START`
releases O storage on accepted post start, before post's validation allocates
its banks. The dispatcher and workspace agree on the new descriptor value.
Physical RAM, suspended frame vectors, memo and controllers remain separately
charged.

#### Frame-vector release operation

The internal workspace/scheduler interface adds `op=7,target=2` to release one
complete, dead frame-vector slice. Model, generation, domain, layer, token,
length and slot must match the current live frame. `bank` selects the frame
bank; scalar index selects slice 0, or audio slice 0..2. Component and data
must both be zero. Other targets retain their previous meanings.

| Release boundary | Behavior |
| --- | --- |
| Descriptor check | Reject malformed fields with error 5 before any backing access |
| Registered tag/visibility check | Require a reserved, completely committed slice with no partial pair; reject stale, missing or underflowing state with error 7 |
| Commit | Atomically clear reservation, visibility and pair progress and subtract the actual/shadow vector bytes from frame totals and the matching native subset |
| Response | Use the existing registered publication/held-response path; no backing read/write or external transaction |
| Later reuse | A new write must obtain the existing prospective vector grant before its first backing write; stale RAM contents remain unreadable |
| Pop/invalidation | Count only the remaining reservations; never subtract a released slice twice |

`replay_audio_history` now releases packed bank-0 slice 1 after successful
residual completion: its complete attention vector is dead once that residual
has consumed it. For each nonfinal historical token, it copies the residual
to its retained history slice and waits for the final successful copy response
before releasing bank-0 slice 0. Only an accepted successful release response
permits the next residual job. The final residual stays in slice 0 for the
light-convolution consumer. Yield and error paths do not release live or
partially filled vectors. The history controller adds two declared bits
(state width and release selector) but remains 114 rounded bytes.

This removes dead vector reservations at actual lifetime boundaries; it does
not reduce the worst-case six-slice suspended audio frame ceiling. Original
predecessors, partial attention and accumulated histories may still coexist
on a dependency yield. With the new native controller census, minimum-context
E2B scratch leaves 36411 bytes after the audio private envelope, or 48187 after
the vision private envelope, before retained features, native frame vectors,
scalar continuations and memo. No legal deep-frame fit is inferred from those
remainders. The unresolved milestone is a finite legal suspension/liveness
analysis and, where needed, further genuine streaming/rematerialization rather
than rejecting a legal request with error 7.

Saved changes: `tensor_image`, `replay_vision_layer`, `replay_execute`,
`replay_workspace`, `eval_schedule` and `replay_audio_history`, plus the design
documents. Tools used: view, rg, glob, apply_patch and read-only Bash/Python
source inspection. No static elaboration, simulation, synthesis, preparation
harness or receipt ran. The reserved static elaboration remains unused until
design closure. Independent Verifier must exercise discarded header/entry
word corruption, memory-error priority, release/regrant, stale/read-after-release,
partial/error paths and the unchanged complete allocation/traffic obligations.

### Current increment: scalar phase aliases and guarded audio phase maximum

The ordinary attention-output projection uses two existing 32-bit registers
instead of additional operand registers. `rotary_data_hold` holds the converted
attention component and then its separately rounded product. `scalar_hold`
holds the fetched O weight. These aliases exist only in `ATTENTION_WAIT`:
all RoPE writes have retired before attention starts, and the layer scalar
is fetched only after attention, feed-forward and PLE have completed.
Conversion/product results and the weight are written by the existing main
sequential controller on their accepted successful responses. The output
sequencer owns only its state, error and accumulator; no register has two
sequential drivers. Errors drain through the existing output path.

The output row register now has `$clog2(MAX_H)` bits (12 production, 3 compact).
The selected model's validated H bounds it; comparison against the full-width
hidden length occurs before the last-row increment. External projection
descriptors and tensor row indices remain 32 bits. No arithmetic precision,
reduction ordering, vector lifetime or handshake latency changes.

The full/post workers' own external-vector controller counts are respectively
2021/2005 bits in production, or 253/251 rounded bytes. Compact counts are
2012/1996 bits, or 252/250 bytes. Compared with the immediately preceding
source, these save eleven rounded bytes in each of the two connected
production instances (twelve each in compact). Applying only that proven
declaration delta to the previous conservative E2B ordinary-global envelope
gives <=32217/32234/32744 bytes for C=1/3/64, leaving >=551/534/24 bytes.
This remains a conservative source-derived envelope, not an observed fit.

Native audio's private preflight reservation is now 16384 rather than 38912
bytes in both the replay dispatcher and workspace descriptor validator.
The prior number summed serialized children. Suspended workspace vectors,
their scalar slots, completed memo entries and every controller remain
separately charged; none is released or reclassified by this change.

| Private audio phase | Conservative live-bank bound | Release before successor |
| --- | --- | --- |
| Replay heads, including normalized cache and pre-attention | 10240 bytes | Child `PUBLISH` clears cache/private allocation flags before its held done response is accepted |
| Post-attention residual, including its pre-attention child | 16384 bytes | The same release-before-response rule precedes the parent's post-check/next phase |
| Light convolution/GLU | 6144 bytes | Child publication releases banks before the parent starts feed-forward |
| Feed-forward | 6144 bytes | Child publication releases banks before final normalization |

`replay_audio_residual` observes the **sum**, not a selected-child mux.
It rejects heads/post coexistence or either child exceeding its listed bound
with the existing sticky error 7. `replay_audio_layer` additionally checks
history/convolution/feed-forward pairwise exclusion and their individual
bounds through its registered allocation/RAM-fault path. The dispatcher
still reports `max(granted envelope, observed complete child sum)` and
latches an overrun. Thus the prospective allocator reserves the maximum
while actual overlap cannot disappear from the observation ledger.
Physical RAM reports are unchanged: this reduces a live reservation, not
the number of instantiated memory bits. No new state register or spill
path is introduced.

At E2B's smallest padded context the native-scratch ceiling is 86016 bytes.
The preceding 36485-byte native-controller census and the new 16384-byte
private envelope leave at most 33147 bytes for all other native state.
That remainder is **not** an approved stack allowance: retained features,
PLE/embedding, native frame vectors/scalars and memo entries all consume it.
Deep native dependencies, whole-fallback partition feasibility and actual
eviction/regeneration/transition execution still need closure.

#### Declaration-name and RAM-read alias reconciliation

A repeated read-only scan of all 94 RTL files finds 3013 internal scalar
declaration occurrences and the unchanged 52 array declarations, excluding
function locals and ANSI ports. The same 39 occurrences without a direct
census-name reference resolve as follows; a generated occurrence is not
assumed to be a single physical instance.

| Declaration exception | Existing charge or non-storage classification |
| --- | --- |
| Ledger's two generated `value` declarations | `registered_nodes()*NODE_BITS`, including shared/zero-node elimination and output-register multiplicity |
| Full/post worker bank `read_q` | Four 16-bit read aliases in the local census, removed when external-vector backing is selected; private output-bank read register adds 16 only in full mode |
| Embedding bank `read_q` | `input_q/ple_q`, removed in external-vector mode |
| Audio feed-forward's three and light-convolution's two local read registers | Explicit conditional 48/32-bit terms; absent in external-vector mode |
| Audio GLU `read_q` | Conditional local `bank_q` charge |
| Final-head `payload_q` | `normalized_q` charge; external-payload mode conservatively retains that constant-width term |
| Frontier/ring/cache `occupied` masks | Their separate visibility/resident metadata expressions |
| Frontier executor private hidden `read_q` | `hidden_q`; in integrated external-hidden mode this charges the native parent's `ordinary_hidden_q` instead |
| Native parent's four phase-bank `read_q` registers | The 64-bit phase-bank readback term in native own state, once across all clients |
| Owner-tile `input_ram_q` | `input_q`; streaming-source mode conservatively retains the constant-width term |
| Replay dispatcher's two embedding-bank `read_q` registers | Conditional 32-bit dispatcher term; absent with external embedding backing |
| Replay dispatcher's three native-bank `read_q` registers | `native_vector_rdata` in `NATIVE_VECTOR_BITS`, once, not once per consuming child |
| Replay audio layer local vector `read_q` | Conditional 48-bit own-state term; absent when connected to dispatcher backing |
| Replay vision layer projected `read_q` | Conditional `projected_q` charge; external branch backing is charged at the dispatcher |
| Vision post-layer branch `read_q` | Conditional 16-bit local branch-read term |
| Replay attention `scalar_write_data` | Combinational write mux, not stored state |
| Fourteen tensor-shape temporaries | Combinational shape/format decoder, not stored state |

The scan finds no repeated direct `$bits` scalar-name term in a local
census. The registered-output scan's remaining public `reg` declarations
are combinational request/checkpoint muxes, not additional retained state.
This closes the listed declaration-name exceptions; it does not certify
every literal/generate child-report multiplicity or all array liveness.
Whole-hierarchy per-instance reconciliation remains necessary.

Changed RTL: `asym_attn_ple`, `replay_execute`, `replay_workspace`,
`replay_audio_layer` and `replay_audio_residual`. Source inspection used
view, rg and read-only Bash/Python; edits used apply_patch. No static
elaboration, simulation, synthesis, diagnostic harness or preparation
receipt was produced. The reserved static elaboration remains unused.
Independent verification and hardware acceptance remain pending.

### Current increment: streamed attention projection and shared ledger stages

The ordinary full-text worker now retains the H-element BF16 attention-output
projection, not the Q*D-element concatenated attention tile. For each output
row, it recomputes Q, learned Q normalization, RoPE and attention in ascending
head/component order. Each attention component stays valid and stalled while
the existing weight reader fetches that row/column and the shared FP32 unit
performs BF16 conversion, separately rounded multiplication and accumulation.
The accumulator starts at positive zero for each row and is narrowed only
after all Q*D columns. This preserves the projection's original ascending-column
reduction and BF16 boundary; it is not a partial-sum reassociation. The complete
output vector is committed before post-attention RMS normalization reads it
into the branch bank. The query bank may therefore be reused between rows
without overwriting completed output rows.

The O descriptor temporarily occupies the gate-descriptor registers; the
GeGLU gate lookup overwrites them only after attention and its normalization
have retired. No additional tensor descriptor archive is allocated. The
POST_ONLY worker retains its existing supplied-branch path and never enters
this recomputation schedule.

| Boundary | Registered ownership and visibility |
| --- | --- |
| O descriptor captured | Reserve the H-element output bank; no unfilled element is read |
| Attention component first becomes valid | Leave ready low; enter the registered weight-start state |
| Weight result | Capture the actual result, then execute conversion, multiply and add with separate start/wait edges |
| Accumulation result | Register the new scalar accumulator before asserting component ready in the acknowledgment state |
| Head completion | Reuse the query bank; keep normalized input until the final head of the final output row |
| Row completion | Narrow the scalar with the existing FP operation, write one BF16 output row, then clear the accumulator before restarting head zero |
| Vector completion | Normalize the committed output bank into the distinct branch bank; release the output allocation only after that normalization retires |
| Weight/arithmetic failure | Retire the accepted weight result, stop new weight commands, drain the attention child's remaining components, and publish the concrete error after child completion |
| Reset | Reset both controllers and scalar state; invalidate allocations without initializing output RAM |

This trades substantially more Q/attention/owner work, weight traffic and latency
for storage. Those transactions remain real public-interface traffic. Neither
total-DDR savings nor a throughput improvement is claimed. Native shared layers
still use owner K/V; this schedule introduces no shared-layer K/V tensor.

Integrated full-text reservations, excluding the separately charged retained
hidden/PLE vectors, are now E2B local/global 6656/7168 bytes, E4B
10752/11264 bytes and compact actual 40/48 bytes. Their attention-phase bound
is two hidden vectors plus one query head; feed-forward remains two hidden
vectors. The standalone private-residual/private-PLE charges are unchanged.
The private output bank's reserved physical payload changes from 8192 to
5120 bytes in production and from 32 to 16 bytes in compact geometry.
Scalar/controller changes are additional, not hidden inside that reduction.

The allocation ledger now physically instantiates only nonzero, distinct
registered reduction subtrees. Elaboration-time leaf identities distinguish
actual components, shadow components, actual/shadow metadata, native workspace,
native controllers and integration state. A subtree can share an earlier
metric's register only when every ordered leaf identity matches. Sharing never
reorders an addition or bypasses a register stage. Constant-zero nodes are
wires, not retained zero registers. All five reduction stages and the sixth
partition/output stage remain; valid/model/check/fallback/overlap/error tags
retain their original alignment.

`REPORT_BREAKDOWN` is a legal 0/1 parameter, default 1. Only prospective admission
sets it to zero: its unused payload/replay breakdown outputs are zero and their
private reduction registers are absent. Equivalent, native scratch, text
workspace, actual/shadow results and every admission comparison remain enabled.
The top's observation ledger keeps the complete breakdown.

Each node now stores a 23-bit byte count and sticky fault, using a 24-bit
carry-detecting addition. All 64-bit input bits above bit 22 are checked before
truncation; any such input, addition carry, subset fault or partition underflow
propagates failure and saturates affected reported sums to all ones. It cannot
produce a small accepted allocation. Legal ordinary allocations are bounded by
3 MiB frontier + 1 MiB ring + 1 MiB native scratch + 64 KiB complete text
workspace + 256 resident bytes = 5,308,672 bytes, below 2^23. Fallback is at
most 1 MiB. Every nonnegative subtotal is also below that bound. The matched
unshared denominator and physical-reserved-RAM disclosure are not narrowed.
An over-budget proposal is still an implementation failure, never an accepted
workload or permission to spill.

The source-derived ledger census is 126 unique reduction nodes plus eight
output nodes for observation, and 107 plus six for admission. Including the
42 protocol/error-tag bits gives 3258/2754 declared bits, or 408/345 rounded
bytes, instead of 1062 bytes each. These are counts of explicit registers,
not inferred FPGA utilization or a synthesis result.

Resident tags now factor their common generation into the registered session
epoch and their common visibility rule. Each stored key is
`{model[1:0],owner[4:0],token[16:0],is_value,head[0],pair[7:0]}`.
The full public owner/head/token/component checks still precede any insertion;
invalid descriptors cannot make a truncated key readable. Each accepted fetch
captures its full 32-bit generation. A hit requires equality with the current
generation. Invalidation drains/cancels the outstanding fetch and clears all
occupied bits before advancing that generation; entries from different epochs
can never coexist as readable entries. This retains generation-qualified tags
without duplicating 32 epoch bits per resident word. Neither payload precision,
round-robin replacement nor capacity 1/3/64 behavior is changed. Resident
metadata is now ceil(35*C/8) bytes, including occupied bits.

A read-only scalar declaration audit of the revised resident cache finds
464 controller bits (58 rounded bytes), with no omitted or duplicated scalar
term; its tag/occupied arrays remain separately charged metadata. Combining
the previous connected census with the new ledger declarations and conservative
17-byte controller increments for each full/post text worker gives the
following **upper envelopes**, not execution results:

| E2B global coexistence, ordinary mode | C=1 | C=3 | C=64 |
| --- | --- | --- | --- |
| Complete text workspace, bytes | <=32239 | <=32256 | <=32766 |
| Margin to 32768 bytes | >=529 | >=512 | >=2 |

These bounds retain the earlier simultaneously charged retained vectors,
owner source and owner head tile. They deliberately do not subtract the
cache controller's one-byte reduction. Such a narrow C=64 margin is not design
closure: the complete hierarchy declaration audit and actual legal-case
liveness/partition feasibility, including native scratch, continuation frames,
memo eviction/regeneration and mode transitions, remain unfinished. Any
unaccounted register/copy or denied legal request must be repaired. The previous
over-budget envelopes below are retained as historical design diagnostics,
not silently replaced by a passing claim.

A finite lexical pass over all 94 native RTL files inventories 3015 internal
scalar declaration occurrences and 52 internal array declarations, excluding
function-local temporaries and ANSI port declarations. Thirty-nine scalar
occurrences lack a direct `$bits` name reference: two generated ledger `value`
declarations, aliased synchronous RAM read registers, the three storage
visibility masks, the combinational replay scalar-write mux, and the fourteen
combinational tensor-shape temporaries. Alias/generated multiplicities and
conditional omission still require per-instance byte reconciliation; the
lexical counts are not elaborated instance counts or a completed census.
The source inspection also confirms that the resident cache's full descriptor
checks gate its synchronous payload read, not only its eventual response.

Only source reads, edits and read-only Bash/Python declaration/count inspection
were performed for this increment. No functional or synthesis harness,
simulation, static elaboration, preparation probe or receipt was produced.
The reserved static elaboration remains pending complete design closure,
then independent Verifier handoff.

### Prior exact metadata keys and storage declaration audit

The frontier, local ring and bounded replay workspace now store only independent
tag information. This is lossless key factoring, not cache-value compression:
all BF16 payloads, generation checks, numerical operations and public descriptor
widths remain unchanged. No legal input is truncated before its existing
full-width validation.

| Storage | Stored key and reconstruction | Visibility / boundary |
| --- | --- | --- |
| Frontier | Five-bit layer tag per token, plus the existing occupied bit | The write check requires layer `< owners`, at most 23; reads compare the complete eight-bit request to the zero-extended stored tag, and advancement uses a nine-bit sum |
| Local ring | Token bits `[16:SLOT_BITS]`; the addressed slot already supplies the low `SLOT_BITS` bits | Production window 512 stores eight tag bits per slot; compact window 4 stores fifteen. Full token `<=131071`, model, owner and generation checks remain before tag use |
| Replay frame and memo | Twenty-five-bit `{domain[1:0],layer[5:0],token[16:0]}` | Validated layers are at most 42. Every stored descriptor has the session's model/generation and the fixed domain/model vector length; those fields are reconstructed from the registered session |
| Replay pair progress | Eleven-bit next pair index rather than a twelve-bit even component | The public component is still twelve bits and checked even/in-range before mutation. Reconstruct the expected component as `{pair_index,1'b0}` |

Replay continues to capture the complete 73-bit public request and response
tags. Its existing full-width session, length, layer and token checks precede
every tag write. Pop returns the expanded frame tag. The frame/memo RAM read
registers now hold the narrow key; expansion is combinational after the same
synchronous read edge, so neither the RAM read nor public response gains or
loses a cycle. Domain length reconstruction is shared with descriptor
validation. Successful bind/invalidate clears frame, vector, scalar and memo
visibility before another request, and reset invalidates that same state;
neither operation initializes payload or tag RAM. Therefore old-session keys
cannot become hits merely because their reconstruction uses the new session.
Invalid bind attempts retain the old session and its generation checks.

The ring still clears all lane visibility on a token retag and commits only
the successfully completed lane. A token separated by one window has the same
slot but a different stored quotient. Invalid high token bits are rejected,
not aliased. The frontier still commits a tag only after the complete hidden
vector. Replay pair-progress slice strides are eleven bits per vector and
66 bits per six-vector frame, including push/pop, copy, restart, completion
and backing-error cleanup.

Read-only declaration inspection of these three changed modules gives the
following production counts. Every scalar `reg` declaration in each module
is present exactly once in its controller expression or metadata expression;
the listed payload/tag arrays are charged separately. This scoped audit is
not yet a declaration audit of every connected module.

| Module | Controller bits / rounded bytes | Metadata bits / rounded bytes | Separate array bits |
| --- | --- | --- | --- |
| Frontier | 577 / 73 | 6144 / 768 | Payload 32571392; layer tags 5120, already within metadata |
| Local ring | 419 / 53 | 6144 / 768 | Payload 8388608; token tags 4096, already within metadata |
| Replay workspace | 2103 / 263 | 9536 / 1192 | Frame keys 1600 and memo keys 400, already within metadata; backing payload remains charged by its existing allocator |

Compact frontier metadata is 384 bytes and compact ring metadata is 8 bytes.
Both native prospective admission and top-level observation retain production
shadow metadata of 768/768 bytes for frontier/ring, instead of reusing the
smaller compact declarations. Replay metadata has the same declaration size
in both geometries. Physical byte reports change only for the tag/register
storage actually narrowed; no payload RAM removal is claimed.

Relative to the preceding connected census, metadata decreases by
384+1536+528=2448 bytes. The ring controller decreases by three rounded bytes
and the workspace controller by twelve; the frontier controller remains
73 rounded bytes. Consequently executor field 24 is 4893 bytes, complete
replay is 42370, binding subtree field 22 is 43753, and its native subset
remains 36485. Other preceding terms are unchanged. Metadata at C=3 totals
2755 bytes, fixed non-native text terms total 18758, and the same conservative
global coexistence envelope is now 38726 rather than 41189 bytes.
It still exceeds E2B's mandatory 32768-byte ceiling by 5958 bytes.
These are source-derived counts, not a successful allocation or hardware
result. Further connected overlays/scheduling reductions, whole-hierarchy
declaration coverage and native/fallback legal-case partition feasibility
including eviction/regeneration remain unfinished. No required workload may
be denied to make a budget appear satisfied.

No RTL elaboration, simulation, synthesis or preparation probe was run for
this increment. The one reserved static elaboration remains pending design
closure, followed immediately by independent verification.

### Prior retained PLE backing and connected controller census

`anvil_en1_frontier_execute.SHARED_PLE` and
`anvil_en1_asym_attn_ple.SHARED_PLE` are default-off, legal 0/1 parameters.
They require external vector RAM. The connected native executor selects both:
the full-text worker's vector port 3 accesses the executor's retained PLE
in `feature_payload`, not a second copy in the shared text-phase bank.
Replay and embedding continue to use the separate phase bank.

| Boundary | Ownership, visibility and accounting |
| --- | --- |
| Embedding | Only the executor writes retained PLE; all components and the final accepted beat must commit before text starts |
| Text initial PLE load | Read the retained component through the existing callback, then write the identical value through worker port 3; do not release the retained allocation at the last callback |
| Text normalization/MLP/gated PLE | Worker port 3 reads the same retained PLE under the registered layer reservation; original token PLE stays immutable |
| Worker bank edge | Check the complete 12-bit component address, layer ownership, committed retained PLE and absence of native-feature ownership before indexing |
| Conflicting retained/worker access | Suppress RAM accesses and latch the existing allocation fault; completion reports error 7 |
| Layer completion | Release retained PLE at vector commit, including the existing error/invalidation paths |
| Reset | Disable worker/retained RAM enables; leave payload uninitialized and invalidate all visibility |
| Byte ledger | Field 2 charges retained PLE once; shared worker live/shadow bytes and field-20 reservations exclude exactly that PLE vector |
| Physical disclosure | Keep the executor feature bank and the replay/embedding text-phase PLE bank in their original physical fields; no SRAM-capacity removal is claimed |
| Standalone defaults | Keep the existing private PLE copy and last-load release when `SHARED_PLE=0` |

This removes 512 production/shadow bytes (8 compact actual bytes) from the
integrated field-20 reservation. Combined with shared residual, the integrated
local/global reservations become 7680/12288 bytes for E2B,
10240/14336 for E4B and 40/64 for compact actual geometry. No scalar register
or native/replay allocation is removed.

The following finite census evaluates the connected controller-byte
expressions with production geometry, external vector/embedding/hidden RAM,
and C=3. It includes every retained child report reached by those expressions;
it is source accounting, not an HDL execution, synthesis result or proof that
the lists cover every declaration. Independent verification must audit
declaration coverage and dynamically observe allocations.

| Connected report | Byte-rounded declared bytes |
| --- | --- |
| Ordinary executor own controller | 172 |
| Ordinary executor, including frontier/ring, embedding, full text, anchor and final logits | 4896 |
| Binding own controller, field 16 | 139 |
| Native assembly own controller and phase RAM read registers, field 17 | 162 |
| Replay dispatcher own controller, including native RAM ownership/read state | 143 |
| Replay text workers and their separate arithmetic/controller descendants | 6461 |
| Replay vision controllers and descendants | 6907 |
| Replay audio controllers and descendants | 25859 |
| Complete replay executor, including scheduler, dispatcher and workspace controller | 42382 |
| Owner replay including owner tile | 1365 |
| Binding arbiter | 18 |
| Complete reported binding subtree, field 22 | 43765 |
| Native-reconstruction subset of field 22, charged to native scratch | 36485 |
| Frontier scheduler / native arbiter / cache controller | 21 / 18 / 59 |
| Prospective allocation controller including its ledger | 1097 |
| Combined field 23 | 1195 |
| Top own controller / native external-memory bridge | 295 / 17 |
| CSR counters, snapshots and protocol state | 945 |
| Observation ledger / completion guard | 1062 / 27 |
| Top integration total | 2346 |
| Frontier / local-ring / replay visibility metadata | 1152 / 2304 / 1720 |
| Resident metadata, C=3 | 27 |

Native scratch is a subset, not an additional copy of field 22.
The metadata and integration terms remain in the equivalent-byte total and
text partition exactly as wired. Their separate physical disclosure is not
permission to remove them from that ledger.

Before the PLE backing alias, the fixed non-native text terms sum to 21221
bytes at C=3. The global field-20 envelope (12800), retained hidden/PLE
(3584), owner source (3072) and owner head tile (1024) would require a
41701-byte reservation if they coexist. Sharing PLE reduces that envelope
to 41189, still above 32768. This is a conservative source-derived
reservation calculation, not an observed transaction or a passing workload.
Even the local analogous reservation is not certified by a declaration count.
Required legal workloads must not be denied to satisfy this ceiling.
Further actual overlays/scheduling changes, complete payload liveness
analysis, native scratch/deep-frame feasibility and fallback eviction/
regeneration feasibility remain design work. The single reserved static
elaboration remains pending until that closure; no functional or synthesis
preparation harness is authorized for Designer.

### Prior checked-width allocation arithmetic and ordinary phase envelope

The allocation ledger keeps its eight coherent metrics and six registered
edges. Each reduction node now stores a 32-bit byte count and a sticky
overflow bit instead of an unchecked 64-bit count. The first stage checks
both operands' complete high halves; each later stage checks its addition
carry and propagates both child flags. No input address, public byte-count
port, baseline, CSR counter or 69-bit strict-ratio comparison is narrowed.

An admitted ordinary representation is below 6 MiB, including the 3 MiB
frontier, at most 1 MiB ring, 1 MiB native scratch, 64 KiB text workspace and
resident words. A fallback is at most 1 MiB. All reduction terms are
nonnegative subsets of that representation, so their legal partial sums fit
32 bits. Oversized or corrupt observations still receive a diagnostic,
not a truncated small allocation or permission to continue.

| Allocation boundary | Registered result |
| --- | --- |
| First addition | Check all 64 input bits; retain low 32 bits and high-half/carry fault |
| Subsequent addition | One 33-bit carry-detecting addition; preserve either child fault |
| Workspace subtraction | Check native-subset consistency and unsigned underflow on the same sampled observation |
| Invalid reduction | Assert `report_partition_error`; expose an affected metric as unsigned64 maximum, never a wrapped success-shaped value |
| Grant/guard | Either consumer rejects the partition-error report using its existing failure path |
| Reset/back-to-back observations | Zero outputs during reset; retain the existing model, mode, check-valid and six-edge correspondence |

Each ledger's declared storage is now 8490 bits / 1062 bytes, including
all node flags, totals and tags, rather than 16426 bits / 2054 bytes.
Both literal ledgers remain instantiated: their combined declaration
reduction is 1984 bytes, not a deletion of admission or observation.
The prospective controller's separate 276 bits / 35 bytes remain charged.
This is a source declaration count, not a synthesis or timing result.

Ordinary full-text admission now reserves the maximum of its phase envelopes,
not the sum of banks whose allocated lifetimes cannot coincide. Let `h` be
hidden-vector bytes, `e` PLE bytes, `q` selected head-vector bytes and `Q`
the number of query heads. The envelope is
`max(3*h+e, 2*h+e+(Q+1)*q)`. During attention, residual and normalized work
coexist with one query and all accumulated attention components. The final
head retires work and query before output projection starts. Output projection
therefore needs `2*h+e+Q*q`; later norm/MLP/PLE phases need at most `3*h+e`.
Every transition releases and reserves its flags on the same registered edge;
backpressure retains the current phase and cannot create a bank overlap.

| Geometry | Local / global field-20 reservation, bytes |
| --- | --- |
| Compact actual | 64 / 88 |
| E2B production or production shadow | 11264 / 15872 |
| E4B production or production shadow | 15872 / 19968 |

This changes only the complete private-worker envelope. Independently flagged
child live bytes still override it if larger. Retained outer vectors, owner
source/head tiles, suspended frames, scalar state, metadata and physical
reserved RAM are not removed or reassigned. Whole-system legal-workload fit
remains unfinished; these local reductions are not a successful allocation
or an authorization to deny required legal work.

### Ordinary residual and retained-vector backing ownership

`anvil_en1_frontier_execute.EXTERNAL_HIDDEN_RAM` is a legal 0/1 parameter,
default 0. At 1 it requires `EXTERNAL_VECTOR_RAM=1` and exports its enabled
synchronous hidden-bank read/write port with complete 32-bit component
addresses. The caller must connect that bank to the ordinary full-text
worker's residual bank (vector port 0), not to the replay/embedding phase
bank. `anvil_en1_asym_attn_ple.SHARED_RESIDUAL` is default 0, legal 0/1;
1 requires external vector RAM and assigns residual payload accounting to
the caller. Residual arithmetic, allocated/visibility flags and RAM requests
remain unchanged.

The connected native assembly selects this mode and retains a separate
ordinary hidden bank. Its full-text residual port and executor hidden port
access that one bank. Existing text phase bank 0 still serves replay post
and embedding; those may overlap a retained ordinary input and must not
overwrite it. No storage is silently released when a feature callback yields.

| Bank boundary | Ownership / accounting |
| --- | --- |
| Ordinary layer start | Field 2 already reserves the complete hidden vector; keep that charge until completion/retention release |
| Initial residual load | Frontier-backed sources fill the shared bank; retained-vector sources read it and write back the identical input before any residual update |
| Residual update | All original-input callbacks have retired before normalization/residual processing overwrites the bank |
| Output | The worker reads its completed residual; the executor's accepted output writes the same component back, with no second vector allocation |
| Enabled RAM edge | One selected writer and one selected reader, with full physical/model address checks before indexing |
| Competing executor/worker access | Suppress accesses and latch protocol error 7; never choose one silently |
| Worker access without registered full-text ownership or field-2 hidden reservation | Suppress access and latch error 7 |
| Reset | Disable all RAM enables and public external-RAM outputs; leave payload uninitialized and invalidate its visibility |
| Standalone defaults | Keep the original local executor hidden bank and ordinary private residual charge |

In integrated mode field 20 excludes the residual's `h` bytes from both
its phase envelope and the child's live/shadow report. Field 2 retains
those same `h` bytes; no other field changes classification. Integrated
local/global field-20 reservations are 8192/12800 for E2B, 10752/14848
for E4B, and 48/72 for compact actual geometry. Default standalone envelopes
remain the preceding table's values. The physical hidden bank remains
charged once in field 2, and the separately needed replay/embedding phase
bank remains in the physical field-20 disclosure. This is a real connected
backing alias, not removal of idle physical SRAM from the reported FPGA cost.
The shared hidden read register retains its existing charge through the
executor's `hidden_q` term in field 24; moving its declaration to the native
assembly does not add or remove a register. The four replay/embedding phase
read registers retain their separate native-controller charge.

### Native feed-forward binary32 ownership

The native MLP row uses one binary32 service for its down projection, nested
gate/up projection, GeGLU, audio activation and final BF16 materialization.
Clipped projection, native normalization and native MLP row expose the same
default-off `EXTERNAL_FP` channel as the text primitives. External mode removes
only the local binary32 unit; directories, interval clamps, dividers,
converters, descriptors, reductions and held results remain fully charged.
Audio feed-forward and vision post-layer select external mode in their norm
and MLP children and share their existing residual unit across those phases.

| Boundary | Binary32 ownership and materialization |
| --- | --- |
| Reset | Service request/result readiness and payload outputs are zero; all worker FSMs and the one local service reset together |
| MLP down start/wait | Down projection owns the service except during a registered nested gate/up, GeGLU, activation or materialization start/wait interval |
| Down source callback | Down projection waits for the intermediate; the selected nested child may use the otherwise idle service, including its weight-decoding phases |
| Nested completion | Retire the child's last arithmetic result before returning its scalar completion; owner changes only with registered source-state advancement |
| Clipped source callback | Input/output clamps are comparison-only; their stalled callback never causes arithmetic ownership to change |
| Norm scale callback | Native norm retains its existing internal scale/norm phase selection and forwards the selected request to the enclosing service |
| Audio FF / vision post norm start/wait | Native norm owns the service, including nested scale decoding and held responses |
| Audio FF / vision post MLP start/wait | The MLP row owns the service, including nested projections and activation |
| Residual / narrowing | Only the enclosing worker owns the service; ascending reduction order and separately rounded operations are unchanged |
| Memory/source/result/output stall | Keep the registered phase and route both request and response to that same owner |
| Error | Consume the active child's completion using its original error path; do not launch another owner before the arithmetic result is retired |
| Single row / first-and-last | The same start/wait and callback sequence applies; no bypass of BF16 materialization |
| Standalone defaults | `EXTERNAL_FP=0` keeps a local service and does not read the unconnected external inputs; values other than 0/1 explicitly diagnose |

Each surviving `anvil_en1_fp32` contributes its complete 68-byte declared
reservation. Before this overlay the native MLP row had five such units:
down, inner, GeGLU, audio activation and materialization. It now has one
by default, or zero in external mode, saving 272 or 340 bytes respectively
against that prior row. Audio FF and vision post each retain one enclosing
unit rather than a local norm unit, five MLP units and a residual unit:
408 fewer declared bytes per literal subtree. These are nested totals,
not additive reductions or whole-system feasibility results. No vector RAM,
clamp, divider or suspended replay-frame reservation is removed.

| Arithmetic descendants only | Previous declared bytes | Shared declared bytes |
| --- | --- | --- |
| Native MLP row: two projections, GeGLU, audio activation, local FP | 1111 | 839 standalone / 771 external |
| Audio FF: norm/scale arithmetic, MLP arithmetic, residual FP | 1549 | 1141 |
| Vision post: norm/scale arithmetic, MLP arithmetic, residual FP | 1549 | 1141 |

These rows exclude every enclosing controller, tensor directory and clamp,
which their unchanged connected reports still add. The MLP row's own
337 declared register bits remain 43 bytes. Its children retain ascending
column reductions and their original BF16 result stages. Audio SiLU remains
the activation-plus-narrowing path; it is not replaced with a multiply-by-one
GeGLU shortcut. Both parent-contained and replay-contained feed-forward/post
instances inherit this implementation through their existing literal children.

Latest saved text-path delta: the full text worker shares one binary32 unit
across norm, scale decoding, projection, rotary, attention, gated MLP/PLE and
residual/scalar operations. Embedding and final-logit workers similarly share
one unit across their serialized children. Gated projection, softcap and
attention expose the validated default-off external service. The POST_ONLY
build physically omits the unused standalone projection, rotary and attention
subtrees; it still executes the supplied attention branch's post-normalization,
residual, MLP, gated PLE and layer scalar. Retained enclosing controllers and
all surviving child state remain charged. These are source-level declaration
changes, not demonstrated whole-system feasibility.

The preceding arithmetic delta: normalization and rotary primitives expose
the default-off external binary32 service. Rotary shares one service across
frequency generation, trigonometry and pair rotation. Owner projection tiles
share one physical unit across projection, norm, scale decoding and rotary;
native normalization shares one across norm and its scale reader. Registered
phase ownership includes nested scale callbacks. All retained scalar state,
converters and division units remain fully charged.

The preceding arithmetic delta: projection and gated-projection subtrees now
share a single binary32 unit across serialized weight decoding, activation,
exponential, multiplication and reduction phases. Softcap similarly shares
its binary32 unit with its activation/exponential subtree. Every child FSM
retains its scalar census; only physically absent arithmetic units contribute
zero. The primitive reservation inventory and ownership/cycle rules below
describe these overlays. Whole-system physical overlays and legal-workload
feasibility remain unfinished.

The preceding allocation delta: ordinary frontier, local ring, retained vectors,
modality staging, anchor transfer, embedding and full-text payload now pass
whole-system admission before their allocation/child starts. A registered native
arbiter serializes these requests with the existing binding's owner/workspace/
private-worker requests. Frontier/ring actual and production-shadow reservations
retain their admitted sizes until successful invalidation, including descriptor
changes for a new session. Denial reports error 7 without a spill; this is not
proof that every legal workload fits. The primitive inventory does not establish
complete whole-system accounting or legal-case feasibility.
The reserved static elaboration has not run; this is not a ready handoff or
a verification result.

## Connected parent-compatible top and session boundary

`rtl/anvil_en1_top.sv` now preserves every named parent parameter and port,
including signed `emb_data`, and adds the admitted native/logit/CSR ports.
Additional verification parameters are `COMPACT=0`, `RESIDENT_ENTRIES=3`
and `FORCE_FALLBACK=0`; COMPACT and FORCE_FALLBACK accept only 0/1.
Parent geometry parameters affect only the literal immutable `anvil_e3_top`
instance. Native geometry remains selected by model, not parent parameters.
All declared original parent RTL sources are dependencies of the delivered
top. No parent source is copied into, modified by, or replaced within RTL.

The public acceptance edge captures all parent and native descriptor fields.
Model 0 dispatches to the literal parent, preserving its validation,
numerics, errors, embedding stream and ready/valid behavior. The wrapper
adds dispatch/completion registers; it does not promise identical absolute
parent job latency. Native models 1/2 dispatch to the real `anvil_en1_native`;
model 3 and native precisions above 1 fail with 6 before external accesses.
Parent mode ignores the added native precision/decode fields.

Native `job_tokens` is the complete, currently addressable text stream
length, including markers/placeholders, for both prefill and decode.
A prefill requires `job_position=0`. Decode requires an established
successful session, `job_position=previous_job_tokens`, and
`job_tokens=previous_job_tokens+1`; it does not supply a one-element
replacement buffer. The original arrays at the unchanged tokens,
positions and masks bases expose the immutable prefix plus the appended
element. The top compares model, precision, mode, all three weight bases,
original text/mask/position/image/audio bases and encoder geometry with the
captured successful session before accepting that append for execution.
Native recomputation deliberately rebuilds the exact complete context;
there is no persistent external hidden-state archive or hidden duplicate
KV state between jobs. Scratch/kv bases and output dimension are captured
but have no native spill/embedding-output semantics.

All native positions are checked through actual public memory reads:
unsigned32 position[t] must equal t for every t in the complete context,
in ascending order. After each position check, an actual public read checks
mask[t] as unsigned32 zero or one and supplies the source-visibility bit to
the matched-traffic calculation described below. The top checks the complete text/position/mask byte
ranges, native position/context bounds, enabled-modality geometry and
alignment before starting that scan. A failed position read returns 2,
a mismatched position or nonboolean mask returns 5, and an invalid append/session returns 7.
No native worker starts after such a failure. The worker's immutable
tensor-directory validation remains responsible for complete native
image/audio/weight image bounds before their tensor accesses.

Mode 0 is native text, 1/2 enable image, 3/4 enable audio and 5/6 enable
both; mode 7 rejects. Unlike the parent fusion path, every native mode
supplies its explicit marker/placeholder text stream and requires
`job_tokens>0`. Native modes always return last-token logits, not parent
embeddings. Only the matching parent/native output stream can assert
valid. Successful native completion establishes the next append position.
Accepted parent work or a new prefill invalidates the old public session.
Native execution failure invalidates it. A rejected decode before native
dispatch leaves the prior successful session descriptor intact.

| Top boundary | Pre-edge handshake / post-edge state |
| --- | --- |
| Reset | All public outputs zero, both children reset, session invalid; payload RAM remains governed by child visibility tags |
| First released edge | IDLE may accept one job; no request-derived memory valid before E2 |
| Job E0 | Capture every descriptor field, clear current error, leave IDLE |
| E1 | Validate registered model/session/ranges; select parent start or registered native position-scan request |
| Position request | Offer registered address to the literal memory bridge; no next scan element until its accepted response has been registered and checked |
| Mask request | After position validation, offer the captured mask address on the same registered bridge; register and validate its response before counting source reuse |
| Traffic calculation | Register local/global reuse spans, layer-weighted counts, byte scaling, their sum and the running total on separate edges |
| Native dispatch | Advance nonzero generation after successful full position/mask scan and traffic accumulation, then offer a stable captured descriptor until native start acceptance |
| Memory | Parent has its own unchanged bridge; positions/native share a second literal registered bridge; only the selected bridge drives public DDR |
| Last logit | Native completion cannot precede acceptance of the final ascending-vocabulary logit |
| Child completion | Accept actual child done; parent publishes later, native additionally drains the allocation pipeline before publishing |
| Stalled outer completion | Hold done/error and close job ingress; no second job may switch memory ownership |
| C=1/3/64 | Identical top sequencing; the real cache handles explicit non-power-of-two replacement wrap |
| Single token | Position[0] must be 0; prefill and final-logit acceptance remain real handshakes |
| Limit | Context 131072 is legal with positions through 131071; append at position 131072 rejects before position access |
| Generation wrap | Full internal invalidation on every native job precedes work; generation wraps from 0xffffffff to 1, never 0 |

The literal `anvil_en1_csr_perf` is connected to public requests and the
captured model/busy/error state. Existing atomic pair, snapshot, saturation
and clear-priority behavior is unchanged. Current connected event metrics
are busy cycles, successful jobs, accepted public read/write bytes
(including failed transactions), accepted alias responses, resident hits,
failed jobs, real owner/replay-owner reprojection bytes, memo hits/evictions
and completed fallback jobs. The matched-unshared payload gauge (metric 16)
is now connected as described below. Replay original-input and weight-image bytes
now update metrics 18/19 on accepted public memory requests, not on
projection results or internal source callbacks. Owner work is not
advertised as avoided work.
Event-model 3 updates neither bank.

Accepted native requests now drive dedicated KV-equivalent and
input/weight/output/total traffic observations, as specified below.
Matched-baseline traffic metric 6 now accumulates the explicit nominal
padded-write/masked-read schedule below for successful, accepted native jobs.
It is a calculated comparison counter, not measured baseline traffic.
Projection-output-byte events must not be relabeled weight-read bytes.
Avoided shared projections, local/global component issue/availability,
and allocation gauges/peaks now have the connected event definitions below.
Complete whole-system allocation/overlay enforcement remains required before handoff.
No static elaboration, simulation, synthesis, timing or hardware result is
claimed for the top.

### Text attention execution telemetry

The attention leaf exposes `attention_activity[3:0]`, sampled pre-edge:
bit 0 is a local component-multiply issue, bit 1 a global issue, bit 2
local lane availability and bit 3 global lane availability. A component
issue is an accepted binary32 multiply with return state DOT_ADD or
VALUE_ADD: one Q*K or probability*V component, not a probability scaling,
normalization, exponentiation, projection or conversion. The serialized
leaf has one such lane. Availability counts each cycle after descriptor
validation until publication of completion, including source, memory,
checkpoint, arithmetic and output stalls. IDLE, validation, publication
and held done responses do not count. A yielded head stops counting once
it publishes completion; a resumed head starts again after validation.
These are component-issue utilization metrics, not pipeline occupancy,
whole-chip utilization or a tokens/s measurement.

The ordinary and replay paths both forward their actual leaf events
without using a dispatcher-selected-worker mux. Native assembly adds
the two one-bit contributions separately for all four counters, retaining
simultaneous activity instead of OR-combining it. CSR metrics 10..13
receive those counts in bit order. Invalid parameter branches and active
reset produce zero events.

`avoided_projection_event` occurs on accepted successful completion of
one shared logical text-layer worker, including a replay POST_ONLY
completion, never on a cache alias lookup or a resumed attention fragment.
Metric 7 adds `4*KV_heads*head_dimension` bytes: the distinct BF16 K and V
output vectors that this logical consumer does not privately project.
Compact builds use their actual one KV head and dimensions 4/8.
Owner layers produce no avoided event. Real owner regeneration remains
charged separately by metric 17 even if a shared consumer caused it;
metric 7 is not a claim that those owner computations were avoided.
Failed or stalled layer completions do not repeatedly add bytes.
No projected-output count is a weight-bandwidth measurement.

### Registered allocation observations and CSR delivery

`anvil_en1_allocation_ledger` samples the native 25-field component vector,
four metadata fields and the top integration reservation each native
execution cycle. Eight independent 32-term balanced adder trees each
have five register stages and one checked 32-bit-value addition per stage.
The sticky fault bit detects high-half inputs and carry overflow as specified
above. The model
and observation-valid tags traverse those same stages. A report therefore
corresponds to one coherent input cycle, not a mixture of five successive
allocations. No per-cycle trace, host sum, dynamic division or subtraction
of idle physical SRAM capacity supplies these totals.

| Report | Terms | CSR |
| --- | --- | --- |
| Payload | Fields 0..15 and 18..21 | Metric 15, current allocated payload gauge |
| Replay reservation | Fields 5..16 and 22, plus workspace visibility metadata | Metric 20, saturating-session-independent maximum |
| KV-equivalent reservation | All 25 component fields, all four metadata fields and integration reservation | Metric 24, maximum |
| Native scratch | Native workspace subset, fields 3/9/10/12..15/19 and native reconstruction controllers | Allocation failure guard; not an additional contribution to metric 24 |
| Production-shadow KV-equivalent reservation | Production-width counterpart of every component and metadata field, plus the same integration reservation | Allocation failure guard; not additional physical storage |
| Production-shadow native scratch | Production-width counterpart of the native scratch subset | Allocation failure guard; not additional physical storage |

Integration reservation includes the enclosing top's complete declared
descriptor/session/traffic registers, the immutable native bridge's
132 register bits (state/write/address/write-data/read-data/error), the
CSR engine's complete two 29-metric counter/snapshot banks and controller/atomic
readback state, the allocation guard and the ledger's own pipeline registers. Arrays already
charged in payload or metadata fields are not added as primitive state.
The inactive immutable parent datapath is not native cache-equivalent
state; its physical FPGA cost still belongs in whole-top synthesis.

The CSR engine accepts allocation reports on an independent, model-tagged
event channel. A delayed native report cannot charge a newly selected
parent bank or suppress that parent's simultaneous ordinary events.
Reports use the existing metric-15 gauge and metric-20/24 maximum rules.
If both event channels target one of those metrics in the same bank,
the dedicated allocation report has priority. Clear still wins over
both channels; snapshot still captures the pre-update counter value.
The last reports can retire after the job leaves native execution, so
completion does not silently drop the pipeline tail. Native completion now
also waits eight drain edges and a subsequent allocation-check edge before
committing a successful session.

These are connected conservative reservations, including held copies
and idle controllers, not independently accepted allocation completeness
or storage savings. Workspace growth now uses the prospective whole-system
admission path below, including ordinary-workspace partition checks;
private-worker grants remain unfinished. The completion guard below reports
actual and production-shadow scratch, fallback-ceiling, overlap and
equivalent-payload violations; it does not authorize over-allocation.
Physical reserved payload and metadata remain separately exposed by
their owning leaves; a live subtotal is not a Quartus resource report.

### Production-width counterpart of compact allocations

The native assembly exposes `allocation_shadow_bytes`, with the same 25
64-bit fields, sampling boundaries and live flags as `allocation_live_bytes`.
It is a parallel reservation ledger, not another RAM allocation. For a live
hidden vector use 3072/5120 bytes for E2B/E4B; for a live PLE vector use
512 bytes. Mixed hidden/PLE banks are computed from their individual owning
flags, never by multiplying a mixed compact subtotal by a guessed ratio.
The full-text and POST_ONLY workers likewise use separate residual, work,
branch/query, PLE and attention lifetimes. Query components use the selected
production 256/512 dimension, and retained attention has eight query heads.
The replay projection tile separately charges its hidden and head vectors.

| Component fields | Production-shadow rule |
| --- | --- |
| 0, frontier | Admitted production hidden bytes times the full padded context, held until successful invalidation |
| 1, local anchor ring | Admitted `min(p,512)` times 1024/2048 bytes, held until successful invalidation |
| 2, retained hidden/PLE | Maximum of the admitted task envelope and owning hidden/PLE lifetime flags, independently |
| 3, 6, feature and owner source | Production hidden vector while the corresponding bank is allocated |
| 4, 7, 9, anchor transfer, owner head and PLE | Compact allocated byte count times 64; production count unchanged |
| 5, bounded workspace | Existing domain-aware frame, scalar and memo shadow, including pending reservations |
| 8, replay projection tile | Production hidden plus selected local/global head vector while the tile is live |
| 10, replay embedding | Sum of the input and text embedding workers' separately flagged production hidden/PLE reservations |
| 11, replay post | POST_ONLY worker's independently flagged production reservations |
| 19, ordinary embedding | Maximum of the admitted complete hidden/PLE envelope and the worker's independently flagged production reservations |
| 20, ordinary text | Maximum of the admitted complete full-text envelope and the worker's independently flagged production reservations |
| 12..18, 21..24 | Unchanged-width native encoder, resident word, binding and controller reservations; connected final-head payload is zero |

Native vision/audio feature staging remains 768/1536 components even in
compact text builds. Modality projection stores its fixed-width encoder input,
not a hidden-sized output bank, so these staging reservations do not scale
with text hidden width. All arithmetic/controller registers retain their
declared widths; compact traversal bounds do not remove them from the shadow.
The frontier/ring metadata shadow reserves 768/768 bytes respectively,
matching their production declarations. Workspace and resident metadata use
the same declaration widths in either geometry.

Actual and shadow equivalent/native-scratch sums traverse the same five
registered addition stages and mode/model/check tags. The guard checks both
against the same production B, strict ratio, fallback ceiling and native
scratch ceiling. A shadow smaller than its corresponding actual subtotal is
itself error 7. These observations prevent a small compact physical bank from
standing in for a production-width allocation pass. They do not execute
production-width numerical work or replace independent liveness observations,
grant-time allocation limits, physical overlays or source-matched FPGA results.

### Replay embedding physical overlay

`anvil_en1_embedding_ple` has an optional `EXTERNAL_VECTOR_RAM` parameter
(legal 0/1, default 0). Its input/PLE bank read and write enables, full
32-bit component addresses and BF16 data are exported without changing the
enabled-edge synchronous RAM timing. Default standalone instances retain
their original two local banks. The wrappers
`anvil_en1_replay_input` and `anvil_en1_replay_text_layer` expose
`EXTERNAL_EMBEDDING_RAM` with the same legal values/default and forward this
storage interface.

The replay executor sets both wrappers to external mode and owns one shared
hidden/PLE bank pair. The dispatcher serializes their work; any yield releases
the embedding worker before another frame executes. Two private payload
instances are therefore replaced by one physical instance (5632 production,
24 compact bytes, rather than twice those amounts). Field 10 reports this
shared physical reservation once, while actual and shadow live reservations
continue to come from the original allocation flags. The shared read registers
are counted once in dispatcher state, not again in each external child.

| Overlay boundary | Behavior |
| --- | --- |
| Enabled read/write edge | Preserve the original bank address, data and registered-read edge |
| Both workers request one bank | Suppress that bank access and latch error 7 |
| Enabled address outside the bank | Suppress that access and latch error 7; do not truncate into a legal address |
| Both workers retain live embedding payload | Latch error 7 even without simultaneous port enables |
| Worker error/done | Retire the worker normally; preserve its earlier specific error, otherwise expose overlay error 7 before the dispatcher response |
| Reset | Invalidate controller/handshake state, with no payload initialization sweep |
| New dispatcher task | Clear the previous task's overlay fault only after that task retired |

### Ordinary/replay embedding physical overlay

The integrated native assembly owns one synchronous hidden/PLE embedding
bank pair shared by the ordinary embedding worker and the replay executor's
already serialized input/text workers. `EXTERNAL_EMBEDDING_RAM` is a legal
0/1 parameter, default 0, on frontier_execute, replay_execute and
replay_binding. At 0, existing standalone storage is retained. At 1, the
wrapper exports the existing two-bank enabled-edge interface; it does not
add an arbitration cycle. The native assembly selects 1 on both paths.

Ordinary feature reconstruction completes before ordinary embedding starts.
Ordinary text can request owner replay. In the ordinary path that owner
projection reads the retained frontier/local ring, without executing an
embedding worker.
Replay input/text embedding reservations do not survive a yielded worker.
Thus no correctly scheduled ordinary embedding payload must coexist with
replay embedding payload. The phase overlay below additionally shares this
pair with the full/post text banks. Surviving feature, frontier, frame and
anchor storage are not aliased into these banks.

| Shared embedding boundary | Behavior |
| --- | --- |
| Pre-edge read/write enable | Select the requesting path's full component address and BF16 data; execute the same enabled-edge synchronous access |
| Address check | Compare the full address before indexing the physical array; suppress out-of-range access |
| Both paths request a bank | Suppress that bank access and latch the existing native protocol fault |
| Both paths retain embedding payload | Latch the same fault even without current port enables |
| Reset | Disable all bank enables and exported payloads; do not initialize payload RAM |
| Read response | Preserve the registered read word until the next enabled read; charge this register once in native state |
| Physical disclosure | The text/embedding phase overlay below charges this pair inside field 20, not again in field 19; external child payload reservations are zero |
| Live/shadow disclosure | Keep fields 10 and 19 and their original lifetime flags separately; do not subtract nominal overlap from live totals |

The two read registers move from replay dispatcher accounting into native
controller accounting, while the ordinary embedding child no longer counts
its removed local read registers. Default standalone instances keep their
original register/physical counts, and their external bank outputs are zero.

This removes a duplicate declared physical pair, not a simultaneous live
reservation. It does not complete grant-time whole-system limiting and is
not a measured M20K inference or resource-fit result.

### Text/embedding phase overlay and model-width access partitions

The connected native assembly uses text banks 0/3 for the embedding worker's
hidden/PLE payload, respectively. Banks 1/2 retain the text work and
branch/query payload. No separate integrated embedding payload arrays or
read registers remain. Standalone child defaults and their enabled-edge
interfaces are unchanged. Phase bank 0 now serves replay POST_ONLY residual
and embedding, not ordinary full-text residual. The latter uses the separate
retained-hidden backing alias specified above.

Ordinary embedding finishes and retires before the full-text worker starts.
Ordinary owner reprojection reads the frontier/ring, not a recursive text
embedding. Fallback does not run the ordinary full-text worker. In fallback,
input reconstruction and text embedding retire before POST_ONLY starts;
their durable results are in the bounded replay frame and separate retained
PLE bank. Native feature reconstruction also completes before ordinary
embedding starts. These phase relationships, not simultaneous port idleness,
permit the overlay. Retained hidden/feature/frame/PLE/anchor copies remain
separately allocated and charged.

The assembly's registered owner selects one of ordinary full text, replay
post text, ordinary embedding or replay embedding from their existing
whole-vector reservation flags (fields 20/11/19/10). Allocation precedes
memory access: text reserves its residual at descriptor validation and
performs its source callback before loading RAM; embedding reserves its
input at validation and performs token/tensor/weight work before its first
store. The following ownership edge therefore precedes every legal first
RAM access without adding a source-response or RAM-read cycle. The flags
continue through their final retained input/PLE/residual use; stalled
operations do not release them.

| Phase-overlay boundary | Behavior |
| --- | --- |
| Unique reservation | Register its owner; only that owner may drive any shared-bank enable |
| No reservation | Release ownership; suppress accesses without an owner |
| Ownership transition | A new unique reservation may replace a released owner on the next edge, never while an old representation is still charged |
| Multiple reservations | Preserve the prior owner, suppress accesses, and latch native protocol error 7 even if all RAM ports are currently idle |
| Foreign access | Suppress the affected bank and latch the same error; an access cannot acquire ownership |
| Address partition | Compare the complete supplied address before indexing, against both physical capacity and selected-model H (1536/2560 production, 8 compact) or P (256 production, 4 compact) |
| Read | Keep the original enabled-edge synchronous read and later capture; embedding reads reuse banks 0/3's registered words |
| Reset | Owner and fault reset; RAM remains uninitialized and unreadable without the existing owning worker's visibility rules |

This removes another 5632 production / 24 compact bytes of declared physical
payload and two duplicate 16-bit read registers. Physical field 20 includes
the four banks once (15872 production / 56 compact bytes), plus the full
worker's separate attention payload; field 19 has only its external child's
physical count, which is zero. Live/shadow fields 10/11/19 retain their complete
charges. Field 20 excludes only the ordinary residual already charged in
field 2 through the connected backing alias. Native controller accounting replaces the prior
96 read-register bits with 64 bits and includes the three-bit owner.

These are local storage ownership and address-partition guards, not the
context-dependent whole-system scratch/fallback/ratio allocator. No legal
capacity-pressure case is declared solved by the invariant error path.
Ordinary total-workspace partition checks now apply to observed allocations
and prospective workspace growth. Private-worker whole-system grants with
eviction/recomputation and independent allocation/traffic verification
remain required.

### Replay vision projection/branch physical overlay

The replay vision layer owns a single synchronous 768-word BF16 bank for
output-projection staging and the post worker's normalized attention/MLP
input branch. These representations are phase-disjoint: projection staging
is completely copied into the current replay frame, including the final
acknowledged pair write, before the post worker can accept start. The
post worker obtains its input from that frame, not from stale staging.
Its raw residual and MLP output banks remain separate and simultaneously
live during MLP execution; neither can alias the branch.

`anvil_en1_vision_post_layer.EXTERNAL_BRANCH_RAM` accepts 0/1, default 0.
The default keeps all three local banks. At 1, its branch RAM port exports
full 32-bit component addresses, BF16 write data and independent read/write
enables; the owner supplies the same enabled-edge synchronous read register.
Only the replay vision wrapper selects this external bank. No descriptor,
numerical operation, source callback latency or output handshake changes.

| Projection/branch boundary | Behavior |
| --- | --- |
| Projection store | Write the current checked row into the shared bank |
| Frame copy | Read synchronously, capture later, assemble an adjacent pair, and wait for its actual workspace response |
| Final copy response | Register/check that response before reaching post start; a failed write cannot transfer ownership |
| Post start acceptance | Release projection visibility/allocation; the post worker subsequently reserves its raw and branch banks |
| Post branch access | Preserve its existing synchronous read/write edge and read-before-write behavior |
| Address/ownership conflict | Check full addresses before indexing; suppress the affected access on an out-of-range address, concurrent owners, or a request outside the post phase |
| Live overlap | Latch an error if projection allocation coexists with post vector allocation, even without current port enables |
| Fault retirement | Retire the active child normally, preserve any earlier specific error, otherwise publish error 7 |
| Reset/new task | Disable payload accesses on reset, without an initialization sweep; clear the prior fault only at a new accepted task |

The shared payload is 1536 bytes, counted once by the replay vision wrapper.
The external post worker declares only its remaining 3072 local bytes.
Together these declare 4608 bytes, rather than the previous 6144-byte sum
of staging and three post banks, excluding the unchanged Q/K/V tile.
Its shared 16-bit read register is counted once in wrapper controller state,
not again in the external post worker. The original independent projection
and post lifetime flags still determine actual and production-shadow live
reservations. This is physical declaration sharing, not an observed M20K,
live-savings, resource-fit or timing result.

### Replay audio convolution/feed-forward physical overlay

`anvil_en1_replay_audio_layer` owns three synchronous 1024-component BF16
banks, shared between its convolution residual/working vectors and its
second feed-forward residual/working vectors. Bank 0 is residual; bank 1
is working. Bank 2 is the convolution GLU child's normalized vector or
the second feed-forward output branch. Within either child all three
vectors may be simultaneously live, so no two bank indices alias.
The convolution completes all output-to-frame pair writes
before its done is accepted. Feed-forward subsequently reloads that frame;
it never consumes the former owner's stale RAM contents. The GLU child
reconstructs and validates its complete normalized vector before each pair
of projection rows. Feed-forward completes its MLP branch before post-norm
visibility. History/frame storage is not aliased by this change.

Both `anvil_en1_audio_lightconv` and `anvil_en1_audio_feedforward` add
`EXTERNAL_VECTOR_RAM=0/1`, default 0. The default retains local banks.
At 1, bit b of `vector_ram_write/read[2:0]` enables bank b;
`vector_ram_waddr/raddr[32*b+:32]` carries the full component address,
and `vector_ram_wdata/rdata[16*b+:16]` carries BF16 data. These are
enabled-edge synchronous RAM ports, not a decoupled request protocol.
The owner supplies registered read data on the original read edge;
the child's existing later capture edge remains unchanged. Payloads
remain uninitialized and unreadable until the existing visibility
conditions permit access. All exported enables/addresses/write data
are zero during active reset.

`anvil_en1_audio_glu_component` also accepts `EXTERNAL_VECTOR_RAM=0/1`,
default 0, and exposes the same enabled-edge single-bank interface
(one-bit enables, 32-bit component addresses, 16-bit data). Lightconv
propagates its parameter and connects this child's port to bank 2.
Local-mode elaboration retains the original GLU bank and three independent
feed-forward banks; it does not depend on unconnected external inputs.
Illegal parameter values retain an explicit parameter diagnostic.

| Audio shared-bank boundary | Behavior |
| --- | --- |
| Child start | Grant the complete three-bank reservation only when the registered owner is free; child and parent advance on the same accepted start |
| Convolution lifetime | Hold ownership through source, weight, output and acknowledged frame-write stalls |
| Nested GLU | Bank 2 remains owned by convolution through every nested normalization, projection and held GLU completion; no separate feed-forward grant can intervene |
| Convolution completion | Release only on actual accepted child done, including failure retirement |
| Feed-forward start | Acquire the released banks; load every input from the completed replay frame before norm/MLP visibility |
| Feed-forward lifetime | Hold through branch-clamp, frame-write and output stalls; release only on accepted done |
| Read/write coincidence | Preserve synchronous read-before-write semantics independently in each bank |
| Invalid access | Check full addresses, phase and registered owner before truncating indices; suppress accesses on range/ownership conflicts |
| Overlap | Concurrent port owners or simultaneously live convolution/feed-forward vectors latch a fault |
| Fault completion | Retire the child normally; preserve an earlier specific error, otherwise expose error 7 and disallow a successful yield |
| Reset/new task | Reset releases ownership and disables RAM accesses without clearing payload; a new task clears the prior task's fault only after retirement |

The wrapper declares 6144 shared payload bytes once. The external
feed-forward worker and external convolution/GLU worker declare no local
vector payload. Compared with the preceding two-bank implementation
(4096 shared bytes plus two private 2048-byte banks), this removes another
2048 bytes of duplicate physical vector declarations. Compared with the
original separate local child payloads it removes 6144 bytes in total.
The unchanged, separate child lifetime reports still charge complete
4096/6144-byte convolution/feed-forward reservations, plus the GLU child's
live payload, to the actual and production-shadow ledger. No live payload
is subtracted merely because the declarations share RAM.
The three shared 16-bit read registers and owner/fault registers are charged
to wrapper control state; external children do not charge those read
registers again. The branch/GLU read register is physically shared, while
each child's independently held callback response remains counted locally.
This local three-bank ownership grant is not the
whole-system native-scratch/fallback limiter, a synthesis result or a
measured memory/timing improvement.

### Cross-domain replay vision/audio physical overlay

The connected replay dispatcher now owns the three synchronous 1024-word
BF16 scratch banks previously declared by its audio-layer wrapper. Vision
projection staging and post-branch storage use the first 768 words of bank 0
during a vision task. Audio convolution/feed-forward/GLU use all three banks
during an audio-layer task. The dispatcher runs only one worker task at a time;
a yielded task has retired its child and retained required state in the
workspace before another worker can start. Neither a suspended continuation
nor a memo refers to stale contents of these scratch banks.

`anvil_en1_replay_vision_layer.EXTERNAL_BRANCH_RAM` and
`anvil_en1_replay_audio_layer.EXTERNAL_VECTOR_RAM` accept 0/1, default 0,
with explicit diagnostics otherwise. Standalone defaults retain their former
local RAMs and read registers. At 1, each wrapper exports its existing
full-address, enabled-edge RAM accesses instead of declaring payload RAM;
the dispatcher selects both external modes. Child arithmetic, internal
projection/post and convolution/feed-forward ownership, read/capture cycles,
BF16 boundaries and workspace callbacks are unchanged.

| Dispatcher shared-bank boundary | Behavior |
| --- | --- |
| Worker start | Register vision/audio ownership on the actual accepted child start; do not advance the dispatcher without that acceptance |
| Worker lifetime | Retain ownership through all source, weight, frame-write, child-output and completion stalls |
| Accepted done/yield | Release only on the child's accepted done; its task-local scratch cannot survive into the next worker |
| Enabled RAM edge | Preserve independent synchronous read-before-write behavior in each bank; hold read registers without an enabled read |
| Port validation | Check full vision addresses against 768 and full audio addresses against 1024 before index truncation |
| Ownership conflict | Suppress all three banks on concurrent ports, wrong owner, accesses outside the selected worker phase, or overlapping live vision/audio-layer payload |
| Fault retirement | Retire the worker normally; preserve an earlier specific failure, otherwise expose error 7 and suppress a successful dependency yield |
| Reset/new task | Disable RAM accesses and release ownership on reset without clearing payload; clear the task fault only at a new accepted dispatcher task |

The dispatcher declares 6144 payload bytes, reported once in the audio
physical-allocation field. The connected vision wrapper no longer declares
its 1536-byte projected/branch bank, and the connected audio wrapper no longer
declares its 6144 scratch bytes. Thus this cross-domain overlay removes
1536 bytes from their combined physical declarations. The children retain
their original separate live/production-shadow reservations; physical sharing
does not subtract either live charge. The three read registers plus the
registered owner/fault (51 bits, rounded to 7 bytes for the native subset)
are counted in dispatcher state, not again in external children. All unrelated
private tile/residual/MLP/history banks remain separately reported.

This closes one cross-domain physical duplication, not every whole-system
grant-time allocation path. The prospective workspace checks below do not
yet grant private worker/arithmetic growth. No
functional, synthesis, M20K inference, resource-fit or timing result is
established by these declarations.

### Replay-frame vector grants and lifetime

The workspace now separates frame ownership, vector reservation and completed
vector visibility. Accepting a frame push reserves its full 128-byte scalar
slot before its first continuation write, but does not allocate unused vector
banks. Each first vector stream, memo-to-frame copy or ordered pair-write
sequence must pass a registered vector grant before its first backing access.
The grant reserves the **entire** selected domain-width vector, not just its
first pair: 16 compact text/feature bytes, 3072/5120 production text/feature
bytes, 1536 vision bytes or 2048 audio bytes. Production shadows reserve the
production vector width on the same edge.

There are six reservation bits per frame, using the existing bank/slice layout.
Non-audio frames can address only slice 0 of each bank; audio can use all six.
A reservation is distinct from readable visibility and ordered pair progress:
granting storage never makes an unfilled vector readable. Rewrites reuse the
existing reservation. A partial write, explicit stream abort or backing error
does not release that frame vector's reservation. It remains charged until the
frame is successfully popped or the workspace is invalidated/reset. Thus
partial/error tensors are not hidden by clearing visibility.

| Frame boundary | Registered action before any dependent backing access |
| --- | --- |
| Push grant | Pass prospective whole-system admission, then reserve the scalar slot, clear the new frame's vector reservations and visibility and write the continuation |
| First vector request | Register actual/shadow candidate totals; do not enter stream, copy or pair backing states |
| Vector grant | Check frame ownership and both physical frame-payload ceilings, pass prospective whole-system admission, then set one reservation bit and update actual/shadow/native subtotals |
| Granted request | On a later edge resume the original vector operation; existing per-pair/last-word completion rules establish visibility |
| Rewrite | Keep the same whole-vector reservation while invalidating/rebuilding visibility |
| Read/copy source | Reject visible or partially written frame state without its reservation as error 7 |
| Pop census | Capture the popped frame's six reservation bits, register their count, then register domain-width actual/shadow byte amounts |
| Pop validation | Check scalar visibility and subtotal underflow on a later edge before reading continuations |
| Pop commit | Release exactly those vector reservations and the scalar slot; clear all of the popped frame's visibility/progress |
| Reset/invalidation | Annul all frame reservations with their counters; do not initialize payload RAM |

The physical frame-payload ceiling is 786432 bytes in both builds, independently
enforced against actual and production-shadow candidates. Frame depth remains
1..64 with the existing decreasing-rank checks; no stride, stack depth,
arithmetic boundary or public port changes. Reservation bits are metadata;
registered mask/count/readback and candidate/return-state storage is controller
state. The physical backing RAM capacity is unchanged and separately disclosed.

This closes local whole-vector-before-write frame allocation and exact release.
Its new prospective admission also checks the context-dependent native-scratch,
fallback-total, ordinary text-workspace partition and strict 45%-baseline
limits before workspace growth. It does not yet admit every private
worker/arithmetic reservation. No executed liveness, numerical, synthesis,
timing or hardware result is claimed.

### Prospective whole-system admission for workspace growth

The workspace path is `replay_workspace -> eval_schedule -> replay_execute ->
replay_binding -> native grant arbiter -> native.workspace_admission`.
Ordinary allocation requests enter the same native arbiter directly from
`frontier_execute`. The literal
`anvil_en1_allocation_admission` reuses the existing registered allocation
ledger, with prospective workspace field 5 and its native subset substituted
for their current values for workspace growth; private-bank requests instead
replace their named existing field as specified below. It includes every other live/shadow component,
metadata and the top integration reservation unchanged, rather than comparing
only the memo or frame subtotal. Top supplies the already registered production
matched-payload baseline; this is a storage denominator, not measured baseline
traffic. No public `anvil_en1_top` port changes.

Before a new frame scalar slot, first frame-vector slice or memo replacement
is reserved, the workspace prepares four complete prospective byte totals:
actual workspace, production-shadow workspace, actual native subset and
production-shadow native subset. A push adds its 128-byte scalar slot,
not unallocated vectors. A vector grant adds the complete domain-width slice.
A memo replacement removes the old destination, then includes the complete
new vector. Native/text cross-domain replacement adjusts the native subset
from the old and new domains independently. Four registered preparation stages
separate base terms, memo terms, scalar additions and native-domain additions.
No new backing write, stream acceptance or copy read precedes admission.

| Internal signal | Meaning |
| --- | --- |
| `grant_valid/grant_ready` | One accepted prospective-allocation request; the four byte totals remain stable while stalled |
| `grant_component[4:0]` | Replacement allocation field: 0/1/2/3/4 for ordinary frontier/ring/retained-vector/feature/anchor-transfer, 5 for workspace growth, 6/7 for owner source/head-tile, 8/9/10/11 for replay attention-tile/PLE/embedding/post, 12/13/14/15 for native vision/audio/audio-feature/image-feature, 19/20 for ordinary embedding/full-text reservations; other fields reject |
| `grant_payload_bytes/grant_shadow_bytes[63:0]` | Complete prospective actual/shadow allocation for the selected field, not a byte increment |
| `grant_native_bytes/grant_native_shadow_bytes[63:0]` | Native-domain subsets of workspace field 5; private requests preserve that field's existing subset, since their selected fields are already included directly in native scratch |
| `grant_rsp_valid/grant_rsp_ready` | One held decision for the accepted request; no second request before retirement |
| `grant_allowed` | Held positive decision; zero is a denial, never a successful allocation or permission to spill |
| Workspace `memo_pin_valid/memo_pin_slot[3:0]` | Scheduler's active dependency memo; snapshot before frame/scalar admission and retain through retries |

| Admission boundary | Pre-edge handshake / post-edge action |
| --- | --- |
| Reset | All grant/decision outputs zero; cancel prospective pipeline validity and pending decisions without initializing payload RAM |
| G0 | Accept one request, capture its matched baseline, and sample the complete prospective allocation into the first ledger stage |
| G1..G4 | Advance the same snapshot/model/fallback/overlap tags through the remaining four balanced ledger stages |
| G5 | Register all reported totals and subtract the coherent native-scratch subset from each workspace envelope; align every observation tag and subset-error flag |
| G6 | Register `20*actual`, `20*shadow`, `9*B` in 69 bits and the independent scratch/text-partition/ceiling/overlap checks |
| G7 | Register the decision and expose a held response; strict comparisons reject equality at 45% |
| G8 or later | Accept the response; a denied request cannot reserve storage |
| After positive response | On the following edge commit only the original requested scalar/vector/memo reservation, then resume its existing backing protocol |
| Denial | Scan deterministic round-robin memo victims, release one eligible completed vector, rebuild the prospective totals, and request a fresh whole-system decision |
| No feasible unpinned victim | Return explicit workspace error 7 without the denied allocation or a spill; this is an implementation failure to resolve, not an accepted capacity fallback |
| Stalled decision | Keep valid/allowed stable; hold the requesting worker/scheduler behind its existing workspace response |

Admission requires positive B, native model 1/2, no ordinary/fallback overlap,
nondecreasing production shadows, and both actual and shadow equivalent
payloads strictly below `0.45*B`. Fallback additionally requires both complete
equivalent totals at most 1 MiB. Ordinary mode additionally requires both
native-scratch totals at most `min(1 MiB, B >> 3)` and both ordinary text
workspace totals at most 32768/65536 bytes for E2B/E4B. These are prospective
conditions on workspace growth, not completion-time observations alone.
The completion guard applies the same partition checks to observed allocations.

The existing serialized Eval/worker protocol prevents another worker from
starting while its workspace request or completed-result copy is pending.
Suspended parent banks remain charged in the snapshot; source/output stalls
cannot remove them. Frame/vector grants pin the scheduler's dependency memo.
A memo-to-frame copy additionally pins its own checked source slot even
without a scheduler pin. Single-token linear replay pins the completed
predecessor across the next frame push. Completed-result memo replacement
occurs after worker done, when its old dependency is no longer being consumed.
The scan skips the pinned slot, an occupied replacement destination and
unoccupied slots as applicable. It never evicts a live frame, partial frame
vector or immutable input. Evicted completed memos are regenerated by the
existing exact decreasing-rank Eval path on the next miss.

The admission FSM and its ledger registers are included in native component
23, so the prospective sum charges the admission hardware itself. Workspace
candidate/pin registers are included in workspace controller accounting.
No additional payload RAM is declared by this path. Its added register
reservation is disclosed even if synthesis can prune unused ledger outputs.

Remaining closure: close remaining arithmetic accounting, finish
physical overlays and establish that every required legal case has sufficient
unspillable workspace. Repeated denial after all evictable memos are gone is
not a permitted substitute for exact replay. The remaining grant paths must
be closed before the reserved static elaboration and independent Verifier
handoff. No functional or synthesis experiment has run for this increment.

### Ordinary frontier and private-storage admission

`anvil_en1_frontier_execute` now exposes the same registered allocation
request/decision protocol for fields 0/1/2/3/4/19/20. The native arbiter
registers a complete descriptor and requester identity before request
acceptance, gives the binding priority when both clients request, and retains
the route until response acceptance. Ordinary requests preserve the current
workspace/native subset rather than substituting zero. Only one prospective
allocation is admitted at a time; the next request cannot sample an earlier
uncommitted grant. All added native arbiter state is charged in component 17.

Let `h=2*H`, `q=2*head_dim` and `e=2*PLE` bytes in the selected actual geometry.
Production shadows use the selected production model even for compact builds.
The full-text envelope covers the maximum simultaneous phase allocation,
including every hidden bank, PLE, query and accumulated attention component
that can coexist. It does not allocate an MLP-wide tensor.

| Field | Complete actual reservation | Production-shadow reservation |
| --- | --- | --- |
| 0, frontier | `p*h` | `p*3072` or `p*5120` |
| 1, local ring | Compact `16*min(p,4)`; production `1024*min(p,512)` or `2048*min(p,512)` | `1024*min(p,512)` or `2048*min(p,512)` |
| 2, retained vectors | `h+e` for ordinary work; `h` for fallback result | `3072+512` / `5120+512`, or hidden bytes alone for fallback |
| 3, modality staging | `h` | 3072/5120 |
| 4, local anchor transfer | Compact 8; production 512 | 512 |
| 19, embedding | `h+e` | `3072+512` / `5120+512` |
| 20, full text | `max(3*h+e, 2*h+e+(Q+1)*q)`, minus h in integrated shared-residual mode; compact Q=2 and production Q=8 | Same rule with h=3072/5120, e=512, Q=8 and q=512/1024 |

Each field reports the greater of its complete admitted envelope and actual
child live allocation while reserved, never their sum. Existing child physical
reports and payload RAM declarations are unchanged. Field 2's complete
reservation survives task stalls, writes and completion backpressure; any
retained committed hidden vector remains charged after that envelope retires.
Final normalization reuses that already admitted hidden vector and declares
no private final-head payload.

| Ordinary boundary | Pre-edge handshake / post-edge action |
| --- | --- |
| Reset | Clear grant outputs, reservations, held sizes and admission fault; do not initialize payload RAM |
| New control descriptor | Retire obsolete retained hidden/PLE/feature visibility; preserve old frontier/ring sizes until the existing invalidate responses succeed |
| Configure frontier | Admit field 0, capture both byte sizes, then issue the ordinary frontier control command on a later edge |
| Configure ring | After successful frontier configuration, admit field 1 before issuing ring configuration |
| Frontier/ring invalidation | Retain the old charge throughout command/response stalls; release only on accepted successful invalidation, before fallback result admission |
| Native feature token | Admit field 3 before Eval start; preserve it throughout reconstruction and embedding consumption, then retire it on the accepted last feature read or failure cleanup |
| Embedding | Admit field 2, then field 19, before embedding start; neither grant marks hidden/PLE data readable |
| Full text | After embedding done and field 19 release, admit field 20 before layer start; the native registered RAM-owner protocol remains in force |
| Local anchor copy | Admit field 4 before anchor worker start; release after its accepted done result |
| Fallback result | After both ordinary representations are invalidated and the backing region is bound, admit field 2 before Eval start |
| Worker completion | Retire the embedding/text/anchor private reservation only on its accepted child done; held result/error scalars remain in controller accounting |
| Task response stall | Keep any surviving task envelope charged until the response is accepted |
| Denial | Return error 7 without the denied child start, data allocation or spill; earlier surviving representations remain charged until their normal release |
| Child exceeds admitted envelope | Preserve the larger live report, latch a task admission fault and report error 7 at publication; do not hide the excess by clamping |

Frontier/ring shadows are now supplied by the owning executor from captured
grants, not recomputed using a newly captured session descriptor. This prevents
a model/context transition from revaluing an old representation before release.
The executor's envelope flags, held sizes and fault bit are charged in component
24. Ordinary grant denial is not an eviction/recomputation proof or accepted
behavior for a required legal workload. Conservative-envelope feasibility,
remaining arithmetic accounting and physical overlays still require closure.
No static elaboration, simulation, synthesis or hardware result is established
by this source increment.

### Owner-source and projection-tile admission

`anvil_en1_owner_replay` now requests field 6 before exposing an Eval start
or starting ordinary owner projection. The complete raw/normalized bank
reservation is `2*H` bytes: compact actual 16, production shadow 3072/5120
for E2B/E4B. This is the existing single bank, first filled by fallback
Eval when required and then overwritten by normalized values at the frozen
normalization boundary. There is no second normalized-vector allocation.

After fallback Eval has completed, or directly after ordinary source
admission, it requests field 7 for the complete projected head bank.
Local/global actual bytes are 8/16 in compact geometry and 512/1024 in
production; the production-shadow bytes are always 512/1024. Each request
is a replacement of the corresponding existing ledger field, not a byte
increment. The raw reservation remains charged while the tile decision
is pending, and both remain charged through projection and its stalls.
The existing controller reservation includes returned scalar/pair data.

The binding arbitrates owner and workspace/private grants without a new
external interface. It selects and registers one complete descriptor,
retains its requester identity until decision acceptance, and permits no
other request through that arbitration interval. Owner selection waits
until the replay scheduler is idle. Thus a prior Eval completes its output,
workspace invalidation and done handshake before a new owner grant
snapshot; owner field 6 is already charged during an owner-triggered Eval.
The workspace path's pinned-memo eviction/retry remains unchanged. Owner
grants do not evict live replay frames or read uncommitted source data.

| Owner/binding boundary | Pre-edge handshake / post-edge action |
| --- | --- |
| Reset | Clear grant validity, binding descriptor/route and fault state, and owner allocation flags; payload RAM remains uninitialized/invisible |
| Ring hit | Accept the actual ring response and publish its pair without requesting either owner allocation |
| Ring miss or non-ring owner | Enter raw-grant send only after descriptor validation and hidden/head geometry capture |
| Binding selection | When idle, select an eligible owner request before a workspace request; register all four byte totals and field identity, with no downstream acceptance on this selection edge |
| Admission request | Present the registered descriptor until the existing admission request handshake; route ready only to the selected requester |
| Held decision | Route validity only to the captured requester and retain the descriptor/route through backpressure |
| Positive raw decision | Set `raw_allocated`; only a later edge can accept Eval start or issue the tile request |
| Eval output/done stalls | Retain the entire raw bank while independent replay allocations grow/shrink; visibility still requires every checked output beat and successful Eval completion |
| Positive tile decision | Set `tile_allocated`; only a later edge can accept projection start |
| Projection/source/memory stall | Retain raw and tile reservations and all original descriptor fields |
| Child completion | Accept the tile result, retire raw/tile payload reservations, and retain the returned pair/error through the owner response handshake |
| Denial or malformed Eval result | Publish explicit error 7 (or the child's existing error); retire any earlier owner reservation without starting the denied child or issuing a spill |
| Invalid arbitration state | Latch the existing binding/native protocol-error path; no successful allocation is fabricated |

Both grant-routing state and descriptor registers are included once in binding
field 16. The owner FSM's wider state encoding is included in its existing
subtree controller field 22. No additional payload RAM is declared.
An owner denial with no live replay workspace is still an implementation
feasibility failure, not accepted behavior for a required legal workload.
This closes the owner-source/head-bank grant path, not remaining arithmetic
accounting, physical overlays, functional
correctness, RAM inference or timing. No execution check has run for this
increment; the reserved static elaboration remains pending.

### Replay text private-storage admission

Before the replay text worker starts embedding reconstruction, it requests
workspace operation 7, target 1, using its current frame descriptor, bank 0,
component 0 and the allocation field in the scalar-index field. Request data
packs the complete production-shadow byte count in bits 31:16 and the actual
byte count in bits 15:0. Legal text private encodings are:

| Allocation field | Complete reservation | Compact actual / production shadow |
| --- | --- | --- |
| 8 | Serialized attention projection hidden/head tile | `16+2*Dcompact` / `2*H+2*Dproduction` bytes |
| 9 | Retained reconstructed PLE | 8 / 512 bytes |
| 10 | Embedding hidden and PLE banks | 24 / `2*H+512` bytes |
| 11 | POST_ONLY residual, working, branch and PLE banks | 56 / `6*H+512` bytes |

Production actual equals production shadow. Native private encodings are
specified in the next subsection; all other target-1 encodings reject.
Field 10 also applies to the layer-0 text-input worker; fields 8/9/11 require
a nonzero text frame layer. The input worker obtains admission after validating
its token/modality dependency and before embedding start. It retains the whole
hidden/PLE bank reservation across feature callbacks, frame streaming, abort
draining and held child completion, releasing it only on accepted embedding
done. Feature dependencies are pinned by the same scheduler/workspace path.
This operation is a private-storage preflight, not a scalar read or a write
to the frame's continuation/scalar RAM.
Field 8 uses the existing literal geometry decoder for the logical layer
`frame_layer-1`, with local/global dimensions 4/8 compact and 256/512
production. It reserves the whole serialized tile before attention starts,
including on resumed attention, and remains charged until actual attention
done/yield acceptance. Query/service pair registers and arithmetic state
remain in their existing full controller census; they are not hidden in a
zero tile-payload observation.

The scheduler validates the current worker/frame tag. The workspace validates
the session, descriptor and owned frame before sending a whole-system
admission request for the selected replacement field. Workspace field 5 remains at its
actual live value, including any suspended frames and memos. The native
workspace subset is likewise unchanged. The ledger therefore charges each
reservation once in its existing field, without a duplicate workspace
reservation. PLE and embedding belong to native scratch; attention tile and post belong to the
text partition. Denial uses the same deterministic completed-memo eviction and
fresh admission snapshot as frame/vector growth. The current dependency memo
remains pinned; eviction cannot remove a modality feature still needed for
embedding. A later miss regenerates the evicted value through real Eval.

| Private-storage boundary | Pre-edge handshake / post-edge action |
| --- | --- |
| Reset | No request, response or PLE reservation; existing visibility is invalid |
| P0 | Worker offers stable operation 7/target 1, allocation field/byte counts and the captured current frame descriptor |
| P1 onward | Workspace checks session/frame, prepares native subtotals and sends the selected-field request through the unchanged registered admission pipeline |
| Denial | Evict one eligible completed memo and retry; no requested child start or newly reserved RAM write |
| Positive decision | Publish a held workspace success response; no PLE data becomes visible |
| Worker response acceptance | Reserve the selected entire actual/shadow bank set; PLE success requests embedding admission, attention/embedding/post success enters that child's start state |
| Child stall | Keep the complete bank-set reservation; no unfilled payload is readable |
| Embedding done acceptance | Release its bank-set reservation, retaining the separate reconstructed PLE copy; then request post admission |
| Post done acceptance | Release its bank-set reservation after the actual child completion and drained source callbacks |
| Attention done/yield acceptance | Release the private tile reservation before a dependency descent; suspended frame/checkpoint state remains charged |
| Publication/error | Clear the retained PLE reservation and visibility after child work has drained, as before |

Attention/embedding/post report the larger of their complete reservation and their
child's actual live bytes, separately for actual/shadow. Thus later workspace
growth cannot consume promised bank capacity while a child is filling it,
and an unexpected child overrun remains visible. Reservation bits are charged
in worker controller bytes; no additional payload RAM is declared.

This closes the replay text attention-tile/PLE/embedding/post and text-input embedding private-bank paths.
Ordinary execution/owner projection still requires grant-time closure. The selected-field
mechanism does not establish legal-case feasibility, physical inference,
numerical correctness or acceptance.

### Replay native private-storage admission

The replay dispatcher requests operation 7/target 1 using the same captured
current frame descriptor and dependency-memo pin before starting a native
worker. Its scalar index selects the existing ledger field below; component
and bank must both be zero. Both packed 16-bit byte counts must equal the
selected envelope. Native encoder dimensions remain production widths in
compact text builds, so actual and production-shadow envelopes are equal.

| Field | Worker / legal frame | Complete private-bank envelope, bytes |
| --- | --- | --- |
| 12 | Vision domain 1, frame layer 0 | 0: patch reconstruction streams scalar arithmetic, with no private vector bank |
| 12 | Vision domain 1, frame layers 1..16 | 4608: guarded phase maximum of projected branch 1536, input/head tile 1664 and post raw/branch/MLP 4608 |
| 13 | Audio domain 2, frame layer 0 | 512: both 256-byte subsample point banks |
| 13 | Audio domain 2, frame layers 1..12 | 10240: guarded phase maximum of replay-head cache/pre-attention 10240, frame-backed post-attention raw/pre-attention 10240, convolution/GLU 6144 and feed-forward 6144 |
| 14 | Reconstructed-feature domain 3, frame layer 2 | 6144: projected audio 3072 and modality-input 3072 |
| 15 | Reconstructed-feature domain 3, frame layer 1 | 6432: complete declared mask-bank envelope 3360, pooled vision 1536 and modality-input 1536 |

These are conservative reservations, not claims that mutually serialized
nested banks all contain live data simultaneously. In particular, the
FRAME_HEADS post-attention sum bounds all four outer allocation flags even
where a particular phase uses fewer banks. The image envelope reserves the
entire declared mask bank rather than treating its smaller occupied prefix
as additional available budget. Physical disclosure is unchanged and remains
separate. No vector RAM is added by admission.

| Native boundary | Pre-edge handshake / post-edge action |
| --- | --- |
| Task capture | Register the immutable worker descriptor; clear the prior reservation only after its task response was accepted |
| Validation | Reject illegal lengths, layer/position ranges and missing original-input geometry before requesting admission |
| Preflight send | Hold the complete field/byte/frame request until scheduler/workspace acceptance; no native child starts or external command issues |
| Preflight wait | Workspace validates the owned frame/session and runs full-ledger admission, retaining the dependency pin through completed-memo eviction/retry |
| Success acceptance | Set one reservation bit; enter the selected native child's start state on the following edge |
| Child/source/output stall | Keep the entire selected envelope charged, including while nested frame-vector grants are pending |
| Child done/yield acceptance | Drain the child and publish its result, keeping the envelope through held dispatcher task completion |
| Task completion acceptance | Release the envelope; suspended frame/scalar/memo state remains independently charged |
| Denial exhaustion/error | Publish explicit error 7 (or the concrete workspace error) without starting the denied child; this remains an implementation failure, not accepted fallback |
| Reset | Cancel preflight/reservation validity and drive public handshake/allocation outputs to zero; do not initialize payload RAM |

Each native component reports the larger of its entire reservation and the
underlying child live sum. An unexpected child live sum beyond its granted
envelope is also latched as a dispatcher fault and prevents a successful
publication. The reservation bit is included once in dispatcher controller
accounting and its native-reconstruction subset. Later frame/memo growth
therefore sees the still-promised private banks in its prospective ledger.
Native private preflight leaves workspace field 5 and its native subset
unchanged; it does not reserve a second copy in workspace RAM.

The conservative envelopes and all legal workloads still require feasibility
closure, including small-context native-scratch limits and fallback
continuation depth. Ordinary/frontier workers, owner-projection grants,
remaining arithmetic accounting and physical overlays remain unfinished.
No static, functional, numerical or synthesis check has run for this increment.

### Context-bounded memo grants and exact eviction

The replay workspace control descriptor now includes `control_tokens[31:0]`,
captured with model/generation on the accepted control edge. The connected
Eval scheduler supplies the registered complete text-context length, not an
encoder patch/frame count. A non-invalidation bind rejects zero or more than
131072 tokens with error 5. Invalidation ignores the token count and clears
all memo visibility/reservations and the memo budget. Domain-0 text and
domain-3 reconstructed-feature requests additionally require their token
to be inside that captured context. Encoder-domain token extents retain
their separate scheduler/worker checks.

The implementation chooses an opportunistic memo-payload envelope
`min(131072, B >> 6)` bytes, where B is the admitted model-specific
production-width matched live baseline using 16-token padding and the
512-token production window. This is a microarchitectural cache limit,
not a change to the required total-footprint or native-scratch limits.
The same byte ceiling applies independently to actual and production-shadow
memo payload, including the pending replacement. Physical slot/row bounds
also continue to apply. For the smallest context the envelope is 10752
bytes for E2B and 25088 bytes for E4B, enough for every single legal result
vector, including native audio/vision results. Large contexts cap at
128 KiB. No numerical value, tensor width or materialization changes.

| Memo/control boundary | Pre-edge handshake / post-edge action |
| --- | --- |
| Control acceptance | Capture immutable model, generation and context length; close requests until the control response retires |
| Bind validation | Validate the captured context before enabling a new workspace session |
| Budget terms / sum / commit | Register model-specific local/global terms, their sum, then the scaled/clamped byte ceiling on three separate edges before control publication |
| Replacement candidate | Subtract the selected destination's old actual/shadow bytes, then add the new vector before any new backing write or pending reservation |
| Over-budget candidate | Scan the 16 memo slots from the deterministic round-robin cursor, skipping the destination and unoccupied slots; do not enter STREAM/COPY_READ |
| Budget eviction | Invalidate one completed victim, decrement actual/shadow and native-domain subtotals and the candidate on the same edge, and emit the existing eviction event |
| Recheck | Compare registered reduced candidates on a later edge; continue scanning or grant the replacement |
| Grant | Pass prospective whole-system admission, remove any old destination reservation and charge the complete pending vector before accepting its first stream word or issuing a copy read |
| Commit / abort | Existing commit visibility and abort/backing-error release rules are unchanged; budget-evicted values remain invalid |
| No feasible victim / inconsistent census | Report error 7 without unsigned wraparound or a new backing write; the local memo envelope alone always admits one legal vector, but this does not prove whole-system feasibility |
| Stalled public response | Keep its payload stable; a second workspace request cannot race eviction or read an evicted slot |

Budget eviction has no dirty writeback and never sends an external memory
command. A later scheduler lookup misses and runs the existing decreasing-rank
Eval dependency computation. It does not import a hidden-state or KV answer.
The scheduler does not allocate a new memo while a worker is consuming its
dependency memo: work passthrough can read/copy that memo into the current
frame, but completed-result memo allocations occur only after worker done.
Thus no concurrent pinned consumer is displaced by the new budget scan.
The frame source of a completed-result copy is separate from all memo victims.
Budget scan/control/candidate registers enter the workspace controller census;
unused physical memo capacity is still disclosed, not advertised as removed RAM.

This closes a context-sensitive **memo** grant path with real eviction and
recomputation. Memo, scalar-push and first-vector growth now additionally pass
the prospective whole-system checks above. Private native/text worker and
arithmetic/controller grants and whole-system
feasibility remain unfinished. The outer completion-time allocation guard
is still an observer; its failures cannot be relabeled successful legal execution.

### Native-workspace domain census

The replay workspace additionally reports `native_payload_bytes` and
`native_production_shadow_bytes`. These are subsets of the existing
workspace totals, not new allocations. Domain 0 is text; domains 1, 2
and 3 are vision, audio and reconstructed native features. Charge every
reserved complete vector slice and the complete 128-byte scalar reservation
of every live or pending native frame, and every live or pending native memo vector.
Keep ordinary and production-shadow vector widths separate. The native
parent frame remains charged while a dependency executes, even if the
dispatcher currently selects text work.

| Workspace event | Native subset update |
| --- | --- |
| Frame reserve | Include the pending frame's complete scalar slot before the first continuation write; vectors start unreserved |
| Frame commit | Transfer the pending scalar reservation to committed depth without a zero or double-counted cycle |
| Vector grant | Add the selected complete vector slice before its first backing access, retaining it through partial/error states |
| Pop | Remove the actual popped frame's reserved vector slices and scalar slot using its stored domain, not the incoming request's domain |
| Memo replacement | Remove the victim's stored domain and width; add the pending new vector before its first backing write |
| Memo commit | Transfer pending to committed, retaining the new memo domain |
| Aborted copy or backing error | Release pending memo/push storage; retain granted frame-vector reservations and surviving committed frames/memos until pop/invalidation |
| Reset/session invalidation | Clear both domain subtotals and native-frame count with the existing visibility state |

Native-subtotal underflow or inconsistency is a cache-state error (7),
not unsigned wraparound. These subsets traverse the existing schedule,
executor and binding interfaces without altering numerical scheduling,
backing addresses or external memory traffic. Context-bounded memo replacement
is specified immediately above. These subtotals are
required inputs to the remaining whole-system native-scratch limiter;
by themselves they do not establish grant-time limiting. Their production
counterparts now enter the complete 25-field shadow observation described above.

### Completion-time allocation failure guard

The allocation ledger includes an identically registered sum for
native reconstruction scratch: workspace native payload, fields 3, 9,
10, 12..15 and 19, and the reported native reconstruction controllers.
This deliberately also reserves the embedding/PLE controllers and banks
when not currently selected; idle dispatcher selection cannot erase a
surviving allocation. Scratch is a subset of equivalent bytes, not a
second contribution to that total.

The top's allocation guard checks actual and production-shadow equivalent
bytes independently against `20*P < 9*B`, checks both fallback equivalent
reservations against 1 MiB, and checks both ordinary native scratch
reservations against `min(1 MiB,B>>3)`. B is always the
production-geometry padded baseline, also in compact builds. Comparison
uses widened shift/add operands and a separately registered comparison
stage, never division or a truncating percentage calculation. It also
rejects simultaneous fallback and live ordinary frontier/ring reservations.
Ordinary mode also checks the separately pipelined complete text-workspace
partition described below.
This is an allocation-failure observer: it neither grants excess storage
nor changes the admitted operation to an error-return fallback.

| Completion boundary | Behavior |
| --- | --- |
| New accepted job | Clear only this guard's sticky failure and invalidate comparison pipeline |
| Native execution | Sample coherent allocation and mode observations; retain any failed limit |
| Native done | Retire the real worker response, close native ingress and preserve its error |
| Allocation drain | Wait for the ledger and comparison tail before considering success |
| Allocation check | Preserve an earlier error; otherwise report error 7 on an allocation failure |
| Session commit | Establish the decode session only after both native execution and allocation checks succeeded |
| Reset | Clear guard and pipeline, with no manufactured allocation reports |

These connected observations do not certify independently checked allocation
completeness or FPGA resource fit. Grant-time allocation limiting and remaining
physical phase overlays still must be completed before the design handoff.

### Ordinary complete text-workspace partition

The allocation ledger carries eight parallel balanced five-stage sums.
The first six retain payload, replay, complete equivalent and native-scratch
actual/shadow observations. The two added sums are actual/shadow workspace
envelopes: the complete equivalent ledger excluding only frontier (field 0),
local anchor ring (field 1) and resident KV words (field 18). All other
fields, visibility metadata and integration/control registers remain included.
A sixth registered stage subtracts each coherent native-scratch subtotal
from its envelope. That subtotal is charged to M, never counted twice or
discarded from the complete equivalent ledger. Text-domain workspace frames,
scalar continuations, memos, transient vectors and arithmetic/control state
therefore remain in the text partition.

| Partition boundary | Rule |
| --- | --- |
| Native subset consistency | Actual/shadow workspace native bytes cannot exceed field 5; native reconstruction controllers cannot exceed field 22 in either ledger |
| Envelope subtraction | Underflow retains an explicit partition-error flag; wrapped subtraction is never an admissible byte count |
| Ordinary E2B | Actual and production-shadow complete text workspace each at most 32768 bytes |
| Ordinary E4B | Actual and production-shadow complete text workspace each at most 65536 bytes |
| Shadow consistency | Text workspace shadow must be at least actual, independently of total and native-scratch checks |
| Fallback | Retain complete 1 MiB and strict 45% checks; use the separate <=65536-byte working-state outputs described in the current increment, not the ordinary text limit |
| Reset/report | All outputs and pipeline validity zero during reset; all eight totals and model/mode/error tags describe the same sampled edge |

Both prospective workspace admission and the completion guard consume these
same totals and error flags. Prospective denial uses the existing pinned-memo
eviction/retry path before allocating any denied frame/vector/memo payload.
The top's eight drain edges plus allocation-check edge cover the six ledger
stages and the guard's two comparison stages. All expanded ledger registers,
including the subset-error pipeline and final totals, are included in each
ledger's controller reservation. The prospective instance charges itself
through native field 23; the observation instance charges itself through
integration bytes. No payload RAM, public top port, numerical boundary or
acceptance threshold changes.

This closes partition enforcement for observed allocations and for prospective
workspace growth. It does not yet grant private worker/arithmetic growth,
prove legal-case capacity feasibility or certify physical implementation.
No execution result is claimed.

### Matched-unshared payload gauge

Metric 16 records the full padded matched-unshared payload when the native
engine accepts a validated job, after the successful positions scan.
For production E2B it is `1024*(28*w+14*p)` bytes and for production E4B
`2048*(35*w+14*p)` bytes, where `p=16*ceil(N/16)` and `w=min(p,512)`.
The 28/35 local and seven global layers all retain distinct K/V in this
comparison, including each shared logical consumer's materialized owner copy.
Both precision modes have the same BF16 KV payload. COMPACT uses
`16*(L*w+14*p)`, with `L=28/35` and `w=min(p,4)`, reflecting its actual
one KV head and local/global dimensions 4/8, not production-width savings.

The descriptor-validation edge registers local/global unit counts; the
subsequent position-request edge registers their scaled sum. No memory
access or native dispatch is created by this accounting. Job acceptance
clears these private calculation registers; rejected jobs do not update
the CSR gauge. A CSR clear simultaneous with the native-start event still
wins through the unchanged CSR engine.

This gauge is a model-geometry calculation, not an observed external
traffic baseline or an allocation/savings pass.
The independent executable baseline must still handshake and scoreboard
its real writes/reads; it cannot take its traffic denominator from metric 16.

### Matched-unshared nominal traffic counter

Metric 6 (`matched_unshared_kv_bytes`, low/high 0x050/0x054) adds the
following calculated traffic for each successfully completed native job.
It updates only when the outer successful completion is accepted, once
per job, not when a cache request repeats, a replay frame resumes or a
stalled completion is observed. Parent mode does not produce this event.
CSR clear, saturation, snapshot and atomic-pair rules are unchanged.

Let L=28/35, G=7, K=1/2 for production E2B/E4B, respectively;
Dl=256, Dg=512 and W=512. In compact builds K=1, Dl=4, Dg=8 and W=4,
retaining both complete logical layer maps. Let m[s] be the validated
immutable boolean source mask and p=16*ceil(N/16). The nominal producer
materializes the correct owner K and V into each logical layer's private
copy, including shared consumers; it does not invent private shared
projection tensors.

```
writes = 4*K*p*(L*Dl + G*Dg)
reads  = 4*K*sum(s=0..N-1,
          m[s]*(L*Dl*min(W,N-s) + G*Dg*(N-s)))
metric-6 job increment = writes + reads
```

Each four-byte transfer contains two adjacent BF16 components.
Writes include all padded token slots, including local slots that are
subsequently replaced in the window ring. Live local payload still
occupies only min(p,W) slots; cumulative writes and live allocation are
different quantities. Reads have no padded or future sources. A visible
source s participates in exactly N-s global queries and min(W,N-s) local
queries. The read schedule reuses the loaded K/V pair across grouped Q
heads and counts each pair once per visible source/query/logical layer.
It is a conservative nominal schedule, not the candidate's repeated
softmax-phase reads or owner-rematerialization work. Both precision modes
use BF16 cache words, so they have identical nominal byte counts.
Native decode rebuilds the complete context, and this counter likewise
describes that job's full-context matched computation, not an incremental
baseline with a retained previous job.

The top's existing position scan now interleaves one mask read per source.
These are real additional immutable-input transactions, included in actual
read/input/total counters, never baseline KV traffic. An unsuccessful read
returns error 2; a nonboolean mask returns error 5 before native dispatch.
Native attention still reads its real masks; this scan supplies neither
hidden states nor numerical answers. The immutable-session rule prevents
the scan and later attention from observing different masks.

Byte calculation has registered count/scale/sum/accumulation stages and
bounded shift/add constant coefficients, with no division, modulo,
unbounded combinational loop or dynamic cache-data inspection. All added
state is charged in the integration controller reservation. The private
calculation resets at each accepted job and remains stable through native
execution and outer completion stalls. Clear during a running job clears
the CSR total; subsequent successful job completion still contributes that
job's complete nominal increment, just as jobs_completed counts at completion.

**This is not the acceptance denominator.** Verifier must independently
execute its public-interface baseline producer and memory responder with
the same padding, masks, BF16 packing and correct owner values, require
successful responses and complete scoreboards, and use its actual accepted
bytes for each savings comparison. A metric-6 value, formula agreement,
alias count or zero candidate KV count cannot replace those transactions.
Any baseline implementation's additional transfers must be reported
explicitly rather than silently attributed to this nominal counter.

### Accepted replay traffic classification

The two memory arbiters now retain input/weight and replay provenance with
the accepted command. `client_input_read_event[i]` is an acceptance event,
not a ready/valid payload: the selected producer asserts it only on an
accepted original-input command. `client_cmd_replay[i]` identifies the
selected execution path. The arbiter samples both only with that client's
command handshake; its outward `cmd_input` and `cmd_replay` are registered
command attributes, stable through command stalls and response retirement.
Client routing IDs do not classify tensor traffic.

The owner/replay binding classifies all of its commands as owner/replay
work. Its owner projection client reads only weight images; the Eval
client classifies original text token IDs, native placeholder maps,
vision pixels/coordinates/input directories and original audio
values/masks/input directories as inputs. Embedding reconstruction's
additional real token-ID reads are included, not just its caller's token
read. Vision layer-zero patch reconstruction reports its actual original
input reads separately from patch-matrix and position-weight reads.
Every other read on these connected native paths reads an immutable
weight image, including its validated tensor directory. On-chip frame,
memo, source-vector and feature callbacks do not create external-input
events.

The outer native arbiter retains that binding's input attribute at its
own command acceptance. Ordinary text commands are not tagged replay.
The immutable-mask client is tagged replay only when its registered
request owner is the Eval path. Position/mask scanning is an original-input
read but is not replay. Finally the top captures command attributes at
the literal memory bridge's command acceptance and increments CSR bytes
only when the corresponding **public** 32-bit memory request is accepted.
An internal command cancelled by reset before public acceptance therefore
does not add traffic; a publicly accepted command with a failed response
still does. Reset clears both classification registers. No tag adds a
memory request, changes arbitration or supplies any numerical answer.

`replay_weight_bytes` reports actual weight-image traffic through the
owner/replay path, not an analytically subtracted excess over the matched
baseline. Replay may increase total DDR traffic. Independent public-address
scoreboards and the executable matched baseline remain mandatory; these
CSR events alone do not certify the no-spill or savings requirements.

### External traffic census and no-spill enforcement

The native assembly and owner/replay binding instantiate the memory arbiter
with `READ_ONLY=1`. All immutable-input and weight commands remain actual
external reads. A client write is accepted internally, retained as an error
transaction and retired through that client's registered result channel.
It never enters SEND, never asserts outward cmd_valid, and never modifies
external memory. The client receives result_error=1 and follows its existing
memory-error unwind; drain waits for that response's actual acceptance.
The parent bridge and the arbiter's default READ_ONLY=0 behavior are unchanged.
READ_ONLY accepts only 0/1; illegal values use the existing diagnostic-only
generate branch. This enforces the native no-external-spill boundary without
claiming that input/weight reads are free, or substituting software KV data.

The top sends every accepted public 32-bit memory request to a separate
model-tagged CSR traffic channel. It uses the bridge's registered provenance,
not the current leaf's command wires. Every native read is classified as an
original immutable input (including positions and scanned masks) or immutable weight-image read.
Any accepted native write is conservatively KV-equivalent, never reclassified
as an innocuous output; the read-only arbiters normally prevent such a write.
Metric 4/5 receive accepted external cache-equivalent reads/writes. Native
cache data has no external read producer: all its responses remain in the
on-chip materialized/rematerialized spaces. Consequently a normal native
job has no metric-4/5 event by construction. This is not a substitute for
the independent public-address/no-spill observer or injected-spill coverage.

Four cumulative atomic low/high pairs are appended after retained metric 24:

| Metric | Low/high CSR | Accepted public bytes |
| --- | --- | --- |
| 25 original_input_bytes | 0x0e8 / 0x0ec | Native original-input reads, ordinary and replay, including directories and positions |
| 26 immutable_weight_bytes | 0x0f0 / 0x0f4 | Native weight-image reads, ordinary and replay, including tensor directories |
| 27 non_kv_output_bytes | 0x0f8 / 0x0fc | Native external non-cache output writes; no such producer exists in this logit-stream implementation |
| 28 total_external_bytes | 0x100 / 0x104 | All parent/native public reads and writes in the selected model bank |

Each event adds four bytes even if its later response fails. A stalled request
adds nothing before acceptance and no request is counted twice. Native classified
bytes plus cache-equivalent bytes partition its total external requests.
Parent classification is not inferred from private parent addresses:
metrics 25..27 remain native-only; parent totals and existing read/write metrics
remain observable. Logits are a ready/valid output stream, not external DDR.

The existing 25-bit event interface and all retained offsets are unchanged.
The additional traffic channel is traffic_valid, traffic_model[1:0],
traffic_write, traffic_input and traffic_cache, sampled pre-edge.
It takes priority over an ordinary event for the same metric/bank; the connected
top does not generate duplicate ordinary traffic events for metrics 4/5.
Allocation-report priority, clear-over-all-events, pre-update snapshots,
saturation, held atomic high halves and invalid-bank rejection are unchanged.
0x108 and all higher non-control addresses reject. The enlarged counter/snapshot
reservation is included in controller_bytes and therefore the whole-system ledger.
Metric 6 is the separately calculated nominal matched schedule above; none
of these candidate counters supplies the independently executed baseline denominator.

## Connected native execution assembly

`rtl/anvil_en1_native.sv` connects the existing frontier scheduler, frontier
executor, owner/replay binding, shared cache and registered memory arbiter.
This is the native execution assembly below the compatible
top/session/CSR wrapper. It is not a substitute top or an accepted design.
Its start descriptor is a complete immutable native context, not a decode
append descriptor; only the outer top may authorize a decode/session change.
It captures model, precision, modality, generation, context length, forced
fallback, original text/mask/image/audio bases and encoder geometry, and all
three weight-image bases before validation. Its legal models, precisions,
geometry and resident capacity are unchanged.

The assembly routes cache regeneration exclusively to the real binding.
Owner source/ring reads return to the frontier executor's actual tagged RAM;
frontier Eval requests and results use that same binding; replay backing
uses the executor's acknowledged disjoint/rebound RAM channel. Only the
ordinary executor issues resident fetches. Recursive replay uses its actual
dependency/projection engine and shared metadata, not a second resident
fetch port that could recursively deadlock a cache miss.

The two metadata requesters share a registered 122-bit command and 79-bit
response router. The packing is
`{op,model,layer,token,is_value,kv_head,component,base}` and
`{addr,owner,alias,error,space}`, respectively. Replay has admission
priority over ordinary execution when both offer a command. An accepted
request owns the complete transaction through response retirement;
priority cannot change a stalled command or response. The assembly's
session-invalidation requester has priority while admitting a new context.
There is exactly one cache, and no duplicate owner-selection logic in
this assembly.

Both attention mask requesters share another registered router. Each
request rereads the actual immutable unsigned32 mask at
`mask_base + 4*token` through memory client 2. Token bounds and the complete
65-bit byte-address sum are checked before access. Only data 0 or 1 is
legal; failed responses and malformed masks return an explicit source
error. Replay has admission priority; a captured response remains routed
only to its captured requester. These are original-input reads, not
cache-equivalent transfers or an all-ones software mask.

The three memory clients are ordinary execution (0), owner/replay binding
(1) and immutable masks (2). The literal registered arbiter is the only
source of this assembly's outward memory commands; no on-chip cache or
backing address is connected to that port. Client IDs are routing IDs,
not tensor-map traffic classifications. The outer parent/native arbiter
still owns the final public DDR port.

| Assembly boundary | Registered behavior |
| --- | --- |
| Start E0 | Capture every native field; no child start or memory command derived from live input |
| E1 validation | Reject native model/precision with 6; reject context, enabled-modality geometry, alignment and full text/mask address-range errors with 5 |
| Session cache barrier | Issue a real cache invalidate and wait for its response; no new execution is dispatched |
| Frontier barrier | Configure executor, which releases old frontier/ring visibility before responding |
| Replay binding | Configure actual owner/replay engine with the same captured generation/context and selected ordinary/fallback mode |
| Schedule start | Dispatch only after all three preceding barriers succeed |
| Metadata ingress | Capture selected full command, then offer to cache on a later edge; register its actual response before requester visibility |
| Mask ingress | Capture requester/token, validate, issue actual read, register accepted response, then publish held mask/error |
| Fallback transition | Existing executor releases frontier and ring before binding base-zero replay backing and starting actual Eval |
| Final result | Schedule waits for actual output completion, including final-logit acceptance |
| Completion drain | Wait for executor, replay and both routers to be idle before asserting arbiter drain; acknowledge drain before publishing done |
| Stalled done | Hold error and valid; do not admit another context |
| Reset | Cancel child/router generations and arbiter work; all public outputs zero |
| C=1/C=3/C=64 | Same literal cache, explicit replacement wrap; no capacity-dependent router widths |

Draining cannot close the memory arbiter while a worker still needs to
finish: both the drain request and its state transition use the same
worker/router-idle condition. Configuration and execution errors retain
their real child error and follow the drain boundary. A descriptor rejected
before dispatch issues no child or memory request. Public prefill/decode session validation, positions-array validation and
parent mode routing belong to the enclosing top described above, not to
this complete-context execution interface.

### Allocation observation vector

`allocation_live_bytes` and `allocation_physical_bytes` contain 25 unsigned
64-bit fields, field i at `[64*i+:64]`. These are named component reports,
not a complete accepted live ledger. No aggregate savings or allocator
success is inferred from them.

| i | Component |
| --- | --- |
| 0 | Frontier payload RAM, including its physically disjoint replay tail |
| 1 | Local anchor ring |
| 2 | Ordinary hidden/PLE live reservations; physical field counts the hidden bank |
| 3 | Ordinary reconstructed native-feature live reservation; physical field counts the shared feature/PLE bank |
| 4 | Anchor materialization worker's reported vector storage |
| 5 | Actual workspace frame/memo/scalar live payload |
| 6 | Owner raw-source/in-place normalized-source vector |
| 7 | Owner projection/normalization head tile, excluding the shared source bank |
| 8 | Replay text tile |
| 9 | Replay PLE vector |
| 10 | Replay embedding vector |
| 11 | Replay post-attention/MLP vector |
| 12 | Replay vision vectors |
| 13 | Replay audio vectors |
| 14 | Replay audio-feature vectors |
| 15 | Replay image-feature vectors |
| 16 | Binding's own controller registers |
| 17 | Native assembly's own descriptor/router/controller registers |
| 18 | Occupied resident KV pairs |
| 19 | Ordinary embedding reconstruction's input/PLE payload |
| 20 | Ordinary text attention/PLE/MLP payload |
| 21 | Standalone final-head normalized vector; zero in the connected external-bank mode, charged in field 2 instead |
| 22 | Reported replay subtree controllers, including workspace and owner-source control, excluding field 16 |
| 23 | Native memory arbiter, frontier scheduler and cache controller registers |
| 24 | Ordinary executor, frontier/ring control, embedding, full text, anchor and final-head scalar/numerical state |

Fields 19..21 originate at the payload owners rather than the dispatch mux.
The embedding worker reserves its `2H` input at legal validation and its
`2P` PLE bank before the first projection starts. Each remains charged until
its final output handshake; error publication releases abandoned banks.
The standalone final head reserves `2H` through its arithmetic and output
stalls. The connected head instead overwrites the retained field-2 hidden
bank in place after each raw component's last normalization read. Its
field-21 payload and physical reservation are zero, not a second copy.
Text-bank lifetimes and their actual physical overlay are specified below.
Replay input and text workers now forward these same embedding/post
owner reports instead of deriving visibility from the caller's current
worker selection. Both embedding instances are summed, so a retained
child allocation cannot disappear merely because dispatch changed.

### Text-bank lifetime and physical overlay

The integrated native assembly physically overlays the ordinary full text
worker's work/branch/PLE banks with the replay text POST_ONLY
worker's corresponding banks. Ordinary residual instead shares its executor's
retained hidden bank as specified above; the fourth phase bank remains for
replay residual and embedding. Both text workers select `EXTERNAL_VECTOR_RAM=1` through
their enclosing wrappers; standalone defaults remain 0. For each of four
banks (residual/work/branch/PLE in ascending packed-lane order), the
external interface exposes write/read enables, 12-bit component addresses
and 16-bit write/read data. Each enabled read updates its corresponding
registered data on that rising edge, exactly like the local-RAM default.
No ready signal, asynchronous read or added callback latency is introduced.
The assembly owns one physical set of these four synchronous RAMs.

The full worker runs only on ordinary text tasks; on that path owner misses
read the frontier rather than running text Eval. Native-feature Eval happens
before the ordinary text worker starts. Fallback runs text Eval instead of
the ordinary worker. Replay POST_ONLY retains no bank across a yielded
dependency: its result is checkpointed into the workspace before that
worker completes. Thus these two sets cannot have concurrently live vectors.
The assembly detects simultaneous bank requests or live allocations as
a sticky protocol fault, not as permission to silently overwrite a worker.
Active reset disables all shared-bank accesses; generation/visibility
state stays in the workers and is not initialized by clearing payload RAM.

Physical field 20 includes the shared bank set once, plus the full worker's
separate attention-output bank. Physical field 11 is zero for this integrated
POST_ONLY worker. Live fields 20/11 continue to report the actual requesting
worker's vector lifetimes; bytes are not dropped merely because physical
ownership moved to the assembly. This removes another 15872 production /
56 compact declared payload bytes compared with two local bank sets;
independent allocation observations and source-matched FPGA inference
remain mandatory.

The full and POST_ONLY workers share each query head with the subsequent
attention-output/MLP branch in **one declared H-component synchronous RAM**.
There is one registered read port and one write port for this shared bank.
Each query finishes before the next query overwrites it; the final query
retires before the output projection first writes the branch. Norm source/
destination selection and rotary split-half indices are unchanged.
POST_ONLY elaborates no attention-output RAM, rather than merely reporting
that a declared attention bank is unused.

Physical payload is `2*(3*MAX_H+P+Q*MAX_D)` for full text and
`2*(3*MAX_H+P)` for POST_ONLY. Production reservations are respectively
24064 and 15872 bytes; compact reservations are 88 and 56 bytes.
Residual, normalized-work, shared query/branch, attention-output and PLE
allocations have separate registered lifetime bits:

| Bank | Reservation begins | Reservation ends |
| --- | --- | --- |
| Residual, `2H` | Successful descriptor validation, before source loading | Accepted last output value |
| PLE, `2P` | First accepted PLE source request | Last PLE gated-projection row is written |
| Normalized work, `2H` | Input or pre-FF norm setup, before any write | Last attention head completes, or last MLP row is written |
| Query, `2D`, in shared bank | Query projection descriptor | That attention head completes |
| Branch, `2H`, in shared bank | First POST_ONLY branch-load request, output-projection start or gated-projection start | Final residual-add row is written |
| Attention output, `2Q*D` | First attention-head start | Final output-projection row is written |

Error publication releases all remaining text-bank reservations after the
failed child has retired. Internal source replies reject an unallocated
bank as well as an out-of-range index. Scalar output/readback copies remain
charged by the controller census after their vector bank is released.
These are whole-bank occupied-prefix reservations, not one-word-at-a-time
claims or physical resource measurements.

The ordinary executor allocates its hidden output bank only when
embedding starts, not throughout preceding native-feature reconstruction.
Its PLE reservation starts with embedding for text tokens; for native
placeholders it starts when the final successful feature callback retires,
as described below.
Initial frontier fill discards PLE at embedding commit. Other layers free
the transport PLE only after the leaf accepts its last PLE source reply;
the leaf's own copy remains charged. Failed tasks release all abandoned
transport banks at publication. The owner source and tile banks retire at
the actual tile-result handshake, while the returned pair remains charged
as scalar state through a stalled regeneration response. Tile live bytes
use `2*(H+D)`; its separate maximum physical reservation is unchanged.

Replay text now retains a separate PLE allocation bit across
EMBED_WAIT -> EMBED_REGISTER -> POST_START. A completed vector no longer
disappears from the ledger for the intermediate commit cycle merely because
the child selection changed. PLE visibility still requires successful
component-count/tag checks; error publication releases the allocation.

Fields 22..24 charge the reported registers continuously outside reset,
including inactive instances and held payload/readback registers. This
is a conservative reservation, not a phase-dependent claim that idle
registers have been physically removed. Their physical fields equal
their live reservation fields. They include no vector/tag RAM already
charged in other fields.

Field 22 sums the existing text, vision, audio and feature-controller
reports across **all** literal instances, not the selected worker mux.
The selected-worker report remains available at the replay leaf but is
not added again. Eval scheduling and workspace controllers are included
once, with scheduler size derived from its declared register widths
instead of the previous fixed 175-byte value. The binding's own
controller remains separately charged in field 16.

Workspace metadata now counts exactly its two tag arrays, frame/vector
reservation/visibility maps, pair/memo visibility maps, pair-progress components, memo domains and
scalar occupancy bitmap. All other workspace registers, including tag
readback copies, continuations, partial-copy words and pending-allocation
counters, belong to its controller report. This partitions that leaf's
declared state rather than hiding control words in a tag-array subtotal.
Cache, frontier and ring controllers likewise exclude their separately
reported resident/frontier/ring payload and tag/occupied arrays while
including returned/stalled data copies.

Physical field 5 is zero **only because** the actual backing RAM is
physically counted once in field 0. `workspace_reserved_bytes` separately
reports the logical backing partition, and `workspace_shadow_bytes` the
existing production-width shadow allocation. Neither may be silently
substituted for live bytes. Metadata has four separate 64-bit fields:
frontier token tags, ring token/lane tags, workspace visibility metadata,
and resident tags/occupied bits. Primitive and enclosing-top scalar state
now enter the reports as described below; transient-vector liveness,
short-context native scratch, ordinary workspace and the full fallback
ceiling remain to be enforced. Physical field 0 is not a claim that all its reserved words are
live or that FPGA resource fit is established.

The binary32, division/sqrt, unsigned conversion, exp, activation,
normalization, projection, Q4/BF16 weight reader, GeGLU, gated projection,
softcap, frequency, sin/cos, rotary and tensor-directory primitives now
expose declared-register censuses. Compound primitive reports include
each literal arithmetic child once. Their native vision/audio parents
add these reports to the existing controller categories; separately
exposed native child-controller reports remain separate, not added twice.
The ordinary embedding/text/final workers and owner tile similarly sum
their own scalar/readback registers and their literal primitive children.
Replay input/post, attention-projection, checkpoint and K/V wrappers
forward these through fields 22/24. The previous fixed 74/100/53-byte
checkpoint/executor/tile estimates have been replaced by declared-width
censuses, including partial pairs and retained dependency descriptors.
Combinational function temporaries and loop-unrolling indices are not
stored state; synchronous RAM readback registers are.

### Primitive reservation inventory and exponential arithmetic overlay

The following inventory is derived from the declared RTL registers and literal
child connections, not an executed allocation measurement. Own reservations
round the complete local census upward to a byte before adding child reports.
They remain charged while reset is released, including idle, failed and stalled
operations. Consequently starting an arithmetic operation does not allocate
additional scalar storage: its operands, partial products, reductions, readback
copies and held response are already in the controller reservation used by
prospective admission. Vector/RAM payload remains separately admitted; it is
not part of this justification.

Names in this table have prefix `anvil_en1_`. Child reports are additive for
literal instances, not multiplied by the number of times their FSM is called.
All entries apply to both precisions and both model geometries.

| Primitive | Local reserved bits / bytes | Literal arithmetic children included in report |
| --- | --- | --- |
| `fp32` | 542 / 68 | None; includes all four partial products and three 48-bit product/reduction registers |
| `fp32_divsqrt` | 500 / 63 | None; includes division, square-root and reciprocal-square-root continuations |
| `uint_to_fp32` | 79 / 10 | None |
| `uint_div` | 144 / 18 | None |
| `bf16_clamp` | 75 / 10 | None |
| `exp` | 220 / 28 | One `fp32` in standalone mode; none in external-arithmetic mode |
| `activation` | 403 / 51 | One external-arithmetic `exp`, one `fp32_divsqrt`, plus one `fp32` only in standalone mode |
| `softplus` | 407 / 51 | One `fp32`, one external-arithmetic `exp`, one `fp32_divsqrt` |
| `norm` | 490 / 62 | One each of `uint_to_fp32`, `fp32_divsqrt`, plus one `fp32` only in standalone mode |
| `rope_frequency` | 134 / 17 | One `fp32_divsqrt`, plus one `fp32` only in standalone mode |
| `sincos` | 589 / 74 | One each of `uint_to_fp32`, `fp32_divsqrt`, plus one `fp32` only in standalone mode; local reservation conservatively also includes the two combinational quadrant words (64 bits), not additional physical storage |
| `rotary_pair` | 472 / 59 | One each of external-arithmetic `rope_frequency`, external-arithmetic `sincos`, `uint_to_fp32`, plus one `fp32` only in standalone mode |
| `softcap` | 208 / 26 | One each of `fp32_divsqrt`, external-arithmetic `activation`, plus one `fp32` only in standalone mode |
| `geglu_pair` | 179 / 23 | One external-arithmetic `activation`, plus one `fp32` only in standalone mode |
| `weight_read` | 1335 / 167 | One `fp32` only in standalone mode; local count includes the complete extent/address partial products |
| `projection` | 514 / 65 | One external-arithmetic `weight_read`, plus one `fp32` only in standalone mode |
| `gated_projection` | 1226 / 154 | One each of external-arithmetic `projection`, `geglu_pair`, `weight_read`, plus one `fp32` only in standalone mode |
| `attention_head` | 1056 / 132 | One each of external-arithmetic `exp`, `fp32_divsqrt`, plus one `fp32` only in standalone mode |

`exp.EXTERNAL_FP` accepts exactly 0 or 1 and defaults to 0. Mode 0 retains
the standalone binary32 unit and its full reservation; its additional
arithmetic request outputs are zero and its additional response inputs are
unused. Mode 1 removes that literal unit at elaboration and exposes its
unchanged registered `start`/`done` transaction through
`arithmetic_valid/ready`, `arithmetic_operation[2:0]`,
`arithmetic_a/b[31:0]`, and
`arithmetic_result_valid/ready/data[31:0]/error[3:0]`.
Only the absent unit's byte contribution becomes zero. The exponential
descriptor, polynomial, operands, coefficient counter, power and held
result/error all remain reserved.

Every current exponential consumer selects mode 1:
`activation`, `softplus`, `attention_head`, `vision_attention_head`,
`audio_attention_head`, and `audio_relative_position`. Each routes one
binary32 service, supplied locally or by its enclosing worker. During its complete EXP_START/EXP_WAIT interval
(EXP_SEND/EXP_WAIT in vision attention), it routes that unit exclusively
to the exponential FSM; otherwise it routes it to its original arithmetic
FSM. This is a physical scalar-state overlay, not a phase-dependent omission
of live registers. Parent scalar reductions and all exponential scalar state
remain separate. Reports remove exactly one 68-byte binary32 child per
literal exponential instance relative to the preceding unshared exponential
implementation, in both actual and production-shadow
controller ledgers. Repeated calls do not multiply this declaration delta;
no system-wide byte total, FPGA resource saving or timing result is inferred.

| Boundary | Ownership and registered behavior |
| --- | --- |
| Reset | Both FSMs and the one physical arithmetic unit reset; arithmetic request/response outputs are zero |
| Enter exponential phase | The parent's preceding binary32 response has already been accepted before the parent prepares the exponential argument and enters its send state |
| Exponential start acceptance | The child registers its operand; it cannot issue an arithmetic request on the same acceptance edge |
| Child arithmetic request | The child's existing MUL_START/ADD_START states hold operation/operands until the physical unit accepts; no parent arithmetic start can occur in an exponential phase |
| Child arithmetic result | Only the child's existing MUL_WAIT/ADD_WAIT states assert result readiness; the parent remains in its exponential wait state and cannot consume the binary32 result as its own |
| Exponential response | The child's final binary32 response retired before its existing PUBLISH/RESPONSE states; the parent accepts the held exponential result/error before changing phase |
| Parent arithmetic resumes | The shared unit is already idle; original parent FP_START/FP_WAIT sequencing resumes without a new arithmetic stage or changed reduction order |
| Stalled child/parent result | Phase selection and registered request payload remain stable until the corresponding acceptance; no arbitration queue or second transaction exists |
| Error | An arithmetic error follows the unchanged exponential error publication, then the unchanged parent error retirement; ownership does not switch with an outstanding transaction |
| Single operation / repeated calls | Identical sequencing; the physical unit's normal response acceptance returns it to IDLE before reuse |

This retires the primitive scalar-growth grant question: those registers are
statically reserved, rather than dynamically allocated at arithmetic start.
It does not retire the whole-system register census, other physical overlay
opportunities, fallback partition fit, native-scratch fit or legal-case
feasibility after memo eviction. No arithmetic request is permission to
spill or to ignore a failed admission. Independent numerical, stalled-channel,
allocation and synthesis checks remain required.

### Serialized projection/activation arithmetic ownership

`weight_read`, `projection`, `activation` and `geglu_pair` now also accept
`EXTERNAL_FP=0/1`, default 0, with the same explicit illegal-value diagnostic
and arithmetic channel as `exp`. Mode 0 declares exactly one local binary32
unit; mode 1 removes that declaration and forwards the selected registered
request/result handshake to its parent. All additional outputs are zero in
standalone mode or active reset. No public top, cache, source-vector, tensor,
memory or numerical interface changes.

The default projection routes its unit to the weight reader throughout
WEIGHT_START/WEIGHT_WAIT, including memory and decode stalls. Outside that
phase it retains its original source-conversion, multiply, ascending-column
sum and final BF16 materialization schedule. The default GeGLU pair routes
its unit to activation throughout ACTIVATION_START/ACTIVATION_WAIT, including
the nested exponential arithmetic; its subsequent gate/product
materializations are unchanged.

Gated projection selects external arithmetic for all three children:
projection, GeGLU pair and down-weight reader. Its one local unit serves
PROJECTION_START/PROJECTION_WAIT, GATED_START/GATED_WAIT and
DOWN_START/DOWN_WAIT respectively; outside these disjoint phases it serves
the original multiply, accumulation and final materialization FSM.
Projection's weight reader and GeGLU's activation/exponential forward
their requests through this same channel; they do not declare hidden
binary32 units. Softcap similarly selects external arithmetic for its
activation child during TANH_START/TANH_WAIT and retains its local unit for
the final multiply/narrow. Division/sqrt units remain physically separate
and fully charged; this increment does not remove their reservations.

The following byte counts are declared-width reservations derived from the
inventory above, not synthesis or measured allocation. They include every
local scalar and literal descendant controller, even while idle. They apply
equally to actual and production-shadow controller terms.

| Subtree | Before this increment | Current standalone | Current external-FP mode |
| --- | --- | --- | --- |
| `weight_read` | 235 | 235 | 167 |
| `projection` | 368 | 300 | 232 |
| `activation` | 210 | 210 | 142 |
| `geglu_pair` | 301 | 233 | 165 |
| `gated_projection` | 1126 | 786 | 718 |
| `softcap` | 367 | 299 | 231 |

Thus a literal gated projection has one, not six, physical binary32 units,
removing five 68-byte reservations relative to the immediately preceding
source. Its 154-byte enclosing controller, two 167-byte weight-reader
controllers, 65-byte projection controller, 23-byte GeGLU controller,
51-byte activation controller, 28-byte exponential controller and
63-byte division controller all remain charged. These are per-subtree
totals, not additive system totals: do not add a child's standalone total
again to an ancestor that already includes it. Other literal instances
elsewhere in the design remain separate and charged.

| Boundary | Ownership and registered behavior |
| --- | --- |
| Reset / first released edge | All existing FSMs and the one physical unit reset; arithmetic outputs are zero during reset. Release alone creates no request; descriptors still require their original start acceptance |
| Child phase entry | Any earlier local arithmetic response has retired. The parent's registered state selects the child from its start state through its accepted done response |
| Child start | Registers its descriptor before generating arithmetic; it cannot start an arithmetic operation on its own descriptor-acceptance edge |
| Nested request | Only the selected child path supplies valid, operation and operands. Every forwarding level is combinational routing of registered state, not another storage allocation, numerical stage or combinational arithmetic recursion |
| Request stall | Child state and operands remain held. Parent stays in that child's phase; neither sibling nor parent can start a competing operation |
| Result stall | Only the selected child's arithmetic wait state supplies readiness; siblings cannot consume the response |
| Child memory/source/output stall | Keep ownership through the complete child task, even when it is not currently using the binary32 unit |
| Done / phase exit | The child's last arithmetic result retires before its existing PUBLISH/RESPONSE states. The parent cannot switch phase until accepting the held child done/result |
| Arithmetic or memory/source error | Existing child error is retained and propagated through its original done states. No new start, phase switch or hidden spill bypasses outstanding work |
| C=1/3/64, one token, partial Q4 row | Ownership is independent of resident capacity and loop trip count. Original exact row boundaries, nibble order, conversion and reduction order remain unchanged |
| Repeated calls | The physical unit is idle after its accepted result, before the next request; no tags, queue, speculative request or extra transaction state is introduced |

This closes the local serialized projection/activation-subtree physical
overlay milestone. Controller reporting follows the literal generated
hierarchy; no phase-dependent masking of retained scalar state is used.
The forwarding muxes feed the existing registered binary32 input boundary,
not an unregistered numerical result. Their target-device timing still
requires source-matched STA. Whole-system census, remaining overlays and
legal-case ordinary/native/fallback fit remain open; these declaration
reductions do not establish any system-level storage or traffic pass.

### Normalization/rotary arithmetic ownership

The next scalar overlay uses the existing arithmetic channel for `norm`,
`rope_frequency`, `sincos` and `rotary_pair`, with `EXTERNAL_FP=0/1`,
default 0 and an explicit diagnostic for other values. Only the literal
binary32 unit is optional. Every descriptor, reduction, partial result,
held response, integer converter and division/square-root unit stays
declared and fully charged. Normalization's source/scale callbacks,
reduction order and BF16 boundaries are unchanged.

Rotary frequency generation, position conversion, trigonometry and pair
rotation are serialized by its existing registered FSM. Frequency and
trigonometry use external FP mode and share the rotary unit. The owner
tile selects external mode in projection, normalization, scale reader and
rotary, serving them with one physical unit. A native normalization worker
similarly shares one unit between normalization and its scale reader.
Existing standalone callers need no additional connections.

| Cycle / degenerate boundary | Ownership rule |
| --- | --- |
| Reset / first released edge | All existing FSMs and the one unit reset; arithmetic outputs are zero in active reset. Release without a start creates no request |
| Rotary phase | FREQUENCY_START/WAIT selects frequency; TRIG_START/WAIT selects trigonometry; otherwise only the original FP_START/WAIT can use FP |
| Owner projection / rotary | Complete PROJECTION_START/WAIT and ROTARY_START/WAIT phases select their respective child |
| Owner/native normalization | Complete NORM_START/WAIT selects normalization except during SCALE_START/WAIT, which selects the scale reader |
| Scale callback entry | Norm has retired its preceding FP result before requesting a scale. It waits for the scale response without issuing arithmetic; the nested reader owns FP until its done is accepted |
| Scale callback exit | Reader's FP result retires before its done response; SCALE_REGISTER/PUBLISH/RESPONSE retain the scale result while the now-idle FP service returns to norm |
| Pre-edge handshake / post-edge update | Existing starts/results sample pre-edge valid and ready. State and descriptor changes occur post-edge; no newly created valid is consumed at its creation edge |
| Request, memory, source or result stall | Registered phase and operands hold; no instantaneous-valid priority arbitration or owner change is allowed |
| Error / child done | Existing error and done paths drain their transactions before ownership changes; no new queue or hidden replay spill |
| One-element vector, zero index, partial global rotary | Existing loop/identity/error paths apply unchanged. A skipped arithmetic phase has no transaction to retire |
| C=1/3/64, repeated calls | Capacity does not affect ownership; accepted arithmetic responses return the unit to IDLE before reuse |

Declared reservations (bytes, including descendants, not measured allocations):
`norm` is 203 standalone / 135 external, `rope_frequency` 148 / 80,
`sincos` 215 / 147, and `rotary_pair` 364 / 296 after its two child
overlays (previous rotary total 500). Native normalization removes one
68-byte unit from its full child sum. The owner's projection/norm/scale/
rotary arithmetic subtree is 898 bytes instead of 1238; its enclosing
controller, tensor directory and payload banks are unchanged. Ancestor
reports consume those literal child reports; these nested reductions must
not be added a second time. No whole-system feasibility, inferred resource,
timing or functional result follows from these declared widths.

The cache now exposes actual `resident_live_bytes = 4*resident_count`.
Insertion increments the count only when replacing an unoccupied slot;
successful invalidation clears it with the occupied bitmap. Physical
resident payload is `4*C`, with tag/occupied metadata reported separately.
Hit/miss events occur once on the validated lookup decision, not on each
cycle of a stalled fetch response. Alias events occur on accepted successful
aliased metadata responses. None counts an error or cancelled lookup as a
hit/miss, or changes the existing metadata/fetch cycle table.

### Text-worker arithmetic ownership and post-only elaboration

`gated_projection`, `softcap` and `attention_head` accept `EXTERNAL_FP=0/1`,
default 0, with the same arithmetic channel and explicit illegal-parameter
diagnostic as the preceding primitives. Default standalone use remains
self-contained. External mode physically omits only the binary32 unit:
all scalar reductions, tensor descriptors, checkpoint copies, activation
state, exponential state and divider state remain declared and reported.
The attention-head subtree is 291 bytes standalone or 223 external, including
its 132-byte local controller, 28-byte exponential and 63-byte divider.

`asym_attn_ple` selects external mode in its norm, scale reader, projection,
rotary, attention and gated-projection children. `embedding_ple` selects it
in norm, weight reader and projection; `final_logits` selects it in norm,
scale reader, projection and softcap. Each enclosing worker declares exactly
one binary32 service. Requests and results traverse combinational selection
of registered phase, operation and operands into the existing unit's
registered input boundary. Selection adds no queue, numerical stage, operand
storage or reordered reduction. Every existing response boundary still
requires acceptance before the dependent next phase starts.

| Cycle / degenerate boundary | Ownership and behavior |
| --- | --- |
| Reset / first released edge | Existing FSMs and the one physical unit reset; arithmetic outputs are zero during active reset. Release without an accepted start cannot create a request |
| Text worker | Complete NORM_START/WAIT, PROJECTION_START/WAIT, ROTARY_START/WAIT, ATTENTION_START/WAIT and GATED_START/WAIT select their respective child; otherwise only local FP_START/WAIT may use the unit |
| Text norm callback / layer scalar | W_START/WAIT or SCALAR_START/WAIT exclusively select the weight reader, overriding norm selection for the nested scale callback |
| Embedding worker | Complete PROJECTION_START/WAIT and NORM_START/WAIT select the corresponding child, except WEIGHT_START/WAIT or SCALE_START/WAIT select its weight reader; all other arithmetic belongs to the original local FSM |
| Final logits | Complete NORM_START/WAIT or PROJECTION_START/WAIT select the child; W_START/WAIT overrides norm for scale decoding; SOFTCAP_START/WAIT selects softcap. All children are idle outside their tasks |
| Nested callback entry | Norm has retired its preceding arithmetic response before requesting a scale. It cannot issue another arithmetic request while waiting for that scale |
| Nested callback return | The reader retires its last arithmetic response before publishing its held done. Parent scale-register/publish/response states retain the scale result while the now-idle service returns to norm |
| Stalled request, source, memory or child done | Keep the same phase owner, registered operation and operands. An idle arithmetic cycle is not permission to reassign an active child task |
| Stalled arithmetic result | Only the selected child's wait state supplies readiness; neither siblings nor the enclosing local FSM consume it |
| Error / phase exit | Existing arithmetic, source and memory error paths retire the child normally before changing ownership. No new transaction, spill or success-shaped fallback |
| Repeated calls, one component, partial Q4, C=1/3/64 | Identical service ownership; original loop counts, row boundaries, nibble order, conversion, reduction and materialization rules remain unchanged |
| POST_ONLY branch input | Load the supplied hidden attention branch after residual/PLE input, then enter N_POST_ATTENTION directly. No query projection, rotary, attention or output-projection task is started |
| POST_ONLY physical omission | Elaboration does not declare the direct projection, rotary or attention child. Their reports and unused request/result outputs are constant zero. The enclosing controller, norm, weight reader, gated projection and one binary32 service remain fully charged |

The post-only optimization is not omission of attention from replay inference:
`replay_text_layer` still invokes its connected attention executor before
supplying that branch to the post worker. The full ordinary worker retains
its real attention/projection/rotary instances. Both configurations preserve
the public source, cache, memory, output and done interfaces and their
registered behavior. The already-absent POST_ONLY attention payload remains
absent; no new payload RAM or dynamic reservation is introduced.

The following declared controller-subtree totals exclude the enclosing worker
controller and tensor directory, which remain separate and unchanged. They
include every named child exactly once and apply to actual and production
shadow scalar reservations in both models and precisions.

| Worker arithmetic subtree | Before text-worker overlay | Current |
| --- | --- | --- |
| Full text: norm, projection, rotary, attention, gated projection, weight reader and local FP | 2247 bytes | 1839 bytes |
| POST_ONLY: same previously declared children | 2247 bytes | 1088 bytes |
| Embedding: norm, projection, weight reader and local FP | 806 bytes | 602 bytes |
| Final logits: norm, scale reader, projection and softcap, including new shared FP | 1037 bytes | 833 bytes |

The full-text delta is six absent 68-byte units. The post-only delta also
removes the 232-byte external projection, 296-byte external rotary and
223-byte external attention subtrees. Embedding and final logits each remove
three physical units; final logits replaces four child units with one new
shared unit. These are literal per-worker deltas, not additive hierarchy or
whole-system totals. Enclosing reports already include them. Physical sharing
of these scalar units does not retire the whole-system census, other
overlays, ordinary/native/fallback partition-fit proof or memo-eviction
feasibility. No synthesis, timing, numerical, traffic or measured allocation
result is claimed.

No commands, elaboration, simulation, synthesis or preparation probes have
run for these arithmetic increments. Independent verification remains pending;
the reserved static elaboration is still unused.

## Ordinary native-feature routing and disjoint replay backing

### Owner/frontier arbitration onto the real replay engine

`anvil_en1_replay_binding` contains literal, connected `owner_replay`,
`replay_execute` and two-client `memory_arbiter` instances. It binds a native
session with registered model/precision/modality/generation/context and
immutable text/image/audio source and weight-image descriptors. Control
is accepted only while both engines and the root router are idle.
Successful owner configuration is required before regeneration or Eval
ingress opens. A pending control closes new regeneration/root ingress,
but does not disable the routes needed to finish accepted work.
In particular, an already accepted owner regeneration may still start its
required internal Eval root while control is pending. Blocking that root
would deadlock the control's own idle/drain precondition. New frontier
roots remain blocked, and the enclosing barrier must finish frontier
work before presenting session control.

The cache alone drives its regeneration input. Ordinary owner projections
use its tagged frontier/ring callbacks. Fallback owner projections request
a real domain-0 Eval root; the returned ordered hidden vector feeds the
existing normalized/rotated K/V projection worker. Frontier input features
and full fallback text execution use the other Eval requester. Both share
one literal continuation/memo/arithmetic implementation and one backing
channel, not replicated replay engines or software answers.

Owner roots have priority when both start channels are offered. The
router captures the selected complete root descriptor before validating
and sending it to the scheduler. No priority change can replace a
stalled scheduler descriptor. Exact session fields are checked; invalid
native model/precision errors use 6 and descriptor/session mismatches use
7 before scheduler/backing/memory access. Only the captured requester
receives the output stream and held completion. This priority is not
preemption: an accepted root executes to actual completion.

| Binding boundary | Behavior |
| --- | --- |
| Session C0 | Capture every descriptor field and close data ingress |
| Session validation | Validate model, precision, context and text/weight alignment before dispatch to owner configuration |
| Configuration response | Propagate the actual owner error; open new ingress only after successful configuration and the held control response retires |
| Competing root R0 | Accept only owner, otherwise frontier; register descriptor and response owner |
| R1/R2 | Validate captured session identity, then offer a registered descriptor to the real scheduler |
| Root output/completion stall | Route only to the captured requester; no new root/control can overwrite its descriptor |
| Root final output | After the last accepted pair, invalidate real workspace visibility through its acknowledged control channel before publishing done |
| Root failure | Drain/clear workspace, then hold explicit requester-specific error completion |
| External command | Two-client registered arbiter retains command, response and issuing owner until their actual handshakes |
| Reset | Zero public outputs/validity and cancel all three literal instances |

Local memory-owner IDs 0/1 distinguish owner projection from replay
execution; they are not memory-address classes. An enclosing arbiter
still owns the actual external DDR port. Native weight/input traffic must
be classified from the tensor map, including failed accepted reads,
not inferred from these local IDs. Replay's cache metadata port is
outward; there is no duplicate owner map inside this binding.

Workspace frame/memo live/shadow/reserved/metadata, owner source/tile,
text tile, PLE/embedding/post, native encoder and image/audio feature
live/physical reports are passed through as separate quantities. Its
own 840-bit controller is explicitly reported as 105 bytes using the
declared register widths. These reports do not yet include every child
controller, primitive, arbiter, transient or top state and are not a
complete admitted allocation ledger.

Every successful Eval root now releases workspace memo/frame/scalar
visibility after its last accepted output, before done. Memo reuse and
eviction *within* that root are unchanged; new roots already performed a
fresh workspace binding, so no cross-root reuse is lost. Image worker
cancellation is connected to accepted root completion as well as a new
root, releasing an abandoned suspended image continuation after failure.
Normal lower-rank yields do not cancel the retained numerical worker.
The enclosing session barrier must still wait for actual root/owner
completion and all shared cache/memory responses before reusing RAM.

### Ordinary feature transport and physical partition

The ordinary frontier executor now sends a native placeholder to the same
real Eval engine used by fallback: `eval_domain=3`, `eval_layer=1` for image
or 2 for audio, and `eval_token` is the original text position. Text fallback
continues to use domain 0 and its requested text layer. The Eval descriptor
is held through request acceptance. The ordinary executor starts embedding
only after H ascending feature values, an exact last flag and successful
actual Eval completion have all been observed.

Features and ordinary transport PLE now share one synchronous BF16 RAM,
distinct from both the frontier and retained last-token hidden vector.
The latter must survive native feature evaluation for upper shared layers.
The shared bank reserves 5120 bytes in production and 16 bytes in compact
builds, reported only by `feature_physical_bytes`; `vector_physical_bytes`
reports the separate hidden bank, without another PLE array. This removes
512 production or 8 compact declared payload bytes, not measured FPGA RAM.

`feature_live_bytes` charges the full selected `2*H` bytes from feature
request acceptance, including partial/error reception, through the final
successful feature callback acceptance. That edge releases feature
visibility and reserves the `2*P` PLE prefix in `vector_live_bytes`.
Embedding consumes all H feature components in ascending order into its
own input bank before projection, PLE normalization or any PLE output.
The last callback's registered scalar remains charged in controller state.
The feature and PLE vector lifetimes therefore do not overlap. For text,
PLE is reserved at embedding start. PLE writes require this reservation
and no live feature; a violating stream sets the existing input error.
Failed feature/embedding completion releases abandoned reservations.
The single shared RAM has one synchronous write port (feature fill or
later PLE fill) and one synchronous read port (feature callbacks or later
PLE source callbacks). Hidden reads/writes use their independent RAM.

Embedding's native callbacks read only this completed, generation/token/kind
tagged bank. Every callback is captured, checked, synchronously read and
registered before response. Bad model/kind/token/index, missing completion
or stale generation returns an explicit source error. The response is held
through backpressure. An actual embedding completion cancels any abandoned
internal callback before another task is admitted. No native feature can
arrive from the legacy outward modality response inputs; outward modality
requests and response readiness are zero in this executor.

The existing frontier payload RAM now provides **disjoint ordinary replay
backing**, rather than trying to reuse live text words. In production,
ordinary frontier word addresses are below 786432 and ordinary replay word
b is physically `786432+b`. In compact builds the corresponding split is
2048 words, matching the unchanged 8192-byte ordinary frontier cap. The
backing request remains a relative 18-bit word index, with the same range,
generation checks and acknowledged synchronous access as fallback.
`backing_bound` now denotes backing availability in either valid ordinary
mode or explicitly bound fallback mode.

| Backing boundary | Registered behavior |
| --- | --- |
| Ordinary configure | Validate/allocate the unchanged padded frontier; only a successful allocation enables the disjoint backing |
| Ordinary read/write | Capture relative address/data/generation; validate, then access the physical tail and publish its held response |
| Frontier versus replay access | One RAM transaction at a time; control, vector write and vector read retain priority over backing ingress |
| Ordinary-to-fallback | Drain accepted work, release frontier and ring, then bind op 3; fallback backing uses physical base zero |
| New ordinary session | Release any fallback binding first; invalidation clears visibility, not payload bits |
| Range/generation error | No payload access; acknowledged error 7 |
| Reset | Public outputs/visibility zero; no initialization advertises payload as readable |

The physical shared RAM reservation is now 1017856 words / 4071424 bytes in
production and 208896 words / 835584 bytes in compact builds. This is one
array, not a simultaneous copy of ordinary and fallback payload. The
ordinary 3 MiB cap and all live-payload acceptance limits are unchanged.
Unused physical tail capacity is not a KV-memory saving. Workspace live
frames/memos/scalars, suspended native worker scratch and the feature bank
still require complete phase-overlay accounting and enforcement of
`M <= min(1 MiB,floor(B/8))`; the physical partition alone does not establish
this bound, resource fit or 100 MHz timing. Whole-system binding and
independent verification remain pending.

## Durable causal-convolution history layout

### Durable image placeholder-to-feature execution

`anvil_en1_replay_image_feature` implements domain-3 layer 1 by connecting
the immutable text-placeholder mapper to `anvil_en1_vision_soft_token`.
The mapper supplies the actual image ordinal and total placeholder count.
The physical pool count is the exactly checked integer quotient
patches/9 from the sequential divider; a remainder is an error. The
existing vision-bin mapper still validates the coordinate directory,
grid, occupied physical bins and expected valid soft-token count.
Neither the placeholder ordinal nor a source patch is an image feature.

The real pool requests domain-1 layer-16 components. A missing patch
memo yields Eval(16,patch) at rank 17, below feature rank 18, while
retaining the literal soft-token/pool FSM and its RAM. It does not restart
pooling from a partial sum or substitute a host encoder answer. Each
component keeps the original ascending-patch binary32 multiply/add
order, pool BF16 boundary, sqrt(768) scaling, modality normalization and
projection. This can regenerate an evicted patch for another component;
there is no latency or total-weight-traffic improvement claim.

Image continuation is
`{0x454e3149,generation[31:0],text_position[31:0],patch[31:0],component[31:0]}`.
The worker checks the complete resumed model, precision, modality,
generation, text extent, text position, frame slot, image geometry and
immutable base addresses against its retained descriptor. It also checks
this continuation and the exact domain-1/layer-16/patch/768-component memo
descriptor before any memo read. The source pair is acknowledged,
registered and lane-selected before its held numerical callback response.
Wrong resumed descriptors fail the outstanding source explicitly and
drain the real child to completion.

| Image feature boundary | Pre-edge acceptance and post-edge action |
| --- | --- |
| Fresh task | Capture descriptor; sequentially divide and validate before immutable mapping or numerical dispatch |
| Source miss | Accept actual child callback, register patch/index, validate, then publish the lower-rank dependency |
| Yield response | Retire the task response, enter suspended state; retain pool/controller/RAM and hold the outstanding numerical source response absent |
| Lower-rank work | Only the separate vision replay worker executes; suspended image feature emits no memory or workspace command |
| Resume | Capture exact returned descriptor; validate on a later edge, then issue the real aligned memo read |
| Source response | Register the acknowledged memo pair and selected BF16 lane; hold response/error until the pool accepts |
| Feature output | Accept ordered H values, write each pair to frame bank 0 and await its acknowledgment before the next pair |
| Final response | Require actual child completion, H values, exact last and all pair acknowledgments; only then release the retained child |
| Root cancellation | An accepted root completion or a new scheduler-root handshake cancels any abandoned source-stalled image continuation and resets child visibility; dependency yields do not cancel it |
| Reset | All public outputs zero; controller validity and child visibility invalidated |

Same-rank feature nesting is prohibited by the scheduler rank check.
Vision dependencies cannot invoke a text/image-feature ancestor, so one
retained literal image worker is sufficient. There is no recursive
elaboration or unbounded vector archive. Root cancellation is connected to the replay scheduler's actual root
acceptance/completion, not to an arbitrary mid-transaction task change;
normal yields never reset the child.

The image worker reports its live vector allocation continuously while
suspended, including while a separate lower-rank encoder frame executes.
Its physical vector reservation is 6432 bytes: 1824-byte physical-bin
mask, 1536-byte pooled BF16 vector and 3072-byte modality-normalized
bank. These remain additive to workspace frames/memos and lower-layer
scratch, not a claimed overlay. Its own controller and all reported
nested controllers are separate outputs. Primitive-state completion,
whole-system allocation enforcement and actual physical RAM inference
remain pending; this declaration is not measured resource-fit evidence.

### Completed native-feature replay binding

Domain 3 is the internal completed-modality feature domain. Layer 2
identifies audio; layer 1 identifies image features.
Its vector length is the selected text H (8 in compact builds), not the
native encoder width. This domain does not change the public job descriptor
or introduce host-generated features. Its dependency rank is 18; text
Eval rank is 19+l, vision/audio encoder Eval rank remains 1+l. Thus text
input may depend on a completed feature, and a feature may depend on a
completed encoder, with strict rank descent and the same 64-frame bound.
Domain-3 layer 0 and other feature kinds reject before work.

Domain-3 token is the original text-stream placeholder position, not a
host-provided encoder ordinal. `anvil_en1_native_token_map` scans the
entire immutable token stream, validates vocabulary and permitted modality
placeholders, and derives the requested same-kind ordinal and total count.
For audio it scans the actual immutable validity mask at source frame
4*s for every subsampled token s, selects the requested true-mask ordinal,
and requires total true masks to equal the audio placeholder count.
Image mapping returns the ordinal/count for the existing vision-bin mapper;
it does not assume all physical bins are valid. A wrong target identity,
missing ordinal, malformed mask or count mismatch is an explicit error.
All accepted scan/directory/mask reads, even failed responses, are original
input bytes. The mapper has bounded scalar state and no feature archive.

`anvil_en1_replay_audio_feature` maps the text placeholder before yielding
for domain-2 Eval(12,mapped_token), before numerical feature production.
Resume requires the exact model/session/mapped-token, 1024-component
dependency and bounded memo slot, with continuation
`{0x454e3146,mapped_token[31:0],96'b0}`. The continuation retains only
the checked mapping, not an encoder vector. No encoder or feature answer
enters the immutable-input memory port. The existing `audio_feature`
worker performs the genuine 1024-to-1536 native projection with bias,
unscaled RMS normalization and selected-H modality projection.
All layer-12 callbacks read the matching scheduler-owned memo through
op 4/target 1, aligned BF16 pairs. The scheduler cannot evict that memo
while this task owns execution.

| Feature boundary | Registered behavior |
| --- | --- |
| Start | Capture session/frame/dependency descriptor; validate before yield or child dispatch |
| Mapping | Execute actual immutable token/mask scans and retire/check their result before publishing any encoder dependency |
| Missing dependency | Publish the checked mapped-token lower-rank dependency without starting numerical work |
| Source | Capture callback, validate model/generation/layer/token/index, accept memo read, register response and hold actual BF16 lane |
| Output | Accept ordered H values, form aligned pairs, await each op 6/target 2 frame write acknowledgment |
| Completion | Retire actual feature done only after source/pair responses drain; require H values, exact last and no unpaired lane |
| Failure/reset | Drain active child using explicit failed callbacks/discarded outputs; stop new pair writes after first failure; reset cancels generation validity |

Domain-3 frames charge each granted H vector, up to two, and memos one H
vector, plus the existing scalar frame charge. Compact per-vector payload
is 16 bytes; production E2B/E4B per-vector payloads are 3072/5120 bytes.
Both actual and production-width shadow allocations remain visible;
fixed physical frame/memo strides are unchanged.
The literal audio feature worker's 1536-vector/projection banks and
controller reports are additive, not fictitious RAM overlays.
Whole-system session binding and primitive/scratch accounting remain
integration obligations before a ready handoff.

The domain-0 layer-zero input worker binds native placeholders to this
feature domain before starting embedding reconstruction. It yields
Eval(domain 3,layer kind,text_position), with kind 1 for image and 2 for audio, using
`{0x454e314d,128'b0}` as its input continuation. Resume rereads the
immutable token identity and validates the exact H-wide feature memo
descriptor. Real embedding/PLE native callbacks read that memo with
op 4/target 1, never the outward host modality port.
Embedding computes all feature replacement/PLE boundaries before its input
stream can be stored. The input worker waits for the first real input
valid before opening the workspace streaming write reservation; this
prevents a live store from blocking the preceding feature memo reads.
Each memo read is captured/registered/held, and source or embedding
failure drains the actual child before returning the original error.
Text-only behavior is retained; image and audio callbacks both use actual
completed native features.

Higher text layers retain the completed entering vector and projected
attention branch in their existing two frame banks while yielding for the
same selected native feature memo. Their distinct PLE continuation is
`{0x454e314c,128'b0}`. Resume validates the feature descriptor, rereads
the immutable placeholder identity and skips predecessor/attention
reexecution; it does not skip embedding/PLE arithmetic. Embedding feature
callbacks use the acknowledged memo source FSM, and actual PLE still
passes through the existing gated post-attention/MLP residual engine.
The source FSM distinguishes feature memo, entering/attention frame and
local PLE reads; only one is outstanding. The reread immutable token kind
must match the feature layer before embedding starts. Full system
integration still requires completion.

`anvil_en1_replay_audio_history` materializes the query attention
residual and at most four causal predecessors before starting lightconv.
Each is produced by the same numerical `replay_audio_residual` worker,
not a same-rank Eval push. Its genuine entering-vector dependencies still
decrease encoder layer. This bounded materialization preserves all previous
completed histories while that worker yields for a missing lower-layer input.

An audio frame supports six 1024-component BF16 subvectors, at most 12288
live vector bytes, within the admitted 12 KiB vector-frame ceiling. Its two banks each
have three slices. Scratch entering/residual is bank 0/slice 0; scratch
heads is bank 0/slice 1. Completed residuals at distances 0,1,2,3 are
copied respectively to bank 0/slice 2 and bank 1/slices 0,1,2.
The oldest required residual remains in scratch bank 0/slice 0.
For query positions less than four, only the legal causal predecessors
are reconstructed; the last reconstructed residual likewise stays in
scratch. No seventh vector or hidden-state archive is allocated.

Workspace vector operations select slice using req_scalar_index[1:0],
with all upper bits zero. Slice 0 retains existing behavior. Nonzero
slices are legal only for domain 2, frame vector reads (op 4/target 0)
and ordered frame pair writes (op 6/target 2), with the later extensions
for committed pair replacement (op 6/target 3) and frame release/move
(op 7/targets 2/3). Each extension retains its operation-specific
validation; memo/scalar/copy ABI is unchanged. Each slice has independent
visibility and ordered pair progress.
Validation first registers the selected slice index. TAG_READ synchronously
registers that slice's visibility, pair-progress flag and next component;
TAG_CHECK and PAIR_SETUP consume those registered observations, not a
combinational progress-array lookup followed by a same-stage comparison.
Audio vector grants in compact geometry also reserve 2048 bytes per slice:
native encoder widths are not compacted. The compact backing bank stride is
widened to the production 1536-word stride, and its physical reservation
is disclosed separately from live domain-specific frame allocation.
The audio production shadow frame charge is the same reserved slices, up to
12 KiB, plus 128 scalar bytes from frame push.

`replay_audio_residual` adds the default-preserving PACKED_FRAME=1 option
for this enclosing stage: only head frame-vector traffic is redirected
from bank 1/slice 0 to bank 0/slice 1. Memo reads, scalar checkpoints and
predecessor copies retain their semantics. The enclosing history worker
retags frame/scalar operations with the enclosing query frame descriptor,
while preserving actual historical tokens in memo descriptors and child
numerical descriptors. Completed vectors are not memoized as encoder Eval.

| Durable history boundary | Registered behavior |
| --- | --- |
| Start | Capture full session/frame/continuation/dependency descriptor; validate before child dispatch |
| Child completion | Retire actual residual done, check error/yield/bank, then copy or finish |
| Copy | Read one aligned scratch pair, register response, write its actual data to the selected history slice, acknowledge before advancing |
| Yield | Forward the child's saved head continuation; predecessor-only yields carry an enclosing tagged history-offset continuation |
| Resume | Derive and validate distance 0..min(query,4); restore the real child continuation; never restart completed histories |
| Final history | Leave the final successful residual in scratch; finish only after all earlier copies and real child completion |
| Reset/error | Reset cancels validity; first child/read/write failure ends the stage, never publishes completed history |

The history worker is an intermediate stage, not a complete conformer or
Eval result. Its enclosing `replay_audio_layer` connects the existing real
lightconv, FF2, final clamp and norm_out. Lightconv receives only acknowledged
reads of these computed causal vectors. Its immutable-weight commands cannot
overlap a live history reconstruction: all histories finish first. No
additional historical Eval or lightconv checkpoint is needed after that
phase, because every lightconv historical callback is bounded by distance 4.

Lightconv first copies its query residual and computes every depthwise row
before it emits outputs. Those outputs replace scratch bank 0/slice 0 only
after historical reads finish. FF2 reads that convolution vector, executes
its genuine pinned 0.5 residual boundary, and emits actual values through the
fixed clamp to bank 1/slice 0. Norm_out kind 0x2115 reads this distinct
complete clamped source and writes bank 0/slice 0. Only norm_out completion,
all 1024 ordered outputs and the final acknowledged pair allow bank 0 to
be returned as an encoder Eval result.

| Enclosing layer boundary | Registered behavior |
| --- | --- |
| History yield | Forward the real history continuation/dependency after child done retires; other engines stay idle |
| History finish | Check complete causal count before starting lightconv; only then expose history callbacks |
| Source callback | Capture tag/token/index, validate causal distance and slice, read aligned workspace pair, register and hold actual BF16 lane |
| Lightconv output | Capture ordered BF16 pairs; acknowledge scratch replacement before accepting another output |
| FF2 output | Hold FF2 after each accepted value, execute the clamp, then pair and acknowledge its actual result |
| Norm_out | Read bank 1/slice 0 without overwriting it; pair/acknowledge bank 0/slice 0 outputs |
| Phase completion | Retire real child done; require exact stream count/last/no unpaired lane/no failed source or pair before next engine |
| Failure | Drain source/active child and accepted workspace responses; stop pair writes after first failure; return error instead of Eval |

Each literal worker's vector and controller reports remain additive; the six
durable vectors are already charged by the workspace frame reservation.
No extra private durable banks or claimed physical overlays are introduced.
`replay_execute` dispatches encoder frames 1..12 through this layer worker
and returns its real yielded dependencies to `eval_schedule`. Completed
audio-feature/session routing and whole-system scratch overlays remain
necessary before a ready handoff. No numerical, functional, synthesis or
timing result is implied by this layout.

## Durable audio attention-residual/frame binding

`anvil_en1_replay_audio_residual` connects the saved genuine eight-head
worker to `anvil_en1_audio_attention_residual #(.FRAME_HEADS(1))`.
This is a completed **attention-residual stage**, not a completed conformer
layer or Eval result. The outer descriptor, predecessor/memo binding,
head checkpoints and dependency continuations remain those of
`replay_audio_heads`. No domain-2 higher-layer dispatch is enabled by this
increment.

`FRAME_HEADS` is an elaboration-time choice, legal only at 0 or 1.
Its default 0 preserves the existing complete attention-residual worker:
entering-vector callbacks, genuine FF1/pre-attention and all eight numerical
heads, post projection, clamp, learned post norm and residual. The added
`source_kind` is 0 for entering-layer callbacks. With `FRAME_HEADS=1`,
the worker reconstructs the same actual query FF1 residual through the
literal pre-attention worker, checking both complete streams; it does not
execute heads again or store the discarded normalized stream. Instead,
source_kind 1 supplies the actual committed head concatenation for the
clipped 0x210a projection. Generation/model/layer/query/index accompany
both kinds. The production frame wrapper supplies only acknowledged
reads of its genuine frame banks, not a host attention answer.

The head stage first commits bank 1 while leaving entering-vector bank 0
immutable. The post stage then reconstructs query FF1 from bank 0 into
its own synchronous 2048-byte residual bank. It projects from bank 1
into a separate synchronous 2048-byte working bank, applies the existing
BF16 +/-1e10 clamp and learned 0x210b RMSNorm, and executes
BF16_RNE(binary32_add(FF1_residual,normalized_post_attention)).
No extra 0.5 weighting, norm_out or second residual is inserted.

Only after all entering-vector and head source reads finish does the post
stage emit outputs. Its wrapper replaces frame bank 0 with the actual
attention residual using ordered operation 6/target 2 pairs. The first
pair invalidates its old visibility, and each pair waits for a concrete
workspace response; the final pair acknowledgment and actual successful
post completion are both required before returning successful bank 0.
Bank 1 remains the head vector until the later enclosing conformer stage
explicitly reuses it. No additional durable output archive is allocated.
The wrapper rejects any outward frame source callback after output begins.

| Compound residual boundary | Registered cycle and degenerate behavior |
| --- | --- |
| Start/reset | Register the full descriptor before validation; zero all public outputs and cancel validity during reset |
| Head dispatch | Start only after validation; wait for real child done before checking bank/yield/error and selecting post work |
| Head yield | Forward the unchanged tagged head/input continuation and strictly lower-layer dependency only after accepted head-stage completion |
| Resume | Restore through the same literal head worker; finished head pairs remain in frame bank 1; do not rerun completed heads |
| Post source | Capture kind/full tag/index, validate, issue an aligned frame-bank read, register the actual response, select the BF16 lane, then hold the callback response |
| Post memory | Own immutable directory/weight commands only during post execution; all head work has retired before ownership changes |
| Output pair | Capture low then high lane; keep descriptor/data stable through workspace backpressure; acknowledge before accepting another output |
| In-place safety | No bank-0 replacement before query FF1 reconstruction and every bank-1 projection read retire |
| Completion | Require 1024 ascending outputs, correct last, no unpaired lane, all accepted writes acknowledged and real successful post done |
| Error | Preserve first source/write/child error, drain the still-live post/source worker, and return failure rather than a completed vector |

The compound worker sums both literal children's live and physical vector
reports and exposes all their reported controller groups separately.
Its own registers include descriptor, source-response and partial-pair state
in `controller_bytes`. `FRAME_HEADS=1` reserves only its two outer vector
banks (4096 bytes), plus the literal pre-attention's physical reservation;
the unused head/cache arrays have no enabled payload accesses. The two
workers are separate RTL instances: their physical reservations are summed,
not falsely advertised as a phase overlay. Durable frame-bank allocation
remains charged by `replay_workspace`, not again as a private vector.
Primitive arithmetic state and whole-system scratch partitioning still need
complete integrated accounting and source-matched synthesis observations.

Accepted post directory/weight commands count four bytes even when their
responses fail. Accepted entering/head callbacks count two on-chip source
bytes. The real head worker's original-mask, weight, projection and
intermediate events remain connected. All of these events are advisory DUT
observations; independent handshake/address classification remains mandatory.

The enclosing history/layer workers described above now connect historical
light convolution and FF2/norm_out. Modality/session routing and whole-system
integration remain unfinished. This compound attention residual itself must
not be dispatched or memoized as Eval(frame_layer,query); only the enclosing
layer's completed norm_out may supply that result.
No functional, numerical, synthesis or timing check has run for this binding.

## Complete native conformer and durable audio-head binding

`anvil_en1_audio_layer` connects one complete native 1024-component conformer
layer, numbered 0..11. Its sole external hidden-vector callback supplies
the actual input to that layer at a requested subsampled token. The worker
executes FF1, all eight relative-attention heads, output projection/post norm
and residual through `audio_attention_residual`; then `audio_lightconv`;
then actual FF2 with its existing 0.5 BF16 residual boundary; finally the
fixed +/-1e10 BF16 clamp followed by learned RMSNorm kind 0x2115. No
additional residual or 0.5 scaling is applied after norm_out.

During light convolution, query attention-residual components come from
the completed immutable query bank. Historical components at distance
1..4 are reconstructed by the same real attention-residual engine,
including its FF1, mask, eight heads, projection and post norm. One tagged
complete historical vector is cached on-chip. This is recomputation of
an intermediate within a layer, not an Eval push at the same layer rank;
every outward hidden callback still requests the entering vector from the
preceding encoder layer. The durable frame dispatcher must eventually
suspend these real computations when that entering vector needs Eval.
The connected non-resumable conformer does not yet provide that dispatcher.

Three outer 2048-byte synchronous vector banks retain query attention
residual, historical attention residual and light-convolution output.
After convolution completion, its query bank is reused for clamped FF2
outputs. The historical cache is invalidated and released before FF2.
The convolution-output bank stays immutable through FF2's source reads,
then releases before norm_out. Norm_out never overwrites its source.
The connected physical vector reservation is 34816 bytes, including
all saved child vector banks. Its scheduled vector-live bound is 26624
bytes during a historical reconstruction; partial refills and failed
computations remain charged until their real completions retire.
Controller and primitive arithmetic state are additional, not included
in that vector-only bound. Whole-system scratch overlays remain required.

| Conformer boundary | Registered cycle/degenerate behavior |
| --- | --- |
| Start/reset | Capture descriptor before validation; reset zeroes public outputs and drops every bank's visibility |
| Raw source | Only the selected attention worker forwards real layer-entry callbacks; no generated attention/conv/MLP answer is accepted from outside |
| Historical miss | Accept and retain callback, invalidate old visibility, run actual attention reconstruction, accept its complete stream and done, then perform synchronous read/capture/response |
| Memory handover | Lightconv/GLU has retired its preceding weight response before requesting a hidden callback; attention owns memory only during the registered refill start/wait |
| Vector commits | Require exactly 1024 ascending components and correct last, plus actual successful child completion; partial/error banks remain unreadable |
| FF2 clamp | Accept a raw output, stall FF2, execute actual clamp, write RAM on a later edge, then restore FF2 readiness |
| Final output | Valid/index/data/last stay stable while stalled; count only accepted norm outputs; final acceptance precedes done |
| Error | Preserve first specific reconstruction/child failure; retire child work before error done; release allocations only at done acceptance |

The durable head wrapper `anvil_en1_replay_audio_attention` binds the real
REPLAY=1 audio attention executor to acknowledged workspace operations 6/7,
target 0, domain 2, length 1024. Logical layer l belongs to frame_layer l+1.
Its 160-bit continuation is `{0x454e3141, generation[31:0],
query_token[31:0], frame_layer[7:0], frame_slot[5:0], model[1:0],
precision[1:0], logical_layer[7:0], head[2:0], 35'b0}`.
Restore validates this descriptor before reading scalar words. Only the
head's 22 live checkpoint words are saved at frame scalar indices 8..29;
reserved head words 22..31 are recreated as zero. Scalars 30/31 remain
available for the enclosing worker's output count/unpaired BF16 lane.

The head wrapper's outward source callback supplies actual **entering-layer**
BF16 components, not precomputed FF1 or normalized attention inputs. Before
accepting an available-vector decision for Q/K/V, it executes the literal
`anvil_en1_audio_pre_attention` on that requested token. Raw FF1 residual
outputs are checked and discarded; all 1024 normalized outputs are checked
and stored in a tagged synchronous 2048-byte on-chip cache. Successful child
completion and both complete streams precede cache visibility. The head then
reads only that normalized cache. A cache hit bypasses outward dependency
resolution; relative-K decisions always use the native local position engine.
A miss with action 1 still uses the existing durable head checkpoint. A miss
with action 0 stalls that same pending head decision during genuine FF1
reconstruction. No accepted head/weight response remains outstanding at that
handover. A new start/resume invalidates the cache and recomputes it as needed.
This cache does not retain an encoder activation archive across Eval tasks.

| Normalized audio-source boundary | Registered behavior |
| --- | --- |
| Available miss | Accept the outward decision, capture token, then start genuine FF1/pre-attention on a later edge; do not accept the pending head decision until cache commit |
| Source callback | Forward only pre-attention entering-layer reads; caller must supply committed query frame or matching lower-layer memo data |
| Cache fill | Require raw kind 0 followed by normalized kind 1, each 1024 ascending BF16 components and correct last; partial/failed fill is not visible |
| Cache hit | Accept the original head need, then service actual normalized source requests with separate tag validation/read/capture/response stages |
| Error | Drain pre-attention output/completion, reject the still-pending head need with action 2, retire head completion, preserve the first specific failure |
| Stall/reset | Held source/need/result payloads do not change while stalled; reset zeros all public outputs and invalidates cache visibility |

The wrapper exposes cache-inclusive vector live/physical allocation and
pre-attention/controller allocations separately from the executor/controller
outputs already present. The 2048-byte cache is charged from refill start,
including partial failures, through completion acceptance; the literal
pre-attention's vector reservations remain additional. Neither declared
allocation outputs nor RAM attributes establish measured liveness or M20K
inference.
Accepted entering-layer source callbacks count two on-chip bytes each.
Accepted pre-attention directory/weight commands count four immutable-weight
bytes each, including requests whose later response fails; the executor's
original-mask and projection-weight observations stay separately connected.
These are actual event outputs, not substitutes for the independent external
handshake/address-classification scoreboard.

| Durable audio-head boundary | Registered behavior |
| --- | --- |
| Need | Capture an actual accepted yield decision and its token; relative K is locally generated and cannot request a historical Eval dependency |
| Checkpoint | Accept the complete tagged head checkpoint only after prior service/arithmetic retirement; freeze it before workspace traffic |
| Yield drain | Wait for and accept the executor's real done_yield completion before saving or publishing a task yield; never leave it busy for the next resume |
| Scalar save/restore | Each request waits for a registered actual response and error check; the 22nd successful acknowledgment precedes task yield/start |
| Resume | Validate frame/model/generation/query/layer/head and reserved bits; restore the same arithmetic reduction order, not a software answer |
| Failure | Retire executor completion before returning errors; failed scalar writes never become a successful continuation |

These bindings are implementation contracts, not verified numerical, RAM,
timing or hardware results. Domain-2 full-layer continuation/memo dispatch
is connected through the enclosing layer worker; completed audio-feature
routing and whole-system allocation accounting remain required.

### Durable eight-head audio/frame stage

`anvil_en1_replay_audio_heads` is an attention-output stage for the enclosing
conformer dispatcher, not a completed encoder Eval result. It binds the actual
query predecessor to frame bank 0, executes heads 0..7 with the genuine
pre-attention/head wrapper above, and writes all 1024 head-concatenation
components to frame bank 1 by acknowledged operation 6/target 2 pairs.
Bank 0 stays immutable through the entire stage. Historical source requests
read only the matching domain-2 lower-layer memo slot using operation 4/
target 1; query requests use operation 4/target 0 on the committed frame.
An unavailable historical token yields exactly Eval(frame_layer-1,token),
never same-rank Eval or a host-generated FF1 answer.

Initial input yield uses continuation `{0x454e3148,128'b0}`. Head yields
retain the full head wrapper continuation (magic 0x454e3141). In addition
to acknowledged checkpoint words 8..29, the stage saves accepted global
component count in scalar 30 and the unpaired low BF16 lane in scalar 31.
Resume checks count is within the tagged head's 128-component interval,
that scalar 31's upper half is zero, and that even counts have no unpaired
lane. Workspace pair-progress/visibility persists across child Eval.
Final successful head completion is insufficient by itself: the 1024th
component's pair write must have acknowledged, all heads must complete,
and no source/workspace error may be pending before returning bank 1.

| Eight-head frame boundary | Registered behavior |
| --- | --- |
| Initial/linear mode | Bind the genuine query predecessor before the first head; mode 2 is a supplied-predecessor optimization, not different arithmetic |
| Input dependency | Missing predecessor returns the input continuation; resumed matching memo copy must acknowledge before any head start |
| Historical callback | Capture full source tag/index, validate query frame or supplied memo identity, accept workspace read, register result, select BF16 lane, then hold response |
| Accepted head output | Check head-relative index/last and global count; capture low lane or complete high/low pair; stall head until actual write acknowledgment |
| Head dependency | Retire the wrapper's real yielded completion (including checkpoint saves), save count/low scalars, then expose the dependency continuation |
| Head resume | Restore and validate the two outer scalars before starting the tagged numerical head; do not recopy query bank or restart finished heads |
| Failure/reset | Drain active head/source traffic before error completion; reset invalidates state; no failed/partial attention bank is returned as a completed vector |

This stage has no extra vector bank: its durable vectors live in the existing
accounted frame banks. Its literal head wrapper's cache/pre-attention vectors,
binding controller, frame-source/scalar controller and numerical children
remain additional reported allocations. The enclosing dispatcher must still
execute output projection, post norm/FF1 residual, causal light convolution,
FF2 and norm_out before it can publish Eval(frame_layer,query). It must retain
or recompute intermediate stage state within the admitted frame/workspace
bounds. The eight-head stage alone is not authorized as a layer substitute.

### Native audio layer-zero replay

`anvil_en1_replay_audio_input` reconstructs Eval(0,t) with the saved real
two-stage subsampler and Ha input projection. It writes all 1024 actual
BF16 outputs into domain-2 frame bank 0 using acknowledged aligned-pair
operation 6, target 2. The first pair starts an unreadable partial vector;
the final successful pair acknowledgment commits it. A successful task
also requires the subsampler's actual successful completion and complete
ascending count/last checks; no initialization or mask bit supplies data.
The input worker returns bank 0, without an invented historical dependency.
The original mask remains independently addressable at stride-4 source
positions for later attention; subsampling does not replace masked vector
components with software-produced answers.

`anvil_en1_replay_execute` captures native_audio_base,
native_audio_weights_base and native_audio_frames at root acceptance,
alongside its existing immutable vision fields. Its registered domain-2
layer-0 dispatch selects only this input worker for external commands,
workspace requests and completion. Native source, projection, point-replay
and vector/controller allocation outputs separately expose actual audio
reconstruction. Higher domain-2 layers 1..12 now select
`replay_audio_layer`, with registered workspace/command/completion selection.
Its genuine yielded continuation and strictly lower-layer dependency return
to the existing scheduler. Only final successful norm_out returns an Eval
vector. The extended audio layer-controller and history/GLU events expose
actual connected work, not numerical or timing acceptance.

| Audio Eval(0) boundary | Registered behavior |
| --- | --- |
| Descriptor | Capture model/precision/generation/frame/token/immutable bases; require frame_layer 0 and token<ceil(frames/4), frames 1..131072 |
| Single vector | Exactly 1024 outputs; low lane captured before high lane forms a stable 32-bit pair |
| Pair ingress/backpressure | Child stalls during pair request/response; pair descriptor and payload remain stable; actual acknowledgment precedes the next component |
| Child and workspace errors | Preserve first error, drain the numerical child and accepted pair response, then fail task without a success-shaped vector |
| Completion/reset | Real child done and all accepted pairs precede task done; reset cancels validity without initializing payload RAM |

## Native audio relative-attention boundaries

The saved connected attention increment uses native Ha=1024, eight heads
and Da=128, including compact text builds. Its tile source is the actual
BF16 `norm_pre_attn(clamp(feed_forward1(...)))` vector; it is not an
original audio input, a finished attention answer or a normalized K/V
vector. The conformer/replay producer must reconstruct this boundary for
each requested token. Selector 0/1/2/3 denotes Q/K/V/relative K.
Q/K/V use clipped matrix kinds 0x2105/2106/2107. Relative K uses the
unclipped 0x2108 matrix and locally generated sinusoidal inputs, never
an external positional-embedding tensor. All matrix rows materialize
BF16 before subsequent scaling.

Relative inputs have concatenated sine/cosine layout over 512 timescales.
For input column c, i=c[8:0]; inverse timescale is
exp(-i*ln(10000)/511). Generate binary32 ln(10000) as 0x41135d8e,
divide by binary32 511 with the sequential divider, multiply by converted
i, execute the existing exp engine and multiply by converted distance
0..12. Sine/cosine use the existing range-reduced engine and narrow to
BF16. These are implemented transcendental approximations subject to the
unchanged numerical/attention tolerances, not claims of bit-exact libm.
Every projection multiply/add and every format conversion retains the
exact primitive contract and ascending-column order.

Q is widened from its BF16 clipped projection, multiplied by binary32
Da^-0.5/log(2)=0x3e0293ee, then by the widened BF16 result of
softplus(per_dim_scale[c]). K is widened and multiplied by
binary32 log(1+e)/log(2)=0x3ff28370. V and relative K are only widened.
The actual BF16 scale vector 0x2109 is independently validated/read.
Softplus uses the pinned threshold x>20 -> x, otherwise the stable
max(x,0)+log1p(exp(-abs(x))) expression. Its log1p engine evaluates
2*y*sum(j=0..11,y^(2*j)/(2*j+1)), y=z/(2+z), in ascending j order
with separately rounded binary32 operations. Negative underflow
produces positive zero; NaN is canonical and +infinity remains infinity.
The BF16 softplus boundary is retained before Q multiplication.

The attention head enumerates every one of the 24 blocked context
columns, including left/right padding, using a sequential divide-by-12
to obtain the block start. Permitted unmasked keys satisfy
0<=query-key<12 and the original subsampled key-valid mask. Out-of-range
columns are masked and supply padded +0 V. For an unmasked key at
distance d, the actual blocked relative shift selects relative input
position 12-d, whose descending positional ID is d. Content and relative
dot products reduce independently in ascending component order;
their binary32 sum passes through 50*tanh(score/50).
Masked logits are binary32 -1e9 (0xce6e6b28), not negative infinity.
Therefore an all-masked row still executes its 24-way stable softmax
and value reduction; it must not become an error or an invented zero
answer. Probabilities and value accumulation remain binary32 until
the final head output narrows to BF16.

| Attention boundary | Cycle/ownership rule |
| --- | --- |
| Start/reset | Pre-edge acceptance captures all tags; active reset zeroes public outputs; first released edge has no unsolicited valid |
| Tile pair | Aligned component pairs 0..126; both actual rows finish before the stable 64-bit binary32 pair response becomes valid |
| Source/mask | Accept request, register response on a later edge, then use registered response; hold valid/payload under backpressure |
| Projection memory | Only the selected directory/matrix/scale reader owns cmd/result; ownership changes only after accepted completion |
| Replay need | Yield only immediately before a Q/K/V/relative request, after prior memory/arithmetic responses have retired |
| Continuation | A tagged 1024-bit checkpoint preserves the complete scalar reduction state; resume validates descriptor, phase, selector, key and bounds before dispatch |
| Output/done | Emit ascending 0..127; final BF16 acceptance precedes completion; no response is consumed on its creation edge |
| Padding/all masked | All 24 columns participate; padded V is +0, and masked real V still executes the actual projection/value multiply |
| Error/reset | Preserve first concrete child error; no new work after failure; reset cancels visibility and continuation validity |

The pair tile owns no hidden-vector archive. Its live/physical payload is
controller/scalar state plus connected arithmetic and directory/decoder
state; all of these still need the final whole-system allocation overlay.
The head preserves one bounded scalar continuation, not a 24x128 KV tensor.
Only checkpoint words 0..21 carry data. A durable worker must persist those
22 words at scalar indices 8..29, reserve 30/31 for its output count and
unpaired BF16 lane, and recreate reserved words 22..31 as zero on restore.
This fits the existing 32-word compact scalar frame without widening it.
These boundaries do not authorize same-layer replay recursion, a native
feature spill or host-supplied Q/K/V. Full conformer frame dispatch is now
connected through the enclosing history/layer workers, not independently
accepted as numerically or physically correct.

### Connected audio pre-attention vector

`anvil_en1_audio_pre_attention` accepts a real layer-entry source callback,
not an already completed FF1/attention vector. It connects the saved actual
feed_forward1 (mode 1) and then the fixed BF16 +/-1e10 clamp and learned
norm_pre_attn 0x2104. Its ordered output_kind 0 stream is the unclipped
FF1 residual; output_kind 1 is the complete normalized attention input.
Every FF1 raw beat must be accepted before it is clamped and stored in the
2048-byte synchronous working bank. While clamp/store completes, FF1 is
stalled without relinquishing any outstanding memory response. The complete
successful 1024-component collection is a prerequisite for normalization;
there is no visibility through initialization or a partial bank.
The normalization source stays immutable through all reductions and output.
Done requires both full ordered streams, actual accepted child completions
and no concrete child/source error.

| Pre-attention boundary | Registered behavior |
| --- | --- |
| FF1 stream | Raw output pre-edge acceptance captures index/value and increments the raw count once |
| Clamp/store | A later actual clamp result writes RAM; FF1 readiness stays low until the write is complete |
| Norm | Starts after FF1 done and final clamp/store; source read/capture/response occupy distinct edges |
| Kind transition | Full kind 0 completion precedes any kind 1 valid |
| Reset/error | Reset drops bank visibility; errors drain children and prohibit successful done |
| Allocation | 2048 parent bytes plus up to 6144 FF1 vector bytes; FF1 vector lifetime ends before norm starts |

The connected attention-residual worker retains the query's full FF1 residual,
collects all eight 128-component heads before clipped post matrix 0x210a,
applies the fixed stability clamp and learned norm_post_attn 0x210b, and adds
the corresponding unclipped query residual. It neither applies 0.5 to this
branch nor omits its post norm. Historical normalized inputs are reconstructed
by this real pre-attention worker from layer-entry callbacks and held in a
single tagged on-chip vector cache. Every token change discards old visibility
before refill; every query/head/matrix/source/output stream is checked against
its actual tag/index/count/last. Four 2048-byte vector banks (query residual,
head outputs, normalized source and post working) are physically separate.
Working-bank normalization emits outward without overwriting its input.
The source cache can remain live alongside the query/head allocations while
pre-attention is rebuilding a different token; its partial refill is charged,
but not readable. Generated features are never issued on the external port.
Durable continuation/memo binding and the complete conformer remain required.

## Native causal audio light-convolution increment

### Durable native vision replay dispatch

The next native replay worker uses the existing scheduler's domain 1,
768-component frames and 16-entry memo pool. Eval(0,patch) executes
`vision_patch` from immutable image inputs. Eval(l,patch), l=1..16,
first obtains Eval(l-1,patch) and copies the completed memo vector into
frame bank 0. Preserve that bank throughout bidirectional attention.
Run all 12 genuine 64-component attention heads, writing ascending
BF16 pairs to frame bank 1. An unavailable historical patch yields a
dependency Eval(l-1,historical_patch); it never recurses combinationally
or overwrites another patch's layer input. Query sources read bank 0;
historical sources read the tagged completed memo dependency.

Save each interrupted head's actual 512-bit arithmetic checkpoint at
scalar words 8..23 using `replay_vision_attention`. Save the outer
worker's global output count and unpaired low BF16 component at words
24 and 25 before returning a yield. The returned 160-bit descriptor
identifies generation, model, precision, query, frame, logical layer
and head. Restore both outer words before resuming the head; require
the count to belong to that head's 64-component interval. No expected
numerical answer or scalar reduction is reconstructed in software.
Read saved head word 17 as well, and require its next output-component
field to equal the restored count modulo 64; phases before value output
must have no emitted components. This is a checkpoint consistency check,
not another retained vector or a new numerical boundary.
The predecessor-only continuation has magic 0x454e314a and zeros in
the remaining bits. It authorizes only the same patch's immediately
preceding vision layer, not a different memo source.

After complete successful attention, execute clipped output projection
0x1106 for every row using the completed bank-1 vector. Replace bank 1
with its actual projected result, then execute `vision_post_layer`
from bank 0 and the projected bank 1. Its complete input collection
precedes replacement of bank 1 with final layer outputs.

| Native replay boundary | Registered behavior |
| --- | --- |
| Start/reset | Capture descriptor pre-edge; zero public outputs and invalidate visibility during reset |
| Predecessor | Yield before reads if absent; copy only the tagged completed same-domain memo on resume |
| Head output pair | Capture low then high; stall the head while a workspace pair transaction retires |
| Missing patch | Accept need, save actual head checkpoint, save outer words, then publish dependency |
| Resume | Validate outer descriptor, read saved words, validate count, then start restored head |
| Source | Capture tag/index, validate, read aligned frame/memo pair, capture, then hold one BF16 response |
| Output projection | Read only a completed head vector; collect every row before replacing that vector |
| Post layer | Load complete raw/branch inputs before any bank-1 output replacement |
| Failure | Drain child outputs/done and workspace responses; preserve first concrete error |
| Completion | Require every ordered pair write and successful child done before worker done |
| Native liveness | Frame pairs and scalar words stay charged across yields; child partial banks stay charged through done acceptance |

The output-projection vector needs one 1536-byte synchronous bank,
including partial/error collection through completion. Saved head words
occupy 64 bytes and outer words 8 bytes per interrupted frame, additional
to the scheduler's return record. Existing child vector reservations,
all scalar/controllers and arithmetic state remain additional. This
increment does not certify the final 1 MiB overlay or physical RAM fit.
The native dispatcher must carry original image geometry and immutable
image/vision-weight bases captured for the whole replay session.

`anvil_en1_replay_execute` now carries this worker as domain 1, alongside
the retained domain-0 input/text workers. The added start descriptor is
`eval_domain[1:0]`, `native_image_base[63:0]`,
`native_vision_weights_base[63:0]`, and the three 32-bit
`native_patches/native_patch_rows/native_patch_columns` counts. Capture
those image fields only on accepted root start; capture task generation
from the scheduler for each dispatched worker. Domain 0 retains text
vector lengths and its existing single-token linear schedule. Domain 1
retains native 768-wide vectors even in COMPACT builds, uses `token` as
the requested patch, and permits Eval layer 0..16. The original text
token/weight bases remain separate immutable descriptor fields, not
aliases for image storage.

The public root reproduction sequence is active reset, reset release,
accepted start with a complete registered root/image descriptor,
service aligned external read commands and on-chip backing requests
with one response each, accept every ascending output component, and
then accept done. The backing channel belongs to the declared on-chip
workspace RAM and must never be routed to external DDR. New native
controller/vector outputs expose all connected worker categories for
system accounting; inherited workspace live/shadow/physical outputs
include frames, memo and scalar reservations across yields. Directory
and payload traffic classification must still scoreboard the external
address map; native input/projection events are not a replacement for
that independent public-handshake ledger.

The dispatcher reconstructs domain-2 layer zero from actual immutable
audio inputs and layers 1..12 through the durable conformer worker.
Text modality callbacks still require
their native session/placeholder dispatcher. Those are implementation
gaps, not authorized removal of native audio or multimodal acceptance.
No functional or synthesis pass is established for the saved workers.

`anvil_en1_audio_glu_component` reconstructs one channel of the pinned
light-convolution input. Its descriptor captures model, precision, generation,
audio layer 0..11, token 0..131071, channel 0..1023 and aligned immutable
audio-weight base. Its source callback supplies the actual hidden vector
after that layer's attention residual, at the captured token; it is not an
encoder-output or host GLU-answer boundary. Execute learned pre_layer_norm
0x210c over all 1024 channels with no stability clamp before this norm.
Collect every ordered BF16 norm output in one 2048-byte synchronous bank,
and expose that bank to projections only after successful complete norm.
Execute clipped linear_start 0x210d rows channel and channel+1024 in that
order. The first half is the multiplicand; the second half is the sigmoid
gate. Existing `geglu_pair` operation 2 implements BF16 sigmoid
materialization, separately rounded binary32 multiplication with the first
half and final BF16 materialization. No GeGLU/GELU or SiLU replaces GLU.
Every reconstruction performs actual norm-scale and matrix reads.

`anvil_en1_audio_depthwise_row` validates tensor 0x210e as 1024 rows by
5 flattened OIW columns. It executes all five multiply/add terms in
ascending kernel order, starting from binary32 +0 and materializing BF16
only after the complete reduction. Kernel j addresses token-4+j at the
same channel. Determine left padding by token < 4-j before subtraction;
padding supplies BF16 +0 without a source request, but still executes the
actual weight multiply/add, including exceptional weights. There is no
right padding, bias, validity-mask multiplication, cross-channel sum,
clipped depthwise weight, or external activation archive. The callback
must reconstruct an actual completed GLU component, not a raw hidden
component. Tensor directory, BF16/Q4 partial-row layout and address overflow
validation precede accesses.

`anvil_en1_audio_lightconv` connects these two leaves into the complete
light-convolution residual at one token. Capture the 1024-channel unclipped
attention residual in one 2048-byte synchronous bank. Execute each genuine
depthwise row; each historical callback dispatches `audio_glu_component`
and waits for its actual successful completion. Store all 1024 depthwise
results in a second 2048-byte bank before applying the pinned BF16 +/-1e10
stability clamp, learned conv_norm 0x210f and BF16 SiLU. Execute clipped
linear_end 0x2110 for every output row, add the corresponding original
residual using binary32 addition and BF16 materialization, and stream in
ascending order. This residual has no 0.5 weighting or additional norm.
It does not skip false audio validity positions; pinned light convolution
does not apply the attention mask.

| Light-convolution boundary | Registered behavior |
| --- | --- |
| Start/reset | Pre-edge acceptance captures descriptors; active reset zeroes public outputs and discards bank visibility |
| Norm collection | Accept all 1024 ordered components/last; check actual successful done before projection visibility |
| GLU rows | First-half projection completes before second-half projection; both complete before sigmoid/product |
| Depthwise coordinates | Capture j, classify padding, then subtract; kernel 0..4 visits once even at token 0 |
| Historical callback | Capture/validate model, generation, layer, token and channel; dispatch genuine GLU only on a later edge |
| External ownership | Parent projection is paused after its weight response retires; GLU owns memory until its done retires |
| RAM callback | Capture address; synchronous read; separate capture and held response; never read partial/unfilled vectors |
| Conv norm/SiLU | Complete clamped vector before norm; complete norm before in-place unary SiLU traversal |
| Output | Capture actual row result; separately add/narrow residual; hold index/data/last until accepted |
| Completion/error | Drain accepted child responses, preserve first concrete child failure, and wait for final output acceptance |
| Live allocation | Charge partial/error banks from accepted start through accepted done; no release at result creation |

With default local storage, physical vector reservation is 6144 bytes: residual 2048, convolution/working
2048, and the GLU child's normalized bank 2048. The two outer banks remain
live throughout the task; the child's bank is additionally live during
historical reconstruction, including partially filled/failed norm work.
Every retained scalar, directory/projection/norm/clamp/arithmetic state and
response reservation is additional. Public allocation outputs expose outer
and child vector occupancy separately through their sum and physical sum;
controller outputs include connected child controller reports. Final system
overlay/replay accounting must also charge arithmetic leaf state not already
included by those reports. Reprojection increases weight and native-source
reads and is not avoided computation. No practical latency claim is made.
The replay audio wrapper instead selects the external three-bank overlay
specified above; it owns and reports all 6144 physical bytes once, including
the nested GLU bank shared with the later feed-forward branch.

These modules supply an actual light-convolution sublayer, not complete
audio attention, a complete conformer, durable native replay or system
integration. Functional/numerical/synthesis evidence belongs to the
independent Verifier.

### Native audio output projection

`anvil_en1_audio_output` accepts one actual completed layer-12 audio token
vector through its source callback, at native width 1024. Capture model,
precision, generation, token and immutable audio-weight base; validate
0x2200 at layer 0xffff as 1536x1024 and 0x2201 as one BF16 vector of
1536 components before numerical execution. Compute each output_proj row
with the genuine BF16/Q4 matrix reader and ascending-column binary32
multiply/add reduction, followed by BF16 projection materialization.
Read its actual BF16 bias component, add in binary32 and materialize
BF16 again. No clamp, SiLU, residual, learned norm or 0.5 weighting belongs
to output_proj. Stream all 1536 components in ascending order, with held
last and completion only after the last output is accepted.

Directory validation, row start, projection completion capture, bias read,
bias completion capture, add/narrow, output creation, output acceptance and
done acceptance are distinct registered events. BF16 bias format is
independent of matrix precision. All accepted directory/matrix/bias reads,
including failed responses, are weight bytes; source callbacks are logical
native reads and are not advertised as external KV transfers. The leaf has
no vector bank; its scalar reductions/reservations and every child arithmetic
or directory state still belong to the native live ledger.

`anvil_en1_audio_feature` collects that complete successful 1536-component
output vector in one 3072-byte synchronous bank before dispatching the
saved modality projection in audio mode. Enforce index/last and complete
done before source visibility; malformed/partial/error output cannot be
used by normalization. Its synchronous callback supplies the stored vector
to actual unscaled RMSNorm followed by the native H projection (0x2202),
with no embedding-scale multiply, learned scale or projection bias. All
H outputs must be ordered and last must agree before successful completion.
The outer collection bank and the modality normalized bank can both be
live (6144 bytes total). Include both in physical reservations and occupancy
through completion acceptance, plus all scalar/child state. Source callbacks
remain real layer-12 native dependencies for the replay dispatcher; the
wrapper does not provide a finished host audio answer. Complete audio
attention, conformer dispatch, placeholder mapping, bounded replay and
whole-system allocation/compatibility integration remain required.

## Native vision pooling and modality projection increment

### Valid-bin ordinals and native subsampling boundaries

`anvil_en1_vision_bins` maps an ordinal in the stripped soft-token stream to
an actual physical pooled bin. Capture model, generation, patch/grid/bin
counts, ordinal, expected placeholder count and the immutable input base.
Validate the same coordinates and floor quotients as `vision_pool`; never
infer a dense rectangular bin map from dimensions alone. Scan coordinates
once for the actual max-x stride and again to set one presence bit per
mapped physical bin, including clamped padding in bin zero. Duplicate
coordinates set an existing bit, not another valid token. Enumerate all bins
in ascending order, select the requested true-bin ordinal, and finish counting
even after selecting it. Success requires the computed count to equal
expected_soft_tokens and an actually selected bin. A count mismatch is error
7, not successful truncation or a false-bin placeholder.

The presence RAM is 456 synchronous 32-bit words (1824 physical/live bytes),
covering the existing legal maximum of 14563 bins, with unused bits in the
last word. Charge the full allocation from accepted start through accepted
done, including partial initialization and errors. Clear every word
sequentially before the two coordinate scans; never asynchronously reset RAM
or read an uninitialized word. Bin set is a registered read/modify/write,
with the write retired before advancing to another patch, including repeated
patches in the same word. Enumeration reads only completed mask words and
ignores bits outside pool_count. Reset discards visibility and the next start
clears the whole allocation before reading. No original-input writes or
external mask/feature archive are allowed.

`anvil_en1_vision_soft_token` connects this checked ordinal to the real
`vision_feature` pool/norm/projection. It must accept the complete successful
mapping before dispatching the numerical feature, check that the feature
returns a true mask, and count all H ascending output components and last.
Mapping allocation is released before feature vector allocation starts;
their physical reservations remain additive (6432 bytes). Actual numerical
vector peak remains 3072 bytes, with mapping peak 1824 bytes in its separate
phase; all directory, divider, arithmetic and controller state is additional.
There is no H-vector copy in this wrapper. Accepted mapping and feature reads
are separately performed and both counted as original-input traffic.
The native session still must derive expected_soft_tokens and ordinal by
scanning the original token stream, not trust a host feature map.

The subsampling numerical leaf, `anvil_en1_audio_conv_row`, accepts
stage 0/1, model/precision/generation, original frames, output time/frequency/
channel and immutable audio weights. Stage 0 has one input channel and 128
output channels; stage 1 has 128 input channels and 32 output channels.
Input time lengths are frames and ceil(frames/2); output time lengths are
ceil(frames/2) and ceil(frames/4). Input frequency lengths are 128/64 and
output frequency lengths are 64/32. All lengths are computed by shifts and
odd-bit additions at separate registered stages. Frames are 1..131072.
Validate time/frequency/channel ranges before any weight or source request.

Use real OIHW convolution matrices 0x2000/2002, rows 128/32, columns 9/1152,
at layer 0xffff from the audio tensor image. The existing BF16/Q4 row reader
must enforce partial Q4 rows without reading the next row. For ascending
flattened column j, sequentially divide by 9 for input channel and remainder,
then by 3 for kernel y/x. Spatial input is (2*time+kernel_y-1,
2*frequency+kernel_x-1). Out-of-domain spatial padding supplies +0; it
issues no mask or feature source request but still participates in the
weight multiply/reduction, including exceptional weight encodings.
For an in-domain source, fetch the original validity mask at input_time
for stage 0, or 2*input_time for stage 1. A mask word other than 0/1 is an
explicit descriptor error. Stage 0 source_stage=0 supplies immutable raw
input BF16 at (time,frequency,channel0); stage 1 source_stage=1 supplies real
completed layer-0 norm/ReLU data at (time,frequency,channel0..127). Even a
false mask still reads that actual source and executes BF16(source*mask),
preserving zero-times-infinity/NaN. No host convolution answer is permitted.
Projection uses the prescribed binary32 multiply/add order, then one BF16
convolution materialization. It has no bias, clipping, RMS substitution,
activation or channel normalization: the enclosing point engine must gather
all 128/32 channel rows and execute actual learned LayerNorm followed by ReLU.

| Ordinal/subsampling boundary | Registered behavior |
| --- | --- |
| Start/reset | Capture at pre-edge handshake; reset zeroes every public output; next job starts fresh visibility |
| Mapping RAM | Sequential whole-RAM clear; synchronous read; separate capture/modify/write; no read/write collision |
| Ordinal selection | Count every true bin exactly once in ascending physical order; publish only after complete-count comparison |
| Phase handoff | Accept mapping done, register/check its descriptor, then start feature; no allocation overlap |
| Conv geometry | Register ceil/half lengths, then classify output tuple, then validate immutable directory |
| Conv source coordinate | Sequential floor quotients; separate doubled-origin, add, subtract and bounds stages |
| Conv padding/mask | Padding has no source callback; real source is multiplied by actual 0/1 mask and BF16 materialized |
| Conv callbacks | Mask/source request and response handshakes are distinct edges; payload remains stable while stalled |
| Conv completion | Drain real projection completion, preserve first callback/memory error, register result and publish stable done |
| Single-beat/count-one | Ordinal 0 and bin-count 1 enumerate once; a conv row returns one held BF16 result, not an empty vector |

These are implementation boundaries, not simulation or synthesis results.
Native replay must supply source callbacks, bound their continuations and
include mask/control/scratch state in the complete live ledger.

`anvil_en1_audio_subsample_point` executes one complete native spatial
point, not an independently normalized convolution channel. Its descriptor
omits output_channel: gather all 128/32 rows in ascending channel order
through `audio_conv_row`, then learned channel LayerNorm 0x2001/2003 with
epsilon 1e-6, then BF16 ReLU. ReLU maps strictly negative nonzero finite
values and negative infinity to +0, preserves signed zero and positive
values/infinity, and preserves canonical quiet NaN. The point streams
128/32 actual channels in ascending order with last on the final channel.
The sampled output validity word comes from original frame 2*output_time
for stage 0 or 4*output_time for stage 1, matching mask[:,::2] at each layer;
invalid output points still execute the actual convolution/norm/ReLU path.
The caller must use this mask for the next stage, not suppress an encoder
layer or manufacture a zero normalized point.

One 128-component synchronous BF16 bank reserves and charges 256 bytes
from accepted start through completion acceptance, also for stage 1 and
failed/partial receives. Complete successful convolution rows are necessary
before norm-source visibility. Each norm-source callback captures its index,
reads RAM synchronously and publishes the captured response on a later edge.
One scalar output reservation decouples accepted normalized output from the
ReLU classification/public output; all three events are distinct edges.
While public output is stalled, index/data/last stay stable; norm completion
cannot retire until the final public output has retired. Shape-one jobs
still perform all native channels. Numerical, directory and control state
is additional to the bank. This point engine does not cache spatial tensors,
perform the 1024-dimensional flattened input projection, implement replay
dispatch, or supply its source callback from a host-produced feature.

`anvil_en1_audio_input` reads one actual original audio item from the
versioned immutable ANI1 input image. Its registered descriptor is model,
generation, frames, kind (0 BF16 feature / 1 validity word), frame, frequency
and audio_base. Feature frequency is 0..127; mask frequency must be zero.
Frames are 1..131072 and frame must be strictly smaller. Kind 0 selects
0x3010 [frames,128], kind 1 selects 0x3011 [frames]; all other kinds reject.
Validate the tensor directory and returned geometry/type, register byte
offset, 65-bit base sum and aligned-word end in separate stages, then issue
one actual 32-bit read. Feature rows are 256 bytes and use low/high
little-endian BF16 lanes; result_data[15:0] returns the exact encoding
without arithmetic or host normalization. Mask returns the entire word
and rejects values outside 0/1. Memory errors remain error 2; malformed
descriptors/lengths/addresses/masks remain error 5. Count all accepted
directory/payload reads, including failed responses, as original-input
bytes. No write or generated-feature memory path exists. Scalar held
words/descriptors are counted by controller_bytes; there is no vector RAM.
This is the original-input service for subsampling, not a replacement
for native layer-0 point production or bounded replay.

`anvil_en1_audio_subsample_execute` connects the point's raw stage-0 sources
and all original validity reads to `audio_input`. Stage-1 generated sources
request the actual preceding normalized/ReLU point through the generated
callback (generation/model/time/frequency/channel); the callback never
accepts a finished convolution row or encoded audio hidden vector in place
of that component. Native replay must produce it. Callback acceptance
registers and validates tags before any original-input or generated request.
Mask/source responses are captured, registered and then exposed to the
point on a later edge. First callback failure is retained, including
audio_input error 2/5, and overrides the point's boolean callback error 7
after the failed child response retires. No further source work can pass
as successful after a callback failure.

External ownership belongs to original-input service only while servicing
a drained point mask/source callback; otherwise it belongs to point weight/
norm work. Point callbacks arise only after its preceding weight response
has retired; point memory ready/response-valid are disabled throughout the
original-input service. The original-input response retires before ownership
returns. Count accepted input-directory/payload transfers as original-input
bytes and accepted point-directory/matrix/norm-scale transfers as weight
bytes, including failures, with no double counting of logical mask/source
callbacks. Generated reads expose a separate two-byte logical source event,
not invented external traffic. This wrapper adds scalar state but no vector
copy; the point's full 256-byte allocation remains live until actual done.
Stage-0 spatial point execution is connected to its real input boundary;
stage-1 preceding-point replay, flattened input projection, the remaining
audio layers and native system dispatch are still required.

`anvil_en1_audio_subsample` is the real complete native input projection.
Capture a native output token time (0..ceil(frames/4)-1), original input/
audio-weight bases, generation/model/precision; validate matrix 0x2004 at
layer 0xffff as 1024 rows by 1024 columns. Compute all 1024 rows in ascending
order. For each actual requested source column, frequency=column[9:5] and
channel=column[4:0] are the pinned [frequency,channel] flattening of stage 1.
Execute the full stage-1 point through `audio_subsample_execute`, drain all
32 actual outputs, retain only the selected component and require complete
successful done. Its generated callback executes a complete stage-0 point,
drains all 128 outputs, retains the requested preceding-channel component,
and returns it only after actual complete done. Stage 0 reads raw inputs
through the real immutable-input service. These two fixed controller levels
are bounded, synthesizable native rematerialization, not recursive RTL or
an external feature archive. There is no memo of a complete spatial tensor.

The upper matrix waits for the stage-1 point; the stage-1 point waits for the
stage-0 point. Parent memory ready/response-valid are disabled while the
child owns memory. Each ownership handoff occurs after the parent's prior
accepted weight response has retired; each child finishes and retires its
own responses before returning a component. Failed child errors propagate
through the enclosing failed source responses and are preserved verbatim
at the final completion. Every nested original-input and weight transfer
is real and counted once in its actual class. Recomputing all point channels
per selected component causes very high weight/input traffic and latency;
none of this work is advertised as avoided computation or a speedup.

Two separate point banks are physically reserved (512 bytes total).
Both can be live together while the stage-1 channel reduction requests
stage 0; all partially filled vectors, scalar retained components,
projection/norm/directory/arithmetic state and controller state are
additional in the ledger. No 1024-component input bank or output copy
is allocated: the projected rows stream, with completion waiting for final
acceptance. Every stage-1 result's mask must agree with the immutable
original output mask, sampled at frame 4*token; a false mask does not skip
numerical input projection. The complete conformer encoder, native
continuation/frame dispatch, final audio projection and top-level session
integration remain separate unfinished requirements.

The pooling leaf accepts one physical pooled-bin index, not a host-generated
feature or a text placeholder index. For the pinned kernel 3, patch_count
must equal 9*pool_count; patch_rows*patch_columns must equal patch_count.
The immutable original-input directory supplies kind 0x3001 signed x/y
coordinates. Scan all patches first to find max(clamp(x,0))+1, as in the
pinned pooler; use floor(max_x/3) as the pooled-row stride. For every patch,
the exact pooled index is floor(clamp(x,0)/3) +
stride*floor(clamp(y,0)/3). Validate every such index before source access.
Only (-1,-1) is padding; malformed or out-of-grid coordinates reject.
An all-padding image rejects before division or generated-source access.

Bin mask is **weight presence**, including clamped padding in bin zero,
not merely presence of a nonpadding patch. Padding contributes positive zero
without reading its encoder output. Each component sums separately rounded
binary32 products BF16(hidden)*weight in ascending patch order, with weight
binary32(1/9) for matching bins and positive zero otherwise. Nonpadding
nonmatching patches still supply their real encoder component: this preserves
zero-times-infinity/NaN semantics instead of assuming all features are finite.
The complete pooled component is RNE narrowed to BF16, then widened,
multiplied by the RNE binary32 sqrt(768), and narrowed again to BF16.
Pinned standardize=false introduces no bias/scale tensor. All 768 components
are streamed; a false-mask physical bin is explicit and cannot count as a
valid soft token. The enclosing native producer still must enumerate true
bins in ascending order, strip false bins and validate placeholder counts.
The configured 280-token input therefore has 2520 padded patches; bounded
fixtures can use fewer groups without shrinking the native vector width.

`anvil_en1_uint_div` is a registered 32-digit restoring unsigned divider,
with separate comparison and subtraction edges for every digit.
It has no combinational divider, modulo, or data-dependent unbounded loop.
Divide-by-zero returns error 5 after registered classification.
Pool integer quotients and floating reciprocal/root use real iterative RTL.
No division is inferred from an RTL expression.

The modality projection leaf accepts image_class 1/2 and an immutable
vision/audio weight-image directory. Source width is 768 for vision,
1536 for completed native audio. Execute unscaled RMSNorm with epsilon 1e-6,
materialize the complete BF16 normalized vector, and compute ascending H
output rows through the real
BF16/Q4 decoder and projection primitive. It is neither a clipped linear
nor an additive text-embedding substitution. COMPACT changes H to 8 only;
source width remains native. No learned norm scale, bias or extra sqrt(H)
is applied. Matrix 0x1200/2202 at layer 0xffff is validated before starting
the normalization, so malformed weight images cannot consume source work.
One 1536-component synchronous BF16 bank reserves 3072 bytes;
live bytes are 1536/3072 from norm start through completion acceptance,
including partially received vectors. Complete ordered norm output and
successful done are necessary before bank visibility. Final completion
follows the final accepted projected component.

| Pool/projection boundary | Registered behavior |
| --- | --- |
| Start P0/P1/P2 | Capture descriptor; validate ranges; register grid products before comparing; only then access the directory |
| Coordinate read | Separate row offset, address sum, bounds comparison, accepted response and coordinate validation stages |
| Integer quotient | Capture operands; classify; 32 two-edge restoring digits; publish; stable result until accepted |
| Bin mapping | Divide x and y separately; register stride*y; later add x; validate pooled index |
| Pool source | Capture accepted BF16 component/error; multiply then add through separate real binary32 operations |
| Pool arithmetic | BF16 pooled materialization precedes sqrt(768) scaling; final BF16 output held until accepted |
| Modality norm | Validate projection directory first; preserve exact count/index/last and actual child error; commit only after complete successful norm |
| Projection source | Capture column, synchronous bank read, later response; no external generated-feature read |
| Error/reset | Explicit held error after accepted responses retire; reset zeroes public outputs and clears visibility, never resets payload RAM |

These leaves supply downstream numerical operations, not native Eval
dispatch, source-vector production, the complete audio encoder or top-level
inference. Whole-system native scratch and fallback limits remain to be
connected and independently measured. No numerical, synthesis or physical
acceptance is claimed.

`anvil_en1_vision_feature` connects a real physical-bin pool to the real
vision modality norm/projection. Its public source requests entering vision
layer 16 from the native producer, never a projected host feature. It captures
model/precision/generation, the entire patch/grid/bin descriptor and both
immutable image/weight bases. One 768-component synchronous BF16 bank receives
the pool result. Its complete indices/last and consistent bin mask, together
with actual successful pool done, are required before source visibility.
False bins drain all components and complete successfully with done_mask=0,
emitting no text-space vector. True bins emit all H projected components in
order and complete with done_mask=1 only after the last acceptance.

The raw pool bank is live from accepted pool start through completion
acceptance, including false-bin and failed receives: 1536 bytes. It remains
live during unscaled normalization, concurrently with the projection leaf's
1536-byte vision normalized vector. Their total live vector peak is 3072
bytes, their physical reservation is 4608 bytes, and all scalar/child state
is additional. The normalized bank is not charged before real norm start.
No controller may silently reuse or externally spill either bank. Source
callbacks use synchronous reads and delayed stable responses. Memory routing
stays with the selected pool or projection until actual child completion,
not a combinational change in live descriptor ports. Whole-system phase
overlay still must place these leaves inside the native scratch ceiling.
Physical-bin enumeration/valid-ordinal mapping remains the native session
producer's responsibility; done_mask is not a placeholder-count certificate.

### Native audio feed-forward residual

`anvil_en1_audio_feedforward` selects native feed_forward1/2 with modes 1/2,
layer 0..11 and a registered model/precision/generation/token/weight descriptor.
It loads all 1024 actual input components, retaining the unclipped residual.
Clamp a separate working vector to BF16 bounds 0xd015 and 0x5015: these are
BF16_RNE(-1e10)..BF16_RNE(1e10), matching the pinned scalar gradient_clipping.
Apply learned pre-RMSNorm kind 0x2100/2111; execute every real clipped
FF1/SiLU/FF2 output row through `anvil_en1_native_mlp_row` mode 1/2; clamp that
branch again; learned post-RMSNorm kind 0x2103/2114; separately rounded
binary32 multiplication by 0.5 and BF16 materialization; binary32 addition
of the unclipped residual and BF16 materialization. Stream all 1024 results.
Do not apply 0.5 to the residual or invent a GeGLU up matrix for audio.

The three synchronous 1024-component BF16 banks (residual, normalized working
input, output branch) reserve 6144 bytes with default local storage.
The replay audio wrapper selects the external residual/working overlay
specified above; this worker then declares only its 2048-byte branch.
Charge the complete 6144-byte live padded
allocation from accepted job start through done acceptance, even during
receive, errors and output stalls. Inputs and branch become readable only
after their entire vectors are received; norms overwrite only a component
already consumed during the output pass, after full scalar reductions.
This is local-vector reuse, not causal overwrite of another encoder token.
The connected native encoder still owns historical/chunk/conv dependencies.

| Audio FF boundary | Registered behavior |
| --- | --- |
| Descriptor F0/F1/F2 | Capture full job; validate mode/model/precision/layer/token before input or weight requests |
| Input/MLP receive | Register accepted result; write on a later edge; complete vector before norm visibility |
| Clamp | Synchronous read and later capture; real BF16 interval check; write only after acknowledged clamp result |
| Norm | Actual directory/scales/RMS; check complete ordered index/last and done before next stage |
| MLP callback | Tagged requested component; synchronous working-bank read; later stable response |
| Final residual | Read both banks; register operands; multiply, BF16 narrow, widen, add and BF16 narrow in distinct registered calls |
| Error/reset | Drain child result, preserve original error, no new work after failure; zero reset outputs without payload RAM reset writes |

This completes each audio FF sublayer, not audio attention, light convolution,
subsampling, output projection, durable native replay or complete inference.

## Connected native vision layer and mixed-domain replay storage

`anvil_en1_vision_layer` now connects the real vision attention row executor
to the complete post-attention vision residual/MLP path. Its registered
descriptor is model, precision, generation, patch count/grid, query patch,
native layer 0..15 and immutable input/vision-weight bases. Native geometry
remains H=768, I=3072, Q=12, D=64 in both text verification modes.
Source callbacks identify the generation/model/entering layer/patch/component;
the producer must return committed on-chip entering-layer components and
preserve all bidirectional inputs until their consumers have finished.
This connected leaf does not provide recursive source service or replace the
still-required bounded native replay dispatcher.

`anvil_en1_vision_attention_row` computes one genuine clipped output row
(kind 0x1106). For each actual ascending-column callback, it executes the
native attention head indexed by column[9:6], drains all 64 acknowledged
components, selects column[5:0], waits for successful head completion and
then responds to the waiting output projection. It explicitly checks
indices, last flags, selected-component presence and full head completion.
It does not allocate a complete concatenated attention tensor. Repeated
head/Q/K/V/coordinate/weight computations are actual work, not cache hits or
avoided projections. A malformed grid is rejected after a registered
16x16 product and later comparison, before the first row memory command.

Memory ownership passes to the head only while the output projection is
waiting for an accepted source callback and its earlier memory response has
retired. It passes back only after actual head completion. A failed head
returns its actual error through the waiting row; the first child error is
preserved instead of being collapsed to successful zero output. No layer
source callback is interpreted as permission for external feature storage.

`anvil_en1_native_norm` is a learned native normalization wrapper. Vision
uses image_class 1, vector length 768, layer 0..15, and kinds
0x1100/1107/1108/110c. Audio image_class 2 permits LayerNorm for subsampling
kinds 0x2001/2003 at layer 0xffff, lengths 128/32, and learned RMSNorm for
layer 0..11 kinds 0x2100/2103/2104/210b/210c/210f/2111/2114/2115,
length 1024. Audio head per_dim_scale 0x2109 is not a norm descriptor.
LayerNorm subtracts the real ascending-component mean and uses centered
variance; its learned affine scale has no bias. Native vector lengths never
shrink in compact text builds. The wrapper validates the immutable BF16
scale descriptor through the real directory, reads every scale through the
BF16 weight decoder, and executes `anvil_en1_norm` with epsilon 1e-6.
Scales are BF16 in both matrix precision modes. Its source/output streams
are individually acknowledged; the original scale-read error survives the
norm's failed response and later completion.

`anvil_en1_vision_post_layer` performs these frozen operations in order:
load the raw entering vector and real output-projected attention branch;
learned post-attention RMSNorm; BF16 residual add; learned pre-feedforward
RMSNorm; every clipped GeGLU/down row through `anvil_en1_native_mlp_row`;
learned post-feedforward RMSNorm; BF16 residual add and ordered output.
The input attention branch is already output-projected, not a raw head.
Each residual widens its two BF16 operands, separately rounds the binary32
add and then RNE materializes BF16. There is no text PLE, text layer scalar,
audio 0.5 weighting or extra final norm in this vision layer.

Three synchronous 768-component BF16 banks retain the raw/residual, normalized
attention/MLP input and MLP output vectors: 1536 bytes each, 4608 bytes total.
Standalone instances own all three. The replay wrapper shares the branch's
physical bank with its earlier, completely consumed projection staging,
as specified in the projection/branch overlay table above; the post worker's
live reservation still includes that branch.
The raw residual survives every MLP row. Only the norm output phase overwrites
an already consumed component of its source bank, after full reductions.
There is no bidirectional overwrite of another patch's entering vector.
Input banks become readable only after all 768 components are stored.
Norm output guards check count/index/last and reject incomplete materialization
before subsequent work. Final output is held through backpressure, and done
follows acceptance of component 767. Bank allocations remain charged through
error or success completion acceptance.

| Boundary | Registered behavior |
| --- | --- |
| Layer L0/L1/L2/L3 | Capture descriptor; validate all ranges; grid product; grid equality check; only then start post worker |
| Raw/branch input | Capture accepted response; store on a later edge; commit only after final component |
| Norm directory/scale | Validate directory result before scale access; register scale result before response; retire failure through norm |
| Local bank callback | Capture index/bank; validate committed visibility; synchronous read; later capture and response |
| Attention row callback | Capture requested column; validate; execute/drain actual head; check full output; later source response |
| Norm transition | Check complete 768-component output on an edge after child completion before dispatching residual/MLP |
| Residual | Synchronous bank read; capture operands; real binary32 add; BF16 conversion; store or stalled output |
| Reset/errors | Public outputs zero; payload RAM is not reset; reset clears visibility; accepted child errors retire before explicit done |

Each wrapper exposes byte-rounded declared controller-register widths, with
all numerical/directory/weight child registers additional. Layer vector
live observations include the post worker's up to 4608 bytes and the existing
1664-byte Q/K/V tile reservation, without a second sum of the tile.
Replay physical observations count the 1536-byte shared staging/branch bank,
3072-byte private post banks and 1664-byte tile once each. Reserved
vector capacity is not measured M20K block use. The whole-system native scratch
limit, fallback arithmetic/control limit, resource fit and timing still
require complete connected allocation accounting and independent evidence.

Compact text replay no longer substitutes H=8 for native vector frames.
`anvil_en1_eval_schedule` and `anvil_en1_replay_workspace` select 8 for domain
0/3, 768 for vision and 1024 for audio. Compact physical frame strides
are 3072 words, with two 1536-word banks; memo strides are 512 words; scalar
strides are 34 words. Frame/memo regions are disjoint for mixed-domain
stacks, including the upper native component and the next frame/memo slot.
The existing generation/rank/tag/committed-vector guards remain in force.

Compact live reservations count each granted complete vector prefix:
16 text/feature, 1536 vision or 2048 audio bytes per reserved slice, plus
136 scalar bytes per pending/live frame. Memo reservations count 16/1536/2048 bytes by domain,
including pending writes/copies. Eviction first releases the old reservation,
then charges the new one; its domain is retained as metadata. Push/pop/reset
update the real domain-specific live totals. Unaddressable stride holes
are unused physical capacity, not occupied tensors or claimed memory savings.
The memo-domain map is 32 metadata bits. Four 32-bit allocation totals
(actual/shadow frame and memo bytes) belong to controller state, not metadata.
Production uses the same domain-specific grants: text/native feature frames
can reserve two H vectors, vision two 768-vectors, and audio six
1024-vectors; memo entries reserve one vector. Shadow counters independently
track the production-width counterpart of every granted prefix during compact execution. Scalar
reservations are 136 bytes per production, shadow and compact frame.
Pending allocations count before backing writes; committed
totals change on vector grant/pop/memo commit/eviction, with reset/invalidation
clearing all four totals. Physical layout and supported depths are unchanged.

The compact backing address space reserves 206976 words / 827904 bytes.
The current disjoint ordinary backing physical layout is specified at the
start of this document. The ordinary frontier cap stays 8192 bytes / 512
text tokens. A fallback mode transition must still release the ordinary
frontier before binding its base-zero backing; no simultaneous old/new
representation or additional payload array is introduced.
This is source-level layout repair, not an executed liveness/savings result.
Native dispatch/continuations, pooling/feature source integration, audio execution,
single-token linear replay, full allocation accounting and top integration
remain necessary before design readiness.

## Bidirectional native vision attention and replay boundary

`anvil_en1_vision_attention_head` executes one native 64-component head over
all supplied patches, including keys after the query's patch index. There is
no text causal/window mask, grouped-query alias, text owner metadata or
head-dimension scaling: pinned vision scaling is 1.0. Its mask channel returns
whether each key's original coordinates are nonpadding. Padded query patches
still execute attention; the pool, not the head, suppresses their final encoder
features. Immutable coordinates and source vectors must survive all three
softmax passes and every replay yield.

The scalar algorithm shares the existing binary32/exp/division primitives.
Pass 0 computes the maximum score and valid-key count. Pass 1 recomputes the
same scores and sums max-subtracted exponentials. Pass 2 recomputes scores,
materializes BF16 probabilities, and accumulates one BF16 output component
in ascending key order. Pass 2 repeats for components 0..63, avoiding a live
score/probability tensor or vector accumulator. Q/K dot products use ascending
components, separate binary32 multiply/add, and no intermediate BF16 score
rounding. Only the completed value reduction narrows to BF16. An all-masked
image rejects with descriptor error 5 without reading Q/K/V or dividing by
zero; it is not converted into a successful zero feature.

Q/K/V service requests specify model, precision, native layer, patch, selector
(0 Q / 1 K / 2 V), head and even aligned component 0..62. The returned 32-bit
word contains the actual adjacent BF16 pair, low component first. Every
accepted service response is registered before lane selection and arithmetic.
The service must compute from immutable on-chip entering-layer vectors,
never an externally supplied generated feature.

In `REPLAY=1`, each service request first publishes a dependency decision.
Action 0 means the source vector is available, 1 requests a drained yield,
and 2/3 reject with cache-state error 7. The consumer must commit the current
query vector as well as historical keys; query projection can itself require
an Eval child. A yield happens only before accepting a service request, with
mask/arithmetic/service transactions all retired. `checkpoint_valid` holds the
complete 512-bit numerical continuation until acceptance, then the head
returns idle without a false done. An enclosing layer dispatcher must store
it in acknowledged scalar continuations before executing a smaller-rank
vision Eval dependency. Resume revalidates the complete descriptor/generation,
then reacquires the same dependency decision and service request. No unfinished
reduction, accepted output, or BF16 probability is discarded/recomputed with a
different reduction order.

| Checkpoint bits | Meaning |
| --- | --- |
| 511:480 | Magic 0x454e3156 |
| 479:448 | Session generation |
| 447:446 / 445:444 | Native model / precision |
| 443:436 / 435:432 | Vision layer / query head |
| 431:400 / 399:368 | Query patch / patch count |
| 367:336 / 335:304 | Current key patch / valid keys counted |
| 303:302 / 301:296 / 295:290 | Pass / dot component / output component |
| 289:288 | Pending Q/K/V selector |
| 287:272 / 271:256 | BF16 query component / BF16 probability |
| 255:224 / 223:192 | Binary32 dot accumulator / maximum |
| 191:160 / 159:128 / 127:96 | Binary32 exponential sum / inverse / value accumulator |
| 95:0 | Reserved zero |

`REPLAY=0` ignores resume inputs and never emits a dependency/yield. Both
parameter values use exactly the same arithmetic and native production
geometry. Invalid parameter values explicitly diagnose; no compact vision
geometry or synthetic head result is introduced.

| Vision head boundary | Registered behavior |
| --- | --- |
| H0/H1/H2 | Capture complete descriptor; validate model/precision/layer/head/count/query; first mask/restore work only after validation |
| Mask M0/M1/M2 | Accept request; register accepted response; then decide skip/start-dot; invalid mask responses explicitly fail |
| Service S0/S1/S2 | Dependency decision precedes registered request; register pair/error; select the requested lane on a later edge |
| Replay yield | No outstanding response; hold checkpoint; acceptance returns idle, not successful done |
| Resume | Match generation/model/precision/layer/head/query/count, zero reserved bits and legal traversal/selector before source work |
| N=1 | Exactly one permitted key per pass; query patch 0; component 63 is the final output |
| Output/completion | Stable component/index/last while stalled; advance only on acceptance; done follows acceptance of component 63 |
| Reset/error | All public outputs zero during reset; retire accepted child responses, stop new work, hold explicit failure completion |

`anvil_en1_vision_attention_execute` binds the head to a literal
`anvil_en1_vision_qkv_tile` and real immutable coordinate reads. It validates
the original image's coordinate-directory entry before starting the head.
Every mask and Q/K/V service request rereads both signed coordinates for
that patch, checking padding or nonnegative in-grid coordinates before
dispatch. Original-input traffic includes these accepted coordinate reads,
including failed responses and repeats. Tile directory/projection/scale
reads are separate immutable-weight traffic. The executor never drives a
write command or interprets the tile result as an external address.

Source callbacks expose the captured generation/model/layer/patch and actual
component requested by the tile's input norm. Their producer is a committed
on-chip Eval/frame source. During replay, the public dependency descriptor
identifies precisely the Q/K/V source patch about to be used. Yield releases
the head only after its held checkpoint is accepted; the executor itself
returns idle on that same acceptance, without a normal done. The enclosing
native layer dispatcher must durably save the checkpoint before child work.
This executor does not implement that dispatcher or bidirectional overwrite.

Coordinates use aligned 32-bit reads. The captured patch*8 offset, row start,
parallel row/payload ends, extent comparison and later y-address each have
separate registered stages; all 65-bit
address sums reject overflow or out-of-payload extent before access. A failed
coordinate memory response is retired and preserved as external error 2,
not collapsed to mask-state error 7. A malformed pair rejects with 5. The
head receives its actual failed mask/service response and retires completion
before executor failure publication. Child routing remains selected through
stalls and accepted responses; no same-edge newly created response is consumed.

The head's declared controller bytes include
its held 512-bit resume word and scalar operands; floating-point, exponential
and reciprocal child state are additional. There is no vector bank in this
head or executor. Tile live/physical vectors and controller observations are
forwarded separately, not included twice. All tile/head numerical children
still require whole-system accounting and phase overlay. The connected
vision residual/GeGLU leaf is described above; durable native continuation
dispatch, pooling/feature integration and audio execution remain required. This
interface freeze is not functional or timing evidence.

## Native clipped-linear and vision-input implementation boundary

The next owned increment implements scalar BF16 clamp, a real directory-driven
native clipped projection, and the vision Eval(0,patch) input operation. These
are numerical building blocks, not an authorization to replace either native
encoder with patch projection or to accept a host-produced feature.

`anvil_en1_bf16_clamp` captures a BF16 value and BF16 min/max. Signed zero
compares equal irrespective of sign; equal endpoints leave the value unchanged.
Finite/subnormal values and infinities compare by sign and magnitude. A NaN
value becomes canonical 0x7fc0. NaN bounds or min>max return descriptor error 5,
not a silently sorted interval. The comparisons and final selection occupy
separate registered stages. This helper has no vectors or memory commands.

`anvil_en1_clipped_projection` accepts native model/precision, image_class
(1 vision / 2 audio), tensor_kind/layer, image_base and row_index. Only actual
clipped matrix schema members are legal. It validates and reads each scalar
input_min/input_max/output_min/output_max from the immutable native directory
using kind+0x4000/5000/6000/7000, then validates the matrix itself. Bounds are
validated before source reads or numerical matrix execution. One captured
BF16 source value at a time is clamped with the same scalar helper and supplied
to the existing projection's ascending-column, separate binary32 multiply/add
path. The materialized BF16 row is output-clamped before completion. There is
no retained clipped input vector, altered Q4 order, external activation write,
or new numerical reduction implementation. Accepted directory/bound/matrix
transactions, including failed responses and repeated reads, remain weight
traffic. Future folded GeGLU/conformer controllers must use this path at every
pinned clipped linear, not just the final projection.

`anvil_en1_vision_patch` accepts model/precision, immutable image_base and
vision_weights_base, patch_count/rows/columns, and patch_index. Geometry is
native 768 input/output components even in a compact text build. It checks
rows*columns exactly equals patch_count, bounds patch_count to 131072 (the
existing Eval token domain), and requires each axis in 1..10240. The validated
axes use a registered 16x16 product and a later extent check; no runtime divider or
unchecked truncated extent is used. It validates input tensors 0x3000/3001
and weight tensors 0x1000/1001 before reading numerical payload. The selected
coordinates must be either (-1,-1) padding or nonnegative x<columns,y<rows.
Patch order is the input directory row order, not an assumed spatial order.

Each projection source request reads the actual BF16 pixel at
[patch_index,component] from the immutable input payload. Pixel preprocessing
uses binary32 subtract 0.5 and BF16 materialization, then binary32 multiply
2 and BF16 materialization before the dot product. Patch projection narrows once after
the complete ascending-column reduction. Position x and y entries are BF16:
their binary32 sum narrows once, then its binary32 sum with the BF16 projected
row narrows once. Padding suppresses only the position addition here; it does
not fabricate a zero patch projection. The later pool must suppress padding
encoder outputs as prescribed by the pinned model. The streamed patch outputs
are ascending 0..767 and stable under backpressure. Each is genuine computed
BF16 data; done follows acceptance of component 767. No 768-component
pixel/output bank or generated modality feature archive is allocated.

| Native leaf boundary | Registered stage and degenerate/error behavior |
| --- | --- |
| Clamp A0/A1/A2/A3 | Capture; classify/compare; select/error; publish held result; no same-edge consumption of first valid |
| Clipped projection P0/P1/P2 | Capture native descriptor; validate schema/row/model/precision; dispatch first directory read |
| Source request S0/S1/S2 | Capture the requested index; accept/register external on-chip source response; only then start clamp |
| Source clamp response | Retire the clamp before presenting held BF16 to projection; index remains stable until it is consumed |
| Bound read M0/M1/M2 | Accept aligned read; capture response on a later edge; use value/error on a subsequent edge |
| Vision patch V0/V1/V2 | Capture; validate domain; register the 16x16 extent product before later extent validation |
| Patch/source length one | Each primitive allows a single source; patch geometry itself remains fixed 768, never silently reduced |
| Padding | (-1,-1) suppresses positions only; mixed negative/nonnegative coordinates reject before pixel/projection access |
| Final output | Retire final streamed patch component before done; output and done payloads remain held during stalls |
| Error/reset | Retire each accepted child/source/memory response before failure; stop new work; active reset zeros all public outputs |

All child arithmetic/control and tensor validator registers remain additional
whole-system allocations. Scalar-only leaves do not prove the native scratch
bound, physical fit, full fallback ledger or timing. Complete native
vision/audio replay binding, pooling/feature integration, session/masks and compatible
literal top integration remain necessary before the design can be ready.

### Native vision Q/K/V tile

`anvil_en1_vision_qkv_tile` captures native model/precision, vision layer 0..15,
patch index 0..131071, selector 0 Q / 1 K / 2 V, head 0..11, even aligned
component 0..62, immutable vision_weights_base and signed x/y coordinates.
Coordinates must be (-1,-1) padding or nonnegative values below 10240.
Its H source request/response is an immutable on-chip Eval/frame vector, not
an external generated-feature tensor. It executes learned 768-dimensional
input RMSNorm, 64 actual clipped projection rows for the selected head,
then learned 64-dimensional Q/K RMSNorm or unscaled V RMSNorm. Q/K rotate
separate 32-dimensional x/y partitions at theta 100; V never rotates.
Projection input rows are read in ascending-column order by the existing
clipped projection. This tile has no text owner alias or shared K/V weights.

The tile reserves one 1536-byte normalized-input bank and one 128-byte head
bank, both synchronous M20K-candidate arrays with no asynchronous payload
reset. Full banks become live before any partial write and remain charged
through final result acceptance; partially initialized data is never readable.
Projection cannot read the normalized input until its checked full stream
and norm completion. Head norm follows all 64 projected rows. Its output pass
may overwrite the just-read component because no later norm operation reads
that component again. Pair reads follow the complete checked head-norm stream.
The RAM read and capture stages are separate and serialized with source reads.
Declared vector_live_bytes and vector_physical_bytes cover these two banks;
all tile, directory, clipped-source, norm, scale-reader, rotary and scalar
arithmetic registers remain additional whole-system arithmetic/control state.

The existing rotary-pair leaf gains default-off `SIGNED_POSITION=0/1`.
Default 0 preserves the unsigned text range 0..131071. Mode 1 converts the
two's-complement position's magnitude through the existing real unsigned
converter, restores its binary32 sign before angle multiplication, and permits
magnitudes through 131071. No negative position is treated as zero. Vision
enables this mode so padding coordinates -1 obey the pinned axial arithmetic;
their attention/pooling mask remains the enclosing encoder's responsibility.
This parameter adds no alternative trigonometric approximation or tensor
answer. Illegal parameter values explicitly diagnose.

| Vision tile boundary | Registered behavior |
| --- | --- |
| T0/T1/T2 | Capture full descriptor; validate all native ranges; start input-scale directory lookup |
| Input/head visibility | Exact ascending index and last checks plus successful norm done precede use |
| Clipped row result | Retire real projection response, write one raw head component, then advance row |
| Scale failure | Drain the accepted weight response and norm error before tile completion; preserve external error 2 |
| Internal source | Capture index; validate committed bank; synchronous RAM read; capture; held response |
| Axial pair | Read i and i+16 within the selected 32-component partition; execute mode-2 rotary; select the requested lane |
| Pair completion | Preserve first adjacent component while computing second; publish aligned 32-bit BF16 pair only after both |
| Reset/stall/error | Zero public outputs in reset; hold request/result descriptors while stalled; no partial bank, fixed-latency success or external KV write |

These native tiles still require bidirectional vision Eval/layer dispatch,
native audio execution and complete top integration. They do not establish
whole-model behavior, resource fit or independently observed acceptance.

### Folded native MLP row

`anvil_en1_native_mlp_row` computes one native output row with no allocated
intermediate vector. Mode 0 is vision GeGLU: real clipped gate/up kinds
0x1109/110a, BF16 GELU_tanh and gated multiply, then real clipped down kind
0x110b. Modes 1/2 are audio feed_forward1/2: clipped kinds 0x2101/2112,
BF16 SiLU, then clipped kinds 0x2102/2113. Audio does not invent an up
projection or multiply by a host-provided vector. The surrounding native
layer remains responsible for its pre/post norms, residuals, audio gradient
clamps and 0.5 residual weighting.

The outer down clipped projection owns the ascending 3072/4096-component
reduction. Each source callback captures the requested intermediate row,
temporarily routes the one external command stream to the inner real
gate/up clipped projection, and returns its genuinely computed BF16
activation/gated value. Outer down input/output clipping is still applied
by that actual clipped projection, not bypassed with the unclipped
`gated_projection` helper. Each additional gate/up execution and all accepted
directory/bound/matrix reads are actual weight work/traffic. Output-row
repetition regenerates intermediates exactly; no throughput or total DDR
improvement is claimed.

Source callbacks expose generation, native model/layer/token, mode and actual
component, referring to the committed, already pre-normalized on-chip layer
input. The producer must keep it immutable through every gate/up reduction.
The leaf never writes hidden state externally. No callback accepts a
precomputed MLP intermediate, activation, or numerical answer.

| Native MLP row boundary | Registered behavior |
| --- | --- |
| R0/R1/R2 | Capture descriptor; validate mode/model/precision/layer/token/output-row; then start real down clipped projection |
| Intermediate callback | Capture exact requested row; validate range; start actual gate projection, then up only in vision mode |
| Down continuation | Its real weight/partial sum remain held while the inner source is computed; outer memory route resumes only after inner retirement |
| Activation | Vision uses materialized GeGLU; audio uses SiLU then one BF16 narrowing, with no invented up multiply |
| Source failure | Return acknowledged failure to down projection; preserve original child error rather than collapsing all failures to 7 |
| Completion | Retire down done only with source service idle; register numerical result/error, then publish held completion |
| Reset/stall | Zero every public output in reset; hold source/command/result descriptors; no partial success or activation spill |

Declared controller bytes count descriptors, callback indices, held gate/up/
activation/output scalars and routing state. Both actual clipped-projection
controllers and scalar-clamp state are exposed separately; their numerical/
directory children and activation/GeGLU/narrowing engines remain additional
whole-system allocations. This leaf has no live/reserved vector bank.
It is not a complete vision residual layer or audio conformer, nor the durable
native replay layer dispatcher required before design readiness.

### Durable native vision-head continuation

`anvil_en1_replay_vision_attention` connects the real replay-enabled vision
executor to the existing workspace's acknowledged scalar operation 6/7,
target 0. The current frame tag is native domain 1, model/generation, query
patch, entering layer `frame_layer=vision_layer+1`, length 768 and frame slot.
No compact native-vector substitution is made. The mixed-domain compact
workspace now supplies real native frame widths as described above; the
enclosing native worker must still bind them and service the smaller-rank
dependency before native replay readiness.

At a real head yield, capture the complete 512-bit checkpoint and pending
source patch, then write all 16 little-endian words to scalar indices 8..23.
Every word waits for its real acknowledgment; only the final successful
acknowledgment permits done_yield. Words 0..7 remain scheduler-owned; 24..31
are available to an enclosing native layer's branch continuation. A failed
save returns the actual error without a usable yield continuation. Resume
validates the outer tag, reads/acknowledges all 16 words, then the real head
revalidates its full numerical descriptor before execution. Scalar occupancy
and the backing controller, not an uncounted local array, determine whether
the words exist. No synthetic successful backing response is generated.

The 160-bit outer continuation is:
159:128 magic 0x454e3157; 127:96 generation; 95:64 query patch;
63:56 frame layer; 55:50 frame slot; 49:48 model; 47:46 precision;
45:38 vision layer; 37:34 head; 33:0 zero. The yielded dependency is
`Eval(vision_layer,pending_patch)` and therefore strictly below the current
`Eval(vision_layer+1,query_patch)` frame. Query, key and value source needs all
use this dependency boundary; none recurse at the same encoder layer.

| Durable head boundary | Registered behavior |
| --- | --- |
| W0/W1/W2/W3 | Capture complete descriptor/frame/continuation; validate native frame/outer tag; registered 16x16 grid product and later extent check precede any work access |
| Yield capture | Accept only with executor/tile drained; capture actual numerical checkpoint, not expected scalar results |
| Save/read request | Stable native frame tag, scalar index and data through stalls; each response registers before index advance |
| Final save | Final acknowledgment precedes yield publication; failure never publishes usable continuation |
| Resume | Read every occupied word; start real executor only after last read is registered |
| Error/reset | Preserve actual work/memory errors; active reset zeros all public outputs; no late numerical result is rebound to a new generation |

The wrapper's held checkpoint/scalars/descriptor and the executor/head resume
copies are separately charged by their controller byte observations, in
addition to the 64 live workspace scalar bytes. These are real transient
copies, not assumed memory savings. A complete native layer dispatcher,
on-chip source binding, vector/memo allocation and whole-system ledger are
still required; this acknowledged continuation path is not full fallback
acceptance.

## Frame-pair assembly and streamed attention output projection

Operation 6 retains scalar-write target 0. Its new target 2 assembles a current
frame vector one aligned BF16 pair per acknowledged request; target 3 patches
one pair of an already committed current frame vector. Operation 7 has
scalar-read target 0, private-admission target 1 and complete dead-vector
release target 2 as specified above. The scheduler permits both pair operations only with its
exact current frame tag, never a dependency memo or another frame. Components
are even and smaller than the descriptor's full H length; data is the
little-endian BF16 pair in `req_data`. Other targets reject before backing access.

Assembly starts at component 0, clearing destination visibility before its
write. A per-bank next-component counter requires every subsequent request
in ascending pair order. A new component-0 request explicitly restarts an
assembly, never preserves an old readable destination. Only a successful final
write acknowledgment commits the complete bank. Requests/responses release the
single workspace transaction between pairs, allowing raw-input reads and child
Eval execution while the unfinished destination remains live but unreadable.
Patch requires a committed bank and never changes its full-vector occupancy;
its caller must preserve the norm/output pass's no-future-read-of-overwritten-
input rule. Failed assembly or patch acknowledgments invalidate that bank.
Push/pop/session invalidation clear both assembly progress and visibility.
Progress is control metadata, not a hidden copy of vector payload.

Production and compact scalar slots contain 34 words so
the unchanged head checkpoint at 8..14 and an enclosing projection checkpoint
at 15..19 can coexist; words 0..7 remain scheduler-owned. Shadow accounting
charges the same full 136-byte scalar slot for every compact frame. The added
128 12-bit next-component registers and 128 progress-valid bits occupy 208
byte-rounded metadata bytes; existing whole-bank payload reservations do not
grow. Dedicated progress metadata is reset, not numerical RAM payload.

`anvil_en1_replay_attention_projection` streams each real BF16 head output
through the actual 0x0106 output-matrix row decoder, separately rounded
binary32 multiply/add in ascending head/component order, then narrows the
completed row once. It recomputes heads for each H output row rather than
retaining an 8192-byte global attention vector outside the frame budget.
It writes ascending completed BF16 output pairs to the opposite frame bank
through operation-6 target-2 assembly. The raw input bank remains immutable.
This is the attention branch before post-attention norm and residual, not
a completed text layer. Recomputation counts as real work and real traffic.

Every accepted component is fully incorporated into the row sum before a
head completion/yield can retire. At yield the inner head's existing 8..14
words are already acknowledged. Its lower 160 checkpoint bits are then saved
in five acknowledged words 15..19. Only afterward does the projection publish
its 160-bit outer continuation:
bits 159:128 magic `0x454e3150`, 127:116 output row, 115:112 query head,
111:102 next component, 101:70 binary32 accumulated sum, 69:54 pending even-row
BF16 value, and 53:0 zero. The pending low value is relevant when row is odd.
Resume validates descriptor/ranges/magic, revalidates immutable tensor 0x0106,
restores all five words, and resumes the actual numerical head, never restarts
its accumulated reduction. Previously acknowledged destination pairs remain
in that same frame while the shared numerical engine executes child work.

| Pair/projection boundary | Registered behavior |
| --- | --- |
| Start P0/P1/P2 | Capture descriptor/continuation; validate distinct source/destination banks and frame; then issue tensor lookup |
| Pair A0/A1/A2 | Capture request; validate aligned component and live frame; check assembly progress/committed patch destination before write |
| Pair visibility | Final backing acknowledgment precedes complete-bank visibility and the later held response |
| Head component | Capture BF16/index/last; read real matrix weight; registered multiply then add; only then advance component |
| Head yield | Retire all numerical/work/memory responses; save five lower checkpoint words; publish outer continuation after final scalar acknowledgment |
| Resume | Restore scalar words before starting the head; reacquire canonical owner metadata through the existing executor |
| Final branch | Narrow every complete row; acknowledge final assembled pair; hold done until acceptance |
| Error/reset | Drain any accepted weight/head/work transaction before error completion; invalidate failed pair visibility; reset cancels both checkpoints |

The head executor's optional `PAUSABLE=1` mode is used only by this folded
projection. `pause` may assert only immediately after acceptance of a head
component with the Q/K/V service idle and no work, mask, metadata or external
transaction outstanding. While paused, the executor gates public request/
response handshakes and does not retire head completion. The projection reads
the output weight and incorporates the component before releasing pause.
If that weight/arithmetic operation fails, it releases pause with `cancel`
asserted: new Q/fetch requests receive explicit source error and a new owner
need decision rejects, without starting another numerical tile. The head then
retires its actual error before projection failure completion. This is not a
general asynchronous cancellation of an outstanding tile. PAUSABLE defaults
off, preserving the original executor path.

No functional or synthesis result is claimed by this interface freeze.

### Shared post-attention numerical path

`anvil_en1_asym_attn_ple` adds compile-time `POST_ONLY=0/1`, default 0.
POST_ONLY=1 loads the original raw H input, original-input-derived combined
P-dimensional PLE, and the complete H-dimensional output-projected attention
branch. The existing source descriptor gains `source_is_branch`; it is mutually
exclusive with `source_is_ple`. Raw input has both selectors zero. All three
streams use the existing individually acknowledged source component interface.
After the final branch load, this mode enters the same post-attention norm,
residual, pre-FF norm, streamed GeGLU, post-FF norm, residual, gated PLE,
post-PLE norm, residual and layer-scalar FSM used by ordinary execution.
It does not renormalize an already computed attention input or project Q/K/V.
Production shapes, intermediate doubling, operation boundaries and error
handling are unchanged; POST_ONLY is not a replacement arithmetic model.
No output is emitted until every required source component is loaded.
The ordinary instance explicitly leaves the new branch selector unused.

The replay layer dispatcher must use this mode only after the real attention
projection has committed its opposite frame bank. It must reconstruct PLE
from original immutable token/modality inputs for the actual layer, not from
the preceding Eval hidden vector. It may reuse numerical scratch after a child
has returned; there are no historical Eval yields within post-attention text
arithmetic. Post-only residual/work/branch scratch and PLE are additional live
allocations, not free copies of the frame banks. All instantiated numerical
registers and any physically reserved unused Q/attention banks still require
whole-system ledger and independent synthesis scrutiny.

`anvil_en1_replay_text_layer` is the registered text Eval(l,t), l>0 dispatcher.
Fresh/mode-2 tasks bind Eval(l-1,t) into frame bank 0 through the exact predecessor
copy guard. A missing predecessor yields magic `0x454e3149` in continuation
bits 159:128 with the remaining bits zero. Mode-1 resumes either that binding
continuation or the `0x454e3150` attention-projection continuation. Other modes/
continuations reject. Attention uses logical layer l-1 and commits branch bank
1 before PLE reconstruction. Missing historical owner data yields its actual
owner/token with the acknowledged projection continuation; no shared-layer
private K/V is introduced.

After attention completes, the dispatcher rereads the immutable original token
to select permitted text/image/audio reconstruction and executes the genuine
embedding/combined-PLE engine at layer l-1. Both its H input stream and P PLE
stream must have correct ascending indices, length and last flags before PLE
becomes usable. Input values are drained, not substituted for the preceding
Eval vector. Only P PLE values are retained in an additional synchronous bank.
The post-only numerical path reads actual committed raw/branch frame pairs
through the tagged workspace and reads the checked PLE bank. Complete post
outputs overwrite frame bank 1 through ascending acknowledged pair assembly
only after the post engine has loaded its input branch. Its final done retires
only after the last output pair acknowledgment. The scheduler, not this worker,
then copies the completed Eval result to memo and releases its frame.

The PLE bank is additional 512 live/reserved production bytes (8 compact).
The reconstruction and post engines' vector banks and scalar registers are
additional allocations with phase-dependent liveness, not frame aliases.
Native modality responses still must come from the real on-chip encoder;
this worker does not implement that encoder or authorize a host feature answer.
This dispatcher is a text-layer implementation, not yet a connected complete
root Eval/native/session/top system.

`anvil_en1_replay_execute` connects the existing Eval scheduler/workspace to
the real input reconstruction and text-layer workers. Its root is text domain
0, with the full production layer count and compact numerical geometry
selected only by COMPACT. A scheduler task is captured into a registered
descriptor before dispatch. Layer 0 uses native input reconstruction; positive
layers use the resumable text dispatcher. Task completion is returned only
from the real selected worker, with its bank/dependency/continuation. Workspace
stream writes from reconstruction and pair/scalar requests from layer execution
use the same scheduler-guarded channel. Root output comes only from the
scheduler's acknowledged completed memo reads, not from a bypass stream.
Backpressure is preserved through every selected memory/work/modality/cache
channel. The external original-input/weight command port still must connect
through the one shared arbiter, and backing through the drained frontier RAM.
Native modality feature production, session/reset integration, complete live
allocation accounting and the parent-compatible literal top remain required;
this connected text Eval increment does not claim those missing surfaces.

## Replay Q, historical fetch and frame-input increment

The optional `ALLOW_QUERY=0/1` capability on `anvil_en1_owner_kv_tile`
and its workspace adapter defaults to disabled. With it disabled, root
owner replay remains strictly K/V-only and explicitly ties off the new
`is_query` and four-bit `query_head` inputs. With it enabled, a registered
`is_query=1` descriptor projects the **logical layer's own Q**, including
upper shared layers, using tensors 0x0101/0x0102. It never uses that layer
as a K/V owner. Both paths use the same learned input RMS, genuine projection,
BF16 materialization and paired RoPE arithmetic. Q has 2/8 heads in compact/
production geometry, with learned D-dimensional Q RMS. K/V retains its
1/2-head validation, owner-only matrices, learned K RMS and unscaled V RMS.
`is_query && is_value` is illegal. Actual Q row events are separate from
owner-reprojection events; they must not inflate avoided K/V work.

`anvil_en1_replay_attention_execute` connects the resumable head, Q source
and dependency projection responder. Its descriptor includes the current
Eval(layer+1,position) frame, the already committed raw-input bank, and
optionally the scheduler's one completed dependency memo handle. Q and K/V
time-share **one** workspace tile and its H/D banks. A transient Q pair
can serve its two adjacent component reads within this descriptor; it is
invalidated on every start, yield and completion. No tensor answer is
injected externally. Q pair regeneration intentionally recomputes a full
normalized head; no latency or weight-traffic improvement is claimed.

Every historical fetch first consumes real canonical metadata from the
cache, without a second alias map. The post-metadata need decision permits
the current frame only for owner=layer and token=position. Otherwise it
requires an exact completed Eval(owner,token) memo tag. Missing dependencies
yield the actual saved numerical checkpoint after acknowledged scalar writes.
On resume, the head reobtains metadata; the supplied dependency handle is
validated again before projection. The allowed fetch descriptor is captured
and must match every subsequent fetch field. Real owner computation uses
the workspace tile, not the cache's occupied root regen channel. This
inner BF16 responder is not a resident root-cache hit and does not fabricate
such telemetry. Actual source reads and projected owner rows are reported.
Masks remain the caller's real immutable-input/mask response channel.

Head outputs may precede a later yield. The enclosing layer worker must
retain every accepted component/partial reduction in its actual live frame
before handing off a dependency; it must not copy an unfinished vector to
memo or restart a saved reduction. This executor does not implement those
residual/PLE/MLP/whole-layer continuation stages or dispatch.

| Q/dependency executor boundary | Required behavior |
| --- | --- |
| Start D0/D1/D2 | Capture the complete descriptor, validate model/precision/frame/memo, then start the registered numerical head |
| Q pair | Read tagged current raw input, execute learned input/Q norms and actual Q projection/RoPE; select only the requested BF16 lane |
| Tile ownership | Q and historical projection are mutually exclusive; retain workspace/memory routing until real source and tile responses retire |
| Need/fetch | Need follows canonical metadata; allow captures the exact owner descriptor, yield issues no fetch, mismatch returns error 7 |
| Historical dependency | Missing memo requests smaller-rank Eval, never a recursive wait on root regen or an external activation read |
| Component/done stalls | Hold the actual component/checkpoint/error; done cannot retire on creation or before service responses |
| Q source error | Retire the numerical tile and head source response, preserving the actual tile error instead of losing it through the head's one-bit source-error channel |
| Reset | Zero public outputs, invalidate Q/authorization/checkpoint state and cancel the internal numerical generation |

The executor has 796 explicitly declared register bits, including both
pair registers and both held 160-bit continuations: 100 byte-rounded bytes.
`pair_live_bytes` is a **subset observation**, not additional RAM to add
again to controller bytes. The adapter now has 419 register bits / 53
byte-rounded bytes. Checkpoint bridge state is separately exposed, as is
the one 2H+2D tile-bank allocation; every child arithmetic register remains
additional whole-system accounting. The optional projection mode adds
three controller bits in the numerical tile. These numbers do not establish
the final fallback/ordinary physical or live-allocation bounds.

### Acknowledged predecessor-vector binding

Before layer attention, the worker must commit the completed preceding Eval
vector to its current frame's raw-input bank. Opening a streamed vector write
and then requesting memo reads through the same single-outstanding workspace
would deadlock. Internal store target 3 therefore means **memo-to-frame copy**,
not a streamed write and not an external activation ingress. Existing targets
0/1/2 and operation identities remain unchanged. The public request descriptor
identifies the destination live frame/bank with its complete tag; `req_data`
encodes source memo slot in bits 31:26, source layer in 25:18 and source token
in 17:0. Token bit 17 must be zero. Model/generation/domain/length are inherited
from the destination/session. The source layer must be strictly smaller than
the destination layer. The scheduler authorizes this request only if **every**
source field equals its one returned dependency, with identical domain/length.
Other target-3 requests reject before backing access.

The workspace checks the destination frame tag, then synchronously reads the
specified occupied memo tag and compares its full source identity. Only then
does it invalidate the destination bank and copy ascending 32-bit pairs through
its existing acknowledged backing read/write FSM and one-word copy register.
No second vector RAM, new frame, memo allocation, eviction or external transfer
is introduced. Destination visibility commits only after every read and write
response succeeds. A failed backing response leaves the destination unreadable
and the source memo unchanged. Successful copy has a real memo-hit event, not
an alias hit. The existing complete-vector-to-memo target 2 still checks its
own complete source bank and retains its existing replacement behavior.

| Frame-input/copy boundary | Required behavior |
| --- | --- |
| Fresh predecessor absent | Request Eval(frame_layer-1,token) as a real scheduler dependency; do not construct a zero input |
| Linear single-token input | Consume the scheduler's actual returned predecessor memo using the same complete-tag copy path |
| Copy request/response stall | Hold source encoding and destination descriptor; complete only after the final acknowledged write and response |
| Source/destination tags | Reject stale generation, wrong layer/token/length/domain/slot or uncommitted bank before access |
| Source lifetime | Keep source occupied and unchanged until all copy reads retire; no memo replacement during the transaction |
| Failed copy | Stop after the failed accepted backing response; never expose a partial destination as an input |
| Reset | Clear controller/copy visibility, not RAM payload; no successful completion survives reset |

This is a required internal data-movement addition, not execution of a complete
layer. The whole-layer numerical worker, native encoders, final liveness ledger
and compatible top/session/arbiter/CSR integration remain unfinished.
`anvil_en1_replay_frame_input` implements that predecessor-binding subtask:
it validates a text Eval frame and either requests the exact preceding Eval
dependency or issues target-3 copy from the supplied matching memo. Done
follows the real copy response and an additional registered error stage;
it is not whole-layer completion. Its 166 declared controller bits occupy
21 byte-rounded bytes, with no private vector RAM. The copy extension adds
no new workspace registers or backing reservation.

## Owner-replay transport and vector-commit boundary

`anvil_en1_owner_replay` is the session-bound owner-projection transport.
It consumes the cache's aligned `regen_*` descriptor without deriving another
consumer-to-owner map. A control handshake captures model, precision,
generation, tokens, text weights base and ordinary/fallback representation.
Control op `control_invalidate=1` releases the current representation.
Control is accepted only while idle, after any old regen response has retired.
A pending control request closes regen ingress. The enclosing session barrier
must also drain the shared external arbiter, cache, frontier and ring before
changing generation; this leaf's control acknowledgement alone is not that
whole-system barrier.

An ordinary local-anchor request first uses the ring's registered read
channel. Only a real tagged ring hit produces a KV pair. A ring miss proceeds
to the numerical owner tile, whose source requests read the current tagged
frontier at the **actual owner input layer**. A missing/stale frontier vector
is an explicit source error; there is no zero-filled answer, shared projection,
external activation read, or assumption that a page commit filled payload.
Other ordinary owners go directly to the owner tile. Frontier requests are
for the even H-component; the captured low/high lane selects the BF16 response
for each tile source request. All source descriptors are checked against the
captured regen descriptor before any frontier access.

In fallback, a miss starts the internal numerical Eval producer with
model/precision/generation, domain 0, owner layer, token and context length.
The producer shares the enclosing session's registered original-input,
modality and weight descriptor; those fields are not recaptured from live
job ports when a cache miss occurs. The producer
must really evaluate `Eval(owner,token)` with its bounded stack/memo FSM.
`eval_output_valid/ready/index/data/last` streams the resulting H-vector in
ascending component order. A successful producer done is necessary **and**
exactly H accepted beats with correct last flags are necessary to commit it.
Until both occur, the receiving bank is unreadable. The committed vector stays
unchanged through the input-norm reduction pass. During the subsequent
ascending output pass, each consumed component may be overwritten by its
actual normalized BF16 result as specified below.
An erroneous stream is drained until producer completion and returns error 7;
a producer error is propagated. No tile command is issued for an incomplete
or failed vector.

The Eval start/output/done channels are internal engine connections, not a
public host API for injecting computed hidden states. The numerical Eval
producer is not implemented by this transport; it must be connected in RTL
before the design is ready. In particular, a future evaluator must service
its decreasing-layer dependencies without recursively waiting on this occupied
root regen channel. It owns its continuation-suspended owner-projection work,
not a second external master. This requirement is unchanged by exposing the
transport boundary.

The transport exposes its shared raw/normalized-source payload, physical
reservation, and completed owner-projection events. One synchronous
Hmax=2560 BF16 bank reserves 5120 bytes (16 bytes compact); live payload is
2H bytes, including incomplete fallback-vector receive lifetime and every
ordinary/fallback tile operation. The owner tile uses EXTERNAL_INPUT_RAM=1,
so no private H-vector is elaborated inside it. Tile scratch is separately
2D live bytes, with 1024 physical bytes (16 compact). Combined physical
source/tile payload is 6144 bytes (32 compact), rather than 11264 (48).
This removes a real declared Hmax array, not just its accounting field.
These and all scalar/child state must be
included in the phase-overlaid text/fallback ledger. The owner tile emits a two-byte event
for each successfully completed K/V projection row, totaling `2D` for a
complete head. A failure before/during projection is not falsely counted as
a whole computed head. This measures actual projected K/V payload, not the
requested four-byte result and not avoided work.
Replay weight/input accepted bytes are scored at the shared
arbiter, including failed responses; this event is not a substitute.

| Owner transport cycle/degenerate boundary | Behavior |
| --- | --- |
| Control B0/B1/B2 | Capture session, validate, expose held acknowledgement; release/invalidate only after old response retirement |
| Regen G0/G1/G2 | Capture descriptor, validate against session/owner geometry, then issue ring/Eval/tile work |
| Ring hit | Capture actual pair/error, publish held cache regen response on following edge |
| Fallback vector | Allocate at Eval start acceptance; write only checked accepted components; commit after complete stream and successful done |
| Source S0/S1/S2 | Capture index/lane; synchronous bank read or registered frontier request/response; publish immutable BF16 response |
| Tile completion | Capture actual pair/error; publish on next edge; release raw vector after regen response acceptance |
| Control concurrent with work | Close new ingress but preserve old command/response payload; control handshake waits for idle |
| Invalid owner/head/component | Reject before Eval, frontier, ring or external weight access; no clamping |
| Error / early done | Drain the real producer's done; no incomplete vector becomes visible |
| Reset | Zero every public output/valid; clear all source/vector visibility, with no asynchronous RAM reset writes |
| Stalls / one outstanding | Hold all descriptors and payloads; response creation is never response acceptance |

### Ordinary frontier task schedule

`anvil_en1_frontier_schedule` captures model, precision, generation, tokens,
and the verification-only forced-fallback selector. It uses the actual padded
frontier capacity (3 MiB production, 8192 bytes for the existing compact
frontier) to select the representation. It is a controller, not a numerical
engine or allocator: every task must be connected to a real internal engine
and only that engine's accepted completion advances the schedule.

The task descriptor is op[2:0], model/precision[1:0], generation/tokens/token
[31:0], layer[7:0] and source_frontier. Task op meanings are:

| Op | Connected execution required before successful task done |
| --- | --- |
| 0 | Configure the ordinary frontier and local ring, after enclosing session drain/invalidation |
| 1 | Construct the real native original input for token and commit its complete H-vector as frontier layer 0 |
| 2 | Materialize every head and distinct K/V component of the last local owner for token into the local ring, from its still-unmodified entering frontier |
| 3 | Run the complete requested text layer and commit its full output as frontier input layer+1; do not overwrite before the complete vector is computed |
| 4 | Freeze the complete frontier entering the final global owner |
| 5 | Run the requested last-token layer; source is frozen frontier for the final global owner and the retained last-token output bank for upper layers |
| 6 | Stream the actual final last-token H-vector through the result consumer; task done follows the final accepted component |
| 7 | Drain/release ordinary storage, bind the bounded fallback workspace, and execute full numerical Eval(L,last token), including real memo/continuations; not a status-bit or host result |

The enclosing top separately configures the cache and replay session and
retains all original inputs. Op 7's numerical engine remains required; this
task schedule does not implement or certify fallback Eval. Shared-layer
tasks have no frontier writes or K/V materialization.

Ordinary fill visits original tokens 0..N-1. Prefix layers 0..owners-2 each
visit tokens N-1..0. Before executing layer owners-2 (the last local owner),
materialize its ring for tokens max(0,N-window)..N-1 in ascending order, while
all those frontier vectors still enter that layer. Then execute that layer
in descending order and freeze the resulting frontier. Execute only token
N-1 at layers owners-1..L-1, keeping the frozen owner input unchanged.
The ring loop uses the actual window (512 production, 4 compact), not padded
padding words as causal tokens; physical padded ring occupancy still belongs
in the allocator ledger.

| Schedule cycle/degenerate boundary | Behavior |
| --- | --- |
| Start D0/D1/D2 | Capture descriptor; validate; register first task; no task valid before D2 |
| Task request | Descriptor holds through backpressure; request acceptance opens exactly one outstanding task |
| Task done | Accept only while waiting for a previously accepted request; register error; dependent next task appears no earlier than next edge |
| N=1 | Fill token 0 once; each prefix visits token 0 once; ring materializes once; all last-token layers retain production maps |
| Window wrap | First ring token is max(0,N-window); no modulo operator or token overflow |
| Frontier capacity | Compare padded BF16 bytes to actual partition; greater-than selects fallback, equality fits |
| Mode change | Representation stays captured for the entire job; release/drain belongs to the actual op 0/7 executor |
| Error | Stop issuing tasks; publish explicit done error after the failed outstanding task retires |
| Completion/reset | Stable done until accepted; no completion on creation edge; active reset zeroes every output and task validity |

### Frontier task execution boundary

`anvil_en1_frontier_execute` binds the schedule to the existing numerical
embedding/PLE, text-layer, anchor-materialization and final-logit engines.
Its idle control channel captures model, precision, generation, tokens,
original token-image base, weight-image base and modality selection. Task
descriptors must match this captured session. Control invalidation and a
new binding first release the old frontier and ring, and clear retained
vector visibility. The enclosing top must already have drained cache/replay
and external memory before accepting this session control. This executor is
not a substitute for that whole-system barrier.

Control modality is a permitted domain, not a forced type for every token:
0 text, 1 image+text, 2 audio+text, 3 image/audio/text. Before each original
input/PLE reconstruction the executor performs a registered original token
read and selects text, image or audio from the pinned placeholder identity.
A placeholder outside the permitted domain errors before encoder work.
The embedding engine still performs its own validated immutable token read.
Both accepted reads count as original-input traffic; duplicate original-input
reads are not avoided KV transfers.

The executor contains the frontier and ring. The canonical cache channels
are selected between the anchor and layer engines for the entire accepted
task, including stalled responses. Owner replay reaches the same frontier
through a separately registered read arbiter and the same ring through its
tagged read port. Owner frontier reads have ingress priority over layer
source reads; an accepted read retains its routing owner until response
acceptance. There is no external KV address interpretation.
Pending executor control closes task ingress, not the owner reads needed
to finish an already accepted numerical task. Otherwise a requested drain
could deadlock that task's outstanding cache miss.

Tasks 1, 3 and 5 reconstruct original-input-derived PLE with the actual
embedding engine. Its complete input and PLE streams are checked before
numerical layer start. For input fill, the H-vector is retained then written
to frontier layer 0. For text-layer tasks the reconstructed original H-vector
is drained, not mistaken for the current layer input. Combined PLE is held
in a P-bank; entering hidden sources use the tagged frontier or the complete
retained last-token vector according to the captured schedule descriptor.
The text engine computes its complete output before emitting components.
The executor checks and retains all H output components before starting any
frontier write. A prefix write commits entering layer `layer+1`; last-token
tasks never overwrite the frozen frontier. Retained-vector tags include
generation, token and entering layer.

Task 0 configures both real ordinary storage leaves. Task 2 runs actual
anchor materialization. Task 4 freezes the frontier. Task 6 starts actual
final RMS normalization, tied vocabulary projection and softcap; completion
follows the last accepted **logit**, not merely the hidden-vector stream.
Task 7 releases both ordinary stores before binding the frontier RAM to
fallback backing and calling the internal numerical Eval producer at
`Eval(L,N-1)`. Eval is an internal RTL producer, not a host-provided answer.
The executor exposes the bound backing channel for the real continuation/
memo workspace. The Eval producer remains required implementation elsewhere;
neither this transport nor binding RAM implements or certifies fallback.

Two synchronous private H/P banks reserve `2*Hmax+2*P` bytes: 5632 production,
24 compact. Live payload includes the full selected H-vector during receive
and through its last use, and P during receive/committed layer use. Raw
original H is not allocated during PLE-only reconstruction. All frontier,
ring and anchor payload/reservation/metadata outputs are exposed separately.
The separate ordinary native-feature bank and its Eval-domain routing are
specified above; its live/physical reports are additive to these H/P banks.
These banks and numerical child state still require integration into the
complete phase-overlaid ledger; the executor does not claim that ledger
or the production resource/timing bounds are already established.

| Executor cycle/degenerate boundary | Behavior |
| --- | --- |
| Control/task E0/E1/E2 | Capture, validate, then start registered real work; tasks cannot use live descriptor ports |
| N=1, first/last | Check exactly H/P components; paired frontier writes have first and last on the only beat when applicable |
| Source arbitration | Capture requester/lane, issue one tagged read, hold routing through response acceptance |
| Full-vector receive | Exact ascending indices and last flag plus successful engine done are required before visibility |
| Prefix overwrite | Begin frontier write only after the full numerical output and successful engine done |
| Upper shared layers | Consume the tagged previous last-token result, never an overwritten owner frontier |
| Memory/cache stalls | Child selection and descriptors remain fixed until the actual completion retires |
| Invalid task | Error 6 for model/precision; 5 for ranges; 7 for session/source-state mismatch, before offending engine access |
| Error | Drain accepted child completion; partial vectors remain unreadable and no dependent task starts |
| Mode/control transition | Release ordinary ring/frontier before fallback binding or new ordinary configuration |
| Reset | Zero all public outputs and clear visibility; no asynchronous payload RAM reset writes |

### Complete local-anchor materialization

`anvil_en1_anchor_materialize` executes one ordinary schedule op 2 for one
token. Its descriptor is model, actual local owner and token. It accepts only
owners 13/22 (the last local owner of that model), and uses the canonical
cache metadata response before every aligned-pair data fetch. It checks the
actual returned owner, non-alias identity and on-chip/rematerialized space;
it never sends `rsp_addr` to DDR or bypasses cache ownership with a local map.
All cache miss data must come from the connected owner's actual projection.

For each K head, then each V head, collect every local aligned pair through
the cache into one synchronous D/2-word lane buffer. Only after the complete
lane is fetched and all cache responses are retired start the ring's lane
write. Stream the buffered pairs in order with correct first/last and await
the ring's acknowledged complete-vector commit. Then reuse the buffer for
the next lane. This sequencing avoids holding the single-port ring writer
open while a cache miss tries to read that same ring. It also prevents a
partially collected lane from becoming a hit. The enclosing session owns
the ring/cache generation and must retain the owner's entering frontier
until all lanes complete.

The buffer reserves 512 bytes production or 8 compact, counted as live during
collection and through ring commit/completion. It is a real transient copy,
not hidden resident capacity. At most one metadata request, fetch or ring
write transaction is outstanding. Errors retire the real failed response and
stop new requests; only already committed complete lanes survive until
enclosing error invalidation. Layer execution must not start after a failed
materialization.

| Materialization boundary | Behavior |
| --- | --- |
| Start A0/A1/A2 | Capture; validate last-local owner/token; no metadata request before A2 |
| Metadata | Register true owner/error/space before starting fetch; no address-based external KV read |
| Fetch | Register actual BF16 pair, synchronously write buffer, then advance index |
| Ring write | Begins only after complete lane collection; first/last single-pair semantics derive from pair count |
| Ring stream | Synchronous read and held pair/flags; next index only after accepted write beat |
| Lane switch | Await successful ring done and release buffer visibility before collecting next lane |
| Done/error/reset | Held explicit result, no partial success; active reset zeroes public outputs and vector visibility without RAM reset writes |

## Source boundary and provenance

The 32 files in `anvil_e3_reference/rtl/` are immutable parent compatibility
references. Model 0 must instantiate the parent top with every named parameter,
port width, and signedness unchanged. Parent fixed-point multimodal execution
is not a substitute for either native model's BF16 computation. The current
`design/GENERATIONAL_HANDOFF.md` lists the inherited modules but
reports all historical STA/PPA/HIL quantities as N/A. It supplies no numerical
parent signoff evidence. No parent timing, resource, throughput, or quality
result is asserted here.

Immutable public semantic sources:

| Source | Revision |
| --- | --- |
| `google/gemma-4-E2B-it/config.json` | `3e22461f65e89153144f8adb70e3b8c2cc9845a7` |
| `google/gemma-4-E4B-it/config.json` | `ee0ef6023621cff504d758262d4e04895a5af4a2` |
| `huggingface/transformers` | `4888db4eea0577a249c82bc2fd11b2e343494134` |

Operation sources at that transformers revision are
`src/transformers/models/gemma4/modeling_gemma4.py`,
`src/transformers/models/gemma4/configuration_gemma4.py`, and
`src/transformers/modeling_rope_utils.py`. Reading these public sources does
not certify production checkpoints. Offline verification must use independently
generated project-owned fixtures, not network access or moving revisions.
Runtime metadata is not a deliverable source or verification prerequisite.

## Production geometry and legal configurations

| Quantity | Model 1, E2B | Model 2, E4B |
| --- | --- | --- |
| Layers L | 35 | 42 |
| Hidden H | 1536 | 2560 |
| Base intermediate I | 6144 | 10240 |
| Query heads Q | 8 | 8 |
| KV heads K | 1 | 2 |
| Shared layers | 15..34 | 24..41 |
| Nonshared owners | 0..14 | 0..23 |
| Global layers | 4,9,14,19,24,29,34 | 5,11,17,23,29,35,41 |
| Shared local/global anchors | 13 / 14 | 22 / 23 |
| Shared intermediate J | 12288 | 10240 |
| Query-to-KV grouping | 8:1 | 4:1 |

All other text layers are local. Owner(l) is l for nonshared layers and the
anchor of the consumer's attention type otherwise. K and V are distinct.
Every layer has its own Q, output, MLP, PLE, residual-norm, and scalar tensors.
Shared layers have no K projection, V projection, or K learned-norm tensor.
Using a consumer's nonexistent K/V tensors is an error, not a cache miss.

Both models use local head dimension 256, global head dimension 512, local
window 512, PLE dimension P=256, vocabulary V=262144, page size 16, RMS epsilon
1e-6, and positions 0..131071 inclusive. Live context N is 1..131072.
Local attention at t sees max(0,t-511)..t; global attention sees 0..t, excluding
masked input positions. Pinned small-model `use_bidirectional_attention` is
null: text tokens, including modality placeholders after replacement, are causal.
Vision encoder attention itself is bidirectional and cannot use in-place
descending-token overwrite.

Precision 0 means BF16 weights and precision 1 means Q4_0 matrix weights.
Both use BF16 activations, norm scales, biases, layer scalars, and KV.
Model 3 and precisions 2/3 reject with error 6 before any offending access.

Verification-only `COMPACT=1` sets H=8, I=16, Q=2, K=1, local/global dimensions
4/8, P=4, V=32, and window 4. Production L, sharing maps, schedules, and E2B
shared doubling remain unchanged. Compact mode is not production performance.
Resident capacity `RESIDENT_ENTRIES` is any integer 1..64, including 3.
Invalid parameters require an explicit diagnostic in a generate branch whose
ports remain well formed, following advisory lesson `exp-6d5cc92e6f5a86894eaae275`.

## Native tensor-image ABI

Every native weights base addresses an independently bounded, versioned tensor
image. No private packing tool, host pointer, or implicit checkpoint path is
part of the ABI. All integers, FP encodings, and bus words are little endian.
All address sums are evaluated with a carry bit; overflow rejects before access.

Each 64-byte header has these byte offsets:

| Offset | Width | Meaning |
| --- | --- | --- |
| 0 | 4 | Magic `0x31564e41` (ASCII ANV1) |
| 4 | 4 | ABI version `0x00010000` |
| 8 | 4 | Native model 1 or 2 |
| 12 | 4 | Weight precision 0 or 1 |
| 16 | 8 | Total image byte length, including header |
| 24 | 4 | Directory entry count |
| 28 | 4 | Entry byte length, exactly 64 |
| 32 | 8 | Directory offset relative to this image |
| 40 | 4 | Flags, zero in ABI 1 |
| 44 | 20 | Reserved, zero |

Directory entries are 64 bytes:

| Offset | Width | Meaning |
| --- | --- | --- |
| 0 | 2 | Tensor kind from the tables below |
| 2 | 2 | Layer instance; `0xffff` for non-layer tensors |
| 4 | 1 | Type: 0 BF16, 1 Q4_0, 2 unsigned32, 3 signed32 |
| 5 | 1 | Rank 0..4 |
| 6 | 2 | Flags, zero |
| 8 | 8 | Payload byte offset relative to this image |
| 16 | 8 | Payload byte length |
| 24 | 16 | Four unsigned32 dimensions, unused dimensions equal 1 |
| 40 | 4 | Byte row stride; exact encoded aligned row size |
| 44 | 20 | Reserved, zero |

Kinds/instances are unique. Directory order is the table order below, with
each layer's rows repeated in ascending layer order before the next layer.
The text, vision, and audio image directories contain their respective tables,
not references into another image. Reject absent, duplicated, unknown, wrong
rank/type/dimension, overlapping, misaligned, or out-of-image payloads.
Header/directory bytes are immutable weight traffic. The directory must not
overlap any payload. Each payload and row begins at a 4-byte boundary.
An exact tied head reuses text kind 0x0000, never an independent lm_head copy.

BF16 rows store two elements per 32-bit word, even element in low 16 bits.
Odd-length rows have a zero high-half pad. Row size is 4*ceil(columns/2).
Scalars/vectors use the same rule, including two pad bytes for a scalar.
Matrix rows are output-major, with ascending input-column reductions.
OIHW convolution rows flatten I,H,W in that order; depthwise rows contain
only one input channel. No arithmetic traverses padding as a tensor element.
Scalars have rank 0 with four dimensions equal to 1; vectors have rank 1
with the vector length in dimension 0. Rank-1 vectors use one encoded row.
Rank-2 matrices have dimension 0 rows and dimension 1 columns. Convolution
matrices retain the displayed OIHW/OIW rank in the directory and flatten
dimensions 1..3 into each output-channel row. The rank-3 BF16 vision position
table instead has 2*10240 rows of 768 columns. These conventions apply to both
precision modes, including partial Q4 convolution rows.

Q4_0 rows consist of ceil(columns/32) blocks. Each block has a 2-byte FP16
scale followed by 16 packed bytes: low nibble j is element j; high nibble j is
element j+16. Weight equals scale*(nibble-8), decoded into binary32.
The final partial block cannot access the next row. Its unused nibbles are
encoded as 8 and ignored. Align the complete row to 4 bytes; do not align each
18-byte block separately. Thus row size is 4*ceil(18*ceil(columns/32)/4).
Embeddings, projections, convolution matrices, and tied logits are matrix
weights; all use the selected precision. Norms, biases, and clipping bounds
remain BF16. There is no INT4 activation or KV representation.

### Text directory and tensor enumeration

Names below have prefix `model.language_model.`. J(l) is I for all E4B layers
and E2B owners, and 2I for E2B shared layers. D(l) is the attention head
dimension. Kind numbers are stable; missing owner-only entries are omitted,
not zero-filled tensors.

| Kind | Pinned suffix | Dimensions | Type |
| --- | --- | --- | --- |
| 0x0000 | `embed_tokens.weight` | V,H | Matrix |
| 0x0001 | `embed_tokens_per_layer.weight` | V,L*P | Matrix |
| 0x0002 | `per_layer_model_projection.weight` | L*P,H | Matrix |
| 0x0003 | `per_layer_projection_norm.weight` | P | BF16 |
| 0x0004 | `norm.weight` | H | BF16 |
| 0x0100 | `layers.l.input_layernorm.weight` | H | BF16 |
| 0x0101 | `layers.l.self_attn.q_proj.weight` | Q*D,H | Matrix |
| 0x0102 | `layers.l.self_attn.q_norm.weight` | D | BF16 |
| 0x0103 | `layers.l.self_attn.k_proj.weight` (owner only) | K*D,H | Matrix |
| 0x0104 | `layers.l.self_attn.k_norm.weight` (owner only) | D | BF16 |
| 0x0105 | `layers.l.self_attn.v_proj.weight` (owner only) | K*D,H | Matrix |
| 0x0106 | `layers.l.self_attn.o_proj.weight` | H,Q*D | Matrix |
| 0x0107 | `layers.l.post_attention_layernorm.weight` | H | BF16 |
| 0x0108 | `layers.l.pre_feedforward_layernorm.weight` | H | BF16 |
| 0x0109 | `layers.l.mlp.gate_proj.weight` | J,H | Matrix |
| 0x010a | `layers.l.mlp.up_proj.weight` | J,H | Matrix |
| 0x010b | `layers.l.mlp.down_proj.weight` | H,J | Matrix |
| 0x010c | `layers.l.post_feedforward_layernorm.weight` | H | BF16 |
| 0x010d | `layers.l.per_layer_input_gate.weight` | P,H | Matrix |
| 0x010e | `layers.l.per_layer_projection.weight` | H,P | Matrix |
| 0x010f | `layers.l.post_per_layer_input_norm.weight` | H | BF16 |
| 0x0110 | `layers.l.layer_scalar` | 1 | BF16 |

`v_norm` has no learned tensor. Q/K learned scales are D-dimensional and
broadcast over heads, not independent per-head tables.

### Vision directory

Use Hv=768, Iv=3072, Qv=Kv=12, Dv=64, Lv=16. Prefix is
`model.vision_tower.` unless a full name is supplied.

| Kind | Pinned suffix | Dimensions | Type |
| --- | --- | --- | --- |
| 0x1000 | `patch_embedder.input_proj.weight` | Hv,3*16*16 | Matrix |
| 0x1001 | `patch_embedder.position_embedding_table` | 2,10240,Hv | BF16 |
| 0x1100 | `encoder.layers.l.input_layernorm.weight` | Hv | BF16 |
| 0x1101 | `encoder.layers.l.self_attn.q_proj.linear.weight` | Qv*Dv,Hv | Clipped matrix |
| 0x1102 | `encoder.layers.l.self_attn.q_norm.weight` | Dv | BF16 |
| 0x1103 | `encoder.layers.l.self_attn.k_proj.linear.weight` | Kv*Dv,Hv | Clipped matrix |
| 0x1104 | `encoder.layers.l.self_attn.k_norm.weight` | Dv | BF16 |
| 0x1105 | `encoder.layers.l.self_attn.v_proj.linear.weight` | Kv*Dv,Hv | Clipped matrix |
| 0x1106 | `encoder.layers.l.self_attn.o_proj.linear.weight` | Hv,Qv*Dv | Clipped matrix |
| 0x1107 | `encoder.layers.l.post_attention_layernorm.weight` | Hv | BF16 |
| 0x1108 | `encoder.layers.l.pre_feedforward_layernorm.weight` | Hv | BF16 |
| 0x1109 | `encoder.layers.l.mlp.gate_proj.linear.weight` | Iv,Hv | Clipped matrix |
| 0x110a | `encoder.layers.l.mlp.up_proj.linear.weight` | Iv,Hv | Clipped matrix |
| 0x110b | `encoder.layers.l.mlp.down_proj.linear.weight` | Hv,Iv | Clipped matrix |
| 0x110c | `encoder.layers.l.post_feedforward_layernorm.weight` | Hv | BF16 |
| 0x1200 | `model.embed_vision.embedding_projection.weight` | H,Hv | Matrix |

Every clipped matrix kind has four following BF16 scalar entries in order
`input_min,input_max,output_min,output_max`, with kind = matrix kind + 0x4000,
0x5000, 0x6000, 0x7000, and the same layer instance. Their pinned names replace
`.linear.weight` with the named buffer. These entries consume RNG positions
in the deterministic fixture enumeration. Directed default clipping bounds
are infinities; finite ordinary fixtures use independently chosen ordered
bounds. There is no std_bias/std_scale tensor: pinned standardize is false.

### Audio directory

Use Ha=1024, Ia=4096, Qa=8, Da=128, La=12, output A=1536.
Prefix is `model.audio_tower.`. Audio input is preprocessed BF16 [frames,128].

| Kind | Pinned suffix | Dimensions | Type |
| --- | --- | --- | --- |
| 0x2000 | `subsample_conv_projection.layer0.conv.weight` | 128,1,3,3 | Matrix, OIHW |
| 0x2001 | `subsample_conv_projection.layer0.norm.weight` | 128 | BF16 |
| 0x2002 | `subsample_conv_projection.layer1.conv.weight` | 32,128,3,3 | Matrix, OIHW |
| 0x2003 | `subsample_conv_projection.layer1.norm.weight` | 32 | BF16 |
| 0x2004 | `subsample_conv_projection.input_proj_linear.weight` | Ha,32*32 | Matrix |
| 0x2100 | `layers.l.feed_forward1.pre_layer_norm.weight` | Ha | BF16 |
| 0x2101 | `layers.l.feed_forward1.ffw_layer_1.linear.weight` | Ia,Ha | Clipped matrix |
| 0x2102 | `layers.l.feed_forward1.ffw_layer_2.linear.weight` | Ha,Ia | Clipped matrix |
| 0x2103 | `layers.l.feed_forward1.post_layer_norm.weight` | Ha | BF16 |
| 0x2104 | `layers.l.norm_pre_attn.weight` | Ha | BF16 |
| 0x2105 | `layers.l.self_attn.q_proj.linear.weight` | Ha,Ha | Clipped matrix |
| 0x2106 | `layers.l.self_attn.k_proj.linear.weight` | Ha,Ha | Clipped matrix |
| 0x2107 | `layers.l.self_attn.v_proj.linear.weight` | Ha,Ha | Clipped matrix |
| 0x2108 | `layers.l.self_attn.relative_k_proj.weight` | Ha,Ha | Matrix |
| 0x2109 | `layers.l.self_attn.per_dim_scale` | Da | BF16 |
| 0x210a | `layers.l.self_attn.post.linear.weight` | Ha,Ha | Clipped matrix |
| 0x210b | `layers.l.norm_post_attn.weight` | Ha | BF16 |
| 0x210c | `layers.l.lconv1d.pre_layer_norm.weight` | Ha | BF16 |
| 0x210d | `layers.l.lconv1d.linear_start.linear.weight` | 2*Ha,Ha | Clipped matrix |
| 0x210e | `layers.l.lconv1d.depthwise_conv1d.weight` | Ha,1,5 | Matrix, OIW |
| 0x210f | `layers.l.lconv1d.conv_norm.weight` | Ha | BF16 |
| 0x2110 | `layers.l.lconv1d.linear_end.linear.weight` | Ha,Ha | Clipped matrix |
| 0x2111 | `layers.l.feed_forward2.pre_layer_norm.weight` | Ha | BF16 |
| 0x2112 | `layers.l.feed_forward2.ffw_layer_1.linear.weight` | Ia,Ha | Clipped matrix |
| 0x2113 | `layers.l.feed_forward2.ffw_layer_2.linear.weight` | Ha,Ia | Clipped matrix |
| 0x2114 | `layers.l.feed_forward2.post_layer_norm.weight` | Ha | BF16 |
| 0x2115 | `layers.l.norm_out.weight` | Ha | BF16 |
| 0x2200 | `output_proj.weight` | A,Ha | Matrix |
| 0x2201 | `output_proj.bias` | A | BF16 |
| 0x2202 | `model.embed_audio.embedding_projection.weight` | H,A | Matrix |

Audio clipping-buffer kinds use the same +0x4000/5000/6000/7000 scheme and
following-entry order as vision. Relative sinusoidal timescales and fixed
softcap 50 are derived constants, not host-computed attention or tensors.

### Original-input ABI and session descriptor

The top preserves all parent fields. Native descriptor capture includes those
fields plus job_model[1:0], job_precision[1:0], job_decode, job_position[31:0],
and kv_base[63:0]. Native weights_base/vision_weights_base/audio_weights_base
address the three images above. scratch_base and kv_base are captured for ABI
compatibility but never authorize native activation or KV spills.

Native tokens_base addresses unsigned32 token IDs; positions_base addresses
unsigned32 positions; mask_base addresses unsigned32 0/1 masks. job_tokens
is the native stream length including modality markers and placeholders.
Parent model 0 retains the original meanings, including its fusion-generated
markers. Native streams supply boi=255999, image=258880, eoi=258882,
boa=256000, audio=258881, and eoa=258883 explicitly. Placeholder counts must
match generated valid soft tokens; placeholders map to PAD 0 for token-identity
PLE, while the context projection uses the actual generated feature.
Compact fixtures may use project-owned in-vocabulary placeholder IDs; production
IDs remain as above.

For native image modes, image_base addresses a 64-byte input header followed by
directory entries with the same shape as the weight ABI. Input magic is
`0x31494e41` (ANI1), precision field is 0, and kinds are 0x3000 BF16
[patches,768] pixels, 0x3001 signed32 [patches,2] patch coordinates.
job_patch_rows*job_patch_cols must equal the supplied patch count, without
overflow. The pinned patch tensor is flattened [channel,y,x], not RGB bytes.
Pixels are transformed by 2*(pixel-0.5) in RTL; coordinates (-1,-1) are padding.
Audio_base similarly supplies kinds 0x3010 BF16 [job_audio_frames,128] and
0x3011 unsigned32 [job_audio_frames] valid mask. No generated features, PLE,
hidden-state archive, or numerical answer may enter these original-input images.

Prefill at position 0 starts a session; decode appends one token exactly at the
expected position. The original prefix inputs and weights remain immutable and
addressable until session invalidation. Descriptors must reject zero tokens,
bad dimensions, positions past 131071, lengths, alignments, or address sums
before offending access. Native modality reconstruction rereads these original
inputs as necessary; replay does not mutate them.

## Numerical rules and materialization table

BF16_RNE denotes round-to-nearest ties-to-even, preserving signed zero and
subnormals, with infinity overflow and canonical quiet NaN 0x7fc0.
Binary32 operations similarly preserve subnormals and use canonical NaN
0x7fc00000. Multiply and add are separately rounded, never fused. Reductions
start at +0 and consume ascending columns/components/tokens; replay uses the
same order and materialization, irrespective of descending output-token order.
No reassociation, compression tolerance, or fallback-specific tolerance exists.

| Operation | Input and internal arithmetic | Materialized output |
| --- | --- | --- |
| Matrix projection | BF16 x, BF16 or decoded binary32 w; binary32 multiply then ascending-column binary32 add | BF16 vector |
| Native clipped linear | clamp each BF16 input to real BF16 input bounds; same matrix projection; clamp the BF16 row to real BF16 output bounds | BF16 vector |
| Vision pixel preprocessing | binary32 pixel-0.5, BF16 round, binary32 multiply 2, BF16 round; flatten channel/y/x | BF16 projection input |
| Vision patch position | real patch matrix projection; binary32 sum of BF16 x/y table values and BF16 round; binary32 patch+position sum and BF16 round | BF16 encoder input |
| RMSNorm | binary32 square, ascending-component sum, binary32 mean + binary32 epsilon; reciprocal square root; binary32 x*inv followed by learned scale if present | BF16 vector |
| LayerNorm (audio subsampling) | ascending-component binary32 mean and centered variance, epsilon, inverse root, learned scale; no bias | BF16 vector |
| Text embedding | matrix row decode, multiply by BF16_RNE(sqrt(H)) | BF16 vector |
| Token-identity PLE | matrix row decode, multiply by BF16_RNE(sqrt(P)), select layer P slice | BF16 P vector |
| Context PLE | matrix projection of original native input; multiply by BF16_RNE(1/sqrt(H)); P-slice RMSNorm with learned scale | BF16 P vector |
| Combined PLE | binary32 add of identity/context then BF16 round; multiply by BF16_RNE(1/sqrt(2)) | BF16 P vector |
| Q and K | projection then per-head RMSNorm, learned D scale shared across heads | BF16 Q/K vectors |
| V | distinct projection then per-head RMSNorm, no learned scale | BF16 V vectors |
| RoPE | derived frequencies, position multiply and sin/cos; BF16 sin/cos; separately rounded x*cos and rotate_half(x)*sin then add | BF16 Q/K vectors |
| Attention score | ascending-component binary32 multiply/add of BF16 Q/K; text scaling 1.0 | binary32 score |
| Text masks | skip illegal keys before maximum/reduction; no future or expired-local key | no payload |
| Softmax | binary32 max-subtracted exponentials and ascending-key sum; sequential reciprocal; normalize then round | BF16 probabilities |
| Attention values | ascending-key binary32 probability*V multiply/add | BF16 vector |
| GELU_tanh | 0.5*x*(1+tanh(sqrt(2/pi)*(x+0.044715*x*x*x))), separate binary32 ops | BF16 vector |
| GeGLU | independently materialized gate/up projections, GELU(gate)*up | BF16 intermediate, streamed |
| Residual | binary32 sum of two BF16 vectors | BF16 vector |
| PLE gate | GELU(materialized H-to-P projection)*combined PLE; P-to-H projection, post norm, residual | BF16 vector |
| Layer scalar | binary32 hidden*BF16 scalar after all residuals | BF16 layer output |
| Final projection | final learned RMSNorm then tied embedding matrix projection | BF16 raw logits |
| Final softcap | binary32 divide by 30, tanh, multiply by 30 | BF16 streamed logits |

Text layer order is input norm, attention, post-attention norm, first residual,
pre-feedforward norm, GeGLU, post-feedforward norm, second residual, gated PLE
projection, post-PLE norm, third residual, layer scalar. PLE depends on the
original reconstructed input, not the current hidden state, except its gate.

Local RoPE uses theta 10000 over the full local dimension. Global uses pinned
`proportional` theta 1000000 and partial factor 0.25. For a head of dimension D,
the half-length frequency vector has f[i]=theta^(-2*i/D) for
i<floor(0.25*D/2), and zero for all remaining i<D/2. Concatenate this vector
with itself. Rotate_half pairs component i with i+D/2: the rotated production
global components are 0..63 and 256..319, not a contiguous first quarter.
Default factor is 1.0 and attention scaling is 1.0. Local frequencies use
the same exponent denominator D, but every i<D/2 is nonzero.

Vision axial frequencies use theta=100 and spatial dimension Dv/2, so
f[i]=100^(-2*i/(Dv/2)) for i<Dv/4. Construct cosine/sine components as
[x-frequencies,x-frequencies,y-frequencies,y-frequencies], then rotate each
spatial Dv/2 partition independently. The ordinary text rotate_half over a
complete Dv head is not the pinned multidimensional vision operation.

Native vision performs patch projection plus the sum of learned x/y position
rows, 16 bidirectional attention/GeGLU residual layers with the same four
learned norms, Q/K learned norms and unscaled V RMSNorm, axial theta-100 RoPE,
clipped linears, 3x3 spatial pooling into 280 valid soft tokens, binary32
sqrt(768) scaling, BF16 materialization, unscaled modality RMSNorm, and H
projection. Configuration normalization maps legacy vision rope_type default
to axial. Padding embeddings contribute zero to pooling; no encoder input may
be overwritten before all consumers finish.

Native audio performs two stride-2 3x3 padded subsampling convolutions,
channel LayerNorm and ReLU, time/frequency/channel flattening, Ha projection,
12 conformer layers, A projection with bias, unscaled modality RMSNorm, and H
projection. Each conformer layer orders feedforward1 (SiLU and 0.5 residual
weight), normalized chunked attention and residual, normalized causal light
convolution with GLU and SiLU and residual, feedforward2 (0.5 weighting), final
norm. Clip buffers and the fixed 1e10 stability clamps are applied at pinned
boundaries. Chunk size is 12, left 13/right 0; the pinned masking function uses
strict distance <12, and excludes future positions. Relative-position content
and shifted relative-key scores are both computed in hardware. Query scaling
uses Da^-0.5/log(2)*softplus(per_dim_scale); K scaling is
log(1+e)/log(2). Audio score softcap is 50*tanh(score/50). No host encoder,
attention, PLE, or MLP substitution is legal.

Approximation requirements: tanh absolute error <=2^-10 on [-8,8] with
saturation outside; GELU error <=2^-7*max(1,abs(x)) for abs(x)<=16; softmax
component error <=2^-8 and sum error <=2^-7. Finite final logits must remain
in [-30,30] and have error <=0.25+0.02*abs(binary64 reference). Format
conversion, Q4 decoding, addressing, and primitive binary32 operations require
exact independent comparisons, including exceptional arithmetic.

### Registered arithmetic stage and valid table

This table specifies the intended shared primitive engine before its RTL.
One primitive is outstanding. Every input is registered on acceptance A0.
Arithmetic result valid is held until acceptance, not pulsed or combinational.

| Primitive | Registered stages after A0 | Result |
| --- | --- | --- |
| BF16 widen/narrow | A1 classify and exact widen or RNE narrow; A2 publish | after A2 |
| FP16 widen | A1 classify; normalize subnormal one bit/cycle; exact pack; publish | completion-valid after normalization/pack |
| FP add | A1 classify/unpack; A2 align with sticky; A3 signed sum; bounded iterative normalization; registered RNE/pack | completion-valid after normalization/pack |
| FP multiply | A1 classify/unpack; normalize subnormal operands one bit/cycle; four registered 12x12 products; two registered reduction stages; exponent alignment; registered RNE/pack | completion-valid after normalization/pack |
| Unsigned divide | D1 register operands; D2..D33 one restoring quotient bit per cycle; D34 RNE/pack | after D34 |
| Square root | S1 register radicand; bounded one digit per cycle; final normalization and RNE stage | completion-valid after final stage |
| Binary32 divide | classify, bounded operand normalization, normalized numerator setup, 26 restoring fractional bits, subnormal alignment, RNE/pack, publish | completion-valid after publish |
| Binary32 reciprocal root | classify and normalize; exact-power special case or 78 restoring bits for a rational radicand then 27 root digits; one final RNE/pack, publish | completion-valid after publish |
| Unsigned32 to binary32 | capture, at most 31 one-bit normalization shifts, RNE/pack, publish | completion-valid after publish |
| Transcendentals | register range reduction; bounded iterative polynomial/CORDIC primitive calls; register materialization | completion-valid, no fixed-latency fiction |
| Projection | one decoded weight/input at a time; registered multiply then registered add; ascending-column counter | vector write only after full row |
| Norm/attention | scalar continuation with bounded registered reduction loops and iterative divider/root/exp | completion-valid |

FP exponent/normalization paths must themselves use bounded-depth registered
or iterative shift/count logic. Variable shifts, reductions, and tree depth
need actual shared-runtime timing scrutiny; this table does not certify WNS.
No real-valued RTL, black-box numerical answer, combinational runtime `/` or
`%`, mixed sequential blocking/nonblocking assignment, or recursive
elaboration is permitted.

The internal `anvil_en1_fp32` primitive accepts start_valid/start_ready,
operation[2:0], operand_a[31:0], operand_b[31:0], and returns
done_valid/done_ready, done_data[31:0], done_error[3:0]. Operations 0/1 are
binary32 add/multiply, 2 widens operand_a[15:0] BF16, 3 narrows binary32 to
zero-extended BF16, and 4 widens operand_a[15:0] FP16. Operations 5..7 reject
with error 6. Conversion special cases also canonicalize NaN. FP16 subnormal
conversion uses bounded one-bit normalization, not a floating-point host call.
This primitive has no memory commands, vectors, or replay frames.

### Implemented scalar arithmetic and streamed leaf interfaces

`anvil_en1_fp32_divsqrt` accepts the same scalar start/done handshake as the
format/add/multiply primitive, with operation[1:0] selecting 0 binary32 a/b,
1 sqrt(a), or 2 reciprocal sqrt(a). Operation 3 rejects with error 6.
All three produce a single RNE binary32 result, including subnormal division
outputs. Reciprocal root must not be implemented by first rounding sqrt(a)
and then rounding its reciprocal: that changes the admitted normalization
boundary. Its implementation forms the rational radicand by iterative
division, computes an integer root, retains both remainders as sticky
information, and rounds only once. NaN is canonical. Sqrt(-0) is -0;
reciprocal sqrt(-0) is -infinity; negative nonzero root arguments are NaN.
Division zero/infinity special cases follow binary32 semantics and do not
invent a protocol error for a valid exceptional floating-point operation.

`anvil_en1_uint_to_fp32` accepts an unsigned32 operand and returns its RNE
binary32 encoding, including exact +0 for input zero. Its normalization
and rounding are bounded FSM stages, not a host conversion or real-valued RTL.
Norm vector lengths through 16384 convert exactly.

`anvil_en1_exp` accepts a binary32 operand and returns a binary32 exponential
approximation. It reduces signed x into (-ln(2),ln(2)) using registered
binary32 add calls and a signed bounded scale counter. ln(2) is 0x3f317218.
It evaluates degree-8 exp Taylor coefficients by descending Horner degree
with separately rounded multiply/add, then applies two representable power
of two scales using the multiply primitive. Coefficients from degree 8 to 0
are 0x37d00d01, 0x39500d01, 0x3ab60b61, 0x3c088889, 0x3d2aaaab,
0x3e2aaaab, 0x3f000000, 0x3f800000, 0x3f800000.
NaN canonicalizes; +infinity returns +infinity and -infinity returns +0.
Finite x>=89 returns +infinity and x<=-104 returns +0, outside the
nonzero finite binary32 exponential range. Intermediate reduction and
Horner values are binary32, not BF16. This is a proposed implementation
to be independently tested against the unchanged softmax/tanh thresholds;
the coefficients themselves are not evidence that those thresholds pass.

`anvil_en1_activation` selects operation 0 tanh, 1 GELU_tanh, 2 SiLU, or
3 sigmoid. For tanh it evaluates exp(-2*abs(x)), then
(1-exp)/(1+exp), restoring the input sign. At abs(x)>=8 it returns the
signed unit value, preserving the admitted saturation rule. At signed zero
it preserves that sign. GELU uses 0x3d372713 for 0.044715 and 0x3f4c422a
for sqrt(2/pi); compute x*x, that result*x, the cubic coefficient product,
its sum with x, and the argument coefficient product, in that order.
After tanh, compute 1+tanh, 0.5*x, and their product; only the caller
materializes the BF16 result. Sigmoid uses exp(-abs(x)) to avoid overflow:
negative x returns exp/(1+exp), nonnegative x returns 1/(1+exp).
SiLU then multiplies x by that binary32 result. Arithmetic NaNs canonicalize;
GELU/SiLU at negative infinity follow their invalid infinity-times-zero
boundary and return canonical NaN. Each scalar result is registered and
held through backpressure. These leaves do not claim a final logit softcap
until the native layer/logit controller connects them.

`anvil_en1_norm` is a streamed RMSNorm/LayerNorm leaf. Its descriptor is
layer_norm, learned_scale, vector_length[31:0], epsilon[31:0].
Length 1..16384 and finite nonnegative epsilon are legal; native RMS callers
must use the prescribed binary32 epsilon 1e-6. It issues
source_valid/source_ready with source_index[31:0] and accepts one BF16
source_rsp_data[15:0] plus source_rsp_error through
source_rsp_valid/source_rsp_ready. With learned_scale set, the corresponding
scale request/response channel uses the same index and BF16 widths.
The caller must supply immutable on-chip vector values throughout all passes.

RMSNorm reduces squared components in ascending order, divides by the exact
binary32 length, adds epsilon, and obtains a once-rounded reciprocal root.
LayerNorm first reduces the mean, then rereads and reduces squared centered
components in ascending order before the same variance/root path. The
output pass rereads components, centers only for LayerNorm, multiplies by
the inverse root, multiplies by the learned scale only when requested, and
narrows once to BF16. Unscaled V normalization makes no scale requests.
The normalized_valid/normalized_ready stream carries normalized_index[31:0],
normalized_data[15:0], and normalized_last. A length-1 vector emits one
first-and-last value; done follows its acceptance, not its creation.
The leaf allocates only scalar registers; it neither retains a hidden vector
nor emits external activation commands. The future allocator must include
these scalar and child-engine registers in the complete workspace ledger.

`anvil_en1_weight_read` and `anvil_en1_projection` have the standard
cmd/result channels. Their registered tensor descriptor is precision[1:0],
tensor_base[63:0], tensor_bytes[63:0], tensor_rows[31:0],
tensor_columns[31:0], row_stride[31:0], and row_index[31:0].
The reader also captures column_index[31:0] and returns one binary32 weight.
The projection traverses all columns of one row and returns a zero-extended
BF16 row result. Both require positive rows/columns <=1048576 and indices
within bounds. Actual production tensor shapes are further enforced by
the tensor-image validator; these wide leaf bounds are not extra model
geometry or permission to access an invented tensor.

The reader checks exact BF16/Q4 encoded row stride, total tensor length,
alignment, and address overflow before a memory request. BF16 elements widen
through the exact format primitive. A Q4 block starts at 18*(column>>5)
within its row; its FP16 scale starts at byte 0 and the selected packed
byte at 2+column[3:0]. Column bit 4 chooses low/high nibble, mapping the
decoded signed integer to -8..7 before a binary32 scale multiply.
Aligned 32-bit reads never cross an encoded row; partial blocks cannot
consume the next row. The current folded reader rereads scales and may
read the same aligned weight word more than once. Every such accepted
transaction is weight traffic, not avoided traffic or external KV traffic.

The projection requests on-chip BF16 vector components through the same
source request/response signals as norm. It begins each reduction at +0,
widens each component, separately rounds its weight multiply and accumulated
add, advances in ascending column order, and narrows only after the final
column. A source error returns cache-state error 7; an accepted external
read error is retired and returns error 2 without a new command.
Malformed tensor lengths/addresses return error 5; invalid precision returns
error 6. Scalar errors propagate through done_error; no error produces a
valid success-shaped numerical answer.

`anvil_en1_tensor_shape` is the model/precision-aware directory schema.
It accepts image_class 0 text, 1 vision, 2 audio, or 3 original input,
kind[15:0], layer[15:0], and model/precision[1:0]. For original inputs
input_audio chooses image/audio and input_items is the required patch/frame
count. It returns validity, expected type/rank/dimensions, flattened rows
and columns, and exact entry count. Text counts are 540/665 for E2B/E4B,
vision 659, audio 752, and each original-input image 2. These include all
four scalar clipping entries following every clipped matrix. Shared-layer
K/V and K-norm entries are explicitly invalid, not optional zero tensors.
COMPACT changes only the admitted text geometry; vision/audio encoder
geometry remains the pinned native geometry.

`anvil_en1_tensor_image` captures the same schema selector plus image_base
and requested tensor_kind/tensor_layer, and uses only the standard read-only
cmd/result channels. It validates the 64-byte header before directory reads,
then validates every directory entry's prescribed shape, type, dimensions,
reserved bits, exact stride/length, payload alignment, image containment,
and exclusion of header/directory intervals. It rereads the first six words
of each earlier entry for pairwise uniqueness and payload-overlap checks;
no sorted-offset assumption or unbounded metadata archive is used.
Exact entry counts, valid schema membership, and uniqueness jointly require
the complete tensor set. A lookup completes successfully only after the
entire image validates and the requested entry is found. Returned
done_base/done_bytes[63:0], done_rows/done_columns/done_stride[31:0],
and done_type[7:0] are then an admitted payload descriptor; invalid images
return error 5 and zero those descriptor fields. Accepted memory errors
return error 2, while invalid selected model/precision returns error 6.

The header, current entry, and six prior-entry words use 1216 register bits;
the remaining control/address/shape/extent registers are bounded independently
of directory length. This conservative implementation revalidates an entire
immutable image on each lookup and has quadratic directory-read work.
Its actual extra weight/original-input traffic must be counted. It does not
assert usable throughput, latency, physical fit, or unmeasured SRAM savings.
Only a future connected arbiter may drive external memory.

For all implemented leaves, input acceptance captures descriptors; no changing
start pin influences in-flight work. Returned source/memory responses are
registered before dependent arithmetic or accesses. Active reset zeros every
public output and clears valid state. There are no vector/payload RAMs in
these new leaves, no host numerical answer ports, and no hidden-state writes.
These interfaces expose substantive arithmetic but do not replace the
required connected top/replay/modalities or independent cases A--E.

### Rotary and bounded attention leaf contract

The following implementation stages are frozen before this source increment.
They do not assert that the independent numerical thresholds have passed.

`anvil_en1_rope_frequency` selects theta with mode 0=10000 (local),
1=1000000 (global proportional), or 2=100 (one vision spatial partition).
Its dimension is the full text head dimension or the vision spatial partition
dimension, respectively. Legal leaf dimensions are 4,8,16,32,64,128,256,512;
the caller enforces the production/compact model geometry. Pair i must be
less than D/2. Global pairs i>=D/8 have frequency exactly +0.
For remaining pairs, form theta^(i/(D/2)) using binary32 square roots and
products: start product=1, root=sqrt(theta), and bit=(D/2)>>1; for each
descending bit multiply product by root only if i has that bit, then square
root root before the next bit. Return binary32 1/product. All roots,
products, and the reciprocal round independently. Pair zero returns 1.
This specifies the finite hardware frequency evaluation order; independent
verification must compare the resulting rotary components against the pinned
operation and numerical contract, not assume repeated-root evaluation is a
bit-exact substitute for a particular host math library's power implementation.

`anvil_en1_sincos` takes a binary32 angle and returns two binary32 scalars.
Finite magnitude must be <=262144, which covers native position-derived
angles. Larger finite arguments reject with error 5; exceptional arguments
return canonical NaN for both results. Signed zero is preserved in sine.
For magnitude <=2^-12, sine is the input and cosine is 1. Otherwise convert
the binary32 magnitude to unsigned fixed Q44, reduce modulo a Q44 2*pi
constant with 18 descending shift/subtract steps, then choose the nearest
pi/2 quadrant to leave magnitude <=pi/4. Q44 pi is 0x00003243f6a8885a,
2*pi is 0x00006487ed5110b4. Fixed-to-binary32 conversion uses iterative
normalization and RNE, not an integer-to-real host function.
Evaluate sine through degree 11 and cosine through degree 12 using Horner
polynomials in r*r. Coefficient +/-1/k! is obtained by unsigned32 factorial
conversion followed by the binary32 divider; every polynomial multiply/add
rounds separately. Restore quadrant and argument signs only after both
polynomials complete. This bounded approximation requires independent checks.

`anvil_en1_rotary_pair` captures mode, dimension, pair index, unsigned position,
and a 32-bit pair containing BF16 a in the low lane and BF16 b in the high
lane. Position is <=131071. It connects the frequency and sine/cosine engines,
multiplies the binary32 frequency by the exactly converted position, narrows
sine/cosine to BF16, and returns
BF16_RNE(a*cos-b*sin) and BF16_RNE(b*cos+a*sin). Each product and sum uses
separately rounded binary32 arithmetic. Text pairs are i and i+D/2.
Vision pairs use this leaf independently in the x and y spatial partitions;
the caller supplies the corresponding coordinate, not the full-head pairing.

`anvil_en1_geglu_pair` captures BF16 gate/up and operation 0=GELU_tanh,
1=SiLU, or 2=GLU sigmoid; operation 3 rejects with error 6. It materializes
the activation to BF16 before multiplying by the independently materialized
up value and narrowing the product. Thus text GeGLU and the PLE gate share
the same GELU materialization, while native audio can reuse the same folded
scalar channel without bypassing its prescribed operation.
`anvil_en1_softcap` captures a BF16 raw value and cap selector 0=30 or 1=50;
it divides the widened value by the binary32 cap, evaluates tanh, multiplies
by the cap, and narrows once when output_binary32 is clear. Selector 0
implements final text softcapping with BF16 input/output. Audio attention
scores use both input_binary32 and output_binary32 so they are not
prematurely narrowed.

`anvil_en1_attention_head` is a scalar-workspace text attention engine.
Its descriptor is native model, logical layer, query head, and query position.
It derives only head dimensions, grouping and window schedule from geometry;
it never derives an owner alias. Every K/V read first obtains the canonical
metadata response for the logical layer, consumes its owner and native space,
then issues the real fetch channel with that owner. A caller supplies immutable
on-chip BF16 Q components and 0/1 key masks through separate registered
request/response channels. No projected K/V or host-produced score enters
the engine except through the real cache fetch interface.

The head scans permitted keys in ascending order for maximum, rereads them
for the max-subtracted exponential sum, obtains binary32 1/sum, then scans
the keys again separately for each output component. Each last scan recomputes
the score, exponential, normalized BF16 probability, and real V fetch.
There is no private score/probability archive. Dot products traverse ascending
components and value reductions traverse ascending keys. Masked keys issue
no K/V requests. An empty permitted-key set produces zero attention output,
without a divide-by-zero or fabricated cache answer. Nonempty exceptional
scores propagate canonical NaN through the normal arithmetic.
Output BF16 components stream in ascending order; done follows acceptance
of the last component. This deliberately folded design adds owner-replay
and Q/mask rereads, which are real work, not avoided projection traffic.

| New scalar/attention stage | Registered dependency order |
| --- | --- |
| Frequency | capture/validate; bounded descending-bit root/product calls; reciprocal; publish |
| Sine/cosine | capture/classify; Q44 conversion; 18 modulo steps; quadrant/normalize/RNE; bounded coefficient/divider/Horner calls; sign restoration; publish |
| Rotary pair | capture/validate; frequency; position conversion; angle multiply; sine/cosine; two BF16 trigonometric conversions; four separate products/two adds; BF16 outputs; publish |
| GeGLU/softcap | capture/validate; activation or divide/tanh; required materializations; multiply; final narrow; publish |
| Attention | capture/validate; mask request/register; component Q request/register; metadata/fetch/register; dot multiply/add; max or exponential/sum; reciprocal; probability narrow; V fetch/register; value multiply/add; output narrow/accept |

Every child result is consumed on an already-visible valid handshake and
registered before the next dependent operation. All starts/results and
source/cache requests remain stable under backpressure. There is one
outstanding request per leaf; reset clears all validity and zeroes public
outputs. Scalar state and all instantiated child arithmetic registers must
be included in the future complete replay workspace allocation; lack of
vector RAM in a leaf is not permission to omit its scalar footprint.

`anvil_en1_gated_projection` evaluates one output row of a streamed gated
projection. It captures precision, activation (the GeGLU-pair operation),
up_mode (0=second matrix projection, 1=on-chip up vector, 2=unit up),
and complete gate/up/down tensor descriptors, plus down_row.
Gate columns H must be 1..2560, gate rows J must be 1..12288;
down columns equal J and down rows are 1..2560. Matrix up has the same
H/J dimensions as gate. On-chip-vector up has one BF16 value per J index.
Unused up tensor descriptor fields do not authorize reads in modes 1/2.
Invalid up_mode/activation rejects with error 6 and bad geometry with error 5.
Native tensor-image lookup still enforces each model's exact tensor shapes.

For each j in ascending order, run the full gate row projection, run the
up row projection or read the immutable on-chip up component or use BF16 1,
run the connected GeGLU-pair leaf with required BF16 materializations, read
down[row,j] through the bounded BF16/Q4 reader, then separately multiply
and add into a binary32 accumulator. Narrow only after the final j.
Mode 0 is text/vision GeGLU; mode 1 is gated PLE using the independently
constructed combined PLE vector; mode 2 with SiLU is audio feedforward.
The surrounding layer controller owns norms, residuals and scalar order.

The gate and up projections reuse one projection instance; down weights use
one reader. A registered local transaction owner selects their read-only
cmd/result channels and changes only after a child done handshake, when its
memory response has retired. The shared external arbiter remains the sole
external master. The source H-vector stays immutable for the entire row.
No J-wide intermediate is allocated; each output row recomputes every gated
intermediate. This increases actual weight/replay work and cannot be counted
as avoided computation. Stage order is descriptor capture/validation,
gate projection, selected up source, activation/materialization, down read,
binary32 multiply/add, bounded j advance, BF16 narrow, registered completion.

### Owner projection/rematerialization tile boundary

`anvil_en1_owner_kv_tile` is a read-only numerical leaf below owner_replay,
not a replacement for Eval, the resident cache, or a native layer controller.
Its captured descriptor is model[1:0], precision[1:0], owner[7:0],
token[31:0], is_value, kv_head[1:0], component[9:0], and weights_base[63:0].
Component must be even and less than the owner's head dimension; the result
is the aligned adjacent BF16 components (component,component+1), low lane
first. Only actual owners 0..14/0..23 are legal. Passing a shared consumer
instead of the cache's owner response rejects with error 7 before memory
access. This leaf does not implement another logical-to-anchor alias map.

Source requests carry the captured model, owner and token and an H-component
index. The caller supplies the BF16 hidden vector **entering** that owner
layer, immutable for the whole operation in the default private-RAM mode.
An ordinary caller reads the
correct tagged frontier; fallback must really evaluate that vector. A
precomputed normalized vector or KV answer is not a native source substitute.
The leaf validates the text image and looks up the owner's input-layernorm
kind 0x0100, then RMS-normalizes the entering vector with its learned H scale
and epsilon 0x358637bd (binary32 1e-6). It materializes the normalized H
vector in synchronous on-chip scratch.

Look up the distinct owner K or V matrix (0x0103/0x0105). Project all D rows
for the selected KV head, row kv_head*D+i, in ascending i; each row is a
complete ascending-H-column binary32 reduction with BF16 output. Normalize
that complete head with epsilon 1e-6. K looks up and applies the shared
D-dimensional learned scale 0x0104; V never looks up that tensor and never
issues a head-scale request. Both paths perform the input learned norm.
The normalized head overwrites its projection scratch only in the norm
output pass, after the full reduction has finished. Norm reads a component
and retires it before accepting the write to that component.

For K, obtain each requested component by rotating the true half-head pair
(i,i+D/2), where i=component modulo D/2, through the connected rotary leaf.
Perform this independently for the two adjacent result components; select
the correct lower/upper result lane. Thus cache aligned pairs are not confused
with RoPE half-head pairs. Local owners use mode 0 and global owners mode 1.
V returns the two normalized adjacent components directly, without rotary.
All projection/scale/directory reads go through the standard cmd/result
channel and the future sole external arbiter; the leaf emits no writes.
Lookup, projection and scale-reader ownership changes only after completion
and memory-response retirement. Accepted failures count as weight traffic.

Production scratch reservations are one 2560-component BF16 input bank and
one 512-component BF16 head bank (6144 bytes total); compact reservations are
H=8 and D=8 (32 bytes total). Actual live vector payload is 2H+2D bytes after
the head is filled, plus scalar/child arithmetic and returned words. These
are part of, not additions to, the complete text/replay workspace ledger.
Unused physical bank capacity is disclosed separately. No full K*D tensor,
extra normalized-head copy, score array, or external activation archive is
allocated. These scratch reservations must ultimately be phase-overlaid
with the controller workspace; simply instantiating private banks beside
other complete workspace banks is not proof of the admitted full ledger.

`EXTERNAL_INPUT_RAM` accepts 0/1 and defaults to 0; existing nested
replay/query leaves keep their private normalized-input storage unchanged.
Only the owner transport selects 1. In that mode the tile elaborates no
input array and exports `input_store_valid/index[31:0]/data[15:0]` for each
accepted input-normalization output. Its connected synchronous RAM always
accepts these writes. `source_normalized` distinguishes later projection
reads of those computed values from the original entering-vector norm
reads. These are storage interfaces, not externally supplied numerical
answers or external memory commands.

| Shared owner source phase | RAM owner and boundary |
| --- | --- |
| Fallback Eval receive | Original entering vector fills the source bank; exact H-beat completion is required |
| Input RMS reduction | Read original raw bank in fallback or tagged frontier in ordinary mode; no normalized writes yet |
| Input RMS output | Ascending component read retires before that component's normalized write; future components remain original |
| Normalization stores | Require exact ascending indices, no duplicates or writes past H; reserve shared source before first write |
| Projection reads | Require successful complete normalized-vector visibility; read the same source bank, never write the ordinary frontier |
| Head norm/RoPE | Retain normalized source reservation and separate D-bank until the real tile response retires |
| Error/reset | Never expose partial normalization as a valid projection source; propagate errors, and invalidate visibility |

The transport checks every normalized store index and completion and
returns error 7 for a malformed/incomplete store stream even if the tile
otherwise reports success. Original versus normalized source identity is
registered with each callback through stalls. Input RMS reduction and
output retain the existing binary32 reduction and BF16 materialization
order. There is one shared synchronous write port (Eval fill or norm
output) and one registered read port, with no simultaneous representation
copy and no dependence on same-address RAM read-during-write behavior.

| Owner tile cycle/degenerate boundary | Required behavior |
| --- | --- |
| Start T0 / T1 / T2 | Pre-edge acceptance captures descriptor; T1 validates geometry; no memory command before T2 |
| Source/scale request S0 | Descriptor/index stable until pre-edge handshake; one response outstanding |
| Internal scratch read S0/S1/S2 | Capture index, synchronous RAM read, register payload; valid after S2 and hold through acceptance |
| External read M0/M1/M2 | Child records command acceptance, registers response, then starts dependent arithmetic; no fabricated same-edge response |
| Norm output | Write only accepted output; finish reduction before any in-place head write; final beat acceptance precedes done |
| Completion | Publish registered adjacent pair/error; hold through backpressure; next start only on the edge following response retirement |
| Compact/global head | D=4/8, full production owner schedules; last even component pairs remain in bounds |
| Owner/head/component rejection | Shared owner, head past K-1, odd or out-of-head component rejects before tensor access; no clamping |
| Reset/cancellation | Active reset zeroes public outputs/valids and prevents RAM writes; caller drains external work before generation reuse |
| Concurrent RAM read/write | Serialized source read and corresponding output write; other-bank projection writes cannot collide |

The caller must not use reset as a substitute for retiring an already accepted
external transaction. Session invalidation/cancellation is owned by the
generation-aware replay/arbiter barrier, still required above this leaf.
This connected tile does not certify the repeated-root RoPE approximation,
normalization arithmetic, production-width thresholds, or full inference.

### Original embedding and combined PLE reconstruction leaf

`anvil_en1_embedding_ple` captures native model/precision, a requested layer,
absolute token index, tokens_base, weights_base, and modality selector
0=text, 1=image feature, 2=audio feature. Selector 3 rejects. It reads the
actual unsigned32 token ID from tokens_base+4*index using a carry-checked
aligned address, checks vocabulary bounds, and validates the selector
against the original placeholder ID. Compact fixtures reserve image=28,
audio=29, boi=24, boa=25, eoi=26, eoa=27; production IDs remain unchanged.
An image/audio placeholder with selector 0 is a cache-state error, not a
text embedding shortcut. Other text tokens, including explicit modality
markers, use their own identities. Placeholder identity PLE uses token 0.

Text input reconstruction validates/looks up kind 0x0000, decodes the
actual token embedding row, multiplies by BF16_RNE(sqrt(H)), and materializes
each H component. Modality reconstruction instead requests each BF16 native
projected feature component through modality_valid/modality_ready with
model, kind, token and index. This is an internal generated-feature interface:
its producer must execute the pinned native encoder and modality projection
on-chip. It is not a public host-supplied hidden-state archive, does not
complete an encoder, and cannot count as multimodal execution by itself.

The leaf constructs context PLE by projecting the immutable reconstructed
H-vector with kind 0x0002, rows layer*P+i, then separately multiplying the
materialized projection by BF16_RNE(1/sqrt(H)) and materializing again.
It normalizes that P-slice with kind 0x0003 and epsilon 1e-6. It decodes
identity kind 0x0001 at the selected token row and columns layer*P+i,
multiplies by BF16_RNE(sqrt(P)), materializes, adds to normalized context,
materializes, multiplies by BF16_RNE(1/sqrt(2))=0x3f35, and materializes
the combined P-vector. This vector is intended for the existing real
gated-projection leaf's up_mode=1; it is not an additive layer residual.

sqrt(H) and reciprocal sqrt(H) are independently computed from the exact
binary32 H through the root engine and narrowed once to BF16. sqrt(P)
is exactly 16 in production or 2 in compact mode. Projection reductions
and all multiply/add calls preserve the existing ascending-column and
separate-rounding rules. The complete native H and combined P vectors stream
in ascending order on separate input/ple output channels. H is emitted
first, then P; completion follows acceptance of the last P component.
Neither stream is a host-produced numerical answer.

| Embedding/PLE cycle and boundary | Behavior |
| --- | --- |
| E0/E1/E2 | Capture descriptor, validate model/layer/precision/index, form address; no original-input command before E2 |
| Token request/response | Stable aligned read, one accepted response, register before ID checks or payload lookup |
| Feature request | Hold kind/token/component until accepted; register response/error before scratch write |
| Scalar stages | Register root result, BF16 conversion, weight multiply and each subsequent narrow/add/multiply |
| Scratch source F0/F1/F2 | Capture source index, synchronous read, register payload; response valid after F2 |
| In-place P norm/combination | All norm reductions precede output writes; identity combination replaces only its fully consumed P component |
| Output stall | Valid/index/data/last remain stable; last creation is not completion |
| Single output/degenerated index | First/last flags derive from the actual length; layer 0 and last layer retain complete P slices |
| Invalid selector/ID/overflow | Error before offending payload read; no ID clamping or success-shaped substitute |
| Reset/session reuse | Zero public outputs/valids, gate RAM writes; enclosing arbiter drains accepted work before invalidating session |

One H-component and one P-component BF16 scratch bank reserve 5632 bytes
in production (Hmax=2560,P=256), or 24 bytes compact (H=8,P=4). Live vectors
are 2H+2P bytes plus scalar/control/child temporaries. Only the actual
layer's P slice is stored, not L*P, and no external activation commands
exist. Input and combined-P scratch remain live through their accepted
streams; any frontier or frame copy concurrently receiving those streams
must also appear in the complete liveness ledger. Final controller integration
must overlay this workspace with owner/text arithmetic phases as admitted.

This leaf has no session manager, native encoder, layer residual controller,
replay stack or memo. Its feature interface does not waive those missing
connected engines. Production and compact numerical comparisons remain
independent Verifier work, not assertions established by this design table.

### Complete text-layer controller boundary

`anvil_en1_asym_attn_ple` captures model, precision, layer, absolute token
position and text weights base. It evaluates one full text layer, not final
logits or a session. Its `source_valid/source_ready` channel requests the
captured entering H-vector or the original-input-derived combined P-vector:
`source_is_ple=0/1`, with an ascending component index and captured
model/layer/token. The caller must supply immutable on-chip vectors, not
normalized values or software-generated layer answers. Responses have BF16
data and an explicit error. H then P are copied before numerical work begins.

The controller connects one projection, one norm, one rotary-pair, one
attention-head, one gated-projection, one weight reader, the tensor-image
validator and binary32 residual/scalar arithmetic. The attention leaf's mask,
canonical cache metadata and cache fetch channels are exposed unchanged.
No logical owner map or external KV address is recreated in this controller.
The enclosing scheduler must service a miss using the cache's actual owner.

Input RMSNorm produces the work vector. For each query head, project D rows
of kind 0x0101, normalize with the shared D-scale 0x0102, rotate all half-head
pairs, then run the actual attention leaf and store its accepted D outputs
in head-major concatenation order. Query-head outputs do not complete the
layer. Kind 0x0106 projects that concatenation to an H-branch vector.
Post-attention norm precedes a separately rounded residual add. Pre-FF norm
produces the immutable MLP source; kinds 0x0109/0x010a/0x010b perform real
GeGLU/down projection. The validator supplies the actual J width, including
E2B shared doubling. Post-FF norm precedes the second residual add.
Kinds 0x010d/0x010e use the current residual as gate source and the retained
combined P-vector as `up_mode=1`; post-PLE norm and the third residual follow.
Finally kind 0x0110 multiplies every residual component before BF16 output.

Three synchronous H-banks retain residual, normalized work and the shared
query/branch representation. A Q*D bank retains the attention concatenation;
a P-bank retains combined PLE. No separate D-bank, J-vector or probability/score array is
allocated. Norm may overwrite its branch/Q bank only after its complete
reduction and consumption of the corresponding input component. MLP and
PLE down rows write the distinct branch bank, never overwrite their gate
source mid-matrix. The conservative full-bank live upper bound is
`6H+2Q*D+2P`: E2B global 17920 bytes, E4B global 24064 bytes.
Actual phase lifetimes reduce this subtotal as described at the start of
this document; query and branch never occupy the shared bank simultaneously.
Production physical payload reservation is 24064 bytes; compact 88 bytes.
All returned words and scalar/child state additionally belong in the final
workspace ledger. This leaf implements the query/branch overlay; it does
**not** establish the complete whole-system workspace bound.

| Layer cycle/degenerate boundary | Behavior |
| --- | --- |
| L0/L1/L2 | Capture descriptor, validate native model/precision/layer/position, then issue first vector request; no tensor command before L2 |
| Entering/PLE source | Stable captured index/kind/descriptor until acceptance; register response/error before RAM write |
| Internal source S0/S1/S2 | Capture bank/index, synchronous read, register payload/error; hold response until child accepts |
| Tensor/norm ownership | Validate/lookup descriptor, register it, select reader, then start norm/projection; change external owner only after active child and response retirement |
| Head boundaries | Complete Q projection, Q norm and paired rotary before attention; finish every accepted head component before next head |
| Residual/scalar | Synchronous bank read, register operands, separate binary32 operation and BF16 narrow, then write |
| Output | Ascending H BF16 stream; stalled data/index/last stay stable; done follows acceptance of final component |
| Errors/reset | Propagate actual child/source errors, zero all public outputs during reset, never expose an incomplete layer as successful |
| Single/last component | Component counters terminate by comparison, not modulo; final creation is not acceptance |
| Concurrent banks | Source reads and corresponding in-place writes are serialized; distinct branch protects gate-source liveness |

Generation cancellation, descending frontier order, ring materialization,
continuation/memo fallback, encoder production, final norm/tied logits and
session arbitration remain enclosing-engine responsibilities. This boundary
does not authorize omitting them or using external generated-state storage.

### Native tied final-logit stream

`anvil_en1_final_logits` captures model, precision and text weights base.
A public indexed BF16 source channel supplies the actual last-layer
last-token H-vector;
no external activation region or software-produced logit is read.
Look up final learned RMS scale kind 0x0004 at instance 0xffff, execute
`anvil_en1_norm` with epsilon 1e-6, and retain accepted BF16 normalized outputs
in one synchronous H-bank. Only a successful complete normalization commits
the bank. Lookup tied kind 0x0000, then use the genuine projection engine to
evaluate rows 0..262143 (0..31 compact) in order. The raw matrix result is
materialized BF16 per the frozen table, then `anvil_en1_softcap` executes
30*tanh(raw/30), with BF16 input/output.

The leaf's read-only cmd/result channels multiplex tensor validation, norm
scales and tied matrix weights. Ownership changes after child completion,
not while a memory response remains outstanding. One logit is buffered.
`logit_valid/data[15:0]/index[17:0]/last` remain stable until accepted;
done is exposed only after the last logit handshake, or an explicit retired
child/source error. Starting another descriptor requires done retirement.
No final embedding copy or vocabulary-sized result array is allocated.
`EXTERNAL_PAYLOAD_RAM=0` is the standalone default: preserve the caller's
original vector until normalization completes and allocate an internal
normalized bank of 2H bytes (3072 E2B, 5120 E4B, 16 compact), with 5120
production physical reservation. The external-bank parameter accepts only
0/1; illegal values use the well-formed diagnostic-only generate branch.

The connected ordinary/fallback output executor selects
`EXTERNAL_PAYLOAD_RAM=1`. This generate branch declares no normalized
payload RAM. `normalized_store_valid/ready`, index[31:0], data[15:0] and
last carry accepted BF16 normalization outputs to the executor's retained
hidden bank. Store valid and payload are held through backpressure by
the actual norm output channel. Malformed norm beats are consumed as
errors, not stored or exposed as successful normalization.
`source_is_normalized=0` identifies original normalization reads;
`source_is_normalized=1` identifies tied projection reads after successful
norm completion. The existing source ready/valid/response channels serve
both phases, with at most one source callback outstanding.

RMS reduction reads the complete original bank before the output pass.
The output pass rereads original components in ascending index order and
emits a normalized component only after consuming its original value.
The executor can therefore overwrite exactly that component without
changing the reduction order, BF16 boundaries or any later raw read.
The executor independently checks every store's exact ascending index,
last flag, vector generation/token/layer identity and total count; raw
reads cannot revisit an overwritten prefix, and normalized reads reject
until all H stores have committed. All RAM accesses remain synchronous.
The same hidden allocation remains live through all projection/logit
stalls and is released on actual final-head completion; its payload is
counted once in field 2. Field 21 reports zero in this mode. This removes
5120 production / 16 compact declared physical payload bytes, not measured
M20K blocks or a proved FPGA resource/timing improvement.
Child/control/scalar state, including the independent store counter and
callback phase bit, remains in the enclosing ledger.
The leaf alone does not complete session, cache, native modality or replay
integration.

| Final-logit boundary | Behavior |
| --- | --- |
| Start J0/J1/J2 | Capture descriptor, reject illegal model/precision, then begin tensor lookup; no descriptor-derived command before J2 |
| Norm output | Check ascending index, final flag and complete H count; commit only after actual successful norm done |
| Tied source T0/T1/T2 | Capture index, synchronous H-bank read, register data/error; hold response until accepted |
| External-bank stores | Accept/store the matching normalized component on the same rising edge; a stalled store cannot advance the output-pass index |
| External-bank source | Capture raw/normalized identity with index; reject overwritten raw reads or premature normalized reads before the synchronous bank access |
| Tensor/scale/projection | Registered descriptor and retained owner; error reaches done only after child's response retirement |
| First/last logit | Rows ascend from 0 to V-1; completion follows final acceptance, not creation |
| Logit backpressure | Held data/index/last, no next-row projection or duplicate final completion |
| Reset | All public channels and payload-validity zero, no reset sweep of H-bank |
| Source/weight error | Stop new work after child drains; do not emit a zero logit as successful work |

### Registered single-transaction memory arbiter

`anvil_en1_memory_arbiter` multiplexes `CLIENTS=1..8` standard cmd/result
channels. Packed lane c uses bits `[64*c+:64]` for addresses and
`[32*c+:32]` for data; valid/ready/write/error use bit c. Illegal client
counts have well-formed diagnostic-only ports and an explicit parameter
rejection; they are not silently clamped into a functioning configuration.

In idle, a registered round-robin pointer examines one client per clock.
An absent client advances the pointer; an accepted command retains that
client until its response retires. There is no unregistered external
request passthrough or fixed grant-latency promise. Acceptance A0 registers
address, write flag and payload. External valid first appears after A0.
External acceptance M0 enters the response-wait state; a response accepted
M1 registers data/error; client result valid appears after M1 and cannot
retire until M2 or later. The next command may be accepted only on a later
edge than response retirement. `cmd_owner[2:0]` identifies the captured
client for traffic classification at the actual external handshake, not
an additional transaction or an alias-derived byte count.

Drain acceptance closes all client ingress immediately, without changing a
stalled external command or client response. An already captured command
must still issue, receive its actual external response and deliver that
response to the original client. Only then is `drain_done_valid` held until
accepted. Drain does not cancel a memory response, reset an engine, complete
a session or invalidate a generation by itself. The enclosing session
controller must retire engine work and generation state around this barrier.
Reset gates all public outputs to zero; no payload/state validity survives it.
An impossible control-state encoding latches `protocol_error`, closes ingress
and does not fabricate drain completion; reset is needed after enclosing
error recovery. This indicator must be consumed by the final session controller.

| Arbiter boundary | Behavior |
| --- | --- |
| CLIENTS=1/3/8 | Explicit terminal-pointer wrap, no modulo operator or power-of-two assumption |
| Client/external command stalls | Captured address/write/data/client remain stable until actual acceptance |
| External/client response stalls | Buffer actual data/error; preserve validity until original client accepts |
| Command and response same edge | Response is not ready in send state; no dependent same-edge consumption |
| Drain and ingress same edge | Drain wins; no new client command acceptance |
| Drain and response retirement | Retire response once, then publish drain completion |
| READ_ONLY=1 write A0 | Capture client and command; enter registered rejection, with no outward command valid |
| Rejected write A1 | Publish held zero-data error response; client cannot consume it until A2 or later |
| Drain during rejected write | Preserve the error response; publish drain completion only after that client's acceptance |
| READ_ONLY=0 | Existing read/write transaction path, one actual external response per command |
| Reset | Zero channels and flags; enclosing bridge handles already accepted physical transactions |

## Cache, replay, and storage

Logical pages are immutable owner aliases. A commit-owner-page is legal only
for a true owner; it is not a data write and cannot turn unfilled payload into
readable KV. A fetch returns only an actually materialized resident word or an
actual owner-replay response. Metadata address lookup alone never supplies data.

Resident tags are (model,generation,owner,token,is_value,KV_head,component_pair).
Each resident payload is exactly one aligned 32-bit pair of BF16 components.
Fully associative hits do not advance replacement. Successful miss insertion
uses deterministic round-robin 0..C-1; capacity 3 wraps by comparison, not a mask.
There is no dirty eviction or external KV fallback. Failed or cancelled replay
does not install a word or advance replacement.

Ordinary execution allocates a token-major BF16 frontier <=3 MiB. Evaluate
each causal owner layer's output tokens in descending position order; preserve
the complete current input token until its full output is ready. At the last
local owner, retain normalized/rotated K and normalized V in a tagged local
anchor ring. Preserve the frontier entering the final global owner, execute
only the last token through that owner and all shared layers, and regenerate
missing global-owner components from the preserved frontier. Shared consumers
never project with shared weights. Earlier owner replay uses the currently
valid layer frontier, not an already overwritten layer output.

If padded frontier exceeds 3 MiB, drain outstanding work and invalidate frontier
and local ring before reusing RAM for bounded-workspace replay. No overlap of
old/new representations or spill is legal. Eval(l,t) is the BF16 vector entering
owner layer l; Eval(0,t) reconstructs immutable original inputs. Every recursive
text or encoder dependency decreases layer depth. Use explicit continuation
frames, loop counters, and return states, not recursive RTL. Completed-vector
memo eviction causes exact regeneration. Stream MLP intermediates.

Fallback ceiling is 1 MiB, inclusive of 64 vector frames of at most 12 KiB,
128 KiB memo, 64 KiB scalar continuations, and 64 KiB arithmetic/control/
resident state. Production vector depth must remain below 64; no primitive
arithmetic FSM consumes another vector frame. Single-token replay uses a linear
path. Compact fallback still reports actual and production-width shadow live
allocation, and must satisfy its measured ratio rather than borrow the
large-context inequality.

Let p=16*ceil(N/16), w=min(p,512), and C<=64. Matched unshared BF16 baselines
store distinct correct-owner K and V per logical layer with identical padding
and masks:

| Model | Baseline B | Ordinary maximum P |
| --- | --- | --- |
| E2B | 1024*(28*w+14*p) | 3072*p+1024*w+32768+4*C+M |
| E4B | 2048*(35*w+14*p) | 5120*p+2048*w+65536+4*C+M |

M includes all concurrent native reconstruction scratch and is <=min(1 MiB,
floor(B/8)). Arithmetic banks are phase overlaid, not extra hidden tensors.
Every transient copy and live frame appears in the allocation ledger. Metadata
and physical reserved SRAM are separately disclosed; unused reservation is not
advertised as removed FPGA memory.

First padded fallback is p=1040 (N=1025) for E2B and p=624 (N=609) for E4B.
The exact corresponding baselines are 29,589,504 bytes (28.21875 MiB) and
54,591,488 bytes (52.0625 MiB), correcting the proposal's MiB wording.
Require measured P<0.45B separately for both models and both precision modes.

Native accepted external KV/cache-equivalent bytes are zero. This includes
frontier, local ring, replay frames, memo, arithmetic continuations, and
generated modality features regardless of address labels. All accepted failed
or retried transfers still count. Separately report weights, original inputs,
non-KV outputs, and total bytes. Reduced KV traffic does not imply reduced total
DDR traffic, practical latency, tokens/s, or quality.

The independent unshared baseline must actually handshake its padded KV writes
and attention reads with successful responses and a nonzero denominator.
Require candidate external KV bytes <0.45*baseline bytes separately, never by
averaging models/precisions or counting aliases as traffic.

### Bounded replay workspace backing contract

`anvil_en1_replay_workspace` is a storage/controller leaf, not the completed
`Eval` interpreter. Its only payload transport is an on-chip backing-word
channel; it has no DDR command port. Ordinary native-feature evaluation uses
the disjoint tail of the shared RAM specified above. For a representation
change to fallback, the replay scheduler must first drain and invalidate the
ordinary frontier and local ring.
The frontier's control op 3 binds its existing payload RAM to fallback backing
access, only from an inactive state, with zero ordinary live bytes. Op 1
releases either representation. A new ordinary op 0 cannot acquire RAM while
fallback binding remains active: release first. Binding is not allocation of
a second copy of RAM and is not an implemented fallback numerical result.

The backing interface carries `backing_valid/ready`, `backing_write`,
`backing_addr[17:0]` (a **word index**, never an external byte address),
`backing_wdata[31:0]`, and a held `backing_rsp_valid/ready/data/error`.
Every accepted write receives one response after the synchronous write.
Every accepted read receives the actual synchronous RAM word. The legal
backing range is 0..231551 in production and 0..206975 in compact mode.
Fallback operations require op 3 binding; ordinary operations require a
successfully allocated ordinary frontier and use the disjoint physical tail.
Backing transport does not
make uninitialized words readable through the workspace's public interface.

| Partition | Production words / bytes | Compact words / bytes |
| --- | --- | --- |
| 64 two-bank frame slots | 196608 / 786432 | 196608 / 786432 |
| 16 memo vector slots | 32768 / 131072 | 8192 / 32768 |
| 64 scalar continuation slots | 2176 / 8704 | 2176 / 8704 |
| Backing total | 231552 / 926208 | 206976 / 827904 |

Frame f starts at `f*3072` words in both geometries. Each of its two
vector banks has 1536 words. Audio slice j starts at bank_base+j*512.
Memo slot s starts at `196608+s*2048` (compact `196608+s*512`).
Scalar slot f starts at `229376+f*34` (compact `204800+f*34`).
Complete domain-specific vector prefixes, including any occupied padding,
count as live payload, not merely returned components. The reserved frame/
memo strides in this table describe physical capacity, not occupied holes.
Production and shadow text/feature frames charge 3072/5120 bytes by model
per granted vector, vision 1536 and audio 2048 per granted slice. Maximum
vector payloads remain 6144/10240, 3072 and 12288 per frame respectively;
unused frame banks/slices are unallocated, not prematurely readable.
Memos charge 3072/5120, 1536 or 2048 bytes.
Every production/shadow live or pending frame additionally reserves its
complete 136-byte scalar slot, including unused scalar words.
The physical and shadow scalar layouts are identical in both builds.
Words 0..7 hold scheduler continuations, 8..14 the text attention checkpoint,
15..19 its output-projection checkpoint, 8..23 the vision checkpoint,
24/25 its outer projection state, 8..29 the audio checkpoint, and 30/31
its head reduction state. Audio history adds channel/low-half state at 32
and FP32 accumulator state at 33. These different workers share one current frame's
scalar address space under the existing mutually exclusive domain dispatcher.
The maximum actual scalar index is 33; requests at 34 or above reject before
backing access. No checkpoint is shortened or moved to an uncounted register bank.
Physical reserved backing is reported separately; in fallback it is the
first part of the shared frontier RAM, and in ordinary mode it is its
disjoint tail, not an extra inferred payload array. Compact physical RAM
reserves 209024 words / 836096 bytes to cover both its ordinary partition
and disjoint replay backing; its ordinary frontier allocation cap remains
8192 bytes and 512 tokens. Production physical RAM reserves 1017984 words /
4071936 bytes; the ordinary 3 MiB allocation cap is unchanged. Unused physical words
are not advertised as live payload or saved FPGA memory.
The unreserved 122368 production bytes within the 1 MiB total do not relax
the admitted arithmetic/control/resident partition ceiling of 65536 bytes.
That partition must cover
**all** workspace descriptor registers, masks, returned data, resident cache,
primitive state and connected arithmetic buffers. These are not established
as fitting merely by reserving this partition. The current increment
separately enforces this 65536-byte working-state limit at prospective
admission and observed completion; its actual legal-case fit remains open.

Workspace control captures a native model and generation or invalidates.
It is serialized behind accepted transactions and stalled responses. Start
clears all frame/memo/scalar visibility; invalidation releases live slots.
The eight request ops are push-frame (0), pop-frame (1), update-continuation
(2), complete-vector-store (3), vector-pair-read (4), memo-lookup (5),
scalar-word-write/frame-pair-write (6), and scalar-word-read/private-bank-preflight
(7, distinguished by target 0/1).
Requests capture model, generation, domain, layer, token, vector length,
frame/slot handle, bank, aligned component, scalar index, data and a 256-bit
continuation. Domain 0 is text, 1 vision, 2 audio, 3 completed modality features. Text/feature lengths
equal the selected H (8 in compact mode); vision/audio lengths stay 768/1024
in both modes.
Text layer is 0..L, vision 0..16, audio 0..12; feature layer 1/2 identifies
image/audio. Feature tokens are original text positions. The saved dispatcher
implements both image and audio feature workers. Image pooling retains
its literal numerical state across lower-rank encoder dependency yields;
its separately reported live banks remain charged during those yields.
Token is 0..131071.
Memo tags include every descriptor field affecting the vector
(model, generation, domain, layer, token, length).

Push allocates the next of 64 frame slots, clears its vector reservations/
visibility and scalar visibility, writes the eight continuation words, and commits depth
only after all backing responses. Rank is `text_layer+19`, `vision_layer+1`,
`audio_layer+1`, or 18 for completed features: child pushes must strictly decrease rank. This enforces
bounded dependency descent; it does not implement the neural operator that
must request the correct child. Pop reads the top continuation from backing
RAM, then releases the frame's reserved vector slices and scalar slot. Update writes only the top
frame's continuation. Additional scalar words are individually valid only
after acknowledged writes; unfilled scalar reads error rather than return
RAM initialization. Only live frame handles with the complete matching
descriptor tag are accessible for updates, vector and scalar operations.
Pop always addresses the current top of the captured session.

Before any frame continuation write, PUSH_SETUP registers prospective actual
and production-shadow frame bytes with a carry bit, using the new frame's
maximum vector requirement as a conservative capacity precheck, not a live
vector reservation. FRAME_RESERVE checks
both against the 786432-byte vector partition and checks that another scalar
slot fits below depth 64. Only the successful check establishes pending_push,
invalidates the new slot and starts its eight acknowledged continuation writes.
Only the complete scalar slot is charged at this boundary. Subsequent
FRAME_VECTOR_RESERVE/GRANT states register and check a selected whole-vector
candidate before its first backing access, as specified above.
For a memo replacement, VECTOR_SETUP first rejects inconsistent subtraction
accounting, then registers the total without the replaced vector.
MEMO_RESERVE adds the new actual/shadow vector sizes in a separate cycle.
MEMO_VALIDATE checks actual capacity (131072 production / 32768 compact bytes)
and the 131072-byte production-shadow ceiling before invalidating an old slot,
emitting eviction or reserving/writing the replacement. Unsuccessful admission
preserves the prior readable memo and returns error 7. These checks do not
silently clamp geometry or evict an in-progress frame.

| Workspace allocation boundary | Registered behavior |
| --- | --- |
| Push calculation | One 33-bit addition per actual/shadow candidate, then a later capacity check |
| Memo calculation | Subtract replaced bytes, add new bytes, then compare in three separate cycles |
| Push reservation | Complete scalar slot is visible before its first continuation backing write; vectors are initially unreserved |
| Vector reservation | Complete selected frame vector and its production shadow are charged before any stream/copy/pair backing access, including partial/error tensors |
| Explicit vector release | Operation 7/target 2 validates the current frame and committed slice, atomically removes its visibility/reservation and actual/native/shadow bytes, then publishes the response without backing traffic |
| Memo reservation | Complete pending replacement is visible before its first backing write |
| Pop release | Register the reservation-mask count, then actual/shadow bytes, then check subtotal consistency before reading continuations and releasing the frame |
| Backing range | cmd valid is suppressed for addresses outside the current declared partition; publish error 7 without an access |
| Depth 64 / scalar 32 | Reject before slot/address truncation can advertise a legal transaction |
| Reset/invalidation | Existing drain/visibility rules apply; candidate registers do not grant payload visibility |

These local partition guards are supplemented by the prospective whole-system
workspace admission described above, including ordinary text, native-scratch,
full fallback and forced-short-context ratio checks. Private-worker growth
still requires integrated grant-time limits before Verifier handoff.

Vector store target 0 is a frame bank and target 1 a memo slot. It accepts
exactly length/2 aligned 32-bit beats, checking first/last. The existing target
loses visibility before the first beat; a malformed stream, backing error,
reset or invalidation cannot commit partial payload. Vector read target 0
requires a completed frame bank. Target 1 requires a completed memo slot and
the complete matching tag; an old evicted handle cannot read its successor.
Component must be even and below length.
An accepted stream beat with `write_abort=1` explicitly annuls an unfinished
store without a backing access and returns error 7. The producer uses this
only after draining a failed numerical/input/weight operation, then preserves
that original failure in its task completion. An abort is never a successful
short vector. The Eval scheduler forwards the worker's `work_write_abort`
and accepts task completion only after the aborted workspace response retires.

Vector-store target 2 copies an already committed frame bank to memo entirely
inside the workspace. `req_slot` and `req_bank` identify the source frame;
the complete source tag must match the requested Eval descriptor. The source
remains live and immutable while the destination is selected by the same
memo replacement rule. Each actual backing read is registered before its
corresponding acknowledged destination write. Only one 32-bit copy word is
retained, in addition to the backing response register; both belong in the
arithmetic/control ledger. No external vector stream, hidden tensor buffer or
DDR command is used. Destination visibility commits only after every pair,
and `rsp_slot` returns the new memo handle. With `req_data=0`, the source remains
reserved through the entire copy; a subsequent explicit dead-vector release
or pop may retire it. With `req_data=1`, the checked top-frame consuming
transfer specified above retains one full vector charge across the disjoint
source-suffix/destination-prefix representation and makes the old frame
vector unreadable at grant commit. Other data values reject. Backing failure
leaves the memo destination unreadable; a consuming transfer also discards
its incomplete representation rather than restoring a source result.

Target 3 is the acknowledged memo-to-frame copy described in the predecessor
binding table above. It copies only an occupied, fully matching, smaller-layer
memo into the specified live frame/bank. It does not enter the streamed-write
state, allocate/replace a memo, or alter any backing partition.

Memo lookup scans 16 occupied tags sequentially and returns a slot/hit, not a
fabricated vector. Complete-vector memo stores first scan for an existing tag.
An existing-tag replacement preserves the round-robin cursor. A new tag uses
the cursor and advances it only after successful full-vector commit; evicting
an occupied slot emits an eviction event when visibility is removed. A failed
store leaves that slot empty. Lookup hits emit hit events; invalidation is not
an eviction. Returned handles do not pin memo slots against later replacement.

| Workspace/backing cycle or degenerate boundary | Behavior |
| --- | --- |
| Active reset | Every public output zero; frame, memo and scalar validity cleared without payload reset |
| First released edge | Idle control/request readiness; no old-generation data becomes visible |
| Control versus request | Control wins at ingress; neither bypasses a stalled result |
| Request W0/W1 | Capture all fields, then validate before backing access |
| Backing B0/B1/B2/B3 | Capture request, validate, synchronous RAM access, register actual response; no same-edge response consumption |
| Frame depth 0/64 | Empty pop and 65th push error before RAM access; no depth wrap |
| Dependency push | Strictly smaller registered rank; primitive iterations use no vector frame |
| Vector first/last | Final beat's acknowledged write precedes visibility; malformed beat is not issued |
| Memo cursor | Terminal comparison wraps 15 to 0; hit replacement does not advance |
| Scalar/vector collisions | One backing operation outstanding; no simultaneous read/write collision |
| Error and partial store | Drain accepted backing response, leave target unreadable, expose explicit error |
| Stalled response | Data, descriptor, continuation, hit, slot and error remain stable |

The workspace is required infrastructure for the genuine continuation/memo
fallback, not evidence that fallback inference, regeneration, termination,
full-system allocation or any acceptance case has executed.

### Explicit Eval scheduling and numerical-worker boundary

`anvil_en1_eval_schedule` is the nonrecursive dependency/controller half of
fallback Eval. It owns one `anvil_en1_replay_workspace` and issues registered
numerical tasks for a frame, rather than expanding RTL recursively or accepting
a host-produced vector. A separate resumable numerical worker is required to
execute the tasks; implementing this boundary does not claim that worker exists.
The scheduler accepts a registered native model/precision/modality/generation,
root domain/layer/token/context, and immutable original-input/weight addresses.
It binds the workspace for that invocation, so a new invocation cannot reuse
memo data from another precision or input image.

Task mode 0 starts a fresh Eval frame. Mode 1 resumes a suspended frame with
a successfully materialized dependency memo handle and a 160-bit worker
continuation. Mode 2 supplies the completed preceding hidden vector to a fresh
single-token text-layer task. The worker descriptor includes the frame slot
and complete Eval identity. The worker uses only the forwarded workspace
channel for frame vector/scalar storage and dependency memo reads. It cannot
push/pop frames, store memo entries, change a parent's continuation, or write
the scheduler's scalar words 0..7. It must serialize/drain all primitive,
memory and workspace work before completing or yielding a task.
Store target 3 is guarded by both the current frame tag and the exact returned
dependency's packed source identity. Operation-6 pair assembly/patch targets
are guarded by the current frame tag, alignment and workspace visibility/
progress. Neither addition can access an arbitrary memo or another frame.

A yielded task captures the required dependency identity and the worker
continuation. The scheduler first looks up its complete memo tag. A hit resumes
the original task with that memo handle. A miss pushes a strictly smaller-rank
child, whose eight continuation words encode the parent's identity/slot and
the exact worker continuation. Numerical loop indices and partial binary32
reductions not in the 160-bit continuation occupy acknowledged scalar words
8..255 (8..31 compact) of the parent's frame. The worker must freeze both parent
vector banks before yielding; nested tasks may only use their own frame.

The child must complete a real frame vector before the scheduler can copy it
to memo. Copy commits before pop; pop retrieves the parent's saved return
descriptor and releases the child's frame. A resumed worker may read the
returned memo handle until its next yield, when replacement becomes possible.
It must consume/copy needed dependency values before yielding again. No stale
handle bypasses the workspace's full tag check.

For a single-token text root, the controller evaluates entering hidden states
0..root_layer linearly, popping each completed frame before pushing the next.
The preceding memo handle is supplied in mode 2. This avoids a needless
root_layer-deep stack for the one-token residual chain. Actual evicted owner
dependencies still use the ordinary decreasing-rank child protocol; they are
not invented K/V answers. Multiple-token and encoder dependencies use the
explicit stack. For all paths, a completed root is read from its actual memo
slot and emitted as a checked ascending BF16 vector, followed by completion
only after the final component acceptance.

| Eval schedule cycle/degenerate boundary | Required behavior |
| --- | --- |
| Start E0/E1/E2 | Capture descriptor, validate root/session/addresses, then bind workspace; no numerical task on E0/E1 |
| Task T0 | Capture a stable frame/continuation/dependency descriptor before worker execution |
| Worker request versus done | A done/yield is accepted only after every forwarded workspace response retires; no request/done race |
| Dependency layer 0 / native PLE | Native reconstruction and per-layer PLE may request lower-rank completed features, whose dependencies descend into encoders; text cannot request text at an equal/higher layer |
| Memo hit/miss | A hit resumes after its registered lookup response; a miss waits for actual child computation and copy completion |
| Copy and pop | Committed frame stays live through memo copy; its final destination acknowledgment precedes frame release |
| Single token/root layer 0 | Exactly one reconstruction task; no needless history stack or empty vector |
| Error | Retire outstanding workspace work, invalidate all live frame/memo allocations, then publish failure; never emit a failed vector |
| Output stall | BF16 component/index/last remain stable until accepted; no completion before final acceptance |
| Reset | Zero all public outputs and cancel validity; backing payload is not initialized or advertised as readable |

All dependency loop bounds and numerical operations still belong to the
required resumable worker. The scheduler's rank check establishes decreasing
dependency depth but is not a mathematical oracle for attention masks or owner
selection. Native encoders, the numerical worker, shared-channel integration,
and complete scalar/physical/live accounting remain implementation work.
Its explicit register declarations occupy 1398 bits, disclosed as 175
byte-rounded `scheduler_state_bytes`; this is additional to the workspace's
payload/visibility figures, not a full-system resource estimate.

`anvil_en1_replay_input` supplies the text-domain Eval(0,t) reconstruction
subtask. It rereads the immutable token identity, selects each placeholder's
native image/audio feature boundary within the captured modality domain, and
runs the actual embedding/PLE arithmetic leaf. The complete ascending BF16
input stream is pair-packed directly into the assigned frame bank 0 through
the forwarded workspace store. It has no second H-vector copy. The embedding
leaf's own H/P banks and arithmetic state still count in the live ledger.
Its unused layer-0 PLE stream is drained, not treated as hidden-state data.
Both the acknowledged full-vector store and the real embedding completion
must succeed before task completion. Early numerical failure explicitly
aborts the unfinished store and retires its response before failure completion.
This subtask does not implement higher-layer or encoder Eval.
Its own 445 explicitly declared register bits are disclosed as 56
byte-rounded `controller_state_bytes`, including the retained low half,
32-bit pair, token response and command address. The embedding leaf's banks
reserve 5632 production bytes or 24 compact bytes, with selected H/P live
bytes reported through the full receive/consume lifetime. Those bank figures
exclude the embedding leaf's scalar/child registers; the full allocator must
include them independently.

| Eval input cycle/degenerate boundary | Behavior |
| --- | --- |
| Start/validation | Descriptor captured before token address validation; Eval layer must be 0 and native text token must be in the immutable prefix |
| Token read | Actual external response registered before placeholder/domain selection; an error returns 2 with no embedding start |
| Workspace ingress stall | Store request and its complete frame descriptor remain valid/stable, even if embedding fails while ingress is stalled |
| Embedding input pairs | Check every ascending index and last flag; low/high BF16 lanes form one stable acknowledged workspace beat |
| Word stall and late error | Do not withdraw an already presented word; retire it, then abort an unfinished store or fail after a completed store |
| Early embedding failure | Drain any accepted input/weight work, explicitly abort and retire the unfinished workspace transaction, then preserve the original failure |
| Full vector / completion | Last accepted word is not visibility; wait for the actual store response and the real embedding completion |
| Reset | No valid, readiness, command, data or ledger output survives active reset; no frame payload is initialized |

### Resumable attention subtask boundary

The numerical text worker uses one folded attention engine across suspended
frames; it must not retain an arithmetic instance per recursive dependency.
`anvil_en1_attention_head` gains an optional `REPLAY` parameter (0 or 1,
default 0). The ordinary layer path explicitly disables/ties off this
interface and keeps its existing protocol and arithmetic sequence.
In replay mode only, a registered `need_valid/need_ready` decision follows
successful canonical cache metadata retirement and precedes any fetch valid.
The decision descriptor is model, actual owner, token, selector, KV head and
component. Decision 0 authorizes the following real data fetch; decision 1
requests a checkpoint/yield; decisions 2/3 fail with cache-state error 7.
The need channel is not a cache request and never claims a cache hit.

The yield point is deliberately between operations: no mask, query, metadata,
fetch or arithmetic transaction remains outstanding. A successful yield
releases the attention instance for a child and is not head completion.
Resumption validates its saved descriptor, reobtains canonical metadata,
and issues the need decision again. It does not resume directly into a fetch
using a stale owner/address. An enclosing replay worker must consume the
returned dependency memo and run real owner normalization/projection/rotary
before authorizing that fetch. It cannot feed a host-produced K/V answer
or wait recursively on the root cache's outstanding regen.

The checkpoint is exactly 384 bits. Bit positions are frozen here before
RTL implementation. State not listed is dead at this boundary and is
reconstructed from the registered descriptor or the next actual response.
No reduction is restarted, reassociated, approximated or narrowed on resume.

| Checkpoint bits | Preserved state |
| --- | --- |
| 383:352 | Format magic `0x454e3141` |
| 351:343 | Reserved zero |
| 342:341, 340:333, 332:329 | Model, logical attention layer, query head |
| 328:297, 296:265, 264:233 | Query position, current key token, active-key count |
| 232:231 | Pass 0 max / 1 exponential sum / 2 value |
| 230:221, 220:211, 210:201 | Dot component, output component, requested cache component |
| 200, 199:192 | K/V selector and most recently observed canonical owner |
| 191:176, 175:160 | BF16 query component and probability |
| 159:128, 127:96, 95:64 | Binary32 dot accumulator, maximum, exponential sum |
| 63:32, 31:0 | Binary32 reciprocal sum and value accumulator |

`anvil_en1_replay_attention` wraps that actual numerical head and serializes
checkpoint storage on the existing worker workspace channel. It writes
checkpoint bits 383:160 to acknowledged scalar words 8..14 of the current
frame in ascending word order; bits 159:0 are its subtask continuation.
Resume reads those same seven individually visible words before starting
the attention engine. Scalar word 15 remains available for the enclosing
worker's stage/head continuation; words 0..7 remain scheduler-owned.
The 28 stored bytes and all live bridge/head/child registers are part of
the live allocation ledger, not additional uncounted RAM. The bridge has
no vector store and does not create a separate checkpoint payload array.
Its 590 explicitly declared register bits occupy 74 byte-rounded controller
bytes, including its 48-byte held checkpoint and returned scalar word.
The head's additional resume flag/held checkpoint occupy 385 bits; its
existing numerical and instantiated primitive registers remain additional
accounting. These are not counted again as a separate checkpoint RAM.

The subtask start captures model, attention layer/head/position and the
complete current Eval frame identity. Precision-independent BF16 attention
receives Q and masks from the enclosing numerical worker, and K/V exclusively
on its public canonical metadata/data interfaces. On yield, subtask done
contains the saved continuation and exact owner/token/selector/head/component
descriptor needed by that worker. A yield is visible only after the final
scalar response retires. It is not the scheduler's task completion and must
not trigger a memo copy of an unfinished layer vector.

| Resumable attention cycle/degenerate boundary | Required behavior |
| --- | --- |
| Start A0/A1 | Capture frame/attention/continuation fields; validate before scalar access or numerical start |
| Need N0 | Metadata response has retired; sample allow/yield/error before ever presenting fetch valid |
| Yield Y0 | Capture the stable checkpoint; only then release the numerical head and start scalar writes |
| Scalar S0/S1/S2 | Hold request/tag/data through acceptance; register response/error; advance only on the following edge |
| Resume | Read all seven saved words, validate magic/descriptor/mask bounds, then requery metadata; no stale-owner shortcut |
| Single component / C=1,3,64 | Checkpoint format is independent of cache capacity; cache replacement may require further real owner work |
| Need/fetch stall | Do not withdraw a presented fetch or mutate its payload; yielding is possible only before fetch valid |
| Failed scalar access | Retire the accepted response, stop subsequent accesses and return error; never publish a successful checkpoint |
| Done stall | Error, yield flag, continuation and dependency descriptor remain stable until accepted |
| Reset | Cancel checkpoint/read visibility and zero every public output without clearing backing payload |

This defines a resumable numerical attention subtask, not a complete Eval
text layer. Q generation and the dependency projection responder are connected
in `anvil_en1_replay_attention_execute`; the enclosing frame-vector
residual/PLE/MLP stages, whole-layer continuation and dispatch remain required.
Independent functional/numerical/eviction/reset verification remains pending.

`anvil_en1_replay_kv_tile` is the owner-projection source adapter for nested
replay attention. It instantiates the same genuine `anvil_en1_owner_kv_tile`
used by root owner replay, including input/learned-K/unscaled-V normalization,
projection materialization and local/global rotary. It obtains raw BF16
hidden components through acknowledged workspace vector reads; it allocates
no second raw H-vector. Its output is an actual normalized/rotated component
pair, not a recursive cache regen request or a supplied hidden/KV answer.
Canonical metadata still comes from the cache and chooses the owner before
this adapter is started.

The registered descriptor includes model/precision/owner/token/selector/
head/component, immutable weight-image base, context length, and a complete
workspace source handle. A memo source is Eval(owner,token), target 1 with its
returned memo slot. A current-frame source is target 0, tagged
Eval(owner+1,token), whose chosen bank the enclosing worker has already
committed as that layer's input. The adapter validates these relationships
and geometry before numerical start. It does not read an arbitrary shared
layer as an owner or access a shared-layer projection tensor.
The requested output component is an aligned pair index (bit 0 clear);
the attention responder selects the requested BF16 lane after real pair
completion. An odd output-pair descriptor fails before numerical start.
Each numerical source request captures/validates model, owner, token and
component, issues an aligned-pair workspace read with the frozen source
identity, registers the actual response, and selects the requested BF16 lane.
The memo handle must remain valid until projection completion; no task may
yield/replace it mid-projection. Errors are returned through the real source/
tile completion path after the outstanding response retires.

| Nested owner tile boundary | Behavior |
| --- | --- |
| Start / validation | Capture all descriptor fields; reject native/precision/context/owner/source mismatches before source or weight access |
| Source pair | Component bit 0 selects BF16 lane; aligned component clears bit 0, never advances into a neighboring vector |
| Source request stall | Slot, complete tag, bank, length and component remain stable; no backing access bypasses the workspace |
| Source error | Register error before numerical source response; no zero-shaped successful source fallback |
| Completion | Wait for real normalized/rotated tile completion and retired source work; returned pair/error remains held |
| Projection telemetry | Report each actual projected row, including work preceding a later error; do not classify nested owner work as avoided shared computation |
| Reset | Zero channels/telemetry and discard validity, not backing payload |

Tile H/D banks retain their existing maximum 6144-byte production reservation
(32 compact); scalar/control/child registers and returned words remain
additional live accounting. The adapter itself has only bounded registers.
Its 419 explicitly declared register bits occupy 53 byte-rounded controller
bytes, including its pair/source response registers. The tile and all child
numerical registers are additional, not included in that controller figure.
Accepted internal source reads are disclosed separately from external
original-input bytes, which only the shared arbiter can count.
`anvil_en1_replay_attention_execute` connects this subtask to the registered
dependency handle and actual replay attention data responder. The enclosing
whole-layer worker must still dispatch it and persist partial layer results
across scheduler yields.

### Ordinary frontier storage boundary

`anvil_en1_frontier` provides the ordinary token-major storage, not a complete
replay controller. COMPACT is 0/1; it reserves 3 MiB of 32-bit payload RAM
in production and 524288 bytes in compact mode. The compact ordinary partition
is capped at 8192 bytes and holds 512 H=8 vectors, allowing ordinary 17-token cases;
the remaining physical words cover native fallback vectors and continuations. Forcing a smaller frontier
is a later replay-controller partition decision, not a change to arithmetic.
Control op 0 starts a session with captured model, generation and context
length; op 1 invalidates; op 2 freezes all further writes. Op 3 binds the
released RAM to the fallback backing channel described above.
Control acknowledgement reports padded_tokens, live_bytes, and fallback_needed.
If the padded frontier exceeds its reservation, release the previous frontier,
clear visibility, and return fallback_needed with zero ordinary live bytes.
This is a capacity-selection response, not a native job-completion error or
an implemented fallback. The replay controller must proceed with real bounded
workspace execution in the same overlaid storage before it can complete a job.

Each write_start captures generation, token and entering-layer tag. Initial
layer 0 fills an empty vector. A replacement must advance that vector's tag
by exactly one layer and cannot exceed the final global-owner input layer.
The caller must already have computed the entire output vector before starting
an overwrite. Accept exactly H/2 32-bit beats in ascending pair order, checking
write_first and write_last, including simultaneous first/last for a one-pair
configuration if such geometry is later admitted. A malformed beat is not
written, leaves the target vector unreadable, and returns error 7.
Commit the token's layer/valid tag only after the final RAM write edge.
Padding occupies the allocation ledger but is not a readable token.

A read captures generation, token, entering layer and aligned component pair.
Reject unfilled, stale, wrong-layer, out-of-context or frozen-session-mismatched
descriptors before RAM access. Freezing preserves reads at existing tags and
does not manufacture a new layer. Payload RAM has synchronous registered reads
and writes with no reset sweep; per-token valid bits make old words inaccessible.
Reads/writes/control are serialized. The resettable controller uses asynchronous
reset; the dedicated payload RAM process has no asynchronous reset, to preserve
M20K inference. Active reset gates all public outputs and RAM write enables.

Control stages are capture, validation/padding, extent calculation, publication.
Read stages are capture, descriptor/tag check, synchronous RAM read, registered
result publication. Writes are capture, check, accepted beat writes, commit,
registered completion. No new transaction is accepted until the prior response
retires. Control has priority over write_start, which has priority over read.
Control changes and invalidation wait for the currently stalled result to drain.
Live bytes count the complete padded occupied frontier; metadata and physical
reserved bytes are separately visible. Payload visibility uses token tags, not
an external hidden-state archive or word-initialization data.

`anvil_en1_local_ring` stores only the ordinary path's last local owner.
Control captures model, generation and context length to arm the ring, or
invalidates it. Production reserves 1 MiB; compact reserves 64 bytes for
four local tokens with one KV head and four components. Live allocation is
1024*w bytes for E2B, 2048*w for E4B, or 16*min(p,4) in compact mode.
The unused second physical head in production E2B is reserved RAM, not live
payload or claimed removed FPGA memory.

Writes capture the true owner, token, selector and head, and receive one
complete local normalized/rotated K or normalized V head in ascending aligned
32-bit pairs. Only owner=owners-2 is writable. A wrapped slot retags the
token and clears every selector/head valid bit before receiving new words.
A same-token replacement clears only its selector/head valid bit.
The final accepted RAM write precedes visibility commit. Malformed first/last
flags reject the beat and leave that lane unreadable.

Reads capture model, generation, true owner, token, selector, head and aligned
pair index. Stale generations, nonlocal owners, inactive rings, wrapped tags,
and unfilled lanes are explicit misses (hit=0,data=0,error=0), not a KV answer;
owner replay must continue with a real projection. Bad native model or local
component/head bounds returns an error. A hit returns the actual registered
payload word. Tokens are tagged rather than assumed valid by address wrap.
One transaction is outstanding and all results remain stable through stalls.
Control has priority over write-start, then reads. RAM uses a dedicated
synchronous process, resettable visibility metadata, and no payload reset sweep.
Physical payload and token-metadata reservations are disclosed separately.
The complete replay engine still owns session barriers, frontier/ring lifetime
overlay, fallback allocation and cancellation; neither storage leaf completes
a neural job by itself.

## Public interfaces

`anvil_en1_top` retains all parent parameters and ports from
`anvil_e3_reference/rtl/anvil_e3_top.sv`. Native additions:

| Direction | Signals |
| --- | --- |
| Input | job_model[1:0], job_precision[1:0], job_decode, job_position[31:0], kv_base[63:0], logit_ready |
| Output | logit_valid, logit_data[15:0], logit_index[17:0], logit_last |
| Input | csr_valid, csr_write, csr_addr[11:0], csr_wdata[31:0], csr_rsp_ready |
| Output | csr_ready, csr_rsp_valid, csr_rdata[31:0], csr_error |

One job and one external transaction outstanding. Only the shared arbiter
drives external memory. Native logits stream in ascending vocabulary order;
done waits for the final accepted logit. Required connected literal instances
are `anvil_en1_kv_shared_cache`, `anvil_en1_asym_attn_ple`,
`anvil_en1_owner_replay`, and `anvil_en1_csr_perf`. Top consumes cache owner/
address/fetch responses; it must not duplicate the alias map.

Cache metadata input: req_valid, req_op[2:0], req_model[1:0], req_layer[7:0],
req_token[31:0], req_is_value, req_kv_head[1:0], req_component[9:0],
req_base[63:0]; output req_ready. Response: rsp_valid, rsp_addr[63:0],
rsp_owner[7:0], rsp_alias, rsp_error[3:0], rsp_space[1:0]; input rsp_ready.
Ops 0/1/2 are lookup/commit-owner-page/invalidate-session; other ops reject.
Space 0 is external parent identity, 1 resident on-chip, 2 owner-rematerialized
virtual space, 3 invalid. Native req_base is not an external address.

Native virtual aligned pair address =
(model<<44)|(owner<<36)|(token<<19)|(is_value<<18)|(KV_head<<16)|
((component>>1)<<2). Resident pair address is 4*resident_index in space 1.
Native metadata always names space 2; residency is observed through the fetch
channel, so a metadata stall does not reserve a slot against eviction. Model-0
metadata is an identity bridge: req_base already names the requested parent
component and must be aligned. Parent top does not issue native data fetches.

Fetch input: fetch_valid, fetch_model[1:0], fetch_owner[7:0],
fetch_token[31:0], fetch_is_value, fetch_kv_head[1:0], fetch_component[9:0].
Output: fetch_ready, fetch_rsp_valid, fetch_rsp_data[15:0],
fetch_rsp_error[3:0]; input fetch_rsp_ready. Fetch owner must already be a real
owner returned by metadata. Cache alone issues regen_valid with identical
descriptor fields prefixed `regen_`, accepts regen_ready, and receives
regen_rsp_valid, regen_rsp_data[31:0], regen_rsp_error[3:0], returning
regen_rsp_ready. Regen component is aligned even; fetch chooses the requested
low/high BF16 lane. Replay owns projection-weight and original-input commands
through the arbiter. The local ring remains in owner_replay and is also reached
through actual regen completion, not fabricated metadata payload.

Execution-engine signals: start_valid/start_ready plus registered descriptor;
cmd_valid/cmd_ready, cmd_write, cmd_addr[63:0], cmd_wdata[31:0];
result_valid/result_ready, result_data[31:0], result_error;
done_valid/done_ready, done_error[3:0]. Invalid inputs never return a
success-shaped zero answer.

### Cycle and degenerate-boundary table

Handshakes sample immediately before rising edges; state/counters change
afterward. A newly created response cannot be accepted on its creation edge.
Every stalled valid and payload remains stable until accepted.

| Boundary | Required behavior |
| --- | --- |
| Active reset | All public outputs zero; valid/generation state invalid |
| First post-reset edge | No unsolicited valid; ready may assert from idle |
| Job E0/E1/E2 | E0 captures every field; E1 validates; E2 dispatches or asserts error done; no earlier request-derived external valid |
| Memory M0/M1/M2 | M0 accepts request, one outstanding; M1 registers accepted response; dependent work no earlier than M2 |
| Metadata K0/K1/K2 | K0 captures; K1 registers owner/error/address; K2 exposes stable response |
| Fetch F0/F1/F2 | F0 captures; F1 tag/data lookup; F2 exposes hit; miss regen starts no earlier than F2 and waits for real completion |
| Replay result | Register accepted pair/error; fetch valid appears on following edge |
| CSR C0/C1 | Capture at C0; stable response after C1 |
| Response R0/R1 | Accepted valid clears after R0; next same-channel request may accept at R1 |
| C=1 | Single slot replacement, no zero-width pointer |
| C=3 | Wrap at 2 to 0 explicitly; no power-of-two masking |
| Single token/beat | first and last coincide; complete only after acceptance |
| Invalidate with stalled response | Stop new ingress; preserve old stalled payload, drain accepted work, then clear tags and advance generation before acknowledging invalidation |
| Invalidate with stalled regen | Preserve registered request until accepted; drain late result without insertion; cancelled fetch returns error 7; no new generation until old responses retire |
| Reset during any stall | Reset cancels generation and drops valid; shared arbiter also cancels old work |
| Page commit | Cannot install payload or allocate a shared private page |
| Clear plus counter event | Clear wins, event is not counted |
| Mode transition | Drain first, release old live allocations, then allocate replacement |

Invalidation is a barrier: K2 acknowledgement is delayed if necessary until
old work drains, rather than breaking stalled-valid stability. All other legal
metadata requests follow K0/K1/K2 exactly. Cache invalidation clears all models'
resident tags and round-robin pointer; tags use a 32-bit generation plus explicit
valid bits, so generation wrap cannot resurrect stale payload.

Preserve parent errors and add 6 invalid model/precision and 7 cache-state
violation. Cache malformed operation is error 1; invalid geometry/address
is 2. Memory error stops new work, retires the accepted response, and fails
the job. Native access errors are visible on completion and CSR error metrics.

## Telemetry and acceptance ownership

CSR 0x000 is version 0x01000000; 0x004 capabilities; 0x008 clear/snapshot;
0x00c status/model. From 0x020, retain contiguous atomic low/high pairs:
cycles, jobs_completed, memory_read_bytes, memory_write_bytes, kv_read_bytes,
kv_write_bytes, matched_unshared_kv_bytes, avoided_projection_bytes, alias_hits,
resident_tile_hits, local_head_component_cycles, global_head_component_cycles,
local_available_component_cycles, global_available_component_cycles, errors,
allocated_kv_payload_bytes, matched_unshared_kv_payload_bytes. Add after that
range: owner_reprojection_bytes, replay_input_bytes, replay_weight_bytes,
replay_activation_peak_bytes, memo_hits, memo_evictions, fallback_jobs,
peak_live_kv_equivalent_bytes. Counters saturate 64 bits; clear wins; unknown or
misaligned accesses error. Parent/native metrics stay separate. Actual owner
reprojection must not be counted as avoided projection.

The CSR event interface is event_valid, event_model[1:0], event_mask[24:0],
and event_values[1599:0], with metric i in bits [64*i+:64]. One accepted
event bundle updates parent bank 0 for model 0 or native bank 1 for models 1/2.
The connected top guarantees legal event_model values; model 3 has no bank.
Metric indices 15/16 are absolute live-payload gauges, 20/24 are peaks, and
other metrics add unsigned deltas with saturation. Allocation gauges are not
advertised as cumulative allocated traffic. Weight/input byte events include
replay and failed accepted transactions in the appropriate class.

CSR capabilities is 0x000000ff: BF16, Q4_0, owner aliases, owner replay,
local/global attention, PLE, native vision, and native audio are bits 0..7.
This is the target product capability word, not an assertion that disconnected
partial sources deliver those engines. Status bits are busy[0], model[9:8],
error[15:12], and selected metric bank[16]. Write 0x00c with only bit 16 set
or cleared to select native/parent metrics; other writable bits reject.
Read-only version/capabilities reject writes.

Write 0x008 bit 0 to clear both banks, bit 1 to capture both banks and enable
snapshot reads, bit 2 to release snapshot reads. Reserved bits and simultaneous
capture/release reject. Clear plus capture creates a zero snapshot; clear
dominates simultaneous events. Capture alone samples pre-edge counters, before
the capture-edge event update. Write acknowledgements return zero data.
Read 0x008 returns snapshot-active in bit 1.

A metric low-word read captures its high half plus bank/index; the matching
high-word read returns that captured high half. A high-word read without a
matching preceding low-word read rejects rather than fabricate an atomic pair.
Bank selection and snapshot/clear commands invalidate this pair latch. Stalled
CSR responses retain their already captured data while counters continue.
The internal CSR module also receives status_model[1:0], status_busy and
status_error[3:0] from the connected job controller.

The unchanged mandatory suites are contract, behavior with seeds 17,43,89,
defects, benchmark, synthesis, and portable, through `tests/verify.py`.
Independent Verifier owns all tests, models, fixtures, traffic/liveness
observers, actual-handshake baseline, mutations, and synthesis checks.
Designer does not author or execute these checks.

Fixture RNG is xorshift32 with steps <<13, >>17, <<5 and truncation after each
step; zero seeds are illegal. Tensor order is the directory table enumeration,
row-major element order. Ordinary BF16 matrix values are
BF16_RNE(((next_u32 & 31)-16)/64), norm scales
BF16_RNE(1+((next_u32 & 7)-3)/64), layer scalars
BF16_RNE(1+((next_u32 & 3)-1)/128). Q4 scales are FP16 1/32 and nibbles
next_u32 & 15 in the prescribed packing. Token t is (7*t+seed) modulo fixture
vocabulary in software. Directed exceptional and clipping fixtures are separate.

Required execution remains the admitted cases A--E: full-map compact top-level
ordinary/fallback inference, two-token historical replay, real 17-token memo
eviction/regeneration, production-width nonzero projection/norm/RoPE tiles,
all listed page/window/context boundaries, actual live allocation and memory
handshakes, failed memory responses, incompressible payloads, both precisions,
models, anchors, capacities 1/3/64, reset and backpressure. Independently
compare intermediate owner KV, normalized values, PLE, and every final logit.
All ten original mutations plus replay-spill and missing-live-frame allocation
must fail their intended assertion, not compilation or unrelated timeout.

All six original commands remain mandatory and self-contained. No future
product report is an engineering input. The shared runtime separately executes
timing-lint, Quartus 17.1 STA WNS>=0 at <=10 ns, and physical PCIe Gen3x8 HIL.
L1 scripts must not hardcode JTAG cables or PCIe BDFs. An independently approved
product PDF is authored/reviewed/rendered by the shared runtime only after
engineering acceptance.
