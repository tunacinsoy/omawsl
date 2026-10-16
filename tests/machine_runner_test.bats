#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  source "$REPO_ROOT/tests/machine/run"
  export HOME="$BATS_TEST_TMPDIR/home"
  export OMAWSL_STATE_DIR="$HOME/.local/state/omawsl"
  export OMAWSL_MACHINE_WINDOWS_USERS="$BATS_TEST_TMPDIR/winusers"
  export OMAWSL_CMD_EXE_FALLBACK="$BATS_TEST_TMPDIR/no-such-cmd.exe"
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"
  export REAL_HOME_FOR_TEST="$HOME"
  mkdir -p "$HOME" "$TMPDIR"
  stub_command gh
}

# make_repo - a committed, pushed git repo for the runner to archive.
make_repo() {
  local origin="$BATS_TEST_TMPDIR/origin.git" repo="$BATS_TEST_TMPDIR/repo"
  git init -q --bare "$origin"
  git init -q -b main "$repo"
  echo hi > "$repo/README.md"
  mkdir -p "$repo/bin"
  echo 'echo "sandbox copy of omawsl $*"' > "$repo/bin/omawsl"
  git -C "$repo" add README.md bin/omawsl
  git -C "$repo" -c user.name=t -c user.email=t@t commit -q -m init
  git -C "$repo" remote add origin "$origin"
  git -C "$repo" push -q origin main
  export OMAWSL_MACHINE_REPO_ROOT="$repo"
}

# commit_file <path> <content> - adds a committed file to the make_repo repo.
commit_file() {
  mkdir -p "$(dirname "$OMAWSL_MACHINE_REPO_ROOT/$1")"
  printf '%s\n' "$2" > "$OMAWSL_MACHINE_REPO_ROOT/$1"
  git -C "$OMAWSL_MACHINE_REPO_ROOT" add "$1"
  git -C "$OMAWSL_MACHINE_REPO_ROOT" -c user.name=t -c user.email=t@t commit -q -m "add $1"
}

# check_file <name> <bats test body> - one machine check for the runner to run.
check_file() {
  export OMAWSL_MACHINE_CHECKS_DIR="$BATS_TEST_TMPDIR/checks"
  mkdir -p "$OMAWSL_MACHINE_CHECKS_DIR"
  printf '@test "%s" {\n%s\n}\n' "$1" "$2" > "$OMAWSL_MACHINE_CHECKS_DIR/$1.bats"
}

@test "fingerprint is stable when nothing changes, and copes with missing dirs" {
  run omawsl_machine_fingerprint
  [ "$status" -eq 0 ]
  local first="$output"
  run omawsl_machine_fingerprint
  [ "$output" = "$first" ]
}

@test "fingerprint changes when a dotfile in HOME changes" {
  echo a > "$HOME/.bashrc"
  local before; before="$(omawsl_machine_fingerprint)"
  echo ab > "$HOME/.bashrc"
  [ "$(omawsl_machine_fingerprint)" != "$before" ]
}

@test "fingerprint changes when a file appears under ~/.config" {
  mkdir -p "$HOME/.config/zellij"
  local before; before="$(omawsl_machine_fingerprint)"
  echo x > "$HOME/.config/zellij/config.kdl"
  [ "$(omawsl_machine_fingerprint)" != "$before" ]
}

@test "fingerprint ignores the install's .git directory" {
  mkdir -p "$HOME/.local/share/omawsl/.git"
  local before; before="$(omawsl_machine_fingerprint)"
  echo x > "$HOME/.local/share/omawsl/.git/index"
  [ "$(omawsl_machine_fingerprint)" = "$before" ]
}

