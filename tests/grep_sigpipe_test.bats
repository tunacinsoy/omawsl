#!/usr/bin/env bats

# `cmd | grep -q pattern` under `set -o pipefail` fails at random: grep
# quits at the first match, and if cmd is still writing it dies of SIGPIPE
# (status 141), which pipefail turns into "no match". These fakes write the
# matching line, pause, then write more - a pipe breaks on that every time.

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  export OMAWSL_STATE_DIR="$BATS_TEST_TMPDIR/state"
  mkdir -p "$HOME"
}

# slow_lines <first> <rest...> - prints <first>, waits, then the rest.
slow_lines() {
  printf '%s\n' "$1"
  shift
  sleep 0.3
  printf '%s\n' "$@"
}

fake_gh() {
  gh() {
    echo "gh $*" >> "$STUB_LOG"
    [[ "$1 $2" != "extension list" ]] || slow_lines $'gh copilot\tgithub/gh-copilot\tv1.0.0' $'gh dash\tdlvhdr/gh-dash\tv4.0.0'
  }
}

fake_docker() {
  sudo() {
    echo "sudo $*" >> "$STUB_LOG"
    case "$*" in
      "docker ps"*) slow_lines omawsl-redis some-other-container ;;
      "docker volume ls"*) slow_lines omawsl-redis-data some-other-volume ;;
    esac
  }
  omawsl_docker_reachable() { return 0; }
}

@test "a valid theme name is always accepted, however slowly the theme list is written" {
  source "$REPO_ROOT/bin/omawsl-sub/theme.sh"
  omawsl_theme_names() { slow_lines rose-pine catppuccin; }
  run omawsl_theme_is_valid rose-pine
  [ "$status" -eq 0 ]
}

@test "the old gh-copilot extension is found and removed when it's listed first" {
  source "$REPO_ROOT/install/terminal/app-gh-copilot.sh"
  fake_gh
  run omawsl_gh_copilot_remove_old_extension
  [[ "$(stub_calls)" == *"gh extension remove gh-copilot"* ]]
}

@test "uninstalling Copilot finds and removes the old gh-copilot extension when it's listed first" {
  source "$REPO_ROOT/uninstall/app-gh-copilot.sh"
  fake_gh
  stub_hide_command mise
  run omawsl_uninstall_gh_copilot
  [[ "$(stub_calls)" == *"gh extension remove gh-copilot"* ]]
}

@test "an existing storage container is recognized, so it's not started a second time" {
  source "$REPO_ROOT/install/terminal/select-dev-storage.sh"
  fake_docker
  run omawsl_ensure_container omawsl-redis redis:7
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"docker run"* ]]
}

@test "uninstalling storage finds and removes the container and its volume" {
  source "$REPO_ROOT/uninstall/storage.sh"
  fake_docker
  run omawsl_uninstall_storage Redis
  [[ "$(stub_calls)" == *"sudo docker rm -f omawsl-redis"* ]]
  [[ "$(stub_calls)" == *"sudo docker volume rm omawsl-redis-data"* ]]
}
