`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Testbench: tb_qpsk_frame_sync_top
//
// DUT: qpsk_frame_sync_top.sv (the real top including FIR Compiler IP)
//
// Loopback test: TX output → RX input directly (no channel/noise).
// Verifies the entire pipeline including:
//   - QPSK Modulator (latest version)
//   - Frame Builder
//   - Upsample
//   - TX RRC Filter (Xilinx FIR Compiler IP)
//   - RX RRC Filter (Xilinx FIR Compiler IP, matched filter)
//   - Downsample
//   - Preamble Correlator (after bug fix)
//   - Frame Sync Detector
//   - QPSK Demodulator (latest version)
//
// NOTE: Requires Xilinx FIR Compiler IP. Compile with:
//   xvhdl ../../Vivado_Project/single_carrier_modem.gen/sources_1/ip/fir_rrc/sim/fir_rrc.vhd
//   xvhdl ../../Vivado_Project/single_carrier_modem.gen/sources_1/ip/fir_rrc_rx/sim/fir_rrc_rx.vhd
//   xvlog -sv <RTL files> tb_qpsk_frame_sync_top.sv
//   xelab -L xil_defaultlib -L xpm tb_qpsk_frame_sync_top -s sim_top
//   xsim sim_top -runall
//////////////////////////////////////////////////////////////////////////////////

module tb_qpsk_frame_sync_top;

    parameter int W            = 16;
    parameter int W_2          = 40;
    parameter int W_3          = 56;
    parameter int SPS          = 4;
    parameter int PREAMBLE_LEN = 16;
    parameter int N_PAYLOAD    = 100;
    parameter int N_FRAME      = PREAMBLE_LEN + N_PAYLOAD;
    parameter int FIR_DELAY    = 20;  // FIR group delay margin (symbols)

    logic clk, rst_n;
    initial clk = 0;
    always #5 clk = ~clk;  // 100 MHz

    // === DUT signals ===
    // TX side
    logic                  tx_frame_start;
    logic [15:0]           tx_payload_len;
    logic [1:0]            tx_bits;
    logic                  tx_bits_valid, tx_bits_ready;
    logic signed [W_2-1:0] tx_out_i, tx_out_q;
    logic                  tx_out_valid, tx_out_ready;

    // RX side
    logic signed [W_2-1:0] rx_in_i, rx_in_q;
    logic                  rx_in_valid, rx_in_ready;
    logic [1:0]            rx_bits;
    logic                  rx_bits_valid, rx_bits_ready;

    logic signed [W_3-1:0] rx_out_i, rx_out_q;
    logic                  rx_out_valid, rx_out_ready;

    logic                  rx_sync_found;
    logic [31:0]           rx_sync_index;
    logic [63:0]           rx_sync_mag;

    // === DUT instantiation ===
    qpsk_frame_sync_top #(
        .W(W),
        .W_2(W_2),
        .W_3(W_3),
        .SPS(SPS),
        .OFFSET(0),
        .PREAMBLE_LEN(PREAMBLE_LEN),
        .W_CORR(72),
        // Detector compares mag_sq[127:64] (64-bit upper) > THRESHOLD.
        // After FIR filtering, peak |R|^2 ≈ 1.5e19 in upper 64 bits, sidelobes ≤ 5e18.
        // Use 1e19 to filter sidelobes.
        .SYNC_THRESHOLD(64'd10_000_000_000_000_000_000)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),

        // TX
        .tx_frame_start(tx_frame_start),
        .tx_payload_len(tx_payload_len),
        .tx_bits(tx_bits),
        .tx_bits_valid(tx_bits_valid),
        .tx_bits_ready(tx_bits_ready),
        .tx_out_i(tx_out_i),
        .tx_out_q(tx_out_q),
        .tx_out_valid(tx_out_valid),
        .tx_out_ready(tx_out_ready),

        // RX
        .rx_in_i(rx_in_i),
        .rx_in_q(rx_in_q),
        .rx_in_valid(rx_in_valid),
        .rx_in_ready(rx_in_ready),
        .rx_bits(rx_bits),
        .rx_bits_valid(rx_bits_valid),
        .rx_bits_ready(rx_bits_ready),

        .rx_out_i(rx_out_i),
        .rx_out_q(rx_out_q),
        .rx_out_valid(rx_out_valid),
        .rx_out_ready(rx_out_ready),

        .rx_sync_found(rx_sync_found),
        .rx_sync_index(rx_sync_index),
        .rx_sync_mag(rx_sync_mag)
    );

    // === Loopback: TX -> RX ===
    assign rx_in_i      = tx_out_i;
    assign rx_in_q      = tx_out_q;
    assign rx_in_valid  = tx_out_valid;
    assign tx_out_ready = rx_in_ready;

    // Always accept RX outputs
    assign rx_bits_ready = 1'b1;
    assign rx_out_ready  = 1'b1;

    // === Test stimulus ===
    parameter int RX_BUF_SIZE = N_FRAME + 128;  // extra room for FIR pipeline
    logic [1:0]  tx_bit_mem [0:N_PAYLOAD-1];
    logic [1:0]  rx_bit_mem [0:RX_BUF_SIZE-1];
    logic [15:0] lfsr_reg;
    integer rx_total, sync_count;

    function automatic logic [15:0] lfsr_next(logic [15:0] s);
        return {s[14:0], s[15] ^ s[13] ^ s[12] ^ s[10]};
    endfunction

    initial begin
        $display("=== qpsk_frame_sync_top Testbench (with FIR IP) ===");
        $display("    %0d preamble + %0d payload = %0d frame symbols",
                 PREAMBLE_LEN, N_PAYLOAD, N_FRAME);

        rst_n          = 0;
        tx_frame_start = 0;
        tx_payload_len = 0;
        tx_bits        = 0;
        tx_bits_valid  = 0;
        lfsr_reg       = 16'hACE1;
        rx_total       = 0;
        sync_count     = 0;

        repeat(20) @(posedge clk);
        rst_n = 1;
        repeat(10) @(posedge clk);

        // Trigger frame
        tx_payload_len = N_PAYLOAD;
        tx_frame_start = 1;
        @(posedge clk);
        tx_frame_start = 0;

        fork
            // === TX driver ===
            begin
                // Send the test frame
                for (int i = 0; i < N_PAYLOAD; i++) begin
                    @(posedge clk);
                    tx_bits       = lfsr_reg[1:0];
                    tx_bits_valid = 1;
                    tx_bit_mem[i] = lfsr_reg[1:0];
                    lfsr_reg      = lfsr_next(lfsr_reg);
                    while (1) begin
                        @(posedge clk);
                        if (tx_bits_ready) break;
                    end
                    tx_bits_valid = 0;
                end
                $display("TX: %0d payload bit-pairs sent", N_PAYLOAD);

                // Start a SECOND frame to keep TX FIR pipeline flowing
                // (otherwise the tail symbols of first frame stay in FIR)
                repeat(2) @(posedge clk);
                tx_payload_len = N_PAYLOAD;
                tx_frame_start = 1;
                @(posedge clk);
                tx_frame_start = 0;
                for (int i = 0; i < N_PAYLOAD; i++) begin
                    @(posedge clk);
                    tx_bits       = 2'b00;  // dummy filler
                    tx_bits_valid = 1;
                    while (1) begin
                        @(posedge clk);
                        if (tx_bits_ready) break;
                    end
                    tx_bits_valid = 0;
                end
            end

            // === RX collector ===
            begin
                for (int cycle = 0; cycle < 20000; cycle++) begin
                    @(posedge clk);

                    if (rx_sync_found) begin
                        $display("  >> SYNC: index=%0d, mag=%0d",
                                 rx_sync_index, rx_sync_mag);
                        sync_count++;
                    end

                    if (rx_bits_valid) begin
                        if (rx_total < RX_BUF_SIZE) begin
                            rx_bit_mem[rx_total] = rx_bits;
                        end
                        rx_total++;
                    end

                    if (rx_total >= RX_BUF_SIZE) break;
                end
            end
        join

        repeat(20) @(posedge clk);

        $display("");
        $display("RX symbols collected: %0d", rx_total);
        $display("Sync detections:      %0d", sync_count);

        // Find payload alignment in collected demod stream.
        // Sync_index points to peak (end of preamble) in the rx_dn sample numbering,
        // but rx_total/demod stream may have different starting offset due to
        // demod pipeline delay. Search a wide window.
        begin
            automatic int best_offset = -1;
            automatic int best_errors = N_PAYLOAD + 1;

            for (int off = 0; off + N_PAYLOAD <= rx_total; off++) begin
                automatic int e = 0;
                for (int i = 0; i < N_PAYLOAD; i++) begin
                    if (rx_bit_mem[off + i] !== tx_bit_mem[i])
                        e++;
                end
                if (e < best_errors) begin
                    best_errors = e;
                    best_offset = off;
                end
            end

            if (best_offset >= 0)
                $display("Best alignment: offset=%0d, errors=%0d / %0d",
                         best_offset, best_errors, N_PAYLOAD);

            // 2 sync detections expected: real frame + dummy flush frame
            if (sync_count >= 1 && best_errors == 0)
                $display("PASS: End-to-end (with FIR) BER = 0/%0d!", N_PAYLOAD);
            else if (sync_count == 0)
                $display("FAIL: No frame sync detected");
            else
                $display("FAIL: %0d bit errors at best offset %0d",
                         best_errors, best_offset);
        end

        $finish;
    end

    initial begin
        #20000000;
        $display("TIMEOUT! rx_total=%0d", rx_total);
        $finish;
    end

endmodule
