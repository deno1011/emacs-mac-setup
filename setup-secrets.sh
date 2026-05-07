#!/bin/bash
set -e

CONFIG_FILE="$HOME/setup-emacs-mac.conf"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "ERROR: $CONFIG_FILE not found. Run bootstrap.sh first."
  exit 1
fi
source "$CONFIG_FILE"

EMACS_SECRETS="$HOME/.emacs.d/secrets.el"

if [ -z "$GH_USER" ]; then
  echo "ERROR: GH_USER not set — Bitwarden not configured in local mode."
  exit 1
fi

if ! command -v bw &>/dev/null; then
  echo "ERROR: Bitwarden CLI not installed. Run ~/setup-bitwarden.sh first."
  exit 1
fi

# --- Unlock ---
BW_MASTER=$(security find-generic-password -a "$BW_KEYCHAIN_ACCOUNT" -s "$BW_KEYCHAIN_SERVICE" -w 2>/dev/null) || true
if [ -z "$BW_MASTER" ]; then
  printf "==> Bitwarden master password: "
  read -rs BW_MASTER
  echo ""
fi

export _BW_MASTER="$BW_MASTER"
BW_SESSION=$(bw unlock --passwordenv _BW_MASTER --raw 2>/dev/null) || true
unset _BW_MASTER

if [ -z "$BW_SESSION" ]; then
  echo "ERROR: Bitwarden unlock failed. Remove keychain entry and retry:"
  echo "  security delete-generic-password -a \"$BW_KEYCHAIN_ACCOUNT\" -s \"$BW_KEYCHAIN_SERVICE\""
  exit 1
fi
export BW_SESSION
bw sync --session "$BW_SESSION" &>/dev/null || true

# --- Fetch Anthropic key ---
echo "==> Fetching Anthropic API key from Bitwarden (item: $BW_ANTHROPIC_ITEM, field: $BW_FIELD)..."
ANTHROPIC_API_KEY=$(bw get item "$BW_ANTHROPIC_ITEM" --session "$BW_SESSION" 2>/dev/null \
  | python3 -c "
import sys, json
d = json.load(sys.stdin)
fields = d.get('fields', [])
match = [f['value'] for f in fields if f['name'] == '$BW_FIELD']
print(match[0].strip() if match else '')
") || true

if [ -z "$ANTHROPIC_API_KEY" ]; then
  echo "ERROR: Key not found in Bitwarden (item: $BW_ANTHROPIC_ITEM, field: $BW_FIELD)."
  echo "       Add the entry first, then re-run this script."
  exit 1
fi

# --- Write secrets.el ---
mkdir -p "$HOME/.emacs.d"
printf '(setenv "ANTHROPIC_API_KEY" "%s")\n' "$ANTHROPIC_API_KEY" > "$EMACS_SECRETS"
echo "==> secrets.el written to $EMACS_SECRETS"
echo "    Restart Emacs for the change to take effect."
