#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OMAWSL_ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../../install/lib.sh
source "$OMAWSL_ROOT_DIR/install/lib.sh"
# shellcheck source=windows-terminal.sh
source "$SCRIPT_DIR/windows-terminal.sh"

# omawsl_theme_names
# The 10 ported theme folder names, in Omakub's own picker order
# (design spec §11).
omawsl_theme_names() {
  cat <<'EOF'
catppuccin
everforest
gruvbox
kanagawa
matte-black
nord
osaka-jade
ristretto
rose-pine
tokyo-night
EOF
}

# omawsl_theme_is_valid <folder_name>
omawsl_theme_is_valid() {
  omawsl_theme_names | grep -qx "$1"
}

# omawsl_theme_display_name <folder_name>
# Title-cases a folder name back to Omakub's own gum choose label (e.g.
# "rose-pine" -> "Rose Pine").
omawsl_theme_display_name() {
  echo "$1" | sed -E 's/(^|-)([a-z])/\1\U\2/g; s/-/ /g'
}

# omawsl_theme_folder_name <name>
# Reverses omawsl_theme_display_name - lower-cases and hyphenates,
# exactly what Omakub's own theme.sh does to its gum choose result.
# Idempotent on input that's already in folder form.
omawsl_theme_folder_name() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | tr ' ' '-'
}

# omawsl_theme_opencode_preset <folder_name>
# Maps omawsl's theme folder names to opencode's own built-in preset
# names (opencode.ai/docs/themes/, ~/.config/opencode/tui.json's
# "theme" key) where a direct match exists. Fails (empty stdout,
# nonzero exit) for the 4 themes with no built-in opencode preset
# (matte-black, osaka-jade, ristretto, rose-pine) - design spec §11
# marks opencode theming "best-effort... skipped rather than forcing a
# workaround" for exactly this kind of gap; opencode's separate
# custom-theme JSON format for arbitrary colors is a different,
# unverified schema and out of scope here.
omawsl_theme_opencode_preset() {
  case "$1" in
    tokyo-night) echo "tokyonight" ;;
    everforest) echo "everforest" ;;
    catppuccin) echo "catppuccin" ;;
    gruvbox) echo "gruvbox" ;;
    kanagawa) echo "kanagawa" ;;
    nord) echo "nord" ;;
    *) return 1 ;;
  esac
}

# omawsl_theme_apply_opencode <folder_name>
# Sets opencode's own "theme" key when opencode is reachable and this
# theme has a built-in opencode preset (see
# omawsl_theme_opencode_preset above) - no-ops otherwise, same
# detect-and-defer shape as every other optional component this
# function touches.
omawsl_theme_apply_opencode() {
  local name="$1"
  command -v opencode &>/dev/null || return 0
  command -v jq &>/dev/null || return 0

  local preset
  preset="$(omawsl_theme_opencode_preset "$name")" || return 0

  local config_file="$HOME/.config/opencode/tui.json"
  mkdir -p "$(dirname "$config_file")"
  if [[ ! -f "$config_file" ]]; then
    echo '{"$schema": "https://opencode.ai/tui.json"}' > "$config_file"
  fi

  local tmp
  tmp="$(mktemp)"
  jq --arg theme "$preset" '.theme = $theme' "$config_file" > "$tmp"
  mv "$tmp" "$config_file"
}

# omawsl_theme_apply <folder_name>
# Applies one theme across every installed component, matching Omakub's
# own bin/omakub-sub/theme.sh (design spec §11): zellij (per-theme file
# + sed-patch the active reference), btop (same shape), Neovim (only if
# ~/.config/nvim exists - Phase 4's app-neovim.sh only creates it when
# Neovim was selected), VS Code/Cursor (via each theme's own vscode.sh,
# which sources themes/set-vscode-theme.sh - Task 2), opencode (only
# for the 6 themes with a built-in preset - see
# omawsl_theme_apply_opencode above), and Windows Terminal (Task 6).
omawsl_theme_apply() {
  local name="$1"
  local theme_dir="$OMAWSL_ROOT_DIR/themes/$name"

  if ! omawsl_theme_is_valid "$name"; then
    echo "omawsl: unknown theme '$name'" >&2
    echo "Valid themes: $(omawsl_theme_names | tr '\n' ' ')" >&2
    return 1
  fi

  mkdir -p "$HOME/.config/zellij/themes"
  cp "$theme_dir/zellij.kdl" "$HOME/.config/zellij/themes/$name.kdl"
  if [[ -f "$HOME/.config/zellij/config.kdl" ]]; then
    sed -i "s/theme \".*\"/theme \"$name\"/g" "$HOME/.config/zellij/config.kdl"
  fi

  if [[ -f "$HOME/.config/btop/btop.conf" ]]; then
    mkdir -p "$HOME/.config/btop/themes"
    cp "$theme_dir/btop.theme" "$HOME/.config/btop/themes/$name.theme"
    sed -i "s/color_theme = \".*\"/color_theme = \"$name\"/g" "$HOME/.config/btop/btop.conf"
  fi

  if [[ -d "$HOME/.config/nvim" ]]; then
    mkdir -p "$HOME/.config/nvim/lua/plugins"
    cp "$theme_dir/neovim.lua" "$HOME/.config/nvim/lua/plugins/theme.lua"
  fi

  # shellcheck source=/dev/null
  source "$theme_dir/vscode.sh"

  omawsl_theme_apply_opencode "$name"

  omawsl_theme_apply_windows_terminal "$theme_dir/windows-terminal-scheme.json"
}

# omawsl_theme_command [name]
# Entry point for `bin/omawsl theme [name]`. With no name, prompts via
# gum choose using Omakub's own Title Case labels (design spec §11);
# with a name, accepts either form ("rose-pine" or "Rose Pine") for
# convenience on the command line.
omawsl_theme_command() {
  local input="${1:-}"
  local name

  if [[ -z "$input" ]]; then
    local choice
    choice="$(omawsl_theme_names | while read -r n; do omawsl_theme_display_name "$n"; done | gum choose --header "Choose your theme")"
    [[ -n "$choice" ]] || return 0
    name="$(omawsl_theme_folder_name "$choice")"
  else
    name="$(omawsl_theme_folder_name "$input")"
  fi

  omawsl_theme_apply "$name"
}
