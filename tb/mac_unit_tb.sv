// ==============================================================================
// Project: Adaptive MAC Processing Core (AMPC) for TinyML Inference Acceleration
// Target:  AMD/Xilinx Zynq-7010 (xc7z010clg400-1) | Vivado 2026.1
// File:    mac_unit_tb.sv
// Module:  mac_unit_tb
// Author:  VLSI/FPGA Project Team
// Details: Stage 1 - Comprehensive Self-Checking Testbench for mac_unit
// ==============================================================================

`timescale 1ns / 1ps

module mac_unit_tb;

    // Parameters matching DUT configuration
    localparam int DATA_WIDTH   = 8;
    localparam int WEIGHT_WIDTH = 8;
    localparam int ACC_WIDTH    = 32;

    // Testbench Stimulus and Monitor Signals
    logic signed [DATA_WIDTH-1:0]   tb_data_in;
    logic signed [WEIGHT_WIDTH-1:0] tb_weight;
    logic signed [ACC_WIDTH-1:0]    tb_acc_in;
    logic signed [ACC_WIDTH-1:0]    tb_acc_out;

    // Test Statistics and Accounting
    integer test_num   = 0;
    integer pass_count = 0;
    integer fail_count = 0;

    // --------------------------------------------------------------------------
    // Instantiate Device Under Test (DUT)
    // --------------------------------------------------------------------------
    mac_unit #(
        .DATA_WIDTH   (DATA_WIDTH),
        .WEIGHT_WIDTH (WEIGHT_WIDTH),
        .ACC_WIDTH    (ACC_WIDTH)
    ) dut (
        .data_in (tb_data_in),
        .weight  (tb_weight),
        .acc_in  (tb_acc_in),
        .acc_out (tb_acc_out)
    );

    // --------------------------------------------------------------------------
    // Verification Task:
    // Applies inputs, waits for combinational settling, verifies against an
    // independent mathematical reference model, checks for X/Z, and records pass/fail.
    // --------------------------------------------------------------------------
    task check_mac(
        input logic signed [DATA_WIDTH-1:0]   d,
        input logic signed [WEIGHT_WIDTH-1:0] w,
        input logic signed [ACC_WIDTH-1:0]    a,
        input string                          desc
    );
        // Independent software reference model (using standard integer math)
        int product_calc;
        int expected_out;
        begin
            test_num++;
            tb_data_in = d;
            tb_weight  = w;
            tb_acc_in  = a;

            // Wait 10 ns for combinational propagation
            #10;

            // Independent Reference Calculation
            product_calc = int'(d) * int'(w);
            expected_out = int'(a) + product_calc;

            // Check for unknown or high-impedance values (X or Z)
            if ($isunknown(tb_acc_out)) begin
                $display("[FAIL] Test %02d: %-32s | Data=%4d, Weight=%4d, AccIn=%8d | Error: Output contains X/Z (Actual: %b)",
                         test_num, desc, d, w, a, tb_acc_out);
                fail_count++;
            end
            // Check output against independent golden model
            else if (tb_acc_out === expected_out) begin
                $display("[PASS] Test %02d: %-32s | Data=%4d, Weight=%4d, AccIn=%8d | Result=%8d", 
                         test_num, desc, d, w, a, tb_acc_out);
                pass_count++;
            end else begin
                $display("[FAIL] Test %02d: %-32s | Data=%4d, Weight=%4d, AccIn=%8d | Expected=%8d, Actual=%8d", 
                         test_num, desc, d, w, a, expected_out, tb_acc_out);
                fail_count++;
            end
        end
    endtask

    // --------------------------------------------------------------------------
    // Main Stimulus Process
    // --------------------------------------------------------------------------
    initial begin
        $display("==============================================================================");
        $display("   AMPC PROJECT: STAGE 1 MAC UNIT (mac_unit) SELF-CHECKING VERIFICATION       ");
        $display("==============================================================================");

        // ----------------------------------------------------------------------
        // SECTION 1: MANDATORY MASTER SPECIFICATION TESTS (Tests 1 - 6)
        // ----------------------------------------------------------------------
        $display("\n--- [1] MANDATORY SPECIFICATION TESTS ---");
        // Test 1: data = 3, weight = 4, acc = 5 -> expected = 17
        check_mac(8'sd3, 8'sd4, 32'sd5, "Test 1: Positive values");

        // Test 2: data = 0, weight = 10, acc = 5 -> expected = 5
        check_mac(8'sd0, 8'sd10, 32'sd5, "Test 2: Zero data");

        // Test 3: data = -3, weight = 4, acc = 5 -> expected = -7
        check_mac(-8'sd3, 8'sd4, 32'sd5, "Test 3: Negative data");

        // Test 4: data = 3, weight = -4, acc = 5 -> expected = -7
        check_mac(8'sd3, -8'sd4, 32'sd5, "Test 4: Negative weight");

        // Test 5: data = -3, weight = -4, acc = 5 -> expected = 17
        check_mac(-8'sd3, -8'sd4, 32'sd5, "Test 5: Both negative");

        // Test 6: data = 10, weight = 10, acc = 100 -> expected = 200
        check_mac(8'sd10, 8'sd10, 32'sd100, "Test 6: Positive accumulation");

        // ----------------------------------------------------------------------
        // SECTION 2: INT8 BOUNDARY & CORNER CASES
        // ----------------------------------------------------------------------
        $display("\n--- [2] INT8 BOUNDARY & EXTREME CORNER CASES ---");
        // Min * Min: (-128) * (-128) = +16384
        check_mac(-8'sd128, -8'sd128, 32'sd0, "Boundary: Min*Min (-128*-128)");

        // Max * Max: (+127) * (+127) = +16129
        check_mac(8'sd127, 8'sd127, 32'sd0, "Boundary: Max*Max (127*127)");

        // Min * Max: (-128) * (+127) = -16256
        check_mac(-8'sd128, 8'sd127, 32'sd0, "Boundary: Min*Max (-128*127)");

        // Max * Min: (+127) * (-128) = -16256
        check_mac(8'sd127, -8'sd128, 32'sd0, "Boundary: Max*Min (127*-128)");

        // Min * 1 with negative accumulator
        check_mac(-8'sd128, 8'sd1, -32'sd1000, "Boundary: Min*1 with neg acc");

        // Max * -1 with positive accumulator
        check_mac(8'sd127, -8'sd1, 32'sd1000, "Boundary: Max*-1 with pos acc");

        // ----------------------------------------------------------------------
        // SECTION 3: EXTENSIVE ZERO & OFFSET TESTS
        // ----------------------------------------------------------------------
        $display("\n--- [3] ZERO OPERAND & LARGE OFFSET TESTS ---");
        check_mac(8'sd0, 8'sd0, 32'sd0, "All zeros (0*0 + 0)");
        check_mac(8'sd25, 8'sd0, 32'sd50, "Zero weight (25*0 + 50)");
        check_mac(8'sd12, 8'sd8, 32'sd0, "Zero accumulator (12*8 + 0)");
        check_mac(-8'sd8, -8'sd7, -32'sd50, "Both neg with neg acc");
        check_mac(8'sd10, 8'sd10, 32'sd1000000, "Large positive acc (1M)");
        check_mac(8'sd10, 8'sd10, -32'sd1000000, "Large negative acc (-1M)");

        // ----------------------------------------------------------------------
        // SECTION 4: 25 RANDOMIZED TEST VECTORS
        // ----------------------------------------------------------------------
        $display("\n--- [4] 25 RANDOMIZED SIGNED TEST VECTORS ---");
        for (int i = 0; i < 25; i++) begin
            logic signed [7:0]  rand_d;
            logic signed [7:0]  rand_w;
            logic signed [31:0] rand_a;
            string test_name;

            // Generate signed random 8-bit and 32-bit values
            rand_d = $urandom_range(0, 255);
            rand_w = $urandom_range(0, 255);
            rand_a = $random();

            $sformat(test_name, "Random vector #%0d", i + 1);
            check_mac(rand_d, rand_w, rand_a, test_name);
        end

        // ----------------------------------------------------------------------
        // FINAL RESULTS SUMMARY
        // ----------------------------------------------------------------------
        $display("\n==============================================================================");
        $display("                   STAGE 1 MAC UNIT FINAL TEST REPORT                         ");
        $display("==============================================================================");
        $display(" Total Tests Executed : %0d", test_num);
        $display(" Total Tests Passed   : %0d", pass_count);
        $display(" Total Tests Failed   : %0d", fail_count);
        $display("==============================================================================");

        if (fail_count == 0) begin
            $display(" >>> MAC UNIT STATUS: PASS <<<");
            $display(" All %0d test cases matched independent mathematical model with ZERO errors.", test_num);
        end else begin
            $display(" >>> MAC UNIT STATUS: FAIL <<<");
            $display(" Test suite failed with %0d discrepancies!", fail_count);
        end
        $display("==============================================================================");

        $finish;
    end

endmodule
