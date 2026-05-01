# Waveform setup for tb_qpsk_modulator
log_wave -recursive *

add_wave /tb_qpsk_modulator/clk
add_wave /tb_qpsk_modulator/rst_n
add_wave_divider "TX Input"
add_wave -radix bin /tb_qpsk_modulator/in_data
add_wave /tb_qpsk_modulator/in_valid
add_wave /tb_qpsk_modulator/in_ready
add_wave_divider "Symbol Output"
add_wave -radix dec /tb_qpsk_modulator/out_i
add_wave -radix dec /tb_qpsk_modulator/out_q
add_wave /tb_qpsk_modulator/out_valid
add_wave /tb_qpsk_modulator/out_ready

run -all
