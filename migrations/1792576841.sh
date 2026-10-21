#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OMAWSL_ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../bin/omawsl-sub/theme.sh
source "$OMAWSL_ROOT_DIR/bin/omawsl-sub/theme.sh"

# VS Code and Cursor now get omawsl's theme colors through their settings
# alone, instead of a theme extension installed with `code` / `cmd.exe` -
# omawsl no longer starts Windows programs from WSL. This re-applies the
# active theme's colors once, so VS Code matches the terminal without
# waiting for the next `omawsl theme`. The active theme is the one zellij
# points at, if its theme file exists (only `omawsl theme` creates it - see
# migrations/1786305600.sh).
zellij_config="$HOME/.config/zellij/config.kdl"
active_theme=""
if [[ -f "$zellij_config" ]]; then
  active_theme="$(grep -oP '(?<=theme ")[^"]+' "$zellij_config" | head -n1 || true)"
fi
if [[ -n "$active_theme" ]] && omawsl_theme_is_valid "$active_theme" &&
  [[ -f "$HOME/.config/zellij/themes/$active_theme.kdl" ]]; then
  omawsl_theme_apply_vscode "$OMAWSL_ROOT_DIR/themes/$active_theme"
fi

# Ristretto used to install Monokai Pro, a paid extension whose "Register
# now" dialog shows on every VS Code start (#37). Uninstalling it would
# mean running VS Code, so this only says where it is - looked up by
# folder name, nothing is run.
profile="$(omawsl_windows_userprofile 2>/dev/null || true)"
for dir in "${profile:+$profile/.vscode/extensions}" "$HOME/.vscode-server/extensions"; do
  [[ -n "$dir" ]] || continue
  if compgen -G "$dir/monokai.theme-monokai-pro-vscode-*" >/dev/null; then
    echo "omawsl: Monokai Pro is still installed in VS Code, and its \"Register now\" dialog will keep coming. omawsl doesn't need it any more: remove it in VS Code's Extensions view."
    break
  fi
done
