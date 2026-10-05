# Adaptive FPGA Accelerator for TinyML Inference

## Overview

This project presents an **Adaptive MAC Processing Core (AMPC)** architecture for accelerating TinyML inference on FPGA hardware.

The architecture is designed to provide configurable MAC (Multiply-Accumulate) processing capability based on the computational requirements of the workload.

## Project Goals

- Design a configurable FPGA-based MAC processing architecture
- Support multiple MAC processing configurations
- Develop the accelerator using RTL/SystemVerilog
- Verify the design through simulation and testbenches
- Explore FPGA implementation for TinyML inference workloads

## Architecture

The AMPC architecture consists of:

- MAC Processing Cores
- Configurable MAC array
- Controller for workload/core allocation
- Input data and weight processing
- Accumulation logic
- Output/valid control

The design targets the **AMD/Xilinx Zynq-7010 FPGA** platform.

## Data Format

The current design uses:

- **Input data:** Signed INT8
- **Weights:** Signed INT8
- **Accumulator:** Signed INT32

## Repository Structure

```text
├── rtl/
│   └── RTL design files
│
├── tb/
│   └── Testbench and verification files
│
└── README.md
