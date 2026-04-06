`timescale 1ns / 1ps

module tb_axis_downsample_pick;

    parameter int W      = 16;
    parameter int W_3    = 16;   // Use 16-bit for this test (no RRC widening)
    parameter int SPS    = 4;
    parameter int OFFSET = 0;
    parameter int N_SAMP = 144;  // upsampled input
    parameter int N_SYM  = 36;   // expected output symbols

    logic                  clk, rst_n;
    logic signed [W_3-1:0] in_i, in_q;
    logic                  in_valid, in_ready;
    logic signed [W_3-1:0] out_i, out_q;
    logic                  out_valid, out_ready;

    // Test vectors
    logic signed [W_3-1:0] tv_in_i  [0:N_SAMP-1];
    logic signed [W_3-1:0] tv_in_q  [0:N_SAMP-1];
    logic signed [W_3-1:0] tv_out_i [0:N_SYM-1];
    logic signed [W_3-1:0] tv_out_q [0:N_SYM-1];

    axis_downsample_pick #(
        .W(W), .W_3(W_3), .SPS(SPS), .OFFSET(OFFSET)
    ) dut (.*);

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        $readmemh("tv_up_out_i.hex", tv_in_i);    // upsampled as input
        $readmemh("tv_up_out_q.hex", tv_in_q);
        $readmemh("tv_ds_out_i.hex", tv_out_i);   // original symbols as expected
        $readmemh("tv_ds_out_q.hex", tv_out_q);
    end

    int rx_cnt, errors;

    initial begin
        $display("=== Downsample Pick Testbench (SPS=%0d, OFFSET=%0d) ===", SPS, OFFSET);
        rst_n     = 0;
        in_valid  = 0;
        in_i      = 0;
        in_q      = 0;
        out_ready = 1;
        errors    = 0;
        rx_cnt    = 0;

        repeat(5) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        fork
            // Drive upsampled samples
            begin
                for (int i = 0; i < N_SAMP; i++) begin
                    @(posedge clk);
                    in_i     <= tv_in_i[i];
                    in_q     <= tv_in_q[i];
                    in_valid <= 1;
                    do @(posedge clk); while (!in_ready);
                    in_valid <= 0;
                end
            end

            // Check downsampled output
            begin
                while (rx_cnt < N_SYM) begin
                    @(posedge clk);
                    if (out_valid && out_ready) begin
                        if (out_i !== tv_out_i[rx_cnt] || out_q !== tv_out_q[rx_cnt]) begin
                            $display("  ERROR [%0d]: I=%0d (exp %0d), Q=%0d (exp %0d)",
                                     rx_cnt, out_i, tv_out_i[rx_cnt], out_q, tv_out_q[rx_cnt]);
                            errors++;
                        end else begin
                            if (rx_cnt < 4 || rx_cnt == N_SYM-1)
                                $display("  OK  [%0d]: I=%6d  Q=%6d", rx_cnt, out_i, out_q);
                        end
                        rx_cnt++;
                    end
                end
            end
        join

        repeat(5) @(posedge clk);

        if (errors == 0)
            $display("PASS: All %0d downsampled symbols correct! (÷%0d, offset=%0d)",
                     N_SYM, SPS, OFFSET);
        else
            $display("FAIL: %0d errors out of %0d", errors, N_SYM);

        $finish;
    end

    initial begin
        #500000;
        $display("TIMEOUT! rx_cnt=%0d", rx_cnt);
        $finish;
    end

endmodule
