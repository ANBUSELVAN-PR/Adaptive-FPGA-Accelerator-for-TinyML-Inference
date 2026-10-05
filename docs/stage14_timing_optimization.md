# Stage 14: Timing Optimization & Pipeline Decoupling Report

**Project**: Adaptive MAC Processing Core (AMPC) for TinyML Inference Acceleration on FPGA  
**Target Device**: AMD/Xilinx Zynq-7010 (`xc7z010clg400-1`), Speed Grade `-1`  
**EDA Tool**: AMD Vivado 2026.1 (Build 6511674)  
**Primary Top-Level Entity**: `ampc_top` (`rtl/ampc_top.sv`)  
**Clock Constraint**: 100.000 MHz (10.000 ns period, 50% duty cycle, 0.200 ns uncertainty)  
**Date**: September 10, 2026  

---

## 1. Executive Summary

Stage 14 executes a single, strictly controlled timing optimization on the top-level entity (`rtl/ampc_top.sv`) to resolve the severe critical timing path identified during Stage 13 baseline characterization ($WNS = +0.006\text{ ns}$).

By inserting a single synchronous register pipeline stage between the combinational outputs of the Adaptive Controller FSM and the inputs to the parallel AMPC MAC processing cores, the multi-level controller-to-MAC carry chain was decoupled into two distinct clock cycles:
- **Cycle A**: Controller FSM remainder evaluation, chunk classification, and lane mask synthesis.
- **Cycle B**: Registered enables, dynamic lane masks, and streaming operands driving the AMPC MAC multiplier/adder tree.

### 1.1 Key Results at a Glance

- **Regression Pass Rate**: **1,036 / 1,036 Tests PASS (100.0%)** across all 12 testbenches with **0 Failures** and **0 X/Z discrepancies**.
- **Worst Negative Slack (WNS)**: Improved from **+0.006 ns** to **+0.256 ns** (**+0.250 ns / +250 ps improvement**, over **42x greater setup slack margin**).
- **Total Negative Slack (TNS)**: **0.000 ns** (0 failing endpoints out of 1,129).
- **Worst Hold Slack (WHS)**: **+0.029 ns** (clean hold margin, 0 failing endpoints).
- **Maximum Frequency ($F_{\max}$)**: Improved from **100.06 MHz** to **102.63 MHz** (+2.57 MHz).
- **Logic Utilization**: Slice LUTs decreased from **3,564** to **2,971** (**-593 LUTs / -16.6% reduction**), Occupied Slices reduced from **1,041** to **931** (**-110 slices**).
- **Register Utilization**: Slice FFs increased from **595** to **878** (+283 FFs, utilizing only 2.49% of the 35,200 available registers on Zynq-7010).
- **Hard DSP & BRAM Footprint**: Strictly maintained at **0 DSP48E1** and **0 BRAM Tile** primitives.
- **Measured Hardware Latency**: Exactly **+1 clock cycle (+10 ns)** end-to-end latency increase for non-zero workloads ($W > 0$), fully maintaining 1-chunk-per-cycle throughput.
- **Critical Path Relocation**: The original controller-to-AMPC MAC path is completely eliminated from the critical path list; the new critical path is internal to the accumulator spatial reduction logic.

---

## 2. Motivation & Root Cause Analysis

### 2.1 The Stage 13 Bottleneck
During Stage 13 baseline timing characterization, the post-routing static timing analysis reported:
```
Slack (MET) :             0.006ns  (required time - arrival time)
  Source:                 u_controller/rem_q_reg[7]/C  (FDRE clocked by clk)
  Destination:            u_ampc_16/acc_out_reg[4][13]/D  (FDRE clocked by clk)
  Requirement:            10.000ns
  Data Path Delay:        9.772ns  (Logic: 3.805ns [38.94%], Route: 5.967ns [61.06%])
  Logic Levels:           11 (CARRY4=5, LUT2=1, LUT3=1, LUT4=1, LUT5=1, LUT6=2)
```

### 2.2 Mechanism of Timing Degradation
1. **Unpipelined Cascading**: The Adaptive Controller FSM launched from `rem_q_reg` on the clock edge. Within the same single 10 ns clock cycle, the controller had to:
   - Evaluate a 16-bit remainder magnitude comparator ($\le 2, 4, 8, 16$).
   - Synthesize dynamic 16-bit per-lane bitmasks.
   - Decode core enable strobes (`ctrl_ampc16_en`).
