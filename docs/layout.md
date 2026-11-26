# Room layout and floor marks — placement A

Source of truth for the topology: `docs/layout-source.json` (room planner export,
2026-11-26). The plan is generated from it, never drawn by hand:

```bash
python3 tools/render_plan.py docs/layout-source.json --width 76 --real-span 280
```

## To-scale plan

```
+----------------------------------------------------------------------------+
|############################################################################|
|#                                                                          #|
|#                          :A                                              #|
|#                        ::                                                #|
|=                      ::                                                  #|
|=                   :::                                                    #|
|=            1  ::                                                         #|
|=          ::                                                              #|
|=        ::                                                                #|
|=     :::                                                                  #|
|=   ::                                                      3              #|
|= ::                                                                       #|
|E:                                                                         #|
|=                                                                          #|
|=                                                                          #|
|###########################################################...........######|
+----------------------------------------------------------------------------+
     E  ESP32-S3       A  AP router       1  in zone       3  out of zone
     # wall   = window   . door   : line of sight
```

## Measurements vs sketch — read this before quoting any number

| Quantity | Value | Status |
|---|---|---|
| Node height | **88 cm** | **measured** (tape) |
| AP height | **88 cm** | **measured** (tape) |
| AP ↔ node | **280 cm** | **measured** (tape) |
| Room size | ≈ 589 × 403 cm | sketch, scaled — estimate |
| Door 98 / window 324 / walls 270 | planner values | unverified |
| Seat positions, wall offsets | plan units | sketch |

The planner reads 361 units for a measured 280 cm, so **the sketch is ~1.29×
oversize**. Only the three measured numbers above may be quoted in the thesis or
used to compute anything. The sketch is for topology — what is where, relative to
what — and every distance you need must come off a tape.

Corollary: earlier notes said 260 cm. **280 cm supersedes it**, so the
2026-11-25/26 sessions carry a 20 cm mislabelled distance in their `session.md`.
The raw data is unaffected; the label is wrong by 20 cm.

## Marks to tape

Use the walls and the door as physical references; the plan's numbers are only a
proportional guide.

| Mark | Position | Use |
|---|---|---|
| **Node** | against the left wall, under the window, 88 cm high | never moved mid-campaign |
| **AP** | against the top wall, 88 cm high | never moved mid-campaign |
| **P1** | mid-point of the measured 280 cm line, **within 20 cm of it laterally** | `person_in_zone_static` |
| **P3** | far side of the room, at least 1.5 m off the AP–node line | `person_out_of_zone` |
| **ZONE** | 60 cm wide strip along the measured line, 40 cm short of each end | moving condition |

P1 sits 140 cm from the AP and 140 cm from the node, because it is the mid-point.
Get that from the tape, not from the sketch.

Why 60 cm wide and 20 cm lateral tolerance: the first Fresnel radius at 2.4 GHz
over 280 cm is `sqrt(λ·d₁d₂/(d₁+d₂))` ≈ **30 cm**. A body further than ~30 cm
from the line is no longer obstructing the direct path, it is only changing
reflections — which is the *other* condition.

For reference, the sketch puts the "in zone" mark at ~23 cm off the line once
scaled, i.e. right on the Fresnel edge. Aim inside 20 cm instead.

## What each condition means, physically

| Label | Body position | Path affected |
|---|---|---|
| `empty_room` | nobody in the room, door closed | none |
| `person_in_zone_static` | seated at P1, still | blocks the direct path — large, easy effect |
| `person_in_zone_moving` | walking along the taped zone | sweeps the direct path — largest effect |
| `person_out_of_zone` | seated at P3, still | reflected paths only — small, hard effect |

`person_in_zone_static` is the **primary** L3 contrast. `person_out_of_zone` is
the **hard negative**: it decides whether the claim is interesting, and it is the
one most likely to fail. Collect and report both, in separate recordings — never
in one schedule.

## What to do during a run

The cue script announces every transition. Beyond that:

**`empty_room`:**
- out of the room, door closed, nobody else in it
- do not open the door to check the capture; the data is on disk
- no pets, no fans switched on or off mid-run

**`person_in_zone_static`:**
- seated at P1, within 20 cm of the AP–node line
- feet flat, back against the chair, same chair and orientation every session
- breathe normally; breathing is the L2 signal, not noise
- do not fidget, check the phone, shift weight or talk

**`person_in_zone_moving`:**
- steady pace along the taped strip, ~1 m/s
- same direction each pass, or alternate and note it
- do not stop inside the zone or turn sharply at the ends

**`person_out_of_zone`:**
- seated at P3, same posture as P1, facing the same way
- do not drift onto the AP–node line "to be safe" — that is the other condition

## Things that silently ruin a session

- moving the node, the cable or the router after the baseline — all shift the channel
- a chair left in the zone during `empty_room`
- someone walking past the door during any block
- phone resting on the node (metal, next to the antenna)
- changing posture mid-block — the largest within-block variance source
- a window opened or a blind moved between blocks
- running on battery with the laptop set to suspend

## RF notes worth recording in the thesis

- The node sits close to the left wall (the sketch says ~8 cm), so its PCB antenna
  has a large reflecting plane immediately behind it.
- The node is in front of a wide window. If the planner's 90 cm sill is right, the
  board at 88 cm is just below it — glass, frame and the outdoors are all part of
  the static channel. Verify the sill with a tape before describing it.
- AP and node are both at 88 cm, so the direct path is horizontal: no specular
  floor or ceiling reflection, which is why the direct ray dominates.

## Checklist before the first block

- [ ] AP↔node taped at **280 cm**; P1 at the mid-point
- [ ] both antennas 88 cm, measured
- [ ] node taped, cable broken only at the PC end
- [ ] zone taped, P1 and P3 marked, P1 within 20 cm of the line
- [ ] chair in position for P1 and P3
- [ ] nobody else in the building who might walk past
- [ ] `~/rec.sh --status` on the phone says `(none), (none), free`
