#!/bin/bash
# Shared setup helpers. Source this file; do not run it directly.

SETUP_DIR="${SETUP_DIR:-$HOME/emacs-mac-setup}"
SETUP_CONFIG="${SETUP_CONFIG:-$SETUP_DIR/setup-emacs-mac.conf}"
SETUP_TEMPLATE="${SETUP_TEMPLATE:-$SETUP_DIR/setup-emacs-mac.conf.template}"
SETUP_STATE="${SETUP_STATE:-$SETUP_DIR/.setup-state}"

setup_add_homebrew_to_path() {
  [ -f /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
  [ -f /usr/local/bin/brew ]    && eval "$(/usr/local/bin/brew shellenv)"
  export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
}

setup_state_set() {
  local key="$1" value="$2"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  mkdir -p "$SETUP_DIR"
  local tmp
  tmp="$(mktemp)"
  [ -f "$SETUP_STATE" ] || : > "$SETUP_STATE"
  awk -v key="$key" -v value="$value" '
    BEGIN { done = 0 }
    index($0, key "=") == 1 { print key "=\"" value "\""; done = 1; next }
    { print }
    END { if (!done) print key "=\"" value "\"" }
  ' "$SETUP_STATE" > "$tmp"
  mv "$tmp" "$SETUP_STATE"
}

setup_state_get() {
  local key="$1"
  grep "^${key}=" "$SETUP_STATE" 2>/dev/null | head -1 | cut -d= -f2- | sed 's/^"//; s/"$//'
}

setup_phase() {
  setup_state_set LAST_PHASE "$1"
  echo ""
  echo "==> $1"
}

setup_fail() {
  local message="$1" next="${2:-bash ~/emacs-mac-setup/setup-doctor.sh}"
  setup_state_set LAST_ERROR "$message"
  setup_state_set NEXT_STEP "$next"
  echo ""
  echo "======================================================================"
  echo "Setup paused"
  echo "======================================================================"
  echo ""
  echo "Problem:"
  echo "  $message"
  echo ""
  echo "Next action:"
  echo "  $next"
  echo ""
  echo "After fixing, resume with:"
  echo "  bash ~/emacs-mac-setup/bootstrap.sh stable --resume"
  echo "======================================================================"
  return 1
}

setup_ensure_config() {
  mkdir -p "$SETUP_DIR"
  if [ ! -f "$SETUP_CONFIG" ]; then
    [ -f "$SETUP_TEMPLATE" ] || setup_fail "Config template not found: $SETUP_TEMPLATE" "bash ~/emacs-mac-setup/bootstrap.sh stable"
    cp "$SETUP_TEMPLATE" "$SETUP_CONFIG"
    echo "  Created config: $SETUP_CONFIG"
  fi
}

setup_config_get() {
  local key="$1"
  grep "^${key}=" "$SETUP_CONFIG" 2>/dev/null | head -1 | cut -d= -f2- | sed 's/^"//; s/"$//'
}

setup_config_set() {
  local key="$1" value="$2"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  setup_ensure_config || return 1
  local tmp
  tmp="$(mktemp)"
  awk -v key="$key" -v value="$value" '
    BEGIN { done = 0 }
    index($0, key "=") == 1 { print key "=\"" value "\""; done = 1; next }
    { print }
    END { if (!done) print key "=\"" value "\"" }
  ' "$SETUP_CONFIG" > "$tmp"
  mv "$tmp" "$SETUP_CONFIG"
}

setup_load_config() {
  setup_ensure_config || return 1
  # shellcheck disable=SC1090
  source "$SETUP_CONFIG"
  MACOS_KEYCHAIN_ACCOUNT="${MACOS_KEYCHAIN_ACCOUNT:-${BW_KEYCHAIN_ACCOUNT:-$USER}}"
  BITWARDEN_EMAIL="${BITWARDEN_EMAIL:-${BW_EMAIL:-}}"
  BW_EMAIL="$BITWARDEN_EMAIL"
}

setup_prompt() {
  local prompt="$1" default="${2:-}" value
  if [ -n "$default" ]; then
    printf "  %-58s [%s]: " "$prompt" "$default" > /dev/tty
  else
    printf "  %-58s: " "$prompt" > /dev/tty
  fi
  read -r value < /dev/tty
  printf '%s' "${value:-$default}"
}

setup_prompt_secret() {
  local prompt="$1" value
  printf "  %-58s: " "$prompt" > /dev/tty
  read -rs value < /dev/tty
  echo "" > /dev/tty
  printf '%s' "$value"
}

setup_prompt_config_if_empty() {
  local key="$1" prompt="$2" default="$3" value
  value="$(setup_config_get "$key")"
  if [ -z "$value" ]; then
    value="$(setup_prompt "$prompt" "$default")"
    [ -n "$value" ] && setup_config_set "$key" "$value"
  fi
}

setup_require_config() {
  local missing="" key
  for key in "$@"; do
    if [ -z "$(setup_config_get "$key")" ]; then
      missing="${missing}${key} "
    fi
  done
  if [ -n "$missing" ]; then
    setup_fail "Missing required config value(s): $missing" "bash ~/emacs-mac-setup/setup-intake.sh --repair config"
    return 1
  fi
}

setup_require_bitwarden_email() {
  setup_load_config || return 1
  if [ -z "${BITWARDEN_EMAIL:-}" ]; then
    setup_fail "Missing required config value(s): BITWARDEN_EMAIL " "bash ~/emacs-mac-setup/setup-intake.sh --repair config"
    return 1
  fi
}

setup_keychain_get() {
  local account="${MACOS_KEYCHAIN_ACCOUNT:-${BW_KEYCHAIN_ACCOUNT:-$USER}}" service="${BW_KEYCHAIN_SERVICE:-bitwarden-master}"
  security find-generic-password -a "$account" -s "$service" -w 2>/dev/null || true
}

setup_keychain_set() {
  local password="$1" account="${MACOS_KEYCHAIN_ACCOUNT:-${BW_KEYCHAIN_ACCOUNT:-$USER}}" service="${BW_KEYCHAIN_SERVICE:-bitwarden-master}"
  [ -n "$password" ] || return 1
  security delete-generic-password -a "$account" -s "$service" 2>/dev/null || true
  security add-generic-password -a "$account" -s "$service" -w "$password" -A >/dev/null
}

setup_install_bitwarden_tools() {
  setup_add_homebrew_to_path
  command -v brew >/dev/null 2>&1 || setup_fail "Homebrew is required before Bitwarden setup." "bash ~/emacs-mac-setup/bootstrap.sh stable"
  if ! command -v bw >/dev/null 2>&1; then
    echo "  Installing Bitwarden CLI..."
    brew install bitwarden-cli
  fi
  if [ ! -d "/Applications/Bitwarden.app" ] && [ ! -d "$HOME/Applications/Bitwarden.app" ]; then
    echo "  Installing Bitwarden desktop app..."
    brew install --cask bitwarden || echo "  WARN: Bitwarden app install failed; CLI setup can still continue."
  fi
}

setup_bw_status() {
  command -v bw >/dev/null 2>&1 || { echo "missing"; return; }
  bw status 2>/dev/null | sed -n 's/.*"status"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
}

setup_bw_unlock_with_keychain() {
  setup_load_config || return 1
  command -v bw >/dev/null 2>&1 || setup_fail "Bitwarden CLI is not installed." "bash ~/emacs-mac-setup/setup-intake.sh --repair bitwarden"
  local master status session
  master="$(setup_keychain_get)"
  [ -n "$master" ] || setup_fail "Bitwarden master password is not stored in macOS Keychain." "bash ~/emacs-mac-setup/setup-intake.sh --repair bitwarden"
  export __BW_PW="$master"
  status="$(setup_bw_status)"
  if [ "$status" = "unauthenticated" ]; then
    [ -n "${BITWARDEN_EMAIL:-}" ] || setup_fail "Bitwarden email is missing from setup config." "bash ~/emacs-mac-setup/setup-intake.sh --repair bitwarden"
    session="$(bw login "$BITWARDEN_EMAIL" --passwordenv __BW_PW --raw 2>/dev/null)" || true
  else
    session="$(bw unlock --passwordenv __BW_PW --raw 2>/dev/null)" || true
  fi
  unset __BW_PW
  [ -n "$session" ] || setup_fail "Bitwarden login/unlock failed. Password, email, or 2FA state needs attention." "bash ~/emacs-mac-setup/setup-intake.sh --repair bitwarden"
  export BW_SESSION="$session"
  bw sync --session "$BW_SESSION" >/dev/null 2>&1 || true
}

setup_bw_get_field() {
  local item="$1" field="$2"
  [ -n "$item" ] || return 0
  [ -n "$field" ] || return 0
  bw get item "$item" --session "$BW_SESSION" 2>/dev/null \
    | python3 -c "
import sys,json
d=json.load(sys.stdin)
f=[x.get('value','') for x in d.get('fields',[]) if x.get('name')=='$field']
print((f[0] if f else (d.get('login') or {}).get('password') or '').strip())
" 2>/dev/null || true
}

setup_bw_create_item() {
  local name="$1" field="$2" value="$3"
  [ -n "$name" ]  || setup_fail "Refusing to create a Bitwarden item with an empty name." "bash ~/emacs-mac-setup/setup-intake.sh --repair config"
  [ -n "$field" ] || setup_fail "Refusing to create Bitwarden item '$name' with an empty field name." "bash ~/emacs-mac-setup/setup-intake.sh --repair config"
  [ -n "$value" ] || return 0
  if bw get item "$name" --session "$BW_SESSION" >/dev/null 2>&1; then
    echo "  Already exists: $name"
    return 0
  fi
  local encoded
  encoded=$(python3 -c "
import json,sys
name,field,value=sys.argv[1],sys.argv[2],sys.argv[3]
print(json.dumps({'type':1,'name':name,'login':{'password':value},'fields':[{'name':field,'value':value,'type':1}]}))
" "$name" "$field" "$value" | bw encode)
  echo "$encoded" | bw create item --session "$BW_SESSION" >/dev/null
  echo "  Created: $name"
}

setup_print_inventory() {
  setup_load_config || return 1
  echo ""
  echo "Detected setup inventory:"
  echo ""
  echo "Config:"
  echo "  setup-emacs-mac.conf      $([ -f "$SETUP_CONFIG" ] && echo found || echo missing)"
  echo "  GH_USER                   ${GH_USER:-<local mode>}"
  echo "  GH_REPO                   ${GH_REPO:-emacs-data}"
  echo "  BW_FIELD                  ${BW_FIELD:-<missing>}"
  echo "  BW_GEMINI_ITEM            ${BW_GEMINI_ITEM:-<missing>}"
  echo ""
  echo "macOS Keychain:"
  if [ -n "${BW_KEYCHAIN_SERVICE:-}" ] && [ -n "$(setup_keychain_get)" ]; then
    echo "  Bitwarden password        found"
  else
    echo "  Bitwarden password        missing"
  fi
  echo ""
  echo "Tools:"
  echo "  Homebrew                  $(command -v brew >/dev/null 2>&1 && echo installed || echo missing)"
  echo "  GitHub CLI                $(command -v gh >/dev/null 2>&1 && echo installed || echo missing)"
  echo "  Bitwarden CLI             $(command -v bw >/dev/null 2>&1 && echo installed || echo missing)"
  echo "  Bitwarden status          $(setup_bw_status 2>/dev/null || echo unknown)"
  echo ""
}
