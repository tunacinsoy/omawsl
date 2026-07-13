#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../install/lib.sh
source "$SCRIPT_DIR/../install/lib.sh"

# omawsl_uninstall_claude_cli
# Inverse of install/terminal/app-claude-cli.sh. Claude Code's own
# installer has no built-in uninstall subcommand (confirmed via
# `claude --help` on the real test WSL2 instance); it places a symlink at
# ~/.local/bin/claude pointing into ~/.local/share/claude/versions/... -
# removing both is a complete uninstall.
omawsl_uninstall_claude_cli() {
  rm -rf "$HOME/.local/share/claude" "$HOME/.local/bin/claude"
  echo "omawsl: Claude Code CLI removed."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_uninstall_claude_cli
fi
