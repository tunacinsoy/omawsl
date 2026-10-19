#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OMAWSL_ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../themes/set-vscode-theme.sh
source "$OMAWSL_ROOT_DIR/themes/set-vscode-theme.sh"

# Issue #37: the Ristretto theme used to install Monokai Pro, a paid
# extension whose "Register now to continue using it" dialog pops up on
# every VS Code start. Ristretto now ships its own theme instead (see
# themes/ristretto/vscode.sh).
#
# Anyone still on Monokai Pro's Ristretto filter is moved onto the new
# theme first, so removing Monokai Pro below never drops them back to VS
# Code's default theme. Monokai Pro is then removed for everyone, whatever
# theme is active: it activates on every VS Code start (onStartupFinished),
# so leaving it installed keeps the dialog coming. Both steps silently
# no-op where VS Code or the Windows side isn't reachable.
if omawsl_theme_vscode_uses "Monokai Pro (Filter Ristretto)"; then
  # shellcheck source=../themes/ristretto/vscode.sh
  source "$OMAWSL_ROOT_DIR/themes/ristretto/vscode.sh"
fi

omawsl_vscode_uninstall_extension monokai.theme-monokai-pro-vscode
