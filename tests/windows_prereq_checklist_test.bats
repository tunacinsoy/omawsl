#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

@test "with nothing to show, returns immediately without prompting" {
  run bash -c '
    source "'"$REPO_ROOT"'/install/lib.sh"
    source "'"$REPO_ROOT"'/install/windows-prereq-checklist.sh"
    omawsl_windows_prereq_checklist
  ' < /dev/null
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "with an item to show, declining exits 0 without continuing" {
  run bash -c '
    source "'"$REPO_ROOT"'/install/lib.sh"
    source "'"$REPO_ROOT"'/install/windows-prereq-checklist.sh"
    omawsl_windows_checklist_items() { echo "  - VS Code - install it first"; }
    omawsl_windows_prereq_checklist
    echo "SHOULD_NOT_REACH_HERE"
  ' <<< "n"
  [ "$status" -eq 0 ]
  [[ "$output" == *"We RECOMMEND stopping here"* ]]
  [[ "$output" == *"Exiting - nothing has been installed yet"* ]]
  [[ "$output" != *"SHOULD_NOT_REACH_HERE"* ]]
}

@test "with an item to show, answering yes continues past the prompt" {
  run bash -c '
    source "'"$REPO_ROOT"'/install/lib.sh"
    source "'"$REPO_ROOT"'/install/windows-prereq-checklist.sh"
    omawsl_windows_checklist_items() { echo "  - VS Code - install it first"; }
    omawsl_windows_prereq_checklist
    echo "REACHED_AFTER_CHECKLIST"
  ' <<< "y"
  [ "$status" -eq 0 ]
  [[ "$output" == *"REACHED_AFTER_CHECKLIST"* ]]
}

@test "real checklist: shows a Docker Desktop item when chosen and docker isn't reachable" {
  run bash -c '
    source "'"$REPO_ROOT"'/install/lib.sh"
    source "'"$REPO_ROOT"'/install/windows-prereq-checklist.sh"
    export OMAWSL_DOCKER_MODE="Docker Desktop for Windows"
    export PATH=/nonexistent
    omawsl_windows_checklist_items
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"Docker Desktop"* ]]
  [[ "$output" == *"docs/windows-setup.md#docker-desktop"* ]]
}

@test "real checklist: shows nothing when Docker Desktop was chosen but docker is already reachable" {
  run bash -c '
    source "'"$REPO_ROOT"'/install/lib.sh"
    source "'"$REPO_ROOT"'/install/windows-prereq-checklist.sh"
    export OMAWSL_DOCKER_MODE="Docker Desktop for Windows"
    docker() { :; }
    export -f docker
    omawsl_windows_checklist_items
  '
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "real checklist: shows nothing when Engine-only mode was chosen" {
  run bash -c '
    source "'"$REPO_ROOT"'/install/lib.sh"
    source "'"$REPO_ROOT"'/install/windows-prereq-checklist.sh"
    export OMAWSL_DOCKER_MODE="Docker Engine only, inside WSL (recommended)"
    export PATH=/nonexistent
    omawsl_windows_checklist_items
  '
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "real checklist: shows a VS Code item when chosen and code isn't reachable" {
  run bash -c '
    source "'"$REPO_ROOT"'/install/lib.sh"
    source "'"$REPO_ROOT"'/install/windows-prereq-checklist.sh"
    export OMAWSL_EDITORS="VS Code"
    export PATH=/nonexistent
    omawsl_windows_checklist_items
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"VS Code"* ]]
  [[ "$output" == *"docs/windows-setup.md#vscode"* ]]
}

@test "real checklist: shows nothing for VS Code when code is already reachable" {
  run bash -c '
    source "'"$REPO_ROOT"'/install/lib.sh"
    source "'"$REPO_ROOT"'/install/windows-prereq-checklist.sh"
    export OMAWSL_EDITORS="VS Code"
    code() { :; }
    export -f code
    omawsl_windows_checklist_items
  '
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "real checklist: shows a Cursor item when chosen and cursor isn't reachable" {
  run bash -c '
    source "'"$REPO_ROOT"'/install/lib.sh"
    source "'"$REPO_ROOT"'/install/windows-prereq-checklist.sh"
    export OMAWSL_EDITORS="Cursor"
    export PATH=/nonexistent
    omawsl_windows_checklist_items
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"Cursor"* ]]
  [[ "$output" == *"docs/windows-setup.md#cursor"* ]]
}

@test "real checklist: shows nothing when neither VS Code nor Cursor was chosen" {
  run bash -c '
    source "'"$REPO_ROOT"'/install/lib.sh"
    source "'"$REPO_ROOT"'/install/windows-prereq-checklist.sh"
    export OMAWSL_EDITORS="Neovim"
    export PATH=/nonexistent
    omawsl_windows_checklist_items
  '
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
