#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OMAWSL_ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../install/lib.sh
source "$OMAWSL_ROOT_DIR/install/lib.sh"
# shellcheck source=../install/terminal/app-vscode.sh
source "$OMAWSL_ROOT_DIR/install/terminal/app-vscode.sh"

# Fixes the real bug this migration's own commit message documents (issue
# #32, #9): VS Code's own default auto-updater (update.mode: "default")
# silently checks for, downloads, and stages a new build on nearly every
# launch of the Electron helper process the WSL `code` CLI wrapper spawns
# internally - confirmed live, a single `--locate-extension` call (the
# wrapper's own first step on every invocation) completed a full
# checking/downloading/downloaded/ready cycle in under 90 seconds. Since
# Remote-WSL's server install is pinned to the exact commit of the
# currently-running Windows-side build, every user who selected VS Code
# before this fix has update.mode left at its default and is getting hit
# by the WSL-side "Updating VS Code Server" reinstall on nearly every
# `code .`, independent of whether they select VS Code again.
# omawsl_vscode_disable_auto_update is already idempotent and
# content-checked (a no-op if update.mode is already set, whatever its
# value), so this is safe to run unconditionally - it silently no-ops if
# VS Code was never installed on Windows or the profile can't be resolved.
omawsl_vscode_disable_auto_update
