// ==============================================================================
// Project: Adaptive MAC Processing Core (AMPC) for TinyML Inference Acceleration
// Target:  AMD/Xilinx Zynq-7010 (xc7z010clg400-1) | Vivado 2026.1
// File:    adaptive_controller.sv
// Module:  adaptive_controller
// Author:  VLSI/FPGA Project Team
// Details: Stage 10 - Workload-Dependent Adaptive Controller and Chunking FSM
// ==============================================================================

`timescale 1ns / 1ps

module adaptive_controller #(
    parameter int WORKLOAD_WIDTH = 16   // Supported workload request width (up to 65535 operations)
) (
    input  logic                         clk,                // System Clock
    input  logic                         rst_n,              // Synchronous Active-Low Reset
    input  logic                         start,              // Workload Start / Request Strobe
    input  logic [WORKLOAD_WIDTH-1:0]    workload_size,      // Requested Workload Size W

    // Status & Handshaking
    output logic                         ready,              // Ready to accept a new workload request
    output logic                         busy,               // Asserted while processing workload chunks
    output logic                         done,               // Asserted for 1 cycle upon batch completion

    // AMPC Core Selection & Individual Enables
    output logic [1:0]                   core_sel,           // 2'b00: AMPC-2, 2'b01: AMPC-4, 2'b10: AMPC-8, 2'b11: AMPC-16
    output logic [3:0]                   core_en,            // [0]: AMPC-2, [1]: AMPC-4, [2]: AMPC-8, [3]: AMPC-16
    output logic                         ampc2_en,           // Dedicated AMPC-2 Enable
    output logic                         ampc4_en,           // Dedicated AMPC-4 Enable
    output logic                         ampc8_en,           // Dedicated AMPC-8 Enable
    output logic                         ampc16_en,          // Dedicated AMPC-16 Enable

    // Dynamic Per-Core Lane Masks
    output logic [1:0]                   ampc2_lane_mask,    // Active lane mask for AMPC-2
    output logic [3:0]                   ampc4_lane_mask,    // Active lane mask for AMPC-4
    output logic [7:0]                   ampc8_lane_mask,    // Active lane mask for AMPC-8
    output logic [15:0]                  ampc16_lane_mask,   // Active lane mask for AMPC-16

    // Execution Telemetry
    output logic [WORKLOAD_WIDTH-1:0]    current_chunk_size, // Active operations executed in current cycle
    output logic [WORKLOAD_WIDTH-1:0]    remaining_workload, // Remaining unexecuted operations
    output logic                         chunk_valid         // Strobe asserted during each active execution chunk
);

    // --------------------------------------------------------------------------
    // Controller FSM State Encoding
    // --------------------------------------------------------------------------
    typedef enum logic [1:0] {
        ST_IDLE    = 2'b00,  // Awaiting start request
        ST_EXECUTE = 2'b01,  // Actively executing current workload chunk across selected AMPC
        ST_DONE    = 2'b10   // Workload batch completed (1-cycle pulse)
    } state_t;

    state_t state_q, state_d;

    // Internal Registers
    logic [WORKLOAD_WIDTH-1:0] rem_q, rem_d;

    // Combinational evaluation signals for current chunk
    logic [1:0]                chunk_core_sel;
    logic [3:0]                chunk_core_en;
    logic [WORKLOAD_WIDTH-1:0] chunk_size_comb;
    logic [1:0]                chunk_mask_2;
    logic [3:0]                chunk_mask_4;
    logic [7:0]                chunk_mask_8;
    logic [15:0]               chunk_mask_16;

    // --------------------------------------------------------------------------
    // Workload Chunk Classification & Mask Synthesis Logic
    // Evaluates the current remaining workload (rem_q) and selects:
    //   - optimal AMPC core granularity (AMPC-2, AMPC-4, AMPC-8, or AMPC-16)
    //   - active lane mask for the selected core
    //   - operation count (chunk_size) consumed in the current execution cycle
    // --------------------------------------------------------------------------
    always_comb begin
        // Default zero assignments
        chunk_core_sel  = 2'b00;
        chunk_core_en   = 4'b0000;
        chunk_size_comb = '0;
        chunk_mask_2    = 2'b00;
        chunk_mask_4    = 4'b0000;
        chunk_mask_8    = 8'b00000000;
        chunk_mask_16   = 16'h0000;

        if (rem_q == '0) begin
            chunk_core_sel  = 2'b00;
            chunk_core_en   = 4'b0000;
            chunk_size_comb = '0;
        end else if (rem_q <= 16'd2) begin
            // Select AMPC-2
            chunk_core_sel  = 2'b00;
            chunk_core_en   = 4'b0001;
            chunk_size_comb = rem_q;
            chunk_mask_2    = (rem_q == 16'd1) ? 2'b01 : 2'b11;
        end else if (rem_q <= 16'd4) begin
            // Select AMPC-4
            chunk_core_sel  = 2'b01;
            chunk_core_en   = 4'b0010;
            chunk_size_comb = rem_q;
            case (rem_q[2:0])
                3'd1: chunk_mask_4 = 4'b0001;
                3'd2: chunk_mask_4 = 4'b0011;
                3'd3: chunk_mask_4 = 4'b0111;
                default: chunk_mask_4 = 4'b1111;
            endcase
        end else if (rem_q <= 16'd8) begin
            // Select AMPC-8
            chunk_core_sel  = 2'b10;
            chunk_core_en   = 4'b0100;
            chunk_size_comb = rem_q;
            if (rem_q >= 16'd8) begin
                chunk_mask_8 = 8'b11111111;
            end else begin
                chunk_mask_8 = 8'((8'b1 << rem_q[2:0]) - 8'd1);
            end
        end else if (rem_q <= 16'd16) begin
            // Select AMPC-16 (Single-cycle remainder <= 16)
            chunk_core_sel  = 2'b11;
            chunk_core_en   = 4'b1000;
            chunk_size_comb = rem_q;
            if (rem_q >= 16'd16) begin
                chunk_mask_16 = 16'hFFFF;
            end else begin
                chunk_mask_16 = 16'((16'b1 << rem_q[3:0]) - 16'd1);
            end
        end else begin
            // Select AMPC-16 (Multi-cycle chunk: consume 16 operations)
            chunk_core_sel  = 2'b11;
            chunk_core_en   = 4'b1000;
            chunk_size_comb = 16'd16;
            chunk_mask_16   = 16'hFFFF;
        end
    end

    // --------------------------------------------------------------------------
    // FSM State Transition & Progress Calculation
    // --------------------------------------------------------------------------
    always_comb begin
        state_d = state_q;
        rem_d   = rem_q;

        case (state_q)
            ST_IDLE: begin
                if (start) begin
                    if (workload_size == '0) begin
                        // Zero workload: immediately signal completion with no active execution
                        rem_d   = '0;
                        state_d = ST_DONE;
                    end else begin
                        rem_d   = workload_size;
                        state_d = ST_EXECUTE;
                    end
                end
            end

            ST_EXECUTE: begin
                // Decrement workload by current chunk size
                if (rem_q <= chunk_size_comb) begin
                    rem_d   = '0;
                    state_d = ST_DONE;
                end else begin
                    rem_d   = rem_q - chunk_size_comb;
                    state_d = ST_EXECUTE; // Continue executing remaining chunks
                end
            end

            ST_DONE: begin
                // 1-cycle completion pulse, then return to IDLE
                state_d = ST_IDLE;
            end

            default: begin
                state_d = ST_IDLE;
            end
        endcase
    end

    // --------------------------------------------------------------------------
    // Sequential State & Register Update
    // --------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state_q <= ST_IDLE;
            rem_q   <= '0;
        end else begin
            state_q <= state_d;
            rem_q   <= rem_d;
        end
    end

    // --------------------------------------------------------------------------
    // Primary Control Outputs Generation
    // --------------------------------------------------------------------------
    always_comb begin
        // Status signals
        ready              = (state_q == ST_IDLE);
        busy               = (state_q == ST_EXECUTE);
        done               = (state_q == ST_DONE);
        chunk_valid        = (state_q == ST_EXECUTE);

        remaining_workload = rem_q;

        if (state_q == ST_EXECUTE) begin
            core_sel           = chunk_core_sel;
            core_en            = chunk_core_en;
            ampc2_en           = chunk_core_en[0];
            ampc4_en           = chunk_core_en[1];
            ampc8_en           = chunk_core_en[2];
            ampc16_en          = chunk_core_en[3];
            ampc2_lane_mask    = chunk_mask_2;
            ampc4_lane_mask    = chunk_mask_4;
            ampc8_lane_mask    = chunk_mask_8;
            ampc16_lane_mask   = chunk_mask_16;
            current_chunk_size = chunk_size_comb;
        end else begin
            // In IDLE and DONE states, all execution enables and masks are strictly zero
            core_sel           = 2'b00;
            core_en            = 4'b0000;
            ampc2_en           = 1'b0;
            ampc4_en           = 1'b0;
            ampc8_en           = 1'b0;
            ampc16_en          = 1'b0;
            ampc2_lane_mask    = 2'b00;
            ampc4_lane_mask    = 4'b0000;
            ampc8_lane_mask    = 8'b00000000;
            ampc16_lane_mask   = 16'h0000;
            current_chunk_size = '0;
        end
    end

endmodule
