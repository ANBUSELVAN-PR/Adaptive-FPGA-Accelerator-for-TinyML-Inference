# Architecture Notes: Adaptive MAC Processing Core (AMPC) for TinyML Inference

**Target Device**: AMD/Xilinx Zynq-7010 (`xc7z010clg400-1`)  
**Design Environment**: Vivado 2026.1  
**HDL Standard**: Synthesizable SystemVerilog (`.sv`)  
**Status**: Stage 10 (Adaptive Controller / FSM) Verified (126/126 PASS)

---

## 1. Project Objective
The objective of this project is to design, verify, and implement an FPGA-based hardware accelerator architecture for **TinyML inference workloads**.
The architecture introduces the **Adaptive MAC Processing Core (AMPC)** paradigm, providing dynamic, workload-dependent parallelism to accelerate vector dot-products and matrix-vector multiplications without forcing every workload to activate a fixed, monolithic MAC array.

---

## 2. AMPC Concept & Architectural Principles
In TinyML layers (e.g. depthwise separable convolutions, dense layers, quantized linear projections), the number of MAC operations required varies widely across layers.
The architecture provides heterogeneous compute granularities:
- **AMPC-2**: 2 parallel MAC units (minimal power/switching for tiny workloads)
- **AMPC-4**: 4 parallel MAC units
- **AMPC-8**: 8 parallel MAC units
- **AMPC-16**: 16 parallel MAC units (maximum parallel throughput)

### Important Clarifications:
- **Resource Reality**: Unused MAC cores do NOT physically disappear from the FPGA fabric; all instantiated cores consume physical FPGA resources (LUTs, FFs, DSP48E1 slices).
- **Evaluation Criteria**: The architecture is evaluated on **workload-dependent activation, switching activity reduction, latency, throughput, DSP/LUT utilization, and scalability**, not fictitious silicon removal.

---

## 3. Numerical Representation & Data Path
- **Input Activations ($x_i$)**: Signed 8-bit integers (`INT8`, range $[-128, +127]$)
- **Weights ($w_i$)**: Signed 8-bit integers (`INT8`, range $[-128, +127]$)
- **Accumulator ($\text{acc}$)**: Signed 32-bit integers (`INT32`, range $[-2^{31}, +2^{31}-1]$)
- **Fundamental MAC Equation**:
  $$\text{acc\_out} = (x_i \times w_i) + \text{acc\_in}$$
- **Sign Extension**: The $8 \times 8$ signed multiplication produces a 16-bit signed product (range $[-16256, +16384]$). This 16-bit signed product is explicitly sign-extended to 32 bits before addition with the 32-bit accumulator.

---

## 4. Stage 1: MAC Unit (`mac_unit.sv`)
- **Type**: Pure combinational signed MAC unit.
- **Port Interface**:
  - `input  logic signed [DATA_WIDTH-1:0]   data_in`  (default: 8-bit)
  - `input  logic signed [WEIGHT_WIDTH-1:0] weight`   (default: 8-bit)
  - `input  logic signed [ACC_WIDTH-1:0]    acc_in`   (default: 32-bit)
  - `output logic signed [ACC_WIDTH-1:0]    acc_out`  (default: 32-bit)
- **Mapping**: Directly synthesizable into Xilinx 7-series DSP48E1 slices ($25 \times 18$ multiplier + 48-bit accumulator).
- **Status**: Verified with 43/43 tests passing in Vivado 2026.1.

---

## 5. Stage 2: AMPC-2 (`ampc_2.sv`)
- **Type**: 2-Lane Parallel Adaptive MAC Processing Core.
- **Architectural Enhancements**:
  - **Dynamic Lane Masking (`lane_mask[1:0]`)**: Enables individual activation or masking of Lane 0 and Lane 1 (explicitly driven, no default port value).
  - **Operand Gating**: When a lane is masked or disabled, operands are forced to zero, preventing dynamic power waste from toggling and guaranteeing that $(0 \times 0) + \text{acc\_in}[i] = \text{acc\_in}[i]$ (accumulator preserved without introducing garbage data).
  - **Synchronous Pipeline Stage**: 1-cycle registered output stage (`acc_out[0:1]`) with active-low synchronous reset (`rst_n`) and valid strobe (`valid_out = en`).
