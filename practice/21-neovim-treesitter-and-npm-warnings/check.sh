#!/usr/bin/env bash
set -euo pipefail

# Side effects: none. omawsl_filter_allow_scripts_warning is a pure
# text-in/text-out function (stdin -> stdout) with no dispatcher, no file
# writes, and no command invocations of its own - sourcing npm-filter.sh
# is safe. Every sample below is canned text standing in for npm's
# already-captured output; no real `npm` or `mise` command ever runs, and
# nothing touches the network. That's deliberate: this phase's real
# omawsl_install_npm_cli_wrapper does install real software via a real
# package manager, which a check script must never actually trigger - see
# lib.sh in this directory (Part 1, uncovered by any check) for that part.

here="$(cd "$(dirname "$0")" && pwd)"
source "$here/npm-filter.sh"

failed=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; failed=1; }

# run_filter <input> -> prints filtered output on stdout, never aborts
# the check under set -e/pipefail even if the function under test errors
# or doesn't exist yet.
run_filter() {
  local input="$1"
  printf '%s\n' "$input" | omawsl_filter_allow_scripts_warning 2>/dev/null
}

# ---------------------------------------------------------------------
# Sample 1: the real shape of npm's output when it has something to
# warn about - the multi-line allow-scripts advisory block, one
# unrelated real npm warning that must survive, and an ordinary success
# line that must also survive.
# ---------------------------------------------------------------------

mixed_input="npm warn allow-scripts 1 package has install scripts not yet covered by allowScripts:
npm warn allow-scripts   tree-sitter-cli@0.26.12 (install: node install.js)
npm warn allow-scripts
npm warn allow-scripts Run \`npm approve-scripts --allow-scripts-pending\` to review, or \`npm approve-scripts <pkg>\` to allow.
npm warn deprecated some-dep@1.0.0: use something-else instead
added 1 package in 1s"

expected_mixed="npm warn deprecated some-dep@1.0.0: use something-else instead
added 1 package in 1s"

filtered_mixed="$(run_filter "$mixed_input" || echo '<error>')"

if [[ "$filtered_mixed" != *"allow-scripts"* ]]; then
  pass "the allow-scripts advisory block is removed from mixed output"
else
  fail "the allow-scripts advisory block is still present in the filtered output (a line starting with 'npm warn allow-scripts' survived)"
fi

if [[ "$filtered_mixed" == *"npm warn deprecated some-dep@1.0.0: use something-else instead"* ]]; then
  pass "an unrelated real npm warning (deprecation notice) is NOT swallowed"
else
  fail "an unrelated npm warning was removed too - the filter is too broad, matching more than just the allow-scripts prefix"
fi

if [[ "$filtered_mixed" == *"added 1 package in 1s"* ]]; then
  pass "ordinary success output (a non-warning line) survives the filter"
else
  fail "ordinary success output ('added 1 package in 1s') did not survive the filter"
fi

if [[ "$filtered_mixed" == "$expected_mixed" ]]; then
  pass "filtered output matches exactly (right lines, right order, nothing extra, nothing missing)"
else
  fail "filtered output did not match exactly what was expected — got:
---
$filtered_mixed
---
expected:
---
$expected_mixed
---"
fi

# ---------------------------------------------------------------------
# Sample 2: edge case - every line of input is an allow-scripts line, so
# nothing should survive. The function must still exit 0, not error out
# just because its output ended up empty (the `grep -v ... || true`
# lesson from the Walkthrough).
# ---------------------------------------------------------------------

only_advisory_input="npm warn allow-scripts 1 package has install scripts not yet covered by allowScripts:
npm warn allow-scripts   some-other-pkg@2.0.0 (install: node install.js)"

set +e
filtered_only_advisory="$(printf '%s\n' "$only_advisory_input" | omawsl_filter_allow_scripts_warning 2>/dev/null)"
only_advisory_status=$?
set -e

if [[ "$only_advisory_status" -eq 0 ]]; then
  pass "the function exits 0 even when every input line gets filtered out"
else
  fail "the function exited non-zero ($only_advisory_status) when every input line matched and was filtered out — it should still succeed, just print nothing"
fi

if [[ -z "$filtered_only_advisory" ]]; then
  pass "output is empty when every input line was an allow-scripts line"
else
  fail "expected empty output when every input line was an allow-scripts line, got: '$filtered_only_advisory'"
fi

# ---------------------------------------------------------------------
# Sample 3: no allow-scripts lines at all - plain input must pass
# through completely untouched, in order.
# ---------------------------------------------------------------------

plain_input="npm warn deprecated old-thing@0.1.0: no longer maintained
added 3 packages in 2s"

filtered_plain="$(run_filter "$plain_input" || echo '<error>')"

if [[ "$filtered_plain" == "$plain_input" ]]; then
  pass "input with no allow-scripts lines passes through completely unchanged"
else
  fail "plain input (no allow-scripts lines) was altered — got:
---
$filtered_plain
---
expected (unchanged):
---
$plain_input
---"
fi

exit "$failed"
