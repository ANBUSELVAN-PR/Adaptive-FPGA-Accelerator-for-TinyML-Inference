"""
Compute Python Golden Results for all 16 Workloads across 3 Models
"""

import os
import json
import numpy as np

def compute_golden(act, wgt):
    running_sum = 0
    for a, w in zip(act, wgt):
        prod = int(np.int16(int(a) * int(w)))
        running_sum += prod
        running_sum = int(np.int32(running_sum))
    relu_val = max(running_sum, 0)
    return running_sum, relu_val

def run_golden_evaluation():
    print("==================================================")
    print(" STAGE 16: COMPUTING GOLDEN FOR 3 MODELS          ")
    print("==================================================")

    vectors_dir = os.path.join(os.path.dirname(__file__), 'vectors')
    results_dir = os.path.join(os.path.dirname(__file__), 'results')
    os.makedirs(results_dir, exist_ok=True)

    manifest_file = os.path.join(vectors_dir, 'three_model_manifest.json')
    with open(manifest_file, 'r') as f:
        manifest = json.load(f)

    results = {}
    print(f"{'Key':<16} | {'Model':<18} | {'Layer':<6} | {'W':<4} | {'Chunks':<6} | {'Dot Product':<12} | {'ReLU Out':<10}")
    print("-" * 84)

    for key, info in manifest.items():
        act = np.load(os.path.join(vectors_dir, f"{key}_act.npy"))
        wgt = np.load(os.path.join(vectors_dir, f"{key}_wgt.npy"))
        dot, relu = compute_golden(act, wgt)

        results[key] = {
            'model': info['model'],
            'layer': info['layer'],
            'op_type': info['op_type'],
            'workload_size': info['workload_size'],
            'decomp': info['decomp'],
            'chunks': info['chunks'],
            'raw_mac_sum': dot,
            'relu_out': relu
        }

        print(f"{key:<16} | {info['model']:<18} | {info['layer']:<6} | {info['workload_size']:<4} | {info['chunks']:<6} | {dot:<12} | {relu:<10}")

    out_file = os.path.join(results_dir, 'three_model_golden_results.json')
    with open(out_file, 'w') as f:
        json.dump(results, f, indent=4)

    print("-" * 84)
    print(f"Saved golden results to: {out_file}")
    print("==================================================")

if __name__ == '__main__':
    run_golden_evaluation()
