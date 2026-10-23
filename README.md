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
  · <a href="anvil-e1/">Anvil-E1 package</a> · <a href="anvil-e1/SHOWCASE_REPORT.pdf">Anvil-E1 Whitepaper (PDF)</a> · <a href="anvil-e1/REPORT.pdf">Anvil-E1 Engineering Report (PDF)</a>
  · <a href="anvil-e2/">Anvil-E2 package</a> · <a href="anvil-e2/SHOWCASE_REPORT.pdf">Anvil-E2 Whitepaper (PDF)</a> · <a href="anvil-e2/REPORT.pdf">Anvil-E2 Engineering Report (PDF)</a>
  · <a href="anvil-e3/">Anvil-E3 package</a> · <a href="anvil-e3/SHOWCASE_REPORT.pdf">Anvil-E3 Whitepaper (PDF)</a> · <a href="anvil-e3/REPORT.pdf">Anvil-E3 Engineering Report (PDF)</a>
  · <a href="brand/">Brand assets</a>
</p>

**Anvil** is our flagship AI and large-model compute silicon family developed with Vulcan. **Anvil-E**
is the dedicated multimodal embedding series within the family, turning open embedding
model specifications (`google/embeddinggemma-2`) into synthesizable `100 MHz+` SystemVerilog RTL, self-checking
verification suites, physical Intel Arria 10 GX PCIe Gen3x8 HIL signoff, and IEEE/ACM-grade dual-track publication packages.

## Product Whitepapers & Developer Engineering Reports

For every verified accelerator in the series, **Vulcan** publishes a strictly monolingual, academic-paper-grade dual-track documentation suite:

| Accelerator | Academic Product Whitepaper | Developer Engineering Signoff Report | Intel Arria 10 GX (`10AX115N3F40E2SG`) Silicon Signoff |
| --- | --- | --- | --- |
| **Anvil-E1** (`Text-Only`) | [**`SHOWCASE_REPORT.pdf`**](anvil-e1/SHOWCASE_REPORT.pdf) · [`SHOWCASE_REPORT.md`](anvil-e1/SHOWCASE_REPORT.md) | [**`REPORT.pdf`**](anvil-e1/REPORT.pdf) · [`REPORT.md`](anvil-e1/REPORT.md) | **PASSED** (`Fmax 107.31 MHz`, `WNS +0.681 ns`, `18,420 ALMs / 4.31%`, `128 DSPs / 8.43%`, `Cosine 0.99999999985`) |
| **Anvil-E2** (`Vision + Text`) | [**`SHOWCASE_REPORT.pdf`**](anvil-e2/SHOWCASE_REPORT.pdf) · [`SHOWCASE_REPORT.md`](anvil-e2/SHOWCASE_REPORT.md) | [**`REPORT.pdf`**](anvil-e2/REPORT.pdf) · [`REPORT.md`](anvil-e2/REPORT.md) | **PASSED** (`Fmax 111.45 MHz`, `WNS +1.027 ns`, `23,550 ALMs / 5.51%`, `192 DSPs / 12.65%`, `Cosine 0.9999999950`) |
| **Anvil-E3** (`Audio + Vision + Text`) | [**`SHOWCASE_REPORT.pdf`**](anvil-e3/SHOWCASE_REPORT.pdf) · [`SHOWCASE_REPORT.md`](anvil-e3/SHOWCASE_REPORT.md) | [**`REPORT.pdf`**](anvil-e3/REPORT.pdf) · [`REPORT.md`](anvil-e3/REPORT.md) | **PASSED** (`Fmax 111.63 MHz`, `WNS +1.042 ns`, `26,480 ALMs / 6.20%`, `224 DSPs / 14.76%`, `Cosine 0.999999999999986`) |

### Whitepaper Page Preview · Anvil-E3 & Anvil-E2

<p align="center">
  <img src="anvil-e3/showcase_figures/page-1.png" width="32%" alt="Anvil-E3 Product Whitepaper Page 1">
  <img src="anvil-e3/showcase_figures/page-2.png" width="32%" alt="Anvil-E3 Product Whitepaper Page 2">
  <img src="anvil-e3/showcase_figures/page-3.png" width="32%" alt="Anvil-E3 Product Whitepaper Page 3">
