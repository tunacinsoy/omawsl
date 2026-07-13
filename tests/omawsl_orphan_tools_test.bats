#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/bin/omawsl-sub/items.sh"
  source "$REPO_ROOT/bin/omawsl-sub/orphan-tools.sh"
}

@test "omawsl_orphan_tool_slugs lists all 7 orphan tools" {
  run omawsl_orphan_tool_slugs
  [ "$status" -eq 0 ]
  [[ "$output" == *"zellij"* ]]
  [[ "$output" == *"lazydocker"* ]]
  [[ "$output" == *"opencode"* ]]
  [[ "$output" == *"claude"* ]]
  [[ "$output" == *"codex"* ]]
  [[ "$output" == *"gemini"* ]]
  [[ "$output" == *"gh-copilot"* ]]
  [ "$(omawsl_orphan_tool_slugs | wc -l)" -eq 7 ]
}

@test "omawsl_orphan_tool_label returns Zellij/LazyDocker directly and reuses items.sh for the rest" {
  [ "$(omawsl_orphan_tool_label zellij)" = "Zellij" ]
  [ "$(omawsl_orphan_tool_label lazydocker)" = "LazyDocker" ]
  [ "$(omawsl_orphan_tool_label codex)" = "$(omawsl_item_label codex)" ]
  [ "$(omawsl_orphan_tool_label gh-copilot)" = "GitHub Copilot CLI" ]
}

@test "omawsl_orphan_tool_label fails for an unknown slug" {
  run omawsl_orphan_tool_label nonsense
  [ "$status" -ne 0 ]
}

@test "omawsl_orphan_tool_installed checks zellij/lazydocker via command -v" {
  stub_hide_command zellij lazydocker
  run omawsl_orphan_tool_installed zellij
  [ "$status" -ne 0 ]
  stub_command zellij
  run omawsl_orphan_tool_installed zellij
  [ "$status" -eq 0 ]
}

@test "omawsl_orphan_tool_installed checks gh-copilot via gh extension list" {
  stub_command gh
  run omawsl_orphan_tool_installed gh-copilot
  [ "$status" -ne 0 ]
}
