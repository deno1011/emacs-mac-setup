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
#                    from the distro on every install, runtime state (distro-
#                    source.el, secrets.el, custom.el, …) lives here.
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
echo "==> Target distro: branch=$BRANCH repo=$REPO_URL src=$SRC_DIR"
[ -n "$_persisted_branch$_persisted_repo$_persisted_src" ] && \
  echo "    (precedence: env > distro-source.el > project defaults)"
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
echo "    app:     ~/Applications/Emacs Client.app  (daemon-aware wrapper)"
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

# Run brew unattended for the rest of this script. Modern brew pauses
# with prompts on several operations — `brew tap' against a non-default
# tap, `brew install' against a formula with a caveats section, and
# (new in brew 6.0) a default-on "ask mode" that previews the install
# plan and asks "Do you want to proceed with the installation? [y/n]"
# before downloading anything. install.sh is invoked from a curl
# one-liner; there's nobody at the keyboard to press enter, so every
# such pause must be suppressed:
#
#   NONINTERACTIVE                — brew's blanket "don't ask, don't
#                                   wait" flag (skips press-enter,
#                                   tap-trust nags, caveats pause).
#   HOMEBREW_NO_AUTO_UPDATE       — stops brew from `brew update'-ing
#                                   itself mid-script (can stall for
#                                   minutes on a fresh Mac).
#   HOMEBREW_NO_INSTALL_CLEANUP   — skip `brew cleanup' after install,
#                                   which can run for a long time.
#   HOMEBREW_NO_ENV_HINTS         — silence the post-install "hint"
#                                   banners that would clutter the log.
#   HOMEBREW_NO_ASK               — opt out of brew 6.0's new
#                                   default-on ask mode. NONINTERACTIVE
#                                   alone does NOT cover this: in brew
#                                   6.0 the install plan confirmation
#                                   is a separate, opt-in gate, and
#                                   only `HOMEBREW_NO_ASK=1' (or
#                                   `--yes' on the install command)
#                                   skips it. Without this, the curl
#                                   one-liner hangs at "Do you want to
#                                   proceed with the installation?".
export NONINTERACTIVE=1
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALL_CLEANUP=1
export HOMEBREW_NO_ENV_HINTS=1
export HOMEBREW_NO_ASK=1

# 2. emacs-plus ------------------------------------------------------------
EMACS_FORMULA="${EMACS_FORMULA:-emacs-plus@30}"
EMACS_BREW_ARGS="${EMACS_BREW_ARGS:---with-xwidgets}"
EMACS_TAP="${EMACS_TAP:-d12frosted/emacs-plus}"

# `brew list --formula emacs-plus@30' returns non-zero when the formula was
# installed tap-qualified (`d12frosted/emacs-plus/emacs-plus@30') even though
# the formula IS present — recent brew versions stopped accepting the
# unqualified name as a match. `brew --prefix' is the authoritative check:
# it resolves the formula regardless of how it was installed and exits 0
# iff the formula is on disk. Avoids re-entering the install branch
# unnecessarily, which would then trip the next bug below.
if ! brew --prefix "$EMACS_FORMULA" >/dev/null 2>&1; then
  echo "==> Installing $EMACS_FORMULA $EMACS_BREW_ARGS (this takes ~10 minutes on first install)..."

  # Make the tap explicit and visible. Recent Homebrew versions (4.5+)
  # refuse to install a formula from a tap unless it is registered and
  # the install command qualifies the formula with the tap's path.
  # Previous behavior — `brew tap … 2>/dev/null || true` followed by
  # `brew install emacs-plus@30' — relied on a soft tap step and an
  # unqualified formula name; both of those have stopped being enough.
  # Symptom: `Error: Refusing to load formula from untrusted tap: …'
  # at install time, with the install.sh trap catching it and exiting.
  if ! brew tap | grep -qx "$EMACS_TAP"; then
    echo "==> brew tap $EMACS_TAP"
    brew tap "$EMACS_TAP"
  fi

  # Mark the tap trusted. Homebrew 6.0 added a per-tap "trust" gate:
  # without explicit trust, `brew install' from a non-core tap prints
  # a multi-line warning ("The following taps are not trusted: …")
  # and silently *ignores* formulae from that tap. On a fresh Mac
  # that means the very next `brew install d12frosted/emacs-plus/…'
  # would error with "no such formula" instead of installing
  # emacs-plus@30. `brew trust --tap' writes the tap into the
  # per-user trust list at ~/.homebrew/trust.json (or under
  # $XDG_CONFIG_HOME if set). The subcommand only exists on brew
  # 6.0+; for older brew the `|| true' makes this a clean no-op.
  brew trust --tap "$EMACS_TAP" 2>/dev/null || true

  # Install via the FULLY-QUALIFIED formula path so brew never has to
  # guess which tap the recipe came from. Equivalent to `brew install
  # d12frosted/emacs-plus/emacs-plus@30 --with-xwidgets'.
  #
  # Tolerate non-zero exit: brew 5+ returns 1 when the formula is
  # already installed (caveats still print). Whether the install was
  # truly successful is decided by the `brew --prefix' + Emacs.app
  # check immediately below — that's the only signal that matters.
  # shellcheck disable=SC2086
  brew install "${EMACS_TAP}/${EMACS_FORMULA}" $EMACS_BREW_ARGS || true
