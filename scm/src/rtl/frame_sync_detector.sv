`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: frame_sync_detector
// Description: 
//   Detects frame synchronization by finding peak in correlation output
//   
//   Algorithm:
//   1. Compute correlation magnitude: |R|² = R_I² + R_Q²
//   2. Find local maximum (peak detection)
//   3. Compare against threshold
//   4. Output sync pulse when peak > threshold
//   
//   Output:
//   - sync_found: pulse when frame is detected
//   - sync_index: position of the peak (for debugging/verification)
//   - sync_mag: magnitude of the peak (for SNR estimation)
//
// Parameters:
//   W_CORR    : Correlation input bit width
//   THRESHOLD : Detection threshold (can be adaptive in advanced version)
//////////////////////////////////////////////////////////////////////////////////

module frame_sync_detector #(
    parameter int      W_CORR    = 72,
    parameter longint  THRESHOLD = 64'd1000000000  // 64-bit to match mag_sq[127:64] width
)(
    input  logic                     clk,
    input  logic                     rst_n,
    
    // Correlation input
    input  logic signed [W_CORR-1:0] corr_i,
    input  logic signed [W_CORR-1:0] corr_q,
    input  logic                     corr_valid,
    output logic                     corr_ready,
    
    // Sync detection output
    output logic                     sync_found,      // pulse when frame detected
    output logic [31:0]              sync_index,      // sample index of detection
    output logic [63:0]              sync_mag         // magnitude² of correlation peak
);

    // =========================================================================
    // Magnitude² Computation: |R|² = R_I² + R_Q²
    // =========================================================================
    logic [127:0] mag_sq;  // Need large width for squared values
    logic         mag_valid;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mag_sq    <= '0;
            mag_valid <= 1'b0;
        end else begin
            if (corr_valid) begin
                // Compute magnitude squared
                mag_sq    <= (corr_i * corr_i) + (corr_q * corr_q);
                mag_valid <= 1'b1;
            end else begin
                mag_valid <= 1'b0;
            end
        end
    end
    
    // Always ready to accept correlation
    assign corr_ready = 1'b1;
    
    // =========================================================================
    // Peak Detection with Hysteresis
    // =========================================================================
    // Strategy: Simple threshold crossing with cooldown period
    // - Detect when mag_sq > THRESHOLD
    // - After detection, ignore next COOLDOWN samples to avoid multiple triggers
    
    localparam int COOLDOWN_CYCLES = 32;  // Ignore next 32 samples after detection
    
    logic [31:0] sample_counter;
    logic [31:0] cooldown_counter;
    logic        in_cooldown;
    
    logic [127:0] mag_sq_d1, mag_sq_d2;  // For peak finding
    logic         mag_valid_d1, mag_valid_d2;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sample_counter   <= '0;
            cooldown_counter <= '0;
            in_cooldown      <= 1'b0;
            sync_found       <= 1'b0;
            sync_index       <= '0;
            sync_mag         <= '0;
            mag_sq_d1        <= '0;
            mag_sq_d2        <= '0;
            mag_valid_d1     <= 1'b0;
            mag_valid_d2     <= 1'b0;
        end else begin
            // Delay line for peak detection
            mag_sq_d1    <= mag_sq;
            mag_sq_d2    <= mag_sq_d1;
            mag_valid_d1 <= mag_valid;
            mag_valid_d2 <= mag_valid_d1;
            
            // Default: no sync found
            sync_found <= 1'b0;
            
            // Sample counter (for indexing)
            if (mag_valid) begin
                sample_counter <= sample_counter + 1;
            end
            
            // Cooldown management
            if (in_cooldown) begin
                if (cooldown_counter > 0) begin
                    cooldown_counter <= cooldown_counter - 1;
                end else begin
                    in_cooldown <= 1'b0;
                end
            end
            
            // Peak detection: current sample is local maximum
            // and exceeds threshold
            if (mag_valid_d1 && !in_cooldown) begin
                // Simple threshold crossing (can be improved with local max check)
                if (mag_sq_d1[127:64] > THRESHOLD) begin  // Use upper bits for comparison
                    sync_found       <= 1'b1;
                    sync_index       <= sample_counter - 1;  // -1 because of delay
                    sync_mag         <= mag_sq_d1[127:64];   // Store upper 64 bits
                    
                    // Start cooldown
                    in_cooldown      <= 1'b1;
                    cooldown_counter <= COOLDOWN_CYCLES;
                end
            end
        end
    end

endmodule