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
setup_load_config

if [ -z "$(setup_config_get GH_USER)" ] && command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  _GH_DETECTED=$(gh api user --jq '.login' 2>/dev/null || true)
  [ -n "$_GH_DETECTED" ] && setup_config_set GH_USER "$_GH_DETECTED"
  unset _GH_DETECTED
fi

if [ -z "$(setup_config_get GIT_NAME)" ] && [ -n "$(setup_config_get GH_USER)" ] \
   && command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  echo "  Looking for existing setup-emacs-mac.conf in GitHub repos..."
  _GH_USER="$(setup_config_get GH_USER)"
  _DATA_REPO_NAME=""
  _REPOS="$(gh api "user/repos?sort=pushed&direction=desc" --paginate --jq '.[].name' 2>/dev/null)" || true
  _BEST_DATE=""
  for _SCAN_REPO in $_REPOS; do
    _SCAN_DATE="$(gh api "repos/$_GH_USER/$_SCAN_REPO/commits?path=config/setup-emacs-mac.conf&per_page=1" \
      --jq '.[0].commit.committer.date' 2>/dev/null)" || true
    if [ -n "$_SCAN_DATE" ] && { [ -z "$_BEST_DATE" ] || [[ "$_SCAN_DATE" > "$_BEST_DATE" ]]; }; then
      _BEST_DATE="$_SCAN_DATE"
      _DATA_REPO_NAME="$_SCAN_REPO"
    fi
  done
  if [ -n "$_DATA_REPO_NAME" ]; then
    _CONF_CONTENT="$(gh api "repos/$_GH_USER/$_DATA_REPO_NAME/contents/config/setup-emacs-mac.conf" --jq '.content' 2>/dev/null)" || true
    if [ -n "$_CONF_CONTENT" ]; then
      _CONF_TMP="$(mktemp)"
      echo "$_CONF_CONTENT" | tr -d '\n' | python3 -c "import sys,base64; sys.stdout.buffer.write(base64.b64decode(sys.stdin.read()))" > "$_CONF_TMP" 2>/dev/null || true
      if grep -q '^GIT_NAME="[^"]' "$_CONF_TMP" 2>/dev/null; then
        cp "$_CONF_TMP" "$SETUP_CONFIG"
        echo "  Loaded existing config from $_GH_USER/$_DATA_REPO_NAME."
      fi
      rm -f "$_CONF_TMP"
    fi
  fi
  unset _GH_USER _DATA_REPO_NAME _REPOS _BEST_DATE _SCAN_REPO _SCAN_DATE _CONF_CONTENT _CONF_TMP
  setup_load_config
fi

setup_print_inventory

setup_phase "Phase 2/5: Resolve setup data"
setup_prompt_config_if_empty GIT_NAME            "Full name (git commits)"                     ""
setup_prompt_config_if_empty GIT_EMAIL           "Email (git commits)"                         ""
setup_prompt_config_if_empty GH_USER             "GitHub username (Enter for local-only mode)"  ""
setup_prompt_config_if_empty GH_REPO             "Emacs data repo"                             "emacs-data"

setup_load_config