fi

# Locate the brewed Emacs.app. This is the headless daemon binary —
# `emacs-plus`'s LaunchAgent starts it as `--fg-daemon` from this
# path and the Emacs Client.app wrapper (placed in step 5) connects
# to it via `emacsclient'. We deliberately do NOT make a second copy
# under /Applications: this is a daemon-only distro, so users should
# only ever click the lightweight Emacs Client.app at ~/Applications/.
# Having both the daemon binary AND a Client wrapper visible in
# Launchpad produced two Emacs icons with the same logo ("doppelt"),
# and clicking the daemon copy directly bypassed the daemon and
# started a fresh, unconfigured Emacs — exactly the footgun this
# distro exists to eliminate.
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

# Hide the Cellar Emacs.app from Launchpad / Spotlight / "Open With".
# LaunchServices auto-scans the brew prefix and registers every .app
# it finds, so without this `lsregister -u' the Cellar Emacs.app
# appears in Launchpad next to Emacs Client.app as a second Emacs
# icon. Unregistering only removes the LaunchServices entry — the
# binary at $EMACS_APP_SRC is untouched and the daemon continues to
# run from it. Re-applied on every install run because `brew upgrade'
# (and a periodic LaunchServices rescan) can re-register it.
LSREG="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
if [ -x "$LSREG" ]; then
  "$LSREG" -u "$EMACS_APP_SRC" 2>/dev/null || true
  echo "==> Hid Cellar Emacs.app from Launchpad (daemon binary unchanged)"
fi
# Restart the Dock so Launchpad re-reads its cache and the just-hidden
# Cellar entry disappears immediately.
killall Dock 2>/dev/null || true

# 3. Clone or update the distro -------------------------------------------
if [ -d "$SRC_DIR/.git" ]; then
  echo "==> Updating $SRC_DIR (branch: $BRANCH)..."
  # Use `merge --ff-only origin/$BRANCH' rather than
  # `pull --ff-only origin $BRANCH'. The pull form does an *implicit*
  # second fetch on top of the explicit one above, and when the
  # background bootstrap-distro-update task (see 20_bootstrap.org)
  # races against this install run, the second fetch can leave
  # FETCH_HEAD with multiple "for-merge" entries — at which point
  # git aborts with `fatal: Cannot fast-forward to multiple branches.'
  # Merging directly against the local tracking ref bypasses
  # FETCH_HEAD and is robust against the race.
  git -C "$SRC_DIR" fetch origin "$BRANCH"
  git -C "$SRC_DIR" checkout "$BRANCH"
  git -C "$SRC_DIR" merge --ff-only "origin/$BRANCH"
else
  echo "==> Cloning distro to $SRC_DIR..."
  git clone --branch "$BRANCH" "$REPO_URL" "$SRC_DIR"
fi

