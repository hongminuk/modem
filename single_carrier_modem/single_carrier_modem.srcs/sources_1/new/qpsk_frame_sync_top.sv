`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: qpsk_frame_sync_top
// Description: 
//   Complete QPSK Modem with Frame Synchronization
//   
//   TX Path: Payload → Frame Builder → Upsample → TX RRC
//   RX Path: RX RRC → Downsample → Correlator → Detector
//   
//   Features:
//   - Automatic preamble insertion (TX)
//   - Correlation-based frame detection (RX)
//   - Sync pulse output when frame detected
//
// Parameters:
//   W            : Symbol bit width (16)
//   W_2          : TX RRC output width (40)
//   W_3          : RX RRC output width (56)
//   SPS          : Samples per symbol (4)
//   OFFSET       : Downsample offset (0)
//   PREAMBLE_LEN : Preamble length in symbols (16)
//   W_CORR       : Correlator output width (72)
//   SYNC_THRESHOLD : Frame detection threshold
//////////////////////////////////////////////////////////////////////////////////

module qpsk_frame_sync_top #(
    parameter int W              = 16,
    parameter int W_2            = 40,
    parameter int W_3            = 56,
    parameter int SPS            = 4,
    parameter int OFFSET         = 0,
    parameter int PREAMBLE_LEN   = 16,
    parameter int W_CORR         = 72,
    parameter longint SYNC_THRESHOLD = 64'd500000000  // Adjust based on SNR
)(
    input  logic                 clk,
    input  logic                 rst_n,
    
    // =========================================================================
    // TX Side: Payload Input
    // =========================================================================
    // Frame control
    input  logic                 tx_frame_start,    // Pulse to start new frame
    input  logic [15:0]          tx_payload_len,    // Number of payload symbols
    
    // Payload symbols (user data)
    input  logic signed [W-1:0]  tx_payload_i,
    input  logic signed [W-1:0]  tx_payload_q,
    input  logic                 tx_payload_valid,
    output logic                 tx_payload_ready,
    
    // TX Output (to channel/DAC)
    output logic signed [W_2-1:0] tx_out_i,
    output logic signed [W_2-1:0] tx_out_q,
    output logic                  tx_out_valid,
    input  logic                  tx_out_ready,
    
    // =========================================================================
    // RX Side: Channel Input
    // =========================================================================
    // RX Input (from channel/ADC)
    input  logic signed [W_2-1:0] rx_in_i,
    input  logic signed [W_2-1:0] rx_in_q,
    input  logic                  rx_in_valid,
    output logic                  rx_in_ready,
    
    // RX Output: Recovered symbols
    output logic signed [W_3-1:0] rx_out_i,
    output logic signed [W_3-1:0] rx_out_q,
    output logic                  rx_out_valid,
    input  logic                  rx_out_ready,
    
    // Frame Sync Output
    output logic                  rx_sync_found,    // Pulse when frame detected
    output logic [31:0]           rx_sync_index,    // Sample index of detection
    output logic [63:0]           rx_sync_mag       // Correlation magnitude
);

    // =========================================================================
    // TX Path: Frame Builder
    // =========================================================================
    logic signed [W-1:0] frame_i, frame_q;
    logic                frame_valid, frame_ready;
    
    frame_builder #(
        .W(W),
        .PREAMBLE_LEN(PREAMBLE_LEN)
    ) u_frame_builder (
        .clk(clk),
        .rst_n(rst_n),
        
        // Control
        .in_frame_start(tx_frame_start),
        .in_payload_len(tx_payload_len),
        
        // Payload input
        .in_i(tx_payload_i),
        .in_q(tx_payload_q),
        .in_valid(tx_payload_valid),
        .in_ready(tx_payload_ready),
        
        // Frame output (preamble + payload)
        .out_i(frame_i),
        .out_q(frame_q),
        .out_valid(frame_valid),
        .out_ready(frame_ready)
    );
    
    // =========================================================================
    // TX Path: Upsample
    // =========================================================================
    logic signed [W-1:0] tx_up_i, tx_up_q;
    logic                tx_up_valid, tx_up_ready;
    
    axis_upsample_zeros #(
        .W(W),
        .SPS(SPS)
    ) u_tx_upsample (
        .clk(clk),
        .rst_n(rst_n),
        .in_i(frame_i),
        .in_q(frame_q),
        .in_valid(frame_valid),
        .in_ready(frame_ready),
        .out_i(tx_up_i),
        .out_q(tx_up_q),
        .out_valid(tx_up_valid),
        .out_ready(tx_up_ready)
    );
    
    // =========================================================================
    // TX Path: TX RRC Filter (I/Q)
    // =========================================================================
    logic tx_valid_i, tx_valid_q;
    logic tx_ready_i, tx_ready_q;
    logic tx_fir_valid, tx_fir_ready;
    
    // Both FIRs must be ready
    assign tx_up_ready = tx_ready_i & tx_ready_q;
    assign tx_fir_valid = tx_up_valid & (tx_ready_i & tx_ready_q);
    
    // Connect to downstream (TX output ready)
    assign tx_fir_ready = tx_out_ready;
    
    fir_rrc u_fir_tx_i (
        .aclk(clk),
        .aresetn(rst_n),
        .s_axis_data_tvalid(tx_fir_valid),
        .s_axis_data_tready(tx_ready_i),
        .s_axis_data_tdata(tx_up_i),
        .m_axis_data_tvalid(tx_valid_i),
        .m_axis_data_tready(tx_fir_ready),
        .m_axis_data_tdata(tx_out_i)
    );
    
    fir_rrc u_fir_tx_q (
        .aclk(clk),
        .aresetn(rst_n),
        .s_axis_data_tvalid(tx_fir_valid),
        .s_axis_data_tready(tx_ready_q),
        .s_axis_data_tdata(tx_up_q),
        .m_axis_data_tvalid(tx_valid_q),
        .m_axis_data_tready(tx_fir_ready),
        .m_axis_data_tdata(tx_out_q)
    );
    
    // TX output valid when both I/Q are valid
    assign tx_out_valid = tx_valid_i & tx_valid_q;
    
    // =========================================================================
    // RX Path: RX RRC Filter (Matched Filter, I/Q)
    // =========================================================================
    logic signed [W_3-1:0] rx_fir_i, rx_fir_q;
    logic                  rx_fir_valid_i, rx_fir_valid_q;
    logic                  rx_fir_ready_i, rx_fir_ready_q;
    logic                  rx_fir_valid, rx_fir_ready;
    
    // Both FIRs receive same valid signal
    assign rx_fir_valid = rx_in_valid;
    assign rx_in_ready = rx_fir_ready_i & rx_fir_ready_q;
    
    fir_rrc_rx u_fir_rx_i (
        .aclk(clk),
        .aresetn(rst_n),
        .s_axis_data_tvalid(rx_fir_valid),
        .s_axis_data_tready(rx_fir_ready_i),
        .s_axis_data_tdata(rx_in_i),
        .m_axis_data_tvalid(rx_fir_valid_i),
        .m_axis_data_tready(rx_fir_ready),
        .m_axis_data_tdata(rx_fir_i)
    );
    
    fir_rrc_rx u_fir_rx_q (
        .aclk(clk),
        .aresetn(rst_n),
        .s_axis_data_tvalid(rx_fir_valid),
        .s_axis_data_tready(rx_fir_ready_q),
        .s_axis_data_tdata(rx_in_q),
        .m_axis_data_tvalid(rx_fir_valid_q),
        .m_axis_data_tready(rx_fir_ready),
        .m_axis_data_tdata(rx_fir_q)
    );
    
    // =========================================================================
    // RX Path: Downsample
    // =========================================================================
    logic signed [W_3-1:0] rx_dn_i, rx_dn_q;
    logic                  rx_dn_valid, rx_dn_ready;
    
    assign rx_fir_ready = rx_dn_ready;
    
    axis_downsample_pick #(
        .W(W),
        .W_3(W_3),
        .SPS(SPS),
        .OFFSET(OFFSET)
    ) u_rx_downsample (
        .clk(clk),
        .rst_n(rst_n),
        .in_i(rx_fir_i),
        .in_q(rx_fir_q),
        .in_valid(rx_fir_valid_i & rx_fir_valid_q),
        .in_ready(rx_dn_ready),
        .out_i(rx_dn_i),
        .out_q(rx_dn_q),
        .out_valid(rx_dn_valid),
        .out_ready(rx_dn_ready)
    );
    
    // =========================================================================
    // RX Path: Preamble Correlator
    // =========================================================================
    logic signed [W_CORR-1:0] corr_i, corr_q;
    logic                     corr_valid, corr_ready;
    
    preamble_correlator #(
        .W(W_3),
        .W_CORR(W_CORR),
        .PREAMBLE_LEN(PREAMBLE_LEN)
    ) u_correlator (
        .clk(clk),
        .rst_n(rst_n),
        .in_i(rx_dn_i),
        .in_q(rx_dn_q),
        .in_valid(rx_dn_valid),
        .in_ready(rx_dn_ready),
        .corr_i(corr_i),
        .corr_q(corr_q),
        .corr_valid(corr_valid),
        .corr_ready(corr_ready)
    );
    
    // =========================================================================
    // RX Path: Frame Sync Detector
    // =========================================================================
    frame_sync_detector #(
        .W_CORR(W_CORR),
        .THRESHOLD(SYNC_THRESHOLD)
    ) u_detector (
        .clk(clk),
        .rst_n(rst_n),
        .corr_i(corr_i),
        .corr_q(corr_q),
        .corr_valid(corr_valid),
        .corr_ready(corr_ready),
        .sync_found(rx_sync_found),
        .sync_index(rx_sync_index),
        .sync_mag(rx_sync_mag)
    );
    
    // =========================================================================
    // RX Output: Connect to correlator output (symbols with sync info)
    // =========================================================================
    // Note: In a complete system, you'd use rx_sync_found to extract payload
    // For now, we pass through the downsampled symbols
    assign rx_out_i     = rx_dn_i;
    assign rx_out_q     = rx_dn_q;
    assign rx_out_valid = rx_dn_valid;
    assign rx_out_ready = 1'b1;  // Always ready for now
    
    // If you want backpressure from output:
    // assign rx_dn_ready = rx_out_ready & corr_ready;

endmodule
