`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 02/11/2026 08:03:08 AM
// Design Name: 
// Module Name: frame_builder
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


module frame_builder #(
    parameter int W             = 16,
    parameter int PREAMBLE_LEN  = 16    // preamble length in symbols
)(
    input  logic                clk,
    input  logic                rst_n,
    
    // Control interface
    input  logic                in_frame_start,     // pulse : start new frame
    input  logic [15:0]         in_payload_len,     // payload symbols count
    
    // Payload input (symbol-rate I/Q)
    input  logic signed [W-1:0] in_i,
    input  logic signed [W-1:0] in_q,
    input  logic                in_valid,
    output logic                in_ready,
    
    // Frame output (preamble + payload, symbol-rate I/Q)
    output logic signed [W-1:0] out_i,
    output logic signed [W-1:0] out_q,
    output logic                out_valid,
    input  logic                out_ready
);

// Preamble Pattern Definition
// 16-symbol QPSK preamble with good autocorrelation properties
// Pattern inspired by Barker code mapped to QPSK
// Each symbol: I, Q ∈ {-1, +1} scaled to ±12000

localparam int SCALE = 12000;

// Barker-like sequence
// Pattern: [+1+j, +1+j, +1-j, -1-j, -1+j, +1+j, -1-j, +1-j,
//          +1+j, -1-j, -1-j, +1+j, -1+j, -1+j, +1-j, +1+j]
// Preamble I channel (16 symbols)
localparam logic signed [15:0] PREAMBLE_I [0:15] = '{
    16'sd12000,  16'sd12000,  16'sd12000, -16'sd12000,  // +1, +1, +1, -1
    -16'sd12000,  16'sd12000, -16'sd12000,  16'sd12000,  // -1, +1, -1, +1
    16'sd12000, -16'sd12000, -16'sd12000,  16'sd12000,  // +1, -1, -1, +1
    -16'sd12000, -16'sd12000,  16'sd12000,  16'sd12000   // -1, -1, +1, +1
};  
// Preamble Q channel (16 symbols)
localparam logic signed [15:0] PREAMBLE_Q [0:15] = '{
    16'sd12000,  16'sd12000, -16'sd12000, -16'sd12000,  // +j, +j, -j, -j
    16'sd12000,  16'sd12000, -16'sd12000, -16'sd12000,  // +j, +j, -j, -j
    16'sd12000, -16'sd12000, -16'sd12000,  16'sd12000,  // +j, -j, -j, +j
    16'sd12000,  16'sd12000, -16'sd12000,  16'sd12000   // +j, +j, -j, +j
};

// State Machine
typedef enum logic [1:0] {
    IDLE,       // waiting for frame_start
    PREAMBLE,   // sending preamble
    PAYLOAD     // forwarding payload
} state_t;

state_t state, state_next;

logic [15:0] preamble_cnt, preamble_cnt_next;   // preamble symbol counter
logic [15:0] payload_cnt, payload_cnt_next;     // payload symbol counter
logic [15:0] payload_len_hold;                  // stored payload length


// State Regitser
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state           <= IDLE;
        preamble_cnt    <= '0;
        payload_cnt     <= '0;
        payload_len_hold<= '0;
    end else begin
        state           <= state_next;
        preamble_cnt    <= preamble_cnt_next;
        payload_cnt     <= payload_cnt_next;
    
        // Latch payload length at frame start
        if (in_frame_start) begin
            payload_len_hold <= in_payload_len;
        end
    end
end

// Next State Logic
always_comb begin
    // Default: hold current state
    state_next          = state;
    preamble_cnt_next   = preamble_cnt;
    payload_cnt_next    = payload_cnt;
    
    case (state)
        IDLE: begin
            if (in_frame_start) begin
                state_next          = PREAMBLE;
                preamble_cnt_next   = '0;
                payload_cnt_next    = '0;
            end
        end PREAMBLE: begin
            // Advance preamble counter when output is accepted
            if (out_valid && out_ready) begin
                if (preamble_cnt == PREAMBLE_LEN-1) begin
                    state_next          = PAYLOAD;
                    preamble_cnt_next   = '0;
                end else begin
                    preamble_cnt_next   = preamble_cnt + 1;
                end
            end
        end PAYLOAD: begin
            // Forward payload symbols
            if (in_valid && in_ready) begin
                if(payload_cnt == payload_len_hold - 1) begin
                    state_next       = IDLE;
                    payload_cnt_next = '0;
                end else begin
                    payload_cnt_next = payload_cnt + 1;
                end
            end
        end default: state_next = IDLE;
    endcase
end

// Output Logic
always_comb begin
    // Default assignments
    out_i       = '0;
    out_q       = '0;
    out_valid   = 1'b0;
    in_ready    = 1'b0;    
    
    case (state)
        IDLE: begin
            // No output, ready for new frame
            out_valid   = 1'b0;
            in_ready    = 1'b0;
        end PREAMBLE: begin
            // Output preamble pattern
            out_i       = PREAMBLE_I[preamble_cnt];
            out_q       = PREAMBLE_Q[preamble_cnt];
            out_valid   = 1'b1;
            in_ready    = 1'b0; // not consuming input during preamble
        end PAYLOAD: begin
            // Forward input to output
            out_i       = in_i;
            out_q       = in_q;
            out_valid   = in_valid;
            in_ready    = out_ready;
        end default: begin
            out_valid   = 1'b0;
            in_ready    = 1'b0;
        end
    endcase
end

endmodule