- **Status**: Verified with 40/40 tests passing in Vivado 2026.1.

---

## 6. Stage 3: AMPC-4 (`ampc_4.sv`)
- **Type**: 4-Lane Parallel Adaptive MAC Processing Core.
- **Architectural Implementation**:
  - Exactly 4 parallel MAC units instantiating verified `mac_unit.sv`.
  - Same parameterization: `DATA_WIDTH=8`, `WEIGHT_WIDTH=8`, `ACC_WIDTH=32`.
  - Explicit per-lane dynamic masking (`lane_mask[3:0]`) without default value.
  - Operand gating layer suppressing toggling on inactive lanes ($0 \times 0 + \text{acc\_in}[i] = \text{acc\_in}[i]$).
  - Identical 1-cycle registered output latency and synchronous reset (`rst_n`) matching AMPC-2.
  - Outputs directly compatible with planned 4-lane spatial reduction adder tree in `accumulator.sv`.
- **Status**: Verified with 45/45 tests passing in Vivado 2026.1.

---

## 7. Stage 4: AMPC-8 (`ampc_8.sv`)
- **Type**: 8-Lane Parallel Adaptive MAC Processing Core.
- **Architectural Implementation**:
  - Exactly 8 parallel MAC units instantiating verified `mac_unit.sv`.
  - Same parameterization: `DATA_WIDTH=8`, `WEIGHT_WIDTH=8`, `ACC_WIDTH=32`.
  - Explicit per-lane dynamic masking (`lane_mask[7:0]`) without default value.
  - Operand gating layer suppressing toggling on inactive lanes ($0 \times 0 + \text{acc\_in}[i] = \text{acc\_in}[i]$).
  - Identical 1-cycle registered output latency and synchronous reset (`rst_n`) matching AMPC-2 and AMPC-4.
  - Supports arbitrary workload remainders $W=1, 2, 3, 4, 5, 6, 7, 8$ with precision masking.
  - 8-lane parallel output directly compatible with planned 8-lane spatial reduction adder tree in `accumulator.sv`.
- **Status**: Verified with 54/54 tests passing in Vivado 2026.1.

---

## 8. Stage 5: AMPC-16 (`ampc_16.sv`)
- **Type**: 16-Lane Parallel Adaptive MAC Processing Core.
- **Architectural Implementation**:
  - Exactly 16 parallel MAC units instantiating verified `mac_unit.sv`.
  - Same parameterization: `DATA_WIDTH=8`, `WEIGHT_WIDTH=8`, `ACC_WIDTH=32`.
  - Explicit per-lane dynamic masking (`lane_mask[15:0]`) without default value.
  - Operand gating layer suppressing toggling on inactive lanes ($0 \times 0 + \text{acc\_in}[i] = \text{acc\_in}[i]$).
  - Identical 1-cycle registered output latency and synchronous reset (`rst_n`) matching AMPC-2, AMPC-4, and AMPC-8.
  - Fully supports arbitrary and non-power-of-two workloads ($W=9, 10, 12, 15, 16$) with clean precision masking.
  - 16-lane parallel output directly compatible with planned 16-lane spatial reduction adder tree in `accumulator.sv`.
- **Status**: Verified with 68/68 tests passing in Vivado 2026.1.

---

## 9. Stage 6: Common Accumulator & Spatial Reduction (`accumulator.sv`)
- **Type**: Unified spatial reduction adder and temporal multi-cycle accumulator block.
- **Architectural Implementation**:
  - **Interface**:
    - Max 16-lane input: `input logic signed [31:0] lane_data [0:15]`
    - Dynamic lane mask: `input logic [15:0] lane_mask`
    - Control: `clk`, synchronous active-low `rst_n`, `en`, `valid_in`
    - Output: Registered scalar `accumulated_out` (signed INT32) and `valid_out` strobe.
  - **Spatial Reduction Layer**:
    - Evaluates `lane_mask[i]` for each lane $i \in [0, 15]$.
    - Only active lanes (`lane_mask[i] == 1'b1`) contribute to the spatial reduction.
    - Inactive lanes (`lane_mask[i] == 1'b0`) strictly contribute 0, preventing preserved accumulator state from masked AMPC lanes from corrupting the sum.
    - Uses an internal 36-bit reduction width (`ACC_WIDTH + $clog2(LANES) = 36`) to eliminate intermediate spatial overflow when summing 16 signed 32-bit values.
  - **Temporal Accumulation Layer**:
    - Gated by `(en && valid_in)`. When either signal is 0, the accumulator cleanly maintains its existing value and deasserts `valid_out`.
    - Updates running sum on `posedge clk`: `accumulated_out <= accumulated_out + ACC_WIDTH'(spatial_sum)`.
    - Adheres to standard two's-complement wrapping if the mathematical running sum exceeds the signed INT32 range.
  - **Status**: Verified with 90/90 tests passing in Vivado 2026.1 (100% PASS, 0 failures, 0 X/Z).

