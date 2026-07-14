#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  # zellij is genuinely installed on real dev/test machines running this
  # suite - without this, EVERY `bash -i -c` test below (not just the
  # zellij-specific ones) would exec into a real, honest-to-goodness TUI
  # app with no terminal to interact with it, hanging forever. ZELLIJ (not
  # PATH-hiding) is the reliable guard here: PATH-hiding gets reset by
  # every later stub_hide_command call in a given test (each call replaces
  # PATH with a fresh shadow dir), so a test that hides some other command
  # would silently un-hide zellij again - confirmed this the hard way
  # (inconsistent hangs depending on which tests ran and in what order).
  # The zellij tests below that need the real exec behavior explicitly
  # `unset ZELLIJ` themselves to override this default.
  export ZELLIJ=0
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

# --- aliases parity (docs/superpowers/specs/2026-07-14-omawsl-aliases-parity-design.md) ---

@test "cat is aliased to batcat when batcat is on PATH (apt's bat package installs the binary as batcat)" {
  export HOME="$BATS_TEST_TMPDIR/home_with_batcat"
  mkdir -p "$HOME/.local/bin"
  printf '#!/usr/bin/env bash\ntrue\n' > "$HOME/.local/bin/batcat"
  chmod +x "$HOME/.local/bin/batcat"
  export PATH="$HOME/.local/bin:$PATH"
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  run bash -i -c 'alias cat'
  [ "$status" -eq 0 ]
  [[ "$output" == "alias cat='batcat --paging=never'" ]]
}

@test "cat is not aliased when batcat is not on PATH" {
  export HOME="$BATS_TEST_TMPDIR/home_no_batcat"
  mkdir -p "$HOME"
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  stub_hide_command batcat
  run bash -i -c 'alias cat'
  [ "$status" -ne 0 ]
}

@test "fd is aliased to fdfind when fdfind is on PATH (apt's fd-find package installs the binary as fdfind)" {
  export HOME="$BATS_TEST_TMPDIR/home_with_fdfind"
  mkdir -p "$HOME/.local/bin"
  printf '#!/usr/bin/env bash\ntrue\n' > "$HOME/.local/bin/fdfind"
  chmod +x "$HOME/.local/bin/fdfind"
  export PATH="$HOME/.local/bin:$PATH"
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  run bash -i -c 'alias fd'
  [ "$status" -eq 0 ]
  [[ "$output" == "alias fd='fdfind'" ]]
}

@test "ff previews with batcat when both fzf and batcat are on PATH" {
  export HOME="$BATS_TEST_TMPDIR/home_with_ff"
  mkdir -p "$HOME/.local/bin"
  printf '#!/usr/bin/env bash\ntrue\n' > "$HOME/.local/bin/fzf"
  printf '#!/usr/bin/env bash\ntrue\n' > "$HOME/.local/bin/batcat"
  chmod +x "$HOME/.local/bin/fzf" "$HOME/.local/bin/batcat"
  export PATH="$HOME/.local/bin:$PATH"
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  run bash -i -c 'alias ff'
  [ "$status" -eq 0 ]
  [[ "$output" == *"batcat --style=numbers --color=always"* ]]
}

@test "ff is not defined when batcat is missing even if fzf is present" {
  export HOME="$BATS_TEST_TMPDIR/home_ff_no_batcat"
  mkdir -p "$HOME/.local/bin"
  printf '#!/usr/bin/env bash\ntrue\n' > "$HOME/.local/bin/fzf"
  chmod +x "$HOME/.local/bin/fzf"
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  stub_hide_command batcat
  export PATH="$HOME/.local/bin:$PATH"
  run bash -i -c 'alias ff'
  [ "$status" -ne 0 ]
}

@test "ls/lsa/lt/lta get eza's long-format icon flags when eza is on PATH" {
  export HOME="$BATS_TEST_TMPDIR/home_with_eza"
  mkdir -p "$HOME/.local/bin"
  printf '#!/usr/bin/env bash\ntrue\n' > "$HOME/.local/bin/eza"
  chmod +x "$HOME/.local/bin/eza"
  export PATH="$HOME/.local/bin:$PATH"
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  run bash -i -c 'alias ls; alias lsa; alias lt; alias lta'
  [ "$status" -eq 0 ]
  [[ "$output" == *"alias ls='eza -lh --group-directories-first --icons=auto'"* ]]
  [[ "$output" == *"alias lsa='ls -a'"* ]]
  [[ "$output" == *"alias lt='eza --tree --level=2 --long --icons --git'"* ]]
  [[ "$output" == *"alias lta='lt -a'"* ]]
}

