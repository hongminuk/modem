transcript off
onbreak {quit -force}
onerror {quit -force}
transcript on

asim +access +r +m+fir_rrc  -L xil_defaultlib -L xbip_utils_v3_0_14 -L axi_utils_v2_0_10 -L fir_compiler_v7_2_23 -L secureip -O5 xil_defaultlib.fir_rrc

do {fir_rrc.udo}

run 1000ns

endsim

quit -force
