#!/bin/bash
set -e

[ -f /opt/homebrew/bin/brew ]        && eval "$(/opt/homebrew/bin/brew shellenv)"
[ -f /usr/local/bin/brew ]           && eval "$(/usr/local/bin/brew shellenv)"
[ -f "$HOME/homebrew/bin/brew" ]     && eval "$($HOME/homebrew/bin/brew shellenv)"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skip() { echo "==> Already done: $1 — skipping."; }

# --- Detect Homebrew write access ---
_BREW_WRITABLE=false
[ -w "$(brew --prefix 2>/dev/null)" ] && _BREW_WRITABLE=true

brew_install_or_warn() {
  local PKG="$1"; shift
  if brew list "$PKG" &>/dev/null 2>&1 || brew list --cask "$PKG" &>/dev/null 2>&1; then
    skip "$PKG"; return 0
  fi
  if [ "$_BREW_WRITABLE" = true ]; then
    brew install "$PKG" "$@"
  else
    echo "WARN: $PKG not installed — Homebrew is read-only for this user."
    echo "      Ask the Mac owner to run: brew install $PKG $*"
    return 1
  fi
}

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
CONFIG_FILE="$HOME/setup-emacs-mac.conf"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "ERROR: Config file not found: $CONFIG_FILE"
  echo "Template: ~/setup-emacs-mac.conf.template"
  exit 1
fi
source "$CONFIG_FILE"
# Normalise CONF_REPO: strip any leading "user/" prefix in case the config contains the full form
CONF_REPO="${CONF_REPO##*/}"
source "$HOME/bw-unlock.sh"

