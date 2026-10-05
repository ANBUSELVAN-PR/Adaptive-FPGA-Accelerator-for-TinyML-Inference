// ==============================================================================
// Project: Adaptive MAC Processing Core (AMPC) for TinyML Inference Acceleration
// Target:  AMD/Xilinx Zynq-7010 (xc7z010clg400-1) | Vivado 2026.1
// File:    accumulator.sv
// Module:  accumulator
// Author:  VLSI/FPGA Project Team
// Details: Stage 6 - Common Spatial Reduction and Temporal Accumulator Block
// ==============================================================================

`timescale 1ns / 1ps

module accumulator #(
    parameter int ACC_WIDTH = 32,   // Accumulator bit-width (Signed INT32)
    parameter int LANES     = 16    // Maximum supported parallel input lanes
) (
    input  logic                         clk,             // System Clock
    input  logic                         rst_n,           // Synchronous Active-Low Reset
    input  logic                         en,              // Module Enable
    input  logic                         valid_in,        // Input Data Valid Strobe from active AMPC
    input  logic [LANES-1:0]             lane_mask,       // Active Lane Bitmask (1=Active, 0=Masked)

    // Parallel lane inputs from active AMPC core
    input  logic signed [ACC_WIDTH-1:0]  lane_data [0:LANES-1],

    // Scalar accumulated dot-product output
    output logic signed [ACC_WIDTH-1:0]  accumulated_out,
    output logic                         valid_out        // Strobe indicating completed accumulator update
);

    // Intermediate spatial reduction width: 32 + clog2(16) = 36 bits
    // Eliminates intermediate overflow during summation of 16 signed 32-bit lane values.
    localparam int REDUCTION_WIDTH = ACC_WIDTH + $clog2(LANES);
    logic signed [REDUCTION_WIDTH-1:0] spatial_sum;

    // --------------------------------------------------------------------------
    // 1. Spatial Reduction Layer
    // Sums only the lanes where lane_mask[i] == 1'b1.
    // Inactive lanes (lane_mask[i] == 1'b0) strictly contribute 0, guaranteeing
    // that residual or preserved data on masked lanes never corrupts the sum.
    // --------------------------------------------------------------------------
    always_comb begin
        spatial_sum = '0;
        for (int i = 0; i < LANES; i = i + 1) begin
            if (lane_mask[i]) begin
                // Explicit sign-extension of 32-bit signed lane to 36-bit intermediate
                spatial_sum = spatial_sum + $signed({{ (REDUCTION_WIDTH - ACC_WIDTH){lane_data[i][ACC_WIDTH-1]} }, lane_data[i]});
            end
        end
    end

    // --------------------------------------------------------------------------
    // 2. Temporal Accumulation Layer
    // Accumulates spatial reduction sums across valid execution cycles.
    // Update Condition: (en && valid_in). If either is 0, accumulator holds state.
    // Overflow note: Standard two's-complement arithmetic applies if the 32-bit
    // running sum exceeds the signed INT32 range [-2^31, +2^31-1].
    // --------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            accumulated_out <= '0;
            valid_out       <= 1'b0;
        end else begin
            if (en && valid_in) begin
                accumulated_out <= accumulated_out + ACC_WIDTH'(spatial_sum);
                valid_out       <= 1'b1;
            end else begin
                valid_out       <= 1'b0;
            end
        end
    end

endmodule
