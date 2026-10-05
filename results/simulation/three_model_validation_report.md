# Three-Model AI Validation Report: Adaptive MAC Processing Core (AMPC)

## Executive Summary
This report documents the hardware arithmetic validation of the **Adaptive MAC Processing Core (AMPC)** architecture across representative INT8 workloads extracted from **three trained TinyML neural-network models**:
1. **MNIST TinyMLP** (Fully-connected classification)
2. **Fashion-MNIST TinyML CNN** (Grayscale convolutional classification)
3. **CIFAR-10 TinyML CNN** (Color RGB convolutional classification)

> [!IMPORTANT]
> **Scientific Accuracy Statement**:
> The AMPC architecture was validated using representative INT8 MAC workloads extracted from three trained TinyML neural-network models. We do **not** claim that complete neural networks were implemented end-to-end on the FPGA fabric. The validation proves that the hardware compute engine faithfully executes real quantized neural network dot-product and convolution tensor workloads with bit-level mathematical equivalence (`Difference = 0`) across all adaptive decomposition configurations.

---

## 1. Model Descriptions & Training Results

All three models were trained using PyTorch with realistic TinyML constraints suitable for edge deployment.

| Model | Architecture | Dataset Details | Epochs | Parameters | Test Accuracy | Model Checkpoint |
|---|---|---|:---:|:---:|:---:|---|
| **MNIST TinyMLP** | `Linear(784, 32)` $\rightarrow$ `ReLU` $\rightarrow$ `Linear(32, 10)` | 28×28 Grayscale, 10 classes | 5 | 25,450 | **96.36%** | `ai_validation/model/mnist_tinymlp.pth` |
| **Fashion-MNIST TinyML CNN** | `Conv2D(1→8, 3×3)` $\rightarrow$ `MaxPool` $\rightarrow$ `Conv2D(8→16, 3×3)` $\rightarrow$ `MaxPool` $\rightarrow$ `FC(784→10)` | 28×28 Grayscale, 10 classes | 5 | 9,098 | **88.59%** | `ai_validation/model/fashion_mnist_cnn.pth` |
| **CIFAR-10 TinyML CNN** | `Conv2D(3→16, 3×3)` $\rightarrow$ `MaxPool` $\rightarrow$ `Conv2D(16→32, 3×3)` $\rightarrow$ `MaxPool` $\rightarrow$ `FC(2048→10)` | 32×32×3 Color RGB, 10 classes | 5 | 25,578 | **67.64%** | `ai_validation/model/cifar10_cnn.pth` |

*Note: Model accuracy represents software model accuracy evaluated on test sets. RTL equivalence confirms hardware arithmetic correctness.*

---

## 2. INT8 Quantization Methodology

Symmetric per-tensor signed INT8 quantization was applied to the extracted model weights and activations:

$$\text{scale} = \frac{\max(|x|)}{127}$$

$$q = \text{clip}\left(\left\lfloor \frac{x}{\text{scale}} + 0.5 \right\rceil, -128, 127\right)$$

- Inputs and weights are signed 8-bit integers (`[-128, 127]`).
- Individual products produce signed 16-bit intermediate values.
- Accumulation maintains full 32-bit signed precision without overflow or rounding noise.
- Quantized scale values:
  - MNIST: $S_x = 0.007874$, $S_w = 0.003923$
  - Fashion-MNIST Conv1: $S_x = 0.007874$, $S_w = 0.007255$
  - Fashion-MNIST Conv2: $S_x = 0.024227$, $S_w = 0.005574$
  - CIFAR-10 Conv1: $S_x = 0.007874$, $S_w = 0.006935$
  - CIFAR-10 Conv2: $S_x = 0.022986$, $S_w = 0.004068$

---

## 3. Representative Real MAC Workload Extraction

Rather than arbitrary synthetic vectors, workloads were extracted from actual layer dot products:
- **Convolution receptive field MAC count**: $\text{kernel\_h} \times \text{kernel\_w} \times C_{\text{in}}$
  - Fashion-MNIST Conv1: $3 \times 3 \times 1 = 9$ MACs (single receptive field)
  - Fashion-MNIST Conv2: $3 \times 3 \times 8 = 72$ MACs (complete 8-channel receptive field)
  - CIFAR-10 Conv1: $3 \times 3 \times 3 = 27$ MACs (complete RGB 3-channel receptive field)
  - CIFAR-10 Conv2: $3 \times 3 \times 16 = 144$ MACs (complete 16-channel receptive field)
- **Arbitrary sub-channel and boundary workloads**: $W = 9, 17, 25, 33$ testing multi-chunk adaptive decomposition boundaries across convolutional and fully-connected layers.
- **Full FC1 Neuron Dot-Product**: $W = 784$ MACs (entire input layer reduction).

---

## 4. Hardware Verification & RTL Equivalence Table

Each workload was executed on the frozen Stage 14 production AMPC RTL (`xc7z010clg400-1`) via Vivado 2026.1 xsim and compared against the Python golden reference arithmetic.

