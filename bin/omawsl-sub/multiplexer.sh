#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OMAWSL_ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../../install/lib.sh
source "$OMAWSL_ROOT_DIR/install/lib.sh"
# shellcheck source=../../install/terminal/app-herdr.sh
source "$OMAWSL_ROOT_DIR/install/terminal/app-herdr.sh"

# omawsl_multiplexer_current
# The saved choice as a slug - zellij when nothing was ever chosen,
# matching configs/bashrc's own default.
omawsl_multiplexer_current() {
  omawsl_multiplexer_slug "$(omawsl_load_choice OMAWSL_MULTIPLEXER)"
}

# omawsl_multiplexer_set <slug>
# Makes <slug> what every new terminal opens. Herdr is installed (and its
# config deployed) first, and the choice is only saved once that worked -
# a blocked herdr.dev download on a corporate network leaves the previous
# choice in place instead of a choice bashrc would silently ignore.
# Nothing changes for the terminal this runs in.
omawsl_multiplexer_set() {
  local slug="$1"
  case "$slug" in
    zellij) ;;
    herdr)
      if ! command -v herdr &>/dev/null; then
        omawsl_herdr_install_steps || true
        hash -r
        if ! command -v herdr &>/dev/null; then
          echo "omawsl: Herdr install failed - staying on $(omawsl_multiplexer_current)." >&2
          return 1
        fi
      fi
      omawsl_install_herdr_config
      ;;
    *)
      echo "omawsl: unknown multiplexer '$slug' - choose zellij or herdr." >&2
      return 1
      ;;
  esac
  omawsl_save_choice OMAWSL_MULTIPLEXER "$slug"
  echo "omawsl: new terminals will open $slug - open a new terminal to switch."
}

# omawsl_multiplexer_command [slug]
# Entry point for `bin/omawsl multiplexer [zellij|herdr]`. With no
# argument, asks via gum; cancelling the picker changes nothing.
omawsl_multiplexer_command() {
  local input="${1:-}"
  if [[ -z "$input" ]]; then
    local choice
    choice="$(gum choose --header "Terminal multiplexer (currently: $(omawsl_multiplexer_current))" \
      "$OMAWSL_MULTIPLEXER_LABEL_ZELLIJ" "$OMAWSL_MULTIPLEXER_LABEL_HERDR")" || choice=""
    [[ -n "$choice" ]] || return 0
    input="$(omawsl_multiplexer_slug "$choice")"
  fi
  omawsl_multiplexer_set "$input"
}
