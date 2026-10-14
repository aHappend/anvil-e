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
  · <a href="brand/">Brand assets</a>
</p>

**Anvil** is our AI accelerator silicon family developed with Vulcan. **Anvil-E**
is the dedicated embedding series within the family, turning open embedding
model specifications into synthesizable SystemVerilog RTL, self-checking
verification suites and reproducible delivery packages.

## Series roadmap

| Generation | Design | Target model & scope | Status |
| --- | --- | --- | --- |
| **Gen-1** | **[Anvil-E1](anvil-e1/)** | [Google EmbeddingGemma-2 (`google/embeddinggemma-2`)](https://huggingface.co/google/embeddinggemma-2) · Text-Only edition (24-layer 5:1 hybrid sliding/full attention, 512d → 768d projection, mean pooling and L2 normalization) | In Progress — Vulcan 0.6 Autonomous RTL Design & Verification (HF google/embeddinggemma-2) |
| **Gen-2** | **Anvil-E2** | Google EmbeddingGemma-2 · Vision + Text token frontend integration | Planned |
| **Gen-3** | **Anvil-E3** | Google EmbeddingGemma-2 · Audio + Vision + Text unified embedding engine | Planned |

## Anvil-E1 · Generation 1 (Text-Only edition)

`Anvil-E1` targets the authoritative HuggingFace [`google/embeddinggemma-2`](https://huggingface.co/google/embeddinggemma-2)
text embedding pipeline (`embedding_gemma2_text` + `1_Pooling` + `2_Normalize`),
with architecture decomposition, RTL implementation and verification conducted
through Vulcan 0.6:

| Stage | Architectural specification (`google/embeddinggemma-2`) | Hardware engineering focus |
| --- | --- | --- |
| **Backbone (`0_Transformer`)** | 24 layers, `hidden_size = 512`, `hidden_size_per_layer_input = 512` (Per-Layer Input injection), `intermediate_size = 2048` (`gelu_pytorch_tanh`), `vocab_size = 262,144` | Parameterized datapath, RMSNorm, RoPE, GeGLU/GELU-tanh FFN and extensible token-stream ingress |
| **Hybrid attention (5:1)** | 20 sliding-window layers (`window = 512`, 4Q:2KV GQA, `head_dim = 256`, `rope_theta = 10,000`) + 4 global full-attention layers (layers 5/11/17/23, 4Q:1KV MQA, `head_dim = 512`, `rope_theta = 1,000,000`) | Unified local/global attention schedule and KV addressing |
| **Projection & Pooling (`1_Pooling`)** | Linear projection `512 → 768` (`embedding_dim = 768`) followed by masked `mean` pooling (`include_prompt = true`) | Masked token accumulation and reciprocal length scaling |
| **Normalization (`2_Normalize`)** | Unit L2 normalization with Matryoshka Representation Learning (MRL) dimensions `768 / 512 / 256 / 128` | Hardware reciprocal-square-root L2 normalizer and dimension-selectable egress |

- **Current engineering status**: `In Progress — Vulcan 0.6 Autonomous RTL Design & Verification (HF google/embeddinggemma-2)` (updated `2026-10-15 04:14:28 UTC+8`)
- **Authoritative model configs**: [`anvil-e1/hf_embeddinggemma2_spec/`](anvil-e1/hf_embeddinggemma2_spec/)
- **Deliverable directory**: [`anvil-e1/`](anvil-e1/) (`rtl/`, `tb/`, `docs/`, `reports/`)

## Delivery package standard

Consistent with the Vulcan open-hardware series, published packages provide:

- Accepted synthesizable RTL, interface/architecture documentation and integration instructions.
- Reproducible verification sources, configuration matrices, tool versions and commands, plus simulation and generic synthesis evidence.
- Explicit scope boundaries: results describe simulation and generic synthesis; they do not claim silicon measurements or physical signoff. Closed framework code, prompts, provider sessions, credentials, private experience capsules and internal operating records are not part of the public package.

## Explore

- **[Project website](https://ahappend.github.io/vulcan/)** — meet Vulcan.
- **[Vulcan Showcase](https://github.com/aHappend/vulcan-showcase)** — open RTL designs and selected engineering results from Vulcan.
- **[Anvil-E1 package](anvil-e1/)** — specification, RTL, verification sources and status record.
- **[Visual identity](brand/)** — original logos, marks and application icon.

## License

Published code, documentation and artwork are provided under the [MIT License](LICENSE).
