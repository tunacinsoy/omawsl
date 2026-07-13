#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/uninstall/app-neovim.sh"
  source "$REPO_ROOT/uninstall/app-opencode.sh"
  stub_command sudo
}

@test "omawsl_uninstall_neovim removes the LazyVim config dir and purges the apt package" {
  mkdir -p "$HOME/.config/nvim/lua/plugins"
  run omawsl_uninstall_neovim
  [ "$status" -eq 0 ]
  [ ! -d "$HOME/.config/nvim" ]
  [[ "$(stub_calls)" == *"sudo apt-get purge -y neovim"* ]]
}

@test "omawsl_uninstall_neovim no-ops cleanly when nvim config never existed" {
  run omawsl_uninstall_neovim
  [ "$status" -eq 0 ]
}

@test "omawsl_uninstall_opencode removes the ~/.opencode directory" {
  mkdir -p "$HOME/.opencode/bin"
  touch "$HOME/.opencode/bin/opencode"
  run omawsl_uninstall_opencode
  [ "$status" -eq 0 ]
  [ ! -d "$HOME/.opencode" ]
}
