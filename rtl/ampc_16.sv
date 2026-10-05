// ==============================================================================
// Project: Adaptive MAC Processing Core (AMPC) for TinyML Inference Acceleration
// Target:  AMD/Xilinx Zynq-7010 (xc7z010clg400-1) | Vivado 2026.1
// File:    ampc_16.sv
// Module:  ampc_16
// Author:  VLSI/FPGA Project Team
// Details: Stage 5 - 16-Lane Adaptive MAC Processing Core (AMPC-16)
// ==============================================================================

`timescale 1ns / 1ps

module ampc_16 #(
    parameter int DATA_WIDTH   = 8,   // Activation width (Signed INT8)
    parameter int WEIGHT_WIDTH = 8,   // Weight parameter width (Signed INT8)
    parameter int ACC_WIDTH    = 32   // Accumulator width (Signed INT32)
) (
    input  logic                          clk,        // System Clock
    input  logic                          rst_n,      // Synchronous Active-Low Reset
    input  logic                          en,         // Core-Level Processing Enable
    input  logic [15:0]                   lane_mask,  // Per-lane mask [15:0] (1=Active, 0=Masked, explicitly driven)

    // Parallel 16-lane inputs
    input  logic signed [DATA_WIDTH-1:0]   data_in  [0:15],
    input  logic signed [WEIGHT_WIDTH-1:0] weight   [0:15],
    input  logic signed [ACC_WIDTH-1:0]    acc_in   [0:15],

    // Registered 16-lane outputs
    output logic signed [ACC_WIDTH-1:0]    acc_out  [0:15],
    output logic                          valid_out   // Output valid strobe (asserted 1 cycle after enable)
);

    // Gated operand wires to suppress switching activity and garbage on disabled lanes
    logic signed [DATA_WIDTH-1:0]   effective_data   [0:15];
    logic signed [WEIGHT_WIDTH-1:0] effective_weight [0:15];

    // Combinational outputs from individual MAC units
    logic signed [ACC_WIDTH-1:0]    mac_result       [0:15];

    // --------------------------------------------------------------------------
    // Dynamic Lane Masking & Multiplier Operand Gating
    // When a lane is masked (lane_mask[i] == 0) or en == 0:
    // Operands are forced to 0, ensuring (0 * 0) + acc_in[i] = acc_in[i].
    // This preserves existing accumulation without introducing garbage data,
    // while preventing dynamic power consumption from unwanted toggling.
    // --------------------------------------------------------------------------
    genvar i;
    generate
        for (i = 0; i < 16; i = i + 1) begin : gen_lane_gating
            assign effective_data[i]   = (en && lane_mask[i]) ? data_in[i] : {DATA_WIDTH{1'b0}};
            assign effective_weight[i] = (en && lane_mask[i]) ? weight[i]  : {WEIGHT_WIDTH{1'b0}};
        end
    endgenerate

    // --------------------------------------------------------------------------
    // Instantiate 16 Parallel MAC Processing Units
    // --------------------------------------------------------------------------
    generate
        for (i = 0; i < 16; i = i + 1) begin : gen_mac_units
            mac_unit #(
                .DATA_WIDTH   (DATA_WIDTH),
                .WEIGHT_WIDTH (WEIGHT_WIDTH),
                .ACC_WIDTH    (ACC_WIDTH)
            ) u_mac (
                .data_in (effective_data[i]),
                .weight  (effective_weight[i]),
                .acc_in  (acc_in[i]),
                .acc_out (mac_result[i])
            );
        end
    endgenerate

    // --------------------------------------------------------------------------
    // Sequential Pipeline Stage (Output Register & Valid Strobe)
    // Latency: Exactly 1 clock cycle from (en && inputs) to registered acc_out.
    // Reset: Synchronous active-low reset (rst_n) matching Xilinx 7-series DSP48.
    // --------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            for (int k = 0; k < 16; k = k + 1) begin
                acc_out[k] <= '0;
            end
            valid_out <= 1'b0;
        end else begin
            if (en) begin
                for (int k = 0; k < 16; k = k + 1) begin
                    acc_out[k] <= mac_result[k];
                end
                valid_out <= 1'b1;
            end else begin
                valid_out <= 1'b0;
            end
        end
    end

endmodule
