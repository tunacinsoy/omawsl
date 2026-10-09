#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/install/terminal/app-herdr.sh"
  stub_command curl
  stub_command sh
}

@test "no-ops entirely when zellij is the chosen multiplexer" {
  export OMAWSL_MULTIPLEXER=zellij
  run omawsl_install_herdr
  [ "$status" -eq 0 ]
  [ -z "$(stub_calls)" ]
  [ ! -f "$HOME/.config/herdr/config.toml" ]
}

@test "installs via the official installer when herdr is chosen and missing" {
  export OMAWSL_MULTIPLEXER=herdr
  stub_hide_command herdr
  # The piped-to `sh` stands in for herdr.dev's installer: it puts a herdr
  # on PATH, like the real one does.
  sh() {
    echo "sh $*" >> "$STUB_LOG"
    mkdir -p "$HOME/.local/bin"
    printf '#!/usr/bin/env bash\n' > "$HOME/.local/bin/herdr"
    chmod +x "$HOME/.local/bin/herdr"
  }
  export -f sh
  export PATH="$HOME/.local/bin:$PATH"
  run omawsl_install_herdr
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"curl -fsSL https://herdr.dev/install.sh"* ]]
  [ -f "$HOME/.config/herdr/config.toml" ]
}

@test "skips the download when herdr is already installed, but still deploys the config" {
  export OMAWSL_MULTIPLEXER=herdr
  stub_command herdr
  run omawsl_install_herdr
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"curl"* ]]
  [ -f "$HOME/.config/herdr/config.toml" ]
}

@test "omawsl_herdr_install_steps runs unconditionally" {
  stub_command herdr
  run omawsl_herdr_install_steps
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"herdr.dev/install.sh"* ]]
}

@test "config deploy substitutes the real repo root for @OMAWSL_ROOT@" {
  run omawsl_install_herdr_config
  [ "$status" -eq 0 ]
  local f="$HOME/.config/herdr/config.toml"
  ! grep -q '@OMAWSL_ROOT@' "$f"
  grep -qF "command = \"$REPO_ROOT/bin/omawsl-herdr-mode pane\"" "$f"
}

@test "config deploy never overwrites an existing Herdr config" {
  mkdir -p "$HOME/.config/herdr"
  echo 'prefix = "ctrl+a"' > "$HOME/.config/herdr/config.toml"
  run omawsl_install_herdr_config
  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/.config/herdr/config.toml")" = 'prefix = "ctrl+a"' ]
}

@test "config deploy adopts zellij's current omawsl theme" {
  mkdir -p "$HOME/.config/zellij"
  printf 'theme "rose-pine"\n' > "$HOME/.config/zellij/config.kdl"
  stub_hide_command herdr
  run omawsl_install_herdr_config
  [ "$status" -eq 0 ]
  grep -qx 'name = "rose-pine-dawn"' "$HOME/.config/herdr/config.toml"
}

@test "omawsl_herdr_theme_name maps every omawsl theme to a Herdr built-in" {
  [ "$(omawsl_herdr_theme_name tokyo-night)" = "tokyo-night" ]
  [ "$(omawsl_herdr_theme_name dracula)" = "dracula" ]
  [ "$(omawsl_herdr_theme_name one-dark)" = "one-dark" ]
  [ "$(omawsl_herdr_theme_name solarized)" = "solarized" ]
  [ "$(omawsl_herdr_theme_name rose-pine)" = "rose-pine-dawn" ]
  [ "$(omawsl_herdr_theme_name everforest)" = "terminal" ]
  [ "$(omawsl_herdr_theme_name matte-black)" = "terminal" ]
}

@test "omawsl_herdr_apply_theme rewrites only the theme name line and reloads herdr" {
  mkdir -p "$HOME/.config/herdr"
  printf '[theme]\nname = "tokyo-night"\n[keys]\nprefix = "ctrl+g"\n' > "$HOME/.config/herdr/config.toml"
  stub_command herdr
  run omawsl_herdr_apply_theme nord
  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/.config/herdr/config.toml")" = $'[theme]\nname = "nord"\n[keys]\nprefix = "ctrl+g"' ]
  [[ "$(stub_calls)" == *"herdr server reload-config"* ]]
}

@test "omawsl_herdr_apply_theme is a no-op when there's no Herdr config" {
  run omawsl_herdr_apply_theme nord
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.config/herdr" ]
}

@test "a failed Herdr download falls back to zellij instead of aborting the install" {
  export OMAWSL_MULTIPLEXER=herdr
  omawsl_save_choice OMAWSL_MULTIPLEXER herdr
  stub_hide_command herdr
  curl() { echo "curl $*" >> "$STUB_LOG"; return 6; }
  export -f curl
  run omawsl_install_herdr
  [ "$status" -eq 0 ]
  [ "$(omawsl_load_choice OMAWSL_MULTIPLEXER)" = "zellij" ]
  [[ "$output" == *"new terminals will open zellij"* ]]
  [ ! -f "$HOME/.config/herdr/config.toml" ]
}

