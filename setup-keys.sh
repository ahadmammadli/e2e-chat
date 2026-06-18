#!/usr/bin/env bash

set -euo pipefail

CONF_DIR="$HOME/.config/e2e-chat"
IDENTITY="$CONF_DIR/identity.txt"
RECIPIENTS="$CONF_DIR/recipients.txt"

mkdir -p "$CONF_DIR"

command -v age-keygen >/dev/null 2>&1 || {
  echo "[!] age-keygen not found"
  exit 1
}

if [[ -f "$IDENTITY" ]]; then
  echo "[!] Identity already exists: $IDENTITY"
  echo "[!] Not overwriting it."
  exit 1
fi

age-keygen -o "$IDENTITY"

grep -Eo 'age1[0-9a-z]+' "$IDENTITY" > "$RECIPIENTS"

chmod 600 "$IDENTITY"
chmod 600 "$RECIPIENTS"

echo
echo "[+] Identity created:"
echo "    $IDENTITY"
echo
echo "[+] Your public key:"
cat "$RECIPIENTS"
echo
echo "[*] Share this public key with other users."
echo "[*] Add everyone else's public keys into:"
echo "    $RECIPIENTS"
