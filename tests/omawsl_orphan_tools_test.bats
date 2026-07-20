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

@test "omawsl_orphan_tool_slugs lists all 8 orphan tools" {
  run omawsl_orphan_tool_slugs
  [ "$status" -eq 0 ]
  [[ "$output" == *"zellij"* ]]
  [[ "$output" == *"lazydocker"* ]]
  [[ "$output" == *"opencode"* ]]
  [[ "$output" == *"claude"* ]]
  [[ "$output" == *"codex"* ]]
  [[ "$output" == *"gemini"* ]]
  [[ "$output" == *"gh-copilot"* ]]
  [[ "$output" == *"aws"* ]]
  [ "$(omawsl_orphan_tool_slugs | wc -l)" -eq 8 ]
}

@test "omawsl_orphan_tool_label returns Zellij/LazyDocker directly and reuses items.sh for the rest" {
  [ "$(omawsl_orphan_tool_label zellij)" = "Zellij" ]
  [ "$(omawsl_orphan_tool_label lazydocker)" = "LazyDocker" ]
  [ "$(omawsl_orphan_tool_label codex)" = "$(omawsl_item_label codex)" ]
  [ "$(omawsl_orphan_tool_label gh-copilot)" = "GitHub Copilot CLI" ]
  [ "$(omawsl_orphan_tool_label aws)" = "AWS CLI" ]
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

@test "omawsl_orphan_tool_installed checks gh-copilot via command -v copilot" {
  stub_hide_command copilot
  run omawsl_orphan_tool_installed gh-copilot
  [ "$status" -ne 0 ]
  stub_command copilot
  run omawsl_orphan_tool_installed gh-copilot
  [ "$status" -eq 0 ]
}

@test "omawsl_orphan_tool_installed checks aws via command -v" {
  stub_hide_command aws
  run omawsl_orphan_tool_installed aws
  [ "$status" -ne 0 ]
  stub_command aws
  run omawsl_orphan_tool_installed aws
  [ "$status" -eq 0 ]
}

@test "omawsl_orphan_tool_version_installed extracts aws-cli's semver from its --version output" {
  aws() { echo "aws-cli/2.15.30 Python/3.11.6 Linux/6.18.33.2 exe/x86_64.ubuntu.26"; }
  export -f aws
  [ "$(omawsl_orphan_tool_version_installed aws)" = "2.15.30" ]
}

@test "omawsl_orphan_tool_version_latest resolves aws via the aws/aws-cli GitHub repo" {
  curl() { echo '{"tag_name":"2.19.0"}'; }
  export -f curl
  [ "$(omawsl_orphan_tool_version_latest aws)" = "2.19.0" ]
}

@test "omawsl_orphan_tool_apply_update calls aws_cli_install_steps for aws" {
  omawsl_aws_cli_install_steps() { echo "aws-cli-updated" >> "$STUB_LOG"; }
  export -f omawsl_aws_cli_install_steps
  run omawsl_orphan_tool_apply_update aws
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"aws-cli-updated"* ]]
}

@test "omawsl_orphan_extract_semver pulls the first X.Y.Z token out of arbitrary text" {
  [ "$(omawsl_orphan_extract_semver "zellij 0.44.3")" = "0.44.3" ]
  [ "$(omawsl_orphan_extract_semver $'Version: 0.25.2\nGit commit: abc123')" = "0.25.2" ]
  [ "$(omawsl_orphan_extract_semver "2.1.207 (Claude Code)")" = "2.1.207" ]
  [ "$(omawsl_orphan_extract_semver "")" = "" ]
}

@test "omawsl_orphan_tools_format_line reports update available when versions differ" {
  run omawsl_orphan_tools_format_line codex "0.38.1" "0.41.0"
  [[ "$output" == *"Codex CLI"* ]]
  [[ "$output" == *"current: 0.38.1"* ]]
  [[ "$output" == *"latest: 0.41.0"* ]]
  [[ "$output" == *"update available"* ]]
}

@test "omawsl_orphan_tools_format_line reports up to date when versions match" {
  run omawsl_orphan_tools_format_line gemini "2.1.0" "2.1.0"
  [[ "$output" == *"up to date"* ]]
}

@test "omawsl_orphan_tools_format_line reports unknown when latest is empty" {
  run omawsl_orphan_tools_format_line zellij "0.44.3" ""
  [[ "$output" == *"unknown"* ]]
}

@test "omawsl_orphan_tool_apply_update dispatches to the right tool's steps function" {
  omawsl_codex_cli_install_steps() { echo "codex-updated" >> "$STUB_LOG"; }
  export -f omawsl_codex_cli_install_steps
  run omawsl_orphan_tool_apply_update codex
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"codex-updated"* ]]
}

@test "omawsl_orphan_tool_apply_update calls gh_copilot_install_steps for gh-copilot" {
  omawsl_gh_copilot_install_steps() { echo "gh-copilot-updated" >> "$STUB_LOG"; }
  export -f omawsl_gh_copilot_install_steps
  run omawsl_orphan_tool_apply_update gh-copilot
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"gh-copilot-updated"* ]]
}

@test "omawsl_orphan_tool_apply_update isolates a failure and keeps a zero exit" {
  omawsl_codex_cli_install_steps() { return 1; }
  export -f omawsl_codex_cli_install_steps
  run omawsl_orphan_tool_apply_update codex
  [ "$status" -eq 0 ]
  [[ "$output" == *"failed to update"* ]]
}

@test "omawsl_orphan_tool_apply_update reports a real AWS CLI download failure as failed to update, not updated" {
  dpkg() { echo "amd64"; }
  export -f dpkg
  curl() { return 1; }
  export -f curl
  run omawsl_orphan_tool_apply_update aws
  [ "$status" -eq 0 ]
  [[ "$output" == *"failed to update"* ]]
  [[ "$output" != *"updated AWS CLI"* ]]
}

