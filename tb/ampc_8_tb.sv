// ==============================================================================
// Project: Adaptive MAC Processing Core (AMPC) for TinyML Inference Acceleration
// Target:  AMD/Xilinx Zynq-7010 (xc7z010clg400-1) | Vivado 2026.1
// File:    ampc_8_tb.sv
// Module:  ampc_8_tb
// Author:  VLSI/FPGA Project Team
// Details: Stage 4 - Comprehensive Self-Checking Testbench for ampc_8
// ==============================================================================

`timescale 1ns / 1ps

module ampc_8_tb;

    localparam int DATA_WIDTH   = 8;
    localparam int WEIGHT_WIDTH = 8;
    localparam int ACC_WIDTH    = 32;
    localparam int LANES        = 8;

    // Clock and Control Signals
    logic        clk;
    logic        rst_n;
    logic        en;
    logic [7:0]  lane_mask;

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
    ampc_8 #(
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
    // Applies 8-lane inputs on falling edge, samples DUT on rising edge (1 cycle latency),
    // compares against independent reference model, checks for X/Z.
    // --------------------------------------------------------------------------
    task check_ampc_8(
        input logic                           test_en,
        input logic [7:0]                     test_mask,
        input logic signed [DATA_WIDTH-1:0]   d_in [0:LANES-1],
        input logic signed [WEIGHT_WIDTH-1:0] w_in [0:LANES-1],
        input logic signed [ACC_WIDTH-1:0]    a_in [0:LANES-1],
        input string                          desc
    );
        int expected_out [0:LANES-1];
        logic expected_valid;
        bit match;
        bit has_xz;
        begin
            test_num++;

            // Apply inputs on falling edge for robust setup
            @(negedge clk);
            en        = test_en;
            lane_mask = test_mask;
            for (int k = 0; k < LANES; k++) begin
                data_in[k] = d_in[k];
                weight[k]  = w_in[k];
                acc_in[k]  = a_in[k];
            end

            // Independent Reference Model Calculation
            expected_valid = test_en;
            for (int k = 0; k < LANES; k++) begin
                if (test_en && test_mask[k]) begin
                    int prod;
                    prod = int'(d_in[k]) * int'(w_in[k]);
                    expected_out[k] = int'(a_in[k]) + prod;
                end else begin
                    // Masked or disabled lane forces operands to 0, preserving accumulator input
                    expected_out[k] = int'(a_in[k]);
                end
            end

            // Wait for clock edge where output register captures computation
            @(posedge clk);
            #1; // Delta delay to inspect stable registered outputs

            // Check for unknown / X / Z
            has_xz = 1'b0;
            for (int k = 0; k < LANES; k++) begin
                if ($isunknown(acc_out[k])) has_xz = 1'b1;
            end
            if ($isunknown(valid_out)) has_xz = 1'b1;

            if (has_xz) begin
                $display("[FAIL] Test %02d: %-36s | Output contains X/Z! (valid=%b)", test_num, desc, valid_out);
                fail_count++;
            end else begin
                // Check all 8 lanes against independent reference model
                match = (valid_out === expected_valid);
                for (int k = 0; k < LANES; k++) begin
                    if (acc_out[k] !== expected_out[k]) match = 1'b0;
                end

                if (match) begin
                    $display("[PASS] Test %02d: %-36s | All 8 lanes match | v=%b", test_num, desc, valid_out);
                    pass_count++;
                end else begin
                    $display("[FAIL] Test %02d: %-36s | Mismatch on output lanes! (valid actual=%b, exp=%b)", 
                             test_num, desc, valid_out, expected_valid);
                    for (int k = 0; k < LANES; k++) begin
                        if (acc_out[k] !== expected_out[k]) begin
                            $display("       -> Lane %0d: Expected=%8d, Actual=%8d", k, expected_out[k], acc_out[k]);
                        end
                    end
                    fail_count++;
                end
            end
        end
    endtask

    // --------------------------------------------------------------------------
    // Main Stimulus Process
    // --------------------------------------------------------------------------
    initial begin
        logic signed [7:0]  d_vec [0:7];
        logic signed [7:0]  w_vec [0:7];
        logic signed [31:0] a_vec [0:7];

        $display("==============================================================================");
        $display("     AMPC PROJECT: STAGE 4 AMPC-8 (ampc_8) SELF-CHECKING VERIFICATION         ");
        $display("==============================================================================");

        // Initialize signals
        clk       = 0;
        rst_n     = 0;
        en        = 0;
        lane_mask = 8'b00000000;
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
        begin
            bit rst_ok;
            rst_ok = (valid_out === 1'b0);
            for (int k = 0; k < LANES; k++) begin
                if (acc_out[k] !== 32'sd0) rst_ok = 1'b0;
            end

            if (rst_ok) begin
                $display("[PASS] Test %02d: Synchronous Reset Verification    | All 8 outputs zeroed, valid=0", test_num);
                pass_count++;
            end else begin
                $display("[FAIL] Test %02d: Reset Failure! (valid=%b)", test_num, valid_out);
                fail_count++;
            end
        end

        // Release reset
        @(negedge clk);
        rst_n = 1'b1;

        // Verify enable low (en=0) keeps valid_out=0
        begin
            test_num++;
            @(negedge clk);
            en = 0; lane_mask = 8'b11111111;
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
        // SECTION 2: ALL 8 LANES ACTIVE (ARITHMETIC TESTS)
        // ----------------------------------------------------------------------
        $display("\n--- [2] ALL 8 LANES ACTIVE (lane_mask = 8'b11111111) ---");
        // Positive values across all 8 lanes
        for (int k = 0; k < 8; k++) begin
            d_vec[k] = 8'(k + 2);
            w_vec[k] = 8'(k + 3);
            a_vec[k] = 32'(k * 10 + 5);
        end
        check_ampc_8(1'b1, 8'b11111111, d_vec, w_vec, a_vec, "All 8 lanes positive values");

        // Negative values across all 8 lanes
        for (int k = 0; k < 8; k++) begin
            d_vec[k] = -8'(k + 2);
            w_vec[k] = -8'(k + 3);
            a_vec[k] = -32'(k * 10 + 5);
        end
        check_ampc_8(1'b1, 8'b11111111, d_vec, w_vec, a_vec, "All 8 lanes negative values");

        // Mixed signs across lanes
        for (int k = 0; k < 8; k++) begin
            d_vec[k] = (k % 2 == 0) ? 8'(k + 3) : -8'(k + 3);
            w_vec[k] = (k % 3 == 0) ? -8'(k + 2) : 8'(k + 2);
            a_vec[k] = (k % 2 == 0) ? 32'(k * 20) : -32'(k * 20);
        end
        check_ampc_8(1'b1, 8'b11111111, d_vec, w_vec, a_vec, "Mixed signs across all 8 lanes");

        // Zero operands
        for (int k = 0; k < 8; k++) begin
            d_vec[k] = (k == 0) ? 8'sd0 : 8'(k + 5);
            w_vec[k] = (k == 1) ? 8'sd0 : 8'(k + 2);
            a_vec[k] = (k == 2) ? 32'sd0 : 32'(k * 50);
        end
        check_ampc_8(1'b1, 8'b11111111, d_vec, w_vec, a_vec, "Zero data, weight, and accumulator");

        // INT8 minimum and maximum boundaries
        d_vec[0] = -8'sd128; w_vec[0] = -8'sd128; a_vec[0] = 32'sd0;     // +16384
        d_vec[1] =  8'sd127; w_vec[1] =  8'sd127; a_vec[1] = 32'sd0;     // +16129
        d_vec[2] = -8'sd128; w_vec[2] =  8'sd127; a_vec[2] = 32'sd100;   // -16156
        d_vec[3] =  8'sd127; w_vec[3] = -8'sd128; a_vec[3] = -32'sd100;  // -16356
        d_vec[4] = -8'sd128; w_vec[4] =  8'sd1;   a_vec[4] = -32'sd1000; // -1128
        d_vec[5] =  8'sd127; w_vec[5] = -8'sd1;   a_vec[5] = 32'sd1000;  // +873
        d_vec[6] = -8'sd128; w_vec[6] =  8'sd0;   a_vec[6] = 32'sd5000;  // +5000
        d_vec[7] =  8'sd0;   w_vec[7] = -8'sd128; a_vec[7] = -32'sd5000; // -5000
        check_ampc_8(1'b1, 8'b11111111, d_vec, w_vec, a_vec, "INT8 boundary extreme conditions");

        // Large INT32 accumulator offsets
        for (int k = 0; k < 8; k++) begin
            d_vec[k] = 8'sd10; w_vec[k] = 8'sd10;
            a_vec[k] = (k % 2 == 0) ? 32'sd1000000 : -32'sd1000000;
        end
        check_ampc_8(1'b1, 8'b11111111, d_vec, w_vec, a_vec, "Large INT32 accumulator offsets");

        // ----------------------------------------------------------------------
        // SECTION 3: INDIVIDUAL ONE-HOT LANE MASKS (8 TESTS)
        // ----------------------------------------------------------------------
        $display("\n--- [3] INDIVIDUAL ONE-HOT LANE MASK TESTS ---");
        for (int lane = 0; lane < 8; lane++) begin
            logic [7:0] one_hot_mask;
            string test_name;
            one_hot_mask = (8'b1 << lane);
            for (int k = 0; k < 8; k++) begin
                d_vec[k] = 8'(k + 4);
                w_vec[k] = 8'(k + 2);
                a_vec[k] = 32'(k * 100 + 50);
            end
            $sformat(test_name, "One-hot mask: Lane %0d active (%b)", lane, one_hot_mask);
            check_ampc_8(1'b1, one_hot_mask, d_vec, w_vec, a_vec, test_name);
        end

        // ----------------------------------------------------------------------
        // SECTION 4: PARTIAL WORKLOAD MASKS (W=1, 2, 3, 4, 5, 6, 7)
        // ----------------------------------------------------------------------
        $display("\n--- [4] PARTIAL WORKLOAD MASKS (REMAINDER SUPPORT) ---");
        // Workload = 1 (Mask: 8'b00000001)
        check_ampc_8(1'b1, 8'b00000001, d_vec, w_vec, a_vec, "Workload=1 (Mask 8'b00000001)");

        // Workload = 2 (Mask: 8'b00000011)
        check_ampc_8(1'b1, 8'b00000011, d_vec, w_vec, a_vec, "Workload=2 (Mask 8'b00000011)");

        // Workload = 3 (Mask: 8'b00000111)
        check_ampc_8(1'b1, 8'b00000111, d_vec, w_vec, a_vec, "Workload=3 (Mask 8'b00000111)");

        // Workload = 4 (Mask: 8'b00001111)
        check_ampc_8(1'b1, 8'b00001111, d_vec, w_vec, a_vec, "Workload=4 (Mask 8'b00001111)");

        // Workload = 5 (Mask: 8'b00011111)
        check_ampc_8(1'b1, 8'b00011111, d_vec, w_vec, a_vec, "Workload=5 (Mask 8'b00011111)");

        // Workload = 6 (Mask: 8'b00111111)
        check_ampc_8(1'b1, 8'b00111111, d_vec, w_vec, a_vec, "Workload=6 (Mask 8'b00111111)");

        // Workload = 7 (Mask: 8'b01111111)
        check_ampc_8(1'b1, 8'b01111111, d_vec, w_vec, a_vec, "Workload=7 (Mask 8'b01111111)");

        // All lanes masked (Mask: 8'b00000000)
        check_ampc_8(1'b1, 8'b00000000, d_vec, w_vec, a_vec, "All lanes masked (8'b00000000)");

        // ----------------------------------------------------------------------
        // SECTION 5: CONSECUTIVE MULTI-CYCLE STREAMING (5 CYCLES)
        // ----------------------------------------------------------------------
        $display("\n--- [5] CONSECUTIVE MULTI-CYCLE STREAMING (5 CYCLES) ---");
        for (int c = 0; c < 5; c++) begin
            string stream_name;
            for (int k = 0; k < 8; k++) begin
                d_vec[k] = 8'(c + k + 1);
                w_vec[k] = 8'(c + k + 2);
                a_vec[k] = 32'(c * 50 + k * 10);
            end
            $sformat(stream_name, "Pipelined Stream Cycle %0d", c + 1);
            check_ampc_8(1'b1, 8'b11111111, d_vec, w_vec, a_vec, stream_name);
        end

        // ----------------------------------------------------------------------
        // SECTION 6: 25 RANDOMIZED SIGNED TEST VECTORS
        // ----------------------------------------------------------------------
        $display("\n--- [6] 25 RANDOMIZED TEST VECTORS (ARBITRARY MASKS & INPUTS) ---");
        for (int i = 0; i < 25; i++) begin
            logic [7:0] r_mask;
            string test_name;

            for (int k = 0; k < 8; k++) begin
                d_vec[k] = $urandom_range(0, 255);
                w_vec[k] = $urandom_range(0, 255);
                a_vec[k] = $random();
            end
            r_mask = $urandom_range(0, 255);

            $sformat(test_name, "Random vector #%0d (mask=%b)", i + 1, r_mask);
            check_ampc_8(1'b1, r_mask, d_vec, w_vec, a_vec, test_name);
        end

        // ----------------------------------------------------------------------
        // FINAL RESULTS SUMMARY
        // ----------------------------------------------------------------------
        $display("\n==============================================================================");
        $display("                   STAGE 4 AMPC-8 FINAL TEST REPORT                           ");
        $display("==============================================================================");
        $display(" Total Tests Executed : %0d", test_num);
        $display(" Total Tests Passed   : %0d", pass_count);
        $display(" Total Tests Failed   : %0d", fail_count);
        $display("==============================================================================");

        if (fail_count == 0) begin
            $display(" >>> AMPC-8 STATUS: PASS <<<");
            $display(" All %0d test cases matched independent reference model with ZERO errors.", test_num);
        end else begin
            $display(" >>> AMPC-8 STATUS: FAIL <<<");
            $display(" Test suite failed with %0d discrepancies!", fail_count);
        end
        $display("==============================================================================");

        $finish;
    end

endmodule
