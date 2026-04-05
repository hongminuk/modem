`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: tb_qpsk_frame_sync_top
// Description: 
//   Testbench for complete frame sync system
//   Tests TX→RX loopback with frame detection
//////////////////////////////////////////////////////////////////////////////////

module tb_qpsk_frame_sync_top;

    // Parameters (match DUT)
    localparam int W              = 16;
    localparam int W_2            = 40;
    localparam int W_3            = 56;
    localparam int SPS            = 4;
    localparam int OFFSET         = 0;
    localparam int PREAMBLE_LEN   = 16;
    localparam int W_CORR         = 72;
    localparam longint SYNC_THRESHOLD = 64'd500000000;
    
    // Clock and reset
    logic clk, rst_n;
    
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;  // 100MHz
    end
    
    initial begin
        rst_n = 1'b0;
        repeat (20) @(posedge clk);
        rst_n = 1'b1;
    end
    
    // =========================================================================
    // DUT Signals
    // =========================================================================
    // TX Side
    logic                tx_frame_start;
    logic [15:0]         tx_payload_len;
    logic signed [W-1:0] tx_payload_i, tx_payload_q;
    logic                tx_payload_valid, tx_payload_ready;
    logic signed [W_2-1:0] tx_out_i, tx_out_q;
    logic                  tx_out_valid, tx_out_ready;
    
    // RX Side
    logic signed [W_2-1:0] rx_in_i, rx_in_q;
    logic                  rx_in_valid, rx_in_ready;
    logic signed [W_3-1:0] rx_out_i, rx_out_q;
    logic                  rx_out_valid, rx_out_ready;
    logic                  rx_sync_found;
    logic [31:0]           rx_sync_index;
    logic [63:0]           rx_sync_mag;
    
    // =========================================================================
    // DUT Instantiation
    // =========================================================================
    qpsk_frame_sync_top #(
        .W(W),
        .W_2(W_2),
        .W_3(W_3),
        .SPS(SPS),
        .OFFSET(OFFSET),
        .PREAMBLE_LEN(PREAMBLE_LEN),
        .W_CORR(W_CORR),
        .SYNC_THRESHOLD(SYNC_THRESHOLD)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        
        // TX
        .tx_frame_start(tx_frame_start),
        .tx_payload_len(tx_payload_len),
        .tx_payload_i(tx_payload_i),
        .tx_payload_q(tx_payload_q),
        .tx_payload_valid(tx_payload_valid),
        .tx_payload_ready(tx_payload_ready),
        .tx_out_i(tx_out_i),
        .tx_out_q(tx_out_q),
        .tx_out_valid(tx_out_valid),
        .tx_out_ready(tx_out_ready),
        
        // RX
        .rx_in_i(rx_in_i),
        .rx_in_q(rx_in_q),
        .rx_in_valid(rx_in_valid),
        .rx_in_ready(rx_in_ready),
        .rx_out_i(rx_out_i),
        .rx_out_q(rx_out_q),
        .rx_out_valid(rx_out_valid),
        .rx_out_ready(rx_out_ready),
        .rx_sync_found(rx_sync_found),
        .rx_sync_index(rx_sync_index),
        .rx_sync_mag(rx_sync_mag)
    );
    
    // =========================================================================
    // Loopback Connection (TX → RX)
    // =========================================================================
    // Direct connection for ideal channel test
    assign rx_in_i     = tx_out_i;
    assign rx_in_q     = tx_out_q;
    assign rx_in_valid = tx_out_valid;
    assign tx_out_ready = rx_in_ready;
    
    // RX output ready
    assign rx_out_ready = 1'b1;
    
    // =========================================================================
    // Monitoring
    // =========================================================================
    int tx_frame_count;
    int tx_payload_count;
    int rx_sync_count;
    int rx_symbol_count;
    
    // Monitor TX
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            tx_frame_count   <= 0;
            tx_payload_count <= 0;
        end else begin
            if (tx_frame_start) begin
                tx_frame_count <= tx_frame_count + 1;
                $display("[%0t] TX: Starting Frame #%0d with %0d payload symbols", 
                         $time, tx_frame_count + 1, tx_payload_len);
            end
            
            if (tx_payload_valid && tx_payload_ready) begin
                tx_payload_count <= tx_payload_count + 1;
            end
        end
    end
    
    // Monitor RX Sync
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            rx_sync_count <= 0;
        end else begin
            if (rx_sync_found) begin
                rx_sync_count <= rx_sync_count + 1;
                $display("[%0t] RX: *** SYNC FOUND #%0d *** Index=%0d, Mag=%0d", 
                         $time, rx_sync_count + 1, rx_sync_index, rx_sync_mag);
            end
        end
    end
    
    // Monitor RX Symbols
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            rx_symbol_count <= 0;
        end else begin
            if (rx_out_valid && rx_out_ready) begin
                rx_symbol_count <= rx_symbol_count + 1;
                if (rx_symbol_count < 20 || rx_symbol_count % 50 == 0) begin
                    $display("[%0t] RX Symbol #%0d: I=%0d, Q=%0d", 
                             $time, rx_symbol_count, rx_out_i, rx_out_q);
                end
            end
        end
    end
    
    // =========================================================================
    // Stimulus Task
    // =========================================================================
    task automatic send_payload_symbol(input logic signed [W-1:0] I, Q);
        begin
            @(posedge clk);
            tx_payload_i     <= I;
            tx_payload_q     <= Q;
            tx_payload_valid <= 1'b1;
            
            // Wait until accepted
            do @(posedge clk);
            while (!(tx_payload_valid && tx_payload_ready));
            
            tx_payload_valid <= 1'b0;
        end
    endtask
    
    // =========================================================================
    // Main Test Stimulus
    // =========================================================================
    initial begin
        // Initialize
        tx_frame_start   = 1'b0;
        tx_payload_len   = 16'd0;
        tx_payload_i     = '0;
        tx_payload_q     = '0;
        tx_payload_valid = 1'b0;
        
        wait(rst_n);
        repeat (50) @(posedge clk);
        
        $display("\n========================================");
        $display("QPSK Frame Sync System Test");
        $display("========================================\n");
        
        // =====================================================================
        // Test 1: Single frame with 20 payload symbols
        // =====================================================================
        $display("Test 1: Sending frame with 20 payload symbols");
        
        @(posedge clk);
        tx_frame_start <= 1'b1;             // frame start !
        tx_payload_len <= 16'd20;           // 20 payloads
        @(posedge clk);
        tx_frame_start <= 1'b0;             // 
        
        // Send 20 random QPSK symbols
        for (int k = 0; k < 20; k++) begin
            logic b0, b1;
            b0 = $urandom_range(0,1);
            b1 = $urandom_range(0,1);
            
            send_payload_symbol(
                b0 ? -16'sd12000 : 16'sd12000,
                b1 ? -16'sd12000 : 16'sd12000
            );
        end
        
        // Wait for processing
        repeat (200) @(posedge clk);
        
        // =====================================================================
        // Test 2: Multiple frames
        // =====================================================================
        $display("\nTest 2: Sending 3 consecutive frames");
        
        for (int frame = 0; frame < 3; frame++) begin
            int num_payload = 15 + frame * 5;  // 15, 20, 25 symbols
            
            @(posedge clk);
            tx_frame_start <= 1'b1;
            tx_payload_len <= num_payload;
            @(posedge clk);
            tx_frame_start <= 1'b0;
            
            // Send payload
            for (int k = 0; k < num_payload; k++) begin
                logic b0, b1;
                b0 = $urandom_range(0,1);
                b1 = $urandom_range(0,1);
                
                send_payload_symbol(
                    b0 ? -16'sd12000 : 16'sd12000,
                    b1 ? -16'sd12000 : 16'sd12000
                );
            end
            
            // Gap between frames
            repeat (100) @(posedge clk);
        end
        
        // Wait for pipeline to flush
        repeat (500) @(posedge clk);
        
        // =====================================================================
        // Summary
        // =====================================================================
        $display("\n========================================");
        $display("Test Summary");
        $display("========================================");
        $display("TX Frames transmitted: %0d", tx_frame_count);
        $display("TX Payload symbols:    %0d", tx_payload_count);
        $display("RX Syncs detected:     %0d", rx_sync_count);
        $display("RX Symbols received:   %0d", rx_symbol_count);
        
        if (rx_sync_count == tx_frame_count) begin
            $display("\n*** SUCCESS: All frames detected! ***");
        end else begin
            $display("\n*** WARNING: Frame detection mismatch! ***");
            $display("Expected: %0d, Got: %0d", tx_frame_count, rx_sync_count);
            $display("Consider adjusting SYNC_THRESHOLD.");
        end
        
        $display("\n========================================");
        $finish;
    end
    
    // Timeout watchdog
    initial begin
        #2000000;  // 2ms timeout
        $display("\nERROR: Simulation timeout!");
        $finish;
    end

endmodule