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
  unset HTTP_PROXY HTTPS_PROXY NO_PROXY http_proxy https_proxy no_proxy || true
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

# --- omawsl_detect_proxy_env ------------------------------------------------

@test "detect_proxy_env: prefers the uppercase form when both are set" {
  export HTTP_PROXY="http://upper:8080"
  export http_proxy="http://lower:8080"
  run omawsl_detect_proxy_env HTTP_PROXY
  [ "$status" -eq 0 ]
  [ "$output" == "http://upper:8080" ]
}

@test "detect_proxy_env: falls back to the lowercase form when uppercase is unset" {
  unset HTTP_PROXY || true
  export http_proxy="http://lower:8080"
  run omawsl_detect_proxy_env HTTP_PROXY
  [ "$status" -eq 0 ]
  [ "$output" == "http://lower:8080" ]
}

@test "detect_proxy_env: empty when neither form is set" {
  unset HTTP_PROXY http_proxy || true
  run omawsl_detect_proxy_env HTTP_PROXY
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- omawsl_docker_proxy_conflict --------------------------------------------

@test "proxy_conflict: false when the directory doesn't exist yet" {
  run omawsl_docker_proxy_conflict "$BATS_TEST_TMPDIR/nope" "$BATS_TEST_TMPDIR/nope/omawsl-proxy.conf"
  [ "$status" -eq 1 ]
}

@test "proxy_conflict: false when the directory is empty" {
  mkdir -p "$BATS_TEST_TMPDIR/svc-empty"
  run omawsl_docker_proxy_conflict "$BATS_TEST_TMPDIR/svc-empty" "$BATS_TEST_TMPDIR/svc-empty/omawsl-proxy.conf"
  [ "$status" -eq 1 ]
}

@test "proxy_conflict: false when only omawsl's own file sets a proxy" {
  local dir="$BATS_TEST_TMPDIR/svc-own"
  mkdir -p "$dir"
  printf '[Service]\nEnvironment="HTTP_PROXY=http://x:8080"\n' > "$dir/omawsl-proxy.conf"
  run omawsl_docker_proxy_conflict "$dir" "$dir/omawsl-proxy.conf"
  [ "$status" -eq 1 ]
}

@test "proxy_conflict: true when another .conf file already sets a proxy" {
  local dir="$BATS_TEST_TMPDIR/svc-corp"
  mkdir -p "$dir"
  printf '[Service]\nEnvironment="HTTP_PROXY=http://corp:8080"\n' > "$dir/corp-managed.conf"
  run omawsl_docker_proxy_conflict "$dir" "$dir/omawsl-proxy.conf"
  [ "$status" -eq 0 ]
}

@test "proxy_conflict: false when another .conf file exists but doesn't mention a proxy" {
  local dir="$BATS_TEST_TMPDIR/svc-unrelated"
  mkdir -p "$dir"
  printf '[Service]\nEnvironment="SOMETHING_ELSE=1"\n' > "$dir/unrelated.conf"
  run omawsl_docker_proxy_conflict "$dir" "$dir/omawsl-proxy.conf"
  [ "$status" -eq 1 ]
}

# --- omawsl_configure_docker_proxy -------------------------------------------

_stub_sudo_forwarding() {
  sudo() {
    echo "sudo $*" >> "$STUB_LOG"
    case "$1" in
      mkdir) shift; command mkdir "$@" ;;
      tee) shift; command tee "$@" ;;
      cat) shift; command cat "$@" ;;
      rm) shift; command rm "$@" 2>/dev/null || true ;;
      systemctl) : ;;
      *) : ;;
    esac
  }
  export -f sudo
}

@test "configure_docker_proxy: no-ops when no proxy is set" {
  unset HTTP_PROXY HTTPS_PROXY NO_PROXY http_proxy https_proxy no_proxy || true
  _stub_sudo_forwarding
  local dir="$BATS_TEST_TMPDIR/svc-noproxy"
  run omawsl_configure_docker_proxy "$dir"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -f "$dir/omawsl-proxy.conf" ]
  [ -z "$(stub_calls)" ]
}

