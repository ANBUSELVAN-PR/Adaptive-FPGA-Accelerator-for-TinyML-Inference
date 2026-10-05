# FPGA Implementation & Timing Closure Report: AMPC

## 1. Implementation Overview

The complete Adaptive MAC Processing Core (AMPC) top-level (`ampc_top`) was synthesized, placed, and routed using **AMD Vivado 2026.1** targeting an entry-level **AMD/Xilinx Zynq-7010 SoC FPGA** (`xc7z010clg400-1`, Speed Grade `-1`).

The implementation follows an **Out-of-Context (OOC)** IP core flow (`synth_design -mode out_of_context`) to characterize intrinsic FPGA fabric performance and silicon resource consumption without artificial board-level I/O pin-count bottlenecks.

---

## 2. Target Device & Constraints

- **FPGA Part**: AMD/Xilinx Zynq-7010 (`xc7z010clg400-1`)
- **Package**: CLG400 (400-pin BGA)
- **Speed Grade**: `-1` (slowest commercial grade)
- **Primary Clock Constraint**: 100.000 MHz ($T_{\text{clk}} = 10.000\text{ ns}$, 50% duty cycle)
- **Clock Uncertainty**: 0.200 ns
- **Constraints File**: `constraints/ampc_timing.xdc`

---

## 3. Post-Implementation Resource Utilization

Data extracted from `results/implementation/post_route_util_summary.rpt`:

| Resource Type | Used | Available on Zynq-7010 | Utilization Percentage (%) |
| :--- | :---: | :---: | :---: |
| **Slice LUTs** | **2,971** | 17,600 | **16.88%** |
| ├── LUT as Logic | 2,947 | 17,600 | 16.74% |
| └── LUT as Distributed RAM | 24 | 6,000 | 0.40% |
| **Slice Registers (Flip-Flops)** | **878** | 35,200 | **2.49%** |
| **Occupied Slices** | **931** | 4,400 | **21.16%** |
| **CARRY4 Primitives** | **438** | 4,400 | **9.95%** |
| **DSP48E1 Slices** | **0** | 80 | **0.00%** |
| **Block RAM (RAMB36E1/18E1)** | **0** | 60 | **0.00%** |
| **Unique Control Sets** | 12 | 4,400 | 0.27% |

### Key Resource Observations:
1. **Zero Hard DSP Slices Used**: Vivado mapped all 30 signed INT8 multipliers into LUT logic and fast CARRY4 chains. All 80 physical DSP48E1 slices on the Zynq-7010 remain completely unallocated and available for adjacent system-level processing (e.g., FFTs, image filters, or host DMA).
2. **Zero Block RAM Tiles Used**: Input and weight buffers (64 depth $\times$ 8-bit width) mapped efficiently into 24 distributed LUTRAM cells, preserving all 60 Block RAM tiles.
3. **Compact Footprint**: The entire accelerator consumes only ~17% of LUTs and ~2.5% of registers on the smallest Zynq-7000 family device.

---

## 4. Post-Routing Static Timing Analysis

Data extracted from `results/implementation/post_route_timing.rpt`:

| Timing Metric | Achieved Value | Constraint Target | Margin / Status |
| :--- | :---: | :---: | :---: |
| **Worst Negative Slack (WNS)** | **+0.256 ns** | $\ge 0.000\text{ ns}$ | **MET (+256 ps margin)** |
| **Total Negative Slack (TNS)** | **0.000 ns** | $0.000\text{ ns}$ | **MET (0 failing endpoints / 1,129)** |
| **Worst Hold Slack (WHS)** | **+0.029 ns** | $\ge 0.000\text{ ns}$ | **MET (+29 ps margin)** |
| **Total Hold Slack (THS)** | **0.000 ns** | $0.000\text{ ns}$ | **MET (0 failing endpoints / 1,129)** |
| **Worst Pulse Width Slack (WPWS)** | **+3.750 ns** | $\ge 0.000\text{ ns}$ | **MET** |
| **Total Pulse Width Slack (TPWS)** | **0.000 ns** | $0.000\text{ ns}$ | **MET (0 failing endpoints / 902)** |
| **Operating Frequency ($F_{\text{target}}$)** | **100.000 MHz** | 100.000 MHz | **Timing Closed** |
| **Estimated Max Operating Frequency ($F_{\max}$)** | **102.63 MHz** | — | $F_{\max} = \frac{1}{10.000 - 0.256}\text{ GHz}$ |

---

## 5. Pipeline Optimization & Timing Evolution

### 5.1 Baseline Bottleneck (Stage 13)
During initial baseline implementation, the post-routing WNS was razor-thin at **+0.006 ns** (+6 ps).
- **Critical Path**: From the Adaptive Controller FSM remainder comparator (`rem_q_reg[7]`), through 16-bit remainder classification logic, through high-fanout core enable nets (877 loads), directly into the AMPC-16 multiplier carry chain (`acc_out_reg[4][13]`).
- **Logic Levels**: 11 logic levels within a single 10 ns clock cycle.

### 5.2 Stage 14 Pipeline Decoupling Fix
A single synchronous pipeline register stage was inserted between the Controller FSM and the parallel AMPC cores:
- **Cycle 1**: Controller FSM evaluates remaining workload, determines target core, and synthesizes dynamic lane masks.
- **Cycle 2**: Registered enables and masks drive the parallel MAC array alongside streaming operands.
- **Results**:
  - WNS improved from **+0.006 ns** to **+0.256 ns** (**+42x greater timing margin**).
  - Logic LUT count decreased by 16.6% (from 3,564 to 2,971) due to improved synthesis logic factoring.
  - End-to-end latency increased by exactly 1 clock cycle (+10 ns) while fully maintaining 1-chunk-per-clock-cycle streaming throughput.

---

## 6. Power Estimation Breakdown

Data extracted from `results/implementation/post_route_power.rpt` (Vector-less estimation at 100 MHz, ambient 25.0 °C):

| Subsystem | Power (W) | Power (mW) | Percentage of Total (%) |
| :--- | :---: | :---: | :---: |
| **Dynamic Power** | **0.037 W** | **37 mW** | **29.1%** |
| ├── Clocks | 0.013 W | 13 mW | 10.2% |
| ├── Slice Logic | 0.013 W | 13 mW | 10.2% |
| └── Signals / Routing | 0.011 W | 11 mW | 8.7% |
| **Device Static Power** | **0.090 W** | **90 mW** | **70.9%** |
| **Total Estimated On-Chip Power** | **0.127 W** | **127 mW** | **100.0%** |
| **Junction Temperature** | **26.5 °C** | — | Thermal Margin: 58.5 °C |

---

## 7. Stage 15 DSP Resource Exploration Summary

An exploratory study investigated whether mapping multipliers into dedicated DSP48E1 primitives was advantageous:
- **Root Cause of 0 DSP in Baseline**: Vivado heuristics treat $8 \times 8$ bit multiplication as sub-threshold for $25 \times 18$ DSP48E1 slices, and combinational separation between the multiplier and the spatial accumulator prevented inferring DSP internal feedback registers.
- **Experimental Verification**: An explicit DSP-inferred MAC (`mac_unit_dsp.sv`) was created and verified across 40 testbenches (`tb/experimental/mac_unit_dsp_tb.sv`) and synthesized (`exp_dsp_eval_top.sv`).
- **Architectural Decision**: The LUT-based baseline remains the production standard because:
  1. It consumes 0 DSP slices, leaving 100% of FPGA DSP resources available for host system tasks.
  2. It achieves clean 100 MHz timing closure on the slowest `-1` speed grade.
  3. Total dynamic power is minimal at 37 mW.
