#!/bin/bash
# Emacs-for-Mac — opinionated preconfigured Emacs distro.
# One curl, one command, done:
#
#   curl -fsSL https://raw.githubusercontent.com/deno1011/emacs-mac-setup/main/install.sh | /bin/bash
#
# After this runs you have:
#   - emacs-plus installed
#   - ~/.emacs.d  -> symlink to the distro's emacs.d/   (updates via `git pull`)
#   - ~/emacs/    -> example wiki + GTD agenda + TOUR.org (your data from here on)
#   - ~/.emacs.d/secrets.el -> template; uncomment one method to add your API keys
#
# Re-running install.sh is idempotent. It pulls latest distro code and never
# overwrites ~/emacs/ or ~/.emacs.d/secrets.el once they exist.

set -e

REPO_URL="${EMACS_MAC_REPO_URL:-https://github.com/deno1011/emacs-mac-setup.git}"
BRANCH="${EMACS_MAC_BRANCH:-main}"
SRC_DIR="${EMACS_MAC_SRC_DIR:-$HOME/emacs-mac-setup-src}"
EMACS_D="$HOME/.emacs.d"
# Override DATA_DIR per-Mac with EMACS_DATA_DIR=<path>. init.el reads the
# same env var so the installer's seed location and Emacs's runtime data
# root stay in sync. For GUI Emacs (launched from Finder/Dock), also run:
#   launchctl setenv EMACS_DATA_DIR "<path>"
DATA_DIR="${EMACS_DATA_DIR:-$HOME/emacs}"

echo "==> Emacs-for-Mac installer"
echo "    repo:    $REPO_URL  (branch: $BRANCH)"
echo "    distro:  $SRC_DIR"
echo "    config:  $EMACS_D (-> $SRC_DIR/emacs.d)"
echo "    data:    $DATA_DIR$([ -n "${EMACS_DATA_DIR:-}" ] && echo "  (from EMACS_DATA_DIR)")"
echo ""

