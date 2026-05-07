#!/bin/bash
# Bootstrap: Downloads all Emacs setup scripts from GitHub.
# Usage: bash bootstrap.sh [user/private-conf-repo]
# Example: bash bootstrap.sh janedoe/mac-setup-conf
# (user/repo required here since GH_USER is not yet known at bootstrap time)

set -e

BASE_URL="https://raw.githubusercontent.com/deno1011/emacs-mac-setup/main"
CONF_REPO="${1:-}"
DEST="$(pwd)"
CONFIG_FILE="$HOME/setup-emacs-mac.conf"

SCRIPTS=(
  setup-emacs-native-plus-mac.sh
  setup-emacs-native-yamamoto-mac.sh
  setup-emacs-docker-mac.sh
  uninstall-emacs-native-plus-mac.sh
  uninstall-emacs-native-yamamoto-mac.sh
  uninstall-emacs-docker-mac.sh
  unlock-git-crypt.sh
  remove-bitwarden-keychain.sh
  fill-config.sh
  setup-bitwarden.sh
  setup-secrets.sh
  setup-emacs-mac.conf.template
  config.org
  init.el
)

echo "==> Downloading scripts to $DEST/..."
for SCRIPT in "${SCRIPTS[@]}"; do
  echo "    $SCRIPT"
  curl -fsSL "${BASE_URL}/${SCRIPT}" -o "$DEST/${SCRIPT}"
done

chmod +x \
  "$DEST/setup-emacs-native-plus-mac.sh" \
  "$DEST/setup-emacs-native-yamamoto-mac.sh" \
  "$DEST/setup-emacs-docker-mac.sh" \
  "$DEST/uninstall-emacs-native-plus-mac.sh" \
  "$DEST/uninstall-emacs-native-yamamoto-mac.sh" \
  "$DEST/uninstall-emacs-docker-mac.sh" \
  "$DEST/unlock-git-crypt.sh" \
  "$DEST/remove-bitwarden-keychain.sh" \
  "$DEST/fill-config.sh" \
  "$DEST/setup-bitwarden.sh" \
  "$DEST/setup-secrets.sh"

# --- Pull personal config from private repo ---
CONF_PULLED=false
if [ -n "$CONF_REPO" ]; then
  echo ""
  echo "==> Trying to pull personal config from github.com/${CONF_REPO}..."
  CONF_TMP=$(mktemp -d)

  if command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1; then
    if gh repo clone "$CONF_REPO" "$CONF_TMP/conf" &>/dev/null 2>&1; then
      CONF_PULLED=true
    fi
  fi
  if [ "$CONF_PULLED" = false ]; then
    if git clone "https://github.com/${CONF_REPO}.git" "$CONF_TMP/conf" &>/dev/null 2>&1; then
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

# --- Always ensure config exists (copy template if not pulled) ---
if [ "$CONF_PULLED" = false ]; then
  cp "$DEST/setup-emacs-mac.conf.template" "$CONFIG_FILE"
  echo "==> setup-emacs-mac.conf created from template."
fi

echo ""
echo "======================================================================"
echo "Bootstrap complete!"
echo "======================================================================"
echo ""

if [ "$CONF_PULLED" = true ]; then
  echo "  Personal config pulled and ready."
  echo ""
  printf "  Fill in config now to verify or update values? [y/N] "
  read -r FILL
  if [ "$FILL" = "y" ] || [ "$FILL" = "Y" ]; then
    bash "$DEST/fill-config.sh"
  fi
else
  echo "  Config created from template — fill in your details."
  echo ""
  printf "  Fill in config now interactively? [Y/n] "
  read -r FILL
  if [ "$FILL" != "n" ] && [ "$FILL" != "N" ]; then
    bash "$DEST/fill-config.sh"
  else
    echo ""
    echo "  Fill in manually later:  open ~/setup-emacs-mac.conf"
    echo "  Or run interactively:    bash $DEST/fill-config.sh"
  fi
fi

# --- Bitwarden setup ---
source "$CONFIG_FILE"
echo ""
if [ -n "$GH_USER" ]; then
  printf "  Set up Bitwarden entries now? [Y/n] "
  read -r BW_ANS
  if [ "$BW_ANS" != "n" ] && [ "$BW_ANS" != "N" ]; then
    bash "$DEST/setup-bitwarden.sh"
  else
    echo "  Run $DEST/setup-bitwarden.sh any time to create the required vault entries."
  fi
else
  echo "  GH_USER not set — local mode, Bitwarden not required."
  echo "  Run $DEST/setup-bitwarden.sh after setting GH_USER if you want GitHub sync."
fi

echo ""
echo "  Run a setup script when ready:"
echo "    bash $DEST/setup-emacs-native-plus-mac.sh      # recommended (LSP, native comp)"
echo "    bash $DEST/setup-emacs-native-yamamoto-mac.sh  # smooth rendering, trackpad"
echo "    bash $DEST/setup-emacs-docker-mac.sh           # isolated in Docker"
echo ""
echo "  Docs: https://github.com/deno1011/emacs-mac-setup/blob/main/README.md"
echo ""
