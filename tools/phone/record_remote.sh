#!/usr/bin/env bash
# record_remote.sh — cue an alternating CSI capture on the PC, from the phone.
#
# Terminal UI only: no Termux:API, no vibration, no TTS, no torch. The screen is
# the interface and the ASCII bell (BEL) is the alarm, so it works with a plain
# Termux install and nothing else. Keep the phone in your hand and the screen on.
#
# It SSHes the launch command to the PC, waits for the PC's own countdown to
# finish, then drives a full-screen cue display. The schedule is anchored to the
# PC's "RECORDING" line, NOT to the moment SSH was invoked: the measurement starts
# after the PC's countdown AND after the board boots (~5 s), so anchoring on the
# launch would put every block boundary out by that sum.
#
# Setup, once:
#   pkg install openssh
#   ssh-keygen -t ed25519 -N '' -f ~/.ssh/id_ed25519
#   ssh-copy-id you@pc
#
# Usage:
#   ./record_remote.sh --alternate 60 --cycles 5
#   ./record_remote.sh --dry-run --alternate 10 --cycles 1   # no PC, local test
#   ./record_remote.sh --status    # is a capture running on the PC?
#   ./record_remote.sh --stop      # SIGTERM the remote worker (finalises it)
#
# Ctrl-C here stops the phone loop AND stops the PC capture (EXIT trap). A SIGKILL
# from Android cannot be trapped, so keep the screen on and the app in the
# foreground; otherwise the PC capture runs on unguided.
#
# Exit codes: 0 ok, 1 usage, 2 cannot reach the PC, 3 remote never started,
#             4 the PC is already running a capture.

set -uo pipefail
export LC_ALL=C

HOST="${CSI_HOST:-pc}"
REPO="${CSI_REPO:-~/Documents/UNI/BEng_Project/wifi-csi-thesis}"
ALTERNATE=60
CYCLES=5
DIST_CM=260
HEIGHT_CM=88
LEAD=""
LEAD_GIVEN=0
BOOT=5
DRY=0
SILENT=0
MODE=run
NOTES="phone-cued alternating block"
COND_A="empty_room"
COND_B="person_in_zone_static"
BAR_W=42

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
    --condition-a)  COND_A="${2:?}"; shift 2 ;;
    --condition-b)  COND_B="${2:?}"; shift 2 ;;
    --lead)         LEAD="${2:?}"; LEAD_GIVEN=1; shift 2 ;;
    --boot)         BOOT="${2:?}"; shift 2 ;;
    --notes)        NOTES="${2:?}"; shift 2 ;;
    --dry-run)      DRY=1; shift ;;
    --silent)       SILENT=1; shift ;;
    -h|--help)      usage 0 ;;
    *) echo "unknown argument: $1" >&2; usage 1 ;;
  esac
done

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
  LEAD=$(( ALTERNATE / 3 )); (( LEAD > 12 )) && LEAD=12; (( LEAD < 1 )) && LEAD=1
fi

N=$(( 2 * CYCLES ))
NOTE_ALT=$(( 2 * ALTERNATE * CYCLES ))
LOG="${TMPDIR:-/tmp}/csi_remote_$$.log"
HLOG="${HOME}/csi_cue.log"

