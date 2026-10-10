#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
source "$SCRIPT_DIR/../lib.sh"

# Resolved once, at source time: bin/omawsl-sub/theme.sh and
# multiplexer.sh source this file too, and every omawsl script reassigns
# SCRIPT_DIR at its own top - by the time a function below runs, SCRIPT_DIR
# may point somewhere else entirely.
OMAWSL_HERDR_REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# omawsl_herdr_install_steps
# The actual install command, no guard - same split rationale as
# omawsl_claude_cli_install_steps. Herdr (herdrdev/herdr, issue #10) ships
# its own POSIX-sh installer, which verifies the binary's SHA-256 against
# herdr.dev's release manifest and places it at $HOME/.local/bin/herdr
# (already on PATH) - no npm/mise involved.
omawsl_herdr_install_steps() {
  curl -fsSL https://herdr.dev/install.sh | sh
}

# omawsl_herdr_theme_name <omawsl_theme_folder>
# Herdr's built-in theme for each omawsl theme. Rose Pine is the light
# Dawn variant everywhere else in omawsl (see themes/rose-pine/vscode.sh),
# so it maps to Herdr's rose-pine-dawn. Themes with no Herdr built-in use
# "terminal", which follows the outer terminal's palette - and omawsl
# theme already syncs Windows Terminal's color scheme.
omawsl_herdr_theme_name() {
  case "$1" in
    catppuccin|dracula|gruvbox|kanagawa|nord|one-dark|solarized|tokyo-night) echo "$1" ;;
    rose-pine) echo "rose-pine-dawn" ;;
    *) echo "terminal" ;;
  esac
}

# omawsl_herdr_apply_theme <omawsl_theme_folder>
# Rewrites only the [theme] `name = "..."` line of Herdr's config - the
# rest of the file is the user's (docs/config-safety.md) - and no-ops when
# there's no config or no such line (a user's own config that sets no
# theme stays that way). A running Herdr server picks the change up via
# reload-config; when none is running that fails harmlessly.
omawsl_herdr_apply_theme() {
  local config_file="$HOME/.config/herdr/config.toml"
  [[ -f "$config_file" ]] || return 0
  grep -qE '^name = "' "$config_file" || return 0
  local herdr_theme
  herdr_theme="$(omawsl_herdr_theme_name "$1")"
  sed -i -E "s/^name = \".*\"/name = \"$herdr_theme\"/" "$config_file"
  if command -v herdr &>/dev/null; then
    herdr server reload-config >/dev/null 2>&1 || true
  fi
}

