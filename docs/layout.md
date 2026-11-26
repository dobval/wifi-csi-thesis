# Room layout and floor marks — placement A

Fill in the measured values once, photograph the tape, and commit this file. Every
session's `session.md` references these marks, so the labels mean the same thing
across days.

## Top-down plan (not to scale)

```
              +-------------------------------------------------------+
              |                                                       |
              |                                         P3 *          |
              |                                       (far corner)    |
              |                                                       |
              |                                                       |
   +------+   |   + = = = = = = = = = = = = = = = = = = = +         |
   |  AP  |===|===|| 260 cm, AP and node both 88 cm up  ||=====* Node|
   |MR30G |   |   + = = = = = = = = = = = = = = = = = = = +         |
   +------+   |        [                                         ]    |
              |        [   taped ZONE: 60 cm wide, 160 cm long  ]    |
              |        [   P1 *  (mid-point, sensing position)   ]    |
              |        [                                         ]    |
              |                                                       |
              +-------------------------------------------------------+
                    ^                                              ^
                 door                                            window
```

ASCII only because it survives diffs, phones and terminals. `=` is the AP–node
line of sight; `[ ]` is the taped zone boundary.

## Marks

Tape these to the floor. All distances measured with a tape measure, not estimated.

| Mark | Where | Used for |
|---|---|---|
| **Node** | 88 cm above floor, bare board, taped down | never moved mid-campaign |
| **AP** | router, 88 cm above floor | never moved mid-campaign |
| **P1** | mid-point of the AP–node line, inside the taped zone | `person_in_zone_static` |
| **P3** | far corner, at least 1.5 m off the AP–node line | `person_out_of_zone` |
| **ZONE** | strip 60 cm wide × 160 cm long, centred on the AP–node line | moving condition |

Why 60 cm wide: the first Fresnel radius at 2.4 GHz over 260 cm is ~28 cm at the
mid-point, so a 60 cm strip contains the whole ellipsoid where the direct path
actually travels. A body inside it perturbs the line-of-sight path; a body outside
it perturbs only reflections.

## What each condition means, physically

| Label | Body position | Path affected |
|---|---|---|
| `empty_room` | nobody in the room, door closed | none |
| `person_in_zone_static` | seated at P1, still | blocks the direct path — large, easy effect |
| `person_in_zone_moving` | walking along the taped zone | sweeps the direct path — largest effect |
| `person_out_of_zone` | seated at P3, still | reflected paths only — small, hard effect |

`person_in_zone_static` is the **primary** L3 contrast. `person_out_of_zone` is the
**hard negative**: it is the one that decides whether the claim is interesting, and
it is the one most likely to fail. Collect and report both, separately — never in
the same schedule.

## What to do during a run

The cue script announces every transition. Beyond that:

**While `empty_room`:**
- out of the room, door closed, nobody else in it
- do not open the door to check on the capture; read `csi_clock.csv` afterwards
- no pets, no fans switched on or off mid-run

**While `person_in_zone_static`:**
- seated at P1, feet flat, back against the chair
- same chair, same orientation, every session — record it in `session.md`
- breathe normally; breathing is signal, not noise
- do not fidget, check the phone, or shift weight
- do not talk

**While `person_in_zone_moving`:**
- walk at a steady pace along the taped strip, ~1 m/s
- same direction each pass, or alternate and note it
- do not stop inside the zone, do not turn sharply at the ends

**While `person_out_of_zone`:**
- seated at P3, same posture as P1, facing the same way
- do not sit on the AP–node line "just to be safe" — that is the other condition

## Things that silently ruin a session

- moving the node, the cable, or the router after the baseline (all shift the channel)
- a chair in the zone during `empty_room`
- someone walking past the doorway during any block
- phone on the node (it is metal, and it is next to the antenna)
- changing posture mid-block — the largest within-block variance source
- running the capture on battery power with the laptop suspending

## Checklist before the first block

- [ ] both ends 88 cm high, measured
- [ ] node taped, cable broken only at the PC end
- [ ] zone taped, P1 and P3 marked
- [ ] chair in position for P1 and P3
- [ ] nobody else in the building who might walk past
- [ ] `~/rec.sh --status` on the phone says `(none), (none), free`