# ------------------------------------------------------------------ helpers
have() { command -v "$1" >/dev/null 2>&1; }
log()  { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$HLOG"; }

# Clock without forking: Android kills apps that spawn thousands of children.
now_us() {
  if [[ -n ${EPOCHREALTIME:-} ]]; then
    local t=$EPOCHREALTIME frac
    frac=${t#*.}
    while (( ${#frac} < 6 )); do frac+="0"; done
    REPLY=$(( ${t%.*} * 1000000 + 10#${frac} ))
  else
    REPLY=$(date +%s%6N)
  fi
}

cond_text() {
  case "$1" in
    empty_room)            echo "out of the room, door closed" ;;
    person_in_zone_static) echo "stand at P1, on the AP-node line" ;;
    person_in_zone_moving) echo "walk slowly along the node-AP line" ;;
    person_out_of_zone)    echo "sit on the sofa at P3" ;;
    *)                     echo "follow condition $1" ;;
  esac
}

bell() { (( SILENT )) || printf '\a\a\a'; }

bar() {
  local n=$(( $1 * BAR_W / 100 )) a b
  (( n > BAR_W )) && n=$BAR_W
  (( n < 0 )) && n=0
  printf -v a '%*s' "$n" '';            a=${a// /#}
  printf -v b '%*s' $(( BAR_W - n )) ''; b=${b// /-}
  BAR="$a$b"
}

# Full-screen redraw from globals: PHASE, k, LEFT_S, COND[], TXT[]
render() {
  local left=$LEFT_S pct
  (( left < 0 )) && left=0
  case "$PHASE" in
    move) pct=100 ;;
    hold) pct=$(( (ALTERNATE - left) * 100 / ALTERNATE )) ;;
    *)    pct=0 ;;
  esac
  bar "$pct"
  printf '\033[H\033[2J'
  printf ' alternating CSI capture          block %2d / %d\n' "$k" "$N"
  printf ' %s\n\n' "--------------------------------------------------"
  if [[ "$PHASE" == move ]]; then
    printf '   MOVE NOW  ->  %s\n\n' "${COND[$k]}"
    printf '   %s\n\n' "${TXT[$k]}"
    printf '   be there in %d s\n' "$left"
  else
    printf '   %s\n\n' "${COND[$k]}"
    printf '   %s\n\n' "${TXT[$k]}"
    printf '   %d s left in this block\n' "$left"
  fi
  printf '\n [%s]\n' "$BAR"
  if (( k < N )); then
    printf '\n next: %s\n' "${COND[$(( k + 1 ))]}"
  else
    printf '\n next: end of capture\n'
  fi
}

wait_until_us() {
  local target=$1 rem
  while :; do
    now_us
    rem=$(( target - REPLY ))
    (( rem <= 0 )) && { LEFT_S=0; render; return 0; }
    LEFT_S=$(( (rem + 999999) / 1000000 ))
    render
    sleep 1
  done
}

# ------------------------------------------------------------------ preflight
if (( ! DRY )); then
  have ssh || { echo "ssh not found: pkg install openssh" >&2; exit 1; }
  if ! ssh -o BatchMode=yes -o ConnectTimeout=8 "$HOST" true 2>/dev/null; then
    echo "cannot reach '$HOST' over ssh without a password prompt." >&2
    echo "check ~/.ssh/config on the phone and that ssh-copy-id has been done." >&2
    exit 2
  fi
fi

sshq() { ssh -o BatchMode=yes -o ConnectTimeout=8 "$HOST" "$@"; }

CAPTURE_LIVE=0
on_exit() {
  local rc=$?
  if (( CAPTURE_LIVE )); then
    printf '\033[H\033[2J'
    echo "cue loop ended early - stopping the PC capture so it is not orphaned"
    log "ended early rc=$rc; stopping remote capture"
    sshq "pkill -TERM -f 'capture_serial\.py'" >/dev/null 2>&1 || true
  fi
  log "exit rc=$rc"
}
trap on_exit EXIT

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
    echo "  worker still alive - probably stuck in close(). On the PC:" >&2
    echo "    pgrep -af capture_serial.py    # then: kill -9 <pid>" >&2
    exit 1
  fi
  echo "  worker gone; session finalised, lock released."
  exit 0
fi

# ------------------------------------------------------------------ launch
if [[ "$REPO" == "~/"* ]]; then
  remote="cd \"\$HOME\"/$(printf %q "${REPO#\~/}") && ./tools/record_session.sh"
elif [[ "$REPO" == "~" ]]; then
  remote="cd \"\$HOME\" && ./tools/record_session.sh"
else
  remote="cd $(printf %q "$REPO") && ./tools/record_session.sh"
fi
remote+=" --label alternating --alternate $ALTERNATE --cycles $CYCLES"
remote+=" --condition-a $COND_A --condition-b $COND_B"
remote+=" --distance-cm $DIST_CM --height-cm $HEIGHT_CM"
remote+=" --notes $(printf %q "$NOTES")"

printf '\033[H\033[2J'
printf ' alternating capture\n'
printf ' %d x (%ds %s + %ds %s) = %ds\n\n' \
       "$CYCLES" "$ALTERNATE" "$COND_A" "$ALTERNATE" "$COND_B" "$NOTE_ALT"

if (( DRY )); then
  echo " DRY RUN: no PC. Simulating a 4 s launch."
  : > "$LOG"
  now_us; T0_US=$(( REPLY + 4000000 ))
else
  echo " launching on the PC..."
  log "launch alt=$ALTERNATE cycles=$CYCLES host=$HOST"
  ssh -o BatchMode=yes -o ConnectTimeout=8 "$HOST" "$remote" </dev/null >"$LOG" 2>&1 &
  SSH_PID=$!

  found=0; locked=0
  now_us; t_wait_us=$REPLY
  for ((_i = 0; _i < 200; _i++)); do
    _log=""
    [[ -r "$LOG" ]] && _log=$(<"$LOG")
    if [[ $_log == *RECORDING* ]]; then found=1; break; fi
    if [[ $_log == *"already running"* ]]; then locked=1; break; fi
    if ! kill -0 "$SSH_PID" 2>/dev/null; then break; fi
    _last=${_log##*$'\r'}
    now_us
    printf '\r  %3ds  %-52s' "$(( (REPLY - t_wait_us) / 1000000 ))" "${_last:0:52}"
    sleep 1
  done
  printf '\r%70s\r' ''

  if (( locked )); then
    echo "The PC is already running a capture, so this launch was refused." >&2
    echo "  check: bash $0 --status" >&2
    echo "  stop : bash $0 --stop" >&2
    exit 4
  fi
  if (( ! found )); then
    echo "the remote capture never reached RECORDING. Remote output:" >&2
    sed 's/^/    /' "$LOG" | tail -20 >&2
    exit 3
  fi

  now_us; T0_US=$(( REPLY + BOOT * 1000000 ))
  CAPTURE_LIVE=1
  log "measurement anchor set"
fi

# ------------------------------------------------------------------ schedule
declare -a COND TXT
for ((i = 1; i <= N; i++)); do
  if (( i % 2 == 1 )); then COND[$i]=$COND_A; TXT[$i]=$(cond_text "$COND_A")
  else                        COND[$i]=$COND_B; TXT[$i]=$(cond_text "$COND_B"); fi
done

k=1; PHASE=hold; LEFT_S=$ALTERNATE
render
bell

# Event list of (absolute second, phase, block). The "move" cue for block m fires
# LEAD seconds before block m starts, while block m-1 is still the current block,
# so the displayed block number always matches the clock.
ev_t=(); ev_ph=(); ev_k=()
for ((m = 1; m <= N; m++)); do
  bs=$(( (m - 1) * ALTERNATE ))
  if (( m > 1 )); then
    ev_t+=($(( bs - LEAD ))); ev_ph+=("move"); ev_k+=($m)
  fi
  ev_t+=($bs); ev_ph+=("hold"); ev_k+=($m)
done

for ((i = 0; i < ${#ev_t[@]}; i++)); do
  t=${ev_t[$i]}
  if (( t > 0 )); then
    wait_until_us $(( T0_US + t * 1000000 ))
  fi
  PHASE=${ev_ph[$i]}
  k=${ev_k[$i]}
  LEFT_S=$ALTERNATE
  if [[ "$PHASE" == move ]]; then bell; fi
  render
done

# the last block runs from its start to the end of the schedule
PHASE=hold; k=$N
wait_until_us $(( T0_US + NOTE_ALT * 1000000 ))

CAPTURE_LIVE=0
k=$N; PHASE=hold; LEFT_S=0; render
printf '\033[H\033[2J'
printf '\n DONE - capture finished, you can go back\n\n'
bell

if (( ! DRY )); then
  rm -f "$LOG"
  echo " remote session folder:"
  sshq "ls -dt data/*alternating*/ | head -1" | sed 's/^/   /'
  echo
  echo " analyse on the PC:"
  echo "   python3 tools/probe_alt.py <that folder>"
fi
