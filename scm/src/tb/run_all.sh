#!/bin/bash
# Run all 8 testbenches (text mode, PASS/FAIL only)
# Usage: ./run_all.sh
#   or:  ./run_all.sh gui <tb_name>   (open specific TB in GUI with waveform)

set -e
cd "$(dirname "$0")"

RTL_DIR="../rtl"
PASS=0
FAIL=0
TOTAL=8

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
)

# GUI mode: open specific TB
if [ "$1" = "gui" ] && [ -n "$2" ]; then
    for entry in "${TBS[@]}"; do
        name="${entry%%:*}"
        rtl_list="${entry##*:}"
        if [ "$name" = "$2" ]; then
            rtl_files=""
            for f in $rtl_list; do rtl_files="$rtl_files $RTL_DIR/$f"; done
            echo "=== Compiling $name ==="
            xvlog -sv $rtl_files ${name}.sv
            xelab -debug typical $name -s $name
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

    # Compile
    if ! xvlog -sv $rtl_files ${name}.sv > /dev/null 2>&1; then
        echo "  COMPILE ERROR"
        FAIL=$((FAIL+1))
        continue
    fi

    # Elaborate
    if ! xelab -debug typical $name -s $name > /dev/null 2>&1; then
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
