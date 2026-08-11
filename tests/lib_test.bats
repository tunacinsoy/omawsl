#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  gum_stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  source "$REPO_ROOT/install/lib.sh"
}

@test "omawsl_version_ge: greater major version" {
  run omawsl_version_ge "26.04" "24.04"
  [ "$status" -eq 0 ]
}

@test "omawsl_version_ge: equal version" {
  run omawsl_version_ge "24.04" "24.04"
  [ "$status" -eq 0 ]
}

@test "omawsl_version_ge: greater minor, same major" {
  run omawsl_version_ge "24.10" "24.04"
  [ "$status" -eq 0 ]
}

@test "omawsl_version_ge: lesser major version" {
  run omawsl_version_ge "22.04" "24.04"
  [ "$status" -eq 1 ]
}

@test "omawsl_version_ge: lesser minor, same major" {
  run omawsl_version_ge "24.02" "24.04"
  [ "$status" -eq 1 ]
}

@test "omawsl_list_has: item present" {
  run omawsl_list_has "Go,Python,Rust" "Go"
  [ "$status" -eq 0 ]
}

@test "omawsl_list_has: item absent" {
  run omawsl_list_has "Go,Python,Rust" "Java"
  [ "$status" -eq 1 ]
}

@test "omawsl_list_has: does not match as a bare substring" {
  run omawsl_list_has "GoLang,Python" "Go"
  [ "$status" -eq 1 ]
}

@test "omawsl_list_has: empty list never matches" {
  run omawsl_list_has "" "Go"
  [ "$status" -eq 1 ]
}

@test "omawsl_is_wsl2_kernel: real WSL2 kernel string matches" {
  run omawsl_is_wsl2_kernel "6.18.33.2-microsoft-standard-WSL2"
  [ "$status" -eq 0 ]
}

@test "omawsl_is_wsl2_kernel: WSL1-style kernel string does not match" {
  run omawsl_is_wsl2_kernel "4.4.0-19041-Microsoft"
  [ "$status" -eq 1 ]
}

@test "omawsl_is_wsl2_kernel: bare Linux kernel string does not match" {
  run omawsl_is_wsl2_kernel "5.4.0-91-generic"
  [ "$status" -eq 1 ]
}

@test "omawsl_save_choice + omawsl_load_choice: round-trips a value" {
  export OMAWSL_STATE_DIR="$BATS_TEST_TMPDIR/state"
  omawsl_save_choice OMAWSL_LANGUAGES "Go,Python"
  run omawsl_load_choice OMAWSL_LANGUAGES
  [ "$status" -eq 0 ]
  [ "$output" = "Go,Python" ]
}

@test "omawsl_save_choice: overwrites a prior value for the same key" {
  export OMAWSL_STATE_DIR="$BATS_TEST_TMPDIR/state"
  omawsl_save_choice OMAWSL_LANGUAGES "Go"
  omawsl_save_choice OMAWSL_LANGUAGES "Go,Rust"
  run omawsl_load_choice OMAWSL_LANGUAGES
  [ "$output" = "Go,Rust" ]
  [ "$(grep -c '^OMAWSL_LANGUAGES=' "$OMAWSL_STATE_DIR/choices.env")" -eq 1 ]
}

@test "omawsl_save_choice: two different keys are both loadable independently" {
  export OMAWSL_STATE_DIR="$BATS_TEST_TMPDIR/state"
  omawsl_save_choice OMAWSL_LANGUAGES "Go"
  omawsl_save_choice OMAWSL_STORAGE "MySQL"
  run omawsl_load_choice OMAWSL_LANGUAGES
  [ "$output" = "Go" ]
  run omawsl_load_choice OMAWSL_STORAGE
  [ "$output" = "MySQL" ]
}

