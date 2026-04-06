# Waveform setup for tb_qpsk_modulator
log_wave -recursive *

add_wave /tb_qpsk_modulator/clk
add_wave /tb_qpsk_modulator/rst_n
add_wave -divider "TX Input"
add_wave -radix binary /tb_qpsk_modulator/in_data
add_wave /tb_qpsk_modulator/in_valid
add_wave /tb_qpsk_modulator/in_ready
add_wave -divider "Symbol Output"
add_wave -radix decimal /tb_qpsk_modulator/out_i
add_wave -radix decimal /tb_qpsk_modulator/out_q
add_wave /tb_qpsk_modulator/out_valid
add_wave /tb_qpsk_modulator/out_ready

run -all
