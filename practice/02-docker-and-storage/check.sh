#!/usr/bin/env bash
set -euo pipefail

# This phase's real implementation installs docker-ce via apt, adds the
# real user to the docker group, and starts real containers that bind
# local ports. None of that may ever run for real in this check - see
# check-generation.md, Strategy B, Technique 2.
#
# Every dangerous command this phase's code calls (sudo, docker, apt-get,
# usermod, curl, gpg) is replaced below with a same-named shell function
# that only logs what it was asked to do. Because every learner file is
# `source`d directly into this script's own process (or into a `( ... )`
# subshell forked from it) - never exec'd as a separate `bash script.sh`
# child process - a plain function definition is enough to intercept every
# call by name; there is no process boundary here for a stub to fail to
# cross. `sudo` is the one that matters most: every apt-get/usermod/tee/gpg
# call in the real implementation is routed through it, and `sudo`
# resolves its target via the *calling* shell first, so stubbing `sudo`
# alone intercepts everything wrapped in it.
#
# `omawsl_docker_engine`'s real implementation can call `exit 0` directly
# (the restart-required path) - sourced install scripts are meant to be
# able to do that (it deliberately ends the whole install.sh run). Calling
# it in this check's own process would end this check script too, so every
# call into docker.sh below happens inside a `( ... )` subshell: `exit`
# there only ends the subshell, and its output/exit status is captured
# safely into a variable.

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
failed=0

dir="$(cd "$(dirname "$0")" && pwd)"
lib_file="$dir/lib.sh"
docker_file="$dir/docker.sh"
storage_file="$dir/select-dev-storage.sh"

calls_log="$scratch/calls.log"
: > "$calls_log"

# --- stubs: no real install, no real group edit, no real container ever runs ---

sudo() {
  echo "sudo $*" >> "$calls_log"
  # Emulate `sudo tee [-a] <file>` well enough to actually write the piped
  # stdin into the target file, so the systemd-guard idempotency check
  # below (append once, detect "already there" on the next call) has real
  # file content to look at, the same as a real `tee` would leave behind.
  if [[ "${1:-}" == "tee" ]]; then
    shift
    local append=0
    if [[ "${1:-}" == "-a" ]]; then
      append=1
      shift
    fi
    if [[ "$append" == "1" ]]; then
      cat >> "$1"
    else
      cat > "$1"
    fi
  fi
  return 0
}
docker() { echo "docker $*" >> "$calls_log"; return 0; }
apt-get() { echo "apt-get $*" >> "$calls_log"; return 0; }
usermod() { echo "usermod $*" >> "$calls_log"; return 0; }
curl() { echo "curl $*" >> "$calls_log"; return 0; }
gpg() { echo "gpg $*" >> "$calls_log"; return 0; }
export -f sudo docker apt-get usermod curl gpg

calls() { cat "$calls_log"; }
reset_calls() { : > "$calls_log"; }

check() {
  local description="$1" ok="$2"
  if [[ "$ok" == "0" ]]; then
    echo "PASS: $description"
  else
    echo "FAIL: $description"
    failed=1
  fi
}

# =====================================================================
# lib.sh: omawsl_docker_reachable
# =====================================================================

if ( source "$lib_file" && omawsl_docker_reachable ) >/dev/null 2>&1; then
  check "omawsl_docker_reachable succeeds when a docker command is on PATH" 0
else
  check "omawsl_docker_reachable succeeds when a docker command is on PATH" 1
fi

if ( unset -f docker; PATH=/nonexistent; source "$lib_file" && ! omawsl_docker_reachable ) >/dev/null 2>&1; then
  check "omawsl_docker_reachable fails when nothing named docker is on PATH" 0
else
  check "omawsl_docker_reachable fails when nothing named docker is on PATH" 1
fi

# =====================================================================
# docker.sh: omawsl_docker_desktop
# =====================================================================

output="$( ( source "$lib_file" && source "$docker_file" && omawsl_docker_desktop ) 2>&1 || echo '<error>' )"
if [[ -z "$output" ]]; then
  check "desktop mode: does nothing when docker is already reachable" 0
else
  check "desktop mode: does nothing when docker is already reachable (got: $output)" 1
fi

output="$( ( unset -f docker; PATH=/nonexistent; source "$lib_file" && source "$docker_file" && omawsl_docker_desktop ) 2>&1 || echo '<error>' )"
if [[ "$output" == *"docs/windows-setup.md#docker-desktop"* && "$output" == *"re-run install.sh"* ]]; then
  check "desktop mode: prints a deferral message pointing at docs/windows-setup.md#docker-desktop when docker isn't reachable" 0
