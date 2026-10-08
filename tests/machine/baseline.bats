#!/usr/bin/env bats

# Real-machine baseline checks. Run only through tests/machine/run, inside
# its sandbox (throwaway HOME, no sudo, no Windows side). Unlike
# tests/*.bats nothing here is stubbed: these use this machine's real
# tools, real choices and real network/proxy.

setup() {
  if [[ -z "${OMAWSL_MACHINE_ROOT:-}" ]]; then
    echo "run these through tests/machine/run, not bats directly" >&2
    return 1
  fi
}

@test "configs/bashrc loads in an interactive shell with this machine's real tools" {
  # ZELLIJ set: skips the multiplexer exec at the end of bashrc, which
  # would otherwise replace this shell before it could report back.
  run env ZELLIJ=machine-check bash --norc -i -c "source '$OMAWSL_MACHINE_ROOT/configs/bashrc' && echo bashrc-loaded"
  [ "$status" -eq 0 ]
  [[ "$output" == *bashrc-loaded* ]]
  [[ "$output" != *"command not found"* ]]
  [[ "$output" != *"syntax error"* ]]
  [[ "$output" != *"No such file or directory"* ]]
}

@test "omawsl doctor runs to completion against this machine's real choices" {
  run "$OMAWSL_MACHINE_ROOT/bin/omawsl" doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"omawsl doctor - checking"* ]]
  [[ "$output" == *"Terminal multiplexer:"* ]]
}

@test "GitHub release downloads omawsl's installer uses are reachable from this network" {
  # The same URL shape install/terminal/apps-terminal.sh downloads zellij
  # from; a 1-byte range request proves the redirect chain and proxy work
  # without downloading the release.
  run curl -fsSL -r 0-0 -o /dev/null -w '%{http_code}' \
    "https://github.com/zellij-org/zellij/releases/latest/download/zellij-$(uname -m)-unknown-linux-musl.tar.gz"
  [ "$status" -eq 0 ]
  [[ "$output" == 200 || "$output" == 206 ]]
}

@test "the GitHub API omawsl resolves release versions from is reachable" {
  run curl -fsSL https://api.github.com/repos/jesseduffield/lazygit/releases/latest
  [ "$status" -eq 0 ]
  [[ "$output" == *'"tag_name"'* ]]
}
