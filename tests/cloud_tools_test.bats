#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/install/terminal/cloud-tools.sh"
  stub_command sudo
  stub_command gpg
  # This WSL instance has real terraform installed on it (from a real
  # Task 6 verification run) - hide it so `command -v terraform` behaves
  # the same on this machine as on a fresh one, regardless of what's
  # actually installed.
  stub_hide_command terraform
  # Same reason: this instance also has a real, already-configured
  # /etc/apt/sources.list.d/hashicorp.list. The omawsl_cloud_tools-level
  # tests below call the dispatcher with no explicit paths, which falls
  # back to the real system paths - override via env var so they always
  # see a fresh, non-existent sources file regardless of host state.
  export OMAWSL_TERRAFORM_APT_SOURCES_FILE="$BATS_TEST_TMPDIR/hashicorp-default.list"
  export OMAWSL_TERRAFORM_APT_KEYRINGS_DIR="$BATS_TEST_TMPDIR/keyrings-default"
}

# --- omawsl_install_terraform ------------------------------------------------

@test "terraform: installs via apt when not already present" {
  stub_command curl
  sources_file="$BATS_TEST_TMPDIR/hashicorp.list"
  keyrings_dir="$BATS_TEST_TMPDIR/keyrings"
  run omawsl_install_terraform "$sources_file" "$keyrings_dir"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"curl -fsSL https://apt.releases.hashicorp.com/gpg"* ]]
  # --yes: without it, gpg interactively prompts "File exists. Overwrite?"
  # whenever the keyring is already there from an earlier attempt (e.g.
  # a prior run that fetched the key but failed later) - confirmed on a
  # real WSL2 run, where this hung the whole non-interactive install.
  [[ "$(stub_calls)" == *"sudo gpg --yes --dearmor -o $keyrings_dir/hashicorp.gpg"* ]]
  [[ "$(stub_calls)" == *"sudo tee $sources_file"* ]]
  [[ "$(stub_calls)" == *"sudo apt-get install -y terraform"* ]]
}

@test "terraform: no-ops when already installed" {
  stub_command curl
  stub_command terraform
  run omawsl_install_terraform "$BATS_TEST_TMPDIR/hashicorp.list" "$BATS_TEST_TMPDIR/keyrings"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"curl"* ]]
}

@test "terraform: skips the repo-add step when the sources file already exists" {
  stub_command curl
  sources_file="$BATS_TEST_TMPDIR/hashicorp-existing.list"
  : > "$sources_file"
  run omawsl_install_terraform "$sources_file" "$BATS_TEST_TMPDIR/keyrings"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"curl"* ]]
  [[ "$(stub_calls)" == *"sudo apt-get install -y terraform"* ]]
}

@test "terraform: isolates a repo-add failure instead of aborting" {
  stub_command curl 1
  sources_file="$BATS_TEST_TMPDIR/hashicorp-fail.list"
  run omawsl_install_terraform "$sources_file" "$BATS_TEST_TMPDIR/keyrings"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Terraform install failed"* ]]
  [[ "$(stub_calls)" != *"apt-get install -y terraform"* ]]
}

@test "terraform: removes the sources file when apt-get itself fails, so a retry doesn't inherit a broken repo listing" {
  # Regression test: on a real WSL2 run, a failed Azure CLI repo-add left
  # a broken /etc/apt/sources.list.d/azure-cli.list behind (the repo
  # simply doesn't have a Release file for this Ubuntu codename yet) -
  # every LATER apt-get call in the same run then failed too (apt exits
  # nonzero when any configured repo errors), which aborted the entire
  # install.sh run under set -e inside the unrelated libraries.sh step.
  # sudo is overridden locally (not the generic stub_command) so "sudo rm"
  # forwards to a real rm - the sources file must actually disappear on
  # disk, not just have the log record an attempt.
  sudo() {
    echo "sudo $*" >> "$STUB_LOG"
    if [[ "$1" == "apt-get" ]]; then
      return 1
    fi
    if [[ "$1" == "rm" ]]; then
      shift
      command rm "$@"
      return $?
    fi
    return 0
  }
  export -f sudo
  sources_file="$BATS_TEST_TMPDIR/hashicorp-preexisting.list"
  : > "$sources_file"
  run omawsl_install_terraform "$sources_file" "$BATS_TEST_TMPDIR/keyrings"
  [ "$status" -eq 0 ]
  [ ! -f "$sources_file" ]
  [[ "$output" == *"Terraform install failed"* ]]
}

# --- omawsl_cloud_tools --------------------------------------------------------

@test "cloud_tools: installs terraform when selected" {
  stub_command curl
  export OMAWSL_LANGUAGES="Terraform"
  omawsl_cloud_tools
  [[ "$(stub_calls)" == *"apt-get install -y terraform"* ]]
}

@test "cloud_tools: selecting nothing installs nothing" {
  export OMAWSL_LANGUAGES="Go,Rust"
  omawsl_cloud_tools
  [[ "$(stub_calls)" != *"terraform"* ]]
}
