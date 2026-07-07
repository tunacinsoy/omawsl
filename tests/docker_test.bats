#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/install/terminal/docker.sh"
  stub_command sudo
  stub_command curl
  stub_command gpg
  export USER=testuser
}

# --- omawsl_docker_desktop ------------------------------------------------

@test "desktop mode: does nothing when docker is already reachable" {
  stub_command docker
  run omawsl_docker_desktop
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "desktop mode: prints a deferral message when docker isn't reachable" {
  run bash -c '
    export PATH=/nonexistent
    source "'"$REPO_ROOT"'/install/lib.sh"
    source "'"$REPO_ROOT"'/install/terminal/docker.sh"
    omawsl_docker_desktop
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"docs/windows-setup.md#docker-desktop"* ]]
  [[ "$output" == *"re-run install.sh"* ]]
}

# --- omawsl_docker dispatcher ----------------------------------------------

@test "dispatcher: routes to desktop mode when Docker Desktop is selected" {
  run bash -c '
    source "'"$REPO_ROOT"'/install/lib.sh"
    source "'"$REPO_ROOT"'/install/terminal/docker.sh"
    omawsl_docker_desktop() { echo "DESKTOP_CALLED"; }
    export OMAWSL_DOCKER_MODE="Docker Desktop for Windows"
    omawsl_docker
  '
  [ "$status" -eq 0 ]
  [[ "$output" == "DESKTOP_CALLED" ]]
}

@test "dispatcher: routes to engine mode for the recommended option" {
  run bash -c '
    source "'"$REPO_ROOT"'/install/lib.sh"
    source "'"$REPO_ROOT"'/install/terminal/docker.sh"
    omawsl_docker_engine() { echo "ENGINE_CALLED"; }
    export OMAWSL_DOCKER_MODE="Docker Engine only, inside WSL (recommended)"
    omawsl_docker
  '
  [ "$status" -eq 0 ]
  [[ "$output" == "ENGINE_CALLED" ]]
}

@test "dispatcher: routes to engine mode when OMAWSL_DOCKER_MODE is unset" {
  run bash -c '
    source "'"$REPO_ROOT"'/install/lib.sh"
    source "'"$REPO_ROOT"'/install/terminal/docker.sh"
    omawsl_docker_engine() { echo "ENGINE_CALLED"; }
    omawsl_docker
  '
  [ "$status" -eq 0 ]
  [[ "$output" == "ENGINE_CALLED" ]]
}

# --- omawsl_check_docker_path_collision -------------------------------------

@test "path collision: a single docker path is fine" {
  run omawsl_check_docker_path_collision "/usr/bin/docker"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "path collision: native docker resolving first is fine even with a second path present" {
  run omawsl_check_docker_path_collision "/usr/bin/docker
/mnt/c/Program Files/Docker/resources/bin/docker"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "path collision: warns when a non-native docker resolves first" {
  run omawsl_check_docker_path_collision "/mnt/c/Program Files/Docker/resources/bin/docker
/usr/bin/docker"
  [ "$status" -eq 0 ]
  [[ "$output" == *"multiple 'docker' binaries"* ]]
  [[ "$output" == *"/usr/bin/docker"* ]]
}

# --- omawsl_install_docker_ce ------------------------------------------------

@test "install_docker_ce: adds the apt repo and key when the sources file doesn't exist yet" {
  sources_file="$BATS_TEST_TMPDIR/docker.list"
  keyrings_dir="$BATS_TEST_TMPDIR/keyrings"
  run omawsl_install_docker_ce "$sources_file" "$keyrings_dir"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"sudo install -m 0755 -d $keyrings_dir"* ]]
  [[ "$(stub_calls)" == *"curl -fsSL https://download.docker.com/linux/ubuntu/gpg"* ]]
  [[ "$(stub_calls)" == *"sudo gpg --dearmor -o $keyrings_dir/docker.gpg"* ]]
  [[ "$(stub_calls)" == *"sudo tee $sources_file"* ]]
  [[ "$(stub_calls)" == *"sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"* ]]
}

