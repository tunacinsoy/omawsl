#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/uninstall/app-claude-cli.sh"
  source "$REPO_ROOT/uninstall/app-codex-cli.sh"
  source "$REPO_ROOT/uninstall/app-antigravity-cli.sh"
}

@test "omawsl_uninstall_claude_cli removes the binary and its data dir" {
  mkdir -p "$HOME/.local/share/claude/versions" "$HOME/.local/bin"
  ln -s "$HOME/.local/share/claude/versions/1.0" "$HOME/.local/bin/claude"
  run omawsl_uninstall_claude_cli
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.local/bin/claude" ]
  [ ! -d "$HOME/.local/share/claude" ]
}

@test "omawsl_uninstall_codex_cli uninstalls the npm package and removes the wrapper" {
  stub_command mise
  mkdir -p "$HOME/.local/bin"
  cat > "$HOME/.local/bin/codex" <<'EOF'
#!/usr/bin/env bash
exec mise exec node@lts -- codex "$@"
EOF
  chmod +x "$HOME/.local/bin/codex"
  run omawsl_uninstall_codex_cli
  [ "$status" -eq 0 ]
  [ ! -f "$HOME/.local/bin/codex" ]
  [[ "$(stub_calls)" == *"mise exec node@lts -- npm uninstall -g @openai/codex"* ]]
}

@test "omawsl_uninstall_antigravity_cli removes the binary and its updater state dir" {
  mkdir -p "$HOME/.local/bin" "$HOME/.gemini/antigravity-cli"
  touch "$HOME/.local/bin/agy"
  run omawsl_uninstall_antigravity_cli
  [ "$status" -eq 0 ]
  [ ! -f "$HOME/.local/bin/agy" ]
  [ ! -d "$HOME/.gemini/antigravity-cli" ]
}

@test "omawsl_uninstall_codex_cli no-ops cleanly when mise isn't reachable" {
  stub_hide_command mise
  mkdir -p "$HOME/.local/bin"
  touch "$HOME/.local/bin/codex"
  run omawsl_uninstall_codex_cli
  [ "$status" -eq 0 ]
  [ ! -f "$HOME/.local/bin/codex" ]
}