---

## 10. Stage 7: ReLU Activation Unit (`relu.sv`)
- **Purpose**: Implements the standard Rectified Linear Unit ($\text{ReLU}$) activation function for TinyML neural-network inference, operating downstream of the common accumulator.
- **Transfer Function**:
  $$\text{ReLU}(x) = \begin{cases} x, & \text{if } x > 0 \\ 0, & \text{if } x \le 0 \end{cases}$$
- **Data Representation & Signedness**:
  - Operates on signed INT32 inputs (`input logic signed [DATA_WIDTH-1:0] data_in`, default `DATA_WIDTH = 32`).
  - Employs an explicit signed relational comparison against zero (`if (data_in < 0)`).
  - Negative values (including extreme minimum $-2147483648$, negative boundaries, and negative arbitrary values) are mapped to 0.
  - Non-negative values (including $0$, $+1$, positive boundaries, and extreme maximum $+2147483647$) are preserved with bit-exact fidelity.
- **Timing & Latency**:
  - Implemented as a pure combinational logic block (`always_comb`).
  - Introduces zero additional clock-cycle pipeline latency ($0$ cycles).
- **Status & Verification**:
  - Verified with 88/88 tests passing in Vivado 2026.1 (100% PASS, 0 failures, 0 X/Z).
  - Standalone verification and full-project top-level compilation and elaboration passed cleanly.

---

## 11. Stage 8: Input & Weight Buffers (`input_buffer.sv`, `weight_buffer.sv`)
- **Purpose**:
  - `input_buffer.sv`: Modular on-chip activation storage holding signed INT8 input vectors for feed-forward inference.
  - `weight_buffer.sv`: Modular on-chip weight storage holding signed INT8 quantized filter/kernel coefficients.
- **Data Representation & Parameterization**:
  - Data Width: Signed 8-bit integers (`DATA_WIDTH = 8`).
  - Storage Depth: Configurable parameter (`DEPTH = 64` words default, `ADDR_WIDTH = $clog2(DEPTH) = 6` bits).
- **Read/Write Behavior & Timing**:
  - **Write Operation**: Synchronous write committing `wr_data` to `mem[wr_addr]` on the rising clock edge when `wr_en` is asserted.
  - **Read Operation & Latency**: Synchronous read with deterministic **1-clock-cycle latency** (`rd_data` registered on `posedge clk`).
  - **Collision Handling**: Write-First (write-through) forwarding logic ensures immediate visibility on `rd_data` during simultaneous write and read to the same address (`wr_en && wr_addr == rd_addr`).
- **Reset Strategy & FPGA Resource Mapping**:
  - **Synchronous Active-Low Reset (`!rst_n`)**: Explicitly clears the read output register `rd_data <= '0'`.
  - **Memory Storage Array (`mem`)**: Left unreset to prevent massive routing/multiplexer explosion and enable clean FPGA memory mapping.
  - **FPGA Synthesis Resource Clarification**: The actual physical resource mapping (LUTRAM/distributed RAM vs. dedicated Block RAM slices) will be determined during Vivado synthesis based on depth, access patterns, and timing constraints. No premature claims of BRAM or LUTRAM utilization are made prior to synthesis.
- **Status & Verification**:
  - `input_buffer_tb.sv`: 135/135 tests passed (100% PASS, 0 failures, 0 X/Z).
  - `weight_buffer_tb.sv`: 135/135 tests passed (100% PASS, 0 failures, 0 X/Z).
  - Standalone verification and full-project top-level compilation and elaboration (`ampc_top`) passed cleanly.

