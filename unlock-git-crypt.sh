#!/bin/bash
set -e

CONFIG_FILE="$HOME/setup-emacs-mac.conf"
source "$CONFIG_FILE"

ICLOUD_REPO_PATH="$HOME/Library/Mobile Documents/com~apple~CloudDocs/$GH_REPO"

echo "==> Bitwarden entsperren..."
if ! command -v bw &>/dev/null; then
  echo "ERROR: Bitwarden CLI nicht installiert (brew install bitwarden-cli)"
  exit 1
fi

BW_MASTER=$(security find-generic-password -a "$BW_KEYCHAIN_ACCOUNT" -s "$BW_KEYCHAIN_SERVICE" -w 2>/dev/null) || true
if [ -z "$BW_MASTER" ]; then
  echo "==> Bitwarden Master-Passwort eingeben:"
  read -rs BW_MASTER
  echo ""
fi

BW_STATUS=$(bw status 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('status','unauthenticated'))" 2>/dev/null || echo "unauthenticated")
export _BW_MASTER="$BW_MASTER"
if [ "$BW_STATUS" = "unauthenticated" ]; then
  echo "==> Bitwarden: Erstanmeldung auf diesem Mac..."
  printf "  Bitwarden E-Mail: "
  read -r BW_EMAIL
  BW_SESSION=$(bw login "$BW_EMAIL" --passwordenv _BW_MASTER --raw 2>/dev/null) || true
  if [ -z "$BW_SESSION" ]; then
    echo "  Auto-Login fehlgeschlagen (2FA oder falsche Zugangsdaten) — interaktiver Login:"
    unset _BW_MASTER
    bw login
    export _BW_MASTER="$BW_MASTER"
    BW_SESSION=$(bw unlock --passwordenv _BW_MASTER --raw 2>/dev/null) || true
  fi
fi
if [ -z "$BW_SESSION" ]; then
  BW_SESSION=$(bw unlock --passwordenv _BW_MASTER --raw 2>/dev/null) || true
fi
unset _BW_MASTER

if [ -z "$BW_SESSION" ]; then
  echo "ERROR: Bitwarden konnte nicht entsperrt werden."
  exit 1
fi
export BW_SESSION
bw sync --session "$BW_SESSION" &>/dev/null || true

echo "==> git-crypt Key aus Bitwarden holen (Feld: $BW_FIELD)..."
GC_KEY=$(bw get item "$BW_ITEM" --session "$BW_SESSION" 2>/dev/null \
  | python3 -c "import sys,json;d=json.load(sys.stdin);fields=d.get('fields',[]);key=[f['value'] for f in fields if f['name']=='${BW_FIELD}'];print(key[0].strip() if key else '')") || true

if [ -z "$GC_KEY" ]; then
  echo "ERROR: git-crypt Key nicht gefunden in Bitwarden (Item: $BW_ITEM, Feld: $BW_FIELD)"
  exit 1
fi

echo "==> git-crypt Repo entsperren..."
echo "$GC_KEY" | tr -d '[:space:]' | python3 -c "import sys,base64; data=sys.stdin.read().strip(); sys.stdout.buffer.write(base64.b64decode(data + '=='))" > /tmp/gckey
git -C "$ICLOUD_REPO_PATH" crypt unlock /tmp/gckey
rm -f /tmp/gckey

echo ""
echo "==> Ergebnis:"
head -c 30 "$ICLOUD_REPO_PATH/org/inbox.org" 2>/dev/null && echo "" || true
echo "Fertig! org/ Dateien sind jetzt entschlüsselt."
