#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/bin/omawsl-sub/theme.sh"
}

@test "omawsl_theme_names lists all 10 themes" {
  [[ "$(omawsl_theme_names | wc -l)" -eq 10 ]]
  [[ "$(omawsl_theme_names)" == *"tokyo-night"* ]]
  [[ "$(omawsl_theme_names)" == *"rose-pine"* ]]
}

@test "omawsl_theme_is_valid accepts real theme names and rejects unknown ones" {
  omawsl_theme_is_valid "tokyo-night"
  omawsl_theme_is_valid "rose-pine"
  ! omawsl_theme_is_valid "not-a-real-theme"
}

@test "omawsl_theme_display_name title-cases hyphenated folder names" {
  [[ "$(omawsl_theme_display_name "rose-pine")" == "Rose Pine" ]]
  [[ "$(omawsl_theme_display_name "tokyo-night")" == "Tokyo Night" ]]
  [[ "$(omawsl_theme_display_name "osaka-jade")" == "Osaka Jade" ]]
  [[ "$(omawsl_theme_display_name "catppuccin")" == "Catppuccin" ]]
}

@test "omawsl_theme_folder_name reverses omawsl_theme_display_name and is idempotent on folder form" {
  [[ "$(omawsl_theme_folder_name "Rose Pine")" == "rose-pine" ]]
  [[ "$(omawsl_theme_folder_name "rose-pine")" == "rose-pine" ]]
}

@test "omawsl_theme_apply rejects an unknown theme name without touching anything" {
  run omawsl_theme_apply "not-a-real-theme"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown theme"* ]]
  [ ! -d "$HOME/.config/zellij" ]
}

@test "omawsl_theme_apply copies the zellij/btop theme files and patches the active references" {
  mkdir -p "$HOME/.config/zellij" "$HOME/.config/btop"
  cp "$REPO_ROOT/configs/zellij.kdl" "$HOME/.config/zellij/config.kdl"
  cp "$REPO_ROOT/configs/btop.conf" "$HOME/.config/btop/btop.conf"

  run omawsl_theme_apply "tokyo-night"
  [ "$status" -eq 0 ]

  diff "$HOME/.config/zellij/themes/tokyo-night.kdl" "$REPO_ROOT/themes/tokyo-night/zellij.kdl"
  grep -q 'theme "tokyo-night"' "$HOME/.config/zellij/config.kdl"

  diff "$HOME/.config/btop/themes/tokyo-night.theme" "$REPO_ROOT/themes/tokyo-night/btop.theme"
  grep -q 'color_theme = "tokyo-night"' "$HOME/.config/btop/btop.conf"
}

@test "omawsl_theme_apply only touches neovim's theme.lua when ~/.config/nvim exists" {
  run omawsl_theme_apply "tokyo-night"
  [ "$status" -eq 0 ]
  [ ! -f "$HOME/.config/nvim/lua/plugins/theme.lua" ]

  mkdir -p "$HOME/.config/nvim"
  run omawsl_theme_apply "tokyo-night"
  [ "$status" -eq 0 ]
  diff "$HOME/.config/nvim/lua/plugins/theme.lua" "$REPO_ROOT/themes/tokyo-night/neovim.lua"
}

@test "omawsl_theme_apply syncs the Windows Terminal scheme via omawsl_theme_apply_windows_terminal" {
  omawsl_theme_apply_windows_terminal() { echo "windows-terminal-sync-called $1" >> "$STUB_LOG"; }
  export -f omawsl_theme_apply_windows_terminal
  run omawsl_theme_apply "tokyo-night"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"windows-terminal-sync-called $REPO_ROOT/themes/tokyo-night/windows-terminal-scheme.json"* ]]
}