# omawsl_toml_set <file> <table> <key> <value>
# Sets one `key = value` line inside `[table]`, leaving every other line of
# the file alone: replaces the key's line if the table has one, adds it at
# the end of the table if not, and appends the whole table at the end of
# the file if it isn't there at all. <value> is written verbatim, so
# strings need their own quotes. Only understands standard `[table]`
# headers, not dotted keys or inline tables - fine for the two Herdr
# settings omawsl owns.
omawsl_toml_set() {
  local file="$1" table="$2" key="$3" value="$4"
  local tmp
  tmp="$(mktemp)"
  awk -v header="[$table]" -v key="$key" -v line="$key = $value" '
    function emit() { print line; done = 1 }
    $0 == header { in_table = 1; seen = 1; print; next }
    in_table && /^[[:space:]]*\[/ { if (!done) emit(); in_table = 0 }
    in_table && $0 ~ "^[[:space:]]*" key "[[:space:]]*=" { if (!done) emit(); next }
    { print }
    END {
      if (in_table && !done) emit()
      if (!seen) { print ""; print header; emit() }
    }
  ' "$file" > "$tmp"
  cat "$tmp" > "$file"
  rm -f "$tmp"
}

# omawsl_herdr_apply_notifications
# Turns Herdr's own alerts off - `[ui.sound] enabled = false` and
# `[ui.toast] delivery = "off"`, the only two Herdr settings `omawsl
# notifications` touches - and reloads a running Herdr, same shape as
# omawsl_herdr_apply_theme. Herdr calls every Claude turn end "done", even
# while background work still runs, so the alerts come from
# bin/omawsl-claude-notify instead, whatever the choice. No-op without a
# Herdr config.
omawsl_herdr_apply_notifications() {
  local config_file="$HOME/.config/herdr/config.toml"
  [[ -f "$config_file" ]] || return 0
  omawsl_toml_set "$config_file" ui.sound enabled false
  omawsl_toml_set "$config_file" ui.toast delivery '"off"'
  if command -v herdr &>/dev/null; then
    herdr server reload-config >/dev/null 2>&1 || true
  fi
}

# omawsl_herdr_unlink_notify_send
# Removes ~/.local/bin/notify-send only when it's omawsl's own link -
# older omawsl linked it in for Herdr's popups; bin/omawsl-claude-notify
# now calls bin/omawsl-notify-send directly.
omawsl_herdr_unlink_notify_send() {
  local link="$HOME/.local/bin/notify-send"
  if [[ -L "$link" && "$(readlink "$link")" == "$OMAWSL_HERDR_REPO_ROOT/bin/omawsl-notify-send" ]]; then
    rm -f "$link"
  fi
}

# Marks omawsl's own entries in ~/.claude/settings.json.
OMAWSL_CLAUDE_HOOK_MARK="bin/omawsl-claude-notify"

# omawsl_claude_hooks_install
# Points Claude Code's Stop, Notification and PreToolUse(AskUserQuestion)
# hooks at bin/omawsl-claude-notify, which raises the alerts behind
# `omawsl notifications`. settings.json has no drop-in directory, so this
# is the smallest content-checked addition (docs/config-safety.md): one
# entry per event, added only if that event has none of ours yet, nothing
# else changed - except that entries pointing at another omawsl checkout
# (moved, or a dev worktree) are repointed at this one. No ~/.claude yet
# means Claude Code never ran, and no jq means no safe edit - both only
# say so, since Herdr's own alerts are off either way. Invalid JSON is
# never rewritten, only reported.
omawsl_claude_hooks_install() {
  local dir="$HOME/.claude"
  local file="$dir/settings.json"
  if [[ ! -d "$dir" ]]; then
    echo "omawsl: Claude Code hasn't run yet, so it can't notify you - start it once, then run: omawsl notifications" >&2
    return 0
  fi
  if ! command -v jq &>/dev/null; then
    echo "omawsl: jq is missing, so Claude Code can't be set up to notify you - install it (sudo apt-get install jq), then run: omawsl notifications" >&2
    return 0
  fi
  [[ -f "$file" ]] || echo '{}' > "$file"
  if ! jq -e 'type == "object"' "$file" >/dev/null 2>&1; then
    echo "omawsl: $file isn't valid JSON - leaving it alone, so Claude Code won't notify you. Fix it, then run: omawsl notifications" >&2
    return 0
  fi
  local tmp
  tmp="$(mktemp)"
  jq --arg cmd "\"$OMAWSL_HERDR_REPO_ROOT/bin/omawsl-claude-notify\"" --arg mark "$OMAWSL_CLAUDE_HOOK_MARK" '
    def add($event; $matcher; $arg):
      if any(.hooks[$event][]?.hooks[]?; (.command // "") | contains($mark)) then .
      else .hooks[$event] += [
        (if $matcher then {matcher: $matcher} else {} end)
        + {hooks: [{type: "command", command: ($cmd + " " + $arg), async: true, timeout: 10}]}
      ]
      end;
    def ours: (.command // "") | contains($mark);
    def current: (.command // "") | startswith($cmd + " ");
    .hooks //= {}
    | .hooks |= with_entries(
        if (.value | type) == "array" then
          .value |= map(
            if (.hooks | type) == "array" and any(.hooks[]; ours and (current | not))
            then (.hooks |= map(select(ours and (current | not) | not))) | select((.hooks | length) > 0)
            else . end)
        else . end)
    | add("Stop"; null; "stop")
    | add("Notification"; null; "notify")
    | add("PreToolUse"; "AskUserQuestion"; "ask")
  ' "$file" > "$tmp" && cat "$tmp" > "$file"
  rm -f "$tmp"
}

# omawsl_claude_hooks_remove
# Takes out exactly the entries omawsl_claude_hooks_install added, plus
# any matcher group or event left empty by that. A file without them (or
# that isn't valid JSON) is left byte-for-byte alone.
omawsl_claude_hooks_remove() {
  local file="$HOME/.claude/settings.json"
  [[ -f "$file" ]] || return 0
  grep -qF "$OMAWSL_CLAUDE_HOOK_MARK" "$file" || return 0
  command -v jq &>/dev/null || return 0
  jq -e 'type == "object"' "$file" >/dev/null 2>&1 || return 0
  local tmp
  tmp="$(mktemp)"
  jq --arg mark "$OMAWSL_CLAUDE_HOOK_MARK" '
    if (.hooks | type) != "object" then . else
      .hooks |= with_entries(
        .value |= (if type == "array" then
          map(if (.hooks | type) == "array"
              then .hooks |= map(select((.command // "") | contains($mark) | not))
              else . end)
          | map(select((.hooks | type) != "array" or (.hooks | length) > 0))
        else . end)
      )
      | .hooks |= with_entries(select(.value != []))
      | if .hooks == {} then del(.hooks) else . end
    end
  ' "$file" > "$tmp" && cat "$tmp" > "$file"
  rm -f "$tmp"
}

# omawsl_herdr_setup_notifications <both|sound|popup|off>
# Everything one notifications choice needs. Sound: paplay
# (pulseaudio-utils), which reaches Windows' speakers via WSLg's
# PulseAudio server. Any alert choice: the Claude Code hooks that raise
# them; off removes those. Herdr's own alerts are always switched off.
# Fails only when paplay can't be installed, so callers can keep the
# previous choice. Missing WSLg only warns - the choice still applies once
# it's there.
omawsl_herdr_setup_notifications() {
  local slug="$1"
  case "$slug" in
    both|sound)
      if ! command -v paplay &>/dev/null; then
        sudo apt-get install -y pulseaudio-utils || true
        hash -r
        if ! command -v paplay &>/dev/null; then
          echo "omawsl: couldn't install pulseaudio-utils (paplay) - Claude Code can't play sounds without it." >&2
          return 1
        fi
      fi
      [[ -n "${PULSE_SERVER:-}" ]] ||
        echo "omawsl: no WSLg audio here (PULSE_SERVER is unset) - sounds won't be heard until WSLg is available." >&2
      ;;
  esac
  omawsl_herdr_unlink_notify_send
  case "$slug" in
    off) omawsl_claude_hooks_remove ;;
    *) omawsl_claude_hooks_install ;;
  esac
  omawsl_herdr_apply_notifications
}

# omawsl_zellij_current_theme
# The omawsl theme currently applied, read back from zellij's config -
# `omawsl theme` rewrites its `theme "..."` line on every run, so it's the
# one place that always reflects the last theme picked. Empty when zellij
# has no config.
omawsl_zellij_current_theme() {
  sed -nE 's/^theme "(.*)"/\1/p' "$HOME/.config/zellij/config.kdl" 2>/dev/null | head -n1
}

# omawsl_install_herdr_config
# Deploys configs/herdr.toml (zellij.kdl's keymap, ported) to Herdr's
# real config location, with @OMAWSL_ROOT@ replaced by this checkout's
# path. Copy-if-absent like omawsl_install_zellij_config - a user's own
# Herdr config is never touched. A freshly deployed config then adopts
# whatever omawsl theme is already applied, so switching to Herdr months
# after picking a theme doesn't revert Herdr's chrome to tokyo-night. Same
# for a notifications choice saved before Herdr's config existed (the
# first-run question) - a setup failure there only warns, it never stops
# the install.
omawsl_install_herdr_config() {
  local config_file="$HOME/.config/herdr/config.toml"
  [[ -f "$config_file" ]] && return 0
  mkdir -p "$(dirname "$config_file")"
  sed "s#@OMAWSL_ROOT@#$OMAWSL_HERDR_REPO_ROOT#g" "$OMAWSL_HERDR_REPO_ROOT/configs/herdr.toml" > "$config_file"
  local theme
  theme="$(omawsl_zellij_current_theme)"
  if [[ -n "$theme" ]]; then
    omawsl_herdr_apply_theme "$theme"
  fi
  local notifications
  notifications="$(omawsl_load_choice OMAWSL_HERDR_NOTIFICATIONS)"
  if [[ -n "$notifications" ]]; then
    omawsl_herdr_setup_notifications "$notifications" ||
      echo "omawsl: Herdr notifications not fully set up - retry with: omawsl notifications $notifications" >&2
  fi
}

# omawsl_herdr_ensure_installed
# Succeeds once herdr is on PATH, downloading it first if needed. Judged
# by the binary actually being there afterwards, not by the installer's
# exit status - a corporate network blocking herdr.dev is the expected
# failure, and it must never take a whole install.sh run down with it.
omawsl_herdr_ensure_installed() {
  command -v herdr &>/dev/null && return 0
  omawsl_herdr_install_steps || true
  hash -r
  command -v herdr &>/dev/null
}

# omawsl_install_herdr
# Only when Herdr is the chosen multiplexer (OMAWSL_MULTIPLEXER, set by
# install/first-run-choices.sh or `omawsl multiplexer herdr`). Idempotent:
# the download is skipped when herdr is already on PATH, the config deploy
# is copy-if-absent. If Herdr can't be installed, the choice goes back to
# zellij (with a warning) rather than staying on a Herdr that bashrc would
# silently skip.
omawsl_install_herdr() {
  [[ "${OMAWSL_MULTIPLEXER:-}" == herdr ]] || return 0
  if ! omawsl_herdr_ensure_installed; then
    echo "omawsl: Herdr couldn't be installed - new terminals will open zellij. Try again later with: omawsl multiplexer herdr" >&2
    export OMAWSL_MULTIPLEXER=zellij
    omawsl_save_choice OMAWSL_MULTIPLEXER zellij
    return 0
  fi
  omawsl_install_herdr_config
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_install_herdr
fi