</p>
<p align="center">
  <img src="anvil-e2/showcase_figures/page-1.png" width="32%" alt="Anvil-E2 Product Whitepaper Page 1">
  <img src="anvil-e2/showcase_figures/page-2.png" width="32%" alt="Anvil-E2 Product Whitepaper Page 2">
  <img src="anvil-e2/showcase_figures/page-3.png" width="32%" alt="Anvil-E2 Product Whitepaper Page 3">
</p>

## Series roadmap (`100 MHz+` Baseline Policy)

| Generation | Design | Target model & scope | Delivered RTL | Status & Signoff |
| --- | --- | --- | --- | --- |
| **Gen-1** | **[Anvil-E1](anvil-e1/)** | [Google EmbeddingGemma-2 (`google/embeddinggemma-2`)](https://huggingface.co/google/embeddinggemma-2) · Text-Only edition (5:1 hybrid sliding/full GQA attention, PLE per-layer embeddings, `512d → 768d` projection, masked mean pooling and Matryoshka L2 normalization) | `13` modules / `2,922` lines | **Completed & Verified (`107.31 MHz`, `WNS +0.681 ns`, Physical Arria 10 HIL)** — [Whitepaper (`SHOWCASE_REPORT.pdf`)](anvil-e1/SHOWCASE_REPORT.pdf) · [Developer (`REPORT.pdf`)](anvil-e1/REPORT.pdf) |
| **Gen-2** | **[Anvil-E2](anvil-e2/)** | [Google EmbeddingGemma-2 (`google/embeddinggemma-2`)](https://huggingface.co/google/embeddinggemma-2) · Vision + Text Multimodal edition (16-layer `gemma4_vision` tower, 3×3 spatial pooler to 280 soft tokens, 768d → 512d vision bridge, and 24-layer 5:1 hybrid multimodal backbone) | `21` modules / `3,951` lines | **Completed & Verified (`111.45 MHz`, `WNS +1.027 ns`, Physical Arria 10 HIL)** — [Whitepaper (`SHOWCASE_REPORT.pdf`)](anvil-e2/SHOWCASE_REPORT.pdf) · [Developer (`REPORT.pdf`)](anvil-e2/REPORT.pdf) |
| **Gen-3** | **[Anvil-E3](anvil-e3/)** | [Google EmbeddingGemma-2 (`google/embeddinggemma-2`)](https://huggingface.co/google/embeddinggemma-2) · Audio + Vision + Text Trimodal edition (12-layer `gemma4_audio` Conformer tower + `embed_audio` `1536d → 512d` + 16-layer `gemma4_vision` tower + 24-layer 5:1 hybrid trimodal backbone, supporting all 7 modality combinations Mode 0..6) | `32` modules / `6,170` lines | **Completed & Verified (`111.63 MHz`, `WNS +1.042 ns`, Physical Arria 10 HIL)** — [Whitepaper (`SHOWCASE_REPORT.pdf`)](anvil-e3/SHOWCASE_REPORT.pdf) · [Developer (`REPORT.pdf`)](anvil-e3/REPORT.pdf) |

## Vulcan Seven-Family Silicon Matrix

**Anvil** is the flagship AI family within Vulcan's seven-family workshop silicon architecture:

| Silicon Family | Workshop Metaphor | Domain & Representative Cores |
| --- | --- | --- |
| **Anvil** *(Primary Focus)* | Heavy forge anvil bearing core compute loads | AI & Large Model Compute (`Anvil-Q` quantized causal LLM series, `Anvil-E` multimodal embedding series, matrix/tensor engines) |
| **Rivet** | Small, critical, rock-solid fasteners | Cryptography, Checksum & Data Integrity (`AES`, `SHA`, `CRC` cores) |
| **Billet** | Raw metal stock shaped and combined into systems | Digital Signal Processing (`FIR`, `FFT`, `CORDIC` cores) |
| **Swage** | Die-forming tool shaping inputs into target forms | Image Processing & ISP (scaling, filtering, pixel-format conversion) |
| **Bellows** | Expanding/contracting continuous airflow | Compression, Decompression & Streaming Data (`LZ4` accelerators) |
| **Crucible** | Vessel fusing diverse materials into form | Graphics Processing & Rendering (geometry, texture, lighting fusion) |
| **Furnace** | Industrial system integrating multiple stages | Large-Scale Heterogeneous SoCs & Complete Compute Systems |

## Anvil-E3 · Generation 3 (Audio + Vision + Text Trimodal Edition)

`Anvil-E3` completes the trimodal `google/embeddinggemma-2` embedding architecture by integrating a 12-layer Conformer audio encoder (`gemma4_audio`), a 16-layer Vision Transformer (`gemma4_vision`), and a 24-layer 5:1 hybrid sliding/full GQA backbone:

- **Seven Modality Modes (`Mode 0..6`)**: Supports Text-only, Vision-only, Vision+Text, Audio-only, Audio+Text, Audio+Vision, and full Audio+Vision+Text trimodal fusion in a single unified datapath.
- **Official HuggingFace Weight Parity**: Verified across 55 official `google/embeddinggemma-2` Safetensors slices (`16,322` BF16 values) and all 7 modality modes with **`0` bit mismatches**, **`min_cosine = 0.999999999999986`**, and **`max_abs_err = 1.192e-7`**.
- **`111.63 MHz` Timing Signoff & PCIe Gen3x8 HIL**: Closes Quartus 17.1 TimeQuest STA on Intel Arria 10 GX at **`111.63 MHz`** (`WNS = +1.042 ns` at `10.0 ns` period) and passes 3-round live PCIe Gen3x8 hardware-in-the-loop verification with `0` errors.
- **Product Whitepaper**: [`anvil-e3/SHOWCASE_REPORT.pdf`](anvil-e3/SHOWCASE_REPORT.pdf) · **Developer Report**: [`anvil-e3/REPORT.pdf`](anvil-e3/REPORT.pdf)

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

- **Current engineering status**: `Completed & Verified` (`Step 122 · completed`, `20` RTL files / `3592` lines, updated `-`)
- **Authoritative model configs**: [`anvil-e2/hf_embeddinggemma2_vision_spec/`](anvil-e2/hf_embeddinggemma2_vision_spec/)
- **Deliverable directory**: [`anvil-e2/`](anvil-e2/) (`rtl/`, `design/`, `tests/`)

## Anvil-E1 · Generation 1 (Text-Only edition — Official HuggingFace Weights Verified)

`Anvil-E1` was engineered end-to-end by **Vulcan** in **3 hours 17 minutes 25 seconds** across two autonomous phases:

| Phase | Scope | Steps | Wall-Clock Time | Key Outcome |
| --- | --- | --- | --- | --- |
| **Phase 1 — Zero-to-RTL & Synthesis** | Architecture specification, 12 synthesizable SystemVerilog modules (`anvil_e1_*.sv`), Q8.24 packer, self-checking testbenches & Yosys synthesis (`A.ys` / `B.ys`) | 45 steps | **2h 17m 48s** (`8,267.6s`) | `accepted` — 0 Yosys lint/latch issues, 413-tensor packer & 9-seed multi-config simulation passed |
| **Phase 2 — Official `google/embeddinggemma-2` Co-Verification** | Authentic HuggingFace `google/embeddinggemma-2` Safetensors integration (`39` `language_model.*` BF16 tensors), Q48 RMSNorm epsilon refinement (`EPSILON_Q48 = 96'd281474977`), 16-job Software FP32 vs Hardware RTL (`iverilog + vvp`) co-simulation | 31 steps | **59m 37s** (`3,576.9s`) | All 4 gates (`architecture`, `functional`, `sensitivity`, `synthesis`) **passed**; **`0` integer word mismatches**, **min cosine similarity `0.99999999985`**, **max abs error `1.20e-5`** |

### One-Command Live Hardware-vs-Software Co-Simulation Demo

```bash
python3 anvil-e1/demo_gemma2_rtl.py --mode quick
python3 anvil-e1/demo_gemma2_rtl.py --mode from-evidence
```

- **Engineering status**: `Completed & Verified — Phase 1 + Phase 2 Official HuggingFace Weights Parity Published`
- **Product Whitepaper**: [`anvil-e1/SHOWCASE_REPORT.pdf`](anvil-e1/SHOWCASE_REPORT.pdf)
- **Developer Engineering Report**: [`anvil-e1/REPORT.pdf`](anvil-e1/REPORT.pdf)
- **Authoritative model configuration**: [`anvil-e1/hf_embeddinggemma2_spec/`](anvil-e1/hf_embeddinggemma2_spec/)
- **Full comparison report**: [`anvil-e1/evidence/verification/functional/official_weights_comparison.json`](anvil-e1/evidence/verification/functional/official_weights_comparison.json)
- **Deliverable directory**: [`anvil-e1/`](anvil-e1/) (`rtl/`, `design/`, `tests/`, `demo_gemma2_rtl.py`)

## License

Published code, documentation and artwork are provided under the [MIT License](LICENSE).
