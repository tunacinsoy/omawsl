#!/usr/bin/env bash
# Phase 15 exercise stub — see docs/curriculum/15-corp-safe-config-editing.md
#
# Implement ensure_source_line below. This file is meant to be `source`d
# (by check.sh, or by hand while you experiment) — it defines the function
# but never calls it itself, so sourcing it has no side effects on its own.
#
# ensure_source_line <file>
#   Appends a marker-delimited, guarded `source` line pointing at
#   $HOME/.local/share/omawsl/configs/bashrc to <file>, but only if the
#   marker isn't already present. Creates <file> if it doesn't exist.
#   Never modifies, reorders, or deletes anything already in <file>.
#
# See the lesson's Exercise section for the exact contract (marker text,
# guard shape, idempotency requirement).

ensure_source_line() {
  local file="$1"

  # TODO: implement.
  :
}
