# STATE

## Current milestone
On-hardware bring-up complete (2026-11-24). ESP32-S3-DevKitC-1 N16R8 flashed with esp-csi
`csi_recv_router` (router-ping mode) and verified streaming CSI at **~100 Hz** over the COM port.
Flash layout corrected to 16 MB with a 4 MB factory app. Exploratory 6 h 23 m soak captured and
audited (zero lost rows). Six labelled 300 s sessions recorded 2026-11-25 (3 empty, 3 person),
including an interleaved empty → person → empty block.
**Outcome: the session-level design is drift-limited** — two empty sessions separate as strongly
as empty vs person. The unit of analysis must move inside a single recording. See
`results/20261125_l3_probe/ANALYSIS.md`.

## Rig geometry (placement A)
| Item | Value |
|---|---|
| AP ↔ node distance | **260 cm** (tape, written down by the operator) |
| Both antennas height | **88 cm** above floor |
| Node | bare board, on-module PCB antenna, non-metal surface |
| Mount | **taped down** — position committed for the whole soak |
| In-zone position (P1) | **marked on the floor**, mid-point of the node–AP line; subject **stands** there (no chair) |
| Out-of-zone position (P3) | **on the sofa**, far side, well off the node–AP line; subject **sits** |
| Cable handling | USB broken **at the PC end only**, never at the board |
| Measured RSSI at this geometry | mean **−38.2 dBm** (range −32 … −52) |
| Room | 760 × 520 cm, node against the left wall in front of a 324 cm window, AP against the top wall |
| Floor plan | `docs/layout.md`, generated from `docs/layout-source.json` by `tools/render_plan.py` |

Distance and height are measured floor-to-floor with a tape and must be re-measured
(not estimated) after any movement of the rig. Taping and PC-end-only cable breaks
are protocol, not preference: the PCB antenna is parasitically coupled to the USB
cable, so breaking the cable at the board end changes the static channel.

**Only three numbers are measured: 88 cm node height, 88 cm AP height, 260 cm
AP ↔ node.** Everything else in `docs/layout.md` is a proportional sketch from the
room planner and must not be used to derive distances. In particular the planner's
"AP" and "ESP32" markers are text-label positions, offset so the words do not
overlap the drawing — the 361 units between them is the distance between two
labels, not between two objects.

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
- **Soak 2026-11-24 14:39 → 21:02 (6 h 23 m, 958 MiB) audited — see
  `results/2026-1-24_1439-2102/ANALYSIS.md`.** 2 303 823 CSI rows, `seq` 0…2 303 822 with
  **zero missing packets**, 0 malformed rows, 383 consecutive minutes at exactly 6000 rows.
  100.18 Hz mean, p99 17.8 ms, 112 intervals > 50 ms (board-side stalls, max 273 ms; no
  transport loss), 5 counter wraps. All rows `channel=6`, `sig_mode=1`, `len=128`.
  Per-minute mean RSSI wandered **6.9 dB** (−42.0 … −35.2) with a 4.1 dB step; CSI amplitude
  sd correlates with mean RSSI at **r = +0.53** → variance features must be gain-normalised.
  Exploratory only; unlabelled occupancy; never enters M2/M4.
- **Geometry caveat — do not cite the −29 dBm figures.** Every RSSI value in the
  bullets above (−29 / −28 dBm) was taken **untaped, without a log file**, at an
  unrecorded position. They are "instrument alive" checks, not measurements of a
  geometry. The only reading with committed geometry is the soak's **−38.2 dBm at
  260 cm / 88 cm, taped**. The 9 dB gap between the two is **not** a distance
  measurement and must not be reconciled, attributed, or plotted.
