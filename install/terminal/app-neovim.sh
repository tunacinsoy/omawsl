#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
source "$SCRIPT_DIR/../lib.sh"

# omawsl_install_treesitter_cli
# LazyVim's starter config pins nvim-treesitter to its `main` branch, whose
# installer shells out to `tree-sitter build` (lua/nvim-treesitter/install.lua)
# to compile parsers. Ubuntu Noble's apt tree-sitter-cli package is 0.20.8-5,
# which predates that `build` subcommand ("error: The subcommand 'build'
# wasn't recognized"), so every parser except the 3 shipped inside Neovim's
# own runtime (c, lua, vimdoc) silently fails to compile - confirmed via a
# headless `nvim --headless -c "TSInstall! lua"` repro (issue #17). Installs
# a current tree-sitter-cli via a private mise-managed Node runtime (same
# pattern as app-codex-cli.sh/app-gh-copilot.sh) and wraps it in
# $HOME/.local/bin/tree-sitter, which the bashrc config puts ahead of
# /usr/bin on PATH - so it wins over any apt-installed tree-sitter-cli
# without needing to remove that package. The idempotency guard checks for
# our own wrapper specifically, not `command -v tree-sitter`: an old apt
# copy already resolving on PATH is exactly the broken state this fixes, so
# it must not be mistaken for "already installed".
omawsl_install_treesitter_cli() {
  if [[ -x "$HOME/.local/bin/tree-sitter" ]]; then
    return 0
  fi

  mise exec node@lts -- npm install -g tree-sitter-cli

  mkdir -p "$HOME/.local/bin"
  cat > "$HOME/.local/bin/tree-sitter" <<'WRAPPER'
#!/usr/bin/env bash
exec mise exec node@lts -- tree-sitter "$@"
WRAPPER
  chmod +x "$HOME/.local/bin/tree-sitter"
}

# omawsl_install_neovim
# Purely WSL-side, no Windows dependency (design spec §10). Installs
# Neovim via apt, then bootstraps LazyVim using its own official starter
# template (github.com/LazyVim/starter) rather than hand-authoring Lua
# config files - the cloned .git directory is removed afterward, matching
# LazyVim's own documented setup instructions. Skipped entirely if
# ~/.config/nvim already exists, so a user's own existing Neovim config
# is never overwritten. Also provisions a working tree-sitter-cli (see
# omawsl_install_treesitter_cli) so nvim-treesitter's main-branch installer
# can actually compile parsers on a fresh box.
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

  omawsl_install_treesitter_cli
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_install_neovim
fi
