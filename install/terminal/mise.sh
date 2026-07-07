#!/usr/bin/env bash
set -euo pipefail

# omawsl_install_mise
# Installs mise (https://mise.jdx.dev) via its official installer script -
# no stable Ubuntu archive package exists for it, unlike gum/docker-ce.
# Idempotent: no-ops if mise is already on PATH. Exports $HOME/.local/bin
# onto the CURRENT script's PATH immediately, not just via configs/bashrc
# (which only takes effect in a NEW shell) - select-dev-language.sh runs
# moments later in this same sourced session (terminal.sh sources scripts,
# not sub-shells them), so it needs mise reachable right away. Same
# staleness pitfall as the Docker group-membership issue found in Phase 2.
omawsl_install_mise() {
  export PATH="$HOME/.local/bin:$PATH"

  if command -v mise &>/dev/null; then
    return 0
  fi

  curl -fsSL https://mise.run | sh
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_install_mise
fi
