# 20261126_0941_alternating_A

| Field | Value |
|---|---|
| Started (UTC) | 2026-11-26T07:41:16Z |
| Label | `alternating` |
| Placement | `A` |
| Duration requested | 3600 s |
| Exit countdown | 85 s (measurement starts at the first CSI row, ~5 s later) |
| Node → AP distance | 260 cm |
| Node height (floor) | 88 cm |
| Node mount | `taped` |
| USB cable broken at | `pc-end` |
| Subject | _ |
| Rig | ESP32-S3-DevKitC-1 N16R8, on-module PCB antenna |
| Firmware | esp-csi `8633d67` |
| Console | 921600 baud, CH343 → `/dev/ttyACM0` |
| Operator | operator@workstation |

**Notes:** phone-cued alternating block

## Occupancy timeline

<!-- Scripted entry/exit times, or why the label holds for the whole capture. -->

## Alternating schedule

One continuous capture, both conditions, so between-block drift is common-mode.
Machine-readable boundaries in `schedule.csv` (seconds from the first CSI row);
`guard_s` is discarded at each end of every block.

```
ALTERNATING SCHEDULE — 20 cycles x 90s per block (3600s)

Start the phone timer the instant you press Enter. The measurement begins
85s + ~5s boot after that, i.e. at phone time ~90s, so:
  - block boundaries are phone readings 180s, 270s, ...
  - the first 10s and last 10s of each block are discarded as transition

block  condition            phone timer
1      empty_room           90s: stay out
2      person_out_of_zone   168s: walk in, seated by 180s
3      empty_room           270s: leave the room
4      person_out_of_zone   348s: walk in, seated by 360s
5      empty_room           450s: leave the room
6      person_out_of_zone   528s: walk in, seated by 540s
7      empty_room           630s: leave the room
8      person_out_of_zone   708s: walk in, seated by 720s
9      empty_room           810s: leave the room
10     person_out_of_zone   888s: walk in, seated by 900s
11     empty_room           990s: leave the room
12     person_out_of_zone   1068s: walk in, seated by 1080s
13     empty_room           1170s: leave the room
14     person_out_of_zone   1248s: walk in, seated by 1260s
15     empty_room           1350s: leave the room
16     person_out_of_zone   1428s: walk in, seated by 1440s
17     empty_room           1530s: leave the room
18     person_out_of_zone   1608s: walk in, seated by 1620s
19     empty_room           1710s: leave the room
20     person_out_of_zone   1788s: walk in, seated by 1800s
21     empty_room           1890s: leave the room
22     person_out_of_zone   1968s: walk in, seated by 1980s
23     empty_room           2070s: leave the room
24     person_out_of_zone   2148s: walk in, seated by 2160s
25     empty_room           2250s: leave the room
26     person_out_of_zone   2328s: walk in, seated by 2340s
27     empty_room           2430s: leave the room
28     person_out_of_zone   2508s: walk in, seated by 2520s
29     empty_room           2610s: leave the room
30     person_out_of_zone   2688s: walk in, seated by 2700s
31     empty_room           2790s: leave the room
32     person_out_of_zone   2868s: walk in, seated by 2880s
33     empty_room           2970s: leave the room
34     person_out_of_zone   3048s: walk in, seated by 3060s
35     empty_room           3150s: leave the room
36     person_out_of_zone   3228s: walk in, seated by 3240s
37     empty_room           3330s: leave the room
38     person_out_of_zone   3408s: walk in, seated by 3420s
39     empty_room           3510s: leave the room
40     person_out_of_zone   3588s: walk in, seated by 3600s
```

## Capture result

```
stats missing
```

- finished (UTC): 2026-11-26T07:46:20Z
- capture worker exit code: 137
- AP BSSID observed: ap_1
