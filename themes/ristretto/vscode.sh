#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../set-vscode-theme.sh
source "$SCRIPT_DIR/../set-vscode-theme.sh"

omawsl_theme_apply_vscode "Monokai Pro (Filter Ristretto)" "monokai.theme-monokai-pro-vscode"
