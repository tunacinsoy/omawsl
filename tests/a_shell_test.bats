#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
}

@test "copies bashrc and inputrc into HOME" {
  run bash "$REPO_ROOT/install/terminal/a-shell.sh"
  [ "$status" -eq 0 ]
  [ -f "$HOME/.bashrc" ]
  [ -f "$HOME/.inputrc" ]
  diff "$HOME/.bashrc" "$REPO_ROOT/configs/bashrc"
  diff "$HOME/.inputrc" "$REPO_ROOT/configs/inputrc"
}

@test "re-running overwrites deterministically (idempotent)" {
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  echo "some line the user added by hand" >> "$HOME/.bashrc"
  run bash "$REPO_ROOT/install/terminal/a-shell.sh"
  [ "$status" -eq 0 ]
  diff "$HOME/.bashrc" "$REPO_ROOT/configs/bashrc"
}