@test "omawsl_toml_set replaces a key inside its table only" {
  local f="$BATS_TEST_TMPDIR/c.toml"
  printf '[ui.toast.clipboard]\nenabled = true\n[ui.sound]\nenabled = true\npath = "x.mp3"\n' > "$f"
  omawsl_toml_set "$f" ui.sound enabled false
  [ "$(cat "$f")" = $'[ui.toast.clipboard]\nenabled = true\n[ui.sound]\nenabled = false\npath = "x.mp3"' ]
}

@test "omawsl_toml_set adds a missing key to the end of its table" {
  local f="$BATS_TEST_TMPDIR/c.toml"
  printf '[ui.toast]\ndelay_seconds = 1\n\n[keys]\nprefix = "ctrl+g"\n' > "$f"
  omawsl_toml_set "$f" ui.toast delivery '"system"'
  [ "$(cat "$f")" = $'[ui.toast]\ndelay_seconds = 1\n\ndelivery = "system"\n[keys]\nprefix = "ctrl+g"' ]
}

@test "omawsl_toml_set appends a missing table, and is idempotent" {
  local f="$BATS_TEST_TMPDIR/c.toml"
  printf '[keys]\nprefix = "ctrl+g"\n' > "$f"
  omawsl_toml_set "$f" ui.toast delivery '"system"'
  omawsl_toml_set "$f" ui.toast delivery '"system"'
  [ "$(cat "$f")" = $'[keys]\nprefix = "ctrl+g"\n\n[ui.toast]\ndelivery = "system"' ]
}

@test "omawsl_herdr_apply_notifications turns Herdr's own alerts off and reloads herdr" {
  mkdir -p "$HOME/.config/herdr"
  local f="$HOME/.config/herdr/config.toml"
  printf '[keys]\nprefix = "ctrl+g"\n[ui.sound]\nenabled = true\n[ui.toast]\ndelivery = "system"\n' > "$f"
  stub_command herdr
  omawsl_herdr_apply_notifications
  omawsl_herdr_apply_notifications
  grep -qx 'enabled = false' "$f"
  grep -qx 'delivery = "off"' "$f"
  [ "$(grep -c '^\[ui.sound\]' "$f")" -eq 1 ]
  [ "$(grep -c '^\[ui.toast\]' "$f")" -eq 1 ]
  [[ "$(stub_calls)" == *"herdr server reload-config"* ]]
}

@test "omawsl_herdr_apply_notifications is a no-op when there's no Herdr config" {
  run omawsl_herdr_apply_notifications
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.config/herdr" ]
}

@test "notifications setup installs pulseaudio-utils for sound when paplay is missing" {
  stub_hide_command paplay herdr
  sudo() {
    echo "sudo $*" >> "$STUB_LOG"
    mkdir -p "$HOME/.local/bin"
    printf '#!/usr/bin/env bash\n' > "$HOME/.local/bin/paplay"
    chmod +x "$HOME/.local/bin/paplay"
  }
  export -f sudo
  export PATH="$HOME/.local/bin:$PATH"
  run omawsl_herdr_setup_notifications sound
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"sudo apt-get install -y pulseaudio-utils"* ]]
  [ ! -e "$HOME/.local/bin/notify-send" ]
}

@test "notifications setup fails when paplay can't be installed" {
  stub_hide_command paplay herdr
  stub_command sudo 100
  run omawsl_herdr_setup_notifications both
  [ "$status" -ne 0 ]
  [[ "$output" == *"pulseaudio-utils"* ]]
}

@test "notifications setup adds the Claude hooks for an alert choice and removes them for off" {
  stub_command paplay
  stub_hide_command herdr
  mkdir -p "$HOME/.claude"
  local slug
  for slug in both sound popup; do
    omawsl_herdr_setup_notifications "$slug"
    grep -qF 'bin/omawsl-claude-notify' "$HOME/.claude/settings.json" || { echo "$slug"; return 1; }
  done
  omawsl_herdr_setup_notifications off
  ! grep -qF 'bin/omawsl-claude-notify' "$HOME/.claude/settings.json"
}

@test "notifications setup removes omawsl's old notify-send link but never someone else's" {
  stub_command paplay
  stub_hide_command herdr
  mkdir -p "$HOME/.local/bin"
  ln -s "$REPO_ROOT/bin/omawsl-notify-send" "$HOME/.local/bin/notify-send"
  omawsl_herdr_setup_notifications both
  [ ! -e "$HOME/.local/bin/notify-send" ]
  echo mine > "$HOME/.local/bin/notify-send"
  omawsl_herdr_setup_notifications popup
  [ "$(cat "$HOME/.local/bin/notify-send")" = "mine" ]
}

