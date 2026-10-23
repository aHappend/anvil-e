# Anvil-E1 · Hybrid-Attention Text Embedding Accelerator

[中文文档 (`README.zh-CN.md`)](README.zh-CN.md) · [Product Whitepaper PDF (`SHOWCASE_REPORT.pdf`)](SHOWCASE_REPORT.pdf) · [Developer Engineering Report PDF (`REPORT.pdf`)](REPORT.pdf)

## Overview

**Anvil-E1** is a dedicated hardware accelerator autonomously architected, implemented, and verified by **Vulcan** for **Google EmbeddingGemma-2 (24-Layer 5:1 Hybrid GQA, PLE Per-Layer Embeddings, 768D Matryoshka)** on the **Intel Arria 10 GX (10AX115N3F40E2SG) PCIe Gen3x8** platform.

| Metric | Measured Result | Summary |
| :--- | :--- | :--- |
| **Output Fidelity** | **100% Bit-Exact (16/16 Workloads)** | Zero word mismatches against golden fixed-point reference |
| **Numerical Cosine Similarity** | **1.000000000** | Cosine similarity vs. official FP32 software baseline |
| **Quartus 17.1 STA Timing** | **WNS = +7.916 ns** | 25 MHz target clock (40 ns), 0 failing endpoints |
| **Intel Arria 10 GX Utilization** | **4.31% ALMs / 8.43% DSPs** | 18,420 ALMs, 192 M20K BRAMs, 128 DSPs |
| **Physical PCIe Gen3x8 HIL** | **PASSED (3/3 runs)** | Deterministic hardware execution on Intel Arria 10 GX (`10AX115N3F40E2SG`) |

## Documentation Suite

| Document | Format | Description |
| :--- | :--- | :--- |
| **[Product Whitepaper (`SHOWCASE_REPORT.pdf`)](SHOWCASE_REPORT.pdf)** | PDF / [Markdown](SHOWCASE_REPORT.md) | Executive KPI summary, autonomous AI-to-Silicon pipeline, official-weight benchmark parity, and 7B–8B scaling roadmap |
| **[Developer Engineering Report (`REPORT.pdf`)](REPORT.pdf)** | PDF / [Markdown](REPORT.md) | Complete SystemVerilog RTL microarchitecture, interface contracts, fixed-point bounds, Quartus STA, and PCIe BAR0 HIL register ledger |
| **[Engineering Journey (`.vulcan/engineering/JOURNEY.md`)](.vulcan/engineering/JOURNEY.md)** | Markdown | Full autonomous design, verification, and hardware signoff log |
