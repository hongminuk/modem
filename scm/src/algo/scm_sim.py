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
RRC_COEFS = np.array([
    224, -71, -348, -307, 61, 398, 286, -286, -761, -442,
    766, 1954, 1708, -660, -4042, -5641, -2533, 6187, 18177, 28625,
    32767,
    28625, 18177, 6187, -2533, -5641, -4042, -660, 1708, 1954, 766,
    -442, -761, -286, 286, 398, 61, -307, -348, -71, 224,
], dtype=np.float64)


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
    R[n] = sum_k ( r[n-k] * conj(p[k]) )
    corr_I = sum( r_I*p_I + r_Q*p_Q )
    corr_Q = sum( r_Q*p_I - r_I*p_Q )
    """
    L = PREAMBLE_LEN
    N = len(rx_i)
    corr_i = np.zeros(N)
    corr_q = np.zeros(N)

    for n in range(L - 1, N):
        for k in range(L):
            corr_i[n] += rx_i[n - k] * PREAMBLE_I[k] + rx_q[n - k] * PREAMBLE_Q[k]
            corr_q[n] += rx_q[n - k] * PREAMBLE_I[k] - rx_i[n - k] * PREAMBLE_Q[k]

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
def run_simulation(n_payload_syms=100, snr_db=20, seed=42):
    rng = np.random.default_rng(seed)

    # --- TX ---
    n_bits = n_payload_syms * 2
    tx_bits = rng.integers(0, 2, size=n_bits, dtype=np.int8)
    payload_i, payload_q = qpsk_modulate(tx_bits)

    # Frame builder: preamble + payload
    frame_i, frame_q = frame_builder(payload_i, payload_q)
    print(f"Frame: {PREAMBLE_LEN} preamble + {n_payload_syms} payload = {len(frame_i)} symbols")

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

    # Downsample
    # Find optimal offset by checking group delay: 2 * (len(RRC)-1)//2 = 40 samples
    # With SPS=4, offset 0 should align to symbol centers after double RRC filtering
    rxd_i, rxd_q = downsample_pick(rxf_i, rxf_q, SPS, offset=0)

    # Preamble correlator
    corr_i, corr_q = preamble_correlator(rxd_i, rxd_q)

    # Frame sync detector
    threshold = 1e18  # Adjust based on signal levels
    detections, mag_sq = frame_sync_detector(corr_i, corr_q, threshold)
    print(f"Sync detections: {len(detections)}")
    for idx, mag in detections:
        print(f"  index={idx}, mag={mag:.2e}")

    # Extract payload symbols (after preamble)
    if detections:
        sync_idx = detections[0][0]
        payload_start = sync_idx + 1
        payload_end = payload_start + n_payload_syms
        if payload_end <= len(rxd_i):
            rx_payload_i = rxd_i[payload_start:payload_end]
            rx_payload_q = rxd_q[payload_start:payload_end]
            rx_bits = qpsk_demodulate(rx_payload_i, rx_payload_q)
            ber = np.mean(rx_bits != tx_bits)
            print(f"BER = {ber:.6e} (SNR={snr_db} dB)")
        else:
            print("Not enough samples for full payload extraction")
            rx_payload_i = rxd_i[payload_start:]
            rx_payload_q = rxd_q[payload_start:]
    else:
        print("No sync detected - trying without sync")
        rx_payload_i = rxd_i
        rx_payload_q = rxd_q

    # --- Plots ---
    fig, axes = plt.subplots(3, 2, figsize=(14, 10))

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

    # RX after matched filter
    axes[1, 0].plot(rxf_i[:n_show], label="I")
    axes[1, 0].plot(rxf_q[:n_show], label="Q", alpha=0.7)
    axes[1, 0].set_title("RX after Matched Filter")
    axes[1, 0].set_xlabel("Sample")
    axes[1, 0].legend()
    axes[1, 0].grid(True)

    # Correlation magnitude
    axes[1, 1].plot(mag_sq)
    axes[1, 1].axhline(y=threshold, color="r", linestyle="--", label="threshold")
    for idx, mag in detections:
        axes[1, 1].axvline(x=idx, color="g", linestyle="--", alpha=0.5)
    axes[1, 1].set_title("Correlation |R|^2")
    axes[1, 1].set_xlabel("Symbol index")
    axes[1, 1].legend()
    axes[1, 1].grid(True)

    # RX constellation (after downsample)
    axes[2, 0].scatter(rxd_i, rxd_q, s=10, alpha=0.3)
    axes[2, 0].set_title(f"RX Constellation (all, SNR={snr_db}dB)")
    axes[2, 0].set_xlabel("I")
    axes[2, 0].set_ylabel("Q")
    axes[2, 0].grid(True)
    axes[2, 0].axis("equal")

    # Eye diagram (I channel, after matched filter)
    L = 2 * SPS
    n_traces = min(200, len(rxf_i) // L)
    t_eye = np.arange(L) / SPS
    for k in range(n_traces):
        start = k * L
        axes[2, 1].plot(t_eye, rxf_i[start:start + L], color="C0", alpha=0.1)
    axes[2, 1].set_title("Eye Diagram (I, after matched filter)")
    axes[2, 1].set_xlabel("Time (symbols)")
    axes[2, 1].grid(True)

    plt.tight_layout()
    plt.show()


if __name__ == "__main__":
    run_simulation(n_payload_syms=200, snr_db=20, seed=42)
