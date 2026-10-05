# Adaptive FPGA Accelerator for TinyML Inference (AMPC)

[![FPGA](https://img.shields.io/badge/Target%20FPGA-AMD%2F%20Xilinx%20Zynq--7010-blue)](https://www.xilinx.com/products/silicon-devices/soc/zynq-7000.html)
[![EDA](https://img.shields.io/badge/EDA%20Tool-AMD%20Vivado%202026.1-orange)](https://www.xilinx.com/products/design-tools/vivado.html)
[![Standard](https://img.shields.io/badge/HDL-SystemVerilog-brightgreen)](#rtl-design-overview)
[![Regression](https://img.shields.io/badge/Regression-1036%20%2F%201036%20PASS-success)](docs/verification.md)
[![AI-Validation](https://img.shields.io/badge/AI%20Hardware%20Validation-16%20%2F%2016%20Exact%20Match-blueviolet)](docs/verification.md#3-real-tinyml-model-hardware-validation)
[![Timing](https://img.shields.io/badge/Timing-MET%20%40%20100MHz%20(WNS%20%2B0.256ns)-brightgreen)](docs/implementation.md)

---

## 1. Project Overview

The **Adaptive MAC Processing Core (AMPC)** is a synthesizable SystemVerilog hardware accelerator optimized for edge TinyML neural-network inference on FPGA devices. 

In TinyML networks (such as MobileNet, depthwise separable convolutions, dense projection layers, and quantized CNNs), the required dot-product lengths and matrix dimensions vary widely across layers. Traditional monolithic matrix multipliers or fixed systolic arrays suffer from excessive dynamic switching power, padding overhead, and low hardware utilization when executing non-uniform, fine-grained workloads.

AMPC addresses this through **adaptive hardware parallelism**:
- Dynamically allocates computation across heterogeneous parallel processing cores: **AMPC-2**, **AMPC-4**, **AMPC-8**, and **AMPC-16** (totalling 30 physical MAC lanes).
- Employs **dynamic lane masking** and **operand zero-gating** to eliminate dynamic toggling in unused multipliers.
- Integrates an on-chip **Workload Analyzer** and **Adaptive Controller FSM** that decomposes arbitrary dot-product lengths ($W > 16$) into deterministic single-cycle and multi-cycle execution chunks.
- Combines spatial reduction and temporal accumulation into a unified **Common Accumulator**, followed by a zero-latency signed **ReLU** thresholding unit.

---

## 2. Motivation & Architectural Principles

1. **Heterogeneous Compute Granularities**: Rather than forcing small dot-products into a large monolithic compute grid, the accelerator matches core capacity directly to workload demand.
2. **Switching Activity Suppression**: When a MAC lane is masked, its inputs are gated to zero, ensuring $(0 \times 0) + \text{acc} = \text{acc}$ without spurious switching activity or accumulator corruption.
3. **Decoupled Pipeline Architecture**: A registered pipeline stage isolates the control FSM from the arithmetic multiplier carry chains, closing timing at 100 MHz on the slowest `-1` speed grade of AMD/Xilinx Zynq-7010.
4. **Physical Resource Integrity**: The design makes no fictitious claims of silicon removal; all 30 instantiated MAC units remain physically present in the FPGA fabric. The benefit lies in dynamic activation, switching reduction, and low control overhead.

---

## 3. System Architecture & Datapath

The complete accelerator datapath integrates 12 modular SystemVerilog blocks:

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

### Execution Flow:
1. **Decode & Workload Chunking**: The controller evaluates requested workload size $W$ and determines whether it can be computed in a single chunk ($W \le 16$) or requires iterative decomposition ($W > 16$).
2. **Pipelined Issue**: Active core enable and bitmask are registered into the pipeline stage alongside streaming operands.
3. **Parallel Multiply**: Active lanes compute signed INT8 $\times$ INT8 products and latch signed INT32 outputs. Masked lanes are held at zero.
4. **Spatial Reduction & Temporal Accumulation**: The Common Accumulator computes the spatial sum of active lanes using a 36-bit wide intermediate adder tree and adds it to the running sum.
5. **Activation & Completion**: Once all chunks complete, `output_valid` and `done` assert synchronously, presenting the non-linear ReLU clamped result on `output_data`.

For full cycle-by-cycle waveform alignments and state diagrams, see [docs/architecture.md](docs/architecture.md).

---

## 4. Hardware & Target Platform Specifications

| Parameter | Specification |
| :--- | :--- |
| **Target FPGA Device** | AMD/Xilinx Zynq-7010 (`xc7z010clg400-1`), Speed Grade `-1` |
| **EDA Tool** | AMD Vivado 2026.1 (Build 6511674) |
| **Synthesis & Implementation Flow** | Out-of-Context (OOC) IP core flow (`synth_design -mode out_of_context`) |
| **Operating Clock Frequency** | **100.000 MHz** (10.000 ns period, 50% duty cycle, 0.200 ns uncertainty) |
| **Setup Slack (WNS)** | **+0.256 ns** (Timing MET with zero violations) |
| **Hold Slack (WHS)** | **+0.029 ns** (Timing MET with zero violations) |
| **Estimated Maximum Frequency ($F_{\max}$)** | **102.63 MHz** |
| **Total Estimated On-Chip Power** | **0.127 W (127 mW)** (Dynamic: 37 mW, Static: 90 mW) |

---

## 5. Numerical Formats & Data Representations

The architecture uses standard integer quantization parameters common to TinyML frameworks:

- **Input Activations ($x_i$)**: Signed 8-bit integer (`INT8`), dynamic range $[-128, +127]$.
- **Weights ($w_i$)**: Signed 8-bit integer (`INT8`), dynamic range $[-128, +127]$.
- **Multiplier Intermediate Product**: Signed 16-bit integer (`INT16`), $[-16,256, +16,384]$.
- **Sign Extension**: 16-bit product sign-extended to 32 bits before spatial addition.
- **Accumulator Precision**: Signed 32-bit integer (`INT32`), dynamic range $[-2^{31}, +2^{31}-1]$.
- **Spatial Reduction Headroom**: 36-bit internal adder tree (`ACC_WIDTH + $clog2(16) = 36`) to eliminate intermediate spatial overflow.
- **Activation Output (ReLU)**: Signed 32-bit integer (`INT32`), clamped at $\max(0, \text{accumulated\_out})$.

---

## 6. RTL Design Overview

| Module Name | Source File | Description |
| :--- | :--- | :--- |
| **`mac_unit`** | [`rtl/mac_unit.sv`](rtl/mac_unit.sv) | Parameterized combinational signed INT8 MAC with explicit 32-bit sign extension. |
| **`ampc_2`** | [`rtl/ampc_2.sv`](rtl/ampc_2.sv) | 2-lane parallel core with dynamic 2-bit lane masking, operand gating, registered outputs. |
| **`ampc_4`** | [`rtl/ampc_4.sv`](rtl/ampc_4.sv) | 4-lane parallel core with 4-bit dynamic masking, operand zero-gating. |
| **`ampc_8`** | [`rtl/ampc_8.sv`](rtl/ampc_8.sv) | 8-lane parallel core with 8-bit dynamic masking, arbitrary remainder support. |
| **`ampc_16`** | [`rtl/ampc_16.sv`](rtl/ampc_16.sv) | 16-lane parallel core with 16-bit dynamic masking, maximum parallel throughput. |
| **`accumulator`** | [`rtl/accumulator.sv`](rtl/accumulator.sv) | Spatial reduction adder tree across active lanes + multi-cycle temporal accumulator. |
| **`relu`** | [`rtl/relu.sv`](rtl/relu.sv) | Zero-latency combinational signed INT32 thresholding clamp. |
| **`input_buffer`** | [`rtl/input_buffer.sv`](rtl/input_buffer.sv) | 64-word $\times$ 8-bit on-chip activation RAM with write-first collision bypass. |
| **`weight_buffer`** | [`rtl/weight_buffer.sv`](rtl/weight_buffer.sv) | 64-word $\times$ 8-bit on-chip weight RAM with write-first collision bypass. |
| **`workload_analyzer`** | [`rtl/workload_analyzer.sv`](rtl/workload_analyzer.sv) | Real-time workload dimension classifier exposing capacity and remainder telemetry. |
| **`adaptive_controller`** | [`rtl/adaptive_controller.sv`](rtl/adaptive_controller.sv) | 3-state control FSM managing multi-cycle chunk sequencing, core enables, lane masks. |
| **`ampc_top`** | [`rtl/ampc_top.sv`](rtl/ampc_top.sv) | Top-level integration entity featuring Stage 14 pipeline decoupling registers. |
| **`exp_dsp_eval_top`** | [`rtl/experimental/exp_dsp_eval_top.sv`](rtl/experimental/exp_dsp_eval_top.sv) | Stage 15 experimental dual-subsystem DSP evaluation wrapper. |
| **`mac_unit_dsp`** | [`rtl/experimental/mac_unit_dsp.sv`](rtl/experimental/mac_unit_dsp.sv) | Stage 15 experimental DSP48E1-inferred registered MAC block. |

---

## 7. Verification Methodology & Empirical Results

The verification methodology combines exhaustive unit and integration testing with real deep-learning model hardware validation.

### 7.1 Full Unit & Integration Regression Suite (1,036 Tests)
An automated suite of 12 SystemVerilog testbenches tests arithmetic boundary limits, sign extensions, collision forwarding, FSM sequences, and multi-cycle chunk handshakes.

```
==============================================================================
                  RUNNING FULL REGRESSION SUITE (1,036 TESTS)                
==============================================================================
>>> Running mac_unit_tb...          Passed=43  / Expected=43,  Failed=0
>>> Running ampc_2_tb...            Passed=40  / Expected=40,  Failed=0
>>> Running ampc_4_tb...            Passed=45  / Expected=45,  Failed=0
>>> Running ampc_8_tb...            Passed=54  / Expected=54,  Failed=0
>>> Running ampc_16_tb...           Passed=68  / Expected=68,  Failed=0
>>> Running accumulator_tb...       Passed=90  / Expected=90,  Failed=0
>>> Running relu_tb...              Passed=88  / Expected=88,  Failed=0
>>> Running input_buffer_tb...      Passed=135 / Expected=135, Failed=0
>>> Running weight_buffer_tb...     Passed=135 / Expected=135, Failed=0
>>> Running workload_analyzer_tb... Passed=138 / Expected=138, Failed=0
>>> Running adaptive_controller_tb. Passed=126 / Expected=126, Failed=0
>>> Running ampc_top_tb...          Passed=74  / Expected=74,  Failed=0
==============================================================================
REGRESSION SUMMARY: Total Passed: 1,036 / 1036, Total Failed: 0 (100.0% PASS)
==============================================================================
```

### 7.2 Hardware AI Model Validation (Three Real Models)
Real quantized layer weights and input activations were extracted from three PyTorch neural-network models trained on public datasets and executed through the top-level RTL:

1. **MNIST TinyMLP** (`Linear(784, 32) -> ReLU -> Linear(32, 10)`, 96.36% test accuracy)
2. **Fashion-MNIST CNN** (`Conv2D(1→8) -> Conv2D(8→16) -> FC`, 88.59% test accuracy)
3. **CIFAR-10 CNN** (`Conv2D(3→16) -> Conv2D(16→32) -> FC`, 67.64% test accuracy)

| Model | Layer Workload ($W$) | Hardware Decomposition | Python Golden | RTL Measured | Difference ($\Delta$) | Status |
| :--- | :---: | :--- | :---: | :---: | :---: | :---: |
| **MNIST** | 9 | AMPC-16 (9 active, 7 masked) | 1,121 | 1,121 | 0 | **PASS** |
| **MNIST** | 17 | 16 + 1 (AMPC-16 + AMPC-2) | 2,223 | 2,223 | 0 | **PASS** |
| **MNIST** | 25 | 16 + 9 (AMPC-16 + AMPC-16) | 4,465 | 4,465 | 0 | **PASS** |
| **MNIST** | 33 | 16 + 16 + 1 (2x AMPC-16 + AMPC-2) | 6,802 | 6,802 | 0 | **PASS** |
| **MNIST** | 784 | 49 $\times$ 16 (49 full AMPC-16 chunks) | 40,691 | 40,691 | 0 | **PASS** |
| **Fashion-MNIST** | 9 | AMPC-16 (9 active, 7 masked) | 24,812 | 24,812 | 0 | **PASS** |
| **Fashion-MNIST** | 17 | 16 + 1 (AMPC-16 + AMPC-2) | -29,587 | -29,587 | 0 | **PASS** |
| **Fashion-MNIST** | 25 | 16 + 9 (AMPC-16 + AMPC-16) | -27,323 | -27,323 | 0 | **PASS** |
| **Fashion-MNIST** | 33 | 16 + 16 + 1 (2x AMPC-16 + AMPC-2) | -33,189 | -33,189 | 0 | **PASS** |
| **Fashion-MNIST** | 72 | 16*4 + 8 (4x AMPC-16 + 1x AMPC-8) | -44,913 | -44,913 | 0 | **PASS** |
| **CIFAR-10** | 9 | AMPC-16 (9 active, 7 masked) | -20,572 | -20,572 | 0 | **PASS** |
| **CIFAR-10** | 17 | 16 + 1 (AMPC-16 + AMPC-2) | 13,037 | 13,037 | 0 | **PASS** |
| **CIFAR-10** | 25 | 16 + 9 (AMPC-16 + AMPC-16) | 11,916 | 11,916 | 0 | **PASS** |
| **CIFAR-10** | 27 | 16 + 11 (AMPC-16 + AMPC-16) | -24,979 | -24,979 | 0 | **PASS** |
| **CIFAR-10** | 33 | 16 + 16 + 1 (2x AMPC-16 + AMPC-2) | -6,345 | -6,345 | 0 | **PASS** |
| **CIFAR-10** | 144 | 16 $\times$ 9 (9 full AMPC-16 chunks) | -44,460 | -44,460 | 0 | **PASS** |

**Result**: 16/16 workloads matched with bit-level mathematical equivalence (`Difference = 0`). For detailed logs and analysis, see [docs/verification.md](docs/verification.md).

---

## 8. FPGA Implementation & Post-Route Results

Post-implementation reports generated via Vivado 2026.1 on `xc7z010clg400-1`:

### 8.1 Resource Utilization

| Resource | Used | Available | Utilization (%) |
| :--- | :---: | :---: | :---: |
| **Slice LUTs** | **2,971** | 17,600 | **16.88%** |
| ├── LUT as Logic | 2,947 | 17,600 | 16.74% |
| └── LUT as Distributed RAM | 24 | 6,000 | 0.40% |
| **Slice Registers (FFs)** | **878** | 35,200 | **2.49%** |
| **Occupied Slices** | **931** | 4,400 | **21.16%** |
| **CARRY4 Chains** | **438** | 4,400 | **9.95%** |
| **DSP48E1 Blocks** | **0** | 80 | **0.00%** (100% of DSPs free) |
| **Block RAM (BRAM Tile)** | **0** | 60 | **0.00%** (100% of BRAM free) |

### 8.2 Timing Performance Summary

| Metric | Post-Routing Value | Target Constraint | Margin |
| :--- | :---: | :---: | :---: |
| **Setup Slack (WNS)** | **+0.256 ns** | $\ge 0.000\text{ ns}$ | **MET (+256 ps margin)** |
| **Total Negative Slack (TNS)** | **0.000 ns** | $0.000\text{ ns}$ | **0 failing endpoints** |
| **Hold Slack (WHS)** | **+0.029 ns** | $\ge 0.000\text{ ns}$ | **MET (+29 ps margin)** |
| **Pulse Width Slack (WPWS)** | **+3.750 ns** | $\ge 0.000\text{ ns}$ | **MET** |
| **Achieved Clock Frequency** | **100.000 MHz** | 100.000 MHz | **Timing Closed** |
| **Maximum Frequency ($F_{\max}$)** | **102.63 MHz** | — | — |

Detailed timing paths and power breakdown are available in [docs/implementation.md](docs/implementation.md) and [results/implementation/](results/implementation/).

---

## 9. Repository Structure

```
git/
├── rtl/                                # Synthesizable SystemVerilog RTL sources
│   ├── accumulator.sv                  # Spatial reduction tree & multi-cycle accumulator
│   ├── adaptive_controller.sv          # 3-state control FSM orchestrating chunk execution
│   ├── ampc_2.sv                       # 2-lane parallel core with dynamic masking
│   ├── ampc_4.sv                       # 4-lane parallel core
│   ├── ampc_8.sv                       # 8-lane parallel core
│   ├── ampc_16.sv                      # 16-lane parallel core (maximum throughput)
│   ├── ampc_top.sv                     # Top-level accelerator entity (Stage 14 decoupled pipeline)
│   ├── input_buffer.sv                 # On-chip 64x8 activation RAM
│   ├── mac_unit.sv                     # Parameterized signed INT8 MAC unit
│   ├── relu.sv                         # Zero-latency signed INT32 ReLU activation unit
│   ├── weight_buffer.sv                # On-chip 64x8 weight RAM
│   ├── workload_analyzer.sv            # Workload size classifier & telemetry generator
│   └── experimental/                   # Stage 15 DSP exploration sources
│       ├── exp_dsp_eval_top.sv         # Experimental dual-subsystem test top
│       └── mac_unit_dsp.sv             # DSP48E1-inferred registered MAC block
│
├── tb/                                 # Self-checking SystemVerilog testbenches
│   ├── accumulator_tb.sv               # 90 tests
│   ├── adaptive_controller_tb.sv       # 126 tests
│   ├── ampc_2_tb.sv                    # 40 tests
│   ├── ampc_4_tb.sv                    # 45 tests
│   ├── ampc_8_tb.sv                    # 54 tests
│   ├── ampc_16_tb.sv                   # 68 tests
│   ├── ampc_ai_validation_tb.sv        # Stage 16 AI model validation testbench (16 workloads)
│   ├── ampc_top_tb.sv                  # 74 tests (Full datapath integration)
│   ├── input_buffer_tb.sv              # 135 tests
│   ├── mac_unit_tb.sv                  # 43 tests
│   ├── relu_tb.sv                      # 88 tests
│   ├── weight_buffer_tb.sv             # 135 tests
│   ├── workload_analyzer_tb.sv         # 138 tests
│   └── experimental/
│       └── mac_unit_dsp_tb.sv          # 40 tests
│
├── constraints/                        # Physical and timing constraints
│   └── ampc_timing.xdc                 # Primary 100 MHz clock constraint and uncertainty
│
├── docs/                               # Comprehensive technical documentation
│   ├── architecture.md                 # Detailed datapath, FSM, and cycle timing specification
│   ├── verification.md                 # Test suite breakdown, AI validation methodology
│   ├── implementation.md               # Synthesis, placement, routing, and power analysis
│   ├── architecture_notes.md           # Engineering stage-by-stage architecture log
│   ├── stage12_synthesis_report.md     # Stage 12 initial synthesis baseline
│   ├── stage13_baseline_analysis.md    # Stage 13 critical path characterization
│   ├── stage14_timing_optimization.md  # Stage 14 pipeline decoupling timing closure report
│   └── stage15_dsp_investigation.md    # Stage 15 DSP48E1 exploration report
│
├── results/                            # Real Vivado reports and simulation logs
│   ├── simulation/                     # Regression summaries and AI validation logs
│   ├── synthesis/                      # Post-synthesis timing and utilization reports
│   ├── implementation/                 # Post-routing timing, utilization, power, and clock reports
│   └── experimental/                   # Stage 15 experimental DSP reports
│
├── scripts/                            # Automation scripts
│   ├── run_all_tb.ps1                  # PowerShell script executing full 1,036 regression suite
│   ├── run_synth_impl.tcl              # Vivado Tcl script for synthesis and implementation
│   └── run_exp_dsp_synth.tcl           # Vivado Tcl script for Stage 15 DSP exploration
│
├── ai_validation/                      # Python training, quantization, and vector generation
│   ├── train_mnist.py                  # PyTorch MNIST TinyMLP training
│   ├── train_fashion_mnist.py          # PyTorch Fashion-MNIST CNN training
│   ├── train_cifar10.py                # PyTorch CIFAR-10 CNN training
│   ├── quantize.py                     # Symmetric per-tensor INT8 quantization utility
│   ├── export_all_models.py            # Layer weights/activation exporter
│   ├── generate_three_model_vectors.py # Vector extraction for RTL testbench
│   ├── validate.py                     # Python golden reference comparator
│   ├── model/                          # Trained checkpoints and extracted layer weights
│   └── vectors/                        # INT8 text vectors streamed into ampc_ai_validation_tb
│
├── .gitignore                          # Standard Vivado and build artifact ignore rules
└── README.md                           # Main repository documentation
```

---

## 10. How to Reproduce

### 10.1 Running RTL Simulation (Full 1,036 Regression Suite)
Ensure Vivado is installed and in your environment `PATH`:
```powershell
./scripts/run_all_tb.ps1
```

### 10.2 Running AI Model Hardware Validation
```powershell
xvlog -sv rtl/*.sv tb/ampc_ai_validation_tb.sv
xelab -top ampc_ai_validation_tb -snapshot ai_val_snap -timescale 1ns/1ps
xsim ai_val_snap -R
```

### 10.3 Running Synthesis and Implementation
In Vivado batch mode:
```cmd
vivado -mode batch -source scripts/run_synth_impl.tcl
```
Reports will be placed automatically in `results/`.

---

## 11. Current Implementation Status & Roadmap

| Feature / Subsystem | Status | Details |
| :--- | :---: | :--- |
| **Signed INT8 MAC Unit** | **Completed & Verified** | 43/43 tests pass. |
| **AMPC-2 / 4 / 8 / 16 Parallel Cores** | **Completed & Verified** | Dynamic lane masking and operand gating operational. |
| **Spatial & Temporal Accumulator** | **Completed & Verified** | 36-bit reduction tree, multi-cycle accumulation verified. |
| **ReLU Activation Unit** | **Completed & Verified** | Zero-latency combinational clamp. |
| **Input & Weight Buffers** | **Completed & Verified** | 64-depth distributed RAM with write-first bypass. |
| **Adaptive Controller & FSM** | **Completed & Verified** | Multi-cycle chunking tested for $W=1..1000$. |
| **Top-Level Integration (`ampc_top`)**| **Completed & Verified** | Pipeline decoupling closed timing at 100 MHz. |
| **Unit & Integration Regression** | **Completed & Verified** | 1,036 / 1,036 PASS (100% pass rate). |
| **AI Model Hardware Validation** | **Completed & Verified** | 16/16 workloads bit-exact with PyTorch INT8 models ($\Delta = 0$). |
| **FPGA Timing Closure** | **Completed & Verified** | WNS = +0.256 ns @ 100 MHz on Zynq-7010 (`xc7z010clg400-1`). |
| **Hard DSP48E1 Exploration** | **Exploratory Study** | Verified and synthesized in `rtl/experimental/` and `docs/stage15_dsp_investigation.md`. |
| **AXI4-Stream / AXI-Lite Wrapper** | **Planned** | Integrating standard bus interface for Zynq ARM PS DMA transfers. |
| **Output Re-quantization Scaling** | **Planned** | Hardware multiplier for fixed-point integer scaling before writeback. |

---

## 12. Limitations & Design Considerations

1. **Host Interface**: The current top-level exposes native parallel streaming ports (`data_in[0:15]`, `weight[0:15]`) and on-chip buffer write ports. Integration into an SoC requires an AXI4 memory wrapper.
2. **Re-quantization**: Downstream neural network layers typically require scaling 32-bit accumulated values back to INT8 activations using fixed-point scale multiplication and shifting. Currently, raw 32-bit ReLU-clamped outputs are exported.
3. **Buffer Depth**: On-chip buffers are currently parameterized to 64 entries (optimized for distributed LUTRAM). For larger layer footprints, depth parameterization can be expanded to infer Block RAM.

---

## 13. Author

**Anbu Selvan P R**  
VLSI & Digital Systems Design  
Project: Adaptive MAC Processing Core (AMPC) for TinyML Inference
