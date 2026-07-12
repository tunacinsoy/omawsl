#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OMAWSL_ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../../install/lib.sh
source "$OMAWSL_ROOT_DIR/install/lib.sh"
# shellcheck source=migrate.sh
source "$SCRIPT_DIR/migrate.sh"

# omawsl_update
# Entry point for `bin/omawsl update` (design spec §14): git pull inside
# $OMAWSL_HOME, then runs pending migrations - a deliberate improvement
# over upstream Omakub, whose own update flow never automates the git
# pull itself. Detects a dirty working tree first (someone hand-edited a
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
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_update
fi
