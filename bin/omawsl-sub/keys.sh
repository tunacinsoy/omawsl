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
# cheatsheet, and this only shows it - each "## " section whose heading
# has [section]'s words in a row ("herdr" and "zellij" both find the
# shared multiplexer section, "nvim" finds "Neovim (nvim)"). With no
# section, asks which one via gum rather than printing the whole sheet;
# cancelling the picker shows nothing.
omawsl_keys_command() {
  local doc="$OMAWSL_ROOT_DIR/docs/keys.md"
  local want="${1:-}"
  if [[ -z "$want" ]]; then
    local -a sections
    mapfile -t sections < <(sed -n 's/^## //p' "$doc")
    want="$(gum choose --header "Which keys?" "${sections[@]}")" || want=""
    [[ -n "$want" ]] || return 0
  fi
  local out
  out="$(awk -v want="$want" '
    function words(s) { s = tolower(s); gsub(/[^a-z0-9]+/, " ", s); gsub(/^ +| +$/, "", s); return " " s " " }
    BEGIN { want = words(want) }
    /^## / { show = index(words(substr($0, 4)), want) > 0 }
    show' "$doc")"
  if [[ -z "$out" ]]; then
    echo "omawsl: unknown section '$want' - try one of:" >&2
    sed -n 's/^## /  /p' "$doc" >&2
    return 1
  fi
  printf '%s\n' "$out" | omawsl_keys_show
}
