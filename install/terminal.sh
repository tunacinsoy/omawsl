#!/usr/bin/env bash
set -euo pipefail

OMAWSL_INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$OMAWSL_INSTALL_DIR/lib.sh"

# Fixed order, sourced (not sub-shelled) so a failure stops the whole run
# immediately (design spec §8). Extended by later phases (the app-*.sh
# editor/tool scripts) rather than restructured.
# libraries.sh must run before mise.sh/select-dev-language.sh: mise's
# ruby-build backend compiles Ruby (and its OpenSSL) from source unless a
# precompiled binary is available, which needs a C toolchain
# (build-essential) and dev headers that only libraries.sh installs -
# running it after select-dev-language.sh left a real WSL2 instance with no
# C compiler yet, so picking Ruby failed with "No C compiler found".
OMAWSL_TERMINAL_SCRIPTS=(
  "terminal/required/app-gum.sh"
  "terminal/identification.sh"
  "terminal/a-shell.sh"
  "terminal/apps-terminal.sh"
  "terminal/docker.sh"
  "terminal/libraries.sh"
  "terminal/mise.sh"
  "terminal/select-dev-language.sh"
  "terminal/cloud-tools.sh"
  "terminal/select-dev-storage.sh"
)

omawsl_run_terminal_scripts() {
  local script
  # Mapping of script paths to their main function names
  declare -A SCRIPT_FUNCTIONS=(
    ["terminal/required/app-gum.sh"]="omawsl_install_gum"
    ["terminal/identification.sh"]="omawsl_identification"
    ["terminal/a-shell.sh"]="omawsl_install_shell_config"
    ["terminal/apps-terminal.sh"]="omawsl_install_terminal_apps"
    ["terminal/docker.sh"]="omawsl_docker"
    ["terminal/libraries.sh"]="omawsl_install_libraries"
    ["terminal/mise.sh"]="omawsl_install_mise"
    ["terminal/select-dev-language.sh"]="omawsl_select_dev_language"
    ["terminal/cloud-tools.sh"]="omawsl_cloud_tools"
    ["terminal/select-dev-storage.sh"]="omawsl_install_storage"
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
