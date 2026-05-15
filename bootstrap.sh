#!/bin/bash
# Bootstrap: Downloads all Emacs setup scripts from GitHub.
# Usage: bash bootstrap.sh [branch]
# Example: bash bootstrap.sh stable
# GitHub user is detected automatically (gh session → Bitwarden → interactive prompt).

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

# --- Auto-detect GitHub user and pull personal config ---
CONF_PULLED=false
echo ""
echo "==> Detecting GitHub user..."

# Install gh if missing
if ! command -v gh &>/dev/null; then
  echo "    Installing GitHub CLI..."
  brew install gh &>/dev/null
  export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
fi

_BS_GH_USER=""

# 1. Already authenticated — get username from existing session
if command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1; then
  _BS_GH_USER=$(gh api user --jq '.login' 2>/dev/null) || true
  [ -n "$_BS_GH_USER" ] && echo "    GitHub user: $_BS_GH_USER (existing gh session)"
fi

# 2. Not authenticated — try Bitwarden → GitHub token → authenticate → get username
if [ -z "$_BS_GH_USER" ]; then
  _BS_BW_KC_SVC="bitwarden-master"
  _BS_BW_KC_ACC="$USER"
  _BS_BW_GH_ITEM="github-cli-token"
  _BS_BW_FIELD="Key"

  if ! command -v bw &>/dev/null; then
    echo "    Installing Bitwarden CLI..."
    brew install bitwarden-cli &>/dev/null
    export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
  fi

  _BS_GH_TOKEN=""
  if command -v bw &>/dev/null; then
    _BS_BW_MASTER=$(security find-generic-password -a "$_BS_BW_KC_ACC" -s "$_BS_BW_KC_SVC" -w 2>/dev/null) || true
    if [ -z "$_BS_BW_MASTER" ]; then
      printf "    Bitwarden master password: "
      read -rs _BS_BW_MASTER < /dev/tty
      echo ""
    fi
    export __BS_BW_MASTER="$_BS_BW_MASTER"

    _BS_BW_STATUS=$(bw status 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('status','unauthenticated'))" 2>/dev/null || echo "unauthenticated")
    _BS_BW_SESSION=""

    if [ "$_BS_BW_STATUS" = "unauthenticated" ]; then
      printf "    Bitwarden email: "
      read -r _BS_BW_EMAIL < /dev/tty
      _BS_BW_SESSION=$(bw login "$_BS_BW_EMAIL" --passwordenv __BS_BW_MASTER --raw < /dev/tty) || true
    fi

    if [ -z "$_BS_BW_SESSION" ]; then
      _BS_BW_SESSION=$(bw unlock --passwordenv __BS_BW_MASTER --raw 2>/dev/null) || true
    fi
    unset __BS_BW_MASTER

    if [ -n "$_BS_BW_SESSION" ]; then
      echo "    Bitwarden unlocked — fetching GitHub token..."
      bw sync --session "$_BS_BW_SESSION" &>/dev/null || true
      _BS_GH_TOKEN=$(bw get item "$_BS_BW_GH_ITEM" --session "$_BS_BW_SESSION" 2>/dev/null \
        | python3 -c "
import sys,json
d=json.load(sys.stdin)
f=[x['value'] for x in d.get('fields',[]) if x['name']=='${_BS_BW_FIELD}']
if f:
    print(f[0].strip())
else:
    print((d.get('login',{}).get('password') or '').strip())
" 2>/dev/null) || true
    else
      echo "    WARN: Bitwarden unlock failed."
    fi
  fi

  if [ -n "$_BS_GH_TOKEN" ]; then
    echo "$_BS_GH_TOKEN" | gh auth login --with-token
    _BS_GH_USER=$(gh api user --jq '.login' 2>/dev/null) || true
    [ -n "$_BS_GH_USER" ] && echo "    GitHub user: $_BS_GH_USER (authenticated via Bitwarden)"
  fi
  unset _BS_GH_TOKEN _BS_BW_SESSION _BS_BW_MASTER _BS_BW_EMAIL _BS_BW_STATUS \
        _BS_BW_KC_SVC _BS_BW_KC_ACC _BS_BW_GH_ITEM _BS_BW_FIELD
fi

# 3. Still unknown — ask (one question only)
if [ -z "$_BS_GH_USER" ]; then
  printf "  GitHub username (leave blank to skip): "
  read -r _BS_GH_USER < /dev/tty
fi

# Pull config only if no local conf exists — local conf takes precedence
if [ -n "$_BS_GH_USER" ] && [ -f "$CONFIG_FILE" ]; then
  echo "    Local config already exists — skipping pull (local takes precedence)."
  CONF_PULLED=true
elif [ -n "$_BS_GH_USER" ]; then
  # Find the repo with the newest setup-emacs-mac.conf — scan repos directly
  # (code search has indexing delays; commits API is always real-time)
  _DATA_REPO_NAME=""
  if command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1; then
    echo "    Scanning your repos for newest setup-emacs-mac.conf..."
    _REPOS=$(gh api "user/repos?sort=pushed&direction=desc" --paginate \
      --jq '.[].name' 2>/dev/null) || true
    _BEST_DATE=""
    for _SCAN_REPO in $_REPOS; do
      _SCAN_DATE=$(gh api "repos/$_BS_GH_USER/$_SCAN_REPO/commits?path=config/setup-emacs-mac.conf&per_page=1" \
        --jq '.[0].commit.committer.date' 2>/dev/null) || true
      if [ -n "$_SCAN_DATE" ] && { [ -z "$_BEST_DATE" ] || [[ "$_SCAN_DATE" > "$_BEST_DATE" ]]; }; then
        _BEST_DATE="$_SCAN_DATE"
        _DATA_REPO_NAME="$_SCAN_REPO"
      fi
    done
    unset _REPOS _BEST_DATE _SCAN_DATE _SCAN_REPO
  fi
  # Fallback if nothing found
  [ -z "$_DATA_REPO_NAME" ] && _DATA_REPO_NAME="emacs-data"

  DATA_REPO="${_BS_GH_USER}/${_DATA_REPO_NAME}"
  unset _DATA_REPO_NAME
  echo "    Trying to pull config from github.com/${DATA_REPO}..."
  CONF_TMP=$(mktemp -d)
  mkdir -p "$CONF_TMP/conf"

  if command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1; then
    _CONF_CONTENT=$(gh api "repos/$DATA_REPO/contents/config/setup-emacs-mac.conf" --jq '.content' 2>/dev/null) || true
    if [ -n "$_CONF_CONTENT" ]; then
      echo "$_CONF_CONTENT" | tr -d '\n' | python3 -c "import sys,base64; sys.stdout.buffer.write(base64.b64decode(sys.stdin.read()))" \
        > "$CONF_TMP/conf/setup-emacs-mac.conf" 2>/dev/null && CONF_PULLED=true
    fi
    unset _CONF_CONTENT
  fi

  # Fallback: unauthenticated clone (public repos)
  if [ "$CONF_PULLED" = false ]; then
    if GIT_TERMINAL_PROMPT=0 git clone "https://github.com/${DATA_REPO}.git" "$CONF_TMP/conf" &>/dev/null 2>&1; then
      [ -f "$CONF_TMP/conf/config/setup-emacs-mac.conf" ] && CONF_PULLED=true
    fi
  fi

  _CONF_FILE="$CONF_TMP/conf/config/setup-emacs-mac.conf"
  [ ! -f "$_CONF_FILE" ] && _CONF_FILE="$CONF_TMP/conf/setup-emacs-mac.conf"
  if [ "$CONF_PULLED" = true ] && [ -f "$_CONF_FILE" ]; then
    _PULLED_NAME=$(grep '^GIT_NAME=' "$_CONF_FILE" | head -1)
    _PULLED_NAME="${_PULLED_NAME#*=}"; _PULLED_NAME="${_PULLED_NAME%\"}"; _PULLED_NAME="${_PULLED_NAME#\"}"
    if [ -n "$_PULLED_NAME" ]; then
      cp "$_CONF_FILE" "$CONFIG_FILE"
      echo "    setup-emacs-mac.conf pulled — config ready."
    else
      echo "    Pulled config is empty — will configure interactively."
      CONF_PULLED=false
    fi
    unset _PULLED_NAME
  else
    echo "    Config not found in repo — will configure interactively."
    CONF_PULLED=false
  fi
  rm -rf "$CONF_TMP"
fi
unset _BS_GH_USER

# --- Ensure config exists (copy template only if not yet present) ---
if [ "$CONF_PULLED" = false ] && [ ! -f "$CONFIG_FILE" ]; then
  cp "$DEST/setup-emacs-mac.conf.template" "$CONFIG_FILE"
  echo "==> setup-emacs-mac.conf created from template."
fi

if [ "$CONF_PULLED" = true ]; then
  echo "  Personal config pulled and ready."
fi

bash "$DEST/fill-config.sh"

# --- Bitwarden setup ---
source "$CONFIG_FILE"
echo ""
if [ -n "$GH_USER" ]; then
  bash "$DEST/setup-bitwarden.sh"
else
  echo "  GH_USER not set — local mode, Bitwarden not required."
  echo "  Run $DEST/setup-bitwarden.sh after setting GH_USER if you want GitHub sync."
fi

# --- GitHub auth (with token from Bitwarden) ---
if [ -n "$GH_USER" ]; then
  if ! command -v gh &>/dev/null; then
    echo "==> Installing GitHub CLI..."
    brew install gh &>/dev/null
    export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
  fi
  if gh auth status &>/dev/null 2>&1; then
    echo "==> GitHub auth: already authenticated."
  else
    echo "==> Authenticating GitHub..."
    source "$DEST/bw-unlock.sh" 2>/dev/null || true
    _BS_GH_TOKEN=""
    if bw_ensure_session; then
      _BS_GH_TOKEN=$(bw_get_field "$BW_GH_ITEM" "$BW_FIELD") || true
    fi
    if [ -n "$_BS_GH_TOKEN" ]; then
      echo "$_BS_GH_TOKEN" | gh auth login --with-token
      gh auth setup-git
      echo "    GitHub authenticated."
    else
      echo "    WARN: GitHub token not found in Bitwarden — manual login:"
      gh auth login < /dev/tty
      gh auth setup-git
    fi
    unset _BS_GH_TOKEN
  fi
fi

# --- Check and create GitHub repos ---
if [ -n "$GH_USER" ] && gh auth status &>/dev/null 2>&1; then
  echo ""
  echo "==> Checking GitHub repos..."
  source "$CONFIG_FILE"

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
echo "  Run a setup script when ready:"
echo "    bash $DEST/setup-emacs-native-plus-mac.sh      # recommended (LSP, native comp)"
echo "    bash $DEST/setup-emacs-native-yamamoto-mac.sh  # smooth rendering, trackpad"
echo "    bash $DEST/setup-emacs-docker-mac.sh           # isolated in Docker"
echo "    bash $DEST/setup-emacs-orbstack-mac.sh         # isolated in OrbStack, no XQuartz"
echo ""
  echo "  On a new Mac, just run bootstrap — GitHub user is detected automatically:"
  echo "    bash <(curl -fsSL https://raw.githubusercontent.com/deno1011/emacs-mac-setup/stable/bootstrap.sh)"
  echo ""
echo "  Docs: https://github.com/deno1011/emacs-mac-setup/blob/main/README.md"
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
