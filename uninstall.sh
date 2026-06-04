#!/bin/bash
# Reverses install.sh.
#
# Default behaviour: removes the .emacs.d symlink, the distro source
# clone, the Emacs.app bundle/registration, and the emacs-plus formula.
#
# Your data in ~/emacs/ (wiki, GTD, notes) is preserved unless you pass
# --purge-data — that's the only irreversible thing, so opting in is
# required.
#
# Pass --keep-emacs-app if you want to keep Emacs Plus.app + the brew formula
# (e.g., you only want to drop the distro config and switch to a
# different Emacs config).

set -e

EMACS_FORMULA="${EMACS_FORMULA:-emacs-plus@30}"
EMACS_APP_NAME="${EMACS_APP_NAME:-Emacs Plus}"
SRC_DIR="${EMACS_MAC_SRC_DIR:-$HOME/emacs-mac-setup-src}"
EMACS_D="$HOME/.emacs.d"
DATA_DIR="${EMACS_DATA_DIR:-$HOME/emacs}"

emacs_app_bundle_id() {
  local plist="$1/Contents/Info.plist"
  [ -f "$plist" ] || return 1

  plutil -extract CFBundleIdentifier raw "$plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist" 2>/dev/null \
    || defaults read "$plist" CFBundleIdentifier 2>/dev/null
}

emacs_unregister_app() {
  local app="$1"
  [ -e "$app" ] || return 0

  local lsreg="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
  [ -x "$lsreg" ] && "$lsreg" -u "$app" 2>/dev/null || true
  mdimport "$app" 2>/dev/null || true
}

emacs_remove_app_if_ours() {
  local app="$1" bundle_id=""
  [ -e "$app" ] || return 0

  emacs_unregister_app "$app"

  if [ -L "$app" ]; then
    echo "==> Removing symlink $app"
    rm "$app"
  elif [ -d "$app" ]; then
    bundle_id="$(emacs_app_bundle_id "$app" || true)"
    case "$bundle_id" in
      org.gnu.Emacs|"")
        echo "==> Removing Emacs app bundle $app"
        rm -rf "$app"
        ;;
      *)
        echo "==> Leaving third-party app $app ($bundle_id)"
        ;;
    esac
  fi
}

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
  - /Applications/$EMACS_APP_NAME.app  (or \$HOME/Applications/$EMACS_APP_NAME.app)
  - the $EMACS_FORMULA brew formula

Preserved unless --purge-data is passed:
  - $DATA_DIR  (your wiki, agenda, notes)
  - secrets.el (per-Mac, was inside the distro clone — gone with it)

Flags:
  --keep-emacs-app  leave $EMACS_APP_NAME.app + brew formula intact
  --purge-data      ALSO delete $DATA_DIR (irreversible; asks for confirmation)

Env vars (mirror install.sh):
  EMACS_FORMULA      brew formula to remove   (default: emacs-plus@30)
  EMACS_APP_NAME     app bundle display name   (default: Emacs Plus)
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

# 3. Emacs app bundle + brew formula (default) -----------------------------
if [ "$KEEP_EMACS_APP" = "0" ]; then
  [ -f /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
  [ -f /usr/local/bin/brew ]    && eval "$(/usr/local/bin/brew shellenv)"

  # Unregister and remove app bundles so Finder / Spotlight / Launchpad
  # no longer show stale Emacs icons.  Include historical names from the
  # stable setup as well as the current generic bundle name.
  for app in \
    "/Applications/$EMACS_APP_NAME.app" \
    "$HOME/Applications/$EMACS_APP_NAME.app" \
    "/Applications/Emacs Plus.app" \
    "$HOME/Applications/Emacs Plus.app" \
    /Applications/Emacs.app \
    "$HOME/Applications/Emacs.app" \
    "/Applications/Plus Emacs.app" \
    "$HOME/Applications/Plus Emacs.app" \
    "/Applications/Emacs (emacs-plus).app" \
    "$HOME/Applications/Emacs (emacs-plus).app"; do
    emacs_remove_app_if_ours "$app"
  done

  # Homebrew may also have registered the Cellar/opt bundle directly.
  if command -v brew &>/dev/null && brew list --formula "$EMACS_FORMULA" &>/dev/null; then
    emacs_unregister_app "$(brew --prefix "$EMACS_FORMULA")/Emacs.app"
  fi

  if command -v brew &>/dev/null; then
    if brew list --formula "$EMACS_FORMULA" &>/dev/null; then
      echo "==> brew uninstall $EMACS_FORMULA"
      brew uninstall "$EMACS_FORMULA"
    else
      echo "==> $EMACS_FORMULA not installed via Homebrew — skipping uninstall"
    fi
  fi

  # Refresh Launchpad's persistent cache after unregister/removal.
  killall Dock 2>/dev/null || true
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
[ "$KEEP_EMACS_APP" = "1" ] && echo "  $EMACS_APP_NAME.app + $EMACS_FORMULA preserved (--keep-emacs-app)."
[ "$PURGE_DATA"     = "0" ] && [ -d "$DATA_DIR" ] && \
  echo "  Your data at $DATA_DIR is preserved. To remove later: rm -rf '$DATA_DIR'"
echo "  Homebrew untouched. To remove: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)\""
