#!/bin/bash
# Shared Bitwarden helper — source this file, do not run directly.
#
# Usage in other scripts:
#   source "$HOME/bw-unlock.sh"
#   bw_ensure_session || exit 1
#   VALUE=$(bw_get_field "item-name" "field-name")

bw_ensure_session() {
  local _CFG="$HOME/emacs-mac-setup/setup-emacs-mac.conf"
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

  export __BW_PW="$_BW_MASTER"

  # Try unlock first (works if already logged in but locked)
  BW_SESSION=$(bw unlock --passwordenv __BW_PW --raw 2>/dev/null) || true

  if [ -z "$BW_SESSION" ]; then
    # Unlock failed — vault not yet authenticated, need full login
    printf "==> Bitwarden email: " >&2
    read -r _BW_EMAIL < /dev/tty
    BW_SESSION=$(bw login "$_BW_EMAIL" --passwordenv __BW_PW --raw < /dev/tty) || true
    # After login, unlock to get session if login didn't return one
    [ -z "$BW_SESSION" ] && BW_SESSION=$(bw unlock --passwordenv __BW_PW --raw 2>/dev/null) || true
  fi
  unset __BW_PW

  if [ -z "$BW_SESSION" ]; then
    echo "ERROR: Bitwarden unlock failed. To reset:" >&2
    echo "  bash ~/emacs-mac-setup/remove-bitwarden-keychain.sh" >&2
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

# ensure_api_key ITEM_NAME FIELD DISPLAY_NAME [URL_HINT]
#
# Returns the API key on stdout. Status/prompts go to stderr.
#
#   1. Try bw_get_field. If a non-empty key exists, return it.
#   2. Otherwise, prompt the user interactively (read from /dev/tty
#      so it works inside non-interactive contexts too). Empty
#      input = skip.
#   3. If the user provided a key, create a Bitwarden Login item
#      named ITEM_NAME with the key set as BOTH login.password
#      AND a custom field named FIELD. (Both populated for
#      compatibility with bw_get_field's read-order. Subsequent
#      reads via bw_get_field "$ITEM_NAME" "$FIELD" return the key.)
#   4. Sync the vault. Return the key.
#
# Empty stdout = skipped (or save failed but user might not want
# to abort the whole script).
bw_ensure_api_key() {
  local _ITEM="$1" _FIELD="$2" _DISPLAY="$3" _URL_HINT="${4:-}"

  # 1. Try BW first
  local _KEY
  _KEY=$(bw_get_field "$_ITEM" "$_FIELD") || true
  if [ -n "$_KEY" ]; then
    echo "    ✓ $_DISPLAY: loaded from Bitwarden (item: $_ITEM)" >&2
    printf '%s' "$_KEY"
    return 0
  fi

  # 2. Not in BW — prompt
  echo "" >&2
  echo "==> $_DISPLAY not yet in Bitwarden (item name: $_ITEM)" >&2
  [ -n "$_URL_HINT" ] && echo "    Get a key at: $_URL_HINT" >&2
  printf "    Paste your %s now (input hidden; Enter to skip): " "$_DISPLAY" >&2
  IFS= read -rs _KEY < /dev/tty
  echo "" >&2

  if [ -z "$_KEY" ]; then
    echo "    Skipped. You can add the key to Bitwarden as '$_ITEM' later" >&2
    echo "    and re-run setup, or edit ~/.emacs.d/secrets.el directly." >&2
    return 0
  fi

  # 3. Save the new key to Bitwarden
  echo "==> Saving $_DISPLAY to Bitwarden as item '$_ITEM'..." >&2
  local _JSON
  _JSON=$(python3 -c "
import json, sys
print(json.dumps({
  'type': 1,
  'name': '$_ITEM',
  'login': {'password': sys.argv[1]},
  'fields': [{'name': '$_FIELD', 'value': sys.argv[1], 'type': 1}]
}))
" "$_KEY")
  if echo "$_JSON" | bw encode --session "$BW_SESSION" 2>/dev/null \
                   | bw create item --session "$BW_SESSION" > /dev/null 2>&1; then
    echo "    ✓ Saved to Bitwarden." >&2
    bw sync --session "$BW_SESSION" > /dev/null 2>&1 || true
  else
    echo "    WARN: Could not create Bitwarden item. Key will be in" >&2
    echo "          secrets.el for this install only." >&2
  fi

  printf '%s' "$_KEY"
}
