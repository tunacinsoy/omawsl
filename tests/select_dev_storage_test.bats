#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/install/terminal/select-dev-storage.sh"

  DOCKER_EXISTING_CONTAINERS=""
  docker() {
    echo "docker $*" >> "$STUB_LOG"
    if [[ "$1" == "ps" ]]; then
      printf '%s\n' "$DOCKER_EXISTING_CONTAINERS"
    fi
    return 0
  }
  export -f docker
}

@test "creates a container for each selected storage option" {
  export OMAWSL_STORAGE="MySQL,PostgreSQL"
  omawsl_install_storage
  [[ "$(stub_calls)" == *"docker run -d --name omawsl-mysql"*"mysql:8"* ]]
  [[ "$(stub_calls)" == *"docker run -d --name omawsl-postgresql"*"postgres:16"* ]]
  [[ "$(stub_calls)" != *"omawsl-redis"* ]]
}

@test "creates all three when all three are selected" {
  export OMAWSL_STORAGE="MySQL,Redis,PostgreSQL"
  omawsl_install_storage
  [[ "$(stub_calls)" == *"omawsl-mysql"* ]]
  [[ "$(stub_calls)" == *"omawsl-redis"* ]]
  [[ "$(stub_calls)" == *"omawsl-postgresql"* ]]
}

@test "selecting nothing creates no containers" {
  export OMAWSL_STORAGE=""
  omawsl_install_storage
  [[ "$(stub_calls)" != *"docker run"* ]]
}

@test "no-ops cleanly when OMAWSL_STORAGE is unset entirely" {
  unset OMAWSL_STORAGE
  run omawsl_install_storage
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"docker run"* ]]
}

@test "skips creating a container that already exists (idempotent)" {
  export OMAWSL_STORAGE="Redis"
  DOCKER_EXISTING_CONTAINERS="omawsl-redis"
  omawsl_install_storage
  [[ "$(stub_calls)" != *"docker run"* ]]
  [[ "$(stub_calls)" == *"docker ps -a"* ]]
}

@test "creates redis when a differently-named container already exists" {
  export OMAWSL_STORAGE="Redis"
  DOCKER_EXISTING_CONTAINERS="some-other-container"
  omawsl_install_storage
  [[ "$(stub_calls)" == *"docker run -d --name omawsl-redis"* ]]
}
