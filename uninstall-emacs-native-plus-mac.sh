#!/bin/bash

# Usage: bash uninstall-emacs-native-plus-mac.sh [--ask]
# --ask  Prompt before removing each brew package (setup packages + config.org packages)

_ASK=false
[ "${1:-}" = "--ask" ] && _ASK=true

_pkg_remove() {
  local TYPE="$1" PKG="$2"
  case "$TYPE" in
    formula) brew list --formula "$PKG" &>/dev/null || { echo "    $PKG not installed — skipping."; return; } ;;
    cask)    brew list --cask "$PKG" &>/dev/null || { echo "    $PKG not installed — skipping."; return; } ;;
    pip)     pip3 show "$PKG" &>/dev/null || { echo "    $PKG not installed — skipping."; return; } ;;
  esac
  if [ "$_ASK" = true ]; then
    printf "  Remove %s '%s'? [y/N] " "$TYPE" "$PKG"
    read -r _REPLY < /dev/tty
    case "$_REPLY" in y|Y) ;; *) echo "    Skipped."; return ;; esac
  fi
  case "$TYPE" in
    formula) brew uninstall --ignore-dependencies "$PKG" 2>/dev/null && echo "    $PKG removed." || echo "    $PKG not found." ;;
    cask)    brew uninstall --cask "$PKG" 2>/dev/null && echo "    $PKG removed." || echo "    $PKG not found." ;;
    pip)     pip3 uninstall -y "$PKG" 2>/dev/null && echo "    $PKG removed." || echo "    $PKG not found." ;;
  esac
}

# --- Check Emacs version ---
echo "==> Emacs check..."
YAMAMOTO_INSTALLED=false
if brew list emacs-mac@30exp &>/dev/null 2>&1; then
  YAMAMOTO_INSTALLED=true
  echo "  NOTE: emacs-mac@30exp (Yamamoto) is also installed — keeping it."
fi
if ! brew list | grep -q "emacs-plus@30"; then
  echo "  emacs-plus@30 is not installed — nothing to do."
fi

# Returns 0 (true) if any other Emacs variant is still installed after this removal
_other_emacs_installed() {
  brew list emacs-mac@30exp &>/dev/null 2>&1 && return 0
  [ -d "$HOME/Applications/GUI Docker Emacs.app" ]   && return 0
  [ -d "$HOME/Applications/GUI OrbStack Emacs.app" ] && return 0
  return 1
}

# --- Load configuration ---
CONFIG_FILE="$HOME/emacs-mac-setup/setup-emacs-mac.conf"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "ERROR: Config file not found: $CONFIG_FILE"
  exit 1
fi
source "$CONFIG_FILE"

ICLOUD_REPO_PATH="$HOME/Library/Mobile Documents/com~apple~CloudDocs/$GH_REPO"
SYMLINK="$HOME/$GH_REPO"

echo "==> Removing Emacs (emacs-plus)..."
brew uninstall emacs-plus@30 2>/dev/null && echo "    emacs-plus@30 removed." || echo "    emacs-plus@30 not found."
rm -rf "/Applications/Plus Emacs.app" "/Applications/Emacs (emacs-plus).app" 2>/dev/null && echo "    Plus Emacs.app removed." || echo "    Plus Emacs.app not found."

if ! _other_emacs_installed; then
  echo "==> Removing ~/.emacs.d (init.el, secrets.el, packages)..."
  rm -rf "$HOME/.emacs.d" && echo "    ~/.emacs.d removed." || echo "    ~/.emacs.d not found."

  echo "==> Removing symlink ~/emacs-data..."
  rm -f "$SYMLINK" && echo "    Symlink removed." || echo "    Symlink not found."

  echo "==> Preserving data repo — your org files and config are safe."
  echo "    Location: $ICLOUD_REPO_PATH"
  echo "    To fully remove later: rm -rf \"$ICLOUD_REPO_PATH\""

  echo "    Bitwarden keychain entry preserved — to remove: ~/remove-bitwarden-keychain.sh"

  echo "==> Logging out GitHub CLI..."
  gh auth logout --hostname github.com 2>/dev/null && echo "    gh auth removed." || echo "    gh auth not set."

  echo "==> Removing brew packages installed by setup..."
  _pkg_remove formula bitwarden-cli
  _pkg_remove formula gh
  _pkg_remove formula git-crypt

  # Remove packages that config.org installed (tracked in system-packages.log)
  _LOG="$HOME/.emacs.d/system-packages.log"
  if [ -f "$_LOG" ]; then
    echo "==> Removing packages installed by Emacs/config.org..."
    while IFS=: read -r _TYPE _PKG; do
      [ -z "$_TYPE" ] || [ -z "$_PKG" ] && continue
      _pkg_remove "$_TYPE" "$_PKG"
    done < "$_LOG"
    rm -f "$_LOG"
  fi

  echo "==> Clearing global git identity..."
  git config --global --unset user.email 2>/dev/null && echo "    git email cleared." || echo "    git email not set."
  git config --global --unset user.name 2>/dev/null && echo "    git name cleared." || echo "    git name not set."
else
  echo "  Another Emacs variant still installed — keeping shared resources (gh, emacs.d, iCloud repo)."
  if [ "$YAMAMOTO_INSTALLED" = "true" ]; then
    echo "  Linking emacs-mac@30exp as the active version..."
    brew link --overwrite emacs-mac@30exp 2>/dev/null || true
  fi
fi

echo ""
echo "Uninstall complete."
echo "Config and org files remain safely on GitHub."
echo "Setup scripts remain at: ~/setup-emacs-native-plus-mac.sh"
