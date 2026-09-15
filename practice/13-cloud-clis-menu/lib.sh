#!/usr/bin/env bash
set -euo pipefail

# Given - you do not need to change this file.
#
# omawsl_list_has <comma_delimited_list> <item>
# Carried over from an earlier lesson: robust membership check on a
# comma-delimited string. Wraps both sides in delimiters and matches the
# whole token, rather than a bare substring check (which would misfire if
# one option's name is a substring of another, e.g. "Go" inside "Django").
omawsl_list_has() {
  local list="$1" item="$2"
  [[ ",$list," == *",$item,"* ]]
}
