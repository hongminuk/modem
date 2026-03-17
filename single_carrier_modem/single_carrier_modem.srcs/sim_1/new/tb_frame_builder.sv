`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 02/11/2026 12:20:27 PM
// Design Name: 
// Module Name: tb_frame_builder
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module tb_frame_builder;

localparam int W = 16;
localparam int PREAMBLE_LEN = 16;

// Clock and Reset
logic clk, rst_n;

initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;  //100MHz
end

initial begin
    rst_n = 1'b0;
    repeat (20) @(posedge clk);
    rst_n = 1'b1;
end

// DUT signals
logic                in_frame_start;
logic [15:0]         in_payload_len;
logic signed [W-1:0] in_i, in_q;
logic                in_valid, in_ready;
logic signed [W-1:0] out_i, out_q;
logic                out_valid, out_ready;

// DUT instantiation
frame_builder #(
    .W(W),
    .PREAMBLE_LEN(PREAMBLE_LEN)
) dut (
    .clk(clk),
    .rst_n(rst_n),
    .in_frame_start(in_frame_start),
    .in_payload_len(in_payload_len),
    .in_i(in_i),
    .in_q(in_q),
    .in_valid(in_valid),
    .in_ready(in_ready),
    .out_i(out_i),
    .out_q(out_q),
    .out_valid(out_valid),
    .out_ready(out_ready)
);

// Output ready (always ready for this simple test)
initial begin
    out_ready = 1'b1;
end

// Counters
int out_cnt;
int preamble_received;
int payload_received;

// Monitor output
always_ff @(posedge clk) begin
    if (!rst_n) begin
        out_cnt             <= 0;
        preamble_received   <= 0;
        payload_received    <= 0;
    end else begin
        if (out_valid && out_ready) begin
            out_cnt <= out_cnt + 1;
            
            // First 16 symbols should be preamble
            if (out_cnt < PREAMBLE_LEN) begin
                preamble_received <= preamble_received + 1;
                $display("[%0t] PREAMBLE #%0d: I=%0d, Q=%0d", 
                    $time, preamble_received, out_i, out_q);
            end else begin
                payload_received <= payload_received + 1;
                $display("[%0t] PAYLOAD #%0d: I=%0d, Q=%0d",
                    $time, payload_received, out_i, out_q);
            end
        end
    end
end

// Stimulus
initial begin
    in_frame_start  = 1'b0;
    in_payload_len  = 16'd0;
    in_i            = '0;
    in_q            = '0;
    in_valid        = 1'b0;
    
    wait(rst_n);
    repeat (10) @(posedge clk);
    
    //// Test 1: Send one frame with 10 payload symbols
    $display("\n=== Test 1: Frame with 10 payload symbols ===");

    // Start frame
    @(posedge clk);
    in_frame_start <= 1'b1;
    in_payload_len <= 16'd10;
    @(posedge clk);
    in_frame_start <= 1'b0;
    
    // Wait for preamble to be sent
    wait(preamble_received == PREAMBLE_LEN);
    $display("Preamble transmission complete!");
    
    // Now send 10 payload symbols
    for (int k = 0; k < 10; k++) begin
        @(posedge clk);
        in_i     <= 16'sd12000;      //signed decimal / Fixed pattern for now
        in_q     <= 16'sd12000;
        in_valid <= 1'b1;
        
        // Wait until accepted
        wait(in_valid && in_ready);
        @(posedge clk);
        in_valid <= 1'b0;
    end
    
    $display("Payload transmission complete!");
    
    repeat (20) @(posedge clk);
    
    //// Test 2: Send another frame with random QPSK payload
    $display("\n=== Test 2: Frame with 20 random QPSK symbols ===");

    // Wait for preamble
    wait(preamble_received == PREAMBLE_LEN);

    // Note: Counters continues from previous test = this is OK for debugging
    // In real system, you'd reset based on frame boundaries 
    
    // Reset counters for clarity    
//    out_cnt = 0;
//    preamble_received = 0;
//    payload_received = 0;
    
    // Start frame
    @(posedge clk);
    in_frame_start <= 1'b1;
    in_payload_len <= 16'd20;
    @(posedge clk);
    in_frame_start <= 1'b0;
    
    // Wait for preamble
    wait(preamble_received == PREAMBLE_LEN);
    
    // Send 20 random QPSK symbols
    for (int k=0; k < 20; k++) begin
        logic b0, b1;
        
        b0 = $urandom_range(0,1);
        b1 = $urandom_range(0,1);
        
        @(posedge clk);
        in_i        <= b0 ? -16'sd12000 : 16'sd12000;
        in_q        <= b1 ? -16'sd12000 : 16'sd12000;
        in_valid    <= 1'b1;
        
        wait(in_valid && in_valid);
        @(posedge clk);
        in_valid <= 1'b0;        
    end
    
    repeat (20) @(posedge clk);
    
    $display("\n=== Frame Builder Test Complete ===");
    $finish;
end

endmodule
