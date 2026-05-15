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
CONFIG_FILE="$HOME/setup-emacs-mac.conf"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "ERROR: Config file not found: $CONFIG_FILE"
  echo "Template: ~/setup-emacs-mac.conf.template"
  exit 1
fi
source "$CONFIG_FILE"
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

# --- Unlock Bitwarden upfront (GitHub mode only) ---
if [ -n "$GH_USER" ]; then
  if ! command -v bw &>/dev/null; then
    echo "==> Installing Bitwarden CLI..."
    brew install bitwarden-cli
  fi
  bw_ensure_session || exit 1
fi

# --- Tools (GitHub mode only) ---
if [ -n "$GH_USER" ]; then
  command -v bw &>/dev/null       && skip "Bitwarden CLI"  || { echo "==> Installing Bitwarden CLI..."; brew install bitwarden-cli; }
  command -v gh &>/dev/null       && skip "GitHub CLI"     || { echo "==> Installing GitHub CLI...";    brew install gh; }
  command -v git-crypt &>/dev/null && skip "git-crypt"     || { echo "==> Installing git-crypt...";     brew install git-crypt; }
fi

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

  # --- Use conf from emacs-data if already present (subsequent installs) ---
  _EMACS_DATA_CONF="$HOME/Library/Mobile Documents/com~apple~CloudDocs/$GH_REPO/config/setup-emacs-mac.conf"
  if [ -f "$_EMACS_DATA_CONF" ]; then
    cp "$_EMACS_DATA_CONF" "$CONFIG_FILE"
    source "$CONFIG_FILE"
    echo "==> setup-emacs-mac.conf loaded from emacs-data/config/."
  fi

  if [ -d "$ICLOUD_REPO_PATH/.git" ]; then
    skip "iCloud repo"
    git -C "$ICLOUD_REPO_PATH" remote set-url origin "https://github.com/${GH_USER}/${GH_REPO}.git"
    git -C "$ICLOUD_REPO_PATH" pull origin main || true
    # Modular config files are setup-managed — always overwrite from SCRIPT_DIR
    _CF_CHANGED=false
    for _CF in core.org org-setup.org gptel-setup.org; do
      if [ -f "$SCRIPT_DIR/$_CF" ]; then
        if ! diff -q "$SCRIPT_DIR/$_CF" "$ICLOUD_REPO_PATH/config/$_CF" &>/dev/null; then
          cp "$SCRIPT_DIR/$_CF" "$ICLOUD_REPO_PATH/config/$_CF"
          git -C "$ICLOUD_REPO_PATH" add "config/$_CF"
          echo "==> $_CF updated in repo."
          _CF_CHANGED=true
        fi
      fi
    done
    if [ "$_CF_CHANGED" = true ]; then
      git -C "$ICLOUD_REPO_PATH" -c user.email="$GIT_EMAIL" -c user.name="$GIT_NAME" \
        commit -m "chore: update modular config files" 2>/dev/null || true
      git -C "$ICLOUD_REPO_PATH" push origin main 2>/dev/null || true
    fi
    unset _CF _CF_CHANGED
  else
    echo "==> Cloning repo to iCloud..."
    if [ ! -d "$HOME/Library/Mobile Documents/com~apple~CloudDocs" ]; then
      echo "ERROR: iCloud Drive not available."
      echo "       Please enable iCloud Drive in System Settings and run again."
      exit 1
    fi
    git clone "https://github.com/${GH_USER}/${GH_REPO}.git" "$ICLOUD_REPO_PATH"

    mkdir -p "$ICLOUD_REPO_PATH/config" "$ICLOUD_REPO_PATH/data/org"
    if [ ! -f "$ICLOUD_REPO_PATH/config/config.org" ] && [ -f "$SCRIPT_DIR/config.org" ]; then
      cp "$SCRIPT_DIR/config.org"      "$ICLOUD_REPO_PATH/config/config.org"
      cp "$SCRIPT_DIR/core.org"        "$ICLOUD_REPO_PATH/config/core.org"        2>/dev/null || true
      cp "$SCRIPT_DIR/org-setup.org"   "$ICLOUD_REPO_PATH/config/org-setup.org"   2>/dev/null || true
      cp "$SCRIPT_DIR/gptel-setup.org" "$ICLOUD_REPO_PATH/config/gptel-setup.org" 2>/dev/null || true
      echo "    Config files copied to config/ subfolder."
    fi

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
    GC_KEY=$(bw_get_field "$BW_ITEM" "$BW_FIELD") || true
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
      echo "WARN: git-crypt key not found in Bitwarden."
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

# --- Local mode: config.org from scripts folder ---
else
  if [ ! -d "$EMACS_CONFIG_DIR" ]; then
    mkdir -p "$EMACS_CONFIG_DIR/config" "$EMACS_CONFIG_DIR/data/org"
    echo "==> ~/${GH_REPO}/ created."
  fi
  if [ ! -f "$EMACS_CONFIG_DIR/config/config.org" ] && [ -f "$SCRIPT_DIR/config.org" ]; then
    cp "$SCRIPT_DIR/config.org" "$EMACS_CONFIG_DIR/config/config.org"
    echo "==> config.org copied to ~/${GH_REPO}/config/."
  elif [ -f "$EMACS_CONFIG_DIR/config/config.org" ]; then
    skip "config.org (user-managed — not overwritten)"
  else
    echo "WARN: No config.org found — Emacs will start with basic setup."
  fi
  # Modular files are setup-managed — always update like init.el
  for _CF in core.org org-setup.org gptel-setup.org; do
    [ -f "$SCRIPT_DIR/$_CF" ] && cp "$SCRIPT_DIR/$_CF" "$EMACS_CONFIG_DIR/config/$_CF" \
      && echo "==> $_CF updated."
  done
  unset _CF
fi

echo "==> Populating ~/.emacs.d/config-readonly/..."
mkdir -p "$HOME/.emacs.d/config-readonly"
rsync -a --delete "$EMACS_CONFIG_DIR/config/" "$HOME/.emacs.d/config-readonly/"
echo "    config-readonly/ updated."

# --- init.el — always update (managed by setup, not user-customized) ---
if [ -f "$SCRIPT_DIR/init.el" ]; then
  mkdir -p "$HOME/.emacs.d"
  cp "$SCRIPT_DIR/init.el" "$EMACS_INIT"
  echo "==> init.el updated."
else
  echo "ERROR: init.el not found — re-run bootstrap.sh."
  exit 1
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
echo "Start Emacs:  open \"/Applications/$_EMACS_APP_NAME\""
echo ""
if [ -n "$GH_USER" ]; then
  echo "Your config:  ~/${GH_REPO}/config/  (synced via iCloud + GitHub)"
  echo "Your org files: ~/${GH_REPO}/data/org/"
else
  echo "Your config:  ~/${GH_REPO}/config/  (local)"
  echo "To enable GitHub sync: set GH_USER in ~/setup-emacs-mac.conf and re-run."
fi
echo "======================================================================"
