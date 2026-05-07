#!/bin/bash

# --- Emacs-Version prüfen ---
echo "==> Emacs-Check..."
PLUS_INSTALLED=false
if brew list | grep -q "emacs-plus"; then
  PLUS_INSTALLED=true
  echo "  HINWEIS: emacs-plus ist ebenfalls installiert — bleibt erhalten."
fi
if ! brew list emacs-mac@30exp &>/dev/null 2>&1; then
  echo "  emacs-mac@30exp ist nicht installiert — nichts zu tun."
fi

# --- Konfiguration laden ---
CONFIG_FILE="$HOME/setup-emacs-mac.conf"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "ERROR: Konfigurationsdatei nicht gefunden: $CONFIG_FILE"
  exit 1
fi
source "$CONFIG_FILE"

ICLOUD_REPO_PATH="$HOME/Library/Mobile Documents/com~apple~CloudDocs/$GH_REPO"
SYMLINK="$HOME/$GH_REPO"

echo "==> Removing Emacs (emacs-mac@30exp)..."
brew uninstall emacs-mac@30exp 2>/dev/null && echo "    emacs-mac@30exp removed." || echo "    emacs-mac@30exp not found."
brew untap railwaycat/emacsmacport 2>/dev/null || true
rm -rf "/Applications/Emacs (Yamamoto).app" 2>/dev/null && echo "    Emacs (Yamamoto).app removed." || echo "    Emacs (Yamamoto).app not found."

if [ "$PLUS_INSTALLED" = false ]; then
  echo "==> Removing ~/.emacs.d (init.el, secrets.el, packages)..."
  rm -rf "$HOME/.emacs.d" && echo "    ~/.emacs.d removed." || echo "    ~/.emacs.d not found."

  echo "==> Removing symlink ~/emacs-config..."
  rm -f "$SYMLINK" && echo "    Symlink removed." || echo "    Symlink not found."

  echo "==> Removing iCloud repo..."
  rm -rf "$ICLOUD_REPO_PATH" && echo "    iCloud repo removed." || echo "    iCloud repo not found."

  echo "    Bitwarden keychain entry bleibt erhalten — zum Löschen: ~/remove-bitwarden-keychain.sh"

  echo "==> Logging out GitHub CLI..."
  gh auth logout --hostname github.com 2>/dev/null && echo "    gh auth removed." || echo "    gh auth not set."

  echo "==> Removing brew packages installed by setup..."
  brew uninstall --ignore-dependencies bitwarden-cli 2>/dev/null && echo "    bitwarden-cli removed." || echo "    bitwarden-cli not found."
  brew uninstall --ignore-dependencies gh 2>/dev/null && echo "    gh removed." || echo "    gh not found."
  brew uninstall --ignore-dependencies git-crypt 2>/dev/null && echo "    git-crypt removed." || echo "    git-crypt not found."

  echo "==> Clearing global git identity..."
  git config --global --unset user.email 2>/dev/null && echo "    git email cleared." || echo "    git email not set."
  git config --global --unset user.name 2>/dev/null && echo "    git name cleared." || echo "    git name not set."
else
  echo "  Shared resources (~/emacs.d, iCloud repo, packages) bleiben erhalten (emacs-plus noch installiert)."
  echo "  emacs-plus wird als aktive Version verlinkt..."
  brew link --overwrite emacs-plus 2>/dev/null || true
fi

echo ""
echo "Uninstall complete."
echo "Config and org files remain safely on GitHub."
echo "Setup scripts remain at: ~/setup-emacs-native-yamamoto-mac.sh"