else
  check "desktop mode: prints a deferral message pointing at docs/windows-setup.md#docker-desktop when docker isn't reachable (got: $output)" 1
fi

# =====================================================================
# docker.sh: omawsl_docker dispatcher
# =====================================================================

output="$( (
  source "$lib_file" && source "$docker_file"
  omawsl_docker_desktop() { echo "DESKTOP_CALLED"; }
  OMAWSL_DOCKER_MODE="Docker Desktop for Windows" omawsl_docker
) 2>&1 || echo '<error>' )"
if [[ "$output" == "DESKTOP_CALLED" ]]; then
  check "dispatcher: routes to desktop mode when OMAWSL_DOCKER_MODE is the literal Docker Desktop string" 0
else
  check "dispatcher: routes to desktop mode when OMAWSL_DOCKER_MODE is the literal Docker Desktop string (got: $output)" 1
fi

output="$( (
  source "$lib_file" && source "$docker_file"
  omawsl_docker_engine() { echo "ENGINE_CALLED"; }
  OMAWSL_DOCKER_MODE="Docker Engine only, inside WSL (recommended)" omawsl_docker
) 2>&1 || echo '<error>' )"
if [[ "$output" == "ENGINE_CALLED" ]]; then
  check "dispatcher: routes to engine mode for the recommended Engine-only option" 0
else
  check "dispatcher: routes to engine mode for the recommended Engine-only option (got: $output)" 1
fi

output="$( (
  source "$lib_file" && source "$docker_file"
  omawsl_docker_engine() { echo "ENGINE_CALLED"; }
  unset OMAWSL_DOCKER_MODE
  omawsl_docker
) 2>&1 || echo '<error>' )"
if [[ "$output" == "ENGINE_CALLED" ]]; then
  check "dispatcher: routes to engine mode when OMAWSL_DOCKER_MODE is unset (Engine-only is the safe default)" 0
else
  check "dispatcher: routes to engine mode when OMAWSL_DOCKER_MODE is unset (Engine-only is the safe default) (got: $output)" 1
fi

# =====================================================================
# docker.sh: omawsl_check_docker_path_collision
# =====================================================================

output="$( ( source "$lib_file" && source "$docker_file" && omawsl_check_docker_path_collision "/usr/bin/docker" ) 2>&1 || echo '<error>' )"
if [[ -z "$output" ]]; then
  check "path collision: a single docker path on PATH is fine (no warning)" 0
else
  check "path collision: a single docker path on PATH is fine (no warning) (got: $output)" 1
fi

output="$( ( source "$lib_file" && source "$docker_file" && omawsl_check_docker_path_collision "$(printf '/usr/bin/docker\n/mnt/c/Program Files/Docker/resources/bin/docker')" ) 2>&1 || echo '<error>' )"
if [[ -z "$output" ]]; then
  check "path collision: no warning when the native /usr/bin/docker resolves first" 0
else
  check "path collision: no warning when the native /usr/bin/docker resolves first (got: $output)" 1
fi

output="$( ( source "$lib_file" && source "$docker_file" && omawsl_check_docker_path_collision "$(printf '/mnt/c/Program Files/Docker/resources/bin/docker\n/usr/bin/docker')" ) 2>&1 || echo '<error>' )"
if [[ "$output" == *"multiple 'docker' binaries"* && "$output" == *"/usr/bin/docker"* ]]; then
  check "path collision: warns when a non-native docker resolves first" 0
else
  check "path collision: warns when a non-native docker resolves first (got: $output)" 1
fi

# =====================================================================
# docker.sh: omawsl_install_docker_ce
# =====================================================================

reset_calls
sources_file="$scratch/docker.list"
keyrings_dir="$scratch/keyrings"
( source "$lib_file" && source "$docker_file" && omawsl_install_docker_ce "$sources_file" "$keyrings_dir" ) >/dev/null 2>&1 || true
c="$(calls)"
if [[ "$c" == *"sudo install -m 0755 -d $keyrings_dir"* && "$c" == *"curl -fsSL https://download.docker.com/linux/ubuntu/gpg"* \
   && "$c" == *"sudo gpg --dearmor -o $keyrings_dir/docker.gpg"* && "$c" == *"sudo tee $sources_file"* \
   && "$c" == *"sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"* ]]; then
  check "install_docker_ce: adds the apt repo and key when the sources file doesn't exist yet" 0
