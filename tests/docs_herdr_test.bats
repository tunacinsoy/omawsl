#!/usr/bin/env bats

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

@test "README describes omawsl's own theme set, not 'ten ported Omakub themes'" {
  ! grep -qi "ten ported omakub themes" "$REPO_ROOT/README.md"
  grep -q "Dracula" "$REPO_ROOT/README.md"
  grep -q "One Dark" "$REPO_ROOT/README.md"
  grep -q "Solarized" "$REPO_ROOT/README.md"
}

@test "README points Herdr users at docs/herdr.md and omawsl multiplexer" {
  grep -q "docs/herdr.md" "$REPO_ROOT/README.md"
  grep -q "omawsl multiplexer" "$REPO_ROOT/README.md"
}

@test "docs/herdr.md documents the keymap and every known difference" {
  local doc="$REPO_ROOT/docs/herdr.md"
  for s in "Ctrl g" "Ctrl g q" "copy mode" "Alt f" "omawsl multiplexer zellij" "preview"; do
    grep -qF "$s" "$doc" || { echo "missing: $s"; return 1; }
  done
}

@test "docs/herdr.md documents omawsl notifications and its limits" {
  local doc="$REPO_ROOT/docs/herdr.md"
  for s in "omawsl notifications" "pulseaudio-utils" "notify-send" "WSLg" "not** looking at"; do
    grep -qF "$s" "$doc" || { echo "missing: $s"; return 1; }
  done
}

@test "docs/herdr.md explains scrolling Claude chats and the agent summary" {
  local doc="$REPO_ROOT/docs/herdr.md"
  for s in "PgUp" "Ctrl+End" "Ctrl+o" "sidebar"; do
    grep -qF "$s" "$doc" || { echo "missing: $s"; return 1; }
  done
}
