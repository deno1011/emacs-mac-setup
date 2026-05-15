#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$HOME/emacs-mac-setup/setup-emacs-mac.conf"
source "$CONFIG_FILE"

ICLOUD_REPO_PATH="$HOME/Library/Mobile Documents/com~apple~CloudDocs/$GH_REPO"

echo "==> Unlocking Bitwarden..."
source "$SCRIPT_DIR/bw-unlock.sh"
bw_ensure_session || exit 1

echo "==> Fetching git-crypt key from Bitwarden (field: $BW_FIELD)..."
GC_KEY=$(bw_get_field "$BW_ITEM" "$BW_FIELD")

if [ -z "$GC_KEY" ]; then
  echo "ERROR: git-crypt key not found in Bitwarden (Item: $BW_ITEM, Field: $BW_FIELD)"
  exit 1
fi

echo "==> Unlocking git-crypt repo..."
echo "$GC_KEY" | tr -d '[:space:]' | python3 -c "import sys,base64; data=sys.stdin.read().strip(); sys.stdout.buffer.write(base64.b64decode(data + '=='))" > /tmp/gckey
_STASHED=false
if ! git -C "$ICLOUD_REPO_PATH" diff --quiet || ! git -C "$ICLOUD_REPO_PATH" diff --cached --quiet; then
  echo "    Stashing uncommitted changes..."
  git -C "$ICLOUD_REPO_PATH" stash push -m "unlock-git-crypt auto-stash" && _STASHED=true
fi
git -C "$ICLOUD_REPO_PATH" crypt unlock /tmp/gckey
rm -f /tmp/gckey
[ "$_STASHED" = true ] && git -C "$ICLOUD_REPO_PATH" stash pop

echo ""
echo "==> Result:"
head -c 30 "$ICLOUD_REPO_PATH/org/inbox.org" 2>/dev/null && echo "" || true
echo "Done! org/ files are now decrypted."
