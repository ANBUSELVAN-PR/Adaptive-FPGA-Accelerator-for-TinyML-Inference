"""
Export Trained Model Parameters
Extracts fc1.weight, fc1.bias, fc2.weight, fc2.bias from tiny_mlp.pth
Saves both as NumPy (.npy) and formatted text (.txt) files.
"""

import os
import torch
import numpy as np

def export_parameters():
    print("==================================================")
    print("       STAGE 15: EXPORTING MODEL PARAMETERS       ")
    print("==================================================")

    model_dir = os.path.join(os.path.dirname(__file__), 'model')
    model_path = os.path.join(model_dir, 'tiny_mlp.pth')

    if not os.path.exists(model_path):
        raise FileNotFoundError(f"Model file not found at {model_path}")

    state_dict = torch.load(model_path, map_location='cpu', weights_only=True)

    fc1_w = state_dict['fc1.weight'].numpy()  # shape: (32, 784)
    fc1_b = state_dict['fc1.bias'].numpy()    # shape: (32,)
    fc2_w = state_dict['fc2.weight'].numpy()  # shape: (10, 32)
    fc2_b = state_dict['fc2.bias'].numpy()    # shape: (10,)

    params = {
        'fc1_weight': fc1_w,
        'fc1_bias': fc1_b,
        'fc2_weight': fc2_w,
        'fc2_bias': fc2_b
    }

    total_params = 0
    print(f"{'Parameter':<15} | {'Shape':<12} | {'Min Value':<10} | {'Max Value':<10} | {'Count':<8}")
    print("-" * 65)

    for name, arr in params.items():
        count = arr.size
        total_params += count
        min_v = arr.min()
        max_v = arr.max()
        print(f"{name:<15} | {str(arr.shape):<12} | {min_v:<10.5f} | {max_v:<10.5f} | {count:<8}")

        # Save as npy
        npy_path = os.path.join(model_dir, f"{name}.npy")
        np.save(npy_path, arr)

        # Save summary text format
        txt_path = os.path.join(model_dir, f"{name}.txt")
        np.savetxt(txt_path, arr.flatten(), fmt='%.6f')

    print("-" * 65)
    print(f"Total Parameters: {total_params}")

    # Also load sample input image and export as npy/txt
    sample_path = os.path.join(model_dir, 'sample_test_input.pt')
    if os.path.exists(sample_path):
        sample_dict = torch.load(sample_path, weights_only=True)
        img = sample_dict['image'].numpy().flatten()  # shape: (784,)
        lbl = sample_dict['label']
        np.save(os.path.join(model_dir, 'sample_input_784.npy'), img)
        np.savetxt(os.path.join(model_dir, 'sample_input_784.txt'), img, fmt='%.6f')
        print(f"Exported sample test image (label={lbl}): shape {img.shape}, min={img.min():.4f}, max={img.max():.4f}")

    print("==================================================")
    print("        EXPORT COMPLETED SUCCESSFULLY             ")
    print("==================================================")

if __name__ == '__main__':
    export_parameters()
