"""
Generate Representative MAC Workloads for All Three Models
Models:
  Model 1: MNIST TinyMLP
    - W=9, W=17, W=25, W=33, W=784 (FC1 Neuron 0)
  Model 2: Fashion-MNIST TinyML CNN
    - W=9   (Conv1 3x3 filter, single input channel: 1x3x3 = 9 MACs)
    - W=17  (Conv2 channel-slice: 16+1 MACs)
    - W=25  (Conv2 channel-slice: 16+9 MACs)
    - W=33  (Conv2 channel-slice: 16+16+1 MACs)
    - W=72  (Conv2 complete 3x3 filter across all 8 input channels: 8x3x3 = 72 MACs)
    - W=784 (FC Layer Neuron 0: 784 MACs)
  Model 3: CIFAR-10 TinyML CNN
    - W=9   (Conv1 spatial 3x3 slice: 9 MACs)
    - W=17  (Conv2 channel-slice: 16+1 MACs)
    - W=25  (Conv2 channel-slice: 16+9 MACs)
    - W=27  (Conv1 complete 3x3 filter across 3 RGB channels: 3x3x3 = 27 MACs)
    - W=33  (Conv2 channel-slice: 16+16+1 MACs)
    - W=144 (Conv2 complete 3x3 filter across all 16 input channels: 16x3x3 = 144 MACs)
"""

import os
import json
import numpy as np

def quantize_symmetric(values: np.ndarray):
    max_abs = float(np.max(np.abs(values)))
    scale = 1.0 if max_abs == 0.0 else max_abs / 127.0
    q = np.round(values / scale).astype(np.int32)
    q = np.clip(q, -128, 127).astype(np.int8)
    return q, scale

