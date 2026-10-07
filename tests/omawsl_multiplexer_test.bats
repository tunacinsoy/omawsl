#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  gum_stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  export OMAWSL_STATE_DIR="$BATS_TEST_TMPDIR/state"
  mkdir -p "$HOME/.local/bin"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/bin/omawsl-sub/multiplexer.sh"
}

# Fake installer that really puts a herdr on PATH, like the real one.
_fake_successful_install() {
  omawsl_herdr_install_steps() {
    printf '#!/usr/bin/env bash\n' > "$HOME/.local/bin/herdr"
    chmod +x "$HOME/.local/bin/herdr"
    echo "herdr-installed" >> "$STUB_LOG"
  }
  stub_hide_command herdr
  export PATH="$HOME/.local/bin:$PATH"
}

@test "current is zellij when nothing was ever chosen" {
  [ "$(omawsl_multiplexer_current)" = "zellij" ]
}

@test "switching to zellij saves the choice without downloading anything" {
  stub_command curl
  run omawsl_multiplexer_command zellij
  [ "$status" -eq 0 ]
  [ "$(omawsl_load_choice OMAWSL_MULTIPLEXER)" = "zellij" ]
  [[ "$(stub_calls)" != *"curl"* ]]
}

@test "switching to herdr installs it when missing, deploys the config and saves the choice" {
  _fake_successful_install
  run omawsl_multiplexer_command herdr
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"herdr-installed"* ]]
  [ -f "$HOME/.config/herdr/config.toml" ]
  [ "$(omawsl_load_choice OMAWSL_MULTIPLEXER)" = "herdr" ]
  [[ "$output" == *"open a new terminal"* ]]
}

@test "install failure leaves the choice unchanged" {
  omawsl_save_choice OMAWSL_MULTIPLEXER zellij
  omawsl_herdr_install_steps() { return 1; }
  stub_hide_command herdr
  run omawsl_multiplexer_command herdr
  [ "$status" -ne 0 ]
  [ "$(omawsl_load_choice OMAWSL_MULTIPLEXER)" = "zellij" ]
  [[ "$output" == *"staying on zellij"* ]]
}

@test "rejects an unknown multiplexer" {
  run omawsl_multiplexer_command tmux
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown multiplexer 'tmux'"* ]]
}

@test "with no argument, asks via gum and applies the pick" {
  gum_stub_respond "Zellij (default)"
  run omawsl_multiplexer_command
  [ "$status" -eq 0 ]
  [ "$(omawsl_load_choice OMAWSL_MULTIPLEXER)" = "zellij" ]
}

@test "with no argument, cancelling the picker changes nothing" {
  gum_stub_respond ""
  run omawsl_multiplexer_command
  [ "$status" -eq 0 ]
  [ -z "$(omawsl_load_choice OMAWSL_MULTIPLEXER)" ]
}
