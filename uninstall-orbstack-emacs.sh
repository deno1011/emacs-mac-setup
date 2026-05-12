#!/bin/zsh
# uninstall-orbstack-emacs.sh
# Removes the OrbStack Emacs machine and its launchers.
# Does NOT uninstall OrbStack itself (other machines may exist).

set -euo pipefail

MACHINE="emacs-orb"
APPS_DIR="$HOME/Applications"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
step() { print -P "\n${GREEN}==> $1${NC}"; }
warn() { print -P "${YELLOW}WARNING: $1${NC}"; }

# ── confirm ───────────────────────────────────────────────────────────────────
echo "This will DELETE the OrbStack machine '$MACHINE' and all its data."
echo "Your emacs-config git repo data is safe (it's in GitHub)."
echo ""
read "CONFIRM?Type YES to continue: "
[[ "$CONFIRM" == "YES" ]] || { echo "Aborted."; exit 0; }

# ── stop & delete machine ─────────────────────────────────────────────────────
step "Stopping machine '$MACHINE'..."
orb stop "$MACHINE" 2>/dev/null || warn "Machine was not running."

step "Deleting machine '$MACHINE'..."
orb delete "$MACHINE" 2>/dev/null || warn "Machine not found — already deleted?"

# ── remove app bundles ────────────────────────────────────────────────────────
step "Removing app bundles..."
rm -rf "$APPS_DIR/Emacs OrbStack GUI.app"
rm -rf "$APPS_DIR/Emacs OrbStack Console.app"
rm -rf "$APPS_DIR/Emacs OrbStack Shell.app"
rm -rf "$APPS_DIR/Emacs OrbStack Root Shell.app"
# also clean up any old .command files from a previous install
rm -f "$APPS_DIR/Emacs OrbStack GUI.command" \
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
echo ""
read "REMOVE_ORB?Remove OrbStack itself too? (yes/no): "
if [[ "$REMOVE_ORB" == "yes" ]]; then
    step "Uninstalling OrbStack..."
    brew uninstall --cask orbstack || warn "Could not uninstall via brew — remove manually from Applications."
else
    echo "OrbStack kept. You can manage it from its menu bar icon."
fi

print -P "\n${GREEN}✓ OrbStack Emacs uninstalled.${NC}"
