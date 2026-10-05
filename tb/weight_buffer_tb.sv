// ==============================================================================
// Project: Adaptive MAC Processing Core (AMPC) for TinyML Inference Acceleration
// Target:  AMD/Xilinx Zynq-7010 (xc7z010clg400-1) | Vivado 2026.1
// File:    weight_buffer_tb.sv
// Module:  weight_buffer_tb
// Author:  VLSI/FPGA Project Team
// Details: Stage 8 - Comprehensive Self-Checking Testbench for weight_buffer
// ==============================================================================

`timescale 1ns / 1ps

module weight_buffer_tb;

    localparam int DATA_WIDTH = 8;
    localparam int DEPTH      = 64;
    localparam int ADDR_WIDTH = $clog2(DEPTH);

    // Clock and Control
    logic                         clk;
    logic                         rst_n;
    logic                         wr_en;
    logic [ADDR_WIDTH-1:0]        wr_addr;
    logic signed [DATA_WIDTH-1:0] wr_data;
    logic [ADDR_WIDTH-1:0]        rd_addr;

    // DUT Output
    logic signed [DATA_WIDTH-1:0] rd_data;

    // Test Tracking Accounting
    integer test_num   = 0;
    integer pass_count = 0;
    integer fail_count = 0;

    // Independent Reference Model
    logic signed [DATA_WIDTH-1:0] ref_mem [0:DEPTH-1];

    // --------------------------------------------------------------------------
    // Instantiate Device Under Test (DUT)
    // --------------------------------------------------------------------------
    weight_buffer #(
        .DATA_WIDTH (DATA_WIDTH),
        .DEPTH      (DEPTH),
        .ADDR_WIDTH (ADDR_WIDTH)
    ) dut (
        .clk     (clk),
        .rst_n   (rst_n),
        .wr_en   (wr_en),
        .wr_addr (wr_addr),
        .wr_data (wr_data),
        .rd_addr (rd_addr),
        .rd_data (rd_data)
    );

    // 100 MHz Simulation Clock (10ns period)
    always #5 clk = ~clk;

    // --------------------------------------------------------------------------
    // Task: Write Word to Buffer and Update Reference Memory
    // --------------------------------------------------------------------------
    task write_word(
        input logic [ADDR_WIDTH-1:0]        addr,
        input logic signed [DATA_WIDTH-1:0] data
    );
        begin
            @(negedge clk);
            wr_en   = 1'b1;
            wr_addr = addr;
            wr_data = data;
            @(posedge clk);
            #1;
            ref_mem[addr] = data;
            @(negedge clk);
            wr_en   = 1'b0;
        end
    endtask

    // --------------------------------------------------------------------------
    // Task: Read Word from Buffer and Verify Against Reference Model (1-cycle latency)
    // --------------------------------------------------------------------------
    task read_and_check(
        input logic [ADDR_WIDTH-1:0] addr,
        input string                 desc
    );
        logic signed [DATA_WIDTH-1:0] expected;
        begin
            test_num++;
            expected = ref_mem[addr];

            @(negedge clk);
            rd_addr = addr;
            @(posedge clk);
            #1; // 1-cycle synchronous read latency inspect window

            if ($isunknown(rd_data)) begin
                $display("[FAIL] Test %02d: %-36s | Output contains X/Z! Addr=%0d, Data=%b",
                         test_num, desc, addr, rd_data);
                fail_count++;
            end else if (rd_data === expected) begin
                $display("[PASS] Test %02d: %-36s | Addr=%02d -> Data=%4d",
                         test_num, desc, addr, rd_data);
                pass_count++;
            end else begin
                $display("[FAIL] Test %02d: %-36s | Addr=%02d: Expected=%4d, Actual=%4d",
                         test_num, desc, addr, expected, rd_data);
                fail_count++;
            end
        end
    endtask

    // --------------------------------------------------------------------------
    // Task: Simultaneous Write and Read with Collision Check
    // --------------------------------------------------------------------------
    task simultaneous_rw(
        input logic [ADDR_WIDTH-1:0]        w_addr,
        input logic signed [DATA_WIDTH-1:0] w_data,
        input logic [ADDR_WIDTH-1:0]        r_addr,
        input string                        desc
    );
        logic signed [DATA_WIDTH-1:0] expected;
        begin
            test_num++;
            expected = (w_addr == r_addr) ? w_data : ref_mem[r_addr];

            @(negedge clk);
            wr_en   = 1'b1;
            wr_addr = w_addr;
            wr_data = w_data;
            rd_addr = r_addr;
            @(posedge clk);
            #1;
            ref_mem[w_addr] = w_data;

            if ($isunknown(rd_data)) begin
                $display("[FAIL] Test %02d: %-36s | Output contains X/Z! RdAddr=%0d, Data=%b",
                         test_num, desc, r_addr, rd_data);
                fail_count++;
            end else if (rd_data === expected) begin
                $display("[PASS] Test %02d: %-36s | WAddr=%02d (Data=%4d), RAddr=%02d -> Out=%4d",
                         test_num, desc, w_addr, w_data, r_addr, rd_data);
                pass_count++;
            end else begin
                $display("[FAIL] Test %02d: %-36s | Expected=%4d, Actual=%4d",
                         test_num, desc, expected, rd_data);
                fail_count++;
            end

            @(negedge clk);
            wr_en = 1'b0;
        end
    endtask

    // --------------------------------------------------------------------------
    // Main Stimulus Process
    // --------------------------------------------------------------------------
    initial begin
        $display("==============================================================================");
        $display("      AMPC PROJECT: STAGE 8 WEIGHT BUFFER (weight_buffer) VERIFICATION        ");
        $display("==============================================================================");

        // Initialize signals
        clk     = 0;
        rst_n   = 0;
        wr_en   = 0;
        wr_addr = '0;
        wr_data = '0;
        rd_addr = '0;
        for (int i = 0; i < DEPTH; i++) ref_mem[i] = '0;

        // ----------------------------------------------------------------------
        // SECTION 1: RESET BEHAVIOR
        // ----------------------------------------------------------------------
        $display("\n--- [1] SYNCHRONOUS RESET VERIFICATION ---");
        repeat (2) @(posedge clk);
        #1;
        test_num++;
        if (rd_data === 8'sd0) begin
            $display("[PASS] Test %02d: Synchronous Reset Check           | rd_data = %0d", test_num, rd_data);
            pass_count++;
        end else begin
            $display("[FAIL] Test %02d: Reset Check Failed! rd_data = %b", test_num, rd_data);
            fail_count++;
        end

        // Release reset
        @(negedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        // ----------------------------------------------------------------------
        // SECTION 2: SIGNED BOUNDARIES & VALUE CHECKS
        // ----------------------------------------------------------------------
        $display("\n--- [2] SIGNED BOUNDARIES & VALUE CHECKS ---");
        // Positive value
        write_word(6'd0, 8'sd65);
        read_and_check(6'd0, "Positive Value (+65) at Addr 0");

        // Negative value
        write_word(6'd1, -8'sd65);
        read_and_check(6'd1, "Negative Value (-65) at Addr 1");

        // INT8_MAX (+127)
        write_word(6'd2, 8'sh7F);
        read_and_check(6'd2, "INT8_MAX (+127) at Addr 2");

        // INT8_MIN (-128)
        write_word(6'd3, -8'sd128);
        read_and_check(6'd3, "INT8_MIN (-128) at Addr 3");

        // Zero (0)
        write_word(6'd4, 8'sd0);
        read_and_check(6'd4, "Zero (0) at Addr 4");

        // ----------------------------------------------------------------------
        // SECTION 3: OVERWRITING AN EXISTING ADDRESS
        // ----------------------------------------------------------------------
        $display("\n--- [3] OVERWRITE EXISTING ADDRESS ---");
        write_word(6'd0, 8'sd111);
        read_and_check(6'd0, "Overwrite Addr 0 with +111");

        write_word(6'd0, -8'sd120);
        read_and_check(6'd0, "Overwrite Addr 0 with -120");

        // ----------------------------------------------------------------------
        // SECTION 4: SEQUENTIAL BURST WRITE & READ ACROSS ENTIRE BUFFER
        // ----------------------------------------------------------------------
        $display("\n--- [4] SEQUENTIAL WRITE & READ ACROSS ENTIRE BUFFER (64 WORDS) ---");
        // Write pattern across all 64 addresses
        for (int i = 0; i < DEPTH; i++) begin
            logic signed [7:0] val;
            val = -8'sd128 + 8'(i * 3); // Spans negative and positive ranges
            write_word(6'(i), val);
        end

        // Read and verify all 64 addresses
        for (int i = 0; i < DEPTH; i++) begin
            string desc;
            $sformat(desc, "Sequential Read Word %02d", i);
            read_and_check(6'(i), desc);
        end

        // ----------------------------------------------------------------------
        // SECTION 5: SIMULTANEOUS WRITE & READ (COLLISION / WRITE-FIRST & DIFFERENT ADDR)
        // ----------------------------------------------------------------------
        $display("\n--- [5] SIMULTANEOUS WRITE & READ TESTS ---");
        // Same address collision (write-first forwarding)
        simultaneous_rw(6'd20, 8'sd85, 6'd20, "Collision: Write & Read Same Addr 20 (Forwarding)");

        // Different addresses
        simultaneous_rw(6'd25, -8'sd95, 6'd20, "Simultaneous: Write Addr 25, Read Addr 20");
        read_and_check(6'd25, "Verify Addr 25 Committed Correctly");

        // ----------------------------------------------------------------------
        // SECTION 6: 60 RANDOMIZED WRITE / READ TRANSACTIONS
        // ----------------------------------------------------------------------
        $display("\n--- [6] 60 RANDOMIZED WRITE / READ TRANSACTIONS ---");
        for (int i = 0; i < 60; i++) begin
            logic [ADDR_WIDTH-1:0] rand_waddr;
            logic [ADDR_WIDTH-1:0] rand_raddr;
            logic signed [DATA_WIDTH-1:0] rand_data;
            logic do_write;
            string test_name;

            rand_waddr = $urandom_range(0, DEPTH-1);
            rand_raddr = $urandom_range(0, DEPTH-1);
            rand_data  = $random();
            do_write   = ($urandom_range(0, 10) > 3); // 70% writes, 30% reads

            if (do_write) begin
                $sformat(test_name, "Random Op #%02d (Write Addr=%02d, Data=%4d)", i+1, rand_waddr, rand_data);
                write_word(rand_waddr, rand_data);
                // Immediately read back to verify
                read_and_check(rand_waddr, test_name);
            end else begin
                $sformat(test_name, "Random Op #%02d (Read Addr=%02d)", i+1, rand_raddr);
                read_and_check(rand_raddr, test_name);
            end
        end

        // ----------------------------------------------------------------------
        // FINAL RESULTS SUMMARY
        // ----------------------------------------------------------------------
        $display("\n==============================================================================");
        $display("                STAGE 8 WEIGHT BUFFER FINAL TEST REPORT                       ");
        $display("==============================================================================");
        $display(" Total Tests Executed : %0d", test_num);
        $display(" Total Tests Passed   : %0d", pass_count);
        $display(" Total Tests Failed   : %0d", fail_count);
        $display("==============================================================================");

        if (fail_count == 0) begin
            $display(" >>> WEIGHT BUFFER STATUS: PASS <<<");
            $display(" All %0d test cases matched independent reference model with ZERO errors.", test_num);
        end else begin
            $display(" >>> WEIGHT BUFFER STATUS: FAIL <<<");
            $display(" Test suite failed with %0d discrepancies!", fail_count);
        end
        $display("==============================================================================");

        $finish;
    end

endmodule
