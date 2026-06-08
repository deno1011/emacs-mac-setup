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
#   - ~/.emacs.d  -> real directory; init.el + early-init.el are copied in
#                    from the distro on every install, runtime state (data-dir.el,
#                    distro-source.el, secrets.el, custom.el, …) lives here.
#   - ~/emacs/    -> example wiki + GTD agenda + TOUR.org (your data from here on)
#   - ~/.emacs.d/secrets.el -> template; uncomment one method to add your API keys
#
# Re-running install.sh is idempotent. It pulls latest distro code and never
# overwrites ~/emacs/ or ~/.emacs.d/secrets.el once they exist.

set -e
trap 'echo "" >&2; echo "==> install.sh FAILED at line $LINENO: $BASH_COMMAND" >&2; echo "    Re-run with: bash -x ~/emacs-mac-setup-src/install.sh 2>&1 | tee /tmp/install.log" >&2' ERR

# CLI flags ----------------------------------------------------------------
for arg in "$@"; do
  case "$arg" in
    --help|-h)
      cat <<HELP
Usage: bash install.sh

Installs / repairs Emacs from the deno1011/emacs-mac-setup distro.
Package management is handled by elpaca (see emacs.d/init.el's bootstrap
snippet). To update individual packages from inside Emacs after install:
  M-x elpaca-fetch-all     ;; fetch latest commits for every recipe
  M-x elpaca-merge-all     ;; merge fetched refs into HEAD per package
  M-x elpaca-status        ;; UI showing every package's state

Env vars:
  EMACS_MAC_BRANCH      Distro branch to install onto (default: main)
  EMACS_MAC_REPO_URL    Distro repo URL
  EMACS_MAC_SRC_DIR     Where to clone the distro (default: ~/emacs-mac-setup-src)
  EMACS_DATA_DIR        Per-Mac data dir override (default: bootstrap derives from BW.Repo)
HELP
      exit 0
      ;;
  esac
done

# Branch / repo / src-dir defaults. Precedence:
#   1. EMACS_MAC_* env vars (highest — explicit one-off override)
#   2. ~/.emacs.d/distro-source.el saved from a previous install.sh run
#   3. Project defaults (lowest — only used on truly first install)
#
# Previous versions of install.sh ignored distro-source.el entirely and
# fell back to BRANCH=main on every re-run. That silently broke users
# who had installed onto a non-main branch (e.g. refactor/modular-config):
# `git checkout main' wiped emacs.d/ on disk because main didn't have it.
EMACS_D="$HOME/.emacs.d"
_persisted_branch=""
_persisted_repo=""
_persisted_src=""
if [ -f "$EMACS_D/distro-source.el" ]; then
  _persisted_branch="$(awk -F'"' '/my\/distro-branch/   {print $2; exit}' "$EMACS_D/distro-source.el")"
  _persisted_repo="$(  awk -F'"' '/my\/distro-repo-url/ {print $2; exit}' "$EMACS_D/distro-source.el")"
  _persisted_src="$(   awk -F'"' '/my\/distro-src-dir/  {print $2; exit}' "$EMACS_D/distro-source.el")"
fi
REPO_URL="${EMACS_MAC_REPO_URL:-${_persisted_repo:-https://github.com/deno1011/emacs-mac-setup.git}}"
BRANCH="${EMACS_MAC_BRANCH:-${_persisted_branch:-main}}"
SRC_DIR="${EMACS_MAC_SRC_DIR:-${_persisted_src:-$HOME/emacs-mac-setup-src}}"
EMACS_APP_NAME="${EMACS_APP_NAME:-Emacs Plus}"
echo "==> Target distro: branch=$BRANCH repo=$REPO_URL src=$SRC_DIR"
[ -n "$_persisted_branch$_persisted_repo$_persisted_src" ] && \
  echo "    (precedence: env > distro-source.el > project defaults)"
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

