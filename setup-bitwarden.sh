#!/bin/bash
set -e

skip() { echo "  Already exists: $1 — skipping."; }

CONFIG_FILE="$HOME/setup-emacs-mac.conf"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "ERROR: $CONFIG_FILE not found. Run bootstrap.sh first."
  exit 1
fi
source "$CONFIG_FILE"

# --- Bitwarden App ---
if [ -d "/Applications/Bitwarden.app" ] || [ -d "$HOME/Applications/Bitwarden.app" ]; then
  echo "==> Bitwarden App already installed."
else
  printf "==> Bitwarden App not installed. Install it? [Y/n] "
  read -r ans
  if [ "$ans" != "n" ] && [ "$ans" != "N" ]; then
    echo "==> Installing Bitwarden App..."
    brew install --cask bitwarden
  fi
fi

# --- Bitwarden CLI ---
if command -v bw &>/dev/null; then
  echo "==> Bitwarden CLI already installed."
else
  echo "==> Installing Bitwarden CLI..."
  brew install bitwarden-cli
fi

echo ""

# --- Login + unlock ---
BW_STATUS=$(bw status 2>/dev/null \
  | python3 -c "import sys,json; print(json.load(sys.stdin).get('status','unauthenticated'))" \
  2>/dev/null || echo "unauthenticated")

if [ "$BW_STATUS" = "unauthenticated" ]; then
  echo "==> Bitwarden login"
  echo "    Enter your email and master password."
  echo "    If you use 2FA, you will be prompted for the code too."
  echo ""
  printf "  Bitwarden email: "
  read -r BW_EMAIL
  printf "  Master password: "
  read -rs BW_MASTER_INPUT
  echo ""

  # Store master password in Keychain right away
  security delete-generic-password -a "$BW_KEYCHAIN_ACCOUNT" -s "$BW_KEYCHAIN_SERVICE" 2>/dev/null || true
  security add-generic-password -a "$BW_KEYCHAIN_ACCOUNT" -s "$BW_KEYCHAIN_SERVICE" -w "$BW_MASTER_INPUT" -A

  export _BW_MASTER="$BW_MASTER_INPUT"
  BW_SESSION=$(bw login "$BW_EMAIL" --passwordenv _BW_MASTER --raw 2>/dev/null) || true
  unset _BW_MASTER BW_MASTER_INPUT

  if [ -z "$BW_SESSION" ]; then
    echo "  Auto-login failed (2FA or wrong credentials)."
    echo "  Running interactive login — enter credentials when prompted:"
    bw login
    # Re-read master password for unlock
    BW_MASTER_STORED=$(security find-generic-password -a "$BW_KEYCHAIN_ACCOUNT" -s "$BW_KEYCHAIN_SERVICE" -w 2>/dev/null) || true
    export _BW_MASTER="$BW_MASTER_STORED"
    BW_SESSION=$(bw unlock --passwordenv _BW_MASTER --raw 2>/dev/null) || true
    unset _BW_MASTER
  fi
else
  # Already logged in — just unlock
  BW_MASTER=$(security find-generic-password -a "$BW_KEYCHAIN_ACCOUNT" -s "$BW_KEYCHAIN_SERVICE" -w 2>/dev/null) || true
  if [ -z "$BW_MASTER" ]; then
    printf "==> Bitwarden master password (stored in Keychain for future use): "
    read -rs BW_MASTER
    echo ""
    security delete-generic-password -a "$BW_KEYCHAIN_ACCOUNT" -s "$BW_KEYCHAIN_SERVICE" 2>/dev/null || true
    security add-generic-password -a "$BW_KEYCHAIN_ACCOUNT" -s "$BW_KEYCHAIN_SERVICE" -w "$BW_MASTER" -A
  fi
  export _BW_MASTER="$BW_MASTER"
  BW_SESSION=$(bw unlock --passwordenv _BW_MASTER --raw 2>/dev/null) || true
  unset _BW_MASTER
fi

if [ -z "$BW_SESSION" ]; then
  echo "ERROR: Bitwarden unlock failed. Remove keychain entry and retry:"
  echo "  security delete-generic-password -a \"$BW_KEYCHAIN_ACCOUNT\" -s \"$BW_KEYCHAIN_SERVICE\""
  exit 1
