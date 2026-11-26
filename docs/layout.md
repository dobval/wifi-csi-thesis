# Room layout and floor marks — placement A

Source of truth: `docs/layout-source.json` (export from the room planner, 2026-11-26).
The plan below is generated from it, not drawn by hand:

```bash
python3 tools/render_plan.py docs/layout-source.json --width 76
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
|=                 ::                                                       #|
|=            1  ::                                                         #|
|=            :::                                                           #|
|=          ::                                                              #|
|=        ::                                                                #|
|=     :::                                                                  #|
|=   ::                                                      3              #|
|= ::                                                                       #|
|E:                                                                         #|
|=                                                                          #|
|=                                                                          #|
|=                                                                          #|
|=                                                                          #|
|=                                                                          #|
|=                                                                          #|
|=                                                                          #|
|#                                                                          #|
|#                                                                          #|
|#                                                                          #|
|###########################################################...........######|
+----------------------------------------------------------------------------+
     E  ESP32-S3  x=243  y=405        A  AP router  x=520  y=173
     1  in zone   x=363  y=265        3  out of zone x=837  y=365
     # wall   = window   . door   : line of sight
```

Room 760 × 520 cm, walls 270 cm high. The `E` sits hard against the left wall,
immediately in front of a 324 cm window (sill 90 cm). The door is on the
bottom wall at x ≈ 878.

## Geometry — unresolved discrepancy

| Quantity | Value | Source |
|---|---|---|
| AP ↔ node | **361 cm** | planner annotations |
| AP ↔ node | **260 cm** | tape measure, 2026-11-25, in `STATE.md` |
| Node height | 88 cm | tape |
| AP height | 88 cm | tape |

**These disagree by a metre.** The annotation anchors are text labels placed by
eye, so they can be offset — but not by a metre. One of the two is wrong, and the
baseline depends on which. Re-measure AP↔node with a tape before the next
session and correct whichever figure is wrong. Until then, treat 260 cm as the
recorded value and the plan as approximate.

## Marks to tape

Coordinates are planner cm; they assume the plan's origin, not a taped datum.
Use the walls and the door as references, not the numbers alone.

| Mark | Position | Use |
|---|---|---|
| **Node** | against the left wall, x=243, y=405, 88 cm high | never moved mid-campaign |
| **AP** | against the top wall, x=520, y=173, 88 cm high | never moved mid-campaign |
| **P1** | mid-point of the AP–node line, x≈382, y≈289 | `person_in_zone_static` |
| **P3** | right side, x=837, y=365 — 350 cm off the AP–node line | `person_out_of_zone` |
| **ZONE** | 60 cm wide strip along the AP–node line, 50 cm short of each end | moving condition |

The annotated "in zone" point is **30 cm off the AP–node line and 182 cm along it
from the AP** — essentially the mid-point, but sitting right on the edge of the
first Fresnel zone (~28 cm radius at 2.4 GHz over this path). For the in-zone
condition, sit **within 20 cm of the line**, not 30.

## What each condition means, physically

| Label | Body position | Path affected |
|---|---|---|
| `empty_room` | nobody in the room, door closed | none |
| `person_in_zone_static` | seated at P1, still | blocks the direct path — large, easy effect |
| `person_in_zone_moving` | walking along the taped zone | sweeps the direct path — largest effect |
| `person_out_of_zone` | seated at P3, still | reflected paths only — small, hard effect |

`person_in_zone_static` is the **primary** L3 contrast. `person_out_of_zone` is
the **hard negative**: it decides whether the claim is interesting, and it is the
one most likely to fail. Collect and report both, in separate recordings —
never in one schedule.

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

- The node sits ~10 cm from the left wall, so its PCB antenna has a large
  reflecting plane immediately behind it.
- The node is directly in front of a 324 cm window at 88 cm height; the glass
  starts at 90 cm, so the board sits just under the sill. Outdoor multipath and
  any metal window frame are part of the static channel.
- AP and node are both at 88 cm, so the direct path is horizontal — no floor or
  ceiling reflection at the specular angle, which makes the direct ray dominant.

## Checklist before the first block

- [ ] AP↔node re-measured with a tape; disagreement above resolved
- [ ] both antennas 88 cm, measured
- [ ] node taped, cable broken only at the PC end
- [ ] zone taped, P1 and P3 marked
- [ ] chair in position for P1 and P3
- [ ] nobody else in the building who might walk past
- [ ] `~/rec.sh --status` on the phone says `(none), (none), free`