@test "omawsl_load_choice: unset key returns empty string" {
  export OMAWSL_STATE_DIR="$BATS_TEST_TMPDIR/state"
  run omawsl_load_choice OMAWSL_NEVER_SET
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "omawsl_save_choice + omawsl_load_choice: round-trips a value containing quotes and backslashes without executing it" {
  export OMAWSL_STATE_DIR="$BATS_TEST_TMPDIR/state"
  omawsl_save_choice OMAWSL_USER_NAME 'O"Brien $(touch '"$BATS_TEST_TMPDIR"'/pwned) \done'
  run omawsl_load_choice OMAWSL_USER_NAME
  [ "$output" = 'O"Brien $(touch '"$BATS_TEST_TMPDIR"'/pwned) \done' ]
  [ ! -e "$BATS_TEST_TMPDIR/pwned" ]
}

@test "omawsl_docker_reachable: true when a docker command is present" {
  stub_command docker
  run omawsl_docker_reachable
  [ "$status" -eq 0 ]
}

@test "omawsl_docker_reachable: false when nothing named docker is on PATH" {
  run bash -c '
    export PATH=/nonexistent
    source "'"$REPO_ROOT"'/install/lib.sh"
    omawsl_docker_reachable
  '
  [ "$status" -eq 1 ]
}

@test "omawsl_docker_reachable: false when a docker command is on PATH but not functional" {
  # Docker Desktop drops a 'docker' shim onto every WSL distro's PATH, even
  # ones without WSL integration enabled - running it prints a friendly
  # "activate WSL integration" nudge instead of a real docker invocation, and
  # it exits non-zero. A bare `command -v docker` check can't tell this
  # apart from a genuinely working docker - confirmed as a real false
  # positive on a real machine (Docker Desktop installed, integration not
  # enabled for that distro): the stub satisfied `command -v`, so omawsl
  # believed docker was reachable and let later steps call `sudo docker ...`
  # directly, which then failed with a raw "command not found" instead of
  # omawsl's own graceful deferral message.
  stub_command docker 1
  run omawsl_docker_reachable
  [ "$status" -eq 1 ]
}

@test "omawsl_code_reachable: true when a code command is present" {
  stub_command code
  run omawsl_code_reachable
  [ "$status" -eq 0 ]
}

@test "omawsl_code_reachable: false when nothing named code is on PATH" {
  run bash -c '
    export PATH=/nonexistent
    source "'"$REPO_ROOT"'/install/lib.sh"
    omawsl_code_reachable
  '
  [ "$status" -eq 1 ]
}

@test "omawsl_cursor_reachable: true when a cursor command is present" {
  stub_command cursor
  run omawsl_cursor_reachable
  [ "$status" -eq 0 ]
}

@test "omawsl_cursor_reachable: false when nothing named cursor is on PATH" {
  run bash -c '
    export PATH=/nonexistent
    source "'"$REPO_ROOT"'/install/lib.sh"
    omawsl_cursor_reachable
  '
  [ "$status" -eq 1 ]
}

@test "omawsl_write_version_state copies the given root dir's version file into the state dir" {
  export OMAWSL_STATE_DIR="$BATS_TEST_TMPDIR/state"
  local root="$BATS_TEST_TMPDIR/root"
  mkdir -p "$root"
  echo "1234567890" > "$root/version"
  omawsl_write_version_state "$root"
  [ -f "$OMAWSL_STATE_DIR/version" ]
  [ "$(cat "$OMAWSL_STATE_DIR/version")" = "1234567890" ]
}

@test "omawsl_merge_csv unions two comma lists, deduplicated, a's order first" {
  [[ "$(omawsl_merge_csv "Go,Rust" "Python,Go")" == "Go,Rust,Python" ]]
}

@test "omawsl_merge_csv handles an empty existing list" {
  [[ "$(omawsl_merge_csv "" "Go,Rust")" == "Go,Rust" ]]
}

@test "omawsl_merge_csv handles an empty new list" {
  [[ "$(omawsl_merge_csv "Go,Rust" "")" == "Go,Rust" ]]
}

@test "omawsl_remove_from_csv removes one item, preserving order of the rest" {
  [[ "$(omawsl_remove_from_csv "Go,Rust,Python" "Rust")" == "Go,Python" ]]
}

@test "omawsl_remove_from_csv leaves the list unchanged when the item isn't present" {
  [[ "$(omawsl_remove_from_csv "Go,Rust" "Java")" == "Go,Rust" ]]
}

@test "omawsl_remove_from_csv removing the only item yields an empty string" {
  [[ "$(omawsl_remove_from_csv "Go" "Go")" == "" ]]
}

@test "omawsl_remove_from_csv handles an empty list" {
  [[ "$(omawsl_remove_from_csv "" "Go")" == "" ]]
}

@test "omawsl_remove_from_csv does not match as a bare substring" {
  [[ "$(omawsl_remove_from_csv "GoLang,Python" "Go")" == "GoLang,Python" ]]
}

@test "omawsl_ensure_bashrc_source_line: creates the file and appends the guarded source line when the file doesn't exist yet" {
  local bashrc="$BATS_TEST_TMPDIR/bashrc_missing"
  omawsl_ensure_bashrc_source_line "$bashrc" "$BATS_TEST_TMPDIR/configs/bashrc"
  [ -f "$bashrc" ]
  grep -qF '# >>> omawsl >>>' "$bashrc"
  grep -qF "[ -f \"$BATS_TEST_TMPDIR/configs/bashrc\" ] && source \"$BATS_TEST_TMPDIR/configs/bashrc\"" "$bashrc"
  grep -qF '# <<< omawsl <<<' "$bashrc"
}

@test "omawsl_ensure_bashrc_source_line: leaves pre-existing content untouched and appends after it" {
  local bashrc="$BATS_TEST_TMPDIR/bashrc_existing"
  printf 'export SOME_CORP_VAR=1\n' > "$bashrc"
  omawsl_ensure_bashrc_source_line "$bashrc" "$BATS_TEST_TMPDIR/configs/bashrc"
  grep -qF 'export SOME_CORP_VAR=1' "$bashrc"
  grep -qF '# >>> omawsl >>>' "$bashrc"
  [ "$(grep -c 'export SOME_CORP_VAR=1' "$bashrc")" -eq 1 ]
}

@test "omawsl_ensure_bashrc_source_line: re-running is idempotent, marker appears exactly once, hand-added lines survive" {
  local bashrc="$BATS_TEST_TMPDIR/bashrc_idempotent"
  omawsl_ensure_bashrc_source_line "$bashrc" "$BATS_TEST_TMPDIR/configs/bashrc"
  printf 'some line the user added by hand\n' >> "$bashrc"
  omawsl_ensure_bashrc_source_line "$bashrc" "$BATS_TEST_TMPDIR/configs/bashrc"
  [ "$(grep -c '# >>> omawsl >>>' "$bashrc")" -eq 1 ]
  grep -qF 'some line the user added by hand' "$bashrc"
}

@test "omawsl_prompt_copilot_autopilot_if_needed prompts and persists when Copilot CLI is newly picked" {
  export OMAWSL_STATE_DIR="$BATS_TEST_TMPDIR/state"
  gum_stub_respond "Yes - autopilot + allow-all"
  omawsl_prompt_copilot_autopilot_if_needed "GitHub Copilot CLI" ""
  run omawsl_load_choice OMAWSL_COPILOT_AUTOPILOT
  [ "$output" = "Yes - autopilot + allow-all" ]
  [[ "$(stub_calls)" == *"autopilot mode"* ]]
}

@test "omawsl_prompt_copilot_autopilot_if_needed does not prompt when Copilot CLI is not in the picked list" {
  export OMAWSL_STATE_DIR="$BATS_TEST_TMPDIR/state"
  omawsl_prompt_copilot_autopilot_if_needed "VS Code" ""
  run omawsl_load_choice OMAWSL_COPILOT_AUTOPILOT
  [ "$output" = "" ]
  [ -z "$(stub_calls)" ]
}

@test "omawsl_prompt_copilot_autopilot_if_needed does not re-prompt when Copilot CLI was already selected before" {
  export OMAWSL_STATE_DIR="$BATS_TEST_TMPDIR/state"
  omawsl_prompt_copilot_autopilot_if_needed "GitHub Copilot CLI" "GitHub Copilot CLI"
  run omawsl_load_choice OMAWSL_COPILOT_AUTOPILOT
  [ "$output" = "" ]
  [ -z "$(stub_calls)" ]
}

@test "omawsl_prompt_copilot_autopilot_if_needed does not re-prompt once an answer is already persisted" {
  export OMAWSL_STATE_DIR="$BATS_TEST_TMPDIR/state"
  omawsl_save_choice OMAWSL_COPILOT_AUTOPILOT "No - interactive by default (recommended)"
  omawsl_prompt_copilot_autopilot_if_needed "GitHub Copilot CLI" ""
  run omawsl_load_choice OMAWSL_COPILOT_AUTOPILOT
  [ "$output" = "No - interactive by default (recommended)" ]
  [ -z "$(stub_calls)" ]
}

@test "omawsl_prompt_copilot_autopilot_if_needed returns cleanly without persisting anything when the prompt is cancelled" {
  export OMAWSL_STATE_DIR="$BATS_TEST_TMPDIR/state"
  gum() { echo "gum $*" >> "$STUB_LOG"; return 1; }
  export -f gum
  run omawsl_prompt_copilot_autopilot_if_needed "GitHub Copilot CLI" ""
  [ "$status" -eq 0 ]
  run omawsl_load_choice OMAWSL_COPILOT_AUTOPILOT
  [ "$output" = "" ]
}

@test "omawsl_install_npm_cli_wrapper installs the package via mise and writes an executable wrapper" {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  stub_command mise
  run omawsl_install_npm_cli_wrapper tree-sitter-cli tree-sitter
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"mise exec node@lts -- npm install -g tree-sitter-cli"* ]]
  [ -x "$HOME/.local/bin/tree-sitter" ]
  [[ "$(cat "$HOME/.local/bin/tree-sitter")" == *"exec mise exec node@lts -- tree-sitter \"\$@\""* ]]
}

@test "omawsl_install_npm_cli_wrapper propagates a failed npm install instead of writing a wrapper" {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  stub_command mise 1
  run omawsl_install_npm_cli_wrapper tree-sitter-cli tree-sitter
  [ "$status" -ne 0 ]
  [ ! -f "$HOME/.local/bin/tree-sitter" ]
}
