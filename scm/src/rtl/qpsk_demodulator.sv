`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: qpsk_demodulator
// Description:
//   Symbol-to-bit demapper for QPSK (hard decision slicer)
//   Takes one I/Q symbol and outputs 2 bits
//
//   Decision (matches Python scm_sim.py):
//     I >= 0 -> bit 0
//     I <  0 -> bit 1
//     Q >= 0 -> bit 0
//     Q <  0 -> bit 1
//
//   out_data[0] = I decision
//   out_data[1] = Q decision
//////////////////////////////////////////////////////////////////////////////////

module qpsk_demodulator #(
    parameter int W = 56       // input symbol width (after RX processing)
)(
    input  logic                    clk,
    input  logic                    rst_n,

    // Symbol input (I/Q)
    input  logic signed [W-1:0]     in_i,
    input  logic signed [W-1:0]     in_q,
    input  logic                    in_valid,
    output logic                    in_ready,

    // Bit output (2 bits per symbol)
    output logic [1:0]              out_data,
    output logic                    out_valid,
    input  logic                    out_ready
);

    // Hard decision: sign bit (MSB) tells us the decision
    // signed negative => MSB=1 => bit=1
    // signed positive => MSB=0 => bit=0
    logic [1:0] decision;

    assign decision[0] = in_i[W-1];   // I sign bit
    assign decision[1] = in_q[W-1];   // Q sign bit

    // Pass-through with AXI-Stream handshake
    assign in_ready = out_ready || !out_valid;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_data  <= '0;
            out_valid <= 1'b0;
        end else begin
            if (out_valid && out_ready) begin
                out_valid <= 1'b0;
            end

            if (in_valid && in_ready) begin
                out_data  <= decision;
                out_valid <= 1'b1;
            end
        end
    end

endmodule
