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
  · <a href="brand/">品牌素材</a>
</p>

**Anvil** 是基于 Vulcan 研发的 AI 加速芯片家族。**Anvil-E** 是家族中的**嵌入（Embedding）专用芯片系列**，
将开源嵌入模型规范转化为可综合 SystemVerilog RTL、自检验证套件与可复现的工程交付包。

## 系列路线图

| 代际 | 芯片型号 | 目标模型与范围 | 当前状态 |
| --- | --- | --- | --- |
| **第一代** | **[Anvil-E1](anvil-e1/)** | [Google EmbeddingGemma-2 (`google/embeddinggemma-2`)](https://huggingface.co/google/embeddinggemma-2) · 纯文本版（24 层 5:1 滑动窗口/全局注意力混排、512d → 768d 投影、均值池化与 L2 归一化） | In Progress — Autonomous Architecture & RTL Generation by Vulcan 0.7 |
| **第二代** | **Anvil-E2** | Google EmbeddingGemma-2 · 视觉 + 文本多模态前端扩展 | 规划中 |
| **第三代** | **Anvil-E3** | Google EmbeddingGemma-2 · 音频 + 视觉 + 文本统一嵌入加速引擎 | 规划中 |

## Anvil-E1 · 第一代（纯文本版）

`Anvil-E1` 严格对齐 HuggingFace 上的 [`google/embeddinggemma-2`](https://huggingface.co/google/embeddinggemma-2)
纯文本嵌入管线（`embedding_gemma2_text` + `1_Pooling` + `2_Normalize`），
由 Vulcan 0.7 从纯文字需求与官方模型配置出发，自主完成架构拆解、RTL 实现与验证签核：

| 计算阶段 | 模型权威配置（`google/embeddinggemma-2`） | 硬件工程重点 |
| --- | --- | --- |
| **主干网络（`0_Transformer`）** | 24 层，`hidden_size = 512`，`hidden_size_per_layer_input = 512`（PLE 逐层输入注入），`intermediate_size = 2048`（`gelu_pytorch_tanh`），词表 `262,144` | 参数化数据通路、RMSNorm、RoPE、GeGLU/GELU-tanh FFN 及可扩展的多模态 Token 流入口 |
| **5:1 混合注意力** | 20 层滑动窗口注意力（`window = 512`，4Q:2KV GQA，`head_dim = 256`，`rope_theta = 10,000`）+ 4 层全局注意力（第 5/11/17/23 层，4Q:1KV MQA，`head_dim = 512`，`rope_theta = 1,000,000`） | 局部/全局混合注意力调度与 KV 寻址 |
| **投影与池化（`1_Pooling`）** | 线性投影 `512 → 768`（`embedding_dim = 768`）及带掩码均值池化（`pooling_mode = "mean"`） | 有效 Token 掩码累加与倒数长度缩放 |
| **归一化输出（`2_Normalize`）** | L2 单位向量归一化，支持 Matryoshka（`768 / 512 / 256 / 128` 维）截断输出 | 硬件倒数平方根 L2 归一化与可配置维度输出 |

- **当前工程状态**：`In Progress — Autonomous Architecture & RTL Generation by Vulcan 0.7`（最近更新：`2026-10-15 07:31:07 UTC+8`）
- **官方模型配置快照**：[`anvil-e1/hf_embeddinggemma2_spec/`](anvil-e1/hf_embeddinggemma2_spec/)
- **交付包目录**：[`anvil-e1/`](anvil-e1/)（`rtl/`、`tb/`、`docs/`、`reports/`）

## 交付包标准

与 Vulcan 开源硬件系列保持一致，公开交付包包含：

- 已验收的可综合 RTL、接口与架构说明，以及集成指南。
- 可复现的验证源码、参数配置、工具版本和命令，以及仿真与通用综合证据。
- 明确的范围边界：所列结果来自仿真及明确注明的通用综合，不代表芯片实测或物理签核。闭源框架代码、提示词、后端会话、凭据、私有经验胶囊和内部操作记录不属于公开交付包。

## 探索更多

- **[Vulcan 官网](https://ahappend.github.io/vulcan/)**：了解产品。
- **[Vulcan 开源作品集](https://github.com/aHappend/vulcan-showcase)**：浏览 Vulcan 已发布的精选 RTL 设计与工程成果。
- **[Anvil-E1 交付包](anvil-e1/)**：查看模型配置、RTL 源码、验证测试与进度记录。
- **[视觉素材](brand/)**：原版 Logo、品牌图标与应用图标。

## 许可

公开的代码、文档与视觉素材采用 [MIT License](LICENSE)。