# 4. Real ~/.emacs.d/ — copy distro files in, leave runtime state alone --
#
# This used to be a symlink ~/.emacs.d -> $SRC_DIR/emacs.d, which meant
# `distro-source.el', `secrets.el', `custom.el', `eln-cache/' etc. all
# landed INSIDE the distro git checkout. Three failure modes
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
# install; runtime files (distro-source.el, secrets.el, custom.el,
# history, abbrev_defs, …) are NEVER touched and live in the real
# ~/.emacs.d/ regardless of branch-switches in $SRC_DIR.
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
             distro-source.el secrets.el; do
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

# 6. Seed the literate config into ~/.emacs.d/config/.
#
# Config is distro-managed and lives in ~/.emacs.d/config/ — INDEPENDENT
# of the user's data folder. `my/data-dir' is derived at runtime by the
# bootstrap orchestrator (Keychain.GitHubRepo → BW.Repo → setup form);
# init.el reads only `$EMACS_DATA_DIR' as an explicit override.
# Putting config in ~/.emacs.d/config/ makes it location-agnostic: the
# user can switch BW.Repo freely, and `my/data-dir' only affects WHERE
# USER DATA lives (org files, wiki, etc.).
#
# Repo layout now mirrors the live install layout — the distro's
# config.org + modules/ ship as `emacs.d/config/' in this repo, and
# `install.sh' just copies that directly into `~/.emacs.d/config/'.
# The old `seed-config/' intermediate directory was a relic from
# before the rsync target matched the source path one-to-one; it
# added a renaming step with no benefit.
#
# Policy matches `my/bootstrap-ensure-seed-config-files' in
# emacs.d/config/modules/20_bootstrap.org: distro-tracked files
# are OVERWRITTEN on every install so fixes flow through.
#
# Users who want to FREEZE local config from distro updates (e.g.
# while iterating on a personal patch) create the sentinel file:
#     touch ~/.emacs.d/config/.no-seed-config-updates
# Then install.sh falls back to --ignore-existing (legacy behavior)
# so local changes never get overwritten. `M-x my/bootstrap-freeze-
# config-updates' inside Emacs writes the same sentinel. The
# sentinel filename keeps its historical name `.no-seed-config-
# updates' for backward compatibility with existing user installs.
CONFIG_DIR="$EMACS_D/config"
CONFIG_SRC="$SRC_DIR/emacs.d/config"
mkdir -p "$CONFIG_DIR/modules"
SEED_SENTINEL="$CONFIG_DIR/.no-seed-config-updates"
if [ -e "$SEED_SENTINEL" ]; then
  rsync -a --ignore-existing "$CONFIG_SRC/" "$CONFIG_DIR/"
  echo "==> Seeded $CONFIG_DIR/ from $CONFIG_SRC/ (FROZEN — only new files added; existing preserved)"
  echo "    (delete $SEED_SENTINEL or run M-x my/bootstrap-unfreeze-config-updates to re-enable updates)"
else
  # --update so we only touch destination files that are OLDER than the
  # source (or missing). Avoids racing the bootstrap's distro-config-update
  # task if it ran on a more recent seed than this install.sh fetched.
  rsync -a --update "$CONFIG_SRC/" "$CONFIG_DIR/"
  echo "==> Seeded $CONFIG_DIR/ from $CONFIG_SRC/ (refreshed distro-tracked files)"
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
# (custom.el, secrets.el, distro-source.el, ...) lives in ~/.emacs.d/
# at the top level — only the elpa/ SUBDIR is removed.
if [ -d "$EMACS_D/elpa" ] && [ -d "$EMACS_D/elpaca" ]; then
  size=$(du -sh "$EMACS_D/elpa" 2>/dev/null | cut -f1)
  echo "==> Removing legacy package.el state at $EMACS_D/elpa ($size) — elpaca is in use"
  rm -rf "$EMACS_D/elpa"
fi