@test "directory-nav aliases (.. ... ....) are always defined" {
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  run bash -i -c "alias ..; alias ...; alias ...."
  [ "$status" -eq 0 ]
  [[ "$output" == *"alias ..='cd ..'"* ]]
  [[ "$output" == *"alias ...='cd ../..'"* ]]
  [[ "$output" == *"alias ....='cd ../../..'"* ]]
}

@test "cd is aliased to zoxide's z when zoxide is on PATH" {
  export HOME="$BATS_TEST_TMPDIR/home_with_zoxide"
  mkdir -p "$HOME/.local/bin"
  printf '#!/usr/bin/env bash\ntrue\n' > "$HOME/.local/bin/zoxide"
  chmod +x "$HOME/.local/bin/zoxide"
  export PATH="$HOME/.local/bin:$PATH"
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  run bash -i -c 'alias cd'
  [ "$status" -eq 0 ]
  [[ "$output" == "alias cd='z'" ]]
}

@test "cd is not aliased when zoxide is not on PATH" {
  export HOME="$BATS_TEST_TMPDIR/home_no_zoxide"
  mkdir -p "$HOME"
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  stub_hide_command zoxide
  run bash -i -c 'alias cd'
  [ "$status" -ne 0 ]
}

@test "git shortcut and git commit aliases are defined when git is on PATH" {
  export HOME="$BATS_TEST_TMPDIR/home_with_git"
  mkdir -p "$HOME/.local/bin"
  printf '#!/usr/bin/env bash\ntrue\n' > "$HOME/.local/bin/git"
  chmod +x "$HOME/.local/bin/git"
  export PATH="$HOME/.local/bin:$PATH"
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  run bash -i -c 'alias g; alias gcm; alias gcam; alias gcad'
  [ "$status" -eq 0 ]
  [[ "$output" == *"alias g='git'"* ]]
  [[ "$output" == *"alias gcm='git commit -m'"* ]]
  [[ "$output" == *"alias gcam='git commit -a -m'"* ]]
  [[ "$output" == *"alias gcad='git commit -a --amend'"* ]]
}

@test "git shortcut and git commit aliases are not defined when git is missing" {
  export HOME="$BATS_TEST_TMPDIR/home_no_git"
  mkdir -p "$HOME"
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  stub_hide_command git
  run bash -i -c 'alias g'
  [ "$status" -ne 0 ]
}

@test "d/r/lzg/lzd shortcuts are defined when their tools are on PATH" {
  export HOME="$BATS_TEST_TMPDIR/home_with_tool_shortcuts"
  mkdir -p "$HOME/.local/bin"
  for tool in docker rails lazygit lazydocker; do
    printf '#!/usr/bin/env bash\ntrue\n' > "$HOME/.local/bin/$tool"
    chmod +x "$HOME/.local/bin/$tool"
  done
  export PATH="$HOME/.local/bin:$PATH"
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  run bash -i -c 'alias d; alias r; alias lzg; alias lzd'
  [ "$status" -eq 0 ]
  [[ "$output" == *"alias d='docker'"* ]]
  [[ "$output" == *"alias r='rails'"* ]]
  [[ "$output" == *"alias lzg='lazygit'"* ]]
  [[ "$output" == *"alias lzd='lazydocker'"* ]]
}

@test "d/r/lzg/lzd shortcuts are not defined when their tools are missing" {
  export HOME="$BATS_TEST_TMPDIR/home_no_tool_shortcuts"
  mkdir -p "$HOME"
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  stub_hide_command docker rails lazygit lazydocker
  run bash -i -c 'alias d 2>&1; alias r 2>&1; alias lzg 2>&1; alias lzd 2>&1'
  [[ "$output" != *"alias d="* ]]
  [[ "$output" != *"alias r="* ]]
  [[ "$output" != *"alias lzg="* ]]
  [[ "$output" != *"alias lzd="* ]]
}

@test "n opens nvim on the current directory when called with no arguments" {
  export HOME="$BATS_TEST_TMPDIR/home_n_no_args"
  mkdir -p "$HOME/.local/bin"
  cat > "$HOME/.local/bin/nvim" <<'EOF'
#!/usr/bin/env bash
echo "nvim called with: $*" > "$HOME/n_invocation"
EOF
  chmod +x "$HOME/.local/bin/nvim"
  export PATH="$HOME/.local/bin:$PATH"
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  run bash -i -c 'n'
  [ "$status" -eq 0 ]
  [ -f "$HOME/n_invocation" ]
  [[ "$(cat "$HOME/n_invocation")" == "nvim called with: ." ]]
}

