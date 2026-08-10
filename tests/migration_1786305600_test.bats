#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  stub_command sudo
  stub_command curl
  stub_command tar
  stub_hide_command starship
}

@test "installs starship and the default plain config when starship isn't already present" {
  run bash "$REPO_ROOT/migrations/1786305600.sh"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"sudo install -m 0755 /tmp/starship /usr/local/bin/starship"* ]]
  diff "$HOME/.config/starship-plain.toml" "$REPO_ROOT/configs/starship-plain.toml"
}

@test "skips the starship install when it's already present" {
  stub_command starship
  run bash "$REPO_ROOT/migrations/1786305600.sh"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"/usr/local/bin/starship"* ]]
}

@test "no-ops the theme re-apply step cleanly when zellij was never installed/configured at all" {
  run bash "$REPO_ROOT/migrations/1786305600.sh"
  [ "$status" -eq 0 ]
  [ ! -f "$HOME/.config/starship.toml" ]
}

@test "leaves the plain un-themed defaults in place for an install that never actually ran 'omawsl theme', even though config.kdl still names the stock tokyo-night reference" {
  mkdir -p "$HOME/.config/zellij"
  cp "$REPO_ROOT/configs/zellij.kdl" "$HOME/.config/zellij/config.kdl"
  run bash "$REPO_ROOT/migrations/1786305600.sh"
  [ "$status" -eq 0 ]
  [ ! -f "$HOME/.config/starship.toml" ]
}

@test "re-applies the theme when the user genuinely ran 'omawsl theme' before (its real theme file exists)" {
  mkdir -p "$HOME/.config/zellij/themes"
  cp "$REPO_ROOT/configs/zellij.kdl" "$HOME/.config/zellij/config.kdl"
  sed -i 's/theme ".*"/theme "rose-pine"/g' "$HOME/.config/zellij/config.kdl"
  cp "$REPO_ROOT/themes/rose-pine/zellij.kdl" "$HOME/.config/zellij/themes/rose-pine.kdl"
  run bash "$REPO_ROOT/migrations/1786305600.sh"
  [ "$status" -eq 0 ]
  diff "$HOME/.config/starship.toml" "$REPO_ROOT/themes/rose-pine/starship.toml"
  diff "$HOME/.config/starship-plain.toml" "$REPO_ROOT/themes/rose-pine/starship-plain.toml"
}

@test "exits 0 (not 1) and no-ops the theme re-apply step when config.kdl exists but has no theme line at all" {
  mkdir -p "$HOME/.config/zellij"
  grep -v '^theme "' "$REPO_ROOT/configs/zellij.kdl" > "$HOME/.config/zellij/config.kdl"
  run bash "$REPO_ROOT/migrations/1786305600.sh"
  [ "$status" -eq 0 ]
  [ ! -f "$HOME/.config/starship.toml" ]
}