else
  check "install_docker_ce: adds the apt repo and key when the sources file doesn't exist yet (calls were: $c)" 1
fi

reset_calls
sources_file2="$scratch/docker2.list"
keyrings_dir2="$scratch/keyrings2"
: > "$sources_file2"
( source "$lib_file" && source "$docker_file" && omawsl_install_docker_ce "$sources_file2" "$keyrings_dir2" ) >/dev/null 2>&1 || true
c="$(calls)"
if [[ "$c" != *"curl -fsSL"* && "$c" != *"gpg --dearmor"* && "$c" == *"sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"* ]]; then
  check "install_docker_ce: skips the repo-add step when the sources file already exists" 0
else
  check "install_docker_ce: skips the repo-add step when the sources file already exists (calls were: $c)" 1
fi

# =====================================================================
# docker.sh: omawsl_docker_engine
# =====================================================================

reset_calls
wsl_conf="$scratch/wsl.conf"
output="$( (
  source "$lib_file" && source "$docker_file"
  omawsl_install_docker_ce() { echo "DOCKER_CE_INSTALLED"; }
  USER=testuser
  omawsl_docker_engine "$wsl_conf" "$scratch/unused-sources.list" "$scratch/unused-keyrings"
  echo "SHOULD_NOT_REACH_HERE"
) 2>&1 || echo '<error>' )"
c="$(calls)"
if [[ "$output" == *"WSL systemd support was just enabled"* && "$output" != *"DOCKER_CE_INSTALLED"* \
   && "$output" != *"SHOULD_NOT_REACH_HERE"* && "$c" == *"sudo tee -a $wsl_conf"* ]]; then
  check "engine mode: enables systemd and stops with a restart message when it wasn't set yet" 0
else
  check "engine mode: enables systemd and stops with a restart message when it wasn't set yet (output: $output | calls: $c)" 1
fi

reset_calls
wsl_conf2="$scratch/wsl-already.conf"
printf '[boot]\nsystemd=true\n' > "$wsl_conf2"
sources_file3="$scratch/docker3.list"
keyrings_dir3="$scratch/keyrings3"
: > "$sources_file3"
output="$( (
  source "$lib_file" && source "$docker_file"
  USER=testuser
  omawsl_docker_engine "$wsl_conf2" "$sources_file3" "$keyrings_dir3"
  echo "REACHED_END"
) 2>&1 || echo '<error>' )"
c="$(calls)"
if [[ "$output" == *"REACHED_END"* && "$output" != *"WSL systemd support was just enabled"* \
   && "$c" == *"sudo usermod -aG docker testuser"* && "$c" != *"sudo tee -a $wsl_conf2"* ]]; then
  check "engine mode: continues past an already-enabled systemd, installs docker, and adds the user to the docker group" 0
else
  check "engine mode: continues past an already-enabled systemd, installs docker, and adds the user to the docker group (output: $output | calls: $c)" 1
fi

# =====================================================================
# docker.sh: omawsl_docker_final_reminder
# =====================================================================

output="$( ( source "$lib_file" && source "$docker_file"; OMAWSL_DOCKER_MODE="Docker Engine only, inside WSL (recommended)" omawsl_docker_final_reminder ) 2>&1 || echo '<error>' )"
if [[ "$output" == *"new terminal"* && "$output" == *"newgrp docker"* ]]; then
  check "final reminder: shown for Engine-only mode" 0
else
  check "final reminder: shown for Engine-only mode (got: $output)" 1
fi

output="$( ( source "$lib_file" && source "$docker_file"; unset OMAWSL_DOCKER_MODE; omawsl_docker_final_reminder ) 2>&1 || echo '<error>' )"
if [[ "$output" == *"new terminal"* ]]; then
  check "final reminder: shown when OMAWSL_DOCKER_MODE is unset (defaults to Engine)" 0
else
  check "final reminder: shown when OMAWSL_DOCKER_MODE is unset (defaults to Engine) (got: $output)" 1
fi

output="$( ( source "$lib_file" && source "$docker_file"; OMAWSL_DOCKER_MODE="Docker Desktop for Windows" omawsl_docker_final_reminder ) 2>&1 || echo '<error>' )"
if [[ -z "$output" ]]; then
  check "final reminder: not shown for Docker Desktop mode" 0
