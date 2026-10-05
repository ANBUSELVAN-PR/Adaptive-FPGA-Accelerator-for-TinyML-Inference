// ==============================================================================
// Project: Adaptive MAC Processing Core (AMPC) for TinyML Inference Acceleration
// Target:  AMD/Xilinx Zynq-7010 (xc7z010clg400-1) | Vivado 2026.1
// File:    ampc_top_tb.sv
// Module:  ampc_top_tb
// Author:  VLSI/FPGA Project Team
// Details: Stage 11 - Comprehensive Self-Checking Testbench for ampc_top
// ==============================================================================

`timescale 1ns / 1ps

module ampc_top_tb;

    localparam int DATA_WIDTH     = 8;
    localparam int ACC_WIDTH      = 32;
    localparam int MAX_LANES      = 16;
    localparam int BUFFER_DEPTH   = 64;
    localparam int WORKLOAD_WIDTH = 16;
    localparam int ADDR_WIDTH     = $clog2(BUFFER_DEPTH);

    // Clock and Control Signals
    logic                         clk;
    logic                         rst_n;
    logic                         start;
    logic [WORKLOAD_WIDTH-1:0]    workload_size;

    // Parallel multi-lane operand streams
    logic signed [DATA_WIDTH-1:0] data_in  [0:MAX_LANES-1];
    logic signed [DATA_WIDTH-1:0] weight   [0:MAX_LANES-1];

    // On-chip buffer ports
    logic                         ibuf_wr_en;
    logic [ADDR_WIDTH-1:0]        ibuf_wr_addr;
    logic signed [DATA_WIDTH-1:0] ibuf_wr_data;
    logic [ADDR_WIDTH-1:0]        ibuf_rd_addr;
    logic signed [DATA_WIDTH-1:0] ibuf_rd_data;

    logic                         wbuf_wr_en;
    logic [ADDR_WIDTH-1:0]        wbuf_wr_addr;
    logic signed [DATA_WIDTH-1:0] wbuf_wr_data;
    logic [ADDR_WIDTH-1:0]        wbuf_rd_addr;
    logic signed [DATA_WIDTH-1:0] wbuf_rd_data;

    // DUT Outputs
    logic                         ready;
    logic                         busy;
    logic                         done;
    logic [1:0]                   active_core;
    logic [4:0]                   analyzer_capacity;
    logic [WORKLOAD_WIDTH-1:0]    analyzer_remainder;
    logic                         analyzer_valid;
    logic signed [ACC_WIDTH-1:0]  accumulated_out;
    logic signed [ACC_WIDTH-1:0]  output_data;
    logic                         output_valid;

    // Test Tracking Accounting
    integer test_num   = 0;
    integer pass_count = 0;
    integer fail_count = 0;

    // --------------------------------------------------------------------------
    // Instantiate Device Under Test (DUT)
    // --------------------------------------------------------------------------
    ampc_top #(
        .DATA_WIDTH     (DATA_WIDTH),
        .ACC_WIDTH      (ACC_WIDTH),
        .MAX_LANES      (MAX_LANES),
        .BUFFER_DEPTH   (BUFFER_DEPTH),
        .WORKLOAD_WIDTH (WORKLOAD_WIDTH)
    ) dut (
        .clk                (clk),
        .rst_n              (rst_n),
        .start              (start),
        .workload_size      (workload_size),
        .data_in            (data_in),
        .weight             (weight),
        .ibuf_wr_en         (ibuf_wr_en),
        .ibuf_wr_addr       (ibuf_wr_addr),
        .ibuf_wr_data       (ibuf_wr_data),
        .ibuf_rd_addr       (ibuf_rd_addr),
        .ibuf_rd_data       (ibuf_rd_data),
        .wbuf_wr_en         (wbuf_wr_en),
        .wbuf_wr_addr       (wbuf_wr_addr),
        .wbuf_wr_data       (wbuf_wr_data),
        .wbuf_rd_addr       (wbuf_rd_addr),
        .wbuf_rd_data       (wbuf_rd_data),
        .ready              (ready),
        .busy               (busy),
        .done               (done),
        .active_core        (active_core),
        .analyzer_capacity  (analyzer_capacity),
        .analyzer_remainder (analyzer_remainder),
        .analyzer_valid     (analyzer_valid),
        .accumulated_out    (accumulated_out),
        .output_data        (output_data),
        .output_valid       (output_valid)
    );

    // 100 MHz Simulation Clock (10ns period)
    always #5 clk = ~clk;

    // --------------------------------------------------------------------------
    // Task: Synchronous Reset
    // --------------------------------------------------------------------------
    task reset_dut();
        begin
            @(negedge clk);
            rst_n         = 1'b0;
            start         = 1'b0;
            workload_size = '0;
            for (int k = 0; k < MAX_LANES; k++) begin
                data_in[k] = '0;
                weight[k]  = '0;
            end
            ibuf_wr_en    = 0;
            wbuf_wr_en    = 0;
            repeat (2) @(posedge clk);
            #1;
            @(negedge clk);
            rst_n         = 1'b1;
            @(posedge clk);
            #1;
        end
    endtask

    // --------------------------------------------------------------------------
    // Task: Run Workload Inference & Verify Dot-Product and ReLU Outputs
    // --------------------------------------------------------------------------
    task run_inference(
        input int                         w_size,
        input logic signed [DATA_WIDTH-1:0] test_x [],
        input logic signed [DATA_WIDTH-1:0] test_wgt [],
        input string                      desc
    );
        longint golden_dot;
        longint golden_relu;
        int remaining_items;
        int stream_idx;
        int chunk_size;
        int chunk_num;
        int timeout;
        begin
            test_num++;

            // Independent Software Golden Reference Model Calculation
            golden_dot = 0;
            for (int i = 0; i < w_size; i++) begin
                golden_dot += longint'(test_x[i]) * longint'(test_wgt[i]);
            end
            golden_relu = (golden_dot < 0) ? 0 : golden_dot;

            // Wait until DUT is ready
            while (!ready) @(posedge clk);

            // Apply start strobe on falling edge
            @(negedge clk);
            start         = 1'b1;
            workload_size = 16'(w_size);

            remaining_items = w_size;
            stream_idx      = 0;
            chunk_num       = 0;

            // Feed first chunk on same falling edge as start
            if (w_size > 0) begin
                chunk_size = (remaining_items > 16) ? 16 : remaining_items;
                for (int k = 0; k < MAX_LANES; k++) begin
                    if (k < chunk_size) begin
                        data_in[k] = test_x[stream_idx + k];
                        weight[k]  = test_wgt[stream_idx + k];
                    end else begin
                        // Inactive lanes fed with nonzero garbage to rigorously test mask isolation!
                        data_in[k] = 8'sd127;
                        weight[k]  = -8'sd128;
                    end
                end
                stream_idx      += chunk_size;
                remaining_items -= chunk_size;
                chunk_num++;
            end

            @(posedge clk);
            #1;
            @(negedge clk);
            start         = 1'b0;
            workload_size = '0;

            // Stream subsequent chunks for multi-cycle workloads (>16)
            while (remaining_items > 0) begin
                // Wait for the posedge clk where the previous chunk is sampled into AMPC
                @(posedge clk);
                #1;
                @(negedge clk);
                chunk_size = (remaining_items > 16) ? 16 : remaining_items;
                for (int k = 0; k < MAX_LANES; k++) begin
                    if (k < chunk_size) begin
                        data_in[k] = test_x[stream_idx + k];
                        weight[k]  = test_wgt[stream_idx + k];
                    end else begin
                        data_in[k] = -8'sd100;
                        weight[k]  = 8'sd99;
                    end
                end
                stream_idx      += chunk_size;
                remaining_items -= chunk_size;
                chunk_num++;
            end

            // Wait for completion (output_valid & done)
            timeout = 0;
            while (!output_valid && timeout < 200) begin
                @(posedge clk);
                #1;
                timeout++;
            end

            // Inspect output correctness
            if ($isunknown(accumulated_out) || $isunknown(output_data) || $isunknown(output_valid) || $isunknown(done)) begin
                $display("[FAIL] Test %03d: %-38s | Output contains X/Z! (dot=%b, relu=%b)",
                         test_num, desc, accumulated_out, output_data);
                fail_count++;
            end else if ((accumulated_out === 32'(golden_dot)) && 
                         (output_data === 32'(golden_relu)) &&
                         (done === 1'b1) && (output_valid === 1'b1)) begin
                $display("[PASS] Test %03d: %-38s | W=%4d -> Dot=%10d, ReLU=%10d, Chunks=%2d",
                         test_num, desc, w_size, accumulated_out, output_data, chunk_num);
                pass_count++;
            end else begin
                $display("[FAIL] Test %03d: %-38s | Exp=[Dot=%10d, ReLU=%10d], Act=[Dot=%10d, ReLU=%10d]",
                         test_num, desc, 32'(golden_dot), 32'(golden_relu), accumulated_out, output_data);
                fail_count++;
            end

            @(posedge clk);
        end
    endtask

    // --------------------------------------------------------------------------
    // Main Stimulus Process
    // --------------------------------------------------------------------------
    initial begin
        logic signed [DATA_WIDTH-1:0] dyn_x   [];
        logic signed [DATA_WIDTH-1:0] dyn_wgt [];

        $display("==============================================================================");
        $display("      AMPC PROJECT: STAGE 11 TOP-LEVEL INTEGRATION (ampc_top) VERIFY          ");
        $display("==============================================================================");

        // Initialize signals
        clk           = 0;
        rst_n         = 0;
        start         = 0;
        workload_size = '0;
        ibuf_wr_en    = 0;
        ibuf_wr_addr  = '0;
        ibuf_wr_data  = '0;
        ibuf_rd_addr  = '0;
        wbuf_wr_en    = 0;
        wbuf_wr_addr  = '0;
        wbuf_wr_data  = '0;
        wbuf_rd_addr  = '0;

        for (int k = 0; k < MAX_LANES; k++) begin
            data_in[k] = '0;
            weight[k]  = '0;
        end

        // ----------------------------------------------------------------------
        // SECTION 1: RESET & IDLE VERIFICATION
        // ----------------------------------------------------------------------
        $display("\n--- [1] SYNCHRONOUS RESET & IDLE VERIFICATION ---");
        repeat (2) @(posedge clk);
        #1;
        test_num++;
        if (ready === 1'b1 && busy === 1'b0 && done === 1'b0 && output_valid === 1'b0) begin
            $display("[PASS] Test %03d: Reset State Verification               | ready=1, busy=0, done=0, out_valid=0", test_num);
            pass_count++;
        end else begin
            $display("[FAIL] Test %03d: Reset State Failed! ready=%b, busy=%b", test_num, ready, busy);
            fail_count++;
        end

        @(negedge clk);
        rst_n = 1'b1;
        @(posedge clk);
        #1;

        // ----------------------------------------------------------------------
        // SECTION 2: ZERO WORKLOAD (W=0)
        // ----------------------------------------------------------------------
        $display("\n--- [2] ZERO WORKLOAD VERIFICATION ---");
        dyn_x   = new[0];
        dyn_wgt = new[0];
        run_inference(0, dyn_x, dyn_wgt, "Zero Workload (W=0 -> Dot=0, ReLU=0)");

        // ----------------------------------------------------------------------
        // SECTION 3: SINGLE-CYCLE WORKLOADS (W=1..16)
        // ----------------------------------------------------------------------
        $display("\n--- [3] SINGLE-CYCLE WORKLOADS (W=1..16) ---");
        // W=1
        dyn_x   = new[1]; dyn_wgt = new[1];
        dyn_x[0] = 8'sd12; dyn_wgt[0] = 8'sd5; // 12 * 5 = 60
        run_inference(1, dyn_x, dyn_wgt, "Single-Lane W=1 (12*5 = 60)");

        // W=2
        dyn_x   = new[2]; dyn_wgt = new[2];
        dyn_x[0] = 8'sd10; dyn_wgt[0] = 8'sd4;   // 40
        dyn_x[1] = -8'sd5; dyn_wgt[1] = 8'sd6;   // -30 -> Dot = 10, ReLU = 10
        run_inference(2, dyn_x, dyn_wgt, "AMPC-2 Core W=2 (Dot=10)");

        // W=3 (AMPC-4 Partial)
        dyn_x   = new[3]; dyn_wgt = new[3];
        dyn_x[0] = 8'sd20; dyn_wgt[0] = 8'sd2;   // 40
        dyn_x[1] = 8'sd15; dyn_wgt[1] = 8'sd3;   // 45
        dyn_x[2] = -8'sd50; dyn_wgt[2] = 8'sd2;  // -100 -> Dot = -15, ReLU = 0
        run_inference(3, dyn_x, dyn_wgt, "AMPC-4 Partial W=3 (Dot=-15, ReLU=0)");

        // W=4 (AMPC-4 Full)
        dyn_x   = new[4]; dyn_wgt = new[4];
        for (int i = 0; i < 4; i++) begin dyn_x[i] = 8'(i*10 + 5); dyn_wgt[i] = 8'sd2; end
        run_inference(4, dyn_x, dyn_wgt, "AMPC-4 Full W=4");

        // W=5 (AMPC-8 Partial)
        dyn_x   = new[5]; dyn_wgt = new[5];
        for (int i = 0; i < 5; i++) begin dyn_x[i] = 8'(i*5); dyn_wgt[i] = 8'sd3; end
        run_inference(5, dyn_x, dyn_wgt, "AMPC-8 Partial W=5");

        // W=8 (AMPC-8 Full)
        dyn_x   = new[8]; dyn_wgt = new[8];
        for (int i = 0; i < 8; i++) begin dyn_x[i] = 8'(i*4 - 10); dyn_wgt[i] = 8'sd2; end
        run_inference(8, dyn_x, dyn_wgt, "AMPC-8 Full W=8");

        // W=9 (AMPC-16 Partial)
        dyn_x   = new[9]; dyn_wgt = new[9];
        for (int i = 0; i < 9; i++) begin dyn_x[i] = 8'(i*3); dyn_wgt[i] = 8'sd4; end
        run_inference(9, dyn_x, dyn_wgt, "AMPC-16 Partial W=9");

        // W=16 (AMPC-16 Full)
        dyn_x   = new[16]; dyn_wgt = new[16];
        for (int i = 0; i < 16; i++) begin dyn_x[i] = 8'(i*2 - 15); dyn_wgt[i] = 8'sd3; end
        run_inference(16, dyn_x, dyn_wgt, "AMPC-16 Full W=16");

        // ----------------------------------------------------------------------
        // SECTION 4: MANDATORY PROMPT MULTI-CYCLE WORKLOADS (>16)
        // ----------------------------------------------------------------------
        $display("\n--- [4] MANDATORY MULTI-CYCLE WORKLOAD TESTS (>16) ---");
        // W=17 (16 + 1)
        dyn_x   = new[17]; dyn_wgt = new[17];
        for (int i = 0; i < 17; i++) begin dyn_x[i] = 8'sd10; dyn_wgt[i] = 8'sd2; end
        run_inference(17, dyn_x, dyn_wgt, "Multi-Cycle W=17 (16+1 -> 17*20 = 340)");

        // W=18 (16 + 2)
        dyn_x   = new[18]; dyn_wgt = new[18];
        for (int i = 0; i < 18; i++) begin dyn_x[i] = 8'(i - 8); dyn_wgt[i] = 8'sd4; end
        run_inference(18, dyn_x, dyn_wgt, "Multi-Cycle W=18 (16+2)");

        // W=25 (16 + 9)
        dyn_x   = new[25]; dyn_wgt = new[25];
        for (int i = 0; i < 25; i++) begin dyn_x[i] = 8'(i * 2); dyn_wgt[i] = 8'sd2; end
        run_inference(25, dyn_x, dyn_wgt, "Multi-Cycle W=25 (16+9)");

        // W=32 (16 + 16)
        dyn_x   = new[32]; dyn_wgt = new[32];
        for (int i = 0; i < 32; i++) begin dyn_x[i] = 8'(i - 16); dyn_wgt[i] = 8'sd3; end
        run_inference(32, dyn_x, dyn_wgt, "Multi-Cycle W=32 (16+16)");

        // W=33 (16 + 16 + 1)
        dyn_x   = new[33]; dyn_wgt = new[33];
        for (int i = 0; i < 33; i++) begin dyn_x[i] = 8'sd5; dyn_wgt[i] = 8'sd5; end // 33 * 25 = 825
        run_inference(33, dyn_x, dyn_wgt, "Multi-Cycle W=33 (16+16+1 -> 33*25 = 825)");

        // W=48 (16*3)
        dyn_x   = new[48]; dyn_wgt = new[48];
        for (int i = 0; i < 48; i++) begin dyn_x[i] = 8'(i % 10); dyn_wgt[i] = 8'sd4; end
        run_inference(48, dyn_x, dyn_wgt, "Multi-Cycle W=48 (16*3)");

        // W=64 (16*4)
        dyn_x   = new[64]; dyn_wgt = new[64];
        for (int i = 0; i < 64; i++) begin dyn_x[i] = 8'(i % 8 - 4); dyn_wgt[i] = 8'sd5; end
        run_inference(64, dyn_x, dyn_wgt, "Multi-Cycle W=64 (16*4)");

        // W=100 (16*6 + 4)
        dyn_x   = new[100]; dyn_wgt = new[100];
        for (int i = 0; i < 100; i++) begin dyn_x[i] = 8'sd3; dyn_wgt[i] = 8'sd7; end // 100 * 21 = 2100
        run_inference(100, dyn_x, dyn_wgt, "Multi-Cycle W=100 (16*6+4 -> 100*21 = 2100)");

        // ----------------------------------------------------------------------
        // SECTION 5: SIGNED EXTREMES & BOUNDARY CASES
        // ----------------------------------------------------------------------
        $display("\n--- [5] SIGNED EXTREMES & BOUNDARIES ---");
        // INT8_MAX * INT8_MAX (127 * 127 = 16129)
        dyn_x = new[4]; dyn_wgt = new[4];
        for (int i = 0; i < 4; i++) begin dyn_x[i] = 8'sh7F; dyn_wgt[i] = 8'sh7F; end
        run_inference(4, dyn_x, dyn_wgt, "Extreme Max (+127 * +127 across 4 lanes)");

        // INT8_MIN * INT8_MIN (-128 * -128 = 16384)
        dyn_x = new[4]; dyn_wgt = new[4];
        for (int i = 0; i < 4; i++) begin dyn_x[i] = -8'sd128; dyn_wgt[i] = -8'sd128; end
        run_inference(4, dyn_x, dyn_wgt, "Extreme Min (-128 * -128 across 4 lanes)");

        // Deep Negative Sum Clamped by ReLU to 0
        dyn_x = new[16]; dyn_wgt = new[16];
        for (int i = 0; i < 16; i++) begin dyn_x[i] = 8'sd100; dyn_wgt[i] = -8'sd100; end // -160,000
        run_inference(16, dyn_x, dyn_wgt, "Negative Sum Clamped by ReLU to 0 (-160k -> 0)");

        // ----------------------------------------------------------------------
        // SECTION 6: 50 RANDOMIZED MULTI-CYCLE INFERENCE RUNS
        // ----------------------------------------------------------------------
        $display("\n--- [6] 50 RANDOMIZED MULTI-CYCLE INFERENCE RUNS ---");
        for (int r = 0; r < 50; r++) begin
            int rand_w;
            string test_name;

            rand_w  = $urandom_range(1, 100);
            dyn_x   = new[rand_w];
            dyn_wgt = new[rand_w];

            for (int i = 0; i < rand_w; i++) begin
                dyn_x[i]   = $random();
                dyn_wgt[i] = $random();
            end

            $sformat(test_name, "Random Workload #%02d (W=%3d)", r+1, rand_w);
            run_inference(rand_w, dyn_x, dyn_wgt, test_name);
        end

        // ----------------------------------------------------------------------
        // SECTION 7: ON-CHIP BUFFER READ/WRITE INTEGRATION
        // ----------------------------------------------------------------------
        $display("\n--- [7] ON-CHIP BUFFER INTEGRATION TESTS ---");
        test_num++;
        // Write pattern to input_buffer and weight_buffer
        @(negedge clk);
        ibuf_wr_en   = 1;
        ibuf_wr_addr = 6'd10;
        ibuf_wr_data = 8'sd42;
        wbuf_wr_en   = 1;
        wbuf_wr_addr = 6'd10;
        wbuf_wr_data = -8'sd88;
        @(posedge clk);
        #1;
        @(negedge clk);
        ibuf_wr_en   = 0;
        wbuf_wr_en   = 0;
        ibuf_rd_addr = 6'd10;
        wbuf_rd_addr = 6'd10;
        @(posedge clk);
        #1;
        if (ibuf_rd_data === 8'sd42 && wbuf_rd_data === -8'sd88) begin
            $display("[PASS] Test %03d: On-Chip Buffer Read/Write Integration  | ibuf[10]=%0d, wbuf[10]=%0d", test_num, ibuf_rd_data, wbuf_rd_data);
            pass_count++;
        end else begin
            $display("[FAIL] Test %03d: Buffer Integration Failed! ibuf=%0d, wbuf=%0d", test_num, ibuf_rd_data, wbuf_rd_data);
            fail_count++;
        end

        // ----------------------------------------------------------------------
        // SECTION 8: BACK-TO-BACK CONSECUTIVE INFERENCES
        // ----------------------------------------------------------------------
        $display("\n--- [8] BACK-TO-BACK CONSECUTIVE INFERENCES ---");
        // Run W=6 immediately followed by W=19
        dyn_x   = new[6]; dyn_wgt = new[6];
        for (int i = 0; i < 6; i++) begin dyn_x[i] = 8'sd7; dyn_wgt[i] = 8'sd3; end
        run_inference(6, dyn_x, dyn_wgt, "Back-to-Back Workload #1 (W=6)");

        dyn_x   = new[19]; dyn_wgt = new[19];
        for (int i = 0; i < 19; i++) begin dyn_x[i] = 8'sd4; dyn_wgt[i] = -8'sd2; end
        run_inference(19, dyn_x, dyn_wgt, "Back-to-Back Workload #2 (W=19)");

        // ----------------------------------------------------------------------
        // FINAL RESULTS SUMMARY
        // ----------------------------------------------------------------------
        $display("\n==============================================================================");
        $display("               STAGE 11 TOP-LEVEL FINAL TEST REPORT                           ");
        $display("==============================================================================");
        $display(" Total Tests Executed : %0d", test_num);
        $display(" Total Tests Passed   : %0d", pass_count);
        $display(" Total Tests Failed   : %0d", fail_count);
        $display("==============================================================================");

        if (fail_count == 0) begin
            $display(" >>> TOP-LEVEL INTEGRATION STATUS: PASS <<<");
            $display(" All %0d test cases matched independent golden model with ZERO errors.", test_num);
        end else begin
            $display(" >>> TOP-LEVEL INTEGRATION STATUS: FAIL <<<");
            $display(" Test suite failed with %0d discrepancies!", fail_count);
        end
        $display("==============================================================================");

        $finish;
    end

    // --------------------------------------------------------------------------
    // Dynamic Runtime Protocol & Timing Assertions
    // --------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst_n) begin
            // 1. Mutually Exclusive Core Enables (At most one AMPC active at any time)
            if ($countones({dut.ctrl_ampc16_en, dut.ctrl_ampc8_en, dut.ctrl_ampc4_en, dut.ctrl_ampc2_en}) > 1) begin
                $error("[ASSERTION FAIL] Multiple AMPC cores enabled simultaneously!");
            end

            // 2. No AMPC Enable when controller is IDLE
            if (ready && !start) begin
                if ({dut.ctrl_ampc16_en, dut.ctrl_ampc8_en, dut.ctrl_ampc4_en, dut.ctrl_ampc2_en} != 4'b0000) begin
                    $error("[ASSERTION FAIL] AMPC core enabled while controller is in IDLE!");
                end
            end

            // 3. Output Valid and Done Co-Assertion
            if (output_valid !== done) begin
                $error("[ASSERTION FAIL] output_valid (%b) mismatch with done (%b)!", output_valid, done);
            end

            // 4. Busy must remain asserted during active processing
            if (dut.is_active_q && !busy) begin
                $error("[ASSERTION FAIL] busy dropped prematurely while top-level is active!");
            end
        end
    end

endmodule
