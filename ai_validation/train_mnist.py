"""
TinyML MNIST MLP Training Script
Architecture:
  Linear(784, 32) -> ReLU -> Linear(32, 10)
"""

import os
import json
import torch
import torch.nn as nn
import torch.optim as optim
from torchvision import datasets, transforms

# Set reproducible seeds
torch.manual_seed(42)

class TinyMLP(nn.Module):
    def __init__(self):
        super(TinyMLP, self).__init__()
        self.fc1 = nn.Linear(784, 32)
        self.relu = nn.ReLU()
        self.fc2 = nn.Linear(32, 10)

    def forward(self, x):
        x = x.view(-1, 784)
        x = self.fc1(x)
        x = self.relu(x)
        x = self.fc2(x)
        return x

def train_and_evaluate():
    print("==================================================")
    print("      STAGE 15: TRAINING MNIST TinyMLP MODEL      ")
    print("==================================================")

    data_dir = os.path.join(os.path.dirname(__file__), 'data')
    model_dir = os.path.join(os.path.dirname(__file__), 'model')
    os.makedirs(data_dir, exist_ok=True)
    os.makedirs(model_dir, exist_ok=True)

    # MNIST preprocessing: Normalize to [0, 1]
    transform = transforms.Compose([
        transforms.ToTensor(),
        transforms.Normalize((0.1307,), (0.3081,))
    ])

    print("Loading MNIST dataset...")
    train_dataset = datasets.MNIST(root=data_dir, train=True, download=True, transform=transform)
    test_dataset = datasets.MNIST(root=data_dir, train=False, download=True, transform=transform)

    train_loader = torch.utils.data.DataLoader(train_dataset, batch_size=64, shuffle=True)
    test_loader = torch.utils.data.DataLoader(test_dataset, batch_size=1000, shuffle=False)

    device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
    print(f"Training device: {device}")

    model = TinyMLP().to(device)
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

    # Evaluation on Test set
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

    # Save model weights & metadata
    model_path = os.path.join(model_dir, 'tiny_mlp.pth')
    torch.save(model.state_dict(), model_path)
    print(f"Model saved successfully to: {model_path}")

    # Save a sample input test image for inference validation
    sample_img, sample_lbl = test_dataset[0]
    sample_path = os.path.join(model_dir, 'sample_test_input.pt')
    torch.save({'image': sample_img, 'label': sample_lbl}, sample_path)
    print(f"Sample test image saved to: {sample_path}")

    metadata = {
        'model_architecture': 'Linear(784, 32) -> ReLU -> Linear(32, 10)',
        'epochs': epochs,
        'batch_size': 64,
        'learning_rate': 0.001,
        'test_accuracy_pct': round(test_acc, 2),
        'test_loss': round(test_loss, 4),
        'fc1_weight_shape': list(model.fc1.weight.shape),
        'fc1_bias_shape': list(model.fc1.bias.shape),
        'fc2_weight_shape': list(model.fc2.weight.shape),
        'fc2_bias_shape': list(model.fc2.bias.shape)
    }
    meta_path = os.path.join(model_dir, 'model_metadata.json')
    with open(meta_path, 'w') as f:
        json.dump(metadata, f, indent=4)
    print(f"Metadata saved to: {meta_path}")
    print("==================================================")
    print("           TRAINING COMPLETED SUCCESSFULLY        ")
    print("==================================================")

if __name__ == '__main__':
    train_and_evaluate()
