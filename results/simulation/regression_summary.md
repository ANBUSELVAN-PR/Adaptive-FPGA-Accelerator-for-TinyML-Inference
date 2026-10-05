# Simulation Regression Summary

**Project**: Adaptive MAC Processing Core (AMPC) for TinyML Inference  
**Environment**: AMD Vivado 2026.1 (`xvlog`, `xelab`, `xsim`)  
**Script**: `scripts/run_all_tb.ps1`  
**Execution Status**: **1,036 / 1,036 PASS (100% Pass Rate)**  
**Discrepancies**: 0 Failures, 0 Unknown (X/Z) states

---

## 1. Unit & Subsystem Test Suite Execution

| Testbench | Primary Entity Under Test | RTL Files Simulated | Expected | Passed | Failed | Status |
| :--- | :--- | :--- | :---: | :---: | :---: | :---: |
| `mac_unit_tb.sv` | `mac_unit` | `rtl/mac_unit.sv` | 43 | 43 | 0 | **PASS** |
| `ampc_2_tb.sv` | `ampc_2` | `rtl/mac_unit.sv`, `rtl/ampc_2.sv` | 40 | 40 | 0 | **PASS** |
| `ampc_4_tb.sv` | `ampc_4` | `rtl/mac_unit.sv`, `rtl/ampc_4.sv` | 45 | 45 | 0 | **PASS** |
| `ampc_8_tb.sv` | `ampc_8` | `rtl/mac_unit.sv`, `rtl/ampc_8.sv` | 54 | 54 | 0 | **PASS** |
| `ampc_16_tb.sv` | `ampc_16` | `rtl/mac_unit.sv`, `rtl/ampc_16.sv` | 68 | 68 | 0 | **PASS** |
| `accumulator_tb.sv` | `accumulator` | `rtl/accumulator.sv` | 90 | 90 | 0 | **PASS** |
| `relu_tb.sv` | `relu` | `rtl/relu.sv` | 88 | 88 | 0 | **PASS** |
| `input_buffer_tb.sv` | `input_buffer` | `rtl/input_buffer.sv` | 135 | 135 | 0 | **PASS** |
| `weight_buffer_tb.sv` | `weight_buffer` | `rtl/weight_buffer.sv` | 135 | 135 | 0 | **PASS** |
| `workload_analyzer_tb.sv` | `workload_analyzer` | `rtl/workload_analyzer.sv` | 138 | 138 | 0 | **PASS** |
| `adaptive_controller_tb.sv`| `adaptive_controller`| `rtl/adaptive_controller.sv` | 126 | 126 | 0 | **PASS** |
| `ampc_top_tb.sv` | `ampc_top` | Full Datapath (12 RTL sources) | 74 | 74 | 0 | **PASS** |
| **Total Tests** | | | **1,036** | **1,036** | **0** | **100% PASS** |

---

## 2. AI Model Hardware Validation

Detailed in `results/simulation/three_model_validation_report.md` and logged in `results/simulation/three_model_rtl_log.txt`:
- **Evaluated Models**: MNIST TinyMLP, Fashion-MNIST CNN, CIFAR-10 CNN.
- **Evaluated Workloads**: 16 representative real layer dot-product workloads ($W=9, 17, 25, 27, 33, 72, 144, 784$).
- **Equivalence Result**: All 16 workloads matched Python golden quantized model outputs with **zero arithmetic error ($\Delta = 0$)**.
