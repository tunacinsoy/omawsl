#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  gum_stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  export OMAWSL_STATE_DIR="$BATS_TEST_TMPDIR/state"
  mkdir -p "$HOME"
  stub_command sudo
  stub_command git
}

@test "runs the full install end to end and writes version state" {
  gum_stub_respond "Personal / unrestricted"
  gum_stub_respond "Docker Engine only, inside WSL (recommended)"
  gum_stub_respond ""
  gum_stub_respond ""
  gum_stub_respond ""
  gum_stub_respond "Ada Lovelace"
  gum_stub_respond "ada@example.com"

  run bash "$REPO_ROOT/install.sh"

  [ "$status" -eq 0 ]
  [[ "$output" == *"install complete"* ]]
  [ -f "$HOME/.bashrc" ]
  [ -f "$HOME/.inputrc" ]
  [ -f "$OMAWSL_STATE_DIR/version" ]
  [ "$(cat "$OMAWSL_STATE_DIR/version")" = "$(cat "$REPO_ROOT/version")" ]
  [ -f "$OMAWSL_STATE_DIR/choices.env" ]
  grep -q '^OMAWSL_NETWORK_MODE="Personal / unrestricted"$' "$OMAWSL_STATE_DIR/choices.env"
  grep -q '^OMAWSL_LANGUAGES=""$' "$OMAWSL_STATE_DIR/choices.env"
}

@test "declining the Windows prereq checklist would exit before installing - not exercised here since this phase has nothing to show" {
  # This phase's omawsl_windows_checklist_items is always empty, so the
  # checklist never actually prompts (Task 6). This test documents that
  # expectation explicitly so a later phase that adds a real checklist item
  # doesn't silently break this "no prompt appears" assumption without
  # someone noticing.
  gum_stub_respond "Personal / unrestricted"
  gum_stub_respond "Docker Engine only, inside WSL (recommended)"
  gum_stub_respond ""
  gum_stub_respond ""
  gum_stub_respond ""
  gum_stub_respond "Ada Lovelace"
  gum_stub_respond "ada@example.com"

  run bash -c "echo '' | bash '$REPO_ROOT/install.sh'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"install complete"* ]]
}
