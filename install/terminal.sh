#!/usr/bin/env bash
set -euo pipefail

OMAWSL_INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$OMAWSL_INSTALL_DIR/lib.sh"

# Fixed order, sourced (not sub-shelled) so a failure stops the whole run
# immediately (design spec §8). Extended by later phases (the app-*.sh
# editor/tool scripts) rather than restructured.
OMAWSL_TERMINAL_SCRIPTS=(
  "terminal/required/app-gum.sh"
  "terminal/identification.sh"
  "terminal/a-shell.sh"
  "terminal/apps-terminal.sh"
  "terminal/docker.sh"
  "terminal/mise.sh"
  "terminal/select-dev-language.sh"
  "terminal/cloud-tools.sh"
  "terminal/select-dev-storage.sh"
  "terminal/app-vscode.sh"
  "terminal/app-neovim.sh"
  "terminal/app-opencode.sh"
  "terminal/app-cursor.sh"
  "terminal/app-claude-cli.sh"
  "terminal/app-codex-cli.sh"
  "terminal/app-gh-copilot.sh"
  "terminal/app-gemini-cli.sh"
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
    ["terminal/docker.sh"]="omawsl_docker"
    ["terminal/mise.sh"]="omawsl_install_mise"
    ["terminal/select-dev-language.sh"]="omawsl_select_dev_language"
    ["terminal/cloud-tools.sh"]="omawsl_cloud_tools"
    ["terminal/select-dev-storage.sh"]="omawsl_install_storage"
    ["terminal/app-vscode.sh"]="omawsl_install_vscode"
    ["terminal/app-neovim.sh"]="omawsl_install_neovim"
    ["terminal/app-opencode.sh"]="omawsl_install_opencode"
    ["terminal/app-cursor.sh"]="omawsl_install_cursor"
    ["terminal/app-claude-cli.sh"]="omawsl_install_claude_cli"
    ["terminal/app-codex-cli.sh"]="omawsl_install_codex_cli"
    ["terminal/app-gh-copilot.sh"]="omawsl_install_gh_copilot"
    ["terminal/app-gemini-cli.sh"]="omawsl_install_gemini_cli"
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
