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

@test "aborts when the user declines the confirmation prompt" {
  unset OMAWSL_ASSUME_YES
  run bash -c 'echo n | bash "'"$REPO_ROOT"'/boot.sh"'
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
