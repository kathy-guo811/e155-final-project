"""Generate test vectors for gsr_filter.sv.

Makes a synthetic noisy GSR signal (32 Hz, codes at 62.5 uV/LSB), runs it
through a bit-exact Python copy of the FPGA filter, and writes:

  filter_in.hex        one 16-bit two's-complement sample per line
  filter_expected.hex  expected filter output for each input
  filter_vectors.png   plot of input vs expected output

Usage:  python3 gen_filter_vectors.py OUTPUT_DIR
"""
import sys
from pathlib import Path

import numpy as np

FS = 32          # samples per second
LSB = 62.5e-6    # volts per code (PGA +/-2.048 V)
K = 3            # must match gsr_filter's K
N = 1024         # number of samples (32 s)


def make_signal(seed=155):
    rng = np.random.default_rng(seed)
    t = np.arange(N) / FS
    v = 0.50 + 0.002 * t                              # 0.5 V baseline, slow drift
    for onset, amp in [(8.0, 0.12), (20.0, 0.06)]:    # two SCRs (seconds, volts)
        tt = np.clip(t - onset, 0, None)
        v += amp * (1 - np.exp(-tt / 0.5)) * np.exp(-tt / 4.0)
    v += rng.normal(0, 0.002, N)                      # ~2 mV RMS noise (32 codes)
    v[[300, 650]] += 0.03                             # two motion-artifact spikes
    codes = np.round(v / LSB).astype(int)
    return np.clip(codes, -32768, 32767)


def iir_filter(x, k=K):
    """Bit-exact model of gsr_filter.sv.

    Python's >> on negative ints is an arithmetic (floor) shift, the same as
    SystemVerilog's >>> on a signed value, so this matches the hardware.
    """
    y = []
    acc = None
    for s in x:
        acc = (s << k) if acc is None else acc + s - (acc >> k)
        y.append(acc >> k)
    return np.array(y)


def write_hex(path, values):
    with open(path, "w") as f:
        for v in values:
            f.write(f"{int(v) & 0xFFFF:04x}\n")       # 16-bit two's complement


def main():
    out = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    out.mkdir(parents=True, exist_ok=True)

    x = make_signal()
    y = iir_filter(x)
    write_hex(out / "filter_in.hex", x)
    write_hex(out / "filter_expected.hex", y)
    print(f"wrote {N} vectors to {out}/")

    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        t = np.arange(N) / FS
        plt.figure(figsize=(10, 4))
        plt.plot(t, x * LSB, lw=0.7, alpha=0.5, label="raw input")
        plt.plot(t, y * LSB, lw=1.6, label=f"IIR output (alpha = 1/{2**K})")
        plt.xlabel("time (s)")
        plt.ylabel("voltage (V)")
        plt.title("GSR filter test vectors")
        plt.legend()
        plt.tight_layout()
        plt.savefig(out / "filter_vectors.png", dpi=150)
        print(f"wrote {out}/filter_vectors.png")
    except ImportError:
        pass


if __name__ == "__main__":
    main()
