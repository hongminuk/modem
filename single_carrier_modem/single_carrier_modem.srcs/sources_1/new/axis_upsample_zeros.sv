`timescale 1ns / 1ps
module axis_upsample_zeros #(
    parameter int W     = 16,
    parameter int SPS   = 4
)(
    input  logic                 clk,
    input  logic                 rst_n,
    
    // symbol-rate input (I/Q)
    input  logic signed [W-1:0]  in_i,
    input  logic signed [W-1:0]  in_q,
    input  logic                 in_valid,
    output logic                 in_ready,
    
    // sample-rate output (I/Q)
    output logic signed [W-1:0]  out_i,
    output logic signed [W-1:0]  out_q,
    output logic                 out_valid,
    input  logic                 out_ready
);

    logic active;
    logic [$clog2(SPS)-1:0] phase;
    logic signed [W-1:0] hold_i, hold_q;
    
    // if(acitve), for(4) out_valid <= '1';
    assign out_valid = active;
    
    // the condition for getting new symbol
    assign in_ready = (!active) && out_ready;
    
    // if(phase==0) out <= symbol ((????))    
    always_comb begin
        if(!active) begin
            out_i = '0;     // if(out_i='0;) with any bitwidth, just assign '0', (W'b0)
            out_q = '0;     // if(out_i='1;) with any bitwidth, just assign '1', (W'b1)
        end else begin
            if (phase == 0) begin
                out_i = hold_i;
                out_q = hold_q;
            end else begin
                out_i = '0;
                out_q = '0;
            end
        end
    end
    
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            active  <= 1'b0;
            phase   <= '0;
            hold_i  <= '0;
            hold_q  <= '0;
        end else begin
            // road the symbol (in_valid & in_ready)
            if (in_valid && in_ready) begin
                hold_i  <= in_i;
                hold_q  <= in_q;
                active  <= 1'b1;
                phase   <= '0;
            end
            
            // At out fire, update phase status
            if(out_valid && out_ready) begin
                if(phase == SPS-1) begin
                    active  <= 1'b0;
                    phase   <= '0;
                end else begin
                    phase   <= phase + 1'b1;
                end 
            end
        end
    end
    
endmodule