#!/usr/bin/env bash
set -euo pipefail

# Minimal helper shared by select-dev-language.sh in this practice
# directory. Same behavior as the real install/lib.sh's omawsl_list_has -
# not part of this lesson's exercise, provided as-is.

# omawsl_list_has <comma_delimited_list> <item>
# Robust membership check on a comma-delimited string. Wraps both sides in
# delimiters and matches the whole token, rather than a bare substring check
# (which would misfire if one option's name is a substring of another).
omawsl_list_has() {
  local list="$1" item="$2"
  [[ ",$list," == *",$item,"* ]]
}
