#!/usr/bin/env bash

set -euo pipefail

STATE_DIR="/tmp/e2e-chat"
LOG="$STATE_DIR/chat.log"

# Ask for port - no default
read -rp "Enter port to listen on: " PORT
PORT="$(printf '%s' "$PORT" | tr -d '[:space:]')"

while ! [[ "$PORT" =~ ^[0-9]+$ ]] || (( PORT < 1 || PORT > 65535 )); do
  echo "[!] Port must be a number between 1 and 65535."
  read -rp "Enter port to listen on: " PORT
  PORT="$(printf '%s' "$PORT" | tr -d '[:space:]')"
done

mkdir -p "$STATE_DIR"
touch "$LOG"
chmod 600 "$LOG"

handler() {
  # Send new log lines to this client
  tail -n 0 -F "$LOG" &
  TAIL_PID=$!

  # Append every received line into the log
  exec 200>>"$LOG"

  while IFS= read -r line; do
    flock -x 200
    printf '%s\n' "$line" >&200
    flock -u 200
  done

  kill "$TAIL_PID" 2>/dev/null || true
}

export -f handler
export LOG STATE_DIR

echo "[relay] Listening on port $PORT..."
echo "[relay] Relay sees ciphertext only."

exec socat TCP-LISTEN:$PORT,reuseaddr,fork EXEC:"bash -lc handler"
