#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../install/lib.sh
source "$SCRIPT_DIR/../install/lib.sh"

# omawsl_uninstall_storage <label>
# Inverse of install/terminal/select-dev-storage.sh's omawsl_ensure_container -
# same sudo docker rationale (group-membership staleness within one sourced
# session, design spec §8). Checks existence before removing rather than
# relying on `docker rm -f` failing silently, since `docker rm`/`volume rm`
# on a name that doesn't exist actually errors (nonzero exit), which would
# trip set -e here.
omawsl_uninstall_storage() {
  local label="$1"
  local container volume
  case "$label" in
    MySQL)      container=omawsl-mysql;      volume=omawsl-mysql-data ;;
    Redis)      container=omawsl-redis;      volume=omawsl-redis-data ;;
    PostgreSQL) container=omawsl-postgresql; volume=omawsl-postgresql-data ;;
    *)
      echo "omawsl: unknown storage option '$label'" >&2
      return 1
      ;;
  esac

  if ! omawsl_docker_reachable; then
    echo "omawsl: 'docker' isn't reachable - nothing to remove for $label."
    return 0
  fi

  if sudo docker ps -a --format '{{.Names}}' | grep -qx "$container"; then
    sudo docker rm -f "$container" >/dev/null
  fi
  if sudo docker volume ls --format '{{.Name}}' | grep -qx "$volume"; then
    sudo docker volume rm "$volume" >/dev/null
  fi
  echo "omawsl: $label container removed (or was already not present)."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_uninstall_storage "$@"
fi
