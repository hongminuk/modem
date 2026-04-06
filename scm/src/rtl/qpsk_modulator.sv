`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: qpsk_modulator
// Description:
//   Bit-to-symbol mapper for QPSK
//   Takes 2 bits per clock and outputs one I/Q symbol
//
//   Mapping (matches Python scm_sim.py):
//     bit 0 -> +SCALE
//     bit 1 -> -SCALE
//
//   in_data[0] -> I channel
//   in_data[1] -> Q channel
//////////////////////////////////////////////////////////////////////////////////

module qpsk_modulator #(
    parameter int W     = 16,
    parameter int SCALE = 12000
)(
    input  logic                clk,
    input  logic                rst_n,

    // Bit input (2 bits per symbol)
    input  logic [1:0]          in_data,
    input  logic                in_valid,
    output logic                in_ready,

    // Symbol output (I/Q)
    output logic signed [W-1:0] out_i,
    output logic signed [W-1:0] out_q,
    output logic                out_valid,
    input  logic                out_ready
);

    // Combinational mapping: 0 -> +SCALE, 1 -> -SCALE
    logic signed [W-1:0] mapped_i, mapped_q;

    assign mapped_i = in_data[0] ? -W'(SCALE) : W'(SCALE);
    assign mapped_q = in_data[1] ? -W'(SCALE) : W'(SCALE);

    // Pass-through with AXI-Stream handshake
    assign in_ready  = out_ready || !out_valid;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_i     <= '0;
            out_q     <= '0;
            out_valid <= 1'b0;
        end else begin
            if (out_valid && out_ready) begin
                out_valid <= 1'b0;
            end

            if (in_valid && in_ready) begin
                out_i     <= mapped_i;
                out_q     <= mapped_q;
                out_valid <= 1'b1;
            end
        end
    end

endmodule
