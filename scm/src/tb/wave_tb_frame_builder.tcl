# Waveform setup for tb_frame_builder
log_wave -recursive *

add_wave /tb_frame_builder/clk
add_wave /tb_frame_builder/rst_n
add_wave_divider "Control"
add_wave /tb_frame_builder/in_frame_start
add_wave -radix unsigned /tb_frame_builder/in_payload_len
add_wave_divider "Payload Input"
add_wave -radix dec /tb_frame_builder/in_i
add_wave -radix dec /tb_frame_builder/in_q
add_wave /tb_frame_builder/in_valid
add_wave /tb_frame_builder/in_ready
add_wave_divider "Frame Output"
add_wave -radix dec /tb_frame_builder/out_i
add_wave -radix dec /tb_frame_builder/out_q
add_wave /tb_frame_builder/out_valid
add_wave /tb_frame_builder/out_ready
add_wave_divider "Internal State"
add_wave /tb_frame_builder/dut/state
add_wave -radix unsigned /tb_frame_builder/dut/preamble_cnt
add_wave -radix unsigned /tb_frame_builder/dut/payload_cnt

run -all
