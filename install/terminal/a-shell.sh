#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OMAWSL_REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../lib.sh
source "$OMAWSL_REPO_ROOT/install/lib.sh"

# omawsl_install_shell_config
# Corp-safe config editing policy (design spec
# docs/superpowers/specs/2026-07-28-corp-safe-config-editing-design.md):
# omawsl owns configs/bashrc/configs/inputrc outright in the repo checkout
# (freely updated by `omawsl update`'s git pull, no copy step needed) and
# adds at most one guarded source line to ~/.bashrc - never overwrites it,
# never touches ~/.inputrc at all.
omawsl_install_shell_config() {
  omawsl_ensure_bashrc_source_line "$HOME/.bashrc" "$OMAWSL_REPO_ROOT/configs/bashrc"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_install_shell_config
fi
