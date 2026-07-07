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

  # sudo forwards "sudo docker ..." to the docker() fake above (production
  # code is expected to invoke docker via sudo - see the permission-denied
  # regression test below), while still logging its own invocation
  # separately so both layers are visible in stub_calls.
  sudo() {
    echo "sudo $*" >> "$STUB_LOG"
    if [[ "$1" == "docker" ]]; then
      shift
      docker "$@"
    fi
  }
  export -f sudo
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

@test "invokes docker via sudo, so a stale current-session group cache doesn't cause permission-denied errors" {
  # Regression test: on a real run, docker.sh's `sudo usermod -aG docker
  # "$USER"` doesn't take effect in the current shell session (group
  # membership is only refreshed on next login) - but terminal/*.sh scripts
  # are sourced into that same session (design spec §8), so this script's
  # own docker calls run moments later, in the same session, still without
  # the new group. A bare `docker ps`/`docker run` there fails with
  # "permission denied while trying to connect to the docker API" even
  # though the daemon is running fine. `sudo docker ...` sidesteps this
  # (the same sudo timestamp cache from docker.sh's own sudo calls covers
  # it), independent of whether the group membership has been refreshed.
  export OMAWSL_STORAGE="Redis"
  omawsl_install_storage
  [[ "$(stub_calls)" == *"sudo docker ps -a"* ]]
  [[ "$(stub_calls)" == *"sudo docker run -d --name omawsl-redis"* ]]
}

@test "skips storage containers cleanly when storage is selected but docker isn't reachable yet" {
  # Deliberately does not rely on setup()'s docker() stub: that function is
  # exported and would satisfy `command -v docker` regardless of PATH, which
  # would mask the very case being tested here. `unset -f docker` strips the
  # inherited stub inside the subshell before docker's absence is checked.
  run bash -c '
    unset -f docker
    source "'"$REPO_ROOT"'/install/lib.sh"
    source "'"$REPO_ROOT"'/install/terminal/select-dev-storage.sh"
    export OMAWSL_STORAGE="MySQL,Redis,PostgreSQL"
    export PATH=/nonexistent
    omawsl_install_storage
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipping storage containers"* ]]
  [[ "$output" == *"docker"*"isn't reachable"* ]]
}