---

## 12. Stage 9: Workload Analyzer (`workload_analyzer.sv`)
- **Purpose**:
  - Evaluates requested workload size $W$ and determines the optimal parallel MAC core capacity ($0, 2, 4, 8, 16$) and workload remainder.
  - Exposes essential chunking metadata to enable the downstream Adaptive Controller to manage multi-cycle execution for arbitrary workloads ($W > 16$).
  - Note: The analyzer itself does *not* perform multi-cycle sequencing; it classifies and decomposes the workload size for the controller FSM.
- **Workload Mapping & Remainder Logic**:
  - **Zero Workload ($W = 0$)**: `selected_capacity = 0`, `remainder = 0` (no cores activated).
  - **Single-Cycle Workloads ($W \in [1, 16]$)**:
    - $W \in [1, 2]$: `selected_capacity = 2` (AMPC-2). Remainder = $(W == 2 \ ?\ 0 : W)$.
    - $W \in [3, 4]$: `selected_capacity = 4` (AMPC-4). Remainder = $(W == 4 \ ?\ 0 : W)$.
    - $W \in [5, 8]$: `selected_capacity = 8` (AMPC-8). Remainder = $(W == 8 \ ?\ 0 : W)$.
    - $W \in [9, 16]$: `selected_capacity = 16` (AMPC-16). Remainder = $(W == 16 \ ?\ 0 : W)$.
  - **Multi-Cycle Workloads ($W > 16$)**:
    - First execution chunk assigns maximum physical capacity: `selected_capacity = 16` (AMPC-16).
    - Remainder exposes remaining uncomputed workload: `remainder = W - 16`.
    - *Explicit Example*: $W = 25 \rightarrow \text{first 16-wide chunk} + 9 \text{ remaining}$.
- **Timing & Latency**:
  - Registered output stage with deterministic **1-clock-cycle latency**.
  - New analysis accepted only when `(en == 1'b1 && valid_in == 1'b1)`.
  - When disabled (`en=0`) or invalid (`valid_in=0`), `valid_out` is driven to `1'b0` and registered outputs hold state.
  - Synchronous active-low reset `!rst_n` clears `selected_capacity <= 0`, `remainder <= 0`, and `valid_out <= 0`.
- **Status & Verification**:
  - Verified with 138/138 tests passing in Vivado 2026.1 (100% PASS, 0 failures, 0 X/Z).
  - Standalone verification and full-project top-level compilation and elaboration (`ampc_top`) passed cleanly.

---

## 13. Stage 10: Adaptive Controller & FSM (`adaptive_controller.sv`)
- **Purpose**:
  - Central hardware control orchestrator managing workload-dependent parallel core selection, dynamic lane mask synthesis, and iterative multi-cycle chunking for workloads larger than 16 MACs.
- **FSM Architecture & States**:
  - `ST_IDLE` (`2'b00`): Awaiting `start` strobe. `ready = 1`, `busy = 0`, `done = 0`, all AMPC enables and masks strictly zero. If $W=0$, transitions directly to `ST_DONE`. If $W>0$, loads `rem_q <= workload_size` and enters `ST_EXECUTE`.
  - `ST_EXECUTE` (`2'b01`): Drives selected AMPC enable, synthesizes active lane mask, asserts `busy = 1` and `chunk_valid = 1`. Iteratively consumes chunks until `rem_q == 0`, then transitions to `ST_DONE`.
  - `ST_DONE` (`2'b10`): Generates a 1-cycle completion pulse (`done = 1`, `busy = 0`). All enables and masks are zero. Transitions back to `ST_IDLE`.
