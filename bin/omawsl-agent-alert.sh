#!/usr/bin/env bash
# Shared by the agent hooks behind `omawsl notifications`
# (bin/omawsl-claude-notify, bin/omawsl-copilot-notify): the checks that
# decide whether to alert at all, naming the agent the way Herdr's sidebar
# does, and the Windows popup and/or sound. Sourced, never run - callers
# set ROOT to the omawsl checkout first. Each agent's own script only
# decides whether its hook event means "done" or "needs you".

# omawsl_agent_alert_start
# Reads the hook JSON on stdin into $input, then exits the calling hook
# (status 0) unless an alert can happen: inside Herdr, jq present, input a
# JSON object, and a saved choice of both/sound/popup (kept in $choice).
omawsl_agent_alert_start() {
  input="$(cat)"
  [[ "${HERDR_ENV:-}" == 1 ]] || exit 0
  command -v jq &>/dev/null || exit 0
  jq -e 'type == "object"' <<< "$input" >/dev/null 2>&1 || exit 0
  # shellcheck source=../install/lib.sh
  source "$ROOT/install/lib.sh"
  choice="$(omawsl_load_choice OMAWSL_HERDR_NOTIFICATIONS)"
  case "$choice" in
    both|sound|popup) ;;
    *) exit 0 ;;
  esac
}

# field <jq path> - one string from the hook JSON, empty when missing.
field() {
  jq -r "$1 // empty" <<< "$input" 2>/dev/null
}

# herdr_name - the agent's name as Herdr's sidebar shows it: the pane's
# note (Ctrl g p c), else its title. Empty outside a Herdr pane.
herdr_name() {
  [[ -n "$pane" ]] || return 0
  jq -r '[.label, .terminal_title_stripped] | map(select(. != null and . != "")) | first // empty' <<< "$pane" 2>/dev/null
}

# herdr_workspace - the name of the Herdr workspace the agent runs in.
# Empty outside a Herdr pane.
herdr_workspace() {
  local id
  id="$(jq -r '.workspace_id // empty' <<< "$pane" 2>/dev/null)"
  [[ -n "$id" ]] || return 0
  herdr workspace get "$id" 2>/dev/null | jq -r '.result.workspace.label // empty' 2>/dev/null
}

# omawsl_agent_alert <done|request> <fallback_name> <body>
# Names the agent the way Herdr's sidebar does, so you know which one to go
# to - <fallback_name> when Herdr has no name for it. A done alert's body
# is the workspace (else the cwd's folder); a request's is <body>.
omawsl_agent_alert() {
  local kind="$1" fallback="$2" body="$3" pane="" title sound_file
  if [[ -n "${HERDR_PANE_ID:-}" ]]; then
    pane="$(herdr pane get "$HERDR_PANE_ID" 2>/dev/null | jq -c '.result.pane // empty' 2>/dev/null)"
  fi
  title="$(herdr_name)"
  title="${title:-$fallback}"
  if [[ "$kind" == done ]]; then
    body="$(herdr_workspace)"
    if [[ -z "$body" ]]; then
      body="$(field .cwd)"
      body="${body%/}"
      body="${body##*/}"
      body="${body:-Finished}"
    fi
    title+=" — done"
    sound_file="Windows Notify System Generic.wav"
  else
    title+=" — needs you"
    sound_file="Windows Proximity Notification.wav"
  fi
  body="${body:0:200}"

  if [[ "$choice" != sound ]]; then
    "${OMAWSL_NOTIFY_SEND:-$ROOT/bin/omawsl-notify-send}" -- "$title" "$body" >/dev/null 2>&1 || true
  fi
  if [[ "$choice" != popup ]]; then
    paplay "${OMAWSL_NOTIFY_SOUND_DIR:-/mnt/c/Windows/Media}/$sound_file" >/dev/null 2>&1 || true
  fi
}
