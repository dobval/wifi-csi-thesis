#!/usr/bin/env bash
# record_remote.sh — cue an alternating CSI capture on the PC, from the phone.
#
# Runs in Termux (Android). It SSHes the launch command to the PC, waits for the
# PC's own countdown to finish, then cues the block schedule with sound,
# vibration, spoken instructions and a torch flash.
#
# Why the cues are anchored to the PC: the measurement does not start when SSH is
# invoked. It starts after the PC's countdown AND after the board boots (~5 s).
# So this script tails the remote log for the "RECORDING" line, then anchors the
# schedule at that instant + boot. SSH latency therefore cancels instead of
# shifting every block boundary.
#
# Setup, once:
#   pkg install openssh termux-api
#   ssh-keygen -t ed25519 -N '' -f ~/.ssh/id_ed25519
#   ssh-copy-id you@pc
#   termux-wake-lock                 # stop Android freezing the cue loop
#   # install the Termux:API app (F-Droid) for vibration / TTS / torch / toast
#
# Usage:
#   ./record_remote.sh --alternate 90 --cycles 20
#   ./record_remote.sh --dry-run --alternate 10 --cycles 2    # no PC, local test
#   ./record_remote.sh --status          # is a capture running on the PC?
#   ./record_remote.sh --stop            # SIGTERM the remote worker (finalises it)
#
# Ctrl-C here stops only the phone's cue loop. The capture on the PC keeps
# running; use --status to check and --stop to end it. Do NOT delete the lock
# file: two readers on one serial port silently corrupt both recordings.
#
# Exit codes: 0 ok, 1 usage, 2 cannot reach the PC, 3 remote capture never
# started, 4 the PC is already running a capture.

set -uo pipefail

HOST="${CSI_HOST:-pc}"
REPO="${CSI_REPO:-~/Documents/UNI/BEng_Project/wifi-csi-thesis}"
ALTERNATE=90
CYCLES=20
DIST_CM=260
HEIGHT_CM=88
LEAD=""          # empty = derived from block length; see validation below
LEAD_GIVEN=0
BOOT=5           # board boot between "RECORDING" and the first CSI row
DRY=0
ALARM=1
MODE=run
NOTES="phone-cued alternating block"

usage() {
  awk 'NR>1 { if ($0 !~ /^#/) exit; sub(/^# ?/, ""); print }' "$0"
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --status)       MODE=status; shift ;;
    --stop)         MODE=stop; shift ;;
    --host)         HOST="${2:?}"; shift 2 ;;
    --repo)         REPO="${2:?}"; shift 2 ;;
    --alternate)    ALTERNATE="${2:?}"; shift 2 ;;
    --cycles)       CYCLES="${2:?}"; shift 2 ;;
    --distance-cm)  DIST_CM="${2:?}"; shift 2 ;;
    --height-cm)    HEIGHT_CM="${2:?}"; shift 2 ;;
    --lead)         LEAD="${2:?}"; LEAD_GIVEN=1; shift 2 ;;
    --boot)         BOOT="${2:?}"; shift 2 ;;
    --notes)        NOTES="${2:?}"; shift 2 ;;
    --dry-run)      DRY=1; shift ;;
    --no-alarm)     ALARM=0; shift ;;
    -h|--help)      usage 0 ;;
    *) echo "unknown argument: $1" >&2; usage 1 ;;
  esac
done

# A real capture must satisfy the PC side too: record_session.sh needs
# --alternate >= 21 so that 2 x guard (10 s default) leaves usable data.
MIN_ALT=3
(( DRY )) || MIN_ALT=21
[[ "$ALTERNATE" =~ ^[0-9]+$ ]] && (( ALTERNATE >= MIN_ALT )) || {
  echo "--alternate must be >= ${MIN_ALT}s$([[ $DRY == 1 ]] || echo ' (PC side needs > 2x guard)')" >&2
  exit 1; }
[[ "$CYCLES" =~ ^[0-9]+$ ]] && (( CYCLES >= 1 )) || { echo "--cycles must be >= 1" >&2; exit 1; }

if (( LEAD_GIVEN )); then
  [[ "$LEAD" =~ ^[0-9]+$ ]] && (( LEAD >= 1 && LEAD < ALTERNATE )) || {
    echo "--lead ${LEAD}s must be at least 1s and less than --alternate ${ALTERNATE}s" >&2
    exit 1; }
else
  # Walk-in warning gives away a third of a short block, capped at 12 s.
  LEAD=$(( ALTERNATE / 3 ))
  (( LEAD > 12 )) && LEAD=12
  (( LEAD < 1 ))  && LEAD=1
fi

NOTE_ALT=$(( 2 * ALTERNATE * CYCLES ))
LOG="${TMPDIR:-/tmp}/csi_remote_$$.log"

