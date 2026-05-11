#!/bin/bash
set -e

CONFIG_FILE="$HOME/setup-emacs-mac.conf"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "ERROR: $CONFIG_FILE not found. Run bootstrap.sh first."
  exit 1
fi
source "$CONFIG_FILE"

ICLOUD_REPO_PATH="$HOME/Library/Mobile Documents/com~apple~CloudDocs/$GH_REPO"
SECRETS_REPO="$ICLOUD_REPO_PATH/emacs.d/secrets.el"
EMACS_SECRETS="$HOME/.emacs.d/secrets.el"

if [ -z "$GH_USER" ]; then
  echo "ERROR: GH_USER not set — Bitwarden not configured in local mode."
  exit 1
fi

mkdir -p "$HOME/.emacs.d"

if [ -f "$SECRETS_REPO" ] && grep -q "setenv" "$SECRETS_REPO" 2>/dev/null; then
  echo "==> secrets.el im Repo verfügbar (git-crypt entschlüsselt) — Symlink anlegen..."
  if [ -L "$EMACS_SECRETS" ] && [ "$(readlink "$EMACS_SECRETS")" = "$SECRETS_REPO" ]; then
    echo "==> Already done: secrets.el symlink — skipping."
  else
    [ -e "$EMACS_SECRETS" ] && rm "$EMACS_SECRETS"
    ln -sf "$SECRETS_REPO" "$EMACS_SECRETS"
    echo "    Symlink: $EMACS_SECRETS → $SECRETS_REPO"
  fi
else
  echo "==> Repo-Datei fehlt oder verschlüsselt — Key aus Bitwarden holen..."
  if ! command -v bw &>/dev/null; then
    echo "ERROR: Bitwarden CLI nicht installiert. Zuerst ~/setup-bitwarden.sh ausführen."
    exit 1
  fi
  source "$HOME/bw-unlock.sh"
  bw_ensure_session || exit 1
  ANTHROPIC_API_KEY=$(bw_get_field "$BW_ANTHROPIC_ITEM" "$BW_ANTHROPIC_FIELD")
  if [ -z "$ANTHROPIC_API_KEY" ]; then
    echo "ERROR: Key nicht in Bitwarden (item: $BW_ANTHROPIC_ITEM, field: $BW_ANTHROPIC_FIELD)."
    echo "       Eintrag anlegen und erneut ausführen."
    exit 1
  fi
  printf '(setenv "ANTHROPIC_API_KEY" "%s")\n' "$ANTHROPIC_API_KEY" > "$EMACS_SECRETS"
  echo "==> secrets.el nach $EMACS_SECRETS geschrieben."
  echo "    Emacs neu starten damit die Änderung wirksam wird."
fi
