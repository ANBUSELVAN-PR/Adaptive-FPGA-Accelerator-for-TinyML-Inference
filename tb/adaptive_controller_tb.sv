// ==============================================================================
// Project: Adaptive MAC Processing Core (AMPC) for TinyML Inference Acceleration
// Target:  AMD/Xilinx Zynq-7010 (xc7z010clg400-1) | Vivado 2026.1
// File:    adaptive_controller_tb.sv
// Module:  adaptive_controller_tb
// Author:  VLSI/FPGA Project Team
// Details: Stage 10 - Comprehensive Self-Checking Testbench for adaptive_controller
// ==============================================================================

`timescale 1ns / 1ps

module adaptive_controller_tb;

    localparam int WORKLOAD_WIDTH = 16;

    // Clock and Control Signals
    logic                         clk;
    logic                         rst_n;
    logic                         start;
    logic [WORKLOAD_WIDTH-1:0]    workload_size;

    // DUT Outputs
    logic                         ready;
    logic                         busy;
    logic                         done;
    logic [1:0]                   core_sel;
    logic [3:0]                   core_en;
    logic                         ampc2_en;
    logic                         ampc4_en;
    logic                         ampc8_en;
    logic                         ampc16_en;
    logic [1:0]                   ampc2_lane_mask;
    logic [3:0]                   ampc4_lane_mask;
    logic [7:0]                   ampc8_lane_mask;
    logic [15:0]                  ampc16_lane_mask;
    logic [WORKLOAD_WIDTH-1:0]    current_chunk_size;
    logic [WORKLOAD_WIDTH-1:0]    remaining_workload;
    logic                         chunk_valid;

    // Accounting
    integer test_num   = 0;
    integer pass_count = 0;
    integer fail_count = 0;

    // --------------------------------------------------------------------------
    // Instantiate Device Under Test (DUT)
    // --------------------------------------------------------------------------
    adaptive_controller #(
        .WORKLOAD_WIDTH (WORKLOAD_WIDTH)
    ) dut (
        .clk                (clk),
        .rst_n              (rst_n),
        .start              (start),
        .workload_size      (workload_size),
        .ready              (ready),
        .busy               (busy),
        .done               (done),
        .core_sel           (core_sel),
        .core_en            (core_en),
        .ampc2_en           (ampc2_en),
        .ampc4_en           (ampc4_en),
        .ampc8_en           (ampc8_en),
        .ampc16_en          (ampc16_en),
        .ampc2_lane_mask    (ampc2_lane_mask),
        .ampc4_lane_mask    (ampc4_lane_mask),
        .ampc8_lane_mask    (ampc8_lane_mask),
        .ampc16_lane_mask   (ampc16_lane_mask),
        .current_chunk_size (current_chunk_size),
        .remaining_workload (remaining_workload),
        .chunk_valid        (chunk_valid)
    );

    // 100 MHz Simulation Clock (10ns period)
    always #5 clk = ~clk;

    // --------------------------------------------------------------------------
    // Helper function to count active 1-bits in a bitvector
    // --------------------------------------------------------------------------
    function automatic int count_ones_16(input logic [15:0] vec);
        int cnt = 0;
        for (int b = 0; b < 16; b++) if (vec[b]) cnt++;
        return cnt;
    endfunction

    // --------------------------------------------------------------------------
    // Continuous Safety Assertions / Checks
    // --------------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst_n) begin
            // 1. Never more than 1 AMPC core enabled at once
            if ((ampc2_en + ampc4_en + ampc8_en + ampc16_en) > 1) begin
                $display("[ASSERTION ERROR] Multiple AMPC cores enabled simultaneously! en2=%b, en4=%b, en8=%b, en16=%b",
                         ampc2_en, ampc4_en, ampc8_en, ampc16_en);
                fail_count++;
            end

            // 2. In IDLE or DONE, all enables and masks must be 0
            if (ready || done) begin
                if ((core_en !== 4'b0000) || (ampc2_lane_mask !== 2'b00) || 
                    (ampc4_lane_mask !== 4'b0000) || (ampc8_lane_mask !== 8'b00) || 
                    (ampc16_lane_mask !== 16'h0000)) begin
                    $display("[ASSERTION ERROR] Non-zero core enables/masks during non-execute state!");
                    fail_count++;
                end
            end

            // 3. Check for X/Z on control outputs
            if ($isunknown(ready) || $isunknown(busy) || $isunknown(done) || 
                $isunknown(core_sel) || $isunknown(core_en)) begin
                $display("[ASSERTION ERROR] Control outputs contain X/Z states!");
                fail_count++;
            end
        end
    end

    // --------------------------------------------------------------------------
    // Task: Synchronous Reset Task
    // --------------------------------------------------------------------------
    task reset_dut();
        begin
            @(negedge clk);
            rst_n         = 1'b0;
            start         = 1'b0;
            workload_size = '0;
            repeat (2) @(posedge clk);
            #1;
            @(negedge clk);
            rst_n         = 1'b1;
            @(posedge clk);
            #1;
        end
    endtask

    // --------------------------------------------------------------------------
    // Verification Task: Run Workload Batch & Verify Against Reference Model
    // --------------------------------------------------------------------------
    task verify_workload(
        input logic [WORKLOAD_WIDTH-1:0] test_w,
        input string                     desc
    );
        int rem_ref;
        int chunk_idx;
        int exp_core_sel;
        int exp_chunk_size;
        logic [15:0] exp_mask;
        int total_accumulated_ops;
        int timeout;
        begin
            test_num++;
            rem_ref = test_w;
            chunk_idx = 0;
            total_accumulated_ops = 0;
            timeout = 0;

            // Apply start strobe on negedge clk
            @(negedge clk);
            start         = 1'b1;
            workload_size = test_w;
            @(posedge clk);
            #1;
            @(negedge clk);
            start         = 1'b0;
            workload_size = '0;

            // Handle W = 0 special case (immediate transition to DONE)
            if (test_w == 0) begin
                if (done !== 1'b1 && busy !== 1'b0) begin
                    @(posedge clk); #1;
                end
                if (done === 1'b1 && busy === 1'b0 && ampc2_en === 1'b0 && 
                    ampc4_en === 1'b0 && ampc8_en === 1'b0 && ampc16_en === 1'b0) begin
                    $display("[PASS] Test %03d: %-38s | W=0 -> Immediate DONE (0 chunks)", test_num, desc);
                    pass_count++;
                end else begin
                    $display("[FAIL] Test %03d: %-38s | W=0 failed! (done=%b, busy=%b)", test_num, desc, done, busy);
                    fail_count++;
                end
                @(posedge clk); #1;
                return;
            end

            // Multi-cycle / Single-cycle Chunk Verification Loop
            while (rem_ref > 0 && timeout < 5000) begin
                chunk_idx++;
                timeout++;

                // Independent Golden Model Chunk Evaluation
                if (rem_ref <= 2) begin
                    exp_core_sel   = 0; // AMPC-2
                    exp_chunk_size = rem_ref;
                    exp_mask       = (rem_ref == 1) ? 16'h0001 : 16'h0003;
                    rem_ref        = 0;
                end else if (rem_ref <= 4) begin
                    exp_core_sel   = 1; // AMPC-4
                    exp_chunk_size = rem_ref;
                    exp_mask       = (16'b1 << rem_ref) - 16'd1;
                    rem_ref        = 0;
                end else if (rem_ref <= 8) begin
                    exp_core_sel   = 2; // AMPC-8
                    exp_chunk_size = rem_ref;
                    exp_mask       = (16'b1 << rem_ref) - 16'd1;
                    rem_ref        = 0;
                end else if (rem_ref <= 16) begin
                    exp_core_sel   = 3; // AMPC-16
                    exp_chunk_size = rem_ref;
                    exp_mask       = (rem_ref == 16) ? 16'hFFFF : ((16'b1 << rem_ref) - 16'd1);
                    rem_ref        = 0;
                end else begin
                    exp_core_sel   = 3; // AMPC-16
                    exp_chunk_size = 16;
                    exp_mask       = 16'hFFFF;
                    rem_ref        = rem_ref - 16;
                end

                total_accumulated_ops += exp_chunk_size;

                // Inspect DUT outputs during this execution cycle
                #1; // Output inspect window
                if (!busy || !chunk_valid) begin
                    $display("[FAIL] Test %03d: %-38s | Chunk %0d: Expected busy=1, chunk_valid=1 (Act: busy=%b, vld=%b)",
                             test_num, desc, chunk_idx, busy, chunk_valid);
                    fail_count++;
                end else if (core_sel !== exp_core_sel[1:0]) begin
                    $display("[FAIL] Test %03d: %-38s | Chunk %0d: Core selection mismatch! Exp=%0d, Act=%0d",
                             test_num, desc, chunk_idx, exp_core_sel, core_sel);
                    fail_count++;
                end else if (current_chunk_size !== exp_chunk_size[15:0]) begin
                    $display("[FAIL] Test %03d: %-38s | Chunk %0d: Chunk size mismatch! Exp=%0d, Act=%0d",
                             test_num, desc, chunk_idx, exp_chunk_size, current_chunk_size);
                    fail_count++;
                end else begin
                    // Verify correct mask based on selected core
                    logic [15:0] act_mask;
                    case (core_sel)
                        2'b00: act_mask = {14'b0, ampc2_lane_mask};
                        2'b01: act_mask = {12'b0, ampc4_lane_mask};
                        2'b10: act_mask = {8'b0, ampc8_lane_mask};
                        2'b11: act_mask = ampc16_lane_mask;
                    endcase

                    if (act_mask !== exp_mask) begin
                        $display("[FAIL] Test %03d: %-38s | Chunk %0d: Mask mismatch! Exp=%04h, Act=%04h",
                                 test_num, desc, chunk_idx, exp_mask, act_mask);
                        fail_count++;
                    end
                end

                // Clock step to next chunk
                @(posedge clk);
            end

            // Verify DONE state on next clock cycle
            #1;
            if (done === 1'b1 && busy === 1'b0 && total_accumulated_ops === int'(test_w)) begin
                $display("[PASS] Test %03d: %-38s | W=%5d -> %0d chunk(s), TotalOps=%5d, DONE=1",
                         test_num, desc, test_w, chunk_idx, total_accumulated_ops, done);
                pass_count++;
            end else begin
                $display("[FAIL] Test %03d: %-38s | Completion mismatch! (done=%b, busy=%b, ops=%0d vs exp=%0d)",
                         test_num, desc, done, busy, total_accumulated_ops, test_w);
                fail_count++;
            end

            // Return to IDLE
            @(posedge clk);
            #1;
            if (!ready) begin
                $display("[FAIL] Test %03d: %-38s | Controller did not return to IDLE (ready=%b)", test_num, desc, ready);
                fail_count++;
            end
        end
    endtask

    // --------------------------------------------------------------------------
    // Main Stimulus Process
    // --------------------------------------------------------------------------
    initial begin
        $display("==============================================================================");
        $display("   AMPC PROJECT: STAGE 10 ADAPTIVE CONTROLLER & FSM (adaptive_controller)     ");
        $display("==============================================================================");

        // Initialize signals
        clk           = 0;
        rst_n         = 0;
        start         = 0;
        workload_size = '0;

        // ----------------------------------------------------------------------
        // SECTION 1: RESET & IDLE BEHAVIOR
        // ----------------------------------------------------------------------
        $display("\n--- [1] SYNCHRONOUS RESET & IDLE VERIFICATION ---");
        repeat (2) @(posedge clk);
        #1;
        test_num++;
        if (busy === 1'b0 && done === 1'b0 && core_en === 4'b0000 && ampc2_lane_mask === 2'b00 && ampc16_lane_mask === 16'h0000) begin
            $display("[PASS] Test %03d: Active-Low Reset Asserted Check         | busy=0, done=0, core_en=0, masks=0", test_num);
            pass_count++;
        end else begin
            $display("[FAIL] Test %03d: Reset Asserted Check Failed!", test_num);
            fail_count++;
        end

        // Release reset
        @(negedge clk);
        rst_n = 1'b1;
        @(posedge clk);
        #1;
        test_num++;
        if (ready === 1'b1 && busy === 1'b0 && done === 1'b0 && core_en === 4'b0000) begin
            $display("[PASS] Test %03d: Idle State After Reset Deassertion     | ready=1, busy=0, done=0, core_en=0", test_num);
            pass_count++;
        end else begin
            $display("[FAIL] Test %03d: Post-Reset Idle Check Failed!", test_num);
            fail_count++;
        end

        // ----------------------------------------------------------------------
        // SECTION 2: ZERO WORKLOAD (W=0)
        // ----------------------------------------------------------------------
        $display("\n--- [2] ZERO WORKLOAD (W=0) ---");
        verify_workload(16'd0, "Zero Workload (W=0 -> No Cores, DONE)");

        // ----------------------------------------------------------------------
        // SECTION 3: SINGLE-CYCLE WORKLOADS (W=1..16)
        // ----------------------------------------------------------------------
        $display("\n--- [3] SINGLE-CYCLE WORKLOADS (W=1..16) ---");
        verify_workload(16'd1,  "Workload W=1  (AMPC-2, Mask=01)");
        verify_workload(16'd2,  "Workload W=2  (AMPC-2, Mask=11)");
        verify_workload(16'd3,  "Workload W=3  (AMPC-4, Mask=0111)");
        verify_workload(16'd4,  "Workload W=4  (AMPC-4, Mask=1111)");
        verify_workload(16'd5,  "Workload W=5  (AMPC-8, Mask=00011111)");
        verify_workload(16'd8,  "Workload W=8  (AMPC-8, Mask=11111111)");
        verify_workload(16'd9,  "Workload W=9  (AMPC-16, Mask=0000000111111111)");
        verify_workload(16'd16, "Workload W=16 (AMPC-16, Mask=1111111111111111)");

        // ----------------------------------------------------------------------
        // SECTION 4: MULTI-CYCLE CHUNKING WORKLOADS (>16)
        // ----------------------------------------------------------------------
        $display("\n--- [4] MULTI-CYCLE CHUNKING WORKLOADS (>16) ---");
        verify_workload(16'd17,  "Workload W=17 (16 + 1 -> AMPC16 + AMPC2)");
        verify_workload(16'd18,  "Workload W=18 (16 + 2 -> AMPC16 + AMPC2)");
        verify_workload(16'd25,  "Workload W=25 (16 + 9 -> AMPC16 + AMPC16)");
        verify_workload(16'd32,  "Workload W=32 (16 + 16 -> AMPC16 + AMPC16)");
        verify_workload(16'd33,  "Workload W=33 (16 + 16 + 1 -> AMPC16*2 + AMPC2)");
        verify_workload(16'd48,  "Workload W=48 (16*3 -> AMPC16*3)");
        verify_workload(16'd64,  "Workload W=64 (16*4 -> AMPC16*4)");
        verify_workload(16'd100, "Workload W=100 (16*6 + 4 -> AMPC16*6 + AMPC4)");

        // ----------------------------------------------------------------------
        // SECTION 5: MAXIMUM REPRESENTABLE WORKLOAD (W=65535)
        // ----------------------------------------------------------------------
        $display("\n--- [5] MAXIMUM WORKLOAD STRESS TEST (W=65535) ---");
        // Note: W=65535 = 4095 chunks of 16 + 1 chunk of 15 (4096 total chunks)
        verify_workload(16'hFFFF, "Maximum Workload W=65535 (4096 Chunks Stress Test)");

        // ----------------------------------------------------------------------
        // SECTION 6: CONSECUTIVE BACK-TO-BACK WORKLOAD BATCHES
        // ----------------------------------------------------------------------
        $display("\n--- [6] CONSECUTIVE BACK-TO-BACK WORKLOAD REQUESTS ---");
        verify_workload(16'd1,  "Consecutive 1: W=1");
        verify_workload(16'd17, "Consecutive 2: W=17");
        verify_workload(16'd3,  "Consecutive 3: W=3");
        verify_workload(16'd33, "Consecutive 4: W=33");
        verify_workload(16'd0,  "Consecutive 5: W=0");
        verify_workload(16'd25, "Consecutive 6: W=25");

        // ----------------------------------------------------------------------
        // SECTION 7: 100 RANDOMIZED WORKLOAD TRANSACTIONS
        // ----------------------------------------------------------------------
        $display("\n--- [7] 100 RANDOMIZED WORKLOAD TEST TRANSACTIONS ---");
        for (int i = 0; i < 100; i++) begin
            logic [WORKLOAD_WIDTH-1:0] rand_w;
            string test_name;

            // Generate mix of tiny (0..16), small (17..64), medium (65..512), and large (513..2048) workloads
            if (i < 25) begin
                rand_w = $urandom_range(0, 16);
            end else if (i < 50) begin
                rand_w = $urandom_range(17, 64);
            end else if (i < 75) begin
                rand_w = $urandom_range(65, 256);
            end else begin
                rand_w = $urandom_range(257, 1024);
            end

            $sformat(test_name, "Random Workload #%03d (W=%4d)", i+1, rand_w);
            verify_workload(rand_w, test_name);
        end

        // ----------------------------------------------------------------------
        // FINAL RESULTS SUMMARY
        // ----------------------------------------------------------------------
        $display("\n==============================================================================");
        $display("             STAGE 10 ADAPTIVE CONTROLLER FINAL TEST REPORT                   ");
        $display("==============================================================================");
        $display(" Total Tests Executed : %0d", test_num);
        $display(" Total Tests Passed   : %0d", pass_count);
        $display(" Total Tests Failed   : %0d", fail_count);
        $display("==============================================================================");

        if (fail_count == 0) begin
            $display(" >>> ADAPTIVE CONTROLLER STATUS: PASS <<<");
            $display(" All %0d test cases matched independent reference model with ZERO errors.", test_num);
        end else begin
            $display(" >>> ADAPTIVE CONTROLLER STATUS: FAIL <<<");
            $display(" Test suite failed with %0d discrepancies!", fail_count);
        end
        $display("==============================================================================");

        $finish;
    end

endmodule
