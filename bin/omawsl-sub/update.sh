#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OMAWSL_ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../../install/lib.sh
source "$OMAWSL_ROOT_DIR/install/lib.sh"
# shellcheck source=migrate.sh
source "$SCRIPT_DIR/migrate.sh"
# shellcheck source=orphan-tools.sh
source "$SCRIPT_DIR/orphan-tools.sh"

# omawsl_update
# Entry point for `bin/omawsl update` (design spec §14, extended by
# docs/superpowers/specs/2026-07-13-omawsl-update-mechanism-design.md
# §4): git pull inside $OMAWSL_HOME, runs pending migrations, then offers
# to update the 7 "orphan" tools that have no native updater of their
# own (§3 of that spec) - never wraps `apt upgrade`/`mise upgrade`
# themselves. Detects a dirty working tree first (someone hand-edited a
# file directly inside the checkout) and refuses to pull over it rather
# than letting `git pull` fail confusingly or silently discard those
# edits. Same $OMAWSL_HOME default/override convention as boot.sh.
omawsl_update() {
  local home_dir="${OMAWSL_HOME:-$HOME/.local/share/omawsl}"

  if [[ ! -d "$home_dir/.git" ]]; then
    echo "omawsl: no checkout found at $home_dir - nothing to update." >&2
    return 1
  fi

  if [[ -n "$(git -C "$home_dir" status --porcelain)" ]]; then
    echo "omawsl: $home_dir has local changes - refusing to 'git pull' over them." >&2
    echo "Commit, stash, or discard those changes yourself, then re-run 'omawsl update'." >&2
    return 1
  fi

  echo "omawsl: pulling latest..."
  if ! git -C "$home_dir" pull; then
    echo "omawsl: 'git pull' failed - check your network connection and try again." >&2
    return 1
  fi

  omawsl_migrate

  echo "omawsl: update complete."

  omawsl_orphan_tools_update

  echo "omawsl: languages/cloud tools -> mise upgrade, or 'omawsl install language <x>'. System packages -> sudo apt upgrade. Full breakdown: docs/updating.md."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_update
fi
