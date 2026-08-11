#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OMAWSL_ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../../install/lib.sh
source "$OMAWSL_ROOT_DIR/install/lib.sh"

# omawsl_migrations_dir
# Overridable via OMAWSL_MIGRATIONS_DIR for testing, same pattern as every
# other OMAWSL_*_FILE/_DIR override in this repo (docker.sh, cloud-tools.sh).
omawsl_migrations_dir() {
  echo "${OMAWSL_MIGRATIONS_DIR:-$OMAWSL_ROOT_DIR/migrations}"
}

# omawsl_migration_timestamps
# Prints every migrations/<timestamp>.sh file's timestamp, one per line,
# sorted numerically ascending. Silent no-op if the dir doesn't exist.
omawsl_migration_timestamps() {
  local dir; dir="$(omawsl_migrations_dir)"
  [[ -d "$dir" ]] || return 0
  local f base
  for f in "$dir"/*.sh; do
    [[ -e "$f" ]] || continue
    base="${f##*/}"
    echo "${base%.sh}"
  done | sort -n
}

# omawsl_last_migrated_timestamp
# Reads the persisted state's version file (design spec §8); defaults to
# 0 if it's never been written (nothing has ever "completed" a migration
# baseline for this user yet).
omawsl_last_migrated_timestamp() {
  local file; file="$(omawsl_choices_dir)/version"
  if [[ -f "$file" ]]; then
    cat "$file"
  else
    echo 0
  fi
}

# omawsl_pending_migrations
omawsl_pending_migrations() {
  local last; last="$(omawsl_last_migrated_timestamp)"
  local ts
  omawsl_migration_timestamps | while IFS= read -r ts; do
    if [[ "$ts" -gt "$last" ]]; then
      echo "$ts"
    fi
  done
}

# omawsl_migrate
# Entry point for `bin/omawsl migrate` (design spec §14): runs every
# migration newer than the recorded state, updating state after EACH one
# individually (not just at the end) so a mid-run failure doesn't lose
# progress already made on a re-run. Afterward, if the repo's own current
# version is newer than what's recorded (e.g. a release bumped `version`
# with zero actual migrations), bumps state to match - otherwise a later
# `migrate` run would see nothing pending but state would never reflect
# "fully up to date."
#
# A migration script failing (e.g. migrations/1786305600.sh's network
# call to fetch starship, on an offline machine or behind a proxy that
# blocks GitHub) stops the loop - later pending migrations may depend on
# an earlier one having actually succeeded, so silently skipping ahead
# isn't safe - but does NOT propagate that failure to the caller as a
# hard error: bin/omawsl-sub/update.sh's own omawsl_update calls this
# before omawsl_orphan_tools_update, and a failed migration has nothing
# to do with whether those unrelated tool updates (lazydocker, zellij,
# ...) can still run. The failed migration's timestamp is deliberately
# left unrecorded (the `echo "$ts" > version` line is only reached on
# success), so it's retried automatically on the very next 'omawsl
# migrate'/'omawsl update' run - no separate recovery path needed here.
omawsl_migrate() {
  local pending; pending="$(omawsl_pending_migrations)"
  local dir; dir="$(omawsl_migrations_dir)"
  local state_dir; state_dir="$(omawsl_choices_dir)"

  if [[ -z "$pending" ]]; then
    echo "omawsl: no pending migrations - up to date."
  else
    mkdir -p "$state_dir"
    local ts
    while IFS= read -r ts; do
      echo "omawsl: running migration $ts..."
      if bash "$dir/$ts.sh"; then
        echo "$ts" > "$state_dir/version"
      else
        echo "omawsl: warning - migration $ts failed and will be retried on the next 'omawsl migrate'/'omawsl update' run." >&2
        return 0
      fi
    done <<< "$pending"
    echo "omawsl: migrations complete."
  fi

  local version_file="${OMAWSL_VERSION_FILE:-$OMAWSL_ROOT_DIR/version}"
  local repo_version; repo_version="$(cat "$version_file")"
  local current; current="$(omawsl_last_migrated_timestamp)"
  if [[ "$repo_version" -gt "$current" ]]; then
    mkdir -p "$state_dir"
    echo "$repo_version" > "$state_dir/version"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_migrate
fi
