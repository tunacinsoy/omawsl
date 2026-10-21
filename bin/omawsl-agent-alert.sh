#!/usr/bin/env bash
# Shared by the agent hooks behind `omawsl notifications`
# (bin/omawsl-claude-notify, bin/omawsl-copilot-notify): the checks that
# decide whether to alert at all, and the sound. Sourced, never run -
# callers set ROOT to the omawsl checkout first. Each agent's own script
# only decides whether its hook event means "done" or "needs you".
#
# Sound only, played inside Linux: paplay through WSLg's PulseAudio server,
# with Ubuntu's own sound theme (sound-theme-freedesktop). omawsl never
# starts Windows programs, so there's no Windows popup.

# omawsl_agent_alert_start
# Reads the hook JSON on stdin into $input, then exits the calling hook
# (status 0) unless an alert can happen: inside Herdr, jq present, input a
# JSON object, and a saved choice of sound.
omawsl_agent_alert_start() {
  input="$(cat)"
  [[ "${HERDR_ENV:-}" == 1 ]] || exit 0
  command -v jq &>/dev/null || exit 0
  jq -e 'type == "object"' <<< "$input" >/dev/null 2>&1 || exit 0
  # shellcheck source=../install/lib.sh
  source "$ROOT/install/lib.sh"
  [[ "$(omawsl_load_choice OMAWSL_HERDR_NOTIFICATIONS)" == sound ]] || exit 0
}

# field <jq path> - one string from the hook JSON, empty when missing.
field() {
  jq -r "$1 // empty" <<< "$input" 2>/dev/null
}

# omawsl_agent_alert <done|request>
# Plays the done or the needs-you sound.
omawsl_agent_alert() {
  local sound_file=message-new-instant.oga
  [[ "$1" != done ]] || sound_file=complete.oga
  paplay "${OMAWSL_NOTIFY_SOUND_DIR:-/usr/share/sounds/freedesktop/stereo}/$sound_file" >/dev/null 2>&1 || true
}
