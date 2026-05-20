#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EMACS_FLAVOR=yamamoto exec bash "$SCRIPT_DIR/setup-emacs-native-mac.sh" "$@"
