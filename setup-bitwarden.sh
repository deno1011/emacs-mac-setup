#!/bin/bash
# Compatibility wrapper. Bitwarden setup is now part of the up-front intake
# flow so bootstrap does not ask for secrets in scattered later steps.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/setup-intake.sh" --repair bitwarden
