# Anvil-E2 Technical Data Sheet & Hardware Verification Report

- **Author**: Sufeng Guo (`v-sufengguo`)
- **Date**: 2026-10-20 (UTC+8)
- **L1 RTL Timing Lint**: `passed` (`lut_clock_gate_hazards = 0`)
- **L2 Quartus Prime 17.1 TimeQuest STA (Arria 10 `10AX115N3F40E2SG`)**: `passed` (`Setup WNS = +4.114 ns`, `Hold WNS = +0.071 ns`, `Fmax = 27.87 MHz`, `clk_div[1]` on Global Clock `CLKCTRL_2J_G_I2`)
- **L3 Physical Arria 10 FPGA HIL (`netsys17`, Chip ID `23645547322997765`)**: `passed` (3/3 deterministic runs, `851,257` cycles @ 25 MHz = `34.05 ms`, `writes = 2,126`, `reads = 44,764`, 0-bit error across all 6 Q8.24 embedding dimensions, RPD SHA256 `8a7e768c13fb...`)

[Product report (PDF)](REPORT.pdf) | [LaTeX source](REPORT.tex) | [English engineering journey](.vulcan/engineering/JOURNEY.md) | [Chinese companion](.vulcan/engineering/JOURNEY.zh-CN.md)

## Illustrated Report Pages (TikZ / pgfplots Diagrams & Hardware Evidence)

### Page 1
![Report Page 1](report_figures/page-01.png)

### Page 2
![Report Page 2](report_figures/page-02.png)

### Page 3
![Report Page 3](report_figures/page-03.png)

### Page 4
![Report Page 4](report_figures/page-04.png)

### Page 5
![Report Page 5](report_figures/page-05.png)

### Page 6
![Report Page 6](report_figures/page-06.png)

### Page 7
![Report Page 7](report_figures/page-07.png)

### Page 8
![Report Page 8](report_figures/page-08.png)

### Page 9
![Report Page 9](report_figures/page-09.png)

### Page 10
![Report Page 10](report_figures/page-10.png)