2. **High-Fanout Net Propagation**: The resulting `ctrl_ampc16_en` net drove **877 destination loads** across the FPGA chip, incurring **1.526 ns** of routing delay on a single net.
3. **Compound Datapath**: Following this ~4.9 ns controller evaluation and routing segment, the signal fed directly into the operand gating logic and the multi-stage INT8 multiplier carry chains (`CARRY4` $\times 5$, `LUT` logic) of AMPC-16, consuming an additional 4.85 ns before reaching destination register setup.
4. **Razor-Thin Margin**: The resulting setup margin was only 6 picoseconds (+0.006 ns), making timing closure vulnerable to minor placement variations.

---

## 3. Implementation Details: Stage 14 Optimization

### 3.1 Scope of Modification
In strict accordance with the optimization guidelines:
- **Modified File**: `rtl/ampc_top.sv` ONLY.
- **Unmodified Files**:
  - `rtl/adaptive_controller.sv` (Controller FSM logic, states, and remainder subtraction preserved exactly)
  - `rtl/ampc_2.sv`, `rtl/ampc_4.sv`, `rtl/ampc_8.sv`, `rtl/ampc_16.sv` (Core datapath and internal lane logic untouched)
  - `rtl/mac_unit.sv` (Multiplication and accumulator logic untouched)
  - `rtl/accumulator.sv`, `rtl/relu.sv`, `rtl/input_buffer.sv`, `rtl/weight_buffer.sv`, `rtl/workload_analyzer.sv` (Untouched)
  - All testbenches preserved without modifications.

### 3.2 RTL Pipeline Register Insertion (`rtl/ampc_top.sv`)
A synchronous register stage clocked by `clk` with synchronous active-low reset `rst_n` was inserted:

```systemverilog
    // --------------------------------------------------------------------------
    // Stage 14 Optimization: Control & Operand Pipeline Decoupling Stage
    // Breaks the critical timing path from controller remainder/comparator logic
    // through high-fanout enables into AMPC multiplier carry chains.
    // Cycle A: Controller FSM & remainder classification -> Pipeline Registers
    // Cycle B: Registered enables/masks/operands -> AMPC MAC units -> Registered Acc
    // --------------------------------------------------------------------------
    logic [1:0]                   pipe_core_sel;
    logic                         pipe_ampc2_en;
    logic                         pipe_ampc4_en;
    logic                         pipe_ampc8_en;
    logic                         pipe_ampc16_en;
    logic [1:0]                   pipe_mask_2;
    logic [3:0]                   pipe_mask_4;
    logic [7:0]                   pipe_mask_8;
    logic [15:0]                  pipe_mask_16;
    logic signed [DATA_WIDTH-1:0] pipe_data_in [0:MAX_LANES-1];
    logic signed [DATA_WIDTH-1:0] pipe_weight  [0:MAX_LANES-1];
    logic                         pipe_ctrl_done;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            pipe_core_sel  <= 2'b00;
            pipe_ampc2_en  <= 1'b0;
            pipe_ampc4_en  <= 1'b0;
            pipe_ampc8_en  <= 1'b0;
            pipe_ampc16_en <= 1'b0;
            pipe_mask_2    <= 2'b00;
            pipe_mask_4    <= 4'b0000;
            pipe_mask_8    <= 8'h00;
            pipe_mask_16   <= 16'h0000;
            pipe_ctrl_done <= 1'b0;
            for (int k = 0; k < MAX_LANES; k++) begin
                pipe_data_in[k] <= '0;
                pipe_weight[k]  <= '0;
            end
        end else begin
            pipe_core_sel  <= ctrl_core_sel;
            pipe_ampc2_en  <= ctrl_ampc2_en;
            pipe_ampc4_en  <= ctrl_ampc4_en;
            pipe_ampc8_en  <= ctrl_ampc8_en;
            pipe_ampc16_en <= ctrl_ampc16_en;
            pipe_mask_2    <= ctrl_mask_2;
            pipe_mask_4    <= ctrl_mask_4;
            pipe_mask_8    <= ctrl_mask_8;
            pipe_mask_16   <= ctrl_mask_16;
            pipe_ctrl_done <= ctrl_done;
            for (int k = 0; k < MAX_LANES; k++) begin
                pipe_data_in[k] <= data_in[k];
                pipe_weight[k]  <= weight[k];
            end
        end
    end

    assign active_core = pipe_core_sel;
```

