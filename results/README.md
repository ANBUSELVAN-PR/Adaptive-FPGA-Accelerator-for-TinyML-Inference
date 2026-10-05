# AMPC Verification & Implementation Results

This directory contains real, unmanipulated simulation, synthesis, and implementation reports generated from Vivado 2026.1 and Python reference models.

## Directory Structure

```
results/
├── simulation/
│   ├── regression_summary.md              # Summary of 1,036-test full regression suite
│   ├── three_model_validation_report.md   # Hardware arithmetic validation across 3 real TinyML models
│   ├── three_model_rtl_log.txt            # Vivado xsim simulation output log for 16 AI workloads
│   ├── three_model_golden_results.json    # Golden Python calculated references for 16 AI workloads
│   ├── model_comparison.csv               # Workload-by-workload arithmetic comparison table
│   ├── validation_summary.md              # Stage 15 MNIST validation summary
│   ├── rtl_simulation_log.txt             # Initial MNIST FC1 simulation log
│   └── python_golden_results.json         # Initial MNIST FC1 golden references
│
├── synthesis/
│   ├── post_synth_util.rpt                # Vivado post-synthesis resource utilization report
│   └── post_synth_timing.rpt              # Vivado post-synthesis timing summary report
│
├── implementation/
│   ├── post_route_timing.rpt              # Post-routing static timing analysis (WNS = +0.256 ns)
│   ├── post_route_util_summary.rpt        # Post-routing summary utilization (2,971 LUTs, 878 FFs, 0 DSP)
│   ├── post_route_util.rpt                # Post-routing hierarchical module-by-module utilization
│   ├── post_route_power.rpt               # Post-routing vector-less power report (127 mW total)
│   ├── post_route_clock.rpt               # Clock network utilization report
│   ├── post_route_drc.rpt                 # Design Rule Check (DRC) report
│   └── post_route_methodology.rpt         # Methodology compliance report
│
└── experimental/
    ├── post_synth_util.rpt                # Stage 15 experimental DSP synthesis utilization
    ├── post_synth_timing.rpt              # Stage 15 experimental DSP synthesis timing
    ├── post_route_util_summary.rpt        # Stage 15 post-route utilization
    ├── post_route_util.rpt                # Stage 15 hierarchical utilization
    ├── post_route_timing.rpt              # Stage 15 post-route timing
    ├── post_route_power.rpt               # Stage 15 post-route power
    └── post_route_drc.rpt                 # Stage 15 DRC report
```

> [!NOTE]
> All results correspond to the Stage 14/Stage 16 production baseline of `ampc_top` on AMD/Xilinx Zynq-7010 (`xc7z010clg400-1`). No placeholder or estimated numbers are used.
