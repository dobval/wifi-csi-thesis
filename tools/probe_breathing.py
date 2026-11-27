#!/usr/bin/env python3
"""Look for a breathing signature in an alternating capture.

    python3 tools/probe_breathing.py data/<session> [--band 0.1 0.5]

Amplitude features are RSSI-equivalent: the radio already reports a scalar level,
and the near-field run showed the perturbation is frequency-flat. Phase is the one
channel RSSI cannot see, because a stationary chest wall changes the electrical
path length at ~0.2-0.3 Hz.

For every block this reports the spectral SNR in the breathing band from three
series:

  phase      CSI phase, unwrapped in time and with the per-frame linear
             subcarrier trend removed (that linear term is the CFO/SFO artefact)
  amplitude  per-subcarrier |H|
  rssi       the scalar the radio reports

SNR is peak power / median power inside the band. Per-subcarrier values are
summarised by their median so a single lucky subcarrier cannot carry the result.
"""
from __future__ import annotations

import argparse
import csv
import os
import sys

import numpy as np

FIELDS = 25


def load_iq(session: str):
    re_, im_, rssi, ts = [], [], [], []
    with open(os.path.join(session, "csi.csv"), newline="") as f:
        for row in csv.reader(f):
            if len(row) != FIELDS or row[0] != "CSI_DATA":
                continue
            try:
                v = [int(t) for t in row[24].strip().strip('"[]').split(",")]
            except ValueError:
                continue
            if len(v) != 128:
                continue
            im_.append(v[0::2])
            re_.append(v[1::2])
            rssi.append(float(row[3]))
            ts.append(int(row[18]))
    im_ = np.asarray(im_, float)
    re_ = np.asarray(re_, float)
    ts = np.asarray(ts, np.int64)
    if not len(ts):
        sys.exit("no CSI rows")
    wraps = np.concatenate([[0], np.cumsum(np.diff(ts) < 0)]).astype(np.int64)
    t = (ts + wraps * 2 ** 32 - (ts[0] + 0)) / 1e6
    return im_, re_, np.asarray(rssi), t


def spectrum_snr(x: np.ndarray, fs: float, lo: float, hi: float) -> tuple[float, float]:
    """Peak/median power ratio in [lo, hi] Hz, and the peak frequency."""
    # Remove mean AND linear trend: sub-0.1 Hz drift otherwise leaks into the
    # 0.1-0.5 Hz band and makes empty blocks look like breathing.
    n0 = len(x)
    t0 = np.arange(n0, dtype=float)
    x = x - np.polyval(np.polyfit(t0, x, 1), t0)
    if x.std() == 0:
        return 0.0, 0.0
    n = len(x)
    w = np.hanning(n)
    p = np.abs(np.fft.rfft(x * w)) ** 2
    f = np.fft.rfftfreq(n, 1 / fs)
    band = (f >= lo) & (f <= hi)
    if not band.any():
        return 0.0, 0.0
    pb = p[band]
    if np.median(pb) <= 0:
        return 0.0, 0.0
    k = int(np.argmax(pb))
    return float(pb[k] / np.median(pb)), float(f[band][k])


def clean_phase(ph: np.ndarray) -> np.ndarray:
    """Unwrap in time, then remove the per-frame linear trend across subcarriers."""
    ph = np.unwrap(ph, axis=0)
    k = np.arange(ph.shape[1], dtype=float)
    k -= k.mean()
    denom = (k * k).sum()
    slope = (ph * k).sum(axis=1) / denom
    return ph - slope[:, None] * k[None, :]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("session")
    ap.add_argument("--band", nargs=2, type=float, default=(0.1, 0.5))
    ap.add_argument("--guard", type=float, default=10.0)
    args = ap.parse_args()

    im_, re_, rssi, t = load_iq(args.session)
    sched_path = os.path.join(args.session, "schedule.csv")
    if not os.path.isfile(sched_path):
        sys.exit(f"{sched_path} not found")
    sched = list(csv.DictReader(open(sched_path, newline="")))

    fs = 100.0
    amp = np.hypot(im_, re_)
    ph = clean_phase(np.arctan2(im_, re_))

    print(f"band {args.band[0]}-{args.band[1]} Hz   fs~{fs:.0f} Hz   "
          f"guard {args.guard:.0f} s\n")
    hdr = f"{'blk':>3} {'cond':<22} {'secs':>5} {'phase':>7} {'amp':>7} {'rssi':>7} {'peak Hz':>8}"
    print(hdr)
    rows = []
    for b in sched:
        t0 = float(b["t_start_s"]) + args.guard
        t1 = float(b["t_end_s"]) - args.guard
        m = (t >= t0) & (t < t1)
        if m.sum() < 500:
            continue
        secs = float(m.sum()) / fs
        p_snr = [spectrum_snr(ph[m, j], fs, *args.band) for j in range(ph.shape[1])]
        a_snr = [spectrum_snr(amp[m, j], fs, *args.band) for j in range(amp.shape[1])]
        r_snr = spectrum_snr(rssi[m], fs, *args.band)
        ph_med = float(np.median([s for s, _ in p_snr]))
        am_med = float(np.median([s for s, _ in a_snr]))
        pk = float(np.median([f for _, f in p_snr]))
        print(f"{int(b['block']):3d} {b['condition']:<22} {secs:5.1f} "
              f"{ph_med:7.2f} {am_med:7.2f} {r_snr[0]:7.2f} {pk:8.2f}")
        rows.append((b["condition"], ph_med, am_med, r_snr[0]))

    if rows:
        e = [r for r in rows if r[0] == "empty_room"]
        p = [r for r in rows if r[0] != "empty_room"]
        if e and p:
            print(f"\n  median over blocks   empty   person")
            for i, name in ((1, "phase SNR"), (2, "amp SNR  "), (3, "rssi SNR ")):
                print(f"  {name}          {np.median([r[i] for r in e]):6.2f}  "
                      f"{np.median([r[i] for r in p]):6.2f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
