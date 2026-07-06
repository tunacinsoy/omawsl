#!/usr/bin/env bash
set -euo pipefail

OMAWSL_ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=install/lib.sh
source "$OMAWSL_ROOT_DIR/install/lib.sh"
# shellcheck source=install/check-version.sh
source "$OMAWSL_ROOT_DIR/install/check-version.sh"
# shellcheck source=install/terminal/required/app-gum.sh
source "$OMAWSL_ROOT_DIR/install/terminal/required/app-gum.sh"
# shellcheck source=install/first-run-choices.sh
source "$OMAWSL_ROOT_DIR/install/first-run-choices.sh"
# shellcheck source=install/windows-prereq-checklist.sh
source "$OMAWSL_ROOT_DIR/install/windows-prereq-checklist.sh"
# shellcheck source=install/terminal.sh
source "$OMAWSL_ROOT_DIR/install/terminal.sh"

omawsl_write_version_state() {
  local dir; dir="$(omawsl_choices_dir)"
  mkdir -p "$dir"
  cp "$OMAWSL_ROOT_DIR/version" "$dir/version"
}

omawsl_install() {
  omawsl_check_version

  # Bootstrap gum before any prompt needs it - must happen before
  # first-run-choices.sh, not as part of terminal.sh's later pass (which
  # would be too late for the prompts below). Sourced above; called
  # explicitly here since every install/terminal/*.sh script only auto-runs
  # when executed directly, not when sourced.
  omawsl_install_gum

  omawsl_first_run_choices
  omawsl_windows_prereq_checklist
  omawsl_run_terminal_scripts

  omawsl_write_version_state

  echo
  echo "omawsl: install complete."
  echo "See docs/windows-setup.md for the manual Windows-side steps."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_install
fi