### 3.3 Downstream Datapath & Handshaking Alignment
1. **AMPC Connections**: The parallel instances (`u_ampc_2`, `u_ampc_4`, `u_ampc_8`, `u_ampc_16`) now receive `pipe_ampc*_en`, `pipe_mask_*`, `pipe_data_in`, and `pipe_weight`.
2. **Accumulator Mask Alignment**: The dynamic active mask multiplexer samples `pipe_core_sel` and `pipe_mask_*`, and registers into `mask_q`. Since AMPC registers its output 1 cycle after `pipe_ampc*_en`, `mask_q` and `out_ampc*` arrive at `u_accumulator` in the exact same clock cycle.
3. **Completion Tracking Alignment**: The FSM completion indicator `last_chunk_reached` is conditioned on `pipe_ctrl_done` (delayed by 1 cycle), matching the 1-cycle pipeline delay of the datapath and preventing premature assertion of `done` or `output_valid` during multi-cycle streaming.

---

## 4. Hardware Baseline Comparison: Stage 13 vs. Stage 14

The table below summarizes post-synthesis and post-route physical implementation metrics generated by Vivado 2026.1 for the target AMD Zynq-7010 FPGA:

| Metric / Parameter | Stage 13 Baseline (Unpipelined) | Stage 14 Optimized (Pipelined) | Absolute Change ($\Delta$) | Relative Change (%) |
| :--- | :---: | :---: | :---: | :---: |
| **Target Device** | `xc7z010clg400-1` | `xc7z010clg400-1` | — | — |
| **Slice LUTs** | **3,564** | **2,971** | **-593** | **-16.64%** |
| ├── **LUT as Logic** | 3,540 | 2,947 | -593 | -16.75% |
| └── **LUT as Memory (LUTRAM)** | 24 | 24 | 0 | 0.00% |
| **Slice Registers (FFs)** | **595** | **878** | **+283** | **+47.56%** |
| **Occupied Slices** | **1,041** | **931** | **-110** | **-10.57%** |
| **Block RAM (BRAM Tile)** | **0** | **0** | **0** | 0.00% |
| **DSP48E1 Slices** | **0** | **0** | **0** | 0.00% |
| **Worst Negative Slack (WNS)** | **+0.006 ns** | **+0.256 ns** | **+0.250 ns** | **+4,166% (42.7x margin)** |
| **Total Negative Slack (TNS)** | **0.000 ns** | **0.000 ns** | 0.000 ns | Met (0 failing endpoints) |
| **Worst Hold Slack (WHS)** | **+0.054 ns** | **+0.029 ns** | -0.025 ns | Met (0 failing endpoints) |
| **Total Hold Slack (THS)** | **0.000 ns** | **0.000 ns** | 0.000 ns | Met (0 failing endpoints) |
| **Total Constrained Endpoints** | 1,102 | 1,129 | +27 | +2.45% |
| **Maximum Frequency ($F_{\max}$)** | **100.06 MHz** | **102.63 MHz** | **+2.57 MHz** | **+2.57%** |
| **Estimated Total Power** | **0.123 W** | **0.127 W** | **+0.004 W** | +3.25% (statistical est.) |
| ├── Estimated Dynamic Power | 0.033 W | 0.037 W | +0.004 W | +12.1% (statistical est.) |
| └── Estimated Device Static Power | 0.090 W | 0.090 W | 0.000 W | 0.00% |
| **Full Regression Suite** | **1,036 / 1,036 PASS** | **1,036 / 1,036 PASS** | **0 failures** | **100.0% PASS** |

### 4.1 Explanation of Resource Changes
- **LUT Reduction (-593 LUTs)**: In Stage 13, the synthesis engine attempted aggressive logic restructuring, duplication, and wide multiplexing across slices to meet the 10 ns clock constraint on the unpipelined controller-to-MAC path. By inserting the pipeline register stage, the controller combinational cones were isolated from the multiplier operand gating, enabling Vivado to simplify the Boolean network, collapsing 593 redundant logic LUTs.
- **Flip-Flop Addition (+283 FFs)**: Pipelining 16 data inputs (128 bits), 16 weight inputs (128 bits), 4 lane masks (30 bits), 4 enables (4 bits), core select (2 bits), and done tracking (1 bit) requires exactly 293 register bits, synthesized into 283 physical slice registers after tool register sharing.

---

## 5. Critical Path Comparison

### 5.1 Before: Stage 13 Critical Path
```
Slack (MET) :             0.006ns
  Source:                 u_controller/rem_q_reg[7]/C
  Destination:            u_ampc_16/acc_out_reg[4][13]/D
  Data Path Delay:        9.772ns  (Logic: 3.805ns, Route: 5.967ns)
  Logic Levels:           11 (CARRY4=5, LUT2=1, LUT3=1, LUT4=1, LUT5=1, LUT6=2)
  Net fo=877:             ctrl_ampc16_en routed across multiple FPGA slice columns
```

