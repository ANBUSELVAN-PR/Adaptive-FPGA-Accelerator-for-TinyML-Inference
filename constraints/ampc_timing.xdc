# ==============================================================================
# Project: Adaptive MAC Processing Core (AMPC) for TinyML Inference Acceleration
# Target:  AMD/Xilinx Zynq-7010 (xc7z010clg400-1) | Vivado 2026.1
# File:    ampc_timing.xdc
# Details: Primary timing constraints for ampc_top
# ==============================================================================

# Primary System Clock Constraint: 100 MHz (10.000 ns period, 50% duty cycle)
create_clock -period 10.000 -name clk -waveform {0.000 5.000} [get_ports clk]

# Set clock uncertainty baseline
set_clock_uncertainty 0.200 [get_clocks clk]
