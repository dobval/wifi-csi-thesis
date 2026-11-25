#!/usr/bin/env python3
"""Two-session CSI comparison probe (training-free).

    python3 tools/probe_l3.py data/<A> data/<B> [--profile] [--names A B]

Why there is no classifier here
-------------------------------
With one session per class, leave-one-session-out supervised learning is
impossible: training on session A gives you a single class, so the fitted
weights collapse to numerical noise and any AUC is arbitrary. (An earlier
version of this file made exactly that mistake; it reported AUC 0.976 from a
weight vector with norm 2e-16.)

What is done instead is a two-sample rank test per feature: the AUC of a single
feature between two groups is a Mann-Whitney U statistic, needs no training, and
is threshold-free. Because 18 features are tested at once, the maximum AUC is
biased upward, so the observed maximum is compared against a permutation null
(labels shuffled, 200 draws) rather than against 0.5.

Always read the TEST pair against the within-session control: two halves of the
same session have a constant label, so any separation there is drift.
"""
from __future__ import annotations

import argparse
import csv
import json
import os
import sys

import numpy as np

WIN = 200      # 2 s at ~100 Hz
HOP = 200      # non-overlapping
BANDS = 8
NPERM = 200


# ----------------------------------------------------------------- data
def load(path: str, skip: int = 0) -> tuple[np.ndarray, np.ndarray, list[int]]:
    amp, rssi, seqs = [], [], []
    with open(path, newline="") as f:
        for row in csv.reader(f):
            if len(row) != 25 or row[0] != "CSI_DATA":
                continue
            try:
                v = [int(t) for t in row[24].strip().strip('"[]').split(",")]
            except ValueError:
                continue
            if len(v) != 128:
                continue          # truncated seam line
            amp.append(np.hypot(v[0::2], v[1::2]))
            rssi.append(float(row[3]))
            seqs.append(int(row[1]))
    a, r, s = np.asarray(amp), np.asarray(rssi), seqs
    if skip:
        a, r, s = a[skip:], r[skip:], s[skip:]
    return a, r, s


def legacy_settle_rows(session_dir: str) -> int:
    """Rows to skip for a session recorded with the old --settle window."""
    p = os.path.join(session_dir.rstrip("/"), "csi_stats.json")
    if not os.path.isfile(p):
        return 0
    try:
        st = json.load(open(p))
    except (OSError, ValueError):
        return 0
    settle = float(st.get("settle_s") or 0.0)
    span, rows = st.get("csi_span_s"), st.get("csi_rows")
    if settle <= 0 or not span or not rows:
        return 0
    return int(round(settle * rows / span))


def windows(x: np.ndarray) -> np.ndarray:
    n = (len(x) - WIN) // HOP + 1
    return np.stack([x[i * HOP:i * HOP + WIN] for i in range(n)])


FEAT_NAMES = ([f"mean_band{b}" for b in range(BANDS)]
              + [f"sd_band{b}" for b in range(BANDS)]
              + ["rssi_mean", "rssi_sd"])


def feats(amp: np.ndarray, rssi: np.ndarray) -> np.ndarray:
    W = windows(amp)
    R = windows(rssi)
    n = len(W)
    mu, sd = W.mean(1), W.std(1)
    g = mu.mean(1, keepdims=True) + 1e-9
    mu_b = (mu / g).reshape(n, BANDS, -1).mean(2)
    sd_b = (sd / g).reshape(n, BANDS, -1).mean(2)
    return np.hstack([mu_b, sd_b, R.mean(1, keepdims=True), R.std(1, keepdims=True)])


# ----------------------------------------------------------------- stats
def auc_1d(a: np.ndarray, b: np.ndarray) -> float:
    """Mann-Whitney AUC of feature `a` vs feature `b`, tie-aware."""
    x = np.concatenate([a, b])
    order = np.argsort(x, kind="mergesort")
    xs = x[order]
    ranks = np.empty(len(x), dtype=float)
    i = 0
    while i < len(xs):
        j = i
        while j + 1 < len(xs) and xs[j + 1] == xs[i]:
            j += 1
        ranks[order[i:j + 1]] = 0.5 * (i + j) + 1.0
        i = j + 1
    r1 = ranks[:len(a)].sum()
    return float((r1 - len(a) * (len(a) + 1) / 2) / (len(a) * len(b)))


def max_auc(A: np.ndarray, B: np.ndarray) -> tuple[float, int]:
    vals = np.array([auc_1d(A[:, j], B[:, j]) for j in range(A.shape[1])])
    k = int(np.argmax(np.abs(vals - 0.5)))
    return float(vals[k]), k


