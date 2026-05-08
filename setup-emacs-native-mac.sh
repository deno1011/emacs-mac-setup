#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skip() { echo "==> Already done: $1 — skipping."; }

# --- Flavor-Parameter (gesetzt von Wrapper-Skripten oder direkt via EMACS_FLAVOR=...) ---
case "${EMACS_FLAVOR:-plus}" in
  yamamoto)
    _EMACS_PKG="emacs-mac@30exp"
    _EMACS_OTHER_PKG="emacs-plus@30"
    _EMACS_TAP="railwaycat/emacsmacport"
    _EMACS_APP_NAME="Emacs (Yamamoto).app"
    _EMACS_LABEL="Yamamoto"
    _EMACS_UNINSTALL="uninstall-emacs-native-yamamoto-mac.sh"
    ;;
  plus|*)
    _EMACS_PKG="emacs-plus@30"
    _EMACS_OTHER_PKG="emacs-mac@30exp"
    _EMACS_TAP="d12frosted/emacs-plus"
    _EMACS_APP_NAME="Emacs (emacs-plus).app"
    _EMACS_LABEL="emacs-plus"
    _EMACS_UNINSTALL="uninstall-emacs-native-plus-mac.sh"
    ;;
esac

# --- Emacs-Check ---
echo "==> Emacs-Check..."
if brew list 2>/dev/null | grep -q "^${_EMACS_OTHER_PKG}"; then
  echo "  HINWEIS: $_EMACS_OTHER_PKG ist ebenfalls installiert."
  echo "           $_EMACS_PKG wird als aktive Version verlinkt."
fi
if brew list 2>/dev/null | grep -q "^${_EMACS_PKG}"; then
  EMACS_VER=$(emacs --version 2>/dev/null | head -1 || echo "unbekannt")
  echo "  $_EMACS_PKG bereits installiert: $EMACS_VER"
  echo "  Zum Deinstallieren: ~/$_EMACS_UNINSTALL"
fi

# --- Konfiguration laden ---
CONFIG_FILE="$HOME/setup-emacs-mac.conf"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "ERROR: Konfigurationsdatei nicht gefunden: $CONFIG_FILE"
  echo "Vorlage: ~/setup-emacs-mac.conf.template"
  exit 1
fi
source "$CONFIG_FILE"
source "$HOME/bw-unlock.sh"

