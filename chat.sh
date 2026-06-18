#!/usr/bin/env bash

clear
set -euo pipefail

CONF_DIR="$HOME/.config/e2e-chat"
IDENTITY="$CONF_DIR/identity.txt"
RECIPIENTS="$CONF_DIR/recipients.txt"

BANNER_TEXT="CIA greets you lol :)"
JOIN_JOKE='[*] CIA noticed %s joined the chat 👁️'
LEAVE_JOKE='[*] CIA kicked %s out of the chat. Watch your six 😤'
HERE_JOKE='[*] CIA confirms %s is already lurking here 🕵️'
LOCAL_LEAVE_JOKE='[*] CIA escorted you out, %s. Bye 👋'
SEP='-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_'

# ---------- automatic paths ----------
mkdir -p "$CONF_DIR"

# ---------- checks ----------
command -v age >/dev/null 2>&1 || { echo "[!] age not found"; exit 1; }
command -v socat >/dev/null 2>&1 || { echo "[!] socat not found"; exit 1; }

[[ -f "$IDENTITY" ]] || { echo "[!] Missing identity: $IDENTITY"; exit 1; }
[[ -f "$RECIPIENTS" ]] || { echo "[!] Missing recipients: $RECIPIENTS"; exit 1; }

# ---------- input validation ----------
is_valid_host() {
  local host="$1"

  # IPv4
  if [[ "$host" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    local IFS=.
    local parts=($host)
    local p
    for p in "${parts[@]}"; do
      (( p >= 0 && p <= 255 )) || return 1
    done
    return 0
  fi

  # hostname / simple domain / localhost
  [[ "$host" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]$|^localhost$ ]]
}

is_valid_port() {
  local port="$1"
  [[ "$port" =~ ^[0-9]+$ ]] || return 1
  (( port >= 1 && port <= 65535 ))
}

is_valid_username() {
  local name="$1"
  [[ ${#name} -ge 1 && ${#name} -le 33 ]]
}

# ---------- prompt helpers ----------
prompt_host() {
  local value

  while true; do
    read -r -p "Enter server IP/host: " value

    if [[ -z "$value" ]]; then
      continue
    fi

    if is_valid_host "$value"; then
      printf '%s' "$value"
      return 0
    fi

    printf '[!] Invalid host. Use a valid IPv4 address, hostname, or "localhost".\n' >&2
  done
}

prompt_port() {
  local value

  while true; do
    read -r -p "Enter server port: " value

    if [[ -z "$value" ]]; then
      continue
    fi

    if is_valid_port "$value"; then
      printf '%s' "$value"
      return 0
    fi

    if [[ ! "$value" =~ ^[0-9]+$ ]]; then
      printf '[!] Invalid port. Numbers only.\n' >&2
    else
      printf '[!] Invalid port. Enter a number between 1 and 65535.\n' >&2
    fi
  done
}

prompt_username() {
  local value

  while true; do
    read -r -p "Enter your username: " value

    if [[ -z "$value" ]]; then
      continue
    fi

    if ! is_valid_username "$value"; then
      printf '[!] Invalid username. Maximum length is 33 characters.\n' >&2
      continue
    fi

    printf '%s' "$value"
    return 0
  done
}

# ---------- helpers ----------
b64dec() {
  if base64 -d </dev/null >/dev/null 2>&1; then
    base64 -d
  else
    base64 -D
  fi
}

encrypt_line() {
  printf '%s' "$1" | age -R "$RECIPIENTS" 2>/dev/null | base64 | tr -d '\n'
}

decrypt_line() {
  printf '%s' "$1" | b64dec 2>/dev/null | age --decrypt -i "$IDENTITY" 2>/dev/null
}

timestamp() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }
trim() { printf '%s' "$1" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'; }

send_cipher_line() { printf '%s\n' "$1" >&3; }

send_system_main() {
  local action="$1"
  local payload="__SYS__|${action}|${NAME}"
  local enc
  enc="$(encrypt_line "$payload" || true)"
  [[ -n "${enc:-}" ]] && send_cipher_line "$enc"
}

send_system_direct() {
  local action="$1"
  local payload="__SYS__|${action}|${NAME}"
  local enc
  enc="$(encrypt_line "$payload" || true)"
  [[ -z "${enc:-}" ]] && return 0
  printf '%s\n' "$enc" | socat - "TCP:$SERVER_HOST:$SERVER_PORT" >/dev/null 2>&1 || true
}

# ---------- UI helpers ----------
clear_prompt_area() {
  printf '\r\033[K'
  printf '\033[1A\033[K'
  printf '\033[1A\033[K'
  printf '\033[1A\033[K'
}

print_message_local() {
  local text="$1"
  clear_prompt_area
  printf '%s\n\n%s\n\n%s > ' "$text" "$SEP" "$NAME"
}

print_message_remote() {
  local text="$1"
  clear_prompt_area
  printf '\n%s\n\n%s\n\n%s > ' "$text" "$SEP" "$NAME"
}

redraw_prompt_only() {
  clear_prompt_area
  printf '%s\n\n%s > ' "$SEP" "$NAME"
}

# ---------- startup UI ----------
clear
if command -v figlet >/dev/null 2>&1; then
  figlet "$BANNER_TEXT"
else
  echo "$BANNER_TEXT"
fi
echo

SERVER_HOST="$(prompt_host)"
SERVER_PORT="$(prompt_port)"
NAME="$(prompt_username)"

echo
echo "[*] Connecting to relay $SERVER_HOST:$SERVER_PORT ..."
echo
echo "[*] Type messages below. Ctrl+C to exit."
echo
printf "$JOIN_JOKE\n\n" "$NAME"

# ---------- IPC ----------
IN_FIFO="/tmp/e2e-chat.in.$$"
OUT_FIFO="/tmp/e2e-chat.out.$$"
mkfifo "$IN_FIFO" "$OUT_FIFO"

cleanup() {
  [[ -n "${RECV_PID:-}" ]] && kill "$RECV_PID" 2>/dev/null || true
  [[ -n "${SOCAT_PID:-}" ]] && kill "$SOCAT_PID" 2>/dev/null || true
  exec 3>&- 2>/dev/null || true
  exec 4<&- 2>/dev/null || true
  rm -f "$IN_FIFO" "$OUT_FIFO"
}

on_ctrl_c() {
  echo
  trap - INT

  send_system_main "LEAVE" || true
  send_system_direct "LEAVE" || true

  printf "$LOCAL_LEAVE_JOKE\n" "$NAME"
  cleanup
  exit 0
}
trap on_ctrl_c INT
trap cleanup EXIT

socat - "TCP:$SERVER_HOST:$SERVER_PORT" <"$OUT_FIFO" >"$IN_FIFO" 2>/dev/null &
SOCAT_PID=$!

exec 3>"$OUT_FIFO"
exec 4<"$IN_FIFO"

send_system_main "JOIN" || true

# ---------- receiver ----------
{
  while IFS= read -r line <&4; do
    plaintext="$(decrypt_line "$line" || true)"
    [[ -z "${plaintext:-}" ]] && continue

    IFS='|' read -r a b c <<<"$plaintext" || true

    if [[ "$a" == "__SYS__" ]]; then
      action="$(trim "${b:-}")"
      user="$(trim "${c:-}")"
      [[ -z "$action" || -z "$user" ]] && continue
      [[ "$user" == "$NAME" ]] && continue

      if [[ "$action" == "JOIN" ]]; then
        print_message_remote "$(printf "$JOIN_JOKE" "$user")"

        payload="__SYS__|HERE|${NAME}"
        enc="$(encrypt_line "$payload" || true)"
        [[ -n "${enc:-}" ]] && send_cipher_line "$enc"

      elif [[ "$action" == "LEAVE" ]]; then
        print_message_remote "$(printf "$LEAVE_JOKE" "$user")"

      elif [[ "$action" == "HERE" ]]; then
        print_message_remote "$(printf "$HERE_JOKE" "$user")"
      fi

      continue
    fi

    who="$(trim "${b:-}")"
    msg="${c:-}"
    [[ -z "$who" ]] && continue
    [[ "$who" == "$NAME" ]] && continue

    print_message_remote "$who > $msg"
  done
} &
RECV_PID=$!

# ---------- sender ----------
printf '%s\n\n%s > ' "$SEP" "$NAME"

while true; do
  IFS= read -r msg || break
  raw_msg="$msg"

  check_msg="$(trim "$raw_msg")"
  if [[ -z "$check_msg" ]]; then
    redraw_prompt_only
    continue
  fi

  ts="$(timestamp)"
  payload="${ts}|${NAME}|${raw_msg}"
  enc="$(encrypt_line "$payload" || true)"

  if [[ -n "${enc:-}" ]]; then
    print_message_local "$NAME > $raw_msg"
    send_cipher_line "$enc"
  fi
done