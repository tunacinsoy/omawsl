#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
source "$SCRIPT_DIR/../lib.sh"

# omawsl_ensure_container <name> <docker run args...>
# Idempotent: does nothing if a container by this name already exists
# (running or stopped) - `docker run` itself is not safe to re-run blindly,
# since it errors out on a name collision rather than no-op (design spec
# §7: "container creation is guarded by a name-existence check").
omawsl_ensure_container() {
  local name="$1"; shift
  if docker ps -a --format '{{.Names}}' | grep -qx "$name"; then
    return 0
  fi
  docker run -d --name "$name" --restart unless-stopped "$@"
}

# omawsl_install_storage
# Creates one Docker container per selection in OMAWSL_STORAGE. Nothing is
# pre-selected by default and selecting nothing is a valid, expected state
# (design spec §6, §12) - each branch below no-ops cleanly if its option
# wasn't picked, rather than assuming at least one was. Passwords below are
# a fixed local-dev-only default, not a secret - these containers are only
# reachable from localhost via WSL2's automatic port-forwarding.
omawsl_install_storage() {
  local storage="${OMAWSL_STORAGE:-}"

  # If storage was selected but `docker` isn't reachable yet (e.g. Docker
  # Desktop was picked and deferred by docker.sh's own detect-and-defer
  # check - design spec §6, §9), skip container creation cleanly instead of
  # letting `docker ps`/`docker run` fail and abort the whole install under
  # `set -e`. omawsl_docker_reachable is the same check Docker Desktop's own
  # deferral uses, so this follows that identical pattern.
  if [[ -n "$storage" ]] && ! omawsl_docker_reachable; then
    echo "omawsl: skipping storage containers - 'docker' isn't reachable yet."
    echo "Finish Docker setup (see the checklist above), then re-run install.sh."
    return 0
  fi

  if omawsl_list_has "$storage" "MySQL"; then
    omawsl_ensure_container omawsl-mysql \
      -p 3306:3306 \
      -e MYSQL_ROOT_PASSWORD=password \
      -v omawsl-mysql-data:/var/lib/mysql \
      mysql:8
  fi

  if omawsl_list_has "$storage" "Redis"; then
    omawsl_ensure_container omawsl-redis \
      -p 6379:6379 \
      -v omawsl-redis-data:/data \
      redis:7
  fi

  if omawsl_list_has "$storage" "PostgreSQL"; then
    omawsl_ensure_container omawsl-postgresql \
      -p 5432:5432 \
      -e POSTGRES_PASSWORD=password \
      -v omawsl-postgresql-data:/var/lib/postgresql/data \
      postgres:16
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_install_storage
fi
