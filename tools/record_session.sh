#!/usr/bin/env bash
# record_session.sh — start a labelled CSI capture session.
#
# Creates data/<YYYYMMDD>_<label>_<placement>/, writes the protocol file, counts
# down so you can leave the room, captures in a detached tmux session, then
# finalises with a SHA-256 manifest and capture statistics.
#
#   ./tools/record_session.sh --label person_out_of_zone --duration 300 \
#       --distance-cm 260 --height-cm 88 --notes "subject seated, far corner"
#
# Rig handling is recorded per session and defaults to the committed protocol:
#   --node-mount taped        how the node is held (taped|loose|stand|hand)
#   --cable-break pc-end      where the USB is broken (pc-end|board)
# Both affect the static channel: the PCB antenna is coupled to the USB cable.
#
# Timing: --countdown is the quiet time before the port opens (the open resets
# the board, costing ~5 s of boot banner). The measurement window starts at the
# first CSI row, i.e. launch + countdown + boot, and runs for --duration. The
# exact boot wait is recorded as boot_wait_s in csi_stats.json.
#
# Labels (from the condition taxonomy; geometry-based, never inferred):
#   empty_room                verified no humans/pets, scripted entry/exit
#   person_in_zone_static     person at a marked floor position, still
#   person_in_zone_moving     scripted walk-throughs
#   person_out_of_zone        person present elsewhere in the room (hard negative)
#   occupied_uncontrolled     soak/ambient only, occupancy unknown -> exploratory
#
# Exit codes: 0 started/finished, 1 usage/config error, 2 capture already running.

set -euo pipefail

SELF="$(readlink -f "${BASH_SOURCE[0]}")"
ROOT="$(dirname "$(dirname "$SELF")")"
PYBIN=""

usage() { sed -n '2,20p' "$SELF" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

# ----------------------------------------------------------------- args
LABEL=""; PLACEMENT="A"; DURATION=300; COUNTDOWN=15; COUNTDOWN_GIVEN=0
ALTERNATE=0; CYCLES=0; GUARD=10
DIST_CM=""; HEIGHT_CM=""; SUBJECT=""; NOTES=""; PORT="/dev/ttyACM0"
OUTDIR="$ROOT/data"; FOREGROUND=0; RESET=1; INNER_DIR=""
MOUNT="taped"; CABLE="pc-end"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --label)        LABEL="${2:?}"; shift 2 ;;
    --placement)    PLACEMENT="${2:?}"; shift 2 ;;
    --duration)     DURATION="${2:?}"; shift 2 ;;
    --countdown)    COUNTDOWN="${2:?}"; COUNTDOWN_GIVEN=1; shift 2 ;;
    --alternate)    ALTERNATE="${2:?}"; shift 2 ;;
    --cycles)       CYCLES="${2:?}"; shift 2 ;;
    --guard)        GUARD="${2:?}"; shift 2 ;;
    --distance-cm)  DIST_CM="${2:?}"; shift 2 ;;
    --height-cm)    HEIGHT_CM="${2:?}"; shift 2 ;;
    --subject)      SUBJECT="${2:?}"; shift 2 ;;
    --notes)        NOTES="${2:?}"; shift 2 ;;
    --node-mount)   MOUNT="${2:?}"; shift 2 ;;
    --cable-break)  CABLE="${2:?}"; shift 2 ;;
    --port)         PORT="${2:?}"; shift 2 ;;
    --outdir)       OUTDIR="${2:?}"; shift 2 ;;
    --foreground)   FOREGROUND=1; shift ;;
    --no-reset)     RESET=0; shift ;;
    --inner)        INNER_DIR="${2:?}"; shift 2 ;;
    -h|--help)      usage 0 ;;
    *) echo "unknown argument: $1" >&2; usage 1 ;;
  esac
done

find_python() {
  local c
  if [[ -n "${IDF_PYTHON_ENV_PATH:-}" && -x "$IDF_PYTHON_ENV_PATH/bin/python" ]]; then
    PYBIN="$IDF_PYTHON_ENV_PATH/bin/python"; return 0
  fi
  for c in "$HOME/.espressif/python_env/idf5.3_py3.11_env/bin/python" \
           "$HOME/.espressif/python_env/"*/bin/python; do
    [[ -x "$c" ]] && { PYBIN="$c"; return 0; }
  done
  if python3 -c 'import serial' 2>/dev/null; then PYBIN="python3"; return 0; fi
  echo "no python with pyserial found (source the IDF env or install pyserial)" >&2
  return 1
}

