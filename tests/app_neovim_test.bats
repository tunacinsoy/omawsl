#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/install/terminal/app-neovim.sh"
  stub_command sudo
  stub_command git
}

@test "no-ops entirely when Neovim isn't selected" {
  export OMAWSL_EDITORS=""
  run omawsl_install_neovim
  [ "$status" -eq 0 ]
  [ -z "$(stub_calls)" ]
}

@test "installs neovim and bootstraps LazyVim's starter config" {
  export OMAWSL_EDITORS="Neovim"
  run omawsl_install_neovim
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"sudo apt-get install -y neovim"* ]]
  [[ "$(stub_calls)" == *"git clone https://github.com/LazyVim/starter $HOME/.config/nvim"* ]]
}

@test "does not overwrite an existing nvim config" {
  export OMAWSL_EDITORS="Neovim"
  mkdir -p "$HOME/.config/nvim"
  echo "existing config" > "$HOME/.config/nvim/init.lua"
  run omawsl_install_neovim
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"git clone"* ]]
  [ "$(cat "$HOME/.config/nvim/init.lua")" = "existing config" ]
}