# ------------------------------------------------------------------ helpers
have() { command -v "$1" >/dev/null 2>&1; }
now()  { date +%s.%N; }

banner() {
  clear 2>/dev/null || printf '\n'
  printf '%s\n' "────────────────────────────────────────────"
  printf '  %s\n' "$@"
  printf '%s\n' "────────────────────────────────────────────"
}

alarm() {
  # alarm URGENT|SOFT  "text"
  local kind="$1" text="$2"
  (( ALARM )) || return 0
  if have termux-tts-speak; then
    termux-tts-speak -r 0.60 "$text" >/dev/null 2>&1 &
  fi
  if have termux-vibrate; then
    if [[ "$kind" == URGENT ]]; then
      termux-vibrate -f -d 700 >/dev/null 2>&1 &
      ( sleep 0.35; termux-vibrate -f -d 300 >/dev/null 2>&1 ) &
    else
      termux-vibrate -d 200 >/dev/null 2>&1 &
    fi
  fi
  if [[ "$kind" == URGENT ]] && have termux-torch; then
    ( termux-torch on >/dev/null 2>&1; sleep 0.25; termux-torch off >/dev/null 2>&1 ) &
  fi
  if have termux-toast; then
    termux-toast -s "$text" >/dev/null 2>&1 &
  fi
  printf '\a'
}

# wait_until TARGET "label" — 1 Hz countdown to an absolute epoch time
wait_until() {
  local target="$1" label="$2" rem
  while :; do
    rem=$(awk -v t="$target" -v n="$(now)" 'BEGIN{ printf "%.1f", t-n }')
    awk -v r="$rem" 'BEGIN{ exit !(r <= 0.05) }' && return 0
    printf '\r  %-34s in %6.0fs ' "$label" "$rem"
    sleep 0.25
  done
}

# ------------------------------------------------------------------ preflight
if (( ! DRY )); then
  have ssh || { echo "ssh not found: pkg install openssh" >&2; exit 1; }
  if ! have termux-wake-lock; then
    echo "warning: termux-wake-lock not found; Android may freeze the cue loop" >&2
  else
    termux-wake-lock >/dev/null 2>&1 || true
  fi
  if ! ssh -o BatchMode=yes -o ConnectTimeout=8 "$HOST" true 2>/dev/null; then
    echo "cannot reach '$HOST' over ssh without a password prompt." >&2
    echo "check ~/.ssh/config on the phone and that ssh-copy-id has been done." >&2
    exit 2
  fi
fi

sshq() { ssh -o BatchMode=yes -o ConnectTimeout=8 "$HOST" "$@"; }

if [[ "$MODE" == status ]]; then
  echo "capture processes on $HOST:"
  sshq "pgrep -af 'capture_serial\.py' || echo '(none)'" | sed 's/^/  /'
  echo "tmux sessions:"
  sshq "tmux ls 2>/dev/null | grep csi- || echo '(none)'" | sed 's/^/  /'
  printf 'capture lock: '
  sshq "flock -n /tmp/esp32_csi_capture.lock true 2>/dev/null && echo free || echo HELD"
  exit 0
fi

if [[ "$MODE" == stop ]]; then
  echo "SIGTERM -> capture worker on $HOST"
  sshq "pkill -TERM -f 'capture_serial\.py' && echo '  signal sent' || echo '  no worker found'"
  sleep 3
  if sshq "pgrep -f 'capture_serial\.py' >/dev/null 2>&1"; then
    echo "  worker still alive — probably stuck in close(). On the PC:" >&2
    echo "    pgrep -af capture_serial.py    # then: kill -9 <pid>" >&2
    exit 1
  fi
  echo "  worker gone; session finalised, lock released."
  exit 0
fi

