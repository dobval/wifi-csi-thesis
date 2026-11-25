# 20261125_1511_person_out_of_zone_A

| Field | Value |
|---|---|
| Started (UTC) | 2026-11-25T13:11:19Z |
| Label | `person_out_of_zone` |
| Placement | `A` |
| Duration requested | 300 s |
| Exit countdown | 30 s |
| Settle window | 15 s after first CSI row (excluded from the measurement window) |
| Node → AP distance | 260 cm |
| Node height (floor) | 88 cm |
| Node mount | `taped` |
| USB cable broken at | `pc-end` |
| Subject | _ |
| Rig | ESP32-S3-DevKitC-1 N16R8, on-module PCB antenna |
| Firmware | esp-csi `8633d67` |
| Console | 921600 baud, CH343 → `/dev/ttyACM0` |
| Operator | operator@workstation |

**Notes:** subject seated within 5 seconds of executing this command

## Occupancy timeline

<!-- Scripted entry/exit times, or why the label holds for the whole capture. -->

## Capture result

```
{
  "port": "/dev/ttyACM0",
  "baud": 921600,
  "out": "<repo>/data/20261125_1511_person_out_of_zone_A/csi.csv",
  "started_unix_ns": 1795612310247640320,
  "stopped_unix_ns": 1795612630576798257,
  "elapsed_s": 320.329,
  "boot_wait_s": 5.207,
  "settle_s": 15.0,
  "first_csi_unix_ns": 1795612315454747867,
  "csi_span_s": 315.122,
  "bytes": 13847319,
  "total_lines": 31658,
  "csi_rows": 31549,
  "rows_per_s": 100.117,
  "malformed_csi_rows": 0,
  "trailing_partial_line": true,
  "non_csi_lines": 109,
  "non_csi_samples": [
    "Build:Mar 27 2021",
    "rst:0x15 (USB_UART_CHIP_RESET),boot:0x8 (SPI_FAST_FLASH_BOOT)",
    "Saved PC:0x4037ac62",
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
  "last_seq": "31548",
  "channels": {
    "6": 31549
  },
  "max_interrow_gap_ms": 5207.13,
  "last_board_local_timestamp_us": "320469431"
}```

- finished (UTC): 2026-11-25T13:17:10Z
- capture worker exit code: 0
- AP BSSID observed: ap_1
