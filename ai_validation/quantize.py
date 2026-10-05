"""
INT8 Quantization Module
Implements symmetric per-tensor INT8 quantization:
  scale = max(abs(values)) / 127
  q = round(values / scale)
  clamp to [-128, 127]
"""

import os
import json
import numpy as np

def quantize_symmetric(values: np.ndarray, tensor_name: str = "tensor"):
    """
    Symmetric per-tensor quantization to signed INT8 [-128, 127].
    Returns (quantized_int8, scale)
    """
    max_abs = float(np.max(np.abs(values)))
    if max_abs == 0.0:
        scale = 1.0
    else:
        scale = max_abs / 127.0

    quantized = np.round(values / scale).astype(np.int32)
    quantized = np.clip(quantized, -128, 127).astype(np.int8)

    print(f"Quantized {tensor_name:<18} | Float range: [{values.min():.5f}, {values.max():.5f}] | Scale: {scale:.6e} | INT8 range: [{quantized.min()}, {quantized.max()}]")
    return quantized, scale

def quantize_model_and_inputs():
    print("==================================================")
    print("      STAGE 15: SYMMETRIC INT8 QUANTIZATION       ")
    print("==================================================")

    model_dir = os.path.join(os.path.dirname(__file__), 'model')
    vectors_dir = os.path.join(os.path.dirname(__file__), 'vectors')
    os.makedirs(vectors_dir, exist_ok=True)

    # Load exported floats
    fc1_w = np.load(os.path.join(model_dir, 'fc1_weight.npy'))
    fc1_b = np.load(os.path.join(model_dir, 'fc1_bias.npy'))
    fc2_w = np.load(os.path.join(model_dir, 'fc2_weight.npy'))
    fc2_b = np.load(os.path.join(model_dir, 'fc2_bias.npy'))
    sample_input = np.load(os.path.join(model_dir, 'sample_input_784.npy'))

    # Quantize weights and input activations
    fc1_w_q, scale_fc1_w = quantize_symmetric(fc1_w, "fc1.weight")
    fc2_w_q, scale_fc2_w = quantize_symmetric(fc2_w, "fc2.weight")
    input_q, scale_input = quantize_symmetric(sample_input, "input_activation")

    # Quantize biases to INT32 using scale_input * scale_weight (standard TinyML quantized bias)
    # bias_q = round(bias / (scale_input * scale_weight))
    scale_fc1_b = scale_input * scale_fc1_w
    fc1_b_q = np.round(fc1_b / scale_fc1_b).astype(np.int32)
    print(f"Quantized {'fc1.bias':<18} | Float range: [{fc1_b.min():.5f}, {fc1_b.max():.5f}] | Scale: {scale_fc1_b:.6e} | INT32 range: [{fc1_b_q.min()}, {fc1_b_q.max()}]")

    # Save quantized arrays in vectors/ and model/
    np.save(os.path.join(vectors_dir, 'fc1_weight_int8.npy'), fc1_w_q)
    np.save(os.path.join(vectors_dir, 'fc2_weight_int8.npy'), fc2_w_q)
    np.save(os.path.join(vectors_dir, 'input_activation_int8.npy'), input_q)
    np.save(os.path.join(vectors_dir, 'fc1_bias_int32.npy'), fc1_b_q)

    # Save scales and quantization configuration
    quant_meta = {
        'rule': 'symmetric per-tensor signed INT8: scale = max(abs(x))/127, q = clip(round(x/scale), -128, 127)',
        'scale_input': scale_input,
        'scale_fc1_weight': scale_fc1_w,
        'scale_fc1_bias': scale_fc1_b,
        'scale_fc2_weight': scale_fc2_w,
        'fc1_weight_int8_min': int(fc1_w_q.min()),
        'fc1_weight_int8_max': int(fc1_w_q.max()),
        'input_activation_int8_min': int(input_q.min()),
        'input_activation_int8_max': int(input_q.max()),
        'fc1_bias_int32_min': int(fc1_b_q.min()),
        'fc1_bias_int32_max': int(fc1_b_q.max())
    }

    with open(os.path.join(vectors_dir, 'quantization_metadata.json'), 'w') as f:
        json.dump(quant_meta, f, indent=4)

    print("--------------------------------------------------")
    print("Quantization completed and saved to ai_validation/vectors/")
    print("==================================================")

if __name__ == '__main__':
    quantize_model_and_inputs()
