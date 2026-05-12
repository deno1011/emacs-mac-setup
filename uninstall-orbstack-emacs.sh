#!/bin/zsh
# uninstall-orbstack-emacs.sh
# Removes the OrbStack Emacs machine and its launchers.
# Does NOT uninstall OrbStack itself (other machines may exist).
# Usage: bash uninstall-orbstack-emacs.sh [--ask]
# --ask  Prompt before each optional step (delete machine, remove OrbStack)

set -euo pipefail

_ASK=false
[[ "${1:-}" == "--ask" ]] && _ASK=true

MACHINE="emacs-orb"
APPS_DIR="$HOME/Applications"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
step() { print -P "\n${GREEN}==> $1${NC}"; }
warn() { print -P "${YELLOW}WARNING: $1${NC}"; }

# ── stop & delete machine ─────────────────────────────────────────────────────
if [[ "$_ASK" == true ]]; then
    echo "This will DELETE the OrbStack machine '$MACHINE' and all its data."
    echo "Your emacs-config git repo data is safe (it's in GitHub)."
    read "_REPLY?Proceed? (yes/no): " < /dev/tty
    [[ "$_REPLY" == "yes" ]] || { echo "Aborted."; exit 0; }
fi

step "Stopping machine '$MACHINE'..."
orb stop "$MACHINE" 2>/dev/null || warn "Machine was not running."

step "Deleting machine '$MACHINE'..."
orb delete "$MACHINE" 2>/dev/null || warn "Machine not found — already deleted?"

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

print -P "\n${GREEN}✓ OrbStack Emacs uninstalled.${NC}"
