#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OMAWSL_ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../install/lib.sh
source "$OMAWSL_ROOT_DIR/install/lib.sh"
# shellcheck source=../install/terminal/apps-terminal.sh
source "$OMAWSL_ROOT_DIR/install/terminal/apps-terminal.sh"

# Fixes the real pane-frame drift bug this migration's own commit message
# documents: zellij 0.45.0 changed its own default pane_frame_style from
# "full" (a full border around each pane) to "titles" (a single title
# line), and zellij auto-regenerates ~/.config/zellij/config.kdl (backing
# the old one up to config.kdl.bak) on breaking config-schema bumps like
# that one - the freshly-generated file always reflects zellij's *current*
# default for anything the old file never set explicitly. Since
# configs/zellij.kdl never set pane_frame_style before this fix, anyone
# who ran `omawsl update` across that zellij release already has a
# reskinned config.kdl sitting on disk right now, independent of whether
# they update zellij again - configs/bashrc's own new pre-launch guard
# (see its comment) only re-checks this on the *next* zellij launch, so
# this migration applies the same fix immediately instead of waiting on
# that trigger. omawsl_zellij_ensure_pane_frame_style is already
# idempotent and content-checked (a no-op if the setting is already
# present, whatever its value), so this is safe to run unconditionally.
omawsl_zellij_ensure_pane_frame_style
