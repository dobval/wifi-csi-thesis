# Wi-Fi CSI sensing on a single ESP32-S3

BEng thesis project. The question: **what can one ESP32-S3 infer about people in a
room from Channel State Information taken from ordinary router pings?** No second
inference node, no modified AP, no CSI tool on the router.

## Background

Wi-Fi signals fill a room and reflect off everything in it, people included. A
receiver can measure how the channel to the transmitter is altered — subcarrier by
subcarrier, about a hundred times a second. That measurement is **Channel State
Information (CSI)**, and it turns ordinary Wi-Fi into a sensing modality: presence,
motion, even breathing, without a wearable, a camera, or any cooperation from the
person. Working without a camera is also the privacy argument.

Most published systems need two or more devices, or a modified access point.
Detecting a *stationary* person with a single cheap receiver against a stock home
router is not established — the strongest open-source ESP32 implementation
explicitly declines to claim it. IEEE 802.11bf, the first Wi-Fi sensing standard,
reached final approval in 2025, which makes "what can commodity hardware actually
do?" a timely question rather than a solved one.

The long-term aim is **inference on the microcontroller itself**: a few-kilobyte
quantised model producing a decision on-device, so no raw CSI stream ever leaves
the chip. That is the Edge AI / TinyML argument — the measurement stream is
~44 KB/s, while a decision is a few bytes.

## Claim ladder

The work is a ladder of three claims, each a standalone deliverable. Failure at a
higher rung erases nothing below it.

| Rung | Claim | Status |
|---|---|---|
| **L1** | Detect human motion (walk-through) | not started — the pipeline is validated, no motion captures yet |
| **L2** | Breathing rate of a still person at 1–3 m | tooling only; phase probe finds nothing in 40 s blocks, needs 120 s blocks |
| **L3** | Stationary human vs empty room | **detected at 80 cm** (5/5 blocks, p ≈ 0.03) but the perturbation is frequency-flat gain, which RSSI measures equally well |

The most useful result so far is a **negative one**: at 260 cm with both antennas
at 88 cm, a stationary person at the mid-point perturbs the link by ~1 dB,
uniformly across all subcarriers, which is *below the link's own 2.2 dB/10 min
drift*. CSI adds nothing over RSSI there. Moving the subject into the antenna's
near field (80 cm) produces a sign-stable 1.2 dB shadow — reliable, but still
frequency-flat. Details in `results/`.

## Where things are

| Path | What it is |
|---|---|
| `STATE.md` | rolling status: current milestone, rig config, known issues, next action |
| `RESEARCH.md` | frozen claim ladder and RQ wording |
| `repository_and_data_discipline.txt` | mandated layout and data rules |
| `firmware/` | what is flashed: pinned esp-csi commit, the one local change, rebuild steps |
| `tools/` | capture, cueing and analysis scripts (table below) |
| `data/` | **metadata** for every capture: protocol, stats, integrity manifest, clock sidecar |
| `sessions/INDEX.md` | generated index of every session and its status |
| `results/` | analysis write-ups, one folder per investigation |
| `docs/` | floor plan (`layout.md`, generated from `layout-source.json`) and rig documentation |

## Read this first

1. `STATE.md` — where the project stands right now
2. `RESEARCH.md` — what is actually being claimed
3. `results/20261126_alternating_probe/ANALYSIS.md` — the L3 measurements and why
   the effect is RSSI-equivalent
4. `docs/layout.md` — the room, the floor marks, and which numbers are measured

## What is deliberately not in git

Raw CSI is ~150 MB per hour (the 6 h 23 m soak is 960 MiB). None of it is
committed:

- `data/**/*.csv`, `results/**/*.log` are gitignored
- the 1 Hz `*_clock.csv` alignment sidecars **are** committed (~20 KB each), so a
  session can still be re-aligned to wall clock without the payload
- `sdkconfig` is gitignored because it contains the Wi-Fi password

## If you clone this repo

```bash
git config core.hooksPath .githooks   # blocks MAC addresses and the SSID
```

The hook is committed; the deny-list it optionally reads is not. Raw captures also
contain the access point's MAC in every row, which is why they stay out of git.

The repository is therefore ~600 KB of text: tooling, protocols, statistics and
analysis. Raw captures live on the rig machine and are catalogued by
`sessions/INDEX.md` with a SHA-256 manifest per session.

## Running a capture

On the PC:

```bash
./tools/record_session.sh --label alternating --alternate 60 --cycles 5 \
    --condition-a empty_room --condition-b person_in_zone_static \
    --distance-cm 260 --height-cm 88
```

This writes `data/<YYYYMMDD>_<HHMM>_alternating_A/`, prints a countdown so you can
leave the room, and records under tmux. It ends by itself, appends the capture
statistics to `session.md`, and writes `manifest.sha256`.

From a phone in Termux, `tools/phone/record_remote.sh` launches the above over SSH
and then cues the blocks on screen (terminal only — no Termux:API).

## Analysing

```bash
python3 tools/index_sessions.py                 # refresh sessions/INDEX.md
python3 tools/probe_alt.py data/<session>       # paired deltas, shape-vs-gain
python3 tools/probe_breathing.py data/<session> # breathing-band spectrum
```

## Tools

| Script | Purpose |
|---|---|
| `record_session.sh` | start a labelled capture; writes protocol + stats + manifest |
| `capture_serial.py` | serial → file worker, called by the above; verbatim bytes |
| `phone/record_remote.sh` | Termux: launch over SSH and cue the blocks on screen |
| `probe_alt.py` | analyse **one** alternating recording (the main tool) |
| `probe_l3.py` | compare **two separate** sessions — legacy, superseded for L3 |
| `probe_breathing.py` | breathing-band spectrum from phase/amplitude/RSSI — experimental |
| `render_plan.py` | ASCII floor plan from `docs/layout-source.json` |
| `index_sessions.py` | regenerate `sessions/INDEX.md` |

## Pinned versions

ESP-IDF v5.3.6, esp-csi `8633d67`, GCC 13.2.0. Do not upgrade mid-campaign: a
toolchain change is a rig change, and the empty baseline must be re-recorded. The
full pin list lives at the top of `STATE.md`.