# --- Validate required fields (only when GitHub is configured) ---
if [ -n "$GH_USER" ]; then
  MISSING=()
  [ -z "$GIT_NAME" ]  && MISSING+=("GIT_NAME")
  [ -z "$GIT_EMAIL" ] && MISSING+=("GIT_EMAIL")
  [ -z "$GH_REPO" ]   && MISSING+=("GH_REPO")
  if [ ${#MISSING[@]} -gt 0 ]; then
    echo "ERROR: GH_USER is set but the following fields are missing in $CONFIG_FILE:"
    for F in "${MISSING[@]}"; do echo "  $F"; done
    exit 1
  fi
fi

# --- Set paths ---
EMACS_INIT="$HOME/.emacs.d/init.el"
EMACS_SECRETS="$HOME/.emacs.d/secrets.el"
if [ -n "$GH_USER" ]; then
  ICLOUD_REPO_PATH="$HOME/Library/Mobile Documents/com~apple~CloudDocs/$GH_REPO"
  EMACS_CONFIG_DIR="$HOME/$GH_REPO"
else
  EMACS_CONFIG_DIR="$HOME/emacs-config"
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

# --- Unlock Bitwarden upfront (GitHub mode only) ---
if [ -n "$GH_USER" ]; then
  if [ ! -d "$ICLOUD_REPO_PATH/.git" ] || ! gh auth status &>/dev/null 2>&1 || [ ! -f "$EMACS_SECRETS" ]; then
    if ! command -v bw &>/dev/null; then
      echo "==> Installing Bitwarden CLI..."
      brew install bitwarden-cli
    fi
    bw_ensure_session || exit 1
  fi
fi

# --- Tools (GitHub mode only) ---
if [ -n "$GH_USER" ]; then
  command -v bw &>/dev/null        || brew_install_or_warn bitwarden-cli
  command -v gh &>/dev/null        || brew_install_or_warn gh
  command -v git-crypt &>/dev/null || brew_install_or_warn git-crypt
fi

# --- Install Emacs ---
brew unlink "$_EMACS_OTHER_PKG" 2>/dev/null || true
brew unlink coreutils 2>/dev/null || true
if brew list 2>/dev/null | grep -q "^${_EMACS_PKG}"; then
  skip "Emacs ($_EMACS_PKG)"
else
  if [ "$_BREW_WRITABLE" = false ]; then
    echo "ERROR: Emacs ($_EMACS_PKG) is not installed and Homebrew is read-only for this user."
    echo "       Ask the Mac owner to run this setup script first, then re-run as this user."
    exit 1
  fi
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
  if [ -w /Applications ]; then
    _APP_DEST="/Applications"
  else
    _APP_DEST="$HOME/Applications"
    mkdir -p "$_APP_DEST"
    echo "    NOTE: /Applications not writable — installing to ~/Applications/ instead."
  fi
  rm -rf "$_APP_DEST/$_EMACS_APP_NAME"
  cp -r "$EMACS_APP" "$_APP_DEST/$_EMACS_APP_NAME"
  echo "==> $_EMACS_APP_NAME → $_APP_DEST"
else
  echo "WARN: Emacs.app not found under $_EMACS_CELLAR_DIR"
  _APP_DEST="/Applications"
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
    echo "==> Authenticating GitHub CLI with token from Bitwarden..."
    GH_TOKEN=$(bw_get_field "$BW_GH_ITEM" "$BW_FIELD") || true
    if [ -n "$GH_TOKEN" ]; then
      if echo "$GH_TOKEN" | gh auth login --with-token 2>/dev/null; then
        gh auth setup-git
      else
        echo "WARN: GitHub Token expired or invalid — please log in manually:"
        gh auth login < /dev/tty
        gh auth setup-git
      fi
    else
      echo "WARN: GitHub token not found in Bitwarden. Please log in manually:"
      gh auth login < /dev/tty
      gh auth setup-git
    fi
  fi

  # --- Pull conf from private repo (if configured) ---
  if [ -n "$CONF_REPO" ]; then
    CONF_URL="https://github.com/${GH_USER}/${CONF_REPO}.git"
    CONF_TMP=$(mktemp -d)
    if git clone "$CONF_URL" "$CONF_TMP" &>/dev/null 2>&1; then
      if [ -f "$CONF_TMP/setup-emacs-mac.conf" ]; then
        cp "$CONF_TMP/setup-emacs-mac.conf" "$CONFIG_FILE"
        source "$CONFIG_FILE"
        echo "==> setup-emacs-mac.conf updated from private repo."
      fi
    else
      echo "WARN: Private conf repo not reachable ($CONF_REPO) — using local config."
    fi
    rm -rf "$CONF_TMP"
    ICLOUD_REPO_PATH="$HOME/Library/Mobile Documents/com~apple~CloudDocs/$GH_REPO"
    EMACS_CONFIG_DIR="$HOME/$GH_REPO"
  fi

  if [ -d "$ICLOUD_REPO_PATH/.git" ]; then
    skip "iCloud repo"
    git -C "$ICLOUD_REPO_PATH" remote set-url origin "https://github.com/${GH_USER}/${GH_REPO}.git"
    git -C "$ICLOUD_REPO_PATH" pull origin main || true
  else
    echo "==> Cloning repo to iCloud..."
    if [ ! -d "$HOME/Library/Mobile Documents/com~apple~CloudDocs" ]; then
      echo "ERROR: iCloud Drive not available."
      echo "       Please enable iCloud Drive in System Settings and run again."
      exit 1
    fi
    git clone "https://github.com/${GH_USER}/${GH_REPO}.git" "$ICLOUD_REPO_PATH"

    if [ ! -f "$ICLOUD_REPO_PATH/config.org" ] && [ -f "$SCRIPT_DIR/config.org" ]; then
      cp "$SCRIPT_DIR/config.org" "$ICLOUD_REPO_PATH/config.org"
      echo "    config.org copied from local fallback."
    fi

    git -C "$ICLOUD_REPO_PATH" config user.email "$GIT_EMAIL"
    git -C "$ICLOUD_REPO_PATH" config user.name "$GIT_NAME"

    cat > "$ICLOUD_REPO_PATH/.git/hooks/post-commit" << 'HOOKEOF'
#!/bin/sh
REPO_ORG="$(git rev-parse --show-toplevel)/org"
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

  _FIRST_ORG=$(find "$ICLOUD_REPO_PATH/org" -name "*.org" 2>/dev/null | head -1)
  _FILES_ENCRYPTED=false
  [ -n "$_FIRST_ORG" ] && file "$_FIRST_ORG" | grep -q "data" && _FILES_ENCRYPTED=true

  if [ "$_GC_INITIALIZED" = false ] || [ "$_FILES_ENCRYPTED" = true ]; then
    GC_KEY=$(bw_get_field "$BW_ITEM" "$BW_FIELD") || true
    if [ -n "$GC_KEY" ]; then
      if echo "$GC_KEY" | tr -d '[:space:]' | python3 -c "import sys,base64; data=sys.stdin.read().strip(); sys.stdout.buffer.write(base64.b64decode(data + '=='))" > /tmp/gckey 2>/dev/null; then
        if [ "$_GC_INITIALIZED" = false ]; then
          echo "==> Initialising git-crypt (fresh repo)..."
          (cd "$ICLOUD_REPO_PATH" && git crypt init) 2>/dev/null
          cp /tmp/gckey "$ICLOUD_REPO_PATH/.git/git-crypt/keys/default"
          if [ ! -f "$ICLOUD_REPO_PATH/.gitattributes" ]; then
            echo "org/** filter=git-crypt diff=git-crypt" > "$ICLOUD_REPO_PATH/.gitattributes"
            git -C "$ICLOUD_REPO_PATH" add .gitattributes
            git -C "$ICLOUD_REPO_PATH" -c user.email="$GIT_EMAIL" -c user.name="$GIT_NAME" \
              commit -m "Add git-crypt for org/ directory" 2>/dev/null || true
            git -C "$ICLOUD_REPO_PATH" push origin main 2>/dev/null || true
          fi
          echo "    git-crypt initialised."
        else
          if git -C "$ICLOUD_REPO_PATH" crypt unlock /tmp/gckey 2>/dev/null; then
            git -C "$ICLOUD_REPO_PATH" checkout HEAD -- org/ 2>/dev/null || true
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
      echo "WARN: git-crypt key not found in Bitwarden."
    fi
  else
    skip "git-crypt (org/ already decrypted)"
  fi

  if [ -L "$EMACS_CONFIG_DIR" ] && [ "$(readlink "$EMACS_CONFIG_DIR")" = "$ICLOUD_REPO_PATH" ]; then
    skip "Symlink ~/emacs-config"
  else
    echo "==> Symlink ~/emacs-config → iCloud erstellen..."
    ln -sfn "$ICLOUD_REPO_PATH" "$EMACS_CONFIG_DIR"
  fi

# --- Local mode: config.org from scripts folder ---
else
  if [ ! -d "$EMACS_CONFIG_DIR" ]; then
    mkdir -p "$EMACS_CONFIG_DIR"
    echo "==> ~/emacs-config/ created."
  fi
  if [ ! -f "$EMACS_CONFIG_DIR/config.org" ] && [ -f "$SCRIPT_DIR/config.org" ]; then
    cp "$SCRIPT_DIR/config.org" "$EMACS_CONFIG_DIR/config.org"
    echo "==> config.org copied to ~/emacs-config/."
  elif [ -f "$EMACS_CONFIG_DIR/config.org" ]; then
    skip "config.org (already present)"
  else
    echo "WARN: No config.org found — Emacs will start with basic setup."
  fi
fi

# --- init.el ---
if [ -f "$EMACS_INIT" ]; then
  skip "init.el"
else
  mkdir -p "$HOME/.emacs.d"
  if [ -f "$SCRIPT_DIR/init.el" ]; then
    cp "$SCRIPT_DIR/init.el" "$EMACS_INIT"
    echo "==> init.el installiert."
  else
    echo "ERROR: init.el not found — re-run bootstrap.sh."
    exit 1
  fi
fi

# --- secrets.el ---
if [ -f "$EMACS_SECRETS" ]; then
  skip "secrets.el"
else
  mkdir -p "$HOME/.emacs.d"
  if [ -n "$GH_USER" ] && [ -n "$BW_SESSION" ]; then
    echo "==> Fetching Anthropic API key from Bitwarden..."
    ANTHROPIC_API_KEY=$(bw_get_field "$BW_ANTHROPIC_ITEM" "$BW_FIELD") || true
    if [ -n "$ANTHROPIC_API_KEY" ]; then
      printf '(setenv "ANTHROPIC_API_KEY" "%s")\n' "$ANTHROPIC_API_KEY" > "$EMACS_SECRETS"
      echo "    secrets.el written with API key."
    else
      echo "WARN: Anthropic API key not found — empty secrets.el created."
      echo ";; secrets.el — add API keys here" > "$EMACS_SECRETS"
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

echo ""
echo "======================================================================"
echo "Native Emacs ($_EMACS_LABEL) setup complete!"
echo "======================================================================"
echo ""
echo "Start Emacs:  open \"$_APP_DEST/$_EMACS_APP_NAME\""
echo ""
if [ -n "$GH_USER" ]; then
  echo "Your config:  ~/emacs-config/config.org  (synced via iCloud + GitHub)"
  echo "Your org files: ~/emacs-config/org/"
else
  echo "Your config:  ~/emacs-config/config.org  (local)"
  echo "To enable GitHub sync: set GH_USER in ~/setup-emacs-mac.conf and re-run."
fi
echo "======================================================================"
