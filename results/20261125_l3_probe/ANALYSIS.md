# L3 probe — drift-limited negative result

Six 300 s sessions recorded 2026-11-25, placement A (280 cm AP ↔ node, 88 cm,
taped, PC-end cable breaks, no LOS block). Subject ~200 cm from the AP.

| Session | Label |
|---|---|
| `20261125_1000_empty_room_A` | empty |
| `20261125_1010_person_out_of_zone_A` | person — **contaminated**, subject transit during capture |
| `20261125_1511_person_out_of_zone_A` | person |
| `20261125_1525_empty_room_A` | empty (A1) |
| `20261125_1533_person_out_of_zone_A` | person (B) |
| `20261125_1540_empty_room_A` | empty (A2) |

A1 → B → A2 is an interleaved block, 15 min end to end.

## 1. Correction: the first analysis was invalid

An earlier version of `tools/probe_l3.py` reported cross-session AUCs of
0.870–0.980. **Those numbers were meaningless and are withdrawn.**

The model was trained on one session only, with a constant target and no bias
term. A model fitted to a single class cannot discriminate; the fitted weight
vector had norm 2×10⁻¹⁶ and the scores were floating-point noise. Any AUC can
come out of that, including 0.976 and 0.001.

The design error is structural, not a typo: **with one session per class,
leave-one-session-out supervised learning is impossible.** There is no second
class in the training set.

`tools/probe_l3.py` now uses a training-free two-sample rank test (Mann-Whitney
AUC per feature) with a permutation null for the max-over-features statistic.
Nothing is fitted, so nothing can collapse.

## 2. Integrity (all six sessions)

Every session: **0 sequence gaps**, ~100.0 Hz, `channel=6`, `sig_mode=1`,
`len=128`, one malformed row (the capture seam), RSSI −37 to −38 dBm.

## 3. Results

`|AUC−0.5|` is the effect size; "null" is the 95th percentile of the same
statistic with labels shuffled (200 draws).

| Pair | Time gap | Best feature | AUC | \|AUC−0.5\| | null | Verdict |
|---|---|---|---|---|---|---|
| **empty1 vs empty2** | **15 min** | `rssi_mean` | **1.000** | **0.500** | 0.089 | above null |
| empty1 vs person (B) | 8 min | `sd_band6` | 0.953 | 0.453 | 0.092 | above null |
| person (B) vs empty2 | 7 min | `rssi_mean` | 0.987 | 0.487 | 0.093 | above null |
| empty (10:00) vs person (15:11) | 5 h | `sd_band2` | 0.050 | 0.450 | 0.095 | above null |

Within-session controls (label constant, so this is pure drift):

| Pair | Best feature | AUC | \|AUC−0.5\| | null |
|---|---|---|---|---|
| empty1, half vs half | `sd_band3` | 0.709 | 0.209 | 0.126 |
| empty2, half vs half | `sd_band1` | 0.310 | 0.190 | 0.122 |
| person (B), half vs half | `sd_band5` | 0.911 | 0.411 | 0.135 |
| empty (10:00), half vs half | `sd_band4` | 0.288 | 0.212 | 0.131 |
| person (15:11), half vs half | `mean_band2` | 0.674 | 0.174 | 0.128 |

## 4. The decisive control

**Two sessions with the same label — both empty — separate at |AUC−0.5| = 0.500,
on `rssi_mean` alone, 15 minutes apart.** Mean RSSI was −37.39 ± 0.49 dB and
−38.03 ± 0.18 dB.

That value is at least as large as every empty-vs-person comparison
(0.450, 0.453, 0.487). Between-session drift therefore accounts for the entire
apparent class difference. No person effect survives it.

Two further signs that the drift interpretation is right, not merely possible:

- The amplitude change **flips sign** between the two clean person sessions:
  −0.37 dB (15:11) and +0.80 dB (15:33). A physical occupancy effect at fixed
  geometry should not do that; a changing environment can.
- Within-session drift is itself large: the person (B) session separates from its
  own second half at 0.411, close to the cross-session figures.

## 5. What this does and does not mean

**Not** "a far-end person is invisible to CSI." The raw measurements show mean
|H| differing by 0.4–0.8 dB between conditions, which is larger than the 1 dB
RSSI quantisation and consistent with a real multipath perturbation.

**What it means:** at one 5-minute session per condition, the perturbation is
**smaller than the drift between sessions**, so the experiment cannot attribute
it to occupancy. This is a resolution limit of the design, not a physical claim.

**And:** RSSI alone perfectly separated two *empty* sessions. Any RSSI-threshold
occupancy detector would report a condition change on an unchanged room. That
survives as a standalone finding.

## 6. Design consequence — this changes the collection protocol

Sessions cannot be the unit of analysis. With sessions as the unit, drift is
confounded with the label, and no amount of extra sessions fixes it cheaply.

The unit must be **within one continuous recording**: alternate the condition on
a scripted schedule (e.g. 60 s person-out / 60 s person-in, repeated) with
ground-truth event timestamps, so drift is common to all classes and cancels in
any comparison. This is the standard design for occupancy sensing and it is why
the event-marker problem was flagged at the start.

Concretely, the next capture needs:

1. A single recording of ≥10 min with scripted occupancy transitions.
2. A timestamped event log (condition changes, written to the same clock domain
   as `local_timestamp`), so windows can be labelled by time rather than by file.
3. Analysis that splits *within* that recording and reports the null from
   held-out time blocks of the same recording.

Until that exists, no classifier trained on these six sessions is meaningful.

## 7. Tooling state

- `tools/probe_l3.py` — training-free, permutation-nulled. Safe to run on any pair.
- `tools/record_session.sh` — single `--countdown`; measurement starts at the
  first CSI row; `boot_wait_s` recorded.
- Raw `csi.csv` files are gitignored (~13 MB each). `session.md`, `capture.env`,
  `csi_stats.json`, `manifest.sha256` and `csi_clock.csv` are committed.
