#!/bin/zsh
# uninstall-emacs-orbstack-mac.sh
# Removes the OrbStack Emacs machine and its launchers.
# Does NOT uninstall OrbStack itself (other machines may exist).
# Usage: bash uninstall-emacs-orbstack-mac.sh [--ask]
# --ask  Prompt before each optional step (delete machine, remove OrbStack)

set -euo pipefail

_ASK=false
[[ "${1:-}" == "--ask" ]] && _ASK=true

MACHINE="emacs-orb"
APPS_DIR="$HOME/Applications"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
step() { print -P "\n${GREEN}==> $1${NC}"; }
warn() { print -P "${YELLOW}WARNING: $1${NC}"; }

_pkg_remove() {
  local TYPE="$1" PKG="$2"
  case "$TYPE" in
    formula) brew list --formula "$PKG" &>/dev/null || { echo "    $PKG not installed — skipping."; return; } ;;
    cask)    brew list --cask "$PKG" &>/dev/null || { echo "    $PKG not installed — skipping."; return; } ;;
    pip)     pip3 show "$PKG" &>/dev/null || { echo "    $PKG not installed — skipping."; return; } ;;
  esac
  if [[ "$_ASK" == true ]]; then
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

# Returns 0 (true) if any other Emacs variant is still installed after this removal
_other_emacs_installed() {
  brew list emacs-plus@30 &>/dev/null 2>&1           && return 0
  brew list emacs-mac@30exp &>/dev/null 2>&1         && return 0
  [[ -d "$HOME/Applications/GUI Docker Emacs.app" ]] && return 0
  return 1
}

# ── stop & delete machine ─────────────────────────────────────────────────────
if [[ "$_ASK" == true ]]; then
    echo "This will DELETE the OrbStack machine '$MACHINE' and all its data."
    echo "Your emacs-config git repo data is safe (it's in GitHub)."
    read "_REPLY?Proceed? (yes/no): " < /dev/tty
    [[ "$_REPLY" == "yes" ]] || { echo "Aborted."; exit 0; }
fi

step "Deleting machine '$MACHINE'..."
orb delete --force "$MACHINE" 2>/dev/null || warn "Machine not found — already deleted?"

# ── remove app bundles ────────────────────────────────────────────────────────
step "Removing app bundles..."
rm -rf "$APPS_DIR/GUI OrbStack Emacs.app"
rm -rf "$APPS_DIR/Console OrbStack Emacs.app"
rm -rf "$APPS_DIR/Shell OrbStack Emacs.app"
rm -rf "$APPS_DIR/Root Shell OrbStack Emacs.app"
# also clean up old names from previous installs
rm -rf "$APPS_DIR/Emacs OrbStack GUI.app" \
       "$APPS_DIR/Emacs OrbStack Console.app" \
       "$APPS_DIR/Emacs OrbStack Shell.app" \
       "$APPS_DIR/Emacs OrbStack Root Shell.app"
rm -f  "$APPS_DIR/Emacs OrbStack GUI.command" \
       "$APPS_DIR/Emacs OrbStack Console.command" \
       "$APPS_DIR/Emacs OrbStack Shell.command" \
       "$APPS_DIR/Emacs OrbStack Root Shell.command"

# ── remove alias ──────────────────────────────────────────────────────────────
step "Removing shell alias..."
if grep -q "emacs-orb" ~/.zshrc 2>/dev/null; then
    sed -i '' '/emacs-orb/d' ~/.zshrc
    echo "Removed alias from ~/.zshrc"
fi

# ── optionally uninstall OrbStack ─────────────────────────────────────────────
if [[ "$_ASK" == true ]]; then
    read "_REPLY?Remove OrbStack itself too? (yes/no): " < /dev/tty
    if [[ "$_REPLY" == "yes" ]]; then
        step "Uninstalling OrbStack..."
        brew uninstall --cask orbstack || warn "Could not uninstall via brew — remove manually from Applications."
    else
        echo "OrbStack kept."
    fi
fi

# ── load config and remove shared resources if last variant ───────────────────
CONFIG_FILE="$HOME/emacs-mac-setup/setup-emacs-mac.conf"
[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"

if ! _other_emacs_installed; then
  step "Removing iCloud repo..."
  ICLOUD_REPO_PATH="$HOME/Library/Mobile Documents/com~apple~CloudDocs/$GH_REPO"
  rm -rf "$ICLOUD_REPO_PATH" && echo "    iCloud repo removed." || echo "    iCloud repo not found."

  step "Removing ~/.emacs.d..."
  rm -rf "$HOME/.emacs.d" && echo "    ~/.emacs.d removed." || echo "    ~/.emacs.d not found."

  echo "    Bitwarden keychain entry preserved — to remove: ~/remove-bitwarden-keychain.sh"

  step "Logging out GitHub CLI..."
  gh auth logout --hostname github.com 2>/dev/null && echo "    gh auth removed." || echo "    gh auth not set."

  step "Removing brew packages installed by setup..."
  _pkg_remove formula bitwarden-cli
  _pkg_remove formula gh
  _pkg_remove formula git-crypt

  step "Clearing global git identity..."
  git config --global --unset user.email 2>/dev/null && echo "    git email cleared." || echo "    git email not set."
  git config --global --unset user.name 2>/dev/null && echo "    git name cleared." || echo "    git name not set."
else
  echo "  Another Emacs variant still installed — keeping shared resources (gh, emacs.d, iCloud repo)."
fi

print -P "\n${GREEN}✓ OrbStack Emacs uninstalled.${NC}"
