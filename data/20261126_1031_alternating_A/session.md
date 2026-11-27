# 20261126_1031_alternating_A

| Field | Value |
|---|---|
| Started (UTC) | 2026-11-26T08:31:15Z |
| Label | `alternating` |
| Placement | `A` |
| Duration requested | 1200 s |
| Exit countdown | 55 s (measurement starts at the first CSI row, ~5 s later) |
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
ALTERNATING SCHEDULE — 10 cycles x 60s per block (1200s)

Contrast: empty_room  <->  person_in_zone_static

Start the phone timer the instant you press Enter. The measurement begins
55s + ~5s boot after that, i.e. at phone time ~60s, so:
  - block boundaries are phone readings 120s, 180s, ...
  - the first 10s and last 10s of each block are discarded as transition
  - floor marks and posture: docs/layout.md

block  condition                ready by   what to do
1      empty_room               60s        out of the room, door closed, nobody else in
2      person_in_zone_static    120s       stand at P1 (marked mid-point of the AP-node line), stay still
3      empty_room               180s       out of the room, door closed, nobody else in
4      person_in_zone_static    240s       stand at P1 (marked mid-point of the AP-node line), stay still
5      empty_room               300s       out of the room, door closed, nobody else in
6      person_in_zone_static    360s       stand at P1 (marked mid-point of the AP-node line), stay still
7      empty_room               420s       out of the room, door closed, nobody else in
8      person_in_zone_static    480s       stand at P1 (marked mid-point of the AP-node line), stay still
9      empty_room               540s       out of the room, door closed, nobody else in
10     person_in_zone_static    600s       stand at P1 (marked mid-point of the AP-node line), stay still
11     empty_room               660s       out of the room, door closed, nobody else in
12     person_in_zone_static    720s       stand at P1 (marked mid-point of the AP-node line), stay still
13     empty_room               780s       out of the room, door closed, nobody else in
14     person_in_zone_static    840s       stand at P1 (marked mid-point of the AP-node line), stay still
15     empty_room               900s       out of the room, door closed, nobody else in
16     person_in_zone_static    960s       stand at P1 (marked mid-point of the AP-node line), stay still
17     empty_room               1020s      out of the room, door closed, nobody else in
18     person_in_zone_static    1080s      stand at P1 (marked mid-point of the AP-node line), stay still
19     empty_room               1140s      out of the room, door closed, nobody else in
20     person_in_zone_static    1200s      stand at P1 (marked mid-point of the AP-node line), stay still
```

## Capture result

```
{
  "port": "/dev/ttyACM0",
  "baud": 921600,
  "out": "<repo>/data/20261126_1031_alternating_A/csi.csv",
  "started_unix_ns": 1795681931140136541,
  "stopped_unix_ns": 1795682180381264740,
  "elapsed_s": 249.241,
  "boot_wait_s": 4.606,
  "first_csi_unix_ns": 1795681935746188304,
  "csi_span_s": 244.635,
  "bytes": 10686520,
  "total_lines": 24622,
  "csi_rows": 24513,
  "rows_per_s": 100.202,
  "malformed_csi_rows": 0,
  "trailing_partial_line": false,
  "non_csi_lines": 109,
  "non_csi_samples": [
    "Build:Mar 27 2021",
    "rst:0x15 (USB_UART_CHIP_RESET),boot:0x8 (SPI_FAST_FLASH_BOOT)",
    "Saved PC:0x40048839",
    "SPIWP:0xee",
    "mode:DIO, clock div:1",
    "load:0x3fce2810,len:0x1828",
    "load:0x403c8700,len:0x4",
    "load:0x403c8704,len:0xcf8",
    "load:0x403cb700,len:0x2ed0",
    "entry 0x403c891c",
    "\u001b[0;32mI (26) boot: ESP-IDF v5.3.6 2nd stage bootloader\u001b[0m",
    "\u001b[0;32mI (27) boot: compile time Nov 24 2026 12:35:25\u001b[0m",
    "\u001b[0;32mI (27) boot: Multicore bootloader\u001b[0m",
    "\u001b[0;32mI (27) boot: chip revision: v0.2\u001b[0m",
    "\u001b[0;32mI (28) boot: efuse block revision: v1.4\u001b[0m",
    "\u001b[0;32mI (28) boot.esp32s3: Boot SPI Speed : 80MHz\u001b[0m",
    "\u001b[0;32mI (29) boot.esp32s3: SPI Mode       : DIO\u001b[0m",
    "\u001b[0;32mI (29) boot.esp32s3: SPI Flash Size : 16MB\u001b[0m",
    "\u001b[0;32mI (30) boot: Enabling RNG early entropy source...\u001b[0m",
    "\u001b[0;32mI (30) boot: Partition Table:\u001b[0m"
  ],
  "first_seq": "0",
  "last_seq": "24512",
  "channels": {
    "6": 24513
  },
  "max_interrow_gap_ms": 4606.07,
  "last_board_local_timestamp_us": "249392452"
}```

- finished (UTC): 2026-11-26T08:36:20Z
- capture worker exit code: 0
- AP BSSID observed: ap_1
