#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
source "$SCRIPT_DIR/../lib.sh"

# omawsl_install_neovim
# Purely WSL-side, no Windows dependency (design spec §10). Installs
# Neovim via apt, then bootstraps LazyVim using its own official starter
# template (github.com/LazyVim/starter) rather than hand-authoring Lua
# config files - the cloned .git directory is removed afterward, matching
# LazyVim's own documented setup instructions. Skipped entirely if
# ~/.config/nvim already exists, so a user's own existing Neovim config
# is never overwritten.
omawsl_install_neovim() {
  if ! omawsl_list_has "${OMAWSL_EDITORS:-}" "Neovim"; then
    return 0
  fi

  sudo apt-get update -qq
  sudo apt-get install -y neovim

  if [[ ! -d "$HOME/.config/nvim" ]]; then
    git clone https://github.com/LazyVim/starter "$HOME/.config/nvim"
    rm -rf "$HOME/.config/nvim/.git"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_install_neovim
fi