def generate_three_model_vectors():
    print("==================================================")
    print(" STAGE 16: GENERATING WORKLOADS FOR 3 MODELS      ")
    print("==================================================")

    model_dir = os.path.join(os.path.dirname(__file__), 'model')
    vectors_dir = os.path.join(os.path.dirname(__file__), 'vectors')
    os.makedirs(vectors_dir, exist_ok=True)

    manifest = {}

    # =========================================================================
    # MODEL 1: MNIST MLP
    # =========================================================================
    print(">>> Generating Vectors for Model 1 (MNIST MLP)...")
    m1_w = np.load(os.path.join(model_dir, 'm1_fc1_weight.npy')) # (32, 784)
    m1_x = np.load(os.path.join(model_dir, 'sample_input_784.npy')) # (784,)
    m1_w_q, _ = quantize_symmetric(m1_w[0, :])
    m1_x_q, _ = quantize_symmetric(m1_x)

    for w_size in [9, 17, 25, 33, 784]:
        name = f"m1_mnist_w{w_size}"
        act = m1_x_q[:w_size]
        wgt = m1_w_q[:w_size]
        np.save(os.path.join(vectors_dir, f"{name}_act.npy"), act)
        np.save(os.path.join(vectors_dir, f"{name}_wgt.npy"), wgt)
        with open(os.path.join(vectors_dir, f"{name}_act.txt"), 'w') as f:
            for v in act: f.write(f"{int(v)}\n")
        with open(os.path.join(vectors_dir, f"{name}_wgt.txt"), 'w') as f:
            for v in wgt: f.write(f"{int(v)}\n")

        manifest[name] = {
            'model': 'MNIST TinyMLP',
            'layer': 'FC1',
            'op_type': 'Fully-Connected Dot-Product',
            'workload_size': w_size,
            'decomp': "AMPC-16 (9 lanes active)" if w_size == 9 else
                      "16 + 1 (AMPC-16 + AMPC-2)" if w_size == 17 else
                      "16 + 9 (AMPC-16 + AMPC-16 partial)" if w_size == 25 else
                      "16 + 16 + 1 (2x AMPC-16 + AMPC-2)" if w_size == 33 else
                      "49 x 16 (49x AMPC-16 chunks)",
            'chunks': 1 if w_size == 9 else 2 if w_size in [17, 25] else 3 if w_size == 33 else 49
        }

    # =========================================================================
    # MODEL 2: Fashion-MNIST CNN
    # =========================================================================
    print(">>> Generating Vectors for Model 2 (Fashion-MNIST CNN)...")
    # Conv1: Filter 0 has shape (1, 3, 3) = 9 weights
    m2_c1_w = np.load(os.path.join(model_dir, 'm2_conv1_weight.npy')) # (8, 1, 3, 3)
    m2_c1_x = np.load(os.path.join(model_dir, 'm2_conv1_act_in.npy')) # (28, 28)
    # Extract 3x3 patch at center (14, 14)
    m2_c1_patch = m2_c1_x[13:16, 13:16].flatten() # 9 elements
    m2_c1_filt0 = m2_c1_w[0, 0, :, :].flatten()   # 9 elements
    m2_c1_patch_q, _ = quantize_symmetric(m2_c1_patch)
    m2_c1_filt0_q, _ = quantize_symmetric(m2_c1_filt0)

    # Conv2: Filter 0 has shape (8, 3, 3) = 72 weights
    m2_c2_w = np.load(os.path.join(model_dir, 'm2_conv2_weight.npy')) # (16, 8, 3, 3)
    m2_c2_x = np.load(os.path.join(model_dir, 'm2_conv2_act_in.npy')) # (8, 14, 14)
    # Extract 8 x (3x3) patch at center (7, 7)
    m2_c2_patch = m2_c2_x[:, 6:9, 6:9].flatten() # 8 * 9 = 72 elements
    m2_c2_filt0 = m2_c2_w[0, :, :, :].flatten()   # 72 elements
    m2_c2_patch_q, _ = quantize_symmetric(m2_c2_patch)
    m2_c2_filt0_q, _ = quantize_symmetric(m2_c2_filt0)

    # Save Fashion-MNIST Workloads:
    # W=9 (Conv1 3x3)
    f_workloads = [
        ('m2_fashion_w9', m2_c1_patch_q[:9], m2_c1_filt0_q[:9], 'Conv1', 'Conv2D 3x3 Kernel (1 channel)', 9, 'AMPC-16 (9 lanes active)', 1),
        ('m2_fashion_w17', m2_c2_patch_q[:17], m2_c2_filt0_q[:17], 'Conv2', 'Conv2D Channel Slice (17 ops)', 17, '16 + 1 (AMPC-16 + AMPC-2)', 2),
        ('m2_fashion_w25', m2_c2_patch_q[:25], m2_c2_filt0_q[:25], 'Conv2', 'Conv2D Channel Slice (25 ops)', 25, '16 + 9 (AMPC-16 + AMPC-16 partial)', 2),
        ('m2_fashion_w33', m2_c2_patch_q[:33], m2_c2_filt0_q[:33], 'Conv2', 'Conv2D Channel Slice (33 ops)', 33, '16 + 16 + 1 (2x AMPC-16 + AMPC-2)', 3),
        ('m2_fashion_w72', m2_c2_patch_q[:72], m2_c2_filt0_q[:72], 'Conv2', 'Complete Conv2D 8x3x3 Output Feature', 72, '16*4 + 8 (4x AMPC-16 + 1x AMPC-8)', 5),
    ]

    for name, act, wgt, layer, op_desc, w_size, decomp, chunks in f_workloads:
        np.save(os.path.join(vectors_dir, f"{name}_act.npy"), act)
        np.save(os.path.join(vectors_dir, f"{name}_wgt.npy"), wgt)
        with open(os.path.join(vectors_dir, f"{name}_act.txt"), 'w') as f:
            for v in act: f.write(f"{int(v)}\n")
        with open(os.path.join(vectors_dir, f"{name}_wgt.txt"), 'w') as f:
            for v in wgt: f.write(f"{int(v)}\n")

        manifest[name] = {
            'model': 'Fashion-MNIST CNN',
            'layer': layer,
            'op_type': op_desc,
            'workload_size': w_size,
            'decomp': decomp,
            'chunks': chunks
        }

    # =========================================================================
    # MODEL 3: CIFAR-10 CNN
    # =========================================================================
    print(">>> Generating Vectors for Model 3 (CIFAR-10 CNN)...")
    # Conv1: Filter 0 has shape (3, 3, 3) = 27 weights (RGB 3x3)
    m3_c1_w = np.load(os.path.join(model_dir, 'm3_conv1_weight.npy')) # (16, 3, 3, 3)
    m3_c1_x = np.load(os.path.join(model_dir, 'm3_conv1_act_in.npy')) # (3, 32, 32)
    m3_c1_patch = m3_c1_x[:, 15:18, 15:18].flatten() # 3 * 9 = 27 elements
    m3_c1_filt0 = m3_c1_w[0, :, :, :].flatten()       # 27 elements
    m3_c1_patch_q, _ = quantize_symmetric(m3_c1_patch)
    m3_c1_filt0_q, _ = quantize_symmetric(m3_c1_filt0)

    # Conv2: Filter 0 has shape (16, 3, 3) = 144 weights (16 channels x 3x3)
    m3_c2_w = np.load(os.path.join(model_dir, 'm3_conv2_weight.npy')) # (32, 16, 3, 3)
    m3_c2_x = np.load(os.path.join(model_dir, 'm3_conv2_act_in.npy')) # (16, 16, 16)
    m3_c2_patch = m3_c2_x[:, 7:10, 7:10].flatten() # 16 * 9 = 144 elements
    m3_c2_filt0 = m3_c2_w[0, :, :, :].flatten()     # 144 elements
    m3_c2_patch_q, _ = quantize_symmetric(m3_c2_patch)
    m3_c2_filt0_q, _ = quantize_symmetric(m3_c2_filt0)

    c_workloads = [
        ('m3_cifar_w9', m3_c1_patch_q[:9], m3_c1_filt0_q[:9], 'Conv1', 'Conv2D Single-Channel Slice (9 ops)', 9, 'AMPC-16 (9 lanes active)', 1),
        ('m3_cifar_w17', m3_c2_patch_q[:17], m3_c2_filt0_q[:17], 'Conv2', 'Conv2D Channel Slice (17 ops)', 17, '16 + 1 (AMPC-16 + AMPC-2)', 2),
        ('m3_cifar_w25', m3_c2_patch_q[:25], m3_c2_filt0_q[:25], 'Conv2', 'Conv2D Channel Slice (25 ops)', 25, '16 + 9 (AMPC-16 + AMPC-16 partial)', 2),
        ('m3_cifar_w27', m3_c1_patch_q[:27], m3_c1_filt0_q[:27], 'Conv1', 'Complete Conv2D RGB 3x3x3 Output Feature', 27, '16 + 11 (AMPC-16 + AMPC-16 partial)', 2),
        ('m3_cifar_w33', m3_c2_patch_q[:33], m3_c2_filt0_q[:33], 'Conv2', 'Conv2D Channel Slice (33 ops)', 33, '16 + 16 + 1 (2x AMPC-16 + AMPC-2)', 3),
        ('m3_cifar_w144', m3_c2_patch_q[:144], m3_c2_filt0_q[:144], 'Conv2', 'Complete Conv2D 16x3x3 Output Feature', 144, '16*9 (9 full AMPC-16 chunks)', 9)
    ]

    for name, act, wgt, layer, op_desc, w_size, decomp, chunks in c_workloads:
        np.save(os.path.join(vectors_dir, f"{name}_act.npy"), act)
        np.save(os.path.join(vectors_dir, f"{name}_wgt.npy"), wgt)
        with open(os.path.join(vectors_dir, f"{name}_act.txt"), 'w') as f:
            for v in act: f.write(f"{int(v)}\n")
        with open(os.path.join(vectors_dir, f"{name}_wgt.txt"), 'w') as f:
            for v in wgt: f.write(f"{int(v)}\n")

        manifest[name] = {
            'model': 'CIFAR-10 CNN',
            'layer': layer,
            'op_type': op_desc,
            'workload_size': w_size,
            'decomp': decomp,
            'chunks': chunks
        }

    manifest_file = os.path.join(vectors_dir, 'three_model_manifest.json')
    with open(manifest_file, 'w') as f:
        json.dump(manifest, f, indent=4)

    print("-" * 65)
    print(f"Generated a total of {len(manifest)} validated workloads across 3 models.")
    print(f"Manifest saved to: {manifest_file}")
    print("==================================================")
    print("     ALL THREE MODEL VECTORS GENERATED            ")
    print("==================================================")

if __name__ == '__main__':
    generate_three_model_vectors()
