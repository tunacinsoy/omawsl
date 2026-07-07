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
  # Relies on `docker` not being reachable via `command -v docker`. Excluding
  # whole PATH directories doesn't work: /usr/bin and /bin (the latter
  # commonly a usrmerge symlink to the former) hold `bash` and every
  # coreutil this test also needs, alongside `docker` once this WSL
  # instance has docker-ce installed natively (a normal side effect of
  # running this very script for real). A fixed "safe" directory list
  # doesn't work either - it already broke once for Docker Desktop's
  # /mnt/c/... interop. Instead, build a shadow directory of symlinks to
  # every other binary from the standard system directories, skipping only
  # the literal name "docker" wherever it appears - deterministic
  # regardless of how many places or why `docker` is reachable here, while
  # leaving every other tool this test needs (bash, coreutils, uname, ...)
  # fully available.
  local shadow_dir="$BATS_TEST_TMPDIR/path-without-docker"
  mkdir -p "$shadow_dir"
  local sysdir f base
  for sysdir in /usr/local/sbin /usr/local/bin /usr/sbin /usr/bin /sbin /bin /usr/games /usr/local/games /usr/lib/wsl/lib; do
    [[ -d "$sysdir" ]] || continue
    for f in "$sysdir"/*; do
      [[ -e "$f" ]] || continue
      base="${f##*/}"
      [[ "$base" == "docker" ]] && continue
      [[ -e "$shadow_dir/$base" ]] && continue
      ln -s "$f" "$shadow_dir/$base" 2>/dev/null || true
    done
  done
  local restricted_path="$shadow_dir"

  gum_stub_respond "Personal / unrestricted"
  gum_stub_respond "Docker Desktop for Windows"
  gum_stub_respond ""
  gum_stub_respond ""
  gum_stub_respond ""
  gum_stub_respond "Ada Lovelace"
  gum_stub_respond "ada@example.com"

  run env PATH="$restricted_path" bash -c "echo n | bash '$REPO_ROOT/install.sh'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Docker Desktop"* ]]
  [[ "$output" == *"Exiting - nothing has been installed yet"* ]]
  [[ "$output" != *"install complete"* ]]
  [ ! -f "$HOME/.bashrc" ]
}