else
  check "final reminder: not shown for Docker Desktop mode (got: $output)" 1
fi

# =====================================================================
# select-dev-storage.sh: omawsl_install_storage / omawsl_ensure_container
# =====================================================================

reset_calls
( export OMAWSL_STORAGE="MySQL,PostgreSQL"; source "$storage_file" && omawsl_install_storage ) >/dev/null 2>&1 || true
c="$(calls)"
if [[ "$c" == *"sudo docker run -d --name omawsl-mysql"*"mysql:8"* && "$c" == *"sudo docker run -d --name omawsl-postgresql"*"postgres:16"* \
   && "$c" != *"omawsl-redis"* ]]; then
  check "creates a container for each selected storage option, and only those" 0
else
  check "creates a container for each selected storage option, and only those (calls were: $c)" 1
fi

reset_calls
( export OMAWSL_STORAGE="MySQL,Redis,PostgreSQL"; source "$storage_file" && omawsl_install_storage ) >/dev/null 2>&1 || true
c="$(calls)"
if [[ "$c" == *"omawsl-mysql"* && "$c" == *"omawsl-redis"* && "$c" == *"omawsl-postgresql"* ]]; then
  check "creates all three containers when all three are selected" 0
else
  check "creates all three containers when all three are selected (calls were: $c)" 1
fi

reset_calls
( export OMAWSL_STORAGE=""; source "$storage_file" && omawsl_install_storage ) >/dev/null 2>&1 || true
c="$(calls)"
if [[ "$c" != *"docker run"* ]]; then
  check "selecting nothing (empty OMAWSL_STORAGE) creates no containers" 0
else
  check "selecting nothing (empty OMAWSL_STORAGE) creates no containers (calls were: $c)" 1
fi

reset_calls
if ( unset OMAWSL_STORAGE; source "$storage_file" && omawsl_install_storage ) >/dev/null 2>&1; then
  storage_unset_status=0
else
  storage_unset_status=1
fi
c="$(calls)"
if [[ "$storage_unset_status" == "0" && "$c" != *"docker run"* ]]; then
  check "no-ops cleanly (no crash, no containers) when OMAWSL_STORAGE is unset entirely" 0
else
  check "no-ops cleanly (no crash, no containers) when OMAWSL_STORAGE is unset entirely (status: $storage_unset_status, calls were: $c)" 1
fi

reset_calls
( export OMAWSL_STORAGE="Redis"
  source "$storage_file"
  sudo() {
    echo "sudo $*" >> "$calls_log"
    if [[ "${1:-}" == "docker" && "${2:-}" == "ps" ]]; then
      echo "omawsl-redis"
    fi
    return 0
  }
  omawsl_install_storage
) >/dev/null 2>&1 || true
c="$(calls)"
if [[ "$c" != *"docker run"* && "$c" == *"docker ps -a"* ]]; then
  check "skips creating a container that already exists (idempotent)" 0
else
  check "skips creating a container that already exists (idempotent) (calls were: $c)" 1
fi

reset_calls
( export OMAWSL_STORAGE="Redis"
  source "$storage_file"
  sudo() {
    echo "sudo $*" >> "$calls_log"
    if [[ "${1:-}" == "docker" && "${2:-}" == "ps" ]]; then
      echo "some-other-container"
    fi
    return 0
  }
  omawsl_install_storage
) >/dev/null 2>&1 || true
c="$(calls)"
if [[ "$c" == *"sudo docker run -d --name omawsl-redis"* ]]; then
  check "creates redis when a differently-named container already exists" 0
else
  check "creates redis when a differently-named container already exists (calls were: $c)" 1
fi

reset_calls
# Source the file first, while PATH is still intact (SCRIPT_DIR's own
# `dirname` lookup needs it), then strip docker's reachability out from
# under it before calling the function under test - mirrors how the
# original project's own select_dev_storage_test.bats orders this exact
# check for the same reason.
output="$( (
  source "$storage_file"
  unset -f docker
  PATH=/nonexistent
  export OMAWSL_STORAGE="Redis"
  omawsl_install_storage
) 2>&1 || echo '<error>' )"
c="$(calls)"
if [[ "$output" == *"skipping storage containers"* && "$c" != *"docker run"* ]]; then
  check "skips storage containers cleanly (no crash) when selected but docker isn't reachable yet" 0
else
  check "skips storage containers cleanly (no crash) when selected but docker isn't reachable yet (output: $output | calls: $c)" 1
fi

exit "$failed"
