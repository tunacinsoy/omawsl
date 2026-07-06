#!/usr/bin/env bash
set -euo pipefail

omawsl_install_terminal_apps() {
  sudo apt-get update -qq
  sudo apt-get install -y fzf ripgrep bat eza zoxide plocate apache2-utils fd-find
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_install_terminal_apps
fi
