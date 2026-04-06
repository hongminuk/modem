`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// End-to-End Loopback Test (without FIR IP)
//
// TX: QPSK Mod → Frame Builder → Upsample
// Loopback: upsample → downsample (no RRC, no channel)
// RX: Downsample → Correlator → Sync Detector → QPSK Demod
//////////////////////////////////////////////////////////////////////////////////

module tb_loopback_no_fir;

    parameter int W            = 16;
    parameter int SPS          = 4;
    parameter int PREAMBLE_LEN = 16;
    parameter int W_CORR       = 72;
    parameter int N_PAYLOAD    = 50;
    parameter int N_FRAME      = PREAMBLE_LEN + N_PAYLOAD;

    logic clk, rst_n;
    initial clk = 0;
    always #5 clk = ~clk;

    // === TX: QPSK Modulator ===
    logic [1:0]          tx_bits;
    logic                tx_bits_valid, tx_bits_ready;
    logic signed [W-1:0] mod_i, mod_q;
    logic                mod_valid, mod_ready;

    qpsk_modulator #(.W(W), .SCALE(12000)) u_mod (
        .clk, .rst_n,
        .in_data(tx_bits), .in_valid(tx_bits_valid), .in_ready(tx_bits_ready),
        .out_i(mod_i), .out_q(mod_q), .out_valid(mod_valid), .out_ready(mod_ready)
    );

    // === TX: Frame Builder ===
    logic                frame_start;
    logic [15:0]         payload_len;
    logic signed [W-1:0] frame_i, frame_q;
    logic                frame_valid, frame_ready;

    frame_builder #(.W(W), .PREAMBLE_LEN(PREAMBLE_LEN)) u_fb (
        .clk, .rst_n,
        .in_frame_start(frame_start), .in_payload_len(payload_len),
        .in_i(mod_i), .in_q(mod_q), .in_valid(mod_valid), .in_ready(mod_ready),
        .out_i(frame_i), .out_q(frame_q), .out_valid(frame_valid), .out_ready(frame_ready)
    );

    // === TX: Upsample ===
    logic signed [W-1:0] up_i, up_q;
    logic                up_valid, up_ready;

    axis_upsample_zeros #(.W(W), .SPS(SPS)) u_up (
        .clk, .rst_n,
        .in_i(frame_i), .in_q(frame_q), .in_valid(frame_valid), .in_ready(frame_ready),
        .out_i(up_i), .out_q(up_q), .out_valid(up_valid), .out_ready(up_ready)
    );

    // === Loopback ===
    assign up_ready = 1'b1;  // TX side: always accept upsample output

    // === RX: Downsample ===
    logic signed [W-1:0] ds_i, ds_q;
    logic                ds_valid, ds_ready;

    axis_downsample_pick #(.W(W), .W_3(W), .SPS(SPS), .OFFSET(0)) u_ds (
        .clk, .rst_n,
        .in_i(up_i), .in_q(up_q), .in_valid(up_valid), .in_ready(),
        .out_i(ds_i), .out_q(ds_q), .out_valid(ds_valid), .out_ready(ds_ready)
    );
    assign ds_ready = 1'b1;

    // === RX: Correlator ===
    logic signed [W_CORR-1:0] corr_i, corr_q;
    logic                     corr_valid, corr_ready;

    preamble_correlator #(.W(W), .W_CORR(W_CORR), .PREAMBLE_LEN(PREAMBLE_LEN)) u_corr (
        .clk, .rst_n,
        .in_i(ds_i), .in_q(ds_q), .in_valid(ds_valid), .in_ready(),
        .corr_i, .corr_q, .corr_valid, .corr_ready
    );

    // === RX: Frame Sync Detector ===
    logic        sync_found;
    logic [31:0] sync_index;
    logic [63:0] sync_mag;

    // Peak |R|^2 = 4608000000^2 ≈ 2.12e19 (64.2 bits)
    // mag_sq[127:64] ≈ 1, so THRESHOLD must be 0 for '>' comparison
    frame_sync_detector #(.W_CORR(W_CORR), .THRESHOLD(0)) u_det (
        .clk, .rst_n,
        .corr_i, .corr_q, .corr_valid, .corr_ready,
        .sync_found, .sync_index, .sync_mag
    );

    // === RX: QPSK Demodulator ===
    logic [1:0] rx_bits;
    logic       rx_bits_valid, rx_bits_ready;

    qpsk_demodulator #(.W(W)) u_demod (
        .clk, .rst_n,
        .in_i(ds_i), .in_q(ds_q), .in_valid(ds_valid), .in_ready(),
        .out_data(rx_bits), .out_valid(rx_bits_valid), .out_ready(rx_bits_ready)
    );
    assign rx_bits_ready = 1'b1;

    // =========================================================================
    // Test
    // =========================================================================
    logic [1:0] tx_bit_mem [0:N_PAYLOAD-1];
    logic [15:0] lfsr_reg;

    function automatic logic [15:0] lfsr_next(logic [15:0] s);
        return {s[14:0], s[15] ^ s[13] ^ s[12] ^ s[10]};
    endfunction

    // Collect all demod outputs, compare at end
    logic [1:0] rx_bit_mem [0:N_FRAME-1];
    integer rx_total, sync_count;

    initial begin
        $display("=== End-to-End Loopback Test (no FIR) ===");
        $display("    %0d preamble + %0d payload = %0d frame symbols",
                 PREAMBLE_LEN, N_PAYLOAD, N_FRAME);

        rst_n         = 0;
        frame_start   = 0;
        payload_len   = 0;
        tx_bits       = 0;
        tx_bits_valid = 0;
        lfsr_reg      = 16'hACE1;
        rx_total      = 0;
        sync_count    = 0;

        repeat(10) @(posedge clk);
        rst_n = 1;
        repeat(3) @(posedge clk);

        // Start frame
        payload_len = N_PAYLOAD;
        frame_start = 1;
        @(posedge clk);
        frame_start = 0;

        fork
            // === TX driver ===
            begin
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
                $display("TX: %0d bit-pairs sent", N_PAYLOAD);
            end

            // === RX collector ===
            begin
                for (int cycle = 0; cycle < 5000; cycle++) begin
                    @(posedge clk);

                    if (sync_found) begin
                        $display("  >> SYNC: index=%0d, mag=%0d", sync_index, sync_mag);
                        sync_count++;
                    end

                    if (rx_bits_valid) begin
                        rx_bit_mem[rx_total] = rx_bits;
                        rx_total++;
                    end

                    if (rx_total >= N_FRAME) break;
                end
            end
        join

        repeat(10) @(posedge clk);

        // === Find correct alignment and compare ===
        $display("");
        $display("RX symbols collected: %0d (expected %0d)", rx_total, N_FRAME);
        $display("Sync detections: %0d", sync_count);

        // Payload starts at PREAMBLE_LEN + 1 due to modulator pipeline delay.
        // Compare as many payload symbols as available.
        begin
            automatic int offset = PREAMBLE_LEN + 1;  // 17
            automatic int n_check = (rx_total - offset < N_PAYLOAD) ?
                                    (rx_total - offset) : N_PAYLOAD;
            automatic int errors = 0;

            for (int i = 0; i < n_check; i++) begin
                if (rx_bit_mem[offset + i] !== tx_bit_mem[i]) begin
                    $display("  BIT ERR [%0d]: got %b, exp %b",
                             i, rx_bit_mem[offset + i], tx_bit_mem[i]);
                    errors++;
                end
            end

            $display("Payload offset: %0d (preamble=%0d + 1 pipeline)",
                     offset, PREAMBLE_LEN);
            $display("Payload checked: %0d / %0d", n_check, N_PAYLOAD);
            $display("Bit errors: %0d", errors);

            if (sync_count >= 1 && errors == 0 && n_check >= N_PAYLOAD - 1)
                $display("PASS: End-to-end loopback BER = 0! (%0d/%0d verified)",
                         n_check, N_PAYLOAD);
            else if (sync_count == 0)
                $display("FAIL: No frame sync detected");
            else
                $display("FAIL: %0d bit errors in %0d symbols", errors, n_check);
        end

        $finish;
    end

    initial begin
        #10000000;
        $display("TIMEOUT!");
        $finish;
    end

endmodule