# 4. Real ~/.emacs.d/ — copy distro files in, leave runtime state alone --
#
# This used to be a symlink ~/.emacs.d -> $SRC_DIR/emacs.d, which meant
# `data-dir.el', `distro-source.el', `secrets.el', `custom.el', `eln-cache/'
# etc. all landed INSIDE the distro git checkout. Three failure modes
# followed from that:
#   1. `git clean -fd' on the distro checkout (e.g. during reset) wiped
#      every runtime file (none were tracked).
#   2. `git checkout' to a branch that doesn't have `emacs.d/' (e.g. the
#      pre-modular `main') made the symlink target vanish — Emacs
#      couldn't find init.el and failed to start.
#   3. Backup tools that follow symlinks ended up backing up the distro
#      tree alongside runtime state.
#
# Real directory + copy is the standard layout. Distro-owned files
# (init.el, early-init.el, secrets.el.template) get copied IN on every
# install; runtime files (data-dir.el, distro-source.el, secrets.el,
# custom.el, history, abbrev_defs, …) are NEVER touched and live in the
# real ~/.emacs.d/ regardless of branch-switches in $SRC_DIR.
if [ -L "$EMACS_D" ]; then
  target="$(readlink "$EMACS_D")"
  echo "==> $EMACS_D is currently a symlink to $target — replacing with real directory"
  rm "$EMACS_D"
  mkdir -p "$EMACS_D"
  # Recover any runtime files that the symlink was pointing at, if the
  # target was the distro emacs.d. They'll be re-copied by step 5 (init.el,
  # early-init.el) and step 5b (distro-source.el writer), but custom.el,
  # secrets.el, etc. need to be preserved.
  if [ -d "$target" ]; then
    for f in custom.el abbrev_defs history org-clock-save.el \
             data-dir.el distro-source.el secrets.el; do
      if [ -f "$target/$f" ] && [ ! -e "$EMACS_D/$f" ]; then
        cp "$target/$f" "$EMACS_D/$f"
        echo "    recovered $EMACS_D/$f"
      fi
    done
    if [ -d "$target/eln-cache" ] && [ ! -d "$EMACS_D/eln-cache" ]; then
      cp -R "$target/eln-cache" "$EMACS_D/"
      echo "    recovered $EMACS_D/eln-cache/"
    fi
    if [ -d "$target/elpa" ] && [ ! -d "$EMACS_D/elpa" ]; then
      cp -R "$target/elpa" "$EMACS_D/"
      echo "    recovered $EMACS_D/elpa/"
    fi
  fi
elif [ ! -e "$EMACS_D" ]; then
  mkdir -p "$EMACS_D"
fi

# Copy distro-owned thin loader files INTO the real ~/.emacs.d/.
# `-p' preserves timestamps; `-f' overwrites our own previous copy (the
# loader IS distro-owned and should track the seed). Runtime files are
# never touched here.
cp -fp "$SRC_DIR/emacs.d/init.el"       "$EMACS_D/init.el"
cp -fp "$SRC_DIR/emacs.d/early-init.el" "$EMACS_D/early-init.el"
echo "==> Copied init.el + early-init.el into $EMACS_D"

# 5. secrets.el — per-Mac, never overwritten on update. Seeded from the
# template only if no real secrets.el exists yet.
if [ ! -e "$EMACS_D/secrets.el" ]; then
  cp "$SRC_DIR/emacs.d/secrets.el.template" "$EMACS_D/secrets.el"
  echo "==> Seeded $EMACS_D/secrets.el from secrets.el.template"
fi

# 5b. distro-source.el — runtime metadata so next launch of Emacs picks
# up the same repo / branch / src dir without the user needing to remember
# EMACS_MAC_BRANCH=... on re-runs. Also lets `my/bootstrap-start-distro-
# config-update-task' pull from the correct branch (defaults to main
# otherwise — which is what wiped this user's setup the first time).
# Written UNCONDITIONALLY: the values come from the precedence rules at
# the top of this script, so rewriting reflects the actual state on disk.
cat > "$EMACS_D/distro-source.el" <<EOF
;;; distro-source.el --- generated runtime metadata -*- lexical-binding: t; -*-
;; Runtime file. install.sh rewrites this when EMACS_MAC_REPO_URL / EMACS_MAC_BRANCH / EMACS_MAC_SRC_DIR change.

