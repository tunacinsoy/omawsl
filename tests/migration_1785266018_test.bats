#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
}

@test "appends the guarded source line to an old-style ~/.bashrc without removing its existing content" {
  printf '# omawsl bashrc - baseline dev environment configuration for WSL2 Ubuntu.\nsome old omawsl content\n' > "$HOME/.bashrc"
  run bash "$REPO_ROOT/migrations/1785266018.sh"
  [ "$status" -eq 0 ]
  grep -qF 'some old omawsl content' "$HOME/.bashrc"
  grep -qF '# >>> omawsl >>>' "$HOME/.bashrc"
  grep -qF "source \"$REPO_ROOT/configs/bashrc\"" "$HOME/.bashrc"
}

@test "leaves a hand-diverged ~/.bashrc alone and just appends the guarded source line" {
  printf 'export SOME_CORP_VAR=1\n' > "$HOME/.bashrc"
  run bash "$REPO_ROOT/migrations/1785266018.sh"
  [ "$status" -eq 0 ]
  grep -qF 'export SOME_CORP_VAR=1' "$HOME/.bashrc"
  grep -qF '# >>> omawsl >>>' "$HOME/.bashrc"
}

@test "no-ops cleanly when ~/.bashrc doesn't exist yet" {
  run bash "$REPO_ROOT/migrations/1785266018.sh"
  [ "$status" -eq 0 ]
  [ -f "$HOME/.bashrc" ]
  grep -qF '# >>> omawsl >>>' "$HOME/.bashrc"
}

@test "leaves an old-style ~/.inputrc completely untouched (never deletes it)" {
  printf '# omawsl inputrc - readline configuration for more usable bash history search.\nset show-all-if-ambiguous on\n' > "$HOME/.inputrc"
  run bash "$REPO_ROOT/migrations/1785266018.sh"
  [ "$status" -eq 0 ]
  [ -f "$HOME/.inputrc" ]
  [[ "$(cat "$HOME/.inputrc")" == $'# omawsl inputrc - readline configuration for more usable bash history search.\nset show-all-if-ambiguous on' ]]
}

@test "leaves a user's own non-omawsl ~/.inputrc completely untouched" {
  printf 'set editing-mode vi\n' > "$HOME/.inputrc"
  run bash "$REPO_ROOT/migrations/1785266018.sh"
  [ "$status" -eq 0 ]
  [ -f "$HOME/.inputrc" ]
  [[ "$(cat "$HOME/.inputrc")" == "set editing-mode vi" ]]
}

@test "prints an advisory about the old bashrc copy when ~/.bashrc starts with the omawsl banner" {
  printf '# omawsl bashrc - baseline dev environment configuration for WSL2 Ubuntu.\nsome old omawsl content\n' > "$HOME/.bashrc"
  run bash "$REPO_ROOT/migrations/1785266018.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"omawsl: ~/.bashrc still has a full copy of an older omawsl config"* ]]
}

@test "does not print the old-bashrc-copy advisory when ~/.bashrc has no omawsl banner" {
  printf 'export SOME_CORP_VAR=1\n' > "$HOME/.bashrc"
  run bash "$REPO_ROOT/migrations/1785266018.sh"
  [ "$status" -eq 0 ]
  [[ "$output" != *"omawsl: ~/.bashrc still has a full copy of an older omawsl config"* ]]
}
