# Anvil-E (`anvil-e`) — AI Embedding Silicon Series

**`Anvil`** is our AI hardware accelerator family. **`Anvil-E`** is the dedicated **Embedding Series** within the Anvil family, engineered autonomously from high-level natural-language specifications by **Vulcan 0.6**.

---

## Product Roadmap (`Anvil-E` Series)

| Generation | Chip Name | Target Model & Modality | Status |
| :--- | :--- | :--- | :--- |
| **Gen-1** | **`Anvil-E1`** | **Google EmbeddingGemma-2 (Text-Only Edition)** | **In Progress — Autonomous Architecture & RTL Generation by Vulcan 0.6** |
| **Gen-2** | **`Anvil-E2`** | Google EmbeddingGemma-2 + Vision Token Frontend | Planned (Next Iteration) |
| **Gen-3** | **`Anvil-E3`** | Unified Text + Vision + Audio Multimodal Embedding Engine | Planned |

---

## Generation 1: `Anvil-E1` (Text-Only EmbeddingGemma-2 Accelerator)

`Anvil-E1` is designed end-to-end by **Vulcan 0.6** from a pure-text specification targeting Google's **EmbeddingGemma-2** text embedding architecture:
- **Autonomous Architecture & Module Decomposition**: Vulcan 0.6 independently analyzes the EmbeddingGemma-2 text computation graph (Token Embedding, RMSNorm, RoPE, Grouped-Query Attention with Logit Soft-Capping, GeGLU FFN, Masked Mean Pooling, and L2 Normalization) and partitions the hardware datapath and control hierarchy.
- **Full Hardware Verification & Signoff**: Self-checking SystemVerilog testbenches (`iverilog`/`vvp` simulation) + `yosys` RTL synthesis signoff (zero latches, full cell statistics).
- **Extensible Multimodal Interface**: Designed with a unified token-stream ingress interface to seamlessly accommodate Vision and Audio tokenizers in `Anvil-E2` and `Anvil-E3`.

### Current Engineering Progress
- **Engine**: Vulcan 0.6 (`hardware.rtl` autonomous multi-role closed loop: `Coordinator -> Reviewer -> Designer -> Verifier`)
- **Current Status**: `In Progress — Autonomous Architecture & RTL Generation by Vulcan 0.6`
- **Last Updated (UTC+8)**: `2026-10-15 04:14:28 UTC+8`
- **Deliverable Directory**: [`anvil-e1/`](./anvil-e1/) (`rtl/`, `tb/`, `docs/`, `reports/`)

---

## License & Open-Source Notice

This repository publishes the complete open-source hardware deliverable package (`rtl/`, `tb/`, `docs/`, `reports/`) for **`Anvil-E1`**. The underlying Vulcan 0.6 automated silicon engineering platform remains proprietary.
