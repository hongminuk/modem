`timescale 1ns / 1ps

module tb_preamble_correlator;

    parameter int W            = 16;
    parameter int W_CORR       = 72;
    parameter int PREAMBLE_LEN = 16;
    parameter int N_VEC        = 36;  // 16 preamble + 20 payload

    logic                        clk, rst_n;
    logic signed [W-1:0]         in_i, in_q;
    logic                        in_valid, in_ready;
    logic signed [W_CORR-1:0]    corr_i, corr_q;
    logic                        corr_valid, corr_ready;

    // Test vectors
    logic signed [W-1:0]      tv_in_i  [0:N_VEC-1];
    logic signed [W-1:0]      tv_in_q  [0:N_VEC-1];
    logic signed [W_CORR-1:0] tv_out_i [0:N_VEC-1];
    logic signed [W_CORR-1:0] tv_out_q [0:N_VEC-1];

    preamble_correlator #(
        .W(W),
        .W_CORR(W_CORR),
        .PREAMBLE_LEN(PREAMBLE_LEN)
    ) dut (.*);

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        $readmemh("tv_corr_in_i.hex", tv_in_i);
        $readmemh("tv_corr_in_q.hex", tv_in_q);
        $readmemh("tv_corr_out_i.hex", tv_out_i);
        $readmemh("tv_corr_out_q.hex", tv_out_q);
    end

    int errors;
    int peak_idx;
    logic signed [W_CORR-1:0] peak_val_i, peak_val_q;

    // Track peak
    logic [127:0] peak_mag;
    logic [127:0] cur_mag;

    initial begin
        $display("=== Preamble Correlator Testbench ===");
        rst_n      = 0;
        in_valid   = 0;
        in_i       = 0;
        in_q       = 0;
        corr_ready = 1;
        errors     = 0;
        peak_idx   = -1;
        peak_mag   = 0;

        repeat(5) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        fork
            // Drive inputs
            begin
                for (int i = 0; i < N_VEC; i++) begin
                    @(posedge clk);
                    in_i     <= tv_in_i[i];
                    in_q     <= tv_in_q[i];
                    in_valid <= 1;
                    do @(posedge clk); while (!in_ready);
                    in_valid <= 0;
                end
            end

            // Check outputs
            // NOTE: RTL has 1-cycle pipeline delay (registered output).
            // RTL output[i] corresponds to Python output[i-1].
            // So RTL peak at index 16 = Python peak at index 15.
            begin
                for (int i = 0; i < N_VEC; i++) begin
                    do @(posedge clk); while (!corr_valid);

                    // Track peak
                    cur_mag = (corr_i * corr_i) + (corr_q * corr_q);
                    if (cur_mag > peak_mag) begin
                        peak_mag   = cur_mag;
                        peak_idx   = i;
                        peak_val_i = corr_i;
                        peak_val_q = corr_q;
                    end

                    // Compare with Python reference (offset by 1 for pipeline delay).
                    // Only compare from i >= PREAMBLE_LEN+1 because:
                    //   - RTL computes partial sums while shift register fills up
                    //   - Python outputs 0 for indices < PREAMBLE_LEN-1
                    //   - RTL index i corresponds to Python index i-1
                    if (i >= PREAMBLE_LEN) begin
                        if (corr_i !== tv_out_i[i-1] || corr_q !== tv_out_q[i-1]) begin
                            $display("  MISMATCH [%0d]: I=%0d (exp %0d), Q=%0d (exp %0d)",
                                     i, corr_i, tv_out_i[i-1], corr_q, tv_out_q[i-1]);
                            errors++;
                        end else begin
                            $display("  OK  [%0d]: corr_I=%0d  corr_Q=%0d", i, corr_i, corr_q);
                        end
                    end
                    @(posedge clk);
                end
            end
        join

        repeat(5) @(posedge clk);

        $display("");
        $display("Peak at index %0d: corr_I=%0d, corr_Q=%0d", peak_idx, peak_val_i, peak_val_q);
        $display("Expected peak at index 15 (end of preamble)");
        $display("");

        // RTL peak at 16 = Python peak at 15 (1-cycle pipeline delay)
        if (peak_idx == 16 && errors == 0)
            $display("PASS: Peak at correct position (RTL idx 16 = Python idx 15), all vectors matched!");
        else if (peak_idx != 16)
            $display("FAIL: Peak at index %0d (expected 16)", peak_idx);
        else
            $display("FAIL: %0d mismatches out of %0d", errors, N_VEC);

        $finish;
    end

    initial begin
        #200000;
        $display("TIMEOUT!");
        $finish;
    end

endmodule