@test "fingerprint covers Windows Terminal and VS Code settings" {
  local wt="$OMAWSL_MACHINE_WINDOWS_USERS/u/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState"
  local vs="$OMAWSL_MACHINE_WINDOWS_USERS/u/AppData/Roaming/Code/User"
  mkdir -p "$wt" "$vs"
  echo '{}' > "$wt/settings.json"; echo '{}' > "$vs/settings.json"
  local before; before="$(omawsl_machine_fingerprint)"
  [[ "$before" == *"$wt/settings.json"* ]]
  [[ "$before" == *"$vs/settings.json"* ]]
  echo '{"a":1}' > "$wt/settings.json"
  [ "$(omawsl_machine_fingerprint)" != "$before" ]
}

@test "sandbox PATH drops /mnt entries and puts the stub dir first" {
  PATH="/usr/bin:/mnt/c/Windows/System32:/bin:/mnt/c/Program Files/x" run omawsl_machine_sandbox_path /stubs
  [ "$output" = "/stubs:/usr/bin:/bin" ]
}

@test "sandbox holds only committed files, the real choices.env, and a failing sudo" {
  make_repo
  echo dirty > "$OMAWSL_MACHINE_REPO_ROOT/uncommitted.txt"
  mkdir -p "$OMAWSL_STATE_DIR"; echo 'OMAWSL_MULTIPLEXER="herdr"' > "$OMAWSL_STATE_DIR/choices.env"
  local sb="$BATS_TEST_TMPDIR/sb"
  omawsl_machine_make_sandbox "$sb" "$(git -C "$OMAWSL_MACHINE_REPO_ROOT" rev-parse HEAD)"
  [ -f "$sb/omawsl/README.md" ]
  [ ! -e "$sb/omawsl/uncommitted.txt" ]
  grep -q herdr "$sb/home/.local/state/omawsl/choices.env"
  run "$sb/bin/sudo" true
  [ "$status" -eq 1 ]
  [[ "$output" == *"not allowed"* ]]
}

@test "a passing run reports machine/personal for HEAD and removes the sandbox" {
  make_repo
  check_file sandboxed '
  [ "$HOME" != "$REAL_HOME_FOR_TEST" ]
  [ -f "$OMAWSL_MACHINE_ROOT/README.md" ]
  [ "$OMAWSL_HOME" = "$OMAWSL_MACHINE_ROOT" ]
  ! sudo true'
  local sha; sha="$(git -C "$OMAWSL_MACHINE_REPO_ROOT" rev-parse HEAD)"
  run omawsl_machine_main
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"gh api -X POST repos/{owner}/{repo}/statuses/$sha -f state=success -f context=machine/personal -f description=1 machine checks passed"* ]]
  [ -z "$(ls -A "$TMPDIR")" ]
}

@test "a failing check reports nothing and removes the sandbox" {
  make_repo
  check_file fails 'false'
  run omawsl_machine_main
  [ "$status" -eq 1 ]
  [[ "$output" == *"Nothing reported to GitHub"* ]]
  [[ "$(stub_calls)" != *"gh "* ]]
  [ -z "$(ls -A "$TMPDIR")" ]
}

@test "a check that changes the real machine fails the run, names the path, reports nothing" {
  make_repo
  check_file writes_home 'echo changed > "$REAL_HOME_FOR_TEST/.bashrc"'
  run omawsl_machine_main
  [ "$status" -eq 1 ]
  [[ "$output" == *"the real machine changed during the run"* ]]
  [[ "$output" == *"$HOME/.bashrc"* ]]
  [[ "$(stub_calls)" != *"gh "* ]]
}

@test "refuses to run with uncommitted changes" {
  make_repo
  check_file ok 'true'
  echo dirty > "$OMAWSL_MACHINE_REPO_ROOT/README.md"
  run omawsl_machine_main
  [ "$status" -eq 1 ]
  [[ "$output" == *"uncommitted changes"* ]]
  [[ "$(stub_calls)" != *"gh "* ]]
}

@test "refuses to report an unpushed HEAD" {
  make_repo
  check_file ok 'true'
  git -C "$OMAWSL_MACHINE_REPO_ROOT" -c user.name=t -c user.email=t@t commit -q --allow-empty -m local
  run omawsl_machine_main
  [ "$status" -eq 1 ]
  [[ "$output" == *"isn't pushed"* ]]
  [[ "$(stub_calls)" != *"gh "* ]]
}

