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
