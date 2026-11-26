# Alternating protocol — first partial run, 2026-11-26

`data/20261126_0949_alternating_A_PARTIAL/` — 360 s captured, 35 643 rows,
0 sequence gaps, 100.2 Hz, channel 6, 0 malformed rows.

**Only blocks 1–3 are valid.** The phone cue loop died just before block 4.
Blocks 4+ were recorded but the subject was not guided, so their labels are
meaningless. Always analyse this session with `--blocks 1-3`.

## What actually happened

| block | condition | mean \|H\| | mean RSSI |
|---|---|---|---|
| 1 | empty_room | 9.373 | −39.02 |
| 2 | person_out_of_zone | 9.812 | −38.84 |
| 3 | empty_room | 9.187 | −39.11 |
| 4 | person_out_of_zone *(not cued)* | 10.639 | −38.35 |

The two empty blocks agree to **0.19** in mean amplitude. The person blocks sit
**+0.44** and **+1.45** above their neighbours.

That ordering is the first evidence that the within-recording design works: with
both conditions in one continuous capture, the empty blocks are more similar to
each other than either is to a person block. The earlier session-level design
could not show this, because two empty sessions 15 min apart separated as
strongly as empty vs person.

## What this is not

Not evidence of detection. With 3 usable blocks there is **one** paired
observation, and the permutation null over 3 blocks is degenerate:

```
per-cycle paired difference: n=1, delta +0.44
best block feature AUC 0.000 -> permutation null 0.500 -> within null
```

`within null` is the correct verdict: one pair cannot exceed a null built from
one pair. This run validates the *mechanism*, not the effect.

## The failure

The phone script exited around block 4 (~6 min into the run) and Termux showed
its end-of-session prompt; pressing Enter closed the session. The PC capture
continued unguided until it was stopped manually.

Three fixes came out of it (`tools/phone/record_remote.sh`):

1. **Auto-stop on exit.** An `EXIT` trap now sends `SIGTERM` to the remote worker
   if the cue loop ends before the schedule completes. An unguided capture has no
   valid labels, so leaving it running only holds the serial port for an hour.
2. **Phone-side log** at `~/csi_cue.log`, timestamped, including every cue and the
   exit code, so a failure leaves evidence instead of a closed terminal.
3. **`</dev/null` on the background ssh**, so it cannot consume keystrokes meant
   for the cue loop.

Running the cue loop inside phone-side `tmux` protects against the *terminal*
closing. It does not protect against Android killing the app; that needs battery
optimisation disabled for Termux. The later SIGKILLs were caused by `alarm()`
backgrounding up to five jobs per cue and crossing Android's concurrent-child
limit; the cue loop is now terminal-only and forks once per second.

## Next

Re-run a full schedule. Then `probe_alt.py` with no `--blocks` restriction, and
read the within-recording null (odd vs even empty blocks) before the effect.

---

## First complete run — `20261126_1050_alternating_A` (600 s, 5 pairs)

Mechanical success: 10/10 blocks used, 60 186 rows, 0 skipped, phone survived the
whole run with the terminal-only cue display. The plumbing now works.

| block | condition | mean \|H\| | RSSI |
|---|---|---|---|
| 1 | empty_room | 10.324 | −37.50 |
| 2 | person_in_zone_static | 8.919 | −38.41 |
| 3 | empty_room | 10.296 | −37.49 |
| 4 | person_in_zone_static | 10.926 | −36.50 |
| 5 | empty_room | 8.313 | −39.03 |
| 6 | person_in_zone_static | 9.508 | −37.61 |
| 7 | empty_room | 8.309 | −39.03 |
| 8 | person_in_zone_static | 10.464 | −36.80 |
| 9 | empty_room | 10.479 | −36.94 |
| 10 | person_in_zone_static | 12.722 | −35.40 |

Paired deltas (person − empty): −1.27, +0.52, +1.17, +2.00, +1.68 dB.
Mean **+0.82 dB**, sd 1.49 units, **4/5 positive**, paired **t = 1.45 on 4 df**
(p ≈ 0.22). At d = 0.65 this needs **≈19 pairs** for 80 % power.

### Why the reported "within null" is not a negative result

The permutation null over 5-vs-5 blocks saturates at |AUC−0.5| = 0.500: with ten
blocks and nineteen features, chance alone separates them perfectly on at least
one feature. So "within null" here means the test has **no power**, not that the
effect is absent. `probe_alt.py` now prints that warning explicitly.

### The real problem: the empty baseline is bimodal

Empty means: 10.324, 10.296, **8.313, 8.309**, 10.479 — a **~2 dB step** down
between cycles 2 and 3 and back up by cycle 5. Person means scatter 8.919–12.722,
a range of ~3.8 units (~3.4 dB). Both are larger than the +0.82 dB effect.

The empty-vs-empty statistic (|AUC−0.5| = 0.333) is that step showing up, not
drift-free stability. Something about the "empty" condition was not constant
across the run, and the person blocks varied more than the condition did.

Until that is explained, more pairs will only buy precision about an unstable
contrast.

### Shape is invariant: the effect is frequency-flat gain

Block-mean subcarrier pattern correlates at **r = 0.991** between empty blocks,
**0.990** between person blocks, and **0.982** across conditions. The 64-subcarrier
profile is essentially the same in all ten blocks.

| feature | empty | person | AUC |
|---|---|---|---|
| gain (mean \|H\|) | 9.544 ± 1.01 | 10.508 ± 1.31 | 0.280 |
| gain-normalised temporal sd | 0.355 ± 0.037 | 0.350 ± 0.048 | **0.520** |
| RSSI | −37.0 | −36.6 | 0.240 |

**After dividing out the gain there is nothing left** (AUC 0.520 is chance). The
entire difference between the conditions is a scalar level shift of ~1 dB applied
uniformly across the 20 MHz band — which is exactly what RSSI measures, and RSSI
scores the same (0.240 vs 0.280).

Meanwhile the *empty* condition alone spans **2.17 dB over ten minutes** with
nobody in the room. The 6 h soak showed minute-to-minute steps up to 4.1 dB.

### What this means

At 260 cm and 88 cm, a stationary person is a **frequency-flat ~1 dB
perturbation, below the link's own drift**. CSI carries no information that RSSI
does not, because the body is not changing the multipath *structure* — only the
overall level. Posture, facing and arm position are therefore not the source of
the variance; they were ruled out by the invariant shape.

Two honest options:

1. **Report it as the detection envelope.** "At 260 cm, both antennas at 88 cm, a
   stationary person is a ~1 dB frequency-flat perturbation, indistinguishable
   from the link's 2.2 dB/10 min drift. CSI offers no gain over RSSI at this
   geometry." That is a defensible negative result.
2. **Change the geometry so the body intercepts a meaningful share of the power.**
   Standing in the near field of one antenna (~60–80 cm) loads and detunes it,
   producing large and frequency-selective changes. That is where CSI should
   separate from RSSI — but the detection zone is then the antenna's near field,
   not the middle of the room.
