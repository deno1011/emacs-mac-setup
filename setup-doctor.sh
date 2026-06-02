#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/setup-lib.sh"

setup_add_homebrew_to_path
setup_load_config || true

echo ""
echo "======================================================================"
echo "Emacs Mac Setup Doctor"
echo "======================================================================"

setup_print_inventory || true

echo "State:"
echo "  Last phase                $(setup_state_get LAST_PHASE)"
echo "  Last error                $(setup_state_get LAST_ERROR)"
echo "  Next step                 $(setup_state_get NEXT_STEP)"
echo ""

if [ -n "${GH_USER:-}" ]; then
  echo "Validation:"
  _MISSING=""
  for _K in GIT_NAME GIT_EMAIL GH_REPO BW_FIELD BW_ITEM BW_GH_ITEM BW_GEMINI_ITEM BW_KEYCHAIN_SERVICE BW_EMAIL; do
    [ -z "$(setup_config_get "$_K")" ] && _MISSING="${_MISSING}${_K} "
  done
  [ -n "$_MISSING" ] && echo "  Config                    missing: $_MISSING" || echo "  Config                    ok"
  unset _K _MISSING
  if [ -z "$(setup_keychain_get)" ]; then
    echo "  Bitwarden Keychain        missing"
    echo "  Repair: bash ~/emacs-mac-setup/setup-intake.sh --repair bitwarden"
  else
    echo "  Bitwarden Keychain        found"
  fi
  if command -v bw >/dev/null 2>&1; then
    if setup_bw_unlock_with_keychain >/dev/null 2>&1; then
      echo "  Bitwarden unlock          ok"
      [ -n "$(setup_bw_get_field "$BW_GEMINI_ITEM" "$BW_FIELD")" ] \
        && echo "  Gemini key                found" \
        || echo "  Gemini key                missing (repair: setup-intake.sh --repair gemini)"
      [ -n "$(setup_bw_get_field "$BW_GH_ITEM" "$BW_FIELD")" ] \
        && echo "  GitHub token              found" \
        || echo "  GitHub token              missing (browser login fallback available)"
    else
      echo "  Bitwarden unlock          failed"
      echo "  Repair: bash ~/emacs-mac-setup/setup-intake.sh --repair bitwarden"
    fi
  fi
else
  echo "Validation:"
  echo "  Local-only mode           ok"
fi

echo ""
echo "Resume:"
echo "  bash ~/emacs-mac-setup/bootstrap.sh stable --resume"
echo "======================================================================"
