// ==============================================================================
// Project: Adaptive MAC Processing Core (AMPC) for TinyML Inference Acceleration
// Target:  AMD/Xilinx Zynq-7010 (xc7z010clg400-1) | Vivado 2026.1
// File:    exp_dsp_eval_top.sv
// Module:  exp_dsp_eval_top
// Details: Stage 15 Experimental - Dual Subsystem for DSP48E1 vs LUT MAC Evaluation
//          Contains:
//          Subsystem A: 4-Lane LUT-based registered MAC pipeline (matching AMPC-4 baseline)
//          Subsystem B: 4-Lane DSP-based registered MAC pipeline (using mac_unit_dsp)
// ==============================================================================

`timescale 1ns / 1ps

module exp_dsp_eval_top #(
    parameter int LANES = 4
) (
    input  logic                         clk,
    input  logic                         rst_n,
    input  logic                         en,
    input  logic [LANES-1:0]             lane_mask,

    // Inputs for 4-lane LUT baseline core
    input  logic signed [7:0]            lut_data_in  [0:LANES-1],
    input  logic signed [7:0]            lut_weight   [0:LANES-1],
    output logic signed [31:0]           lut_acc_out  [0:LANES-1],
    output logic                         lut_valid_out,

    // Inputs for 4-lane DSP experimental core
    input  logic signed [7:0]            dsp_data_in  [0:LANES-1],
    input  logic signed [7:0]            dsp_weight   [0:LANES-1],
    output logic signed [31:0]           dsp_acc_out  [0:LANES-1],
    output logic                         dsp_valid_out
);

    // --------------------------------------------------------------------------
    // Subsystem A: 4-Lane LUT-based MAC pipeline (Baseline Architecture)
    // --------------------------------------------------------------------------
    logic signed [7:0]  eff_lut_data   [0:LANES-1];
    logic signed [7:0]  eff_lut_weight [0:LANES-1];
    logic signed [31:0] lut_mac_result [0:LANES-1];

    genvar i;
    generate
        for (i = 0; i < LANES; i = i + 1) begin : gen_lut_lanes
            assign eff_lut_data[i]   = (en && lane_mask[i]) ? lut_data_in[i] : 8'sd0;
            assign eff_lut_weight[i] = (en && lane_mask[i]) ? lut_weight[i]  : 8'sd0;

            mac_unit #(
                .DATA_WIDTH(8), .WEIGHT_WIDTH(8), .ACC_WIDTH(32)
            ) u_mac_lut (
                .data_in (eff_lut_data[i]),
                .weight  (eff_lut_weight[i]),
                .acc_in  (32'sd0),
                .acc_out (lut_mac_result[i])
            );
        end
    endgenerate

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            for (int k = 0; k < LANES; k++) lut_acc_out[k] <= '0;
            lut_valid_out <= 1'b0;
        end else begin
            if (en) begin
                for (int k = 0; k < LANES; k++) lut_acc_out[k] <= lut_mac_result[k];
                lut_valid_out <= 1'b1;
            end else begin
                lut_valid_out <= 1'b0;
            end
        end
    end

    // --------------------------------------------------------------------------
    // Subsystem B: 4-Lane DSP-based MAC pipeline (Experimental Architecture)
    // --------------------------------------------------------------------------
    logic signed [7:0]  eff_dsp_data   [0:LANES-1];
    logic signed [7:0]  eff_dsp_weight [0:LANES-1];
    logic signed [31:0] dsp_mac_result [0:LANES-1];

    generate
        for (i = 0; i < LANES; i = i + 1) begin : gen_dsp_lanes
            assign eff_dsp_data[i]   = (en && lane_mask[i]) ? dsp_data_in[i] : 8'sd0;
            assign eff_dsp_weight[i] = (en && lane_mask[i]) ? dsp_weight[i]  : 8'sd0;

            mac_unit_dsp #(
                .DATA_WIDTH(8), .WEIGHT_WIDTH(8), .ACC_WIDTH(32)
            ) u_mac_dsp (
                .data_in (eff_dsp_data[i]),
                .weight  (eff_dsp_weight[i]),
                .acc_in  (32'sd0),
                .acc_out (dsp_mac_result[i])
            );
        end
    endgenerate

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            for (int k = 0; k < LANES; k++) dsp_acc_out[k] <= '0;
            dsp_valid_out <= 1'b0;
        end else begin
            if (en) begin
                for (int k = 0; k < LANES; k++) dsp_acc_out[k] <= dsp_mac_result[k];
                dsp_valid_out <= 1'b1;
            end else begin
                dsp_valid_out <= 1'b0;
            end
        end
    end

endmodule
