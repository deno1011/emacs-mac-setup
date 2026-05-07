#!/bin/bash
set -e

CONFIG_FILE="$HOME/setup-emacs-mac.conf"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "ERROR: $CONFIG_FILE not found. Run bootstrap.sh first."
  exit 1
fi
source "$CONFIG_FILE"

EMACS_SECRETS="$HOME/.emacs.d/secrets.el"

if [ -z "$GH_USER" ]; then
  echo "ERROR: GH_USER not set — Bitwarden not configured in local mode."
  exit 1
fi

if ! command -v bw &>/dev/null; then
  echo "ERROR: Bitwarden CLI not installed. Run ~/setup-bitwarden.sh first."
  exit 1
fi

source "$HOME/bw-unlock.sh"
bw_ensure_session || exit 1

echo "==> Fetching Anthropic API key from Bitwarden (item: $BW_ANTHROPIC_ITEM, field: $BW_ANTHROPIC_FIELD)..."
ANTHROPIC_API_KEY=$(bw_get_field "$BW_ANTHROPIC_ITEM" "$BW_ANTHROPIC_FIELD")

if [ -z "$ANTHROPIC_API_KEY" ]; then
  echo "ERROR: Key not found in Bitwarden (item: $BW_ANTHROPIC_ITEM, field: $BW_ANTHROPIC_FIELD)."
  echo "       Add the entry first, then re-run this script."
  exit 1
fi

mkdir -p "$HOME/.emacs.d"
printf '(setenv "ANTHROPIC_API_KEY" "%s")\n' "$ANTHROPIC_API_KEY" > "$EMACS_SECRETS"
echo "==> secrets.el written to $EMACS_SECRETS"
echo "    Restart Emacs for the change to take effect."
