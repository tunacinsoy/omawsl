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
# Entry point for `bin/omawsl update` (design spec §14, §4): git pull
# inside $OMAWSL_HOME, runs pending migrations, then offers
# to update the 9 "orphan" tools that have no native updater of their
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

  # Guarded rather than a bare call: omawsl_migrate (bin/omawsl-sub/
  # migrate.sh) already catches its own migration failures and returns 0,
  # but that contract living in a different file is exactly the kind of
  # thing a future change there could accidentally regress - this `if`
  # is cheap insurance so a migration failure, even a hard one, can never
  # again take the orphan-tools phase below down with it (see
  # migrate.sh's own comment for the full story of why that combo
  # matters: an offline machine/corp proxy failing the starship download
  # in migrations/1786305600.sh must not cost the user their lazydocker/
  # zellij/etc. updates too).
  if ! omawsl_migrate; then
    echo "omawsl: warning - migrate step failed; continuing with orphan-tool updates." >&2
  fi

  echo "omawsl: update complete."

  omawsl_orphan_tools_update

  echo "omawsl: languages/cloud tools -> mise upgrade, or 'omawsl install language <x>'. System packages -> sudo apt upgrade. Full breakdown: docs/updating.md."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_update
fi
