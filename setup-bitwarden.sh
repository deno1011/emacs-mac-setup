#!/bin/bash
set -e

[ -f /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
[ -f /usr/local/bin/brew ]    && eval "$(/usr/local/bin/brew shellenv)"

skip() { echo "  Already exists: $1 — skipping."; }

CONFIG_FILE="$HOME/emacs-mac-setup/setup-emacs-mac.conf"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "ERROR: $CONFIG_FILE not found. Run bootstrap.sh first."
  exit 1
fi
source "$CONFIG_FILE"

# --- Bitwarden CLI ---
if command -v bw &>/dev/null; then
  echo "==> Bitwarden CLI already installed."
else
  echo "==> Installing Bitwarden CLI..."
  if ! brew install bitwarden-cli; then
    echo "    Install had a link error — trying to fix..."
    brew link --overwrite bitwarden-cli 2>/dev/null || true
    if ! command -v bw &>/dev/null; then
      echo "ERROR: Bitwarden CLI install failed. Run manually:"
      echo "  brew uninstall bitwarden-cli && brew install bitwarden-cli"
      exit 1
    fi
  fi
  echo "    Bitwarden CLI installed."
fi

# --- Bitwarden App ---
if [ -d "/Applications/Bitwarden.app" ] || [ -d "$HOME/Applications/Bitwarden.app" ]; then
  echo "==> Bitwarden App already installed."
else
  echo ""
  echo "==> Installing Bitwarden desktop app..."
  if brew install --cask bitwarden; then
    echo "    Bitwarden desktop app installed."
  else
    echo "    WARN: Bitwarden desktop app install failed."
    echo "    You can still continue with the CLI, or install the app later from:"
    echo "    https://bitwarden.com/download/"
  fi
fi

echo ""

# --- Login + unlock ---
BW_STATUS=$(bw status 2>/dev/null \
  | python3 -c "import sys,json; print(json.load(sys.stdin).get('status','unauthenticated'))" \
  2>/dev/null || echo "unauthenticated")

if [ "$BW_STATUS" = "unauthenticated" ]; then
  echo "==> Bitwarden login"
  echo "    Enter your email and master password for an existing Bitwarden account."
  echo "    If you use 2FA, you will be prompted for the code too."
  echo "    New to Bitwarden? Create and verify an account first; then return here."
  echo ""
  printf "  Do you already have a Bitwarden account? [y/N]: "
  read -r BW_HAS_ACCOUNT < /dev/tty
  case "$BW_HAS_ACCOUNT" in
    y|Y|yes|YES)
      ;;
    *)
      echo ""
      echo "==> Opening Bitwarden so you can create an account."
      open -a Bitwarden 2>/dev/null || open "https://vault.bitwarden.com/#/register" 2>/dev/null || true
      echo ""
      echo "  Create the Bitwarden account, verify the email if Bitwarden asks,"
      echo "  then return to this terminal."
      printf "  Press Return when the account exists and you are ready to log in..."
      read -r _BW_WAIT < /dev/tty
      unset _BW_WAIT
      ;;
  esac
  unset BW_HAS_ACCOUNT

  printf "  Bitwarden email: "
  read -r BW_EMAIL < /dev/tty
  printf "  Master password: "
  read -rs BW_MASTER_INPUT < /dev/tty
  echo ""

  # Store master password in Keychain right away
  security delete-generic-password -a "$BW_KEYCHAIN_ACCOUNT" -s "$BW_KEYCHAIN_SERVICE" 2>/dev/null || true
  security add-generic-password -a "$BW_KEYCHAIN_ACCOUNT" -s "$BW_KEYCHAIN_SERVICE" -w "$BW_MASTER_INPUT" -A

  export _BW_MASTER="$BW_MASTER_INPUT"
  BW_SESSION=$(bw login "$BW_EMAIL" --passwordenv _BW_MASTER --raw 2>/dev/null) || true
  unset _BW_MASTER BW_MASTER_INPUT

  if [ -z "$BW_SESSION" ]; then
    echo "  Auto-login failed (2FA or wrong credentials)."
    echo "  If this is a new account, make sure it was created and verified first."
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
    read -rs BW_MASTER < /dev/tty
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

