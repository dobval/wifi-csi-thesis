# STATE

## Current milestone
On-hardware bring-up complete (2026-11-24). ESP32-S3-DevKitC-1 N16R8 flashed with esp-csi
`csi_recv_router` (router-ping mode) and verified streaming CSI at **~100 Hz** over the COM port.
Flash layout corrected to 16 MB with a 4 MB factory app. No baseline data recorded yet.

## Pinned versions
| Item | Pin | Location |
|---|---|---|
| ESP-IDF | **v5.3.6** (LTS, commit `79e3454c68248bd7d881721c9b2e94561378a8ce`) | `~/esp/esp-idf` |
| esp-csi | master @ `8633d67152db2808f141cc1595970aa9cf406045` (2026-04-22) | `~/esp/esp-csi` |
| Xtensa toolchain | esp-13.2.0_20250707 (GCC 13.2.0) | `~/.espressif` |
| Python env | idf5.3_py3.11_env (Python 3.11.5) | `~/.espressif/python_env` |
| Rig A board | ESP32-S3-DevKitC-1, WROOM-1 **N16R8** (16 MB flash, 8 MB octal PSRAM), 2× USB-C | on bench |
| Rig B board | same model — spare / `csi_send` diagnostic partner | unused |

Do not upgrade these mid-campaign; a toolchain change is a rig change (re-record empty baseline).

## Environment
- Debian (forky/sid), CMake 4.3.4, ninja 1.13.2.
- Activate in any shell: `get_idf` (alias in `~/.bashrc` → `. ~/esp/esp-idf/export.sh`).
- User is in `dialout` (serial access; re-login if a shell predates the change).

## Repository
- Git-initialised 2026-11-24, branch `main`, local identity `dobval <100198047+dobval@users.noreply.github.com>`.
- Tracked: `STATE.md`, `RESEARCH.md`, `repository_and_data_discipline.txt`, `firmware/`, `tools/`,
  `data/`, `sessions/`, `results/`, `docs/`.
- Ignored: ESP-IDF build artifacts (`build/`, `managed_components/`, `*.bin`), per-machine
  `sdkconfig*` (holds Wi-Fi credentials), Python caches, `.vscode/`.
- `*.csv` is marked `-text` in `.gitattributes` so raw captures are never line-ending-normalised.

## Hardware / rig A
- ESP32-S3-DevKitC-1 clone, WROOM-1 N16R8, chip rev v0.2, 240 MHz. On-module PCB antenna
  (no IPEX); no external antenna.
- **COM port = CH343 USB-UART bridge (`1a86:55d3`) → `/dev/ttyACM0`.** The CH343 uses the
  CDC-ACM class driver, so it enumerates as `ttyACM*`, **not** `ttyUSB*` (this differs from the
  CH340/CP210x guidance in most tutorials). Stable path:
  `/dev/serial/by-id/usb-1a86_USB_Single_Serial_5D33086450-if00`.
- Second USB-C port = ESP32-S3 native USB-Serial-JTAG (GPIO19/20), would appear as `/dev/ttyACM1`
  (`303a:1001`). Unused so far; required later for OpenOCD JTAG (`board/esp32s3-builtin.cfg`).
  Both ports power the board; never plug both in at once.
- Physical rig: bare board on a non-metal surface, one USB-C data cable, **nothing in the headers**,
  no breadboard (keeps metal and jumper wires out of the antenna near-field).
- AP: SSID `ssid_1` (dedicated 2.4 GHz SSID, separate from the 5 GHz one), BSSID
  `ap_1`, STA IP `192.168.1.x`.
- Router: Mercusys **MR30G** (AC1200; 2.4 GHz 802.11n 300 Mbps, 5 GHz 802.11ac). Settings live at
  **Advanced → Wireless → Wireless Settings** (Mercusys FAQ-321 lists MR30G explicitly).
