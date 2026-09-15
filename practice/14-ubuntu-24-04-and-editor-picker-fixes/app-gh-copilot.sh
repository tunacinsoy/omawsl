#!/usr/bin/env bash
set -euo pipefail

# omawsl_gh_copilot_install_steps
# PROVIDED - do not change. Stands in for the real installer (which would
# really run `npm install -g @github/copilot` and write a wrapper script).
# Just records that it ran, by writing to $OMAWSL_TEST_LOG - one line per
# call - so a check script can tell whether your guard function below
# called it or correctly skipped it, without any real npm/network access.
omawsl_gh_copilot_install_steps() {
  echo "install_steps called" >> "${OMAWSL_TEST_LOG:-/dev/null}"
}

# TODO: omawsl_install_gh_copilot
#
# GitHub retired the old `gh extension install github/gh-copilot` path
# (invoked as `gh copilot ...`, discoverable via `gh extension list`) in
# favor of a standalone `@github/copilot` npm package that provides a real,
# independent `copilot` command on PATH.
#
# An idempotency guard checks for the CURRENT shape of "already installed" -
# and here that shape changed out from under the old check. A guard that
# still looked for the gh extension (or grepped `gh extension list` output)
# would never find the new standalone binary, and would trigger a real
# reinstall on every single run forever.
#
# Implement this function so it:
#   1. Does nothing (returns 0) if `copilot` is already resolvable on the
#      current $PATH.
#   2. Otherwise, calls omawsl_gh_copilot_install_steps (defined above).
#
# (The real omawsl also runs a one-time migration step first, to clean up
# the old gh extension for anyone who installed it before this switch -
# out of scope for this exercise; focus only on the guard shape above.)
#
# omawsl_install_gh_copilot() {
#   ...
# }
