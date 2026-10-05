// ==============================================================================
// Project: Adaptive MAC Processing Core (AMPC) for TinyML Inference Acceleration
// Target:  AMD/Xilinx Zynq-7010 (xc7z010clg400-1) | Vivado 2026.1
// File:    workload_analyzer.sv
// Module:  workload_analyzer
// Author:  VLSI/FPGA Project Team
// Details: Stage 9 - Modular Workload Analyzer with Multi-Cycle Chunking Expose
// ==============================================================================

`timescale 1ns / 1ps

module workload_analyzer #(
    parameter int WORKLOAD_WIDTH = 16   // Workload size bit-width (supports up to 65535 operations)
) (
    input  logic                         clk,                // System Clock
    input  logic                         rst_n,              // Synchronous Active-Low Reset
    input  logic                         en,                 // Module Enable
    input  logic                         valid_in,           // Input Workload Valid Strobe
    input  logic [WORKLOAD_WIDTH-1:0]    workload_size,      // Requested Workload Size W

    output logic [4:0]                   selected_capacity,  // Selected Parallel AMPC Core (0, 2, 4, 8, 16)
    output logic [WORKLOAD_WIDTH-1:0]    remainder,          // Active lane count (if W<=16) or remaining workload for multi-cycle (if W>16)
    output logic                         valid_out           // Valid Analysis Output Strobe (1-cycle latency)
);

    // Combinational evaluation wires
    logic [4:0]                next_capacity;
    logic [WORKLOAD_WIDTH-1:0] next_remainder;

    // --------------------------------------------------------------------------
    // Workload-to-Capacity Analysis Logic:
    // 1. Zero Workload (W = 0):
    //    Capacity = 0, Remainder = 0 (No core activated).
    // 2. Single-Cycle Workloads (W in 1..16):
    //    - W in 1..2  -> Capacity = 2 (AMPC-2). Remainder = (W==2 ? 0 : W).
    //    - W in 3..4  -> Capacity = 4 (AMPC-4). Remainder = (W==4 ? 0 : W).
    //    - W in 5..8  -> Capacity = 8 (AMPC-8). Remainder = (W==8 ? 0 : W).
    //    - W in 9..16 -> Capacity = 16 (AMPC-16). Remainder = (W==16 ? 0 : W).
    // 3. Multi-Cycle Workloads (W > 16):
    //    - First execution chunk assigns maximum physical capacity (Capacity = 16).
    //    - Remainder exposes remaining workload for subsequent chunks: Remainder = W - 16.
    // --------------------------------------------------------------------------
    always_comb begin
        if (workload_size == '0) begin
            next_capacity  = 5'd0;
            next_remainder = '0;
        end else if (workload_size <= 16'd2) begin
            next_capacity  = 5'd2;
            next_remainder = (workload_size == 16'd2) ? '0 : workload_size;
        end else if (workload_size <= 16'd4) begin
            next_capacity  = 5'd4;
            next_remainder = (workload_size == 16'd4) ? '0 : workload_size;
        end else if (workload_size <= 16'd8) begin
            next_capacity  = 5'd8;
            next_remainder = (workload_size == 16'd8) ? '0 : workload_size;
        end else if (workload_size <= 16'd16) begin
            next_capacity  = 5'd16;
            next_remainder = (workload_size == 16'd16) ? '0 : workload_size;
        end else begin
            next_capacity  = 5'd16;
            next_remainder = workload_size - 16'd16;
        end
    end

    // --------------------------------------------------------------------------
    // Synchronous Registered Output Stage:
    // - Deterministic 1-clock-cycle latency.
    // - Transaction accepted when (en == 1 && valid_in == 1).
    // - When disabled or invalid, previous values hold and valid_out deasserts.
    // - Synchronous active-low reset clears all registers.
    // --------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            selected_capacity <= 5'd0;
            remainder         <= '0;
            valid_out         <= 1'b0;
        end else begin
            if (en && valid_in) begin
                selected_capacity <= next_capacity;
                remainder         <= next_remainder;
                valid_out         <= 1'b1;
            end else begin
                valid_out         <= 1'b0;
            end
        end
    end

endmodule
