#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/setup-lib.sh"

REPAIR_MODE=""
if [ "${1:-}" = "--repair" ]; then
  REPAIR_MODE="${2:-}"
fi

setup_add_homebrew_to_path
setup_phase "Phase 1/5: Discover existing setup"
setup_ensure_config
setup_runtime_load

if [ -z "$(setup_config_get GH_USER)" ] && command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  _GH_DETECTED=$(gh api user --jq '.login' 2>/dev/null || true)
  [ -n "$_GH_DETECTED" ] && setup_config_set GH_USER "$_GH_DETECTED"
  unset _GH_DETECTED
fi

if [ -z "$(setup_config_get GIT_NAME)" ] && [ -n "$(setup_config_get GH_USER)" ] \
   && command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  echo "  Looking for existing setup-emacs-mac.conf in known GitHub repos..."
  setup_try_load_private_config_from_github || true
  setup_runtime_load
fi

setup_print_inventory

setup_phase "Phase 2/5: Resolve setup data"
setup_prompt_config_if_empty GIT_NAME            "Full name (git commits)"                     ""
setup_prompt_config_if_empty GIT_EMAIL           "Email (git commits)"                         ""
setup_prompt_config_if_empty GH_USER             "GitHub username (Enter for local-only mode)"  ""
setup_prompt_config_if_empty GH_REPO             "Emacs data repo"                             "emacs-data"

setup_runtime_load

