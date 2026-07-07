#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
source "$SCRIPT_DIR/../lib.sh"

# omawsl_install_language <mise_tool_name>
# Idempotent by construction: `mise use --global` re-pins an already-set
# version harmlessly (design spec §7).
omawsl_install_language() {
  local mise_tool="$1"
  mise use --global "${mise_tool}@latest"
}

# omawsl_select_dev_language
# Installs one mise-managed tool per selection in OMAWSL_LANGUAGES.
# Terraform and Azure CLI live in this same picker but are cloud-tools.sh's
# job, not this script's (design spec §6, §12). Nothing is pre-selected by
# default and selecting nothing is a valid, expected state - each branch
# below no-ops cleanly if its option wasn't picked.
omawsl_select_dev_language() {
  local languages="${OMAWSL_LANGUAGES:-}"

  if omawsl_list_has "$languages" "Ruby on Rails"; then
    omawsl_install_language ruby
    gem install rails --no-document
  fi

  if omawsl_list_has "$languages" "Node.js"; then
    omawsl_install_language node
  fi

  if omawsl_list_has "$languages" "Go"; then
    omawsl_install_language go
  fi

  if omawsl_list_has "$languages" "PHP"; then
    omawsl_install_language php
  fi

  if omawsl_list_has "$languages" "Python"; then
    omawsl_install_language python
  fi

  if omawsl_list_has "$languages" "Elixir"; then
    omawsl_install_language elixir
  fi

  if omawsl_list_has "$languages" "Rust"; then
    omawsl_install_language rust
  fi

  if omawsl_list_has "$languages" "Java"; then
    omawsl_install_language java
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_select_dev_language
fi
