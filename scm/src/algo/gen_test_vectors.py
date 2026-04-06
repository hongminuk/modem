"""
Generate test vectors for RTL simulation.
Writes hex files that can be loaded by $readmemh in SystemVerilog testbenches.

Generates:
  tv_tx_bits.hex       - TX input bits (2 bits per line)
  tv_mod_i.hex         - Modulator output I (16-bit signed hex)
  tv_mod_q.hex         - Modulator output Q (16-bit signed hex)
  tv_frame_i.hex       - Frame builder output I
  tv_frame_q.hex       - Frame builder output Q
  tv_demod_bits.hex    - Expected demod output (2 bits per line)
"""

import numpy as np
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from scm_sim import (
    qpsk_modulate, frame_builder, qpsk_demodulate,
    SCALE, PREAMBLE_LEN, PREAMBLE_I, PREAMBLE_Q,
)

TV_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tb")


def to_hex_signed(val, bits=16):
    """Convert signed integer to hex string."""
    if val < 0:
        val = (1 << bits) + val
    return f"{val:0{bits // 4}X}"


def write_hex_file(path, values, bits=16):
    with open(path, "w") as f:
        for v in values:
            f.write(to_hex_signed(int(v), bits) + "\n")


def write_bits_file(path, bit_pairs):
    """Write 2-bit values as hex (00, 01, 02, 03)."""
    with open(path, "w") as f:
        for b in bit_pairs:
            f.write(f"{int(b):02X}\n")


def main():
    rng = np.random.default_rng(42)
    n_payload = 20
    n_bits = n_payload * 2
    tx_bits = rng.integers(0, 2, size=n_bits, dtype=np.int8)

    # QPSK Modulation
    payload_i, payload_q = qpsk_modulate(tx_bits)

    # Frame Builder
    frame_i, frame_q = frame_builder(payload_i, payload_q)

    # Pack bits into 2-bit values: in_data[0]=I bit, in_data[1]=Q bit
    tx_bit_pairs = []
    for k in range(n_payload):
        pair = tx_bits[2 * k] | (tx_bits[2 * k + 1] << 1)
        tx_bit_pairs.append(pair)

    # Demod expected: from known symbols
    demod_bits = qpsk_demodulate(frame_i, frame_q)
    demod_pairs = []
    for k in range(len(frame_i)):
        pair = demod_bits[2 * k] | (demod_bits[2 * k + 1] << 1)
        demod_pairs.append(pair)

    # Write files
    os.makedirs(TV_DIR, exist_ok=True)
    write_bits_file(os.path.join(TV_DIR, "tv_tx_bits.hex"), tx_bit_pairs)
    write_hex_file(os.path.join(TV_DIR, "tv_mod_i.hex"), payload_i, 16)
    write_hex_file(os.path.join(TV_DIR, "tv_mod_q.hex"), payload_q, 16)
    write_hex_file(os.path.join(TV_DIR, "tv_frame_i.hex"), frame_i, 16)
    write_hex_file(os.path.join(TV_DIR, "tv_frame_q.hex"), frame_q, 16)
    write_bits_file(os.path.join(TV_DIR, "tv_demod_bits.hex"), demod_pairs)

    print(f"Generated test vectors in {TV_DIR}/")
    print(f"  tx_bits:    {len(tx_bit_pairs)} entries")
    print(f"  mod_i/q:    {len(payload_i)} entries")
    print(f"  frame_i/q:  {len(frame_i)} entries")
    print(f"  demod_bits: {len(demod_pairs)} entries")

    # Print first few for verification
    print("\nFirst 5 tx_bit_pairs:", tx_bit_pairs[:5])
    print("First 5 mod_i:", payload_i[:5].astype(int))
    print("First 5 mod_q:", payload_q[:5].astype(int))
    print("Frame I (preamble start):", frame_i[:4].astype(int))


if __name__ == "__main__":
    main()