def perm_null(A: np.ndarray, B: np.ndarray, rng: np.random.Generator) -> float:
    """95th percentile of max|AUC-0.5| over features with labels shuffled."""
    P = np.vstack([A, B])
    n = len(A)
    stats = np.empty(NPERM)
    for i in range(NPERM):
        idx = rng.permutation(len(P))
        a, b = P[idx[:n]], P[idx[n:]]
        v = np.array([auc_1d(a[:, j], b[:, j]) for j in range(P.shape[1])])
        stats[i] = np.max(np.abs(v - 0.5))
    return float(np.percentile(stats, 95))


def cohens_d(a: np.ndarray, b: np.ndarray) -> float:
    sp = np.sqrt((a.var(ddof=1) + b.var(ddof=1)) / 2)
    return float((b.mean() - a.mean()) / (sp + 1e-12))


# ----------------------------------------------------------------- report
def integrity(name: str, amp, rssi, seqs) -> None:
    drops = sum(1 for i in range(1, len(seqs)) if seqs[i] != seqs[i - 1] + 1)
    print(f"  {name:9s} rows {len(amp):6d}  seq gaps {drops:3d}  "
          f"span {len(amp)/100:6.1f} s  rssi {rssi.mean():7.2f} ± {rssi.std():4.2f} dB")


def report_pair(na, A, Fa, nb, B, Fb, rng, label) -> None:
    obs, k = max_auc(Fa, Fb)
    null = perm_null(Fa, Fb, rng)
    ratio = 20 * np.log10(B.mean() / A.mean())
    print(f"\n  {label}")
    print(f"    mean|H|  {na} {A.mean():.3f}   {nb} {B.mean():.3f}   "
          f"{ratio:+.2f} dB   d(per-row) {cohens_d(A.mean(1), B.mean(1)):+.2f}")
    print(f"    best feature  {FEAT_NAMES[k]:12s} AUC {obs:5.3f}  "
          f"(|AUC-0.5| = {abs(obs-0.5):.3f})")
    print(f"    permutation null (95th pct of max|AUC-0.5|) = {null:.3f}   "
          f"-> {'ABOVE null' if abs(obs-0.5) > null else 'within null'}")


def profile(name: str, amp: np.ndarray, rssi: np.ndarray, block: int = 500) -> None:
    print(f"\n  {name}: 5 s blocks (t, mean|H|, sd|H|, rssi)")
    for i in range(len(amp) // block):
        sl = slice(i * block, (i + 1) * block)
        print(f"    {i*block/100:6.1f}  {amp[sl].mean():7.3f}  {amp[sl].std():6.3f}  "
              f"{rssi[sl].mean():7.2f}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("a")
    ap.add_argument("b")
    ap.add_argument("--profile", action="store_true")
    ap.add_argument("--names", nargs=2, default=("A", "B"))
    ap.add_argument("--seed", type=int, default=0)
    args = ap.parse_args()
    rng = np.random.default_rng(args.seed)

    raw = [args.a, args.b]
    paths = [p if p.endswith(".csv") else f"{p.rstrip('/')}/csi.csv" for p in raw]
    loaded = []
    for p, nm, r in zip(paths, args.names, raw):
        skip = 0 if r.endswith(".csv") else legacy_settle_rows(r)
        amp, rssi, seqs = load(p, skip=skip)
        if skip:
            print(f"  note: {nm} recorded with a settle window; skipping first {skip} rows")
        loaded.append((amp, rssi))
        integrity(nm, amp, rssi, seqs)

    (aa, ra), (ab, rb) = loaded
    na, nb = args.names
    Fa, Fb = feats(aa, ra), feats(ab, rb)
    print(f"\n  windows: {na}={len(Fa)}  {nb}={len(Fb)}   features={Fa.shape[1]}")

    print("\n== within-session controls (label constant -> this is drift) ==")
    for nm, (a, r) in zip(args.names, loaded):
        F = feats(a, r)
        h = len(F) // 2
        report_pair(nm, a, F[:h], nm, a, F[h:], rng, f"{nm} h1 vs h2  [NULL]")

    print("\n== the actual comparison ==")
    report_pair(na, aa, Fa, nb, ab, Fb, rng, f"{na} vs {nb}")

    if args.profile:
        for nm, (a, r) in zip(args.names, loaded):
            profile(nm, a, r)

    print("\n  Read the comparison against the within-session controls. If the best")
    print("  feature is no better than a session's own halves, drift explains it.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
