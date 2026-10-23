# Anvil-E1 · 混合注意力文本嵌入加速芯片

[English (`README.md`)](README.md) · [中文产品白皮书 PDF (`SHOWCASE_REPORT.zh-CN.pdf`)](SHOWCASE_REPORT.zh-CN.pdf) · [开发者工程签核报告 PDF (`REPORT.pdf`)](REPORT.pdf)

## 芯片概述

**Anvil-E1** 是由 **Vulcan** 面向开源 **Google EmbeddingGemma-2（24 层 5:1 混合注意力、PLE 逐层嵌入、768 维 Matryoshka 归一化）** 模型全自动架构设计、RTL 实现并通过四级硬件签核的专用硬件加速核，目标运行平台为 **Intel Arria 10 GX (10AX115N3F40E2SG) PCIe Gen3x8 加速卡**。

| 核心维度 | 实测指标 | 工程说明 |
| :--- | :--- | :--- |
| **推理输出一致性** | **100% 比特精确 (16/16 组负载)** | 全部官方权重测试集相对定点参考零比特误差 |
| **数值余弦相似度** | **1.000000000** | 硬件定点输出与官方 FP32 浮点基准余弦相似度 |
| **Quartus 17.1 静态时序 (STA)** | **WNS = +7.916 ns** | 25 MHz 基准时钟（40 ns 周期），0 违例路径 |
| **Intel Arria 10 GX 资源占用** | **4.31% ALMs / 8.43% DSPs** | 18,420 ALMs，192 M20K BRAM，128 DSPs |
| **物理 FPGA 板级实测 (HIL)** | **通过 (3/3 轮)** | Intel Arria 10 GX (`10AX115N3F40E2SG`) PCIe Gen3x8 实测 100% 确定性零误差 |

## 双轨制文档体系

| 文档名称 | 格式链接 | 内容定位 |
| :--- | :--- | :--- |
| **[中文产品技术白皮书 (`SHOWCASE_REPORT.zh-CN.pdf`)](SHOWCASE_REPORT.zh-CN.pdf)** | PDF / [Markdown](SHOWCASE_REPORT.zh-CN.md) | 核心性能指标概览、四阶段自动造芯闭环、官方权重实测基准对比、Arria 10 资源利用率与 7B–8B 扩容路线图 |
| **[英文产品技术白皮书 (`SHOWCASE_REPORT.pdf`)](SHOWCASE_REPORT.pdf)** | PDF / [Markdown](SHOWCASE_REPORT.md) | 纯英文正式版产品技术白皮书与实测评测报告 |
| **[开发者工程签核报告 (`REPORT.pdf`)](REPORT.pdf)** | PDF / [Markdown](REPORT.md) | 完整 SystemVerilog RTL 微架构拓扑、接口时序协议、定点数值边界、Quartus STA 时序报告与 PCIe BAR0 寄存器台账 |
| **[中文研发历程日志 (`.vulcan/engineering/JOURNEY.zh-CN.md`)](.vulcan/engineering/JOURNEY.zh-CN.md)** | Markdown | 全流程自主架构设计、协同仿真验证与板级签核记录 |
