#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
}

@test "copies bashrc and inputrc into HOME" {
  run bash "$REPO_ROOT/install/terminal/a-shell.sh"
  [ "$status" -eq 0 ]
  [ -f "$HOME/.bashrc" ]
  [ -f "$HOME/.inputrc" ]
  diff "$HOME/.bashrc" "$REPO_ROOT/configs/bashrc"
  diff "$HOME/.inputrc" "$REPO_ROOT/configs/inputrc"
}

@test "re-running overwrites deterministically (idempotent)" {
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  echo "some line the user added by hand" >> "$HOME/.bashrc"
  run bash "$REPO_ROOT/install/terminal/a-shell.sh"
  [ "$status" -eq 0 ]
  diff "$HOME/.bashrc" "$REPO_ROOT/configs/bashrc"
}

@test "EDITOR/VISUAL default to nano when nvim is not on PATH" {
  export HOME="$BATS_TEST_TMPDIR/home_no_nvim"
  mkdir -p "$HOME"
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  # A fixed PATH like "/usr/bin:/bin" stops hiding nvim the moment a real
  # WSL2 run genuinely installs it there (apt puts it at /usr/bin/nvim) -
  # confirmed happening on this machine after Phase 4's own manual
  # verification. stub_hide_command builds a shadow PATH of everything
  # except the named command, so this stays deterministic regardless of
  # where nvim is really installed (same fix already applied to
  # docker/terraform/mise in earlier phases).
  stub_hide_command nvim
  run bash -i -c 'echo "$EDITOR:$VISUAL"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"nano:nano"* ]]
}

@test "EDITOR/VISUAL are nvim when nvim is on PATH" {
  export HOME="$BATS_TEST_TMPDIR/home_with_nvim"
  mkdir -p "$HOME/.local/bin"
  printf '#!/usr/bin/env bash\ntrue\n' > "$HOME/.local/bin/nvim"
  chmod +x "$HOME/.local/bin/nvim"
  export PATH="$HOME/.local/bin:$PATH"
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  run bash -i -c 'echo "$EDITOR:$VISUAL"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"nvim:nvim"* ]]
}

@test "mise activate runs even though mise is only reachable via \$HOME/.local/bin, added later in the same file" {
  # Regression test: mise (like nvim above) only becomes installed under
  # $HOME/.local/bin, not already on the ambient PATH. Unlike the nvim
  # check, the mise-activate check historically ran BEFORE the
  # $HOME/.local/bin PATH export later in this same file, so `command -v
  # mise` always failed and `mise activate bash` never ran in any
  # interactive shell - confirmed on a real WSL2 run where `mise --version`
  # worked (found via the later export) but `go`/`ruby`/`gem` did not
  # (mise's shims were never activated).
  export HOME="$BATS_TEST_TMPDIR/home_with_mise"
  mkdir -p "$HOME/.local/bin"
  cat > "$HOME/.local/bin/mise" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "activate" ]]; then
  echo 'echo MISE_ACTIVATED_MARKER'
fi
EOF
  chmod +x "$HOME/.local/bin/mise"
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  run bash -i -c 'true'
  [ "$status" -eq 0 ]
  [[ "$output" == *"MISE_ACTIVATED_MARKER"* ]]
}
