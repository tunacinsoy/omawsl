#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  source "$REPO_ROOT/install/terminal/apps-terminal.sh"
  stub_command sudo
  # lazygit's and lazydocker's install steps both parse a GitHub API JSON
  # response to resolve the latest version (their release asset filenames
  # embed the version number, unlike zellij's) - a plain dumb stub_command
  # curl (no stdout) would make that `grep -Po` come up empty, and under
  # this sourced script's `set -e` an empty-match grep in a bare
  # assignment aborts the whole function.
  stub_command_output_for curl "api.github.com/repos/jesseduffield/lazygit" '{"tag_name": "v9.9.9"}'
  stub_command_output_for curl "api.github.com/repos/jesseduffield/lazydocker" '{"tag_name": "v8.8.8"}'
  stub_command tar
  stub_hide_command lazydocker zellij lazygit fastfetch
}

@test "installs the full Omakub-parity terminal tool set via apt, including the newly-folded-in always-on tools" {
  run omawsl_install_terminal_apps
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"sudo apt-get install -y fzf ripgrep bat eza zoxide plocate apache2-utils fd-find gh btop"* ]]
  [[ "$(stub_calls)" != *"apt-get install -y fzf ripgrep bat eza zoxide plocate apache2-utils fd-find gh btop fastfetch"* ]]
}

@test "installs lazydocker via its official GitHub release when not already present" {
  run omawsl_install_lazydocker
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"curl -fsSL https://api.github.com/repos/jesseduffield/lazydocker/releases/latest"* ]]
  [[ "$(stub_calls)" == *"curl -fsSL https://github.com/jesseduffield/lazydocker/releases/download/v8.8.8/lazydocker_8.8.8_Linux_x86_64.tar.gz"* ]]
  [[ "$(stub_calls)" == *"sudo install -m 0755 /tmp/lazydocker /usr/local/bin/lazydocker"* ]]
}

@test "skips lazydocker when already installed" {
  stub_command lazydocker
  run omawsl_install_lazydocker
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"jesseduffield/lazydocker"* ]]
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
  [[ "$(stub_calls)" == *"sudo apt-get install -y fzf ripgrep bat eza zoxide plocate apache2-utils fd-find gh btop jq"* ]]
}

@test "installs bash-completion alongside the rest of the always-on apt tool set" {
  # Explicit install rather than relying on it arriving as a transitive
  # dependency of something else (confirmed present-but-unsourced on the
  # real test WSL2 instance before this) - configs/bashrc sources it, but
  # sourcing a package that isn't guaranteed to be installed would be
  # fragile.
  run omawsl_install_terminal_apps
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"sudo apt-get install -y fzf ripgrep bat eza zoxide plocate apache2-utils fd-find gh btop jq bash-completion"* ]]
}

@test "installs lazygit via its official GitHub release when not already present" {
  run omawsl_install_lazygit
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"curl -fsSL https://api.github.com/repos/jesseduffield/lazygit/releases/latest"* ]]
  [[ "$(stub_calls)" == *"curl -fsSL https://github.com/jesseduffield/lazygit/releases/download/v9.9.9/lazygit_9.9.9_linux_x86_64.tar.gz"* ]]
  [[ "$(stub_calls)" == *"sudo install -m 0755 /tmp/lazygit /usr/local/bin/lazygit"* ]]
}

@test "skips lazygit when already installed" {
  stub_command lazygit
  run omawsl_install_lazygit
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"jesseduffield/lazygit"* ]]
}

@test "omawsl_lazygit_install_steps runs unconditionally, even if lazygit is already installed" {
  stub_command lazygit
  run omawsl_lazygit_install_steps
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"jesseduffield/lazygit"* ]]
}

@test "installs fastfetch via its official .deb release when not already present" {
  run omawsl_install_fastfetch
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"curl -fsSL -o "*"https://github.com/fastfetch-cli/fastfetch/releases/latest/download/fastfetch-linux-amd64.deb"* ]]
  [[ "$(stub_calls)" == *"sudo apt-get install -y "*.deb* ]]
}

@test "skips fastfetch when already installed" {
  stub_command fastfetch
  run omawsl_install_fastfetch
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"fastfetch-cli/fastfetch"* ]]
}

@test "omawsl_fastfetch_install_steps runs unconditionally, even if fastfetch is already installed" {
  stub_command fastfetch
  run omawsl_fastfetch_install_steps
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"fastfetch-cli/fastfetch"* ]]
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
  [[ "$(stub_calls)" == *"jesseduffield/lazydocker"* ]]
}
