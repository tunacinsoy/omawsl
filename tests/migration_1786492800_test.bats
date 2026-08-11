#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  stub_command mise
}

@test "installs tree-sitter-cli when Neovim/LazyVim is already installed" {
  mkdir -p "$HOME/.config/nvim"
  run bash "$REPO_ROOT/migrations/1786492800.sh"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"mise exec node@lts -- npm install -g tree-sitter-cli"* ]]
  [ -x "$HOME/.local/bin/tree-sitter" ]
}

@test "no-ops cleanly when Neovim was never installed" {
  run bash "$REPO_ROOT/migrations/1786492800.sh"
  [ "$status" -eq 0 ]
  [ -z "$(stub_calls)" ]
  [ ! -f "$HOME/.local/bin/tree-sitter" ]
}

@test "is idempotent once the wrapper already exists" {
  mkdir -p "$HOME/.config/nvim" "$HOME/.local/bin"
  cat > "$HOME/.local/bin/tree-sitter" <<'EOF'
#!/usr/bin/env bash
exec mise exec node@lts -- tree-sitter "$@"
EOF
  chmod +x "$HOME/.local/bin/tree-sitter"

  run bash "$REPO_ROOT/migrations/1786492800.sh"
  [ "$status" -eq 0 ]
  [ -z "$(stub_calls)" ]
}

@test "exits non-zero when the npm install fails, so migrate.sh retries it on the next run" {
  mkdir -p "$HOME/.config/nvim"
  stub_command mise 1
  run bash "$REPO_ROOT/migrations/1786492800.sh"
  [ "$status" -ne 0 ]
  [ ! -f "$HOME/.local/bin/tree-sitter" ]
}