(setq my/distro-repo-url "$REPO_URL")
(setq my/distro-branch "$BRANCH")
(setq my/distro-src-dir "$SRC_DIR")
EOF
echo "==> Wrote $EMACS_D/distro-source.el (branch=$BRANCH)"

# 5c. data-dir.el — only if the user supplied EMACS_DATA_DIR explicitly.
# Otherwise leave it alone: bootstrap derives it from BW.Repo (which is
# the canonical source of truth across Macs) and writes the file itself.
# Pinning DATA_DIR here from an unset env var would override BW.Repo and
# point the runtime at $HOME/emacs, defeating the per-Mac data-dir model.
if [ -n "$EMACS_DATA_DIR" ]; then
  cat > "$EMACS_D/data-dir.el" <<EOF
;;; data-dir.el --- generated by install.sh from EMACS_DATA_DIR -*- lexical-binding: t; -*-
;; install.sh wrote this from \$EMACS_DATA_DIR. Bootstrap will overwrite
;; it on first launch with the path derived from the BW.Repo field
;; (canonical, cross-Mac source of truth).

(setq my/data-dir "$EMACS_DATA_DIR")
EOF
  echo "==> Wrote $EMACS_D/data-dir.el from \$EMACS_DATA_DIR=$EMACS_DATA_DIR"
fi

# 6. Seed the literate config into the user's data dir ($DATA_DIR/config/).
#
# Policy matches `my/bootstrap-ensure-seed-config-files' in
# seed-config/modules/10-bootstrap.org (the bootstrap's auto-update task):
# distro-tracked files in seed-config/ are OVERWRITTEN in the user's
# config dir on every install, so fixes flow through immediately and
# users on a single curl can recover from a broken state.
#
# Users who want to FREEZE their local config from distro updates
# (e.g. while iterating on a personal patch) create the sentinel file:
#     touch $DATA_DIR/config/.no-seed-config-updates
# Then install.sh falls back to --ignore-existing (legacy behavior) so
# local changes never get overwritten. `M-x my/bootstrap-freeze-config-updates'
# inside Emacs writes the same sentinel.
mkdir -p "$DATA_DIR/config/modules"
SEED_SENTINEL="$DATA_DIR/config/.no-seed-config-updates"
if [ -e "$SEED_SENTINEL" ]; then
  rsync -a --ignore-existing "$SRC_DIR/seed-config/" "$DATA_DIR/config/"
  echo "==> Seeded $DATA_DIR/config/ from $SRC_DIR/seed-config/ (FROZEN — only new files added; existing preserved)"
  echo "    (delete $SEED_SENTINEL or run M-x my/bootstrap-unfreeze-config-updates to re-enable updates)"
else
  # --update so we only touch destination files that are OLDER than the
  # source (or missing). Avoids racing the bootstrap's distro-config-update
  # task if it ran on a more recent seed than this install.sh fetched.
  rsync -a --update "$SRC_DIR/seed-config/" "$DATA_DIR/config/"
  echo "==> Seeded $DATA_DIR/config/ from $SRC_DIR/seed-config/ (refreshed distro-tracked files)"
fi

# 6b. Wipe legacy ~/.emacs.d/elpa/ (package.el state) when elpaca is in use --
#
# We use elpaca exclusively now — packages live in ~/.emacs.d/elpaca/.
# A pre-existing ~/.emacs.d/elpa/ from an earlier package.el setup is
# pure dead weight: it isn't on `load-path' under the current init.el
# (we don't call `package-initialize'), but its presence can still trip
# elpaca's "compat loaded before Elpaca activation" warning when stale
# byte-compiled autoload files in elpa/ get picked up by Emacs's lazy
# load mechanism through legacy paths.
#
# Wipe it once when both directories exist. The user's runtime state
# (custom.el, secrets.el, distro-source.el, data-dir.el, ...) lives in
# ~/.emacs.d/ at the top level — only the elpa/ SUBDIR is removed.
if [ -d "$EMACS_D/elpa" ] && [ -d "$EMACS_D/elpaca" ]; then
  size=$(du -sh "$EMACS_D/elpa" 2>/dev/null | cut -f1)
  echo "==> Removing legacy package.el state at $EMACS_D/elpa ($size) — elpaca is in use"
  rm -rf "$EMACS_D/elpa"