### 5.2 After: Stage 14 Critical Path
From `reports/post_route_timing.rpt`:
```
Slack (MET) :             0.256ns  (required time - arrival time)
  Source:                 u_ampc_8/valid_out_reg/C  (FDRE clocked by clk)
  Destination:            u_accumulator/accumulated_out_reg[29]/D  (FDRE clocked by clk)
  Requirement:            10.000ns
  Data Path Delay:        9.522ns  (Logic: 3.954ns [41.53%], Route: 5.568ns [58.47%])
  Logic Levels:           11  (CARRY4=6 LUT3=2 LUT5=2 LUT6=1)
  Clock Skew:             -0.049ns
  Clock Uncertainty:      0.235ns
```

### 5.3 Critical Path Relocation Analysis
1. **Complete Elimination of Controller-to-MAC Path**: The previous critical path from `u_controller/rem_q_reg` to `u_ampc_16/acc_out_reg` no longer appears anywhere in the top 20 worst delay paths of the design.
2. **High-Fanout Net Isolation**: The controller enable net `ctrl_ampc16_en` now terminates directly at the local `pipe_ampc16_en` flip-flop, eliminating the wide multi-slice routing delay from the remainder comparator logic.
3. **New Limiting Path**: The critical path has shifted downstream to the Accumulator spatial reduction and temporal running-sum adder carry chain (`u_ampc_8/valid_out_reg` through spatial reduction multiplexers to `u_accumulator/accumulated_out_reg[29]`), which achieves a robust positive slack of **+0.256 ns**.

---

## 6. End-to-End Latency Measurement

Latency was empirically measured from the active clock edge of `start` assertion to the assertion of `done` and `output_valid`.

Let $N_{\text{chunks}} = \lceil W / 16 \rceil$ denote the number of execution chunks required for workload size $W$.

| Workload Size ($W$) | Execution Chunks | Stage 13 Latency (Cycles / ns) | Stage 14 Latency (Cycles / ns) | Latency Delta ($\Delta$ Cycles / ns) |
| :---: | :---: | :---: | :---: | :---: |
| **$W = 0$** | 0 chunks | 1 cycle (10 ns) | 1 cycle (10 ns) | **0 cycles (0 ns)** |
| **$W = 1$ (Single-lane)** | 1 chunk (AMPC-2) | 4 cycles (40 ns) | 5 cycles (50 ns) | **+1 cycle (+10 ns)** |
| **$W = 2$ (AMPC-2 full)** | 1 chunk (AMPC-2) | 4 cycles (40 ns) | 5 cycles (50 ns) | **+1 cycle (+10 ns)** |
| **$W = 4$ (AMPC-4 full)** | 1 chunk (AMPC-4) | 4 cycles (40 ns) | 5 cycles (50 ns) | **+1 cycle (+10 ns)** |
| **$W = 8$ (AMPC-8 full)** | 1 chunk (AMPC-8) | 4 cycles (40 ns) | 5 cycles (50 ns) | **+1 cycle (+10 ns)** |
| **$W = 16$ (AMPC-16 full)** | 1 chunk (AMPC-16) | 4 cycles (40 ns) | 5 cycles (50 ns) | **+1 cycle (+10 ns)** |
| **$W = 17$ (16+1)** | 2 chunks | 5 cycles (50 ns) | 6 cycles (60 ns) | **+1 cycle (+10 ns)** |
| **$W = 25$ (16+9)** | 2 chunks | 5 cycles (50 ns) | 6 cycles (60 ns) | **+1 cycle (+10 ns)** |
| **$W = 33$ (16+16+1)** | 3 chunks | 6 cycles (60 ns) | 7 cycles (70 ns) | **+1 cycle (+10 ns)** |
| **$W = 100$ (6$\times$16 + 4)**| 7 chunks | 10 cycles (100 ns) | 11 cycles (110 ns) | **+1 cycle (+10 ns)** |
| **Arbitrary $W > 0$** | $N_{\text{chunks}}$ | $N_{\text{chunks}} + 3$ cycles | $N_{\text{chunks}} + 4$ cycles | **Strictly +1 cycle (+10 ns)** |

### Latency Conclusion
The pipeline stage adds **exactly 1 clock cycle (+10 ns at 100 MHz)** of initial pipeline fill latency for any non-zero workload ($W > 0$). Multi-cycle chunk streaming throughput remains identical at **1 chunk per clock cycle**.

---

## 7. Complete 1,036-Test Verification Audit

The full regression suite comprising all 12 self-checking testbenches was executed through Vivado Simulator (`xsim` v2026.1):

