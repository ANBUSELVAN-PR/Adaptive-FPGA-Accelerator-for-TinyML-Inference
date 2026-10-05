# Stage 15: DSP48E1 Resource Investigation Report

**Project**: Adaptive MAC Processing Core (AMPC) for TinyML Inference Acceleration on FPGA  
**Target Device**: AMD/Xilinx Zynq-7010 (`xc7z010clg400-1`), Speed Grade `-1`  
**EDA Tool**: AMD Vivado 2026.1 (Build 6511674)  
**Primary Top-Level Entity**: `ampc_top` (`rtl/ampc_top.sv`)  
**Clock Constraint**: 100.000 MHz (10.000 ns period, 50% duty cycle)  
**Date**: September 10, 2026  

---

## 1. Executive Summary & Problem Formulation

The production Stage 14 AMPC architecture contains **30 physical MAC lanes** (AMPC-2: 2, AMPC-4: 4, AMPC-8: 8, AMPC-16: 16) performing signed INT8 $\times$ INT8 multiplication with signed INT32 accumulation. Despite having **80 hard DSP48E1 slices available** on the target Zynq-7010 device, the Stage 14 post-route design utilizes **0 DSP48E1 slices** and **2,971 slice LUTs**.

**Objective of Stage 15 Investigation**:
1. Uncover the exact compiler heuristics and architectural reasons why Vivado infers LUT/carry chains instead of DSP48E1 blocks in `ampc_top`.
2. Construct an experimental DSP-inferred MAC unit (`rtl/experimental/mac_unit_dsp.sv`) and verify functional equivalence against the baseline golden model across extreme boundary conditions and randomized test vectors (`tb/experimental/mac_unit_dsp_tb.sv`).
3. Synthesize an experimental dual-subsystem test top (`rtl/experimental/exp_dsp_eval_top.sv`) on `xc7z010clg400-1` to measure actual resource utilization, timing, and power tradeoffs.
4. Provide a definitive architectural recommendation regarding whether DSP inference should be integrated into the main production baseline.

---

## 2. Section A: Stage 14 Production Baseline Characterization

The table below summarizes the frozen Stage 14 hardware baseline for the complete accelerator top-level:

| Metric | Stage 14 Frozen Baseline | Available Device Resources | Utilization % |
| :--- | :---: | :---: | :---: |
| **Target Device** | `xc7z010clg400-1` | — | — |
| **Slice LUTs** | **2,971** | 17,600 | **16.88%** |
| ├── Logic LUTs | 2,947 | 17,600 | 16.74% |
| └── LUTRAMs | 24 | 6,000 | 0.40% |
| **Slice Registers (FFs)** | **878** | 35,200 | **2.49%** |
| **Occupied Slices** | **931** | 4,400 | **21.16%** |
| **Block RAM (BRAM Tile)** | **0** | 60 | **0.00%** |
| **DSP48E1 Slices** | **0** | 80 | **0.00%** |
| **Worst Negative Slack (WNS)** | **+0.256 ns** | — | Timing MET |
| **Worst Hold Slack (WHS)** | **+0.029 ns** | — | Timing MET |
| **Estimated Max Freq ($F_{\max}$)**| **102.63 MHz** | — | — |
| **Estimated Total Power** | **0.127 W** | — | Vector-less Vivado estimate |
| ├── Dynamic Power (Est.) | 0.037 W (37 mW) | — | 29.1% |
| └── Device Static Power | 0.090 W (90 mW) | — | 70.9% |
| **Full Regression Suite** | **1,036 / 1,036 PASS** | — | **100% PASS** |

### Why Did Vivado Infer 0 DSP Blocks in the Baseline?
Inspection of `rtl/mac_unit.sv` and `rtl/ampc_*.sv` reveals two primary mechanisms:

1. **Sub-Threshold Multiplier Bitwidth (INT8 $\times$ INT8)**:
   - A standard DSP48E1 primitive features an asymmetric $25 \times 18$ signed two's complement multiplier with a 48-bit accumulator.
   - An $8 \times 8$ signed multiplication produces only a 16-bit intermediate product.
   - Vivado's default synthesis strategy (`synth_design -mode out_of_context` with default `-max_dsp` threshold) calculates that an $8 \times 8$ multiplier requires only ~25–35 LUTs. Under standard area-performance optimization heuristics, Vivado considers mapping an 8-bit multiplier to a $25 \times 18$ DSP slice an inefficient allocation of hard silicon primitives unless the designer explicitly requests it.
2. **Combinational Multiplying & Accumulation Separation**:
   - In `mac_unit.sv`, the multiplier and adder are written as purely combinational assign statements (`assign mult_result = data_in * weight; assign acc_out = acc_in + ...;`).
   - The register boundary is located downstream at the AMPC core level (`acc_out_reg` in `ampc_*.sv`), preceded by combinational operand gating (`(en && lane_mask[i]) ? ... : 0`).
   - To infer an internal DSP48E1 accumulator register (`PREG`), Vivado requires registered feedback within the module. Because the temporal accumulation is performed spatially by the Common Accumulator (`accumulator.sv`) rather than locally inside each MAC, Vivado decomposed the multiplication into general slice LUT logic and `CARRY4` chains.

