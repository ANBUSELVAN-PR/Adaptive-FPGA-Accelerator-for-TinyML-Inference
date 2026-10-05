// ==============================================================================
// Project: Adaptive MAC Processing Core (AMPC) for TinyML Inference Acceleration
// Target:  AMD/Xilinx Zynq-7010 (xc7z010clg400-1) | Vivado 2026.1
// File:    mac_unit_dsp.sv
// Module:  mac_unit_dsp
// Details: Stage 15 Experimental - DSP48E1 Inferred Signed INT8 x INT8 + INT32 MAC Unit
// ==============================================================================

`timescale 1ns / 1ps

module mac_unit_dsp #(
    parameter int DATA_WIDTH   = 8,   // Input activation bit-width (Signed INT8)
    parameter int WEIGHT_WIDTH = 8,   // Quantized weight bit-width (Signed INT8)
    parameter int ACC_WIDTH    = 32   // Accumulator bit-width (Signed INT32)
) (
    input  logic signed [DATA_WIDTH-1:0]   data_in,  // Signed input activation
    input  logic signed [WEIGHT_WIDTH-1:0] weight,   // Signed weight parameter
    input  logic signed [ACC_WIDTH-1:0]    acc_in,   // Signed accumulator input
    output logic signed [ACC_WIDTH-1:0]    acc_out   // Signed accumulator output
);

    // Intermediate signed product width: (8 + 8 = 16 bits for INT8)
    localparam int PROD_WIDTH = DATA_WIDTH + WEIGHT_WIDTH;

    // Explicit Vivado synthesis attribute requesting dedicated DSP block mapping
    (* use_dsp = "yes" *) logic signed [PROD_WIDTH-1:0] mult_result;

    // Step 1: Signed multiplication (INT8 x INT8 -> INT16)
    assign mult_result = data_in * weight;

    // Step 2: Sign-extension and accumulation (INT16 -> INT32)
    assign acc_out = acc_in + $signed({{ (ACC_WIDTH - PROD_WIDTH){mult_result[PROD_WIDTH-1]} }, mult_result});

endmodule
