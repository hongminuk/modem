`timescale 1ns / 1ps

module tb_frame_sync_detector;

    parameter int W_CORR    = 72;
    // mag_sq = corr_i^2 + corr_q^2 (128-bit). Detector compares mag_sq[127:64] > THRESHOLD.
    // Peak: 4608000000^2 ≈ 2.12e19 → upper 64 bits ≈ 1
    // Noise: 50^2 + 40^2 = 4100 → upper 64 bits = 0
    parameter int THRESHOLD = 32'd0;  // Any nonzero upper bits triggers
    parameter int N_VEC     = 36;

    logic                     clk, rst_n;
    logic signed [W_CORR-1:0] corr_i, corr_q;
    logic                     corr_valid, corr_ready;
    logic                     sync_found;
    logic [31:0]              sync_index;
    logic [63:0]              sync_mag;

    frame_sync_detector #(
        .W_CORR(W_CORR),
        .THRESHOLD(THRESHOLD)
    ) dut (.*);

    initial clk = 0;
    always #5 clk = ~clk;

    // Synthesize test input: known correlation pattern with one clear peak
    // Simulate preamble correlator output: peak at index 15, small elsewhere
    logic signed [W_CORR-1:0] test_corr_i [0:N_VEC-1];
    logic signed [W_CORR-1:0] test_corr_q [0:N_VEC-1];

    initial begin
        // Initialize to small values
        for (int i = 0; i < N_VEC; i++) begin
            test_corr_i[i] = (i % 3 == 0) ? 72'sd50 : -72'sd30;
            test_corr_q[i] = (i % 5 == 0) ? -72'sd40 : 72'sd20;
        end
        // Inject peak at index 15 (simulates end of preamble)
        test_corr_i[15] = 72'sd4608000000;
        test_corr_q[15] = 72'sd0;
    end

    int sync_count;
    int first_sync_index;

    initial begin
        $display("=== Frame Sync Detector Testbench ===");
        $display("    THRESHOLD = %0d", THRESHOLD);
        rst_n      = 0;
        corr_valid = 0;
        corr_i     = 0;
        corr_q     = 0;
        sync_count = 0;
        first_sync_index = -1;

        repeat(5) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // Feed correlation values
        for (int i = 0; i < N_VEC; i++) begin
            @(posedge clk);
            corr_i     <= test_corr_i[i];
            corr_q     <= test_corr_q[i];
            corr_valid <= 1;
            @(posedge clk);
            corr_valid <= 0;

            // Check for sync detection (may appear 1-2 cycles after valid)
            repeat(3) begin
                @(posedge clk);
                if (sync_found) begin
                    $display("  SYNC at input[%0d]: sync_index=%0d, sync_mag=%0d",
                             i, sync_index, sync_mag);
                    if (first_sync_index < 0)
                        first_sync_index = sync_index;
                    sync_count++;
                end
            end
        end

        repeat(10) @(posedge clk);

        $display("");
        $display("Total sync detections: %0d", sync_count);
        $display("First sync index: %0d", first_sync_index);

        if (sync_count == 1)
            $display("PASS: Exactly 1 sync detection!");
        else if (sync_count == 0)
            $display("FAIL: No sync detected (threshold may be too high)");
        else
            $display("INFO: %0d detections (cooldown may need tuning)", sync_count);

        $finish;
    end

    initial begin
        #200000;
        $display("TIMEOUT!");
        $finish;
    end

endmodule
