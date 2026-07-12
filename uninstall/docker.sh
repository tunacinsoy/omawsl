#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../install/lib.sh
source "$SCRIPT_DIR/../install/lib.sh"

# omawsl_uninstall_omawsl_containers
# Removes every omawsl-* container/volume this repo could have created
# across all three storage options (design spec §7's own uninstall/docker.sh
# scope: "removes docker-ce + containers/images/volumes it created"), not
# just whatever's currently selected in OMAWSL_STORAGE - a full Docker
# teardown removes everything omawsl ever touched, regardless of the
# user's current picker state. `|| true` on each: unlike storage.sh's
# per-item uninstall (which checks existence first), this is a best-effort
# sweep over fixed candidate names, so a missing container/volume is
# expected, not exceptional.
omawsl_uninstall_omawsl_containers() {
  omawsl_docker_reachable || return 0
  local name
  for name in omawsl-mysql omawsl-redis omawsl-postgresql; do
    sudo docker rm -f "$name" >/dev/null 2>&1 || true
  done
  for name in omawsl-mysql-data omawsl-redis-data omawsl-postgresql-data; do
    sudo docker volume rm "$name" >/dev/null 2>&1 || true
  done
}

# omawsl_uninstall_docker [apt_sources_file] [keyrings_dir]
# Detect-and-defer's inverse: if OMAWSL_DOCKER_MODE (persisted in
# choices.env, design spec §6) was Docker Desktop, omawsl's docker.sh
# never installed docker-ce (design spec §9) - so there's genuinely
# nothing here for THIS repo to uninstall. Otherwise purges docker-ce and
# its apt source/keyring, same paths omawsl_install_docker_ce writes
# (install/terminal/docker.sh). Deliberately leaves the user's docker
# group membership in place rather than auto-revoking it - that's a
# broader system change than "undo what omawsl installed."
omawsl_uninstall_docker() {
  local apt_sources_file="${1:-/etc/apt/sources.list.d/docker.list}"
  local keyrings_dir="${2:-/etc/apt/keyrings}"

  if [[ "$(omawsl_load_choice OMAWSL_DOCKER_MODE)" == "Docker Desktop for Windows" ]]; then
    echo "omawsl: Docker was set up via Docker Desktop for Windows - omawsl never installed it, so there's nothing to uninstall here."
    echo "Uninstall Docker Desktop yourself on the Windows side if you want to remove it."
    return 0
  fi

  omawsl_uninstall_omawsl_containers

  if ! command -v docker &>/dev/null; then
    echo "omawsl: docker-ce isn't installed - nothing more to do."
    return 0
  fi

  sudo apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo rm -f "$apt_sources_file" "$keyrings_dir/docker.gpg"
  echo "omawsl: docker-ce removed. Your user's docker group membership was left in place - run 'sudo gpasswd -d \"\$USER\" docker' yourself if you want that removed too."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_uninstall_docker "$@"
fi
