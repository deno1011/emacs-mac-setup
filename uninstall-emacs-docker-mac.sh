#!/bin/bash

# Usage: bash uninstall-emacs-docker-mac.sh [--ask]
# --ask  Prompt before removing each brew package installed by the setup

_ASK=false
[ "${1:-}" = "--ask" ] && _ASK=true

_pkg_remove() {
  local TYPE="$1" PKG="$2"
  case "$TYPE" in
    formula) brew list --formula "$PKG" &>/dev/null || { echo "    $PKG not installed — skipping."; return; } ;;
    cask)    brew list --cask "$PKG" &>/dev/null || { echo "    $PKG not installed — skipping."; return; } ;;
  esac
  if [ "$_ASK" = true ]; then
    printf "  Remove %s '%s'? [y/N] " "$TYPE" "$PKG"
    read -r _REPLY < /dev/tty
    case "$_REPLY" in y|Y) ;; *) echo "    Skipped."; return ;; esac
  fi
  case "$TYPE" in
    formula) brew uninstall --ignore-dependencies "$PKG" 2>/dev/null && echo "    $PKG removed." || echo "    $PKG not found." ;;
    cask)    brew uninstall --cask "$PKG" 2>/dev/null && echo "    $PKG removed." || echo "    $PKG not found." ;;
  esac
}

# --- Load configuration ---
CONFIG_FILE="$HOME/setup-emacs-mac.conf"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "ERROR: Config file not found: $CONFIG_FILE"
  exit 1
fi
source "$CONFIG_FILE"

if [ -d "/Applications/Utilities/XQuartz.app" ]; then
  echo "==> Enter admin password (once, for XQuartz uninstall):"
  read -rs ADMIN_PASS
  echo ""
fi

echo "==> Stopping and removing Docker container..."
docker rm -f "$DOCKER_CONTAINER" 2>/dev/null && echo "    Container removed." || echo "    No container found."

echo "==> Removing Docker image..."
docker rmi "$DOCKER_IMAGE" 2>/dev/null && echo "    Image removed." || echo "    No image found."

echo "==> Removing Docker volume..."
docker volume rm "$DOCKER_VOLUME" 2>/dev/null && echo "    Volume removed." || echo "    No volume found."

echo "==> Removing hello-world image..."
docker rmi hello-world 2>/dev/null || true

echo "==> Stopping Colima..."
colima stop 2>/dev/null && echo "    Colima stopped." || echo "    Colima was not running."

echo "==> Uninstalling Docker CLI..."
_pkg_remove formula docker
_pkg_remove formula colima

if [ -d "/Applications/Utilities/XQuartz.app" ]; then
  echo "==> Uninstalling XQuartz..."
  echo "$ADMIN_PASS" | sudo -S rm -rf /Applications/Utilities/XQuartz.app
  echo "$ADMIN_PASS" | sudo -S rm -rf /opt/homebrew/Caskroom/xquartz
fi

echo "==> Removing project directory..."
rm -rf ~/emacs-docker && echo "    ~/emacs-docker removed." || echo "    ~/emacs-docker not found."

echo "==> Removing Emacs app bundles..."
rm -rf ~/Applications/"GUI Docker Emacs.app" && echo "    GUI Docker Emacs removed." || echo "    GUI Docker Emacs not found."
rm -rf ~/Applications/"Console Docker Emacs.app" && echo "    Console Docker Emacs removed." || echo "    Console Docker Emacs not found."
rm -rf ~/Applications/"Shell Docker Emacs.app" && echo "    Shell Docker Emacs removed." || echo "    Shell Docker Emacs not found."
rm -rf ~/Applications/"Root Shell Docker Emacs.app" && echo "    Root Shell Docker Emacs removed." || echo "    Root Shell Docker Emacs not found."

echo "==> Removing emacs alias from ~/.zshrc..."
sed -i '' '/# Emacs in Docker/,/^}/d' ~/.zshrc && echo "    Alias removed." || echo "    Alias not found."

echo "==> Removing iCloud repo..."
ICLOUD_REPO_PATH="$HOME/Library/Mobile Documents/com~apple~CloudDocs/$GH_REPO"
rm -rf "$ICLOUD_REPO_PATH" && echo "    iCloud repo removed." || echo "    iCloud repo not found."

echo "==> Removing iCloud symlink..."
rm -f "$HOME/.emacs-icloud-repo" || true

echo "    Bitwarden keychain entry preserved — to remove: ~/remove-bitwarden-keychain.sh"

echo "==> Removing brew packages installed by setup..."
_pkg_remove formula bitwarden-cli
_pkg_remove formula gh
_pkg_remove formula git-crypt

echo "==> Logging out GitHub CLI..."
gh auth logout --hostname github.com 2>/dev/null && echo "    gh auth removed." || echo "    gh not authenticated."

echo "==> Clearing global git identity..."
git config --global --unset user.email 2>/dev/null && echo "    git email cleared." || echo "    git email not set."
git config --global --unset user.name 2>/dev/null && echo "    git name cleared." || echo "    git name not set."

echo "==> Cleaning Homebrew cache..."
rm -f ~/Library/Caches/Homebrew/downloads/*.incomplete
brew cleanup 2>/dev/null || true

echo ""
echo "Uninstall complete. Environment is clean."
echo "The setup script remains at: ~/setup-emacs-docker-mac.sh"
echo "The config file remains at:  ~/setup-emacs-mac.conf"