@test "every function omawsl_orphan_tool_apply_update dispatches to actually exists" {
  for fn in omawsl_zellij_install_steps omawsl_lazydocker_install_steps \
            omawsl_opencode_install_steps omawsl_claude_cli_install_steps \
            omawsl_codex_cli_install_steps omawsl_gemini_cli_install_steps \
            omawsl_gh_copilot_install_steps omawsl_aws_cli_install_steps; do
    declare -F "$fn" >/dev/null || { echo "missing function: $fn"; return 1; }
  done
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

@test "omawsl_orphan_tool_version_latest dispatches to github for binary-release tools and npm for the three npm globals" {
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
  [ "$(omawsl_orphan_tool_version_latest gh-copilot)" = "8.8.8" ]
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

@test "omawsl_orphan_tools_check_versions bounds total wait by a single shared timeout, not timeout * number of hung jobs" {
  omawsl_orphan_tool_version_latest() { sleep 10; echo "9.9.9"; }
  export -f omawsl_orphan_tool_version_latest

  local tmp_dir="$BATS_TEST_TMPDIR/results-multi-timeout"
  mkdir -p "$tmp_dir"

  local start elapsed
  start="$(date +%s)"
  omawsl_orphan_tools_check_versions "$tmp_dir" 1 zellij lazydocker opencode
  elapsed=$(( $(date +%s) - start ))

  # All 3 jobs hang simultaneously. With the bug (a fresh timeout_seconds
  # countdown restarted per wait-loop iteration) this would take ~3s (1s *
  # 3 jobs). With a single shared deadline it should stay close to the 1s
  # bound - allow generous slack for CI/WSL scheduling jitter, but well
  # under the ~3s the bug would produce.
  [ "$elapsed" -le 2 ]

  [ "$(cat "$tmp_dir/zellij.result")" = "$(printf '\t')" ]
  [ "$(cat "$tmp_dir/lazydocker.result")" = "$(printf '\t')" ]
  [ "$(cat "$tmp_dir/opencode.result")" = "$(printf '\t')" ]
}

@test "omawsl_orphan_tools_installed_slugs lists only what's actually installed" {
  stub_hide_command zellij lazydocker opencode claude codex gemini gh copilot
  stub_command zellij
  stub_command codex
  run omawsl_orphan_tools_installed_slugs
  [ "$status" -eq 0 ]
  [[ "$output" == *"zellij"* ]]
  [[ "$output" == *"codex"* ]]
  [[ "$output" != *"lazydocker"* ]]
}

@test "omawsl_orphan_tools_update no-ops cleanly when no orphan tool is installed" {
  stub_hide_command zellij lazydocker opencode claude codex gemini gh copilot
  run omawsl_orphan_tools_update
  [ "$status" -eq 0 ]
  [[ "$output" == *"no orphan tools installed"* ]]
}

@test "omawsl_orphan_tools_update skips the picker when everything is confirmed up to date" {
  stub_hide_command lazydocker opencode claude codex gemini gh copilot
  stub_command zellij
  zellij() { echo "zellij 1.0.0"; }
  export -f zellij
  omawsl_orphan_tool_version_latest() { echo "1.0.0"; }
  export -f omawsl_orphan_tool_version_latest
  run omawsl_orphan_tools_update
  [ "$status" -eq 0 ]
  [[ "$output" == *"already up to date"* ]]
  [[ "$(stub_calls)" != *"gum choose"* ]]
}

@test "omawsl_orphan_tools_update shows the picker, pre-selecting only outdated tools, and applies what's picked" {
  stub_hide_command lazydocker opencode claude codex gemini gh copilot
  stub_command zellij
  gum_stub_init
  zellij() { echo "zellij 1.0.0"; }
  export -f zellij
  omawsl_orphan_tool_version_latest() { echo "2.0.0"; }
  export -f omawsl_orphan_tool_version_latest
  omawsl_zellij_install_steps() { echo "zellij-updated" >> "$STUB_LOG"; }
  export -f omawsl_zellij_install_steps
  gum_stub_respond "$(omawsl_orphan_tools_format_line zellij 1.0.0 2.0.0)"

  run omawsl_orphan_tools_update
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"gum choose"* ]]
  [[ "$(stub_calls)" == *"--selected"* ]]
  [[ "$(stub_calls)" == *"zellij-updated"* ]]
}

@test "omawsl_orphan_tools_update still shows the picker when a tool is unknown, even with none confirmed outdated" {
  stub_hide_command lazydocker opencode claude codex gemini gh copilot
  stub_command zellij
  gum_stub_init
  zellij() { echo "zellij 1.0.0"; }
  export -f zellij
  omawsl_orphan_tool_version_latest() { echo ""; }
  export -f omawsl_orphan_tool_version_latest
  gum_stub_respond ""

  run omawsl_orphan_tools_update
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"gum choose"* ]]
}

@test "omawsl_orphan_tools_live_check eventually prints the resolved version line" {
  local tmp_dir="$BATS_TEST_TMPDIR/live-check"
  mkdir -p "$tmp_dir"
  zellij() { echo "zellij 1.0.0"; }
  export -f zellij
  omawsl_orphan_tool_version_latest() { echo "2.0.0"; }
  export -f omawsl_orphan_tool_version_latest
  run omawsl_orphan_tools_live_check "$tmp_dir" 5 zellij
  [ "$status" -eq 0 ]
  [[ "$output" == *"current: 1.0.0"* ]]
  [[ "$output" == *"latest: 2.0.0"* ]]
}
