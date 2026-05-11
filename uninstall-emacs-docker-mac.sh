#!/bin/bash

# --- Konfiguration laden ---
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
brew uninstall docker 2>/dev/null || true

if [ -d "/Applications/Utilities/XQuartz.app" ]; then
  echo "==> Uninstalling XQuartz..."
  echo "$ADMIN_PASS" | sudo -S rm -rf /Applications/Utilities/XQuartz.app
  echo "$ADMIN_PASS" | sudo -S rm -rf /opt/homebrew/Caskroom/xquartz
fi

echo "==> Removing project directory..."
rm -rf ~/emacs-docker && echo "    ~/emacs-docker removed." || echo "    ~/emacs-docker not found."

echo "==> Removing Emacs app bundles..."
rm -rf ~/Applications/"Emacs Docker GUI.app" && echo "    Emacs Docker GUI removed." || echo "    Emacs Docker GUI not found."
rm -rf ~/Applications/"Emacs Docker Console.app" && echo "    Emacs Docker Console removed." || echo "    Emacs Docker Console not found."
rm -rf ~/Applications/"Emacs Docker Shell.app" && echo "    Emacs Docker Shell removed." || echo "    Emacs Docker Shell not found."
rm -rf ~/Applications/"Emacs Docker Root Shell.app" && echo "    Emacs Docker Root Shell removed." || echo "    Emacs Docker Root Shell not found."

echo "==> Removing emacs alias from ~/.zshrc..."
sed -i '' '/# Emacs in Docker/,/^}/d' ~/.zshrc && echo "    Alias removed." || echo "    Alias not found."

echo "==> Removing iCloud repo..."
ICLOUD_REPO_PATH="$HOME/Library/Mobile Documents/com~apple~CloudDocs/$GH_REPO"
rm -rf "$ICLOUD_REPO_PATH" && echo "    iCloud repo removed." || echo "    iCloud repo not found."

echo "==> Removing iCloud symlink..."
rm -f "$HOME/.emacs-icloud-repo" || true

echo "    Bitwarden keychain entry preserved — to remove: ~/remove-bitwarden-keychain.sh"

echo "==> Removing brew packages installed by setup..."
brew uninstall --ignore-dependencies bitwarden-cli 2>/dev/null && echo "    bitwarden-cli removed." || echo "    bitwarden-cli not found."
brew uninstall --ignore-dependencies gh 2>/dev/null && echo "    gh removed." || echo "    gh not found."
brew uninstall --ignore-dependencies git-crypt 2>/dev/null && echo "    git-crypt removed." || echo "    git-crypt not found."

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
