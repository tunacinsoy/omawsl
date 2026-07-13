#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/uninstall/storage.sh"

  # Default docker stub that returns all containers/volumes when queried
  docker() {
    echo "docker $*" >> "$STUB_LOG"
    if [[ "$1" == "ps" && "$2" == "-a" ]]; then
      echo "omawsl-mysql"
      echo "omawsl-redis"
      echo "omawsl-postgresql"
    elif [[ "$1" == "volume" && "$2" == "ls" ]]; then
      echo "omawsl-mysql-data"
      echo "omawsl-redis-data"
      echo "omawsl-postgresql-data"
    fi
  }
  export -f docker

  sudo() {
    echo "sudo $*" >> "$STUB_LOG"
    if [[ "$1" == "docker" ]]; then
      shift
      docker "$@"
    fi
  }
  export -f sudo
}

@test "omawsl_uninstall_storage removes an existing MySQL container and its volume" {
  run omawsl_uninstall_storage "MySQL"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"docker rm -f omawsl-mysql"* ]]
  [[ "$(stub_calls)" == *"docker volume rm omawsl-mysql-data"* ]]
}

@test "omawsl_uninstall_storage no-ops when the container was never created" {
  # Override docker to return nothing when ps or volume ls is called
  docker() {
    echo "docker $*" >> "$STUB_LOG"
    # Return nothing - containers/volumes don't exist
  }
  export -f docker
  run omawsl_uninstall_storage "Redis"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"rm -f"* ]]
  [[ "$output" == *"Redis"* ]]
}

@test "omawsl_uninstall_storage no-ops cleanly when docker isn't reachable" {
  unset -f docker
  stub_hide_command docker
  run omawsl_uninstall_storage "PostgreSQL"
  [ "$status" -eq 0 ]
  [[ "$output" == *"isn't reachable"* ]]
}

@test "omawsl_uninstall_storage rejects an unknown label" {
  run omawsl_uninstall_storage "MongoDB"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown"* ]]
}