fi

# 7. Daemon-aware launchers ------------------------------------------------
#
# Subsequent Emacs starts go through the daemon (~/Library/LaunchAgents/
# homebrew.mxcl.emacs-plus@30.plist, installed by `brew services start' —
# the bootstrap auto-configures this on first launch). New emacsclient
# frames open in 10-50 ms instead of paying the full ~2-3 s bootstrap
# cost each time. The wrapper below starts the daemon on demand for the
# rare case where the LaunchAgent hasn't booted it yet (e.g. first
# install before the LaunchAgent loads, or right after `brew services
# stop emacs-plus@30').
mkdir -p "$HOME/bin"
cat > "$HOME/bin/emacs-gui" <<'EOF'
#!/bin/bash
# Open an Emacs GUI frame via the daemon. Starts the daemon on demand.
if ! emacsclient -e "(emacs-pid)" >/dev/null 2>&1; then
    emacs --daemon
    sleep 1
fi
exec emacsclient -c -n "$@"
EOF
chmod +x "$HOME/bin/emacs-gui"
echo "==> Wrote $HOME/bin/emacs-gui (daemon-aware launcher)"

# macOS .app wrapper so the Dock / Launchpad / Spotlight icon also uses the
# daemon model. Stays under ~/Applications/ so brew updates to emacs-plus
# never touch it. Unsigned — Gatekeeper will warn on first launch; the user
# right-clicks Open the first time.
APP_DIR="$HOME/Applications/Emacs Client.app"
mkdir -p "$APP_DIR/Contents/MacOS"
cat > "$APP_DIR/Contents/MacOS/Emacs Client" <<'EOF'
#!/bin/bash
exec "$HOME/bin/emacs-gui" "$@"
EOF
chmod +x "$APP_DIR/Contents/MacOS/Emacs Client"
cat > "$APP_DIR/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Emacs Client</string>
    <key>CFBundleIdentifier</key>
    <string>org.gnu.EmacsClient</string>
    <key>CFBundleName</key>
    <string>Emacs Client</string>
    <key>CFBundleDisplayName</key>
    <string>Emacs Client</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSUIElement</key>
    <false/>
</dict>
</plist>
EOF
echo "==> Wrote $APP_DIR (.app wrapper for the daemon-aware launcher)"

# 6. Done ------------------------------------------------------------------
echo ""
echo "======================================================================"
echo "Done."
echo "======================================================================"
echo "  ~/.emacs.d:  $EMACS_D  (real dir; init.el + early-init.el copied from $SRC_DIR/emacs.d/)"
echo "  Data root:   $DATA_DIR    (= my/data-dir; literate config lives at \$DATA_DIR/config/)"
echo "  Modules:     \$DATA_DIR/config/modules/   (one .org per concern, ordered by NN- prefix)"
echo "  Secrets:     $SRC_DIR/emacs.d/secrets.el   (per-Mac, not in git)"
echo ""
echo "  First launch (init.el) loads \$DATA_DIR/config/config.org, which"
echo "  discovers and runs the modules in numeric order. The first module"
echo "  (10-bootstrap.org) does:"
echo "    1. Ask whether to use Bitwarden for secrets (recommended)"
echo "    2. If yes — prompt for email + master, cache to macOS Keychain"
echo "    3. Read or create the emacs-credentials Bitwarden item"
echo "    4. Install + authenticate gh CLI"
echo "    5. Clone (or create + push) your private data repo into $DATA_DIR"
echo "    6. Unlock git-crypt if the repo uses it (key in BW under GitCryptKey)"
echo "    7. Generate any missing starter content via elisp templates"
echo "    8. Load API keys (Gemini/Anthropic/OpenAI/Groq) from BW or Keychain"
echo ""
echo "  Update later:   bash $SRC_DIR/install.sh"
echo "  Uninstall:      bash $SRC_DIR/uninstall.sh"
echo "======================================================================"
open "$EMACS_APP_DST"