fw_hash() {
  local d="$HOME/esp/esp-csi"
  if git -C "$d" rev-parse --git-dir >/dev/null 2>&1; then
    local h; h="$(git -C "$d" rev-parse --short HEAD)"
    git -C "$d" diff --quiet && echo "$h" || echo "$h-dirty"
  else
    echo "unknown"
  fi
}

# ----------------------------------------------------------------- inner mode
if [[ -n "$INNER_DIR" ]]; then
  # Hold an exclusive lock for the whole capture. fd 9 stays open until this
  # process exits, so a second capture cannot start on the same host.
  LOCK="${TMPDIR:-/tmp}/esp32_csi_capture.lock"
  exec 9>"$LOCK"
  flock -n 9 || { echo "another capture holds $LOCK" >&2; exit 2; }
  # shellcheck disable=SC1091
  source "$INNER_DIR/capture.env"
  find_python || exit 1
  set +e
  "$PYBIN" "$ROOT/tools/capture_serial.py" \
      --port "$PORT" --baud 921600 \
      --out "$INNER_DIR/csi.csv" --duration "$DURATION" \
      $([[ "$RESET" == "1" ]] || echo "--no-reset")
  rc=$?
  set -e

  # ---- finalise
  {
    echo
    echo "## Capture result"
    echo
    echo '```'
    cat "$INNER_DIR/csi_stats.json" 2>/dev/null || echo "stats missing"
    echo '```'
    echo
    echo "- finished (UTC): $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo "- capture worker exit code: $rc"
  } >> "$INNER_DIR/session.md"

  if [[ -s "$INNER_DIR/csi.csv" ]]; then
    ( cd "$INNER_DIR" && sha256sum csi.csv > manifest.sha256 )
    bssid="$(awk -F, '/^CSI_DATA,/{print $3; exit}' "$INNER_DIR/csi.csv")"
    [[ -n "$bssid" ]] && echo "- AP BSSID observed: $bssid" >> "$INNER_DIR/session.md"
    rows="$(grep -c '^CSI_DATA,' "$INNER_DIR/csi.csv" || true)"
    if [[ "${rows:-0}" -eq 0 ]]; then
      echo "- **INVALID: zero CSI rows captured — do not label this session.**" >> "$INNER_DIR/session.md"
    fi
  else
    echo "- **INVALID: csi.csv is empty — capture never started (wrong port? board off?).**" >> "$INNER_DIR/session.md"
  fi

  echo
  echo "session complete: $INNER_DIR"
  ls -l "$INNER_DIR"
  exit "$rc"
fi

# ----------------------------------------------------------------- outer mode
[[ -n "$LABEL" ]] || { echo "--label is required" >&2; usage 1; }
case "$LABEL" in
  empty_room|person_in_zone_static|person_in_zone_moving|person_out_of_zone|occupied_uncontrolled|alternating) ;;
  *) echo "invalid --label '$LABEL'" >&2; usage 1 ;;
esac
[[ "$DURATION" =~ ^[0-9]+$ ]] || { echo "--duration must be an integer (0 = until stopped)" >&2; exit 1; }
(( DURATION == 0 || DURATION >= 5 )) || { echo "--duration must be 0 or >= 5 s" >&2; exit 1; }

if (( ALTERNATE > 0 )); then
  [[ "$LABEL" == "alternating" ]] || {
    echo "--alternate records both conditions in one file; use --label alternating" >&2; exit 1; }
  [[ "$ALTERNATE" =~ ^[0-9]+$ ]] && (( ALTERNATE >= 20 )) || {
    echo "--alternate must be >= 20 s" >&2; exit 1; }
  [[ "$CYCLES" =~ ^[0-9]+$ ]] && (( CYCLES >= 1 )) || {
    echo "--alternate needs --cycles N (N = empty+person pairs)" >&2; exit 1; }
  [[ "$GUARD" =~ ^[0-9]+$ ]] || { echo "--guard must be an integer" >&2; exit 1; }
  (( 2 * GUARD < ALTERNATE )) || {
    echo "--guard ${GUARD}s leaves no usable data in a ${ALTERNATE}s block (need 2*guard < alternate)" >&2
    exit 1; }
  DURATION=$(( 2 * ALTERNATE * CYCLES ))
  # The measurement starts ~5 s after the port opens (board boot). Pick the
  # countdown so it starts at exactly ONE block length after launch: then the
  # phone timer's block multiples are the transitions, with no mental arithmetic.
  if (( COUNTDOWN_GIVEN == 0 )); then COUNTDOWN=$(( ALTERNATE - 5 )); fi
  (( COUNTDOWN >= 10 )) || COUNTDOWN=10
  # Phone-time offset of measurement start. Not assumed to be ALTERNATE: if the
  # operator overrides --countdown the cue sheet must still be correct.
  OFFSET=$(( COUNTDOWN + 5 ))
