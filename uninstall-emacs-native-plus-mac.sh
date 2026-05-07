#!/bin/bash

# --- Emacs-Version prüfen ---
echo "==> Emacs-Check..."
YAMAMOTO_INSTALLED=false
if brew list emacs-mac@30exp &>/dev/null 2>&1; then
  YAMAMOTO_INSTALLED=true
  echo "  HINWEIS: emacs-mac@30exp (Yamamoto) ist ebenfalls installiert — bleibt erhalten."
fi
if ! brew list | grep -q "emacs-plus@30"; then
  echo "  emacs-plus@30 ist nicht installiert — nichts zu tun."
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

echo "==> Removing Emacs (emacs-plus)..."
brew uninstall emacs-plus@30 2>/dev/null && echo "    emacs-plus@30 removed." || echo "    emacs-plus@30 not found."
rm -rf "/Applications/Emacs (emacs-plus).app" 2>/dev/null && echo "    Emacs (emacs-plus).app removed." || echo "    Emacs (emacs-plus).app not found."

if [ "$YAMAMOTO_INSTALLED" = false ]; then
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

  # Remove packages that config.org installed (tracked in system-packages.log)
  _LOG="$HOME/.emacs.d/system-packages.log"
  if [ -f "$_LOG" ]; then
    echo "==> Removing packages installed by Emacs/config.org..."
    while IFS=: read -r _TYPE _PKG; do
      [ -z "$_TYPE" ] || [ -z "$_PKG" ] && continue
      case "$_TYPE" in
        formula) brew uninstall --ignore-dependencies "$_PKG" 2>/dev/null && echo "    $_PKG removed." || echo "    $_PKG not found." ;;
        cask)    brew uninstall --cask "$_PKG" 2>/dev/null && echo "    $_PKG removed." || echo "    $_PKG not found." ;;
      esac
    done < "$_LOG"
    rm -f "$_LOG"
  fi

  echo "==> Clearing global git identity..."
  git config --global --unset user.email 2>/dev/null && echo "    git email cleared." || echo "    git email not set."
  git config --global --unset user.name 2>/dev/null && echo "    git name cleared." || echo "    git name not set."
else
  echo "  Shared resources (~/emacs.d, iCloud repo, packages) bleiben erhalten (Yamamoto noch installiert)."
  echo "  emacs-mac@30exp wird als aktive Version verlinkt..."
  brew link --overwrite emacs-mac@30exp 2>/dev/null || true
fi

echo ""
echo "Uninstall complete."
echo "Config and org files remain safely on GitHub."
echo "Setup scripts remain at: ~/setup-emacs-native-plus-mac.sh"
