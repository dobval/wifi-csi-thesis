# Soak analysis — `soak_2026-11-24_1439.log`

6 h 23 m continuous capture, 2026-11-24 14:39 → 21:02. Unscripted occupancy.
**Status: exploratory only.** Not a labelled session; never enters the M2/M4 training sets.

- File: `results/2026-1-24_1439-2102/soak_2026-11-24_1439.log`
- Size: 1 004 519 639 B (958 MiB) → **150 MB/h**
- Rig: ESP32-S3-DevKitC-1 N16R8, on-module PCB antenna, bare board
- Geometry: AP ↔ node **260 cm**, both at **88 cm** height, direct LOS
- AP: `ssid_1`, BSSID `ap_1`
- Firmware: esp-csi `8633d67`

## 1. Transport integrity — pass

| Check | Result |
|---|---|
| CSI rows | 2 303 823 |
| Non-CSI lines | 114 (boot banner + `idf_monitor` preamble, all in the first second) |
| Malformed rows (no terminating `]"`) | **0** |
| ANSI escapes inside CSI rows | **0** |
| `seq` range | 0 → 2 303 822 |
| Missing packets | **0** |
| Backwards `seq` jumps | **0** |
| Rows per full minute | **6000 exactly, 383 consecutive minutes** |

2 303 823 = 383 × 6000 + 5823 (first, partial minute). The 921 600-baud
CH343 link and the host never dropped a line for 6 h 23 m. This is the strongest
possible evidence that 150 MB/h text streaming is sustainable on this rig.

## 2. PHY stability — pass

| Field | Observed |
|---|---|
| `channel` | 6 for **all** 2 303 823 rows |
| `sig_mode` | 1 (HT) for all rows |
| `len` | 128 for all rows |
| `mcs` | 7 for 2 278 844 rows (**98.96 %**); 6 for 23 895; ≤5 for 1 080 |
| `bandwidth` / `sgi` / `secondary_channel` | 0 / 0 / 0 for all rows |
| `noise_floor` | −96 dBm for 2 277 641 rows (**98.88 %**), never above −93 |

No channel hopping and no fallback to 11b/11g: `sig_mode=1`, `len=128` throughout.

The MCS downshifts are **isolated, not sustained**: the longest contiguous run
below MCS 7 is 4 rows (40 ms), they are spread evenly across all six hours
(0.89–1.61 % per hour), and the mean RSSI during those frames matches the hourly
mean to within 0.1 dB (−39.29 vs −39.37 dBm in h00; −37.47 vs −37.55 in h04).
So they are the AP's per-frame rate control probing, **not** fading-driven rate
fallback. Report it as "98.96 % HT MCS 7, isolated downshifts only", not as
"MCS pinned".

`noise_floor` sits at its measurement floor (−96 dBm) for 98.9 % of the session
and never rises. Two readings, and only the cautious one is safe: it shows no
AGC/gain movement, but because it is saturated at the floor it **cannot** be used
as a receiver-thermal probe. Do not build a temperature-drift argument on it.

> Note: `STATE.md` records that this soak may predate the channel-6 pinning, when
> the router was on Auto and seen hopping 8/10. The log contradicts that — it is
> 100 % channel 6. Reconcile before citing the soak as "pre-pinning".

## 2a. Rig stability controls (operator-confirmed)

- The node was **taped down before the soak** — position fixed at 260 cm / 88 cm
  for the entire 6 h 23 m.
- The USB cable was **only ever broken at the PC end**, never at the board.

This matters because the on-module PCB antenna is parasitically coupled to the
USB cable and its ground return. Breaking the cable at the board end changes the
near-field and therefore the static channel transfer function. Doing it at the PC
end leaves the board-side geometry untouched.

Combined with the PHY evidence above, the 6.9 dB wander in §4 is **neither
mechanical (node never moved) nor rate adaptation (downshifts uncorrelated with
RSSI) nor receiver gain (noise floor static)**. What remains is genuine
channel-gain change: environment (multipath / occupancy) or AP-side transmit
behaviour. That is the strongest form of the argument, and it is only available
because these two handling rules were followed.

### The −29 dBm reading is not a reference point

The bring-up RSSI checks (−29 dBm, and −28 dBm before the SSID change) were taken
**untaped, with no log file**, at an unrecorded position. They therefore have
unknown geometry and **cannot be compared** with the soak's −38.2 dBm.

