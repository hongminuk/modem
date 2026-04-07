# Bug Report: qpsk_frame_sync_top & frame_sync_detector

| Field | Value |
|-------|-------|
| **Severity** | Critical (multi-driver), Medium (param width) |
| **Component** | `qpsk_frame_sync_top.sv`, `frame_sync_detector.sv` |
| **Status** | Fixed |
| **Detected** | 2026-04-08 (during tb_qpsk_frame_sync_top creation) |
| **Affects** | End-to-end RX path operation |

---

## Bug #1: Multiple Driver on `rx_dn_ready` (Critical)

### 1.1 Location

`scm/src/rtl/qpsk_frame_sync_top.sv` lines 234, 249, 253, 272 (before fix)

### 1.2 Symptom

```
ERROR: [VRFC 10-3823] variable 'rx_dn_ready' might have multiple concurrent drivers
[/home/hong/workspace_claude/modem/scm/src/rtl/qpsk_frame_sync_top.sv:272]
```

The design **failed elaboration** as soon as a top-level testbench was created.
The original test environment (Vivado project mode) had been masking this error.

### 1.3 Root Cause

A single wire `rx_dn_ready` was connected to TWO module output ports simultaneously:

```systemverilog
// BEFORE (BUG):
logic rx_dn_ready;  // single wire

axis_downsample_pick u_rx_downsample (
    ...
    .in_ready(rx_dn_ready),     // OUTPUT — drives rx_dn_ready
    .out_ready(rx_dn_ready)     // INPUT  — also wired to same signal
);

preamble_correlator u_correlator (
    ...
    .in_ready(rx_dn_ready)      // OUTPUT — also drives rx_dn_ready (CONFLICT)
);
```

`axis_downsample_pick.in_ready` and `preamble_correlator.in_ready` are both
**output ports** (backpressure from receiver to upstream). Connecting both to
the same wire causes multi-driver contention.

### 1.4 Logical Confusion

The original code seems to confuse two distinct AXI-Stream backpressure signals:

1. **Downsample's upstream backpressure** (`u_rx_downsample.in_ready`):
   tells the RX FIR whether downsample can accept more samples.

2. **Correlator's upstream backpressure** (`u_correlator.in_ready`):
   tells the downsample whether correlator can accept more symbols.

These are **different signals** and must be separate wires.

### 1.5 Fix

Split into two separate wires:

```systemverilog
// AFTER (FIXED):
logic rx_dn_in_ready;   // downsample → upstream (FIR) backpressure
logic rx_dn_out_ready;  // correlator → downsample backpressure

assign rx_fir_ready = rx_dn_in_ready;

axis_downsample_pick u_rx_downsample (
    ...
    .in_ready(rx_dn_in_ready),
    .out_ready(rx_dn_out_ready)
);

preamble_correlator u_correlator (
    ...
    .in_ready(rx_dn_out_ready)
);
```

### 1.6 Why This Was Not Caught Earlier

- Vivado synthesis may have silently picked one driver and ignored the other
  (or caused random behavior depending on synthesis options)
- The original design had no end-to-end testbench at the RTL simulation level
- All previous testing was through Vivado project-mode synthesis flows that
  may have been more forgiving than xelab's strict elaboration

---

## Bug #2: THRESHOLD Parameter Width Mismatch (Medium)

### 2.1 Location

`scm/src/rtl/frame_sync_detector.sv` line 25 (before fix)
`scm/src/rtl/qpsk_frame_sync_top.sv` line 35 (passes value)

### 2.2 Symptom

When threshold is set to a 64-bit value (e.g., `64'd5_000_000_000_000_000_000`),
it gets truncated to 32 bits. After RX FIR filtering, signal magnitudes are huge
(`mag_sq` upper 64 bits ~ 10¹⁸ to 10¹⁹), so any 32-bit threshold is exceeded by
EVERY sample, causing **continuous false sync detections** (every cycle triggers).

Observed: 64 sync detections in a single 50-symbol payload test.

### 2.3 Root Cause

```systemverilog
// frame_sync_detector.sv (BEFORE):
module frame_sync_detector #(
    parameter int W_CORR    = 72,
    parameter int THRESHOLD = 32'd1000000000  // ← 32-bit int parameter
)(...)

// qpsk_frame_sync_top.sv (BEFORE):
parameter longint SYNC_THRESHOLD = 64'd500000000  // ← 64-bit declared
...
frame_sync_detector #(
    .W_CORR(W_CORR),
    .THRESHOLD(SYNC_THRESHOLD)  // ← 64-bit value passed to 32-bit param!
) u_detector (...);
```

