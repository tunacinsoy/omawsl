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
  # Tests below assert on $INPUTRC's value (configs/bashrc:36's
  # [ -z "${INPUTRC:-}" ] guard) - unset here so they're deterministic
  # regardless of whether the host shell running this suite already has
  # its own INPUTRC exported.
  unset INPUTRC
}

@test "adds a marker-guarded source line to ~/.bashrc, does not copy configs/bashrc's content in" {
  run bash "$REPO_ROOT/install/terminal/a-shell.sh"
  [ "$status" -eq 0 ]
  [ -f "$HOME/.bashrc" ]
  grep -qF '# >>> omawsl >>>' "$HOME/.bashrc"
  grep -qF "source \"$REPO_ROOT/configs/bashrc\"" "$HOME/.bashrc"
  ! diff -q "$HOME/.bashrc" "$REPO_ROOT/configs/bashrc" >/dev/null 2>&1
  [ ! -f "$HOME/.inputrc" ]
}

@test "re-running is idempotent and never touches pre-existing ~/.bashrc content" {
  printf 'export SOME_CORP_VAR=1\n' > "$HOME/.bashrc"
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  echo "some line the user added by hand" >> "$HOME/.bashrc"
  run bash "$REPO_ROOT/install/terminal/a-shell.sh"
  [ "$status" -eq 0 ]
  grep -qF 'export SOME_CORP_VAR=1' "$HOME/.bashrc"
  grep -qF 'some line the user added by hand' "$HOME/.bashrc"
  [ "$(grep -c '# >>> omawsl >>>' "$HOME/.bashrc")" -eq 1 ]
}

@test "INPUTRC points at omawsl's own inputrc when the user has no ~/.inputrc" {
  export HOME="$BATS_TEST_TMPDIR/home_no_inputrc"
  mkdir -p "$HOME"
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  run bash -i -c 'echo "$INPUTRC"'
  [ "$status" -eq 0 ]
  # Exact-line, not exact-equality: a sandbox with no controlling TTY
  # makes `bash -i` print "cannot set terminal process group"/"no job
  # control" warnings to stderr, which bats' `run` merges into $output
  # alongside the real one-line answer, so a plain `==` comparison isn't
  # safe here - but matching a whole line (rather than a bare substring)
  # still catches a regression that duplicates or mangles the value,
  # which a `*substring*` wildcard would miss. Same tolerant-of-noise
  # style every other assertion in this file already uses.
  [ "$(printf '%s\n' "$output" | grep -cFx "$REPO_ROOT/configs/inputrc")" -eq 1 ]
}

