"""
Single Carrier Modem simulation - matches RTL in scm/src/rtl/

Signal chain (RTL-equivalent):
  TX: QPSK symbols -> frame_builder -> upsample_zeros(x4) -> RRC filter
  RX: RRC matched filter -> downsample_pick(÷4) -> preamble_correlator -> frame_sync_detector

Parameters from RTL (qpsk_frame_sync_top.sv):
  W            = 16    (symbol bit width)
  W_2          = 40    (TX RRC output width)
  W_3          = 56    (RX RRC output width)
  SPS          = 4
  PREAMBLE_LEN = 16
  SCALE        = 12000 (preamble amplitude)
"""

import numpy as np
import matplotlib.pyplot as plt
from rrc_filter import rrc_filter, quantize_to_int

# =============================================================================
# RTL Parameters
# =============================================================================
W = 16
SPS = 4
BETA = 0.35
SPAN = 10
PREAMBLE_LEN = 16
SCALE = 12000

# Preamble pattern (from frame_builder.sv / preamble_correlator.sv)
PREAMBLE_I = np.array([
     SCALE,  SCALE,  SCALE, -SCALE,
    -SCALE,  SCALE, -SCALE,  SCALE,
     SCALE, -SCALE, -SCALE,  SCALE,
    -SCALE, -SCALE,  SCALE,  SCALE,
], dtype=np.float64)

PREAMBLE_Q = np.array([
     SCALE,  SCALE, -SCALE, -SCALE,
     SCALE,  SCALE, -SCALE, -SCALE,
     SCALE, -SCALE, -SCALE,  SCALE,
     SCALE,  SCALE, -SCALE,  SCALE,
], dtype=np.float64)

# RRC filter coefficients (from COE file, 16-bit quantized)
RRC_COEFS_INT = np.array([
    224, -71, -348, -307, 61, 398, 286, -286, -761, -442,
    766, 1954, 1708, -660, -4042, -5641, -2533, 6187, 18177, 28625,
    32767,
    28625, 18177, 6187, -2533, -5641, -4042, -660, 1708, 1954, 766,
    -442, -761, -286, 286, 398, 61, -307, -348, -71, 224,
], dtype=np.float64)

# Normalized coefficients for Python simulation (unit energy)
RRC_COEFS = RRC_COEFS_INT / np.sqrt(np.sum(RRC_COEFS_INT ** 2))

# Filter group delay in samples (single filter)
RRC_DELAY = (len(RRC_COEFS) - 1) // 2  # = 20 samples


# =============================================================================
# TX: QPSK Modulation
# =============================================================================
def qpsk_modulate(bits):
    """Map bits to QPSK symbols. 0->+SCALE, 1->-SCALE."""
    assert len(bits) % 2 == 0
    I = np.where(bits[0::2] == 0, SCALE, -SCALE).astype(np.float64)
    Q = np.where(bits[1::2] == 0, SCALE, -SCALE).astype(np.float64)
    return I, Q


# =============================================================================
# TX: Frame Builder (frame_builder.sv)
# =============================================================================
def frame_builder(payload_i, payload_q):
    """Prepend preamble to payload."""
    frame_i = np.concatenate([PREAMBLE_I, payload_i])
    frame_q = np.concatenate([PREAMBLE_Q, payload_q])
    return frame_i, frame_q


# =============================================================================
# TX: Upsample with zero insertion (axis_upsample_zeros.sv)
# =============================================================================
def upsample_zeros(sym_i, sym_q, sps):
    """Insert zeros between symbols. Phase 0 = symbol, phase 1..SPS-1 = 0."""
    n = len(sym_i)
    up_i = np.zeros(n * sps)
    up_q = np.zeros(n * sps)
    up_i[::sps] = sym_i
    up_q[::sps] = sym_q
    return up_i, up_q


# =============================================================================
# TX: RRC Filter (fir_rrc IP)
# =============================================================================
def rrc_filter_apply(x, coefs):
    """Apply FIR filter (same as Vivado FIR Compiler)."""
    return np.convolve(x, coefs, mode="full")


# =============================================================================
# Channel: AWGN
# =============================================================================
def add_awgn(sig_i, sig_q, snr_db, rng):
    """Add white Gaussian noise to I/Q channels."""
    power = np.mean(sig_i ** 2 + sig_q ** 2)
    noise_power = power / (10 ** (snr_db / 10))
    sigma = np.sqrt(noise_power / 2)
    sig_i = sig_i + rng.normal(0, sigma, size=sig_i.shape)
    sig_q = sig_q + rng.normal(0, sigma, size=sig_q.shape)
    return sig_i, sig_q


# =============================================================================
# RX: RRC Matched Filter (fir_rrc_rx IP)
# =============================================================================
# Same function as rrc_filter_apply (same coefficients for matched filter)


# =============================================================================
# RX: Downsample pick (axis_downsample_pick.sv)
# =============================================================================
def downsample_pick(sig_i, sig_q, sps, offset=0):
    """Pick every SPS-th sample starting at offset."""
    return sig_i[offset::sps], sig_q[offset::sps]


