#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$HOME/emacs-mac-setup/setup-emacs-mac.conf"
source "$SCRIPT_DIR/bw-unlock.sh"
trap 'setup_runtime_cleanup_secret_keychain 2>/dev/null || true' EXIT
setup_runtime_load

ICLOUD_REPO_PATH="$HOME/Library/Mobile Documents/com~apple~CloudDocs/$GH_REPO"

echo "==> Loading git-crypt key from setup runtime..."
GC_KEY="${GIT_CRYPT_KEY:-}"
if [ -z "$GC_KEY" ]; then
  echo "==> Runtime key missing — trying Bitwarden fallback..."
  bw_ensure_session || exit 1
  GC_KEY=$(bw_get_field "$BW_ITEM" "$BW_FIELD")
fi

if [ -z "$GC_KEY" ]; then
  echo "ERROR: git-crypt key missing. Repair with: bash ~/emacs-mac-setup/setup-intake.sh --repair config"
  exit 1
fi

echo "==> Unlocking git-crypt repo..."
echo "$GC_KEY" | tr -d '[:space:]' | python3 -c "import sys,base64; data=sys.stdin.read().strip(); sys.stdout.buffer.write(base64.b64decode(data + '=='))" > /tmp/gckey
if ! git -C "$ICLOUD_REPO_PATH" diff --quiet; then
  echo "    Restoring data/org/ to clean state (encrypted blobs — safe to discard)..."
  git -C "$ICLOUD_REPO_PATH" checkout -- data/org/ 2>/dev/null || true
fi
git -C "$ICLOUD_REPO_PATH" crypt unlock /tmp/gckey
rm -f /tmp/gckey

echo ""
echo "==> Result:"
head -c 30 "$ICLOUD_REPO_PATH/org/inbox.org" 2>/dev/null && echo "" || true
echo "Done! org/ files are now decrypted."
setup_runtime_cleanup_secret_keychain
