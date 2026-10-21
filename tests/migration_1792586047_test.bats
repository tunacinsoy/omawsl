#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  export OMAWSL_TERRAFORM_APT_SOURCES_FILE="$BATS_TEST_TMPDIR/hashicorp.list"
  stub_command sudo
  stub_command curl
}

@test "downloads HashiCorp's current key into the keyring its apt source names (issue #54)" {
  echo "deb [arch=amd64 signed-by=$BATS_TEST_TMPDIR/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com noble main" > "$OMAWSL_TERRAFORM_APT_SOURCES_FILE"
  run bash "$REPO_ROOT/migrations/1792586047.sh"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"curl -fsSL https://apt.releases.hashicorp.com/gpg"* ]]
  [[ "$(stub_calls)" == *"sudo gpg --yes --dearmor -o $BATS_TEST_TMPDIR/keyrings/hashicorp.gpg"* ]]
}

@test "also refreshes a keyring HashiCorp's own setup steps named" {
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com noble main" > "$OMAWSL_TERRAFORM_APT_SOURCES_FILE"
  run bash "$REPO_ROOT/migrations/1792586047.sh"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"sudo gpg --yes --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg"* ]]
}

@test "no-ops cleanly when HashiCorp's apt repo isn't set up" {
  run bash "$REPO_ROOT/migrations/1792586047.sh"
  [ "$status" -eq 0 ]
  [ -z "$(stub_calls)" ]
}

@test "no-ops when the apt source names no keyring" {
  echo "deb https://apt.releases.hashicorp.com noble main" > "$OMAWSL_TERRAFORM_APT_SOURCES_FILE"
  run bash "$REPO_ROOT/migrations/1792586047.sh"
  [ "$status" -eq 0 ]
  [ -z "$(stub_calls)" ]
}

@test "exits non-zero when the download fails, so migrate.sh retries it on the next run" {
  echo "deb [signed-by=$BATS_TEST_TMPDIR/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com noble main" > "$OMAWSL_TERRAFORM_APT_SOURCES_FILE"
  stub_command curl 1
  run bash "$REPO_ROOT/migrations/1792586047.sh"
  [ "$status" -ne 0 ]
}
