<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="brand/logo-dark.svg">
    <img src="brand/logo.svg" width="480" alt="Vulcan">
  </picture>
</p>

<h1 align="center">Anvil-E · 把嵌入模型，锻造成芯片。</h1>

<p align="center">
  开源嵌入加速 RTL 设计，展示真实工程成果。
  <br>
  <a href="https://ahappend.github.io/vulcan/">访问官网</a>
  · <a href="https://github.com/aHappend/vulcan-showcase">Vulcan 作品集</a>
  · <a href="README.md">English</a>
  · <a href="anvil-e1/">Anvil-E1 交付包</a>
  · <a href="anvil-e2/">Anvil-E2 交付包</a>
  · <a href="brand/">品牌素材</a>
</p>

**Anvil** 是基于 Vulcan 研发的 AI 加速芯片家族。**Anvil-E** 是家族中的**嵌入（Embedding）专用芯片系列**，
将开源嵌入模型规范转化为可综合 SystemVerilog RTL、自检验证套件与可复现的工程交付包。

## 系列路线图

| 代际 | 芯片型号 | 目标模型与范围 | 自主研发总耗时 | 当前状态 |
| --- | --- | --- | --- | --- |
| **第一代** | **[Anvil-E1](anvil-e1/)** | [Google EmbeddingGemma-2 (`google/embeddinggemma-2`)](https://huggingface.co/google/embeddinggemma-2) · 纯文本版（5:1 滑动窗口/全局 GQA 混合注意力、PLE 逐层嵌入、512d → 768d 投影、掩码均值池化与 Matryoshka L2 归一化） | **总计 3 小时 17 分 25 秒**（一阶段 RTL 生成 `2h 17m 48s` + 二阶段 HF 官方权重软硬联调 `59m 37s`） | 已完成并验证 — [产品交付报告 (`REPORT.pdf`)](anvil-e1/REPORT.pdf) 与一键联调 Demo 已发布 |
| **第二代** | **[Anvil-E2](anvil-e2/)** | [Google EmbeddingGemma-2 (`google/embeddinggemma-2`)](https://huggingface.co/google/embeddinggemma-2) · 视觉 + 文本多模态版（16 层 `gemma4_vision` 视觉编码塔、3×3 空间池化 280 软 Token、768d → 512d 跨模态投影及 24 层 5:1 混合主干） | **5 小时 19 分 57 秒**（`Step 79 · recovery_feedback`，`20` 个 RTL 模块 / `3544` 行） | In Progress — Autonomous Vision+Text Architecture & RTL Generation by Vulcan 0.8 |
| **第三代** | **Anvil-E3** | Google EmbeddingGemma-2 · 音频 + 视觉 + 文本统一嵌入加速引擎 | — | 规划中 |

## Anvil-E2 · 第二代（视觉 + 文本多模态版）

`Anvil-E2` 将 `Anvil-E` 系列推进至 HuggingFace [`google/embeddinggemma-2`](https://huggingface.co/google/embeddinggemma-2)
的**视觉 + 文本多模态嵌入管线**，由升级后的 **Vulcan 0.8** 自主完成架构设计、模块化 RTL 编写与黑盒独立验证：

| 计算阶段 | 模型权威配置（`google/embeddinggemma-2`） | 硬件工程重点 |
| --- | --- | --- |
| **视觉 Patch 与二维位置编码（`vision_tower.patch_embedder`）** | `patch_size = 16`（`input_proj [768, 768]`），`position_embedding_table [2, 10240, 768]`，二维 `axial` RoPE（`rope_theta = 100.0`） | 带截断范围的 Patch 线性投影、二维坐标位置表查表与轴向旋转位置编码 |
| **16 层视觉编码塔（`vision_tower.encoder`）** | 16 层，`hidden_size = 768`，`intermediate_size = 3072`（`gelu_pytorch_tanh`），12 头注意力（`head_dim = 64`，含 `q_norm`/`k_norm`），每层 4 处 RMSNorm | 参数化视觉 Transformer 数据通路与激活/权重量化钳位支持 |
| **空间池化与跨模态投影（`embed_vision`）** | `pooling_kernel_size = 3` 空间池化（每图输出 `280` 个视觉软 Token）+ `embedding_projection [512, 768]` | 3×3 空间软 Token 汇聚、`768 → 512` 维跨模态投影及 `BOI`/`IMAGE`/`EOI` 多模态序列融合 |
| **多模态混合主干与归一化（`0_Transformer` + `1_Pooling` + `2_Normalize`）** | 24 层 5:1 滑动窗口/全局混合注意力（`512d` + PLE `512d`）、`512 → 768` 投影、掩码均值池化与 Matryoshka L2 归一化（`768 / 512 / 256 / 128`） | 视觉软 Token 与文本 Token 统一注意力调度、掩码池化与倒数平方根归一化 |

- **当前工程状态**：`In Progress — Autonomous Vision+Text Architecture & RTL Generation by Vulcan 0.8`（`Step 79 · recovery_feedback`，`20` 个 RTL 模块 / `3544` 行，最近更新：`2026-10-15 20:31:46 UTC+8`）
- **官方多模态配置快照**：[`anvil-e2/hf_embeddinggemma2_vision_spec/`](anvil-e2/hf_embeddinggemma2_vision_spec/)
- **交付包目录**：[`anvil-e2/`](anvil-e2/)（`rtl/`、`design/`、`tests/`）

## Anvil-E1 · 第一代（纯文本版 — HuggingFace 官方权重软硬联调收官）

`Anvil-E1` 由 **Vulcan** 分两个阶段全自主完成从零设计、RTL 综合与 HuggingFace 官方权重软硬联调，**总用时 3 小时 17 分 25 秒**：

| 阶段 | 工程范围 | 自主步数 | 实际耗时 | 核心产出与验收指标 |
| --- | --- | --- | --- | --- |
| **第一阶段（从零架构设计 + RTL 实现 + 逻辑综合）** | 架构规约、12 个可综合 SystemVerilog 模块（`anvil_e1_*.sv`）、Q8.24 权重打包器、自检 Testbench 与 Yosys 综合（`A.ys` / `B.ys`） | 45 步 | **2 小时 17 分 48 秒**（`8,267.6s`） | `accepted` — Yosys 零 Latch/结构告警，413 张量打包与 9 随机种子多配置仿真全通 |
| **第二阶段（官方 `google/embeddinggemma-2` 权重接入与软硬联调）** | 接入 HuggingFace 官方 `google/embeddinggemma-2` Safetensors 权重切片（`39` 个 `language_model.*` BF16 张量）、Q48 RMSNorm $\epsilon$ 边界精化（`EPSILON_Q48 = 96'd281474977`）、16 组官方作业软件 FP32 vs 硬件 RTL（`iverilog + vvp`）周期精确协同仿真 | 31 步 | **59 分 37 秒**（`3,576.9s`） | 四项门禁（`architecture`、`functional`、`sensitivity`、`synthesis`）**全部 `passed`**；**定点参考 `0` 比特误差**，**相对官方 FP32 最小余弦相似度 `0.99999999985`**，**最大绝对误差 `1.20e-5`** |

### 一键运行 Gemma-2 软硬同跑联调 Demo

```bash
python3 anvil-e1/demo_gemma2_rtl.py --mode quick
python3 anvil-e1/demo_gemma2_rtl.py --mode from-evidence
```

- **工程状态**：`Completed & Verified — Phase 1 + Phase 2 Official HuggingFace Weights Parity Published`
- **产品交付报告**：[`anvil-e1/REPORT.pdf`](anvil-e1/REPORT.pdf)
- **官方权重与评测报告**：[`anvil-e1/evidence/verification/functional/official_weights_comparison.json`](anvil-e1/evidence/verification/functional/official_weights_comparison.json)
- **交付包目录**：[`anvil-e1/`](anvil-e1/)（13 个可综合 SystemVerilog 模块、架构与官方权重评测文档、自检验证套件与一键联调 Demo）

## 许可

公开的代码、文档与视觉素材采用 [MIT License](LICENSE)。
