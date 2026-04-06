# Waveform setup for tb_frame_sync_detector
log_wave -recursive *

add_wave /tb_frame_sync_detector/clk
add_wave /tb_frame_sync_detector/rst_n
add_wave -divider "Correlation Input"
add_wave -radix decimal /tb_frame_sync_detector/corr_i
add_wave -radix decimal /tb_frame_sync_detector/corr_q
add_wave /tb_frame_sync_detector/corr_valid
add_wave /tb_frame_sync_detector/corr_ready
add_wave -divider "Sync Output"
add_wave /tb_frame_sync_detector/sync_found
add_wave -radix unsigned /tb_frame_sync_detector/sync_index
add_wave -radix unsigned /tb_frame_sync_detector/sync_mag
add_wave -divider "Internal"
add_wave -radix unsigned /tb_frame_sync_detector/dut/mag_sq
add_wave /tb_frame_sync_detector/dut/in_cooldown
add_wave -radix unsigned /tb_frame_sync_detector/dut/sample_counter

run -all