fi
export BW_SESSION
bw sync --session "$BW_SESSION" &>/dev/null || true
echo "==> Bitwarden vault unlocked."
echo ""

# --- Helper: create item with a single hidden custom field ---
bw_create_item() {
  local NAME="$1" VALUE="$2"
  if bw get item "$NAME" --session "$BW_SESSION" &>/dev/null 2>&1; then
    skip "$NAME"
    return
  fi
  local ENCODED
  ENCODED=$(python3 -c "
import json, sys
name, field, value = sys.argv[1], sys.argv[2], sys.argv[3]
print(json.dumps({
    'type': 1,
    'name': name,
    'login': {'username': None, 'password': None},
    'fields': [{'name': field, 'value': value, 'type': 1}]
}))
" "$NAME" "$BW_FIELD" "$VALUE" | bw encode)
  bw create item "$ENCODED" --session "$BW_SESSION" &>/dev/null
  echo "  Created: $NAME  (field: $BW_FIELD)"
}

# --- Prompt for values ---
echo "==> Enter values for Bitwarden entries."
echo "    Press Enter to skip an entry."
echo "    Type 'n' at any prompt to stop and use placeholder values instead."
echo ""

SKIP_ALL=false
GH_TOKEN_VAL=""
GC_KEY_VAL=""
ANTHROPIC_VAL=""

printf "  %-54s: " "GitHub Personal Access Token  (repo scope)"
read -rs GH_TOKEN_VAL
echo ""
if [ "$GH_TOKEN_VAL" = "n" ]; then SKIP_ALL=true; GH_TOKEN_VAL=""; fi

if [ "$SKIP_ALL" = false ]; then
  printf "  %-54s: " "git-crypt key base64  (Enter to skip — optional)"
  read -rs GC_KEY_VAL
  echo ""
  if [ "$GC_KEY_VAL" = "n" ]; then SKIP_ALL=true; GC_KEY_VAL=""; fi
fi

if [ "$SKIP_ALL" = false ]; then
  printf "  %-54s: " "Anthropic API Key  (Enter to skip — optional)"
  read -rs ANTHROPIC_VAL
  echo ""
  if [ "$ANTHROPIC_VAL" = "n" ]; then SKIP_ALL=true; ANTHROPIC_VAL=""; fi
fi

# --- Auto-setup with placeholders if aborted ---
if [ "$SKIP_ALL" = true ]; then
  echo ""
  echo "==> Some entries were skipped."
  printf "    Create all missing Bitwarden entries with placeholder values now? [y/N] "
  read -r ans
  if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
    [ -z "$GH_TOKEN_VAL" ]   && GH_TOKEN_VAL="PLACEHOLDER_GITHUB_TOKEN"
    [ -z "$GC_KEY_VAL" ]     && GC_KEY_VAL="PLACEHOLDER_GIT_CRYPT_KEY"
    [ -z "$ANTHROPIC_VAL" ]  && ANTHROPIC_VAL="PLACEHOLDER_ANTHROPIC_KEY"
  fi
fi

# --- Create entries ---
echo ""
echo "==> Creating Bitwarden entries..."
[ -n "$GH_TOKEN_VAL" ]   && bw_create_item "$BW_GH_ITEM"        "$GH_TOKEN_VAL"
[ -n "$GC_KEY_VAL" ]     && bw_create_item "$BW_ITEM"           "$GC_KEY_VAL"
[ -n "$ANTHROPIC_VAL" ]  && bw_create_item "$BW_ANTHROPIC_ITEM" "$ANTHROPIC_VAL"

echo ""
echo "======================================================================"
echo "Bitwarden setup complete!"
echo "======================================================================"
echo ""
echo "  Vault entries use field name: $BW_FIELD"
HAS_PLACEHOLDER=false
echo "$GH_TOKEN_VAL$GC_KEY_VAL$ANTHROPIC_VAL" | grep -q "PLACEHOLDER" && HAS_PLACEHOLDER=true || true
if [ "$HAS_PLACEHOLDER" = true ]; then
  echo ""
  echo "  IMPORTANT: Placeholder values were created."
  echo "  Open the Bitwarden app and replace them with real values before running setup."
fi
echo ""
