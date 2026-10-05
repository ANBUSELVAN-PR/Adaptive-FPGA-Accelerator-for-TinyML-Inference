# ==============================================================================
# Project: Adaptive MAC Processing Core (AMPC) for TinyML Inference Acceleration
# Target:  AMD/Xilinx Zynq-7010 (xc7z010clg400-1) | Vivado 2026.1
# File:    run_synth_impl.tcl
# Details: Automated Vivado Synthesis & Implementation Script
# ==============================================================================

# Create reports directory if it doesn't exist
file mkdir "reports"

# 1. Read SystemVerilog RTL Sources
read_verilog -sv "rtl/mac_unit.sv"
read_verilog -sv "rtl/ampc_2.sv"
read_verilog -sv "rtl/ampc_4.sv"
read_verilog -sv "rtl/ampc_8.sv"
read_verilog -sv "rtl/ampc_16.sv"
read_verilog -sv "rtl/accumulator.sv"
read_verilog -sv "rtl/relu.sv"
read_verilog -sv "rtl/input_buffer.sv"
read_verilog -sv "rtl/weight_buffer.sv"
read_verilog -sv "rtl/workload_analyzer.sv"
read_verilog -sv "rtl/adaptive_controller.sv"
read_verilog -sv "rtl/ampc_top.sv"

# 2. Read Timing Constraints
read_xdc "constraints/ampc_timing.xdc"

# 3. Run Synthesis (Out-of-Context mode for IP core characterization)
puts "=============================================================================="
puts "                STARTING VIVADO SYNTHESIS (xc7z010clg400-1)                   "
puts "=============================================================================="
synth_design -top ampc_top -part xc7z010clg400-1 -mode out_of_context

# 4. Post-Synthesis Reports
report_utilization -file "reports/post_synth_util.rpt"
report_timing_summary -file "reports/post_synth_timing.rpt"

# 5. Run Implementation (Optimization, Placement, Routing)
puts "=============================================================================="
puts "                STARTING VIVADO IMPLEMENTATION (opt, place, route)            "
puts "=============================================================================="
opt_design
place_design
route_design

# 6. Post-Implementation Reports
puts "=============================================================================="
puts "                GENERATING POST-IMPLEMENTATION REPORTS                        "
puts "=============================================================================="
report_utilization -file "reports/post_route_util.rpt" -hierarchical -hierarchical_depth 3
report_utilization -file "reports/post_route_util_summary.rpt"
report_timing_summary -max_paths 20 -report_unconstrained -file "reports/post_route_timing.rpt"
report_power -file "reports/post_route_power.rpt"
report_clock_utilization -file "reports/post_route_clock.rpt"
report_drc -file "reports/post_route_drc.rpt"
report_methodology -file "reports/post_route_methodology.rpt"

puts "=============================================================================="
puts "                SYNTHESIS & IMPLEMENTATION RUN COMPLETED                      "
puts "=============================================================================="
