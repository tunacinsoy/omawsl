#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
source "$SCRIPT_DIR/../lib.sh"

# Resolved once, at source time: bin/omawsl-sub/theme.sh and
# multiplexer.sh source this file too, and every omawsl script reassigns
# SCRIPT_DIR at its own top - by the time a function below runs, SCRIPT_DIR
# may point somewhere else entirely.
OMAWSL_HERDR_REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# omawsl_herdr_install_steps
# The actual install command, no guard - same split rationale as
# omawsl_claude_cli_install_steps. Herdr (herdrdev/herdr, issue #10) ships
# its own POSIX-sh installer, which verifies the binary's SHA-256 against
# herdr.dev's release manifest and places it at $HOME/.local/bin/herdr
# (already on PATH) - no npm/mise involved.
omawsl_herdr_install_steps() {
  curl -fsSL https://herdr.dev/install.sh | sh
}

# omawsl_herdr_theme_name <omawsl_theme_folder>
# Herdr's built-in theme for each omawsl theme. Rose Pine is the light
# Dawn variant everywhere else in omawsl (see themes/rose-pine/vscode.sh),
# so it maps to Herdr's rose-pine-dawn. Themes with no Herdr built-in use
# "terminal", which follows the outer terminal's palette - and omawsl
# theme already syncs Windows Terminal's color scheme.
omawsl_herdr_theme_name() {
  case "$1" in
    catppuccin|dracula|gruvbox|kanagawa|nord|one-dark|solarized|tokyo-night) echo "$1" ;;
    rose-pine) echo "rose-pine-dawn" ;;
    *) echo "terminal" ;;
  esac
}

# omawsl_herdr_apply_theme <omawsl_theme_folder>
# Rewrites only the [theme] `name = "..."` line of Herdr's config - the
# rest of the file is the user's (docs/config-safety.md) - and no-ops when
# there's no config or no such line (a user's own config that sets no
# theme stays that way). A running Herdr server picks the change up via
# reload-config; when none is running that fails harmlessly.
omawsl_herdr_apply_theme() {
  local config_file="$HOME/.config/herdr/config.toml"
  [[ -f "$config_file" ]] || return 0
  grep -qE '^name = "' "$config_file" || return 0
  local herdr_theme
  herdr_theme="$(omawsl_herdr_theme_name "$1")"
  sed -i -E "s/^name = \".*\"/name = \"$herdr_theme\"/" "$config_file"
  if command -v herdr &>/dev/null; then
    herdr server reload-config >/dev/null 2>&1 || true
  fi
}

# omawsl_zellij_current_theme
# The omawsl theme currently applied, read back from zellij's config -
# `omawsl theme` rewrites its `theme "..."` line on every run, so it's the
# one place that always reflects the last theme picked. Empty when zellij
# has no config.
omawsl_zellij_current_theme() {
  sed -nE 's/^theme "(.*)"/\1/p' "$HOME/.config/zellij/config.kdl" 2>/dev/null | head -n1
}

# omawsl_install_herdr_config
# Deploys configs/herdr.toml (zellij.kdl's keymap, ported) to Herdr's
# real config location, with @OMAWSL_ROOT@ replaced by this checkout's
# path. Copy-if-absent like omawsl_install_zellij_config - a user's own
# Herdr config is never touched. A freshly deployed config then adopts
# whatever omawsl theme is already applied, so switching to Herdr months
# after picking a theme doesn't revert Herdr's chrome to tokyo-night.
omawsl_install_herdr_config() {
  local config_file="$HOME/.config/herdr/config.toml"
  [[ -f "$config_file" ]] && return 0
  mkdir -p "$(dirname "$config_file")"
  sed "s#@OMAWSL_ROOT@#$OMAWSL_HERDR_REPO_ROOT#g" "$OMAWSL_HERDR_REPO_ROOT/configs/herdr.toml" > "$config_file"
  local theme
  theme="$(omawsl_zellij_current_theme)"
  if [[ -n "$theme" ]]; then
    omawsl_herdr_apply_theme "$theme"
  fi
}

# omawsl_herdr_ensure_installed
# Succeeds once herdr is on PATH, downloading it first if needed. Judged
# by the binary actually being there afterwards, not by the installer's
# exit status - a corporate network blocking herdr.dev is the expected
# failure, and it must never take a whole install.sh run down with it.
omawsl_herdr_ensure_installed() {
  command -v herdr &>/dev/null && return 0
  omawsl_herdr_install_steps || true
  hash -r
  command -v herdr &>/dev/null
}

# omawsl_install_herdr
# Only when Herdr is the chosen multiplexer (OMAWSL_MULTIPLEXER, set by
# install/first-run-choices.sh or `omawsl multiplexer herdr`). Idempotent:
# the download is skipped when herdr is already on PATH, the config deploy
# is copy-if-absent. If Herdr can't be installed, the choice goes back to
# zellij (with a warning) rather than staying on a Herdr that bashrc would
# silently skip.
omawsl_install_herdr() {
  [[ "${OMAWSL_MULTIPLEXER:-}" == herdr ]] || return 0
  if ! omawsl_herdr_ensure_installed; then
    echo "omawsl: Herdr couldn't be installed - new terminals will open zellij. Try again later with: omawsl multiplexer herdr" >&2
    export OMAWSL_MULTIPLEXER=zellij
    omawsl_save_choice OMAWSL_MULTIPLEXER zellij
    return 0
  fi
  omawsl_install_herdr_config
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_install_herdr
fi
