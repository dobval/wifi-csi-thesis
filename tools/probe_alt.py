#!/usr/bin/env python3
"""Analyse one alternating capture (both conditions in a single recording).

    python3 tools/probe_alt.py data/<...>_alternating_A/

Why this exists: between-session drift was shown to be as large as any occupancy
effect (two empty sessions 15 min apart separated at |AUC-0.5| = 0.50). Recording
both conditions inside one continuous capture makes drift common-mode, so the
comparison below is paired within the recording rather than across sessions.

The null is built from the same recording: odd empty blocks vs even empty blocks.
If the person blocks are no more separable from empty blocks than the empty blocks
are from each other, drift still explains it.

Time base: `local_timestamp` (board microseconds), unwrapped across its 2**32 us
rollover. Row indices are NOT used, because the board stalls (max 273 ms observed)
would shift block boundaries.
"""
from __future__ import annotations

import argparse
import csv
import os
import sys

import numpy as np

BANDS = 8
NPERM = 500
WRAP = 2 ** 32


def load(session: str) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Return (amp[n,64], rssi[n], t_s[n]) with t from the board clock."""
    amp, rssi, ts = [], [], []
    with open(os.path.join(session, "csi.csv"), newline="") as f:
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
            ts.append(int(row[18]))
    amp, rssi, ts = np.asarray(amp), np.asarray(rssi), np.asarray(ts, dtype=np.int64)
    if not len(ts):
        sys.exit("no CSI rows")

    # unwrap the 32-bit microsecond counter
    d = np.diff(ts)
    wraps = np.concatenate([[0], np.cumsum(d < 0)]).astype(np.int64)
    t_abs = ts + wraps * WRAP
    t_s = (t_abs - t_abs[0]) / 1e6
    return amp, rssi, t_s


def read_schedule(session: str) -> list[dict]:
    p = os.path.join(session, "schedule.csv")
    if not os.path.isfile(p):
        sys.exit(f"{p} not found — record with --alternate to create one")
    out = []
    with open(p, newline="") as f:
        for r in csv.DictReader(f):
            out.append({"block": int(r["block"]), "cond": r["condition"],
                        "t0": float(r["t_start_s"]), "t1": float(r["t_end_s"]),
                        "guard": float(r["guard_s"])})
    return out


def block_feats(amp, rssi, m):
    mu, sd = amp[m].mean(0), amp[m].std(0)
    g = mu.mean() + 1e-9
    mb = (mu / g).reshape(BANDS, -1).mean(1)
    sb = (sd / g).reshape(BANDS, -1).mean(1)
    return np.r_[mb, sb, mu.mean(), rssi[m].mean(), rssi[m].std()]


FEAT = ([f"mean_band{b}" for b in range(BANDS)]
        + [f"sd_band{b}" for b in range(BANDS)]
        + ["gain", "rssi_mean", "rssi_sd"])


def auc_1d(a, b):
    x = np.concatenate([a, b])
    order = np.argsort(x, kind="mergesort")
    xs = x[order]
    ranks = np.empty(len(x))
    i = 0
    while i < len(xs):
        j = i
        while j + 1 < len(xs) and xs[j + 1] == xs[i]:
            j += 1
        ranks[order[i:j + 1]] = 0.5 * (i + j) + 1.0
        i = j + 1
    r1 = ranks[:len(a)].sum()
    return (r1 - len(a) * (len(a) + 1) / 2) / (len(a) * len(b))


def max_auc(A, B):
    v = np.array([auc_1d(A[:, j], B[:, j]) for j in range(A.shape[1])])
    k = int(np.argmax(np.abs(v - 0.5)))
    return v[k], k


def perm_null(A, B, rng):
    P = np.vstack([A, B]); n = len(A)
    s = np.empty(NPERM)
    for i in range(NPERM):
        idx = rng.permutation(len(P))
        a, b = P[idx[:n]], P[idx[n:]]
        v = np.array([auc_1d(a[:, j], b[:, j]) for j in range(P.shape[1])])
        s[i] = np.max(np.abs(v - 0.5))
    return float(np.percentile(s, 95))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("session")
    ap.add_argument("--seed", type=int, default=0)
    args = ap.parse_args()
    rng = np.random.default_rng(args.seed)

    amp, rssi, t_s = load(args.session)
    sched = read_schedule(args.session)

    rows, feats, skipped = [], [], 0
    for b in sched:
        lo, hi = b["t0"] + b["guard"], b["t1"] - b["guard"]
        m = (t_s >= lo) & (t_s < hi)
        if m.sum() < 100:
            skipped += 1
            continue
        feats.append(block_feats(amp, rssi, m))
        rows.append({"block": b["block"], "cond": b["cond"], "n": int(m.sum()),
                     "meanH": float(amp[m].mean()), "rssi": float(rssi[m].mean()),
                     "t0": b["t0"], "t1": b["t1"]})

    F = np.asarray(feats)
    cond = np.array([r["cond"] for r in rows])
    isE = cond == "empty_room"
    print(f"blocks used {len(rows)} of {len(sched)} (skipped {skipped})   "
          f"rows {len(amp)}   span {t_s[-1]:.1f} s")

    # ---- paired comparison, cycle by cycle
    print("\n== per-cycle paired difference (person - empty) in mean|H| ==")
    dif = []
    for c in range(1, max(int(r["block"]) for r in rows) // 2 + 1):
        try:
            e = next(r for r in rows if r["block"] == 2 * c - 1)
            p = next(r for r in rows if r["block"] == 2 * c)
        except StopIteration:
            continue
        d = p["meanH"] - e["meanH"]
        dif.append(d)
        print(f"  cycle {c:3d}  empty {e['meanH']:7.3f}  person {p['meanH']:7.3f}  "
              f"delta {d:+7.3f} dB-equiv {20*np.log10(p['meanH']/e['meanH']):+6.2f} dB")
    if dif:
        dif = np.asarray(dif)
        same = np.mean(np.sign(dif) == np.sign(np.median(dif))) * 100
        se = dif.std(ddof=1) / np.sqrt(len(dif)) if len(dif) > 1 else np.nan
        tstat = f"{dif.mean()/se:.2f}" if se and np.isfinite(se) and se > 0 else "n/a"
        print(f"\n  n={len(dif)}  mean {dif.mean():+.3f}  sd {dif.std(ddof=1):.3f}  "
              f"se {se:.3f}  t={tstat}  sign-consistency {same:.0f}%")

    # ---- block-level separability
    E, P = F[isE], F[~isE]
    obs, k = max_auc(E, P)
    null = perm_null(E, P, rng)
    print(f"\n== block-level separability ==")
    print(f"  empty blocks {len(E)}  person blocks {len(P)}")
    print(f"  best feature {FEAT[k]:12s} AUC {obs:5.3f}  |AUC-0.5| {abs(obs-0.5):.3f}")
    print(f"  permutation null 95th pct             {null:.3f}  -> "
          f"{'ABOVE null' if abs(obs-0.5) > null else 'within null'}")

    # ---- the null from inside the same recording
    idxE = np.where(isE)[0]
    if len(idxE) >= 4:
        a, b = F[idxE[0::2]], F[idxE[1::2]]
        o2, k2 = max_auc(a, b)
        n2 = perm_null(a, b, rng)
        print(f"\n== within-recording null: odd empty vs even empty blocks ==")
        print(f"  best feature {FEAT[k2]:12s} AUC {o2:5.3f}  |AUC-0.5| {abs(o2-0.5):.3f}"
              f"  null {n2:.3f} -> {'ABOVE null' if abs(o2-0.5) > n2 else 'within null'}")
        print("  Empty blocks should be indistinguishable from each other. If they are not,")
        print("  the recording is drifting faster than the block length and the person")
        print("  comparison cannot be trusted.")

    return 0


if __name__ == "__main__":
    sys.exit(main())
