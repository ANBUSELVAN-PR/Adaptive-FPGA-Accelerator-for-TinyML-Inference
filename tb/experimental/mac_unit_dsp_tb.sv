// ==============================================================================
// Project: Adaptive MAC Processing Core (AMPC) for TinyML Inference Acceleration
// Target:  AMD/Xilinx Zynq-7010 (xc7z010clg400-1) | Vivado 2026.1
// File:    mac_unit_dsp_tb.sv
// Module:  mac_unit_dsp_tb
// Details: Stage 15 Experimental - Self-Checking Testbench for mac_unit_dsp
// ==============================================================================

`timescale 1ns / 1ps

module mac_unit_dsp_tb;

    localparam int DATA_WIDTH   = 8;
    localparam int WEIGHT_WIDTH = 8;
    localparam int ACC_WIDTH    = 32;

    logic signed [DATA_WIDTH-1:0]   tb_data_in;
    logic signed [WEIGHT_WIDTH-1:0] tb_weight;
    logic signed [ACC_WIDTH-1:0]    tb_acc_in;
    logic signed [ACC_WIDTH-1:0]    tb_acc_out_dsp;
    logic signed [ACC_WIDTH-1:0]    tb_acc_out_lut;

    integer test_num   = 0;
    integer pass_count = 0;
    integer fail_count = 0;

    // Instantiate Experimental DSP DUT
    mac_unit_dsp #(
        .DATA_WIDTH   (DATA_WIDTH),
        .WEIGHT_WIDTH (WEIGHT_WIDTH),
        .ACC_WIDTH    (ACC_WIDTH)
    ) dut_dsp (
        .data_in (tb_data_in),
        .weight  (tb_weight),
        .acc_in  (tb_acc_in),
        .acc_out (tb_acc_out_dsp)
    );

    // Instantiate Golden Baseline mac_unit (for exact co-simulation equivalence)
    mac_unit #(
        .DATA_WIDTH   (DATA_WIDTH),
        .WEIGHT_WIDTH (WEIGHT_WIDTH),
        .ACC_WIDTH    (ACC_WIDTH)
    ) dut_golden (
        .data_in (tb_data_in),
        .weight  (tb_weight),
        .acc_in  (tb_acc_in),
        .acc_out (tb_acc_out_lut)
    );

    task check_mac_dsp(
        input logic signed [DATA_WIDTH-1:0]   d,
        input logic signed [WEIGHT_WIDTH-1:0] w,
        input logic signed [ACC_WIDTH-1:0]    a,
        input string                          desc
    );
        int product_calc;
        int expected_out;
        begin
            test_num++;
            tb_data_in = d;
            tb_weight  = w;
            tb_acc_in  = a;

            #10;

            product_calc = int'(d) * int'(w);
            expected_out = int'(a) + product_calc;

            if ($isunknown(tb_acc_out_dsp)) begin
                $display("[FAIL] Test %02d: %-32s | Data=%4d, Weight=%4d, AccIn=%8d | Error: DSP Output contains X/Z (%b)",
                         test_num, desc, d, w, a, tb_acc_out_dsp);
                fail_count++;
            end else if ((tb_acc_out_dsp === expected_out) && (tb_acc_out_dsp === tb_acc_out_lut)) begin
                $display("[PASS] Test %02d: %-32s | D=%4d, W=%4d, Acc=%8d | Result=%8d (Matches LUT & Golden)", 
                         test_num, desc, d, w, a, tb_acc_out_dsp);
                pass_count++;
            end else begin
                $display("[FAIL] Test %02d: %-32s | Exp=%8d, ActDSP=%8d, ActLUT=%8d", 
                         test_num, desc, expected_out, tb_acc_out_dsp, tb_acc_out_lut);
                fail_count++;
            end
        end
    endtask

    initial begin
        $display("==============================================================================");
        $display("   STAGE 15: EXPERIMENTAL DSP MAC UNIT (mac_unit_dsp) VERIFICATION           ");
        $display("==============================================================================");

        // Section 1: Positive Values
        check_mac_dsp(8'sd5, 8'sd10, 32'sd100, "Small positive operands");
        check_mac_dsp(8'sd12, 8'sd5, 32'sd0, "Zero accumulator input");
        check_mac_dsp(8'sd64, 8'sd64, 32'sd1000, "Medium positive square");

        // Section 2: Negative Values
        check_mac_dsp(-8'sd5, 8'sd10, 32'sd100, "Negative data, pos weight");
        check_mac_dsp(8'sd10, -8'sd5, 32'sd100, "Pos data, neg weight");
        check_mac_dsp(-8'sd10, -8'sd10, 32'sd0, "Negative x negative = positive");

        // Section 3: Zero Operands
        check_mac_dsp(8'sd0, 8'sd127, 32'sd500, "Zero data operand");
        check_mac_dsp(8'sd127, 8'sd0, 32'sd500, "Zero weight operand");
        check_mac_dsp(8'sd0, 8'sd0, 32'sd1234, "Both zero operands");
        check_mac_dsp(8'sd0, 8'sd0, 32'sd0, "All inputs zero");

        // Section 4: Boundary & Extreme Values
        check_mac_dsp(8'sd127, 8'sd127, 32'sd0, "Max positive square (+127*+127)");
        check_mac_dsp(-8'sd128, -8'sd128, 32'sd0, "Min negative square (-128*-128)");
        check_mac_dsp(-8'sd128, 8'sd127, 32'sd0, "Min neg x Max pos (-128*+127)");
        check_mac_dsp(8'sd127, -8'sd128, 32'sd0, "Max pos x Min neg (+127*-128)");
        check_mac_dsp(8'sd1, 8'sd1, 32'sd0, "Unit positive (+1*+1)");
        check_mac_dsp(-8'sd1, 8'sd1, 32'sd0, "Unit negative (-1*+1)");

        // Section 5: Large INT32 Accumulator Values
        check_mac_dsp(8'sd10, 8'sd10, 32'sd2000000000, "Large positive accumulator");
        check_mac_dsp(8'sd10, 8'sd10, -32'sd2000000000, "Large negative accumulator");
        check_mac_dsp(8'sd127, 8'sd127, 32'sd2147467296, "Near INT32 max threshold");
        check_mac_dsp(-8'sd128, 8'sd127, -32'sd2147467296, "Near INT32 min threshold");

        // Section 6: Randomized Vectors
        for (int i = 0; i < 30; i++) begin
            logic signed [DATA_WIDTH-1:0]   rand_d;
            logic signed [WEIGHT_WIDTH-1:0] rand_w;
            logic signed [ACC_WIDTH-1:0]    rand_a;
            rand_d = $urandom_range(0, 255);
            rand_w = $urandom_range(0, 255);
            rand_a = ($urandom_range(0, 65535) << 16) | $urandom_range(0, 65535);
            check_mac_dsp(rand_d, rand_w, rand_a, $sformatf("Random Vector #%02d", i + 1));
        end

        $display("==============================================================================");
        $display("STAGE 15 EXPERIMENTAL MAC TEST SUMMARY: Passed=%0d, Failed=%0d", pass_count, fail_count);
        $display("==============================================================================");

        if (fail_count == 0) begin
            $display(">>> EXPERIMENTAL DSP MAC VERIFICATION: PASS <<<");
        end else begin
            $display(">>> EXPERIMENTAL DSP MAC VERIFICATION: FAIL <<<");
        end

        $finish;
    end

endmodule