if [ -n "${GH_USER:-}" ]; then
  setup_prompt_config_if_empty BW_FIELD            "Bitwarden custom field name"                  "Key"
  setup_prompt_config_if_empty BW_ITEM             "git-crypt Bitwarden item name"                "emacs-git-crypt-key"
  setup_prompt_config_if_empty BW_GH_ITEM          "GitHub token Bitwarden item name"             "github-cli-token"
  setup_prompt_config_if_empty BW_ANTHROPIC_ITEM   "Anthropic key Bitwarden item name"            "anthropic-api-key"
  setup_prompt_config_if_empty BW_GEMINI_ITEM      "Gemini key Bitwarden item name"               "gemini-api-key"
  setup_prompt_config_if_empty BW_KEYCHAIN_SERVICE "macOS Keychain service label"                 "bitwarden-master"
  setup_runtime_load

  setup_require_config GIT_NAME GIT_EMAIL GH_REPO BW_FIELD BW_ITEM BW_GH_ITEM BW_ANTHROPIC_ITEM BW_GEMINI_ITEM BW_KEYCHAIN_SERVICE
  if [ "$REPAIR_MODE" = "bitwarden" ]; then
    _BW_EMAIL="$(setup_prompt "Bitwarden email / username" "${BITWARDEN_EMAIL:-}")"
    [ -n "$_BW_EMAIL" ] && setup_config_set BITWARDEN_EMAIL "$_BW_EMAIL"
    unset _BW_EMAIL
  else
    setup_prompt_config_if_empty BITWARDEN_EMAIL "Bitwarden email / username" ""
  fi
  setup_runtime_load
  setup_require_bitwarden_email

  setup_phase "Phase 3/5: Collect passwords and tokens"
  if [ -z "${BITWARDEN_MASTER_PASSWORD:-}" ] || [ "$REPAIR_MODE" = "bitwarden" ]; then
    echo ""
    if [ -z "${BITWARDEN_MASTER_PASSWORD:-}" ]; then
      echo "  No existing Bitwarden master password found in macOS Keychain."
      echo "  Lookup accounts: $(setup_keychain_lookup_accounts_label)"
      echo "  Lookup service: ${BW_KEYCHAIN_SERVICE:-bitwarden-master} (fallback: bitwarden-master)"
    fi
    echo "  Bitwarden master password is saved to macOS Keychain, not setup config."
    _BW_MASTER="$(setup_prompt_secret "Bitwarden master password")"
    [ -n "$_BW_MASTER" ] || setup_fail "Bitwarden master password is required in GitHub mode." "bash ~/emacs-mac-setup/setup-intake.sh --repair bitwarden"
    setup_runtime_store_bitwarden_master "$_BW_MASTER" || setup_fail "Could not store Bitwarden password in macOS Keychain." "bash ~/emacs-mac-setup/setup-intake.sh --repair bitwarden"
    unset _BW_MASTER
  else
    export BITWARDEN_MASTER_PASSWORD
    if [ -z "$(setup_keychain_get)" ]; then
      setup_keychain_set "$BITWARDEN_MASTER_PASSWORD" || setup_fail "Could not store Bitwarden password in macOS Keychain." "bash ~/emacs-mac-setup/setup-intake.sh --repair bitwarden"
    fi
  fi
  setup_runtime_load

  setup_phase "Phase 4/5: Validate Bitwarden and sync secrets"
  setup_install_bitwarden_tools

  setup_bw_unlock_with_keychain || exit 1
  setup_state_set BITWARDEN_LOGIN_OK true
  echo "  Bitwarden vault unlocked."

  setup_runtime_import_secret_from_bitwarden GITHUB_TOKEN "$BW_GH_ITEM" "$BW_FIELD"
  setup_runtime_import_secret_from_bitwarden GIT_CRYPT_KEY "$BW_ITEM" "$BW_FIELD"
  setup_runtime_import_secret_from_bitwarden GEMINI_API_KEY "$BW_GEMINI_ITEM" "$BW_FIELD"
  setup_runtime_import_secret_from_bitwarden ANTHROPIC_API_KEY "$BW_ANTHROPIC_ITEM" "$BW_FIELD"
  setup_runtime_load

  if [ -z "${GITHUB_TOKEN:-}" ] && command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    _GH_TOKEN="$(gh auth token 2>/dev/null || true)"
    [ -n "$_GH_TOKEN" ] && setup_runtime_store_secret GITHUB_TOKEN "$_GH_TOKEN"
    unset _GH_TOKEN
  fi

  if [ -z "${GITHUB_TOKEN:-}" ] || [ "$REPAIR_MODE" = "github-token" ]; then
    echo ""
    _GH_TOKEN="$(setup_prompt_secret "GitHub token (repo scope; required unless gh is already logged in)")"
    [ -n "$_GH_TOKEN" ] && setup_runtime_store_secret GITHUB_TOKEN "$_GH_TOKEN"
    unset _GH_TOKEN
  fi

  if [ -z "${GEMINI_API_KEY:-}" ] || [ "$REPAIR_MODE" = "gemini" ]; then
    echo ""
    echo "  Gemini is the default gptel backend. Get a free key at:"
    echo "  https://aistudio.google.com/apikey"
    _GEMINI_KEY="$(setup_prompt_secret "Gemini API key (Enter to skip)")"
    [ -n "$_GEMINI_KEY" ] && setup_runtime_store_secret GEMINI_API_KEY "$_GEMINI_KEY"
    unset _GEMINI_KEY
  fi

  if [ -z "${ANTHROPIC_API_KEY:-}" ] || [ "$REPAIR_MODE" = "anthropic" ]; then
    echo ""
    _ANTHROPIC_KEY="$(setup_prompt_secret "Anthropic API key (optional, Enter to skip)")"
    [ -n "$_ANTHROPIC_KEY" ] && setup_runtime_store_secret ANTHROPIC_API_KEY "$_ANTHROPIC_KEY"
    unset _ANTHROPIC_KEY
  fi
  setup_runtime_load

  if [ -z "${GITHUB_TOKEN:-}" ] && ! { command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; }; then
    setup_fail "GitHub token is missing. Automatic setup cannot authenticate later without interrupting." "bash ~/emacs-mac-setup/setup-intake.sh --repair github-token"
  fi

  if [ -z "${GIT_CRYPT_KEY:-}" ]; then
    echo "  git-crypt key missing — generating one now."
    command -v git-crypt >/dev/null 2>&1 || brew install git-crypt
    _GC_TMP="$(mktemp -d)"
    git -C "$_GC_TMP" init -q
    (cd "$_GC_TMP" && git crypt init) 2>/dev/null
    (cd "$_GC_TMP" && git crypt export-key /tmp/gckey_bs)
    _GC_KEY="$(base64 -i /tmp/gckey_bs | tr -d '\n')"
    rm -f /tmp/gckey_bs
    rm -rf "$_GC_TMP"
    setup_runtime_store_secret GIT_CRYPT_KEY "$_GC_KEY"
    unset _GC_KEY _GC_TMP
  fi
  setup_runtime_load

  setup_runtime_mirror_secret_to_bitwarden GITHUB_TOKEN "$BW_GH_ITEM" "$BW_FIELD"
  setup_runtime_mirror_secret_to_bitwarden GIT_CRYPT_KEY "$BW_ITEM" "$BW_FIELD"
  setup_runtime_mirror_secret_to_bitwarden GEMINI_API_KEY "$BW_GEMINI_ITEM" "$BW_FIELD"
  setup_runtime_mirror_secret_to_bitwarden ANTHROPIC_API_KEY "$BW_ANTHROPIC_ITEM" "$BW_FIELD"

  setup_phase "Phase 5/5: Final validation"
  setup_runtime_require GIT_NAME GIT_EMAIL GH_REPO BW_FIELD BW_ITEM BW_GH_ITEM BW_ANTHROPIC_ITEM BW_GEMINI_ITEM BW_KEYCHAIN_SERVICE BITWARDEN_EMAIL BITWARDEN_MASTER_PASSWORD GIT_CRYPT_KEY
  if [ -z "${GITHUB_TOKEN:-}" ] && ! { command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; }; then
    setup_fail "GitHub token is missing and gh is not already authenticated." "bash ~/emacs-mac-setup/setup-intake.sh --repair github-token"
  fi
else
  echo "  Local-only mode selected. Bitwarden/GitHub setup will be skipped."
fi

setup_state_set INTAKE_DONE true
setup_state_set LAST_ERROR ""
setup_state_set NEXT_STEP ""

echo ""
echo "======================================================================"
echo "Setup intake complete"
echo "======================================================================"
echo "  Config: $SETUP_CONFIG"
echo "  Mode:   $([ -n "${GH_USER:-}" ] && echo "GitHub + Bitwarden" || echo "local-only")"
echo "======================================================================"
