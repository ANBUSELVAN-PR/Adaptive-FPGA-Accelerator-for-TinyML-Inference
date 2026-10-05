# Stage 15: TinyML AI Model Hardware Validation Report

### Model Architecture
- **Task**: Real MNIST Digit Classification
- **Topology**: `Linear(784, 32) -> ReLU -> Linear(32, 10)`
- **Trained Parameters**: 25,450 parameters
- **Trained Test Accuracy**: **96.36%** (5 epochs on MNIST test set)
- **Quantization Scheme**: Symmetric per-tensor signed INT8 (`scale = max(|x|)/127`)
- **Quantized Data Format**: Signed INT8 activations, signed INT8 weights, signed INT32 accumulation, signed INT32 ReLU

---

### Production Hardware Target
- **Device**: AMD/Xilinx Zynq-7010 (`xc7z010clg400-1`), Vivado 2026.1
- **Baseline**: Stage 14 Frozen Production Top-Level (`ampc_top.sv`)
- **Clock**: 100.000 MHz ($WNS = +0.256\text{ ns}$, clean timing closure)
- **Throughput**: 1 chunk per clock cycle

---

### AMPC Validation Workloads & Empirical Verification

The 784-MAC workload represents **Neuron 0 of the first fully-connected layer** (`fc1`, 784 inputs $\rightarrow$ 32 outputs). Workloads $W=9, 17, 25, 33$ demonstrate adaptive core selection, lane masking, and multi-cycle remainder chunking across real neural network weights and input activations.

| Workload ($W$) | Adaptive Decomposition | Python Golden Result | RTL Measured Result | Difference ($\Delta$) | Pass / Fail Status |
| :---: | :--- | :---: | :---: | :---: | :---: |
| **9** | AMPC-16 (9 lanes active, 7 masked) | 475 | 475 | 0 | **PASS** |
| **17** | 16 + 1 (AMPC-16 + AMPC-2 lane 0) | 988 | 988 | 0 | **PASS** |
| **25** | 16 + 9 (AMPC-16 + AMPC-16 partial) | 1976 | 1976 | 0 | **PASS** |
| **33** | 16 + 16 + 1 (2x AMPC-16 + AMPC-2) | 3040 | 3040 | 0 | **PASS** |
| **784** | 49 x 16 (49 full AMPC-16 chunks) | 17640 | 17640 | 0 | **PASS** |

---

### Architectural Conclusion
1. **Exact Mathematical Equivalence**: Across all evaluated TinyML workloads (including the complete 784-element dot product comprising 49 consecutive AMPC-16 chunks), the RTL output matched the Python floating-point derived INT8 quantized golden model with **zero arithmetic error (Difference = 0)**.
2. **Adaptive Lane Masking Integrity**: Inactive lanes were driven with random noise during streaming, confirming that lane masking completely isolates unneeded multipliers.
3. **Production RTL Preservation**: Zero lines of the Stage 14 production RTL were altered. The AMPC top-level seamlessly accelerated real deep learning workloads.