# --- Pflichtfelder prüfen (nur wenn GitHub konfiguriert) ---
if [ -n "$GH_USER" ]; then
  MISSING=()
  [ -z "$GIT_NAME" ]  && MISSING+=("GIT_NAME")
  [ -z "$GIT_EMAIL" ] && MISSING+=("GIT_EMAIL")
  [ -z "$GH_REPO" ]   && MISSING+=("GH_REPO")
  if [ ${#MISSING[@]} -gt 0 ]; then
    echo "ERROR: GH_USER ist gesetzt, aber folgende Felder fehlen in $CONFIG_FILE:"
    for F in "${MISSING[@]}"; do echo "  $F"; done
    exit 1
  fi
fi

# --- Pfade setzen ---
EMACS_INIT="$HOME/.emacs.d/init.el"
EMACS_SECRETS="$HOME/.emacs.d/secrets.el"
if [ -n "$GH_USER" ]; then
  ICLOUD_REPO_PATH="$HOME/Library/Mobile Documents/com~apple~CloudDocs/$GH_REPO"
  EMACS_CONFIG_DIR="$HOME/$GH_REPO"
else
  EMACS_CONFIG_DIR="$HOME/emacs-config"
  echo "==> GitHub nicht konfiguriert — lokale Config wird verwendet."
fi

# --- Homebrew ---
if ! command -v brew &>/dev/null; then
  echo "ERROR: Homebrew nicht gefunden. Bitte installieren: https://brew.sh"
  exit 1
fi

# --- Stale symlinks vorab bereinigen (verhindert brew link-Fehler) ---
for _PKG in node coreutils; do
  brew unlink "$_PKG" 2>/dev/null || true
done

# --- Bitwarden vorab entsperren (nur im GitHub-Modus) ---
if [ -n "$GH_USER" ]; then
  if [ ! -d "$ICLOUD_REPO_PATH/.git" ] || ! gh auth status &>/dev/null 2>&1 || [ ! -f "$EMACS_SECRETS" ]; then
    if ! command -v bw &>/dev/null; then
      echo "==> Installing Bitwarden CLI..."
      brew install bitwarden-cli
    fi
    bw_ensure_session || exit 1
  fi
fi

# --- Tools (nur im GitHub-Modus) ---
if [ -n "$GH_USER" ]; then
  command -v bw &>/dev/null       && skip "Bitwarden CLI"  || { echo "==> Installing Bitwarden CLI..."; brew install bitwarden-cli; }
  command -v gh &>/dev/null       && skip "GitHub CLI"     || { echo "==> Installing GitHub CLI...";    brew install gh; }
  command -v git-crypt &>/dev/null && skip "git-crypt"     || { echo "==> Installing git-crypt...";     brew install git-crypt; }
fi

# --- Emacs installieren ---
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
      echo "ERROR: emacs-mac@30exp Build fehlgeschlagen."
      echo "       Alternativen:"
      echo "         1. Stabiles emacs-plus verwenden: ~/setup-emacs-native-plus-mac.sh"
      echo "         2. Issues melden: https://github.com/railwaycat/homebrew-emacsmacport/issues"
      exit 1
    fi
  else
    brew install emacs-plus@30 --with-xwidgets
  fi
fi
brew link --overwrite "$_EMACS_PKG" 2>/dev/null || true

_EMACS_PREFIX=$(brew --prefix "$_EMACS_PKG" 2>/dev/null)
EMACS_APP=$(find "$_EMACS_PREFIX" -name "Emacs.app" -maxdepth 4 2>/dev/null | head -1)
if [ -n "$EMACS_APP" ]; then
  rm -rf "/Applications/$_EMACS_APP_NAME"
  cp -r "$EMACS_APP" "/Applications/$_EMACS_APP_NAME"
  echo "==> $_EMACS_APP_NAME → /Applications"
else
  echo "WARN: Emacs.app nicht gefunden unter $_EMACS_PREFIX"
fi

EMACS_BIN=$(find "$_EMACS_PREFIX" -name "emacs" -path "*/bin/emacs" -maxdepth 4 2>/dev/null | head -1)
[ -z "$EMACS_BIN" ] && EMACS_BIN=$(command -v emacs 2>/dev/null) || true
if [ -z "$EMACS_BIN" ]; then
  echo "ERROR: Emacs binary nicht gefunden nach Installation."
  exit 1
fi
echo "==> Using Emacs: $EMACS_BIN"

# --- GitHub-Modus: Auth, Repo, Symlink ---
if [ -n "$GH_USER" ]; then
  if gh auth status &>/dev/null 2>&1; then
    skip "GitHub CLI auth"
  else
    echo "==> GitHub CLI mit Token aus Bitwarden authentifizieren..."
    GH_TOKEN=$(bw_get_field "$BW_GH_ITEM" "$BW_FIELD") || true
    if [ -n "$GH_TOKEN" ]; then
      if echo "$GH_TOKEN" | gh auth login --with-token 2>/dev/null; then
        gh auth setup-git
      else
        echo "WARN: GitHub Token abgelaufen oder ungültig — bitte manuell einloggen:"
        gh auth login < /dev/tty
        gh auth setup-git
      fi
    else
      echo "WARN: GitHub Token nicht in Bitwarden gefunden. Bitte manuell:"
      gh auth login < /dev/tty
      gh auth setup-git
    fi
  fi

  # --- Conf aus privatem Repo pullen (falls konfiguriert) ---
  if [ -n "$CONF_REPO" ]; then
    CONF_URL="https://github.com/${GH_USER}/${CONF_REPO}.git"
    CONF_TMP=$(mktemp -d)
    if git clone "$CONF_URL" "$CONF_TMP" &>/dev/null 2>&1; then
      if [ -f "$CONF_TMP/setup-emacs-mac.conf" ]; then
        cp "$CONF_TMP/setup-emacs-mac.conf" "$CONFIG_FILE"
        source "$CONFIG_FILE"
        echo "==> setup-emacs-mac.conf aus privatem Repo aktualisiert."
      fi
    else
      echo "WARN: Privates Conf-Repo nicht erreichbar ($CONF_REPO) — lokale Config wird verwendet."
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
    echo "==> Repo nach iCloud klonen..."
    if [ ! -d "$HOME/Library/Mobile Documents/com~apple~CloudDocs" ]; then
      echo "ERROR: iCloud Drive nicht verfügbar."
      echo "       Bitte iCloud Drive in Systemeinstellungen aktivieren und erneut ausführen."
      exit 1
    fi
    git clone "https://github.com/${GH_USER}/${GH_REPO}.git" "$ICLOUD_REPO_PATH"

    if [ ! -f "$ICLOUD_REPO_PATH/config.org" ] && [ -f "$SCRIPT_DIR/config.org" ]; then
      cp "$SCRIPT_DIR/config.org" "$ICLOUD_REPO_PATH/config.org"
      echo "    config.org aus lokalem Fallback kopiert."
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
    echo "    iCloud-Repo eingerichtet."
  fi

  # --- git-crypt: immer prüfen und ggf. entsperren ---
  _FIRST_ORG=$(find "$ICLOUD_REPO_PATH/org" -name "*.org" 2>/dev/null | head -1)
  if [ -n "$_FIRST_ORG" ] && file "$_FIRST_ORG" | grep -q "data"; then
    echo "==> org/ Dateien verschlüsselt — git-crypt entsperren..."
    GC_KEY=$(bw_get_field "$BW_ITEM" "$BW_FIELD") || true
    if [ -n "$GC_KEY" ]; then
      if echo "$GC_KEY" | tr -d '[:space:]' | python3 -c "import sys,base64; data=sys.stdin.read().strip(); sys.stdout.buffer.write(base64.b64decode(data + '=='))" > /tmp/gckey 2>/dev/null; then
        if git -C "$ICLOUD_REPO_PATH" crypt unlock /tmp/gckey 2>/dev/null; then
          git -C "$ICLOUD_REPO_PATH" checkout HEAD -- org/ 2>/dev/null || true
          echo "    git-crypt entsperrt und org/ ausgecheckt."
        else
          echo "WARN: git-crypt unlock fehlgeschlagen — org/ Dateien noch verschlüsselt."
        fi
      else
        echo "WARN: Bitwarden-Wert ist kein gültiges Base64."
      fi
      rm -f /tmp/gckey
    else
      echo "WARN: git-crypt Key nicht in Bitwarden gefunden."
    fi
  else
    skip "git-crypt (org/ bereits entschlüsselt)"
  fi

  if [ -L "$EMACS_CONFIG_DIR" ] && [ "$(readlink "$EMACS_CONFIG_DIR")" = "$ICLOUD_REPO_PATH" ]; then
    skip "Symlink ~/emacs-config"
  else
    echo "==> Symlink ~/emacs-config → iCloud erstellen..."
    ln -sfn "$ICLOUD_REPO_PATH" "$EMACS_CONFIG_DIR"
  fi

# --- Lokaler Modus: config.org aus Scripts-Ordner ---
else
  if [ ! -d "$EMACS_CONFIG_DIR" ]; then
    mkdir -p "$EMACS_CONFIG_DIR"
    echo "==> ~/emacs-config/ erstellt."
  fi
  if [ ! -f "$EMACS_CONFIG_DIR/config.org" ] && [ -f "$SCRIPT_DIR/config.org" ]; then
    cp "$SCRIPT_DIR/config.org" "$EMACS_CONFIG_DIR/config.org"
    echo "==> config.org nach ~/emacs-config/ kopiert."
  elif [ -f "$EMACS_CONFIG_DIR/config.org" ]; then
    skip "config.org (already present)"
  else
    echo "WARN: Keine config.org gefunden — Emacs startet mit Basissetup."
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
    echo "ERROR: init.el nicht gefunden — bootstrap.sh erneut ausführen."
    exit 1
  fi
fi

# --- secrets.el ---
if [ -f "$EMACS_SECRETS" ]; then
  skip "secrets.el"
else
  mkdir -p "$HOME/.emacs.d"
  if [ -n "$GH_USER" ] && [ -n "$BW_SESSION" ]; then
    echo "==> Anthropic API Key aus Bitwarden holen..."
    ANTHROPIC_API_KEY=$(bw_get_field "$BW_ANTHROPIC_ITEM" "$BW_FIELD") || true
    if [ -n "$ANTHROPIC_API_KEY" ]; then
      printf '(setenv "ANTHROPIC_API_KEY" "%s")\n' "$ANTHROPIC_API_KEY" > "$EMACS_SECRETS"
      echo "    secrets.el mit API Key geschrieben."
    else
      echo "WARN: Anthropic API Key nicht gefunden — leere secrets.el erstellt."
      echo ";; secrets.el — add API keys here" > "$EMACS_SECRETS"
    fi
  else
    echo ";; secrets.el — add API keys here" > "$EMACS_SECRETS"
    echo "==> secrets.el erstellt (leer — kein GitHub/Bitwarden konfiguriert)."
  fi
fi

# --- Git-Identität global setzen (nur im GitHub-Modus) ---
if [ -n "$GH_USER" ]; then
  if git config --global user.email 2>/dev/null | grep -q "@"; then
    skip "Git-Identität"
  else
    echo "==> Git-Identität setzen..."
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
  echo "Your config:  ~/emacs-config/config.org  (synced via iCloud + GitHub)"
  echo "Your org files: ~/emacs-config/org/"
else
  echo "Your config:  ~/emacs-config/config.org  (local)"
  echo "To enable GitHub sync: set GH_USER in ~/setup-emacs-mac.conf and re-run."
fi
echo "======================================================================"
