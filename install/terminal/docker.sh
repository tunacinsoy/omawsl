#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
# shellcheck source=../lib.sh
source "$SCRIPT_DIR/../lib.sh"

OMAWSL_DOCKER_MODE_DESKTOP="Docker Desktop for Windows"

# omawsl_docker_desktop
# Docker Desktop was explicitly chosen (design spec §9): never installs
# docker-ce. Detect-and-defer, the same shape later phases use for
# VS Code/Cursor - if `docker` is already reachable via Docker Desktop's
# WSL integration, there's nothing to do; otherwise this is a genuine
# Windows-side prerequisite already surfaced up front by
# windows-prereq-checklist.sh, so this is just a non-fatal reminder if the
# user proceeded anyway without completing it yet.
omawsl_docker_desktop() {
  if omawsl_docker_reachable; then
    return 0
  fi

  echo "omawsl: Docker Desktop was selected but 'docker' isn't reachable yet."
  echo "Install Docker Desktop and enable WSL integration for this distro - see docs/windows-setup.md#docker-desktop."
  echo "Nothing else to do here for now; re-run install.sh after completing that step."
}

# omawsl_check_docker_path_collision [which_a_docker_output]
# Docker Desktop's docker.exe interop shim can land earlier on PATH than the
# natively apt-installed docker binary - a real case seen on an actual test
# machine during this project's design review (design spec §9 step 3).
# Warns rather than silently leaving resolution order to chance. Takes the
# `which -a docker` output as an argument so it's unit-testable with
# fixture paths instead of depending on the real host's PATH.
omawsl_check_docker_path_collision() {
  local which_output="${1:-$(which -a docker 2>/dev/null || true)}"
  [[ -z "$which_output" ]] && return 0

  local first_path
  first_path="$(echo "$which_output" | head -n1)"
  local count
  count="$(echo "$which_output" | grep -c . || true)"

  if [[ "$count" -gt 1 && "$first_path" != "/usr/bin/docker" ]]; then
    echo "omawsl: multiple 'docker' binaries found on PATH:"
    echo "$which_output"
    echo "'$first_path' resolves first, which isn't the natively installed docker-ce."
    echo "Reorder your PATH (e.g. in ~/.bashrc) so /usr/bin/docker comes first, or the"
    echo "Docker Desktop interop version may shadow it unexpectedly."
  fi
}

# omawsl_install_docker_ce [apt_sources_file] [keyrings_dir]
# Idempotent: the repo-add + GPG-key steps only run once (guarded by the
# sources file not existing yet); `apt-get install` itself no-ops on
# already-installed packages regardless. Parameterized paths default to the
# real system locations and are only ever overridden in tests.
omawsl_install_docker_ce() {
  local apt_sources_file="${1:-/etc/apt/sources.list.d/docker.list}"
  local keyrings_dir="${2:-/etc/apt/keyrings}"

  sudo apt-get update -qq
  sudo apt-get install -y ca-certificates curl gnupg

  if [[ ! -f "$apt_sources_file" ]]; then
    sudo install -m 0755 -d "$keyrings_dir"
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o "$keyrings_dir/docker.gpg"
    sudo chmod a+r "$keyrings_dir/docker.gpg"
    echo "deb [arch=$(dpkg --print-architecture) signed-by=$keyrings_dir/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
      | sudo tee "$apt_sources_file" >/dev/null
    sudo apt-get update -qq
  fi

  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

# omawsl_docker_engine [wsl_conf_file] [apt_sources_file] [keyrings_dir]
# Engine-only is the pre-highlighted default (design spec §6, §9): installs
# docker-ce natively inside WSL, no Windows-side dependency. Every path
# defaults to an OMAWSL_* env-var override (falling back to the real system
# location) before falling back further to an explicit positional arg's
# default - this is what makes it safely callable both directly (tests,
# explicit tmp paths) and via the zero-arg terminal.sh dispatch table (a
# real run, where only the env-var override matters).
omawsl_docker_engine() {
  local wsl_conf="${1:-${OMAWSL_WSL_CONF_FILE:-/etc/wsl.conf}}"
  local apt_sources_file="${2:-${OMAWSL_DOCKER_APT_SOURCES_FILE:-/etc/apt/sources.list.d/docker.list}}"
  local keyrings_dir="${3:-${OMAWSL_DOCKER_APT_KEYRINGS_DIR:-/etc/apt/keyrings}}"

  # A script running inside the live WSL instance cannot restart the WSL VM
  # itself. Because install/terminal/*.sh scripts are sourced (not
  # sub-shelled) by terminal.sh, this `exit 0` deliberately terminates the
  # entire install.sh run, not just this script - intentional (design spec
  # §9): the remaining steps have no useful work to do until after the
  # restart, so this returns immediately rather than installing docker-ce
  # against a not-yet-systemd WSL instance. Re-running install.sh afterward
  # resumes cleanly since this guard becomes a no-op.
  if ! grep -q "^systemd=true" "$wsl_conf" 2>/dev/null; then
    printf '[boot]\nsystemd=true\n' | sudo tee -a "$wsl_conf" >/dev/null
    echo "omawsl: WSL systemd support was just enabled."
    echo "Run 'wsl --shutdown' from Windows (PowerShell/cmd), reopen this terminal, then re-run install.sh to finish Docker setup."
    exit 0
  fi

  omawsl_install_docker_ce "$apt_sources_file" "$keyrings_dir"

  sudo usermod -aG docker "$USER"
  echo "omawsl: open a new terminal (or run 'newgrp docker') before using Docker without sudo."

  omawsl_check_docker_path_collision
}

# omawsl_docker
# Branches on OMAWSL_DOCKER_MODE (design spec §6, §9). Treats anything other
# than the literal Docker Desktop option as Engine-only, matching that
# prompt's pre-highlighted default.
omawsl_docker() {
  if [[ "${OMAWSL_DOCKER_MODE:-}" == "$OMAWSL_DOCKER_MODE_DESKTOP" ]]; then
    omawsl_docker_desktop
  else
    omawsl_docker_engine
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_docker
fi
