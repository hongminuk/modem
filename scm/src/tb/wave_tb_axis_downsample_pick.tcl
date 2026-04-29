# Waveform setup for tb_axis_downsample_pick
log_wave -recursive *

add_wave /tb_axis_downsample_pick/clk
add_wave /tb_axis_downsample_pick/rst_n
add_wave_divider "Sample Input"
add_wave -radix decimal /tb_axis_downsample_pick/in_i
add_wave -radix decimal /tb_axis_downsample_pick/in_q
add_wave /tb_axis_downsample_pick/in_valid
add_wave /tb_axis_downsample_pick/in_ready
add_wave_divider "Symbol Output"
add_wave -radix decimal /tb_axis_downsample_pick/out_i
add_wave -radix decimal /tb_axis_downsample_pick/out_q
add_wave /tb_axis_downsample_pick/out_valid
add_wave /tb_axis_downsample_pick/out_ready
add_wave_divider "Internal"
add_wave -radix unsigned /tb_axis_downsample_pick/dut/phase

run -all
