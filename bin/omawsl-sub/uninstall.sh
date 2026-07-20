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
    ruby|node|go|php|python|elixir|rust|java|terraform)
      label="$(omawsl_item_label "$slug")"
      # shellcheck source=/dev/null
      source "$OMAWSL_ROOT_DIR/uninstall/dev-language.sh"
      omawsl_uninstall_language "$label"
      ;;
    azure|aws|gcp)
      label="$(omawsl_item_label "$slug")"
      # shellcheck source=/dev/null
      source "$OMAWSL_ROOT_DIR/uninstall/cloud-clis.sh"
      omawsl_uninstall_cloud_cli "$label"
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
    antigravity)
      # shellcheck source=/dev/null
      source "$OMAWSL_ROOT_DIR/uninstall/app-antigravity-cli.sh"
      omawsl_uninstall_antigravity_cli
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

# omawsl_uninstall_deselect <slug>
# After a successful uninstall, also removes the item from its
# choices.env list (OMAWSL_LANGUAGES/EDITORS/STORAGE), so `doctor` and
# the interactive `install` picker stop treating a deliberately-removed
# item as still selected. `docker` has no list of its own to edit -
# OMAWSL_DOCKER_MODE is a single mode choice, not a multi-select - so
# this no-ops for that slug.
omawsl_uninstall_deselect() {
  local slug="$1"
  local category
  category="$(omawsl_item_category "$slug")" || return 0

  local key
  case "$category" in
    language) key=OMAWSL_LANGUAGES ;;
    cloud)    key=OMAWSL_CLOUD_CLIS ;;
    editor)   key=OMAWSL_EDITORS ;;
    storage)  key=OMAWSL_STORAGE ;;
    *) return 0 ;;
  esac

  local label
  label="$(omawsl_item_label "$slug")"
  local existing
  existing="$(omawsl_load_choice "$key")"
  omawsl_save_choice "$key" "$(omawsl_remove_from_csv "$existing" "$label")"
}

# omawsl_uninstall_command [slug]
# Entry point for `bin/omawsl uninstall <name>` (design spec §14).
# Deselecting only runs after a successful dispatch - under set -e, a
# failed/unknown-item dispatch aborts this function before
# omawsl_uninstall_deselect is ever reached, so choices.env is left
# untouched when uninstall didn't actually resolve to anything real.
omawsl_uninstall_command() {
  local slug="${1:-}"
  if [[ -z "$slug" ]]; then
    echo "Usage: omawsl uninstall <name>" >&2
    return 1
  fi
  omawsl_uninstall_dispatch "$slug"
  omawsl_uninstall_deselect "$slug"
}
