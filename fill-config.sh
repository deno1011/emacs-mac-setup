#!/bin/bash
# Interactively fill in setup-emacs-mac.conf
# Can be run standalone at any time: bash ~/fill-config.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$HOME/setup-emacs-mac.conf"
TEMPLATE="$SCRIPT_DIR/setup-emacs-mac.conf.template"

if [ ! -f "$CONFIG_FILE" ]; then
  if [ -f "$TEMPLATE" ]; then
    cp "$TEMPLATE" "$CONFIG_FILE"
  else
    echo "ERROR: Neither config nor template found in ~/. Run bootstrap.sh first."
    exit 1
  fi
fi

set_value() {
  local KEY="$1"
  local PROMPT="$2"
  local DEFAULT="$3"
  local CURRENT
  CURRENT=$(grep "^${KEY}=" "$CONFIG_FILE" | sed 's/^[^=]*=["'"'"']\{0,1\}\(.*\)["'"'"']\{0,1\}$/\1/' | tr -d '"')

  local SHOW="${CURRENT:-$DEFAULT}"
  printf "  %-58s [%s]: " "$PROMPT" "$SHOW"
  read -r INPUT

  if [ -n "$INPUT" ]; then
    # User typed a new value — save it
    sed -i '' "s|^${KEY}=.*|${KEY}=\"${INPUT}\"|" "$CONFIG_FILE"
  elif [ -z "$CURRENT" ] && [ -n "$DEFAULT" ]; then
    # No existing value — apply default
    sed -i '' "s|^${KEY}=.*|${KEY}=\"${DEFAULT}\"|" "$CONFIG_FILE"
  fi
  # Existing value + Enter pressed → keep unchanged
}

echo ""
echo "Fill in setup-emacs-mac.conf"
echo "============================"
echo "Press Enter to keep the value shown in [brackets]."
echo ""

echo "Git identity (used in commit messages):"
set_value GIT_NAME  "Full name          (e.g. Jane Smith)"        ""
set_value GIT_EMAIL "Email              (e.g. jane@example.com)"  ""

echo ""
echo "GitHub (leave GH_USER empty for local mode — no GitHub sync):"
set_value GH_USER   "GitHub username    (e.g. janedoe)"           ""
set_value GH_REPO   "Emacs config repo  (e.g. emacs-config)"      "emacs-config"
set_value CONF_REPO "Private conf repo  (e.g. mac-setup-conf)"    "mac-setup-conf"

echo ""
echo "Advanced — Bitwarden item and field names (press Enter to keep defaults):"
set_value BW_FIELD           "Bitwarden field    (custom field name in all BW entries)" "Key"
set_value BW_ITEM            "git-crypt item     (Bitwarden entry name)"                "emacs-git-crypt-key"
set_value BW_GH_ITEM         "GitHub token item  (Bitwarden entry name)"               "github-cli-token"
set_value BW_ANTHROPIC_ITEM  "Anthropic key item (Bitwarden entry name)"               "anthropic-api-key"
set_value BW_KEYCHAIN_SERVICE "Keychain service  (macOS Keychain label)"               "bitwarden-master"

echo ""
echo "=============================="
echo "Config saved to $CONFIG_FILE"
echo ""
grep -E "^(GIT_NAME|GIT_EMAIL|GH_USER|GH_REPO|CONF_REPO)=" "$CONFIG_FILE"
echo ""
