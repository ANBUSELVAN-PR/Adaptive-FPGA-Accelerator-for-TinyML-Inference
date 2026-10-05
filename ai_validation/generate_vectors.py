"""
Generate Real MAC Workloads for AMPC Validation
Workloads:
  - W = 9   (AMPC-16 partial, 9 active lanes masked)
  - W = 17  (AMPC-16 full + AMPC-2 single lane: 16 + 1)
  - W = 25  (AMPC-16 full + AMPC-16 partial 9 lanes: 16 + 9)
  - W = 33  (AMPC-16 + AMPC-16 + AMPC-2: 16 + 16 + 1)
  - W = 784 (49 x AMPC-16 chunks, representing Neuron 0 of FC1)
"""

import os
import json
import numpy as np

def generate_workload_vectors():
    print("==================================================")
    print("     STAGE 15: GENERATING REAL MAC WORKLOADS      ")
    print("==================================================")

    vectors_dir = os.path.join(os.path.dirname(__file__), 'vectors')

    # Load real quantized tensors
    fc1_w_q = np.load(os.path.join(vectors_dir, 'fc1_weight_int8.npy'))     # shape (32, 784)
    input_q = np.load(os.path.join(vectors_dir, 'input_activation_int8.npy')) # shape (784,)
    fc1_b_q = np.load(os.path.join(vectors_dir, 'fc1_bias_int32.npy'))        # shape (32,)

    # Neuron 0 of fc1 layer:
    neuron_idx = 0
    w_neuron = fc1_w_q[neuron_idx, :]  # 784 INT8 weights
    act_784 = input_q                  # 784 INT8 activations
    bias_neuron = int(fc1_b_q[neuron_idx]) # INT32 bias

    workloads = [9, 17, 25, 33, 784]
    workload_manifest = {}

    for w_size in workloads:
        # Extract the first w_size elements from real neuron weights and input activations
        act_slice = act_784[:w_size].astype(np.int8)
        wgt_slice = w_neuron[:w_size].astype(np.int8)

        # Expected adaptive chunk decomposition matching ampc_top architecture:
        if w_size == 9:
            decomp = "1 chunk: AMPC-16 (9 active lanes, 7 masked)"
            chunks = 1
        elif w_size == 17:
            decomp = "2 chunks: 16 + 1 (AMPC-16 full + AMPC-2 single lane)"
            chunks = 2
        elif w_size == 25:
            decomp = "2 chunks: 16 + 9 (AMPC-16 full + AMPC-16 partial 9 lanes)"
            chunks = 2
        elif w_size == 33:
            decomp = "3 chunks: 16 + 16 + 1 (2 x AMPC-16 full + AMPC-2 single lane)"
            chunks = 3
        elif w_size == 784:
            decomp = "49 chunks: 49 x AMPC-16 full (784 MACs)"
            chunks = 49
        else:
            decomp = f"{w_size} elements"
            chunks = (w_size + 15) // 16

        prefix = f"workload_{w_size}"
        np.save(os.path.join(vectors_dir, f"{prefix}_act.npy"), act_slice)
        np.save(os.path.join(vectors_dir, f"{prefix}_wgt.npy"), wgt_slice)

        # Text files formatted for SystemVerilog testbench streaming
        with open(os.path.join(vectors_dir, f"{prefix}_act.txt"), 'w') as f:
            for val in act_slice:
                f.write(f"{int(val)}\n")

        with open(os.path.join(vectors_dir, f"{prefix}_wgt.txt"), 'w') as f:
            for val in wgt_slice:
                f.write(f"{int(val)}\n")

        # In hex format for clean Verilog consumption
        with open(os.path.join(vectors_dir, f"{prefix}_act_hex.txt"), 'w') as f:
            for val in act_slice:
                f.write(f"{int(val) & 0xFF:02X}\n")

        with open(os.path.join(vectors_dir, f"{prefix}_wgt_hex.txt"), 'w') as f:
            for val in wgt_slice:
                f.write(f"{int(val) & 0xFF:02X}\n")

        workload_manifest[f"W_{w_size}"] = {
            'workload_size': w_size,
            'decomposition': decomp,
            'chunk_count': chunks,
            'act_min': int(act_slice.min()),
            'act_max': int(act_slice.max()),
            'wgt_min': int(wgt_slice.min()),
            'wgt_max': int(wgt_slice.max()),
            'bias': bias_neuron if w_size == 784 else 0
        }

        print(f"Generated Workload W={w_size:<4} | Chunks: {chunks:<2} | Decomp: {decomp:<45} | Act: [{act_slice.min():4d}, {act_slice.max():4d}] | Wgt: [{wgt_slice.min():4d}, {wgt_slice.max():4d}]")

    manifest_path = os.path.join(vectors_dir, 'workloads_manifest.json')
    with open(manifest_path, 'w') as f:
        json.dump(workload_manifest, f, indent=4)
    print(f"Saved manifest to: {manifest_path}")
    print("==================================================")
    print("        WORKLOAD GENERATION COMPLETED             ")
    print("==================================================")

if __name__ == '__main__':
    generate_workload_vectors()