@test "--no-report runs an unpushed HEAD and reports nothing" {
  make_repo
  check_file ok 'true'
  git -C "$OMAWSL_MACHINE_REPO_ROOT" -c user.name=t -c user.email=t@t commit -q --allow-empty -m local
  run omawsl_machine_main --no-report
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing sent to GitHub"* ]]
  [[ "$(stub_calls)" != *"gh "* ]]
}

@test "rejects unknown arguments" {
  run omawsl_machine_main --bogus
  [ "$status" -eq 2 ]
  [[ "$output" == *"Usage: tests/machine/run [--no-report]"* ]]
}

@test "fingerprint ignores dotfiles omawsl doesn't manage, like Claude Code's ~/.claude.json" {
  echo a > "$HOME/.claude.json"; echo a > "$HOME/.bash_history"
  local before; before="$(omawsl_machine_fingerprint)"
  echo ab > "$HOME/.claude.json"; echo ab > "$HOME/.bash_history"
  [ "$(omawsl_machine_fingerprint)" = "$before" ]
}

@test "fingerprint follows a symlinked ~/.bashrc to the real file" {
  mkdir -p "$BATS_TEST_TMPDIR/dotfiles"
  echo a > "$BATS_TEST_TMPDIR/dotfiles/bashrc"
  ln -s "$BATS_TEST_TMPDIR/dotfiles/bashrc" "$HOME/.bashrc"
  local before; before="$(omawsl_machine_fingerprint)"
  echo ab > "$BATS_TEST_TMPDIR/dotfiles/bashrc"
  [ "$(omawsl_machine_fingerprint)" != "$before" ]
}

@test "sandbox archives the given commit, not whatever HEAD has moved to since" {
  make_repo
  local sha; sha="$(git -C "$OMAWSL_MACHINE_REPO_ROOT" rev-parse HEAD)"
  commit_file README.md moved-on
  local sb="$BATS_TEST_TMPDIR/sb"
  omawsl_machine_make_sandbox "$sb" "$sha"
  [ "$(cat "$sb/omawsl/README.md")" = hi ]
}

@test "checks don't inherit the live Herdr or zellij session, or XDG dirs" {
  make_repo
  export HERDR_ENV=1 HERDR_SOCKET_PATH=/live.sock HERDR_PANE_ID=p1 ZELLIJ=0 ZELLIJ_SESSION_NAME=s
  export XDG_CONFIG_HOME=/real/config XDG_DATA_HOME=/real/data XDG_STATE_HOME=/real/state XDG_CACHE_HOME=/real/cache
  check_file isolated '
  [ -z "${HERDR_ENV:-}${HERDR_SOCKET_PATH:-}${HERDR_PANE_ID:-}" ]
  [ -z "${ZELLIJ:-}${ZELLIJ_SESSION_NAME:-}" ]
  [ -z "${XDG_CONFIG_HOME:-}${XDG_DATA_HOME:-}${XDG_STATE_HOME:-}${XDG_CACHE_HOME:-}" ]'
  run omawsl_machine_main --no-report
  [ "$status" -eq 0 ]
}

@test "omawsl on the checks' PATH runs the sandboxed copy, not the real install" {
  make_repo
  check_file own_omawsl '[ "$(omawsl doctor)" = "sandbox copy of omawsl doctor" ]'
  run omawsl_machine_main --no-report
  [ "$status" -eq 0 ]
}

@test "by default it runs the checks committed at HEAD, from the sandbox copy" {
  make_repo
  unset OMAWSL_MACHINE_CHECKS_DIR
  commit_file tests/machine/where.bats '@test "runs from the sandbox" {
  [[ "$BATS_TEST_FILENAME" == "$OMAWSL_MACHINE_ROOT"/* ]]
}'
  git -C "$OMAWSL_MACHINE_REPO_ROOT" push -q origin main
  run omawsl_machine_main
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"description=1 machine checks passed"* ]]
}
