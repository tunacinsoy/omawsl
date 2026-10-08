#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  DOC="$REPO_ROOT/docs/keys.md"
  # Plain cat output, so tests can match the doc's text as written.
  stub_hide_command batcat
  source "$REPO_ROOT/bin/omawsl-sub/keys.sh"
}

# Every chord docs/keys.md lists in backticks, one per line, with
# "Alt h/j/k/l" expanded to "Alt h" ... "Alt l".
doc_chords() {
  grep -oE '`[^`]+`' "$DOC" | tr -d '`' | while read -r span; do
    local head="${span% *}" last="${span##* }" k
    [[ "$span" == *" "* ]] || { echo "$span"; continue; }
    IFS=/ read -ra ks <<<"$last"
    for k in "${ks[@]}"; do echo "$head $k"; done
  done
}

# herdr.toml spelling -> docs spelling: prefix+g -> "Ctrl g g",
# alt+left -> "Alt ←", alt+minus -> "Alt -", prefix+1..9 -> "Ctrl g 1-9".
herdr_to_doc() {
  sed -E 's/^prefix\+/Ctrl g /; s/(^| )alt\+/\1Alt /; s/(^| )ctrl\+/\1Ctrl /;
    s/left$/←/; s/right$/→/; s/up$/↑/; s/down$/↓/;
    s/minus$/-/; s/comma$/,/; s/1\.\.9$/1-9/'
}

@test "omawsl keys prints every section" {
  run omawsl_keys_command
  [ "$status" -eq 0 ]
  for s in "zellij" "Herdr" "Shell" "Claude Code" "Neovim" "lazygit" "lazydocker" "btop"; do
    [[ "$output" == *"## "*"$s"* ]] || { echo "missing section: $s"; return 1; }
  done
}

@test "omawsl keys <tool> prints only that tool's section" {
  run omawsl_keys_command lazygit
  [ "$status" -eq 0 ]
  [[ "$output" == *"## lazygit"* ]]
  [[ "$output" != *"## Shell"* ]]
  [[ "$output" != *"## lazydocker"* ]]
}

@test "omawsl keys herdr and omawsl keys zellij both show the multiplexer keys" {
  run omawsl_keys_command herdr
  [[ "$output" == *"Ctrl g g"* ]]
  [[ "$output" != *"## Shell"* ]]
  run omawsl_keys_command zellij
  [[ "$output" == *"Alt n"* ]]
}

@test "omawsl keys nvim finds the Neovim section" {
  run omawsl_keys_command nvim
  [ "$status" -eq 0 ]
  [[ "$output" == *"## Neovim"* ]]
}

@test "omawsl keys with an unknown section fails and lists the valid ones" {
  run omawsl_keys_command nope
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown section 'nope'"* ]]
  [[ "$output" == *"lazygit"* ]]
}

@test "omawsl keys colors the cheatsheet with batcat when it's installed" {
  stub_command batcat
  run omawsl_keys_command shell
  [[ "$(stub_calls)" == *"batcat "*"--language=markdown"* ]]
}

@test "bin/omawsl keys runs end to end" {
  run bash "$REPO_ROOT/bin/omawsl" keys shell
  [ "$status" -eq 0 ]
  [[ "$output" == *"Ctrl r"* ]]
}

@test "every key configs/herdr.toml binds is in docs/keys.md" {
  local chords missing="" k
  chords="$(doc_chords)"
  while read -r k; do
    grep -qxF "$k" <<<"$chords" || missing+="$k"$'\n'
  done < <(grep -vE '^\s*#' "$REPO_ROOT/configs/herdr.toml" |
    grep -oE '"(prefix|alt|ctrl)\+[^"]+"' | tr -d '"' | herdr_to_doc | sort -u)
  [[ -z "$missing" ]] || { echo "not in docs/keys.md:"; echo "$missing"; return 1; }
}

@test "every Alt chord configs/zellij.kdl binds is in docs/keys.md" {
  local chords missing="" k
  chords="$(doc_chords)"
  while read -r k; do
    grep -qxF "$k" <<<"$chords" || missing+="$k"$'\n'
  done < <(grep -oE 'bind "Alt [^"]+"' "$REPO_ROOT/configs/zellij.kdl" |
    sed -E 's/bind "(.*)"/\1/; s/Left$/←/; s/Right$/→/; s/Up$/↑/; s/Down$/↓/' | sort -u)
  [[ -z "$missing" ]] || { echo "not in docs/keys.md:"; echo "$missing"; return 1; }
}

@test "README and docs/herdr.md point at omawsl keys" {
  grep -q "omawsl keys" "$REPO_ROOT/README.md"
  grep -q "docs/keys.md\|omawsl keys" "$REPO_ROOT/docs/herdr.md"
}
