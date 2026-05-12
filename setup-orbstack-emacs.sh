#!/bin/zsh
# setup-orbstack-emacs.sh
# Sets up Emacs in an OrbStack Linux machine.
# Idempotent — safe to run multiple times.

set -euo pipefail

MACHINE="emacs-orb"
EUSER="emacs"
APPS_DIR="$HOME/Applications"

# ── Load personal config ───────────────────────────────────────────────────────
CONFIG_FILE="$HOME/setup-emacs-mac.conf"
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
else
    print -P "\033[1;33mWARNING: ~/setup-emacs-mac.conf not found — set GH_USER, GH_REPO, GIT_NAME, GIT_EMAIL manually.\033[0m"
fi
GH_USER="${GH_USER:-}"
GH_REPO="${GH_REPO:-emacs-config}"
GIT_NAME="${GIT_NAME:-}"
GIT_EMAIL="${GIT_EMAIL:-}"

# ── GitHub token (from gh CLI on Mac, already authenticated) ──────────────────
GH_TOKEN=""
if [[ -n "$GH_USER" ]]; then
    if command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1; then
        GH_TOKEN=$(gh auth token 2>/dev/null || true)
    fi
    [[ -z "$GH_TOKEN" ]] && print -P "\033[1;33mWARNING: GitHub not authenticated — private repo clone may prompt for credentials. Run: gh auth login\033[0m"
fi

# ── helpers ──────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
step()  { print -P "\n${GREEN}==> $1${NC}"; }
warn()  { print -P "${YELLOW}WARNING: $1${NC}"; }
die()   { print -P "${RED}ERROR: $1${NC}"; exit 1; }

root() { orb -m "$MACHINE" -u root   "$@"; }
orbu() { orb -m "$MACHINE" -u $EUSER "$@"; }

# ── 1. OrbStack ───────────────────────────────────────────────────────────────
step "Checking OrbStack..."
if ! command -v orb &>/dev/null; then
    echo "Installing OrbStack..."
    brew install --cask orbstack
fi

# Wait for OrbStack daemon
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
    echo "Machine already exists — skipping creation."
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
root mkdir -p /home/$EUSER/.emacs.d
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

# ── 9. BeOrg mount ────────────────────────────────────────────────────────────
step "Setting up BeOrg org directory symlink..."
BEORG_PATH="$HOME/Library/Mobile Documents/iCloud~com~appsonthemove~beorg/Documents/org"
if [[ -d "$BEORG_PATH" ]]; then
    # In OrbStack, Mac home is accessible at the same path
    orbu bash -c "
        ln -sfn '/Users/$USER/Library/Mobile Documents/iCloud~com~appsonthemove~beorg/Documents/org' ~/beorg 2>/dev/null || true
    "
fi

# ── 10. init.el ───────────────────────────────────────────────────────────────
step "Writing init.el..."
root tee /home/$EUSER/.emacs.d/init.el > /dev/null << 'INITEOF'
;; Suppress byte-compile warnings at startup
(setq warning-minimum-level :error)

;; Fullscreen without animation freeze
(setq ns-use-fullscreen-animation nil)

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

;; Load secrets (API keys etc.) — not tracked in git
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
            (let* ((org-dir (expand-file-name "org/" (file-name-directory my/config-org-path)))
                   (first-org (car (and (file-directory-p org-dir)
                                        (directory-files org-dir t "\\.org$")))))
              (when (and first-org
                         (with-temp-buffer
                           (insert-file-contents-literally first-org nil 0 10)
                           (string-match-p "\x00" (buffer-string))))
                (display-warning 'emacs-setup
                 "Org files appear encrypted — run: bash ~/unlock-git-crypt.sh"
                 :warning)))))
INITEOF
root chown $EUSER:$EUSER /home/$EUSER/.emacs.d/init.el

# ── 11. unlock-git-crypt helper ───────────────────────────────────────────────
step "Writing git-crypt unlock helper..."
root tee /home/$EUSER/unlock-git-crypt.sh > /dev/null << 'GCEOF'
#!/bin/bash
set -e
REPO="$HOME/emacs-config"
echo "Paste your git-crypt key (base64), then press Ctrl-D:"
KEY_B64=$(cat)
echo "$KEY_B64" | base64 -d > /tmp/gc.key
git -C "$REPO" crypt unlock /tmp/gc.key
rm -f /tmp/gc.key
echo "Unlocked. Restart Emacs."
GCEOF
root chmod +x /home/$EUSER/unlock-git-crypt.sh
root chown $EUSER:$EUSER /home/$EUSER/unlock-git-crypt.sh

# ── 12. App bundles ───────────────────────────────────────────────────────────
step "Creating app bundles in ~/Applications/..."
mkdir -p "$APPS_DIR"

# Remove old .command files if present from a previous run
rm -f "$APPS_DIR/Emacs OrbStack GUI.command" \
      "$APPS_DIR/Emacs OrbStack Console.command" \
      "$APPS_DIR/Emacs OrbStack Shell.command" \
      "$APPS_DIR/Emacs OrbStack Root Shell.command"

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

# GUI Emacs — opens directly, no Terminal window needed (OrbStack handles display)
GUI_APP="$APPS_DIR/Emacs OrbStack GUI.app"
if [[ ! -d "$GUI_APP" ]]; then
    echo "==> Creating Emacs OrbStack GUI app..."
    mkdir -p "$GUI_APP/Contents/MacOS" "$GUI_APP/Contents/Resources"
    cat > "$GUI_APP/Contents/MacOS/Emacs" << APPSCRIPT
