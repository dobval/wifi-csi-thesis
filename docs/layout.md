# Room layout and floor marks — placement A

Topology comes from `docs/layout-source.json` (room planner export, 2026-11-26).
The plan below is generated from it, never drawn by hand:

```bash
python3 tools/render_plan.py docs/layout-source.json --width 76
```

## Plan (topology, not to scale)

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

## What is measured and what is only a sketch

| Quantity | Value | Status |
|---|---|---|
| Node height | **88 cm** | measured |
| AP height | **88 cm** | measured |
| AP ↔ node | **260 cm** | measured |
| Room size | — | sketch; **do not quote** |
| Door 98 / window 324 / walls 270 | planner values | unverified |
| Seat positions, wall offsets | plan units | sketch |

Only the three measured numbers may be used for anything. The plan is "closely
proportional", not to scale.

**Do not compute distances from the plan.** Its "AP" and "ESP32" markers are
*text labels*, offset so the words do not sit on top of the drawing; the 361
units between them is the gap between two labels, not between two objects. No
scale factor can rescue that, so `render_plan.py` reports plan units only.

## What is fixed, and what is not

Fixed, so they cannot drift mid-session:

- the **board and its USB cable** are taped down
- **P1 is marked** on the floor

Not fixed:

- there is no taped *zone boundary* — the 60 cm strip is a conceptual region, and
  only matters for the moving condition
- P3 is not reported as marked; measure it and record the offset

Because P1 is marked, the in-zone condition is reproducible — **provided the mark
is actually used**: stand with the mark between your feet, not merely near it.
A 30 cm error is the size of the Fresnel radius, i.e. a different condition.

## Positions

All distances from a tape measure, never from the plan.

| Position | Where | How to establish it |
|---|---|---|
| **Node** | 260 cm from the AP, 88 cm high, board and cable taped | already done |
| **AP** | 88 cm high | fixed |
| **P1** | mid-point of the node–AP line: **130 cm from each end**, on the line; **marked on the floor**, subject **stands** | use the existing mark |
| **P3** | far side of the room, **at least 1.5 m off** the node–AP line | not marked; measure the perpendicular offset and write it down |
| **zone** | conceptual: 60 cm wide strip along the line, 40 cm short of each end | only needed for the moving condition |

Set P1 by running a string or tape from the node to the AP and measuring 130 cm
along it. Do not estimate the mid-point from the room.

## Why 60 cm wide and 20 cm tolerance

First Fresnel radius at 2.4 GHz over 260 cm:

```
sqrt(λ·d₁·d₂/(d₁+d₂)) = sqrt(0.125 · 1.30 · 1.30 / 2.60) ≈ 0.285 m  →  28 cm
```

A body further than ~28 cm from the line is no longer obstructing the direct path,
it is only changing reflections — which is the *other* condition. So P1 should be
within ~20 cm of the line to be safely inside.

## What each condition means, physically

| Label | Body position | Path affected |
|---|---|---|
| `empty_room` | nobody in the room, door closed | none |
| `person_in_zone_static` | seated at P1, still | blocks the direct path — large, easy effect |
| `person_in_zone_moving` | walking along the zone | sweeps the direct path — largest effect |
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
- **standing** at P1 with the floor mark between your feet — there is no chair
- weight even, arms relaxed, feet planted and unmoving
- do not lean on anything, sway, shift feet, or put a hand on a wall or table
- breathe normally; breathing is the L2 signal, not noise
- do not fidget, check the phone or talk

**`person_in_zone_moving`:**
- steady pace along the node–AP line, past P1, ~1 m/s
- same direction each pass, or alternate and note it
- do not stop inside the zone or turn sharply at the ends

**`person_out_of_zone`:**
- seated at P3, same posture as P1, facing the same way
- do not drift onto the node–AP line "to be safe" — that is the other condition

## Things that silently ruin a session

- moving the node, the cable or the router after the baseline — all shift the channel
- furniture moved into the zone during `empty_room`
- someone walking past the door during any block
- phone resting on the node (metal, next to the antenna)
- changing posture mid-block — the largest within-block variance source
- a window opened or a blind moved between blocks
- running on battery with the laptop set to suspend

## RF notes worth recording in the thesis

- The node sits close to a wall, so its PCB antenna has a reflecting plane
  immediately behind it. (How close is a sketch dimension — measure it if you
  want to state it.)
- The node is in front of a wide window. If the planner's 90 cm sill is right, the
  board at 88 cm is just below it. Verify with a tape before writing it down.
- AP and node are both at 88 cm, so the direct path is horizontal: no specular
  floor or ceiling reflection, which is why the direct ray dominates.

## Checklist before the first block

- [ ] AP↔node taped at **260 cm**, both antennas 88 cm
- [ ] node and cable taped, cable broken only at the PC end
- [ ] the P1 floor mark is used, not approximated (standing, mark between the feet)
- [ ] P3 offset measured and written down
- [ ] posture recorded: P1 is **standing**, P3 is **seated** (do not compare the
      two conditions directly — posture is a confound for that comparison)
- [ ] nobody else in the building who might walk past
- [ ] `~/rec.sh --status` on the phone says `(none), (none), free`
