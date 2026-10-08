#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OMAWSL_ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# omawsl_keys_show
# Prints stdin, colored as markdown when batcat (apps-terminal.sh) is
# there - it pages a long cheatsheet on its own - and plain otherwise.
omawsl_keys_show() {
  if command -v batcat &>/dev/null; then
    batcat --style=plain --language=markdown
  else
    cat
  fi
}

# omawsl_keys_command [section]
# Entry point for `bin/omawsl keys [section]`: docs/keys.md is the one
# cheatsheet, and this only shows it - all of it, or each "## " section
# whose heading has [section] as a word ("herdr" and "zellij" both find
# the shared multiplexer section, "nvim" finds "Neovim (nvim)").
omawsl_keys_command() {
  local doc="$OMAWSL_ROOT_DIR/docs/keys.md"
  if [[ $# -eq 0 ]]; then
    omawsl_keys_show <"$doc"
    return 0
  fi
  local out
  out="$(awk -v want="${1,,}" '
    /^## / { h = tolower($0); gsub(/[^a-z0-9]+/, " ", h); show = index(" " h " ", " " want " ") > 0 }
    show' "$doc")"
  if [[ -z "$out" ]]; then
    echo "omawsl: unknown section '$1' - try one of:" >&2
    sed -n 's/^## /  /p' "$doc" >&2
    return 1
  fi
  printf '%s\n' "$out" | omawsl_keys_show
}
