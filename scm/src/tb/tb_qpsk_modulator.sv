`timescale 1ns / 1ps

module tb_qpsk_modulator;

    parameter int W     = 16;
    parameter int SCALE = 12000;
    parameter int N_VEC = 20;

    logic                clk, rst_n;
    logic [1:0]          in_data;
    logic                in_valid, in_ready;
    logic signed [W-1:0] out_i, out_q;
    logic                out_valid, out_ready;

    // Test vectors from Python
    logic [7:0] tv_bits   [0:N_VEC-1];
    logic signed [W-1:0] tv_mod_i [0:N_VEC-1];
    logic signed [W-1:0] tv_mod_q [0:N_VEC-1];

    qpsk_modulator #(.W(W), .SCALE(SCALE)) dut (.*);

    // Clock: 10ns period
    initial clk = 0;
    always #5 clk = ~clk;

    // Load test vectors
    initial begin
        $readmemh("tv_tx_bits.hex", tv_bits);
        $readmemh("tv_mod_i.hex", tv_mod_i);
        $readmemh("tv_mod_q.hex", tv_mod_q);
    end

    int tx_cnt, rx_cnt;
    int errors;

    initial begin
        $display("=== QPSK Modulator Testbench ===");
        rst_n     = 0;
        in_valid  = 0;
        in_data   = 0;
        out_ready = 1;
        tx_cnt    = 0;
        rx_cnt    = 0;
        errors    = 0;

        repeat(5) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // Drive input bits
        fork
            // TX driver
            begin
                for (int i = 0; i < N_VEC; i++) begin
                    @(posedge clk);
                    in_data  <= tv_bits[i][1:0];
                    in_valid <= 1;
                    // Wait for handshake
                    do @(posedge clk); while (!in_ready);
                    in_valid <= 0;
                end
            end

            // RX checker
            begin
                for (int i = 0; i < N_VEC; i++) begin
                    // Wait for valid output
                    do @(posedge clk); while (!out_valid);

                    if (out_i !== tv_mod_i[i] || out_q !== tv_mod_q[i]) begin
                        $display("ERROR [%0d]: I=%0d (exp %0d), Q=%0d (exp %0d)",
                                 i, out_i, tv_mod_i[i], out_q, tv_mod_q[i]);
                        errors++;
                    end else begin
                        $display("  OK  [%0d]: I=%6d  Q=%6d", i, out_i, out_q);
                    end
                    @(posedge clk);
                end
            end
        join

        repeat(5) @(posedge clk);

        if (errors == 0)
            $display("PASS: All %0d vectors matched!", N_VEC);
        else
            $display("FAIL: %0d errors out of %0d", errors, N_VEC);

        $finish;
    end

    // Timeout
    initial begin
        #100000;
        $display("TIMEOUT!");
        $finish;
    end

endmodule
