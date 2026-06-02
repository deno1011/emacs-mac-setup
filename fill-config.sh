#!/bin/bash
# Compatibility wrapper. The setup intake wizard now owns all interactive
# discovery, config repair, Bitwarden/Keychain setup, and secret prompts.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/setup-intake.sh" "$@"