@test "a pre-existing ~/.inputrc is left untouched and INPUTRC is not overridden" {
  export HOME="$BATS_TEST_TMPDIR/home_own_inputrc"
  mkdir -p "$HOME"
  printf 'set editing-mode vi\n' > "$HOME/.inputrc"
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  run bash -i -c 'echo "$INPUTRC"'
  [ "$status" -eq 0 ]
  [[ "$output" != "$REPO_ROOT/configs/inputrc" ]]
  [[ "$(cat "$HOME/.inputrc")" == "set editing-mode vi" ]]
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

# --- aliases parity ---

@test "cat is aliased to batcat when batcat is on PATH (apt's bat package installs the binary as batcat)" {
  export HOME="$BATS_TEST_TMPDIR/home_with_batcat"
  mkdir -p "$HOME/.local/bin"
  printf '#!/usr/bin/env bash\ntrue\n' > "$HOME/.local/bin/batcat"
  chmod +x "$HOME/.local/bin/batcat"
  export PATH="$HOME/.local/bin:$PATH"
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  run bash -i -c 'alias cat'
  [ "$status" -eq 0 ]
  # Exact-line - see the INPUTRC test above for why exact equality
  # against the whole of $output is unsafe, and why a bare substring
  # match is too loose.
  [ "$(printf '%s\n' "$output" | grep -cFx "alias cat='batcat --paging=never'")" -eq 1 ]
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
  # Exact-line - see the INPUTRC test above for why exact equality
  # against the whole of $output is unsafe, and why a bare substring
  # match is too loose.
  [ "$(printf '%s\n' "$output" | grep -cFx "alias fd='fdfind'")" -eq 1 ]
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
  # Exact-line - see the INPUTRC test above for why exact equality
  # against the whole of $output is unsafe, and why a bare substring
  # match is too loose.
  [ "$(printf '%s\n' "$output" | grep -cFx "alias cd='z'")" -eq 1 ]
}

@test "cd is not aliased when zoxide is not on PATH" {
  export HOME="$BATS_TEST_TMPDIR/home_no_zoxide"
  mkdir -p "$HOME"
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  stub_hide_command zoxide
  run bash -i -c 'alias cd'
  [ "$status" -ne 0 ]
}

@test "cd does not trigger zoxide's doctor false positive when starship is also installed" {
  # Needs the real binaries, not stubs: the bug is in how starship's real
  # PROMPT_COMMAND takeover (it clobbers PROMPT_COMMAND down to the
  # literal string "starship_precmd", stashing whatever was there before -
  # including zoxide's own hook - into STARSHIP_PROMPT_COMMAND, which it
  # still `eval`s every prompt) interacts with zoxide's real doctor check
  # (a literal substring search for '__zoxide_hook' in $PROMPT_COMMAND).
  # The hook still fires correctly either way; only the substring check -
  # and thus this false-positive warning - depends on the real init
  # scripts of both tools.
  command -v zoxide &>/dev/null || skip "zoxide not installed on this test host"
  command -v starship &>/dev/null || skip "starship not installed on this test host"
  export HOME="$BATS_TEST_TMPDIR/home_zoxide_doctor"
  mkdir -p "$HOME"
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  run bash -i -c 'cd /tmp'
  [ "$status" -eq 0 ]
  [[ "$output" != *"zoxide: detected a possible configuration issue"* ]]
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

@test "copilot is aliased to autopilot+allow-all mode when copilot is on PATH and the autopilot choice is Yes" {
  export HOME="$BATS_TEST_TMPDIR/home_copilot_autopilot_yes"
  mkdir -p "$HOME/.local/bin" "$HOME/.local/state/omawsl"
  printf '#!/usr/bin/env bash\ntrue\n' > "$HOME/.local/bin/copilot"
  chmod +x "$HOME/.local/bin/copilot"
  printf 'OMAWSL_COPILOT_AUTOPILOT="Yes - autopilot + allow-all"\n' > "$HOME/.local/state/omawsl/choices.env"
  export PATH="$HOME/.local/bin:$PATH"
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  run bash -i -c 'alias copilot'
  [ "$status" -eq 0 ]
  [[ "$output" == *"alias copilot='copilot --autopilot --allow-all'"* ]]
}

@test "copilot is not aliased when the autopilot choice is No" {
  export HOME="$BATS_TEST_TMPDIR/home_copilot_autopilot_no"
  mkdir -p "$HOME/.local/bin" "$HOME/.local/state/omawsl"
  printf '#!/usr/bin/env bash\ntrue\n' > "$HOME/.local/bin/copilot"
  chmod +x "$HOME/.local/bin/copilot"
  printf 'OMAWSL_COPILOT_AUTOPILOT="No - interactive by default (recommended)"\n' > "$HOME/.local/state/omawsl/choices.env"
  export PATH="$HOME/.local/bin:$PATH"
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  run bash -i -c 'alias copilot'
  [ "$status" -ne 0 ]
}

@test "copilot is not aliased when no autopilot choice was ever persisted, even though copilot is on PATH" {
  export HOME="$BATS_TEST_TMPDIR/home_copilot_no_choice"
  mkdir -p "$HOME/.local/bin"
  printf '#!/usr/bin/env bash\ntrue\n' > "$HOME/.local/bin/copilot"
  chmod +x "$HOME/.local/bin/copilot"
  export PATH="$HOME/.local/bin:$PATH"
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  run bash -i -c 'alias copilot'
  [ "$status" -ne 0 ]
}

@test "copilot alias is not defined when copilot is not on PATH, even if the autopilot choice is Yes" {
  export HOME="$BATS_TEST_TMPDIR/home_copilot_missing"
  mkdir -p "$HOME/.local/state/omawsl"
  printf 'OMAWSL_COPILOT_AUTOPILOT="Yes - autopilot + allow-all"\n' > "$HOME/.local/state/omawsl/choices.env"
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  stub_hide_command copilot
  run bash -i -c 'alias copilot'
  [ "$status" -ne 0 ]
}

@test "copilot alias is defined even though copilot is only reachable via \$HOME/.local/bin, added later in the same file (PATH-ordering regression guard)" {
  export HOME="$BATS_TEST_TMPDIR/home_copilot_path_order"
  mkdir -p "$HOME/.local/bin" "$HOME/.local/state/omawsl"
  printf '#!/usr/bin/env bash\ntrue\n' > "$HOME/.local/bin/copilot"
  chmod +x "$HOME/.local/bin/copilot"
  printf 'OMAWSL_COPILOT_AUTOPILOT="Yes - autopilot + allow-all"\n' > "$HOME/.local/state/omawsl/choices.env"
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  run bash -i -c 'alias copilot'
  [ "$status" -eq 0 ]
  [[ "$output" == *"alias copilot='copilot --autopilot --allow-all'"* ]]
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

@test "STARSHIP_CONFIG is unset (starship's real built-in default) when OMAWSL_FONT_MODE is unset and starship is installed" {
  export HOME="$BATS_TEST_TMPDIR/home_no_font_choice_starship"
  mkdir -p "$HOME/.local/bin"
  printf '#!/usr/bin/env bash\ntrue\n' > "$HOME/.local/bin/starship"
  chmod +x "$HOME/.local/bin/starship"
  export PATH="$HOME/.local/bin:$PATH"
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  run bash -i -c 'echo "STARSHIP_CONFIG=${STARSHIP_CONFIG:-unset}"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"STARSHIP_CONFIG=unset"* ]]
}

@test "STARSHIP_CONFIG is unset when OMAWSL_FONT_MODE is Nerd Font and starship is installed" {
  export HOME="$BATS_TEST_TMPDIR/home_nerd_font_starship"
  mkdir -p "$HOME/.local/state/omawsl" "$HOME/.local/bin"
  printf 'OMAWSL_FONT_MODE="Nerd Font (enhanced)"\n' > "$HOME/.local/state/omawsl/choices.env"
  printf '#!/usr/bin/env bash\ntrue\n' > "$HOME/.local/bin/starship"
  chmod +x "$HOME/.local/bin/starship"
  export PATH="$HOME/.local/bin:$PATH"
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  run bash -i -c 'echo "STARSHIP_CONFIG=${STARSHIP_CONFIG:-unset}"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"STARSHIP_CONFIG=unset"* ]]
}

@test "STARSHIP_CONFIG points at the plain preset when OMAWSL_FONT_MODE is Cascadia Mono and starship is installed" {
  export HOME="$BATS_TEST_TMPDIR/home_cascadia_starship"
  mkdir -p "$HOME/.local/state/omawsl" "$HOME/.local/bin"
  printf 'OMAWSL_FONT_MODE="Cascadia Mono (zero install)"\n' > "$HOME/.local/state/omawsl/choices.env"
  printf '#!/usr/bin/env bash\ntrue\n' > "$HOME/.local/bin/starship"
  chmod +x "$HOME/.local/bin/starship"
  export PATH="$HOME/.local/bin:$PATH"
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  run bash -i -c 'echo "$STARSHIP_CONFIG"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"$HOME/.config/starship-plain.toml"* ]]
}

@test "STARSHIP_CONFIG does not leak across a re-source after OMAWSL_FONT_MODE changes" {
  export HOME="$BATS_TEST_TMPDIR/home_starship_resource"
  mkdir -p "$HOME/.local/state/omawsl" "$HOME/.local/bin"
  printf 'OMAWSL_FONT_MODE="Cascadia Mono (zero install)"\n' > "$HOME/.local/state/omawsl/choices.env"
  printf '#!/usr/bin/env bash\ntrue\n' > "$HOME/.local/bin/starship"
  chmod +x "$HOME/.local/bin/starship"
  export PATH="$HOME/.local/bin:$PATH"
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  # Same repro as the reviewer's: source once under Cascadia Mono (sets
  # STARSHIP_CONFIG), flip choices.env to Nerd Font, then source again in
  # the same shell (e.g. a fresh `install.sh` run, or `omawsl migrate`
  # updating choices.env followed by `source ~/.bashrc`) - the stale
  # export must not survive into the second source.
  run bash -i -c '
    source "$HOME/.bashrc"
    printf "OMAWSL_FONT_MODE=\"Nerd Font (enhanced)\"\n" > "$HOME/.local/state/omawsl/choices.env"
    source "$HOME/.bashrc"
    echo "STARSHIP_CONFIG=${STARSHIP_CONFIG:-unset}"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"STARSHIP_CONFIG=unset"* ]]
}

@test "falls back to the legacy icon-only PS1 when starship is not on PATH" {
  export HOME="$BATS_TEST_TMPDIR/home_no_starship"
  mkdir -p "$HOME"
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  stub_hide_command starship
  run bash -i -c 'echo "$PS1"'
  [ "$status" -eq 0 ]
  [[ "$output" != *'\u@\h'* ]]
  [[ "$output" == *'\[\e]0;\w\a\]'* ]]
}

@test "falls back to the legacy Cascadia Mono PS1 when starship is not on PATH" {
  export HOME="$BATS_TEST_TMPDIR/home_no_starship_cascadia"
  mkdir -p "$HOME/.local/state/omawsl"
  printf 'OMAWSL_FONT_MODE="Cascadia Mono (zero install)"\n' > "$HOME/.local/state/omawsl/choices.env"
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  stub_hide_command starship
  run bash -i -c 'echo "$PS1"'
  [ "$status" -eq 0 ]
  [[ "$output" == *'\u@\h:\w\$ '* ]]
  [[ "$output" == *'\[\e]0;\w\a\]'* ]]
}

@test "starship init runs after zoxide/mise activation in configs/bashrc, not before" {
  local file="$REPO_ROOT/configs/bashrc"
  local zoxide_line mise_line starship_line
  zoxide_line="$(grep -n 'zoxide init bash' "$file" | cut -d: -f1)"
  mise_line="$(grep -n 'mise activate bash' "$file" | cut -d: -f1)"
  starship_line="$(grep -n 'starship init bash' "$file" | cut -d: -f1)"
  [ -n "$zoxide_line" ]
  [ -n "$mise_line" ]
  [ -n "$starship_line" ]
  [ "$starship_line" -gt "$zoxide_line" ]
  [ "$starship_line" -gt "$mise_line" ]
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

@test "sets ZELLIJ_SOCKET_DIR to a /tmp path before exec'ing zellij (WSL2/WSLg XDG_RUNTIME_DIR workaround)" {
  # Regression guard for microsoft/WSL#9689/#10896/#11542 + zellij-org/zellij#4155:
  # WSLg's $XDG_RUNTIME_DIR mount doesn't reliably support the chmod zellij
  # needs on its own socket dir, causing a raw Rust panic instead of a
  # graceful error. bashrc must override ZELLIJ_SOCKET_DIR to sidestep it.
  unset ZELLIJ
  export HOME="$BATS_TEST_TMPDIR/home_zellij_socket_dir"
  mkdir -p "$HOME/.local/bin"
  cat > "$HOME/.local/bin/zellij" <<'EOF'
#!/usr/bin/env bash
echo "$ZELLIJ_SOCKET_DIR" > "$HOME/zellij_socket_dir_seen"
EOF
  chmod +x "$HOME/.local/bin/zellij"
  export PATH="$HOME/.local/bin:$PATH"
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  run bash -i -c 'true'
  [ "$status" -eq 0 ]
  [ -f "$HOME/zellij_socket_dir_seen" ]
  [[ "$(cat "$HOME/zellij_socket_dir_seen")" == "/tmp/zellij-$(id -u)" ]]
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