#!/bin/bash
export PATH="/opt/homebrew/bin:/usr/local/bin:\$PATH"
exec orb -m ${MACHINE} -u ${EUSER} emacs
APPSCRIPT
    chmod +x "$GUI_APP/Contents/MacOS/Emacs"
    cat > "$GUI_APP/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Emacs</string>
    <key>CFBundleIdentifier</key><string>org.gnu.emacs.orbstack</string>
    <key>CFBundleName</key><string>Emacs OrbStack GUI</string>
    <key>CFBundleIconFile</key><string>Emacs</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleVersion</key><string>1.0</string>
</dict>
</plist>
PLIST
    install_icon "$GUI_APP"
fi

# Console Emacs — opens in Terminal
CONSOLE_APP="$APPS_DIR/Emacs OrbStack Console.app"
if [[ ! -d "$CONSOLE_APP" ]]; then
    echo "==> Creating Emacs OrbStack Console app..."
    mkdir -p "$CONSOLE_APP/Contents/MacOS" "$CONSOLE_APP/Contents/Resources"
    cat > "$CONSOLE_APP/Contents/MacOS/EmacsConsole" << CONSOLESCRIPT
#!/bin/bash
osascript -e 'tell application "Terminal" to activate' \
          -e 'tell application "Terminal" to do script "export PATH=/opt/homebrew/bin:/usr/local/bin:\$PATH; orb -m ${MACHINE} -u ${EUSER} emacs -nw"'
CONSOLESCRIPT
    chmod +x "$CONSOLE_APP/Contents/MacOS/EmacsConsole"
    cat > "$CONSOLE_APP/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>EmacsConsole</string>
    <key>CFBundleIdentifier</key><string>org.gnu.emacs.orbstack.console</string>
    <key>CFBundleName</key><string>Emacs OrbStack Console</string>
    <key>CFBundleIconFile</key><string>Emacs</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleVersion</key><string>1.0</string>
</dict>
</plist>
PLIST
    install_icon "$CONSOLE_APP"
fi

# Shell (emacs user)
SHELL_APP="$APPS_DIR/Emacs OrbStack Shell.app"
if [[ ! -d "$SHELL_APP" ]]; then
    echo "==> Creating Emacs OrbStack Shell app..."
    mkdir -p "$SHELL_APP/Contents/MacOS" "$SHELL_APP/Contents/Resources"
    cat > "$SHELL_APP/Contents/MacOS/OrbShell" << SHELLSCRIPT
#!/bin/bash
osascript -e 'tell application "Terminal" to activate' \
          -e 'tell application "Terminal" to do script "export PATH=/opt/homebrew/bin:/usr/local/bin:\$PATH; orb -m ${MACHINE} -u ${EUSER} bash"'
SHELLSCRIPT
    chmod +x "$SHELL_APP/Contents/MacOS/OrbShell"
    cat > "$SHELL_APP/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>OrbShell</string>
    <key>CFBundleIdentifier</key><string>org.gnu.emacs.orbstack.shell</string>
    <key>CFBundleName</key><string>Emacs OrbStack Shell</string>
    <key>CFBundleIconFile</key><string>Emacs</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleVersion</key><string>1.0</string>
</dict>
</plist>
PLIST
    install_icon "$SHELL_APP"
fi

# Root shell
ROOT_APP="$APPS_DIR/Emacs OrbStack Root Shell.app"
if [[ ! -d "$ROOT_APP" ]]; then
    echo "==> Creating Emacs OrbStack Root Shell app..."
    mkdir -p "$ROOT_APP/Contents/MacOS" "$ROOT_APP/Contents/Resources"
    cat > "$ROOT_APP/Contents/MacOS/OrbRootShell" << ROOTSCRIPT
#!/bin/bash
osascript -e 'tell application "Terminal" to activate' \
          -e 'tell application "Terminal" to do script "export PATH=/opt/homebrew/bin:/usr/local/bin:\$PATH; orb -m ${MACHINE} -u root bash"'
ROOTSCRIPT
    chmod +x "$ROOT_APP/Contents/MacOS/OrbRootShell"
    cat > "$ROOT_APP/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>OrbRootShell</string>
    <key>CFBundleIdentifier</key><string>org.gnu.emacs.orbstack.rootshell</string>
    <key>CFBundleName</key><string>Emacs OrbStack Root Shell</string>
    <key>CFBundleIconFile</key><string>Emacs</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleVersion</key><string>1.0</string>
</dict>
</plist>
PLIST
    install_icon "$ROOT_APP"
fi

# ── 13. zsh alias ─────────────────────────────────────────────────────────────
step "Adding shell alias..."
ALIAS_LINE="alias emacs-orb='orb -m $MACHINE -u emacs emacs'"
if ! grep -q "emacs-orb" ~/.zshrc 2>/dev/null; then
    echo "\n$ALIAS_LINE" >> ~/.zshrc
    echo "Added alias 'emacs-orb' to ~/.zshrc"
fi

# ── done ──────────────────────────────────────────────────────────────────────
print -P "\n${GREEN}✓ OrbStack Emacs setup complete!${NC}"
echo ""
echo "Launch options:"
echo "  Terminal:     emacs-orb  (after reloading shell: source ~/.zshrc)"
echo "  App:          ~/Applications/Emacs OrbStack GUI.app"
echo "  Console:      ~/Applications/Emacs OrbStack Console.app"
echo ""
echo "First start installs Emacs packages — may take a few minutes."
echo ""
echo "git-crypt: run  bash ~/unlock-git-crypt.sh  inside the machine to unlock org files."
