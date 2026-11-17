# Anvil-E — Text, vision and audio embedding RTL

[English](README.md) · [简体中文](README.zh-CN.md) · [Repository guide / 文件导航](REPOSITORY_GUIDE.md)

Documentation updated: 2026-11-17. This page describes a repository snapshot, not a live job dashboard.

## Overview

**Anvil-E** publishes chip RTL, technical reports and verification artifacts. Text embedding, vision/text and audio/vision/text datapaths, including attention, pooling and normalization research.

The chip project is public; Vulcan itself remains private and closed-source. Future public releases must be limited to chip technology and public reproducibility materials, excluding Vulcan internal architecture and operating materials. This refresh organizes documentation only; it is not a comprehensive disclosure audit of historical material and does not claim that the existing repository tree has undergone such clearance.

## Scope and evidence

Use the [exact-directory result index](REPOSITORY_GUIDE.md). Functional simulation, synthesis, standalone/virtual-pin timing, board-bridge probing, workload readback and system-software execution are different evidence scopes. A pass at one scope does not establish another. Existing historical results are retained; this documentation refresh neither upgrades nor invalidates them.

Read timing, utilization and performance values from their specific records and applicability conditions; results from differently located copies are not merged. This page makes no fleet-wide claim of physical-board completion, full-model inference, physical Linux boot or measured power/energy efficiency.

## Repository guide

The [repository guide](REPOSITORY_GUIDE.md) lists existing source, constraints, tests, reports and result paths. Hyphenated, underscored and `chips/` directories can be different publication copies; none is silently designated authoritative, moved or deleted.

Start reproduction from the selected chip’s public specification, test instructions and scripts. Tool, input and board requirements belong to that directory. Chip experiments were not rerun as part of this documentation update.

## Existing chip directories

| Chip / variant | Existing root paths | Public artifacts |
| --- | --- | --- |
| ANVIL-E1 | [`anvil-e1/`](anvil-e1/) | [REPORT.md](anvil-e1/REPORT.md) · [REPORT.pdf](anvil-e1/REPORT.pdf) · [SHOWCASE_REPORT.pdf](anvil-e1/SHOWCASE_REPORT.pdf) · [SHOWCASE_REPORT.zh-CN.pdf](anvil-e1/SHOWCASE_REPORT.zh-CN.pdf) |
| ANVIL-E2 | [`anvil-e2/`](anvil-e2/) | [REPORT.md](anvil-e2/REPORT.md) · [REPORT.pdf](anvil-e2/REPORT.pdf) · [SHOWCASE_REPORT.pdf](anvil-e2/SHOWCASE_REPORT.pdf) · [SHOWCASE_REPORT.zh-CN.pdf](anvil-e2/SHOWCASE_REPORT.zh-CN.pdf) |
| ANVIL-E3 | [`anvil-e3/`](anvil-e3/) | [REPORT.md](anvil-e3/REPORT.md) · [REPORT.pdf](anvil-e3/REPORT.pdf) · [SHOWCASE_REPORT.pdf](anvil-e3/SHOWCASE_REPORT.pdf) · [SHOWCASE_REPORT.zh-CN.pdf](anvil-e3/SHOWCASE_REPORT.zh-CN.pdf) |
| ANVIL-EDGE | [`anvil-edge/`](anvil-edge/) · [`anvil_edge/`](anvil_edge/) | [REPORT.md](anvil-edge/REPORT.md) · [REPORT.pdf](anvil-edge/REPORT.pdf) · [SHOWCASE_REPORT.pdf](anvil-edge/SHOWCASE_REPORT.pdf) · [SHOWCASE_REPORT.zh-CN.pdf](anvil-edge/SHOWCASE_REPORT.zh-CN.pdf) |
| ANVIL-EN1 | [`anvil-en1/`](anvil-en1/) · [`anvil_en1/`](anvil_en1/) | [REPORT.md](anvil-en1/REPORT.md) · [REPORT.pdf](anvil-en1/REPORT.pdf) · [SHOWCASE_REPORT.pdf](anvil-en1/SHOWCASE_REPORT.pdf) · [SHOWCASE_REPORT.zh-CN.pdf](anvil-en1/SHOWCASE_REPORT.zh-CN.pdf) |
| ANVIL-EN2 | [`anvil-en2/`](anvil-en2/) · [`anvil_en2/`](anvil_en2/) | [REPORT.md](anvil-en2/REPORT.md) · [REPORT.pdf](anvil-en2/REPORT.pdf) · [SHOWCASE_REPORT.pdf](anvil-en2/SHOWCASE_REPORT.pdf) · [SHOWCASE_REPORT.zh-CN.pdf](anvil-en2/SHOWCASE_REPORT.zh-CN.pdf) |

