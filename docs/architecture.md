# Architecture Specification: Adaptive MAC Processing Core (AMPC)

## 1. Executive Overview

The **Adaptive MAC Processing Core (AMPC)** is a synthesizable SystemVerilog hardware accelerator targeted at edge TinyML neural-network inference workloads on FPGAs (specifically the AMD/Xilinx Zynq-7010 `xc7z010clg400-1`).

In edge deep-learning workloads (e.g., depthwise separable convolutions, pointwise convolutions, fully-connected layers), dot-product lengths and matrix-vector dimensions vary significantly across layers. Traditional fixed-width systolic arrays or monolithic MAC grids suffer from under-utilization and unnecessary dynamic power consumption when processing workloads smaller than their native array dimensions.

AMPC introduces **workload-dependent heterogeneous parallel compute granularities** with dynamic operand gating and lane-level masking:
- **AMPC-2**: 2 parallel MAC lanes (fine-grained minimal switching for tiny workloads)
- **AMPC-4**: 4 parallel MAC lanes
- **AMPC-8**: 8 parallel MAC lanes
- **AMPC-16**: 16 parallel MAC lanes (maximum spatial throughput)
- **Total Physical Compute Footprint**: 30 physical MAC processing lanes.

> [!NOTE]
> **Silicon Resource Realism**: Unused MAC lanes do not vanish from the physical FPGA fabric. All 30 physical MAC lanes consume silicon logic (LUTs/CARRY4 or DSP48E1). Energy efficiency and performance gains stem from dynamic lane masking, operand zero-gating (eliminating switching activity on inactive multipliers), and matching chunk sizes to avoid wasteful pipeline stalls.

---

## 2. Numerical Representation & Arithmetic Precision

The datapath adheres to standard quantized TinyML numerical representations:

| Stage | Data Representation | Bitwidth | Dynamic Range |
| :--- | :--- | :---: | :--- |
| **Input Activations ($x_i$)** | Signed Two's Complement Integer (`INT8`) | 8 bits | $[-128, +127]$ |
| **Weights ($w_i$)** | Signed Two's Complement Integer (`INT8`) | 8 bits | $[-128, +127]$ |
| **Intermediate Multiplier Product** | Signed Two's Complement Integer (`INT16`) | 16 bits | $[-16,256, +16,384]$ |
| **Product Sign Extension** | Explicit Sign Extension to INT32 | 32 bits | Sign-extended bit `[15]` replicated to bits `[31:16]` |
| **Accumulator ($\text{acc}$)** | Signed Two's Complement Integer (`INT32`) | 32 bits | $[-2,147,483,648, +2,147,483,647]$ |
| **Activation Function (ReLU)** | Non-linear Threshold Clamp (`INT32`) | 32 bits | $[0, +2,147,483,647]$ |

