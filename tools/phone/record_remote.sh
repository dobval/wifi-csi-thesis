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
#
# Exit codes: 0 ok, 1 usage, 2 cannot reach the PC, 3 remote capture never started.

set -uo pipefail

HOST="${CSI_HOST:-pc}"
REPO="${CSI_REPO:-~/Documents/UNI/BEng_Project/wifi-csi-thesis}"
ALTERNATE=90
CYCLES=20
DIST_CM=260
HEIGHT_CM=88
LEAD=12          # seconds before a person block to start walking in
BOOT=5           # board boot between "RECORDING" and the first CSI row
DRY=0
ALARM=1
NOTES="phone-cued alternating block"

usage() { sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)         HOST="${2:?}"; shift 2 ;;
    --repo)         REPO="${2:?}"; shift 2 ;;
    --alternate)    ALTERNATE="${2:?}"; shift 2 ;;
    --cycles)       CYCLES="${2:?}"; shift 2 ;;
    --distance-cm)  DIST_CM="${2:?}"; shift 2 ;;
    --height-cm)    HEIGHT_CM="${2:?}"; shift 2 ;;
    --lead)         LEAD="${2:?}"; shift 2 ;;
    --boot)         BOOT="${2:?}"; shift 2 ;;
    --notes)        NOTES="${2:?}"; shift 2 ;;
    --dry-run)      DRY=1; shift ;;
    --no-alarm)     ALARM=0; shift ;;
    -h|--help)      usage 0 ;;
    *) echo "unknown argument: $1" >&2; usage 1 ;;
  esac
done

[[ "$ALTERNATE" =~ ^[0-9]+$ ]] && (( ALTERNATE >= 3 )) || { echo "--alternate must be >= 3" >&2; exit 1; }
[[ "$CYCLES" =~ ^[0-9]+$ ]] && (( CYCLES >= 1 )) || { echo "--cycles must be >= 1" >&2; exit 1; }
(( LEAD < ALTERNATE )) || { echo "--lead must be < --alternate" >&2; exit 1; }

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

  # Wait for the PC to finish its countdown. 0.2 s poll, 150 s ceiling.
  found=0
  for _ in $(seq 1 750); do
    if grep -q 'RECORDING' "$LOG" 2>/dev/null; then found=1; break; fi
    if ! kill -0 "$SSH_PID" 2>/dev/null; then break; fi
    sleep 0.2
  done

  if (( ! found )); then
    echo
    echo "the remote capture never reached RECORDING. Remote output:" >&2
    sed 's/^/    /' "$LOG" >&2 | tail -20
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
