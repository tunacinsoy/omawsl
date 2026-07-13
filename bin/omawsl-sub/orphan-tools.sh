#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OMAWSL_ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../../install/lib.sh
source "$OMAWSL_ROOT_DIR/install/lib.sh"
# shellcheck source=items.sh
source "$SCRIPT_DIR/items.sh"

# Registry + version-check adapters for omawsl's "orphan" tools - tools
# omawsl installs that have no native update command of their own (no
# apt/mise coverage), per
# docs/superpowers/specs/2026-07-13-omawsl-update-mechanism-design.md §3.
# Deliberately separate from items.sh: items.sh is the install/uninstall/
# doctor picker registry (language/editor/storage categories only);
# zellij and lazydocker are always-on, not picker targets, so they don't
# belong there.

# omawsl_orphan_tool_slugs
# All 7 orphan-tool slugs, in a fixed display order.
omawsl_orphan_tool_slugs() {
  printf '%s\n' zellij lazydocker opencode claude codex gemini gh-copilot
}

# omawsl_orphan_tool_label <slug>
# zellij/lazydocker aren't in items.sh (always-on, not a picker target),
# so they get their own labels here; the other 5 slugs are already
# registered there under the exact same slug names install/uninstall/
# doctor use - reused via omawsl_item_label rather than duplicating the
# same 5 label strings a second time.
omawsl_orphan_tool_label() {
  case "$1" in
    zellij) echo "Zellij" ;;
    lazydocker) echo "LazyDocker" ;;
    opencode|claude|codex|gemini|gh-copilot) omawsl_item_label "$1" ;;
    *) return 1 ;;
  esac
}

# omawsl_orphan_tool_installed <slug>
# Is this orphan tool actually present right now? zellij/lazydocker get a
# direct command -v check (they're not in items.sh, so
# bin/omawsl-sub/doctor.sh's own per-slug checks don't cover them
# either); the other 5 repeat the same one-line checks doctor.sh and
# each tool's own install-script guard already use - this repo already
# has that exact check duplicated in at least two places per tool
# (app-codex-cli.sh's own guard, doctor.sh's omawsl_doctor_editor_installed),
# so a third one-line copy here matches existing precedent rather than
# reaching across into doctor.sh's file for a shared helper.
omawsl_orphan_tool_installed() {
  local slug="$1"
  case "$slug" in
    zellij) command -v zellij &>/dev/null ;;
    lazydocker) command -v lazydocker &>/dev/null ;;
    opencode) command -v opencode &>/dev/null ;;
    claude) command -v claude &>/dev/null ;;
    codex) command -v codex &>/dev/null ;;
    gemini) command -v gemini &>/dev/null ;;
    gh-copilot) gh extension list 2>/dev/null | grep -q 'github/gh-copilot' ;;
    *) return 1 ;;
  esac
}
