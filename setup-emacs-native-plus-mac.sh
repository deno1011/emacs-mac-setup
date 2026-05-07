#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skip() { echo "==> Already done: $1 — skipping."; }

# --- Emacs-Version prüfen ---
echo "==> Emacs-Check..."
if brew list emacs-mac@30exp &>/dev/null 2>&1; then
  echo "  HINWEIS: emacs-mac@30exp (Yamamoto) ist ebenfalls installiert."
  echo "           emacs-plus wird als aktive Version verlinkt."
fi
if brew list | grep -q "emacs-plus"; then
  EMACS_VER=$(emacs --version 2>/dev/null | head -1 || echo "unbekannt")
  echo "  emacs-plus bereits installiert: $EMACS_VER"
  echo "  Zum Deinstallieren: ~/uninstall-emacs-native-plus-mac.sh"
fi

# --- Konfiguration laden ---
CONFIG_FILE="$HOME/setup-emacs-mac.conf"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "ERROR: Konfigurationsdatei nicht gefunden: $CONFIG_FILE"
  echo "Vorlage: ~/setup-emacs-mac.conf.template"
  exit 1
fi
source "$CONFIG_FILE"

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

# --- Bitwarden vorab entsperren (nur im GitHub-Modus) ---
if [ -n "$GH_USER" ]; then
  if [ ! -d "$ICLOUD_REPO_PATH/.git" ] || ! gh auth status &>/dev/null 2>&1 || [ ! -f "$EMACS_SECRETS" ]; then
    if ! command -v bw &>/dev/null; then
      echo "==> Installing Bitwarden CLI..."
      brew install bitwarden-cli
    fi
    BW_MASTER=$(security find-generic-password -a "$BW_KEYCHAIN_ACCOUNT" -s "$BW_KEYCHAIN_SERVICE" -w 2>/dev/null) || true
    if [ -z "$BW_MASTER" ]; then
      echo "==> Bitwarden Master-Passwort eingeben (wird einmalig im Mac Keychain gespeichert):"
      read -rs BW_MASTER
      echo ""
      security delete-generic-password -a "$BW_KEYCHAIN_ACCOUNT" -s "$BW_KEYCHAIN_SERVICE" 2>/dev/null || true
      security add-generic-password -a "$BW_KEYCHAIN_ACCOUNT" -s "$BW_KEYCHAIN_SERVICE" -w "$BW_MASTER" -A
    fi
    export _BW_MASTER="$BW_MASTER"
    BW_SESSION=$(bw unlock --passwordenv _BW_MASTER --raw 2>/dev/null) || true
    unset _BW_MASTER
    if [ -z "$BW_SESSION" ]; then
      echo "ERROR: Bitwarden konnte nicht entsperrt werden. Keychain-Eintrag löschen und neu versuchen:"
      echo "  security delete-generic-password -a \"$USER\" -s \"$BW_KEYCHAIN_SERVICE\""
      exit 1
    fi
    export BW_SESSION
    bw sync --session "$BW_SESSION" &>/dev/null || true
  fi
fi

# --- Homebrew ---
if ! command -v brew &>/dev/null; then
  echo "ERROR: Homebrew nicht gefunden. Bitte installieren: https://brew.sh"
  exit 1
fi

# --- Tools (nur im GitHub-Modus) ---
if [ -n "$GH_USER" ]; then
  command -v bw &>/dev/null       && skip "Bitwarden CLI"  || { echo "==> Installing Bitwarden CLI..."; brew install bitwarden-cli; }
  command -v gh &>/dev/null       && skip "GitHub CLI"     || { echo "==> Installing GitHub CLI...";    brew install gh; }
  command -v git-crypt &>/dev/null && skip "git-crypt"     || { echo "==> Installing git-crypt...";     brew install git-crypt; }
fi

# --- aspell ---
if command -v aspell &>/dev/null && aspell dump dicts 2>/dev/null | grep -q "^de"; then
  skip "aspell + German dictionary"
else
  echo "==> Installing aspell with German dictionary..."
  brew install aspell
fi

# --- JetBrains Mono Font ---
if ls ~/Library/Fonts/JetBrainsMono* &>/dev/null; then
  skip "JetBrains Mono font"
else
  echo "==> Installing JetBrains Mono font..."
  brew install --cask font-jetbrains-mono
fi

# --- Emacs (emacs-plus, native comp) ---
brew unlink emacs-mac@30exp 2>/dev/null || true
if brew list | grep -q "emacs-plus"; then
  skip "Emacs (emacs-plus)"
else
  echo "==> Installing Emacs (emacs-plus)..."
  echo "    This may take 10-20 minutes..."
  brew tap d12frosted/emacs-plus
  brew install emacs-plus --with-xwidgets
fi
brew link --overwrite emacs-plus 2>/dev/null || true
EMACS_APP=$(find /opt/homebrew/Cellar/emacs-plus@30/ -name "Emacs.app" -maxdepth 3 2>/dev/null | head -1)
if [ -n "$EMACS_APP" ]; then
  rm -rf "/Applications/Emacs (emacs-plus).app"
  cp -r "$EMACS_APP" "/Applications/Emacs (emacs-plus).app"
  echo "==> Emacs (emacs-plus).app → /Applications"
fi

