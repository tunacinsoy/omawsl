#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/install/terminal/app-gh-copilot.sh"
  stub_command mise
  stub_command gh
}

@test "no-ops entirely when GitHub Copilot CLI isn't selected" {
  export OMAWSL_EDITORS=""
  run omawsl_install_gh_copilot
  [ "$status" -eq 0 ]
  [ -z "$(stub_calls)" ]
  [ ! -f "$HOME/.local/bin/copilot" ]
}

@test "installs via a private mise-managed Node and writes a wrapper" {
  export OMAWSL_EDITORS="GitHub Copilot CLI"
  stub_hide_command copilot
  run omawsl_install_gh_copilot
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"mise exec node@lts -- npm install -g @github/copilot"* ]]
  [ -x "$HOME/.local/bin/copilot" ]
  [[ "$(cat "$HOME/.local/bin/copilot")" == *"exec mise exec node@lts -- copilot"* ]]
}

@test "no-ops the npm install when already installed" {
  export OMAWSL_EDITORS="GitHub Copilot CLI"
  stub_command copilot
  run omawsl_install_gh_copilot
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"npm install"* ]]
}

@test "cleans up the old gh-copilot extension even when copilot is already installed" {
  export OMAWSL_EDITORS="GitHub Copilot CLI"
  stub_command copilot
  gh() {
    echo "gh $*" >> "$STUB_LOG"
    if [[ "$1 $2" == "extension list" ]]; then
      echo "gh copilot	github/gh-copilot	v1.2.3"
    fi
  }
  export -f gh
  run omawsl_install_gh_copilot
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"gh extension remove gh-copilot"* ]]
  [[ "$(stub_calls)" != *"npm install"* ]]
}

@test "skips the old-extension removal when it was never installed" {
  export OMAWSL_EDITORS="GitHub Copilot CLI"
  stub_hide_command copilot
  run omawsl_install_gh_copilot
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"gh extension remove"* ]]
}

@test "omawsl_gh_copilot_install_steps runs unconditionally and (re)writes the wrapper" {
  stub_command copilot
  rm -f "$HOME/.local/bin/copilot"
  run omawsl_gh_copilot_install_steps
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"mise exec node@lts -- npm install -g @github/copilot"* ]]
  [ -x "$HOME/.local/bin/copilot" ]
}

@test "omawsl_gh_copilot_remove_old_extension removes the extension when present" {
  gh() {
    echo "gh $*" >> "$STUB_LOG"
    if [[ "$1 $2" == "extension list" ]]; then
      echo "gh copilot	github/gh-copilot	v1.2.3"
    fi
  }
  export -f gh
  run omawsl_gh_copilot_remove_old_extension
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"gh extension remove gh-copilot"* ]]
}

@test "omawsl_gh_copilot_remove_old_extension no-ops cleanly when gh isn't on PATH" {
  stub_hide_command gh
  run omawsl_gh_copilot_remove_old_extension
  [ "$status" -eq 0 ]
}
