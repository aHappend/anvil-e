<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="brand/logo-dark.svg">
    <img src="brand/logo.svg" width="420" alt="Vulcan">
  </picture>
  <h1>Anvil-E · Multimodal Embedding & Retrieval Silicon</h1>
  <p><strong>Synthesizable 100 MHz+ Text, Vision & Audio Conformer Embedding Accelerators · Intel Arria 10 GX PCIe Gen3x8 HIL · IEEE/ACM Dual-Track Reports</strong></p>
  <p>
    <img src="https://img.shields.io/badge/Platform-Intel_Arria_10_GX-0f766e?style=flat-square" alt="Platform">
    <img src="https://img.shields.io/badge/Quartus_17.1_STA-100_MHz%2B_Closed-0f766e?style=flat-square" alt="STA">
    <img src="https://img.shields.io/badge/PCIe_Gen3x8_HIL-100%25_Passed-1d4ed8?style=flat-square" alt="HIL">
    <img src="https://img.shields.io/badge/Author-Sufeng_Guo_(MSRA)-334155?style=flat-square" alt="Author">
    <img src="https://img.shields.io/badge/License-MIT-64748b?style=flat-square" alt="License">
  </p>
  <p>
    <a href="https://ahappend.github.io/vulcan/">Website</a> ·
    <a href="https://github.com/aHappend/vulcan-showcase">Vulcan Showcase</a> ·
    <a href="https://github.com/aHappend/anvil-q">Anvil-Q (LLM)</a> ·
    <a href="https://github.com/aHappend/anvil-e">Anvil-E (Embedding)</a> ·
    <a href="https://github.com/aHappend/billet-t">Billet-T (FFT/DSP)</a> ·
    <a href="https://github.com/aHappend/billet-f">Billet-F (FIR/IIR)</a> ·
    <a href="https://github.com/aHappend/rivet-a">Rivet-A (AES-GCM)</a> ·
    <a href="https://github.com/aHappend/rivet-h">Rivet-H (SHA/HMAC)</a> ·
    <a href="https://github.com/aHappend/swage-s">Swage-S (ISP)</a> ·
    <a href="https://github.com/aHappend/bellows-l">Bellows-L (LZ4)</a> ·
    <a href="https://github.com/aHappend/crucible-g">Crucible-G (3D)</a> ·
    <a href="https://github.com/aHappend/furnace-x">Furnace-X (SoC)</a> ·
    <a href="README.zh-CN.md"><strong>中文文档</strong></a>
  </p>
</div>

---

**Anvil-E** is the dedicated multimodal embedding series within Vulcan's **Anvil** AI silicon family, turning the authoritative `google/embeddinggemma-2` specification across Text (`Anvil-E1`), Vision+Text (`Anvil-E2`), and Audio+Vision+Text (`Anvil-E3`) into synthesizable `100 MHz+` SystemVerilog RTL with physical Intel Arria 10 GX PCIe Gen3x8 HIL verification.

## Silicon Signoff Matrix & Dual-Track Publications (`100 MHz+` Baseline)

| Gen | Accelerator | Architecture & Numerical Scope | Quartus 17.1 STA (`10.0 ns`) | Intel Arria 10 GX Utilization | PCIe Gen3x8 HIL | Academic & Developer Reports |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Gen-1** | [**Anvil-E1**](anvil-e1/) | `google/embeddinggemma-2` Text-Only · 24L 5:1 Hybrid GQA · PLE + Matryoshka 768D L2 Norm | `107.31 MHz` (`WNS +0.681 ns`) | `18,420 ALMs (4.31%) · 128 DSPs (8.43%) · 192 M20K` | **PASSED (3/3)** | [**Whitepaper PDF**](anvil-e1/SHOWCASE_REPORT.pdf) · [**Engineering PDF**](anvil-e1/REPORT.pdf) |
| **Gen-2** | [**Anvil-E2**](anvil-e2/) | `google/embeddinggemma-2` Vision+Text · 16L ViT + 3x3 Pooler + 24L Hybrid Backbone | `111.45 MHz` (`WNS +1.027 ns`) | `23,550 ALMs (5.51%) · 192 DSPs (12.65%) · 312 M20K` | **PASSED (3/3)** | [**Whitepaper PDF**](anvil-e2/SHOWCASE_REPORT.pdf) · [**Engineering PDF**](anvil-e2/REPORT.pdf) |
| **Gen-3** | [**Anvil-E3**](anvil-e3/) | `google/embeddinggemma-2` Audio+Vision+Text Trimodal · 12L Conformer + 16L ViT + 24L Backbone | `111.63 MHz` (`WNS +1.042 ns`) | `26,480 ALMs (6.20%) · 224 DSPs (14.76%) · 360 M20K` | **PASSED (3/3)** | [**Whitepaper PDF**](anvil-e3/SHOWCASE_REPORT.pdf) · [**Engineering PDF**](anvil-e3/REPORT.pdf) |

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

## Vulcan Seven-Family Workshop Silicon Matrix

| Silicon Family | Workshop Metaphor | Domain & Series Repositories |
| :--- | :--- | :--- |
| **Anvil** *(Primary Focus)* | Heavy forge anvil bearing core compute loads | AI & Large-Model Compute — [**Anvil-Q** (Quantized LLMs)](https://github.com/aHappend/anvil-q) · [**Anvil-E** (Multimodal Embeddings)](https://github.com/aHappend/anvil-e) |
| **Billet** | Raw metal stock shaped and combined into systems | Digital Signal Processing — [**Billet-T** (FFT/Spectral)](https://github.com/aHappend/billet-t) · [**Billet-F** (FIR/SOS-IIR Filters)](https://github.com/aHappend/billet-f) |
| **Rivet** | Small, critical, rock-solid fasteners | Cryptography & Data Integrity — [**Rivet-A** (AES/GCM/DMA)](https://github.com/aHappend/rivet-a) · [**Rivet-H** (SHA-256/512/HMAC)](https://github.com/aHappend/rivet-h) |
| **Swage** | Die-forming tool shaping inputs into target forms | Image Processing & ISP — [**Swage-S** (2D Scaler, 3×3 Spatial Filter, Bayer Demosaic, CSC)](https://github.com/aHappend/swage-s) |
| **Bellows** | Expanding/contracting continuous airflow | Streaming Data Compression — [**Bellows-L** (LZ4 Decompressor, Hash-Table Compressor, XXH32 DMA)](https://github.com/aHappend/bellows-l) |
| **Crucible** | Vessel fusing diverse materials into form | Graphics Processing & Rendering — [**Crucible-G** (Triangle Setup, Tile Rasterizer, Z-Buffer & Texture Shader)](https://github.com/aHappend/crucible-g) |
| **Furnace** | Industrial furnace integrating multiple stages | Heterogeneous SoCs — [**Furnace-X** (Multi-Engine AI + DSP + Crypto + ISP + Compression SoC)](https://github.com/aHappend/furnace-x) |

---
<p align="center"><sub>Author: <strong>Sufeng Guo</strong> · Microsoft Research Asia · <a href="mailto:sufeng_guo@smail.nju.edu.cn">sufeng_guo@smail.nju.edu.cn</a> · <a href="LICENSE">MIT License</a></sub></p>
