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
# scoped tradeoff, not an oversight. Also undoes
# omawsl_install_treesitter_cli: uninstalls the npm global package via the
# same private mise-managed Node runtime it was installed with, then
# removes the $HOME/.local/bin/tree-sitter wrapper - same shape as
# uninstall/app-codex-cli.sh. No-ops the npm step (but still removes the
# wrapper) if mise isn't reachable, since a leftover wrapper pointing at a
# now-broken `mise exec` call is worse than nothing.
omawsl_uninstall_neovim() {
  rm -rf "$HOME/.config/nvim"
  sudo apt-get purge -y neovim

  if command -v mise &>/dev/null; then
    mise exec node@lts -- npm uninstall -g tree-sitter-cli || true
  fi
  rm -f "$HOME/.local/bin/tree-sitter"

  echo "omawsl: Neovim and its LazyVim config removed."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_uninstall_neovim
fi