- **Labelled sessions, 2026-11-25** — six 300 s sessions in `data/` (3 × `empty_room`,
  3 × `person_out_of_zone`), including an interleaved empty → person → empty block
  (15:25 / 15:33 / 15:40). All 0 sequence gaps, 100 Hz, channel 6, RSSI −37…−38 dBm.
  Analysis: `results/20261125_l3_probe/ANALYSIS.md`.
  **Result: drift-limited negative.** Two *empty* sessions recorded 15 min apart separate at
  |AUC−0.5| = **0.500** on `rssi_mean` alone (−37.39 vs −38.03 dBm). Every empty-vs-person
  comparison is 0.450–0.487, i.e. **no larger**. The amplitude change also flips sign between
  the two clean person sessions (−0.37 dB at 15:11, +0.80 dB at 15:33). Between-session drift
  therefore explains the apparent class difference; no person effect survives it.
  **Correction:** earlier figures of AUC 0.870–0.980 in this file were produced by a model
  trained on a single class (‖w‖ ≈ 2e-16) and are **withdrawn**. `tools/probe_l3.py` now uses a
  training-free rank test with a permutation null.
  **Standalone finding that does survive:** RSSI alone perfectly separated two empty sessions, so
  any RSSI-threshold occupancy detector reports a condition change on an unchanged room.
- **`person_out_of_zone` is a real physical perturbation** (mean |H| differs by 0.4–0.8 dB
  between conditions, above the 1 dB RSSI quantisation), but at one session per condition it is
  **smaller than the drift between sessions**. This is a resolution limit of the session-level
  design, not evidence that the person is invisible.

## Known issues / deferred
- 8 MB octal PSRAM not enabled (`CONFIG_SPIRAM` unset). Not needed for CSI capture.
  Note: octal PSRAM occupies GPIO35–37 — never wire those.
- CSI rows are **CRLF-terminated** (`]"` then `\r\n`), mean ~437 B, max 509 B. `csv.reader` handles
  this natively; a hand-rolled `split(',')` + `json.loads` parser must strip `\r` first.
- RSSI at placement A is −38 dBm (260 cm). The mission needs 1–3 m; this is inside that band,
  so placement A is usable — but the soak's 6.9 dB wander means a single RSSI reading proves
  nothing about the geometry. Record distance by tape, not by RSSI.
- Raw captures are ~150 MB/h. `data/**/*.csv|*.log` and `results/**/*.log` are gitignored
  (a 1 GB soak in git history is irreversible). The session dir carries `session.md` +
  `manifest.sha256`; raw files live on disk + external backup. Install `git-lfs` if raw data
  ever needs to be versioned.
- **The phone cue loop was SIGKILLed twice, both times around block 4.** `signal 9` is
  Android's process killer, and it cannot be trapped, so the PC capture is left running
  unguided. Cause: `wait_until` forked 16 processes per second (`date`, two `awk`, `sleep`
  every 0.25 s) — ~19 000 children over a 20 min run. Rewritten to use bash's
  `EPOCHREALTIME` and integer microseconds with one `sleep` per second.
  **That was not the cause.** With battery unrestricted and the fork storm fixed it still died
  at block 4. The real cause: `alarm()` backgrounded up to five jobs per cue (TTS, two
  vibrations, a torch subshell, a toast), twice per block, so ~32 concurrent children accumulated
  and Android's phantom-process killer SIGKILLed Termux. `alarm()` is now serial; nothing in the
  cue path runs in the background.
- **`ser.close()` can block in the kernel** (`wchan tty_wait_until_sent`) when a capture is
  stopped mid-stream on the CH343. Observed 2026-11-26: the worker stopped reading but never
  exited, holding the capture lock. Mitigated: `csi_stats.json` is now written *before* the
  port is closed, and close runs in a daemon thread with a 2 s join. If a worker still hangs,
  `kill -9 <pid>`; the wrapper then finalises the session (exit code 137, `stats missing`).
- **`data/20261126_0941_alternating_A_ABORTED/`** — a 3-minute alternating capture started from
  the phone and interrupted with Ctrl-C on the phone (which does not stop the PC). The subject
  never followed the cue schedule, so the block labels are meaningless. **Do not use it.** Kept
  for the record with its `manifest.sha256` intact.
- **`data/20261126_0949_alternating_A_PARTIAL/`** — the first alternating run that produced usable
  blocks. 360 s, 35 643 rows, 0 gaps. **Only blocks 1–3 are valid**; the phone cue loop died just
  before block 4 and the rest is unguided. Analyse with `--blocks 1-3`. Block means: empty 9.373,
  person 9.812, empty 9.187 — the two empties agree to 0.19 while person blocks sit +0.44 / +1.45
  above them. See `results/20261126_alternating_probe/ANALYSIS.md`. n = 1 paired observation:
  validates the mechanism, not the effect.
