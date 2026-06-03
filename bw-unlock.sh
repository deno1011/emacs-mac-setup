#!/bin/bash
# Shared Bitwarden compatibility API. New scripts should prefer setup-lib.sh
# directly; these function names remain for older setup entry points.

if [ -n "${BASH_SOURCE:-}" ]; then
  _BW_HELPER_FILE="${BASH_SOURCE[0]}"
elif [ -n "${ZSH_VERSION:-}" ]; then
  _BW_HELPER_FILE="${(%):-%x}"
else
  _BW_HELPER_FILE="$0"
fi
_BW_HELPER_DIR="$(cd "$(dirname "$_BW_HELPER_FILE")" && pwd)"
source "$_BW_HELPER_DIR/setup-lib.sh"

bw_ensure_session() {
  setup_ensure_config
  setup_runtime_load
  setup_install_bitwarden_tools
  setup_bw_unlock_with_keychain
}

bw_get_field() {
  setup_bw_get_field "$@"
}

bw_ensure_api_key() {
  local _ITEM="$1" _FIELD="$2" _DISPLAY="$3" _URL_HINT="${4:-}"
  local _KEY

  setup_runtime_load || true
  case "$_ITEM" in
    "${BW_GEMINI_ITEM:-}") _KEY="${GEMINI_API_KEY:-}" ;;
    "${BW_ANTHROPIC_ITEM:-}") _KEY="${ANTHROPIC_API_KEY:-}" ;;
    "${BW_GH_ITEM:-}") _KEY="${GITHUB_TOKEN:-}" ;;
    "${BW_ITEM:-}") _KEY="${GIT_CRYPT_KEY:-}" ;;
  esac
  if [ -n "$_KEY" ]; then
    echo "    $_DISPLAY: loaded from setup runtime" >&2
    printf '%s' "$_KEY"
    return 0
  fi

  _KEY="$(setup_bw_get_field "$_ITEM" "$_FIELD")" || true
  if [ -n "$_KEY" ]; then
    echo "    $_DISPLAY: loaded from Bitwarden (item: $_ITEM)" >&2
    printf '%s' "$_KEY"
    return 0
  fi

  echo "    $_DISPLAY missing in Bitwarden item '$_ITEM'." >&2
  [ -n "$_URL_HINT" ] && echo "    Key page: $_URL_HINT" >&2
  echo "    Repair: bash ~/emacs-mac-setup/setup-intake.sh --repair bitwarden" >&2
  return 0
}
