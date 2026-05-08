#!/bin/bash
# Bootstrap: Downloads all Emacs setup scripts from GitHub.
# Usage: bash bootstrap.sh [user/private-conf-repo]
# Example: bash bootstrap.sh janedoe/mac-setup-conf
# (user/repo required here since GH_USER is not yet known at bootstrap time)

set -e

# --- Homebrew ---
if ! command -v brew &>/dev/null; then
  echo "==> Installing Homebrew (sudo password required)..."
  sudo -v
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  [ -f /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
  [ -f /usr/local/bin/brew ]    && eval "$(/usr/local/bin/brew shellenv)"
fi

CONF_REPO="${1:-}"
DEST="$(pwd)"
CONFIG_FILE="$HOME/setup-emacs-mac.conf"

echo "==> Downloading all scripts to $DEST/..."
_DL_TMP=$(mktemp -d)
curl -fsSL "https://github.com/deno1011/emacs-mac-setup/archive/refs/heads/main.tar.gz" \
  | tar -xz -C "$_DL_TMP" --strip-components=1
for _F in "$_DL_TMP"/*; do
  _NAME="$(basename "$_F")"
  [ "$_NAME" = "bootstrap.sh" ] && continue
  cp "$_F" "$DEST/$_NAME"
  echo "    $_NAME"
done
rm -rf "$_DL_TMP"

chmod +x "$DEST"/*.sh

# --- Pull personal config from private repo ---
CONF_PULLED=false
if [ -n "$CONF_REPO" ]; then
  echo ""
  echo "==> Trying to pull personal config from github.com/${CONF_REPO}..."
  CONF_TMP=$(mktemp -d)

  # Install gh if missing — needed for private repo access
  if ! command -v gh &>/dev/null; then
    echo "    Installing GitHub CLI..."
    brew install gh &>/dev/null
  fi

  # Authenticate gh — fetch token from Bitwarden automatically
  if ! gh auth status &>/dev/null 2>&1; then
    echo "    Authenticating GitHub CLI..."

    # Defaults matching setup-emacs-mac.conf.template
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
      # Get master password from keychain, or prompt once
      _BS_BW_MASTER=$(security find-generic-password -a "$_BS_BW_KC_ACC" -s "$_BS_BW_KC_SVC" -w 2>/dev/null) || true
      if [ -z "$_BS_BW_MASTER" ]; then
        printf "    Bitwarden master password: "
        read -rs _BS_BW_MASTER < /dev/tty
        echo ""
      fi
      export __BS_BW_MASTER="$_BS_BW_MASTER"

      _BS_BW_STATUS=$(bw status 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('status','unauthenticated'))" 2>/dev/null || echo "unauthenticated")
      echo "    Bitwarden: $_BS_BW_STATUS"
      _BS_BW_SESSION=""

      if [ "$_BS_BW_STATUS" = "unauthenticated" ]; then
        printf "    Bitwarden email: "
        read -r _BS_BW_EMAIL < /dev/tty
        # stdin connected to /dev/tty so 2FA prompt works interactively
        _BS_BW_SESSION=$(bw login "$_BS_BW_EMAIL" --passwordenv __BS_BW_MASTER --raw < /dev/tty) || true
      fi

      # If still no session (locked state or login returned no session), try unlock
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
        echo "    WARN: Bitwarden unlock failed — falling back to manual token."
      fi
    fi

    if [ -n "$_BS_GH_TOKEN" ]; then
      echo "$_BS_GH_TOKEN" | gh auth login --with-token
      echo "    GitHub CLI authenticated via Bitwarden."
    else
      echo "    Enter GitHub PAT (Settings → Developer settings → Personal access tokens → Classic, scope: repo):"
      printf "    Token: "
      read -rs _BS_GH_TOKEN < /dev/tty
      echo ""
      [ -n "$_BS_GH_TOKEN" ] && echo "$_BS_GH_TOKEN" | gh auth login --with-token
    fi
    unset _BS_GH_TOKEN _BS_BW_SESSION _BS_BW_MASTER _BS_BW_EMAIL _BS_BW_STATUS \
          _BS_BW_KC_SVC _BS_BW_KC_ACC _BS_BW_GH_ITEM _BS_BW_FIELD
  fi
  if command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1; then
    if gh repo clone "$CONF_REPO" "$CONF_TMP/conf" &>/dev/null 2>&1; then
      CONF_PULLED=true
    fi
  fi
  # Fallback: try unauthenticated (works if repo is public, fails silently if private)
  if [ "$CONF_PULLED" = false ]; then
    if GIT_TERMINAL_PROMPT=0 git clone "https://github.com/${CONF_REPO}.git" "$CONF_TMP/conf" &>/dev/null 2>&1; then
      CONF_PULLED=true
    fi
  fi

  if [ "$CONF_PULLED" = true ] && [ -f "$CONF_TMP/conf/setup-emacs-mac.conf" ]; then
    cp "$CONF_TMP/conf/setup-emacs-mac.conf" "$CONFIG_FILE"
    echo "    setup-emacs-mac.conf pulled — config ready."
  else
    echo "    Private repo not accessible — falling back to template."
    CONF_PULLED=false
  fi
  rm -rf "$CONF_TMP"
fi

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
  _BW_KC_ACC="${BW_KEYCHAIN_ACCOUNT:-$USER}"
  _BW_KC_SVC="${BW_KEYCHAIN_SERVICE:-bitwarden-master}"
  _BW_CONFIGURED=$(security find-generic-password -a "$_BW_KC_ACC" -s "$_BW_KC_SVC" -w 2>/dev/null) || true
  unset _BW_KC_ACC _BW_KC_SVC
  if [ -n "$_BW_CONFIGURED" ]; then
    echo "  Bitwarden already configured — skipping setup."
    echo "  To update vault entries run:  bash $DEST/setup-bitwarden.sh"
  else
    bash "$DEST/setup-bitwarden.sh"
  fi
  unset _BW_CONFIGURED
else
  echo "  GH_USER not set — local mode, Bitwarden not required."
  echo "  Run $DEST/setup-bitwarden.sh after setting GH_USER if you want GitHub sync."
fi

# --- GitHub auth (mit Token aus Bitwarden) ---
if [ -n "$GH_USER" ]; then
  if ! command -v gh &>/dev/null; then
    echo "==> Installing GitHub CLI..."
    brew install gh &>/dev/null
    export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
  fi
  if gh auth status &>/dev/null 2>&1; then
    echo "==> GitHub auth: bereits authentifiziert."
  else
    echo "==> GitHub authentifizieren..."
    source "$DEST/bw-unlock.sh" 2>/dev/null || true
    _BS_GH_TOKEN=""
    if bw_ensure_session; then
      _BS_GH_TOKEN=$(bw_get_field "$BW_GH_ITEM" "$BW_FIELD") || true
    fi
    if [ -n "$_BS_GH_TOKEN" ]; then
      echo "$_BS_GH_TOKEN" | gh auth login --with-token
      gh auth setup-git
      echo "    GitHub authentifiziert."
    else
      echo "    WARN: GitHub-Token nicht in Bitwarden gefunden — manueller Login:"
      gh auth login < /dev/tty
      gh auth setup-git
    fi
    unset _BS_GH_TOKEN
  fi
fi

# --- GitHub Repos prüfen und anlegen ---
if [ -n "$GH_USER" ] && gh auth status &>/dev/null 2>&1; then
  echo ""
  echo "==> GitHub Repos prüfen..."
  source "$CONFIG_FILE"

  _create_repo_if_missing() {
    local REPO_NAME="$1" DESC="$2"
    if gh repo view "$GH_USER/$REPO_NAME" &>/dev/null 2>&1; then
      echo "    $GH_USER/$REPO_NAME — bereits vorhanden."
      return 1  # already existed
    fi
    echo "==> Repo $GH_USER/$REPO_NAME nicht gefunden — anlegen..."
    gh repo create "$GH_USER/$REPO_NAME" --private --description "$DESC"
    echo "    $GH_USER/$REPO_NAME erstellt."
    return 0  # was created
  }

  _create_repo_if_missing "${GH_REPO:-emacs-config}" \
    "Emacs configuration and org files" || true

  if [ -n "${CONF_REPO:-}" ]; then
    _create_repo_if_missing "$CONF_REPO" "Emacs Mac Setup personal config" || true
    echo "==> setup-emacs-mac.conf → $GH_USER/$CONF_REPO hochladen..."
    _CONF_B64=$(base64 -i "$CONFIG_FILE" | tr -d '\n')
    _CONF_SHA=$(gh api "repos/$GH_USER/$CONF_REPO/contents/setup-emacs-mac.conf" --jq '.sha' 2>/dev/null || true)
    if [ -n "$_CONF_SHA" ]; then
      gh api "repos/$GH_USER/$CONF_REPO/contents/setup-emacs-mac.conf" \
        -X PUT -f message="Update config" -f content="$_CONF_B64" -f sha="$_CONF_SHA" \
        &>/dev/null && echo "    setup-emacs-mac.conf aktualisiert." \
        || echo "WARN: Upload fehlgeschlagen — bitte setup-emacs-mac.conf manuell in $GH_USER/$CONF_REPO ablegen."
    else
      gh api "repos/$GH_USER/$CONF_REPO/contents/setup-emacs-mac.conf" \
        -X PUT -f message="Initial config" -f content="$_CONF_B64" \
        &>/dev/null && echo "    setup-emacs-mac.conf hochgeladen." \
        || echo "WARN: Upload fehlgeschlagen — bitte setup-emacs-mac.conf manuell in $GH_USER/$CONF_REPO ablegen."
    fi
    unset _CONF_B64 _CONF_SHA
  fi
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
echo ""
if [ -n "${GH_USER:-}" ] && [ -n "${CONF_REPO:-}" ]; then
  echo "  On a new Mac, skip config questions by passing your config repo:"
  echo "    bash <(curl -fsSL https://raw.githubusercontent.com/deno1011/emacs-mac-setup/main/bootstrap.sh) $GH_USER/$CONF_REPO"
  echo ""
fi
echo "  Docs: https://github.com/deno1011/emacs-mac-setup/blob/main/README.md"
echo ""