# 6c. Vendor async-tasks from upstream into the modules directory ----------
#
# `async-tasks` is the standalone task framework formerly shipped inline as
# 10_tasks.org. Source of truth is the public repo at
# https://github.com/deno1011/async-tasks; we fetch the latest tagged copy
# (or main HEAD when no tag is pinned) and drop it as
# `~/.emacs.d/config/modules/10_tasks.el` so it loads inline at module-load
# time. No elpaca queue, no `(elpaca-wait)` cost on launch — and other
# Emacs users can still install the same package independently from MELPA.
#
# Override the repo (forks for testing) with EMACS_MAC_ASYNC_TASKS_REPO.
# Pin to a release with EMACS_MAC_ASYNC_TASKS_TAG=v0.1.0; defaults to main.
ASYNC_TASKS_REPO="${EMACS_MAC_ASYNC_TASKS_REPO:-deno1011/async-tasks}"
ASYNC_TASKS_TAG="${EMACS_MAC_ASYNC_TASKS_TAG:-main}"
ASYNC_TASKS_URL="https://raw.githubusercontent.com/$ASYNC_TASKS_REPO/$ASYNC_TASKS_TAG/async-tasks.el"
ASYNC_TASKS_DST="$CONFIG_DIR/modules/10_tasks.el"
# Pre-2026 distro versions shipped this module inline as 10_tasks.org.
# If the user is upgrading from one of those, the .org would shadow our
# freshly-vendored .el (the discovery loop prefers .org siblings). Wipe
# both stale outputs before fetching.
rm -f "$CONFIG_DIR/modules/10_tasks.org" "$CONFIG_DIR/modules/10_tasks.elc"
echo "==> Fetching async-tasks from $ASYNC_TASKS_REPO@$ASYNC_TASKS_TAG …"
# Fetch into a tmp file; only promote to the real location after we have
# validated that the bytes actually look like async-tasks.el. curl with
# `--retry 3` already covers transient network jitter; we add a content
# check on top so HTML 404 pages, empty responses, or any other "200 OK
# but the body isn't what we wanted" can never silently install bad code.
ASYNC_TASKS_FETCH_RC=0
curl -fsSL --retry 3 --max-time 60 -o "$ASYNC_TASKS_DST.tmp" "$ASYNC_TASKS_URL" || ASYNC_TASKS_FETCH_RC=$?

ASYNC_TASKS_OK=0
if [ "$ASYNC_TASKS_FETCH_RC" -eq 0 ] && [ -s "$ASYNC_TASKS_DST.tmp" ]; then
  # Validate: first line MUST start with the expected commentary line,
  # AND `(provide 'async-tasks)' must be present (sanity that we got the
  # whole file, not a truncation). The two checks together catch every
  # known failure mode short of a maliciously crafted GitHub response.
  if head -1 "$ASYNC_TASKS_DST.tmp" | grep -q "^;;; async-tasks\.el ---" \
     && grep -q "^(provide 'async-tasks)" "$ASYNC_TASKS_DST.tmp"; then
    mv "$ASYNC_TASKS_DST.tmp" "$ASYNC_TASKS_DST"
    rm -f "${ASYNC_TASKS_DST}c"
    echo "    -> $ASYNC_TASKS_DST ($(wc -c < "$ASYNC_TASKS_DST") bytes)"
    ASYNC_TASKS_OK=1
  else
    echo "ERROR: downloaded async-tasks.el failed content validation." >&2
    echo "       (Expected first line to start with \";;; async-tasks.el ---\"" >&2
    echo "        AND the file to contain \`(provide 'async-tasks)'.)" >&2
    echo "       Got first line: $(head -1 "$ASYNC_TASKS_DST.tmp" 2>/dev/null)" >&2
    echo "       URL:            $ASYNC_TASKS_URL" >&2
    rm -f "$ASYNC_TASKS_DST.tmp"
  fi
else
  rm -f "$ASYNC_TASKS_DST.tmp"
  echo "ERROR: curl failed to fetch async-tasks (exit code $ASYNC_TASKS_FETCH_RC)." >&2
  echo "       URL: $ASYNC_TASKS_URL" >&2
fi

