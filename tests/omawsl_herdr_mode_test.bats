#!/usr/bin/env bats

load 'helpers/stubs'

TWO_TABS='[{"tab_id":"w1:t1","number":1,"focused":true},{"tab_id":"w1:t2","number":2,"focused":false}]'

setup() {
  stub_init
  command -v jq &>/dev/null || skip "jq not installed on this test host"
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  MODE="$REPO_ROOT/bin/omawsl-herdr-mode"
  export HERDR_BIN_PATH="$BATS_TEST_TMPDIR/herdr"
  unset STUB_TAB STUB_TABS STUB_PANES STUB_NEIGHBOR_left STUB_NEIGHBOR_right STUB_NEIGHBOR_up STUB_NEIGHBOR_down
  cat > "$HERDR_BIN_PATH" <<'EOF'
#!/usr/bin/env bash
echo "herdr $*" >> "$STUB_LOG"
# Defaults live in variables: a literal JSON default inside ${VAR:-...}
# would end the expansion at its first "}".
default_panes='[{"pane_id":"w1:p1","rect":{"width":120,"height":40}}]'
default_tabs='[{"tab_id":"w1:t1","number":1,"focused":true}]'
dir=""
for ((i = 1; i <= $#; i++)); do
  if [[ ${!i} == --direction ]]; then j=$((i + 1)); dir=${!j}; fi
done
case "$1 $2" in
  "pane list")
    printf '{"result":{"panes":[{"pane_id":"w1:p1","tab_id":"%s","workspace_id":"w1","focused":true}]}}\n' "${STUB_TAB:-w1:t1}" ;;
  "pane layout")
    printf '{"result":{"layout":{"panes":%s}}}\n' "${STUB_PANES:-$default_panes}" ;;
  "pane neighbor")
    v="STUB_NEIGHBOR_$dir"
    if [[ -n ${!v:-} ]]; then
      printf '{"result":{"neighbor":{"neighbor_pane_id":"%s"}}}\n' "${!v}"
    else
      echo '{"result":{"neighbor":{}}}'
    fi ;;
  "tab list")
    printf '{"result":{"tabs":%s}}\n' "${STUB_TABS:-$default_tabs}" ;;
  *) echo '{}' ;;
esac
EOF
  chmod +x "$HERDR_BIN_PATH"
}

@test "pane mode: d splits the focused pane down" {
  run bash -c "printf d | '$MODE' pane"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"herdr pane split --pane w1:p1 --direction down --focus"* ]]
}

@test "pane mode: hjkl focus is sticky until Esc" {
  run bash -c "printf 'hl\e' | '$MODE' pane"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"herdr pane focus --pane w1:p1 --direction left"* ]]
  [[ "$(stub_calls)" == *"herdr pane focus --pane w1:p1 --direction right"* ]]
}

@test "Esc, Enter and Ctrl g leave a mode without acting" {
  local k
  for k in '\e' '\n' '\a'; do
    run bash -c "printf '$k' | '$MODE' pane"
    [ "$status" -eq 0 ]
  done
  [[ "$(stub_calls)" != *"pane split"* ]]
  [[ "$(stub_calls)" != *"pane focus"* ]]
  [[ "$(stub_calls)" != *"pane close"* ]]
}

@test "Enter sent as a carriage return (how real terminals send it) leaves a mode" {
  export STUB_TABS='[{"tab_id":"w1:t1","number":1,"focused":true},{"tab_id":"w1:t2","number":2,"focused":false}]'
  # l switches tab, then Enter must end the popup - the trailing x would
  # otherwise close the tab.
  run bash -c "printf 'l\rx' | '$MODE' tab"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"herdr tab focus w1:t2"* ]]
  [[ "$(stub_calls)" != *"tab close"* ]]
}

@test "new-pane splits right in a wide pane and down in a tall one" {
  run "$MODE" new-pane
  [[ "$(stub_calls)" == *"pane split --pane w1:p1 --direction right --focus"* ]]
  export STUB_PANES='[{"pane_id":"w1:p1","rect":{"width":60,"height":40}}]'
  run "$MODE" new-pane
  [[ "$(stub_calls)" == *"pane split --pane w1:p1 --direction down --focus"* ]]
}

@test "focus-or-tab moves focus when there's a neighbor that way" {
  export STUB_NEIGHBOR_left=w1:p2
  run "$MODE" focus-or-tab left
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"herdr pane focus --pane w1:p1 --direction left"* ]]
  [[ "$(stub_calls)" != *"tab focus"* ]]
}

@test "focus-or-tab switches tab at the edge, wrapping like zellij" {
  export STUB_TABS="$TWO_TABS"
  run "$MODE" focus-or-tab left
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"herdr tab focus w1:t2"* ]]
}

@test "tab mode: a digit jumps to that tab number" {
  export STUB_TABS="$TWO_TABS"
  run bash -c "printf 2 | '$MODE' tab"
  [[ "$(stub_calls)" == *"herdr tab focus w1:t2"* ]]
}

@test "tab mode: [ at the first tab breaks the pane into a new tab instead of wrapping" {
  export STUB_TABS="$TWO_TABS"
  run bash -c "printf '[' | '$MODE' tab"
  [[ "$(stub_calls)" == *"herdr pane move w1:p1 --new-tab --focus"* ]]
  [[ "$(stub_calls)" != *"--tab w1:t2"* ]]
}

@test "tab mode: ] moves the pane into the next tab" {
  export STUB_TABS="$TWO_TABS"
  run bash -c "printf ']' | '$MODE' tab"
  [[ "$(stub_calls)" == *"herdr pane move w1:p1 --tab w1:t2 --split right --focus"* ]]
}

@test "resize mode: l grows toward a right neighbor, L shrinks from it" {
  export STUB_NEIGHBOR_right=w1:p2
  run bash -c "printf 'lLr' | '$MODE' resize"
  [[ "$(stub_calls)" == *"herdr pane resize --pane w1:p1 --direction right"* ]]
  [[ "$(stub_calls)" == *"herdr pane resize --pane w1:p1 --direction left"* ]]
}

@test "resize mode: does nothing toward a side with no neighbor" {
  run bash -c "printf 'hr' | '$MODE' resize"
  [[ "$(stub_calls)" != *"pane resize"* ]]
}

@test "move mode: h swaps with the pane to the left" {
  run bash -c "printf 'h\e' | '$MODE' move"
  [[ "$(stub_calls)" == *"herdr pane swap --pane w1:p1 --direction left"* ]]
}

@test "tab mode: hjkl switches tab and closes the popup" {
  # Unlike zellij, not sticky: Herdr 0.9 keeps placing popups on the old
  # tab once a running popup switches tabs, so later popups open where the
  # user can't see them. Switching and exiting together avoids that.
  export STUB_TABS="$TWO_TABS"
  run bash -c "printf 'lx' | '$MODE' tab"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"herdr tab focus w1:t2"* ]]
  [[ "$(stub_calls)" != *"tab close"* ]]
}

@test "rejects an unknown mode with usage and exit 2" {
  run "$MODE" not-a-mode
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage: omawsl-herdr-mode"* ]]
}
