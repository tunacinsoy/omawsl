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

  export OMAWSL_WSL_CONF_FILE="$BATS_TEST_TMPDIR/wsl.conf"
  printf '[boot]\nsystemd=true\n' > "$OMAWSL_WSL_CONF_FILE"
  export OMAWSL_DOCKER_APT_SOURCES_FILE="$BATS_TEST_TMPDIR/docker.list"
  export OMAWSL_DOCKER_APT_KEYRINGS_DIR="$BATS_TEST_TMPDIR/keyrings"
  # Pre-seed the apt sources file as already-existing so
  # omawsl_install_docker_ce takes its "already configured" branch and
  # skips the curl|gpg / echo|tee repo-add pipes. Found during Task 5:
  # those pipes' stubbed sudo/curl/gpg exit near-instantly without
  # draining stdin (unlike the real commands), so when this whole script
  # runs as a freshly exec'd process the writer side can lose the SIGPIPE
  # race under pipefail (deterministic 141, not flaky). Both pipes already
  # have dedicated, non-flaky coverage via a direct in-process call in
  # docker_test.bats (tests 9-10), so this loses no coverage.
  : > "$OMAWSL_DOCKER_APT_SOURCES_FILE"
  export USER=testuser
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
  grep -q '^OMAWSL_STORAGE=""$' "$OMAWSL_STATE_DIR/choices.env"
  [[ "$(stub_calls)" == *"sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"* ]]
}

@test "choosing Docker Desktop surfaces the pre-install checklist, and declining exits before installing" {
  # Relies on `docker` not being reachable via `command -v docker`. On a
  # real WSL developer machine, Docker Desktop for Windows can make its
  # interop binary reachable through a WSL-injected /mnt/c/... PATH entry
  # (host state omawsl itself never adds), which would spuriously satisfy
  # `command -v docker` and mask this test's premise. Pin PATH to
  # genuine Linux-side system directories for this subprocess only, so the
  # result is deterministic regardless of what's on the ambient host PATH.
  gum_stub_respond "Personal / unrestricted"
  gum_stub_respond "Docker Desktop for Windows"
  gum_stub_respond ""
  gum_stub_respond ""
  gum_stub_respond ""
  gum_stub_respond "Ada Lovelace"
  gum_stub_respond "ada@example.com"

  run env PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/usr/lib/wsl/lib" bash -c "echo n | bash '$REPO_ROOT/install.sh'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Docker Desktop"* ]]
  [[ "$output" == *"Exiting - nothing has been installed yet"* ]]
  [[ "$output" != *"install complete"* ]]
  [ ! -f "$HOME/.bashrc" ]
}
