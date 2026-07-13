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

@test "omawsl_orphan_extract_semver pulls the first X.Y.Z token out of arbitrary text" {
  [ "$(omawsl_orphan_extract_semver "zellij 0.44.3")" = "0.44.3" ]
  [ "$(omawsl_orphan_extract_semver $'Version: 0.25.2\nGit commit: abc123')" = "0.25.2" ]
  [ "$(omawsl_orphan_extract_semver "2.1.207 (Claude Code)")" = "2.1.207" ]
  [ "$(omawsl_orphan_extract_semver "")" = "" ]
}

@test "omawsl_orphan_extract_semver returns exit 0 and empty output when given text with no semver token (no grep match)" {
  run omawsl_orphan_extract_semver "no version here"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "omawsl_orphan_tool_version_installed returns exit 0 and empty output when a tool's version stub produces no semver (simulating not installed)" {
  zellij() { echo "zellij not found"; }
  export -f zellij
  run omawsl_orphan_tool_version_installed zellij
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "omawsl_orphan_latest_from_github strips a leading v from the release tag" {
  curl() { echo '{"tag_name":"v0.44.3"}'; }
  export -f curl
  [ "$(omawsl_orphan_latest_from_github zellij-org/zellij)" = "0.44.3" ]
}

@test "omawsl_orphan_latest_from_github returns empty on a curl failure" {
  curl() { return 1; }
  export -f curl
  [ "$(omawsl_orphan_latest_from_github zellij-org/zellij)" = "" ]
}

@test "omawsl_orphan_latest_from_github returns empty on malformed JSON" {
  curl() { echo 'not json'; }
  export -f curl
  [ "$(omawsl_orphan_latest_from_github zellij-org/zellij)" = "" ]
}

@test "omawsl_orphan_latest_from_npm uses the private mise Node runtime, not a bare npm" {
  stub_command mise
  omawsl_orphan_latest_from_npm "@openai/codex"
  [[ "$(stub_calls)" == *"mise exec node@lts -- npm view @openai/codex version"* ]]
}

@test "omawsl_orphan_tool_version_installed dispatches per tool" {
  zellij() { echo "zellij 0.44.3"; }
  export -f zellij
  [ "$(omawsl_orphan_tool_version_installed zellij)" = "0.44.3" ]
}

@test "omawsl_orphan_tool_version_latest dispatches to github for binary-release tools and npm for the two npm globals" {
  curl() { echo '{"tag_name":"v9.9.9"}'; }
  export -f curl
  [ "$(omawsl_orphan_tool_version_latest zellij)" = "9.9.9" ]
  [ "$(omawsl_orphan_tool_version_latest claude)" = "9.9.9" ]

  stub_command mise
  gum_stub_init 2>/dev/null || true
  mise() { echo "8.8.8"; }
  export -f mise
  [ "$(omawsl_orphan_tool_version_latest codex)" = "8.8.8" ]
  [ "$(omawsl_orphan_tool_version_latest gemini)" = "8.8.8" ]
}

@test "omawsl_orphan_wait_with_timeout returns 0 for a process that exits on its own" {
  sleep 0.2 &
  run omawsl_orphan_wait_with_timeout "$!" 5
  [ "$status" -eq 0 ]
}

@test "omawsl_orphan_wait_with_timeout kills and returns 1 for a process that outlives the limit" {
  sleep 30 &
  local pid=$!
  run omawsl_orphan_wait_with_timeout "$pid" 1
  [ "$status" -eq 1 ]
  ! kill -0 "$pid" 2>/dev/null
}

@test "omawsl_orphan_tools_check_versions writes one result file per slug in parallel" {
  zellij() { echo "zellij 1.2.3"; }
  export -f zellij
  lazydocker() { echo "Version: 4.5.6"; }
  export -f lazydocker
  curl() { echo '{"tag_name":"v9.9.9"}'; }
  export -f curl

  local tmp_dir="$BATS_TEST_TMPDIR/results"
  mkdir -p "$tmp_dir"
  omawsl_orphan_tools_check_versions "$tmp_dir" 5 zellij lazydocker
  [ "$(cat "$tmp_dir/zellij.result")" = "$(printf '1.2.3\t9.9.9')" ]
  [ "$(cat "$tmp_dir/lazydocker.result")" = "$(printf '4.5.6\t9.9.9')" ]
}

@test "omawsl_orphan_tools_check_versions falls back to empty/empty when a job times out" {
  omawsl_orphan_tool_version_latest() { sleep 30; echo "9.9.9"; }
  export -f omawsl_orphan_tool_version_latest

  local tmp_dir="$BATS_TEST_TMPDIR/results-timeout"
  mkdir -p "$tmp_dir"
  omawsl_orphan_tools_check_versions "$tmp_dir" 1 zellij
  [ "$(cat "$tmp_dir/zellij.result")" = "$(printf '\t')" ]
}
