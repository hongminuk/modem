`timescale 1ns / 1ps

module tb_qpsk_demodulator;

    parameter int W     = 16;
    parameter int N_VEC = 36;  // 16 preamble + 20 payload

    logic                    clk, rst_n;
    logic signed [W-1:0]     in_i, in_q;
    logic                    in_valid, in_ready;
    logic [1:0]              out_data;
    logic                    out_valid, out_ready;

    // Test vectors: frame symbols (preamble + payload) and expected demod bits
    logic signed [W-1:0] tv_frame_i [0:N_VEC-1];
    logic signed [W-1:0] tv_frame_q [0:N_VEC-1];
    logic [7:0]          tv_demod   [0:N_VEC-1];

    qpsk_demodulator #(.W(W)) dut (.*);

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        $readmemh("tv_frame_i.hex", tv_frame_i);
        $readmemh("tv_frame_q.hex", tv_frame_q);
        $readmemh("tv_demod_bits.hex", tv_demod);
    end

    int errors;

    initial begin
        $display("=== QPSK Demodulator Testbench ===");
        rst_n     = 0;
        in_valid  = 0;
        in_i      = 0;
        in_q      = 0;
        out_ready = 1;
        errors    = 0;

        repeat(5) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        fork
            // Drive symbols
            begin
                for (int i = 0; i < N_VEC; i++) begin
                    @(posedge clk);
                    in_i     <= tv_frame_i[i];
                    in_q     <= tv_frame_q[i];
                    in_valid <= 1;
                    do @(posedge clk); while (!in_ready);
                    in_valid <= 0;
                end
            end

            // Check output
            begin
                for (int i = 0; i < N_VEC; i++) begin
                    do @(posedge clk); while (!out_valid);

                    if (out_data !== tv_demod[i][1:0]) begin
                        $display("ERROR [%0d]: got %b (exp %b) | I=%6d Q=%6d",
                                 i, out_data, tv_demod[i][1:0], tv_frame_i[i], tv_frame_q[i]);
                        errors++;
                    end else begin
                        $display("  OK  [%0d]: bits=%b  (I=%6d, Q=%6d)",
                                 i, out_data, tv_frame_i[i], tv_frame_q[i]);
                    end
                    @(posedge clk);
                end
            end
        join

        repeat(5) @(posedge clk);

        if (errors == 0)
            $display("PASS: All %0d symbols demodulated correctly!", N_VEC);
        else
            $display("FAIL: %0d errors out of %0d", errors, N_VEC);

        $finish;
    end

    initial begin
        #100000;
        $display("TIMEOUT!");
        $finish;
    end

endmodule
