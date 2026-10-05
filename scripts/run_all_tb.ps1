$ErrorActionPreference = "Stop"
$Env:PATH = "D:\Xilinx\2026.1\Vivado\bin;" + $Env:PATH

$tests = @(
    @{ name = "mac_unit"; tb = "tb/mac_unit_tb.sv"; rtl = @("rtl/mac_unit.sv"); exp = 43 },
    @{ name = "ampc_2"; tb = "tb/ampc_2_tb.sv"; rtl = @("rtl/mac_unit.sv", "rtl/ampc_2.sv"); exp = 40 },
    @{ name = "ampc_4"; tb = "tb/ampc_4_tb.sv"; rtl = @("rtl/mac_unit.sv", "rtl/ampc_4.sv"); exp = 45 },
    @{ name = "ampc_8"; tb = "tb/ampc_8_tb.sv"; rtl = @("rtl/mac_unit.sv", "rtl/ampc_8.sv"); exp = 54 },
    @{ name = "ampc_16"; tb = "tb/ampc_16_tb.sv"; rtl = @("rtl/mac_unit.sv", "rtl/ampc_16.sv"); exp = 68 },
    @{ name = "accumulator"; tb = "tb/accumulator_tb.sv"; rtl = @("rtl/accumulator.sv"); exp = 90 },
    @{ name = "relu"; tb = "tb/relu_tb.sv"; rtl = @("rtl/relu.sv"); exp = 88 },
    @{ name = "input_buffer"; tb = "tb/input_buffer_tb.sv"; rtl = @("rtl/input_buffer.sv"); exp = 135 },
    @{ name = "weight_buffer"; tb = "tb/weight_buffer_tb.sv"; rtl = @("rtl/weight_buffer.sv"); exp = 135 },
    @{ name = "workload_analyzer"; tb = "tb/workload_analyzer_tb.sv"; rtl = @("rtl/workload_analyzer.sv"); exp = 138 },
    @{ name = "adaptive_controller"; tb = "tb/adaptive_controller_tb.sv"; rtl = @("rtl/adaptive_controller.sv"); exp = 126 },
    @{ name = "ampc_top"; tb = "tb/ampc_top_tb.sv"; rtl = @("rtl/mac_unit.sv", "rtl/ampc_2.sv", "rtl/ampc_4.sv", "rtl/ampc_8.sv", "rtl/ampc_16.sv", "rtl/accumulator.sv", "rtl/relu.sv", "rtl/input_buffer.sv", "rtl/weight_buffer.sv", "rtl/workload_analyzer.sv", "rtl/adaptive_controller.sv", "rtl/ampc_top.sv"); exp = 74 }
)

$total_pass = 0
$total_fail = 0

Write-Host "=============================================================================="
Write-Host "                  RUNNING FULL REGRESSION SUITE (1,036 TESTS)                "
Write-Host "=============================================================================="

foreach ($t in $tests) {
    Write-Host ">>> Running $($t.name)_tb..."
    $rtl_args = $t.rtl -join " "
    $cmd_vlog = "xvlog -sv $rtl_args $($t.tb)"
    Invoke-Expression $cmd_vlog | Out-Null
    
    $snap = "$($t.name)_snap"
    $top = "$($t.name)_tb"
    $cmd_elab = "xelab -top $top -snapshot $snap -timescale 1ns/1ps"
    Invoke-Expression $cmd_elab | Out-Null
    
    $cmd_sim = "xsim $snap -R"
    $out = Invoke-Expression $cmd_sim | Out-String
    
    # Extract pass/fail
    $p = 0
    $f = 0
    if ($out -match "Total Tests Passed\s*:\s*(\d+)") {
        $p = [int]$matches[1]
    } elseif ($out -match "PASSED\s*:\s*(\d+)") {
        $p = [int]$matches[1]
    } elseif ($out -match "Passed\s*:\s*(\d+)") {
        $p = [int]$matches[1]
    }
    
    if ($out -match "Total Tests Failed\s*:\s*(\d+)") {
        $f = [int]$matches[1]
    } elseif ($out -match "FAILED\s*:\s*(\d+)") {
        $f = [int]$matches[1]
    } elseif ($out -match "Failed\s*:\s*(\d+)") {
        $f = [int]$matches[1]
    }
    
    Write-Host "    $($t.name): Passed=$p / Expected=$($t.exp), Failed=$f"
    $total_pass += $p
    $total_fail += $f
}

Write-Host "=============================================================================="
Write-Host "REGRESSION SUMMARY: Total Passed: $total_pass / 1036, Total Failed: $total_fail"
Write-Host "=============================================================================="
