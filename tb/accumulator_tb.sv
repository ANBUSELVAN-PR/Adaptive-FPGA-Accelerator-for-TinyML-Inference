// ==============================================================================
// Project: Adaptive MAC Processing Core (AMPC) for TinyML Inference Acceleration
// Target:  AMD/Xilinx Zynq-7010 (xc7z010clg400-1) | Vivado 2026.1
// File:    accumulator_tb.sv
// Module:  accumulator_tb
// Author:  VLSI/FPGA Project Team
// Details: Stage 6 - Comprehensive Self-Checking Testbench for accumulator
// ==============================================================================

`timescale 1ns / 1ps

module accumulator_tb;

    localparam int ACC_WIDTH = 32;
    localparam int LANES     = 16;

    // Clock and Control Signals
    logic                  clk;
    logic                  rst_n;
    logic                  en;
    logic                  valid_in;
    logic [LANES-1:0]      lane_mask;
    logic signed [ACC_WIDTH-1:0] lane_data [0:LANES-1];

    // DUT Outputs
    logic signed [ACC_WIDTH-1:0] accumulated_out;
    logic                  valid_out;

    // Test Tracking Accounting
    integer test_num   = 0;
    integer pass_count = 0;
    integer fail_count = 0;

    // Independent Software Reference Model State
    longint golden_accumulator = 0;

    // --------------------------------------------------------------------------
    // Instantiate Device Under Test (DUT)
    // --------------------------------------------------------------------------
    accumulator #(
        .ACC_WIDTH (ACC_WIDTH),
        .LANES     (LANES)
    ) dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .en              (en),
        .valid_in        (valid_in),
        .lane_mask       (lane_mask),
        .lane_data       (lane_data),
        .accumulated_out (accumulated_out),
        .valid_out       (valid_out)
    );

    // 100 MHz Simulation Clock (10ns period)
    always #5 clk = ~clk;

    // --------------------------------------------------------------------------
    // Verification Task:
    // Applies stimulus on falling clock edge, samples DUT on rising edge,
    // verifies spatial reduction and temporal accumulation against golden model.
    // --------------------------------------------------------------------------
    task step_accumulator(
        input logic                         test_en,
        input logic                         test_valid_in,
        input logic [LANES-1:0]             test_mask,
        input logic signed [ACC_WIDTH-1:0]  data_arr [0:LANES-1],
        input string                        desc
    );
        longint spatial_sum;
        logic expected_valid_out;
        begin
            test_num++;

            // Apply inputs on falling edge for robust setup
            @(negedge clk);
            en        = test_en;
            valid_in  = test_valid_in;
            lane_mask = test_mask;
            for (int k = 0; k < LANES; k++) begin
                lane_data[k] = data_arr[k];
            end

            // Independent Golden Model Spatial Reduction
            spatial_sum = 0;
            for (int k = 0; k < LANES; k++) begin
                if (test_mask[k]) begin
                    spatial_sum += longint'(data_arr[k]);
                end
            end

            // Temporal Accumulation Logic in Reference Model
            expected_valid_out = test_en && test_valid_in;
            if (expected_valid_out) begin
                golden_accumulator += spatial_sum;
                // Emulate standard 32-bit signed two's complement wrapping
                golden_accumulator = longint'($signed(32'(golden_accumulator)));
            end

            // Wait for rising edge where output register captures update
            @(posedge clk);
            #1; // Delta delay to inspect registered outputs

            // Check for X/Z
            if ($isunknown(accumulated_out) || $isunknown(valid_out)) begin
                $display("[FAIL] Test %02d: %-36s | Output contains X/Z! (out=%b, valid=%b)", 
                         test_num, desc, accumulated_out, valid_out);
                fail_count++;
            end
            // Compare DUT output against independent golden model
            else if ((accumulated_out === 32'(golden_accumulator)) && 
                     (valid_out === expected_valid_out)) begin
                $display("[PASS] Test %02d: %-36s | Acc=%11d, Valid=%b", 
                         test_num, desc, accumulated_out, valid_out);
                pass_count++;
            end else begin
                $display("[FAIL] Test %02d: %-36s | Expected=[Acc=%11d, v=%b], Actual=[Acc=%11d, v=%b]", 
                         test_num, desc, 32'(golden_accumulator), expected_valid_out, accumulated_out, valid_out);
                fail_count++;
            end
        end
    endtask

    // --------------------------------------------------------------------------
    // Helper task to cleanly apply synchronous reset and sync golden model
    // --------------------------------------------------------------------------
    task reset_dut();
        begin
            @(negedge clk);
            rst_n              = 1'b0;
            en                 = 1'b0;
            valid_in           = 1'b0;
            lane_mask          = '0;
            for (int k = 0; k < LANES; k++) lane_data[k] = '0;
            golden_accumulator = 0;
            @(posedge clk);
            #1;
            @(negedge clk);
            rst_n              = 1'b1;
        end
    endtask

    // --------------------------------------------------------------------------
    // Main Stimulus Process
    // --------------------------------------------------------------------------
    initial begin
        logic signed [ACC_WIDTH-1:0] d_vec [0:LANES-1];

        $display("==============================================================================");
        $display("   AMPC PROJECT: STAGE 6 COMMON ACCUMULATOR (accumulator) VERIFICATION        ");
        $display("==============================================================================");

        // Initialize signals
        clk       = 0;
        rst_n     = 0;
        en        = 0;
        valid_in  = 0;
        lane_mask = '0;
        for (int i = 0; i < LANES; i++) d_vec[i] = '0;

        // ----------------------------------------------------------------------
        // SECTION 1: RESET AND IDLE BEHAVIOR
        // ----------------------------------------------------------------------
        $display("\n--- [1] RESET & IDLE VERIFICATION ---");
        repeat (2) @(posedge clk);
        #1;
        test_num++;
        if (accumulated_out === 32'sd0 && valid_out === 1'b0) begin
            $display("[PASS] Test %02d: Synchronous Reset Verification    | accumulated_out=0, valid=0", test_num);
            pass_count++;
        end else begin
            $display("[FAIL] Test %02d: Reset Failure! (out=%0d, valid=%b)", test_num, accumulated_out, valid_out);
            fail_count++;
        end

        // Release reset
        @(negedge clk);
        rst_n = 1'b1;
        golden_accumulator = 0;

        // Test en=0 with valid_in=1
        for (int i = 0; i < LANES; i++) d_vec[i] = 32'sd100;
        step_accumulator(1'b0, 1'b1, 16'hFFFF, d_vec, "Idle: en=0, valid_in=1 (No accumulation)");

        // Test en=1 with valid_in=0
        step_accumulator(1'b1, 1'b0, 16'hFFFF, d_vec, "Idle: en=1, valid_in=0 (No accumulation)");

        // Test en=0 with valid_in=0
        step_accumulator(1'b0, 1'b0, 16'hFFFF, d_vec, "Idle: en=0, valid_in=0 (No accumulation)");

        // ----------------------------------------------------------------------
        // SECTION 2: CRITICAL MASK TEST (NON-ZERO VALUES ON INACTIVE LANES)
        // ----------------------------------------------------------------------
        $display("\n--- [2] CRITICAL MASK TEST (INACTIVE LANES NON-ZERO) ---");
        reset_dut();

        // Mask = 16'h0003. Lanes 0,1 = 100, 200. Lanes 2..15 = large non-zero values!
        d_vec[0] = 32'sd100;
        d_vec[1] = 32'sd200;
        d_vec[2] = 32'sd5000;
        d_vec[3] = -32'sd9999;
        d_vec[4] = 32'sd12345;
        d_vec[5] = -32'sd8888;
        d_vec[6] = 32'sd7777;
        d_vec[7] = -32'sd6666;
        for (int k = 8; k < 16; k++) d_vec[k] = 32'sd99999;

        // Expected reduction = 100 + 200 = 300, NOT the sum of all 16 lanes!
        step_accumulator(1'b1, 1'b1, 16'h0003, d_vec, "Critical Mask: Mask=0003 (exp=300)");

        // ----------------------------------------------------------------------
        // SECTION 3: PROMPT-SPECIFIED TEMPORAL ACCUMULATION (5 CYCLES)
        // ----------------------------------------------------------------------
        $display("\n--- [3] MANDATORY PROMPT TEMPORAL SEQUENCE (5 CYCLES) ---");
        reset_dut();

        // Cycle 1: reduction = 100 -> accumulated = 100
        for (int k = 0; k < 16; k++) d_vec[k] = 32'sd0;
        d_vec[0] = 32'sd60; d_vec[1] = 32'sd40;
        step_accumulator(1'b1, 1'b1, 16'h0003, d_vec, "Temporal Cycle 1 (red=100, acc=100)");

        // Cycle 2: reduction = 250 -> accumulated = 350
        d_vec[0] = 32'sd150; d_vec[1] = 32'sd100;
        step_accumulator(1'b1, 1'b1, 16'h0003, d_vec, "Temporal Cycle 2 (red=250, acc=350)");

        // Cycle 3: reduction = -50 -> accumulated = 300
        d_vec[0] = -32'sd25; d_vec[1] = -32'sd25;
        step_accumulator(1'b1, 1'b1, 16'h0003, d_vec, "Temporal Cycle 3 (red=-50, acc=300)");

        // Cycle 4: reduction = 120 -> accumulated = 420
        d_vec[0] = 32'sd70; d_vec[1] = 32'sd50;
        step_accumulator(1'b1, 1'b1, 16'h0003, d_vec, "Temporal Cycle 4 (red=120, acc=420)");

        // Cycle 5: reduction = -20 -> accumulated = 400
        d_vec[0] = -32'sd10; d_vec[1] = -32'sd10;
        step_accumulator(1'b1, 1'b1, 16'h0003, d_vec, "Temporal Cycle 5 (red=-20, acc=400)");

        // ----------------------------------------------------------------------
        // SECTION 4: VARYING ACTIVE LANE COUNTS (1, 2, 4, 8, 16 LANES)
        // ----------------------------------------------------------------------
        $display("\n--- [4] SCALED ACTIVE LANE TESTS (1, 2, 4, 8, 16 LANES) ---");
        // 1 Lane (W=1, Mask=16'h0001)
        for (int k = 0; k < 16; k++) d_vec[k] = 32'sd25;
        step_accumulator(1'b1, 1'b1, 16'h0001, d_vec, "Single Active Lane (W=1, mask=0001)");

        // 2 Lanes (W=2, Mask=16'h0003)
        for (int k = 0; k < 16; k++) d_vec[k] = 32'sd30;
        step_accumulator(1'b1, 1'b1, 16'h0003, d_vec, "Two Active Lanes (W=2, mask=0003)");

        // 4 Lanes (W=4, Mask=16'h000F)
        for (int k = 0; k < 16; k++) d_vec[k] = 32'sd15;
        step_accumulator(1'b1, 1'b1, 16'h000F, d_vec, "Four Active Lanes (W=4, mask=000F)");

        // 8 Lanes (W=8, Mask=16'h00FF)
        for (int k = 0; k < 16; k++) d_vec[k] = 32'sd10;
        step_accumulator(1'b1, 1'b1, 16'h00FF, d_vec, "Eight Active Lanes (W=8, mask=00FF)");

        // 16 Lanes (W=16, Mask=16'hFFFF)
        for (int k = 0; k < 16; k++) d_vec[k] = 32'sd5;
        step_accumulator(1'b1, 1'b1, 16'hFFFF, d_vec, "Sixteen Active Lanes (W=16, mask=FFFF)");

        // ----------------------------------------------------------------------
        // SECTION 5: ONE-HOT MASKS FOR ALL 16 LANES
        // ----------------------------------------------------------------------
        $display("\n--- [5] ONE-HOT MASKS FOR ALL 16 LANES ---");
        for (int lane = 0; lane < 16; lane++) begin
            logic [15:0] one_hot;
            string test_name;
            one_hot = (16'b1 << lane);
            for (int k = 0; k < 16; k++) d_vec[k] = 32'sd50;
            $sformat(test_name, "One-hot: Lane %02d (Mask=%04h)", lane, one_hot);
            step_accumulator(1'b1, 1'b1, one_hot, d_vec, test_name);
        end

        // ----------------------------------------------------------------------
        // SECTION 6: PARTIAL MASKS & ARITHMETIC CORNER CASES
        // ----------------------------------------------------------------------
        $display("\n--- [6] PARTIAL MASKS & ARITHMETIC CORNER CASES ---");
        // All-zero mask (16'h0000) with non-zero lane data -> no change
        for (int k = 0; k < 16; k++) d_vec[k] = 32'sd999;
        step_accumulator(1'b1, 1'b1, 16'h0000, d_vec, "All-Zero Mask (16'h0000) no change");

        // Partial masks
        step_accumulator(1'b1, 1'b1, 16'h5555, d_vec, "Alternating Mask 16'h5555");
        step_accumulator(1'b1, 1'b1, 16'hAAAA, d_vec, "Alternating Mask 16'hAAAA");
        step_accumulator(1'b1, 1'b1, 16'h01FF, d_vec, "Partial Mask 16'h01FF (9 lanes)");
        step_accumulator(1'b1, 1'b1, 16'h7FFF, d_vec, "Partial Mask 16'h7FFF (15 lanes)");

        // Positive, negative, and mixed signs
        for (int k = 0; k < 16; k++) d_vec[k] = (k % 2 == 0) ? 32'sd500 : -32'sd300;
        step_accumulator(1'b1, 1'b1, 16'hFFFF, d_vec, "Mixed Positive/Negative Sum");

        // Large positive accumulator offset
        for (int k = 0; k < 16; k++) d_vec[k] = 32'sd500000;
        step_accumulator(1'b1, 1'b1, 16'h000F, d_vec, "Large Positive Accumulation (+2M)");

        // Large negative accumulator offset
        for (int k = 0; k < 16; k++) d_vec[k] = -32'sd500000;
        step_accumulator(1'b1, 1'b1, 16'h000F, d_vec, "Large Negative Accumulation (-2M)");

        // Zero operands
        for (int k = 0; k < 16; k++) d_vec[k] = 32'sd0;
        step_accumulator(1'b1, 1'b1, 16'hFFFF, d_vec, "Zero Operands Across All Lanes");

        // ----------------------------------------------------------------------
        // SECTION 7: 50 RANDOMIZED TEST VECTORS (MULTI-CYCLE COMBINATIONS)
        // ----------------------------------------------------------------------
        $display("\n--- [7] 50 RANDOMIZED TEST VECTORS ---");
        for (int i = 0; i < 50; i++) begin
            logic [15:0] rand_mask;
            logic        rand_en;
            logic        rand_vld;
            string test_name;

            rand_mask = $urandom_range(0, 65535);
            rand_en   = ($urandom_range(0, 10) > 1); // Mostly 1, occasionally 0
            rand_vld  = ($urandom_range(0, 10) > 1); // Mostly 1, occasionally 0

            for (int k = 0; k < 16; k++) begin
                // Generate varied signed values spanning negative and positive ranges
                d_vec[k] = $random();
            end

            $sformat(test_name, "Random vector #%02d (m=%04h, en=%b, vld=%b)", 
                     i + 1, rand_mask, rand_en, rand_vld);
            step_accumulator(rand_en, rand_vld, rand_mask, d_vec, test_name);
        end

        // ----------------------------------------------------------------------
        // FINAL RESULTS SUMMARY
        // ----------------------------------------------------------------------
        $display("\n==============================================================================");
        $display("                 STAGE 6 ACCUMULATOR FINAL TEST REPORT                        ");
        $display("==============================================================================");
        $display(" Total Tests Executed : %0d", test_num);
        $display(" Total Tests Passed   : %0d", pass_count);
        $display(" Total Tests Failed   : %0d", fail_count);
        $display("==============================================================================");

        if (fail_count == 0) begin
            $display(" >>> ACCUMULATOR STATUS: PASS <<<");
            $display(" All %0d test cases matched independent reference model with ZERO errors.", test_num);
        end else begin
            $display(" >>> ACCUMULATOR STATUS: FAIL <<<");
            $display(" Test suite failed with %0d discrepancies!", fail_count);
        end
        $display("==============================================================================");

        $finish;
    end

endmodule
