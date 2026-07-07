#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  source "$REPO_ROOT/install/terminal/apps-terminal.sh"
  stub_command sudo
  stub_command curl
  stub_command tar
  stub_hide_command lazydocker zellij
}

@test "installs the full Omakub-parity terminal tool set via apt, including the newly-folded-in always-on tools" {
  run omawsl_install_terminal_apps
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"sudo apt-get install -y fzf ripgrep bat eza zoxide plocate apache2-utils fd-find gh btop fastfetch lazygit"* ]]
}

@test "installs lazydocker via its official script when not already present" {
  run omawsl_install_lazydocker
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"curl -fsSL https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh"* ]]
}

@test "skips lazydocker when already installed" {
  stub_command lazydocker
  run omawsl_install_lazydocker
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"install_update_linux.sh"* ]]
}

@test "installs zellij via its GitHub release when not already present" {
  run omawsl_install_zellij
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"curl -fsSL https://github.com/zellij-org/zellij/releases/latest/download/zellij-"*"-unknown-linux-musl.tar.gz"* ]]
  [[ "$(stub_calls)" == *"sudo install -m 0755 /tmp/zellij /usr/local/bin/zellij"* ]]
}

@test "skips zellij when already installed" {
  stub_command zellij
  run omawsl_install_zellij
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"unknown-linux-musl"* ]]
}
