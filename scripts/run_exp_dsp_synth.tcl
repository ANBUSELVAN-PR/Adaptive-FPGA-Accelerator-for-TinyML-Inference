# ==============================================================================
# Project: Adaptive MAC Processing Core (AMPC) for TinyML Inference Acceleration
# File:    scripts/run_exp_dsp_synth.tcl
# Details: Stage 15 Experimental Synthesis & Implementation Script
# ==============================================================================

file mkdir "reports/experimental"

# Read RTL Sources
read_verilog -sv "rtl/mac_unit.sv"
read_verilog -sv "rtl/experimental/mac_unit_dsp.sv"
read_verilog -sv "rtl/experimental/exp_dsp_eval_top.sv"

# Read Timing Constraints
read_xdc "constraints/ampc_timing.xdc"

# Synthesize
puts "=============================================================================="
puts "       STARTING EXPERIMENTAL SYNTHESIS (exp_dsp_eval_top)                     "
puts "=============================================================================="
synth_design -top exp_dsp_eval_top -part xc7z010clg400-1 -mode out_of_context

report_utilization -file "reports/experimental/post_synth_util.rpt"
report_timing_summary -file "reports/experimental/post_synth_timing.rpt"

opt_design
place_design
route_design

report_utilization -file "reports/experimental/post_route_util.rpt" -hierarchical -hierarchical_depth 3
report_utilization -file "reports/experimental/post_route_util_summary.rpt"
report_timing_summary -max_paths 10 -report_unconstrained -file "reports/experimental/post_route_timing.rpt"
report_power -file "reports/experimental/post_route_power.rpt"
report_drc -file "reports/experimental/post_route_drc.rpt"

puts "=============================================================================="
puts "       EXPERIMENTAL SYNTHESIS & ROUTE COMPLETED                               "
puts "=============================================================================="
