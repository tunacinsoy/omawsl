#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../install/lib.sh
source "$SCRIPT_DIR/../install/lib.sh"

# omawsl_uninstall_neovim
# Inverse of install/terminal/app-neovim.sh: removes the LazyVim config
# tree it cloned and purges the apt-installed neovim package. Removing
# ~/.config/nvim unconditionally mirrors app-neovim.sh's own one-directional
# guard (it only skips the clone if the dir already existed at install
# time) - there is no reliable way to tell "omawsl's LazyVim clone" apart
# from a config a user hand-edited afterward, so this is a documented,
# scoped tradeoff, not an oversight.
omawsl_uninstall_neovim() {
  rm -rf "$HOME/.config/nvim"
  sudo apt-get purge -y neovim
  echo "omawsl: Neovim and its LazyVim config removed."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_uninstall_neovim
fi
