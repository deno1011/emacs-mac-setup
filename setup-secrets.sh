#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$HOME/emacs-mac-setup/setup-emacs-mac.conf"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "ERROR: $CONFIG_FILE not found. Run bootstrap.sh first."
  exit 1
fi
source "$CONFIG_FILE"

ICLOUD_REPO_PATH="$HOME/Library/Mobile Documents/com~apple~CloudDocs/$GH_REPO"
SECRETS_REPO="$ICLOUD_REPO_PATH/emacs.d/secrets.el"
EMACS_SECRETS="$HOME/.emacs.d/secrets.el"

if [ -z "$GH_USER" ]; then
  echo "ERROR: GH_USER not set — Bitwarden not configured in local mode."
  exit 1
fi

mkdir -p "$HOME/.emacs.d"

if [ -f "$SECRETS_REPO" ] && grep -q "setenv" "$SECRETS_REPO" 2>/dev/null; then
  echo "==> secrets.el available in repo (git-crypt decrypted) — creating symlink..."
  if [ -L "$EMACS_SECRETS" ] && [ "$(readlink "$EMACS_SECRETS")" = "$SECRETS_REPO" ]; then
    echo "==> Already done: secrets.el symlink — skipping."
  else
    [ -e "$EMACS_SECRETS" ] && rm "$EMACS_SECRETS"
    ln -sf "$SECRETS_REPO" "$EMACS_SECRETS"
    echo "    Symlink: $EMACS_SECRETS → $SECRETS_REPO"
  fi
else
  echo "==> Repo file missing or still encrypted — fetching key from Bitwarden..."
  if ! command -v bw &>/dev/null; then
    echo "ERROR: Bitwarden CLI not installed. Run $SCRIPT_DIR/setup-bitwarden.sh first."
    exit 1
  fi
  source "$SCRIPT_DIR/bw-unlock.sh"
  bw_ensure_session || exit 1

  echo ";; secrets.el — API keys (not tracked in git)" > "$EMACS_SECRETS"

  # --- Anthropic ---
  ANTHROPIC_API_KEY=$(bw_ensure_api_key \
                        "$BW_ANTHROPIC_ITEM" "$BW_FIELD" \
                        "Anthropic API key" \
                        "https://console.anthropic.com/settings/keys")
  if [ -n "$ANTHROPIC_API_KEY" ]; then
    printf '(setenv "ANTHROPIC_API_KEY" "%s")\n' "$ANTHROPIC_API_KEY" >> "$EMACS_SECRETS"
  fi

  # --- Gemini (free tier — default gptel backend) ---
  GEMINI_API_KEY=$(bw_ensure_api_key \
                     "$BW_GEMINI_ITEM" "$BW_FIELD" \
                     "Gemini API key (free)" \
                     "https://aistudio.google.com/apikey")
  if [ -n "$GEMINI_API_KEY" ]; then
    printf '(setenv "GEMINI_API_KEY" "%s")\n' "$GEMINI_API_KEY" >> "$EMACS_SECRETS"
  fi

  echo "==> secrets.el written to $EMACS_SECRETS."
  echo "    Restart Emacs for the change to take effect."
fi
