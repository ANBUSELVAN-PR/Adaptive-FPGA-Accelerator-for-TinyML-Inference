"""
Train CIFAR-10 TinyML CNN
Architecture:
  Input: 3 x 32 x 32
  Conv2d(3 -> 16, kernel=3, stride=1, padding=1) -> ReLU -> MaxPool2d(2)
  Conv2d(16 -> 32, kernel=3, stride=1, padding=1) -> ReLU -> MaxPool2d(2)
  Flatten -> Linear(32 * 8 * 8 = 2048 -> 10)
"""

import os
import json
import torch
import torch.nn as nn
import torch.optim as optim
from torchvision import datasets, transforms

torch.manual_seed(42)

class CifarCNN(nn.Module):
    def __init__(self):
        super(CifarCNN, self).__init__()
        self.conv1 = nn.Conv2d(3, 16, kernel_size=3, stride=1, padding=1)
        self.relu1 = nn.ReLU()
        self.pool1 = nn.MaxPool2d(2, 2)
        
        self.conv2 = nn.Conv2d(16, 32, kernel_size=3, stride=1, padding=1)
        self.relu2 = nn.ReLU()
        self.pool2 = nn.MaxPool2d(2, 2)
        
        self.fc = nn.Linear(32 * 8 * 8, 10)

    def forward(self, x):
        x = self.pool1(self.relu1(self.conv1(x)))
        x = self.pool2(self.relu2(self.conv2(x)))
        x = x.view(x.size(0), -1)
        x = self.fc(x)
        return x

def train_and_evaluate():
    print("==================================================")
    print("      STAGE 16: TRAINING CIFAR-10 TinyML CNN      ")
    print("==================================================")

    data_dir = os.path.join(os.path.dirname(__file__), 'data')
    model_dir = os.path.join(os.path.dirname(__file__), 'model')
    os.makedirs(data_dir, exist_ok=True)
    os.makedirs(model_dir, exist_ok=True)

    transform = transforms.Compose([
        transforms.ToTensor(),
        transforms.Normalize((0.4914, 0.4822, 0.4465), (0.2470, 0.2435, 0.2616))
    ])

    print("Loading CIFAR-10 dataset...")
    train_dataset = datasets.CIFAR10(root=data_dir, train=True, download=True, transform=transform)
    test_dataset = datasets.CIFAR10(root=data_dir, train=False, download=True, transform=transform)

    train_loader = torch.utils.data.DataLoader(train_dataset, batch_size=64, shuffle=True)
    test_loader = torch.utils.data.DataLoader(test_dataset, batch_size=1000, shuffle=False)

    device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
    print(f"Training device: {device}")

    model = CifarCNN().to(device)
    criterion = nn.CrossEntropyLoss()
    optimizer = optim.Adam(model.parameters(), lr=0.001)

    epochs = 5
    for epoch in range(1, epochs + 1):
        model.train()
        running_loss = 0.0
        correct = 0
        total = 0
        for batch_idx, (data, target) in enumerate(train_loader):
            data, target = data.to(device), target.to(device)
            optimizer.zero_grad()
            output = model(data)
            loss = criterion(output, target)
            loss.backward()
            optimizer.step()

            running_loss += loss.item() * data.size(0)
            pred = output.argmax(dim=1, keepdim=True)
            correct += pred.eq(target.view_as(pred)).sum().item()
            total += target.size(0)

        epoch_loss = running_loss / total
        epoch_acc = 100. * correct / total
        print(f"Epoch {epoch}/{epochs} | Train Loss: {epoch_loss:.4f} | Train Acc: {epoch_acc:.2f}%")

    model.eval()
    test_loss = 0.0
    test_correct = 0
    test_total = 0
    with torch.no_grad():
        for data, target in test_loader:
            data, target = data.to(device), target.to(device)
            output = model(data)
            test_loss += criterion(output, target).item() * data.size(0)
            pred = output.argmax(dim=1, keepdim=True)
            test_correct += pred.eq(target.view_as(pred)).sum().item()
            test_total += target.size(0)

    test_loss /= test_total
    test_acc = 100. * test_correct / test_total
    print("--------------------------------------------------")
    print(f"Final Test Loss: {test_loss:.4f} | Test Accuracy: {test_acc:.2f}%")
    print("--------------------------------------------------")

    model_path = os.path.join(model_dir, 'cifar10_cnn.pth')
    torch.save(model.state_dict(), model_path)
    print(f"Model saved to: {model_path}")

    # Export intermediate activations on sample test image
    sample_img, sample_lbl = test_dataset[0]
    sample_img_t = sample_img.unsqueeze(0).to(device)
    with torch.no_grad():
        c1_out = model.relu1(model.conv1(sample_img_t))
        p1_out = model.pool1(c1_out)
        c2_out = model.relu2(model.conv2(p1_out))
        p2_out = model.pool2(c2_out)
        flat_out = p2_out.view(1, -1)
        fc_out = model.fc(flat_out)

    torch.save({
        'sample_input': sample_img.cpu(),
        'sample_label': sample_lbl,
        'conv1_act_in': sample_img.cpu(),             # (3, 32, 32)
        'conv2_act_in': p1_out.squeeze(0).cpu(),      # (16, 16, 16)
        'fc_act_in': flat_out.squeeze(0).cpu()         # (2048,)
    }, os.path.join(model_dir, 'cifar10_sample_activations.pt'))

    total_params = sum(p.numel() for p in model.parameters())
    metadata = {
        'model_name': 'CIFAR-10 TinyML CNN',
        'architecture': 'Conv2D(3->16, 3x3) -> MaxPool(2) -> Conv2D(16->32, 3x3) -> MaxPool(2) -> FC(2048->10)',
        'epochs': epochs,
        'test_accuracy_pct': round(test_acc, 2),
        'test_loss': round(test_loss, 4),
        'total_parameters': total_params,
        'layers': {
            'conv1': {'weight_shape': list(model.conv1.weight.shape), 'bias_shape': list(model.conv1.bias.shape), 'macs_per_output': 3 * 3 * 3},
            'conv2': {'weight_shape': list(model.conv2.weight.shape), 'bias_shape': list(model.conv2.bias.shape), 'macs_per_output': 16 * 3 * 3},
            'fc': {'weight_shape': list(model.fc.weight.shape), 'bias_shape': list(model.fc.bias.shape), 'macs_per_output': 2048}
        }
    }
    with open(os.path.join(model_dir, 'cifar10_metadata.json'), 'w') as f:
        json.dump(metadata, f, indent=4)
    print("Metadata saved.")
    print("==================================================")
    print("        CIFAR-10 TRAINING COMPLETED               ")
    print("==================================================")

if __name__ == '__main__':
    train_and_evaluate()