# =============================================================================
# RX: Preamble Correlator (preamble_correlator.sv)
# =============================================================================
def preamble_correlator(rx_i, rx_q):
    """
    Sliding cross-correlation with known preamble.
    R[n] = Σ_k r[n-k] * conj(p[L-1-k])

    Uses time-reversed reference so peak aligns to end of preamble:
      corr_I = Σ( r_I[n-k]*p_I[L-1-k] + r_Q[n-k]*p_Q[L-1-k] )
      corr_Q = Σ( r_Q[n-k]*p_I[L-1-k] - r_I[n-k]*p_Q[L-1-k] )

    NOTE: RTL (preamble_correlator.sv) uses shift_i[k]*PREAMBLE[k] which
    is equivalent because shift_i[k] = rx[n-k], making it a convolution.
    Here we explicitly reverse the reference for correct peak alignment.
    """
    L = PREAMBLE_LEN
    N = len(rx_i)
    corr_i = np.zeros(N)
    corr_q = np.zeros(N)

    # Time-reversed preamble reference (matched filter)
    pI_rev = PREAMBLE_I[::-1]
    pQ_rev = PREAMBLE_Q[::-1]

    for n in range(L - 1, N):
        for k in range(L):
            corr_i[n] += rx_i[n - k] * pI_rev[k] + rx_q[n - k] * pQ_rev[k]
            corr_q[n] += rx_q[n - k] * pI_rev[k] - rx_i[n - k] * pQ_rev[k]

    return corr_i, corr_q


# =============================================================================
# RX: Frame Sync Detector (frame_sync_detector.sv)
# =============================================================================
def frame_sync_detector(corr_i, corr_q, threshold, cooldown=32):
    """
    Detect frame by thresholding |R|^2 = corr_I^2 + corr_Q^2.
    Returns list of (index, magnitude) for each detection.
    """
    mag_sq = corr_i ** 2 + corr_q ** 2
    detections = []
    cooldown_cnt = 0

    for n in range(len(mag_sq)):
        if cooldown_cnt > 0:
            cooldown_cnt -= 1
            continue
        if mag_sq[n] > threshold:
            detections.append((n, mag_sq[n]))
            cooldown_cnt = cooldown

    return detections, mag_sq


# =============================================================================
# RX: QPSK Demodulation
# =============================================================================
def qpsk_demodulate(rx_i, rx_q):
    """Hard decision: positive -> 0, negative -> 1."""
    bits = np.empty(len(rx_i) * 2, dtype=np.int8)
    bits[0::2] = (rx_i < 0).astype(np.int8)
    bits[1::2] = (rx_q < 0).astype(np.int8)
    return bits


