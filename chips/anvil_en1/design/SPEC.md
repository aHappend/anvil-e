# Anvil-EN1 implementation contract

Product: `v1.0.0-gemma4-kvshare-e2b-e4b`. Target top: `anvil_en1_top`.
Target device: Intel Arria 10 GX `10AX115N2F45E1SG`, synchronous clock period
at most 10 ns. This document freezes implementation choices; it is not an
engineering acceptance or a claim that every described engine exists.

## Source boundary and provenance

The 32 files in `anvil_e3_reference/rtl/` are immutable parent compatibility
references. Model 0 must instantiate the parent top with every named parameter,
port width, and signedness unchanged. Parent fixed-point multimodal execution
is not a substitute for either native model's BF16 computation. The supplied
tree contains no historical `design/GENERATIONAL_HANDOFF.md`. No parent timing,
resource, throughput, or quality result is asserted here.

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
| FP classify/convert | A1 classify/unpack; A2 shift/guard; A3 RNE/pack | after A3 |
| FP add | A1 classify/unpack; A2 align with sticky; A3 signed sum; bounded iterative normalization; registered RNE/pack | completion-valid after normalization/pack |
| FP multiply | A1 classify/unpack; normalize subnormal operands one bit/cycle; four registered 12x12 products; two registered reduction stages; exponent alignment; registered RNE/pack | completion-valid after normalization/pack |
| Unsigned divide | D1 register operands; D2..D33 one restoring quotient bit per cycle; D34 RNE/pack | after D34 |
| Square root | S1 register radicand; bounded one digit per cycle; final normalization and RNE stage | completion-valid after final stage |
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
