#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/bin/omawsl-sub/migrate.sh"
  source "$REPO_ROOT/bin/omawsl-sub/update.sh"
  git config --global user.email "test@example.com"
  git config --global user.name "Test"
}

@test "omawsl_update fails cleanly when OMAWSL_HOME has no git checkout" {
  export OMAWSL_HOME="$BATS_TEST_TMPDIR/not-a-repo"
  mkdir -p "$OMAWSL_HOME"
  run omawsl_update
  [ "$status" -ne 0 ]
  [[ "$output" == *"no checkout found"* ]]
}

@test "omawsl_update refuses to pull over local changes" {
  export OMAWSL_HOME="$BATS_TEST_TMPDIR/home-repo"
  mkdir -p "$OMAWSL_HOME"
  git -C "$OMAWSL_HOME" init -q
  echo "1" > "$OMAWSL_HOME/version"
  git -C "$OMAWSL_HOME" add version
  git -C "$OMAWSL_HOME" commit -q -m init
  echo "dirty" >> "$OMAWSL_HOME/version"

  run omawsl_update
  [ "$status" -ne 0 ]
  [[ "$output" == *"local changes"* ]]
}

@test "omawsl_update pulls a clean checkout and runs migrate" {
  local origin="$BATS_TEST_TMPDIR/origin.git"
  git init -q --bare "$origin"

  local seed="$BATS_TEST_TMPDIR/seed"
  git clone -q "$origin" "$seed"
  # $origin is empty at clone time, so $seed's initial branch name comes
  # from this machine's own init.defaultBranch config, not from $origin -
  # pin it explicitly so the push/pull below don't depend on that setting
  # (increasingly "main" by default on newer git installs).
  git -C "$seed" checkout -q -B master
  echo "1" > "$seed/version"
  git -C "$seed" add version
  git -C "$seed" commit -q -m init
  git -C "$seed" push -q origin master

  export OMAWSL_HOME="$BATS_TEST_TMPDIR/home-repo"
  git clone -q "$origin" "$OMAWSL_HOME"

  echo "2" > "$seed/version"
  git -C "$seed" add version
  git -C "$seed" commit -q -m "bump version"
  git -C "$seed" push -q origin master

  omawsl_migrate() { echo "migrate-called" >> "$STUB_LOG"; }
  export -f omawsl_migrate
  # omawsl_update also calls the real omawsl_orphan_tools_update after
  # migrate (bin/omawsl-sub/update.sh) - left unstubbed, this test was
  # exercising the real version-check/update flow against whatever AI
  # CLIs happen to be installed on the machine running it, including real
  # network calls. Found by tracing a real hang: `mise exec node@lts --
  # codex --version` landed in an uninterruptible kernel sleep (ps STAT
  # "D"), which no in-process timeout can preempt, wedging this one test
  # (and the whole suite behind it) indefinitely. Stub it so this test
  # only exercises what it's named for: pull + migrate dispatch.
  omawsl_orphan_tools_update() { echo "orphan-tools-update-called" >> "$STUB_LOG"; }
  export -f omawsl_orphan_tools_update

  run omawsl_update
  [ "$status" -eq 0 ]
  [ "$(cat "$OMAWSL_HOME/version")" = "2" ]
  [[ "$(stub_calls)" == *"migrate-called"* ]]
  [[ "$(stub_calls)" == *"orphan-tools-update-called"* ]]
  [[ "$output" == *"update complete"* ]]
}
