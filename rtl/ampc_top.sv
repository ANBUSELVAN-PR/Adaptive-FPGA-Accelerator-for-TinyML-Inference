// ==============================================================================
// Project: Adaptive MAC Processing Core (AMPC) for TinyML Inference Acceleration
// Target:  AMD/Xilinx Zynq-7010 (xc7z010clg400-1) | Vivado 2026.1
// File:    ampc_top.sv
// Module:  ampc_top
// Author:  VLSI/FPGA Project Team
// Details: Stage 11 - Complete Datapath & Control Top-Level Integration Wrapper
// ==============================================================================

`timescale 1ns / 1ps

module ampc_top #(
    parameter int DATA_WIDTH     = 8,   // INT8 signed activations & weights
    parameter int ACC_WIDTH      = 32,  // INT32 signed accumulation & ReLU width
    parameter int MAX_LANES      = 16,  // Maximum parallel MAC lanes (AMPC-16)
    parameter int BUFFER_DEPTH   = 64,  // On-chip activation/weight buffer depth
    parameter int WORKLOAD_WIDTH = 16   // Maximum supported workload size width
) (
    input  logic                         clk,
    input  logic                         rst_n,
    input  logic                         start,
    input  logic [WORKLOAD_WIDTH-1:0]    workload_size,

    // Parallel multi-lane streaming operands (Lanes 0..15)
    input  logic signed [DATA_WIDTH-1:0] data_in  [0:MAX_LANES-1],
    input  logic signed [DATA_WIDTH-1:0] weight   [0:MAX_LANES-1],

    // On-chip Input Activation Buffer Interface
    input  logic                         ibuf_wr_en,
    input  logic [$clog2(BUFFER_DEPTH)-1:0] ibuf_wr_addr,
    input  logic signed [DATA_WIDTH-1:0] ibuf_wr_data,
    input  logic [$clog2(BUFFER_DEPTH)-1:0] ibuf_rd_addr,
    output logic signed [DATA_WIDTH-1:0] ibuf_rd_data,

    // On-chip Filter Weight Buffer Interface
    input  logic                         wbuf_wr_en,
    input  logic [$clog2(BUFFER_DEPTH)-1:0] wbuf_wr_addr,
    input  logic signed [DATA_WIDTH-1:0] wbuf_wr_data,
    input  logic [$clog2(BUFFER_DEPTH)-1:0] wbuf_rd_addr,
    output logic signed [DATA_WIDTH-1:0] wbuf_rd_data,

    // Primary Control & Status Handshaking
    output logic                         ready,
    output logic                         busy,
    output logic                         done,
    output logic [1:0]                   active_core,       // 2'b00: AMPC-2, 2'b01: AMPC-4, 2'b10: AMPC-8, 2'b11: AMPC-16

    // Workload Telemetry (from Workload Analyzer)
    output logic [4:0]                   analyzer_capacity,
    output logic [WORKLOAD_WIDTH-1:0]    analyzer_remainder,
    output logic                         analyzer_valid,

    // Final Scalar Dot-Product & Activated Outputs
    output logic signed [ACC_WIDTH-1:0]  accumulated_out,   // Raw unactivated dot-product
    output logic signed [ACC_WIDTH-1:0]  output_data,       // Post-ReLU non-linear activated output
    output logic                         output_valid       // High when output_data and accumulated_out are final
);

    localparam int ADDR_WIDTH = $clog2(BUFFER_DEPTH);

    // --------------------------------------------------------------------------
    // 1. On-Chip Storage Buffers (Input Activations & Weights)
    // --------------------------------------------------------------------------
    input_buffer #(
        .DATA_WIDTH (DATA_WIDTH),
        .DEPTH      (BUFFER_DEPTH),
        .ADDR_WIDTH (ADDR_WIDTH)
    ) u_input_buffer (
        .clk     (clk),
        .rst_n   (rst_n),
        .wr_en   (ibuf_wr_en),
        .wr_addr (ibuf_wr_addr),
        .wr_data (ibuf_wr_data),
        .rd_addr (ibuf_rd_addr),
        .rd_data (ibuf_rd_data)
    );

    weight_buffer #(
        .DATA_WIDTH (DATA_WIDTH),
        .DEPTH      (BUFFER_DEPTH),
        .ADDR_WIDTH (ADDR_WIDTH)
    ) u_weight_buffer (
        .clk     (clk),
        .rst_n   (rst_n),
        .wr_en   (wbuf_wr_en),
        .wr_addr (wbuf_wr_addr),
        .wr_data (wbuf_wr_data),
        .rd_addr (wbuf_rd_addr),
        .rd_data (wbuf_rd_data)
    );

    // --------------------------------------------------------------------------
    // 2. Workload Analyzer
    // --------------------------------------------------------------------------
    workload_analyzer #(
        .WORKLOAD_WIDTH (WORKLOAD_WIDTH)
    ) u_analyzer (
        .clk               (clk),
        .rst_n             (rst_n),
        .en                (1'b1),
        .valid_in          (start),
        .workload_size     (workload_size),
        .selected_capacity (analyzer_capacity),
        .remainder         (analyzer_remainder),
        .valid_out         (analyzer_valid)
    );

    // --------------------------------------------------------------------------
    // 3. Adaptive Controller & FSM
    // --------------------------------------------------------------------------
    logic [1:0]                   ctrl_core_sel;
    logic [3:0]                   ctrl_core_en;
    logic                         ctrl_ampc2_en, ctrl_ampc4_en, ctrl_ampc8_en, ctrl_ampc16_en;
    logic [1:0]                   ctrl_mask_2;
    logic [3:0]                   ctrl_mask_4;
    logic [7:0]                   ctrl_mask_8;
    logic [15:0]                  ctrl_mask_16;
    logic [WORKLOAD_WIDTH-1:0]    ctrl_chunk_size;
    logic [WORKLOAD_WIDTH-1:0]    ctrl_rem_workload;
    logic                         ctrl_ready, ctrl_busy, ctrl_done, ctrl_chunk_valid;

    adaptive_controller #(
        .WORKLOAD_WIDTH (WORKLOAD_WIDTH)
    ) u_controller (
        .clk                (clk),
        .rst_n              (rst_n),
        .start              (start),
        .workload_size      (workload_size),
        .ready              (ctrl_ready),
        .busy               (ctrl_busy),
        .done               (ctrl_done),
        .core_sel           (ctrl_core_sel),
        .core_en            (ctrl_core_en),
        .ampc2_en           (ctrl_ampc2_en),
        .ampc4_en           (ctrl_ampc4_en),
        .ampc8_en           (ctrl_ampc8_en),
        .ampc16_en          (ctrl_ampc16_en),
        .ampc2_lane_mask    (ctrl_mask_2),
        .ampc4_lane_mask    (ctrl_mask_4),
        .ampc8_lane_mask    (ctrl_mask_8),
        .ampc16_lane_mask   (ctrl_mask_16),
        .current_chunk_size (ctrl_chunk_size),
        .remaining_workload (ctrl_rem_workload),
        .chunk_valid        (ctrl_chunk_valid)
    );

    // --------------------------------------------------------------------------
    // Stage 14 Optimization: Control & Operand Pipeline Decoupling Stage
    // Breaks the critical timing path from controller remainder/comparator logic
    // through high-fanout enables into AMPC multiplier carry chains.
    // Cycle A: Controller FSM & remainder classification -> Pipeline Registers
    // Cycle B: Registered enables/masks/operands -> AMPC MAC units -> Registered Acc
    // --------------------------------------------------------------------------
    logic [1:0]                   pipe_core_sel;
    logic                         pipe_ampc2_en;
    logic                         pipe_ampc4_en;
    logic                         pipe_ampc8_en;
    logic                         pipe_ampc16_en;
    logic [1:0]                   pipe_mask_2;
    logic [3:0]                   pipe_mask_4;
    logic [7:0]                   pipe_mask_8;
    logic [15:0]                  pipe_mask_16;
    logic signed [DATA_WIDTH-1:0] pipe_data_in [0:MAX_LANES-1];
    logic signed [DATA_WIDTH-1:0] pipe_weight  [0:MAX_LANES-1];
    logic                         pipe_ctrl_done;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            pipe_core_sel  <= 2'b00;
            pipe_ampc2_en  <= 1'b0;
            pipe_ampc4_en  <= 1'b0;
            pipe_ampc8_en  <= 1'b0;
            pipe_ampc16_en <= 1'b0;
            pipe_mask_2    <= 2'b00;
            pipe_mask_4    <= 4'b0000;
            pipe_mask_8    <= 8'h00;
            pipe_mask_16   <= 16'h0000;
            pipe_ctrl_done <= 1'b0;
            for (int k = 0; k < MAX_LANES; k++) begin
                pipe_data_in[k] <= '0;
                pipe_weight[k]  <= '0;
            end
        end else begin
            pipe_core_sel  <= ctrl_core_sel;
            pipe_ampc2_en  <= ctrl_ampc2_en;
            pipe_ampc4_en  <= ctrl_ampc4_en;
            pipe_ampc8_en  <= ctrl_ampc8_en;
            pipe_ampc16_en <= ctrl_ampc16_en;
            pipe_mask_2    <= ctrl_mask_2;
            pipe_mask_4    <= ctrl_mask_4;
            pipe_mask_8    <= ctrl_mask_8;
            pipe_mask_16   <= ctrl_mask_16;
            pipe_ctrl_done <= ctrl_done;
            for (int k = 0; k < MAX_LANES; k++) begin
                pipe_data_in[k] <= data_in[k];
                pipe_weight[k]  <= weight[k];
            end
        end
    end

    assign active_core = pipe_core_sel;

    // --------------------------------------------------------------------------
    // 4. Parallel AMPC Processing Cores (AMPC-2, AMPC-4, AMPC-8, AMPC-16)
    // Note: acc_in is tied to 0 because the Common Accumulator manages multi-cycle
    // accumulation, preventing conflicting internal accumulation paths.
    // --------------------------------------------------------------------------
    logic signed [ACC_WIDTH-1:0] zero_acc [0:15];
    always_comb for (int k = 0; k < 16; k++) zero_acc[k] = 32'sd0;

    logic signed [ACC_WIDTH-1:0] out_ampc2  [0:1];
    logic signed [ACC_WIDTH-1:0] out_ampc4  [0:3];
    logic signed [ACC_WIDTH-1:0] out_ampc8  [0:7];
    logic signed [ACC_WIDTH-1:0] out_ampc16 [0:15];

    logic valid_ampc2, valid_ampc4, valid_ampc8, valid_ampc16;

    // AMPC-2 Instance (Lanes 0..1)
    ampc_2 u_ampc_2 (
        .clk       (clk),
        .rst_n     (rst_n),
        .en        (pipe_ampc2_en),
        .lane_mask (pipe_mask_2),
        .data_in   (pipe_data_in[0:1]),
        .weight    (pipe_weight[0:1]),
        .acc_in    (zero_acc[0:1]),
        .acc_out   (out_ampc2),
        .valid_out (valid_ampc2)
    );

    // AMPC-4 Instance (Lanes 0..3)
    ampc_4 u_ampc_4 (
        .clk       (clk),
        .rst_n     (rst_n),
        .en        (pipe_ampc4_en),
        .lane_mask (pipe_mask_4),
        .data_in   (pipe_data_in[0:3]),
        .weight    (pipe_weight[0:3]),
        .acc_in    (zero_acc[0:3]),
        .acc_out   (out_ampc4),
        .valid_out (valid_ampc4)
    );

    // AMPC-8 Instance (Lanes 0..7)
    ampc_8 u_ampc_8 (
        .clk       (clk),
        .rst_n     (rst_n),
        .en        (pipe_ampc8_en),
        .lane_mask (pipe_mask_8),
        .data_in   (pipe_data_in[0:7]),
        .weight    (pipe_weight[0:7]),
        .acc_in    (zero_acc[0:7]),
        .acc_out   (out_ampc8),
        .valid_out (valid_ampc8)
    );

    // AMPC-16 Instance (Lanes 0..15)
    ampc_16 u_ampc_16 (
        .clk       (clk),
        .rst_n     (rst_n),
        .en        (pipe_ampc16_en),
        .lane_mask (pipe_mask_16),
        .data_in   (pipe_data_in),
        .weight    (pipe_weight),
        .acc_in    (zero_acc),
        .acc_out   (out_ampc16),
        .valid_out (valid_ampc16)
    );

    // --------------------------------------------------------------------------
    // 5. Control Pipeline Alignment & Accumulator Multiplexing
    // AMPC registered outputs appear 1 cycle after enable.
    // We pipeline the active lane mask to align with AMPC registered outputs.
    // --------------------------------------------------------------------------
    logic [15:0] current_active_mask;
    always_comb begin
        case (pipe_core_sel)
            2'b00:   current_active_mask = {14'b0, pipe_mask_2};
            2'b01:   current_active_mask = {12'b0, pipe_mask_4};
            2'b10:   current_active_mask = {8'b0,  pipe_mask_8};
            2'b11:   current_active_mask = pipe_mask_16;
            default: current_active_mask = 16'h0000;
        endcase
    end

    logic [15:0] mask_q;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            mask_q <= 16'h0000;
        end else begin
            mask_q <= current_active_mask;
        end
    end

    logic signed [ACC_WIDTH-1:0] accum_lane_data [0:15];
    logic                        accum_valid_in;
    logic [15:0]                 accum_lane_mask;

    always_comb begin
        // Default zero assignments
        for (int k = 0; k < 16; k++) accum_lane_data[k] = 32'sd0;
        accum_valid_in  = 1'b0;
        accum_lane_mask = mask_q;

        if (valid_ampc16) begin
            accum_valid_in  = 1'b1;
            for (int k = 0; k < 16; k++) accum_lane_data[k] = out_ampc16[k];
        end else if (valid_ampc8) begin
            accum_valid_in  = 1'b1;
            for (int k = 0; k < 8; k++)  accum_lane_data[k] = out_ampc8[k];
        end else if (valid_ampc4) begin
            accum_valid_in  = 1'b1;
            for (int k = 0; k < 4; k++)  accum_lane_data[k] = out_ampc4[k];
        end else if (valid_ampc2) begin
            accum_valid_in  = 1'b1;
            for (int k = 0; k < 2; k++)  accum_lane_data[k] = out_ampc2[k];
        end
    end

    // Accumulator synchronous reset on new workload request
    logic accum_rst_n;
    assign accum_rst_n = rst_n && !start;

    // --------------------------------------------------------------------------
    // 6. Common Accumulator (Spatial Reduction & Temporal Accumulation)
    // --------------------------------------------------------------------------
    logic accum_valid_out;

    accumulator #(
        .ACC_WIDTH (ACC_WIDTH),
        .LANES     (MAX_LANES)
    ) u_accumulator (
        .clk             (clk),
        .rst_n           (accum_rst_n),
        .en              (1'b1),
        .valid_in        (accum_valid_in),
        .lane_mask       (accum_lane_mask),
        .lane_data       (accum_lane_data),
        .accumulated_out (accumulated_out),
        .valid_out       (accum_valid_out)
    );

    // --------------------------------------------------------------------------
    // 7. ReLU Non-Linear Activation Unit
    // --------------------------------------------------------------------------
    relu #(
        .DATA_WIDTH (ACC_WIDTH)
    ) u_relu (
        .data_in  (accumulated_out),
        .data_out (output_data)
    );

    // --------------------------------------------------------------------------
    // 8. Top-Level Status, Pipeline Tracking & Handshaking
    // --------------------------------------------------------------------------
    logic is_active_q;
    logic zero_workload_q;

    // Detect when the final chunk has reached the accumulator
    logic last_chunk_reached;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            is_active_q        <= 1'b0;
            zero_workload_q    <= 1'b0;
            done               <= 1'b0;
            output_valid       <= 1'b0;
            last_chunk_reached <= 1'b0;
        end else begin
            done         <= 1'b0;
            output_valid <= 1'b0;

            if (start) begin
                if (workload_size == '0) begin
                    is_active_q     <= 1'b0;
                    zero_workload_q <= 1'b1;
                end else begin
                    is_active_q     <= 1'b1;
                    zero_workload_q <= 1'b0;
                end
                last_chunk_reached <= 1'b0;
            end else if (zero_workload_q) begin
                // W=0 completes immediately
                zero_workload_q <= 1'b0;
                done            <= 1'b1;
                output_valid    <= 1'b1;
            end else if (is_active_q) begin
                // Track when controller has finished issuing chunks (delayed by 1 cycle pipeline)
                if (pipe_ctrl_done) begin
                    last_chunk_reached <= 1'b1;
                end

                // Final accumulated scalar is valid 1 cycle after last chunk enters accumulator
                if (last_chunk_reached && accum_valid_out) begin
                    is_active_q        <= 1'b0;
                    last_chunk_reached <= 1'b0;
                    done               <= 1'b1;
                    output_valid       <= 1'b1;
                end
            end
        end
    end

    assign busy  = is_active_q || start || zero_workload_q;
    assign ready = !busy;

endmodule
