#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/setup-lib.sh"
trap 'setup_runtime_cleanup_secret_keychain 2>/dev/null || true' EXIT

setup_ensure_config
setup_runtime_load

ICLOUD_REPO_PATH="$HOME/Library/Mobile Documents/com~apple~CloudDocs/$GH_REPO"
SECRETS_REPO="$ICLOUD_REPO_PATH/emacs.d/secrets.el"
EMACS_SECRETS="$HOME/.emacs.d/secrets.el"

mkdir -p "$HOME/.emacs.d"

if [ -z "${GH_USER:-}" ]; then
  echo ";; secrets.el — add API keys here" > "$EMACS_SECRETS"
  echo "==> secrets.el created for local mode."
  echo "    To use Bitwarden-backed secrets later, set GH_USER and run:"
  echo "      bash ~/emacs-mac-setup/setup-intake.sh --repair bitwarden"
  exit 0
fi

setup_runtime_require GH_REPO BW_FIELD BW_GEMINI_ITEM BW_KEYCHAIN_SERVICE BITWARDEN_EMAIL BITWARDEN_MASTER_PASSWORD
setup_runtime_load_bitwarden_secrets || exit 1

if [ -f "$SECRETS_REPO" ] && grep -q "setenv" "$SECRETS_REPO" 2>/dev/null; then
  echo "==> secrets.el available in repo (git-crypt decrypted) — creating symlink..."
  if [ -L "$EMACS_SECRETS" ] && [ "$(readlink "$EMACS_SECRETS")" = "$SECRETS_REPO" ]; then
    echo "==> Already done: secrets.el symlink — skipping."
  else
    [ -e "$EMACS_SECRETS" ] && rm "$EMACS_SECRETS"
    ln -sf "$SECRETS_REPO" "$EMACS_SECRETS"
    echo "    Symlink: $EMACS_SECRETS -> $SECRETS_REPO"
  fi
else
  echo "==> Repo file missing or still encrypted — writing keys from setup runtime..."

  echo ";; secrets.el — API keys (not tracked in git)" > "$EMACS_SECRETS"

  if [ -n "$ANTHROPIC_API_KEY" ]; then
    printf '(setenv "ANTHROPIC_API_KEY" "%s")\n' "$ANTHROPIC_API_KEY" >> "$EMACS_SECRETS"
  else
    echo ";; ANTHROPIC_API_KEY: run setup-intake.sh --repair anthropic" >> "$EMACS_SECRETS"
  fi

  if [ -n "$GEMINI_API_KEY" ]; then
    printf '(setenv "GEMINI_API_KEY" "%s")\n' "$GEMINI_API_KEY" >> "$EMACS_SECRETS"
  else
    echo ";; GEMINI_API_KEY: run setup-intake.sh --repair gemini" >> "$EMACS_SECRETS"
  fi

  echo "==> secrets.el written to $EMACS_SECRETS."
  if [ -z "$GEMINI_API_KEY" ] || [ -z "$ANTHROPIC_API_KEY" ]; then
    echo "    Missing API keys can be added with:"
    echo "      bash ~/emacs-mac-setup/setup-intake.sh --repair bitwarden"
  fi
  echo "    Restart Emacs for the change to take effect."
fi

setup_runtime_cleanup_secret_keychain
