#!/bin/bash
set -e

[ -f /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
[ -f /usr/local/bin/brew ]    && eval "$(/usr/local/bin/brew shellenv)"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skip() { echo "==> Already done: $1 — skipping."; }

# --- Flavor parameter (set by wrapper scripts or directly via EMACS_FLAVOR=...) ---
case "${EMACS_FLAVOR:-plus}" in
  yamamoto)
    _EMACS_PKG="emacs-mac@30exp"
    _EMACS_OTHER_PKG="emacs-plus@30"
    _EMACS_TAP="railwaycat/emacsmacport"
    _EMACS_APP_NAME="Yamamoto Emacs.app"
    _EMACS_LABEL="Yamamoto"
    _EMACS_UNINSTALL="uninstall-emacs-native-yamamoto-mac.sh"
    ;;
  plus|*)
    _EMACS_PKG="emacs-plus@30"
    _EMACS_OTHER_PKG="emacs-mac@30exp"
    _EMACS_TAP="d12frosted/emacs-plus"
    _EMACS_APP_NAME="Plus Emacs.app"
    _EMACS_LABEL="emacs-plus"
    _EMACS_UNINSTALL="uninstall-emacs-native-plus-mac.sh"
    ;;
esac

# --- Emacs check ---
echo "==> Emacs check..."
if brew list 2>/dev/null | grep -q "^${_EMACS_OTHER_PKG}"; then
  echo "  NOTE: $_EMACS_OTHER_PKG is also installed."
  echo "        $_EMACS_PKG will be linked as the active version."
fi
if brew list 2>/dev/null | grep -q "^${_EMACS_PKG}"; then
  EMACS_VER=$(emacs --version 2>/dev/null | head -1 || echo "unknown")
  echo "  $_EMACS_PKG bereits installiert: $EMACS_VER"
  echo "  Zum Deinstallieren: ~/$_EMACS_UNINSTALL"
fi

# --- Load configuration ---
CONFIG_FILE="$HOME/emacs-mac-setup/setup-emacs-mac.conf"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "ERROR: Config file not found: $CONFIG_FILE"
  echo "Template: ~/emacs-mac-setup/setup-emacs-mac.conf.template"
  exit 1
fi
source "$SCRIPT_DIR/setup-lib.sh"
trap 'setup_runtime_cleanup_secret_keychain 2>/dev/null || true' EXIT
setup_runtime_load
setup_try_load_private_config_from_github || true
setup_runtime_load

# --- Validate required fields (only when GitHub is configured) ---
if [ -n "$GH_USER" ]; then
  setup_runtime_require GIT_NAME GIT_EMAIL GH_REPO BW_FIELD BW_ITEM BW_GH_ITEM BW_ANTHROPIC_ITEM BW_GEMINI_ITEM BW_KEYCHAIN_SERVICE BITWARDEN_EMAIL BITWARDEN_MASTER_PASSWORD
fi

# --- Set paths ---
EMACS_INIT="$HOME/.emacs.d/init.el"
EMACS_SECRETS="$HOME/.emacs.d/secrets.el"
if [ -n "$GH_USER" ]; then
  ICLOUD_REPO_PATH="$HOME/Library/Mobile Documents/com~apple~CloudDocs/$GH_REPO"
  EMACS_CONFIG_DIR="$HOME/$GH_REPO"
else
  EMACS_CONFIG_DIR="$HOME/${GH_REPO:-emacs-data}"
  echo "==> GitHub not configured — using local config."
fi

# --- Homebrew ---
if ! command -v brew &>/dev/null; then
  echo "ERROR: Homebrew not found. Please install: https://brew.sh"
  exit 1
fi

# --- Clean up stale symlinks upfront (prevents brew link errors) ---
for _PKG in node coreutils; do
  brew unlink "$_PKG" 2>/dev/null || true
done

# --- Tools (GitHub mode only) ---
if [ -n "$GH_USER" ]; then
  command -v bw &>/dev/null       && skip "Bitwarden CLI"  || { echo "==> Installing Bitwarden CLI..."; brew install bitwarden-cli; }
  command -v gh &>/dev/null       && skip "GitHub CLI"     || { echo "==> Installing GitHub CLI...";    brew install gh; }
  command -v git-crypt &>/dev/null && skip "git-crypt"     || { echo "==> Installing git-crypt...";     brew install git-crypt; }
  setup_runtime_load_bitwarden_secrets || exit 1
