#!/usr/bin/env bash
set -euo pipefail

# The `corporate-checklist` check that master's ruleset requires (see
# CONTRIBUTING.md). Passes only when the PR description's
# "## Corporate machine" section has every box ticked and its
# `Tested commit:` line names the PR's current head commit - so a new
# push, which changes the head, needs a fresh corporate test. Run by
# .github/workflows/corporate-checklist.yml with PR_BODY and HEAD_SHA in
# the environment: the body is untrusted input, so it's only ever read
# from a variable, never pasted into a command.

# omawsl_corporate_checklist_section <body>
# Prints the lines between the "## Corporate machine" heading (a longer
# heading like "## Corporate machine checklist" also counts) and the next
# "## " heading. Strips CR first (GitHub's web editor saves CRLF) and HTML
# comments (the template keeps its writing rules in one, and their
# example lines mustn't count as items). Returns 1 if there's no such
# heading.
omawsl_corporate_checklist_section() {
  local cleaned
  cleaned="$(printf '%s\n' "$1" | tr -d '\r' | perl -0pe 's/<!--.*?-->//gs')"
  grep -q '^## Corporate machine' <<< "$cleaned" || return 1
  awk '
    /^## / { in_section = ($0 ~ /^## Corporate machine/); next }
    in_section { print }
  ' <<< "$cleaned"
}

# omawsl_check_corporate_checklist <body> <head_sha>
# Prints one FAIL line per problem (so the Actions log says exactly what's
# missing) and returns 1, or prints a single OK line and returns 0.
omawsl_check_corporate_checklist() {
  local body="$1" head_sha="${2,,}" section
  if ! section="$(omawsl_corporate_checklist_section "$body")"; then
    echo "FAIL: no '## Corporate machine' section in the PR description - copy it from .github/pull_request_template.md."
    return 1
  fi

  local unticked ticked tested failed=0
  unticked="$(grep -cE '^[[:space:]]*[-*] \[ \]' <<< "$section" || true)"
  ticked="$(grep -cE '^[[:space:]]*[-*] \[[xX]\]' <<< "$section" || true)"
  tested="$(grep -m1 -oE '^Tested commit:[[:space:]]*`?[0-9a-fA-F]{7,40}`?[[:space:]]*$' <<< "$section" \
    | grep -oE '[0-9a-fA-F]{7,40}' || true)"
  tested="${tested,,}"

  if [[ "$unticked" -gt 0 ]]; then
    echo "FAIL: $unticked unticked item(s) in '## Corporate machine' - tick each one after doing it on the corporate machine."
    failed=1
  fi
  if [[ "$ticked" -eq 0 ]]; then
    echo "FAIL: no ticked items in '## Corporate machine' - every PR has at least the template's baseline items."
    failed=1
  fi
  if [[ -z "$tested" ]]; then
    echo "FAIL: no 'Tested commit:' line with a commit id (7+ hex characters) in '## Corporate machine'."
    failed=1
  elif [[ "$head_sha" != "$tested"* ]]; then
    echo "FAIL: Tested commit $tested is not this PR's head ($head_sha) - re-test the latest push on the corporate machine."
    failed=1
  fi

  [[ "$failed" -eq 0 ]] || return 1
  echo "OK: $ticked corporate item(s) ticked, tested commit $tested is this PR's head."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_check_corporate_checklist "${PR_BODY:-}" "${HEAD_SHA:-}"
fi