# --- Check which entries are still missing, then only prompt for missing ones ---
_bw_check_item() {
  bw get item "$1" --session "$BW_SESSION" 2>/dev/null \
    | python3 -c "
import sys,json
d=json.load(sys.stdin)
f=[x['value'] for x in d.get('fields',[]) if x['name']=='$BW_FIELD']
v=(f[0] if f else '').strip()
print('' if not v or 'PLACEHOLDER' in v else v)
" 2>/dev/null || true
}

GH_TOKEN_VAL=""
GC_KEY_VAL=""
ANTHROPIC_VAL=""
GEMINI_VAL=""

# --- GitHub Token ---
if [ -n "$(_bw_check_item "$BW_GH_ITEM")" ]; then
  echo "  GitHub Token already in Bitwarden — skipping."
else
  printf "  %-54s: " "GitHub Personal Access Token  (repo scope, Enter to skip)"
  read -rs GH_TOKEN_VAL < /dev/tty
  echo ""
fi

# --- git-crypt key: check or generate automatically ---
if [ -n "$(_bw_check_item "$BW_ITEM")" ]; then
  echo "  git-crypt key already in Bitwarden — skipping."
else
  echo "==> git-crypt key not found — generating automatically..."
  if ! command -v git-crypt &>/dev/null; then
    echo "    Installing git-crypt..."
    brew install git-crypt
  fi
  _GC_TMP=$(mktemp -d)
  git -C "$_GC_TMP" init -q
  (cd "$_GC_TMP" && git crypt init) 2>/dev/null
  (cd "$_GC_TMP" && git crypt export-key /tmp/gckey_bs)
  GC_KEY_VAL=$(base64 -i /tmp/gckey_bs | tr -d '\n')
  rm -f /tmp/gckey_bs
  rm -rf "$_GC_TMP"
  echo "    git-crypt key generated."
fi

# --- Anthropic Key (optional) ---
if [ -n "$(_bw_check_item "$BW_ANTHROPIC_ITEM")" ]; then
  echo "  Anthropic Key already in Bitwarden — skipping."
else
  printf "  %-54s: " "Anthropic API Key  (Enter to skip — optional)"
  read -rs ANTHROPIC_VAL < /dev/tty
  echo ""
fi

# --- Gemini Key (optional, free tier) ---
if [ -n "$(_bw_check_item "$BW_GEMINI_ITEM")" ]; then
  echo "  Gemini Key already in Bitwarden — skipping."
else
  printf "  %-54s: " "Gemini API Key     (free; aistudio.google.com, Enter to skip)"
  read -rs GEMINI_VAL < /dev/tty
  echo ""
fi

# --- Create entries ---
echo ""
echo "==> Creating Bitwarden entries..."
[ -n "$GH_TOKEN_VAL" ]   && bw_create_item "$BW_GH_ITEM"        "$GH_TOKEN_VAL"
[ -n "$GC_KEY_VAL" ]     && bw_create_item "$BW_ITEM"           "$GC_KEY_VAL"
[ -n "$ANTHROPIC_VAL" ]  && bw_create_item "$BW_ANTHROPIC_ITEM" "$ANTHROPIC_VAL"
[ -n "$GEMINI_VAL" ]     && bw_create_item "$BW_GEMINI_ITEM"    "$GEMINI_VAL"

echo ""
echo "======================================================================"
echo "Bitwarden setup complete!"
echo "======================================================================"
echo ""
echo "  Vault entries use field name: $BW_FIELD"
HAS_PLACEHOLDER=false
echo "$GH_TOKEN_VAL$GC_KEY_VAL$ANTHROPIC_VAL$GEMINI_VAL" | grep -q "PLACEHOLDER" && HAS_PLACEHOLDER=true || true
if [ "$HAS_PLACEHOLDER" = true ]; then
  echo ""
  echo "  IMPORTANT: Placeholder values were created."
  echo "  Open the Bitwarden app and replace them with real values before running setup."
fi
if [ -z "$GH_TOKEN_VAL" ] && [ -z "$(_bw_check_item "$BW_GH_ITEM")" ]; then
  echo ""
  echo "  NOTE: GitHub token was skipped — GitHub mode will fall back to interactive"
  echo "  browser login. Run setup-bitwarden.sh again to add it when you have the token."
  echo "  Generate one at: GitHub → Settings → Developer settings → Personal access tokens → Classic (scope: repo)"
fi
echo ""
