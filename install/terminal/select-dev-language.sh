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
    # `mise use --global` only pins the version in mise's config; it does not
    # put mise's Ruby shims on THIS shell's PATH (that requires `mise
    # activate`, which is for interactive shells, not this one-shot script).
    # A bare `gem install` would hit whatever `gem` is first on PATH - often
    # nothing at all - and abort the whole install under `set -e`. `mise exec
    # <tool>@<version> -- <cmd>` runs a single command with that tool's
    # shims added to PATH just for the duration of the call.
    mise exec ruby@latest -- gem install rails --no-document
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
    # Elixir's compiler is written in Erlang, and mise's elixir plugin doesn't
    # pull Erlang in for you - erlang must already be mise-installed and on
    # PATH before elixir's own post-install step runs, or it fails looking
    # for `erl`. Installing erlang first (not in parallel) avoids that.
    omawsl_install_language erlang
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
