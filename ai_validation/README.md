# TinyML AI Model Hardware Validation Workflow

This directory contains the Python scripts that establish the algorithmic training, quantization, vector generation, and bit-accurate reference modeling for the **Adaptive MAC Processing Core (AMPC)** hardware accelerator.

---

## 1. Overview & Purpose

The AI validation workflow verifies that the synthesizable SystemVerilog AMPC core (`ampc_top`) correctly executes real-world neural-network dot products and convolutional receptive fields with bit-exact mathematical equivalence ($\Delta = 0$).

The workflow follows a 5-step pipeline:
1. **Model Training**: Train lightweight PyTorch models on standard datasets (MNIST, Fashion-MNIST, CIFAR-10).
2. **Parameter Export**: Extract floating-point weights, biases, and sample input activation tensors.
3. **INT8 Quantization**: Apply symmetric per-tensor INT8 quantization ($[-128, +127]$).
4. **Vector Generation**: Package representative layer dot products and convolution receptive fields into formatted test vectors.
5. **Bit-Exact Cross-Verification**: Compute bit-accurate golden results matching the AMPC hardware datapath (INT8 multiply, 36-bit spatial sum, INT32 accumulation, and INT32 ReLU clamp) and cross-check against RTL simulation logs.

---

## 2. Included Python Source Scripts

| Script Name | Primary Function | Input Dependencies | Outputs Generated |
| :--- | :--- | :--- | :--- |
| **`train_mnist.py`** | Trains the `TinyMLP` architecture (`Linear(784, 32) -> ReLU -> Linear(32, 10)`) on MNIST. | MNIST dataset | Checkpoint `model/tiny_mlp.pth`, metadata |
| **`train_fashion_mnist.py`** | Trains the `FashionCNN` architecture (`Conv2D(1→8) -> Conv2D(8→16) -> FC`) on Fashion-MNIST. | Fashion-MNIST dataset | Checkpoint `model/fashion_mnist_cnn.pth` |
| **`train_cifar10.py`** | Trains the `CIFAR10CNN` architecture (`Conv2D(3→16) -> Conv2D(16→32) -> FC`) on CIFAR-10. | CIFAR-10 dataset | Checkpoint `model/cifar10_cnn.pth` |
| **`export_model.py`** | Exports FC1 weights, biases, and sample input activations for the baseline MNIST MLP into NumPy arrays and text. | `model/tiny_mlp.pth` | `model/fc1_weight.npy`, `sample_input_784.npy` |
| **`export_all_models.py`** | Exports convolution and fully-connected layer parameters across all three trained models. | `.pth` checkpoints in `model/` | Layer `.npy` arrays in `model/` |
| **`quantize.py`** | Implements symmetric per-tensor INT8 quantization (`scale = max(|x|) / 127`, clamped to $[-128, +127]$). | Exported float `.npy` files | Quantized INT8 arrays and scaling factors |
| **`generate_vectors.py`** | Generates baseline MNIST FC1 workload vectors ($W=9, 17, 25, 33, 784$) in text and NumPy formats. | Quantized weights & inputs | Workload vectors in `vectors/` |
| **`generate_three_model_vectors.py`** | Generates 16 representative real layer workloads across MNIST, Fashion-MNIST, and CIFAR-10 models. | Exported model weights | `vectors/` (`.txt` and `.npy`) + manifest |
| **`reference.py`** | Pure Python bit-accurate golden reference model mimicking the AMPC spatial tree and temporal chunking logic. | Activation & weight vectors | Bit-accurate INT32 dot products & ReLU |
| **`compute_three_model_golden.py`** | Evaluates the golden reference model for all 16 workloads defined in `three_model_manifest.json`. | Vector files in `vectors/` | JSON reference results in `results/` |
| **`validate.py`** | End-to-end automation script coordinating parameter export, quantization, vector generation, and RTL simulation. | Models, Python, Vivado xsim | Comparison summary reports |

---

## 3. Required Python Packages

To execute the scripts in this workflow, install the following standard packages:

```bash
pip install torch torchvision numpy
```

- **`torch`** (PyTorch): Model definition, tensor operations, backpropagation, and state-dict checkpoints.
- **`torchvision`**: Standard dataset loaders (`datasets.MNIST`, `datasets.FashionMNIST`, `datasets.CIFAR10`) and tensor transforms.
- **`numpy`**: Array manipulation, vector formatting, and numerical serialization.
- Built-in Python standard libraries: `os`, `sys`, `json`, `subprocess`.

---

## 4. Intentionally Excluded Files

To keep this repository clean, lightweight, and suitable for direct GitHub browser uploads (under GitHub's 100-file per upload limit), the following generated or heavy binary artifacts are intentionally **not** tracked in git:

1. **`data/` (Raw Datasets)**:
   - MNIST, Fashion-MNIST, and CIFAR-10 archives (`.tar.gz`, raw binary IDX files).
   - *Rationale*: These datasets total hundreds of megabytes. They can be downloaded automatically on-demand by setting `download=True` in torchvision dataset loaders.
2. **`model/` (Trained Model Weights & Checkpoints)**:
   - PyTorch checkpoint files (`*.pth`, `*.pt`) and intermediate extracted numpy weights (`*.npy`, `*.txt`).
   - *Rationale*: Binary weight blobs can be regenerated locally at any time using the provided reproducible training scripts (`train_*.py`).
3. **`vectors/` (Generated Intermediate Vector Files)**:
   - Generated `.npy` and `.txt` stimulus vectors.
   - *Rationale*: Can be generated directly from model parameters using `generate_three_model_vectors.py`.
4. **Python cache files (`__pycache__/`, `*.pyc`)**:
   - Runtime bytecode artifacts ignored via `.gitignore`.
5. **Redundant logs and archives (`results.zip`)**:
   - Human-readable verification logs and reports are permanently documented under `results/simulation/`.

---

## 5. How to Reproduce the AI Validation Flow Locally

To regenerate models, extract parameters, and create vectors from scratch:

```bash
# 1. Train the three TinyML models (reproducible seed = 42)
python train_mnist.py
python train_fashion_mnist.py
python train_cifar10.py

# 2. Export layer parameters to NumPy arrays
python export_all_models.py

# 3. Generate quantized INT8 test vectors and manifest
python generate_three_model_vectors.py

# 4. Compute golden Python arithmetic references
python compute_three_model_golden.py
```

---

## 6. Relationship Between Python Golden Flow and RTL Verification

The outputs generated by `generate_three_model_vectors.py` provide the exact stimulus read by the SystemVerilog testbench:
- **Testbench**: [`tb/ampc_ai_validation_tb.sv`](../tb/ampc_ai_validation_tb.sv)
- **DUT**: [`rtl/ampc_top.sv`](../rtl/ampc_top.sv)
- **Comparison**: Each workload's RTL result is compared against the Python golden computation produced by `compute_three_model_golden.py`.

The verified results (all 16 workloads achieving $\Delta = 0$ bit-exact match) are stored in:
- [`results/simulation/three_model_validation_report.md`](../results/simulation/three_model_validation_report.md)
- [`results/simulation/three_model_rtl_log.txt`](../results/simulation/three_model_rtl_log.txt)
- [`results/simulation/model_comparison.csv`](../results/simulation/model_comparison.csv)