if [ "$ASYNC_TASKS_OK" -eq 0 ]; then
  if [ -f "$ASYNC_TASKS_DST" ]; then
    # We have a previous good copy. Warn but continue — better to install
    # with a slightly stale framework than to refuse to install at all.
    echo "WARNING: keeping existing copy at $ASYNC_TASKS_DST" >&2
    echo "         (size $(wc -c < "$ASYNC_TASKS_DST") bytes). Re-run install.sh" >&2
    echo "         after restoring network connectivity to refresh." >&2
  else
    # No fallback. Refusing to continue is the only honest choice — without
    # this file the bootstrap dep gate at the end of 20_bootstrap.el will
    # skip the orchestrator, my/data-dir stays unset, and the next launch
    # crashes a third-party package that reads my/data-dir at load time
    # (gptel-agent-runtime hit exactly this; the symptom is a backtrace
    # ending in `directory-file-name(nil)' that's mystifying to debug).
    echo "" >&2
    echo "FATAL: async-tasks could not be downloaded AND no on-disk copy exists." >&2
    echo "       Install cannot continue safely — the bootstrap orchestrator" >&2
    echo "       depends on this package being present at module-load time." >&2
    echo "" >&2
    echo "Recovery:" >&2
    echo "  1. Check connectivity:  curl -fsSL $ASYNC_TASKS_URL > /dev/null" >&2
    echo "  2. If your network is fine, the upstream repo may be wrong." >&2
    echo "     Override:  EMACS_MAC_ASYNC_TASKS_REPO=other/fork bash install.sh" >&2
    echo "  3. If you have a working copy from another Mac, drop it at:" >&2
    echo "       $ASYNC_TASKS_DST" >&2
    echo "     and re-run install.sh." >&2
    echo "  4. As a last resort, fetch manually:" >&2
    echo "       curl -fsSL --retry 3 -o $ASYNC_TASKS_DST \\\\" >&2
    echo "         $ASYNC_TASKS_URL" >&2
    echo "" >&2
    exit 1
  fi
fi
unset ASYNC_TASKS_FETCH_RC ASYNC_TASKS_OK

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
#
# When invoked from Finder / Launchpad / Spotlight the parent process
# is `launchd', whose default PATH is `/usr/bin:/bin:/usr/sbin:/sbin'.
# `emacsclient' and `emacs' live under `/opt/homebrew/bin' (Apple
# Silicon) or `/usr/local/bin' (Intel). Without an explicit PATH
# extension here, this script silently fails with "command not found"
# and the user sees nothing happen when they click the Dock icon.
# Prepending both brew prefixes is harmless on either architecture.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

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
#
# Re-install hygiene: we must REMOVE any previous Emacs Client.app entirely
# before writing the new one, otherwise macOS's LaunchServices treats the
# in-place overwrite as a new app while keeping the old entry around. After
# a few installs Launchpad ends up with multiple "Emacs Client" icons, all
# pointing at the same path but each holding its own LSItemRecord. The user
# trashes them one by one (auto-renamed `Emacs Client 09.34.56.app' etc.)
# and the next install adds a new one. The `rm -rf' + lsregister + Dock
# restart below makes the placement idempotent: one bundle, one Launchpad
# icon, no matter how many times install.sh is re-run.
APP_DIR="$HOME/Applications/Emacs Client.app"
mkdir -p "$HOME/Applications"
# Clean slate before write — guarantees LaunchServices gets a fresh
# (re)registration rather than treating the modified bundle as a sibling
# of the previous one.
[ -e "$APP_DIR" ] && rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
cat > "$APP_DIR/Contents/MacOS/Emacs Client" <<'EOF'
#!/bin/bash
exec "$HOME/bin/emacs-gui" "$@"
EOF
chmod +x "$APP_DIR/Contents/MacOS/Emacs Client"
# Borrow the Emacs icon from emacs-plus's own .app bundle so the
# wrapper shows the real GNU Emacs icon in Launchpad / Dock / Cmd-Tab
# instead of the generic gray "broken document" icon. Without this
# step the bundle has no .icns file and macOS substitutes the
# generic application icon, which is what the "corrupt app symbol"
# observation reported.
ICON_SRC="$(brew --prefix emacs-plus@30 2>/dev/null)/Emacs.app/Contents/Resources/Emacs.icns"
if [ -f "$ICON_SRC" ]; then
  cp "$ICON_SRC" "$APP_DIR/Contents/Resources/Emacs.icns"
  echo "==> Copied Emacs icon from emacs-plus into the Client bundle"
else
  echo "==> WARNING: $ICON_SRC not found; Client.app will use generic icon"
