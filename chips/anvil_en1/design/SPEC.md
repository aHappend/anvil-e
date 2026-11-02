# Anvil-EN1 implementation contract

Product: `v1.0.0-gemma4-kvshare-e2b-e4b`. Target top: `anvil_en1_top`.
Target device: Intel Arria 10 GX `10AX115N2F45E1SG`, synchronous clock period
at most 10 ns. This document freezes implementation choices; it is not an
engineering acceptance or a claim that every described engine exists.

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
layer, immutable for the whole operation. An ordinary caller reads the
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

Three synchronous H-banks retain the residual, normalized work and branch.
A D-bank retains one Q head; a Q*D bank retains the attention concatenation;
a P-bank retains combined PLE. No J-vector or probability/score array is
allocated. Norm may overwrite its branch/Q bank only after its complete
reduction and consumption of the corresponding input component. MLP and
PLE down rows write the distinct branch bank, never overwrite their gate
source mid-matrix. Actual vector payload is at most
`6H+2D+2Q*D+2P`: E2B global 18944 bytes, E4B global 25088 bytes.
Production physical payload reservations are 25088 bytes; compact 104 bytes.
All returned words and scalar/child state additionally belong in the final
workspace ledger. Private leaf/controller reservations are **not** yet an
implemented phase overlay or an established full-system allocation bound.

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

### Ordinary frontier storage boundary

### Bounded replay workspace backing contract

`anvil_en1_replay_workspace` is a storage/controller leaf, not the completed
`Eval` interpreter. Its only payload transport is an on-chip backing-word
channel; it has no DDR command port. The replay scheduler must drain and
invalidate the ordinary frontier and local ring before enabling this channel.
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
backing range is 0..245759 in production and 0..1599 in compact mode.
No operation is accepted before op 3 binds the RAM. Backing transport does not
make uninitialized words readable through the workspace's public interface.

| Partition | Production words / bytes | Compact words / bytes |
| --- | --- | --- |
| 64 two-vector frame slots | 196608 / 786432 | 512 / 2048 |
| 16 memo vector slots | 32768 / 131072 | 64 / 256 |
| 64 scalar continuation slots | 16384 / 65536 | 1024 / 4096 |
| Backing total | 245760 / 983040 | 1600 / 6400 |

Frame f starts at `f*3072` production words (`f*8` compact). Each of its two
vector banks has 1536 words (4 compact). Memo slot s starts at
`196608+s*2048` (compact `512+s*4`). Scalar slot f starts at
`229376+f*256` (compact `576+f*16`). Full occupied slot reservations, including
padding, count as live payload, not merely returned components. Production
shadow frame/memo/scalar allocations always use the production slot sizes.
Physical reserved backing is reported separately; it is the first part of
the existing frontier RAM, not an extra inferred payload array.
The remaining 65536 production bytes of the admitted 1 MiB ceiling must cover
**all** workspace descriptor registers, masks, returned data, resident cache,
primitive state and connected arithmetic buffers. These are not established
as fitting merely by reserving this partition.

Workspace control captures a native model and generation or invalidates.
It is serialized behind accepted transactions and stalled responses. Start
clears all frame/memo/scalar visibility; invalidation releases live slots.
The eight request ops are push-frame (0), pop-frame (1), update-continuation
(2), complete-vector-store (3), vector-pair-read (4), memo-lookup (5),
scalar-word-write (6), and scalar-word-read (7).
Requests capture model, generation, domain, layer, token, vector length,
frame/slot handle, bank, aligned component, scalar index, data and a 256-bit
continuation. Domain 0 is text, 1 vision, 2 audio; 3 rejects. Text lengths
equal the selected H, vision/audio lengths are 768/1024, or 8 in compact mode.
Text layer is 0..L, vision 0..16, audio 0..12; token is 0..131071.
Memo tags include every descriptor field affecting the vector
(model, generation, domain, layer, token, length).

Push allocates the next of 64 frame slots, invalidates both vectors and its
scalar visibility, writes the eight continuation words, and commits depth
only after all backing responses. Rank is `text_layer+18`, `vision_layer+1`,
or `audio_layer+1`: child pushes must strictly decrease rank. This enforces
bounded dependency descent; it does not implement the neural operator that
must request the correct child. Pop reads the top continuation from backing
RAM, then releases both frame and scalar slots. Update writes only the top
frame's continuation. Additional scalar words are individually valid only
after acknowledged writes; unfilled scalar reads error rather than return
RAM initialization. Only live frame handles are accessible.

Vector store target 0 is a frame bank and target 1 a memo slot. It accepts
exactly length/2 aligned 32-bit beats, checking first/last. The existing target
loses visibility before the first beat; a malformed stream, backing error,
reset or invalidation cannot commit partial payload. Vector read target 0
requires a completed frame bank. Target 1 requires a completed memo slot and
the complete matching tag; an old evicted handle cannot read its successor.
Component must be even and below length.

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
| Backing B0/B1/B2 | Capture request, synchronous RAM access, register actual response; no same-edge response consumption |
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

`anvil_en1_frontier` provides the ordinary token-major storage, not a complete
replay controller. COMPACT is 0/1; it reserves 3 MiB of 32-bit payload RAM
in production and 8192 bytes in compact mode. The compact reservation holds
512 H=8 vectors, allowing ordinary 17-token cases; forcing a smaller frontier
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
