#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OMAWSL_ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../../install/lib.sh
source "$OMAWSL_ROOT_DIR/install/lib.sh"
# shellcheck source=../../install/terminal/app-herdr.sh
source "$OMAWSL_ROOT_DIR/install/terminal/app-herdr.sh"

# omawsl_notifications_set <both|sound|popup|off>
# Saves how Herdr tells you an agent finished or needs input. With a Herdr
# config, it's set up right away and only saved once that worked (a failed
# pulseaudio-utils install keeps the previous choice). Without one, it's
# just saved - omawsl_install_herdr_config applies it when Herdr is chosen.
omawsl_notifications_set() {
  local slug
  slug="$(omawsl_herdr_notifications_slug "$1")"
  if [[ -z "$slug" ]]; then
    echo "omawsl: unknown notifications choice '$1' - choose both, sound, popup or off." >&2
    return 1
  fi
  if [[ -f "$HOME/.config/herdr/config.toml" ]]; then
    omawsl_herdr_setup_notifications "$slug" || return 1
    omawsl_save_choice OMAWSL_HERDR_NOTIFICATIONS "$slug"
    echo "omawsl: Herdr notifications set to $slug."
  else
    omawsl_save_choice OMAWSL_HERDR_NOTIFICATIONS "$slug"
    echo "omawsl: Herdr notifications set to $slug - applied when you switch to Herdr (omawsl multiplexer herdr)."
  fi
}

# omawsl_notifications_command [both|sound|popup|off]
# Entry point for `bin/omawsl notifications`. With no argument, asks via
# gum; cancelling the picker changes nothing.
omawsl_notifications_command() {
  local input="${1:-}"
  if [[ -z "$input" ]]; then
    local current
    current="$(omawsl_load_choice OMAWSL_HERDR_NOTIFICATIONS)"
    input="$(gum choose --header "Herdr agent notifications (currently: ${current:-not set})" \
      "$OMAWSL_HERDR_NOTIFY_LABEL_BOTH" "$OMAWSL_HERDR_NOTIFY_LABEL_SOUND" \
      "$OMAWSL_HERDR_NOTIFY_LABEL_POPUP" "$OMAWSL_HERDR_NOTIFY_LABEL_OFF")" || input=""
    [[ -n "$input" ]] || return 0
  fi
  omawsl_notifications_set "$input"
}
