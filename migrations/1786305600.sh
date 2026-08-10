#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OMAWSL_ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../install/lib.sh
source "$OMAWSL_ROOT_DIR/install/lib.sh"
# shellcheck source=../install/terminal/apps-terminal.sh
source "$OMAWSL_ROOT_DIR/install/terminal/apps-terminal.sh"
# shellcheck source=../bin/omawsl-sub/theme.sh
source "$OMAWSL_ROOT_DIR/bin/omawsl-sub/theme.sh"

# Starship as the default prompt (design spec
# docs/superpowers/specs/2026-08-09-starship-default-prompt-design.md):
# installs the binary and the un-themed plain-mode config for existing
# installs, same as a fresh install's apps-terminal.sh already does.
omawsl_install_starship
omawsl_install_starship_config

# omawsl_starship_migrate_active_theme
# Preserves visual consistency for anyone who already picked a real
# omawsl theme. zellij is always-on and is theme.sh's first, always-
# patched target, so its config is the closest thing to a single source
# of truth for "what theme is currently active" - there's no separate
# state file for it. config.kdl's `theme "..."` reference alone isn't
# enough, though: configs/zellij.kdl ships with `theme "tokyo-night"`
# baked in from a fresh install, before any real theme file has ever been
# copied - so it names a *valid* theme even for someone who never ran
# `omawsl theme`. The real signal that it genuinely ran is that
# ~/.config/zellij/themes/<name>.kdl actually exists, since only
# omawsl_theme_apply ever creates it.
omawsl_starship_migrate_active_theme() {
  local zellij_config="$HOME/.config/zellij/config.kdl"
  [[ -f "$zellij_config" ]] || return 0
  local active_theme
  active_theme="$(grep -oP '(?<=theme ")[^"]+' "$zellij_config" | head -n1)"
  [[ -n "$active_theme" ]] || return 0
  omawsl_theme_is_valid "$active_theme" || return 0
  [[ -f "$HOME/.config/zellij/themes/$active_theme.kdl" ]] || return 0
  omawsl_theme_apply "$active_theme"
}

omawsl_starship_migrate_active_theme
