#!/bin/bash
# Shared Bitwarden helper — source this file, do not run directly.
#
# Usage in other scripts:
#   source "$HOME/bw-unlock.sh"
#   bw_ensure_session || exit 1
#   VALUE=$(bw_get_field "item-name" "field-name")

bw_ensure_session() {
  local _CFG="$HOME/setup-emacs-mac.conf"
  [ -f "$_CFG" ] && source "$_CFG"
  local _KC_ACC="${BW_KEYCHAIN_ACCOUNT:-$USER}"
  local _KC_SVC="${BW_KEYCHAIN_SERVICE:-bitwarden-master}"

  if ! command -v bw &>/dev/null; then
    echo "ERROR: Bitwarden CLI not installed (brew install bitwarden-cli)" >&2
    return 1
  fi

  local _BW_MASTER
  _BW_MASTER=$(security find-generic-password -a "$_KC_ACC" -s "$_KC_SVC" -w 2>/dev/null) || true
  if [ -z "$_BW_MASTER" ]; then
    printf "==> Bitwarden master password: " >&2
    read -rs _BW_MASTER < /dev/tty
    echo "" >&2
    security delete-generic-password -a "$_KC_ACC" -s "$_KC_SVC" 2>/dev/null || true
    security add-generic-password -a "$_KC_ACC" -s "$_KC_SVC" -w "$_BW_MASTER" -A
  fi

  local _BW_STATUS
  _BW_STATUS=$(bw status 2>/dev/null \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('status','unauthenticated'))" \
    2>/dev/null || echo "unauthenticated")
  export __BW_PW="$_BW_MASTER"

  if [ "$_BW_STATUS" = "unauthenticated" ]; then
    printf "==> Bitwarden email: " >&2
    read -r _BW_EMAIL < /dev/tty
    # /dev/tty allows interactive 2FA input; stderr shows prompts
    BW_SESSION=$(bw login "$_BW_EMAIL" --passwordenv __BW_PW --raw < /dev/tty) || true
  fi
  if [ -z "$BW_SESSION" ]; then
    BW_SESSION=$(bw unlock --passwordenv __BW_PW --raw 2>/dev/null) || true
  fi
  unset __BW_PW

  if [ -z "$BW_SESSION" ]; then
    echo "ERROR: Bitwarden unlock failed. To reset:" >&2
    echo "  bash ~/remove-bitwarden-keychain.sh" >&2
    return 1
  fi
  export BW_SESSION
  bw sync --session "$BW_SESSION" &>/dev/null || true
}

bw_get_field() {
  local _ITEM="$1" _FIELD="$2"
  bw get item "$_ITEM" --session "$BW_SESSION" 2>/dev/null \
    | python3 -c "
import sys, json
d = json.load(sys.stdin)
f = [x['value'] for x in d.get('fields', []) if x['name'] == '$_FIELD']
print((f[0] if f else (d.get('login') or {}).get('password') or '').strip())
" 2>/dev/null || true
}
