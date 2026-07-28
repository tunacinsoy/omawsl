#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OMAWSL_ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../install/lib.sh
source "$OMAWSL_ROOT_DIR/install/lib.sh"

# Corp-safe config editing migration (design spec
# docs/superpowers/specs/2026-07-28-corp-safe-config-editing-design.md):
# every prior install/update `cp`-overwrote ~/.bashrc and ~/.inputrc
# wholesale, so a file starting with omawsl's own banner comment is
# entirely omawsl-authored content - safe to replace with the new
# marker-guarded source line/INPUTRC fallback. A file that doesn't start
# with that banner was never omawsl's; left untouched except for the same
# guarded append a fresh install would do.
omawsl_migrate_bashrc_to_source_line() {
  local bashrc="$HOME/.bashrc"
  if [[ -f "$bashrc" ]] && head -n1 "$bashrc" | grep -qF '# omawsl bashrc - baseline dev environment configuration for WSL2 Ubuntu.'; then
    rm -f "$bashrc"
  fi
  omawsl_ensure_bashrc_source_line "$bashrc" "$OMAWSL_ROOT_DIR/configs/bashrc"
}

omawsl_migrate_inputrc_removal() {
  local inputrc="$HOME/.inputrc"
  if [[ -f "$inputrc" ]] && head -n1 "$inputrc" | grep -qF '# omawsl inputrc - readline configuration for more usable bash history search.'; then
    rm -f "$inputrc"
  fi
}

omawsl_migrate_bashrc_to_source_line
omawsl_migrate_inputrc_removal
