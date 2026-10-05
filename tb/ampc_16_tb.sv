// ==============================================================================
// Project: Adaptive MAC Processing Core (AMPC) for TinyML Inference Acceleration
// Target:  AMD/Xilinx Zynq-7010 (xc7z010clg400-1) | Vivado 2026.1
// File:    ampc_16_tb.sv
// Module:  ampc_16_tb
// Author:  VLSI/FPGA Project Team
// Details: Stage 5 - Comprehensive Self-Checking Testbench for ampc_16
// ==============================================================================

`timescale 1ns / 1ps

module ampc_16_tb;

    localparam int DATA_WIDTH   = 8;
    localparam int WEIGHT_WIDTH = 8;
    localparam int ACC_WIDTH    = 32;
    localparam int LANES        = 16;

    // Clock and Control Signals
    logic        clk;
    logic        rst_n;
    logic        en;
    logic [15:0] lane_mask;

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
    ampc_16 #(
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
    // Applies 16-lane inputs on falling edge, samples DUT on rising edge (1 cycle latency),
    // compares against independent reference model, checks for X/Z.
    // --------------------------------------------------------------------------
    task check_ampc_16(
        input logic                           test_en,
        input logic [15:0]                    test_mask,
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
                // Check all 16 lanes against independent reference model
                match = (valid_out === expected_valid);
                for (int k = 0; k < LANES; k++) begin
                    if (acc_out[k] !== expected_out[k]) match = 1'b0;
                end

                if (match) begin
                    $display("[PASS] Test %02d: %-36s | All 16 lanes match | v=%b", test_num, desc, valid_out);
                    pass_count++;
                end else begin
                    $display("[FAIL] Test %02d: %-36s | Mismatch on output lanes! (valid actual=%b, exp=%b)", 
                             test_num, desc, valid_out, expected_valid);
                    for (int k = 0; k < LANES; k++) begin
                        if (acc_out[k] !== expected_out[k]) begin
                            $display("       -> Lane %02d: Expected=%8d, Actual=%8d", k, expected_out[k], acc_out[k]);
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
        logic signed [7:0]  d_vec [0:15];
        logic signed [7:0]  w_vec [0:15];
        logic signed [31:0] a_vec [0:15];

        $display("==============================================================================");
        $display("     AMPC PROJECT: STAGE 5 AMPC-16 (ampc_16) SELF-CHECKING VERIFICATION       ");
        $display("==============================================================================");

        // Initialize signals
        clk       = 0;
        rst_n     = 0;
        en        = 0;
        lane_mask = 16'h0000;
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
                $display("[PASS] Test %02d: Synchronous Reset Verification    | All 16 outputs zeroed, valid=0", test_num);
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
            en = 0; lane_mask = 16'hFFFF;
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
        // SECTION 2: ALL 16 LANES ACTIVE (ARITHMETIC TESTS)
        // ----------------------------------------------------------------------
        $display("\n--- [2] ALL 16 LANES ACTIVE (lane_mask = 16'hFFFF) ---");
        // Positive values across all 16 lanes
        for (int k = 0; k < 16; k++) begin
            d_vec[k] = 8'(k + 2);
            w_vec[k] = 8'(k + 3);
            a_vec[k] = 32'(k * 10 + 5);
        end
        check_ampc_16(1'b1, 16'hFFFF, d_vec, w_vec, a_vec, "All 16 lanes positive values");

        // Negative values across all 16 lanes
        for (int k = 0; k < 16; k++) begin
            d_vec[k] = -8'(k + 2);
            w_vec[k] = -8'(k + 3);
            a_vec[k] = -32'(k * 10 + 5);
        end
        check_ampc_16(1'b1, 16'hFFFF, d_vec, w_vec, a_vec, "All 16 lanes negative values");

        // Mixed signs across lanes
        for (int k = 0; k < 16; k++) begin
            d_vec[k] = (k % 2 == 0) ? 8'(k + 3) : -8'(k + 3);
            w_vec[k] = (k % 3 == 0) ? -8'(k + 2) : 8'(k + 2);
            a_vec[k] = (k % 2 == 0) ? 32'(k * 20) : -32'(k * 20);
        end
        check_ampc_16(1'b1, 16'hFFFF, d_vec, w_vec, a_vec, "Mixed signs across all 16 lanes");

        // Zero operands
        for (int k = 0; k < 16; k++) begin
            d_vec[k] = (k == 0) ? 8'sd0 : 8'(k + 5);
            w_vec[k] = (k == 1) ? 8'sd0 : 8'(k + 2);
            a_vec[k] = (k == 2) ? 32'sd0 : 32'(k * 50);
        end
        check_ampc_16(1'b1, 16'hFFFF, d_vec, w_vec, a_vec, "Zero data, weight, and accumulator");

        // INT8 minimum and maximum boundaries across all 16 lanes
        for (int k = 0; k < 16; k++) begin
            case (k % 8)
                0: begin d_vec[k] = -8'sd128; w_vec[k] = -8'sd128; a_vec[k] = 32'sd0; end     // +16384
                1: begin d_vec[k] =  8'sd127; w_vec[k] =  8'sd127; a_vec[k] = 32'sd0; end     // +16129
                2: begin d_vec[k] = -8'sd128; w_vec[k] =  8'sd127; a_vec[k] = 32'sd100; end   // -16156
                3: begin d_vec[k] =  8'sd127; w_vec[k] = -8'sd128; a_vec[k] = -32'sd100; end  // -16356
                4: begin d_vec[k] = -8'sd128; w_vec[k] =  8'sd1;   a_vec[k] = -32'sd1000; end // -1128
                5: begin d_vec[k] =  8'sd127; w_vec[k] = -8'sd1;   a_vec[k] = 32'sd1000; end  // +873
                6: begin d_vec[k] = -8'sd128; w_vec[k] =  8'sd0;   a_vec[k] = 32'sd5000; end  // +5000
                7: begin d_vec[k] =  8'sd0;   w_vec[k] = -8'sd128; a_vec[k] = -32'sd5000; end // -5000
            endcase
        end
        check_ampc_16(1'b1, 16'hFFFF, d_vec, w_vec, a_vec, "INT8 boundary extreme conditions");

        // Large INT32 accumulator offsets
        for (int k = 0; k < 16; k++) begin
            d_vec[k] = 8'sd10; w_vec[k] = 8'sd10;
            a_vec[k] = (k % 2 == 0) ? 32'sd1000000 : -32'sd1000000;
        end
        check_ampc_16(1'b1, 16'hFFFF, d_vec, w_vec, a_vec, "Large INT32 accumulator offsets");

        // ----------------------------------------------------------------------
        // SECTION 3: ONE-HOT LANE MASKS FOR ALL 16 LANES
        // ----------------------------------------------------------------------
        $display("\n--- [3] ONE-HOT LANE MASKS FOR ALL 16 LANES ---");
        for (int lane = 0; lane < 16; lane++) begin
            logic [15:0] one_hot_mask;
            string test_name;
            one_hot_mask = (16'b1 << lane);
            for (int k = 0; k < 16; k++) begin
                d_vec[k] = 8'(k + 4);
                w_vec[k] = 8'(k + 2);
                a_vec[k] = 32'(k * 100 + 50);
            end
            $sformat(test_name, "One-hot: Lane %02d active (%04h)", lane, one_hot_mask);
            check_ampc_16(1'b1, one_hot_mask, d_vec, w_vec, a_vec, test_name);
        end

        // ----------------------------------------------------------------------
        // SECTION 4: PARTIAL WORKLOAD MASKS (W=1..8, 9, 10, 12, 15, 16)
        // ----------------------------------------------------------------------
        $display("\n--- [4] PARTIAL WORKLOAD MASKS (REMAINDER SUPPORT) ---");
        // Workloads W=1 to 8
        for (int w = 1; w <= 8; w++) begin
            logic [15:0] w_mask;
            string test_name;
            w_mask = (16'b1 << w) - 1;
            $sformat(test_name, "Partial Workload W=%02d (%04h)", w, w_mask);
            check_ampc_16(1'b1, w_mask, d_vec, w_vec, a_vec, test_name);
        end

        // Workload W=9 (Mandatory Partial Workload: First 9 lanes active)
        check_ampc_16(1'b1, 16'b0000_0001_1111_1111, d_vec, w_vec, a_vec, "Workload W=9 (first 9 lanes active)");

        // Workload W=10
        check_ampc_16(1'b1, 16'b0000_0011_1111_1111, d_vec, w_vec, a_vec, "Workload W=10 (first 10 lanes)");

        // Workload W=12
        check_ampc_16(1'b1, 16'b0000_1111_1111_1111, d_vec, w_vec, a_vec, "Workload W=12 (first 12 lanes)");

        // Workload W=15 (Mandatory Partial Workload: First 15 lanes active)
        check_ampc_16(1'b1, 16'b0111_1111_1111_1111, d_vec, w_vec, a_vec, "Workload W=15 (first 15 lanes)");

        // Workload W=16 (Mandatory Full Workload: All 16 lanes active)
        check_ampc_16(1'b1, 16'b1111_1111_1111_1111, d_vec, w_vec, a_vec, "Workload W=16 (all 16 lanes active)");

        // All lanes masked (Mask = 16'h0000)
        check_ampc_16(1'b1, 16'h0000, d_vec, w_vec, a_vec, "All lanes masked (16'h0000)");

        // ----------------------------------------------------------------------
        // SECTION 5: CONSECUTIVE MULTI-CYCLE STREAMING (5 CYCLES)
        // ----------------------------------------------------------------------
        $display("\n--- [5] CONSECUTIVE MULTI-CYCLE STREAMING (5 CYCLES) ---");
        for (int c = 0; c < 5; c++) begin
            string stream_name;
            for (int k = 0; k < 16; k++) begin
                d_vec[k] = 8'(c + k + 1);
                w_vec[k] = 8'(c + k + 2);
                a_vec[k] = 32'(c * 50 + k * 10);
            end
            $sformat(stream_name, "Pipelined Stream Cycle %0d", c + 1);
            check_ampc_16(1'b1, 16'hFFFF, d_vec, w_vec, a_vec, stream_name);
        end

        // ----------------------------------------------------------------------
        // SECTION 6: 25 RANDOMIZED SIGNED TEST VECTORS
        // ----------------------------------------------------------------------
        $display("\n--- [6] 25 RANDOMIZED TEST VECTORS (ARBITRARY MASKS & INPUTS) ---");
        for (int i = 0; i < 25; i++) begin
            logic [15:0] r_mask;
            string test_name;

            for (int k = 0; k < 16; k++) begin
                d_vec[k] = $urandom_range(0, 255);
                w_vec[k] = $urandom_range(0, 255);
                a_vec[k] = $random();
            end
            r_mask = $urandom_range(0, 65535);

            $sformat(test_name, "Random vector #%0d (mask=%04h)", i + 1, r_mask);
            check_ampc_16(1'b1, r_mask, d_vec, w_vec, a_vec, test_name);
        end

        // ----------------------------------------------------------------------
        // FINAL RESULTS SUMMARY
        // ----------------------------------------------------------------------
        $display("\n==============================================================================");
        $display("                   STAGE 5 AMPC-16 FINAL TEST REPORT                          ");
        $display("==============================================================================");
        $display(" Total Tests Executed : %0d", test_num);
        $display(" Total Tests Passed   : %0d", pass_count);
        $display(" Total Tests Failed   : %0d", fail_count);
        $display("==============================================================================");

        if (fail_count == 0) begin
            $display(" >>> AMPC-16 STATUS: PASS <<<");
            $display(" All %0d test cases matched independent reference model with ZERO errors.", test_num);
        end else begin
            $display(" >>> AMPC-16 STATUS: FAIL <<<");
            $display(" Test suite failed with %0d discrepancies!", fail_count);
        end
        $display("==============================================================================");

        $finish;
    end

endmodule
