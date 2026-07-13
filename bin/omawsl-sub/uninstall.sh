#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OMAWSL_ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../../install/lib.sh
source "$OMAWSL_ROOT_DIR/install/lib.sh"
# shellcheck source=items.sh
source "$SCRIPT_DIR/items.sh"

# omawsl_uninstall_dispatch <slug>
# Sources the matching uninstall/*.sh and calls its function with the
# right argument shape - languages/storage take the picker label (Tasks
# 1, 2), everything else takes no argument.
omawsl_uninstall_dispatch() {
  local slug="$1"
  local label
  case "$slug" in
    ruby|node|go|php|python|elixir|rust|java|terraform|azure)
      label="$(omawsl_item_label "$slug")"
      # shellcheck source=/dev/null
      source "$OMAWSL_ROOT_DIR/uninstall/dev-language.sh"
      omawsl_uninstall_language "$label"
      ;;
    mysql|redis|postgresql)
      label="$(omawsl_item_label "$slug")"
      # shellcheck source=/dev/null
      source "$OMAWSL_ROOT_DIR/uninstall/storage.sh"
      omawsl_uninstall_storage "$label"
      ;;
    docker)
      # shellcheck source=/dev/null
      source "$OMAWSL_ROOT_DIR/uninstall/docker.sh"
      omawsl_uninstall_docker
      ;;
    vscode)
      # shellcheck source=/dev/null
      source "$OMAWSL_ROOT_DIR/uninstall/app-vscode.sh"
      omawsl_uninstall_vscode
      ;;
    cursor)
      # shellcheck source=/dev/null
      source "$OMAWSL_ROOT_DIR/uninstall/app-cursor.sh"
      omawsl_uninstall_cursor
      ;;
    neovim)
      # shellcheck source=/dev/null
      source "$OMAWSL_ROOT_DIR/uninstall/app-neovim.sh"
      omawsl_uninstall_neovim
      ;;
    opencode)
      # shellcheck source=/dev/null
      source "$OMAWSL_ROOT_DIR/uninstall/app-opencode.sh"
      omawsl_uninstall_opencode
      ;;
    claude)
      # shellcheck source=/dev/null
      source "$OMAWSL_ROOT_DIR/uninstall/app-claude-cli.sh"
      omawsl_uninstall_claude_cli
      ;;
    codex)
      # shellcheck source=/dev/null
      source "$OMAWSL_ROOT_DIR/uninstall/app-codex-cli.sh"
      omawsl_uninstall_codex_cli
      ;;
    gemini)
      # shellcheck source=/dev/null
      source "$OMAWSL_ROOT_DIR/uninstall/app-gemini-cli.sh"
      omawsl_uninstall_gemini_cli
      ;;
    gh-copilot)
      # shellcheck source=/dev/null
      source "$OMAWSL_ROOT_DIR/uninstall/app-gh-copilot.sh"
      omawsl_uninstall_gh_copilot
      ;;
    *)
      echo "omawsl: unknown item '$slug'" >&2
      echo "Run 'omawsl install' with no arguments to see the available categories." >&2
      return 1
      ;;
  esac
}

# omawsl_uninstall_command [slug]
# Entry point for `bin/omawsl uninstall <name>` (design spec §14).
omawsl_uninstall_command() {
  local slug="${1:-}"
  if [[ -z "$slug" ]]; then
    echo "Usage: omawsl uninstall <name>" >&2
    return 1
  fi
  omawsl_uninstall_dispatch "$slug"
}