@test "config deploy applies a notifications choice saved before Herdr was set up" {
  export OMAWSL_STATE_DIR="$BATS_TEST_TMPDIR/state"
  omawsl_save_choice OMAWSL_HERDR_NOTIFICATIONS popup
  stub_hide_command herdr
  mkdir -p "$HOME/.claude"
  run omawsl_install_herdr_config
  [ "$status" -eq 0 ]
  grep -qx 'delivery = "off"' "$HOME/.config/herdr/config.toml"
  grep -qF 'bin/omawsl-claude-notify' "$HOME/.claude/settings.json"
}

@test "claude hooks install adds stop, notify and ask hooks once" {
  mkdir -p "$HOME/.claude"
  echo '{"model":"opus"}' > "$HOME/.claude/settings.json"
  omawsl_claude_hooks_install
  omawsl_claude_hooks_install
  local f="$HOME/.claude/settings.json" cmd="\"$REPO_ROOT/bin/omawsl-claude-notify\""
  [ "$(jq -r .model "$f")" = opus ]
  [ "$(jq -r '.hooks.Stop[0].hooks[0].command' "$f")" = "$cmd stop" ]
  [ "$(jq -r '.hooks.Notification[0].hooks[0].command' "$f")" = "$cmd notify" ]
  [ "$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$f")" = "$cmd ask" ]
  [ "$(jq -r '.hooks.PreToolUse[0].matcher' "$f")" = AskUserQuestion ]
  [ "$(jq -r '.hooks.Stop[0].hooks[0].async' "$f")" = true ]
  [ "$(jq '[.hooks[][].hooks[]] | length' "$f")" -eq 3 ]
}

@test "claude hooks install keeps the user's own hooks on the same events" {
  mkdir -p "$HOME/.claude"
  cat > "$HOME/.claude/settings.json" <<'EOF'
{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"python3 mine.py stop"}]}],
"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"guard.sh"}]}]}}
EOF
  omawsl_claude_hooks_install
  local f="$HOME/.claude/settings.json"
  [ "$(jq -r '.hooks.Stop[0].hooks[0].command' "$f")" = "python3 mine.py stop" ]
  [ "$(jq -r '.hooks.Stop | length' "$f")" -eq 2 ]
  [ "$(jq -r '.hooks.PreToolUse[0].matcher' "$f")" = Bash ]
  [ "$(jq -r '.hooks.PreToolUse | length' "$f")" -eq 2 ]
}

@test "claude hooks install creates settings.json when Claude Code has a config dir" {
  mkdir -p "$HOME/.claude"
  omawsl_claude_hooks_install
  [ "$(jq '[.hooks[][].hooks[]] | length' "$HOME/.claude/settings.json")" -eq 3 ]
}

@test "claude hooks install does nothing when Claude Code was never run" {
  run omawsl_claude_hooks_install
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.claude" ]
}

@test "claude hooks install leaves an invalid settings.json alone and says so" {
  mkdir -p "$HOME/.claude"
  printf '{"model": "opus",\n' > "$HOME/.claude/settings.json"
  run omawsl_claude_hooks_install
  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/.claude/settings.json")" = '{"model": "opus",' ]
  [[ "$output" == *"settings.json"* ]]
}

@test "claude hooks remove takes out only omawsl's hooks" {
  mkdir -p "$HOME/.claude"
  cat > "$HOME/.claude/settings.json" <<'EOF'
{"model":"opus","hooks":{"Stop":[{"hooks":[{"type":"command","command":"python3 mine.py stop"}]}]}}
EOF
  omawsl_claude_hooks_install
  omawsl_claude_hooks_remove
  local f="$HOME/.claude/settings.json"
  [ "$(jq -c . "$f")" = '{"model":"opus","hooks":{"Stop":[{"hooks":[{"type":"command","command":"python3 mine.py stop"}]}]}}' ]
}

@test "claude hooks remove leaves a file without omawsl's hooks byte-for-byte alone" {
  mkdir -p "$HOME/.claude"
  printf '{ "model":   "opus" }\n' > "$HOME/.claude/settings.json"
  run omawsl_claude_hooks_remove
  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/.claude/settings.json")" = '{ "model":   "opus" }' ]
  rm "$HOME/.claude/settings.json"
  run omawsl_claude_hooks_remove
  [ "$status" -eq 0 ]
}

@test "claude hooks remove leaves an invalid settings.json alone" {
  mkdir -p "$HOME/.claude"
  printf 'bin/omawsl-claude-notify {' > "$HOME/.claude/settings.json"
  run omawsl_claude_hooks_remove
  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/.claude/settings.json")" = 'bin/omawsl-claude-notify {' ]
}
