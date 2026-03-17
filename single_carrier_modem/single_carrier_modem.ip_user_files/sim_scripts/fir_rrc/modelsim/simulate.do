onbreak {quit -f}
onerror {quit -f}

vsim -voptargs="+acc"  -L xil_defaultlib -L xbip_utils_v3_0_14 -L axi_utils_v2_0_10 -L fir_compiler_v7_2_23 -L secureip -lib xil_defaultlib xil_defaultlib.fir_rrc

set NumericStdNoWarnings 1
set StdArithNoWarnings 1

do {wave.do}

view wave
view structure
view signals

do {fir_rrc.udo}

run 1000ns

quit -force
