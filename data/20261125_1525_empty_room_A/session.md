# 20261125_1525_empty_room_A

| Field | Value |
|---|---|
| Started (UTC) | 2026-11-25T13:25:51Z |
| Label | `empty_room` |
| Placement | `A` |
| Duration requested | 300 s |
| Exit countdown | 20 s (measurement starts at the first CSI row, ~5 s later) |
| Node → AP distance | 260 cm |
| Node height (floor) | 88 cm |
| Node mount | `taped` |
| USB cable broken at | `pc-end` |
| Subject | _ |
| Rig | ESP32-S3-DevKitC-1 N16R8, on-module PCB antenna |
| Firmware | esp-csi `8633d67` |
| Console | 921600 baud, CH343 → `/dev/ttyACM0` |
| Operator | operator@workstation |

**Notes:** A/B/A block 1

## Occupancy timeline

<!-- Scripted entry/exit times, or why the label holds for the whole capture. -->

## Capture result

```
{
  "port": "/dev/ttyACM0",
  "baud": 921600,
  "out": "<repo>/data/20261125_1525_empty_room_A/csi.csv",
  "started_unix_ns": 1795613171614666737,
  "stopped_unix_ns": 1795613476928539471,
  "elapsed_s": 305.314,
  "boot_wait_s": 5.207,
  "first_csi_unix_ns": 1795613176821702541,
  "csi_span_s": 300.107,
  "bytes": 13229131,
  "total_lines": 30145,
  "csi_rows": 30035,
  "rows_per_s": 100.081,
  "malformed_csi_rows": 0,
  "trailing_partial_line": false,
  "non_csi_lines": 110,
  "non_csi_samples": [
    "ESP-ROM:esp32s3-20210327",
    "Build:Mar 27 2021",
    "rst:0x15 (USB_UART_CHIP_RESET),boot:0x8 (SPI_FAST_FLASH_BOOT)",
    "Saved PC:0x4207a6a0",
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
    "\u001b[0;32mI (30) boot: Enabling RNG early entropy source...\u001b[0m"
  ],
  "first_seq": "0",
  "last_seq": "30034",
  "channels": {
    "6": 30035
  },
  "max_interrow_gap_ms": 5207.06,
  "last_board_local_timestamp_us": "305459742"
}```

- finished (UTC): 2026-11-25T13:31:16Z
- capture worker exit code: 0
- AP BSSID observed: ap_1
