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
  stub_command mise
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

@test "installs a current tree-sitter-cli via mise and writes a wrapper" {
  export OMAWSL_EDITORS="Neovim"
  run omawsl_install_neovim
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"mise exec node@lts -- npm install -g tree-sitter-cli"* ]]
  [ -x "$HOME/.local/bin/tree-sitter" ]
  [[ "$(cat "$HOME/.local/bin/tree-sitter")" == *"exec mise exec node@lts -- tree-sitter"* ]]
}

@test "installs tree-sitter-cli even when an old apt-provided tree-sitter is already on PATH" {
  # Ubuntu Noble's apt tree-sitter-cli (0.20.8-5) predates the `build`
  # subcommand nvim-treesitter's main branch needs, so `command -v
  # tree-sitter` finding a binary must not be treated as "already fixed"
  # (issue #17) - the wrapper must still be installed to take PATH
  # precedence over it.
  export OMAWSL_EDITORS="Neovim"
  local fake_bin="$BATS_TEST_TMPDIR/old-tree-sitter-bin"
  mkdir -p "$fake_bin"
  cat > "$fake_bin/tree-sitter" <<'EOF'
#!/usr/bin/env bash
echo "tree-sitter 0.20.8"
EOF
  chmod +x "$fake_bin/tree-sitter"
  export PATH="$fake_bin:$PATH"

  run omawsl_install_neovim
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"mise exec node@lts -- npm install -g tree-sitter-cli"* ]]
  [ -x "$HOME/.local/bin/tree-sitter" ]
}

@test "does not reinstall tree-sitter-cli once our wrapper is already present" {
  export OMAWSL_EDITORS="Neovim"
  mkdir -p "$HOME/.local/bin"
  cat > "$HOME/.local/bin/tree-sitter" <<'EOF'
#!/usr/bin/env bash
exec mise exec node@lts -- tree-sitter "$@"
EOF
  chmod +x "$HOME/.local/bin/tree-sitter"

  run omawsl_install_neovim
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"tree-sitter-cli"* ]]
}
