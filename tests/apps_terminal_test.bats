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

@test "deploys configs/zellij.kdl to ~/.config/zellij/config.kdl" {
  run omawsl_install_zellij_config
  [ "$status" -eq 0 ]
  diff "$HOME/.config/zellij/config.kdl" "$REPO_ROOT/configs/zellij.kdl"
}

@test "does not overwrite an existing zellij config.kdl" {
  mkdir -p "$HOME/.config/zellij"
  echo "theme \"my-custom-theme\"" > "$HOME/.config/zellij/config.kdl"
  run omawsl_install_zellij_config
  [ "$status" -eq 0 ]
  [[ "$(cat "$HOME/.config/zellij/config.kdl")" == 'theme "my-custom-theme"' ]]
}

@test "deploys configs/btop.conf to ~/.config/btop/btop.conf" {
  run omawsl_install_btop_config
  [ "$status" -eq 0 ]
  diff "$HOME/.config/btop/btop.conf" "$REPO_ROOT/configs/btop.conf"
}

@test "does not overwrite an existing btop.conf" {
  mkdir -p "$HOME/.config/btop"
  echo 'color_theme = "my-custom-theme"' > "$HOME/.config/btop/btop.conf"
  run omawsl_install_btop_config
  [ "$status" -eq 0 ]
  [[ "$(cat "$HOME/.config/btop/btop.conf")" == 'color_theme = "my-custom-theme"' ]]
}

@test "installs jq alongside the rest of the always-on apt tool set" {
  run omawsl_install_terminal_apps
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"sudo apt-get install -y fzf ripgrep bat eza zoxide plocate apache2-utils fd-find gh btop fastfetch lazygit jq"* ]]
}

@test "installs bash-completion alongside the rest of the always-on apt tool set" {
  # Explicit install rather than relying on it arriving as a transitive
  # dependency of something else (confirmed present-but-unsourced on the
  # real test WSL2 instance before this) - configs/bashrc sources it, but
  # sourcing a package that isn't guaranteed to be installed would be
  # fragile.
  run omawsl_install_terminal_apps
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"sudo apt-get install -y fzf ripgrep bat eza zoxide plocate apache2-utils fd-find gh btop fastfetch lazygit jq bash-completion"* ]]
}

@test "installs a bin/omawsl wrapper into ~/.local/bin that execs the real script" {
  run omawsl_install_cli
  [ "$status" -eq 0 ]
  [ -x "$HOME/.local/bin/omawsl" ]
  [[ "$(cat "$HOME/.local/bin/omawsl")" == *"exec bash \"$REPO_ROOT/bin/omawsl\""* ]]
}

@test "omawsl_zellij_install_steps runs unconditionally, even if zellij is already installed" {
  stub_command zellij
  run omawsl_zellij_install_steps
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"unknown-linux-musl"* ]]
}

@test "omawsl_lazydocker_install_steps runs unconditionally, even if lazydocker is already installed" {
  stub_command lazydocker
  run omawsl_lazydocker_install_steps
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"install_update_linux.sh"* ]]
}
