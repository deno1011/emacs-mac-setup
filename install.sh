#!/bin/bash
# Emacs-for-Mac — opinionated preconfigured Emacs distro.
# One curl, one command, done:
#
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/deno1011/emacs-mac-setup/main/install.sh)"
#
# NOTE: do NOT pipe via `curl ... | bash`. During the 10-25 min `brew install
# emacs-plus@30 --with-xwidgets` build, cmake/configure can read stdin and
# consume bytes from the same pipe bash is reading the script from — bash
# then hits EOF mid-script and exits cleanly. `bash -c "$(...)"` passes the
# script as a string argument, keeping bash's stdin free.
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
trap 'echo "" >&2; echo "==> install.sh FAILED at line $LINENO: $BASH_COMMAND" >&2; echo "    Re-run with: bash -x ~/emacs-mac-setup-src/install.sh 2>&1 | tee /tmp/install.log" >&2' ERR

REPO_URL="${EMACS_MAC_REPO_URL:-https://github.com/deno1011/emacs-mac-setup.git}"
BRANCH="${EMACS_MAC_BRANCH:-main}"
SRC_DIR="${EMACS_MAC_SRC_DIR:-$HOME/emacs-mac-setup-src}"
EMACS_D="$HOME/.emacs.d"
EMACS_APP_NAME="${EMACS_APP_NAME:-Emacs Plus}"
# Override DATA_DIR per-Mac with EMACS_DATA_DIR=<path>. init.el reads the
# same env var so the installer's seed location and Emacs's runtime data
# root stay in sync. For GUI Emacs (launched from Finder/Dock), also run:
#   launchctl setenv EMACS_DATA_DIR "<path>"
DATA_DIR="${EMACS_DATA_DIR:-$HOME/emacs}"

emacs_app_bundle_id() {
  local plist="$1/Contents/Info.plist"
  [ -f "$plist" ] || return 1

  plutil -extract CFBundleIdentifier raw "$plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist" 2>/dev/null \
    || defaults read "$plist" CFBundleIdentifier 2>/dev/null
}

echo "==> Emacs-for-Mac installer"
echo "    repo:    $REPO_URL  (branch: $BRANCH)"
echo "    distro:  $SRC_DIR"
echo "    config:  $EMACS_D (-> $SRC_DIR/emacs.d)"
echo "    data:    $DATA_DIR$([ -n "${EMACS_DATA_DIR:-}" ] && echo "  (from EMACS_DATA_DIR)")"
echo "    app:     $EMACS_APP_NAME.app"
echo ""