fi

# --- Local AI runtime (Ollama + default model) ---
_truthy() {
  case "$1" in
    1|yes|YES|true|TRUE|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

unset -f _truthy

# Note: Ollama is no longer installed by default. The default gptel
# backend is Gemini 2.0 Flash (free tier — see secrets.el block below
# for the BW-mediated key bootstrap). Local-model fans can still
# install Ollama manually:
#
#   brew install ollama && ollama pull qwen2.5-coder:7b && ollama serve &
#
# The Ollama backend remains registered in gptel-setup.org and
# auto-activates whenever `executable-find "ollama"' succeeds, so no
# config changes are needed if you opt in.

# --- Install Emacs ---
brew unlink "$_EMACS_OTHER_PKG" 2>/dev/null || true
brew unlink coreutils 2>/dev/null || true
if brew list 2>/dev/null | grep -q "^${_EMACS_PKG}"; then
  skip "Emacs ($_EMACS_PKG)"
else
  echo "==> Installing Emacs ($_EMACS_PKG)..."
  echo "    This may take 10-25 minutes..."
  brew tap "$_EMACS_TAP"
  if [ "${EMACS_FLAVOR:-plus}" = "yamamoto" ]; then
    if ! brew install "railwaycat/emacsmacport/emacs-mac@30exp"; then
      echo ""
      echo "ERROR: emacs-mac@30exp build failed."
      echo "       Alternatives:"
      echo "         1. Use stable emacs-plus: ~/setup-emacs-native-plus-mac.sh"
      echo "         2. Report issues: https://github.com/railwaycat/homebrew-emacsmacport/issues"
      exit 1
    fi
  else
    brew install emacs-plus@30 --with-xwidgets
  fi
fi
brew link --overwrite "$_EMACS_PKG" 2>/dev/null || true

# Wipe stale .elc files — byte-compiled files from a different Emacs version
# cause silent package load failures when switching between plus and yamamoto
echo "==> Clearing stale byte-compiled packages..."
find "$HOME/.emacs.d/elpa" -name "*.elc" -delete 2>/dev/null && echo "    Done." || true

_EMACS_CELLAR_DIR="$(brew --prefix)/Cellar/$_EMACS_PKG"
EMACS_APP=$(find "$_EMACS_CELLAR_DIR" -name "Emacs.app" -maxdepth 4 2>/dev/null | head -1)
if [ -n "$EMACS_APP" ]; then
  rm -rf "/Applications/$_EMACS_APP_NAME"
  cp -r "$EMACS_APP" "/Applications/$_EMACS_APP_NAME"
  echo "==> $_EMACS_APP_NAME → /Applications"
else
  echo "WARN: Emacs.app not found under $_EMACS_CELLAR_DIR"
fi

EMACS_BIN=$(find "$_EMACS_CELLAR_DIR" -name "emacs" -path "*/bin/emacs" -maxdepth 4 2>/dev/null | head -1)
[ -z "$EMACS_BIN" ] && EMACS_BIN=$(command -v emacs 2>/dev/null) || true
if [ -z "$EMACS_BIN" ]; then
  echo "ERROR: Emacs binary not found after installation."
  exit 1
fi
echo "==> Using Emacs: $EMACS_BIN"

# --- GitHub-Modus: Auth, Repo, Symlink ---
if [ -n "$GH_USER" ]; then
  if gh auth status &>/dev/null 2>&1; then
    skip "GitHub CLI auth"
  else
    echo "==> Authenticating GitHub CLI with token from setup runtime..."
    if [ -n "${GITHUB_TOKEN:-}" ]; then
      if echo "$GITHUB_TOKEN" | gh auth login --with-token 2>/dev/null; then
        gh auth setup-git
      else
        setup_fail "GitHub token is invalid or expired." "bash ~/emacs-mac-setup/setup-intake.sh --repair github-token"
      fi
    else
      setup_fail "GitHub token missing after intake." "bash ~/emacs-mac-setup/setup-intake.sh --repair github-token"
    fi
  fi

  # --- Use conf from emacs-data if already present (subsequent installs) ---
  _EMACS_DATA_CONF="$HOME/Library/Mobile Documents/com~apple~CloudDocs/$GH_REPO/config/setup-emacs-mac.conf"
  if [ -f "$_EMACS_DATA_CONF" ]; then
    cp "$_EMACS_DATA_CONF" "$CONFIG_FILE"
    setup_runtime_load
    setup_runtime_load_bitwarden_secrets || exit 1
    echo "==> setup-emacs-mac.conf loaded from emacs-data/config/."
  fi

  # Detect GH_REPO rename — find iCloud symlink from same GitHub user with different name
  _OLD_REPO=""
  while IFS= read -r -d '' _LINK; do
    _CNAME=$(basename "$_LINK")
    [ "$_CNAME" = "$GH_REPO" ] && continue
    _TARGET=$(readlink "$_LINK")
    if [[ "$_TARGET" == *"CloudDocs"* ]] && [ -d "$_LINK/.git" ]; then
      _REMOTE=$(git -C "$_LINK" remote get-url origin 2>/dev/null) || true
      if [[ "$_REMOTE" == *"github.com/$GH_USER/"* ]]; then
        _OLD_REPO="$_CNAME"; break
      fi
    fi
  done < <(find "$HOME" -maxdepth 1 -type l -print0 2>/dev/null)

  if [ -n "$_OLD_REPO" ]; then
    echo "==> GH_REPO renamed: $_OLD_REPO → $GH_REPO"
    _OLD_ICLOUD="$HOME/Library/Mobile Documents/com~apple~CloudDocs/$_OLD_REPO"
    gh api "repos/$GH_USER/$_OLD_REPO" -X PATCH -f name="$GH_REPO" &>/dev/null \
      && echo "    GitHub repo renamed." || echo "    WARN: GitHub rename failed — do it manually in repo settings."
    if [ -d "$_OLD_ICLOUD" ] && [ ! -d "$ICLOUD_REPO_PATH" ]; then
      mv "$_OLD_ICLOUD" "$ICLOUD_REPO_PATH" && echo "    iCloud folder renamed."
    fi
    [ -d "$ICLOUD_REPO_PATH/.git" ] && \
      git -C "$ICLOUD_REPO_PATH" remote set-url origin "https://github.com/$GH_USER/$GH_REPO.git"
    rm -f "$HOME/$_OLD_REPO"
    ln -sfn "$ICLOUD_REPO_PATH" "$HOME/$GH_REPO"
    echo "    Symlink updated: ~/$_OLD_REPO → ~/$GH_REPO"
  fi
  unset _OLD_REPO _LINK _CNAME _TARGET _REMOTE _OLD_ICLOUD

  if [ -d "$ICLOUD_REPO_PATH/.git" ]; then
    skip "iCloud repo"
    git -C "$ICLOUD_REPO_PATH" remote set-url origin "https://github.com/${GH_USER}/${GH_REPO}.git"
    git -C "$ICLOUD_REPO_PATH" pull origin main || true
    # Config files (config.org + the split files) self-bootstrap from
    # emacs-mac-setup/stable on first Emacs run via init.el's
    # my/ensure-config-file-from-url, and via config.org's own
    # my/ensure-config-file for the split files. No cp from this
    # script needed — keeps the setup script narrow and the bootstrap
    # logic in one place.
  else
    echo "==> Cloning repo to iCloud..."
    if [ ! -d "$HOME/Library/Mobile Documents/com~apple~CloudDocs" ]; then
      echo "ERROR: iCloud Drive not available."
      echo "       Please enable iCloud Drive in System Settings and run again."
      exit 1
    fi
    git clone "https://github.com/${GH_USER}/${GH_REPO}.git" "$ICLOUD_REPO_PATH"

    _EMACS_DATA_CONF="$ICLOUD_REPO_PATH/config/setup-emacs-mac.conf"
    if [ -f "$_EMACS_DATA_CONF" ]; then
      cp "$_EMACS_DATA_CONF" "$CONFIG_FILE"
      setup_runtime_load
      setup_runtime_load_bitwarden_secrets || exit 1
      echo "==> setup-emacs-mac.conf loaded from cloned emacs-data/config/."
    fi

    mkdir -p "$ICLOUD_REPO_PATH/config" "$ICLOUD_REPO_PATH/data/org"
    # config.org and the split files (core/org-setup/gptel-setup/wiki-setup/
    # org-apple-reminders-setup) self-bootstrap from emacs-mac-setup/stable
    # on first Emacs run via init.el. No cp from SCRIPT_DIR needed.

    git -C "$ICLOUD_REPO_PATH" config user.email "$GIT_EMAIL"
    git -C "$ICLOUD_REPO_PATH" config user.name "$GIT_NAME"

    cat > "$ICLOUD_REPO_PATH/.git/hooks/post-commit" << 'HOOKEOF'
#!/bin/sh
REPO_ORG="$(git rev-parse --show-toplevel)/data/org"
BEORG="$HOME/Library/Mobile Documents/iCloud~com~appsonthemove~beorg/Documents/org"
[ -d "$BEORG" ] && rsync -a --delete "$REPO_ORG/" "$BEORG/" 2>/dev/null || true
git push origin main &
HOOKEOF
    chmod +x "$ICLOUD_REPO_PATH/.git/hooks/post-commit"
    echo "    iCloud repo set up."
  fi

  # --- git-crypt: initialise (fresh repo) or unlock (already encrypted) ---
  _GC_INITIALIZED=false
  [ -d "$ICLOUD_REPO_PATH/.git/git-crypt" ] && _GC_INITIALIZED=true

  _FIRST_ORG=$(find "$ICLOUD_REPO_PATH/data/org" -name "*.org" 2>/dev/null | head -1)
  _FILES_ENCRYPTED=false
  [ -n "$_FIRST_ORG" ] && file "$_FIRST_ORG" | grep -q "data" && _FILES_ENCRYPTED=true

  if [ "$_GC_INITIALIZED" = false ] || [ "$_FILES_ENCRYPTED" = true ]; then
    GC_KEY="${GIT_CRYPT_KEY:-}"
    if [ -n "$GC_KEY" ]; then
      if echo "$GC_KEY" | tr -d '[:space:]' | python3 -c "import sys,base64; data=sys.stdin.read().strip(); sys.stdout.buffer.write(base64.b64decode(data + '=='))" > /tmp/gckey 2>/dev/null; then
        if [ "$_GC_INITIALIZED" = false ]; then
          echo "==> Initialising git-crypt (fresh repo)..."
          (cd "$ICLOUD_REPO_PATH" && git crypt init) 2>/dev/null
          cp /tmp/gckey "$ICLOUD_REPO_PATH/.git/git-crypt/keys/default"
          if [ ! -f "$ICLOUD_REPO_PATH/.gitattributes" ]; then
            echo "data/org/** filter=git-crypt diff=git-crypt" > "$ICLOUD_REPO_PATH/.gitattributes"
            git -C "$ICLOUD_REPO_PATH" add .gitattributes
            git -C "$ICLOUD_REPO_PATH" -c user.email="$GIT_EMAIL" -c user.name="$GIT_NAME" \
              commit -m "Add git-crypt for data/org/ directory" 2>/dev/null || true
            git -C "$ICLOUD_REPO_PATH" push origin main 2>/dev/null || true
          fi
          echo "    git-crypt initialised."
        else
          if git -C "$ICLOUD_REPO_PATH" crypt unlock /tmp/gckey 2>/dev/null; then
            git -C "$ICLOUD_REPO_PATH" checkout HEAD -- data/org/ 2>/dev/null || true
            echo "    git-crypt unlocked and org/ checked out."
          else
            echo "WARN: git-crypt unlock failed — org/ files still encrypted."
          fi
        fi
      else
        echo "WARN: Bitwarden value is not valid Base64."
      fi
      rm -f /tmp/gckey
    else
      echo "WARN: git-crypt key not found in setup runtime."
    fi
  else
    skip "git-crypt (data/org/ already decrypted)"
  fi

  if [ -L "$EMACS_CONFIG_DIR" ] && [ "$(readlink "$EMACS_CONFIG_DIR")" = "$ICLOUD_REPO_PATH" ]; then
    skip "Symlink ~/${GH_REPO}"
  else
    echo "==> Symlink ~/${GH_REPO} → iCloud erstellen..."
    ln -sfn "$ICLOUD_REPO_PATH" "$EMACS_CONFIG_DIR"
  fi

  echo "==> Saving setup-emacs-mac.conf to ~/${GH_REPO}/config/..."
  cp "$CONFIG_FILE" "$ICLOUD_REPO_PATH/config/setup-emacs-mac.conf"
  git -C "$ICLOUD_REPO_PATH" add "config/setup-emacs-mac.conf"
  git -C "$ICLOUD_REPO_PATH" commit -m "chore: update setup-emacs-mac.conf" \
    -c user.email="$GIT_EMAIL" -c user.name="$GIT_NAME" 2>/dev/null || true

# --- Local mode: config.org self-bootstraps on first Emacs run -----
else
  if [ ! -d "$EMACS_CONFIG_DIR" ]; then
    mkdir -p "$EMACS_CONFIG_DIR/config" "$EMACS_CONFIG_DIR/data/org"
    echo "==> ~/${GH_REPO}/ created."
  fi
  # config.org and the split files self-bootstrap from emacs-mac-setup/
  # stable on first Emacs run via init.el's my/ensure-config-file-from-url.
  # No cp from SCRIPT_DIR needed — single source of truth for the
  # bootstrap logic lives in init.el.
fi

echo "==> Populating ~/.emacs.d/config-readonly/..."
mkdir -p "$HOME/.emacs.d/config-readonly"
rsync -a --delete "$EMACS_CONFIG_DIR/config/" "$HOME/.emacs.d/config-readonly/"
echo "    config-readonly/ updated."

# --- init.el — always update (managed by setup, not user-customized) ---
if [ -f "$SCRIPT_DIR/init.el" ]; then
  mkdir -p "$HOME/.emacs.d"
  sed "s|GH_REPO|${GH_REPO}|g" "$SCRIPT_DIR/init.el" > "$EMACS_INIT"
  echo "==> init.el updated."
else
  echo "ERROR: init.el not found — re-run bootstrap.sh."
  exit 1
fi

# --- secrets.el ---
# API keys are read from the up-front setup runtime only. Missing keys are
# repaired through intake, keeping the installer non-interactive after intake.
if [ -f "$EMACS_SECRETS" ]; then
  skip "secrets.el"
else
  mkdir -p "$HOME/.emacs.d"
  if [ -n "$GH_USER" ]; then
    echo ";; secrets.el — API keys (not tracked in git)" > "$EMACS_SECRETS"

    if [ -n "$ANTHROPIC_API_KEY" ]; then
      printf '(setenv "ANTHROPIC_API_KEY" "%s")\n' "$ANTHROPIC_API_KEY" >> "$EMACS_SECRETS"
    else
      echo ";; ANTHROPIC_API_KEY: run setup-intake.sh --repair anthropic" >> "$EMACS_SECRETS"
    fi

    if [ -n "$GEMINI_API_KEY" ]; then
      printf '(setenv "GEMINI_API_KEY" "%s")\n' "$GEMINI_API_KEY" >> "$EMACS_SECRETS"
    else
      echo ";; GEMINI_API_KEY: run setup-intake.sh --repair gemini" >> "$EMACS_SECRETS"
    fi

    echo "==> secrets.el written."
    if [ -z "$GEMINI_API_KEY" ] || [ -z "$ANTHROPIC_API_KEY" ]; then
      echo "    Missing API keys can be added with:"
      echo "      bash ~/emacs-mac-setup/setup-intake.sh --repair bitwarden"
    fi
  else
    echo ";; secrets.el — add API keys here" > "$EMACS_SECRETS"
    echo "==> secrets.el created (empty — no GitHub/Bitwarden configured)."
  fi
fi

# --- Set global git identity (GitHub mode only) ---
if [ -n "$GH_USER" ]; then
  if git config --global user.email 2>/dev/null | grep -q "@"; then
    skip "Git identity"
  else
    echo "==> Setting git identity..."
    git config --global user.email "$GIT_EMAIL"
    git config --global user.name "$GIT_NAME"
  fi
fi

if [ -n "$GH_USER" ]; then
  setup_runtime_cleanup_secret_keychain
fi

echo ""
echo "======================================================================"
echo "Native Emacs ($_EMACS_LABEL) setup complete!"
echo "======================================================================"
echo ""
echo "Start Emacs:  open \"/Applications/$_EMACS_APP_NAME\""
echo ""
if [ -n "$GH_USER" ]; then
  echo "Your config:  ~/${GH_REPO}/config/  (synced via iCloud + GitHub)"
  echo "Your org files: ~/${GH_REPO}/data/org/"
else
  echo "Your config:  ~/${GH_REPO}/config/  (local)"
  echo "To enable GitHub sync: set GH_USER in ~/emacs-mac-setup/setup-emacs-mac.conf and re-run."
fi
echo "======================================================================"