## Architecture catalog and publications

| Generation | Chip | Architecture / research scope | Record navigation | Reports |
| --- | --- | --- | --- | --- |
| **Gen-1** | [**Anvil-E1**](anvil-e1/) | `google/embeddinggemma-2` Text-Only · 24L 5:1 Hybrid GQA · PLE + Matryoshka 768D L2 Norm | [Exact-directory records](REPOSITORY_GUIDE.md) | [**Whitepaper PDF**](anvil-e1/SHOWCASE_REPORT.pdf) · [**Engineering PDF**](anvil-e1/REPORT.pdf) |
| **Gen-2** | [**Anvil-E2**](anvil-e2/) | `google/embeddinggemma-2` Vision+Text · 16L ViT + 3x3 Pooler + 24L Hybrid Backbone | [Exact-directory records](REPOSITORY_GUIDE.md) | [**Whitepaper PDF**](anvil-e2/SHOWCASE_REPORT.pdf) · [**Engineering PDF**](anvil-e2/REPORT.pdf) |
| **Gen-3** | [**Anvil-E3**](anvil-e3/) | `google/embeddinggemma-2` Audio+Vision+Text Trimodal · 12L Conformer + 16L ViT + 24L Backbone | [Exact-directory records](REPOSITORY_GUIDE.md) | [**Whitepaper PDF**](anvil-e3/SHOWCASE_REPORT.pdf) · [**Engineering PDF**](anvil-e3/REPORT.pdf) |
| **Peer-EN1** | [**Anvil-EN1**](anvil-en1/) | `Gemma-4` (`E2B/E4B`) 5:1 Circular Sliding-Window / Global KV + Proportional RoPE + Per-Layer Embeddings (historical E4 lineage label; no E4 directory is published here) | [Exact-directory records](REPOSITORY_GUIDE.md) | [**Whitepaper PDF**](anvil-en1/SHOWCASE_REPORT.pdf) · [**中文白皮书**](anvil-en1/SHOWCASE_REPORT.zh-CN.pdf) · [**Peer Repo**](https://github.com/aHappend/anvil-en) |
| **Peer-EN2** | [**Anvil-EN2**](anvil-en2/) | `Gemma-4 Omni-Modal` Vision Patch + Audio Conformer + Text Unified PLE & Shared-KV Engine | [Exact-directory records](REPOSITORY_GUIDE.md) | [**Whitepaper PDF**](anvil-en2/SHOWCASE_REPORT.pdf) · [**中文白皮书**](anvil-en2/SHOWCASE_REPORT.zh-CN.pdf) · [**Peer Repo**](https://github.com/aHappend/anvil-en) |
| **Standalone SoC** | [**Anvil-Edge**](anvil-edge/) | Zero-Host Edge LLM SoC: Hardware UART + UTF-8/BPE Tokenizer + Vocabulary Detokenizer + Closed-Loop FSM | [Exact-directory records](REPOSITORY_GUIDE.md) | [**Whitepaper PDF**](anvil-edge/SHOWCASE_REPORT.pdf) · [**中文白皮书**](anvil-edge/SHOWCASE_REPORT.zh-CN.pdf) |

## Academic Product Whitepaper Visual Gallery

### Anvil-E1 · Academic Whitepaper Preview ([`anvil-e1/SHOWCASE_REPORT.pdf`](anvil-e1/SHOWCASE_REPORT.pdf))
<table>
  <tr>
    <td align="center" width="33%"><a href="anvil-e1/SHOWCASE_REPORT.pdf"><img src="anvil-e1/showcase_figures/page-1.png" width="100%" alt="Anvil-E1 Page 1"></a><br><sub><strong>Page 1 · Architecture & KPI Summary</strong></sub></td>
    <td align="center" width="33%"><a href="anvil-e1/SHOWCASE_REPORT.pdf"><img src="anvil-e1/showcase_figures/page-2.png" width="100%" alt="Anvil-E1 Page 2"></a><br><sub><strong>Page 2 · Experimental Benchmarks & Parity</strong></sub></td>
    <td align="center" width="33%"><a href="anvil-e1/SHOWCASE_REPORT.pdf"><img src="anvil-e1/showcase_figures/page-3.png" width="100%" alt="Anvil-E1 Page 3"></a><br><sub><strong>Page 3 · Arria 10 STA, HIL & Scaling</strong></sub></td>
  </tr>
</table>

### Anvil-E2 · Academic Whitepaper Preview ([`anvil-e2/SHOWCASE_REPORT.pdf`](anvil-e2/SHOWCASE_REPORT.pdf))
<table>
  <tr>
    <td align="center" width="33%"><a href="anvil-e2/SHOWCASE_REPORT.pdf"><img src="anvil-e2/showcase_figures/page-1.png" width="100%" alt="Anvil-E2 Page 1"></a><br><sub><strong>Page 1 · Architecture & KPI Summary</strong></sub></td>
    <td align="center" width="33%"><a href="anvil-e2/SHOWCASE_REPORT.pdf"><img src="anvil-e2/showcase_figures/page-2.png" width="100%" alt="Anvil-E2 Page 2"></a><br><sub><strong>Page 2 · Experimental Benchmarks & Parity</strong></sub></td>
    <td align="center" width="33%"><a href="anvil-e2/SHOWCASE_REPORT.pdf"><img src="anvil-e2/showcase_figures/page-3.png" width="100%" alt="Anvil-E2 Page 3"></a><br><sub><strong>Page 3 · Arria 10 STA, HIL & Scaling</strong></sub></td>
  </tr>
</table>

### Anvil-E3 · Academic Whitepaper Preview ([`anvil-e3/SHOWCASE_REPORT.pdf`](anvil-e3/SHOWCASE_REPORT.pdf))
<table>
  <tr>
    <td align="center" width="33%"><a href="anvil-e3/SHOWCASE_REPORT.pdf"><img src="anvil-e3/showcase_figures/page-1.png" width="100%" alt="Anvil-E3 Page 1"></a><br><sub><strong>Page 1 · Architecture & KPI Summary</strong></sub></td>
    <td align="center" width="33%"><a href="anvil-e3/SHOWCASE_REPORT.pdf"><img src="anvil-e3/showcase_figures/page-2.png" width="100%" alt="Anvil-E3 Page 2"></a><br><sub><strong>Page 2 · Experimental Benchmarks & Parity</strong></sub></td>
    <td align="center" width="33%"><a href="anvil-e3/SHOWCASE_REPORT.pdf"><img src="anvil-e3/showcase_figures/page-3.png" width="100%" alt="Anvil-E3 Page 3"></a><br><sub><strong>Page 3 · Arria 10 STA, HIL & Scaling</strong></sub></td>
  </tr>
</table>

Anvil-E4 was named in earlier roadmap text but has no corresponding published directory in this snapshot. / 早期规划提到 Anvil-E4，本快照未发布对应目录。

## Related projects

- AI / embeddings: [Anvil-Q](https://github.com/aHappend/anvil-q), [Anvil-E](https://github.com/aHappend/anvil-e), [Anvil-QN](https://github.com/aHappend/anvil-qn), [Anvil-EN](https://github.com/aHappend/anvil-en), [Anvil-D](https://github.com/aHappend/anvil-d).
- Systems: [Hammer-V](https://github.com/aHappend/hammer-v), [Furnace-X](https://github.com/aHappend/furnace-x).
- DSP / vision: [Billet-F](https://github.com/aHappend/billet-f), [Billet-T](https://github.com/aHappend/billet-t), [Swage-S](https://github.com/aHappend/swage-s).
- Data / security / graphics: [Bellows-L](https://github.com/aHappend/bellows-l), [Bellows-N](https://github.com/aHappend/bellows-n), [Rivet-A](https://github.com/aHappend/rivet-a), [Rivet-H](https://github.com/aHappend/rivet-h), [Crucible-G](https://github.com/aHappend/crucible-g), [SABLE](https://github.com/aHappend/sable).
- [Public fleet catalog](https://github.com/aHappend/vulcan-showcase). Related independent research: [ACE-2](https://github.com/aHappend/ace-2), [ACE-3](https://github.com/aHappend/ace-3); these retain their own provenance and acceptance boundaries.
- DSpark is a research direction, not a published chip delivery in this repository; no implementation or repository link is asserted here.
