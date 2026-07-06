#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/install/check-version.sh"
}

write_os_release() {
  cat > "$BATS_TEST_TMPDIR/os-release" <<EOF
ID=$1
VERSION_ID="$2"
EOF
}

@test "passes for Ubuntu 26.04, x86_64, WSL2" {
  write_os_release ubuntu 26.04
  run omawsl_check_version "$BATS_TEST_TMPDIR/os-release" "x86_64" "6.18.33.2-microsoft-standard-WSL2"
  [ "$status" -eq 0 ]
}

@test "passes for Ubuntu exactly at the 24.04 floor" {
  write_os_release ubuntu 24.04
  run omawsl_check_version "$BATS_TEST_TMPDIR/os-release" "x86_64" "6.18.33.2-microsoft-standard-WSL2"
  [ "$status" -eq 0 ]
}

@test "fails for Ubuntu below the 24.04 floor" {
  write_os_release ubuntu 22.04
  run omawsl_check_version "$BATS_TEST_TMPDIR/os-release" "x86_64" "6.18.33.2-microsoft-standard-WSL2"
  [ "$status" -eq 1 ]
  [[ "$output" == *"requires Ubuntu 24.04 or later"* ]]
}

@test "fails for a non-Ubuntu distro" {
  write_os_release debian 12
  run omawsl_check_version "$BATS_TEST_TMPDIR/os-release" "x86_64" "6.18.33.2-microsoft-standard-WSL2"
  [ "$status" -eq 1 ]
  [[ "$output" == *"only supports Ubuntu"* ]]
}

@test "fails for an unsupported architecture" {
  write_os_release ubuntu 26.04
  run omawsl_check_version "$BATS_TEST_TMPDIR/os-release" "i686" "6.18.33.2-microsoft-standard-WSL2"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unsupported architecture"* ]]
}

@test "fails on a WSL1-style kernel" {
  write_os_release ubuntu 26.04
  run omawsl_check_version "$BATS_TEST_TMPDIR/os-release" "x86_64" "4.4.0-19041-Microsoft"
  [ "$status" -eq 1 ]
  [[ "$output" == *"doesn't look like WSL2"* ]]
}

@test "fails when the os-release file is missing" {
  run omawsl_check_version "$BATS_TEST_TMPDIR/does-not-exist" "x86_64" "6.18.33.2-microsoft-standard-WSL2"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot find"* ]]
}

@test "with no arguments, passes against the real host (this test runs inside real WSL2 Ubuntu 26.04)" {
  run omawsl_check_version
  [ "$status" -eq 0 ]
}