@test "omawsl_theme_opencode_preset maps the 6 themes with a real opencode built-in preset" {
  [[ "$(omawsl_theme_opencode_preset "tokyo-night")" == "tokyonight" ]]
  [[ "$(omawsl_theme_opencode_preset "everforest")" == "everforest" ]]
  [[ "$(omawsl_theme_opencode_preset "catppuccin")" == "catppuccin" ]]
  [[ "$(omawsl_theme_opencode_preset "gruvbox")" == "gruvbox" ]]
  [[ "$(omawsl_theme_opencode_preset "kanagawa")" == "kanagawa" ]]
  [[ "$(omawsl_theme_opencode_preset "nord")" == "nord" ]]
}

@test "omawsl_theme_opencode_preset fails for the 4 themes with no built-in opencode preset" {
  ! omawsl_theme_opencode_preset "matte-black"
  ! omawsl_theme_opencode_preset "osaka-jade"
  ! omawsl_theme_opencode_preset "ristretto"
  ! omawsl_theme_opencode_preset "rose-pine"
}

@test "omawsl_theme_apply_opencode sets the theme key when opencode is reachable and a preset exists" {
  command -v jq &>/dev/null || skip "jq not installed on this test host"
  stub_command opencode
  run omawsl_theme_apply_opencode "tokyo-night"
  [ "$status" -eq 0 ]
  [[ "$(jq -r .theme "$HOME/.config/opencode/tui.json")" == "tokyonight" ]]
}

@test "omawsl_theme_apply_opencode no-ops when opencode isn't reachable" {
  stub_hide_command opencode
  run omawsl_theme_apply_opencode "tokyo-night"
  [ "$status" -eq 0 ]
  [ ! -f "$HOME/.config/opencode/tui.json" ]
}

@test "omawsl_theme_apply_opencode no-ops for a theme with no built-in opencode preset" {
  stub_command opencode
  run omawsl_theme_apply_opencode "rose-pine"
  [ "$status" -eq 0 ]
  [ ! -f "$HOME/.config/opencode/tui.json" ]
}

@test "omawsl_theme_command applies the exact theme name given on the command line" {
  omawsl_theme_apply() { echo "apply-called $1" >> "$STUB_LOG"; }
  export -f omawsl_theme_apply
  run omawsl_theme_command "rose-pine"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"apply-called rose-pine"* ]]
}

@test "omawsl_theme_command accepts the Title Case display form too" {
  omawsl_theme_apply() { echo "apply-called $1" >> "$STUB_LOG"; }
  export -f omawsl_theme_apply
  run omawsl_theme_command "Rose Pine"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"apply-called rose-pine"* ]]
}

@test "omawsl_theme_command with no args prompts via gum and applies the chosen theme" {
  omawsl_theme_apply() { echo "apply-called $1" >> "$STUB_LOG"; }
  export -f omawsl_theme_apply
  gum_stub_init
  gum_stub_respond "Tokyo Night"
  run omawsl_theme_command
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"apply-called tokyo-night"* ]]
}

@test "bin/omawsl theme with a valid name applies it end to end (real jq, real files)" {
  command -v jq &>/dev/null || skip "jq not installed on this test host"
  mkdir -p "$HOME/.config/zellij" "$HOME/.config/btop"
  cp "$REPO_ROOT/configs/zellij.kdl" "$HOME/.config/zellij/config.kdl"
  cp "$REPO_ROOT/configs/btop.conf" "$HOME/.config/btop/btop.conf"
  run bash "$REPO_ROOT/bin/omawsl" theme tokyo-night
  [ "$status" -eq 0 ]
  [ -f "$HOME/.config/zellij/themes/tokyo-night.kdl" ]
}

@test "bin/omawsl with an unknown command prints usage and exits non-zero" {
  run bash "$REPO_ROOT/bin/omawsl" not-a-real-command
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown command"* ]]
  [[ "$output" == *"Usage: omawsl"* ]]
}

@test "bin/omawsl with no args prints usage and exits zero" {
  run bash "$REPO_ROOT/bin/omawsl"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: omawsl"* ]]
}
