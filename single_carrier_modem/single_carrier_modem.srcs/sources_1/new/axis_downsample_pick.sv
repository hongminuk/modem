`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 01/15/2026 04:47:47 PM
// Design Name: 
// Module Name: axis_downsample_pick
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


module axis_downsample_pick #(
    parameter int W     = 16,
    parameter int W_3   = 56,
    parameter int SPS   = 4,
    parameter int OFFSET = 2     //0..SPS-1

)(
    input  logic                clk,
    input  logic                rst_n,
    
    // sample-rate input
    input  logic signed [W_3-1:0] in_i,
    input  logic signed [W_3-1:0] in_q,
    input  logic                  in_valid,
    output logic                  in_ready,
    
    // symbol-rate output
    output logic signed [W_3-1:0] out_i,
    output logic signed [W_3-1:0] out_q,
    output logic                  out_valid,
    input  logic                  out_ready
);

    logic [$clog2(SPS)-1:0] phase;
    logic signed [W_3-1:0] out_i_r, out_q_r;
    logic out_valid_r;
    
    assign out_i        = out_i_r;
    assign out_q        = out_q_r;
    assign out_valid    = out_valid_r;  //registered out



  // 선택 샘플(phase==OFFSET)에서는 출력 버퍼가 비어있거나(out_valid=0) 
        //  혹은 소비 가능(out_ready=1)일 때만 입력을 받음
  // 나머지 phase에서는 일단 계속 흘려도 되지만, 
        // phase가 OFFSET에 도달했을 때 버퍼가 막혀있으면 그때 stall 됨.

    // 
    //
    always_comb begin
        if(phase == OFFSET) begin
            in_ready = (!out_valid_r) || out_ready;
        end else begin
            in_ready = 1'b1;
        end  
    end

    wire xfer_in  = in_valid  && in_ready;
    wire xfer_out = out_valid && out_ready;

    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            phase       <= '0;
            out_valid_r <= 1'b0;
            out_i_r     <= '0;
            out_q_r     <= '0;
        end else begin
            // output consumed
            if (xfer_out) begin
                out_valid_r <= 1'b0;
            end
        
            // input accepted -> phase advance
            if (xfer_in) begin
                //capture only at OFFSET
//                if (phase == OFFSET) begin
                if (phase == OFFSET) begin
                    out_i_r     <= in_i;
                    out_q_r     <= in_q;
                    out_valid_r <= 1'b1;
                end
//                end
                
                if (phase == SPS-1) phase <= '0;
                else                phase <= phase + 1'b1;                
            end
        end
    end

endmodule
