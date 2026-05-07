#!/bin/bash

CONFIG_FILE="$HOME/setup-emacs-mac.conf"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "ERROR: Konfigurationsdatei nicht gefunden: $CONFIG_FILE"
  exit 1
fi
source "$CONFIG_FILE"

echo "==> Removing Bitwarden keychain entry..."
echo "    Account:  $BW_KEYCHAIN_ACCOUNT"
echo "    Service:  $BW_KEYCHAIN_SERVICE"
echo ""
read -rp "Wirklich löschen? (j/N): " CONFIRM
if [ "$CONFIRM" != "j" ] && [ "$CONFIRM" != "J" ]; then
  echo "Abgebrochen."
  exit 0
fi

security delete-generic-password -a "$BW_KEYCHAIN_ACCOUNT" -s "$BW_KEYCHAIN_SERVICE" 2>/dev/null \
  && echo "    Keychain entry removed." \
  || echo "    No keychain entry found."