The 9 dB gap is not attributable to distance. An untaped board can read 9 dB
stronger purely from orientation, cable routing, or a hand near the antenna — a
hand in the near-field is worth several dB by itself. Treat those numbers as
"the instrument is alive" checks, not as measurements of a geometry. Only the
soak has committed geometry, and only the soak may be cited as a baseline
position.

## 3. Timing — 100 Hz with bounded jitter

| Metric | Value |
|---|---|
| Mean inter-row interval | 9 982 µs → **100.18 Hz** |
| p50 / p99 / p99.9 | 9 970 / 17 836 / 24 938 µs |
| Intervals > 50 ms | **112** (0.0049 %) |
| Max interval | 273 ms (row 1 847 081) |
| Intervals > 1 s | 0 |
| `local_timestamp` wraps | **5** (2³² µs = 71.6 min; 5 wraps over 383 min is consistent) |

The 112 long intervals cluster between rows 882 k and 1 030 k (≈ 2 h 27 m – 2 h 52 m in)
and again around row 1 847 k. Because `seq` is continuous across them, these are
**board-side stalls, not transport loss**: the rows exist, they were just timestamped
late. Total missing coverage ≈ 8 s in 6.4 h (0.03 %).

Consequence for feature design: window lengths must be defined on
`local_timestamp`, not on row index. A 256-row window is 2.56 s *on average* and
2.7 s across the worst gap.

`local_timestamp` is a **32-bit board-local µs counter**, not wall clock. It wraps
and it cannot be joined to a phone stopwatch. This is why the capture tool writes
a `<name>_clock.csv` alignment sidecar (host Unix ns ↔ board µs, 1 row/s).

## 4. Channel wander — the important result

| Metric | Value |
|---|---|
| Frame RSSI, all rows | mean −38.22, sd 1.62, range −52 … −32 dBm |
| Per-minute mean RSSI | range **−42.03 … −35.15** → **6.88 dB** |
| Largest minute-to-minute step | 4.09 dB (minute 295) |
| First 10 min vs last 10 min | −37.45 → −39.00 dB (1.5 dB) |
| Per-minute CSI amplitude sd | 0.860 … 4.157 (**4.8×**) |
| r(per-minute mean RSSI, per-minute amplitude sd) | **+0.53** |

Two conclusions, both load-bearing for the thesis:

1. **RSSI is not a usable detector.** With no controlled change, the link's mean
   RSSI wandered 6.9 dB over the session and stepped 4 dB inside a minute. Any
   RSSI-threshold occupancy detector would have false-triggered repeatedly. This
   is a clean, quantitative justification for CSI over RSSI — and it comes from
   the rig itself, not from a citation.

2. **Amplitude-variance features are partly power-coupled.** r = +0.53 between
   "movement energy" (amplitude sd) and mean RSSI means roughly a quarter of the
   variance in the movement proxy is explained by gain wander alone. Feature
   extraction must normalise per frame (e.g. divide by the frame's mean
   amplitude, or use subcarrier ratios / phase differences) or the model will
   learn the automatic-gain-control behaviour instead of the room.

Whether the wander is thermal, multipath, or uncontrolled occupancy cannot be
determined without ground truth — which is exactly why this file is exploratory.

## 5. What this soak may and may not be used for

**May be used for:**
- Transport/throughput validation (done: 0 lost rows in 383 full minutes).
- Baseline drift and false-alarm characterisation: run a detector over it and
  report alarms/hour on unlabelled ambient data.
- Feature and filter design (normalisation strategy, window sizing, gap handling).
- A stability appendix: "the instrument ran 6 h 23 m with zero loss".

**May not be used for:**
- Any labelled training or evaluation set.
- Any claim of the form "occupancy was X at time Y".
- Estimating generalisation: one session = one effective domain.

## 6. Storage economics

150 MB/h raw text. A 128-subcarrier int8 I/Q frame is 256 B of payload, so the
CSV text format is ≈ 1.7× the payload and compresses well. Recommended:
keep the raw `.csv` verbatim (immutability argument), store the derived
`float32` array once as `.npy`/`.npz` per session for training. Do not
re-serialise raw data into a different text format.
