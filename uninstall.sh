#!/bin/bash
# Reverses install.sh.
#
# Default behaviour: removes the .emacs.d symlink, the distro source
# clone, the /Applications/Emacs.app symlink, and the emacs-plus formula.
#
# Your data in ~/emacs/ (wiki, GTD, notes) is preserved unless you pass
# --purge-data — that's the only irreversible thing, so opting in is
# required.
#
# Pass --keep-emacs-app if you want to keep Emacs.app + the brew formula
# (e.g., you only want to drop the distro config and switch to a
# different Emacs config).

set -e

EMACS_FORMULA="${EMACS_FORMULA:-emacs-plus@30}"
SRC_DIR="${EMACS_MAC_SRC_DIR:-$HOME/emacs-mac-setup-src}"
EMACS_D="$HOME/.emacs.d"
DATA_DIR="${EMACS_DATA_DIR:-$HOME/emacs}"

KEEP_EMACS_APP=0
PURGE_DATA=0
for arg in "$@"; do
  case "$arg" in
    --keep-emacs-app) KEEP_EMACS_APP=1 ;;
    --purge-data)     PURGE_DATA=1 ;;
    -h|--help)
      cat <<EOF
Usage: bash uninstall.sh [--keep-emacs-app] [--purge-data]

Reverses install.sh. By default removes:
  - $EMACS_D                 (symlink to the distro)
  - $SRC_DIR                 (distro source clone)
  - /Applications/Emacs.app  (or \$HOME/Applications/Emacs.app)
  - the $EMACS_FORMULA brew formula

Preserved unless --purge-data is passed:
  - $DATA_DIR  (your wiki, agenda, notes)
  - secrets.el (per-Mac, was inside the distro clone — gone with it)

Flags:
  --keep-emacs-app  leave Emacs.app + brew formula intact
  --purge-data      ALSO delete $DATA_DIR (irreversible; asks for confirmation)

Env vars (mirror install.sh):
  EMACS_FORMULA      brew formula to remove   (default: emacs-plus@30)
  EMACS_MAC_SRC_DIR  distro clone path        (default: \$HOME/emacs-mac-setup-src)
  EMACS_DATA_DIR     user data root           (default: \$HOME/emacs)

Homebrew itself is never removed.
EOF
      exit 0
      ;;
  esac
done

echo "==> Uninstalling Emacs-for-Mac distro"
echo "    config:  $EMACS_D"
echo "    distro:  $SRC_DIR"
echo "    data:    $DATA_DIR  $([ "$PURGE_DATA" = "1" ] && echo '(will be removed)' || echo '(preserved)')"
echo "    Emacs:   $([ "$KEEP_EMACS_APP" = "1" ] && echo 'preserved (--keep-emacs-app)' || echo 'will be removed')"
echo ""

# 1. ~/.emacs.d symlink ---------------------------------------------------
if [ -L "$EMACS_D" ]; then
  echo "==> Removing $EMACS_D symlink"
  rm "$EMACS_D"
elif [ -d "$EMACS_D" ]; then
  backup="$EMACS_D.uninstalled-$(date +%s)"
  echo "==> $EMACS_D is a real directory; moving to $backup"
  mv "$EMACS_D" "$backup"
fi

# 2. Distro source clone --------------------------------------------------
# (This is also where secrets.el lived — gone with the clone.)
if [ -d "$SRC_DIR" ]; then
  echo "==> Removing distro source at $SRC_DIR"
  rm -rf "$SRC_DIR"
fi

# 3. Emacs.app + brew formula (default) -----------------------------------
if [ "$KEEP_EMACS_APP" = "0" ]; then
  [ -f /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
  [ -f /usr/local/bin/brew ]    && eval "$(/usr/local/bin/brew shellenv)"

  # Unregister from LaunchServices first so Spotlight forgets the app
  # immediately, then remove the symlinks and the formula.
  LSREG="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
  for app in /Applications/Emacs.app "$HOME/Applications/Emacs.app"; do
    if [ -L "$app" ] || [ -d "$app" ]; then
      [ -x "$LSREG" ] && "$LSREG" -u "$app" 2>/dev/null || true
      if [ -L "$app" ]; then
        echo "==> Removing symlink $app"
        rm "$app"
      else
        backup="$app.uninstalled-$(date +%s)"
        echo "==> $app is a real directory; moving to $backup"
        mv "$app" "$backup"
      fi
    fi
  done

  if command -v brew &>/dev/null; then
    if brew list --formula "$EMACS_FORMULA" &>/dev/null; then
      echo "==> brew uninstall $EMACS_FORMULA"
      brew uninstall "$EMACS_FORMULA"
    else
      echo "==> $EMACS_FORMULA not installed via Homebrew — skipping uninstall"
    fi
  fi
fi

# 4. Purge user data (opt-in, destructive) --------------------------------
if [ "$PURGE_DATA" = "1" ] && [ -d "$DATA_DIR" ]; then
  echo ""
  echo "==> --purge-data: removing $DATA_DIR"
  echo "    THIS DELETES YOUR WIKI, AGENDA, AND NOTES. NO BACKUP."
  printf "    Type 'yes' to confirm: "
  read -r confirm < /dev/tty
  if [ "$confirm" = "yes" ]; then
    rm -rf "$DATA_DIR"
    echo "    deleted."
  else
    echo "    skipped (no confirmation)."
  fi
fi

echo ""
echo "======================================================================"
echo "Done."
echo "======================================================================"
[ "$KEEP_EMACS_APP" = "1" ] && echo "  Emacs.app + $EMACS_FORMULA preserved (--keep-emacs-app)."
[ "$PURGE_DATA"     = "0" ] && [ -d "$DATA_DIR" ] && \
  echo "  Your data at $DATA_DIR is preserved. To remove later: rm -rf '$DATA_DIR'"
echo "  Homebrew untouched. To remove: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)\""