if [ -n "${GH_USER:-}" ]; then
  setup_prompt_config_if_empty BW_FIELD            "Bitwarden custom field name"                  "Key"
  setup_prompt_config_if_empty BW_ITEM             "git-crypt Bitwarden item name"                "emacs-git-crypt-key"
  setup_prompt_config_if_empty BW_GH_ITEM          "GitHub token Bitwarden item name"             "github-cli-token"
  setup_prompt_config_if_empty BW_ANTHROPIC_ITEM   "Anthropic key Bitwarden item name"            "anthropic-api-key"
  setup_prompt_config_if_empty BW_GEMINI_ITEM      "Gemini key Bitwarden item name"               "gemini-api-key"
  setup_prompt_config_if_empty BW_KEYCHAIN_SERVICE "macOS Keychain service label"                 "bitwarden-master"
  setup_load_config

  setup_require_config GIT_NAME GIT_EMAIL GH_REPO BW_FIELD BW_ITEM BW_GH_ITEM BW_GEMINI_ITEM BW_KEYCHAIN_SERVICE
  setup_prompt_config_if_empty BW_EMAIL "Bitwarden email" ""
  setup_load_config
  setup_require_config BW_EMAIL

  setup_phase "Phase 3/5: Validate Bitwarden and secrets"
  setup_install_bitwarden_tools

  if [ -z "$(setup_keychain_get)" ] || [ "$REPAIR_MODE" = "bitwarden" ]; then
    echo ""
    echo "  Bitwarden master password is stored in macOS Keychain for future setup runs."
    _BW_MASTER="$(setup_prompt_secret "Bitwarden master password")"
    setup_keychain_set "$_BW_MASTER" || setup_fail "Could not store Bitwarden password in macOS Keychain." "bash ~/emacs-mac-setup/setup-intake.sh --repair bitwarden"
    unset _BW_MASTER
  fi

  setup_bw_unlock_with_keychain || exit 1
  setup_state_set BITWARDEN_LOGIN_OK true
  echo "  Bitwarden vault unlocked."

  _existing_gh="$(setup_bw_get_field "$BW_GH_ITEM" "$BW_FIELD")"
  if [ -z "$_existing_gh" ] || [ "$REPAIR_MODE" = "github-token" ]; then
    echo ""
    echo "  GitHub token is optional here; if skipped, setup falls back to browser login."
    _GH_TOKEN="$(setup_prompt_secret "GitHub token (repo scope, Enter to skip)")"
    [ -n "$_GH_TOKEN" ] && setup_bw_create_item "$BW_GH_ITEM" "$BW_FIELD" "$_GH_TOKEN"
    unset _GH_TOKEN
  fi

  _existing_gc="$(setup_bw_get_field "$BW_ITEM" "$BW_FIELD")"
  if [ -z "$_existing_gc" ]; then
    echo "  git-crypt key missing — generating one now."
    command -v git-crypt >/dev/null 2>&1 || brew install git-crypt
    _GC_TMP="$(mktemp -d)"
    git -C "$_GC_TMP" init -q
    (cd "$_GC_TMP" && git crypt init) 2>/dev/null
    (cd "$_GC_TMP" && git crypt export-key /tmp/gckey_bs)
    _GC_KEY="$(base64 -i /tmp/gckey_bs | tr -d '\n')"
    rm -f /tmp/gckey_bs
    rm -rf "$_GC_TMP"
    setup_bw_create_item "$BW_ITEM" "$BW_FIELD" "$_GC_KEY"
    unset _GC_KEY _GC_TMP
  fi

  _existing_gemini="$(setup_bw_get_field "$BW_GEMINI_ITEM" "$BW_FIELD")"
  if [ -z "$_existing_gemini" ] || [ "$REPAIR_MODE" = "gemini" ]; then
    echo ""
    echo "  Gemini is the default gptel backend. Get a free key at:"
    echo "  https://aistudio.google.com/apikey"
    _GEMINI_KEY="$(setup_prompt_secret "Gemini API key (Enter to skip)")"
    [ -n "$_GEMINI_KEY" ] && setup_bw_create_item "$BW_GEMINI_ITEM" "$BW_FIELD" "$_GEMINI_KEY"
    unset _GEMINI_KEY
  fi

  _existing_anthropic="$(setup_bw_get_field "$BW_ANTHROPIC_ITEM" "$BW_FIELD")"
  if [ -z "$_existing_anthropic" ] || [ "$REPAIR_MODE" = "anthropic" ]; then
    echo ""
    _ANTHROPIC_KEY="$(setup_prompt_secret "Anthropic API key (optional, Enter to skip)")"
    [ -n "$_ANTHROPIC_KEY" ] && setup_bw_create_item "$BW_ANTHROPIC_ITEM" "$BW_FIELD" "$_ANTHROPIC_KEY"
    unset _ANTHROPIC_KEY
  fi

  unset _existing_gh _existing_gc _existing_gemini _existing_anthropic
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