| Model | Layer | Operation | MACs | AMPC Decomposition | Python Golden | RTL Measured | Difference | Status |
|---|---|---|---:|---|---:|---:|---:|:---:|
| **MNIST TinyMLP** | FC1 | Fully-Connected Dot-Product | 9 | AMPC-16 (9 active) | 1,121 | 1,121 | 0 | **PASS** |
| **MNIST TinyMLP** | FC1 | Fully-Connected Dot-Product | 17 | 16 + 1 (AMPC-16 + AMPC-2) | 2,223 | 2,223 | 0 | **PASS** |
| **MNIST TinyMLP** | FC1 | Fully-Connected Dot-Product | 25 | 16 + 9 (AMPC-16 + AMPC-16) | 4,465 | 4,465 | 0 | **PASS** |
| **MNIST TinyMLP** | FC1 | Fully-Connected Dot-Product | 33 | 16 + 16 + 1 (2x AMPC-16 + AMPC-2) | 6,802 | 6,802 | 0 | **PASS** |
| **MNIST TinyMLP** | FC1 | Fully-Connected Dot-Product | 784 | 49 x 16 (49x AMPC-16) | 40,691 | 40,691 | 0 | **PASS** |
| **Fashion-MNIST CNN** | Conv1 | Conv2D 3x3 Kernel (1 channel) | 9 | AMPC-16 (9 active) | 24,812 | 24,812 | 0 | **PASS** |
| **Fashion-MNIST CNN** | Conv2 | Conv2D Channel Slice (17 ops) | 17 | 16 + 1 (AMPC-16 + AMPC-2) | -29,587 | -29,587 | 0 | **PASS** |
| **Fashion-MNIST CNN** | Conv2 | Conv2D Channel Slice (25 ops) | 25 | 16 + 9 (AMPC-16 + AMPC-16) | -27,323 | -27,323 | 0 | **PASS** |
| **Fashion-MNIST CNN** | Conv2 | Conv2D Channel Slice (33 ops) | 33 | 16 + 16 + 1 (2x AMPC-16 + AMPC-2) | -33,189 | -33,189 | 0 | **PASS** |
| **Fashion-MNIST CNN** | Conv2 | Complete Conv2D 8x3x3 Feature | 72 | 16*4 + 8 (4x AMPC-16 + 1x AMPC-8) | -44,913 | -44,913 | 0 | **PASS** |
| **CIFAR-10 CNN** | Conv1 | Conv2D Single-Channel Slice | 9 | AMPC-16 (9 active) | -20,572 | -20,572 | 0 | **PASS** |
| **CIFAR-10 CNN** | Conv2 | Conv2D Channel Slice (17 ops) | 17 | 16 + 1 (AMPC-16 + AMPC-2) | 13,037 | 13,037 | 0 | **PASS** |
| **CIFAR-10 CNN** | Conv2 | Conv2D Channel Slice (25 ops) | 25 | 16 + 9 (AMPC-16 + AMPC-16) | 11,916 | 11,916 | 0 | **PASS** |
| **CIFAR-10 CNN** | Conv1 | Complete Conv2D RGB 3x3x3 Feature | 27 | 16 + 11 (AMPC-16 + AMPC-16) | -24,979 | -24,979 | 0 | **PASS** |
| **CIFAR-10 CNN** | Conv2 | Conv2D Channel Slice (33 ops) | 33 | 16 + 16 + 1 (2x AMPC-16 + AMPC-2) | -6,345 | -6,345 | 0 | **PASS** |
| **CIFAR-10 CNN** | Conv2 | Complete Conv2D 16x3x3 Feature | 144 | 16*9 (9x AMPC-16) | -44,460 | -44,460 | 0 | **PASS** |

**Summary of AI Validation**:
- **Total Workloads Tested**: 16 / 16
- **Bit-Level Matches**: 16 / 16 (100%)
- **Mismatches / Errors**: 0
- **Difference**: 0 across all testcases

---

## 5. Production Regression Verification

Following AI validation, the comprehensive 1,036-test production regression suite was executed on the frozen Stage 14 RTL:

```
==============================================================================
                  RUNNING FULL REGRESSION SUITE (1,036 TESTS)                
==============================================================================
>>> Running mac_unit_tb...            Passed=43 / Expected=43, Failed=0
>>> Running ampc_2_tb...              Passed=40 / Expected=40, Failed=0
>>> Running ampc_4_tb...              Passed=45 / Expected=45, Failed=0
>>> Running ampc_8_tb...              Passed=54 / Expected=54, Failed=0
>>> Running ampc_16_tb...             Passed=68 / Expected=68, Failed=0
>>> Running accumulator_tb...         Passed=90 / Expected=90, Failed=0
>>> Running relu_tb...                Passed=88 / Expected=88, Failed=0
>>> Running input_buffer_tb...        Passed=135 / Expected=135, Failed=0
>>> Running weight_buffer_tb...       Passed=135 / Expected=135, Failed=0
>>> Running workload_analyzer_tb...   Passed=138 / Expected=138, Failed=0
>>> Running adaptive_controller_tb... Passed=126 / Expected=126, Failed=0
>>> Running ampc_top_tb...            Passed=74 / Expected=74, Failed=0
==============================================================================
REGRESSION SUMMARY: Total Passed: 1036 / 1036, Total Failed: 0
==============================================================================
```

- **Regression Result**: **1,036 / 1,036 PASS (0 Failures, 0 X/Z)**
- **RTL Integrity**: All production modules remain completely frozen and unmodified.

---

## 6. Physical Implementation Metrics (Frozen Stage 14 Reference)
For completeness, the physical implementation metrics on AMD Zynq-7010 (`xc7z010clg400-1`) synthesized and implemented in Vivado 2026.1 remain:
- **Slice LUTs**: 2,971 (16.88%)
- **Slice Registers (FF)**: 878 (2.49%)
- **BRAM**: 0
- **DSP48E1**: 0 (Fully LUT-based architecture)
- **Worst Negative Slack (WNS)**: +0.256 ns
- **Worst Hold Slack (WHS)**: +0.029 ns
- **Fmax**: 102.63 MHz
- **Estimated Total On-Chip Power**: 0.127 W
