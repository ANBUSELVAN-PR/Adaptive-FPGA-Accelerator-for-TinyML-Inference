// ==============================================================================
// Project: Adaptive MAC Processing Core (AMPC) for TinyML Inference Acceleration
// Target:  AMD/Xilinx Zynq-7010 (xc7z010clg400-1) | Vivado 2026.1
// File:    ampc_4_tb.sv
// Module:  ampc_4_tb
// Author:  VLSI/FPGA Project Team
// Details: Stage 3 - Comprehensive Self-Checking Testbench for ampc_4
// ==============================================================================

`timescale 1ns / 1ps

module ampc_4_tb;

    localparam int DATA_WIDTH   = 8;
    localparam int WEIGHT_WIDTH = 8;
    localparam int ACC_WIDTH    = 32;
    localparam int LANES        = 4;

    // Clock and Control Signals
    logic        clk;
    logic        rst_n;
    logic        en;
    logic [3:0]  lane_mask;

    // Parallel Stimulus and Monitor Arrays
    logic signed [DATA_WIDTH-1:0]   data_in  [0:LANES-1];
    logic signed [WEIGHT_WIDTH-1:0] weight   [0:LANES-1];
    logic signed [ACC_WIDTH-1:0]    acc_in   [0:LANES-1];
    logic signed [ACC_WIDTH-1:0]    acc_out  [0:LANES-1];
    logic                           valid_out;

    // Test Tracking Accounting
    integer test_num   = 0;
    integer pass_count = 0;
    integer fail_count = 0;

    // --------------------------------------------------------------------------
    // Instantiate Device Under Test (DUT)
    // --------------------------------------------------------------------------
    ampc_4 #(
        .DATA_WIDTH   (DATA_WIDTH),
        .WEIGHT_WIDTH (WEIGHT_WIDTH),
        .ACC_WIDTH    (ACC_WIDTH)
    ) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .en         (en),
        .lane_mask  (lane_mask),
        .data_in    (data_in),
        .weight     (weight),
        .acc_in     (acc_in),
        .acc_out    (acc_out),
        .valid_out  (valid_out)
    );

    // 100 MHz Simulation Clock (10ns period)
    always #5 clk = ~clk;

    // --------------------------------------------------------------------------
    // Verification Task:
    // Applies 4-lane inputs on falling edge, samples DUT on rising edge (1 cycle latency),
    // compares against independent reference model, checks for X/Z.
    // --------------------------------------------------------------------------
    task check_ampc_4(
        input logic                           test_en,
        input logic [3:0]                     test_mask,
        input logic signed [DATA_WIDTH-1:0]   d0, d1, d2, d3,
        input logic signed [WEIGHT_WIDTH-1:0] w0, w1, w2, w3,
        input logic signed [ACC_WIDTH-1:0]    a0, a1, a2, a3,
        input string                          desc
    );
        int expected_out [0:LANES-1];
        logic expected_valid;
        logic signed [DATA_WIDTH-1:0]   d_arr [0:3];
        logic signed [WEIGHT_WIDTH-1:0] w_arr [0:3];
        logic signed [ACC_WIDTH-1:0]    a_arr [0:3];
        begin
            test_num++;

            d_arr[0] = d0; d_arr[1] = d1; d_arr[2] = d2; d_arr[3] = d3;
            w_arr[0] = w0; w_arr[1] = w1; w_arr[2] = w2; w_arr[3] = w3;
            a_arr[0] = a0; a_arr[1] = a1; a_arr[2] = a2; a_arr[3] = a3;

            // Apply inputs on falling edge for robust setup
            @(negedge clk);
            en        = test_en;
            lane_mask = test_mask;
            for (int k = 0; k < LANES; k++) begin
                data_in[k] = d_arr[k];
                weight[k]  = w_arr[k];
                acc_in[k]  = a_arr[k];
            end

            // Independent Reference Model Calculation
            expected_valid = test_en;
            for (int k = 0; k < LANES; k++) begin
                if (test_en && test_mask[k]) begin
                    int prod;
                    prod = int'(d_arr[k]) * int'(w_arr[k]);
                    expected_out[k] = int'(a_arr[k]) + prod;
                end else begin
                    // Masked or disabled lane forces operands to 0, preserving accumulator input
                    expected_out[k] = int'(a_arr[k]);
                end
            end

            // Wait for clock edge where output register captures computation
            @(posedge clk);
            #1; // Delta delay to inspect stable registered outputs

            // Check for unknown / X / Z
            if ($isunknown(acc_out[0]) || $isunknown(acc_out[1]) || 
                $isunknown(acc_out[2]) || $isunknown(acc_out[3]) || $isunknown(valid_out)) begin
                $display("[FAIL] Test %02d: %-36s | Output contains X/Z! (valid=%b)", test_num, desc, valid_out);
                fail_count++;
            end
            // Check outputs against independent reference
            else if ((acc_out[0] === expected_out[0]) && 
                     (acc_out[1] === expected_out[1]) && 
                     (acc_out[2] === expected_out[2]) && 
                     (acc_out[3] === expected_out[3]) && 
                     (valid_out === expected_valid)) begin
                $display("[PASS] Test %02d: %-36s | Out=[%6d, %6d, %6d, %6d] | v=%b", 
                         test_num, desc, acc_out[0], acc_out[1], acc_out[2], acc_out[3], valid_out);
                pass_count++;
            end else begin
                $display("[FAIL] Test %02d: %-36s | Expected=[%6d, %6d, %6d, %6d, v=%b], Actual=[%6d, %6d, %6d, %6d, v=%b]", 
                         test_num, desc, expected_out[0], expected_out[1], expected_out[2], expected_out[3], expected_valid, 
                         acc_out[0], acc_out[1], acc_out[2], acc_out[3], valid_out);
                fail_count++;
            end
        end
    endtask

    // --------------------------------------------------------------------------
    // Main Stimulus Process
    // --------------------------------------------------------------------------
    initial begin
        $display("==============================================================================");
        $display("     AMPC PROJECT: STAGE 3 AMPC-4 (ampc_4) SELF-CHECKING VERIFICATION         ");
        $display("==============================================================================");

        // Initialize signals
        clk       = 0;
        rst_n     = 0;
        en        = 0;
        lane_mask = 4'b0000;
        for (int i = 0; i < LANES; i++) begin
            data_in[i] = '0;
            weight[i]  = '0;
            acc_in[i]  = '0;
        end

        // ----------------------------------------------------------------------
        // SECTION 1: RESET AND IDLE BEHAVIOR
        // ----------------------------------------------------------------------
        $display("\n--- [1] RESET & IDLE VERIFICATION ---");
        repeat (2) @(posedge clk);
        #1;
        test_num++;
        if (acc_out[0] === 32'sd0 && acc_out[1] === 32'sd0 && 
            acc_out[2] === 32'sd0 && acc_out[3] === 32'sd0 && valid_out === 1'b0) begin
            $display("[PASS] Test %02d: Synchronous Reset Verification    | All 4 outputs zeroed, valid=0", test_num);
            pass_count++;
        end else begin
            $display("[FAIL] Test %02d: Reset Failure! (acc_out=[%0d,%0d,%0d,%0d], valid=%b)", 
                     test_num, acc_out[0], acc_out[1], acc_out[2], acc_out[3], valid_out);
            fail_count++;
        end

        // Release reset
        @(negedge clk);
        rst_n = 1'b1;

        // Verify enable low (en=0) keeps valid_out=0
        begin
            test_num++;
            @(negedge clk);
            en = 0; lane_mask = 4'b1111;
            for (int i = 0; i < LANES; i++) begin
                data_in[i] = 8'sd10; weight[i] = 8'sd5; acc_in[i] = 32'sd0;
            end
            @(posedge clk);
            #1;
            if (valid_out === 1'b0) begin
                $display("[PASS] Test %02d: Core Enable Low (en=0)            | valid_out=0 correctly held", test_num);
                pass_count++;
            end else begin
                $display("[FAIL] Test %02d: Core Enable Failure (valid_out=%b)", test_num, valid_out);
                fail_count++;
            end
        end

        // ----------------------------------------------------------------------
        // SECTION 2: ALL 4 LANES ACTIVE (ARITHMETIC TESTS)
        // ----------------------------------------------------------------------
        $display("\n--- [2] ALL 4 LANES ACTIVE (lane_mask = 4'b1111) ---");
        // Positive values across all 4 lanes
        check_ampc_4(1'b1, 4'b1111,
                     8'sd3, 8'sd2, 8'sd5, 8'sd7,     // data
                     8'sd4, 8'sd6, 8'sd3, 8'sd2,     // weights
                     32'sd5, 32'sd10, 32'sd1, 32'sd20, // acc_in
                     "All 4 lanes positive values");

        // Negative values across all 4 lanes
        check_ampc_4(1'b1, 4'b1111,
                     -8'sd3, -8'sd2, -8'sd5, -8'sd7,
                     -8'sd4, -8'sd6, -8'sd3, -8'sd2,
                     -32'sd5, -32'sd10, -32'sd1, -32'sd20,
                     "All 4 lanes negative values");

        // Mixed signs across lanes
        check_ampc_4(1'b1, 4'b1111,
                     -8'sd3, 8'sd3, -8'sd4, 8'sd6,
                     8'sd4, -8'sd4, -8'sd5, 8'sd7,
                     32'sd5, 32'sd5, 32'sd10, -32'sd50,
                     "Mixed signs across all lanes");

        // Zero operands
        check_ampc_4(1'b1, 4'b1111,
                     8'sd0, 8'sd25, 8'sd12, 8'sd0,
                     8'sd0, 8'sd0,  8'sd8,  8'sd10,
                     32'sd0, 32'sd50, 32'sd0, 32'sd100,
                     "Zero data, weight, and accumulator");

        // INT8 minimum and maximum boundaries
        check_ampc_4(1'b1, 4'b1111,
                     -8'sd128, 8'sd127, -8'sd128, 8'sd127,
                     -8'sd128, 8'sd127, 8'sd127,  -8'sd128,
                     32'sd0,   32'sd0,  32'sd100, -32'sd100,
                     "INT8 boundaries (-128, +127)");

        // Large INT32 accumulator offsets
        check_ampc_4(1'b1, 4'b1111,
                     8'sd10, 8'sd10, 8'sd10, 8'sd10,
                     8'sd10, 8'sd10, 8'sd10, 8'sd10,
                     32'sd1000000, -32'sd1000000, 32'sd500000, -32'sd500000,
                     "Large INT32 accumulator offsets");

        // ----------------------------------------------------------------------
        // SECTION 3: EXPLICIT LANE MASK TESTS (MANDATORY REQUIREMENT)
        // ----------------------------------------------------------------------
        $display("\n--- [3] EXPLICIT LANE MASK VERIFICATION ---");
        // Mask = 4'b0001 (Only Lane 0 active)
        check_ampc_4(1'b1, 4'b0001,
                     8'sd8,  8'sd15, 8'sd20, 8'sd30,
                     8'sd5,  8'sd4,  8'sd2,  8'sd1,
                     32'sd10, 32'sd20, 32'sd30, 32'sd40,
                     "Mask 4'b0001 (Only Lane 0 active)");

        // Mask = 4'b0010 (Only Lane 1 active)
        check_ampc_4(1'b1, 4'b0010,
                     8'sd8,  8'sd15, 8'sd20, 8'sd30,
                     8'sd5,  8'sd4,  8'sd2,  8'sd1,
                     32'sd10, 32'sd20, 32'sd30, 32'sd40,
                     "Mask 4'b0010 (Only Lane 1 active)");

        // Mask = 4'b0100 (Only Lane 2 active)
        check_ampc_4(1'b1, 4'b0100,
                     8'sd8,  8'sd15, 8'sd20, 8'sd30,
                     8'sd5,  8'sd4,  8'sd2,  8'sd1,
                     32'sd10, 32'sd20, 32'sd30, 32'sd40,
                     "Mask 4'b0100 (Only Lane 2 active)");

        // Mask = 4'b1000 (Only Lane 3 active)
        check_ampc_4(1'b1, 4'b1000,
                     8'sd8,  8'sd15, 8'sd20, 8'sd30,
                     8'sd5,  8'sd4,  8'sd2,  8'sd1,
                     32'sd10, 32'sd20, 32'sd30, 32'sd40,
                     "Mask 4'b1000 (Only Lane 3 active)");

        // Partial mask: 4'b0011 (Lanes 0 and 1 active, 2 and 3 masked)
        check_ampc_4(1'b1, 4'b0011,
                     8'sd6,  8'sd7,  8'sd10, 8'sd12,
                     8'sd3,  8'sd4,  8'sd5,  8'sd6,
                     32'sd100, 32'sd200, 32'sd300, 32'sd400,
                     "Mask 4'b0011 (Lanes 0, 1 active)");

        // Partial mask: 4'b0111 (Lanes 0, 1, 2 active, 3 masked - Workload=3 case)
        check_ampc_4(1'b1, 4'b0111,
                     8'sd5,  8'sd6,  8'sd7,  8'sd99,
                     8'sd2,  8'sd3,  8'sd4,  8'sd99,
                     32'sd10, 32'sd20, 32'sd30, 32'sd500,
                     "Mask 4'b0111 (Workload=3 remainder)");

        // Mask = 4'b0000 (All lanes masked)
        check_ampc_4(1'b1, 4'b0000,
                     8'sd50, 8'sd60, 8'sd70, 8'sd80,
                     8'sd2,  8'sd3,  8'sd4,  8'sd5,
                     32'sd15, 32'sd25, 32'sd35, 32'sd45,
                     "Mask 4'b0000 (All lanes masked)");

        // ----------------------------------------------------------------------
        // SECTION 4: CONSECUTIVE MULTI-CYCLE STREAMING
        // ----------------------------------------------------------------------
        $display("\n--- [4] CONSECUTIVE MULTI-CYCLE STREAMING (5 CYCLES) ---");
        for (int c = 0; c < 5; c++) begin
            string stream_name;
            $sformat(stream_name, "Pipelined Stream Cycle %0d", c + 1);
            check_ampc_4(1'b1, 4'b1111,
                         8'(c + 1), 8'(c + 2), 8'(c + 3), 8'(c + 4),
                         8'(c + 2), 8'(c + 3), 8'(c + 4), 8'(c + 5),
                         32'(c * 10), 32'(c * 20), 32'(c * 30), 32'(c * 40),
                         stream_name);
        end

        // ----------------------------------------------------------------------
        // SECTION 5: 25 RANDOMIZED SIGNED TEST VECTORS
        // ----------------------------------------------------------------------
        $display("\n--- [5] 25 RANDOMIZED SIGNED TEST VECTORS ---");
        for (int i = 0; i < 25; i++) begin
            logic signed [7:0]  r_d [0:3];
            logic signed [7:0]  r_w [0:3];
            logic signed [31:0] r_a [0:3];
            logic [3:0]         r_mask;
            string test_name;

            for (int k = 0; k < 4; k++) begin
                r_d[k] = $urandom_range(0, 255);
                r_w[k] = $urandom_range(0, 255);
                r_a[k] = $random();
            end
            r_mask = $urandom_range(0, 15); // Random 4-bit mask 4'b0000 .. 4'b1111

            $sformat(test_name, "Random vector #%0d (mask=%b)", i + 1, r_mask);
            check_ampc_4(1'b1, r_mask,
                         r_d[0], r_d[1], r_d[2], r_d[3],
                         r_w[0], r_w[1], r_w[2], r_w[3],
                         r_a[0], r_a[1], r_a[2], r_a[3],
                         test_name);
        end

        // ----------------------------------------------------------------------
        // FINAL RESULTS SUMMARY
        // ----------------------------------------------------------------------
        $display("\n==============================================================================");
        $display("                   STAGE 3 AMPC-4 FINAL TEST REPORT                           ");
        $display("==============================================================================");
        $display(" Total Tests Executed : %0d", test_num);
        $display(" Total Tests Passed   : %0d", pass_count);
        $display(" Total Tests Failed   : %0d", fail_count);
        $display("==============================================================================");

        if (fail_count == 0) begin
            $display(" >>> AMPC-4 STATUS: PASS <<<");
            $display(" All %0d test cases matched independent reference model with ZERO errors.", test_num);
        end else begin
            $display(" >>> AMPC-4 STATUS: FAIL <<<");
            $display(" Test suite failed with %0d discrepancies!", fail_count);
        end
        $display("==============================================================================");

        $finish;
    end

endmodule