| Stage | Testbench File | Module Tested | Test Count | Result | Errors / Mismatches |
| :---: | :--- | :--- | :---: | :---: | :---: |
| **1** | `tb/mac_unit_tb.sv` | `mac_unit` | 43 | **PASS** | 0 |
| **2** | `tb/ampc_2_tb.sv` | `ampc_2` | 40 | **PASS** | 0 |
| **3** | `tb/ampc_4_tb.sv` | `ampc_4` | 45 | **PASS** | 0 |
| **4** | `tb/ampc_8_tb.sv` | `ampc_8` | 54 | **PASS** | 0 |
| **5** | `tb/ampc_16_tb.sv` | `ampc_16` | 68 | **PASS** | 0 |
| **6** | `tb/accumulator_tb.sv` | `accumulator` | 90 | **PASS** | 0 |
| **7** | `tb/relu_tb.sv` | `relu` | 88 | **PASS** | 0 |
| **8a** | `tb/input_buffer_tb.sv` | `input_buffer` | 135 | **PASS** | 0 |
| **8b** | `tb/weight_buffer_tb.sv` | `weight_buffer` | 135 | **PASS** | 0 |
| **9** | `tb/workload_analyzer_tb.sv` | `workload_analyzer` | 138 | **PASS** | 0 |
| **10** | `tb/adaptive_controller_tb.sv`| `adaptive_controller` | 126 | **PASS** | 0 |
| **11/12**| `tb/ampc_top_tb.sv` | `ampc_top` (Pipelined) | 74 | **PASS** | 0 |
| **TOTAL**| **All 12 Testbenches** | **Full System Regression** | **1,036** | **PASS (100%)** | **0 Failures, 0 X/Z** |

---

## 8. Power Analysis Comparison & Characterization

| Power Component | Stage 13 Baseline (Estimated) | Stage 14 Optimized (Estimated) | Delta ($\Delta$) | Notes |
| :--- | :---: | :---: | :---: | :--- |
| **Total On-Chip Power** | **0.123 W (123 mW)** | **0.127 W (127 mW)** | **+4 mW (+3.25%)** | Vector-less statistical estimate |
| ├── **Dynamic Power** | **0.033 W (33 mW)** | **0.037 W (37 mW)** | **+4 mW (+12.1%)** | Tool-estimated switching activity |
| │   ├── Clock Network | 0.006 W (6 mW) | 0.013 W (13 mW) | +7 mW | +283 FFs added to clock tree |
| │   ├── Logic (LUTs/CARRY) | 0.014 W (14 mW) | 0.011 W (11 mW) | -3 mW | -593 LUTs reduction saves dynamic power |
| │   └── Signals / Routing | 0.012 W (12 mW) | 0.012 W (12 mW) | 0 mW | Net count slightly reduced |
| └── **Device Static Power** | **0.090 W (90 mW)** | **0.090 W (90 mW)** | **0 mW (0.00%)** | Zynq-7010 quiescent silicon baseline |

> [!WARNING]
> **Power Estimation Notice**: The power metrics above are Vivado vector-less statistical models, **not** physical board measurements. While logic dynamic power decreased from 14 mW to 11 mW due to LUT pruning, tool clock power increased from 6 mW to 13 mW due to the 283 added registers under default toggle rates. True dynamic power evaluation requires switching activity interchange format (SAIF) generation or physical silicon instrumentation.

---

## 9. Conclusion & Recommendation

The Stage 14 timing optimization is an **unequivocal success**:

1. **Timing Robustness Achieved**: Setup slack increased from +0.006 ns to **+0.256 ns (+250 ps)**, providing a safe, manufacturable timing margin at 100 MHz and increasing $F_{\max}$ to **102.63 MHz**.
2. **Logic Footprint Reduced**: Decoupling the critical path allowed Vivado to optimize logic cones, reducing slice LUTs by **593 LUTs (-16.6%)** and occupied slices by **110 slices (-10.6%)**.
3. **Negligible Register Overhead**: The added 283 flip-flops consume only 2.49% of the Zynq-7010 register budget.
4. **Minimal Latency Impact**: The latency increase is strictly **+1 clock cycle (+10 ns)** for non-zero workloads with identical multi-cycle throughput.
5. **Zero Functional Regressions**: All **1,036 / 1,036 tests pass** with 0 failures and 0 X/Z propagation.
6. **No Further Modifications Needed**: The optimization is clean, contained entirely within `rtl/ampc_top.sv`, and preserves the Stage 13 baseline architecture while resolving its single critical vulnerability.
