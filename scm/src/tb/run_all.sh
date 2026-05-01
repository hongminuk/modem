#!/bin/bash
# Run all 9 testbenches (text mode, PASS/FAIL only)
# Usage: ./run_all.sh
#   or:  ./run_all.sh gui <tb_name>   (open specific TB in GUI with waveform)

set -e
cd "$(dirname "$0")"

RTL_DIR="../rtl"
IP_DIR="../../Vivado_Project/single_carrier_modem.gen/sources_1/ip"
PASS=0
FAIL=0
TOTAL=9

# Clean previous runs
rm -rf xsim.dir .Xil *.jou *.log *.pb *.wdb webtalk* 2>/dev/null

# TB definitions: name:rtl_files
declare -a TBS=(
  "tb_qpsk_modulator:qpsk_modulator.sv"
  "tb_qpsk_demodulator:qpsk_demodulator.sv"
  "tb_frame_builder:frame_builder.sv"
  "tb_axis_upsample_zeros:axis_upsample_zeros.sv"
  "tb_axis_downsample_pick:axis_downsample_pick.sv"
  "tb_preamble_correlator:preamble_correlator.sv"
  "tb_frame_sync_detector:frame_sync_detector.sv"
  "tb_loopback_no_fir:qpsk_modulator.sv qpsk_demodulator.sv frame_builder.sv axis_upsample_zeros.sv axis_downsample_pick.sv preamble_correlator.sv frame_sync_detector.sv"
  "tb_qpsk_frame_sync_top:qpsk_modulator.sv qpsk_demodulator.sv frame_builder.sv axis_upsample_zeros.sv axis_downsample_pick.sv preamble_correlator.sv frame_sync_detector.sv qpsk_frame_sync_top.sv"
)

# Helper: compile FIR IP (only needed for tb_qpsk_frame_sync_top)
compile_fir_ip() {
    xvhdl -work xil_defaultlib \
        $IP_DIR/fir_rrc/sim/fir_rrc.vhd \
        $IP_DIR/fir_rrc_rx/sim/fir_rrc_rx.vhd > /dev/null 2>&1
    # Copy MIF coefficient files
    cp -f $IP_DIR/fir_rrc/fir_rrc.mif . 2>/dev/null
    cp -f $IP_DIR/fir_rrc_rx/fir_rrc_rx.mif . 2>/dev/null
}

# Helper: get xelab args (extra libs for top TB)
xelab_args() {
    local name="$1"
    if [ "$name" = "tb_qpsk_frame_sync_top" ]; then
        echo "-L xil_defaultlib -L fir_compiler_v7_2_23 -debug typical"
    else
        echo "-debug typical"
    fi
}

# GUI mode: open specific TB
if [ "$1" = "gui" ] && [ -n "$2" ]; then
    for entry in "${TBS[@]}"; do
        name="${entry%%:*}"
        rtl_list="${entry##*:}"
        if [ "$name" = "$2" ]; then
            rtl_files=""
            for f in $rtl_list; do rtl_files="$rtl_files $RTL_DIR/$f"; done
            echo "=== Compiling $name ==="
            if [ "$name" = "tb_qpsk_frame_sync_top" ]; then
                compile_fir_ip
            fi
            xvlog -sv $rtl_files ${name}.sv
            xelab $(xelab_args $name) $name -s $name
            echo "=== Opening GUI: $name ==="
            xsim $name -gui -tclbatch wave_${name}.tcl 2>/dev/null || xsim $name -gui
            exit 0
        fi
    done
    echo "ERROR: Unknown TB '$2'"
    echo "Available: ${TBS[*]%%:*}"
    exit 1
fi

# Text mode: run all
echo "========================================"
echo " Running all $TOTAL testbenches"
echo "========================================"
echo ""

for entry in "${TBS[@]}"; do
    name="${entry%%:*}"
    rtl_list="${entry##*:}"

    rtl_files=""
    for f in $rtl_list; do rtl_files="$rtl_files $RTL_DIR/$f"; done

    echo "--- [$((PASS+FAIL+1))/$TOTAL] $name ---"

    # Compile FIR IP if needed
    if [ "$name" = "tb_qpsk_frame_sync_top" ]; then
        compile_fir_ip
    fi

    # Compile RTL + TB
    if ! xvlog -sv $rtl_files ${name}.sv > /dev/null 2>&1; then
        echo "  COMPILE ERROR"
        FAIL=$((FAIL+1))
        continue
    fi

    # Elaborate
    if ! xelab $(xelab_args $name) $name -s $name > /dev/null 2>&1; then
        echo "  ELABORATE ERROR"
        FAIL=$((FAIL+1))
        continue
    fi

    # Run
    result=$(xsim $name -runall 2>&1)
    if echo "$result" | grep -q "PASS"; then
        echo "  PASS"
        PASS=$((PASS+1))
    else
        echo "  FAIL"
        echo "$result" | grep -E "FAIL|ERROR|BIT" | head -5
        FAIL=$((FAIL+1))
    fi
done

echo ""
echo "========================================"
echo " Results: $PASS PASS / $FAIL FAIL / $TOTAL total"
echo "========================================"

# Cleanup
rm -rf xsim.dir .Xil *.jou *.log *.pb *.wdb webtalk* 2>/dev/null

exit $FAIL
