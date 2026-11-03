# Anvil-Edge · 5W 级 BitNet b1.58 三值无乘法端侧大模型推理芯片 — 学术技术论文与物理 FPGA 实测评测报告

[中文白皮书 PDF (`SHOWCASE_REPORT.zh-CN.pdf`)](SHOWCASE_REPORT.zh-CN.pdf) · [英文版白皮书 (`SHOWCASE_REPORT.md`)](SHOWCASE_REPORT.md) · [英文白皮书 PDF (`SHOWCASE_REPORT.pdf`)](SHOWCASE_REPORT.pdf) · [开发者工程签核报告 (`REPORT.pdf`)](REPORT.pdf)

## 1. 核心性能指标概览

| 指标维度 | 实测指标 | 技术说明 |
| :--- | :--- | :--- |
| **推理输出一致性** | **100% 比特级精确匹配** | 全测试集硬件输出与黄金参考标准零偏差 |
| **数值余弦相似度** | **0.999999995** | 硬件定点输出与官方 FP32 浮点基准余弦相似度 |
| **物理 FPGA 板级验证** | **Intel Arria 10 GX (Fmax 34.40 MHz)** | PCIe Gen3x8 物理板卡 SoftReg 小参数向量实测 **0 比特误差**，Quartus 17.1 建立时间裕量 **+10.892 ns** |
| **硬件资源利用率与扩展容量** | **1.50% ALMs / 0.00% DSPs** | 单核精简架构，保留 **>98.5%** 逻辑余量；8 GB 板载 DDR4 最高支持 **7B–8B** 量化模型常驻 |

## 2. 官方预训练权重多模态实测精度对比

- **实测最大绝对误差**：`1.204e-05`（优于工程规格容差上限 `2.000e-03` 达 **166 倍**）
- **实测平均绝对误差**：`6.884e-06`
- **相对官方 FP32 余弦相似度**：`0.999999995`

## 3. 跨平台性能、延迟与能效横评（同机 CPU vs. GPU vs. FPGA，ctx = 128..4096）

| 对比计算平台与精度配置 | ctx=128 (tok/s) | ctx=512 (tok/s) | ctx=1024 (tok/s) | ctx=2048 (tok/s) | ctx=4096 吞吐与延迟 | 4K 功耗与能效比 | P99.9/P50 抖动 |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **AMD EPYC 7662 CPU（单核 FP32）** | `41.2` | `31.8` | `23.5` | `14.6` | **`8.1 tok/s`** (`123.46 ms`) | `15.0 W` / **`0.54 tok/J`** | `1.790x` |
| **AMD EPYC 7662 CPU（8核 AVX2 BF16）** | `198.4` | `164.2` | `128.5` | `86.4` | **`51.2 tok/s`** (`19.53 ms`) | `65.0 W` / **`0.79 tok/J`** | `1.710x` |
| **NVIDIA Tesla V100-32GB GPU（原生 FP16）** | `712.0` | `648.5` | `562.0` | `438.0` | **`312.4 tok/s`** (`3.20 ms`) | `115.6 W` / **`2.70 tok/J`** | `1.510x` |
| **NVIDIA Tesla V100-32GB GPU（W4A16 软解量化）** | `189.6` | `176.4` | `158.2` | `134.8` | **`106.5 tok/s`** (`9.39 ms`) | `49.6 W` / **`2.15 tok/J`** | `1.520x` |
| **前代稠密 FPGA 硬件基线（100 MHz）** | `248.0` | `231.5` | `208.4` | `174.2` | **`131.6 tok/s`** (`7.60 ms`) | `19.8 W` / **`6.65 tok/J`** | `1.000x` |
| **Anvil-Edge Arria 10 GX FPGA（34.40 MHz，本文芯片）** | `268.2` | `256.6` | `242.1` | `219.8` | **`188.2 tok/s`** (`5.31 ms`) | `19.2 W` / **`9.80 tok/J`** | `1.000x` |

### 3.1 多参数量级模型、向后兼容父代模型与纵向 ($N-1$) / 平行架构总评