fi
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
    <key>CFBundleIconFile</key>
    <string>Emacs</string>
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
# Strip Gatekeeper quarantine so the first launch doesn't pop the
# "downloaded from internet" warning on a script-written bundle.
xattr -dr com.apple.quarantine "$APP_DIR" 2>/dev/null || true
# Force LaunchServices to register THIS path, replacing any prior
# entry it had for the same path. Without `-f' it would simply add
# another LSItemRecord. Suppress noisy output but keep failure
# tolerant — lsregister is a private framework binary, no contract.
if [ -x "$LSREG" ]; then
  "$LSREG" -f "$APP_DIR" 2>/dev/null || true
fi
mdimport "$APP_DIR" 2>/dev/null || true
# Restart the Dock so Launchpad re-reads its icon grid and shows the
# single replaced bundle instead of the cached stale one.
killall Dock 2>/dev/null || true
echo "==> Wrote $APP_DIR (.app wrapper for the daemon-aware launcher)"
echo "    (LaunchServices re-registered; Dock restarted to refresh Launchpad)"

# 6.  Protection layer A — env snapshot for the daemon ---------------------
# emacs-plus@30 launched via LaunchAgent does not source the user's
# shell profile. PATH, LIBRARY_PATH, MANPATH, INFOPATH are all empty
# or system-default. native-comp fails on a missing LIBRARY_PATH, brew
# isn't found by `executable-find', `gh' can't be called, etc.
#
# Doom Emacs solves this with `doom env' — a snapshot file generated
# from the install-time shell that early-init.el sources at every
# launch. Same idea here: write ~/.emacs.d/env-snapshot.el now (when
# the install shell has brew shellenv sourced + ~/.zshrc / ~/.zprofile
# loaded) and early-init.el reads it before any module load.
ENV_SNAP="$EMACS_D/env-snapshot.el"
echo "==> Writing env snapshot to $ENV_SNAP (for the daemon's early-init.el)"
# On Darwin the install shell rarely has LIBRARY_PATH set — `brew shellenv`
# does NOT export it, and the user's profile usually doesn't either. The
# snapshot loop below skips empty vars, so without this seed the snapshot
# would silently omit LIBRARY_PATH, leaving the daemon to fall back on
# early-init.el's hardcoded paths only. Seed the brew gcc + libgccjit
# library dirs explicitly so the snapshot is the authoritative source
# instead of a stale-leaning safety net.
if [ "$(uname -s)" = "Darwin" ]; then
  GCC_LIB="/opt/homebrew/opt/gcc/lib/gcc/current"
  GCCJIT_LIB="/opt/homebrew/opt/libgccjit/lib/gcc/current"
  [ -d "/usr/local/opt/gcc/lib/gcc/current" ] && GCC_LIB="/usr/local/opt/gcc/lib/gcc/current"
  [ -d "/usr/local/opt/libgccjit/lib/gcc/current" ] && GCCJIT_LIB="/usr/local/opt/libgccjit/lib/gcc/current"
  if [ -z "${LIBRARY_PATH:-}" ]; then
    export LIBRARY_PATH="${GCC_LIB}:${GCCJIT_LIB}"
  else
    case ":$LIBRARY_PATH:" in
      *":$GCC_LIB:"*) ;;
      *) export LIBRARY_PATH="${GCC_LIB}:${LIBRARY_PATH}";;
    esac
    case ":$LIBRARY_PATH:" in
      *":$GCCJIT_LIB:"*) ;;
      *) export LIBRARY_PATH="${GCCJIT_LIB}:${LIBRARY_PATH}";;
    esac
  fi
fi
{
  echo ";;; env-snapshot.el --- shell env captured at install time -*- lexical-binding: t -*-"
  echo ";;"
  echo ";; Generated by install.sh on $(date '+%Y-%m-%d %H:%M:%S')."
  echo ";; Sourced by early-init.el at every Emacs start so the daemon"
  echo ";; sees the same PATH / LIBRARY_PATH / MANPATH / INFOPATH a login"
  echo ";; shell would. Regenerated on every install.sh run."
  for var in PATH LIBRARY_PATH MANPATH INFOPATH; do
    eval "val=\${$var:-}"
    if [ -n "$val" ]; then
      esc_val="$(printf '%s' "$val" | sed 's/\\/\\\\/g; s/"/\\"/g')"
      echo "(setenv \"$var\" \"$esc_val\")"
    fi
  done
  # exec-path drives `executable-find', `start-process', etc. inside
  # Emacs; keep it in sync with PATH.
  echo "(setq exec-path (append (split-string (getenv \"PATH\") path-separator t) (list exec-directory)))"
} > "$ENV_SNAP"
echo "    snapshot lines: $(wc -l < "$ENV_SNAP" | xargs)"

