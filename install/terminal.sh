#!/usr/bin/env bash
set -euo pipefail

OMAWSL_INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$OMAWSL_INSTALL_DIR/lib.sh"

# Fixed order, sourced (not sub-shelled) so a failure stops the whole run
# immediately (design spec §8). Extended by later phases (docker.sh,
# select-dev-language.sh, cloud-tools.sh, select-dev-storage.sh, the
# app-*.sh editor/tool scripts) rather than restructured.
OMAWSL_TERMINAL_SCRIPTS=(
  "terminal/required/app-gum.sh"
  "terminal/identification.sh"
  "terminal/a-shell.sh"
  "terminal/apps-terminal.sh"
  "terminal/libraries.sh"
)

omawsl_run_terminal_scripts() {
  local script
  # Mapping of script paths to their main function names
  declare -A SCRIPT_FUNCTIONS=(
    ["terminal/required/app-gum.sh"]="omawsl_install_gum"
    ["terminal/identification.sh"]="omawsl_identification"
    ["terminal/a-shell.sh"]="omawsl_install_shell_config"
    ["terminal/apps-terminal.sh"]="omawsl_install_terminal_apps"
    ["terminal/libraries.sh"]="omawsl_install_libraries"
  )

  for script in "${OMAWSL_TERMINAL_SCRIPTS[@]}"; do
    echo "omawsl: running $script"
    # shellcheck source=/dev/null
    source "$OMAWSL_INSTALL_DIR/$script"
    # Call the script's main function
    "${SCRIPT_FUNCTIONS[$script]}"
  done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_run_terminal_scripts
fi