# Build the remote command. A leading "~/" must stay expandable by the REMOTE
# shell, so it is emitted as "$HOME"/<rest> rather than percent-quoted.
if [[ "$REPO" == "~/"* ]]; then
  remote="cd \"\$HOME\"/$(printf %q "${REPO#\~/}") && ./tools/record_session.sh"
elif [[ "$REPO" == "~" ]]; then
  remote="cd \"\$HOME\" && ./tools/record_session.sh"
else
  remote="cd $(printf %q "$REPO") && ./tools/record_session.sh"
fi
remote+=" --label alternating --alternate $ALTERNATE --cycles $CYCLES"
remote+=" --distance-cm $DIST_CM --height-cm $HEIGHT_CM"
remote+=" --notes $(printf %q "$NOTES")"

banner "Alternating capture" \
       "${CYCLES} x (${ALTERNATE}s out + ${ALTERNATE}s in)  =  ${NOTE_ALT}s" \
       "host: ${HOST}"

if (( DRY )); then
  echo
  echo "  DRY RUN: no PC. Simulating a 4 s launch, then the schedule."
  echo "  remote command would be:"
  echo "    ssh $HOST '$remote'"
  : > "$LOG"
  T0=$(awk -v n="$(now)" 'BEGIN{ printf "%.3f", n+4 }')
else
  echo
  echo "  launching on the PC..."
  ssh -o BatchMode=yes -o ConnectTimeout=8 "$HOST" "$remote" >"$LOG" 2>&1 &
  SSH_PID=$!

  # Wait for the PC's countdown. The PC is deliberately silent for countdown +
  # boot (~90 s), so echo its own progress line back or this looks like a hang.
  trap 'printf "\n"; echo "phone cue loop stopped — the PC capture is STILL RUNNING"; echo "  check: bash $0 --status"; echo "  stop : bash $0 --stop"; exit 130' INT
  found=0; locked=0
  t_wait=$(now)
  for _ in $(seq 1 600); do
    if grep -q 'RECORDING' "$LOG" 2>/dev/null; then found=1; break; fi
    if grep -q 'already running' "$LOG" 2>/dev/null; then locked=1; break; fi
    if ! kill -0 "$SSH_PID" 2>/dev/null; then break; fi
    tail_msg=$(tr '\r' '\n' < "$LOG" 2>/dev/null | grep -v '^[[:space:]]*$' | tail -1 | cut -c1-52)
    el=$(awk -v n="$(now)" -v s="$t_wait" 'BEGIN{printf "%d", n-s}')
    printf '\r  %3ss  %-52s' "$el" "${tail_msg:-contacting the PC}"
    sleep 0.25
  done
  printf '\r%70s\r' ''

  if (( locked )); then
    echo "The PC is already running a capture, so this launch was refused." >&2
    echo "Ctrl-C on the phone does NOT stop a capture on the PC." >&2
    echo "  check: bash $0 --status" >&2
    echo "  stop : bash $0 --stop" >&2
    exit 4
  fi

  if (( ! found )); then
    echo "the remote capture never reached RECORDING. Remote output:" >&2
    sed 's/^/    /' "$LOG" | tail -20 >&2
    exit 3
  fi

  # Anchor: the PC prints RECORDING just before opening the port; the first CSI
  # row follows after the board boots.
  T0=$(awk -v n="$(now)" -v b="$BOOT" 'BEGIN{ printf "%.3f", n+b }')
  echo
  echo "  PC is recording. First CSI row in ~${BOOT}s."
fi

# ------------------------------------------------------------------ schedule
if (( ! DRY )); then
  alarm URGENT "Measurement starting. Stay out of the room."
fi
banner "MEASUREMENT STARTED" "stay out of the room"
printf '  (first block is EMPTY — you should already be outside)\n\n'

for ((k = 1; k <= 2 * CYCLES; k++)); do
  bstart=$(( (k - 1) * ALTERNATE ))
  if (( k % 2 == 0 )); then
    # person block: pre-cue to walk, then confirm seated
    wait_until "$(awk -v t="$T0" -v o="$bstart" -v l="$LEAD" 'BEGIN{printf "%.3f", t+o-l}')" \
               "block $k walk in"
    alarm URGENT "Walk in now. Be seated."
    banner "WALK IN NOW" "block $k of $((2*CYCLES)) — be seated"
    wait_until "$(awk -v t="$T0" -v o="$bstart" 'BEGIN{printf "%.3f", t+o}')" \
               "block $k seated"
    alarm SOFT "Seated. Hold still."
    banner "HOLD STILL" "block $k of $((2*CYCLES)) — seated"
  else
    wait_until "$(awk -v t="$T0" -v o="$bstart" 'BEGIN{printf "%.3f", t+o}')" \
               "block $k leave"
    if (( k == 1 )); then
      alarm SOFT "Stay outside."
      banner "STAY OUTSIDE" "block 1 of $((2*CYCLES)) — empty"
    else
      alarm URGENT "Leave the room now."
      banner "LEAVE THE ROOM" "block $k of $((2*CYCLES)) — empty"
    fi
  fi
done

wait_until "$(awk -v t="$T0" -v o="$NOTE_ALT" 'BEGIN{printf "%.3f", t+o}')" "capture ends"
alarm URGENT "Capture complete. You can return."
banner "DONE" "capture finished — you can go back"

if (( ! DRY )); then
  rm -f "$LOG"
  echo
  echo "  remote session folder:"
  ssh -o BatchMode=yes -o ConnectTimeout=8 "$HOST" \
      "cd \"\$HOME\"/$(printf %q "${REPO#\~/}") && ls -dt data/*alternating*/ | head -1" 2>/dev/null \
      | sed 's/^/    /'
  echo
  echo "  analyse on the PC with:"
  echo "    python3 tools/probe_alt.py <that folder>"
fi
