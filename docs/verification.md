# Verification Strategy & Test Results: AMPC Accelerator

## 1. Verification Strategy Overview

The verification environment for the Adaptive MAC Processing Core (AMPC) employs a dual-tier testing methodology:
1. **SystemVerilog Unit & Integration Regression Suite**: Comprehensive coverage of arithmetic corner cases, bitwidth boundaries, FSM state sequences, buffer collision scenarios, and pipeline timing across 12 dedicated testbenches.
2. **AI Model Hardware Validation**: Direct empirical validation of the top-level RTL (`ampc_top`) against INT8 tensor workloads extracted from three real PyTorch neural-network models trained on standard benchmarks (MNIST, Fashion-MNIST, and CIFAR-10).

All simulation is executed using AMD Vivado 2026.1 (`xvlog`, `xelab`, `xsim`) automated via PowerShell scripts.

---

## 2. Production Unit & Integration Regression Suite

The production regression suite comprises **1,036 deterministic and randomized self-checking test vectors** across all 12 modules.

### 2.1 Test Suite Breakdown

| Module Under Test | Testbench File | Tests Run | Pass Count | Fail Count | Coverage Highlights |
| :--- | :--- | :---: | :---: | :---: | :--- |
| **`mac_unit`** | `tb/mac_unit_tb.sv` | 43 | 43 | 0 | Signed limits ($-128 \times +127$, $-128 \times -128$), zero multiplication, negative product accumulation, sign extension to INT32. |
| **`ampc_2`** | `tb/ampc_2_tb.sv` | 40 | 40 | 0 | 2-lane parallel execution, dynamic mask permutations (`2'b00`, `2'b01`, `2'b10`, `2'b11`), operand gating to zero on disabled lanes. |
| **`ampc_4`** | `tb/ampc_4_tb.sv` | 45 | 45 | 0 | 4-lane parallel throughput, partial masks (`4'b0001` through `4'b1111`), zero accumulation preservation on inactive lanes. |
| **`ampc_8`** | `tb/ampc_8_tb.sv` | 54 | 54 | 0 | 8-lane parallel throughput, arbitrary lane mask combinations, boundary remainders $W=1..8$. |
| **`ampc_16`** | `tb/ampc_16_tb.sv` | 68 | 68 | 0 | 16-lane maximum throughput, power-of-two and non-power-of-two masking, operand suppression. |
| **`accumulator`** | `tb/accumulator_tb.sv` | 90 | 90 | 0 | Spatial adder tree sum across active lanes, 36-bit internal headroom, multi-cycle temporal accumulation, active-low reset. |
| **`relu`** | `tb/relu_tb.sv` | 88 | 88 | 0 | Zero-latency signed thresholding, negative boundary clipping ($-2^{31} \to 0$), positive pass-through ($+2^{31}-1$). |
| **`input_buffer`** | `tb/input_buffer_tb.sv` | 135 | 135 | 0 | 64-depth INT8 memory write/read, address boundaries, write-first forwarding on concurrent read/write to same address. |
| **`weight_buffer`** | `tb/weight_buffer_tb.sv` | 135 | 135 | 0 | Synchronous write, registered synchronous read, write-first collision bypass, unreset memory array synthesizability. |
| **`workload_analyzer`** | `tb/workload_analyzer_tb.sv` | 138 | 138 | 0 | Workload classification ($W=0$, $W \in [1, 16]$, $W > 16$), capacity selection (2, 4, 8, 16), remainder computation. |
| **`adaptive_controller`**| `tb/adaptive_controller_tb.sv`| 126 | 126 | 0 | FSM transitions (`ST_IDLE`, `ST_EXECUTE`, `ST_DONE`), dynamic mask synthesis, multi-cycle chunk decrementing ($W=17, 25, 33, 100$). |
| **`ampc_top`** | `tb/ampc_top_tb.sv` | 74 | 74 | 0 | End-to-end integration, Stage 14 pipeline timing alignment, multi-cycle accumulation handshake (`output_valid`, `done`). |
| **Total Regression** | | **1,036** | **1,036** | **0** | **100.0% PASS Rate (0 Failures, 0 X/Z States)** |

### 2.2 Automated Regression Execution
The regression suite is fully automated via PowerShell:
```powershell
./scripts/run_all_tb.ps1
```

---

## 3. Real TinyML Model Hardware Validation

To verify that the accelerator compute engine accurately computes real neural-network layers, real model weights and input activations were extracted from three PyTorch models trained on public datasets.

> [!IMPORTANT]
> **Validation Scope Clarification**:
> Representative INT8 layer dot products and convolutional receptive fields were extracted from trained models and driven into `ampc_top` to verify arithmetic correctness. We do not claim an entire autonomous multi-layer neural-network pipeline is executed on-chip without an external host or scheduler.

### 3.1 Neural Network Models & Quantization