EMACS_BIN=$(find /opt/homebrew/Cellar/emacs-plus*/*/bin/emacs -maxdepth 0 2>/dev/null | head -1)
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
    GH_TOKEN=$(bw get item "$BW_GH_ITEM" --session "$BW_SESSION" 2>/dev/null \
      | python3 -c "import sys,json;d=json.load(sys.stdin);fields=d.get('fields',[]);key=[f['value'] for f in fields if f['name']=='${BW_FIELD}'];print(key[0].strip() if key else '')") || true
    if [ -n "$GH_TOKEN" ]; then
      echo "$GH_TOKEN" | gh auth login --with-token
      gh auth setup-git
    else
      echo "WARN: GitHub Token nicht in Bitwarden gefunden. Bitte manuell:"
      gh auth login
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
    git clone "https://github.com/${GH_USER}/${GH_REPO}.git" "$ICLOUD_REPO_PATH"

    # config.org aus lokalem Fallback kopieren falls im Repo noch nicht vorhanden
    if [ ! -f "$ICLOUD_REPO_PATH/config.org" ] && [ -f "$SCRIPT_DIR/config.org" ]; then
      cp "$SCRIPT_DIR/config.org" "$ICLOUD_REPO_PATH/config.org"
      echo "    config.org aus lokalem Fallback kopiert."
    fi

    GC_KEY=$(bw get item "$BW_ITEM" --session "$BW_SESSION" 2>/dev/null \
      | python3 -c "import sys,json;d=json.load(sys.stdin);fields=d.get('fields',[]);key=[f['value'] for f in fields if f['name']=='${BW_FIELD}'];print(key[0].strip() if key else '')") || true
    if [ -n "$GC_KEY" ]; then
      if echo "$GC_KEY" | tr -d '[:space:]' | python3 -c "import sys,base64; data=sys.stdin.read().strip(); sys.stdout.buffer.write(base64.b64decode(data + '=='))" > /tmp/gckey 2>/dev/null; then
        git -C "$ICLOUD_REPO_PATH" crypt unlock /tmp/gckey 2>/dev/null \
          && echo "    git-crypt entsperrt." \
          || echo "WARN: git-crypt unlock fehlgeschlagen — org/ Dateien noch verschlüsselt."
      else
        echo "WARN: Bitwarden-Wert ist kein gültiges Base64."
      fi
      rm -f /tmp/gckey
    else
      echo "WARN: git-crypt Key nicht in Bitwarden gefunden."
    fi

    git -C "$ICLOUD_REPO_PATH" config user.email "$GIT_EMAIL"
    git -C "$ICLOUD_REPO_PATH" config user.name "$GIT_NAME"

    cat > "$ICLOUD_REPO_PATH/.git/hooks/post-commit" << 'HOOKEOF'
#!/bin/sh
REPO_ORG="$(git rev-parse --show-toplevel)/org"
BEORG="$HOME/Library/Mobile Documents/iCloud~com~appsonthemove~beorg/Documents/org"
[ -d "$BEORG" ] && rsync -a --delete "$REPO_ORG/" "$BEORG/" 2>/dev/null || true
git push origin main
HOOKEOF
    chmod +x "$ICLOUD_REPO_PATH/.git/hooks/post-commit"
    echo "    iCloud-Repo eingerichtet."
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
    ANTHROPIC_API_KEY=$(bw get item "$BW_ANTHROPIC_ITEM" --session "$BW_SESSION" 2>/dev/null \
      | python3 -c "import sys,json; d=json.load(sys.stdin); print(next(f['value'] for f in d.get('fields',[]) if f['name']=='$BW_FIELD'))") || true
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

# --- Emacs Pakete installieren ---
echo "==> Installing Emacs packages (this may take a few minutes)..."
"$EMACS_BIN" --batch --no-init-file \
  --eval "(require 'package)" \
  --eval "(setq package-archives '((\"melpa\" . \"https://melpa.org/packages/\") (\"gnu\" . \"https://elpa.gnu.org/packages/\") (\"nongnu\" . \"https://elpa.nongnu.org/packages/\")))" \
  --eval "(package-initialize)" \
  --eval "(package-refresh-contents)" \
  --eval "(dolist (pkg '(use-package magit doom-themes doom-modeline git-auto-commit-mode which-key rainbow-delimiters ace-window neotree undo-tree expand-region smex ivy counsel swiper org-bullets org-download htmlize gptel)) (unless (package-installed-p pkg) (message \"Installing %s...\" pkg) (package-install pkg)))" \
  --eval "(message \"All packages installed.\")" \
  2>&1 | grep -E "Installing|All packages|Error|error" || true

echo ""
echo "======================================================================"
echo "Native Emacs (emacs-plus) setup complete!"
echo "======================================================================"
echo ""
echo "Start Emacs:  open \"/Applications/Emacs (emacs-plus).app\""
echo ""
if [ -n "$GH_USER" ]; then
  echo "Your config:  ~/emacs-config/config.org  (synced via iCloud + GitHub)"
  echo "Your org files: ~/emacs-config/org/"
else
  echo "Your config:  ~/emacs-config/config.org  (local)"
  echo "To enable GitHub sync: set GH_USER in ~/setup-emacs-mac.conf and re-run."
fi
echo "======================================================================"
