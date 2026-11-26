#!/usr/bin/env python3
"""Raw CSI capture worker.

Writes the serial stream to disk **byte for byte** (the CSI rows are never
rewritten, re-encoded or line-ending-normalised) and emits two sidecars:

  <out>.csv        raw stream, verbatim. Read-only after capture.
  <clock.csv>      alignment sidecar, 1 row/s:
                     host_unix_ns, board_local_timestamp_us, csi_rows
  <stats.json>     integrity summary written on exit

The board's `local_timestamp` field is a 32-bit microsecond counter that wraps
every 2**32 us = 71.6 min (verified: 5 wraps in the 2026-11-24 soak). It cannot
be used for absolute time; that is what the clock sidecar is for.

Exit codes: 0 ok, 1 port/config error, 2 already running.
"""

from __future__ import annotations

import argparse
import errno
import json
import os
import signal
import sys
import time

STOP = False


def _sigterm(_signum, _frame):
    global STOP
    STOP = True


def die(msg: str, code: int = 1) -> "None":
    print(f"capture_serial: {msg}", file=sys.stderr)
    raise SystemExit(code)


def main() -> int:
    ap = argparse.ArgumentParser(description="Capture raw ESP32 CSI serial stream.")
    ap.add_argument("--port", default="/dev/ttyACM0")
    ap.add_argument("--baud", type=int, default=921600)
    ap.add_argument("--out", required=True, help="raw output file (.csv)")
    ap.add_argument("--duration", type=float, default=0.0, help="seconds; 0 = until signal")
    ap.add_argument("--no-reset", action="store_true", help="do not pulse EN/RTS on start")
    ap.add_argument("--boot-timeout", type=float, default=30.0,
                    help="abort if no CSI row arrives within this many seconds")
    ap.add_argument("--force", action="store_true", help="overwrite existing output")
    args = ap.parse_args()

    try:
        import serial  # pyserial
    except ImportError:
        die("pyserial not found. Run with the ESP-IDF venv python, e.g.\n"
            "  ~/.espressif/python_env/idf5.3_py3.11_env/bin/python", 1)

    if not os.path.exists(args.port):
        die(f"serial port {args.port} does not exist (board unplugged?)", 1)
    if os.path.exists(args.out) and not args.force:
        die(f"{args.out} already exists; refuse to clobber raw data (pass --force)", 2)

    base = args.out
    if base.endswith(".csv"):
        base = base[:-4]
    clock_path = base + "_clock.csv"
    stats_path = base + "_stats.json"

    signal.signal(signal.SIGTERM, _sigterm)
    signal.signal(signal.SIGINT, _sigterm)
    # tmux killing a session / closing the terminal sends SIGHUP; treat it as a
    # normal stop so the sidecars and stats file are still written.
    if hasattr(signal, "SIGHUP"):
        signal.signal(signal.SIGHUP, _sigterm)

    try:
        ser = serial.Serial(args.port, args.baud, timeout=0.2)
    except serial.SerialException as exc:
        die(f"cannot open {args.port}: {exc}", 1)

    # pyserial asserts DTR/RTS on open. DTR low-drives IO0 on these boards, so a
    # naive open can park the chip in the bootloader. Force a clean normal boot.
    if not args.no_reset:
        ser.dtr = False   # IO0 high -> normal boot
        ser.rts = True    # EN low    -> hold in reset
        time.sleep(0.15)
        ser.rts = False   # release   -> boot
        ser.dtr = False

    t_start = time.time()
    t_start_ns = time.time_ns()
    # The measurement clock starts at the FIRST CSI row, not at port open:
    # opening the port resets the board, which costs ~5 s of boot banner.
    measure_from = None
    first_csi_ns = None
    resynced = False

    total_lines = 0
    csi_rows = 0
    malformed = 0
    non_csi = 0
    non_csi_samples: list[str] = []
    first_seq = last_seq = None
    channels: dict[str, int] = {}
    board_ts = ""
    max_gap_ns = 0
    last_line_ns = t_start_ns
    last_clock = 0.0
    bytes_written = 0

    buf = b""
    try:
        with open(args.out, "wb") as fout, open(clock_path, "w", encoding="utf-8") as fclock:
            fclock.write("host_unix_ns,board_local_timestamp_us,csi_rows\n")
            while not STOP:
                now = time.time()
                if measure_from is not None and args.duration and (now - measure_from) >= args.duration:
                    break
                if first_csi_ns is None and args.boot_timeout and (now - t_start) > args.boot_timeout:
                    print(f"capture_serial: no CSI row within {args.boot_timeout:.0f} s "
                          f"(board not booting? wrong port? check Wi-Fi credentials)",
                          file=sys.stderr)
                    break
                try:
                    chunk = ser.read(65536)
                except serial.SerialException as exc:
                    print(f"capture_serial: serial read failed: {exc}", file=sys.stderr)
                    break
                if not chunk:
                    continue

                # A capture opened mid-stream can start inside a half-written
                # line (verified: a stale CSI row truncated by the next reset).
                # Drop everything up to the first newline so the file starts on
                # a line boundary.
                if not resynced:
                    i = chunk.find(b"\n")
                    if i < 0:
                        continue
                    chunk = chunk[i + 1:]
                    resynced = True
                    if not chunk:
                        continue

                fout.write(chunk)          # verbatim; never transformed
                bytes_written += len(chunk)

                lines = (buf + chunk).split(b"\n")
                buf = lines.pop()
                for raw in lines:
                    total_lines += 1
                    if not raw.startswith(b"CSI_DATA,"):
                        non_csi += 1
                        if len(non_csi_samples) < 20:
                            s = raw.decode("utf-8", "replace").strip()
                            if s:
                                non_csi_samples.append(s[:200])
                        continue
                    csi_rows += 1
                    if first_csi_ns is None:
                        first_csi_ns = time.time_ns()
                        measure_from = first_csi_ns / 1e9
                    body = raw[:-1] if raw.endswith(b"\r") else raw
                    if not body.endswith(b']"'):
                        malformed += 1
                    parts = raw.split(b",", 19)
                    if len(parts) >= 19:
                        if first_seq is None:
                            first_seq = parts[1].decode("ascii", "replace")
                        last_seq = parts[1].decode("ascii", "replace")
                        ch = parts[16].decode("ascii", "replace")
                        channels[ch] = channels.get(ch, 0) + 1
                        board_ts = parts[18].decode("ascii", "replace").strip()
                    ts = time.time_ns()
                    gap = ts - last_line_ns
                    if gap > max_gap_ns:
                        max_gap_ns = gap
                    last_line_ns = ts

                now = time.time()
                if now - last_clock >= 1.0:
                    fclock.write(f"{time.time_ns()},{board_ts},{csi_rows}\n")
                    fclock.flush()
                    last_clock = now
    except Exception as exc:                      # never lose the sidecars
        print(f"capture_serial: unexpected error: {exc}", file=sys.stderr)
    # The port is closed AFTER the sidecars are written. ser.close() has been
    # observed to block indefinitely in the kernel (wchan tty_wait_until_sent)
    # when a capture is stopped mid-stream, and losing csi_stats.json to a hung
    # close makes the session look like it never ran.
    elapsed = time.time() - t_start
    span = ((time.time_ns() - first_csi_ns) / 1e9) if first_csi_ns else None
    stats = {
        "port": args.port,
        "baud": args.baud,
        "out": os.path.abspath(args.out),
        "started_unix_ns": t_start_ns,
        "stopped_unix_ns": time.time_ns(),
        "elapsed_s": round(elapsed, 3),
        "boot_wait_s": round((first_csi_ns - t_start_ns) / 1e9, 3) if first_csi_ns else None,
        "first_csi_unix_ns": first_csi_ns,
        "csi_span_s": round(span, 3) if span else None,
        "bytes": bytes_written,
        "total_lines": total_lines,
        "csi_rows": csi_rows,
        "rows_per_s": round(csi_rows / span, 3) if span else None,
        "malformed_csi_rows": malformed,
        "trailing_partial_line": bool(buf),
        "non_csi_lines": non_csi,
        "non_csi_samples": non_csi_samples,
        "first_seq": first_seq,
        "last_seq": last_seq,
        "channels": channels,
        "max_interrow_gap_ms": round(max_gap_ns / 1e6, 2),
        "last_board_local_timestamp_us": board_ts,
    }
    with open(stats_path, "w", encoding="utf-8") as f:
        json.dump(stats, f, indent=2)

    # close() can block in the kernel on a USB-serial device that stopped
    # draining. Run it in a daemon thread so a hung close cannot keep the
    # process (and the capture lock) alive; the sidecars are already on disk.
    import threading
    closer = threading.Thread(target=ser.close, daemon=True)
    closer.start()
    closer.join(2.0)

    print(f"csi_rows={csi_rows} rate={stats['rows_per_s']} Hz "
          f"malformed={malformed} non_csi={non_csi} "
          f"max_gap={stats['max_interrow_gap_ms']} ms")
    return 0


if __name__ == "__main__":
    sys.exit(main())
