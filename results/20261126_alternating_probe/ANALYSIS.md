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
