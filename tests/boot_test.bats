#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  export OMAWSL_HOME="$HOME/.local/share/omawsl"
  export OMAWSL_ASSUME_YES=1
  mkdir -p "$HOME"
  stub_command sudo

  # git stub that also fabricates a runnable install.sh on `clone`, so the
  # final `exec install.sh` has something real (if fake) to exec into.
  git() {
    echo "git $*" >> "$STUB_LOG"
    if [[ "$1" == "clone" ]]; then
      mkdir -p "$3"
      printf '#!/usr/bin/env bash\necho "FAKE_INSTALL_SH_RAN"\n' > "$3/install.sh"
      chmod +x "$3/install.sh"
    fi
  }
  export -f git
}

@test "clones into OMAWSL_HOME when it does not exist yet, then execs install.sh" {
  run bash "$REPO_ROOT/boot.sh"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"git clone https://github.com/tunacinsoy/omawsl $OMAWSL_HOME"* ]]
  [[ "$output" == *"FAKE_INSTALL_SH_RAN"* ]]
}

@test "pulls instead of re-cloning when OMAWSL_HOME already has a checkout" {
  mkdir -p "$OMAWSL_HOME/.git"
  printf '#!/usr/bin/env bash\necho "FAKE_INSTALL_SH_RAN"\n' > "$OMAWSL_HOME/install.sh"
  chmod +x "$OMAWSL_HOME/install.sh"

  run bash "$REPO_ROOT/boot.sh"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"git -C $OMAWSL_HOME pull"* ]]
  [[ "$(stub_calls)" != *"git clone"* ]]
  [[ "$output" == *"FAKE_INSTALL_SH_RAN"* ]]
}

@test "checks out OMAWSL_REF when set to something other than master" {
  export OMAWSL_REF="v0.2.0"
  run bash "$REPO_ROOT/boot.sh"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"git -C $OMAWSL_HOME checkout v0.2.0"* ]]
}

@test "runs correctly when piped through stdin, the same way curl -fsSL ... | bash invokes it" {
  # Regression test: `bash boot.sh` (every other test in this file) always
  # gives bash a real file path, so BASH_SOURCE[0] is populated. The
  # documented one-liner (README.md) instead pipes the script's TEXT into
  # bash via stdin - bash then has no source file at all, so BASH_SOURCE is
  # a zero-element array and `${BASH_SOURCE[0]}` is a genuinely unbound
  # reference under `set -u`, aborting before omawsl_boot ever runs.
  run bash -c 'cat "'"$REPO_ROOT"'/boot.sh" | bash'
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"git clone https://github.com/tunacinsoy/omawsl $OMAWSL_HOME"* ]]
  [[ "$output" == *"FAKE_INSTALL_SH_RAN"* ]]
}

@test "does not accept the confirmation from piped stdin - only a real terminal or OMAWSL_ASSUME_YES counts" {
  # Regression test for the /dev/tty fix: under the real `curl | bash`
  # one-liner, stdin is the SCRIPT ITSELF being fed to bash, not the
  # user's real keystrokes - so treating stdin as the confirmation source
  # (the pre-fix behavior) is fundamentally wrong, even though it happens
  # to "work" when a test pipes a literal "y" into a directly-run
  # `bash boot.sh`. setsid detaches this subprocess from any controlling
  # terminal, so `read < /dev/tty` genuinely fails here (confirmed safe,
  # non-hanging: `read` opening a nonexistent /dev/tty fails immediately
  # with ENXIO, caught by the `|| true` already in boot.sh) - proving the
  # fix ignores stdin's "y" entirely rather than accepting it.
  unset OMAWSL_ASSUME_YES
  run setsid bash -c 'echo y | bash "'"$REPO_ROOT"'/boot.sh"'
  [ "$status" -eq 1 ]
  [[ "$output" == *"Aborted"* ]]
  [[ "$(stub_calls)" != *"git clone"* ]]
  [[ "$(stub_calls)" != *"apt-get"* ]]
}

@test "aborts gracefully (not a hang or crash) when no controlling terminal is available at all" {
  unset OMAWSL_ASSUME_YES
  run setsid bash -c 'bash "'"$REPO_ROOT"'/boot.sh" < /dev/null'
  [ "$status" -eq 1 ]
  [[ "$output" == *"Aborted"* ]]
  [[ "$(stub_calls)" != *"git clone"* ]]
  [[ "$(stub_calls)" != *"apt-get"* ]]
}

@test "shows a clear troubleshooting message and exits when the clone fails" {
  git() {
    echo "git $*" >> "$STUB_LOG"
    if [[ "$1" == "clone" ]]; then
      return 1
    fi
  }
  export -f git

  run bash "$REPO_ROOT/boot.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"couldn't reach the omawsl repository"* ]]
  [[ "$output" == *"corporate/restricted network"* ]]
  [[ "$output" != *"FAKE_INSTALL_SH_RAN"* ]]
}

@test "shows a clear troubleshooting message and exits when the pull fails" {
  mkdir -p "$OMAWSL_HOME/.git"

  git() {
    echo "git $*" >> "$STUB_LOG"
    if [[ "$1" == "-C" && "$3" == "pull" ]]; then
      return 1
    fi
  }
  export -f git

  run bash "$REPO_ROOT/boot.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"couldn't reach the omawsl repository"* ]]
  [[ "$output" == *"corporate/restricted network"* ]]
  [[ "$output" != *"FAKE_INSTALL_SH_RAN"* ]]
}
