// ==============================================================================
// Project: Adaptive MAC Processing Core (AMPC) for TinyML Inference Acceleration
// Target:  AMD/Xilinx Zynq-7010 (xc7z010clg400-1) | Vivado 2026.1
// File:    workload_analyzer_tb.sv
// Module:  workload_analyzer_tb
// Author:  VLSI/FPGA Project Team
// Details: Stage 9 - Comprehensive Self-Checking Testbench for workload_analyzer
// ==============================================================================

`timescale 1ns / 1ps

module workload_analyzer_tb;

    localparam int WORKLOAD_WIDTH = 16;

    // Clock and Control Signals
    logic                         clk;
    logic                         rst_n;
    logic                         en;
    logic                         valid_in;
    logic [WORKLOAD_WIDTH-1:0]    workload_size;

    // DUT Outputs
    logic [4:0]                   selected_capacity;
    logic [WORKLOAD_WIDTH-1:0]    remainder;
    logic                         valid_out;

    // Test Tracking Accounting
    integer test_num   = 0;
    integer pass_count = 0;
    integer fail_count = 0;

    // Golden model tracking register
    logic [4:0]                   last_golden_cap;
    logic [WORKLOAD_WIDTH-1:0]    last_golden_rem;

    // --------------------------------------------------------------------------
    // Instantiate Device Under Test (DUT)
    // --------------------------------------------------------------------------
    workload_analyzer #(
        .WORKLOAD_WIDTH (WORKLOAD_WIDTH)
    ) dut (
        .clk               (clk),
        .rst_n             (rst_n),
        .en                (en),
        .valid_in          (valid_in),
        .workload_size     (workload_size),
        .selected_capacity (selected_capacity),
        .remainder         (remainder),
        .valid_out         (valid_out)
    );

    // 100 MHz Simulation Clock (10ns period)
    always #5 clk = ~clk;

    // --------------------------------------------------------------------------
    // Independent Golden Reference Function
    // --------------------------------------------------------------------------
    function void get_expected_analysis(
        input  logic [WORKLOAD_WIDTH-1:0] w,
        output logic [4:0]                exp_cap,
        output logic [WORKLOAD_WIDTH-1:0] exp_rem
    );
        if (w == '0) begin
            exp_cap = 5'd0;
            exp_rem = '0;
        end else if (w <= 16'd2) begin
            exp_cap = 5'd2;
            exp_rem = (w == 16'd2) ? 16'd0 : w;
        end else if (w <= 16'd4) begin
            exp_cap = 5'd4;
            exp_rem = (w == 16'd4) ? 16'd0 : w;
        end else if (w <= 16'd8) begin
            exp_cap = 5'd8;
            exp_rem = (w == 16'd8) ? 16'd0 : w;
        end else if (w <= 16'd16) begin
            exp_cap = 5'd16;
            exp_rem = (w == 16'd16) ? 16'd0 : w;
        end else begin
            exp_cap = 5'd16;
            exp_rem = w - 16'd16;
        end
    endfunction

    // --------------------------------------------------------------------------
    // Verification Task
    // --------------------------------------------------------------------------
    task step_analyzer(
        input logic                      test_en,
        input logic                      test_valid_in,
        input logic [WORKLOAD_WIDTH-1:0] test_wsize,
        input string                     desc
    );
        logic [4:0]                exp_cap;
        logic [WORKLOAD_WIDTH-1:0] exp_rem;
        logic                      exp_valid_out;
        begin
            test_num++;

            // Apply inputs on falling edge for robust setup
            @(negedge clk);
            en            = test_en;
            valid_in      = test_valid_in;
            workload_size = test_wsize;

            // Compute expected outputs
            exp_valid_out = test_en && test_valid_in;
            if (exp_valid_out) begin
                get_expected_analysis(test_wsize, exp_cap, exp_rem);
                last_golden_cap = exp_cap;
                last_golden_rem = exp_rem;
            end else begin
                exp_cap = last_golden_cap; // Retains previous state when not updated
                exp_rem = last_golden_rem;
            end

            // Wait for registered update on rising clock edge
            @(posedge clk);
            #1;

            // Check for X/Z
            if ($isunknown(selected_capacity) || $isunknown(remainder) || $isunknown(valid_out)) begin
                $display("[FAIL] Test %03d: %-38s | Output contains X/Z! (cap=%b, rem=%b, vld=%b)",
                         test_num, desc, selected_capacity, remainder, valid_out);
                fail_count++;
            end
            // Check matching against reference model
            else if ((selected_capacity === exp_cap) &&
                     (remainder === exp_rem) &&
                     (valid_out === exp_valid_out)) begin
                $display("[PASS] Test %03d: %-38s | W=%5d -> Cap=%2d, Rem=%5d, Vld=%b",
                         test_num, desc, test_wsize, selected_capacity, remainder, valid_out);
                pass_count++;
            end else begin
                $display("[FAIL] Test %03d: %-38s | Exp=[Cap=%2d, Rem=%5d, V=%b], Act=[Cap=%2d, Rem=%5d, V=%b]",
                         test_num, desc, exp_cap, exp_rem, exp_valid_out, selected_capacity, remainder, valid_out);
                fail_count++;
            end
        end
    endtask

    // --------------------------------------------------------------------------
    // Main Stimulus Process
    // --------------------------------------------------------------------------
    initial begin
        $display("==============================================================================");
        $display("     AMPC PROJECT: STAGE 9 WORKLOAD ANALYZER (workload_analyzer) VERIFY       ");
        $display("==============================================================================");

        // Initialize signals
        clk             = 0;
        rst_n           = 0;
        en              = 0;
        valid_in        = 0;
        workload_size   = '0;
        last_golden_cap = '0;
        last_golden_rem = '0;

        // ----------------------------------------------------------------------
        // SECTION 1: RESET BEHAVIOR
        // ----------------------------------------------------------------------
        $display("\n--- [1] SYNCHRONOUS RESET VERIFICATION ---");
        repeat (2) @(posedge clk);
        #1;
        test_num++;
        if (selected_capacity === 5'd0 && remainder === 16'd0 && valid_out === 1'b0) begin
            $display("[PASS] Test %03d: Synchronous Reset Verification         | Cap=0, Rem=0, Vld=0", test_num);
            pass_count++;
        end else begin
            $display("[FAIL] Test %03d: Reset Check Failed! (Cap=%d, Rem=%d, Vld=%b)", test_num, selected_capacity, remainder, valid_out);
            fail_count++;
        end

        // Release reset
        @(negedge clk);
        rst_n = 1'b1;
        last_golden_cap = 5'd0;
        last_golden_rem = 16'd0;

        // ----------------------------------------------------------------------
        // SECTION 2: ZERO WORKLOAD BEHAVIOR
        // ----------------------------------------------------------------------
        $display("\n--- [2] ZERO WORKLOAD BEHAVIOR ---");
        step_analyzer(1'b1, 1'b1, 16'd0, "Zero Workload (W=0 -> Cap=0, Rem=0)");

        // ----------------------------------------------------------------------
        // SECTION 3: WORKLOADS 1 TO 16 (EXHAUSTIVE SINGLE-CYCLE CHECKS)
        // ----------------------------------------------------------------------
        $display("\n--- [3] SINGLE-CYCLE WORKLOADS 1 TO 16 ---");
        step_analyzer(1'b1, 1'b1, 16'd1,  "Workload W=1  -> AMPC-2 (Rem=1)");
        step_analyzer(1'b1, 1'b1, 16'd2,  "Workload W=2  -> AMPC-2 (Rem=0)");
        step_analyzer(1'b1, 1'b1, 16'd3,  "Workload W=3  -> AMPC-4 (Rem=3)");
        step_analyzer(1'b1, 1'b1, 16'd4,  "Workload W=4  -> AMPC-4 (Rem=0)");
        step_analyzer(1'b1, 1'b1, 16'd5,  "Workload W=5  -> AMPC-8 (Rem=5)");
        step_analyzer(1'b1, 1'b1, 16'd6,  "Workload W=6  -> AMPC-8 (Rem=6)");
        step_analyzer(1'b1, 1'b1, 16'd7,  "Workload W=7  -> AMPC-8 (Rem=7)");
        step_analyzer(1'b1, 1'b1, 16'd8,  "Workload W=8  -> AMPC-8 (Rem=0)");
        step_analyzer(1'b1, 1'b1, 16'd9,  "Workload W=9  -> AMPC-16 (Rem=9)");
        step_analyzer(1'b1, 1'b1, 16'd10, "Workload W=10 -> AMPC-16 (Rem=10)");
        step_analyzer(1'b1, 1'b1, 16'd11, "Workload W=11 -> AMPC-16 (Rem=11)");
        step_analyzer(1'b1, 1'b1, 16'd12, "Workload W=12 -> AMPC-16 (Rem=12)");
        step_analyzer(1'b1, 1'b1, 16'd13, "Workload W=13 -> AMPC-16 (Rem=13)");
        step_analyzer(1'b1, 1'b1, 16'd14, "Workload W=14 -> AMPC-16 (Rem=14)");
        step_analyzer(1'b1, 1'b1, 16'd15, "Workload W=15 -> AMPC-16 (Rem=15)");
        step_analyzer(1'b1, 1'b1, 16'd16, "Workload W=16 -> AMPC-16 (Rem=0)");

        // ----------------------------------------------------------------------
        // SECTION 4: MULTI-CYCLE & BOUNDARY WORKLOADS (>16)
        // ----------------------------------------------------------------------
        $display("\n--- [4] MULTI-CYCLE & BOUNDARY WORKLOADS (>16) ---");
        step_analyzer(1'b1, 1'b1, 16'd17,   "Workload W=17 -> Cap=16, Rem=1");
        step_analyzer(1'b1, 1'b1, 16'd18,   "Workload W=18 -> Cap=16, Rem=2");
        step_analyzer(1'b1, 1'b1, 16'd25,   "Workload W=25 -> Cap=16, Rem=9");
        step_analyzer(1'b1, 1'b1, 16'd32,   "Workload W=32 -> Cap=16, Rem=16");
        step_analyzer(1'b1, 1'b1, 16'd33,   "Workload W=33 -> Cap=16, Rem=17");
        step_analyzer(1'b1, 1'b1, 16'd48,   "Workload W=48 -> Cap=16, Rem=32");
        step_analyzer(1'b1, 1'b1, 16'd64,   "Workload W=64 -> Cap=16, Rem=48");
        step_analyzer(1'b1, 1'b1, 16'd100,  "Workload W=100 -> Cap=16, Rem=84");
        step_analyzer(1'b1, 1'b1, 16'd256,  "Workload W=256 -> Cap=16, Rem=240");
        step_analyzer(1'b1, 1'b1, 16'd1000, "Workload W=1000 -> Cap=16, Rem=984");
        step_analyzer(1'b1, 1'b1, 16'hFFFF, "Maximum Workload W=65535 -> Cap=16, Rem=65519");

        // ----------------------------------------------------------------------
        // SECTION 5: CONTROL GATING & HOLD BEHAVIOR
        // ----------------------------------------------------------------------
        $display("\n--- [5] CONTROL GATING & HOLD BEHAVIOR ---");
        // Test en=0 with valid_in=1 (should not update, valid_out=0)
        step_analyzer(1'b0, 1'b1, 16'd50, "Gating: en=0, valid_in=1 (Hold State)");

        // Test en=1 with valid_in=0 (should not update, valid_out=0)
        step_analyzer(1'b1, 1'b0, 16'd75, "Gating: en=1, valid_in=0 (Hold State)");

        // Test en=0 with valid_in=0 (should not update, valid_out=0)
        step_analyzer(1'b0, 1'b0, 16'd90, "Gating: en=0, valid_in=0 (Hold State)");

        // ----------------------------------------------------------------------
        // SECTION 6: CONSECUTIVE BACK-TO-BACK WORKLOAD TRANSACTIONS
        // ----------------------------------------------------------------------
        $display("\n--- [6] CONSECUTIVE BACK-TO-BACK TRANSACTIONS ---");
        step_analyzer(1'b1, 1'b1, 16'd1,  "Consecutive 1: W=1");
        step_analyzer(1'b1, 1'b1, 16'd17, "Consecutive 2: W=17");
        step_analyzer(1'b1, 1'b1, 16'd3,  "Consecutive 3: W=3");
        step_analyzer(1'b1, 1'b1, 16'd25, "Consecutive 4: W=25");
        step_analyzer(1'b1, 1'b1, 16'd0,  "Consecutive 5: W=0");
        step_analyzer(1'b1, 1'b1, 16'd8,  "Consecutive 6: W=8");

        // ----------------------------------------------------------------------
        // SECTION 7: 100 RANDOMIZED WORKLOAD TEST VECTORS
        // ----------------------------------------------------------------------
        $display("\n--- [7] 100 RANDOMIZED WORKLOAD TEST VECTORS ---");
        for (int i = 0; i < 100; i++) begin
            logic [WORKLOAD_WIDTH-1:0] rand_w;
            logic                      rand_en;
            logic                      rand_vld;
            string test_name;

            // Generate representative workloads (mix of tiny, small, medium, large)
            if (i < 25) begin
                rand_w = $urandom_range(0, 16);     // 0 to 16
            end else if (i < 50) begin
                rand_w = $urandom_range(17, 64);    // 17 to 64
            end else if (i < 75) begin
                rand_w = $urandom_range(65, 1024);  // 65 to 1024
            end else begin
                rand_w = $urandom_range(1025, 65535); // 1025 to 65535
            end

            rand_en  = ($urandom_range(0, 10) > 1); // 90% enabled
            rand_vld = ($urandom_range(0, 10) > 1); // 90% valid

            $sformat(test_name, "Random vector #%03d (W=%5d, en=%b, vld=%b)", i+1, rand_w, rand_en, rand_vld);
            step_analyzer(rand_en, rand_vld, rand_w, test_name);
        end

        // ----------------------------------------------------------------------
        // FINAL RESULTS SUMMARY
        // ----------------------------------------------------------------------
        $display("\n==============================================================================");
        $display("               STAGE 9 WORKLOAD ANALYZER FINAL TEST REPORT                    ");
        $display("==============================================================================");
        $display(" Total Tests Executed : %0d", test_num);
        $display(" Total Tests Passed   : %0d", pass_count);
        $display(" Total Tests Failed   : %0d", fail_count);
        $display("==============================================================================");

        if (fail_count == 0) begin
            $display(" >>> WORKLOAD ANALYZER STATUS: PASS <<<");
            $display(" All %0d test cases matched independent reference model with ZERO errors.", test_num);
        end else begin
            $display(" >>> WORKLOAD ANALYZER STATUS: FAIL <<<");
            $display(" Test suite failed with %0d discrepancies!", fail_count);
        end
        $display("==============================================================================");

        $finish;
    end

endmodule
