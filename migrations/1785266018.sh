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

omawsl_migrate_bashrc_to_source_line