@test "configure_docker_proxy: writes a fresh drop-in when a proxy is set" {
  export HTTP_PROXY="http://webproxy.example:8080"
  export HTTPS_PROXY="http://webproxy.example:8080"
  export NO_PROXY="localhost,127.0.0.1"
  _stub_sudo_forwarding
  local dir="$BATS_TEST_TMPDIR/svc-fresh"
  run omawsl_configure_docker_proxy "$dir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"configured Docker daemon proxy"* ]]
  [ -f "$dir/omawsl-proxy.conf" ]
  [[ "$(cat "$dir/omawsl-proxy.conf")" == *'Environment="HTTP_PROXY=http://webproxy.example:8080"'* ]]
  [[ "$(cat "$dir/omawsl-proxy.conf")" == *'Environment="HTTPS_PROXY=http://webproxy.example:8080"'* ]]
  [[ "$(cat "$dir/omawsl-proxy.conf")" == *'Environment="NO_PROXY=localhost,127.0.0.1"'* ]]
  [[ "$(stub_calls)" == *"sudo mkdir -p $dir"* ]]
  [[ "$(stub_calls)" == *"sudo chmod 0600 $dir/omawsl-proxy.conf"* ]]
  [[ "$(stub_calls)" == *"sudo systemctl daemon-reload"* ]]
  [[ "$(stub_calls)" == *"sudo systemctl restart docker"* ]]
}

@test "configure_docker_proxy: escapes literal % in proxy values for systemd" {
  export HTTP_PROXY="http://user%40corp:pass@webproxy.example:8080"
  _stub_sudo_forwarding
  local dir="$BATS_TEST_TMPDIR/svc-percent"
  run omawsl_configure_docker_proxy "$dir"
  [ "$status" -eq 0 ]
  [[ "$(cat "$dir/omawsl-proxy.conf")" == *'HTTP_PROXY=http://user%%40corp:pass@webproxy.example:8080'* ]]
}

@test "configure_docker_proxy: idempotent - unchanged content skips write and restart" {
  export HTTP_PROXY="http://webproxy.example:8080"
  export HTTPS_PROXY="http://webproxy.example:8080"
  unset NO_PROXY no_proxy || true
  _stub_sudo_forwarding
  local dir="$BATS_TEST_TMPDIR/svc-idempotent"
  omawsl_configure_docker_proxy "$dir"
  : > "$STUB_LOG"
  run omawsl_configure_docker_proxy "$dir"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  # The read-back via `sudo cat` still happens (that's the idempotency
  # check itself), but no write or restart should occur.
  [[ "$(stub_calls)" != *"mkdir"* ]]
  [[ "$(stub_calls)" != *"tee"* ]]
  [[ "$(stub_calls)" != *"chmod"* ]]
  [[ "$(stub_calls)" != *"systemctl"* ]]
}

@test "configure_docker_proxy: backs off when another file already configures a proxy" {
  export HTTP_PROXY="http://webproxy.example:8080"
  _stub_sudo_forwarding
  local dir="$BATS_TEST_TMPDIR/svc-conflict"
  mkdir -p "$dir"
  printf '[Service]\nEnvironment="HTTP_PROXY=http://corp-own:8080"\n' > "$dir/corp-managed.conf"
  run omawsl_configure_docker_proxy "$dir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"leaving it as-is"* ]]
  [ ! -f "$dir/omawsl-proxy.conf" ]
  [[ "$(stub_calls)" != *"systemctl restart docker"* ]]
}

@test "configure_docker_proxy: removes its own stale file once a conflict appears" {
  export HTTP_PROXY="http://webproxy.example:8080"
  _stub_sudo_forwarding
  local dir="$BATS_TEST_TMPDIR/svc-stale"
  mkdir -p "$dir"
  printf '[Service]\nEnvironment="HTTP_PROXY=http://webproxy.example:8080"\n' > "$dir/omawsl-proxy.conf"
  printf '[Service]\nEnvironment="HTTP_PROXY=http://corp-own:8080"\n' > "$dir/corp-managed.conf"
  run omawsl_configure_docker_proxy "$dir"
  [ "$status" -eq 0 ]
  [ ! -f "$dir/omawsl-proxy.conf" ]
  [[ "$(stub_calls)" == *"systemctl restart docker"* ]]
}

