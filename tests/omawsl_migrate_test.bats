#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  export OMAWSL_STATE_DIR="$BATS_TEST_TMPDIR/state"
  mkdir -p "$HOME"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/bin/omawsl-sub/migrate.sh"
}

@test "omawsl_migrate reports up to date when no migrations directory exists" {
  export OMAWSL_MIGRATIONS_DIR="$BATS_TEST_TMPDIR/no-such-dir"
  export OMAWSL_VERSION_FILE="$BATS_TEST_TMPDIR/version"
  echo 0 > "$OMAWSL_VERSION_FILE"
  run omawsl_migrate
  [ "$status" -eq 0 ]
  [[ "$output" == *"up to date"* ]]
}

@test "omawsl_migrate runs every migration newer than the recorded state, in order" {
  local migrations="$BATS_TEST_TMPDIR/migrations"
  mkdir -p "$migrations"
  echo 'echo "ran-100" >> "$STUB_LOG"' > "$migrations/100.sh"
  echo 'echo "ran-200" >> "$STUB_LOG"' > "$migrations/200.sh"
  export OMAWSL_MIGRATIONS_DIR="$migrations"
  export OMAWSL_VERSION_FILE="$BATS_TEST_TMPDIR/version"
  echo 50 > "$OMAWSL_VERSION_FILE"
  mkdir -p "$OMAWSL_STATE_DIR"
  echo 50 > "$OMAWSL_STATE_DIR/version"

  run omawsl_migrate
  [ "$status" -eq 0 ]
  local calls; calls="$(cat "$STUB_LOG")"
  [[ "$calls" == *"ran-100"* ]]
  [[ "$calls" == *"ran-200"* ]]
  [ "$(cat "$OMAWSL_STATE_DIR/version")" = "200" ]
}

@test "omawsl_migrate warns and stops at a failing migration, without recording it or running later ones" {
  local migrations="$BATS_TEST_TMPDIR/migrations"
  mkdir -p "$migrations"
  echo 'echo "ran-100" >> "$STUB_LOG"; exit 1' > "$migrations/100.sh"
  echo 'echo "ran-200" >> "$STUB_LOG"' > "$migrations/200.sh"
  export OMAWSL_MIGRATIONS_DIR="$migrations"
  export OMAWSL_VERSION_FILE="$BATS_TEST_TMPDIR/version"
  echo 200 > "$OMAWSL_VERSION_FILE"
  mkdir -p "$OMAWSL_STATE_DIR"
  echo 50 > "$OMAWSL_STATE_DIR/version"

  # Must not propagate as a hard failure: bin/omawsl-sub/update.sh calls
  # this before omawsl_orphan_tools_update, and one migration failing
  # shouldn't block unrelated orphan-tool updates from still running.
  run omawsl_migrate
  [ "$status" -eq 0 ]
  [[ "$output" == *"warning"*"migration 100 failed"* ]]
  local calls; calls="$(cat "$STUB_LOG")"
  [[ "$calls" == *"ran-100"* ]]
  [[ "$calls" != *"ran-200"* ]]
  # State stays at 50, not 100 - so the failed migration is retried (not
  # skipped as already-done) on the next 'omawsl migrate' run.
  [ "$(cat "$OMAWSL_STATE_DIR/version")" = "50" ]
}

@test "omawsl_migrate skips migrations already covered by the recorded state" {
  local migrations="$BATS_TEST_TMPDIR/migrations"
  mkdir -p "$migrations"
  echo 'echo "ran-100" >> "$STUB_LOG"' > "$migrations/100.sh"
  export OMAWSL_MIGRATIONS_DIR="$migrations"
  export OMAWSL_VERSION_FILE="$BATS_TEST_TMPDIR/version"
  echo 100 > "$OMAWSL_VERSION_FILE"
  mkdir -p "$OMAWSL_STATE_DIR"
  echo 100 > "$OMAWSL_STATE_DIR/version"

  run omawsl_migrate
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"ran-100"* ]]
  [[ "$output" == *"up to date"* ]]
}

@test "omawsl_migrate bumps state to the repo version even with zero pending migrations" {
  export OMAWSL_MIGRATIONS_DIR="$BATS_TEST_TMPDIR/empty-migrations"
  mkdir -p "$OMAWSL_MIGRATIONS_DIR"
  export OMAWSL_VERSION_FILE="$BATS_TEST_TMPDIR/version"
  echo 999 > "$OMAWSL_VERSION_FILE"
  mkdir -p "$OMAWSL_STATE_DIR"
  echo 500 > "$OMAWSL_STATE_DIR/version"

  run omawsl_migrate
  [ "$status" -eq 0 ]
  [ "$(cat "$OMAWSL_STATE_DIR/version")" = "999" ]
}
