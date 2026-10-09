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

@test "workspaces switch from the prefix, clear of Herdr's swap_pane defaults" {
  grep -qx 'previous_workspace = "prefix+\["' "$CONFIG"
  grep -qx 'next_workspace = "prefix+\]"' "$CONFIG"
  ! grep -qE '^(previous|next)_workspace = "prefix\+shift\+[hjkl]"' "$CONFIG"
}

@test "workspace numbers use plain digits, which work on any keyboard layout" {
  # Herdr matches prefix+shift+N against the US-layout character, so Shift 2
  # is dead on Turkish Q (') or UK/German ("). Herdr's own prefix+1..9 for
  # tabs is turned off - tabs keep zellij's Ctrl g t 1-9.
  grep -qx 'switch_workspace = "prefix+1..9"' "$CONFIG"
  grep -qx 'switch_tab = ""' "$CONFIG"
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

@test "the sidebar shows what each Claude agent is working on" {
  # Claude Code puts a short task summary in its terminal title - zellij
  # showed it in the pane frame. Herdr's border label only says "claude",
  # so the sidebar row carries the summary instead.
  grep -qx '\[ui.sidebar.agents.rows_by_agent\]' "$CONFIG"
  grep -A1 '^\[ui.sidebar.agents.rows_by_agent\]' "$CONFIG" | grep -qE '^claude = .*"terminal_title_stripped"'
}

@test "agent states show as distinct symbols, not just colored dots" {
  # Dots only differ by color; symbols tell blocked / working / done /
  # idle apart by shape too.
  grep -A10 '^\[ui\]' "$CONFIG" | grep -qx 'status_indicators = "symbols"'
}
