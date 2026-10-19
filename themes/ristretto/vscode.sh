#!/usr/bin/env bash
set -euo pipefail

# Captured before sourcing set-vscode-theme.sh, which resets SCRIPT_DIR to
# its own directory.
RISTRETTO_THEME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../set-vscode-theme.sh
source "$RISTRETTO_THEME_DIR/../set-vscode-theme.sh"

# Monokai Pro (Omakub's original choice here) is a paid extension that
# shows a "Register now" dialog on every VS Code start (issue #37), so
# Ristretto ships its own theme instead - generated from Omarchy's VS Code
# theme template with this folder's palette - and installs it as a local
# .vsix. If the .vsix can't be built, the theme setting is still written
# so a later `omawsl theme ristretto` only has to finish the install.
RISTRETTO_VSIX_DIR="$(mktemp -d)"
RISTRETTO_VSIX="$RISTRETTO_VSIX_DIR/omawsl-ristretto-theme.vsix"
if ! omawsl_theme_build_vsix "$RISTRETTO_THEME_DIR/vscode-extension" "$RISTRETTO_VSIX"; then
  echo "omawsl: couldn't package the Ristretto VS Code theme - skipping its install." >&2
  RISTRETTO_VSIX=""
fi
omawsl_theme_apply_vscode "Ristretto (omawsl)" "$RISTRETTO_VSIX"
rm -rf "$RISTRETTO_VSIX_DIR"