| Model Name | Topology | Dataset | Software Accuracy | Quantized Scale Factors |
| :--- | :--- | :--- | :---: | :--- |
| **MNIST TinyMLP** | `Linear(784, 32)` $\to$ `ReLU` $\to$ `Linear(32, 10)` | MNIST (28x28 grayscale) | **96.36%** (5 epochs) | $S_x = 0.007874$, $S_w = 0.003923$ |
| **Fashion-MNIST CNN** | `Conv2D(1→8, 3x3)` $\to$ `Conv2D(8→16, 3x3)` $\to$ `FC(784→10)` | Fashion-MNIST (28x28) | **88.59%** (5 epochs) | Conv1: $S_w = 0.007255$, Conv2: $S_w = 0.005574$ |
| **CIFAR-10 CNN** | `Conv2D(3→16, 3x3)` $\to$ `Conv2D(16→32, 3x3)` $\to$ `FC(2048→10)` | CIFAR-10 (32x32 RGB) | **67.64%** (5 epochs) | Conv1: $S_w = 0.006935$, Conv2: $S_w = 0.004068$ |

Quantization formula:
$$\text{scale} = \frac{\max(|x|)}{127}, \quad q = \text{clip}\left(\left\lfloor \frac{x}{\text{scale}} + 0.5 \right\rceil, -128, 127\right)$$

### 3.2 Hardware-vs-Python Equivalence Results

Each workload was simulated using `tb/ampc_ai_validation_tb.sv` in Vivado xsim and evaluated against golden Python floating-point derived INT8 quantized reference values:

| Model | Layer / Feature | MAC Operations ($W$) | Hardware Decomposition | Golden Result | RTL Measured | Difference ($\Delta$) | Status |
| :--- | :--- | :---: | :--- | :---: | :---: | :---: | :---: |
| **MNIST TinyMLP** | FC1 Sub-vector | 9 | AMPC-16 (9 active, 7 masked) | 1,121 | 1,121 | 0 | **PASS** |
| **MNIST TinyMLP** | FC1 Sub-vector | 17 | 16 + 1 (AMPC-16 + AMPC-2) | 2,223 | 2,223 | 0 | **PASS** |
| **MNIST TinyMLP** | FC1 Sub-vector | 25 | 16 + 9 (AMPC-16 + AMPC-16) | 4,465 | 4,465 | 0 | **PASS** |
| **MNIST TinyMLP** | FC1 Sub-vector | 33 | 16 + 16 + 1 (2x AMPC-16 + AMPC-2) | 6,802 | 6,802 | 0 | **PASS** |
| **MNIST TinyMLP** | Complete Neuron 0 Dot-Product | 784 | 49 $\times$ 16 (49 full AMPC-16 chunks) | 40,691 | 40,691 | 0 | **PASS** |
| **Fashion-MNIST CNN** | Conv1 3x3 Kernel (1 channel) | 9 | AMPC-16 (9 active, 7 masked) | 24,812 | 24,812 | 0 | **PASS** |
| **Fashion-MNIST CNN** | Conv2 Slice | 17 | 16 + 1 (AMPC-16 + AMPC-2) | -29,587 | -29,587 | 0 | **PASS** |
| **Fashion-MNIST CNN** | Conv2 Slice | 25 | 16 + 9 (AMPC-16 + AMPC-16) | -27,323 | -27,323 | 0 | **PASS** |
| **Fashion-MNIST CNN** | Conv2 Slice | 33 | 16 + 16 + 1 (2x AMPC-16 + AMPC-2) | -33,189 | -33,189 | 0 | **PASS** |
| **Fashion-MNIST CNN** | Complete 8x3x3 Feature | 72 | 16*4 + 8 (4x AMPC-16 + 1x AMPC-8) | -44,913 | -44,913 | 0 | **PASS** |
| **CIFAR-10 CNN** | Conv1 Single Channel | 9 | AMPC-16 (9 active, 7 masked) | -20,572 | -20,572 | 0 | **PASS** |
| **CIFAR-10 CNN** | Conv2 Slice | 17 | 16 + 1 (AMPC-16 + AMPC-2) | 13,037 | 13,037 | 0 | **PASS** |
| **CIFAR-10 CNN** | Conv2 Slice | 25 | 16 + 9 (AMPC-16 + AMPC-16) | 11,916 | 11,916 | 0 | **PASS** |
| **CIFAR-10 CNN** | Complete RGB 3x3x3 Receptive Field | 27 | 16 + 11 (AMPC-16 + AMPC-16) | -24,979 | -24,979 | 0 | **PASS** |
| **CIFAR-10 CNN** | Conv2 Slice | 33 | 16 + 16 + 1 (2x AMPC-16 + AMPC-2) | -6,345 | -6,345 | 0 | **PASS** |
| **CIFAR-10 CNN** | Complete 16x3x3 Receptive Field | 144 | 16 $\times$ 9 (9 full AMPC-16 chunks) | -44,460 | -44,460 | 0 | **PASS** |

### 3.3 Verification Findings
1. **Bit-Exact Arithmetic**: All 16 tested layer configurations achieved $\Delta = 0$ error against the Python quantized model.
2. **Noise Isolation on Masked Lanes**: During testing, unneeded lanes were driven with synthetic pseudo-random noise; the zero-gating logic verified that masked lanes contribute strictly zero to the spatial accumulation.
3. **Multi-Cycle Accumulator Stability**: Workloads spanning up to 49 consecutive clock cycles (e.g., $W=784$) accumulated without intermediate overflow or data leakage.