# --- omawsl_install_docker_ce ------------------------------------------------

@test "install_docker_ce: adds the apt repo and key when the sources file doesn't exist yet" {
  sources_file="$BATS_TEST_TMPDIR/docker.list"
  keyrings_dir="$BATS_TEST_TMPDIR/keyrings"
  run omawsl_install_docker_ce "$sources_file" "$keyrings_dir"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"sudo install -m 0755 -d $keyrings_dir"* ]]
  [[ "$(stub_calls)" == *"curl -fsSL https://download.docker.com/linux/ubuntu/gpg"* ]]
  # --yes: without it, gpg interactively prompts "File exists. Overwrite?"
  # whenever the keyring file is already there from an earlier attempt
  # (e.g. a prior run that got the key but failed later) - confirmed on a
  # real WSL2 run, where this hung the whole non-interactive install
  # waiting for input that would never come.
  [[ "$(stub_calls)" == *"sudo gpg --yes --dearmor -o $keyrings_dir/docker.gpg"* ]]
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
    omawsl_docker_engine "'"$wsl_conf"'" "'"$BATS_TEST_TMPDIR"'/docker.list" "'"$BATS_TEST_TMPDIR"'/keyrings" "'"$BATS_TEST_TMPDIR"'/docker.service.d"
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
    omawsl_docker_engine "'"$wsl_conf"'" "'"$BATS_TEST_TMPDIR"'/docker.list" "'"$BATS_TEST_TMPDIR"'/keyrings" "'"$BATS_TEST_TMPDIR"'/docker.service.d"
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

@test "engine mode: recognizes systemd=true with surrounding whitespace as already enabled" {
  wsl_conf="$BATS_TEST_TMPDIR/wsl-whitespace.conf"
  printf '[boot]\n  systemd = true \n' > "$wsl_conf"

  run bash -c '
    source "'"$REPO_ROOT"'/install/lib.sh"
    source "'"$REPO_ROOT"'/install/terminal/docker.sh"
    omawsl_install_docker_ce() { echo "DOCKER_CE_INSTALLED"; }
    export USER=testuser
    omawsl_docker_engine "'"$wsl_conf"'" "'"$BATS_TEST_TMPDIR"'/docker.list" "'"$BATS_TEST_TMPDIR"'/keyrings" "'"$BATS_TEST_TMPDIR"'/docker.service.d"
    echo "REACHED_END"
  '

  [ "$status" -eq 0 ]
  [[ "$output" == *"DOCKER_CE_INSTALLED"* ]]
  [[ "$output" == *"REACHED_END"* ]]
  [[ "$output" != *"WSL systemd support was just enabled"* ]]
  [[ "$(stub_calls)" != *"sudo tee -a $wsl_conf"* ]]
}

@test "engine mode: configures the docker proxy after installing docker-ce" {
  wsl_conf="$BATS_TEST_TMPDIR/wsl-proxy.conf"
  printf '[boot]\nsystemd=true\n' > "$wsl_conf"

  run bash -c '
    source "'"$REPO_ROOT"'/install/lib.sh"
    source "'"$REPO_ROOT"'/install/terminal/docker.sh"
    omawsl_install_docker_ce() { echo "DOCKER_CE_INSTALLED"; }
    omawsl_configure_docker_proxy() { echo "PROXY_CONFIGURED: $1"; }
    export USER=testuser
    omawsl_docker_engine "'"$wsl_conf"'" "'"$BATS_TEST_TMPDIR"'/docker.list" "'"$BATS_TEST_TMPDIR"'/keyrings" "'"$BATS_TEST_TMPDIR"'/docker.service.d"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"DOCKER_CE_INSTALLED"* ]]
  [[ "$output" == *"PROXY_CONFIGURED: $BATS_TEST_TMPDIR/docker.service.d"* ]]
  # docker-ce install must happen before proxy configuration
  [[ "$output" == *"DOCKER_CE_INSTALLED"*"PROXY_CONFIGURED"* ]]
}
