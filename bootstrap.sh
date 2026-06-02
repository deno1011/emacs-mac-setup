#!/bin/bash
# Bootstrap: Downloads all Emacs setup scripts from GitHub.
# Usage: bash bootstrap.sh [branch]
# Example: bash bootstrap.sh stable
# GitHub user is detected from an existing gh session or requested interactively.

set -e

# Ensure Homebrew is in PATH (Apple Silicon: /opt/homebrew, Intel: /usr/local)
[ -f /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
[ -f /usr/local/bin/brew ]    && eval "$(/usr/local/bin/brew shellenv)"

# --- Homebrew ---
if ! command -v brew &>/dev/null; then
  echo "==> Installing Homebrew (sudo password required)..."
  sudo -v
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  [ -f /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
  [ -f /usr/local/bin/brew ]    && eval "$(/usr/local/bin/brew shellenv)"
fi

# Persist brew in shell profile so all future shells and scripts find it
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
      echo "    Added brew to $( basename "$_PROFILE" )"
    fi
  fi
done
unset _BREW_SHELLENV_LINE _PROFILE

_BS_BRANCH="${1:-stable}"
DEST="$HOME/emacs-mac-setup"
mkdir -p "$DEST"
CONFIG_FILE="$HOME/emacs-mac-setup/setup-emacs-mac.conf"

echo "==> Downloading all scripts to $DEST/ (branch: ${_BS_BRANCH})"
_DL_TMP=$(mktemp -d)
curl -fsSL "https://github.com/deno1011/emacs-mac-setup/archive/refs/heads/${_BS_BRANCH}.tar.gz" \
  | tar -xz -C "$_DL_TMP" --strip-components=1
for _F in "$_DL_TMP"/*; do
  [ -f "$_F" ] || continue   # skip subdirectories (e.g. config/)
  _NAME="$(basename "$_F")"
  cp "$_F" "$DEST/$_NAME"
  echo "    $_NAME"
done
rm -rf "$_DL_TMP"

chmod +x "$DEST"/*.sh

# Self-update: re-exec with the freshly downloaded bootstrap.sh (once only)
if [ -z "${_BOOTSTRAP_UPDATED:-}" ] && [ -f "$DEST/bootstrap.sh" ]; then
  export _BOOTSTRAP_UPDATED=1
  exec bash "$DEST/bootstrap.sh" "$@"
fi

# --- Up-front discovery, config, Bitwarden and secret intake ---
source "$DEST/setup-lib.sh"
setup_ensure_config
bash "$DEST/setup-intake.sh"
setup_runtime_load
if [ -n "${GH_USER:-}" ]; then
  setup_runtime_load_bitwarden_secrets || exit 1
fi

# --- GitHub auth (with token from Bitwarden) ---
if [ -n "$GH_USER" ]; then
  if ! command -v gh &>/dev/null; then
    echo "==> Installing GitHub CLI..."
    brew install gh &>/dev/null
    export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
  fi
  if setup_gh_auth_status_stored; then
    echo "==> GitHub auth: already authenticated."
  else
    echo "==> Authenticating GitHub..."
    if [ -n "${GITHUB_TOKEN:-}" ]; then
      setup_gh_auth_login_with_token "$GITHUB_TOKEN"
      echo "    GitHub authenticated."
    else
      setup_fail "GitHub token missing after intake; refusing to interrupt setup with a late login prompt." "bash ~/emacs-mac-setup/setup-intake.sh --repair github-token"
    fi
  fi
fi

if [ -n "${GH_USER:-}" ]; then
  setup_try_load_private_config_from_github || true
  setup_runtime_load
  setup_runtime_load_bitwarden_secrets || exit 1
fi

# --- Check and create GitHub repos ---
if [ -n "$GH_USER" ] && setup_gh_auth_status_stored; then
  echo ""
  echo "==> Checking GitHub repos..."
  setup_runtime_load

  _create_repo_if_missing() {
    local REPO_NAME="$1" DESC="$2"
    if gh api "repos/$GH_USER/$REPO_NAME" &>/dev/null 2>&1; then
      echo "    $GH_USER/$REPO_NAME — already exists."
      return 1  # already existed
    fi
    echo "==> Repo $GH_USER/$REPO_NAME not found — creating..."
    if gh api user/repos -X POST -f name="$REPO_NAME" -f private=true -f description="$DESC" >/dev/null; then
      echo "    $GH_USER/$REPO_NAME created."
      return 0  # was created
    else
      echo "    WARN: Could not create repo $GH_USER/$REPO_NAME."
      return 1
    fi
  }

  _create_repo_if_missing "${GH_REPO:-emacs-data}" \
    "Emacs data: config and org files" || true
fi

echo ""
echo "======================================================================"
echo "Bootstrap complete!"
echo "======================================================================"
echo ""
echo "  Other variants — run anytime, no config changes needed:"
echo "    bash $DEST/setup-emacs-native-yamamoto-mac.sh  # smooth rendering, trackpad"
echo "    bash $DEST/setup-emacs-docker-mac.sh           # isolated in Docker + XQuartz"
echo "    bash $DEST/setup-emacs-orbstack-mac.sh         # isolated in OrbStack, no XQuartz"
echo ""
echo "----------------------------------------------------------------------"
echo "  Activate brew in this terminal (no restart needed):"
if [ -f /opt/homebrew/bin/brew ]; then
  echo '    eval "$(/opt/homebrew/bin/brew shellenv)"'
else
  echo '    eval "$(/usr/local/bin/brew shellenv)"'
fi
echo "----------------------------------------------------------------------"
echo ""
for _i in 5 4 3 2 1; do
  printf "\r  Starting emacs-plus setup in %d s — Ctrl-C to cancel..." "$_i"
  sleep 1
done
printf "\r  Starting emacs-plus setup...                              \n\n"
exec bash "$DEST/setup-emacs-native-plus-mac.sh"
