#!/usr/bin/env bash
# practice/18-copilot-autopilot-mode/autopilot.sh
#
# Rebuild the Copilot CLI autopilot opt-in from scratch. See
# docs/curriculum/18-copilot-autopilot-mode.md, section 3 (Exercise), for
# full behavioral requirements.
#
# `choices.sh` (same directory) is given — it already provides
# omawsl_save_choice/omawsl_load_choice, sourced below. Don't change it.
#
# The persisted key is OMAWSL_COPILOT_AUTOPILOT, and the value stored is
# exactly the literal string "yes" or "no" (this lesson trims away the
# real project's full gum-choose label strings so you can focus on the
# opt-in/persist/alias/clear pattern itself).
#
# The alias line, verbatim, matching the real project:
#   alias copilot="copilot --autopilot --allow-all"
#
# Functions to implement here:
#
#   omawsl_autopilot_install <yes|no>
#     - Persists the answer as OMAWSL_COPILOT_AUTOPILOT via
#       omawsl_save_choice.
#     - If the answer is "yes": ensures the alias line above is present,
#       exactly once, in $HOME/.bashrc. Calling this twice in a row with
#       "yes" must not add a second copy of the line.
#     - If the answer is "no": ensures the alias line is NOT present in
#       $HOME/.bashrc (covers a user who previously said "yes" and is now
#       flipping the choice — the stale alias must not survive). If the
#       line was never there, this is a silent no-op.
#     - Either way, every other line already in $HOME/.bashrc (if any)
#       must be left exactly as it was — this function may add or remove
#       its own one line, never rewrite the whole file.
#
#   omawsl_autopilot_uninstall
#     - Clears the persisted choice (so a later reinstall re-prompts
#       instead of silently inheriting a stale answer — use
#       omawsl_save_choice with an empty value).
#     - Removes the alias line from $HOME/.bashrc if present, leaving
#       every other line untouched. If it isn't there, this is a silent
#       no-op.
#
# Entry point (wire these two subcommands up at the bottom of this file):
#
#   bash autopilot.sh install yes
#   bash autopilot.sh install no
#   bash autopilot.sh uninstall
#
# TODO: implement omawsl_autopilot_install, omawsl_autopilot_uninstall,
# and the subcommand dispatch described above.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=choices.sh
source "$SCRIPT_DIR/choices.sh"
