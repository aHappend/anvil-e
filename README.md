<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="brand/logo-dark.svg">
    <img src="brand/logo.svg" width="480" alt="Vulcan">
  </picture>
</p>

<h1 align="center">Anvil-E · Embedding silicon, forged anew.</h1>

<p align="center">
  Open embedding accelerator RTL. Real engineering results.
  <br>
  <a href="https://ahappend.github.io/vulcan/">Visit the website</a>
  · <a href="https://github.com/aHappend/vulcan-showcase">Vulcan Showcase</a>
  · <a href="README.zh-CN.md">中文</a>
  · <a href="anvil-e1/">Anvil-E1 package</a>
  · <a href="anvil-e2/">Anvil-E2 package</a>
  · <a href="brand/">Brand assets</a>
</p>

**Anvil** is our AI accelerator silicon family developed with Vulcan. **Anvil-E**
is the dedicated embedding series within the family, turning open embedding
model specifications into synthesizable SystemVerilog RTL, self-checking
verification suites and reproducible delivery packages.

## Series roadmap

| Generation | Design | Target model & scope | Status |
| --- | --- | --- | --- |
| **Gen-1** | **[Anvil-E1](anvil-e1/)** | [Google EmbeddingGemma-2 (`google/embeddinggemma-2`)](https://huggingface.co/google/embeddinggemma-2) · Text-Only edition (24-layer 5:1 hybrid sliding/full attention, 512d → 768d projection, mean pooling and L2 normalization) | Completed & Verified — Full Pure-Text RTL Delivery Package Published |
| **Gen-2** | **[Anvil-E2](anvil-e2/)** | [Google EmbeddingGemma-2 (`google/embeddinggemma-2`)](https://huggingface.co/google/embeddinggemma-2) · Vision + Text Multimodal edition (16-layer `gemma4_vision` tower, 3×3 spatial pooler to 280 soft tokens, 768d → 512d vision bridge, and 24-layer 5:1 hybrid multimodal backbone) | Settled — Vision+Text RTL Package Published |
| **Gen-3** | **Anvil-E3** | Google EmbeddingGemma-2 · Audio + Vision + Text unified embedding engine | Planned |

## Anvil-E2 · Generation 2 (Vision + Text Multimodal edition)

`Anvil-E2` extends the `Anvil-E` line to the multimodal Vision + Text architecture of
HuggingFace [`google/embeddinggemma-2`](https://huggingface.co/google/embeddinggemma-2),
engineered autonomously with **Vulcan 0.8**:

| Stage | Architectural specification (`google/embeddinggemma-2`) | Hardware engineering focus |
| --- | --- | --- |
| **Vision Patch & Axial Position (`vision_tower.patch_embedder`)** | `patch_size = 16` (`input_proj [768, 768]`), `position_embedding_table [2, 10240, 768]`, 2D `axial` RoPE (`rope_theta = 100.0`) | Clipped patch projection, 2D coordinate position lookup and axial rotary embedding |
| **Vision Transformer (`vision_tower.encoder`)** | 16 layers, `hidden_size = 768`, `intermediate_size = 3072` (`gelu_pytorch_tanh`), 12-head MHA (`head_dim = 64` with `q_norm`/`k_norm`), 4× RMSNorm per layer | Parameterized vision encoder datapath with input/output clipping support |
| **Spatial Pooler & Vision Bridge (`embed_vision`)** | `pooling_kernel_size = 3` spatial pooling (`default_output_length = 280` soft tokens) + `embedding_projection [512, 768]` | 3×3 spatial token aggregation, 768 → 512 projection and `BOI`/`IMAGE`/`EOI` token stream fusion |
| **Multimodal Backbone & Output (`0_Transformer` + `1_Pooling` + `2_Normalize`)** | 24-layer 5:1 hybrid sliding/full attention (`512d` + PLE `512d`), `512 → 768` projection, masked mean pooling and Matryoshka L2 normalization (`768 / 512 / 256 / 128`) | Unified vision+text sequence attention, masked accumulation and reciprocal-sqrt L2 normalization |

- **Current engineering status**: `Settled — Vision+Text RTL Package Published` (updated `-`)
- **Authoritative model configs**: [`anvil-e2/hf_embeddinggemma2_vision_spec/`](anvil-e2/hf_embeddinggemma2_vision_spec/)
- **Deliverable directory**: [`anvil-e2/`](anvil-e2/) (`rtl/`, `design/`, `tests/`)

## Anvil-E1 · Generation 1 (Text-Only edition)

- **Engineering status**: `Completed & Verified — Full Pure-Text RTL Delivery Package Published`
- **Authoritative model configs**: [`anvil-e1/hf_embeddinggemma2_spec/`](anvil-e1/hf_embeddinggemma2_spec/)
- **Deliverable directory**: [`anvil-e1/`](anvil-e1/) (`rtl/`, `design/`, `tests/`)

## License

Published code, documentation and artwork are provided under the [MIT License](LICENSE).
