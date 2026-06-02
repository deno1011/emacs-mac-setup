#!/bin/bash

CONFIG_FILE="$HOME/emacs-mac-setup/setup-emacs-mac.conf"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "ERROR: Config file not found: $CONFIG_FILE"
  exit 1
fi
source "$CONFIG_FILE"

MACOS_KEYCHAIN_ACCOUNT="${MACOS_KEYCHAIN_ACCOUNT:-$USER}"
BW_KEYCHAIN_SERVICE="${BW_KEYCHAIN_SERVICE:-bitwarden-master}"

echo "==> Removing Bitwarden keychain entry..."
echo "    Account:  $MACOS_KEYCHAIN_ACCOUNT"
echo "    Service:  $BW_KEYCHAIN_SERVICE"
echo ""
read -rp "Really delete? (y/N): " CONFIRM
if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
  echo "Aborted."
  exit 0
fi

security delete-generic-password -a "$MACOS_KEYCHAIN_ACCOUNT" -s "$BW_KEYCHAIN_SERVICE" 2>/dev/null \
  && echo "    Keychain entry removed." \
  || echo "    No keychain entry found."
