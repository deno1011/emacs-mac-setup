#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skip() { echo "==> Already done: $1 — skipping."; }

# --- Konfiguration laden ---
CONFIG_FILE="$HOME/setup-emacs-mac.conf"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "ERROR: Konfigurationsdatei nicht gefunden: $CONFIG_FILE"
  echo "Bitte erstellen (Vorlage: setup-emacs-mac.conf)"
  exit 1
fi
source "$CONFIG_FILE"

# --- Pflichtfelder prüfen ---
MISSING=()
[ -z "$GIT_NAME" ]  && MISSING+=("GIT_NAME")
[ -z "$GIT_EMAIL" ] && MISSING+=("GIT_EMAIL")
[ -z "$GH_USER" ]   && MISSING+=("GH_USER")
[ -z "$GH_REPO" ]   && MISSING+=("GH_REPO")
if [ ${#MISSING[@]} -gt 0 ]; then
  echo "ERROR: Folgende Pflichtfelder fehlen oder sind leer in $CONFIG_FILE:"
  for F in "${MISSING[@]}"; do echo "  $F"; done
  echo "Vorlage: ~/setup-emacs-mac.conf.template"
  exit 1
fi

# --- Passwörter vorab abfragen ---
ICLOUD_REPO_PATH="$HOME/Library/Mobile Documents/com~apple~CloudDocs/$GH_REPO"

# Admin-Passwort nur einlesen wenn XQuartz noch nicht installiert ist
if [ ! -d "/Applications/Utilities/XQuartz.app" ]; then
  echo "==> Admin-Passwort eingeben (einmalig, für XQuartz):"
  read -rs ADMIN_PASS
  echo ""
fi

# Bitwarden wird benötigt wenn: iCloud-Repo fehlt ODER gh nicht authentifiziert ODER API Key fehlt im Container
ANTHROPIC_KEY_SET=$(docker inspect "$DOCKER_CONTAINER" &>/dev/null && docker exec "$DOCKER_CONTAINER" grep -q "ANTHROPIC_API_KEY" /home/emacs/.bashrc 2>/dev/null && echo "yes") || true
if [ ! -d "$ICLOUD_REPO_PATH/.git" ] || ! gh auth status &>/dev/null 2>&1 || [ "$ANTHROPIC_KEY_SET" != "yes" ]; then
  if ! command -v bw &>/dev/null; then
    echo "==> Installing Bitwarden CLI (needed for setup)..."
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
fi

# --- Clean incomplete Homebrew downloads ---
echo "==> Cleaning incomplete Homebrew downloads..."
rm -f ~/Library/Caches/Homebrew/downloads/*.incomplete

# --- XQuartz (direkt installieren, nicht über brew cask, damit sudo-Cache funktioniert) ---
if [ -d "/Applications/Utilities/XQuartz.app" ]; then
  skip "XQuartz (already installed)"
else
  echo "==> Downloading XQuartz..."
  XQUARTZ_URL=$(brew info --cask xquartz --json=v2 2>/dev/null \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['casks'][0]['url'])" 2>/dev/null)
  [ -z "$XQUARTZ_URL" ] && XQUARTZ_URL="https://github.com/XQuartz/XQuartz/releases/download/XQuartz-2.8.5/XQuartz-2.8.5.pkg"
  XQUARTZ_PKG="$(brew --cache)/XQuartz-setup.pkg"
  curl -L --progress-bar -o "$XQUARTZ_PKG" "$XQUARTZ_URL"
  echo "==> Installing XQuartz..."
  echo "$ADMIN_PASS" | sudo -S installer -pkg "$XQUARTZ_PKG" -target /
  rm -f "$XQUARTZ_PKG"
fi

# --- Docker CLI ---
if command -v docker &>/dev/null; then
  skip "Docker CLI (already installed)"
else
  echo "==> Installing Docker CLI..."
  brew install docker
fi

# --- Bitwarden CLI ---
if command -v bw &>/dev/null; then
  skip "Bitwarden CLI (already installed)"
else
  echo "==> Installing Bitwarden CLI..."
  brew install bitwarden-cli
fi

# --- GitHub CLI ---
if ! command -v gh &>/dev/null; then
  echo "==> Installing GitHub CLI..."
  brew install gh
fi

if gh auth status &>/dev/null 2>&1; then
  skip "GitHub CLI auth (already authenticated)"
else
  echo "==> GitHub CLI mit Token aus Bitwarden authentifizieren..."
  GH_TOKEN=$(bw get item "$BW_GH_ITEM" --session "$BW_SESSION" 2>/dev/null \
    | python3 -c "import sys,json;d=json.load(sys.stdin);fields=d.get('fields',[]);key=[f['value'] for f in fields if f['name']=='${BW_FIELD}'];print(key[0].strip() if key else '')") || true
  if [ -n "$GH_TOKEN" ]; then
    echo "$GH_TOKEN" | gh auth login --with-token
  else
    echo "WARN: GitHub Token nicht in Bitwarden gefunden. Bitte manuell anmelden:"
    gh auth login
  fi
fi

# --- git-crypt (Mac) ---
if command -v git-crypt &>/dev/null; then
  skip "git-crypt (already installed)"
else
  echo "==> Installing git-crypt..."
  brew install git-crypt
fi

echo "==> Configuring XQuartz to allow network connections..."
defaults write org.xquartz.X11 nolisten_tcp -bool false
defaults write org.xquartz.X11 no_auth -bool false

echo "==> Starting XQuartz..."
open -a XQuartz
sleep 3

# --- Colima ---
if colima status 2>/dev/null | grep -q "Running"; then
  skip "Colima (already running)"
else
  echo "==> Starting Colima (Docker runtime)..."
  colima start
fi

# --- Docker context ---
if docker context show 2>/dev/null | grep -q "colima"; then
  skip "Docker context (already set to colima)"
else
  echo "==> Switching Docker context to Colima..."
  docker context use colima
fi

# --- Verify Docker ---
echo "==> Verifying Docker..."
docker run --rm hello-world

# --- Project directory ---
mkdir -p ~/emacs-docker

# --- Dockerfile ---
if [ -f ~/emacs-docker/Dockerfile ]; then
  skip "Dockerfile"
else
  echo "==> Creating Dockerfile..."
  cat > ~/emacs-docker/Dockerfile << 'DOCKERFILE'
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

RUN apt-get update && apt-get install -y \
    emacs-lucid \
    dvipng \
    imagemagick \
    fonts-jetbrains-mono \
    git \
    git-crypt \
    curl \
    wget \
    build-essential \
    python3 \
    python3-pip \
    ripgrep \
    texlive \
    texlive-latex-extra \
    texlive-fonts-recommended \
    texlive-science \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g @anthropic-ai/claude-code

RUN useradd -m -s /bin/bash emacs

USER emacs
WORKDIR /home/emacs

CMD ["bash"]
DOCKERFILE
fi


# --- Build Docker image ---
if docker images -q "$DOCKER_IMAGE" 2>/dev/null | grep -q .; then
  skip "Docker image ($DOCKER_IMAGE)"
else
  echo "==> Building Docker image (this will take several minutes)..."
  docker build -t "$DOCKER_IMAGE" ~/emacs-docker
fi

# --- Persistent volume ---
if docker volume ls -q -f name="$DOCKER_VOLUME" 2>/dev/null | grep -q .; then
  skip "Docker volume ($DOCKER_VOLUME)"
else
  echo "==> Creating persistent volume for Emacs home directory..."
  docker volume create "$DOCKER_VOLUME"
fi

# --- Mac-seitige iCloud repo setup ---
ICLOUD_REPO_PATH="$HOME/Library/Mobile Documents/com~apple~CloudDocs/$GH_REPO"
ICLOUD_REPO_SYMLINK="$HOME/.emacs-icloud-repo"

if [ -d "$ICLOUD_REPO_PATH/.git" ]; then
  skip "iCloud repo (already cloned to Mac)"
  echo "==> GitHub Credential-Helper einrichten und pull..."
  gh auth setup-git
  git -C "$ICLOUD_REPO_PATH" remote set-url origin "https://github.com/${GH_USER}/${GH_REPO}.git"
  git -C "$ICLOUD_REPO_PATH" pull origin main || true
else
  echo "==> Schlüssel aus Bitwarden abrufen..."
  KEY_B64=$(bw get item "$BW_ITEM" | python3 -c "import sys,json;d=json.load(sys.stdin);fields=d.get('fields',[]);key=[f['value'] for f in fields if f['name']=='${BW_FIELD}'];print(key[0].strip() if key else '')")

  echo "==> GitHub Credential-Helper einrichten..."
  gh auth setup-git

  echo "==> Repo nach iCloud klonen..."
  git clone "https://github.com/${GH_USER}/${GH_REPO}.git" "$ICLOUD_REPO_PATH"

  echo "==> git-crypt auf Mac entsperren..."
  echo "$KEY_B64" | tr -d '[:space:]' | python3 -c "import sys,base64; data=sys.stdin.read().strip(); sys.stdout.buffer.write(base64.b64decode(data + '=='))" > /tmp/gckey
  git -C "$ICLOUD_REPO_PATH" crypt unlock /tmp/gckey
  rm /tmp/gckey

  echo "==> Git-Identität setzen..."
  git -C "$ICLOUD_REPO_PATH" config user.email "$GIT_EMAIL"
  git -C "$ICLOUD_REPO_PATH" config user.name "$GIT_NAME"

  echo "==> Post-commit hook setzen (auto-push + beorg sync)..."
  cat > "$ICLOUD_REPO_PATH/.git/hooks/post-commit" << 'HOOKEOF'
#!/bin/sh
REPO_ORG="$(git rev-parse --show-toplevel)/org"
BEORG="$HOME/Library/Mobile Documents/iCloud~com~appsonthemove~beorg/Documents/org"
[ -d "$BEORG" ] && rsync -a --delete "$REPO_ORG/" "$BEORG/" 2>/dev/null || true
git push origin main
HOOKEOF
  chmod +x "$ICLOUD_REPO_PATH/.git/hooks/post-commit"

  echo "==> Bestehende beorg-Dateien migrieren..."
  if [ -d "$BEORG_ORG_PATH" ]; then
    rsync -av --ignore-existing "$BEORG_ORG_PATH/" "$ICLOUD_REPO_PATH/org/"
    git -C "$ICLOUD_REPO_PATH" add org/
    if ! git -C "$ICLOUD_REPO_PATH" diff --cached --quiet; then
      git -C "$ICLOUD_REPO_PATH" commit -m "Migrate existing beorg files from iCloud"
      git -C "$ICLOUD_REPO_PATH" push
    else
      echo "    Keine neuen Dateien zu migrieren."
    fi
  fi

  echo "    iCloud-Repo eingerichtet."
fi

# --- Start container ---
HAS_BEORG_MOUNT=false
if docker inspect "$DOCKER_CONTAINER" --format '{{range .HostConfig.Binds}}{{.}} {{end}}' 2>/dev/null | grep -q "/beorg"; then
  HAS_BEORG_MOUNT=true
fi

if docker ps -q -f name="$DOCKER_CONTAINER" 2>/dev/null | grep -q .; then
  if [ "$HAS_BEORG_MOUNT" = false ]; then
    echo "==> Container neu erstellen (beorg-Mount fehlt)..."
    docker rm -f "$DOCKER_CONTAINER"
  else
    skip "Container ($DOCKER_CONTAINER already running)"
  fi
elif docker ps -aq -f name="$DOCKER_CONTAINER" 2>/dev/null | grep -q .; then
  if [ "$HAS_BEORG_MOUNT" = false ]; then
    echo "==> Container neu erstellen (beorg-Mount fehlt)..."
    docker rm -f "$DOCKER_CONTAINER"
  else
    echo "==> Starting existing container..."
    docker start "$DOCKER_CONTAINER"
  fi
fi

if ! docker ps -aq -f name="$DOCKER_CONTAINER" 2>/dev/null | grep -q .; then
  echo "==> Starting container in background..."
  docker run -d --name "$DOCKER_CONTAINER" \
    -v "$DOCKER_VOLUME":/home/emacs \
    -v "$BEORG_ORG_PATH:/beorg" \
    -e GH_USER="$GH_USER" \
    -e GH_REPO="$GH_REPO" \
    -e DISPLAY=host.docker.internal:0 \
    "$DOCKER_IMAGE" sleep infinity
fi

# --- Emacs setup inside container (piped directly, no file created) ---
if docker exec "$DOCKER_CONTAINER" test -f /home/emacs/.emacs.d/init.el 2>/dev/null; then
  skip "Emacs configuration (init.el already present)"
else
  echo "==> Running Emacs setup inside container..."

  # Copy init.el from host into container
  docker exec "$DOCKER_CONTAINER" bash -c 'mkdir -p ~/.emacs.d'
  if [ -f "$SCRIPT_DIR/init.el" ]; then
    docker cp "$SCRIPT_DIR/init.el" "$DOCKER_CONTAINER:/home/emacs/.emacs.d/init.el"
    echo "==> init.el installiert."
  else
    echo "ERROR: ~/init.el nicht gefunden — bootstrap.sh erneut ausführen."
    exit 1
  fi

  # Write starter config.org only if not already present (e.g. cloned from GitHub)
  if docker exec "$DOCKER_CONTAINER" test -f "/home/emacs/${GH_REPO}/config.org" 2>/dev/null; then
    skip "config.org (already present from cloned repo)"
  else
  docker exec "$DOCKER_CONTAINER" bash -c 'cat > ~/'"${GH_REPO}"'/config.org << '"'"'CONFIGEOF'"'"'
#+TITLE: Emacs Configuration
#+PROPERTY: header-args:emacs-lisp :tangle yes

* UI & Appearance
#+begin_src emacs-lisp
;; Prevent XQuartz rendering glitches
(add-to-list '"'"'default-frame-alist '"'"'(inhibit-double-buffering . t))

(tool-bar-mode -1)
(scroll-bar-mode -1)
(menu-bar-mode -1)
(setq inhibit-startup-screen t)
(setq-default line-spacing 3)
(add-to-list '"'"'default-frame-alist '"'"'(internal-border-width . 12))
(defalias '"'"'yes-or-no-p '"'"'y-or-n-p)
(show-paren-mode 1)
(delete-selection-mode 1)
(column-number-mode 1)
(global-auto-revert-mode t)
#+end_src

* Font
#+begin_src emacs-lisp
(set-face-attribute '"'"'default nil :font "JetBrains Mono-13")
(add-to-list '"'"'default-frame-alist '"'"'(font . "JetBrains Mono-13"))
#+end_src

* Theme & Modeline
#+begin_src emacs-lisp
(load-theme '"'"'modus-vivendi t)

(use-package doom-themes
  :config
  (doom-themes-org-config))

(use-package doom-modeline
  :hook (after-init . doom-modeline-mode)
  :custom
  (doom-modeline-height 28)
  (doom-modeline-icon nil))
#+end_src

* Scrolling
#+begin_src emacs-lisp
(setq scroll-conservatively 101
      scroll-margin 3
      fast-but-imprecise-scrolling t)
#+end_src

* Version Control
#+begin_src emacs-lisp
(use-package magit
  :bind ("C-x g" . magit-status))
#+end_src

* Auto-commit Org files
#+begin_src emacs-lisp
(use-package git-auto-commit-mode
  :config
  (setq gac-automatically-push-p t
        gac-automatically-add-new-files-p t))
(add-hook '"'"'org-mode-hook '"'"'git-auto-commit-mode)
#+end_src

* Org Mode
#+begin_src emacs-lisp
(use-package org
  :ensure nil
  :config
  (setq org-directory "~/emacs-config/org"
        org-default-notes-file "~/emacs-config/org/inbox.org"
        org-agenda-files '"'"'("~/emacs-config/org")
        org-confirm-babel-evaluate nil
        org-startup-indented t
        org-startup-folded t
        org-hide-emphasis-markers t
        org-return-follows-link t
        org-log-done '"'"'time
        org-log-into-drawer t)
  (org-babel-do-load-languages
   '"'"'org-babel-load-languages
   '"'"'((emacs-lisp . t)
     (python     . t)
     (shell      . t)))
  (require '"'"'ox-latex)
  (setq org-latex-compiler "pdflatex"))
#+end_src

* Org Capture
#+begin_src emacs-lisp
(global-set-key (kbd "C-c c") '"'"'org-capture)
(global-set-key (kbd "C-c a") '"'"'org-agenda)
(global-set-key (kbd "C-c l") '"'"'org-store-link)
(setq org-capture-templates
      '"'"'(("i" "Inbox" entry (file "~/emacs-config/org/inbox.org")
         "* %?\n%U\n")))
#+end_src

* Terminal
#+begin_src emacs-lisp
(global-set-key (kbd "C-c t") '"'"'eshell)
#+end_src
CONFIGEOF'
  fi

  echo "==> Installing Emacs packages (this may take a few minutes)..."
  docker exec "$DOCKER_CONTAINER" emacs --batch --eval "
(require 'package)
(setq package-archives '((\"melpa\"  . \"https://melpa.org/packages/\")
                         (\"gnu\"    . \"https://elpa.gnu.org/packages/\")
                         (\"nongnu\" . \"https://elpa.nongnu.org/packages/\")))
(package-initialize)
(package-refresh-contents)
(dolist (pkg '(use-package magit doom-themes doom-modeline git-auto-commit-mode))
  (unless (package-installed-p pkg)
    (package-install pkg)))
(message \"Packages installed.\")
"

  echo "==> Verifying installations..."
  docker exec "$DOCKER_CONTAINER" emacs --version
  docker exec "$DOCKER_CONTAINER" git --version

  echo "Emacs setup complete."
fi

# --- startup-sync.sh im Container ---
if docker exec "$DOCKER_CONTAINER" test -f /home/emacs/bin/startup-sync.sh 2>/dev/null; then
  skip "startup-sync.sh (already present)"
else
  echo "==> startup-sync.sh im Container erstellen..."
  docker exec "$DOCKER_CONTAINER" mkdir -p /home/emacs/bin
  docker exec "$DOCKER_CONTAINER" bash -c 'cat > /home/emacs/bin/startup-sync.sh << '"'"'SYNCEOF'"'"'
#!/bin/bash
REPO="/home/emacs/emacs-config"
BEORG="/beorg"
GH_URL="https://github.com/$GH_USER/$GH_REPO.git"

# Clone if not present, pull if present
if [ ! -d "$REPO/.git" ]; then
  git clone "$GH_URL" "$REPO" 2>/dev/null || true
else
  cd "$REPO" && git pull origin main 2>/dev/null || true
fi

# Set up post-commit hook (beorg sync + auto-push)
HOOK="$REPO/.git/hooks/post-commit"
if [ ! -f "$HOOK" ]; then
  printf '"'"'#!/bin/bash\nREPO="$(git rev-parse --show-toplevel)"\nrsync -a --delete "$REPO/org/" /beorg/ 2>/dev/null || true\ngit push origin main 2>/dev/null || true\n'"'"' > "$HOOK"
  chmod +x "$HOOK"
fi

# Sync org files to beorg on startup
[ -d "$BEORG" ] && [ -d "$REPO/org" ] && rsync -a --delete "$REPO/org/" "$BEORG/" 2>/dev/null || true
SYNCEOF'
  docker exec "$DOCKER_CONTAINER" chmod +x /home/emacs/bin/startup-sync.sh
fi

# --- Create macOS app bundle in ~/Applications ---
APP_PATH="$HOME/Applications/Emacs Docker GUI.app"
if [ -d "$APP_PATH" ]; then
  skip "Emacs app bundle"
else
  echo "==> Creating Emacs app bundle in ~/Applications..."
  mkdir -p "$APP_PATH/Contents/MacOS"
  mkdir -p "$APP_PATH/Contents/Resources"

  cat > "$APP_PATH/Contents/MacOS/Emacs" << 'APPSCRIPT'
#!/bin/bash
osascript << 'APPLESCRIPT'
tell application "Terminal"
  activate
  do script "export PATH=/opt/homebrew/bin:/usr/local/bin:/opt/X11/bin:$PATH; open -a XQuartz; sleep 3; /opt/X11/bin/xhost +localhost 2>/dev/null; colima start 2>/dev/null || true; docker start CONTAINER_PLACEHOLDER 2>/dev/null || true; docker exec CONTAINER_PLACEHOLDER /home/emacs/bin/startup-sync.sh 2>/dev/null; docker exec -e DISPLAY=host.docker.internal:0 CONTAINER_PLACEHOLDER emacs"
end tell
APPLESCRIPT
APPSCRIPT
  chmod +x "$APP_PATH/Contents/MacOS/Emacs"
  sed -i '' "s|CONTAINER_PLACEHOLDER|${DOCKER_CONTAINER}|g" "$APP_PATH/Contents/MacOS/Emacs"

  cat > "$APP_PATH/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Emacs</string>
    <key>CFBundleIdentifier</key>
    <string>org.gnu.emacs.docker</string>
    <key>CFBundleName</key>
    <string>Emacs Docker GUI</string>
    <key>CFBundleIconFile</key>
    <string>Emacs</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
</dict>
</plist>
PLIST

  echo "==> Downloading Emacs icon..."
  if curl -fsSL "https://raw.githubusercontent.com/emacs-mirror/emacs/master/etc/images/icons/hicolor/128x128/apps/emacs.png" \
    -o /tmp/emacs.png 2>/dev/null; then
    mkdir -p /tmp/emacs.iconset
    sips -z 16 16   /tmp/emacs.png --out /tmp/emacs.iconset/icon_16x16.png    &>/dev/null
    sips -z 32 32   /tmp/emacs.png --out /tmp/emacs.iconset/icon_16x16@2x.png &>/dev/null
    sips -z 32 32   /tmp/emacs.png --out /tmp/emacs.iconset/icon_32x32.png    &>/dev/null
    sips -z 64 64   /tmp/emacs.png --out /tmp/emacs.iconset/icon_32x32@2x.png &>/dev/null
    sips -z 128 128 /tmp/emacs.png --out /tmp/emacs.iconset/icon_128x128.png  &>/dev/null
    sips -z 256 256 /tmp/emacs.png --out /tmp/emacs.iconset/icon_128x128@2x.png &>/dev/null
    iconutil -c icns /tmp/emacs.iconset -o "$APP_PATH/Contents/Resources/Emacs.icns"
    echo "    Icon created."
  else
    echo "    Icon download failed — app will use default icon."
  fi
fi

# --- Console app bundle ---
CONSOLE_APP_PATH="$HOME/Applications/Emacs Docker Console.app"
if [ -d "$CONSOLE_APP_PATH" ]; then
  skip "Emacs Console app bundle"
else
  echo "==> Creating Emacs Console app bundle in ~/Applications..."
  mkdir -p "$CONSOLE_APP_PATH/Contents/MacOS"
  mkdir -p "$CONSOLE_APP_PATH/Contents/Resources"

  cat > "$CONSOLE_APP_PATH/Contents/MacOS/EmacsConsole" << 'CONSOLESCRIPT'
#!/bin/bash
osascript << 'APPLESCRIPT'
tell application "Terminal"
  activate
  do script "export PATH=/opt/homebrew/bin:/usr/local/bin:$PATH; colima start 2>/dev/null || true; docker start CONTAINER_PLACEHOLDER 2>/dev/null || true; docker exec CONTAINER_PLACEHOLDER /home/emacs/bin/startup-sync.sh 2>/dev/null; docker exec -it CONTAINER_PLACEHOLDER emacs -nw"
end tell
APPLESCRIPT
CONSOLESCRIPT
  chmod +x "$CONSOLE_APP_PATH/Contents/MacOS/EmacsConsole"
  sed -i '' "s|CONTAINER_PLACEHOLDER|${DOCKER_CONTAINER}|g" "$CONSOLE_APP_PATH/Contents/MacOS/EmacsConsole"

  cat > "$CONSOLE_APP_PATH/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>EmacsConsole</string>
    <key>CFBundleIdentifier</key>
    <string>org.gnu.emacs.docker.console</string>
    <key>CFBundleName</key>
    <string>Emacs Docker Console</string>
    <key>CFBundleIconFile</key>
    <string>Emacs</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
</dict>
</plist>
PLIST

  if [ -f /tmp/emacs.png ]; then
    iconutil -c icns /tmp/emacs.iconset -o "$CONSOLE_APP_PATH/Contents/Resources/Emacs.icns" 2>/dev/null \
      && echo "    Icon created." || echo "    Icon skipped."
  fi
fi

# --- Docker shell app bundle ---
SHELL_APP_PATH="$HOME/Applications/Emacs Docker Shell.app"
if [ -d "$SHELL_APP_PATH" ]; then
  skip "Docker Shell app bundle"
else
  echo "==> Creating Docker Shell app bundle in ~/Applications..."
  mkdir -p "$SHELL_APP_PATH/Contents/MacOS"
  mkdir -p "$SHELL_APP_PATH/Contents/Resources"

  cat > "$SHELL_APP_PATH/Contents/MacOS/DockerShell" << 'SHELLSCRIPT'
#!/bin/bash
osascript << 'APPLESCRIPT'
tell application "Terminal"
  activate
  do script "export PATH=/opt/homebrew/bin:/usr/local/bin:$PATH; colima start 2>/dev/null || true; docker start CONTAINER_PLACEHOLDER 2>/dev/null || true; docker exec -it CONTAINER_PLACEHOLDER bash"
end tell
APPLESCRIPT
SHELLSCRIPT
  chmod +x "$SHELL_APP_PATH/Contents/MacOS/DockerShell"
  sed -i '' "s|CONTAINER_PLACEHOLDER|${DOCKER_CONTAINER}|g" "$SHELL_APP_PATH/Contents/MacOS/DockerShell"

  cat > "$SHELL_APP_PATH/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>DockerShell</string>
    <key>CFBundleIdentifier</key>
    <string>org.gnu.emacs.docker.shell</string>
    <key>CFBundleName</key>
    <string>Emacs Docker Shell</string>
    <key>CFBundleIconFile</key>
    <string>Emacs</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
</dict>
</plist>
PLIST

  if [ -f /tmp/emacs.png ]; then
    iconutil -c icns /tmp/emacs.iconset -o "$SHELL_APP_PATH/Contents/Resources/Emacs.icns" 2>/dev/null \
      && echo "    Icon created." || echo "    Icon skipped."
  fi
fi

# --- Docker root shell app bundle ---
ROOT_APP_PATH="$HOME/Applications/Emacs Docker Root Shell.app"
if [ -d "$ROOT_APP_PATH" ]; then
  skip "Docker Root Shell app bundle"
else
  echo "==> Creating Docker Root Shell app bundle in ~/Applications..."
  mkdir -p "$ROOT_APP_PATH/Contents/MacOS"
  mkdir -p "$ROOT_APP_PATH/Contents/Resources"

  cat > "$ROOT_APP_PATH/Contents/MacOS/DockerRootShell" << 'ROOTSCRIPT'
#!/bin/bash
osascript << 'APPLESCRIPT'
tell application "Terminal"
  activate
  do script "export PATH=/opt/homebrew/bin:/usr/local/bin:$PATH; colima start 2>/dev/null || true; docker start CONTAINER_PLACEHOLDER 2>/dev/null || true; docker exec -it --user root CONTAINER_PLACEHOLDER bash"
end tell
APPLESCRIPT
ROOTSCRIPT
  chmod +x "$ROOT_APP_PATH/Contents/MacOS/DockerRootShell"
  sed -i '' "s|CONTAINER_PLACEHOLDER|${DOCKER_CONTAINER}|g" "$ROOT_APP_PATH/Contents/MacOS/DockerRootShell"

  cat > "$ROOT_APP_PATH/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>DockerRootShell</string>
    <key>CFBundleIdentifier</key>
    <string>org.gnu.emacs.docker.rootshell</string>
    <key>CFBundleName</key>
    <string>Emacs Docker Root Shell</string>
    <key>CFBundleIconFile</key>
    <string>Emacs</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
</dict>
</plist>
PLIST

  if [ -f /tmp/emacs.png ]; then
    iconutil -c icns /tmp/emacs.iconset -o "$ROOT_APP_PATH/Contents/Resources/Emacs.icns" 2>/dev/null \
      && echo "    Icon created." || echo "    Icon skipped."
  fi
fi

# --- Shell alias ---
if grep -q "alias emacs=" ~/.zshrc 2>/dev/null; then
  skip "Shell alias (already in ~/.zshrc)"
else
  echo "==> Adding emacs alias to ~/.zshrc..."
  cat >> ~/.zshrc << 'ZSHEOF'

# Emacs in Docker
alias emacs='(){
  export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
  colima start 2>/dev/null || true
  docker start CONTAINER_PLACEHOLDER 2>/dev/null || true
  docker exec CONTAINER_PLACEHOLDER /home/emacs/bin/startup-sync.sh 2>/dev/null
  docker exec -it -e DISPLAY=host.docker.internal:0 CONTAINER_PLACEHOLDER emacs "$@"
}'
ZSHEOF
  sed -i '' "s|CONTAINER_PLACEHOLDER|${DOCKER_CONTAINER}|g" ~/.zshrc
fi

# --- Anthropic API Key im Container setzen ---
if docker exec "$DOCKER_CONTAINER" test -f /home/emacs/.emacs.d/secrets.el 2>/dev/null; then
  skip "ANTHROPIC_API_KEY (already in secrets.el)"
else
  echo "==> Anthropic API Key aus Bitwarden holen..."
  ANTHROPIC_API_KEY=$(bw get item "$BW_ANTHROPIC_ITEM" --session "$BW_SESSION" 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(next(f['value'] for f in d.get('fields',[]) if f['name']=='$BW_FIELD'))") || true
  if [ -n "$ANTHROPIC_API_KEY" ]; then
    docker exec "$DOCKER_CONTAINER" bash -c "mkdir -p ~/.emacs.d && cat > ~/.emacs.d/secrets.el << 'SECRETEOF'
(setenv \"ANTHROPIC_API_KEY\" \"${ANTHROPIC_API_KEY}\")
SECRETEOF"
    echo "    API Key in secrets.el gesetzt."
  else
    echo "WARN: Anthropic API Key nicht in Bitwarden gefunden (Item: $BW_ANTHROPIC_ITEM, Feld: $BW_FIELD)"
  fi
fi

# --- Git-Identität im Container setzen ---
if docker exec "$DOCKER_CONTAINER" git config --global user.email 2>/dev/null | grep -q "@"; then
  skip "Git-Identität (already set)"
else
  echo "==> Git-Identität im Container setzen..."
  docker exec "$DOCKER_CONTAINER" bash -c "git config --global user.email '${GIT_EMAIL}' && git config --global user.name '${GIT_NAME}'"
fi

# --- Claude Code credentials ---
if docker exec "$DOCKER_CONTAINER" test -f /home/emacs/.claude/auth.json 2>/dev/null; then
  skip "Claude Code credentials (already in container)"
elif [ -f ~/.claude/auth.json ]; then
  echo "==> Copying Claude Code credentials to container..."
  docker cp ~/.claude/. "$DOCKER_CONTAINER":/home/emacs/.claude/
  docker exec --user root "$DOCKER_CONTAINER" chown -R emacs:emacs /home/emacs/.claude/
  echo "    Claude Code credentials copied."
else
  echo ""
  echo "---------------------------------------------------------------------"
  echo "HINWEIS: Claude Code noch nicht authentifiziert"
  echo "---------------------------------------------------------------------"
  echo "Führe zuerst aus:  claude"
  echo "Dann das Skript erneut starten um die Credentials in den Container zu kopieren."
  echo "---------------------------------------------------------------------"
fi

echo ""
echo "All done."
echo "NOTE: Run 'colima start' after each reboot before using Docker."
echo "NOTE: To exit Emacs press C-x C-c (Ctrl+x then Ctrl+c)"
echo ""
echo "Emacs app available at: ~/Applications/Emacs (Docker).app"
echo "To enter the container:  docker exec -it ${DOCKER_CONTAINER} bash"
echo ""
echo "==> Starting Emacs..."
docker exec -it "$DOCKER_CONTAINER" emacs
