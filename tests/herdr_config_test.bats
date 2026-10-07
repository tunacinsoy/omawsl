#!/usr/bin/env bats

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
CONFIG="$REPO_ROOT/configs/herdr.toml"

@test "configs/herdr.toml uses Ctrl g as Herdr's prefix, zellij.kdl's own unlock key" {
  grep -qx 'prefix = "ctrl+g"' "$CONFIG"
  grep -q 'bind "Ctrl g" { SwitchToMode "normal"; }' "$REPO_ROOT/configs/zellij.kdl"
}

@test "every helper command points at the checkout via the @OMAWSL_ROOT@ placeholder" {
  run grep -c '^command = "@OMAWSL_ROOT@/bin/omawsl-herdr-mode ' "$CONFIG"
  [ "$output" -eq 11 ]
  ! grep -q '\$HOME/.local/share/omawsl' "$CONFIG"
  [ -x "$REPO_ROOT/bin/omawsl-herdr-mode" ]
}

@test "each zellij mode letter opens its own popup" {
  local pair
  for pair in p:pane t:tab r:resize m:move o:session; do
    grep -A2 "^key = \"prefix+${pair%%:*}\"" "$CONFIG" | grep -q "omawsl-herdr-mode ${pair#*:}\"" \
      || { echo "missing popup for $pair"; return 1; }
  done
}

@test "herdr config check accepts configs/herdr.toml" {
  command -v herdr &>/dev/null || skip "herdr not installed on this test host"
  run env HERDR_CONFIG_PATH="$CONFIG" herdr config check
  [[ "$output" == "config: ok"* ]]
}

@test "binds no key spelling Herdr 0.9's client rejects" {
  # "alt+plus" passes `herdr config check` but the client rewrites it to
  # "alt++" and disables it; "+" can't be bound at all, so Alt = (zellij.kdl's
  # own twin of Alt +) carries "grow" alone.
  ! grep -vE '^[[:space:]]*#' "$CONFIG" | grep -qE '"[^"]*\+plus"|"[^"]*\+\+"'
}
