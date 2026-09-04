#!/usr/bin/env bash

set -u
LC_ALL=C
export LC_ALL

SIM_BIN="${1:?usage: $0 <path-to-interactive-sim-binary>}"
FIFO="uart_rx.in"
BACKUP="uart_rx.in.regression-backup"

if [ ! -x "$SIM_BIN" ]; then
  echo "[interactive] error: $SIM_BIN not found or not executable (build it first)" >&2
  exit 1
fi

OLD_STTY=""
FORWARDER_PID=""
SIM_PID=""

cleanup() {
  trap - EXIT INT TERM HUP
  if [ -n "$FORWARDER_PID" ]; then
    kill "$FORWARDER_PID" 2>/dev/null
    wait "$FORWARDER_PID" 2>/dev/null
  fi
  if [ -n "$SIM_PID" ] && kill -0 "$SIM_PID" 2>/dev/null; then
    kill "$SIM_PID" 2>/dev/null
    wait "$SIM_PID" 2>/dev/null
  fi
  exec 3>&- 2>/dev/null || true
  if [ -n "$OLD_STTY" ]; then
    stty "$OLD_STTY" 2>/dev/null
  fi
  if [ -p "$FIFO" ]; then
    rm -f "$FIFO"
  fi
  if [ -f "$BACKUP" ]; then
    mv -f "$BACKUP" "$FIFO"
  fi
  echo
  echo "[interactive] session ended, terminal restored, uart_rx.in restored."
}
trap cleanup EXIT INT TERM HUP
if [ -e "$FIFO" ] && [ ! -p "$FIFO" ]; then
  mv -f "$FIFO" "$BACKUP"
fi
[ -p "$FIFO" ] || mkfifo "$FIFO"
exec 3<>"$FIFO"

OLD_STTY=$(stty -g)
stty raw -echo -icrnl -inlcr -isig

echo "[interactive] starting $SIM_BIN ..."
echo "[interactive] terminal is now RAW: xv6 handles backspace/^U/^D itself."
echo "[interactive] ^C is delivered to xv6 as a plain byte (no signal handling"
echo "[interactive]  in this console driver) - it will NOT stop this script."
echo "[interactive] to end the session, either let xv6/the simulator halt on"
echo "[interactive]  its own, or send SIGINT/SIGTERM from another terminal."
echo

stdbuf -o0 -e0 "$SIM_BIN" &
SIM_PID=$!
(
  while IFS= read -r -n1 -d '' byte; do
    printf '%s' "$byte" >&3
  done
) <&0 &
FORWARDER_PID=$!

wait "$SIM_PID"
