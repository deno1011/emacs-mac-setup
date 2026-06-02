#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/setup-lib.sh"

setup_add_homebrew_to_path
setup_runtime_load || true

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
  for _K in GIT_NAME GIT_EMAIL GH_REPO BW_FIELD BW_ITEM BW_GH_ITEM BW_ANTHROPIC_ITEM BW_GEMINI_ITEM BW_KEYCHAIN_SERVICE BITWARDEN_EMAIL BITWARDEN_MASTER_PASSWORD GIT_CRYPT_KEY; do
    [ -z "${!_K:-}" ] && _MISSING="${_MISSING}${_K} "
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
    if setup_runtime_load_bitwarden_secrets >/dev/null 2>&1; then
      echo "  Bitwarden unlock          ok"
    else
      echo "  Bitwarden unlock          failed"
      echo "  Repair: bash ~/emacs-mac-setup/setup-intake.sh --repair bitwarden"
    fi
  fi
  [ -n "${GITHUB_TOKEN:-}" ] \
    && echo "  GitHub token              found" \
    || echo "  GitHub token              missing (repair: setup-intake.sh --repair github-token)"
  [ -n "${GEMINI_API_KEY:-}" ] \
    && echo "  Gemini key                found" \
    || echo "  Gemini key                missing (repair: setup-intake.sh --repair gemini)"
  [ -n "${ANTHROPIC_API_KEY:-}" ] \
    && echo "  Anthropic key             found" \
    || echo "  Anthropic key             optional/missing"
else
  echo "Validation:"
  echo "  Local-only mode           ok"
fi

echo ""
echo "Resume:"
echo "  bash ~/emacs-mac-setup/bootstrap.sh stable --resume"
echo "======================================================================"
