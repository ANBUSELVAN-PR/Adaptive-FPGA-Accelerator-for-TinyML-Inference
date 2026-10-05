// ==============================================================================
// Project: Adaptive MAC Processing Core (AMPC) for TinyML Inference Acceleration
// Target:  AMD/Xilinx Zynq-7010 (xc7z010clg400-1) | Vivado 2026.1
// File:    relu.sv
// Module:  relu
// Author:  VLSI/FPGA Project Team
// Details: Stage 7 - Modular Signed INT32 Combinational ReLU Activation Unit
// ==============================================================================

`timescale 1ns / 1ps

module relu #(
    parameter int DATA_WIDTH = 32
) (
    input  logic signed [DATA_WIDTH-1:0] data_in,
    output logic signed [DATA_WIDTH-1:0] data_out
);

    // --------------------------------------------------------------------------
    // Combinational ReLU Transfer Function:
    //   ReLU(x) = x, when x > 0
    //   ReLU(x) = 0, when x <= 0
    //
    // Input is explicitly signed INT32. The comparison against zero is a signed
    // relational comparison. If data_in is negative, output is clamped to 0.
    // If non-negative, data_in passes through unchanged with zero added latency.
    // --------------------------------------------------------------------------
    always_comb begin
        if (data_in < 0) begin
            data_out = '0;
        end else begin
            data_out = data_in;
        end
    end

endmodule
