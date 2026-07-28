#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OMAWSL_ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../install/lib.sh
source "$OMAWSL_ROOT_DIR/install/lib.sh"

# Corp-safe config editing migration (design spec
# docs/superpowers/specs/2026-07-28-corp-safe-config-editing-design.md):
# every prior install/update `cp`-overwrote ~/.bashrc and ~/.inputrc
# wholesale, but a file starting with omawsl's own banner comment only
# proves omawsl *created* it originally - it says nothing about whether
# the user (or corp IT) appended their own lines to it since their last
# `omawsl update`. That's exactly the content this feature exists to
# protect, so this migration never deletes either file, regardless of
# banner match - it only ever appends the guarded source line, same as a
# fresh install would do.
omawsl_migrate_bashrc_to_source_line() {
  omawsl_ensure_bashrc_source_line "$HOME/.bashrc" "$OMAWSL_ROOT_DIR/configs/bashrc"
}

# No migration step for ~/.inputrc: since deletion isn't provably safe (see
# above), and there's nothing else safe to do to an existing file, any
# ~/.inputrc - omawsl-authored or not - is left exactly as-is. Accepted
# trade-off: a user with an old omawsl-authored ~/.inputrc won't benefit
# from the new INPUTRC-fallback pointing at omawsl's own copy, since that
# fallback only activates when ~/.inputrc is absent.

# Print-only advisory (no file mutation beyond what the append above already
# did): every old-style ~/.bashrc omawsl ever wrote starts with this exact
# banner line and ends in `exec zellij`. That old copy now sits ABOVE the
# newly-appended marker block, which is harmless on its own (the migration
# never deletes it - see above), but on a fresh outer shell with zellij
# installed, the old copy's `exec zellij` replaces the shell process before
# ever reaching the new marker block below it, so the new sourced
# configs/bashrc never loads at all. Nudge the user to clean it up by hand
# rather than doing it automatically ourselves.
omawsl_warn_if_old_bashrc_copy_present() {
  [[ -f "$HOME/.bashrc" ]] || return 0
  if head -n1 "$HOME/.bashrc" | grep -qF '# omawsl bashrc - baseline dev environment configuration for WSL2 Ubuntu.'; then
    echo "omawsl: ~/.bashrc still has a full copy of an older omawsl config above the new '# >>> omawsl >>>' block."
    echo "omawsl: it's safe to delete everything above that marker by hand."
    echo "omawsl: leaving it in place may stop the new config from loading, if the old copy ends in 'exec zellij'."
  fi
}

omawsl_migrate_bashrc_to_source_line
omawsl_warn_if_old_bashrc_copy_present
