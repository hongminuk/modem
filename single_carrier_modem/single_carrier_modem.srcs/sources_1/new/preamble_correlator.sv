`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: preamble_correlator
// Description: 
//   Correlates incoming symbol stream with known preamble pattern
//   
//   Computes sliding cross-correlation:
//   R[n] = Σ(k=0 to L-1) { r_I[n-k]·p_I[k] + r_Q[n-k]·p_Q[k] }
//   
//   where:
//   - r_I, r_Q: received I/Q symbols
//   - p_I, p_Q: preamble I/Q pattern
//   - L: preamble length
//   
//   Output: Correlation magnitude and phase for each input symbol
//
// Parameters:
//   W            : Input symbol bit width
//   W_CORR       : Correlation output bit width (needs headroom!)
//   PREAMBLE_LEN : Number of preamble symbols
//////////////////////////////////////////////////////////////////////////////////

module preamble_correlator #(
    parameter int W             = 56,   // Input width (after RRC filter)
    parameter int W_CORR        = 72,   // Correlation output width
    parameter int PREAMBLE_LEN  = 16
)(
    input  logic                    clk,
    input  logic                    rst_n,
    
    // Symbol input (I/Q)
    input  logic signed [W-1:0]     in_i,
    input  logic signed [W-1:0]     in_q,
    input  logic                    in_valid,
    output logic                    in_ready,
    
    // Correlation output
    output logic signed [W_CORR-1:0] corr_i,      // I component of correlation
    output logic signed [W_CORR-1:0] corr_q,      // Q component of correlation
    output logic                     corr_valid,
    input  logic                     corr_ready
);

    // =========================================================================
    // Preamble Pattern (MUST match frame_builder!)
    // =========================================================================
    localparam int SCALE = 12000;
    
    // Preamble I channel (16 symbols) - MUST MATCH frame_builder exactly!
    localparam logic signed [15:0] PREAMBLE_I [0:15] = '{
        16'sd12000,  16'sd12000,  16'sd12000, -16'sd12000,
       -16'sd12000,  16'sd12000, -16'sd12000,  16'sd12000,
        16'sd12000, -16'sd12000, -16'sd12000,  16'sd12000,
       -16'sd12000, -16'sd12000,  16'sd12000,  16'sd12000
    };
    
    // Preamble Q channel (16 symbols) - MUST MATCH frame_builder exactly!
    localparam logic signed [15:0] PREAMBLE_Q [0:15] = '{
        16'sd12000,  16'sd12000, -16'sd12000, -16'sd12000,
        16'sd12000,  16'sd12000, -16'sd12000, -16'sd12000,
        16'sd12000, -16'sd12000, -16'sd12000,  16'sd12000,
        16'sd12000,  16'sd12000, -16'sd12000,  16'sd12000
    };
    
    // =========================================================================
    // Shift Register for incoming symbols (delay line)
    // =========================================================================
    logic signed [W-1:0] shift_i [0:PREAMBLE_LEN-1];
    logic signed [W-1:0] shift_q [0:PREAMBLE_LEN-1];
    
    // =========================================================================
    // Correlation Computation (Combinational)
    // =========================================================================
    // Complex correlation: R = Σ r[k] * conj(p[k])
    //                        = Σ (r_I[k] + j·r_Q[k]) * (p_I[k] - j·p_Q[k])
    //                        = Σ (r_I[k]·p_I[k] + r_Q[k]·p_Q[k]) 
    //                          + j·(r_Q[k]·p_I[k] - r_I[k]·p_Q[k])
    
    logic signed [W_CORR-1:0] sum_i, sum_q;
    
    always_comb begin
        sum_i = '0;
        sum_q = '0;
        
        for (int k = 0; k < PREAMBLE_LEN; k++) begin
            // Real part: r_I[k]*p_I[k] + r_Q[k]*p_Q[k]
            sum_i = sum_i + shift_i[k] * PREAMBLE_I[k] + shift_q[k] * PREAMBLE_Q[k];
            
            // Imag part: r_Q[k]*p_I[k] - r_I[k]*p_Q[k]
            sum_q = sum_q + shift_q[k] * PREAMBLE_I[k] - shift_i[k] * PREAMBLE_Q[k];
        end
    end
    
    // =========================================================================
    // Pipeline Stage: Register correlation output
    // =========================================================================
    logic signed [W_CORR-1:0] corr_i_r, corr_q_r;
    logic                     corr_valid_r;
    
    assign corr_i     = corr_i_r;
    assign corr_q     = corr_q_r;
    assign corr_valid = corr_valid_r;
    
    // Input ready: can accept when output is consumed or not valid
    assign in_ready = (!corr_valid_r) || corr_ready;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            corr_i_r     <= '0;
            corr_q_r     <= '0;
            corr_valid_r <= 1'b0;
            
            // Clear shift registers
            for (int k = 0; k < PREAMBLE_LEN; k++) begin
                shift_i[k] <= '0;
                shift_q[k] <= '0;
            end
        end else begin
            // Output consumed
            if (corr_valid_r && corr_ready) begin
                corr_valid_r <= 1'b0;
            end
            
            // New input accepted
            if (in_valid && in_ready) begin
                // Shift register update
                for (int k = PREAMBLE_LEN-1; k > 0; k--) begin
                    shift_i[k] <= shift_i[k-1];
                    shift_q[k] <= shift_q[k-1];
                end
                shift_i[0] <= in_i;
                shift_q[0] <= in_q;
                
                // Compute and register correlation
                corr_i_r     <= sum_i;
                corr_q_r     <= sum_q;
                corr_valid_r <= 1'b1;
            end
        end
    end

endmodule