---

## 3. Section B: Experimental DSP Implementation

To rigorously evaluate DSP48E1 inference without compromising the frozen production RTL, an isolated experimental module and test environment was constructed.

### 3.1 Experimental RTL Design (`rtl/experimental/mac_unit_dsp.sv`)
The module implements the identical signed INT8 $\times$ INT8 $\rightarrow$ INT32 MAC mathematical definition, augmented with the Vivado synthesis directive `(* use_dsp = "yes" *)`:

```systemverilog
`timescale 1ns / 1ps

module mac_unit_dsp #(
    parameter int DATA_WIDTH   = 8,   // Input activation bit-width (Signed INT8)
    parameter int WEIGHT_WIDTH = 8,   // Quantized weight bit-width (Signed INT8)
    parameter int ACC_WIDTH    = 32   // Accumulator bit-width (Signed INT32)
) (
    input  logic signed [DATA_WIDTH-1:0]   data_in,  // Signed input activation
    input  logic signed [WEIGHT_WIDTH-1:0] weight,   // Signed weight parameter
    input  logic signed [ACC_WIDTH-1:0]    acc_in,   // Signed accumulator input
    output logic signed [ACC_WIDTH-1:0]    acc_out   // Signed accumulator output
);

    localparam int PROD_WIDTH = DATA_WIDTH + WEIGHT_WIDTH;

    // Direct Vivado synthesis engine to map onto dedicated DSP48E1 primitive
    (* use_dsp = "yes" *) logic signed [PROD_WIDTH-1:0] mult_result;

    assign mult_result = data_in * weight;
    assign acc_out     = acc_in + $signed({{ (ACC_WIDTH - PROD_WIDTH){mult_result[PROD_WIDTH-1]} }, mult_result});

endmodule
```

### 3.2 Experimental Testbench & Co-Simulation Verification (`tb/experimental/mac_unit_dsp_tb.sv`)
A self-checking testbench was developed that instantiates `mac_unit_dsp` side-by-side with the baseline `mac_unit` and an independent mathematical golden model. 

**Verification Scope**:
- Small and medium positive values
- Mixed-sign and negative operands
- Zero data, zero weight, and zero accumulator combinations
- Maximum/minimum signed INT8 extremes:
  - $(+127) \times (+127) = +16,129$
  - $(-128) \times (-128) = +16,384$
  - $(-128) \times (+127) = -16,256$
- Large INT32 accumulator values near positive/negative saturation thresholds ($\pm 2 \times 10^9$)
- 30 randomized 32-bit test vectors

**Simulation Result**:
- Executed via `xsim` v2026.1:
```
==============================================================================
   STAGE 15: EXPERIMENTAL DSP MAC UNIT (mac_unit_dsp) VERIFICATION           