# =============================================================================
# Main Simulation
# =============================================================================
def run_simulation(n_payload_syms=100, snr_db=20, seed=42, save_path=None):
    rng = np.random.default_rng(seed)

    # --- TX ---
    n_bits = n_payload_syms * 2
    tx_bits = rng.integers(0, 2, size=n_bits, dtype=np.int8)
    payload_i, payload_q = qpsk_modulate(tx_bits)

    # Frame builder: preamble + payload
    frame_i, frame_q = frame_builder(payload_i, payload_q)
    n_frame_syms = len(frame_i)
    print(f"Frame: {PREAMBLE_LEN} preamble + {n_payload_syms} payload = {n_frame_syms} symbols")

    # Upsample
    up_i, up_q = upsample_zeros(frame_i, frame_q, SPS)

    # TX RRC filter
    tx_i = rrc_filter_apply(up_i, RRC_COEFS)
    tx_q = rrc_filter_apply(up_q, RRC_COEFS)
    print(f"TX samples: {len(tx_i)}")

    # --- Channel ---
    rx_i, rx_q = add_awgn(tx_i, tx_q, snr_db, rng)

    # --- RX ---
    # RX matched filter (same RRC coefficients)
    rxf_i = rrc_filter_apply(rx_i, RRC_COEFS)
    rxf_q = rrc_filter_apply(rx_q, RRC_COEFS)

    # Downsample (offset=0 is correct: total group delay = 40 samples, 40%4=0)
    rxd_i, rxd_q = downsample_pick(rxf_i, rxf_q, SPS, offset=0)

    # Account for double-RRC filter group delay in symbol domain
    # Total delay = 2 * RRC_DELAY = 40 samples = 10 symbols
    sym_delay = 2 * RRC_DELAY // SPS  # = 10

    # Preamble correlator
    corr_i, corr_q = preamble_correlator(rxd_i, rxd_q)

    # Frame sync detector - use adaptive threshold (peak * 0.5)
    mag_sq = corr_i ** 2 + corr_q ** 2
    peak_mag = np.max(mag_sq)
    threshold = peak_mag * 0.5
    detections, mag_sq = frame_sync_detector(corr_i, corr_q, threshold, cooldown=32)
    print(f"Sync detections: {len(detections)}")
    for idx, mag in detections:
        print(f"  index={idx}, mag={mag:.2e}")

    # Extract payload symbols (after preamble, accounting for filter delay)
    rx_bits_out = None
    ber = None
    if detections:
        sync_idx = detections[0][0]
        # sync_idx points to end of preamble correlation peak
        payload_start = sync_idx + 1
        payload_end = payload_start + n_payload_syms
        if payload_end <= len(rxd_i):
            rx_payload_i = rxd_i[payload_start:payload_end]
            rx_payload_q = rxd_q[payload_start:payload_end]
            rx_bits_out = qpsk_demodulate(rx_payload_i, rx_payload_q)
            ber = np.mean(rx_bits_out != tx_bits)
            print(f"BER = {ber:.6e} (SNR={snr_db} dB)")
        else:
            print("Not enough samples for full payload extraction")
    else:
        print("No sync detected!")

    # --- Plots ---
    fig, axes = plt.subplots(3, 2, figsize=(14, 10))
    fig.suptitle(f"QPSK Modem Simulation (SNR={snr_db} dB, {n_payload_syms} payload symbols)", fontsize=14)

    # TX constellation (payload only)
    axes[0, 0].scatter(payload_i, payload_q, s=10, alpha=0.5)
    axes[0, 0].set_title("TX Constellation (payload)")
    axes[0, 0].set_xlabel("I")
    axes[0, 0].set_ylabel("Q")
    axes[0, 0].grid(True)
    axes[0, 0].axis("equal")

    # TX waveform (first few symbols)
    n_show = min(len(tx_i), 20 * SPS)
    axes[0, 1].plot(tx_i[:n_show], label="I")
    axes[0, 1].plot(tx_q[:n_show], label="Q", alpha=0.7)
    axes[0, 1].set_title("TX Waveform (after RRC)")
    axes[0, 1].set_xlabel("Sample")
    axes[0, 1].legend()
    axes[0, 1].grid(True)

    # RX after matched filter (zoom to symbol-rate, show symbol sampling points)
    n_show_rx = min(len(rxf_i), 30 * SPS)
    axes[1, 0].plot(rxf_i[:n_show_rx], label="I", alpha=0.7)
    axes[1, 0].plot(rxf_q[:n_show_rx], label="Q", alpha=0.5)
    # Mark downsample points
    ds_idx = np.arange(0, n_show_rx, SPS)
    axes[1, 0].plot(ds_idx, rxf_i[ds_idx], "ro", markersize=4, label="sample pts")
    axes[1, 0].set_title("RX after Matched Filter (dots=sample points)")
    axes[1, 0].set_xlabel("Sample")
    axes[1, 0].legend()
    axes[1, 0].grid(True)

    # Correlation magnitude
    axes[1, 1].plot(mag_sq)
    axes[1, 1].axhline(y=threshold, color="r", linestyle="--", label=f"threshold ({threshold:.1e})")
    for idx, mag in detections:
        axes[1, 1].axvline(x=idx, color="g", linestyle="--", alpha=0.5)
    axes[1, 1].set_title("Correlation |R|^2")
    axes[1, 1].set_xlabel("Symbol index")
    axes[1, 1].legend()
    axes[1, 1].grid(True)
    axes[1, 1].set_yscale("log")

    # RX constellation (payload only, after sync)
    if detections:
        sync_idx = detections[0][0]
        ps = sync_idx + 1
        pe = ps + n_payload_syms
        if pe <= len(rxd_i):
            axes[2, 0].scatter(rxd_i[ps:pe], rxd_q[ps:pe], s=10, alpha=0.5, label="payload")
    axes[2, 0].set_title(f"RX Constellation (payload, SNR={snr_db}dB)")
    axes[2, 0].set_xlabel("I")
    axes[2, 0].set_ylabel("Q")
    axes[2, 0].grid(True)
    axes[2, 0].axis("equal")
    if ber is not None:
        axes[2, 0].set_title(f"RX Constellation (BER={ber:.2e}, SNR={snr_db}dB)")

    # Eye diagram (I channel, after matched filter, aligned to symbol period)
    # Skip filter transient (first sym_delay * SPS samples)
    eye_start = 2 * RRC_DELAY
    L = 2 * SPS
    n_traces = min(200, (len(rxf_i) - eye_start) // L)
    t_eye = np.arange(L) / SPS
    for k in range(n_traces):
        start = eye_start + k * L
        axes[2, 1].plot(t_eye, rxf_i[start:start + L], color="C0", alpha=0.1)
    axes[2, 1].set_title("Eye Diagram (I, after matched filter)")
    axes[2, 1].set_xlabel("Time (symbols)")
    axes[2, 1].grid(True)

    plt.tight_layout()
    if save_path:
        plt.savefig(save_path, dpi=150)
        print(f"Plot saved: {save_path}")
    else:
        plt.show()

    return {
        "tx_bits": tx_bits, "ber": ber, "detections": detections,
        "rxd_i": rxd_i, "rxd_q": rxd_q, "mag_sq": mag_sq,
    }


if __name__ == "__main__":
    import matplotlib
    matplotlib.use("Agg")
    import os
    save_dir = os.path.dirname(os.path.abspath(__file__))
    run_simulation(n_payload_syms=200, snr_db=20, seed=42,
                   save_path=os.path.join(save_dir, "sim_result.png"))
