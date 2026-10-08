#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OMAWSL_ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../bin/omawsl-sub/notifications.sh
source "$OMAWSL_ROOT_DIR/bin/omawsl-sub/notifications.sh"

# Herdr agent notifications: fresh installs get the first-run question, but
# anyone already on Herdr would never hear about `omawsl notifications` -
# and Herdr's defaults stay silent on WSL. So their next `omawsl update`
# asks the same question once, through the command itself (sudo prompts
# there for pulseaudio-utils if they pick sound). Skipped for zellij users
# (`omawsl multiplexer herdr` points them at the command) and for anyone
# who already chose. Cancelling, or a failed setup, only prints how to do
# it later - never a failed migration, which would block every later one
# and ask again on each update.
omawsl_migrate_herdr_notifications() {
  [[ "$(omawsl_load_choice OMAWSL_MULTIPLEXER)" == herdr ]] || return 0
  [[ -f "$HOME/.config/herdr/config.toml" ]] || return 0
  [[ -z "$(omawsl_load_choice OMAWSL_HERDR_NOTIFICATIONS)" ]] || return 0
  echo "omawsl: Herdr can now tell you when an agent finishes or needs input."
  omawsl_notifications_command ||
    echo "omawsl: Herdr notifications not set up - retry with: omawsl notifications" >&2
  [[ -n "$(omawsl_load_choice OMAWSL_HERDR_NOTIFICATIONS)" ]] ||
    echo "omawsl: choose any time with: omawsl notifications"
}

omawsl_migrate_herdr_notifications
