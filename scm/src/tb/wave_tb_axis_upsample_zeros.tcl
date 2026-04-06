# Waveform setup for tb_axis_upsample_zeros
log_wave -recursive *

add_wave /tb_axis_upsample_zeros/clk
add_wave /tb_axis_upsample_zeros/rst_n
add_wave -divider "Symbol Input"
add_wave -radix decimal /tb_axis_upsample_zeros/in_i
add_wave -radix decimal /tb_axis_upsample_zeros/in_q
add_wave /tb_axis_upsample_zeros/in_valid
add_wave /tb_axis_upsample_zeros/in_ready
add_wave -divider "Upsampled Output"
add_wave -radix decimal /tb_axis_upsample_zeros/out_i
add_wave -radix decimal /tb_axis_upsample_zeros/out_q
add_wave /tb_axis_upsample_zeros/out_valid
add_wave /tb_axis_upsample_zeros/out_ready
add_wave -divider "Internal"
add_wave /tb_axis_upsample_zeros/dut/active
add_wave -radix unsigned /tb_axis_upsample_zeros/dut/phase

run -all
