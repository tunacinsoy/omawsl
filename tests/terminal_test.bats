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
  stub_command curl
  stub_command gpg

  # Pre-seed systemd=true so the Docker engine-mode step (§9) doesn't stop
  # this run early asking for a WSL restart - that early-exit path has its
  # own dedicated coverage in docker_test.bats.
  export OMAWSL_WSL_CONF_FILE="$BATS_TEST_TMPDIR/wsl.conf"
  printf '[boot]\nsystemd=true\n' > "$OMAWSL_WSL_CONF_FILE"
  export OMAWSL_DOCKER_APT_SOURCES_FILE="$BATS_TEST_TMPDIR/docker.list"
  export OMAWSL_DOCKER_APT_KEYRINGS_DIR="$BATS_TEST_TMPDIR/keyrings"

  # Pre-seed the apt sources file too, so omawsl_install_docker_ce takes its
  # already-configured branch and skips the repo-add step. That step pipes
  # a real `curl | sudo gpg` and `echo | sudo tee`, and with sudo/curl/gpg
  # replaced by no-op stub functions that don't read stdin, running it as a
  # freshly exec'd process (as this test does via `run bash terminal.sh`)
  # is subject to a SIGPIPE race: the stub reader on the right side of the
  # pipe returns and closes its end before the left side (which has to
  # spawn `dpkg --print-architecture` and source /etc/os-release first)
  # finishes and writes to it, killing the whole run with exit 141 under
  # `set -euo pipefail`. That repo-add branch already has its own dedicated,
  # non-flaky coverage in docker_test.bats, so it doesn't need to be
  # re-exercised here.
  : > "$OMAWSL_DOCKER_APT_SOURCES_FILE"
  export USER=testuser
}

@test "runs every terminal script in the documented fixed order" {
  gum_stub_respond "Ada Lovelace"
  gum_stub_respond "ada@example.com"

  run bash "$REPO_ROOT/install/terminal.sh"
  [ "$status" -eq 0 ]

  actual_order="$(echo "$output" | grep "^omawsl: running" | sed 's/^omawsl: running //')"
  expected_order="terminal/required/app-gum.sh
terminal/identification.sh
terminal/a-shell.sh
terminal/apps-terminal.sh
terminal/docker.sh
terminal/libraries.sh
terminal/mise.sh
terminal/select-dev-language.sh
terminal/cloud-tools.sh
terminal/select-dev-storage.sh"

  [ "$actual_order" = "$expected_order" ]
  [ -f "$HOME/.bashrc" ]
  [[ "$(stub_calls)" == *"apt-get install -y gum"* ]]
}
