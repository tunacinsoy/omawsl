#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OMAWSL_ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../../install/lib.sh
source "$OMAWSL_ROOT_DIR/install/lib.sh"
# shellcheck source=items.sh
source "$SCRIPT_DIR/items.sh"

# omawsl_doctor_language_installed <slug>
# Terraform/Azure CLI aren't mise-managed (design spec §12), so they're
# checked via command -v; the 8 mise-managed tools are checked against
# `mise ls --current`'s own tool-name column - this is what mise use
# --global actually configures (verified live: `mise ls --current` lists
# exactly go/python/ruby on the real test WSL2 instance after those three
# were selected).
omawsl_doctor_language_installed() {
  local slug="$1"
  case "$slug" in
    terraform) command -v terraform &>/dev/null ;;
    azure) command -v az &>/dev/null ;;
    *)
      local mise_tool
      case "$slug" in
        ruby) mise_tool=ruby ;; node) mise_tool=node ;; go) mise_tool=go ;;
        php) mise_tool=php ;; python) mise_tool=python ;; elixir) mise_tool=elixir ;;
        rust) mise_tool=rust ;; java) mise_tool=java ;;
      esac
      command -v mise &>/dev/null && mise ls --current 2>/dev/null | awk '{print $1}' | grep -qx "$mise_tool"
      ;;
  esac
}

# omawsl_doctor_editor_installed <slug>
omawsl_doctor_editor_installed() {
  local slug="$1"
  case "$slug" in
    vscode) omawsl_code_reachable ;;
    cursor) omawsl_cursor_reachable ;;
    neovim) [[ -d "$HOME/.config/nvim" ]] ;;
    opencode) command -v opencode &>/dev/null ;;
    claude) command -v claude &>/dev/null ;;
    codex) command -v codex &>/dev/null ;;
    gemini) command -v gemini &>/dev/null ;;
    gh-copilot) gh extension list 2>/dev/null | grep -q '^gh-copilot\|^gh copilot' ;;
  esac
}

# omawsl_doctor_storage_installed <slug>
omawsl_doctor_storage_installed() {
  local slug="$1" container
  case "$slug" in
    mysql) container=omawsl-mysql ;;
    redis) container=omawsl-redis ;;
    postgresql) container=omawsl-postgresql ;;
  esac
  omawsl_docker_reachable && sudo docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$container"
}

# omawsl_doctor_report_category <category> <check_fn> <choices_key>
# Cross-checks every selected item in one category against its check
# function, printing [OK]/[PENDING] with the exact `omawsl install`
# command to resolve a gap (design spec §14).
omawsl_doctor_report_category() {
  local category="$1" check_fn="$2" choices_key="$3"
  local selected; selected="$(omawsl_load_choice "$choices_key")"

  if [[ -z "$selected" ]]; then
    echo "  (none selected)"
    return 0
  fi

  local slug label
  while IFS= read -r slug; do
    label="$(omawsl_item_label "$slug")"
    omawsl_list_has "$selected" "$label" || continue
    if "$check_fn" "$slug"; then
      echo "  [OK]      $label"
    else
      echo "  [PENDING] $label - run: omawsl install $category $slug"
    fi
  done < <(omawsl_item_slugs "$category")
}

# omawsl_doctor
# Entry point for `bin/omawsl doctor` (design spec §14).
omawsl_doctor() {
  echo "omawsl doctor - checking what's installed/configured:"
  echo
  echo "Languages & cloud tools:"
  omawsl_doctor_report_category language omawsl_doctor_language_installed OMAWSL_LANGUAGES
  echo
  echo "Editors & AI tooling:"
  omawsl_doctor_report_category editor omawsl_doctor_editor_installed OMAWSL_EDITORS
  echo
  echo "Storage:"
  omawsl_doctor_report_category storage omawsl_doctor_storage_installed OMAWSL_STORAGE

  if [[ "$(omawsl_load_choice OMAWSL_DOCKER_MODE)" == "Docker Desktop for Windows" ]] && ! omawsl_docker_reachable; then
    echo
    echo "Docker:"
    echo "  [PENDING] Docker Desktop for Windows - see docs/windows-setup.md#docker-desktop"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_doctor
fi
