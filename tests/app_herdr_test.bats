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

@test "omawsl_herdr_apply_notifications maps each choice to sound + delivery and reloads herdr" {
  mkdir -p "$HOME/.config/herdr"
  local f="$HOME/.config/herdr/config.toml"
  printf '[keys]\nprefix = "ctrl+g"\n' > "$f"
  stub_command herdr
  local pair
  for pair in both:true:system sound:true:off popup:false:system off:false:off; do
    IFS=: read -r slug sound delivery <<< "$pair"
    omawsl_herdr_apply_notifications "$slug"
    grep -qx "enabled = $sound" "$f" || { echo "$slug: sound"; cat "$f"; return 1; }
    grep -qx "delivery = \"$delivery\"" "$f" || { echo "$slug: delivery"; cat "$f"; return 1; }
  done
  [ "$(grep -c '^\[ui.sound\]' "$f")" -eq 1 ]
  [ "$(grep -c '^\[ui.toast\]' "$f")" -eq 1 ]
  [[ "$(stub_calls)" == *"herdr server reload-config"* ]]
}

@test "omawsl_herdr_apply_notifications is a no-op when there's no Herdr config" {
  run omawsl_herdr_apply_notifications both
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

@test "notifications setup links notify-send for popups and unlinks it for sound-only" {
  stub_command paplay
  stub_hide_command herdr
  omawsl_herdr_setup_notifications popup
  [ "$(readlink "$HOME/.local/bin/notify-send")" = "$REPO_ROOT/bin/omawsl-notify-send" ]
  omawsl_herdr_setup_notifications sound
  [ ! -e "$HOME/.local/bin/notify-send" ]
}

@test "notifications setup never replaces someone else's notify-send" {
  stub_hide_command herdr
  mkdir -p "$HOME/.local/bin"
  echo mine > "$HOME/.local/bin/notify-send"
  run omawsl_herdr_setup_notifications popup
  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/.local/bin/notify-send")" = "mine" ]
  omawsl_herdr_setup_notifications off
  [ "$(cat "$HOME/.local/bin/notify-send")" = "mine" ]
}

@test "config deploy applies a notifications choice saved before Herdr was set up" {
  export OMAWSL_STATE_DIR="$BATS_TEST_TMPDIR/state"
  omawsl_save_choice OMAWSL_HERDR_NOTIFICATIONS popup
  stub_hide_command herdr
  run omawsl_install_herdr_config
  [ "$status" -eq 0 ]
  grep -qx 'delivery = "system"' "$HOME/.config/herdr/config.toml"
  [ -L "$HOME/.local/bin/notify-send" ]
}
