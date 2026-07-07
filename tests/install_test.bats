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
  stub_command mise
  stub_command gem
  # This WSL instance has real docker-ce and real terraform installed on
  # it (from real Task 6/7 verification runs on earlier phases) - hide
  # them (and az, pre-emptively) so `command -v <tool>` behaves the same
  # here as on a fresh instance, regardless of what's actually installed.
  # A fixed "safe" PATH list doesn't work (broke twice already: Docker
  # Desktop's /mnt/c/... interop, then a real docker-ce install); this
  # builds a shadow directory of symlinks to every other binary instead.
  stub_hide_command docker terraform az

  export OMAWSL_WSL_CONF_FILE="$BATS_TEST_TMPDIR/wsl.conf"
  printf '[boot]\nsystemd=true\n' > "$OMAWSL_WSL_CONF_FILE"
  export OMAWSL_DOCKER_APT_SOURCES_FILE="$BATS_TEST_TMPDIR/docker.list"
  export OMAWSL_DOCKER_APT_KEYRINGS_DIR="$BATS_TEST_TMPDIR/keyrings"
  # Pre-seed every third-party apt sources file this run could touch as
  # already-existing, so each one takes its "already configured" branch
  # and skips its curl|gpg / echo|tee repo-add pipes. Found during Phase
  # 2's Task 5: those pipes' stubbed sudo/curl/gpg exit near-instantly
  # without draining stdin (unlike the real commands), so when this whole
  # script runs as a freshly exec'd process the writer side can lose the
  # SIGPIPE race under pipefail (deterministic 141, not flaky). Every one
  # of these pipes already has dedicated, non-flaky coverage via a direct
  # in-process call in docker_test.bats/cloud_tools_test.bats, so this
  # loses no coverage.
  : > "$OMAWSL_DOCKER_APT_SOURCES_FILE"
  export OMAWSL_TERRAFORM_APT_SOURCES_FILE="$BATS_TEST_TMPDIR/hashicorp.list"
  export OMAWSL_TERRAFORM_APT_KEYRINGS_DIR="$BATS_TEST_TMPDIR/keyrings"
  : > "$OMAWSL_TERRAFORM_APT_SOURCES_FILE"
  export OMAWSL_AZURE_CLI_APT_SOURCES_FILE="$BATS_TEST_TMPDIR/azure-cli.list"
  export OMAWSL_AZURE_CLI_APT_KEYRINGS_DIR="$BATS_TEST_TMPDIR/keyrings"
  : > "$OMAWSL_AZURE_CLI_APT_SOURCES_FILE"
  export USER=testuser
}

@test "runs the full install end to end and writes version state" {
  gum_stub_respond "Personal / unrestricted"
  gum_stub_respond "Docker Engine only, inside WSL (recommended)"
  gum_stub_respond ""
  gum_stub_respond $'Go\nTerraform'
  gum_stub_respond ""
  gum_stub_respond "Ada Lovelace"
  gum_stub_respond "ada@example.com"

  run bash "$REPO_ROOT/install.sh"

  [ "$status" -eq 0 ]
  [[ "$output" == *"install complete"* ]]
  [[ "$output" == *"remember to open a new terminal"* ]]
  [ -f "$HOME/.bashrc" ]
  [ -f "$HOME/.inputrc" ]
  [ -f "$OMAWSL_STATE_DIR/version" ]
  [ "$(cat "$OMAWSL_STATE_DIR/version")" = "$(cat "$REPO_ROOT/version")" ]
  [ -f "$OMAWSL_STATE_DIR/choices.env" ]
  grep -q '^OMAWSL_NETWORK_MODE="Personal / unrestricted"$' "$OMAWSL_STATE_DIR/choices.env"
  grep -q '^OMAWSL_LANGUAGES="Go,Terraform"$' "$OMAWSL_STATE_DIR/choices.env"
  grep -q '^OMAWSL_STORAGE=""$' "$OMAWSL_STATE_DIR/choices.env"
  [[ "$(stub_calls)" == *"sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"* ]]
  [[ "$(stub_calls)" == *"mise use --global go@latest"* ]]
  [[ "$(stub_calls)" == *"sudo apt-get install -y terraform"* ]]
  [[ "$(stub_calls)" != *"azure-cli"* ]]
}

@test "choosing Docker Desktop surfaces the pre-install checklist, and declining exits before installing" {
  # Relies on `docker` not being reachable via `command -v docker` -
  # already handled by setup()'s stub_hide_command call above.
  gum_stub_respond "Personal / unrestricted"
  gum_stub_respond "Docker Desktop for Windows"
  gum_stub_respond ""
  gum_stub_respond ""
  gum_stub_respond ""
  gum_stub_respond "Ada Lovelace"
  gum_stub_respond "ada@example.com"

  run bash -c "echo n | bash '$REPO_ROOT/install.sh'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Docker Desktop"* ]]
  [[ "$output" == *"Exiting - nothing has been installed yet"* ]]
  [[ "$output" != *"install complete"* ]]
  [ ! -f "$HOME/.bashrc" ]
}
