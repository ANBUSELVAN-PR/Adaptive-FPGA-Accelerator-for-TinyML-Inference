"""
Export and Extract Parameters and Real Operands for:
  Model 1: MNIST TinyMLP
  Model 2: Fashion-MNIST TinyML CNN
  Model 3: CIFAR-10 TinyML CNN
"""

import os
import torch
import numpy as np

def export_all_models():
    print("==================================================")
    print("   STAGE 16: EXPORTING ALL THREE TINYML MODELS    ")
    print("==================================================")

    model_dir = os.path.join(os.path.dirname(__file__), 'model')

    # ----------------------------------------------------
    # Model 1: MNIST MLP
    # ----------------------------------------------------
    print(">>> Exporting Model 1: MNIST MLP...")
    m1_state = torch.load(os.path.join(model_dir, 'tiny_mlp.pth'), map_location='cpu', weights_only=True)
    np.save(os.path.join(model_dir, 'm1_fc1_weight.npy'), m1_state['fc1.weight'].numpy())
    np.save(os.path.join(model_dir, 'm1_fc1_bias.npy'), m1_state['fc1.bias'].numpy())

    # ----------------------------------------------------
    # Model 2: Fashion-MNIST CNN
    # ----------------------------------------------------
    print(">>> Exporting Model 2: Fashion-MNIST CNN...")
    m2_state = torch.load(os.path.join(model_dir, 'fashion_mnist_cnn.pth'), map_location='cpu', weights_only=True)
    m2_c1_w = m2_state['conv1.weight'].numpy() # (8, 1, 3, 3)
    m2_c1_b = m2_state['conv1.bias'].numpy()   # (8,)
    m2_c2_w = m2_state['conv2.weight'].numpy() # (16, 8, 3, 3)
    m2_c2_b = m2_state['conv2.bias'].numpy()   # (16,)
    m2_fc_w = m2_state['fc.weight'].numpy()    # (10, 784)
    m2_fc_b = m2_state['fc.bias'].numpy()      # (10,)

    np.save(os.path.join(model_dir, 'm2_conv1_weight.npy'), m2_c1_w)
    np.save(os.path.join(model_dir, 'm2_conv1_bias.npy'), m2_c1_b)
    np.save(os.path.join(model_dir, 'm2_conv2_weight.npy'), m2_c2_w)
    np.save(os.path.join(model_dir, 'm2_conv2_bias.npy'), m2_c2_b)
    np.save(os.path.join(model_dir, 'm2_fc_weight.npy'), m2_fc_w)
    np.save(os.path.join(model_dir, 'm2_fc_bias.npy'), m2_fc_b)

    # Load intermediate activations from real sample image
    m2_act = torch.load(os.path.join(model_dir, 'fashion_sample_activations.pt'), weights_only=True)
    np.save(os.path.join(model_dir, 'm2_conv1_act_in.npy'), m2_act['conv1_act_in'].numpy())
    np.save(os.path.join(model_dir, 'm2_conv2_act_in.npy'), m2_act['conv2_act_in'].numpy())
    np.save(os.path.join(model_dir, 'm2_fc_act_in.npy'), m2_act['fc_act_in'].numpy())

    # ----------------------------------------------------
    # Model 3: CIFAR-10 CNN
    # ----------------------------------------------------
    print(">>> Exporting Model 3: CIFAR-10 CNN...")
    m3_state = torch.load(os.path.join(model_dir, 'cifar10_cnn.pth'), map_location='cpu', weights_only=True)
    m3_c1_w = m3_state['conv1.weight'].numpy() # (16, 3, 3, 3)
    m3_c1_b = m3_state['conv1.bias'].numpy()   # (16,)
    m3_c2_w = m3_state['conv2.weight'].numpy() # (32, 16, 3, 3)
    m3_c2_b = m3_state['conv2.bias'].numpy()   # (32,)
    m3_fc_w = m3_state['fc.weight'].numpy()    # (10, 2048)
    m3_fc_b = m3_state['fc.bias'].numpy()      # (10,)

    np.save(os.path.join(model_dir, 'm3_conv1_weight.npy'), m3_c1_w)
    np.save(os.path.join(model_dir, 'm3_conv1_bias.npy'), m3_c1_b)
    np.save(os.path.join(model_dir, 'm3_conv2_weight.npy'), m3_c2_w)
    np.save(os.path.join(model_dir, 'm3_conv2_bias.npy'), m3_c2_b)
    np.save(os.path.join(model_dir, 'm3_fc_weight.npy'), m3_fc_w)
    np.save(os.path.join(model_dir, 'm3_fc_bias.npy'), m3_fc_b)

    m3_act = torch.load(os.path.join(model_dir, 'cifar10_sample_activations.pt'), weights_only=True)
    np.save(os.path.join(model_dir, 'm3_conv1_act_in.npy'), m3_act['conv1_act_in'].numpy())
    np.save(os.path.join(model_dir, 'm3_conv2_act_in.npy'), m3_act['conv2_act_in'].numpy())
    np.save(os.path.join(model_dir, 'm3_fc_act_in.npy'), m3_act['fc_act_in'].numpy())

    print("==================================================")
    print("      ALL THREE MODELS EXPORTED SUCCESSFULLY      ")
    print("==================================================")

if __name__ == '__main__':
    export_all_models()
