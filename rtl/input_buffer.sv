// ==============================================================================
// Project: Adaptive MAC Processing Core (AMPC) for TinyML Inference Acceleration
// Target:  AMD/Xilinx Zynq-7010 (xc7z010clg400-1) | Vivado 2026.1
// File:    input_buffer.sv
// Module:  input_buffer
// Author:  VLSI/FPGA Project Team
// Details: Stage 8 - Parameterized Signed INT8 Activation Storage Buffer
// ==============================================================================

`timescale 1ns / 1ps

module input_buffer #(
    parameter int DATA_WIDTH = 8,                 // Signed INT8 activation data width
    parameter int DEPTH      = 64,                // Buffer storage depth (words)
    parameter int ADDR_WIDTH = $clog2(DEPTH)      // Address bit-width
) (
    input  logic                         clk,      // System Clock
    input  logic                         rst_n,    // Synchronous Active-Low Reset
    input  logic                         wr_en,    // Synchronous Write Enable
    input  logic [ADDR_WIDTH-1:0]        wr_addr,  // Write Address
    input  logic signed [DATA_WIDTH-1:0] wr_data,  // Signed INT8 Activation Input
    input  logic [ADDR_WIDTH-1:0]        rd_addr,  // Read Address
    output logic signed [DATA_WIDTH-1:0] rd_data   // Registered Signed INT8 Activation Output
);

    // --------------------------------------------------------------------------
    // Storage Array:
    // Synthesis Note: Actual FPGA resource mapping (distributed RAM/LUTRAM vs.
    // dedicated Block RAM DSP/BRAM) will be inferred during Vivado synthesis
    // according to depth, access patterns, and synthesis directives.
    // --------------------------------------------------------------------------
    logic signed [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // --------------------------------------------------------------------------
    // Synchronous Read and Write Logic:
    // - Read Latency: Exactly 1 clock cycle (rd_data registered at posedge clk).
    // - Reset Strategy: Output register 'rd_data' is synchronously cleared to 0
    //   on !rst_n. The internal memory array 'mem' is intentionally not reset to
    //   prevent reset-routing explosion and ensure clean FPGA RAM inference.
    // - Collision Mode: Write-First forwarding when (wr_en && wr_addr == rd_addr),
    //   guaranteeing immediate visibility of newly written data on the next cycle.
    // --------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (wr_en) begin
            mem[wr_addr] <= wr_data;
        end

        if (!rst_n) begin
            rd_data <= '0;
        end else if (wr_en && (wr_addr == rd_addr)) begin
            rd_data <= wr_data; // Write-first forwarding on address collision
        end else begin
            rd_data <= mem[rd_addr]; // Synchronous read (1-cycle latency)
        end
    end

endmodule