# 1. Homebrew --------------------------------------------------------------
if ! command -v brew &>/dev/null; then
  echo "==> Installing Homebrew (sudo once)..."
  sudo -v
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
# Activate brew for THIS script — Apple Silicon: /opt/homebrew, Intel: /usr/local
[ -f /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
[ -f /usr/local/bin/brew ]    && eval "$(/usr/local/bin/brew shellenv)"

# Persist brew in shell profile so future shells (and `brew upgrade emacs-plus@30`
# later) find it without re-running install.sh. Intel wins if both prefixes exist
# (rare), matching bootstrap.sh's behaviour on main.
_BREW_SHELLENV_LINE='eval "$(/opt/homebrew/bin/brew shellenv)"'
if [ -f /usr/local/bin/brew ]; then
  _BREW_SHELLENV_LINE='eval "$(/usr/local/bin/brew shellenv)"'
fi
for _PROFILE in "$HOME/.zprofile" "$HOME/.bash_profile"; do
  if [ -f "$_PROFILE" ] || [ "$_PROFILE" = "$HOME/.zprofile" ]; then
    if ! grep -qF 'brew shellenv' "$_PROFILE" 2>/dev/null; then
      echo "" >> "$_PROFILE"
      echo "# Homebrew" >> "$_PROFILE"
      echo "$_BREW_SHELLENV_LINE" >> "$_PROFILE"
      echo "==> Added brew to $(basename "$_PROFILE")"
    fi
  fi
done
unset _BREW_SHELLENV_LINE _PROFILE

# 2. emacs-plus ------------------------------------------------------------
EMACS_FORMULA="${EMACS_FORMULA:-emacs-plus@30}"
EMACS_BREW_ARGS="${EMACS_BREW_ARGS:---with-xwidgets}"

if ! brew list --formula "$EMACS_FORMULA" &>/dev/null; then
  echo "==> Installing $EMACS_FORMULA $EMACS_BREW_ARGS (this takes ~10 minutes on first install)..."
  brew tap d12frosted/emacs-plus 2>/dev/null || true
  # shellcheck disable=SC2086
  brew install "$EMACS_FORMULA" $EMACS_BREW_ARGS
fi

# Place the actual .app bundle in /Applications using `ditto` — Apple's
# recommended tool for copying .app bundles (preserves metadata, code
# signatures, extended attributes, resource forks). Symlinks satisfy
# LaunchServices but DON'T reliably populate Launchpad's icon grid or
# Spotlight's index; a real bundle does.
#
# Trade-off accepted: after `brew upgrade $EMACS_FORMULA`, the copy at
# /Applications/$EMACS_APP_NAME.app stays at the OLD version until install.sh
# runs again. Re-running install.sh is fast (brew install is a no-op
# if the formula is already current) so the workflow is: `brew
# upgrade` → `bash ~/emacs-mac-setup-src/install.sh` to re-copy.
_EMACS_FORMULA_PREFIX="$(brew --prefix "$EMACS_FORMULA" 2>/dev/null)"
EMACS_APP_SRC="$_EMACS_FORMULA_PREFIX/Emacs.app"
echo "==> brew --prefix $EMACS_FORMULA = ${_EMACS_FORMULA_PREFIX:-<empty>}"
if [ -z "$_EMACS_FORMULA_PREFIX" ] || [ ! -d "$EMACS_APP_SRC" ]; then
  {
    echo ""
    echo "ERROR: Emacs.app not found at: $EMACS_APP_SRC"
    echo "       brew --prefix $EMACS_FORMULA returned: ${_EMACS_FORMULA_PREFIX:-<empty>}"
    echo "       Try: brew reinstall $EMACS_FORMULA $EMACS_BREW_ARGS"
    echo "       Then re-run install.sh."
  } >&2
  exit 1
fi
unset _EMACS_FORMULA_PREFIX

EMACS_APP_DST="/Applications/$EMACS_APP_NAME.app"
# Clean up: remove a previous symlink (any version of this script),
# remove a previous ditto copy (will be replaced), or leave alone if
# someone else's same-named app is there (use ~/Applications/ instead).
if [ -L "$EMACS_APP_DST" ]; then
  rm "$EMACS_APP_DST"
elif [ -d "$EMACS_APP_DST" ]; then
  # Heuristic for "ours": Info.plist's CFBundleIdentifier is org.gnu.Emacs.
  # If yes, replace. If no, leave alone and use ~/Applications/.
  existing_bundle_id="$(emacs_app_bundle_id "$EMACS_APP_DST" || true)"
  if [ "$existing_bundle_id" = "org.gnu.Emacs" ]; then
    rm -rf "$EMACS_APP_DST"
  else
    echo "==> $EMACS_APP_DST is a third-party app (${existing_bundle_id:-unknown}) — falling back to ~/Applications/"
    EMACS_APP_DST="$HOME/Applications/$EMACS_APP_NAME.app"
    mkdir -p "$HOME/Applications"
    [ -e "$EMACS_APP_DST" ] && rm -rf "$EMACS_APP_DST"
  fi
fi

# Copy the bundle. `ditto` follows symlinks inside the source bundle
# correctly and writes a real .app on disk that Launchpad indexes.
echo "==> Copying $EMACS_APP_SRC -> $EMACS_APP_DST"
if ! ditto "$EMACS_APP_SRC" "$EMACS_APP_DST"; then
  # /Applications/ write may fail under SIP / managed-machine policies.
  # Fall back to ~/Applications/.
  echo "==> /Applications/ write failed; falling back to ~/Applications/"
  EMACS_APP_DST="$HOME/Applications/$EMACS_APP_NAME.app"
  mkdir -p "$HOME/Applications"
  [ -e "$EMACS_APP_DST" ] && rm -rf "$EMACS_APP_DST"
  if ! ditto "$EMACS_APP_SRC" "$EMACS_APP_DST"; then
    {
      echo ""
      echo "ERROR: ditto failed to copy Emacs.app to both /Applications/ and ~/Applications/."
      echo "       Source: $EMACS_APP_SRC"
      echo "       Check that the source bundle exists and you have write permission."
    } >&2
    exit 1
  fi
fi
echo "==> Copied .app to $EMACS_APP_DST ($(du -sh "$EMACS_APP_DST" 2>/dev/null | cut -f1))"

# Register with LaunchServices so Spotlight / Launchpad / "Open With"
# find it immediately. Without this, the app shows up only after the
# next logout.
LSREG="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
if [ -x "$LSREG" ]; then
  "$LSREG" -f "$EMACS_APP_DST" 2>/dev/null || true
  echo "==> Registered with LaunchServices"
fi
# Nudge Spotlight to index the new bundle immediately.
mdimport "$EMACS_APP_DST" 2>/dev/null || true
# Restart the Dock so Launchpad reads its cache fresh.
killall Dock 2>/dev/null || true
echo "==> Dock restarted; Launchpad will show Emacs after it respawns (~2s)"

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

# 5. secrets.el — per-Mac, never overwritten on update.
# Everything else (starter data, BW unlock, gh clone, API keys) is
# generated by Emacs's bootstrap.org on first launch.
if [ ! -e "$SRC_DIR/emacs.d/secrets.el" ]; then
  cp "$SRC_DIR/emacs.d/secrets.el.template" "$SRC_DIR/emacs.d/secrets.el"
fi
mkdir -p "$DATA_DIR"  # ensure my/data-dir exists so bootstrap.org can write to it

# 6. Done ------------------------------------------------------------------
echo ""
echo "======================================================================"
echo "Done."
echo "======================================================================"
echo "  ~/.emacs.d:  $EMACS_D  ->  $SRC_DIR/emacs.d"
echo "  Data root:   $DATA_DIR    (= my/data-dir; literate config lives at \$DATA_DIR/config/)"
echo "  Seed:        $SRC_DIR/seed-config/   (copied into \$DATA_DIR/config/ on first launch)"
echo "  Secrets:     $SRC_DIR/emacs.d/secrets.el   (per-Mac, not in git)"
echo ""
echo "  First launch (init.el):"
echo "    Seeds \$DATA_DIR/config/ from seed-config/ if .bootstrap-completed is absent."
echo "  Then bootstrap.org runs:"
echo "    1. Ask whether to use Bitwarden for secrets (recommended)"
echo "    2. If yes — prompt for email + master, cache to macOS Keychain"
echo "    3. Read or create the github-cli-token Bitwarden item"
echo "    4. Install + authenticate gh CLI"
echo "    5. Clone (or create + push) your private data repo into $DATA_DIR"
echo "    6. Unlock git-crypt if the repo uses it (key in BW under GitCryptKey)"
echo "    7. Generate any missing starter content via elisp templates"
echo "    8. Load API keys (Gemini/Anthropic/OpenAI/Groq) from BW or Keychain"
echo "    9. Drop \$DATA_DIR/config/.bootstrap-completed so future launches skip seeding"
echo ""
echo "  Update later:   bash $SRC_DIR/install.sh"
echo "  Uninstall:      bash $SRC_DIR/uninstall.sh"
echo "======================================================================"
open "$EMACS_APP_DST"