elif (( CYCLES > 0 )); then
  echo "--cycles has no effect without --alternate" >&2
fi
[[ -e "$PORT" ]] || { echo "port $PORT not found (board plugged in?)" >&2; exit 1; }
find_python || exit 1

if [[ "$MOUNT" != "taped" ]]; then
  echo "warning: --node-mount '$MOUNT' — the soak baseline was taped;" >&2
  echo "         a loose node is not comparable to placement A." >&2
fi
if [[ "$CABLE" != "pc-end" ]]; then
  echo "warning: --cable-break '$CABLE' — breaking at the board end moves the" >&2
  echo "         antenna near-field and shifts the static channel." >&2
fi

if ! command -v flock >/dev/null 2>&1; then
  echo "flock not found (util-linux); cannot guarantee single-capture safety" >&2
  exit 1
fi
LOCK="${TMPDIR:-/tmp}/esp32_csi_capture.lock"
exec 9>"$LOCK"
if ! flock -n 9; then
  echo "a capture is already running (lock: $LOCK)" >&2
  echo "check it with: pgrep -af 'capture_serial.py'" >&2
  echo "the lock is released automatically when that capture exits — do not delete it," >&2
  echo "two readers on one serial port silently corrupt both files" >&2
  exit 2
fi
# The outer process holds the lock THROUGH the countdown, so a second launch
# cannot pass the check and then collide 85 s later when the worker starts.
# It is released immediately before launch; see below.

avail_kb="$(df -Pk "$OUTDIR" 2>/dev/null | awk 'NR==2{print $4}' || echo 0)"
if [[ -n "${avail_kb:-}" ]] && (( avail_kb < 2097152 )); then
  echo "warning: less than 2 GB free on $OUTDIR" >&2
fi

mkdir -p "$OUTDIR"
STAMP="$(date +%Y%m%d_%H%M)"
DIR="$OUTDIR/${STAMP}_${LABEL}_${PLACEMENT}"
n=2; while [[ -e "$DIR" ]]; do DIR="$OUTDIR/${STAMP}_${LABEL}_${PLACEMENT}_r$n"; n=$((n+1)); done
mkdir -p "$DIR"

cat > "$DIR/capture.env" <<EOF
LABEL="$LABEL"
PLACEMENT="$PLACEMENT"
DURATION="$DURATION"
PORT="$PORT"
RESET="$RESET"
MOUNT="$MOUNT"
CABLE="$CABLE"
COUNTDOWN="$COUNTDOWN"
ALTERNATE="$ALTERNATE"
CYCLES="$CYCLES"
GUARD="$GUARD"
EOF

cat > "$DIR/session.md" <<EOF
# ${DIR##*/}

