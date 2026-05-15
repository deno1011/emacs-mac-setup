#!/bin/bash
set -e

[ -f /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
[ -f /usr/local/bin/brew ]    && eval "$(/usr/local/bin/brew shellenv)"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skip() { echo "==> Already done: $1 — skipping."; }

# --- Load configuration ---
CONFIG_FILE="$HOME/emacs-mac-setup/setup-emacs-mac.conf"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "ERROR: Config file not found: $CONFIG_FILE"
  echo "Please create it (template: setup-emacs-mac.conf)"
  exit 1
fi
source "$CONFIG_FILE"
source "$SCRIPT_DIR/bw-unlock.sh"

# --- Check required fields ---
MISSING=()
[ -z "$GIT_NAME" ]  && MISSING+=("GIT_NAME")
[ -z "$GIT_EMAIL" ] && MISSING+=("GIT_EMAIL")
[ -z "$GH_USER" ]   && MISSING+=("GH_USER")
[ -z "$GH_REPO" ]   && MISSING+=("GH_REPO")
if [ ${#MISSING[@]} -gt 0 ]; then
  echo "ERROR: The following required fields are missing or empty in $CONFIG_FILE:"
  for F in "${MISSING[@]}"; do echo "  $F"; done
  echo "Template: ~/emacs-mac-setup/setup-emacs-mac.conf.template"
  exit 1
fi

# --- Prompt for passwords upfront ---
ICLOUD_REPO_PATH="$HOME/Library/Mobile Documents/com~apple~CloudDocs/$GH_REPO"

# Only prompt for admin password if XQuartz is not yet installed
if [ ! -d "/Applications/Utilities/XQuartz.app" ]; then
  echo "==> Enter admin password (once, for XQuartz):"
  read -rs ADMIN_PASS < /dev/tty
  echo ""
fi

# Bitwarden needed if: iCloud repo missing OR gh not authenticated OR API key missing in container
ANTHROPIC_KEY_SET=$(docker inspect "$DOCKER_CONTAINER" &>/dev/null && docker exec "$DOCKER_CONTAINER" grep -q "ANTHROPIC_API_KEY" /home/emacs/.bashrc 2>/dev/null && echo "yes") || true
if [ ! -d "$ICLOUD_REPO_PATH/.git" ] || ! gh auth status &>/dev/null 2>&1 || [ "$ANTHROPIC_KEY_SET" != "yes" ]; then
  if ! command -v bw &>/dev/null; then
    echo "==> Installing Bitwarden CLI (needed for setup)..."
    brew install bitwarden-cli
  fi
  bw_ensure_session || exit 1
fi

# --- Clean incomplete Homebrew downloads ---
echo "==> Cleaning incomplete Homebrew downloads..."
rm -f ~/Library/Caches/Homebrew/downloads/*.incomplete

# --- XQuartz (install directly, not via brew cask, so the sudo cache stays active) ---
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
  echo "==> Upgrading Docker CLI..."
  brew upgrade docker 2>/dev/null || true
else
  echo "==> Installing Docker CLI..."
  brew install docker
fi

# --- Colima (Docker runtime) ---
if command -v colima &>/dev/null; then
  skip "Colima (already installed)"
else
  echo "==> Installing Colima..."
  brew install colima
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
  echo "==> Authenticating GitHub CLI with token from Bitwarden..."
  GH_TOKEN=$(bw_get_field "$BW_GH_ITEM" "$BW_FIELD") || true
  if [ -n "$GH_TOKEN" ]; then
    echo "$GH_TOKEN" | gh auth login --with-token
  else
    echo "WARN: GitHub token not found in Bitwarden. Please log in manually:"
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
  colima start || { echo "ERROR: Colima failed to start."; exit 1; }
fi

# --- Docker context ---
# Resolve Colima socket path — wait up to 30s for socket to appear
COLIMA_SOCK=""
echo "==> Waiting for Colima socket..."
for _I in $(seq 1 30); do
  for CANDIDATE in \
      "$HOME/.colima/docker.sock" \
      "$HOME/.colima/default/docker.sock" \
      "$HOME/.colima/_default/docker.sock"; do
    [ -S "$CANDIDATE" ] && COLIMA_SOCK="$CANDIDATE" && break 2
  done
  sleep 1
done
if [ -z "$COLIMA_SOCK" ]; then
  echo "ERROR: Colima socket not found after 30s."
  echo "       Available Colima files:"
  ls "$HOME/.colima/" 2>/dev/null || echo "       ~/.colima/ does not exist"
  exit 1
fi
echo "    Socket found: $COLIMA_SOCK"
# Create context if missing or broken
if ! docker context inspect colima &>/dev/null 2>&1; then
  echo "==> Creating Docker context for Colima..."
  docker context rm colima 2>/dev/null || true
  docker context create colima --docker "host=unix://${COLIMA_SOCK}"
fi
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
    aspell \
    aspell-de \
    aspell-en \
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

# --- Mac-side iCloud repo setup ---
ICLOUD_REPO_PATH="$HOME/Library/Mobile Documents/com~apple~CloudDocs/$GH_REPO"
ICLOUD_REPO_SYMLINK="$HOME/.emacs-icloud-repo"

if [ -d "$ICLOUD_REPO_PATH/.git" ]; then
  skip "iCloud repo (already cloned to Mac)"
  echo "==> Setting up GitHub credential helper and pulling..."
  gh auth setup-git
  git -C "$ICLOUD_REPO_PATH" remote set-url origin "https://github.com/${GH_USER}/${GH_REPO}.git"
  git -C "$ICLOUD_REPO_PATH" pull origin main || true
else
  echo "==> Fetching key from Bitwarden..."
  KEY_B64=$(bw_get_field "$BW_ITEM" "$BW_FIELD")

  echo "==> Setting up GitHub credential helper..."
  gh auth setup-git

  echo "==> Cloning repo to iCloud..."
  git clone "https://github.com/${GH_USER}/${GH_REPO}.git" "$ICLOUD_REPO_PATH"

  echo "==> Unlocking git-crypt on Mac..."
  echo "$KEY_B64" | tr -d '[:space:]' | python3 -c "import sys,base64; data=sys.stdin.read().strip(); sys.stdout.buffer.write(base64.b64decode(data + '=='))" > /tmp/gckey
  git -C "$ICLOUD_REPO_PATH" crypt unlock /tmp/gckey
  rm /tmp/gckey

  echo "==> Setting git identity..."
  git -C "$ICLOUD_REPO_PATH" config user.email "$GIT_EMAIL"
  git -C "$ICLOUD_REPO_PATH" config user.name "$GIT_NAME"

  echo "==> Setting post-commit hook (auto-push + beorg sync)..."
  cat > "$ICLOUD_REPO_PATH/.git/hooks/post-commit" << 'HOOKEOF'
#!/bin/sh
REPO_ORG="$(git rev-parse --show-toplevel)/org"
BEORG="$HOME/Library/Mobile Documents/iCloud~com~appsonthemove~beorg/Documents/org"
[ -d "$BEORG" ] && rsync -a --delete "$REPO_ORG/" "$BEORG/" 2>/dev/null || true
git push origin main &
HOOKEOF
  chmod +x "$ICLOUD_REPO_PATH/.git/hooks/post-commit"

  echo "==> Migrating existing beorg files..."
  if [ -d "$BEORG_ORG_PATH" ]; then
    rsync -av --ignore-existing "$BEORG_ORG_PATH/" "$ICLOUD_REPO_PATH/org/"
    git -C "$ICLOUD_REPO_PATH" add org/
    if ! git -C "$ICLOUD_REPO_PATH" diff --cached --quiet; then
      git -C "$ICLOUD_REPO_PATH" commit -m "Migrate existing beorg files from iCloud"
      git -C "$ICLOUD_REPO_PATH" push
    else
      echo "    No new files to migrate."
    fi
  fi

  echo "    iCloud repo set up."
fi

# --- Mac-seitige secrets.el symlink ---
_SECRETS_REPO="$ICLOUD_REPO_PATH/emacs.d/secrets.el"
_SECRETS_LOCAL="$HOME/.emacs.d/secrets.el"
if [ -f "$_SECRETS_REPO" ] && grep -q "setenv" "$_SECRETS_REPO" 2>/dev/null; then
  mkdir -p "$HOME/.emacs.d"
  if [ -L "$_SECRETS_LOCAL" ] && [ "$(readlink "$_SECRETS_LOCAL")" = "$_SECRETS_REPO" ]; then
    skip "secrets.el symlink (Mac)"
  else
    [ -e "$_SECRETS_LOCAL" ] && rm "$_SECRETS_LOCAL"
    ln -sf "$_SECRETS_REPO" "$_SECRETS_LOCAL"
    echo "==> secrets.el symlink set: $_SECRETS_LOCAL → $_SECRETS_REPO"
  fi
else
  echo "WARN: $_SECRETS_REPO missing or still encrypted — symlink not set."
fi

# --- Start container ---
HAS_BEORG_MOUNT=false
if docker inspect "$DOCKER_CONTAINER" --format '{{range .HostConfig.Binds}}{{.}} {{end}}' 2>/dev/null | grep -q "/beorg"; then
  HAS_BEORG_MOUNT=true
fi

if docker ps -q -f name="$DOCKER_CONTAINER" 2>/dev/null | grep -q .; then
  if [ "$HAS_BEORG_MOUNT" = false ]; then
    echo "==> Recreating container (beorg mount missing)..."
    docker rm -f "$DOCKER_CONTAINER"
  else
    skip "Container ($DOCKER_CONTAINER already running)"
  fi
elif docker ps -aq -f name="$DOCKER_CONTAINER" 2>/dev/null | grep -q .; then
  if [ "$HAS_BEORG_MOUNT" = false ]; then
    echo "==> Recreating container (beorg mount missing)..."
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

# --- init.el — always update (managed by setup, not user-customized) ---
echo "==> Installing init.el..."
docker exec "$DOCKER_CONTAINER" bash -c 'mkdir -p ~/.emacs.d'
if [ -f "$SCRIPT_DIR/init.el" ]; then
  _INIT_TMP=$(mktemp)
  sed "s|GH_REPO|${GH_REPO}|g" "$SCRIPT_DIR/init.el" > "$_INIT_TMP"
  docker cp "$_INIT_TMP" "$DOCKER_CONTAINER:/home/emacs/.emacs.d/init.el"
  rm -f "$_INIT_TMP"
  docker exec --user root "$DOCKER_CONTAINER" chown emacs:emacs /home/emacs/.emacs.d/init.el
else
  echo "ERROR: init.el not found — run bootstrap.sh first."
  exit 1
fi

# --- Git identity ---
if docker exec "$DOCKER_CONTAINER" git config --global user.email 2>/dev/null | grep -q "@"; then
  skip "Git identity (already set)"
else
  echo "==> Setting git identity in container..."
  docker exec "$DOCKER_CONTAINER" bash -c "git config --global user.email '${GIT_EMAIL}' && git config --global user.name '${GIT_NAME}'"
fi

# --- GitHub credentials (must be set before startup-sync.sh clones) ---
if docker exec "$DOCKER_CONTAINER" test -f /home/emacs/.git-credentials 2>/dev/null; then
  skip "GitHub credentials (already configured in container)"
else
  echo "==> Setting up GitHub credentials in container..."
  GH_TOKEN_CONTAINER=$(gh auth token 2>/dev/null) || true
  if [ -n "$GH_TOKEN_CONTAINER" ]; then
    docker exec "$DOCKER_CONTAINER" git config --global credential.helper store
    docker exec "$DOCKER_CONTAINER" bash -c \
      "printf 'https://${GH_USER}:%s@github.com\n' '${GH_TOKEN_CONTAINER}' > ~/.git-credentials && chmod 600 ~/.git-credentials"
    echo "    GitHub credentials configured."
  else
    echo "WARN: GitHub token not available — container will not be able to clone/push."
  fi
fi

# --- startup-sync.sh ---
if docker exec "$DOCKER_CONTAINER" test -f /home/emacs/bin/startup-sync.sh 2>/dev/null; then
  skip "startup-sync.sh (already present)"
else
  echo "==> Creating startup-sync.sh in container..."
  docker exec "$DOCKER_CONTAINER" mkdir -p /home/emacs/bin
  _SYNC_TMP=$(mktemp)
  cat > "$_SYNC_TMP" << EOF
#!/bin/bash
REPO="/home/emacs/${GH_REPO}"
BEORG="/beorg"
GH_URL="https://github.com/${GH_USER}/${GH_REPO}.git"

if [ ! -d "\$REPO/.git" ]; then
  git clone "\$GH_URL" "\$REPO" 2>/dev/null || true
else
  cd "\$REPO" && git pull origin main 2>/dev/null || true
fi

HOOK="\$REPO/.git/hooks/post-commit"
if [ ! -f "\$HOOK" ]; then
  printf '#!/bin/bash\nREPO="\$(git rev-parse --show-toplevel)"\nrsync -a --delete "\$REPO/data/org/" /beorg/ 2>/dev/null || true\ngit push origin main 2>/dev/null || true &\n' > "\$HOOK"
  chmod +x "\$HOOK"
fi

KEY="\$HOME/.git-crypt-key"
if [ -f "\$KEY" ] && [ -d "\$REPO/.git" ]; then
  git -C "\$REPO" crypt unlock "\$KEY" 2>/dev/null || true
fi

[ -d "\$BEORG" ] && [ -d "\$REPO/data/org" ] && rsync -a --delete "\$REPO/data/org/" "\$BEORG/" 2>/dev/null || true
EOF
  docker cp "$_SYNC_TMP" "$DOCKER_CONTAINER:/home/emacs/bin/startup-sync.sh"
  docker exec --user root "$DOCKER_CONTAINER" chmod +x /home/emacs/bin/startup-sync.sh
  docker exec --user root "$DOCKER_CONTAINER" chown emacs:emacs /home/emacs/bin/startup-sync.sh
  rm -f "$_SYNC_TMP"
fi

# --- Clone repo inside container (run startup-sync.sh now so repo exists for git-crypt) ---
if docker exec "$DOCKER_CONTAINER" test -d "/home/emacs/${GH_REPO}/.git" 2>/dev/null; then
  skip "Repo (already cloned in container)"
else
  echo "==> Cloning repo inside container..."
  docker exec "$DOCKER_CONTAINER" /home/emacs/bin/startup-sync.sh || true
fi

# --- Detect GH_REPO rename inside container ---
_OLD_REPO=$(docker exec "$DOCKER_CONTAINER" bash -c "
  for d in /home/emacs/*/; do
    name=\$(basename \"\${d%/}\")
    [ \"\$name\" = '${GH_REPO}' ] && continue
    if [ -d \"\${d%/}/.git\" ]; then
      remote=\$(git -C \"\${d%/}\" remote get-url origin 2>/dev/null) || true
      if echo \"\$remote\" | grep -q 'github.com/${GH_USER}/'; then
        echo \"\$name\"; break
      fi
    fi
  done
" 2>/dev/null) || true

if [ -n "$_OLD_REPO" ]; then
  echo "==> GH_REPO renamed in container: $_OLD_REPO → $GH_REPO"
  docker exec "$DOCKER_CONTAINER" bash -c "mv /home/emacs/$_OLD_REPO /home/emacs/$GH_REPO 2>/dev/null || true"
  docker exec "$DOCKER_CONTAINER" bash -c "git -C /home/emacs/$GH_REPO remote set-url origin 'https://github.com/$GH_USER/$GH_REPO.git' 2>/dev/null || true"
  echo "    Container repo folder renamed and remote updated."
fi
unset _OLD_REPO

# --- config.org: only copy if missing (user-managed) ---
if docker exec "$DOCKER_CONTAINER" test -f "/home/emacs/${GH_REPO}/config/config.org" 2>/dev/null; then
  skip "config.org (user-managed — not overwritten)"
else
  echo "==> Copying starter config.org into container..."
  docker exec "$DOCKER_CONTAINER" bash -c "mkdir -p ~/${GH_REPO}/config ~/${GH_REPO}/data/org"
  if [ -f "$SCRIPT_DIR/config.org" ]; then
    docker cp "$SCRIPT_DIR/config.org" "$DOCKER_CONTAINER:/home/emacs/${GH_REPO}/config/config.org"
    docker exec --user root "$DOCKER_CONTAINER" chown emacs:emacs "/home/emacs/${GH_REPO}/config/config.org"
  else
    echo "WARN: config.org not found in script dir — Emacs will use built-in defaults."
  fi
fi
# Modular config files are setup-managed — always update from SCRIPT_DIR
for _CF in core.org org-setup.org gptel-setup.org; do
  if [ -f "$SCRIPT_DIR/$_CF" ]; then
    docker cp "$SCRIPT_DIR/$_CF" "$DOCKER_CONTAINER:/home/emacs/${GH_REPO}/config/$_CF"
    docker exec --user root "$DOCKER_CONTAINER" chown emacs:emacs "/home/emacs/${GH_REPO}/config/$_CF"
    echo "==> $_CF updated in container."
  fi
done
unset _CF

echo "==> Verifying container..."
docker exec "$DOCKER_CONTAINER" emacs --version
docker exec "$DOCKER_CONTAINER" git --version

# --- git-crypt key (repo must exist first, cloned above) ---
if docker exec "$DOCKER_CONTAINER" test -f /home/emacs/.git-crypt-key 2>/dev/null; then
  skip "git-crypt key (already stored in container)"
else
  echo "==> Fetching git-crypt key from Bitwarden..."
  GC_KEY_B64=$(bw_get_field "$BW_ITEM" "$BW_FIELD") || true
  if [ -n "$GC_KEY_B64" ]; then
    echo "$GC_KEY_B64" | tr -d '[:space:]' \
      | python3 -c "import sys,base64; data=sys.stdin.read().strip(); sys.stdout.buffer.write(base64.b64decode(data + '=='))" \
      > /tmp/_gckey_docker
    docker cp /tmp/_gckey_docker "$DOCKER_CONTAINER:/home/emacs/.git-crypt-key"
    docker exec --user root "$DOCKER_CONTAINER" chown emacs:emacs /home/emacs/.git-crypt-key
    docker exec --user root "$DOCKER_CONTAINER" chmod 600 /home/emacs/.git-crypt-key
    docker exec "$DOCKER_CONTAINER" git -C "/home/emacs/${GH_REPO}" crypt unlock /home/emacs/.git-crypt-key 2>/dev/null \
      && echo "    git-crypt unlocked." \
      || echo "WARN: git-crypt unlock failed — org/ files still encrypted."
    rm -f /tmp/_gckey_docker
  else
    echo "WARN: git-crypt key not found in Bitwarden — org/ files will remain encrypted."
  fi
fi

# --- secrets.el (Repo → Symlink, else Bitwarden) ---
_C_SECRETS="/home/emacs/.emacs.d/secrets.el"
_C_REPO_SECRETS="/home/emacs/${GH_REPO}/emacs.d/secrets.el"
if docker exec "$DOCKER_CONTAINER" test -L "$_C_SECRETS" 2>/dev/null; then
  skip "secrets.el (symlink already set in container)"
elif docker exec "$DOCKER_CONTAINER" bash -c "[ -f '$_C_REPO_SECRETS' ] && grep -q setenv '$_C_REPO_SECRETS'" 2>/dev/null; then
  echo "==> Symlinking secrets.el from repo (container)..."
  docker exec "$DOCKER_CONTAINER" bash -c "mkdir -p ~/.emacs.d && ln -sf '$_C_REPO_SECRETS' '$_C_SECRETS'"
  docker exec --user root "$DOCKER_CONTAINER" chown -h emacs:emacs "$_C_SECRETS"
  echo "    Symlink set."
else
  echo "==> secrets.el from Bitwarden (repo file missing or still encrypted)..."
  ANTHROPIC_API_KEY=$(bw_get_field "$BW_ANTHROPIC_ITEM" "$BW_FIELD") || true
  if [ -n "$ANTHROPIC_API_KEY" ]; then
    _SECRET_TMP=$(mktemp)
    printf '(setenv "ANTHROPIC_API_KEY" "%s")\n' "$ANTHROPIC_API_KEY" > "$_SECRET_TMP"
    docker exec "$DOCKER_CONTAINER" bash -c 'mkdir -p ~/.emacs.d'
    docker cp "$_SECRET_TMP" "$DOCKER_CONTAINER:$_C_SECRETS"
    docker exec --user root "$DOCKER_CONTAINER" chown emacs:emacs "$_C_SECRETS"
    rm -f "$_SECRET_TMP"
    echo "    API key set from Bitwarden."
  else
    echo "WARN: Anthropic API key not found in Bitwarden (Item: $BW_ANTHROPIC_ITEM, Field: $BW_FIELD)"
  fi
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
  echo "NOTE: Claude Code not yet authenticated"
  echo "---------------------------------------------------------------------"
  echo "Run:  claude"
  echo "Then re-run this script to copy credentials into the container."
  echo "---------------------------------------------------------------------"
fi

# --- Create macOS app bundle in ~/Applications ---
APP_PATH="$HOME/Applications/GUI Docker Emacs.app"
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
    <string>GUI Docker Emacs</string>
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
CONSOLE_APP_PATH="$HOME/Applications/Console Docker Emacs.app"
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
    <string>Console Docker Emacs</string>
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
SHELL_APP_PATH="$HOME/Applications/Shell Docker Emacs.app"
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
    <string>Shell Docker Emacs</string>
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
ROOT_APP_PATH="$HOME/Applications/Root Shell Docker Emacs.app"
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
    <string>Root Shell Docker Emacs</string>
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

echo ""
echo "All done."
echo "NOTE: Run 'colima start' after each reboot before using Docker."
echo "NOTE: To exit Emacs press C-x C-c (Ctrl+x then Ctrl+c)"
echo ""
echo "Emacs app available at: ~/Applications/Emacs (Docker).app"
echo "To enter the container:  docker exec -it ${DOCKER_CONTAINER} bash"
echo ""
echo "==> Starting Emacs..."
/opt/X11/bin/xhost +localhost 2>/dev/null || true
docker exec -it -e DISPLAY=host.docker.internal:0 "$DOCKER_CONTAINER" emacs
