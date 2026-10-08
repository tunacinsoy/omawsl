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

@test "omawsl_update still runs orphan-tools updates when omawsl_migrate fails" {
  local origin="$BATS_TEST_TMPDIR/origin.git"
  git init -q --bare "$origin"

  local seed="$BATS_TEST_TMPDIR/seed"
  git clone -q "$origin" "$seed"
  git -C "$seed" checkout -q -B master
  echo "1" > "$seed/version"
  git -C "$seed" add version
  git -C "$seed" commit -q -m init
  git -C "$seed" push -q origin master

  export OMAWSL_HOME="$BATS_TEST_TMPDIR/home-repo"
  git clone -q "$origin" "$OMAWSL_HOME"

  # Defense-in-depth check (see update.sh's own comment): even if a
  # migration failure somehow propagates as a hard non-zero return from
  # omawsl_migrate itself - despite migrate.sh's own contract to catch
  # that internally - omawsl_update must still reach the orphan-tools
  # phase instead of aborting the rest of the update.
  omawsl_migrate() { echo "migrate-called" >> "$STUB_LOG"; return 1; }
  export -f omawsl_migrate
  omawsl_orphan_tools_update() { echo "orphan-tools-update-called" >> "$STUB_LOG"; }
  export -f omawsl_orphan_tools_update

  run omawsl_update
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"migrate-called"* ]]
  [[ "$(stub_calls)" == *"orphan-tools-update-called"* ]]
  [[ "$output" == *"warning"*"migrate step failed"* ]]
}

# --- omawsl update --ref <branch>: test a branch on a real machine before
# merging it (docs/testing-changes.md) ---

# Builds a fake GitHub ($ORIGIN) with master and feat/xyz, clones it as
# the install ($OMAWSL_HOME, on master), and stubs the post-pull phases.
_install_with_feature_branch() {
  ORIGIN="$BATS_TEST_TMPDIR/origin.git"
  SEED="$BATS_TEST_TMPDIR/seed"
  git init -q --bare "$ORIGIN"
  git clone -q "$ORIGIN" "$SEED"
  git -C "$SEED" checkout -q -B master
  echo "master" > "$SEED/which"
  git -C "$SEED" add which
  git -C "$SEED" commit -q -m init
  git -C "$SEED" push -q origin master
  git -C "$SEED" checkout -q -b feat/xyz
  echo "feature" > "$SEED/which"
  git -C "$SEED" commit -q -am feature
  git -C "$SEED" push -q origin feat/xyz
  git -C "$SEED" checkout -q master

  export OMAWSL_HOME="$BATS_TEST_TMPDIR/home-repo"
  git clone -q "$ORIGIN" "$OMAWSL_HOME"

  omawsl_migrate() { echo "migrate-called" >> "$STUB_LOG"; }
  omawsl_orphan_tools_update() { echo "orphan-tools-update-called" >> "$STUB_LOG"; }
  export -f omawsl_migrate omawsl_orphan_tools_update
}

@test "omawsl update --ref switches the install to a pushed branch, then updates as usual" {
  _install_with_feature_branch
  run omawsl_update --ref feat/xyz
  [ "$status" -eq 0 ]
  [ "$(git -C "$OMAWSL_HOME" branch --show-current)" = "feat/xyz" ]
  [ "$(cat "$OMAWSL_HOME/which")" = "feature" ]
  [[ "$(stub_calls)" == *"migrate-called"* ]]
  [[ "$(stub_calls)" == *"orphan-tools-update-called"* ]]
}

@test "after --ref, a plain omawsl update keeps following that branch" {
  _install_with_feature_branch
  omawsl_update --ref feat/xyz >/dev/null
  git -C "$SEED" checkout -q feat/xyz
  echo "feature v2" > "$SEED/which"
  git -C "$SEED" commit -q -am "fix on the branch"
  git -C "$SEED" push -q origin feat/xyz
  run omawsl_update
  [ "$status" -eq 0 ]
  [ "$(cat "$OMAWSL_HOME/which")" = "feature v2" ]
}

@test "omawsl update reminds you when the machine is testing a branch" {
  _install_with_feature_branch
  run omawsl_update --ref feat/xyz
  [[ "$output" == *"testing 'feat/xyz'"*"omawsl update --ref master"* ]]
}

@test "--ref master goes back, and the reminder disappears" {
  _install_with_feature_branch
  omawsl_update --ref feat/xyz >/dev/null
  run omawsl_update --ref master
  [ "$status" -eq 0 ]
  [ "$(git -C "$OMAWSL_HOME" branch --show-current)" = "master" ]
  [ "$(cat "$OMAWSL_HOME/which")" = "master" ]
  [[ "$output" != *"testing '"* ]]
}

@test "--ref with a branch that isn't on GitHub changes nothing" {
  _install_with_feature_branch
  run omawsl_update --ref feat/not-pushed
  [ "$status" -ne 0 ]
  [[ "$output" == *"couldn't fetch 'feat/not-pushed'"*"is it pushed?"* ]]
  [ "$(git -C "$OMAWSL_HOME" branch --show-current)" = "master" ]
  [[ "$(stub_calls)" != *"migrate-called"* ]]
}

@test "--ref refuses to switch over local changes" {
  _install_with_feature_branch
  echo "hand edit" >> "$OMAWSL_HOME/which"
  run omawsl_update --ref feat/xyz
  [ "$status" -ne 0 ]
  [[ "$output" == *"local changes"* ]]
  [ "$(git -C "$OMAWSL_HOME" branch --show-current)" = "master" ]
}

@test "--ref without a branch name prints usage" {
  _install_with_feature_branch
  run omawsl_update --ref
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage: omawsl update [--ref <branch>]"* ]]
}

@test "bin/omawsl update passes --ref through" {
  _install_with_feature_branch
  run bash "$REPO_ROOT/bin/omawsl" update --ref feat/not-pushed
  [ "$status" -ne 0 ]
  [[ "$output" == *"couldn't fetch 'feat/not-pushed'"* ]]
}
