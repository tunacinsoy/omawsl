#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
source "$SCRIPT_DIR/../lib.sh"

# omawsl_herdr_install_steps
# The actual install command, no guard - same split rationale as
# omawsl_claude_cli_install_steps/omawsl_antigravity_cli_install_steps.
# Herdr (herdrdev/herdr) is a terminal multiplexer for AI coding agents -
# ships its own native curl installer (confirmed via herdr.dev/install.sh),
# which places the binary at $HOME/.local/bin/herdr (already on PATH,
# same as Claude Code CLI's own installer) - no npm/mise involved.
omawsl_herdr_install_steps() {
  curl -fsSL https://herdr.dev/install.sh | bash
}

# omawsl_install_herdr
# Herdr - purely WSL-side, no Windows dependency, same shape as
# app-claude-cli.sh. Idempotent via a command -v guard on `herdr`, the
# binary the installer places on PATH.
omawsl_install_herdr() {
  if ! omawsl_list_has "${OMAWSL_EDITORS:-}" "Herdr"; then
    return 0
  fi

  if command -v herdr &>/dev/null; then
    return 0
  fi

  omawsl_herdr_install_steps
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_install_herdr
fi