$$\text{Product}_i = x_i \times w_i$$
$$\text{Spatial\_Sum} = \sum_{i=0}^{15} (\text{lane\_mask}[i] \ ?\ 32\text{'}(\text{Product}_i) : 0)$$
$$\text{Accumulator}_{\text{new}} = \text{Accumulator}_{\text{prev}} + \text{Spatial\_Sum}$$

---

## 3. Subsystem Decomposition & RTL Modules

The hardware architecture comprises 12 modular SystemVerilog blocks:

```
                                  +-------------------------------------------------------------+
                                  |                          ampc_top                           |
                                  |                                                             |
  [ibuf_wr/rd] ------------> [ Input Buffer (64x8)  ]                                           |
  [wbuf_wr/rd] ------------> [ Weight Buffer (64x8) ]                                           |
                                  |                                                             |
  [start, workload_size] --> [ Workload Analyzer ]                                              |
            |                     | (selected_capacity, remainder telemetry)                    |
            +--------------> [ Adaptive Controller FSM ]                                        |
                                  | (core_en[3:0], dynamic lane_mask, chunk_valid)              |
                                  v                                                             |
                             [ Pipeline Decoupling Register Stage (Stage 14 Timing Fix) ]       |
                                  |                                                             |
                     +------------+------------+------------+                                   |
                     |            |            |            |                                   |
                  [AMPC-2]     [AMPC-4]     [AMPC-8]    [AMPC-16]                               |
                  (2 Lanes)    (4 Lanes)    (8 Lanes)   (16 Lanes)                              |
                     |            |            |            |                                   |
                     +------------+-----+------+------------+                                   |
                                        | (Muxed signed INT32[0:15] + Pipelined Mask)           |
                                        v                                                       |
                               [ Common Accumulator ]                                           |
                               (Spatial Reduction Tree + Temporal Multi-Cycle Accumulation)     |
                                        | (accumulated_out: INT32)                              |
                                        v                                                       |
                                  [ ReLU Unit ]                                                 |
                               (Zero-Latency Combinational Signed Clamp)                        |
                                        | (output_data: INT32)                                  |
                                        v                                                       |
                    [ Status Flags: ready, busy, done, output_valid ]                           |
                                  +-------------------------------------------------------------+
```

### 3.1 MAC Unit (`mac_unit.sv`)
- Pure combinational signed multiplier with adder: `acc_out = (data_in * weight) + acc_in`.
- Parameterized: `DATA_WIDTH=8`, `WEIGHT_WIDTH=8`, `ACC_WIDTH=32`.
- Multiplier product ($8 \times 8 = 16$ bits) is sign-extended to 32 bits before addition.
- In top-level datapath, `acc_in` is tied to zero (`32'sd0`) to keep MACs purely feed-forward, delegating all spatial and temporal accumulation to the unified Common Accumulator.

### 3.2 Parallel Processing Cores (`ampc_2.sv`, `ampc_4.sv`, `ampc_8.sv`, `ampc_16.sv`)
- **Lanes**: 2, 4, 8, and 16 parallel MAC units respectively.
- **Dynamic Lane Masking**: Each lane $i$ is guarded by `lane_mask[i]`.
- **Operand Gating**: When a lane is inactive (`lane_mask[i] == 0`), operands are driven to zero (`data_in = 0, weight = 0`), suppressing signal transitions and eliminating internal carry switching.
- **Pipeline Stage**: 1-clock-cycle synchronous registered output stage (`acc_out[0:N-1]`) with active-low synchronous reset (`rst_n`).

### 3.3 Workload Analyzer (`workload_analyzer.sv`)
- Evaluates total requested vector size $W$ and classifies it into optimal core capacity:
  - $W \in [1, 2] \to$ Capacity 2 (AMPC-2)
  - $W \in [3, 4] \to$ Capacity 4 (AMPC-4)
  - $W \in [5, 8] \to$ Capacity 8 (AMPC-8)
  - $W \in [9, 16] \to$ Capacity 16 (AMPC-16)
  - $W > 16 \to$ Capacity 16 (AMPC-16, with multi-cycle remainder $W - 16$)
- Synchronous registered output with 1-cycle latency.

### 3.4 Adaptive Controller & FSM (`adaptive_controller.sv`)
Central control orchestrator managing workload execution:
- **`ST_IDLE` (`2'b00`)**: Awaits `start` pulse. If $W=0$, completes immediately to `ST_DONE`. If $W>0$, latches `rem_q <= workload_size` and proceeds to `ST_EXECUTE`.
- **`ST_EXECUTE` (`2'b01`)**: 
  - For remaining workload $R$:
    - If $R > 16$: Selects AMPC-16, full mask `16'hFFFF`, decrements $R \Leftarrow R - 16$.
    - If $9 \le R \le 16$: Selects AMPC-16, synthesizes bitmask with $R$ ones, $R \Leftarrow 0$.
    - If $5 \le R \le 8$: Selects AMPC-8, synthesizes bitmask with $R$ ones, $R \Leftarrow 0$.
    - If $3 \le R \le 4$: Selects AMPC-4, synthesizes bitmask with $R$ ones, $R \Leftarrow 0$.
    - If $1 \le R \le 2$: Selects AMPC-2, synthesizes bitmask with $R$ ones, $R \Leftarrow 0$.
  - Generates 1-cycle `chunk_valid` strobe per execution chunk. When $R=0$, transitions to `ST_DONE`.
- **`ST_DONE` (`2'b10`)**: Asserts 1-cycle `done` strobe, clears active enables and masks, returns to `ST_IDLE`.

### 3.5 Common Accumulator (`accumulator.sv`)
- **Spatial Reduction**: Evaluates up to 16 parallel signed INT32 inputs. Masked lanes strictly contribute zero. Uses a 36-bit intermediate adder tree (`ACC_WIDTH + $clog2(16) = 36`) to eliminate intermediate spatial overflow.
- **Temporal Accumulation**: Registered running sum accumulates successive chunks on each asserted `valid_in`.

### 3.6 ReLU Activation Unit (`relu.sv`)
- Zero-cycle combinational signed comparison against zero.
- Preserves positive values bit-for-bit up to $+2,147,483,647$; clamps negative values to $0$.

### 3.7 Activation & Weight Buffers (`input_buffer.sv`, `weight_buffer.sv`)
- Synchronous 64-depth on-chip RAM (`DATA_WIDTH=8`, `ADDR_WIDTH=6`).
- Synchronous write, registered synchronous read (1-cycle latency).
- Write-first bypass logic for concurrent read/write collisions.
- Synthesizes efficiently into FPGA distributed LUTRAM.

---

## 4. Cycle-by-Cycle Pipeline Timing Alignment

To close timing at 100 MHz with clean margins, Stage 14 decoupled the controller from the compute datapath:

1. **Cycle $T_0$ (Controller Decode)**: FSM evaluates remainder $R$, selects target core (`core_en`), and computes dynamic lane mask.
2. **Cycle $T_1$ (Pipeline Decoupling Register)**: Enables and masks are latched into pipeline registers (`ampc*_en_q`, `mask_q`). External/buffer operands stream to parallel MAC inputs.
3. **Cycle $T_2$ (AMPC Registered Execution)**: The active parallel core captures operands, evaluates products, and registers signed INT32 outputs.
4. **Cycle $T_3$ (Spatial & Temporal Accumulation)**: Common Accumulator reads 16-lane output, performs masked spatial adder tree reduction, and accumulates into running sum.
5. **Cycle $T_{\text{final}}$ (Completion & ReLU Clamp)**: When the final chunk accumulates, `output_valid` and `done` assert synchronously. Combinational ReLU presents clamped result on `output_data`.

### Multi-Cycle Workload Examples:
- **$W = 9$**: 1 chunk (AMPC-16, 9 lanes active, 7 masked).
- **$W = 17$**: 2 chunks (Chunk 1: AMPC-16, 16 lanes; Chunk 2: AMPC-2, 1 lane active).
- **$W = 25$**: 2 chunks (Chunk 1: AMPC-16, 16 lanes; Chunk 2: AMPC-16, 9 lanes active).
- **$W = 784$**: 49 chunks (49 full AMPC-16 16-lane chunks).

---

## 5. Architectural Status Classification

- **Implemented & Fully Verified**:
  - `mac_unit.sv` (INT8xINT8 MAC)
  - `ampc_2.sv`, `ampc_4.sv`, `ampc_8.sv`, `ampc_16.sv` (Dynamic lane masking & operand gating)
  - `accumulator.sv` (Spatial reduction + temporal multi-cycle accumulator)
  - `relu.sv` (Combinational non-linear threshold)
  - `input_buffer.sv`, `weight_buffer.sv` (On-chip distributed memories)
  - `workload_analyzer.sv` (Workload decomposition)
  - `adaptive_controller.sv` (FSM chunking orchestrator)
  - `ampc_top.sv` (Top-level integration with Stage 14 pipeline decoupling)
- **Verified via AI Validation**:
  - Real INT8 layer workloads extracted from PyTorch MNIST, Fashion-MNIST, and CIFAR-10 models (16/16 bit-exact matches).
- **In Progress / Exploration**:
  - Hard DSP48E1 mapping investigation (`rtl/experimental/mac_unit_dsp.sv`).
- **Planned Future Work**:
  - Full on-chip AXI4-Stream / AXI4-Lite memory-mapped interface wrapper.
  - Multi-channel parallel weight-buffering and output quantization scaling module.
