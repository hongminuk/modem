# Waveform setup for tb_loopback_no_fir (End-to-End)
log_wave -recursive *

add_wave /tb_loopback_no_fir/clk
add_wave /tb_loopback_no_fir/rst_n

add_wave_divider "TX: Bits In"
add_wave -radix bin /tb_loopback_no_fir/tx_bits
add_wave /tb_loopback_no_fir/tx_bits_valid
add_wave /tb_loopback_no_fir/tx_bits_ready

add_wave_divider "TX: Modulator Out"
add_wave -radix dec /tb_loopback_no_fir/mod_i
add_wave -radix dec /tb_loopback_no_fir/mod_q
add_wave /tb_loopback_no_fir/mod_valid

add_wave_divider "TX: Frame Builder Out"
add_wave -radix dec /tb_loopback_no_fir/frame_i
add_wave -radix dec /tb_loopback_no_fir/frame_q
add_wave /tb_loopback_no_fir/frame_valid
add_wave /tb_loopback_no_fir/frame_start

add_wave_divider "TX: Upsample Out"
add_wave -radix dec /tb_loopback_no_fir/up_i
add_wave -radix dec /tb_loopback_no_fir/up_q
add_wave /tb_loopback_no_fir/up_valid

add_wave_divider "RX: Downsample Out"
add_wave -radix dec /tb_loopback_no_fir/ds_i
add_wave -radix dec /tb_loopback_no_fir/ds_q
add_wave /tb_loopback_no_fir/ds_valid

add_wave_divider "RX: Correlator"
add_wave -radix dec /tb_loopback_no_fir/corr_i
add_wave -radix dec /tb_loopback_no_fir/corr_q
add_wave /tb_loopback_no_fir/corr_valid

add_wave_divider "RX: Sync Detector"
add_wave /tb_loopback_no_fir/sync_found
add_wave -radix unsigned /tb_loopback_no_fir/sync_index
add_wave -radix unsigned /tb_loopback_no_fir/sync_mag

add_wave_divider "RX: Demod Out"
add_wave -radix bin /tb_loopback_no_fir/rx_bits
add_wave /tb_loopback_no_fir/rx_bits_valid

run -all