- **AMPC Core Selection & Dynamic Lane-Mask Synthesis**:
  - For remaining workload $R = \text{rem\_q}$ in current chunk:
    - $R \in [1, 2] \rightarrow \text{AMPC-2}$ (`ampc2_en = 1`), `ampc2_lane_mask` $= (R == 1 \ ?\ 2\text{'b}01 : 2\text{'b}11)$.
    - $R \in [3, 4] \rightarrow \text{AMPC-4}$ (`ampc4_en = 1`), `ampc4_lane_mask` $= (4\text{'b}1 \ll R) - 1$.
    - $R \in [5, 8] \rightarrow \text{AMPC-8}$ (`ampc8_en = 1`), `ampc8_lane_mask` $= (8\text{'b}1 \ll R) - 1$.
    - $R \in [9, 16] \rightarrow \text{AMPC-16}$ (`ampc16_en = 1`), `ampc16_lane_mask` $= (16\text{'b}1 \ll R) - 1$.
    - $R > 16 \rightarrow \text{AMPC-16}$ (`ampc16_en = 1`, full 16-wide chunk), `ampc16_lane_mask` $= 16\text{'h}FFFF$. Next $R \Leftarrow R - 16$.
- **Multi-Cycle Chunking Examples**:
  - **$W = 17$**: Chunk 1 (AMPC-16, 16 lanes, `16'hFFFF`) $\rightarrow$ Chunk 2 (AMPC-2, 1 lane, `2'b01`). Total = 2 chunks ($16 + 1$).
  - **$W = 25$**: Chunk 1 (AMPC-16, 16 lanes, `16'hFFFF`) $\rightarrow$ Chunk 2 (AMPC-16, 9 lanes, `16'h01FF`). Total = 2 chunks ($16 + 9$).
  - **$W = 33$**: Chunk 1 (AMPC-16, 16 lanes, `16'hFFFF`) $\rightarrow$ Chunk 2 (AMPC-16, 16 lanes, `16'hFFFF`) $\rightarrow$ Chunk 3 (AMPC-2, 1 lane, `2'b01`). Total = 3 chunks ($16 + 16 + 1$).
- **Controller / Accumulator Relationship**:
  - The controller asserts `chunk_valid` for exactly 1 clock cycle per execution chunk.
  - The downstream common accumulator captures the spatial reduction on each valid cycle and updates temporal accumulation without duplicate accumulator logic in the controller.
- **Physical Resource Integrity**:
  - All 30 instantiated physical MAC slices remain in the FPGA fabric; the controller applies dynamic gating and enables to eliminate inactive switching activity.
- **Status & Verification**:
  - Verified with 126/126 tests passing in Vivado 2026.1 (100% PASS, 0 failures, 0 X/Z).
  - Standalone verification and full-project top-level compilation and elaboration (`ampc_top`) passed cleanly.

---

## 14. Stage 11: Top-Level Integration Architecture (`ampc_top.sv`)

### 14.1 Top-Level Architecture & Block Diagram
The `ampc_top` module integrates all previously verified modular blocks into a cohesive, high-throughput TinyML inference accelerator datapath:

```
                                      +---------------------------------------------+
                                      |                 ampc_top                    |
                                      |                                             |
[ibuf_wr/rd] ----> [ Input Buffer  ]  |                                             |
[wbuf_wr/rd] ----> [ Weight Buffer ]  |                                             |
                                      |                                             |
[start, W] ------> [ Workload Analyzer ]                                            |
      |                 | (Telemetry: Capacity, Remainder)                          |
      +----------> [ Adaptive Controller FSM ]                                      |
                        | (Core En, Lane Mask, Chunk Size)                          |
                        v                                                           |
           +------------+------------+------------+                                 |
           |            |            |            |                                 |
        [AMPC-2]     [AMPC-4]     [AMPC-8]    [AMPC-16]                             |
           |            |            |            |                                 |
           +------------+-----+------+------------+                                 |
                              | (Muxed signed INT32[0:15] + Pipelined Mask)         |
                              v                                                     |
                     [ Common Accumulator ] (Spatial Reduction + Multi-Cycle Temp)  |
                              | (accumulated_out)                                   |
                              v                                                     |
                        [ ReLU Unit ] (Combinational Non-Linear Clamp)              |
                              | (output_data)                                       |
                              v                                                     |
                 [ Status: ready, busy, done, output_valid ]                        |
                                      +---------------------------------------------+
```

### 14.2 Exact Cycle-by-Cycle Pipeline Timing Alignment
The datapath accounts for the registered output behavior of the parallel AMPC cores and the spatial/temporal accumulator:

1. **Cycle $N$ (Controller Issue)**:
   - FSM is in `ST_EXECUTE`.
   - Controller activates exactly one AMPC core (`core_en[3:0]`) and presents the dynamic active lane mask (`current_active_mask`).
   - External/buffer streaming operands (`data_in[0:15]`, `weight[0:15]`) are presented on the inputs.
2. **Cycle $N+1$ (AMPC Registered Compute & Mask Pipeline)**:
   - Selected AMPC core captures operands and registers signed INT32 lane products (`out_ampc*`, `valid_ampc* = 1`).
   - The active lane mask is simultaneously captured in pipeline register `mask_q <= current_active_mask`.
   - `accum_valid_in` asserts, presenting registered lane products and aligned `mask_q` to the Common Accumulator.
3. **Cycle $N+2$ (Spatial Reduction & Temporal Accumulation)**:
   - Common Accumulator captures active lane results, calculates the spatial tree sum, adds it to `accumulated_out`, and asserts `accum_valid_out = 1`.
4. **Final Cycle (Completion Handshake)**:
   - When the controller has issued all chunks (`ctrl_done = 1`) and the final chunk finishes accumulation (`last_chunk_reached && accum_valid_out`), `output_valid` and `done` assert synchronously.
   - `output_data` reflects the zero-latency combinational ReLU clamp of the final `accumulated_out`.

### 14.3 Multi-Cycle Execution Examples
- **$W = 17$**:
  - Chunk 1: AMPC-16 (16 lanes enabled, mask `16'hFFFF`).
  - Chunk 2: AMPC-2 (1 lane enabled, mask `2'b01`).
  - Common Accumulator performs spatial reduction for Chunk 1 and Chunk 2, accumulating all 17 operations into a single scalar result.
- **$W = 25$**:
  - Chunk 1: AMPC-16 (16 lanes enabled, mask `16'hFFFF`).
  - Chunk 2: AMPC-16 (9 lanes enabled, mask `16'h01FF`).
  - Accumulates $16 + 9 = 25$ operations across 2 cycles.
- **$W = 33$**:
  - Chunk 1: AMPC-16 (16 lanes).
  - Chunk 2: AMPC-16 (16 lanes).
  - Chunk 3: AMPC-2 (1 lane).
  - Accumulates $16 + 16 + 1 = 33$ operations across 3 cycles.
- **$W = 100$**:
  - 6 full chunks of AMPC-16 ($6 \times 16 = 96$) + 1 partial chunk of AMPC-4 (4 lanes, mask `4'b1111`).
  - Total = 7 execution cycles.

### 14.4 AMPC `acc_in` Configuration
- To prevent conflicting internal accumulation state within individual AMPC modules, all AMPC `acc_in` ports are tied to constant `32'sd0`.
- The downstream `accumulator.sv` handles 100% of both spatial reduction (across active lanes) and temporal accumulation (across chunks).

### 14.5 Verification Status (Stage 11)
- **RTL**: `rtl/ampc_top.sv`
- **Testbench**: `tb/ampc_top_tb.sv`
- **Simulation**: Vivado 2026.1 `xvlog` + `xelab` + `xsim`
- **Test Results**: **74/74 PASS (100%)**, 0 Failures, 0 X/Z states.
- **Synthesizability**: Top-level entity `ampc_top` elaborates with 0 errors and 0 warnings.

---

## 15. Stage 12: Full-System Verification & Vivado Synthesis Baseline

### 15.1 Baseline Synthesis & Implementation Summary
- **Target FPGA**: AMD/Xilinx Zynq-7010 (`xc7z010clg400-1`), Speed Grade `-1`.
- **EDA Suite**: AMD Vivado 2026.1 (Build 6511674).
- **Clock Constraint**: 100.000 MHz (10.000 ns period, 50% duty cycle).
- **Synthesis & Implementation Flow**: Out-of-Context (`synth_design -mode out_of_context` $\rightarrow$ `opt_design` $\rightarrow$ `place_design` $\rightarrow$ `route_design`).

### 15.2 Post-Routing Resource Utilization
- **Slice LUTs**: 3,564 / 17,600 (20.25 %)
  - Logic LUTs: 3,540 / 17,600 (20.11 %)
  - Distributed RAM (LUTRAM): 24 / 6,000 (0.40 %)
- **Slice Registers (FFs)**: 595 / 35,200 (1.69 %)
- **Occupied Slices**: 1,041 / 4,400 (23.66 %)
- **DSP48E1 Blocks**: 0 / 80 (0.00 %) — Multipliers synthesized into LUT logic and CARRY4 chains (`438 CARRY4` primitives).
- **Block RAM (BRAM Tile)**: 0 / 60 (0.00 %) — 64-depth activation/weight buffers mapped into Distributed LUTRAM.

### 15.3 Timing Performance & Maximum Frequency
- **Worst Negative Slack (WNS)**: **+0.006 ns** (Timing MET, zero violations).
- **Total Negative Slack (TNS)**: **0.000 ns**.
- **Worst Hold Slack (WHS)**: **+0.054 ns** (Hold MET, zero violations).
- **Total Hold Slack (THS)**: **0.000 ns**.
- **Estimated Maximum Operating Frequency ($F_{\max}$)**:
  $$F_{\max} = \frac{1}{10.000\text{ ns} - 0.006\text{ ns}} \approx \mathbf{100.06\text{ MHz}}$$

### 15.4 Critical Timing Path
- **Startpoint**: `u_controller/rem_q_reg[7]/C` (FDRE clocked by `clk`)
- **Endpoint**: `u_ampc_16/acc_out_reg[4][13]/D` (FDRE clocked by `clk`)
- **Total Delay**: 9.772 ns (Logic Delay: 3.805 ns / 38.94 %, Routing Delay: 5.967 ns / 61.06 %, 11 Logic Levels).
- **Physical Description**: From Controller FSM remaining workload comparator, synthesizing core enable and lane mask, into AMPC-16 dynamic lane multiplier and accumulator carry chain input `D`.

### 15.5 Power Estimation
- **Total Estimated On-Chip Power**: 0.123 W (123 mW).
- **Estimated Dynamic Power**: 0.033 W (33 mW).
- **Estimated Device Static Power**: 0.090 W (90 mW).
- *Note*: Vector-less estimation at 100 MHz; physical hardware validation required for board-level energy efficiency.

---

## 16. Roadmap of Stages
1. **Stage 1: MAC Unit** — Verified combinational signed MAC unit (`mac_unit.sv`). [APPROVED]
2. **Stage 2: AMPC-2** — 2-lane MAC processing core (`ampc_2.sv`). [APPROVED]
3. **Stage 3: AMPC-4** — 4-lane MAC processing core (`ampc_4.sv`). [APPROVED]
4. **Stage 4: AMPC-8** — 8-lane MAC processing core (`ampc_8.sv`). [APPROVED]
5. **Stage 5: AMPC-16** — 16-lane MAC processing core (`ampc_16.sv`). [APPROVED]
6. **Stage 6: Accumulator** — Spatial reduction & temporal accumulator (`accumulator.sv`). [APPROVED]
7. **Stage 7: ReLU** — Signed INT32 non-linear activation function (`relu.sv`). [APPROVED]
8. **Stage 8: Input/Weight Buffers** — On-chip buffer storage for activation/weight vectors (`input_buffer.sv`, `weight_buffer.sv`). [APPROVED]
9. **Stage 9: Workload Analyzer** — Evaluates arbitrary workload size $W$ (`workload_analyzer.sv`). [APPROVED]
10. **Stage 10: Adaptive Controller** — FSM managing core selection, multi-cycle chunking, masking, and handshaking (`adaptive_controller.sv`). [APPROVED]
11. **Stage 11: Top-Level Integration** — Full datapath integration wrapper (`ampc_top.sv`). [APPROVED]
12. **Stage 12: Full-System Verification & Vivado Synthesis Baseline** — **1,036/1,036 simulation PASS**, Synthesis, Placement, Routing, Timing Closure at 100 MHz, Utilization & Power characterization (`reports/`). [APPROVED]
13. **Stage 13: Baseline Comparison & Timing Analysis** — Verified 1,036/1,036 regression count, precise MAC lane terminology, critical path deep-dive analysis, power estimate labeling, conceptual Fixed vs. AMPC comparison (`docs/stage13_baseline_analysis.md`). [COMPLETE]
14. **Stage 14: Final Optimization & Timing Refinement** — Pipelining/DSP mapping optimizations and resource improvements (awaiting approval).
