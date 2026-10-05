// ==============================================================================
// Project: Adaptive MAC Processing Core (AMPC) for TinyML Inference Acceleration
// Target:  AMD/Xilinx Zynq-7010 (xc7z010clg400-1) | Vivado 2026.1
// File:    relu_tb.sv
// Module:  relu_tb
// Author:  VLSI/FPGA Project Team
// Details: Stage 7 - Comprehensive Self-Checking Testbench for relu
// ==============================================================================

`timescale 1ns / 1ps

module relu_tb;

    localparam int DATA_WIDTH = 32;

    // DUT Signals
    logic signed [DATA_WIDTH-1:0] data_in;
    logic signed [DATA_WIDTH-1:0] data_out;

    // Test Tracking Accounting
    integer test_num   = 0;
    integer pass_count = 0;
    integer fail_count = 0;

    // --------------------------------------------------------------------------
    // Instantiate Device Under Test (DUT)
    // --------------------------------------------------------------------------
    relu #(
        .DATA_WIDTH (DATA_WIDTH)
    ) dut (
        .data_in  (data_in),
        .data_out (data_out)
    );

    // --------------------------------------------------------------------------
    // Verification Task:
    // Applies stimulus, allows propagation delay (#5), checks against independent
    // software reference model, and tests for unknown X/Z states.
    // --------------------------------------------------------------------------
    task check_relu(
        input logic signed [DATA_WIDTH-1:0] test_val,
        input string                        desc
    );
        logic signed [DATA_WIDTH-1:0] expected_val;
        begin
            test_num++;
            data_in = test_val;
            #5; // Combinational propagation delay

            // Independent Software Reference Model
            expected_val = (test_val < 0) ? 32'sd0 : test_val;

            // Check for X/Z
            if ($isunknown(data_out)) begin
                $display("[FAIL] Test %02d: %-36s | Output contains X/Z! in=%0d, out=%b",
                         test_num, desc, test_val, data_out);
                fail_count++;
            end
            // Check correctness against reference model
            else if (data_out === expected_val) begin
                $display("[PASS] Test %02d: %-36s | In=%11d -> Out=%11d",
                         test_num, desc, test_val, data_out);
                pass_count++;
            end else begin
                $display("[FAIL] Test %02d: %-36s | Expected=%11d, Actual=%11d",
                         test_num, desc, expected_val, data_out);
                fail_count++;
            end
        end
    endtask

    // --------------------------------------------------------------------------
    // Main Stimulus Process
    // --------------------------------------------------------------------------
    initial begin
        $display("==============================================================================");
        $display("          AMPC PROJECT: STAGE 7 ReLU ACTIVATION UNIT VERIFICATION             ");
        $display("==============================================================================");

        data_in = '0;
        #10;

        // ----------------------------------------------------------------------
        // SECTION 1: MANDATORY PROMPT-SPECIFIED TEST VALUES
        // ----------------------------------------------------------------------
        $display("\n--- [1] MANDATORY PROMPT SPECIFIED VALUES ---");
        check_relu(32'sd1,                    "Prompt Case: +1 (exp=+1)");
        check_relu(32'sd100,                  "Prompt Case: +100 (exp=+100)");
        check_relu(32'sh7FFF_FFFF,            "Prompt Case: +2147483647 INT32_MAX");
        check_relu(32'sd0,                    "Prompt Case: 0 (exp=0)");
        check_relu(-32'sd1,                   "Prompt Case: -1 (exp=0)");
        check_relu(-32'sd100,                 "Prompt Case: -100 (exp=0)");
        check_relu(32'sh8000_0000,            "Prompt Case: -2147483648 INT32_MIN");

        // ----------------------------------------------------------------------
        // SECTION 2: VALUES AROUND ZERO
        // ----------------------------------------------------------------------
        $display("\n--- [2] VALUES AROUND ZERO NEIGHBORHOOD ---");
        check_relu(-32'sd5,                   "Neighborhood: -5");
        check_relu(-32'sd4,                   "Neighborhood: -4");
        check_relu(-32'sd3,                   "Neighborhood: -3");
        check_relu(-32'sd2,                   "Neighborhood: -2");
        check_relu(-32'sd1,                   "Neighborhood: -1");
        check_relu(32'sd0,                    "Neighborhood:  0");
        check_relu(32'sd1,                    "Neighborhood: +1");
        check_relu(32'sd2,                    "Neighborhood: +2");
        check_relu(32'sd3,                    "Neighborhood: +3");
        check_relu(32'sd4,                    "Neighborhood: +4");
        check_relu(32'sd5,                    "Neighborhood: +5");

        // ----------------------------------------------------------------------
        // SECTION 3: BOUNDARY & POWER-OF-TWO VALUES
        // ----------------------------------------------------------------------
        $display("\n--- [3] BOUNDARY & SIGNED DYNAMIC RANGE CASES ---");
        check_relu(32'sh7FFF_FFFE,            "Boundary: INT32_MAX - 1 (+2147483646)");
        check_relu(32'sh8000_0001,            "Boundary: INT32_MIN + 1 (-2147483647)");
        check_relu(32'sd127,                  "Boundary: INT8_MAX (+127)");
        check_relu(-32'sd128,                 "Boundary: INT8_MIN (-128)");
        check_relu(32'sd32767,                "Boundary: INT16_MAX (+32767)");
        check_relu(-32'sd32768,               "Boundary: INT16_MIN (-32768)");
        check_relu(32'sd1000000,              "Positive Large (+1,000,000)");
        check_relu(-32'sd1000000,             "Negative Large (-1,000,000)");
        check_relu(32'sh4000_0000,            "Positive Power of 2 (2^30)");
        check_relu(-32'sh4000_0000,           "Negative Power of 2 (-2^30)");

        // ----------------------------------------------------------------------
        // SECTION 4: 60 RANDOMIZED SIGNED INT32 VECTORS
        // ----------------------------------------------------------------------
        $display("\n--- [4] 60 RANDOMIZED SIGNED INT32 TEST VECTORS ---");
        for (int i = 0; i < 60; i++) begin
            logic signed [31:0] rand_val;
            string test_name;
            rand_val = $random();
            $sformat(test_name, "Random vector #%02d", i + 1);
            check_relu(rand_val, test_name);
        end

        // ----------------------------------------------------------------------
        // FINAL RESULTS SUMMARY
        // ----------------------------------------------------------------------
        $display("\n==============================================================================");
        $display("                   STAGE 7 ReLU FINAL TEST REPORT                             ");
        $display("==============================================================================");
        $display(" Total Tests Executed : %0d", test_num);
        $display(" Total Tests Passed   : %0d", pass_count);
        $display(" Total Tests Failed   : %0d", fail_count);
        $display("==============================================================================");

        if (fail_count == 0) begin
            $display(" >>> ReLU STATUS: PASS <<<");
            $display(" All %0d test cases matched independent reference model with ZERO errors.", test_num);
        end else begin
            $display(" >>> ReLU STATUS: FAIL <<<");
            $display(" Test suite failed with %0d discrepancies!", fail_count);
        end
        $display("==============================================================================");

        $finish;
    end

endmodule
