# Waveform setup for tb_preamble_correlator
log_wave -recursive *

add_wave /tb_preamble_correlator/clk
add_wave /tb_preamble_correlator/rst_n
add_wave_divider "Symbol Input"
add_wave -radix decimal /tb_preamble_correlator/in_i
add_wave -radix decimal /tb_preamble_correlator/in_q
add_wave /tb_preamble_correlator/in_valid
add_wave /tb_preamble_correlator/in_ready
add_wave_divider "Correlation Output"
add_wave -radix decimal /tb_preamble_correlator/corr_i
add_wave -radix decimal /tb_preamble_correlator/corr_q
add_wave /tb_preamble_correlator/corr_valid
add_wave /tb_preamble_correlator/corr_ready

run -all
