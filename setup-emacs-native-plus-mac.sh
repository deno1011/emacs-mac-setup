#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EMACS_FLAVOR=plus exec bash "$SCRIPT_DIR/setup-emacs-native-mac.sh" "$@"
