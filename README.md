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

| Generation | Design | Target model & scope | Autonomous Build Time | Status |
| --- | --- | --- | --- | --- |
| **Gen-1** | **[Anvil-E1](anvil-e1/)** | [Google EmbeddingGemma-2 (`google/embeddinggemma-2`)](https://huggingface.co/google/embeddinggemma-2) · Text-Only edition (5:1 hybrid sliding/full GQA attention, PLE per-layer embeddings, `512d → 768d` projection, masked mean pooling and Matryoshka L2 normalization) | **3h 17m 25s total** (`2h 17m 48s` Phase 1 RTL + `59m 37s` Phase 2 Official HF Weights Co-Sim) | Completed & Verified — [Official Report (`REPORT.pdf`)](anvil-e1/REPORT.pdf) & Live Demo Published |
| **Gen-2** | **[Anvil-E2](anvil-e2/)** | [Google EmbeddingGemma-2 (`google/embeddinggemma-2`)](https://huggingface.co/google/embeddinggemma-2) · Vision + Text Multimodal edition (16-layer `gemma4_vision` tower, 3×3 spatial pooler to 280 soft tokens, 768d → 512d vision bridge, and 24-layer 5:1 hybrid multimodal backbone) | Running (Step 26 Verifier) | In Progress — Autonomous Vision+Text Architecture & RTL Generation by Vulcan 0.8 |
| **Gen-3** | **Anvil-E3** | Google EmbeddingGemma-2 · Audio + Vision + Text unified embedding engine | — | Planned |

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

- **Current engineering status**: `In Progress — Autonomous Vision+Text Architecture & RTL Generation by Vulcan 0.8` (updated `2026-10-15 15:11:43 UTC+8`)
- **Authoritative model configs**: [`anvil-e2/hf_embeddinggemma2_vision_spec/`](anvil-e2/hf_embeddinggemma2_vision_spec/)
- **Deliverable directory**: [`anvil-e2/`](anvil-e2/) (`rtl/`, `design/`, `tests/`)

## Anvil-E1 · Generation 1 (Text-Only edition — Official HuggingFace Weights Verified)

`Anvil-E1` was engineered end-to-end by **Vulcan** in **3 hours 17 minutes 25 seconds** across two autonomous phases:

| Phase | Scope | Steps | Wall-Clock Time | Key Outcome |
| --- | --- | --- | --- | --- |
| **Phase 1 — Zero-to-RTL & Synthesis** | Architecture specification, 12 synthesizable SystemVerilog modules (`anvil_e1_*.sv`), Q8.24 packer, self-checking testbenches & Yosys synthesis (`A.ys` / `B.ys`) | 45 steps | **2h 17m 48s** (`8,267.6s`) | `accepted` — 0 Yosys lint/latch issues, 413-tensor packer & 9-seed multi-config simulation passed |
| **Phase 2 — Official `google/embeddinggemma-2` Co-Verification** | Authentic HuggingFace `google/embeddinggemma-2` Safetensors integration (`39` `language_model.*` BF16 tensors), Q48 RMSNorm epsilon refinement (`EPSILON_Q48 = 96'd281474977`), 16-job Software FP32 vs Hardware RTL (`iverilog + vvp`) co-simulation | 31 steps | **59m 37s** (`3,576.9s`) | All 4 gates (`architecture`, `functional`, `sensitivity`, `synthesis`) **passed**; **`0` integer word mismatches**, **min cosine similarity `0.99999999985`**, **max abs error `1.20e-5`** |

### One-Command Live Hardware-vs-Software Co-Simulation Demo

Run the live co-simulation showcase (directly invoking the Phase 2 verification suite `tests/official.py`, `tests/official_fp32.py`, and compiling `rtl/anvil_e_top.sv` with `iverilog` + `vvp`):

```bash
# Live compile + cycle-accurate RTL simulation (~2.5s)
python3 anvil-e1/demo_gemma2_rtl.py --mode quick

# Display full 16-job official-weight co-simulation table (or --mode full to re-simulate all 16 jobs)
python3 anvil-e1/demo_gemma2_rtl.py --mode from-evidence
```

```text
[1/4] Official HuggingFace `google/embeddinggemma-2` Provenance Verification
  • Safetensors SHA-256 : 3a310d7733a28f533b611eb7525f597303980c2ab2f890487a9a1fcbf0366bfb
  • Extracted Tensors   : 39 language_model.* BF16 tensors verified (11,266 coordinates checked)
  • Layer Topology      : 6-Layer 5:1 Hybrid Attention [0, 0, 0, 0, 0, 5] (Local Sliding + Full GQA)

----------------------------------------------------------------------------------------
Job | Tokens                   | Dim |   Cycles |   Cyc/Tok | BitErr |  MaxAbsErr |     Cosine Sim
----------------------------------------------------------------------------------------
  0 | [2]                      |   6 |    22654 |   22654.0 |      0 |   5.10e-06 |   1.0000000000
  4 | [2, 3]                   |   6 |    48400 |   24200.0 |      0 |   1.17e-05 |   0.9999999999
  8 | [2, 4, 7]                |   6 |    70669 |   23556.3 |      0 |   6.85e-06 |   1.0000000000
 12 | [2, 3, 4, 5, 6, 7, 8, 1] |   6 |   220274 |   27534.2 |      0 |   7.40e-06 |   0.9999999999
 14 | [2, 3, 4, 5, 6, 7, 8, 1] |   2 |   220239 |   27529.9 |      0 |   1.20e-05 |   0.9999999999
----------------------------------------------------------------------------------------

  Detailed Channel-by-Channel Readout for Job 0 (tokens=[2], pos=[7], dim=6):
  Ch | Software FP32/BF16 | RTL Pin `emb_data` (Hex) |  RTL Decoded Q8.24 |    Abs Error
   0 |        +0.71077168 |               0x00b5f530 |        +0.71077251 |     8.34e-07
   1 |        +0.03985842 |               0x000a342f |        +0.03985876 |     3.39e-07
   2 |        -0.42826340 |               0xff925daa |        -0.42825830 |     5.10e-06
   3 |        -0.33611840 |               0xffa9f417 |        -0.33611923 |     8.34e-07
   4 |        +0.09332270 |               0x0017e435 |        +0.09332591 |     3.21e-06
   5 |        -0.43372878 |               0xff90f700 |        -0.43373108 |     2.29e-06
```

- **Engineering status**: `Completed & Verified — Phase 1 + Phase 2 Official HuggingFace Weights Parity Published`
- **Authoritative model configs & official slice**: [`anvil-e1/hf_embeddinggemma2_spec/`](anvil-e1/hf_embeddinggemma2_spec/)
- **Full comparison report**: [`anvil-e1/evidence/verification/functional/official_weights_comparison.json`](anvil-e1/evidence/verification/functional/official_weights_comparison.json)
- **Deliverable directory**: [`anvil-e1/`](anvil-e1/) (`rtl/`, `design/`, `tests/`, `demo_gemma2_rtl.py`)

## License

Published code, documentation and artwork are provided under the [MIT License](LICENSE).