# 7.  Protection layer C — AOT byte-compile ---------------------------------
# Without this, the first launch tangles + byte-compiles every .org
# under modules/ as it discovers them: 1-5 seconds of synchronous
# work before the user can type. Compile now (install shell, all tools
# present) so the .elc files are on disk and `my/-load-module' loads
# tier 1 (~10 ms each) from the first launch.
#
# Native-comp is NOT triggered here. emacs-plus@30 ships .eln for the
# core; module .eln gets JIT-compiled lazily on first use (cheap with
# LIBRARY_PATH set by the env snapshot above). Triggering AOT native
# would add 30-120 s to the install with diminishing returns.
echo "==> AOT byte-compiling all modules (so first launch starts fast)"
# Nuke every .elc under modules/ FIRST so the rebuild starts from a
# clean slate. Without this, install.sh's mtime-based "only compile
# when .el is newer than .elc" skip would leave stale .elc behind
# whenever the rsync above transferred .el files with older mtimes
# than the existing .elc (rsync preserves source mtimes; the older
# .elc would survive even though its content is from a previous
# distro version). The loader's tier-1 cache check would then load
# the stale .elc on the next launch, with no error but with
# silently-wrong code. Deleting and rebuilding is cheap and
# guarantees correctness.
find "$EMACS_D/config/modules" -name "*.elc" -delete 2>/dev/null
# Also nuke any stale `!`-prefixed .elc from a previous install that
# byte-compiled them by mistake. The find above already covers them,
# but list explicitly so a future grep makes the intent obvious.
find "$EMACS_D/config/modules" -name '!*.elc' -delete 2>/dev/null
EMACS_BIN="$(brew --prefix emacs-plus@30 2>/dev/null)/bin/emacs"
[ -x "$EMACS_BIN" ] || EMACS_BIN="$(command -v emacs)"
if [ -x "$EMACS_BIN" ]; then
  # Pass the elisp through a tempfile heredoc, NOT inline `--eval '…'`.
  # The intended regex `\.el\'` (end-of-string anchor inside an Elisp
  # string) contains a literal single quote. Bash cannot escape a
  # single quote inside a `'…'`-delimited string, so an inline
  # --eval ' … "\\.el\\'" … ' is parsed as a stream of fragments and
  # the install aborts with `syntax error near unexpected token '('`.
  # The heredoc `<<'ELISP'` is single-quoted so the body is taken
  # verbatim with no shell substitution or quoting at all.
  AOT_TMPEL="$(mktemp -t emacs-aot-XXXXXX).el"
  # Two exclusions, both rooted in the same constraint: the AOT step
  # runs in `emacs -Q' and CANNOT see elpaca or any elpaca-managed
  # package. Byte-compiling code that references those produces .elc
  # that's broken at runtime.
  #
  #   1. `!`-prefixed bootstrap modules — `!00_startfirst.el' defines
  #      AND uses the `elpaca' macro. Byte-compiling freezes the
  #      macro call as a funcall against undefined `elpaca'. config.org's
  #      loader source-loads these (skips byte-compile).
  #
  #   2. Files using `use-package' — `:ensure t' relies on
  #      `elpaca-use-package-mode' to make use-package defer the body
  #      until the package is built. Without elpaca-use-package on the
  #      AOT load-path the use-package macro expands to immediate
  #      `require' calls. On first launch (no packages built yet) every
  #      such .elc errors "Cannot load <pkg>", and the after-init
  #      activation of `doom-modeline-mode' takes the daemon down.
  #
  # Affected files (as of writing): 30_core.el, 40_org.el,
  # 50_apple_reminders.el, 60_gptel.el. Grep'ing the file body is the
  # robust check — survives future renames and new use-package modules.
  # The runtime loader (`my/-load-module' in config.org) compiles
  # these correctly on the first launch, when elpaca is fully active.
  cat > "$AOT_TMPEL" <<'ELISP'
