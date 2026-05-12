#!/bin/zsh
# setup-orbstack-emacs.sh
# Sets up Emacs in an OrbStack Linux machine.
# Idempotent — safe to run multiple times.

set -euo pipefail

[ -f /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
[ -f /usr/local/bin/brew ]    && eval "$(/usr/local/bin/brew shellenv)"

MACHINE="emacs-orb"
EUSER="emacs"
APPS_DIR="$HOME/Applications"

# ── Load personal config ───────────────────────────────────────────────────────
CONFIG_FILE="$HOME/setup-emacs-mac.conf"
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
else
    echo "ERROR: Config file not found: $CONFIG_FILE"
    echo "Please create it (template: setup-emacs-mac.conf.template)"
    exit 1
fi

GH_USER="${GH_USER:-}"
GH_REPO="${GH_REPO:-emacs-config}"
GIT_NAME="${GIT_NAME:-}"
GIT_EMAIL="${GIT_EMAIL:-}"

MISSING=()
[[ -z "$GIT_NAME" ]]  && MISSING+=("GIT_NAME")
[[ -z "$GIT_EMAIL" ]] && MISSING+=("GIT_EMAIL")
[[ -z "$GH_USER" ]]   && MISSING+=("GH_USER")
[[ -z "$GH_REPO" ]]   && MISSING+=("GH_REPO")
if (( ${#MISSING[@]} > 0 )); then
    echo "ERROR: Missing required fields in $CONFIG_FILE:"
    for F in "${MISSING[@]}"; do echo "  $F"; done
    exit 1
fi

# ── Bitwarden (optional — used for git-crypt key and API key) ─────────────────
BW_AVAILABLE=false
if [[ -f "$HOME/bw-unlock.sh" ]]; then
    source "$HOME/bw-unlock.sh"
    if bw_ensure_session 2>/dev/null; then
        BW_AVAILABLE=true
    else
        echo "WARNING: Bitwarden session not available — git-crypt and API key must be set manually."
    fi
else
    echo "WARNING: bw-unlock.sh not found — skipping Bitwarden steps."
fi

# ── GitHub token ──────────────────────────────────────────────────────────────
GH_TOKEN=""
if command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1; then
    GH_TOKEN=$(gh auth token 2>/dev/null || true)
fi
[[ -z "$GH_TOKEN" ]] && echo "WARNING: GitHub not authenticated — run: gh auth login"

# ── helpers ──────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
step()  { print -P "\n${GREEN}==> $1${NC}"; }
warn()  { print -P "${YELLOW}WARNING: $1${NC}"; }
die()   { print -P "${RED}ERROR: $1${NC}"; exit 1; }
skip()  { echo "==> Already done: $1 — skipping."; }

root() { orb -m "$MACHINE" -u root   "$@"; }
orbu() { orb -m "$MACHINE" -u $EUSER "$@"; }

# ── 1. OrbStack ───────────────────────────────────────────────────────────────
step "Checking OrbStack..."
if ! command -v orb &>/dev/null; then
    echo "Installing OrbStack..."
    brew install --cask orbstack
fi

if ! orb list &>/dev/null 2>&1; then
    echo "Starting OrbStack..."
    open -a OrbStack
    echo "Waiting for OrbStack to start (15 s)..."
    sleep 15
fi

orb list &>/dev/null || die "OrbStack is not responding. Start it from Applications and re-run."

# ── 2. Machine ────────────────────────────────────────────────────────────────
step "Setting up OrbStack machine '$MACHINE'..."
if orb list | grep -q "^$MACHINE"; then
    skip "Machine '$MACHINE'"
else
    orb create ubuntu:24.04 "$MACHINE"
    echo "Waiting for machine to boot..."
    sleep 10
fi

# ── 3. System packages ────────────────────────────────────────────────────────
step "Installing system packages (this may take a few minutes)..."
root apt-get update -qq
root apt-get install -y \
    emacs-lucid \
    texlive texlive-latex-extra texlive-fonts-extra texlive-science \
    dvipng imagemagick \
    gnuplot r-base \
    graphviz plantuml \
    nodejs npm \
    git git-crypt curl wget unzip \
    xclip fontconfig \
    aspell aspell-de aspell-en \
    python3 python3-pip ripgrep \
    2>/dev/null

# ── 4. JetBrains Mono ─────────────────────────────────────────────────────────
step "Installing JetBrains Mono font..."
root bash -c '
    if fc-list | grep -qi "JetBrains Mono"; then
        echo "Already installed."
    else
        mkdir -p /usr/share/fonts/jetbrains-mono
        curl -fsSL "https://github.com/JetBrains/JetBrainsMono/releases/download/v2.304/JetBrainsMono-2.304.zip" \
            -o /tmp/jb.zip
        unzip -o /tmp/jb.zip -d /tmp/jbmono
        cp /tmp/jbmono/fonts/ttf/*.ttf /usr/share/fonts/jetbrains-mono/
        fc-cache -f
    fi
'

# ── 5. Claude Code CLI ────────────────────────────────────────────────────────
step "Installing Claude Code CLI..."
root npm install -g @anthropic-ai/claude-code 2>/dev/null || warn "Claude Code install failed — run manually later."

# ── 6. emacs user ─────────────────────────────────────────────────────────────
step "Setting up emacs user..."
root bash -c "id $EUSER &>/dev/null || useradd -m -s /bin/bash $EUSER"
root mkdir -p /home/$EUSER/.emacs.d /home/$EUSER/bin
root chown -R $EUSER:$EUSER /home/$EUSER

# ── 7. Git config ─────────────────────────────────────────────────────────────
step "Configuring git..."
orbu git config --global user.name  "$GIT_NAME"
orbu git config --global user.email "$GIT_EMAIL"
orbu git config --global pull.rebase false

# ── 8. Clone config repo ──────────────────────────────────────────────────────
step "Cloning emacs-config repo..."
if [[ -n "$GH_TOKEN" ]]; then
    CLONE_URL="https://${GH_TOKEN}@github.com/${GH_USER}/${GH_REPO}.git"
else
    CLONE_URL="https://github.com/${GH_USER}/${GH_REPO}.git"
fi
CLEAN_URL="https://github.com/${GH_USER}/${GH_REPO}.git"

orbu bash -c "
    if [ -d ~/emacs-config/.git ]; then
        echo 'Repo already cloned — pulling.'
        git -C ~/emacs-config remote set-url origin '${CLONE_URL}'
        git -C ~/emacs-config pull
        git -C ~/emacs-config remote set-url origin '${CLEAN_URL}'
    else
        git clone '${CLONE_URL}' ~/emacs-config
        git -C ~/emacs-config remote set-url origin '${CLEAN_URL}'
    fi
"

# ── 9. Git credentials (persistent push/pull) ────────────────────────────────
step "Configuring git credentials in machine..."
if [[ -n "$GH_TOKEN" ]]; then
    orbu bash -c "
        git config --global credential.helper store
        printf 'https://${GH_USER}:%s@github.com\n' '${GH_TOKEN}' > ~/.git-credentials
        chmod 600 ~/.git-credentials
    "
    echo "Git credentials stored."
else
    warn "No GitHub token — git push inside machine may require manual auth."
fi

# ── 10. git-crypt key ─────────────────────────────────────────────────────────
step "Setting up git-crypt..."
if orbu test -f ~/.git-crypt-key 2>/dev/null; then
    skip "git-crypt key"
    orbu git -C ~/emacs-config crypt unlock ~/.git-crypt-key 2>/dev/null \
        && echo "git-crypt unlocked." || true
elif [[ "$BW_AVAILABLE" == true ]]; then
    GC_KEY_B64=$(bw_get_field "$BW_ITEM" "$BW_FIELD") || true
    if [[ -n "$GC_KEY_B64" ]]; then
        echo "$GC_KEY_B64" | tr -d '[:space:]' \
          | python3 -c "import sys,base64; data=sys.stdin.read().strip(); sys.stdout.buffer.write(base64.b64decode(data + '=='))" \
          > "$HOME/.emacs-gc-key-tmp"
        orbu bash -c "cp '/Users/${USER}/.emacs-gc-key-tmp' ~/.git-crypt-key && chmod 600 ~/.git-crypt-key"
        rm -f "$HOME/.emacs-gc-key-tmp"
        orbu git -C ~/emacs-config crypt unlock ~/.git-crypt-key 2>/dev/null \
            && echo "git-crypt unlocked." \
            || warn "git-crypt unlock failed — run bash ~/unlock-git-crypt.sh in the machine."
    else
        warn "git-crypt key not found in Bitwarden (item: $BW_ITEM) — run bash ~/unlock-git-crypt.sh in the machine."
    fi
else
    warn "Bitwarden not available — run bash ~/unlock-git-crypt.sh in the machine to unlock org files."
fi

# ── 11. secrets.el ────────────────────────────────────────────────────────────
step "Setting up secrets.el..."
ICLOUD_SECRETS="/Users/${USER}/Library/Mobile Documents/com~apple~CloudDocs/${GH_REPO}/emacs.d/secrets.el"
orbu bash -c "
    SECRETS_SRC='${ICLOUD_SECRETS}'
    SECRETS_DST=~/.emacs.d/secrets.el
    if [ -f \"\$SECRETS_SRC\" ] && grep -q setenv \"\$SECRETS_SRC\" 2>/dev/null; then
        mkdir -p ~/.emacs.d
        if [ -L \"\$SECRETS_DST\" ] && [ \"\$(readlink \"\$SECRETS_DST\")\" = \"\$SECRETS_SRC\" ]; then
            echo 'secrets.el symlink already set.'
        else
            [ -e \"\$SECRETS_DST\" ] && rm \"\$SECRETS_DST\"
            ln -sf \"\$SECRETS_SRC\" \"\$SECRETS_DST\"
            echo 'secrets.el symlinked from iCloud repo.'
        fi
    else
        echo 'iCloud secrets.el not available yet (git-crypt not unlocked or missing).'
    fi
"

# Bitwarden fallback: write API key directly if iCloud secrets not available
if [[ "$BW_AVAILABLE" == true ]]; then
    orbu bash -c "
        SECRETS_DST=~/.emacs.d/secrets.el
        if [ ! -e \"\$SECRETS_DST\" ]; then
            echo 'Fetching Anthropic API key from Bitwarden...'
        fi
    "
    _SECRETS_MISSING=$(orbu bash -c "[ -e ~/.emacs.d/secrets.el ] && echo 'exists' || echo 'missing'")
    if [[ "$_SECRETS_MISSING" == "missing" ]]; then
        ANTHROPIC_API_KEY=$(bw_get_field "$BW_ANTHROPIC_ITEM" "$BW_FIELD") || true
        if [[ -n "$ANTHROPIC_API_KEY" ]]; then
            _SEC_TMP=$(mktemp)
            printf '(setenv "ANTHROPIC_API_KEY" "%s")\n' "$ANTHROPIC_API_KEY" > "$_SEC_TMP"
            orbu bash -c "mkdir -p ~/.emacs.d"
            orbu bash -c "cat > ~/.emacs.d/secrets.el" < "$_SEC_TMP"
            rm -f "$_SEC_TMP"
            echo "API key written to secrets.el from Bitwarden."
        else
            warn "Anthropic API key not found in Bitwarden (item: $BW_ANTHROPIC_ITEM)."
        fi
    fi
fi

# ── 12. Claude Code credentials ───────────────────────────────────────────────
step "Setting up Claude Code credentials..."
MAC_CLAUDE="/Users/${USER}/.claude"
orbu bash -c "
    if [ -L ~/.claude ] && [ -d ~/.claude ]; then
        echo 'Claude Code credentials already linked.'
    elif [ -d '${MAC_CLAUDE}' ]; then
        ln -sf '${MAC_CLAUDE}' ~/.claude
        echo 'Claude Code credentials symlinked from Mac.'
    else
        echo 'WARN: ~/.claude not found on Mac — run: claude  to authenticate.'
    fi
"

# ── 13. BeOrg symlink ─────────────────────────────────────────────────────────
step "Setting up beorg directory symlink..."
BEORG_PATH="$HOME/Library/Mobile Documents/iCloud~com~appsonthemove~beorg/Documents/org"
if [[ -d "$BEORG_PATH" ]]; then
    orbu bash -c "
        ln -sfn '/Users/$USER/Library/Mobile Documents/iCloud~com~appsonthemove~beorg/Documents/org' ~/beorg 2>/dev/null || true
    "
    echo "beorg symlink set."
else
    warn "beorg iCloud folder not found — symlink skipped."
fi

# ── 14. startup-sync.sh ───────────────────────────────────────────────────────
step "Writing startup-sync.sh..."
root tee /home/$EUSER/bin/startup-sync.sh > /dev/null << 'SYNCEOF'
#!/bin/bash
REPO="$HOME/emacs-config"
BEORG="$HOME/beorg"

# Pull latest
cd "$REPO" && git pull origin main 2>/dev/null || true

# Ensure post-commit hook exists
HOOK="$REPO/.git/hooks/post-commit"
if [ ! -x "$HOOK" ]; then
    cat > "$HOOK" << 'HOOKEOF'
#!/bin/bash
REPO="$(git rev-parse --show-toplevel)"
[ -d "$HOME/beorg" ] && rsync -a --delete "$REPO/org/" "$HOME/beorg/" 2>/dev/null || true
git push origin main 2>/dev/null &
HOOKEOF
    chmod +x "$HOOK"
fi

# Unlock git-crypt if key is available
KEY="$HOME/.git-crypt-key"
if [ -f "$KEY" ]; then
    git -C "$REPO" crypt unlock "$KEY" 2>/dev/null || true
fi

# Sync org/ → beorg
[ -d "$BEORG" ] && [ -d "$REPO/org" ] && rsync -a --delete "$REPO/org/" "$BEORG/" 2>/dev/null || true
SYNCEOF
root chmod +x /home/$EUSER/bin/startup-sync.sh
root chown $EUSER:$EUSER /home/$EUSER/bin/startup-sync.sh

# Run startup-sync.sh once now to set up post-commit hook and sync beorg
orbu bash -c "~/bin/startup-sync.sh 2>/dev/null || true"

# ── 15. init.el ───────────────────────────────────────────────────────────────
step "Writing init.el..."
root tee /home/$EUSER/.emacs.d/init.el > /dev/null << 'INITEOF'
;; Suppress byte-compile warnings at startup
(setq warning-minimum-level :error)

;; Package archives
(require 'package)
(setq package-archives '(("melpa"  . "https://melpa.org/packages/")
                         ("gnu"    . "https://elpa.gnu.org/packages/")
                         ("nongnu" . "https://elpa.nongnu.org/packages/")))
(package-initialize)

;; Bootstrap use-package
(unless (package-installed-p 'use-package)
  (package-refresh-contents)
  (package-install 'use-package))
(require 'use-package)
(setq use-package-always-ensure t)

;; Load secrets (API keys etc.)
(load (expand-file-name "~/.emacs.d/secrets.el") t t)

(defvar my/config-org-path
  (let ((symlink (expand-file-name "~/emacs-config/config.org")))
    (when (file-exists-p symlink) symlink))
  "Resolved path to config.org, or nil if not found.")

(if my/config-org-path
    (condition-case err
        (org-babel-load-file my/config-org-path)
      (error (message "CONFIG LOAD ERROR: %s" err)))
  (message "CONFIG NOT FOUND: ~/emacs-config/config.org"))

(add-hook 'after-init-hook
          (lambda ()
            (load-theme 'modus-vivendi t)
            (when my/config-org-path
              (let* ((org-dir (expand-file-name "org/" (file-name-directory my/config-org-path)))
                     (first-org (car (and (file-directory-p org-dir)
                                          (directory-files org-dir t "\\.org$")))))
                (when (and first-org
                           (with-temp-buffer
                             (insert-file-contents-literally first-org nil 0 10)
                             (string-match-p "\x00" (buffer-string))))
                  (display-warning 'emacs-setup
                   "Org files appear encrypted — run: bash ~/unlock-git-crypt.sh"
                   :warning))))))
INITEOF
root chown $EUSER:$EUSER /home/$EUSER/.emacs.d/init.el

# ── 16. unlock-git-crypt helper ───────────────────────────────────────────────
step "Writing git-crypt unlock helper..."
root tee /home/$EUSER/unlock-git-crypt.sh > /dev/null << 'GCEOF'
#!/bin/bash
set -e
REPO="$HOME/emacs-config"
echo "Paste your git-crypt key (base64), then press Ctrl-D:"
KEY_B64=$(cat)
echo "$KEY_B64" | base64 -d > /tmp/gc.key
git -C "$REPO" crypt unlock /tmp/gc.key
cp /tmp/gc.key ~/.git-crypt-key && chmod 600 ~/.git-crypt-key
rm -f /tmp/gc.key
echo "Unlocked. Key stored at ~/.git-crypt-key. Restart Emacs."
GCEOF
root chmod +x /home/$EUSER/unlock-git-crypt.sh
root chown $EUSER:$EUSER /home/$EUSER/unlock-git-crypt.sh

# ── 17. config.org fallback ───────────────────────────────────────────────────
step "Checking config.org..."
ICLOUD_CONFIG="/Users/${USER}/Library/Mobile Documents/com~apple~CloudDocs/${GH_REPO}/config.org"
orbu bash -c "
    if [ -f ~/emacs-config/config.org ]; then
        echo 'config.org present.'
    elif [ -f '${ICLOUD_CONFIG}' ]; then
        cp '${ICLOUD_CONFIG}' ~/emacs-config/config.org
        echo 'config.org copied from iCloud.'
    else
        echo 'WARN: config.org not found — Emacs will start without config.'
    fi
"

# ── 18. Verification ──────────────────────────────────────────────────────────
step "Verifying installation..."
orbu emacs --version 2>/dev/null | head -1 || warn "Emacs version check failed."
orbu git --version  2>/dev/null | head -1 || warn "Git version check failed."

# ── 19. App bundles ───────────────────────────────────────────────────────────
step "Creating app bundles in ~/Applications/..."
mkdir -p "$APPS_DIR"

# Remove old names from previous runs
rm -f  "$APPS_DIR/Emacs OrbStack GUI.command" \
       "$APPS_DIR/Emacs OrbStack Console.command" \
       "$APPS_DIR/Emacs OrbStack Shell.command" \
       "$APPS_DIR/Emacs OrbStack Root Shell.command"
rm -rf "$APPS_DIR/Emacs OrbStack GUI.app" \
       "$APPS_DIR/Emacs OrbStack Console.app" \
       "$APPS_DIR/Emacs OrbStack Shell.app" \
       "$APPS_DIR/Emacs OrbStack Root Shell.app"

# Download and build Emacs icon (shared by all bundles)
if ! [[ -f /tmp/emacs.iconset/icon_128x128.png ]]; then
    if curl -fsSL "https://raw.githubusercontent.com/emacs-mirror/emacs/master/etc/images/icons/hicolor/128x128/apps/emacs.png" \
        -o /tmp/emacs.png 2>/dev/null; then
        mkdir -p /tmp/emacs.iconset
        sips -z 16 16   /tmp/emacs.png --out /tmp/emacs.iconset/icon_16x16.png    &>/dev/null
        sips -z 32 32   /tmp/emacs.png --out /tmp/emacs.iconset/icon_16x16@2x.png &>/dev/null
        sips -z 32 32   /tmp/emacs.png --out /tmp/emacs.iconset/icon_32x32.png    &>/dev/null
        sips -z 64 64   /tmp/emacs.png --out /tmp/emacs.iconset/icon_32x32@2x.png &>/dev/null
        sips -z 128 128 /tmp/emacs.png --out /tmp/emacs.iconset/icon_128x128.png  &>/dev/null
        sips -z 256 256 /tmp/emacs.png --out /tmp/emacs.iconset/icon_128x128@2x.png &>/dev/null
        echo "    Icon downloaded."
    else
        echo "    Icon download failed — bundles will use default icon."
    fi
fi

install_icon() {
    local bundle="$1"
    [[ -f /tmp/emacs.iconset/icon_128x128.png ]] && \
        iconutil -c icns /tmp/emacs.iconset -o "$bundle/Contents/Resources/Emacs.icns" 2>/dev/null
}

# GUI Emacs — calls startup-sync.sh then opens Emacs (OrbStack handles display)
GUI_APP="$APPS_DIR/GUI OrbStack Emacs.app"
rm -rf "$GUI_APP"   # always recreate to pick up script updates
echo "==> Creating GUI OrbStack Emacs app..."
mkdir -p "$GUI_APP/Contents/MacOS" "$GUI_APP/Contents/Resources"
cat > "$GUI_APP/Contents/MacOS/Emacs" << APPSCRIPT
#!/bin/bash
export PATH="/opt/homebrew/bin:/usr/local/bin:/Applications/OrbStack.app/Contents/MacOS:\$PATH"
orb -m ${MACHINE} -u ${EUSER} bash -c "~/bin/startup-sync.sh 2>/dev/null; emacs"
APPSCRIPT
chmod +x "$GUI_APP/Contents/MacOS/Emacs"
cat > "$GUI_APP/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Emacs</string>
    <key>CFBundleIdentifier</key><string>org.gnu.emacs.orbstack</string>
    <key>CFBundleName</key><string>GUI OrbStack Emacs</string>
    <key>CFBundleIconFile</key><string>Emacs</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleVersion</key><string>1.0</string>
</dict>
</plist>
PLIST
install_icon "$GUI_APP"
xattr -dr com.apple.quarantine "$GUI_APP" 2>/dev/null || true

# Console Emacs — opens in Terminal with startup-sync
CONSOLE_APP="$APPS_DIR/Console OrbStack Emacs.app"
if [[ ! -d "$CONSOLE_APP" ]]; then
    echo "==> Creating Console OrbStack Emacs app..."
    mkdir -p "$CONSOLE_APP/Contents/MacOS" "$CONSOLE_APP/Contents/Resources"
    cat > "$CONSOLE_APP/Contents/MacOS/EmacsConsole" << CONSOLESCRIPT
#!/bin/bash
export PATH="/opt/homebrew/bin:/usr/local/bin:/Applications/OrbStack.app/Contents/MacOS:\$PATH"
osascript -e 'tell application "Terminal" to activate' \
          -e 'tell application "Terminal" to do script "export PATH=/opt/homebrew/bin:/usr/local/bin:/Applications/OrbStack.app/Contents/MacOS:\$PATH; orb -m ${MACHINE} -u ${EUSER} bash -c \"~/bin/startup-sync.sh 2>/dev/null; emacs -nw\""'
CONSOLESCRIPT
    chmod +x "$CONSOLE_APP/Contents/MacOS/EmacsConsole"
    cat > "$CONSOLE_APP/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>EmacsConsole</string>
    <key>CFBundleIdentifier</key><string>org.gnu.emacs.orbstack.console</string>
    <key>CFBundleName</key><string>Console OrbStack Emacs</string>
    <key>CFBundleIconFile</key><string>Emacs</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleVersion</key><string>1.0</string>
</dict>
</plist>
PLIST
    install_icon "$CONSOLE_APP"
    xattr -dr com.apple.quarantine "$CONSOLE_APP" 2>/dev/null || true
fi

# Shell (emacs user)
SHELL_APP="$APPS_DIR/Shell OrbStack Emacs.app"
if [[ ! -d "$SHELL_APP" ]]; then
    echo "==> Creating Shell OrbStack Emacs app..."
    mkdir -p "$SHELL_APP/Contents/MacOS" "$SHELL_APP/Contents/Resources"
    cat > "$SHELL_APP/Contents/MacOS/OrbShell" << SHELLSCRIPT
#!/bin/bash
export PATH="/opt/homebrew/bin:/usr/local/bin:/Applications/OrbStack.app/Contents/MacOS:\$PATH"
osascript -e 'tell application "Terminal" to activate' \
          -e 'tell application "Terminal" to do script "export PATH=/opt/homebrew/bin:/usr/local/bin:/Applications/OrbStack.app/Contents/MacOS:\$PATH; orb -m ${MACHINE} -u ${EUSER} bash"'
SHELLSCRIPT
    chmod +x "$SHELL_APP/Contents/MacOS/OrbShell"
    cat > "$SHELL_APP/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>OrbShell</string>
    <key>CFBundleIdentifier</key><string>org.gnu.emacs.orbstack.shell</string>
    <key>CFBundleName</key><string>Shell OrbStack Emacs</string>
    <key>CFBundleIconFile</key><string>Emacs</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleVersion</key><string>1.0</string>
</dict>
</plist>
PLIST
    install_icon "$SHELL_APP"
    xattr -dr com.apple.quarantine "$SHELL_APP" 2>/dev/null || true
fi

# Root shell
ROOT_APP="$APPS_DIR/Root Shell OrbStack Emacs.app"
if [[ ! -d "$ROOT_APP" ]]; then
    echo "==> Creating Root Shell OrbStack Emacs app..."
    mkdir -p "$ROOT_APP/Contents/MacOS" "$ROOT_APP/Contents/Resources"
    cat > "$ROOT_APP/Contents/MacOS/OrbRootShell" << ROOTSCRIPT
#!/bin/bash
export PATH="/opt/homebrew/bin:/usr/local/bin:/Applications/OrbStack.app/Contents/MacOS:\$PATH"
osascript -e 'tell application "Terminal" to activate' \
          -e 'tell application "Terminal" to do script "export PATH=/opt/homebrew/bin:/usr/local/bin:/Applications/OrbStack.app/Contents/MacOS:\$PATH; orb -m ${MACHINE} -u root bash"'
ROOTSCRIPT
    chmod +x "$ROOT_APP/Contents/MacOS/OrbRootShell"
    cat > "$ROOT_APP/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>OrbRootShell</string>
    <key>CFBundleIdentifier</key><string>org.gnu.emacs.orbstack.rootshell</string>
    <key>CFBundleName</key><string>Root Shell OrbStack Emacs</string>
    <key>CFBundleIconFile</key><string>Emacs</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleVersion</key><string>1.0</string>
</dict>
</plist>
PLIST
    install_icon "$ROOT_APP"
    xattr -dr com.apple.quarantine "$ROOT_APP" 2>/dev/null || true
fi

# ── 20. zsh alias ─────────────────────────────────────────────────────────────
step "Adding shell alias..."
ALIAS_LINE="alias emacs-orb='orb -m $MACHINE -u $EUSER bash -c \"~/bin/startup-sync.sh 2>/dev/null; emacs\"'"
if ! grep -q "emacs-orb" ~/.zshrc 2>/dev/null; then
    echo "\n$ALIAS_LINE" >> ~/.zshrc
    echo "Added alias 'emacs-orb' to ~/.zshrc"
fi

# ── done ──────────────────────────────────────────────────────────────────────
print -P "\n${GREEN}✓ OrbStack Emacs setup complete!${NC}"
echo ""
echo "Launch options:"
echo "  Terminal:   emacs-orb  (after reloading shell: source ~/.zshrc)"
echo "  App:        ~/Applications/GUI OrbStack Emacs.app"
echo "  Console:    ~/Applications/Console OrbStack Emacs.app"
echo ""
echo "First start installs Emacs packages — may take a few minutes."
echo ""
if orbu test -f ~/.git-crypt-key 2>/dev/null; then
    echo "git-crypt: already unlocked."
else
    echo "git-crypt: run  bash ~/unlock-git-crypt.sh  inside the machine to unlock org files."
fi