==============================================================================
[PASS] Test 01:          Small positive operands | D=   5, W=  10, Acc=     100 | Result=     150 (Matches LUT & Golden)
...
[PASS] Test 11:  Max positive square (+127*+127) | D= 127, W= 127, Acc=       0 | Result=   16129 (Matches LUT & Golden)
[PASS] Test 12:  Min negative square (-128*-128) | D=-128, W=-128, Acc=       0 | Result=   16384 (Matches LUT & Golden)
...
[PASS] Test 50:                Random Vector #30 | D= -95, W=  70, Acc=1763911709 | Result=1763905059 (Matches LUT & Golden)
==============================================================================
STAGE 15 EXPERIMENTAL MAC TEST SUMMARY: Passed=50, Failed=0
==============================================================================
>>> EXPERIMENTAL DSP MAC VERIFICATION: PASS <<<
```
**Zero functional discrepancies, 0 X/Z states, 100% bit-accurate equivalence with the baseline.**

---

## 4. Section C: Physical Synthesis & Implementation Measurements

To quantify the hardware differences under identical physical routing conditions, a comparative top-level entity (`rtl/experimental/exp_dsp_eval_top.sv`) was constructed and implemented on `xc7z010clg400-1`:
- **Subsystem A**: 4 parallel registered MAC lanes using baseline `mac_unit` (identical to AMPC-4 core).
- **Subsystem B**: 4 parallel registered MAC lanes using experimental `mac_unit_dsp`.

### 4.1 Measured Hardware Utilization Breakdown

From post-route reports (`reports/experimental/post_route_util.rpt` and `reports/experimental/post_route_util_summary.rpt`):

| Design Element | Subsystem A (4-Lane LUT MAC) | Subsystem B (4-Lane DSP MAC) | Delta per 4-Lane Core | Delta per Single MAC Lane |
| :--- | :---: | :---: | :---: | :---: |
| **Logic LUTs** | **308 LUTs** (77 LUTs / lane) | **0 LUTs** (0 LUTs / lane) | **-308 LUTs (-100%)** | **-77 LUTs / lane** |
| **DSP48E1 Blocks** | **0 DSP** | **4 DSP** | **+4 DSP (+100%)** | **+1 DSP48E1 / lane** |
| **Slice Registers (FFs)** | 32 FFs (inside top slice) | 33 FFs (absorbed into DSP) | ~0 FFs | ~0 FFs |
| **Multiplier Implementation** | Fabric LUTs + `CARRY4` | Hard Silicon `DSP48E1` | Shifted to DSP | Shifted to DSP |

### 4.2 Full Accelerator Extrapolation (30 MAC Lanes)
Extrapolating this verified per-lane measurement to the full 30-lane AMPC accelerator:

| Metric | Stage 14 (All-LUT Baseline) | Extrapolated 30-Lane DSP Implementation | Projected Savings / Cost |
| :--- | :---: | :---: | :---: |
| **DSP48E1 Utilization** | **0 / 80 (0.0%)** | **30 / 80 (37.5%)** | Consumes 30 hard DSP blocks |
| **Logic LUT Footprint** | **2,971 LUTs** | **~660 LUTs** | **Saves ~2,310 LUTs (~77.7% reduction)** |
| **Zynq-7010 LUT Utilization** | **16.88%** | **~3.75%** | Frees up slice fabric for custom logic |
| **BRAM Tile Usage** | 0 / 60 | 0 / 60 | Identical (0) |
| **Clock Constraint (100 MHz)** | Met ($WNS = +0.256\text{ ns}$) | Met ($DSP48E1\text{ }T_{\text{clk}} = 2.154\text{ ns}$) | Capable of >200 MHz operation |

---

## 5. Section D: Advantages & Disadvantages Analysis

### 5.1 Advantages of DSP48E1 Inference
1. **Dramatic Logic Fabric Reduction**:
   - Each MAC lane absorbs 77 logic LUTs into a single DSP48E1 slice.
   - For the 30-lane AMPC core, this yields an estimated **~2,310 LUT saving**, reducing total accelerator LUT footprint to under 700 LUTs (~3.75% of the Zynq-7010).
2. **Superior Intrinsic Silicon Speed**:
   - The DSP48E1 hard primitive in the -1 speed grade Zynq-7010 has a minimum clock period of $T_{\text{min}} = 2.154\text{ ns}$, capable of operating at up to **464 MHz** internally.
3. **Silicon Resource Utilization**:
   - The Zynq-7010 contains 80 DSP slices that currently sit completely idle (0% utilization). Using 30 slices utilizes 37.5% of the DSP budget while leaving 50 DSP slices (62.5%) for other signal processing tasks.

### 5.2 Disadvantages & Architectural Caveats
1. **Inefficient Hard Multiplier Utilization (Bit-Waste)**:
   - The DSP48E1 multiplier natively accepts $25 \times 18$ bits. An $8 \times 8$ multiplication uses only 64 of the available 450 bit-multiplier cross-points, leaving substantial multiplier hardware capacity unutilized within each slice.
2. **Fixed Placement Routing Congestion**:
   - DSP blocks are physically located in dedicated columns on the silicon die (e.g., column X0 on Zynq-7010).
   - In contrast, slice LUTs are distributed uniformly across the entire fabric.
   - Concentrating 30 MAC lanes into dedicated DSP columns can increase routing channel congestion for the wide 16-to-1 spatial reduction tree in `accumulator.sv`.
3. **Power Characteristics**:
   - Vector-less statistical power reports indicate that active DSP blocks consume dedicated power rails ($V_{\text{ccint}}$ dynamic current). While LUT dynamic power drops, DSP static and dynamic leakage can offset savings unless lanes are actively clock-gated or power-managed.

---

## 6. Section E: Architectural Recommendation

### Recommendation: MAINTAIN STAGE 14 ALL-LUT BASELINE AS PRIMARY; OFFER DSP48E1 AS A CONFIGURABLE BUILD OPTION

1. **Do NOT Replace Stage 14 Production RTL**:
   - The current Stage 14 baseline achieves **100% timing closure at 100 MHz ($WNS = +0.256\text{ ns}$)** with zero violations.
   - It consumes only **16.88% of device LUTs** (2,971 / 17,600) and **0 DSPs**, leaving **83.12% LUTs** and **100% DSPs** free.
   - It maintains a **100.0% regression pass rate (1,036 / 1,036 tests)** with proven multi-cycle chunking and verified power stability.
2. **Ideal Application for DSP Inference**:
   - DSP inference is recommended for designs that integrate large auxiliary soft-core processors (e.g., MicroBlaze), complex feature extraction logic, or oversized on-chip activation buffers where Slice LUT availability is heavily constrained (< 20% free LUTs).
3. **Preservation**:
   - The experimental implementation (`rtl/experimental/mac_unit_dsp.sv`, `tb/experimental/mac_unit_dsp_tb.sv`, and `rtl/experimental/exp_dsp_eval_top.sv`) remains cleanly sequestered in `rtl/experimental/` without modifying a single line of the frozen Stage 14 production architecture.