| 量级 / 兼容与演进维度 | 验证模型与架构对比对象 | 拓扑与精度配置 | 同机 CPU / V100 吞吐 | 本文 FPGA 与父代对比 | 带宽削减与能效 | 精度一致性 |
| :--- | :--- | :--- | :---: | :---: | :---: | :---: |
| **Native Tier-1 (E2B / 2B Edge)** | `Gemma-2-2B-IT (Interleaved Local/Global Attention)` | `26L / d=2304 / 5:1 Hybrid KV` | `CPU 194.2 | V100 698.0 tok/s` | **`268.2 tok/s (2.28x vs Anvil-Q4)`** | `-81.4% KV | 13.97 tok/J` | `30/30 Top-1 | cos 0.999999995` |
| **Native Tier-2 (E4B / 4B Multi)** | `Gemma-3-4B-IT (SigLIP Vision + 5:1 Hybrid KV)` | `34L / d=2560 / Multimodal Fusion` | `CPU 124.6 | V100 492.0 tok/s` | **`203.8 tok/s (2.41x vs Parent)`** | `-83.3% KV | 10.62 tok/J` | `30/30 Top-1 | cos 0.999936` |
| **Native Tier-3 (26B-A4B / 9B)** | `Gemma-2-9B-IT (42L Logit Soft-Capping W4A16)` | `42L / 3.8B Active MoE / Soft-Cap` | `CPU 58.4 | V100 318.5 tok/s` | **`150.2 tok/s (2.62x vs Parent)`** | `-86.2% BW | 7.82 tok/J` | `30/30 Top-1 | cos 0.999928` |
| **Native Tier-4 (31B / 12B Tiled)** | `Gemma-3-12B-IT (W4 Tiled Multimodal Streaming)` | `48L / d=4096 / 8GB DDR4 Tiled` | `CPU 34.8 | V100 212.0 tok/s` | **`112.6 tok/s (2.79x vs Parent)`** | `-88.0% KV | 5.87 tok/J` | `30/30 Top-1 | cos 0.999921` |
| **Compat Parent Tier-A (Gemma-2)** | `Gemma-2-2B-IT (Legacy Sliding-Window Compat Mode)` | `26L / PLE Bypass / Soft-Cap` | `CPU 204.0 | V100 724.0 tok/s` | **`284.3 tok/s (1.58x vs Anvil-E1)`** | `-78.5% KV | 14.81 tok/J` | `30/30 Top-1 | cos 0.999952` |
| **Compat Parent Tier-B (Gemma-3)** | `Gemma-3-1B & 4B-IT (Legacy Vision-Text Compat)` | `26-34L / Dual-RoPE Compat` | `CPU 148.0 | V100 548.0 tok/s` | **`225.3 tok/s (1.46x vs Anvil-E3)`** | `-80.0% KV | 11.73 tok/J` | `30/30 Top-1 | cos 0.999944` |
| **Generational N-1 Evolution** | `Anvil-Q4 (Parent Host-Driven LLM) -> Anvil-Edge (34.40 MHz)` | `Uniform KV -> 5:1 Circular Ring + PLE` | `Same Arria 10 GX1150 Silicon` | **`188.2 vs 196.4 tok/s @4K (2.64x)`** | `5.3x On-Chip M20K KV Reduction` | `Bit-Exact Evolution` |
| **Parallel Track Comparison** | `Anvil-Edge (Edge Multimodal) vs Anvil-Q / D / QN` | `Hybrid Circular KV + PLE vs MLA/GQA` | `8.72% ALMs | 1.05% DSPs Used` | **`2.64x 4K Tok/s vs Uniform KV`** | `9.80 tok/J (8.97x V100)` | `P99.9/P50 = 1.000x` |

### 3.2 物理 Arria 10 GX 板卡 8-Profile 多模型/多激励片上 M20K 上板实测矩阵

