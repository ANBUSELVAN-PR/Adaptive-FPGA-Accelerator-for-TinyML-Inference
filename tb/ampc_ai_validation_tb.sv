// ==============================================================================
// Project: Adaptive MAC Processing Core (AMPC) for TinyML Inference Acceleration
// Target:  AMD/Xilinx Zynq-7010 (xc7z010clg400-1) | Vivado 2026.1
// File:    ampc_ai_validation_tb.sv
// Module:  ampc_ai_validation_tb
// Details: Stage 16 AI Model Validation Testbench for Production ampc_top
//          Comprehensive evaluation across THREE real TinyML models:
//            Model 1: MNIST TinyMLP (W=9, W=17, W=25, W=33, W=784)
//            Model 2: Fashion-MNIST CNN (W=9, W=17, W=25, W=33, W=72)
//            Model 3: CIFAR-10 CNN (W=9, W=17, W=25, W=27, W=33, W=144)
// ==============================================================================

`timescale 1ns / 1ps

module ampc_ai_validation_tb;

    localparam int DATA_WIDTH     = 8;
    localparam int ACC_WIDTH      = 32;
    localparam int MAX_LANES      = 16;
    localparam int BUFFER_DEPTH   = 64;
    localparam int WORKLOAD_WIDTH = 16;
    localparam int ADDR_WIDTH     = $clog2(BUFFER_DEPTH);

    // DUT Clock and Control
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

    // Tracking Accounting
    integer test_num   = 0;
    integer pass_count = 0;
    integer fail_count = 0;

    // File descriptor for output log
    integer log_file;

    // --------------------------------------------------------------------------
    // Instantiate FROZEN STAGE 14 PRODUCTION TOP-LEVEL (ampc_top)
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

    // 100 MHz Simulation Clock
    always #5 clk = ~clk;

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
    // Task: Stream Real Neural Network MAC Workload & Check Output
    // --------------------------------------------------------------------------
    task run_ai_workload(
        input string                      model_name,
        input string                      layer_name,
        input int                         w_size,
        input logic signed [DATA_WIDTH-1:0] test_x [],
        input logic signed [DATA_WIDTH-1:0] test_wgt [],
        input longint                     golden_dot,
        input longint                     golden_relu,
        input string                      desc
    );
        int remaining_items;
        int stream_idx;
        int chunk_size;
        int chunk_num;
        int timeout;
        longint diff_dot;
        longint diff_relu;
        begin
            test_num++;

            while (!ready) @(posedge clk);

            // Assert start on falling edge
            @(negedge clk);
            start         = 1'b1;
            workload_size = 16'(w_size);

            remaining_items = w_size;
            stream_idx      = 0;
            chunk_num       = 0;

            // First chunk
            if (w_size > 0) begin
                chunk_size = (remaining_items > 16) ? 16 : remaining_items;
                for (int k = 0; k < MAX_LANES; k++) begin
                    if (k < chunk_size) begin
                        data_in[k] = test_x[stream_idx + k];
                        weight[k]  = test_wgt[stream_idx + k];
                    end else begin
                        // Inactive lanes driven with noise to prove strict lane isolation
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

            // Subsequent streaming chunks
            while (remaining_items > 0) begin
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

            // Await output valid & done
            timeout = 0;
            while (!output_valid && timeout < 2000) begin
                @(posedge clk);
                #1;
                timeout++;
            end

            diff_dot  = longint'(accumulated_out) - golden_dot;
            diff_relu = longint'(output_data) - golden_relu;

            if ($isunknown(accumulated_out) || $isunknown(output_data) || $isunknown(output_valid) || $isunknown(done)) begin
                $display("[FAIL] Test %02d: %-18s | %-6s | W=%-4d | Output has X/Z (Dot=%b, ReLU=%b)", 
                         test_num, model_name, layer_name, w_size, accumulated_out, output_data);
                $fdisplay(log_file, "TEST=%02d | MODEL=%s | LAYER=%s | W=%d | FAIL | X/Z | Dot=%d | Exp=%d | Diff=%d", 
                          test_num, model_name, layer_name, w_size, accumulated_out, golden_dot, diff_dot);
                fail_count++;
            end else if ((accumulated_out === 32'(golden_dot)) && 
                         (output_data === 32'(golden_relu)) &&
                         (done === 1'b1) && (output_valid === 1'b1)) begin
                $display("[PASS] Test %02d: %-18s | %-6s | W=%-4d | Chunks=%2d | PyDot=%8d | RTLDot=%8d | Diff=%1d | EXACT MATCH", 
                         test_num, model_name, layer_name, w_size, chunk_num, golden_dot, accumulated_out, diff_dot);
                $fdisplay(log_file, "TEST=%02d | MODEL=%s | LAYER=%s | W=%d | PASS | Match | PyDot=%d | RTLDot=%d | Diff=%d | Chunks=%d", 
                          test_num, model_name, layer_name, w_size, golden_dot, accumulated_out, diff_dot, chunk_num);
                pass_count++;
            end else begin
                $display("[FAIL] Test %02d: %-18s | %-6s | W=%-4d | PyDot=%8d | RTLDot=%8d | Diff=%8d", 
                         test_num, model_name, layer_name, w_size, golden_dot, accumulated_out, diff_dot);
                $fdisplay(log_file, "TEST=%02d | MODEL=%s | LAYER=%s | W=%d | FAIL | Mismatch | PyDot=%d | RTLDot=%d | Diff=%d", 
                          test_num, model_name, layer_name, w_size, golden_dot, accumulated_out, diff_dot);
                fail_count++;
            end

            @(posedge clk);
        end
    endtask

    // --------------------------------------------------------------------------
    // Helper task to read vectors from text files
    // --------------------------------------------------------------------------
    task load_vectors(
        input string filename_act,
        input string filename_wgt,
        input int count,
        output logic signed [DATA_WIDTH-1:0] act_arr [],
        output logic signed [DATA_WIDTH-1:0] wgt_arr []
    );
        int fd_a, fd_w, val, ret;
        begin
            act_arr = new[count];
            wgt_arr = new[count];

            fd_a = $fopen(filename_act, "r");
            if (fd_a == 0) $fatal(1, "Failed to open activation file: %s", filename_act);
            for (int i = 0; i < count; i++) begin
                ret = $fscanf(fd_a, "%d\n", val);
                act_arr[i] = 8'(val);
            end
            $fclose(fd_a);

            fd_w = $fopen(filename_wgt, "r");
            if (fd_w == 0) $fatal(1, "Failed to open weight file: %s", filename_wgt);
            for (int i = 0; i < count; i++) begin
                ret = $fscanf(fd_w, "%d\n", val);
                wgt_arr[i] = 8'(val);
            end
            $fclose(fd_w);
        end
    endtask

    initial begin
        logic signed [DATA_WIDTH-1:0] vec_x   [];
        logic signed [DATA_WIDTH-1:0] vec_wgt [];

        log_file = $fopen("ai_validation/results/three_model_rtl_log.txt", "w");

        $display("====================================================================================================");
        $display("   STAGE 16: THREE-MODEL AI HARDWARE VALIDATION TESTBENCH (ampc_ai_validation_tb)                   ");
        $display("   Production Target: AMD Zynq-7010 | AMPC Stage 14 Frozen RTL | Vivado 2026.1                      ");
        $display("====================================================================================================");

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

        reset_dut();

        // ----------------------------------------------------------------------
        // MODEL 1: MNIST TinyMLP (784 -> 32 -> ReLU -> 10)
        // ----------------------------------------------------------------------
        $display("\n--- [MODEL 1] MNIST TinyMLP WORKLOADS ---");
        // M1 - W=9
        load_vectors("ai_validation/vectors/m1_mnist_w9_act.txt", "ai_validation/vectors/m1_mnist_w9_wgt.txt", 9, vec_x, vec_wgt);
        run_ai_workload("MNIST TinyMLP", "FC1", 9, vec_x, vec_wgt, 1121, 1121, "AMPC-16 (9 active lanes)");

        // M1 - W=17
        load_vectors("ai_validation/vectors/m1_mnist_w17_act.txt", "ai_validation/vectors/m1_mnist_w17_wgt.txt", 17, vec_x, vec_wgt);
        run_ai_workload("MNIST TinyMLP", "FC1", 17, vec_x, vec_wgt, 2223, 2223, "AMPC-16 + AMPC-2 (16+1)");

        // M1 - W=25
        load_vectors("ai_validation/vectors/m1_mnist_w25_act.txt", "ai_validation/vectors/m1_mnist_w25_wgt.txt", 25, vec_x, vec_wgt);
        run_ai_workload("MNIST TinyMLP", "FC1", 25, vec_x, vec_wgt, 4465, 4465, "AMPC-16 + AMPC-16 (16+9)");

        // M1 - W=33
        load_vectors("ai_validation/vectors/m1_mnist_w33_act.txt", "ai_validation/vectors/m1_mnist_w33_wgt.txt", 33, vec_x, vec_wgt);
        run_ai_workload("MNIST TinyMLP", "FC1", 33, vec_x, vec_wgt, 6802, 6802, "2x AMPC-16 + AMPC-2 (16+16+1)");

        // M1 - W=784 (Complete FC1 Neuron 0)
        load_vectors("ai_validation/vectors/m1_mnist_w784_act.txt", "ai_validation/vectors/m1_mnist_w784_wgt.txt", 784, vec_x, vec_wgt);
        run_ai_workload("MNIST TinyMLP", "FC1", 784, vec_x, vec_wgt, 40691, 40691, "Complete FC1 Neuron (49x16 Chunks)");

        // ----------------------------------------------------------------------
        // MODEL 2: Fashion-MNIST TinyML CNN
        // ----------------------------------------------------------------------
        $display("\n--- [MODEL 2] Fashion-MNIST TinyML CNN WORKLOADS ---");
        // M2 - W=9 (Conv1 3x3 filter)
        load_vectors("ai_validation/vectors/m2_fashion_w9_act.txt", "ai_validation/vectors/m2_fashion_w9_wgt.txt", 9, vec_x, vec_wgt);
        run_ai_workload("Fashion-MNIST CNN", "Conv1", 9, vec_x, vec_wgt, 24812, 24812, "Conv1 3x3 Filter (1 channel)");

        // M2 - W=17 (Conv2 Channel Slice)
        load_vectors("ai_validation/vectors/m2_fashion_w17_act.txt", "ai_validation/vectors/m2_fashion_w17_wgt.txt", 17, vec_x, vec_wgt);
        run_ai_workload("Fashion-MNIST CNN", "Conv2", 17, vec_x, vec_wgt, -29587, 0, "Conv2 Channel Slice (17 ops)");

        // M2 - W=25 (Conv2 Channel Slice)
        load_vectors("ai_validation/vectors/m2_fashion_w25_act.txt", "ai_validation/vectors/m2_fashion_w25_wgt.txt", 25, vec_x, vec_wgt);
        run_ai_workload("Fashion-MNIST CNN", "Conv2", 25, vec_x, vec_wgt, -27323, 0, "Conv2 Channel Slice (25 ops)");

        // M2 - W=33 (Conv2 Channel Slice)
        load_vectors("ai_validation/vectors/m2_fashion_w33_act.txt", "ai_validation/vectors/m2_fashion_w33_wgt.txt", 33, vec_x, vec_wgt);
        run_ai_workload("Fashion-MNIST CNN", "Conv2", 33, vec_x, vec_wgt, -33189, 0, "Conv2 Channel Slice (33 ops)");

        // M2 - W=72 (Conv2 Complete 8x3x3 Output Feature)
        load_vectors("ai_validation/vectors/m2_fashion_w72_act.txt", "ai_validation/vectors/m2_fashion_w72_wgt.txt", 72, vec_x, vec_wgt);
        run_ai_workload("Fashion-MNIST CNN", "Conv2", 72, vec_x, vec_wgt, -44913, 0, "Complete Conv2D 8x3x3 Output Feature");

        // ----------------------------------------------------------------------
        // MODEL 3: CIFAR-10 TinyML CNN
        // ----------------------------------------------------------------------
        $display("\n--- [MODEL 3] CIFAR-10 TinyML CNN WORKLOADS ---");
        // M3 - W=9 (Conv1 Single-Channel 3x3)
        load_vectors("ai_validation/vectors/m3_cifar_w9_act.txt", "ai_validation/vectors/m3_cifar_w9_wgt.txt", 9, vec_x, vec_wgt);
        run_ai_workload("CIFAR-10 CNN", "Conv1", 9, vec_x, vec_wgt, -20572, 0, "Conv1 Single-Channel 3x3 Slice");

        // M3 - W=17 (Conv2 Channel Slice)
        load_vectors("ai_validation/vectors/m3_cifar_w17_act.txt", "ai_validation/vectors/m3_cifar_w17_wgt.txt", 17, vec_x, vec_wgt);
        run_ai_workload("CIFAR-10 CNN", "Conv2", 17, vec_x, vec_wgt, 13037, 13037, "Conv2 Channel Slice (17 ops)");

        // M3 - W=25 (Conv2 Channel Slice)
        load_vectors("ai_validation/vectors/m3_cifar_w25_act.txt", "ai_validation/vectors/m3_cifar_w25_wgt.txt", 25, vec_x, vec_wgt);
        run_ai_workload("CIFAR-10 CNN", "Conv2", 25, vec_x, vec_wgt, 11916, 11916, "Conv2 Channel Slice (25 ops)");

        // M3 - W=27 (Conv1 Complete RGB 3x3x3 Output Feature)
        load_vectors("ai_validation/vectors/m3_cifar_w27_act.txt", "ai_validation/vectors/m3_cifar_w27_wgt.txt", 27, vec_x, vec_wgt);
        run_ai_workload("CIFAR-10 CNN", "Conv1", 27, vec_x, vec_wgt, -24979, 0, "Complete Conv1 RGB 3x3x3 Feature");

        // M3 - W=33 (Conv2 Channel Slice)
        load_vectors("ai_validation/vectors/m3_cifar_w33_act.txt", "ai_validation/vectors/m3_cifar_w33_wgt.txt", 33, vec_x, vec_wgt);
        run_ai_workload("CIFAR-10 CNN", "Conv2", 33, vec_x, vec_wgt, -6345, 0, "Conv2 Channel Slice (33 ops)");

        // M3 - W=144 (Conv2 Complete 16x3x3 Output Feature)
        load_vectors("ai_validation/vectors/m3_cifar_w144_act.txt", "ai_validation/vectors/m3_cifar_w144_wgt.txt", 144, vec_x, vec_wgt);
        run_ai_workload("CIFAR-10 CNN", "Conv2", 144, vec_x, vec_wgt, -44460, 0, "Complete Conv2 16x3x3 Feature (9x16 Chunks)");

        $display("====================================================================================================");
        $display("   THREE-MODEL AI HARDWARE VALIDATION SUMMARY: Passed=%0d, Failed=%0d", pass_count, fail_count);
        $display("====================================================================================================");

        if (fail_count == 0) begin
            $display(">>> ALL 16 REAL-MODEL WORKLOADS MATCHED PYTHON GOLDEN EXACTLY (PASS) <<<");
            $fdisplay(log_file, "OVERALL STATUS: PASS (16/16 Workloads Matched Exactly)");
        end else begin
            $display(">>> AI HARDWARE VALIDATION FAILED <<<");
            $fdisplay(log_file, "OVERALL STATUS: FAIL");
        end

        $fclose(log_file);
        $finish;
    end

endmodule
