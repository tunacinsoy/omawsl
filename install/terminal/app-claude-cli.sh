#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
source "$SCRIPT_DIR/../lib.sh"

# omawsl_install_claude_cli
# Claude Code CLI - purely WSL-side, no Windows dependency (design spec
# §10). Installs via its official native-binary installer (Anthropic's
# own recommended method, avoiding an npm/Node dependency entirely).
# Idempotent via a command -v guard.
omawsl_install_claude_cli() {
  if ! omawsl_list_has "${OMAWSL_EDITORS:-}" "Claude Code CLI"; then
    return 0
  fi

  if command -v claude &>/dev/null; then
    return 0
  fi

  curl -fsSL https://claude.ai/install.sh | bash
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_install_claude_cli
fi
