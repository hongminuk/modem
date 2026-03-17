`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 01/15/2026 05:22:37 PM
// Design Name: 
// Module Name: qpsk_rrc_step1_top
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


module qpsk_rrc_step1_top #(
    parameter int W      = 16,
    parameter int W_2    = 40,
    parameter int W_3    = 56,
    parameter int SPS    = 4,
    parameter int OFFSET = 0
)(
    input  logic                 clk,
    input  logic                 rst_n,
    
    // symbol-rate input (QPSK symbols)
    input  logic signed [W-1:0] sym_i,
    input  logic signed [W-1:0] sym_q,
    input  logic                sym_valid,
    output logic                sym_ready,
    
    // symbol-rate output (after RX matched filter + downsample)
    output logic signed [W_3-1:0] out_i,
    output logic signed [W_3-1:0] out_q,
    output logic                out_valid,
    input  logic                out_ready    
);

    // --- upsample -> sample-rate stream
    logic signed [W-1:0] up_i, up_q;
    logic up_valid, up_ready;
    
    axis_upsample_zeros #(.W(W), .SPS(SPS)) u_up(
        .clk, .rst_n,
        .in_i(sym_i), .in_q(sym_q), .in_valid(sym_valid), .in_ready(sym_ready),
        .out_i(up_i), .out_q(up_q), .out_valid(up_valid), .out_ready(up_ready)
    );
    
    // --- TX RRC FIR (I/Q)
    logic signed [W_2-1:0] tx_i, tx_q;
    logic tx_valid_i, tx_valid_q, tx_ready_i, tx_ready_q;
    logic tx_valid, tx_ready;
    
    assign tx_valid = up_valid;
    // downstream이 두 FIR 모두 받아야 up_ready=1
    assign up_ready = tx_ready;
    
    // 두 FIR이 모두 ready일 때만 진행
    assign tx_ready = tx_ready_i & tx_ready_q;
    
    // FIR Compiler IP:
    fir_rrc u_fir_tx_i (       //fir_tx_rrc_i
        .aclk(clk),
        .aresetn(rst_n),
        .s_axis_data_tvalid(tx_valid),
        .s_axis_data_tready(tx_ready_i),
        .s_axis_data_tdata(up_i),
        .m_axis_data_tvalid(tx_valid_i),
        .m_axis_data_tready(1'b1),          // 
        .m_axis_data_tdata(tx_i)
    );

    fir_rrc u_fir_tx_q (       //fir_tx_rrc_q
        .aclk(clk),
        .aresetn(rst_n),
        .s_axis_data_tvalid(tx_valid),
        .s_axis_data_tready(tx_ready_q),
        .s_axis_data_tdata(up_q),
        .m_axis_data_tvalid(tx_valid_q),
        .m_axis_data_tready(1'b1),          // 
        .m_axis_data_tdata(tx_q)
    );

    // NOTE:
    // 위처럼 m_axis_data_tready를 1로 박으면(항상 소비) 중간 back-pressure가 없는 구조가 됨.
    // 체인을 "진짜 AXIS로" 깔끔히 하려면 아래 RX FIR 입력 ready를 다시 연결해야 함.
    // (아래에 '완전 AXIS 연결 버전'을 별도로 적어줄 수도 있어.)

    // --- RX RRC FIR (Matched filter) (I/Q) : 여기서는 TX 출력이 항상 valid라고 가정하지 말고 묶어야 함
    logic signed [W_3-1:0] rxf_i, rxf_q;
    logic rxf_valid_i, rxf_valid_q, rxf_ready_i, rxf_ready_q;
    logic rxf_valid, rxf_ready;

    // I/Q valid synqronization:
    assign rxf_valid = tx_valid_i & tx_valid_q;
    
    // RX FIR input ready
    assign rxf_ready = rxf_ready_i & rxf_ready_q;

    fir_rrc_rx u_fir_rx_i (
        .aclk(clk),
        .aresetn(rst_n),
        .s_axis_data_tvalid(rxf_valid),
        .s_axis_data_tready(rxf_ready_i),
        .s_axis_data_tdata (tx_i),
        .m_axis_data_tvalid(rxf_valid_i),
        .m_axis_data_tready(1'b1),
        .m_axis_data_tdata (rxf_i)
    );

    fir_rrc_rx u_fir_rx_q (
        .aclk(clk),
        .aresetn(rst_n),
        .s_axis_data_tvalid(rxf_valid),
        .s_axis_data_tready(rxf_ready_q),
        .s_axis_data_tdata (tx_q),
        .m_axis_data_tvalid(rxf_valid_q),
        .m_axis_data_tready(1'b1),
        .m_axis_data_tdata (rxf_q)
    );

    // --- downsample pick (symbol-rate)
    axis_downsample_pick #(.W(W), .W_3(W_3), .SPS(SPS), .OFFSET(OFFSET)) u_dn(
        .clk, .rst_n,
        .in_i(rxf_i), .in_q(rxf_q),
        .in_valid(rxf_valid_i & rxf_valid_q),
        .in_ready(),
        .out_i(out_i),  .out_q(out_q),
        .out_valid(out_valid),
        .out_ready(out_ready)
    );


endmodule