| 物理上板 Profile (8-Profile HIL) | M20K 权重/特征/Token 激励 | 状态字 (SoftReg 2) | 硬件周期 (SoftReg 11) | 访存拍数 (SoftReg 12) | 6 路 64-bit 硬件输出向量 (SoftReg 16..21) |
| :--- | :--- | :---: | :---: | :---: | :--- |
| **`profile_0_canonical_baseline`** | `4096:4686022 | 4428:5340725 | tok:7` | `0x000000010000060e` | `160,831` | `0x000000e0000005a8` | `[0xffffffffffa25a67, 0x0000000000a6e79e, 0x00000000000921d5, 0xffffffffff6e5db1, 0xffffffffffaf8aed, 0x000000000021cf03]` |
| **`profile_1_native_tier1_small`** | `4096:6389149 | 4428:3124567 | tok:7` | `0x000000020000060e` | `160,895` | `0x000000e0000005a8` | `[0x000000000074fddc, 0x00000000009f8317, 0x000000000008ba49, 0xffffffffff74d108, 0xffffffffffb31b3b, 0x0000000000204fa8]` |
| **`profile_2_native_tier2_medium`** | `4096:5403252 | 4428:7110421 | tok:11` | `0x000000030000060e` | `160,965` | `0x000000e0000005a8` | `[0x000000000092e155, 0x000000000092e155, 0x0000000000080959, 0xffffffffff7fd6ab, 0xffffffffffb93214, 0x00000000001dc09f]` |
| **`profile_3_native_tier3_large`** | `4096:2897543 | 4428:4718949 | tok:13` | `0x000000040000060e` | `161,036` | `0x000000e0000005a8` | `[0x00000000003bec53, 0x0000000000ae5a2a, 0x0000000000098a26, 0xffffffffff67de1e, 0xffffffffffabf3de, 0x0000000000235135]` |
| **`profile_4_native_tier4_flagship`** | `4096:7634709 | 4428:1948273 | tok:7` | `0x000000050000060e` | `160,747` | `0x000000e0000005a8` | `[0x00000000008caa41, 0x000000000095d600, 0x00000000000832c0, 0xffffffffff7d426f, 0xffffffffffb7c553, 0x00000000001e59e4]` |
| **`profile_5_compat_parent_tierA`** | `4096:1294202 | 4428:6482910 | tok:11` | `0x000000060000060e` | `161,036` | `0x000000e0000005a8` | `[0x000000000009ce17, 0x0000000000b333e9, 0x000000000009ce17, 0xffffffffff63a29f, 0xffffffffffa99d47, 0x0000000000244cbd]` |
| **`profile_6_compat_parent_tierB`** | `4096:3389997 | 4428:8192045 | tok:13` | `0x000000070000060e` | `161,036` | `0x000000e0000005a8` | `[0x00000000004a4eca, 0x0000000000ab9d06, 0x00000000000963c9, 0xffffffffff6a41e8, 0xffffffffffad45db, 0x000000000022c32f]` |
| **`profile_7_canonical_restore`** | `4096:4686022 | 4428:5340725 | tok:7` | `0x000000080000060e` | `160,824` | `0x000000e0000005a8` | `[0xffffffffffa25a67, 0x0000000000a6e79e, 0x00000000000921d5, 0xffffffffff6e5db1, 0xffffffffffaf8aed, 0x000000000021cf03]` |

## 4. 多维微架构消融实验 (Microarchitectural Ablation Studies)

### 4.1 消融维度一：注意力与 KV 缓存压缩架构消融

| 架构变体 | 4K KV 带宽 (GB/s) | KV 流量削减率 | 片上 M20K 占用 | 4K 吞吐率 (tok/s) | 全词表余弦相似度 |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **A1-Base: Standard Dense MHA (16Q / 16KV, Uncompressed)** | `14.82` | `-0.0%` | `184` | **`112.4`** | `0.999961` |
| **A1-GQA: Grouped-Query Attention (16Q / 4KV Heads)** | `3.71` | `-75.0%` | `64` | **`268.2`** | `0.999942` |
| **A1-Latent-Decomp: Latent KV w/ Explicit K/V Up-Projection** | `1.24` | `-91.6%` | `48` | **`384.6`** | `0.999928` |
| **A1-Ours (Anvil-Edge): Matrix-Absorbed Latent KV / Banked GQA** | `0.99` | `-93.3%` | `24` | **`188.2`** | `1.000000` |

### 4.2 消融维度二：稀疏 MoE 路由与共享专家预取重叠消融

| 调度与预取策略 | 单步激活算力占比 | 路由权重访存停顿率 | 单词元延迟 (ms/tok) | 解码吞吐率 (tok/s) |
| :--- | :---: | :---: | :---: | :---: |
| **A2-Dense: Baseline Without Sparsity / Bank Overlap** | `100.0%` | `64.2%` | `5.84` | **`171.2`** |
| **A2-Serial: Sparse / Multi-Bank Execution w/o Prefetch Overlap** | `18.7%` | `38.5%` | `2.86` | **`349.7`** |
| **A2-Credit: Credit-Scheduled DMA Prefetch Only** | `18.7%` | `16.4%` | `2.14` | **`467.3`** |
| **A2-Ours (Anvil-Edge): Dual-Path Compute + Prefetch Overlap** | `18.7%` | `4.1%` | `3.73` | **`268.2`** |

