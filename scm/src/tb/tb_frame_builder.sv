`timescale 1ns / 1ps

module tb_frame_builder;

    parameter int W            = 16;
    parameter int PREAMBLE_LEN = 16;
    parameter int N_PAYLOAD    = 20;
    parameter int N_FRAME      = 36;  // PREAMBLE_LEN + N_PAYLOAD

    logic                clk, rst_n;
    logic                in_frame_start;
    logic [15:0]         in_payload_len;
    logic signed [W-1:0] in_i, in_q;
    logic                in_valid, in_ready;
    logic signed [W-1:0] out_i, out_q;
    logic                out_valid, out_ready;

    // Test vectors
    logic signed [W-1:0] tv_payload_i [0:N_PAYLOAD-1];
    logic signed [W-1:0] tv_payload_q [0:N_PAYLOAD-1];
    logic signed [W-1:0] tv_frame_i   [0:N_FRAME-1];
    logic signed [W-1:0] tv_frame_q   [0:N_FRAME-1];

    frame_builder #(.W(W), .PREAMBLE_LEN(PREAMBLE_LEN)) dut (.*);

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        $readmemh("tv_fb_payload_i.hex", tv_payload_i);
        $readmemh("tv_fb_payload_q.hex", tv_payload_q);
        $readmemh("tv_fb_out_i.hex", tv_frame_i);
        $readmemh("tv_fb_out_q.hex", tv_frame_q);
    end

    int rx_cnt, errors;

    initial begin
        $display("=== Frame Builder Testbench ===");
        rst_n          = 0;
        in_frame_start = 0;
        in_payload_len = 0;
        in_valid       = 0;
        in_i           = 0;
        in_q           = 0;
        out_ready      = 1;
        errors         = 0;
        rx_cnt         = 0;

        repeat(5) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // Trigger frame start
        in_payload_len = N_PAYLOAD;
        in_frame_start = 1;
        @(posedge clk);
        in_frame_start = 0;

        fork
            // TX: Feed payload symbols (frame_builder pulls them after preamble)
            begin
                int tx_idx = 0;
                while (tx_idx < N_PAYLOAD) begin
                    @(posedge clk);
                    in_i     <= tv_payload_i[tx_idx];
                    in_q     <= tv_payload_q[tx_idx];
                    in_valid <= 1;
                    @(posedge clk);
                    if (in_ready) begin
                        tx_idx++;
                    end
                    in_valid <= 0;
                end
            end

            // RX: Check output (preamble + payload)
            begin
                while (rx_cnt < N_FRAME) begin
                    @(posedge clk);
                    if (out_valid && out_ready) begin
                        if (out_i !== tv_frame_i[rx_cnt] || out_q !== tv_frame_q[rx_cnt]) begin
                            $display("  ERROR [%0d]: I=%0d (exp %0d), Q=%0d (exp %0d)",
                                     rx_cnt, out_i, tv_frame_i[rx_cnt], out_q, tv_frame_q[rx_cnt]);
                            errors++;
                        end else begin
                            if (rx_cnt < 4 || rx_cnt == PREAMBLE_LEN || rx_cnt == N_FRAME-1)
                                $display("  OK  [%0d]: I=%6d  Q=%6d  %s",
                                         rx_cnt, out_i, out_q,
                                         rx_cnt < PREAMBLE_LEN ? "(preamble)" : "(payload)");
                        end
                        rx_cnt++;
                    end
                end
            end
        join

        repeat(5) @(posedge clk);

        if (errors == 0)
            $display("PASS: All %0d frame symbols correct! (%0d preamble + %0d payload)",
                     N_FRAME, PREAMBLE_LEN, N_PAYLOAD);
        else
            $display("FAIL: %0d errors out of %0d", errors, N_FRAME);

        $finish;
    end

    initial begin
        #500000;
        $display("TIMEOUT! rx_cnt=%0d", rx_cnt);
        $finish;
    end

endmodule
