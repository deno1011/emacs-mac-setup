#!/bin/bash
# Reverses install.sh. Removes symlinks and the distro source clone.
# Your data in ~/emacs/ and your secrets in ~/.emacs.d/secrets.el are
# NEVER touched unless you pass --purge-data.

set -e

SRC_DIR="${EMACS_MAC_SRC_DIR:-$HOME/emacs-mac-setup-src}"
EMACS_D="$HOME/.emacs.d"
DATA_DIR="$HOME/emacs"

PURGE_DATA=0
PURGE_EMACS_APP=0
for arg in "$@"; do
  case "$arg" in
    --purge-data)       PURGE_DATA=1 ;;
    --purge-emacs-app)  PURGE_EMACS_APP=1 ;;
    -h|--help)
      cat <<EOF
Usage: bash uninstall.sh [--purge-data] [--purge-emacs-app]

Without flags: removes the .emacs.d symlink + clone of the distro
source. Leaves your data (~/emacs/) and Emacs.app in place.

  --purge-data       also delete ~/emacs/ (your wiki, agenda, notes)
  --purge-emacs-app  also uninstall emacs-plus via Homebrew
EOF
      exit 0
      ;;
  esac
done

# 1. Remove ~/.emacs.d symlink (back up if it's a real dir somehow)
if [ -L "$EMACS_D" ]; then
  echo "==> Removing $EMACS_D symlink"
  rm "$EMACS_D"
elif [ -d "$EMACS_D" ]; then
  backup="$EMACS_D.uninstalled-$(date +%s)"
  echo "==> $EMACS_D is a real directory; moving to $backup"
  mv "$EMACS_D" "$backup"
fi

# 2. Remove distro source clone
if [ -d "$SRC_DIR" ]; then
  echo "==> Removing distro source at $SRC_DIR"
  rm -rf "$SRC_DIR"
fi

# 3. Optional: purge user data
if [ "$PURGE_DATA" = "1" ] && [ -d "$DATA_DIR" ]; then
  echo "==> --purge-data: removing $DATA_DIR (THIS DELETES YOUR WIKI + AGENDA)"
  printf "    Type 'yes' to confirm: "
  read -r confirm < /dev/tty
  if [ "$confirm" = "yes" ]; then
    rm -rf "$DATA_DIR"
    echo "    deleted."
  else
    echo "    skipped (no confirmation)."
  fi
fi

# 4. Optional: uninstall emacs-plus
if [ "$PURGE_EMACS_APP" = "1" ]; then
  echo "==> --purge-emacs-app: uninstalling emacs-plus via Homebrew"
  brew uninstall emacs-plus 2>/dev/null || true
  rm -f /Applications/Emacs.app "$HOME/Applications/Emacs.app" 2>/dev/null || true
fi

echo ""
echo "Done. Emacs.app and Homebrew untouched (unless --purge-emacs-app was passed)."
echo "Your data at $DATA_DIR is preserved (unless --purge-data was passed)."
