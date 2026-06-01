#!/bin/bash
# Interactively fill in setup-emacs-mac.conf
# Can be run standalone at any time: bash ~/fill-config.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$HOME/emacs-mac-setup/setup-emacs-mac.conf"
TEMPLATE="$SCRIPT_DIR/setup-emacs-mac.conf.template"

if [ ! -f "$CONFIG_FILE" ]; then
  if [ -f "$TEMPLATE" ]; then
    cp "$TEMPLATE" "$CONFIG_FILE"
  else
    echo "ERROR: Neither config nor template found in ~/. Run bootstrap.sh first."
    exit 1
  fi
fi

_get_value() {
  grep "^${1}=" "$CONFIG_FILE" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"'
}

# Ask only if not set. Saves immediately on input.
ask_value() {
  local KEY="$1" PROMPT="$2" DEFAULT="$3"
  local CURRENT
  CURRENT=$(_get_value "$KEY")

  if [ -n "$CURRENT" ]; then
    _ASKED_NOTHING=true  # value already set, no prompt needed
    return
  fi

  _HAD_MISSING=true
  printf "  %-58s [%s]: " "$PROMPT" "$DEFAULT"
  read -r INPUT < /dev/tty

  local VALUE="${INPUT:-$DEFAULT}"
  [ -n "$VALUE" ] && sed -i '' "s|^${KEY}=.*|${KEY}=\"${VALUE}\"|" "$CONFIG_FILE"
}

_HAD_MISSING=false
_ASKED_NOTHING=false

ask_value GIT_NAME            "Full name          (e.g. Jane Smith)"                   ""
ask_value GIT_EMAIL           "Email              (e.g. jane@example.com)"             ""
ask_value GH_USER             "GitHub username    (e.g. janedoe)"                      ""
ask_value GH_REPO             "Emacs config repo  (e.g. emacs-data)"                   "emacs-data"
ask_value BW_FIELD            "Bitwarden field    (custom field name in all BW entries)" "Key"
ask_value BW_ITEM             "git-crypt item     (Bitwarden entry name)"              "emacs-git-crypt-key"
ask_value BW_GH_ITEM          "GitHub token item  (Bitwarden entry name)"              "github-cli-token"
ask_value BW_ANTHROPIC_ITEM   "Anthropic key item (Bitwarden entry name)"              "anthropic-api-key"
ask_value BW_GEMINI_ITEM      "Gemini key item    (Bitwarden entry name, free tier OK)" "gemini-api-key"
ask_value BW_KEYCHAIN_SERVICE "Keychain service   (macOS Keychain label)"              "bitwarden-master"

if [ "$_HAD_MISSING" = true ]; then
  echo ""
  echo "  Config saved to $CONFIG_FILE"
  echo ""
  grep -E "^(GIT_NAME|GIT_EMAIL|GH_USER|GH_REPO)=" "$CONFIG_FILE"
  echo ""

  # Sync conf to the data repo's config/ subfolder if available
  _GH_REPO=$(_get_value "GH_REPO"); _GH_REPO="${_GH_REPO:-emacs-data}"
  _DATA_DIR="$HOME/$_GH_REPO"
  if [ -d "$_DATA_DIR/config" ]; then
    cp "$CONFIG_FILE" "$_DATA_DIR/config/setup-emacs-mac.conf"
    git -C "$_DATA_DIR" add "config/setup-emacs-mac.conf" 2>/dev/null || true
    git -C "$_DATA_DIR" commit -m "chore: update setup-emacs-mac.conf" 2>/dev/null || true
    echo "  Synced to ~/$_GH_REPO/config/setup-emacs-mac.conf"
  fi
  unset _GH_REPO _DATA_DIR
fi