@test "n passes arguments through to nvim when called with arguments" {
  export HOME="$BATS_TEST_TMPDIR/home_n_with_args"
  mkdir -p "$HOME/.local/bin"
  cat > "$HOME/.local/bin/nvim" <<'EOF'
#!/usr/bin/env bash
echo "nvim called with: $*" > "$HOME/n_invocation"
EOF
  chmod +x "$HOME/.local/bin/nvim"
  export PATH="$HOME/.local/bin:$PATH"
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  run bash -i -c 'n foo.txt bar.txt'
  [ "$status" -eq 0 ]
  [[ "$(cat "$HOME/n_invocation")" == "nvim called with: foo.txt bar.txt" ]]
}

@test "n is not defined when nvim is not on PATH" {
  export HOME="$BATS_TEST_TMPDIR/home_n_missing"
  mkdir -p "$HOME"
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  stub_hide_command nvim
  run bash -i -c 'type -t n'
  [ "$status" -ne 0 ]
}

@test "PS1 uses Omakub's icon-only prompt with the path in the window title, not user@host:path" {
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  run bash -i -c 'echo "$PS1"'
  [ "$status" -eq 0 ]
  [[ "$output" != *'\u@\h'* ]]
  [[ "$output" == *'\[\e]0;\w\a\]'* ]]
}

# --- zellij auto-launch (Omakub parity: every new interactive shell drops
# into zellij, the way Alacritty's own `[shell] program = "zellij"` does it
# upstream - omawsl has no Alacritty equivalent, so this lives in bashrc
# itself instead, terminal-emulator-agnostic) ---

@test "execs into zellij on shell start when zellij is on PATH and not already inside a session" {
  # setup() exports ZELLIJ=0 by default (see its own comment) - this is
  # the one test that needs it genuinely unset, to exercise the real
  # positive case.
  unset ZELLIJ
  export HOME="$BATS_TEST_TMPDIR/home_zellij_autostart"
  mkdir -p "$HOME/.local/bin"
  cat > "$HOME/.local/bin/zellij" <<'EOF'
#!/usr/bin/env bash
echo "ZELLIJ_STARTED" > "$HOME/zellij_marker"
EOF
  chmod +x "$HOME/.local/bin/zellij"
  export PATH="$HOME/.local/bin:$PATH"
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  run bash -i -c 'true'
  [ "$status" -eq 0 ]
  [ -f "$HOME/zellij_marker" ]
  [[ "$(cat "$HOME/zellij_marker")" == "ZELLIJ_STARTED" ]]
}

@test "does not exec into zellij when already inside a zellij session" {
  # Regression guard: without this, opening a new pane/tab INSIDE an
  # existing zellij session would try to exec another zellij, breaking
  # nested panes entirely. zellij itself sets $ZELLIJ in any shell it
  # spawns - the same guard zellij's own docs recommend.
  export HOME="$BATS_TEST_TMPDIR/home_zellij_nested"
  mkdir -p "$HOME/.local/bin"
  cat > "$HOME/.local/bin/zellij" <<'EOF'
#!/usr/bin/env bash
echo "ZELLIJ_STARTED" > "$HOME/zellij_marker"
EOF
  chmod +x "$HOME/.local/bin/zellij"
  export PATH="$HOME/.local/bin:$PATH"
  export ZELLIJ=0
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  run bash -i -c 'echo STILL_RUNNING'
  [ "$status" -eq 0 ]
  [[ "$output" == *"STILL_RUNNING"* ]]
  [ ! -f "$HOME/zellij_marker" ]
}

@test "does not attempt to exec into zellij when zellij is not on PATH" {
  # ZELLIJ must be genuinely unset here too, otherwise this would pass
  # trivially via the ZELLIJ guard rather than actually exercising the
  # command -v zellij branch this test is named for.
  unset ZELLIJ
  export HOME="$BATS_TEST_TMPDIR/home_zellij_missing"
  mkdir -p "$HOME"
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  stub_hide_command zellij
  run bash -i -c 'echo STILL_RUNNING'
  [ "$status" -eq 0 ]
  [[ "$output" == *"STILL_RUNNING"* ]]
}
