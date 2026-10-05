"""
Python Golden Reference Model for AMPC Accelerator
Simulates exact bit-accurate hardware arithmetic:
  - INT8 activation x INT8 weight = INT16 product
  - Spatial summation across active lanes
  - INT32 temporal accumulation
  - Optional bias addition
  - Signed INT32 ReLU activation: max(accumulated, 0)
"""

import os
import json
import numpy as np

def compute_ampc_golden(act: np.ndarray, wgt: np.ndarray, bias: int = 0):
    """
    Computes exact bit-accurate AMPC hardware arithmetic.
    act: 1D array of signed INT8
    wgt: 1D array of signed INT8
    bias: signed INT32
    Returns dict:
      - raw_mac_sum: int32
      - bias: int32
      - final_accumulated: int32 (raw_mac_sum + bias)
      - relu_out: int32 (max(final_accumulated, 0))
      - chunk_traces: detailed chunk-by-chunk trace
    """
    assert len(act) == len(wgt), "Activation and weight lengths must match"
    total_len = len(act)

    running_sum = 0
    chunk_traces = []

    # Process in chunks matching AMPC hardware execution
    idx = 0
    rem = total_len
    chunk_idx = 0

    while rem > 0:
        chunk_idx += 1
        if rem <= 2:
            core = "AMPC-2"
            c_size = rem
            c_lanes = 2
        elif rem <= 4:
            core = "AMPC-4"
            c_size = rem
            c_lanes = 4
        elif rem <= 8:
            core = "AMPC-8"
            c_size = rem
            c_lanes = 8
        elif rem <= 16:
            core = "AMPC-16"
            c_size = rem
            c_lanes = 16
        else:
            core = "AMPC-16"
            c_size = 16
            c_lanes = 16

        # Slice current chunk
        act_chunk = act[idx : idx + c_size]
        wgt_chunk = wgt[idx : idx + c_size]

        # Multiplications (INT8 x INT8 -> INT16)
        products = []
        for a, w in zip(act_chunk, wgt_chunk):
            prod = int(np.int16(int(a) * int(w)))
            products.append(prod)

        # Spatial sum for this chunk
        spatial_sum = sum(products)
        running_sum += spatial_sum

        # Ensure running sum adheres to 32-bit two's complement behavior
        running_sum = int(np.int32(running_sum))

        chunk_traces.append({
            'chunk_num': chunk_idx,
            'core': core,
            'chunk_size': c_size,
            'spatial_sum': spatial_sum,
            'running_accum': running_sum
        })

        idx += c_size
        rem -= c_size

    raw_mac_sum = running_sum
    final_acc_with_bias = int(np.int32(raw_mac_sum + bias))
    relu_raw = max(raw_mac_sum, 0)
    relu_with_bias = max(final_acc_with_bias, 0)

    return {
        'workload_size': total_len,
        'chunks_count': len(chunk_traces),
        'raw_mac_sum': raw_mac_sum,
        'bias': bias,
        'final_accum_with_bias': final_acc_with_bias,
        'relu_raw': relu_raw,
        'relu_with_bias': relu_with_bias,
        'chunk_traces': chunk_traces
    }

def run_all_reference_workloads():
    print("==================================================")
    print("     STAGE 15: COMPUTING PYTHON GOLDEN RESULTS    ")
    print("==================================================")

    vectors_dir = os.path.join(os.path.dirname(__file__), 'vectors')
    results_dir = os.path.join(os.path.dirname(__file__), 'results')
    os.makedirs(results_dir, exist_ok=True)

    manifest_path = os.path.join(vectors_dir, 'workloads_manifest.json')
    with open(manifest_path, 'r') as f:
        manifest = json.load(f)

    golden_results = {}

    print(f"{'Workload':<10} | {'Chunks':<7} | {'Raw Dot-Prod':<14} | {'Bias':<8} | {'ReLU Out':<10}")
    print("-" * 60)

    for key, info in manifest.items():
        w_size = info['workload_size']
        bias = info.get('bias', 0)

        act = np.load(os.path.join(vectors_dir, f"workload_{w_size}_act.npy"))
        wgt = np.load(os.path.join(vectors_dir, f"workload_{w_size}_wgt.npy"))

        res = compute_ampc_golden(act, wgt, bias)
        golden_results[f"W_{w_size}"] = res

        print(f"W={w_size:<8} | {res['chunks_count']:<7} | {res['raw_mac_sum']:<14} | {res['bias']:<8} | {res['relu_raw']:<10}")

    # Save golden results
    golden_path = os.path.join(results_dir, 'python_golden_results.json')
    with open(golden_path, 'w') as f:
        json.dump(golden_results, f, indent=4)
    print("-" * 60)
    print(f"Saved golden reference results to: {golden_path}")
    print("==================================================")
    print("      PYTHON REFERENCE COMPUTATION COMPLETED      ")
    print("==================================================")

if __name__ == '__main__':
    run_all_reference_workloads()
