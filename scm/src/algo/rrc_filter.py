"""
RRC Filter coefficient generation and COE file export.
Matches RTL: fir_rrc / fir_rrc_rx (FIR Compiler IP)

Parameters (from RTL):
  SPS  = 4
  beta = 0.35
  span = 10 symbols
  coef_bits = 16 (signed)
  taps = span * sPS + 1 = 41
"""

import numpy as np
import matplotlib.pyplot as plt


def rrc_filter(beta, span, sps):
    N = span * sps
    t = np.arange(-N / 2, N / 2 + 1) / sps
    h = np.zeros_like(t, dtype=np.float64)

    for i, ti in enumerate(t):
        if np.isclose(ti, 0.0):
            h[i] = 1.0 - beta + (4.0 * beta / np.pi)
        elif beta != 0 and np.isclose(abs(ti), 1.0 / (4.0 * beta)):
            h[i] = (beta / np.sqrt(2.0)) * (
                (1.0 + 2.0 / np.pi) * np.sin(np.pi / (4.0 * beta))
                + (1.0 - 2.0 / np.pi) * np.cos(np.pi / (4.0 * beta))
            )
        else:
            num = np.sin(np.pi * ti * (1.0 - beta)) + 4.0 * beta * ti * np.cos(np.pi * ti * (1.0 + beta))
            den = np.pi * ti * (1.0 - (4.0 * beta * ti) ** 2)
            h[i] = num / den

    h /= np.sqrt(np.sum(h ** 2))
    return h


def quantize_to_int(h, coef_bits=16):
    maxv = np.max(np.abs(h))
    full = 2 ** (coef_bits - 1) - 1
    scale = full / maxv
    hq = np.round(h * scale).astype(np.int64)
    hq = np.clip(hq, -(2 ** (coef_bits - 1)), 2 ** (coef_bits - 1) - 1)
    return hq, scale


def write_coe(path, coeff_int, radix=10):
    with open(path, "w") as f:
        f.write(f"radix={radix};\n")
        coef_str = " ".join(str(int(c)) for c in coeff_int)
        f.write(f"coefdata={coef_str};\n")


def plot_rrc(h, hq, sps):
    taps = len(h)
    n = np.arange(taps)
    t_sym = (n - (taps - 1) / 2) / sps

    Nfft = 8192
    H = np.fft.fftshift(np.fft.fft(h, Nfft))
    f = np.fft.fftshift(np.fft.fftfreq(Nfft))

    hq_f = hq.astype(np.float64)
    hq_f /= np.sqrt(np.sum(hq_f ** 2))
    Hq = np.fft.fftshift(np.fft.fft(hq_f, Nfft))

    fig, axes = plt.subplots(2, 2, figsize=(12, 8))

    axes[0, 0].stem(t_sym, h, basefmt=" ")
    axes[0, 0].set_title(f"RRC taps (float), {taps} taps, SPS={sps}")
    axes[0, 0].set_xlabel("Time (symbols)")
    axes[0, 0].grid(True)

    axes[0, 1].stem(t_sym, hq, basefmt=" ")
    axes[0, 1].set_title("RRC taps (16-bit quantized)")
    axes[0, 1].set_xlabel("Time (symbols)")
    axes[0, 1].grid(True)

    axes[1, 0].plot(f, 20 * np.log10(np.abs(H) + 1e-12), label="float")
    axes[1, 0].plot(f, 20 * np.log10(np.abs(Hq) + 1e-12), "--", label="quantized")
    axes[1, 0].set_title("Magnitude Response (dB)")
    axes[1, 0].set_xlabel("Normalized frequency")
    axes[1, 0].set_ylabel("dB")
    axes[1, 0].legend()
    axes[1, 0].grid(True)

    err = hq.astype(np.float64) / np.max(np.abs(hq)) - h / np.max(np.abs(h))
    axes[1, 1].stem(t_sym, err, basefmt=" ")
    axes[1, 1].set_title("Quantization Error (normalized)")
    axes[1, 1].set_xlabel("Time (symbols)")
    axes[1, 1].grid(True)

    plt.tight_layout()
    plt.show()


if __name__ == "__main__":
    # Parameters matching RTL
    SPS = 4
    BETA = 0.35
    SPAN = 10
    COEF_BITS = 16

    h = rrc_filter(BETA, SPAN, SPS)
    hq, scale = quantize_to_int(h, COEF_BITS)

    fname = f"rrc_sps{SPS}_beta{BETA}_span{SPAN}_q{COEF_BITS}p.coe".replace(".", "p")
    write_coe(fname, hq)

    print(f"Taps: {len(h)} (expected {SPAN * SPS + 1})")
    print(f"Scale: {scale:.3f}")
    print(f"Coefficients: {hq.tolist()}")
    print(f"COE file: {fname}")

    plot_rrc(h, hq, SPS)
