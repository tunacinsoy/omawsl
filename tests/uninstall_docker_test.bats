#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  export OMAWSL_STATE_DIR="$BATS_TEST_TMPDIR/state"
  mkdir -p "$HOME"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/uninstall/docker.sh"

  # Default docker stub that responds to rm/volume calls
  docker() {
    echo "docker $*" >> "$STUB_LOG"
  }
  export -f docker

  # sudo stub that forwards docker calls to docker()
  sudo() {
    echo "sudo $*" >> "$STUB_LOG"
    if [[ "$1" == "docker" ]]; then
      shift
      docker "$@"
    elif [[ "$1" == "rm" ]]; then
      # Actually remove the file for test verification
      shift
      rm "$@" || true
    fi
  }
  export -f sudo
}

@test "omawsl_uninstall_docker no-ops when Docker Desktop mode was chosen" {
  omawsl_save_choice OMAWSL_DOCKER_MODE "Docker Desktop for Windows"
  stub_command docker
  run omawsl_uninstall_docker
  [ "$status" -eq 0 ]
  [[ "$output" == *"never installed it"* ]]
  [[ "$(stub_calls)" != *"apt-get purge"* ]]
}

@test "omawsl_uninstall_docker purges docker-ce and removes omawsl-* containers/volumes in Engine mode" {
  omawsl_save_choice OMAWSL_DOCKER_MODE "Docker Engine only, inside WSL (recommended)"
  stub_command docker
  local sources="$BATS_TEST_TMPDIR/docker.list"
  local keyrings="$BATS_TEST_TMPDIR/keyrings"
  touch "$sources"
  run omawsl_uninstall_docker "$sources" "$keyrings"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"docker rm -f omawsl-mysql"* ]]
  [[ "$(stub_calls)" == *"docker rm -f omawsl-redis"* ]]
  [[ "$(stub_calls)" == *"docker rm -f omawsl-postgresql"* ]]
  [[ "$(stub_calls)" == *"docker volume rm omawsl-mysql-data"* ]]
  [[ "$(stub_calls)" == *"sudo apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"* ]]
  [ ! -f "$sources" ]
}

@test "omawsl_uninstall_docker no-ops on the apt purge when docker-ce isn't actually installed" {
  omawsl_save_choice OMAWSL_DOCKER_MODE "Docker Engine only, inside WSL (recommended)"
  unset -f docker
  stub_hide_command docker
  run omawsl_uninstall_docker
  [ "$status" -eq 0 ]
  [[ "$output" == *"isn't installed"* ]]
  [[ "$(stub_calls)" != *"apt-get purge"* ]]
}