The parameter type `int` in SystemVerilog is 32-bit signed. Passing a 64-bit
`longint` value silently truncates to the lower 32 bits.

Comparison logic in detector:

```systemverilog
if (mag_sq_d1[127:64] > THRESHOLD) ...
```

`mag_sq_d1[127:64]` is 64-bit but `THRESHOLD` is 32-bit. The comparison
implicitly extends THRESHOLD to 64-bit (zero-extended). For 32-bit max
(0x7FFFFFFF ≈ 2.1e9), any `mag_sq_d1[127:64] > 2.1e9` triggers — and after FIR,
mag_sq[127:64] is in the 10¹⁸ range, so this is ALWAYS true.

### 2.4 Fix

Change parameter type to `longint`:

```systemverilog
// frame_sync_detector.sv (AFTER):
module frame_sync_detector #(
    parameter int      W_CORR    = 72,
    parameter longint  THRESHOLD = 64'd1000000000  // ← 64-bit
)(...)
```

Now `THRESHOLD` matches the width of `mag_sq_d1[127:64]` and 64-bit threshold
values pass through correctly.

### 2.5 Verification

After fix, with `SYNC_THRESHOLD = 64'd10_000_000_000_000_000_000` (1e19):

```
=== qpsk_frame_sync_top Testbench (with FIR IP) ===
  >> SYNC: index=26, mag=14794049535802713184
  >> SYNC: index=142, mag=14768134461927102823    (second frame)
RX symbols collected: 232
Sync detections:      2                            (one per frame, not 64!)
Best alignment: offset=26, errors=0 / 100
PASS: End-to-end (with FIR) BER = 0/100!
```

---

## 3. Test Methodology

The bugs were discovered while creating `tb_qpsk_frame_sync_top.sv`, the first
RTL testbench targeting the actual `qpsk_frame_sync_top` module (with real FIR
Compiler IP). Previous testing used:

- `tb_loopback_no_fir.sv`: connects internal blocks individually, bypassing FIR.
  Did NOT instantiate `qpsk_frame_sync_top` so missed Bug #1.
- Vivado project-mode synthesis: tolerates multi-driver in some cases.

### 3.1 FIR IP Compilation

To run xsim against the real top with Xilinx FIR Compiler IP:

```bash
xvhdl -work xil_defaultlib \
  ../../Vivado_Project/single_carrier_modem.gen/sources_1/ip/fir_rrc/sim/fir_rrc.vhd \
  ../../Vivado_Project/single_carrier_modem.gen/sources_1/ip/fir_rrc_rx/sim/fir_rrc_rx.vhd

# Copy MIF coefficient files to working directory
cp .../fir_rrc/fir_rrc.mif .
cp .../fir_rrc_rx/fir_rrc_rx.mif .

xvlog -sv <RTL files> tb_qpsk_frame_sync_top.sv
xelab -L xil_defaultlib -L fir_compiler_v7_2_23 tb_qpsk_frame_sync_top -s sim_top
xsim sim_top -runall
```

The precompiled FIR Compiler library ships with Vivado at:
`/tools/Xilinx/Vivado/2024.2/data/xsim/ip/fir_compiler_v7_2_23`

---

## 4. Impact Summary

| Bug | Pre-Fix Behavior | Post-Fix Behavior |
|-----|------------------|-------------------|
| #1 Multi-driver | Elaboration fails (xsim) / undefined behavior (synthesis) | Clean elaboration |
| #2 Param width | Continuous false sync (every cycle) | Single sync per frame |

End-to-end test result after both fixes: **BER = 0/100** at SNR = ∞ (loopback).

---

## 5. Lessons Learned

1. **End-to-end RTL TBs catch system-level bugs**: Block-level TBs cannot
   detect multi-driver issues that occur only at the top-level interconnect.

2. **xsim is stricter than synthesis**: An xsim elaboration check would have
   caught Bug #1 immediately. Always run RTL simulation before synthesis.

3. **Parameter type matters in SystemVerilog**: `int` vs `longint` is silent
   truncation. Always size parameters to match the data they control.

4. **Test infrastructure must include the real top module**: Loopback TBs
   that "rebuild" the system from sub-blocks miss top-level bugs.
