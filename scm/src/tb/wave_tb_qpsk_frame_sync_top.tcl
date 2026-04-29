# Waveform setup for tb_qpsk_frame_sync_top (End-to-End with FIR IP)
log_wave -recursive *

add_wave /tb_qpsk_frame_sync_top/clk
add_wave /tb_qpsk_frame_sync_top/rst_n

add_wave_divider "TX: Bits In"
add_wave -radix binary /tb_qpsk_frame_sync_top/tx_bits
add_wave /tb_qpsk_frame_sync_top/tx_bits_valid
add_wave /tb_qpsk_frame_sync_top/tx_bits_ready
add_wave /tb_qpsk_frame_sync_top/tx_frame_start
add_wave -radix unsigned /tb_qpsk_frame_sync_top/tx_payload_len

add_wave_divider "TX: Modulator (latest)"
add_wave -radix decimal /tb_qpsk_frame_sync_top/dut/tx_mod_i
add_wave -radix decimal /tb_qpsk_frame_sync_top/dut/tx_mod_q
add_wave /tb_qpsk_frame_sync_top/dut/tx_mod_valid

add_wave_divider "TX: Frame Builder"
add_wave -radix decimal /tb_qpsk_frame_sync_top/dut/frame_i
add_wave -radix decimal /tb_qpsk_frame_sync_top/dut/frame_q
add_wave /tb_qpsk_frame_sync_top/dut/frame_valid

add_wave_divider "TX: After RRC FIR"
add_wave -radix decimal /tb_qpsk_frame_sync_top/tx_out_i
add_wave -radix decimal /tb_qpsk_frame_sync_top/tx_out_q
add_wave /tb_qpsk_frame_sync_top/tx_out_valid

add_wave_divider "RX: After Matched Filter + Downsample"
add_wave -radix decimal /tb_qpsk_frame_sync_top/dut/rx_dn_i
add_wave -radix decimal /tb_qpsk_frame_sync_top/dut/rx_dn_q
add_wave /tb_qpsk_frame_sync_top/dut/rx_dn_valid

add_wave_divider "RX: Correlator (after bug fix)"
add_wave -radix decimal /tb_qpsk_frame_sync_top/dut/corr_i
add_wave -radix decimal /tb_qpsk_frame_sync_top/dut/corr_q
add_wave /tb_qpsk_frame_sync_top/dut/corr_valid

add_wave_divider "RX: Sync Detector"
add_wave /tb_qpsk_frame_sync_top/rx_sync_found
add_wave -radix unsigned /tb_qpsk_frame_sync_top/rx_sync_index
add_wave -radix unsigned /tb_qpsk_frame_sync_top/rx_sync_mag

add_wave_divider "RX: Demodulator (latest)"
add_wave -radix binary /tb_qpsk_frame_sync_top/rx_bits
add_wave /tb_qpsk_frame_sync_top/rx_bits_valid

run -all