- The capture lock is a `flock` on `/tmp/esp32_csi_capture.lock`. **Never delete it.** Two
  readers on one serial port each receive part of the stream and both files look plausible;
  the corruption is undetectable afterwards. It is released automatically when the capture exits.
- Wi-Fi auth failures surface as `wifi:state: run -> init (0xf00)` + `Wi-Fi disconnected 15` —
  reason 15 is 4-way handshake timeout, i.e. **wrong PSK**. Check `CONFIG_EXAMPLE_WIFI_PASSWORD` first.

## Next action
1. **Change the unit of analysis from session to within-recording.** The A/B/A block showed
   that between-session drift (0.500 on two *empty* sessions) is as large as any occupancy
   effect (0.450–0.487). Sessions cannot be the unit; drift must be common-mode.
2. **Build the alternating-capture mode**: one continuous ≥10 min recording, condition switched
   on a scripted schedule (e.g. 60 s out / 60 s in, repeated), with a timestamped event log in
   the same clock domain as `local_timestamp`. Then windows are labelled by time, not by file,
   and the null comes from held-out time blocks of the *same* recording.
   **Status: implemented** — `record_session.sh --label alternating --alternate 60 --cycles 30`
   writes `schedule.csv` + `cues.txt` and picks the countdown so that the phone-timer block
   boundaries are exactly the transitions. `tools/probe_alt.py` slices by the unwrapped board
   clock, reports per-cycle paired differences, a block-level AUC with a permutation null, and
   a within-recording null (odd vs even empty blocks). Validated on synthetic data only; not yet
   run on hardware.
   **Phone cueing:** `tools/phone/record_remote.sh` (Termux) SSHes the launch command and then
   cues the blocks with vibration / spoken instruction / torch flash. It anchors the schedule to
   the PC's `RECORDING` line rather than to the SSH call, so SSH latency and boot do not shift
   the block boundaries. Dry-run tested; not yet used on a phone.
   **Conditions:** both scripts take `--condition-a` / `--condition-b` (default
   `empty_room` ↔ `person_in_zone_static`). Floor marks, zone geometry and per-condition
   instructions are defined once in `docs/layout.md`. The pair must be chosen deliberately:
   in-zone static is the primary L3 contrast (blocks the Fresnel ellipsoid, large effect);
   out-of-zone is the hard negative (reflections only, small effect); moving is L1. Never put
   three conditions in one schedule. An `EXIT` trap stops the PC capture if the cue loop dies,
   because an unguided alternating capture has no valid labels.
3. Record ≥2 such recordings on ≥2 days before any classifier work.
4. Port the example into `firmware/` (carry over `partitions.csv` + flash size 16 MB); record firmware
   build hash per session.
5. ~~Build the host-side capture script~~ — done and validated on hardware.
6. Treat placement A as committed only as of the soak. The −29 dBm bring-up reading is
   unciteable (untaped, unlogged); do not "reconcile" it with −38.2 dBm. If the rig is
   moved, re-tape, re-measure, and re-record the baseline.

## Pending decision — label taxonomy
Proposed by operator: `static_person_between_APs`, `fidgeting_person_between_APs`,
`no_people_between_APs`, `person_in_zone_static`, `person_in_zone_moving`,
`person_out_of_zone`. Assistant position: labels must describe **ground-truth geometry and
occupancy**, never the link corridor or what the sensor sees. `no_people_between_APs` is
ambiguous (a person 2 m off-axis still perturbs the channel) and should be replaced by
`empty_room` (verified no humans/pets) vs `person_out_of_zone` (present, outside the marked
zone). **Empirically:** `person_out_of_zone` and `empty_room` differ in mean amplitude by 0.4–0.8 dB,
but the sign is not consistent across sessions, so the case for keeping them separate rests on
the physical argument (a body perturbs reflected paths regardless of LOS) and on the fact that
they are different ground-truth states — **not** on a separability claim. Merging them would put
two physically different situations into the negative class. `fidgeting` should be a note in
`session.md`, not a class.

## Blockers
None.