| Field | Value |
|---|---|
| Started (UTC) | $(date -u '+%Y-%m-%dT%H:%M:%SZ') |
| Label | \`$LABEL\` |
| Placement | \`$PLACEMENT\` |
| Duration requested | $([[ "$DURATION" == "0" ]] && echo "open-ended (until stopped)" || echo "${DURATION} s") |
| Exit countdown | ${COUNTDOWN} s (measurement starts at the first CSI row, ~5 s later) |
| Node → AP distance | ${DIST_CM:-_} cm |
| Node height (floor) | ${HEIGHT_CM:-_} cm |
| Node mount | \`$MOUNT\` |
| USB cable broken at | \`$CABLE\` |
| Subject | ${SUBJECT:-_} |
| Rig | ESP32-S3-DevKitC-1 N16R8, on-module PCB antenna |
| Firmware | esp-csi \`$(fw_hash)\` |
| Console | 921600 baud, CH343 → \`$PORT\` |
| Operator | ${USER}@$(hostname -s) |

**Notes:** ${NOTES:-_}

## Occupancy timeline

<!-- Scripted entry/exit times, or why the label holds for the whole capture. -->
EOF

if (( ALTERNATE > 0 )); then
  printf 'block,condition,t_start_s,t_end_s,guard_s\n' > "$DIR/schedule.csv"
  {
    echo "ALTERNATING SCHEDULE — ${CYCLES} cycles x ${ALTERNATE}s per block (${DURATION}s)"
    echo
    echo "Start the phone timer the instant you press Enter. The measurement begins"
    echo "${COUNTDOWN}s + ~5s boot after that, i.e. at phone time ~${OFFSET}s, so:"
    echo "  - block boundaries are phone readings $((OFFSET+ALTERNATE))s, $((OFFSET+2*ALTERNATE))s, ..."
    echo "  - the first ${GUARD}s and last ${GUARD}s of each block are discarded as transition"
    echo
    printf '%-6s %-20s %s\n' "block" "condition" "phone timer"
    for ((c=1; c<=CYCLES; c++)); do
      eb=$(( (2*c-2)*ALTERNATE )); ee=$(( (2*c-1)*ALTERNATE ))
      pb=$(( (2*c-1)*ALTERNATE )); pe=$(( 2*c*ALTERNATE ))
      printf '%d,%s,%d,%d,%d\n' "$((2*c-1))" empty_room "$eb" "$ee" "$GUARD" >> "$DIR/schedule.csv"
      printf '%d,%s,%d,%d,%d\n' "$((2*c))" person_out_of_zone "$pb" "$pe" "$GUARD" >> "$DIR/schedule.csv"
      if (( c == 1 )); then
        printf '%-6d %-20s %ss: stay out\n' "$((2*c-1))" empty_room "$((eb+OFFSET))"
      else
        printf '%-6d %-20s %ss: leave the room\n' "$((2*c-1))" empty_room "$((eb+OFFSET))"
      fi
      printf '%-6d %-20s %ss: walk in, seated by %ss\n' "$((2*c))" person_out_of_zone \
             "$((pb+OFFSET-12))" "$((pb+OFFSET))"
    done
  } > "$DIR/cues.txt"

  cat >> "$DIR/session.md" <<EOF

## Alternating schedule

One continuous capture, both conditions, so between-block drift is common-mode.
Machine-readable boundaries in \`schedule.csv\` (seconds from the first CSI row);
\`guard_s\` is discarded at each end of every block.

\`\`\`
$(cat "$DIR/cues.txt")
\`\`\`
EOF
fi

echo "session dir : $DIR"
echo "label       : $LABEL"
echo "duration    : ${DURATION}s"
if (( ALTERNATE > 0 )); then
  echo "schedule    : ${CYCLES} x (${ALTERNATE}s empty + ${ALTERNATE}s person), guard ${GUARD}s"
  echo "cue sheet   : $DIR/cues.txt   (print it, or open it on the phone)"
fi
echo

if (( ALTERNATE > 0 )); then
  echo ">>> Start the phone timer NOW, then leave. Measurement begins at phone ~${OFFSET}s."
else
  echo ">>> Leave the room / set the condition now."
fi
if (( COUNTDOWN > 0 )); then
  for ((i=COUNTDOWN; i>0; i--)); do
    printf '\r    recording starts in %2d s ' "$i"
    sleep 1
  done
  printf '\r    RECORDING                              \n'
fi

exec 9>&-   # released; the inner worker re-acquires it for the whole capture
if (( FOREGROUND )) || ! command -v tmux >/dev/null 2>&1; then
  (( FOREGROUND )) || echo "tmux not found; running in foreground" >&2
  exec bash "$SELF" --inner "$DIR"
fi

TMUX_NAME="csi-${STAMP}-${LABEL}"
tmux new-session -d -s "$TMUX_NAME" "bash '$SELF' --inner '$DIR'"
echo "capture running in tmux session: $TMUX_NAME"
echo "  watch : tmux attach -t $TMUX_NAME"
echo "  stop  : tmux kill-session -t $TMUX_NAME   (worker flushes + finalises)"
if [[ "$DURATION" == "0" ]]; then
  echo "  mode  : open-ended — it runs until you stop it."
else
  echo "  or just wait ${DURATION}s; it exits by itself."
fi
