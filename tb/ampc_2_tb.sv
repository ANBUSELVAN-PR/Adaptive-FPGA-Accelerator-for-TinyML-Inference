// ==============================================================================
// Project: Adaptive MAC Processing Core (AMPC) for TinyML Inference Acceleration
// Target:  AMD/Xilinx Zynq-7010 (xc7z010clg400-1) | Vivado 2026.1
// File:    ampc_2_tb.sv
// Module:  ampc_2_tb
// Author:  VLSI/FPGA Project Team
// Details: Stage 2 - Comprehensive Self-Checking Testbench for ampc_2
// ==============================================================================

`timescale 1ns / 1ps

module ampc_2_tb;

    localparam int DATA_WIDTH   = 8;
    localparam int WEIGHT_WIDTH = 8;
    localparam int ACC_WIDTH    = 32;
    localparam int LANES        = 2;

    // Clock and Control Signals
    logic        clk;
    logic        rst_n;
    logic        en;
    logic [1:0]  lane_mask;

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
    ampc_2 #(
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
    // Drives stimulus on falling edge, samples DUT on rising edge (1 cycle latency),
    // compares against independent reference model, checks for X/Z.
    // --------------------------------------------------------------------------
    task check_ampc_2(
        input logic                           test_en,
        input logic [1:0]                     test_mask,
        input logic signed [DATA_WIDTH-1:0]   d0, d1,
        input logic signed [WEIGHT_WIDTH-1:0] w0, w1,
        input logic signed [ACC_WIDTH-1:0]    a0, a1,
        input string                          desc
    );
        int expected_out [0:1];
        logic expected_valid;
        begin
            test_num++;

            // Apply inputs on falling edge to provide adequate setup time
            @(negedge clk);
            en        = test_en;
            lane_mask = test_mask;
            data_in[0] = d0; data_in[1] = d1;
            weight[0]  = w0; weight[1]  = w1;
            acc_in[0]  = a0; acc_in[1]  = a1;

            // Independent Reference Model Calculation
            expected_valid = test_en;
            for (int k = 0; k < LANES; k++) begin
                if (test_en && test_mask[k]) begin
                    int prod;
                    prod = (k == 0) ? (int'(d0) * int'(w0)) : (int'(d1) * int'(w1));
                    expected_out[k] = (k == 0) ? (int'(a0) + prod) : (int'(a1) + prod);
                end else begin
                    // When masked or disabled, operand gating produces 0 product, preserving acc_in
                    expected_out[k] = (k == 0) ? int'(a0) : int'(a1);
                end
            end

            // Wait for rising edge where output register captures result
            @(posedge clk);
            #1; // Small delta delay after clock edge to inspect registered outputs

            // Check for unknown / X / Z
            if ($isunknown(acc_out[0]) || $isunknown(acc_out[1]) || $isunknown(valid_out)) begin
                $display("[FAIL] Test %02d: %-32s | Output contains X/Z! (acc_out=[%b, %b], valid=%b)",
                         test_num, desc, acc_out[0], acc_out[1], valid_out);
                fail_count++;
            end
            // Check outputs against independent reference
            else if ((acc_out[0] === expected_out[0]) && 
                     (acc_out[1] === expected_out[1]) && 
                     (valid_out === expected_valid)) begin
                $display("[PASS] Test %02d: %-32s | L0=%8d, L1=%8d | Valid=%b", 
                         test_num, desc, acc_out[0], acc_out[1], valid_out);
                pass_count++;
            end else begin
                $display("[FAIL] Test %02d: %-32s | Expected=[%8d, %8d, v=%b], Actual=[%8d, %8d, v=%b]", 
                         test_num, desc, expected_out[0], expected_out[1], expected_valid, 
                         acc_out[0], acc_out[1], valid_out);
                fail_count++;
            end
        end
    endtask

    // --------------------------------------------------------------------------
    // Main Stimulus Process
    // --------------------------------------------------------------------------
    initial begin
        $display("==============================================================================");
        $display("     AMPC PROJECT: STAGE 2 AMPC-2 (ampc_2) SELF-CHECKING VERIFICATION         ");
        $display("==============================================================================");

        // Initialize signals
        clk       = 0;
        rst_n     = 0;
        en        = 0;
        lane_mask = 2'b00;
        data_in[0] = '0; data_in[1] = '0;
        weight[0]  = '0; weight[1]  = '0;
        acc_in[0]  = '0; acc_in[1]  = '0;

        // ----------------------------------------------------------------------
        // SECTION 1: RESET AND IDLE BEHAVIOR
        // ----------------------------------------------------------------------
        $display("\n--- [1] RESET & IDLE VERIFICATION ---");
        repeat (2) @(posedge clk);
        #1;
        test_num++;
        if (acc_out[0] === 32'sd0 && acc_out[1] === 32'sd0 && valid_out === 1'b0) begin
            $display("[PASS] Test %02d: Synchronous Reset Verification | Outputs zeroed, valid=0", test_num);
            pass_count++;
        end else begin
            $display("[FAIL] Test %02d: Reset Failure! (acc_out=[%0d, %0d], valid=%b)", 
                     test_num, acc_out[0], acc_out[1], valid_out);
            fail_count++;
        end

        // Release reset
        @(negedge clk);
        rst_n = 1'b1;

        // Verify enable disabled (en=0) keeps valid_out=0
        check_mac_idle: begin
            test_num++;
            @(negedge clk);
            en = 0; lane_mask = 2'b11;
            data_in[0] = 8'sd10; data_in[1] = 8'sd20;
            weight[0]  = 8'sd5;  weight[1]  = 8'sd5;
            acc_in[0]  = 32'sd0; acc_in[1]  = 32'sd0;
            @(posedge clk);
            #1;
            if (valid_out === 1'b0) begin
                $display("[PASS] Test %02d: Core Enable Low (en=0)         | valid_out=0 correctly held", test_num);
                pass_count++;
            end else begin
                $display("[FAIL] Test %02d: Core Enable Failure (valid_out=%b)", test_num, valid_out);
                fail_count++;
            end
        end

        // ----------------------------------------------------------------------
        // SECTION 2: PARALLEL COMPUTATION & ARITHMETIC TEST CASES
        // ----------------------------------------------------------------------
        $display("\n--- [2] PARALLEL MAC ARITHMETIC TESTS ---");
        // Positive values on both lanes
        check_ampc_2(1'b1, 2'b11, 
                     8'sd3, 8'sd2,    // d0=3, d1=2
                     8'sd4, 8'sd6,    // w0=4, w1=6
                     32'sd5, 32'sd10, // a0=5, a1=10
                     "Positive values (L0:3*4+5, L1:2*6+10)");

        // Mixed signs on both lanes
        check_ampc_2(1'b1, 2'b11, 
                     -8'sd3, -8'sd5,  // d0=-3, d1=-5
                     8'sd4,  -8'sd6,  // w0=4,  w1=-6
                     32'sd5, -32'sd10,// a0=5,  a1=-10
                     "Mixed signs (L0:-3*4+5, L1:-5*-6+-10)");

        // Large operands and offsets
        check_ampc_2(1'b1, 2'b11, 
                     8'sd10, 8'sd12, 
                     8'sd10, 8'sd8, 
                     32'sd1000, 32'sd2000, 
                     "Large offsets (L0:100+1000, L1:96+2000)");

        // ----------------------------------------------------------------------
        // SECTION 3: LANE MASKING TESTS (MANDATORY REQUIREMENT)
        // ----------------------------------------------------------------------
        $display("\n--- [3] DYNAMIC LANE MASKING TESTS ---");
        // Mask = 2'b01 (Lane 0 active, Lane 1 disabled/masked)
        // Lane 1 data/weight must be suppressed; acc_in must pass through untouched!
        check_ampc_2(1'b1, 2'b01, 
                     8'sd7,  8'sd12,   // d0=7, d1=12
                     8'sd3,  8'sd8,    // w0=3, w1=8
                     32'sd10, 32'sd50, // a0=10, a1=50
                     "Mask 2'b01 (L0 active, L1 masked)");

        // Mask = 2'b10 (Lane 0 disabled/masked, Lane 1 active)
        // Lane 0 data/weight suppressed; a0 passes through; L1 active
        check_ampc_2(1'b1, 2'b10, 
                     8'sd10, 8'sd4, 
                     8'sd10, 8'sd5, 
                     32'sd100, 32'sd20, 
                     "Mask 2'b10 (L0 masked, L1 active)");

        // Mask = 2'b00 (Both lanes masked)
        // Both lanes pass their accumulator inputs with 0 product added
        check_ampc_2(1'b1, 2'b00, 
                     8'sd15, 8'sd25, 
                     8'sd4,  8'sd2, 
                     32'sd75, 32'sd85, 
                     "Mask 2'b00 (Both lanes masked)");

        // ----------------------------------------------------------------------
        // SECTION 4: INT8 EXTREME BOUNDARY CONDITIONS
        // ----------------------------------------------------------------------
        $display("\n--- [4] INT8 EXTREME BOUNDARY CONDITIONS ---");
        // Min*Min on Lane 0 (-128*-128 = +16384), Max*Max on Lane 1 (127*127 = +16129)
        check_ampc_2(1'b1, 2'b11, 
                     -8'sd128, 8'sd127, 
                     -8'sd128, 8'sd127, 
                     32'sd0,   32'sd0, 
                     "Boundary (L0:Min*Min, L1:Max*Max)");

        // Min*Max on Lane 0 (-128*127 = -16256), Max*Min on Lane 1 (127*-128 = -16256)
        check_ampc_2(1'b1, 2'b11, 
                     -8'sd128, 8'sd127, 
                     8'sd127,  -8'sd128, 
                     32'sd100, -32'sd100, 
                     "Boundary (L0:Min*Max, L1:Max*Min)");

        // ----------------------------------------------------------------------
        // SECTION 5: MULTI-CYCLE STREAMING EXECUTION
        // ----------------------------------------------------------------------
        $display("\n--- [5] MULTI-CYCLE STREAMING (5 CONSECUTIVE CYCLES) ---");
        for (int c = 0; c < 5; c++) begin
            string stream_name;
            $sformat(stream_name, "Pipelined Stream Cycle %0d", c + 1);
            check_ampc_2(1'b1, 2'b11, 
                         8'(c + 1),  8'(c + 2), 
                         8'(c + 3),  8'(c + 4), 
                         32'(c * 10), 32'(c * 20), 
                         stream_name);
        end

        // ----------------------------------------------------------------------
        // SECTION 6: 25 RANDOMIZED SIGNED TEST VECTORS
        // ----------------------------------------------------------------------
        $display("\n--- [6] 25 RANDOMIZED TEST VECTORS (ARBITRARY MASKS & INPUTS) ---");
        for (int i = 0; i < 25; i++) begin
            logic signed [7:0]  r_d0, r_d1;
            logic signed [7:0]  r_w0, r_w1;
            logic signed [31:0] r_a0, r_a1;
            logic [1:0]         r_mask;
            string test_name;

            r_d0 = $urandom_range(0, 255);
            r_d1 = $urandom_range(0, 255);
            r_w0 = $urandom_range(0, 255);
            r_w1 = $urandom_range(0, 255);
            r_a0 = $random();
            r_a1 = $random();
            r_mask = $urandom_range(0, 3); // Test masks 2'b00, 2'b01, 2'b10, 2'b11

            $sformat(test_name, "Random vector #%0d (mask=%b)", i + 1, r_mask);
            check_ampc_2(1'b1, r_mask, r_d0, r_d1, r_w0, r_w1, r_a0, r_a1, test_name);
        end

        // ----------------------------------------------------------------------
        // FINAL RESULTS SUMMARY
        // ----------------------------------------------------------------------
        $display("\n==============================================================================");
        $display("                   STAGE 2 AMPC-2 FINAL TEST REPORT                           ");
        $display("==============================================================================");
        $display(" Total Tests Executed : %0d", test_num);
        $display(" Total Tests Passed   : %0d", pass_count);
        $display(" Total Tests Failed   : %0d", fail_count);
        $display("==============================================================================");

        if (fail_count == 0) begin
            $display(" >>> AMPC-2 STATUS: PASS <<<");
            $display(" All %0d test cases matched independent reference model with ZERO errors.", test_num);
        end else begin
            $display(" >>> AMPC-2 STATUS: FAIL <<<");
            $display(" Test suite failed with %0d discrepancies!", fail_count);
        end
        $display("==============================================================================");

        $finish;
    end

endmodule
