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

# Ask for KEY only if not already set. Saves immediately on input.
ask_value() {
  local KEY="$1"
  local PROMPT="$2"
  local DEFAULT="$3"
  local CURRENT
  CURRENT=$(grep "^${KEY}=" "$CONFIG_FILE" | sed 's/^[^=]*=["'"'"']\{0,1\}\(.*\)["'"'"']\{0,1\}$/\1/' | tr -d '"')

  if [ -n "$CURRENT" ]; then
    printf "  %-30s %s\n" "$KEY:" "$CURRENT"
    return
  fi

  local SHOW="${DEFAULT}"
  printf "  %-58s [%s]: " "$PROMPT" "$SHOW"
  read -r INPUT < /dev/tty

  local VALUE="${INPUT:-$DEFAULT}"
  if [ -n "$VALUE" ]; then
    sed -i '' "s|^${KEY}=.*|${KEY}=\"${VALUE}\"|" "$CONFIG_FILE"
  fi
}

echo ""
echo "Fill in setup-emacs-mac.conf"
echo "============================"
echo "Already set values are shown and skipped."
echo ""

echo "Git identity (used in commit messages):"
ask_value GIT_NAME  "Full name          (e.g. Jane Smith)"        ""
ask_value GIT_EMAIL "Email              (e.g. jane@example.com)"  ""

echo ""
echo "GitHub (leave GH_USER empty for local mode — no GitHub sync):"
ask_value GH_USER   "GitHub username    (e.g. janedoe)"           ""
ask_value GH_REPO   "Emacs config repo  (e.g. emacs-config)"      "emacs-config"
ask_value CONF_REPO "Private conf repo  (e.g. mac-setup-conf)"    "mac-setup-conf"

echo ""
echo "Advanced — Bitwarden item and field names:"
ask_value BW_FIELD            "Bitwarden field    (custom field name in all BW entries)" "Key"
ask_value BW_ITEM             "git-crypt item     (Bitwarden entry name)"                "emacs-git-crypt-key"
ask_value BW_GH_ITEM          "GitHub token item  (Bitwarden entry name)"               "github-cli-token"
ask_value BW_ANTHROPIC_ITEM   "Anthropic key item (Bitwarden entry name)"               "anthropic-api-key"
ask_value BW_KEYCHAIN_SERVICE "Keychain service   (macOS Keychain label)"               "bitwarden-master"

echo ""
echo "=============================="
echo "Config saved to $CONFIG_FILE"
echo ""
grep -E "^(GIT_NAME|GIT_EMAIL|GH_USER|GH_REPO|CONF_REPO)=" "$CONFIG_FILE"
echo ""