@test "install_docker_ce: skips the repo-add step when the sources file already exists" {
  sources_file="$BATS_TEST_TMPDIR/docker.list"
  keyrings_dir="$BATS_TEST_TMPDIR/keyrings"
  : > "$sources_file"
  run omawsl_install_docker_ce "$sources_file" "$keyrings_dir"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"curl -fsSL"* ]]
  [[ "$(stub_calls)" != *"gpg --dearmor"* ]]
  [[ "$(stub_calls)" == *"sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"* ]]
}

# --- omawsl_docker_engine -----------------------------------------------------

@test "engine mode: enables systemd and stops with a restart message when it wasn't set yet" {
  wsl_conf="$BATS_TEST_TMPDIR/wsl.conf"
  run bash -c '
    source "'"$REPO_ROOT"'/install/lib.sh"
    source "'"$REPO_ROOT"'/install/terminal/docker.sh"
    omawsl_install_docker_ce() { echo "DOCKER_CE_INSTALLED"; }
    export USER=testuser
    omawsl_docker_engine "'"$wsl_conf"'" "'"$BATS_TEST_TMPDIR"'/docker.list" "'"$BATS_TEST_TMPDIR"'/keyrings"
    echo "SHOULD_NOT_REACH_HERE"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"WSL systemd support was just enabled"* ]]
  [[ "$output" != *"DOCKER_CE_INSTALLED"* ]]
  [[ "$output" != *"SHOULD_NOT_REACH_HERE"* ]]
  [[ "$(stub_calls)" == *"sudo tee -a $wsl_conf"* ]]
}

# --- omawsl_docker_final_reminder ---------------------------------------------

@test "final reminder: shown for Engine-only mode" {
  export OMAWSL_DOCKER_MODE="Docker Engine only, inside WSL (recommended)"
  run omawsl_docker_final_reminder
  [ "$status" -eq 0 ]
  [[ "$output" == *"new terminal"* ]]
  [[ "$output" == *"newgrp docker"* ]]
}

@test "final reminder: shown when OMAWSL_DOCKER_MODE is unset (defaults to Engine)" {
  unset OMAWSL_DOCKER_MODE
  run omawsl_docker_final_reminder
  [ "$status" -eq 0 ]
  [[ "$output" == *"new terminal"* ]]
}

@test "final reminder: not shown for Docker Desktop mode" {
  export OMAWSL_DOCKER_MODE="Docker Desktop for Windows"
  run omawsl_docker_final_reminder
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "engine mode: continues past systemd, installs docker, adds the user to the docker group, when systemd is already enabled" {
  wsl_conf="$BATS_TEST_TMPDIR/wsl-already.conf"
  printf '[boot]\nsystemd=true\n' > "$wsl_conf"

  run bash -c '
    source "'"$REPO_ROOT"'/install/lib.sh"
    source "'"$REPO_ROOT"'/install/terminal/docker.sh"
    omawsl_install_docker_ce() { echo "DOCKER_CE_INSTALLED"; }
    export USER=testuser
    omawsl_docker_engine "'"$wsl_conf"'" "'"$BATS_TEST_TMPDIR"'/docker.list" "'"$BATS_TEST_TMPDIR"'/keyrings"
    echo "REACHED_END"
  '

  [ "$status" -eq 0 ]
  [[ "$output" == *"DOCKER_CE_INSTALLED"* ]]
  [[ "$output" == *"open a new terminal"* ]]
  [[ "$output" == *"REACHED_END"* ]]
  [[ "$output" != *"WSL systemd support was just enabled"* ]]
  [[ "$(stub_calls)" == *"sudo usermod -aG docker testuser"* ]]
  [[ "$(stub_calls)" != *"sudo tee -a $wsl_conf"* ]]
}
