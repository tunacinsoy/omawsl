#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OMAWSL_ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../install/lib.sh
source "$OMAWSL_ROOT_DIR/install/lib.sh"
# shellcheck source=../install/terminal/app-neovim.sh
source "$OMAWSL_ROOT_DIR/install/terminal/app-neovim.sh"

# tree-sitter-cli provisioning (fixes #17) only ran from a fresh
# `omawsl_install_neovim` invocation - i.e. only for someone who re-picks
# "Neovim" in the editor picker. Anyone who already had Neovim/LazyVim
# installed before that fix landed - the exact population hitting #17 in
# the first place - would never see it via `omawsl update`, since that
# only runs migrations + the 9 orphan-tool updaters, and tree-sitter-cli
# is neither (it's a Neovim implementation detail, not a user-facing
# picker item with its own updater). `[[ -d "$HOME/.config/nvim" ]]` is
# the same "is Neovim actually installed" signal app-neovim.sh's own
# clone guard and doctor.sh's omawsl_doctor_installed both already use,
# rather than checking OMAWSL_EDITORS (which only reflects picker
# choices made through omawsl, not a config dir someone brought
# themselves). omawsl_install_treesitter_cli is already idempotent (its
# own wrapper-exists guard), so this is safe to run on every `omawsl
# update` even after it has already applied once.
if [[ -d "$HOME/.config/nvim" ]]; then
  omawsl_install_treesitter_cli
fi
