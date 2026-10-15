# Anvil-E1 · Google EmbeddingGemma-2 Hardware Accelerator (Text-Only Edition)

**Anvil-E1** is a synthesizable SystemVerilog hardware accelerator for [`google/embeddinggemma-2`](https://huggingface.co/google/embeddinggemma-2), autonomously architected, implemented, synthesized, and co-verified against official HuggingFace weights by **Vulcan 0.8**.

## Autonomous Engineering Timeline & Metrics

| Metric | Phase 1 (Zero-to-RTL & Synthesis) | Phase 2 (Official HF Weights & Co-Sim) | Combined Total |
| --- | --- | --- | --- |
| **Wall-Clock Duration** | **2h 17m 48s** (`8,267.6s`) | **59m 37s** (`3,576.9s`) | **3h 17m 25s** (`11,844.5s`) |
| **Autonomous Steps** | 45 steps | 31 steps | 76 steps |
| **RTL Footprint** | 12 modules (`anvil_e1_*.sv`) | +1 wrapper (`anvil_e_top.sv`) + Q48 RMSNorm refinement (`1,704` lines SV total) | 13 synthesizable `.sv` modules |
| **Verification Gates** | `architecture`, `behavior`, `synthesis` (`passed`) | `architecture`, `functional`, `sensitivity`, `synthesis` (`passed`) | All gates `passed` |

## Official HuggingFace `google/embeddinggemma-2` Hardware Co-Simulation Summary

Across all **16 official-weight evaluation jobs** (4 sequence lengths/mask patterns $\times$ 4 Matryoshka output dimensions $D \in \{6, 4, 2, 1\}$):

- **Checkpoint SHA-256**: `3a310d7733a28f533b611eb7525f597303980c2ab2f890487a9a1fcbf0366bfb` (`39` `language_model.*` BF16 tensors, `11,266` verified coordinates)
- **Hardware RTL vs Q8.24 Integer Reference**: **`0` exact word mismatches** (`100%` bit-exact across all 16 jobs)
- **Hardware RTL vs Official FP32/BF16 Software Model**:
  - **Minimum Cosine Similarity**: **`0.9999999998517652`** (acceptance threshold $\ge 0.999$)
  - **Maximum Absolute Error**: **`1.204e-05`** (acceptance threshold $\le 0.002$)
  - **Mean Absolute Error**: **`6.884e-06`**
  - **RMSE**: **`8.601e-06`**
  - **L2-Norm Error**: **`7.761e-08`**
- **Cycle-Accurate Hardware Latency**: `22,613 – 22,654` cycles for 1-token jobs; `220,232 – 220,274` cycles (`~27,530` cycles/token) for 8-token jobs (`1,447,660` total clock cycles simulated in `45.58s` wall-clock).

## Quick-Start Live Co-Simulation Demo

Every function in this demo (`load_official`, `forward_fp32`, `compile_forward`, `compare_trace`, and `negative_control`) was autonomously authored by Vulcan in Phase 2 (`tests/official.py`, `tests/official_fp32.py`, `tests/behavior.py`):

```bash
# 1. Live compile (iverilog) + cycle-accurate RTL simulation (vvp) on Job 0 (~2.5s)
python3 demo_gemma2_rtl.py --mode quick

# 2. Inspect all 16 official-weight jobs from the recorded Phase 2 verification evidence
python3 demo_gemma2_rtl.py --mode from-evidence

# 3. Re-run full 16-job cycle-accurate RTL simulation from scratch (~45s)
python3 demo_gemma2_rtl.py --mode full
```

## Directory Layout

- [`rtl/`](rtl/) — 13 synthesizable SystemVerilog modules (`anvil_e_top.sv`, `anvil_e1_top.sv`, `anvil_e1_controller.sv`, `anvil_e1_sequencer.sv`, `anvil_e1_attention.sv`, `anvil_e1_rope.sv`, `anvil_e1_norm.sv`, `anvil_e1_nonlinear.sv`, `anvil_e1_matvec.sv`, `anvil_e1_mac.sv`, `anvil_e1_pool.sv`, `anvil_e1_address.sv`, `anvil_e1_memory.sv`)
- [`design/`](design/) — [`ARCHITECTURE.md`](design/ARCHITECTURE.md), [`OFFICIAL_WEIGHTS_EVALUATION.md`](design/OFFICIAL_WEIGHTS_EVALUATION.md), and [`pack_model.py`](design/pack_model.py)
- [`tests/`](tests/) — Autonomous verification harness (`verify.py`, `official.py`, `official_fp32.py`, `behavior.py`, `model.py`, `synthesis.py`, and SystemVerilog testbenches `forward.sv`, `norm.sv`, `primitives.sv`, `addresses.sv`)
- [`evidence/verification/functional/official_weights_comparison.json`](evidence/verification/functional/official_weights_comparison.json) — Full 16-job software-vs-hardware comparison report