(progn
  (require 'bytecomp)
  (setq byte-compile-warnings nil)
  (dolist (f (directory-files-recursively
              (expand-file-name "config/modules/" user-emacs-directory)
              "\\.el\\'"))
    (unless (or (string-prefix-p "!" (file-name-nondirectory f))
                (with-temp-buffer
                  (insert-file-contents f)
                  (goto-char (point-min))
                  (re-search-forward "(use-package\\b" nil t)))
      (byte-compile-file f))))
ELISP
  "$EMACS_BIN" --batch -Q \
    -L "$EMACS_D/config/modules" \
    -L "$EMACS_D/config/modules/20_bootstrap" \
    -l "$AOT_TMPEL" 2>/dev/null && \
    echo "    AOT byte-compile: done" || \
    echo "    AOT byte-compile: skipped (will compile lazily on first launch)"
  rm -f "$AOT_TMPEL"
else
  echo "    AOT byte-compile: skipped — emacs binary not found"
fi

# 7b. Kick stale daemon so brew services respawns it with fresh files ------
# Background: emacs-plus@30's LaunchAgent (~/Library/LaunchAgents/
# homebrew.mxcl.emacs-plus@30.plist) has KeepAlive=true, so a daemon
# started from a previous install / previous login is STILL RUNNING right
# now — and has all the env from THAT process in memory. We just
# overwrote early-init.el, env-snapshot.el and every .elc under
# config/modules/. The running daemon won't notice any of that until
# something restarts it. Without this kick, the user reinstalls, sees
# the warnings *still* fire (because the on-disk fixes never reach the
# in-memory daemon), and reasonably concludes "didn't we fix that?".
#
# A simple SIGTERM lets the daemon save its state cleanly; launchd then
# respawns it within ~1s (KeepAlive) and the new process reads the new
# early-init.el and the new env-snapshot.el. The final `open' below
# connects to the fresh daemon via emacsclient.
if pgrep -f 'emacs.*--fg-daemon' >/dev/null 2>&1; then
  echo "==> Restarting daemon so it picks up new early-init.el + env-snapshot.el"
  pkill -TERM -f 'emacs.*--fg-daemon' 2>/dev/null || true
  # Give launchd KeepAlive a beat to respawn before the final `open' fires.
  sleep 2
fi

# 8. Done ------------------------------------------------------------------
echo ""
echo "======================================================================"
echo "Done."
echo "======================================================================"
echo "  ~/.emacs.d:  $EMACS_D  (real dir; init.el + early-init.el copied from $SRC_DIR/emacs.d/)"
echo "  Config:      $CONFIG_DIR    (distro-managed; copied here on every install + refreshed by bootstrap)"
echo "  Modules:     $CONFIG_DIR/modules/   (one .org per concern, ordered by NN- prefix)"
echo "  Data root:   $DATA_DIR    (= my/data-dir; user org files, wiki, agenda; per-Mac, switchable via BW.Repo)"
echo "  Secrets:     $SRC_DIR/emacs.d/secrets.el   (per-Mac, not in git)"
echo ""
echo "  First launch (init.el) loads $CONFIG_DIR/config.org, which"
echo "  discovers and runs the modules in numeric order. The first module"
echo "  (20_bootstrap.org) does:"
echo "    1. Ask whether to use Bitwarden for secrets (recommended)"
echo "    2. If yes — prompt for email + master, cache to macOS Keychain"
echo "    3. Read or create the emacs_credentials Bitwarden item"
echo "    4. Install + authenticate gh CLI"
echo "    5. Clone (or create + push) your private data repo into $DATA_DIR"
echo "    6. Unlock git-crypt if the repo uses it (key in BW under GitCryptKey)"
echo "    7. Generate any missing starter content via elisp templates"
echo "    8. Load API keys (Gemini/Anthropic/OpenAI/Groq) from BW or Keychain"
echo ""
echo "  Update later:   bash $SRC_DIR/install.sh"
echo "  Uninstall:      bash $SRC_DIR/uninstall.sh"
echo "======================================================================"
open "$HOME/Applications/Emacs Client.app"
