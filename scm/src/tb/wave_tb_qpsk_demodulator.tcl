# Waveform setup for tb_qpsk_demodulator
log_wave -recursive *

add_wave /tb_qpsk_demodulator/clk
add_wave /tb_qpsk_demodulator/rst_n
add_wave_divider "Symbol Input"
add_wave -radix dec /tb_qpsk_demodulator/in_i
add_wave -radix dec /tb_qpsk_demodulator/in_q
add_wave /tb_qpsk_demodulator/in_valid
add_wave /tb_qpsk_demodulator/in_ready
add_wave_divider "Bit Output"
add_wave -radix bin /tb_qpsk_demodulator/out_data
add_wave /tb_qpsk_demodulator/out_valid
add_wave /tb_qpsk_demodulator/out_ready

run -all