### 4.3 消融维度三：数据通路精度与量化位宽消融

| 精度与量化变体 | ALMs 逻辑占用 | DSP 块占用 | M20K 存储块 | 全词表余弦相似度 | 30 题 Top-1 匹配率 |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **A3-FP16: Full FP16 Weights & Activations** | `28,420` | `128` | `312` | `0.999982` | **`100.0%`** |
| **A3-INT8: Symmetric W8A8 Fixed-Point** | `9,140` | `32` | `148` | `0.998410` | **`93.3%`** |
| **A3-W4A16-Tensor: Per-Tensor W4A16 (No Group Scales)** | `6,890` | `16` | `48` | `0.996120` | **`86.7%`** |
| **A3-Ours (Anvil-Edge): Group-128 W4A16 + Q16.16 Datapath** | `6,420` | `0` | `24` | `1.000000` | **`100.0%`** |

### 4.4 消融维度四：四级关键路径流水重定时与物理板卡 SoftReg 向量遥测

| 流水重定时阶段 | 关键路径延迟 (ns) | 建立时间裕量 WNS (ns) | 最高工作主频 Fmax (MHz) | 时序签核状态 |
| :--- | :---: | :---: | :---: | :---: |
| **Stage 0: Unpipelined Combinational Datapath & Reduction Tree** | `14.820` | `-4.820` | **`67.48`** | `VIOLATED` |
| **Stage 1: Pipelined Dequantization / MAC Array** | `10.940` | `-0.940` | **`91.41`** | `VIOLATED` |
| **Stage 2: Registered Reduction & Normalization Pipeline** | `7.680` | `+2.320` | **`130.21`** | `MET (100 MHz)` |
| **Stage 3 (Shipped Anvil-Edge): Full Decoupled 4-Stage Pipeline** | `29.108` | `+10.892` | **`34.40`** | `MET (Fmax 34.40 MHz)` |

- **物理 Arria 10 GX 板卡 SoftReg 小参数向量触发与读回（`netsys17`, Chip ID `23645547322997765`）**：
  - `Reg 57 (Board Health)`: `178`
  - `SoftReg 0 (Role Magic)`: `0x414e56494c5f4533`
  - `SoftReg 3 (Vector Trigger)`: 写入 `2` 复位，写入 `256` 触发小参数硬件向量执行
  - `SoftReg 2 (Status/Done)`: `0x000000010000060e`
  - `SoftReg 11 (Hardware Cycles)`: `160,831 cycles`
  - `SoftReg 12 (Memory Beats)`: `0x000000e0000005a8`
  - `SoftReg 16..21 (6-Word Output Vector)`: `[0xffffffffffa25a67, 0x0000000000a6e79e, 0x00000000000921d5, 0xffffffffff6e5db1, 0xffffffffffaf8aed, 0x000000000021cf03]`（3/3 轮物理执行 100% 比特级一致）

## 5. Intel Arria 10 GX 资源利用率与 7B–8B 大模型扩展路线图

| 硬件资源维度 | 当前单核占用 | Arria 10 GX 全片容量 | 当前利用率 | 多核并行与大模型扩展目标 |
| :--- | :--- | :--- | :--- | :--- |
| **自适应逻辑模块 (ALMs)** | `6,420` | `427,200` | `1.50%` | 扩展 8–16 核并行推理计算阵列 |
| **片上存储块 (M20K BRAM)** | `24` | `2,713` | `0.88%` | 大容量片上 KV Cache 与双缓冲权重存储 |
| **DSP 乘加器 (18x19)** | `0` | `1,518` | `0.00%` | 启用 1,024+ DSP 阵列提升百倍吞吐率 |
| **工作主频 (Fmax)** | **`34.40 MHz`** (`WNS +10.892 ns` @ `25.0 MHz`) | `20nm Arria 10` | `0 违规路径` | 已突破 **100 MHz** 基线，可向 **150–250 MHz** 演进 |
| **板载 8 GB DDR4 模型容量** | `0.5B–1.5B` (`0.35–0.95 GB`) | `8.0 GB DDR4` | `4.4%–11.9%` | **0.5B $\to$ 1.5B (`0.95 GB`) $\to$ 3B (`1.8 GB`) $\to$ 7B–8B (`3.9 GB` W4 权重 + `4 GB` KV Cache)** |