# 1. Homebrew --------------------------------------------------------------
if ! command -v brew &>/dev/null; then
  echo "==> Installing Homebrew (sudo once)..."
  sudo -v
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
[ -f /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
[ -f /usr/local/bin/brew ]    && eval "$(/usr/local/bin/brew shellenv)"

# 2. emacs-plus ------------------------------------------------------------
EMACS_FORMULA="${EMACS_FORMULA:-emacs-plus@30}"
EMACS_BREW_ARGS="${EMACS_BREW_ARGS:---with-xwidgets}"

if ! brew list --formula "$EMACS_FORMULA" &>/dev/null; then
  echo "==> Installing $EMACS_FORMULA $EMACS_BREW_ARGS (this takes ~10 minutes on first install)..."
  brew tap d12frosted/emacs-plus 2>/dev/null || true
  # shellcheck disable=SC2086
  brew install "$EMACS_FORMULA" $EMACS_BREW_ARGS
fi

# Symlink the actual installed .app into /Applications so macOS sees it.
# (Re-run is idempotent: ln -sfn replaces an existing symlink; a stale
# broken symlink from an earlier install also gets cleaned up here.)
EMACS_APP_SRC="$(brew --prefix "$EMACS_FORMULA")/Emacs.app"
if [ ! -d "$EMACS_APP_SRC" ]; then
  echo "ERROR: $EMACS_APP_SRC not found after `brew install $EMACS_FORMULA`."
  echo "       Run `brew reinstall $EMACS_FORMULA $EMACS_BREW_ARGS` and re-run install.sh."
  exit 1
fi

EMACS_APP_DST="/Applications/Emacs.app"
# If destination is a real (non-symlink) directory, leave it alone — the
# user has a separately installed Emacs.app we shouldn't overwrite.
if [ -d "$EMACS_APP_DST" ] && [ ! -L "$EMACS_APP_DST" ]; then
  echo "==> $EMACS_APP_DST is a real directory; symlinking into ~/Applications/ instead."
  EMACS_APP_DST="$HOME/Applications/Emacs.app"
  mkdir -p "$HOME/Applications"
fi
# Replace any existing symlink (stale or pointing at the wrong version).
if [ -L "$EMACS_APP_DST" ] || [ ! -e "$EMACS_APP_DST" ]; then
  ln -sfn "$EMACS_APP_SRC" "$EMACS_APP_DST" 2>/dev/null \
    || { EMACS_APP_DST="$HOME/Applications/Emacs.app"; \
         mkdir -p "$HOME/Applications"; \
         ln -sfn "$EMACS_APP_SRC" "$EMACS_APP_DST"; }
  echo "==> Symlink $EMACS_APP_DST -> $EMACS_APP_SRC"
fi

# Register the .app with LaunchServices so Spotlight / Launchpad /
# "Open With" find it immediately. Without this, the app shows up only
# after the next logout.
LSREG="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
if [ -x "$LSREG" ]; then
  "$LSREG" -f "$EMACS_APP_DST" 2>/dev/null || true
  echo "==> Registered with LaunchServices ($EMACS_APP_DST)"
fi

# 3. Clone or update the distro -------------------------------------------
if [ -d "$SRC_DIR/.git" ]; then
  echo "==> Updating $SRC_DIR (branch: $BRANCH)..."
  git -C "$SRC_DIR" fetch origin "$BRANCH"
  git -C "$SRC_DIR" checkout "$BRANCH"
  git -C "$SRC_DIR" pull --ff-only origin "$BRANCH"
else
  echo "==> Cloning distro to $SRC_DIR..."
  git clone --branch "$BRANCH" "$REPO_URL" "$SRC_DIR"
fi

# 4. Symlink ~/.emacs.d -> $SRC_DIR/emacs.d --------------------------------
if [ -L "$EMACS_D" ]; then
  current_target="$(readlink "$EMACS_D")"
  if [ "$current_target" != "$SRC_DIR/emacs.d" ]; then
    echo "==> Re-pointing $EMACS_D from $current_target to $SRC_DIR/emacs.d"
    ln -sfn "$SRC_DIR/emacs.d" "$EMACS_D"
  fi
elif [ -e "$EMACS_D" ]; then
  backup="$EMACS_D.backup-$(date +%s)"
  echo "==> Existing $EMACS_D is a real directory; backing up to $backup"
  mv "$EMACS_D" "$backup"
  ln -s "$SRC_DIR/emacs.d" "$EMACS_D"
else
  ln -s "$SRC_DIR/emacs.d" "$EMACS_D"
fi

# 5. Seed starter data + secrets template (first install only) -------------
FIRST_INSTALL=0
if [ ! -d "$DATA_DIR" ]; then
  echo "==> First install — seeding starter data to $DATA_DIR/"
  mkdir -p "$DATA_DIR/data"
  cp -R "$SRC_DIR/starter-data/wiki" "$DATA_DIR/wiki"
  cp -R "$SRC_DIR/starter-data/org"  "$DATA_DIR/data/org"
  cp    "$SRC_DIR/starter-data/TOUR.org" "$DATA_DIR/TOUR.org"
  FIRST_INSTALL=1
fi

# secrets.el is per-Mac, never overwritten on update
if [ ! -e "$SRC_DIR/emacs.d/secrets.el" ]; then
  cp "$SRC_DIR/emacs.d/secrets.el.template" "$SRC_DIR/emacs.d/secrets.el"
fi

# First-install marker so init.el opens TOUR.org once
[ "$FIRST_INSTALL" = "1" ] && touch "$SRC_DIR/emacs.d/.first-install"

# 6. Done ------------------------------------------------------------------
echo ""
echo "======================================================================"
echo "Done."
echo "======================================================================"
echo "  Config:    $EMACS_D  ->  $SRC_DIR/emacs.d"
echo "  Data:      $DATA_DIR"
echo "  Secrets:   $SRC_DIR/emacs.d/secrets.el  (edit to add API keys)"
echo ""
if [ "$FIRST_INSTALL" = "1" ]; then
  echo "  First launch: TOUR.org will open automatically — a guided tour"
  echo "  of the wiki, agenda, gptel chat, and key bindings."
fi
echo ""
echo "  Update later:   bash $SRC_DIR/install.sh"
echo "  Uninstall:      bash $SRC_DIR/uninstall.sh"
echo "======================================================================"
open -a Emacs