- Pinned 2.4 GHz config (2026-11-24): **channel 6**, **20 MHz**, **802.11n only**, AP/client
  isolation off. Confirmed on air: `sig_mode=1` (HT), `mcs=7`, `bandwidth=0`, `sgi=0`,
  `secondary_channel=0`.

## Firmware config (csi_recv_router)
- Wi-Fi: SSID `ssid_1`; password in `CONFIG_EXAMPLE_WIFI_PASSWORD` (`sdkconfig` line 562).
  `sdkconfig` is gitignored (upstream `.gitignore:70`), so credentials stay out of the repo and
  exist only on this machine. `sdkconfig.defaults` carries the non-secret build settings.
- Flash: `CONFIG_ESPTOOLPY_FLASHSIZE="16MB"`.
- Partition table: **custom** `partitions.csv` (project root) —
  `factory` app **4 MB** @0x10000, `storage` (spiffs) **4 MB** @0x410000. No OTA (USB reflash only).
- Console: 921600 (`CONFIG_ESP_CONSOLE_UART_BAUDRATE`); monitor baud 921600.

## Verified
- `idf.py set-target esp32s3 && idf.py build` in `~/esp/esp-csi/examples/get-started/csi_recv_router` → success.
- `idf.py -p /dev/ttyACM0 -b 921600 flash` → success, hash verified (740,000 B image, app version `8633d67`).
- Flash/partition rebuild 2026-11-24: boot log now reports `SPI Flash Size : 16MB`, no size-mismatch
  warning, partition table `factory 0x10000/0x400000` + `storage 0x410000/0x400000`.
- CSI stream verified 2026-11-24 (pre-partition-change): clean boot log, `================ CSI RECV ================`
  header, then **2000 `CSI_DATA` rows in 20 s (100 Hz)**, RSSI −29 dBm, `len=128`, `sig_len=83`,
  `channel=10`, `secondary_channel=0`; all rows well-formed.
- CSI stream re-verified after 16 MB rebuild: 885 rows in 14 s ≈ **101 Hz** over an 8.7 s window
  (boot consumes 5.3 s), RSSI −28 dBm, `channel=8`, AP `ap_1`.
- CSI stream verified 2026-11-24 after SSID change + router pinning: connected to `ssid_1`,
  **channel 6**, BW20; **949 rows in 9.5 s ≈ 100 Hz**; RSSI −29 dBm; `sig_mode=1` (HT), `mcs=7`,
  `sgi=0`, `bandwidth=0`, `secondary_channel=0`, `len=128`.
- Console baud is already 921600 (`CONFIG_ESP_CONSOLE_UART_BAUDRATE`); ~44 KB/s ≈ 47 % of link
  capacity. A 115200 monitor would drop/truncate CSI lines — always pass `-b 921600`.

## Known issues / deferred
- 8 MB octal PSRAM not enabled (`CONFIG_SPIRAM` unset). Not needed for CSI capture.
  Note: octal PSRAM occupies GPIO35–37 — never wire those.
- CSI rows are **CRLF-terminated** (`]"` then `\r\n`), mean ~437 B, max 509 B. `csv.reader` handles
  this natively; a hand-rolled `split(',')` + `json.loads` parser must strip `\r` first.
- RSSI −29 dBm ⇒ rig A is currently very close to the AP. The mission needs **1–3 m**; reposition
  before recording any baseline.
- Wi-Fi auth failures surface as `wifi:state: run -> init (0xf00)` + `Wi-Fi disconnected 15` —
  reason 15 is 4-way handshake timeout, i.e. **wrong PSK**. Check `CONFIG_EXAMPLE_WIFI_PASSWORD` first.

## Next action
1. Reposition rig A to 1–3 m from the AP, line of sight, antenna end facing the AP; record measured
   distance and RSSI. Re-confirm CSI rows continue.
2. Port the example into `firmware/` (carry over `partitions.csv` + flash size 16 MB); record firmware
   build hash per session.
3. Build the host-side capture script (serial → CSV/parquet + session metadata in `session.md`).
4. Record the first empty-room baseline once placement is fixed.

## Blockers
None.
