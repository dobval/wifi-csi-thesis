# Capture firmware

The rig runs the `csi_recv_router` example from **esp-csi**, unmodified except for
the partition table. Upstream source is not vendored here — it lives in the ESP-IDF
workspace and is pinned by commit so it can be rebuilt exactly.

| Item | Pin |
|---|---|
| esp-csi | master @ `8633d67` (2026-04-22) |
| ESP-IDF | v5.3.6 (`79e3454c`) |
| Toolchain | esp-13.2.0_20250707 (GCC 13.2.0) |
| Target | ESP32-S3, WROOM-1 **N16R8**, 16 MB flash, 8 MB octal PSRAM |
| Console | 921600 baud, CH343 USB-UART (`/dev/ttyACM0`) |

## Local changes to upstream

One file differs: `partitions.csv`, copied into this directory. Upstream assumes a
2 MB app partition; the board has 16 MB.

- `factory` app **4 MB** at `0x10000` — no OTA, the rig is reflashed over USB
- `storage` **4 MB** at `0x410000` — reserved for future on-device logging

`sdkconfig.defaults` is upstream's, copied here for reference: CSI enabled, AMPDU
TX disabled, 921600 console, 240 MHz CPU, 1000 Hz tick.

`sdkconfig` is deliberately **not** in this repo — it holds the Wi-Fi SSID and
password and is machine-local (gitignored).

## Rebuild

```bash
cd ~/esp/esp-csi/examples/get-started/csi_recv_router
cp <repo>/firmware/partitions.csv .
idf.py set-target esp32s3 && idf.py build
idf.py -p /dev/ttyACM0 -b 921600 flash
```

`tools/record_session.sh` records the esp-csi build hash into every `session.md`,
so each capture is traceable to a firmware revision. If the hash ends in `-dirty`,
the firmware was modified after the commit and the session is not comparable.
