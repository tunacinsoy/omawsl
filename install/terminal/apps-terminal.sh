#!/usr/bin/env bash
set -euo pipefail

# omawsl_install_terminal_apps
# Always-on terminal tooling, no picker gate. Installs via apt where a
# stable Ubuntu package exists (verified against Ubuntu 26.04's own
# universe repo: fzf, ripgrep, bat, eza, zoxide, plocate, apache2-utils,
# fd-find, gh, btop, fastfetch, lazygit all have candidates there), plus
# two tools with no Ubuntu package at all (lazydocker, zellij), each
# installed via its own official method below.
omawsl_install_terminal_apps() {
  sudo apt-get update -qq
  sudo apt-get install -y fzf ripgrep bat eza zoxide plocate apache2-utils fd-find gh btop fastfetch lazygit

  omawsl_install_lazydocker
  omawsl_install_zellij
}

# omawsl_install_lazydocker
# No Ubuntu package exists for lazydocker - installs via its official
# script (jesseduffield/lazydocker), which installs to $HOME/.local/bin
# by default (already on PATH via configs/bashrc). The script itself
# always re-downloads/reinstalls unconditionally - this command -v guard
# is what actually makes this idempotent.
omawsl_install_lazydocker() {
  if command -v lazydocker &>/dev/null; then
    return 0
  fi
  curl -fsSL https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh | bash
}

# omawsl_install_zellij
# No Ubuntu package exists for zellij either. Installs the official
# prebuilt musl binary release directly from GitHub rather than the
# project's own `bash <(curl .../launch)` one-liner, so the exact steps
# stay auditable here instead of delegating to an unseen remote script.
# `/releases/latest/download/<asset>` always resolves to the current
# release, so no separate version-lookup step is needed.
omawsl_install_zellij() {
  if command -v zellij &>/dev/null; then
    return 0
  fi
  local arch
  arch="$(uname -m)"
  curl -fsSL "https://github.com/zellij-org/zellij/releases/latest/download/zellij-${arch}-unknown-linux-musl.tar.gz" | tar -xz -C /tmp
  sudo install -m 0755 /tmp/zellij /usr/local/bin/zellij
  rm -f /tmp/zellij
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_install_terminal_apps
fi
