#!/usr/bin/env bash
set -euo pipefail

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
failed=0

lib="$(cd "$(dirname "$0")" && pwd)/lib.sh"

# Every invocation of the learner's ensure_source_line goes through this
# helper, which pins both HOME and the working directory to the scratch
# directory (never the real $HOME) for a fresh child bash process. The
# function under test is expected to build its "what to source" path from
# $HOME, so this containment is required, not optional — an un-prefixed
# call could resolve against the real machine's home directory.
run_ensure_source_line() {
  local target_file="$1"
  ( cd "$scratch" && HOME="$scratch" bash -c "set -euo pipefail; source \"$lib\"; ensure_source_line \"$target_file\"" )
}

expected_target="$scratch/.local/share/omawsl/configs/bashrc"

# --- Scenario (a): no existing content — the file doesn't exist yet ---

file_fresh="$scratch/bashrc_fresh"

if run_ensure_source_line "$file_fresh" >/dev/null 2>&1; then
  echo "PASS: ensure_source_line ran without error on a file that didn't exist yet"
else
  echo "FAIL: ensure_source_line raised an error on a nonexistent file — check the implementation for a syntax or runtime error"
  failed=1
fi

if [[ -f "$file_fresh" ]]; then
  echo "PASS: creates the file when it doesn't exist yet"
else
  echo "FAIL: no file was created at $file_fresh"
  failed=1
fi

if grep -qF '# >>> omawsl >>>' "$file_fresh" 2>/dev/null && grep -qF '# <<< omawsl <<<' "$file_fresh" 2>/dev/null; then
  echo "PASS: appends a '# >>> omawsl >>>' / '# <<< omawsl <<<' marker block"
else
  echo "FAIL: no marker block found in $file_fresh — expected both '# >>> omawsl >>>' and '# <<< omawsl <<<' lines"
  failed=1
fi

if grep -qF "$expected_target" "$file_fresh" 2>/dev/null; then
  echo "PASS: the appended line points at \$HOME/.local/share/omawsl/configs/bashrc, resolved through \$HOME"
else
  echo "FAIL: expected a line referencing $expected_target — build the sourced path from \$HOME rather than hardcoding it"
  failed=1
fi

# --- Scenario (b): the source line is already present — idempotency ---

file_idem="$scratch/bashrc_idempotent"
printf 'export SOME_CORP_VAR=1\n' > "$file_idem"
run_ensure_source_line "$file_idem" >/dev/null 2>&1 || true
printf 'some line the user added by hand\n' >> "$file_idem"
run_ensure_source_line "$file_idem" >/dev/null 2>&1 || true

marker_count="$(grep -c '# >>> omawsl >>>' "$file_idem" 2>/dev/null)" || marker_count=0
if [[ "$marker_count" -eq 1 ]]; then
  echo "PASS: running ensure_source_line twice adds the marker block exactly once (idempotent)"
else
  echo "FAIL: expected exactly 1 '# >>> omawsl >>>' marker after two runs, found $marker_count"
  failed=1
fi

if grep -qF 'export SOME_CORP_VAR=1' "$file_idem" 2>/dev/null && grep -qF 'some line the user added by hand' "$file_idem" 2>/dev/null; then
  echo "PASS: content present before the second run (original line and hand-added line) both survive"
else
  echo "FAIL: pre-existing or hand-added content was lost across two runs — ensure_source_line must never delete lines it didn't add"
  failed=1
fi

# --- Scenario (c): unrelated user content must survive untouched ---

file_unrelated="$scratch/bashrc_unrelated"
printf 'export SOME_CORP_VAR=1\nalias ll="ls -la"\n# a comment the user wrote\n' > "$file_unrelated"

run_ensure_source_line "$file_unrelated" >/dev/null 2>&1 || true

if grep -qF 'export SOME_CORP_VAR=1' "$file_unrelated" 2>/dev/null \
  && grep -qF 'alias ll="ls -la"' "$file_unrelated" 2>/dev/null \
  && grep -qF '# a comment the user wrote' "$file_unrelated" 2>/dev/null; then
  echo "PASS: unrelated pre-existing lines are all still present, untouched"
else
  echo "FAIL: unrelated pre-existing content was modified or removed — ensure_source_line must only ever append"
  failed=1
fi

count_corp="$(grep -c 'export SOME_CORP_VAR=1' "$file_unrelated" 2>/dev/null)" || count_corp=0
count_alias="$(grep -c 'alias ll="ls -la"' "$file_unrelated" 2>/dev/null)" || count_alias=0
if [[ "$count_corp" -eq 1 && "$count_alias" -eq 1 ]]; then
  echo "PASS: unrelated lines were not duplicated"
else
  echo "FAIL: unrelated lines appear more than once (found $count_corp / $count_alias) — the file was rewritten rather than appended to"
  failed=1
fi

if grep -qF '# >>> omawsl >>>' "$file_unrelated" 2>/dev/null; then
  echo "PASS: the marker block was still appended after the unrelated content"
else
  echo "FAIL: no marker block found — ensure_source_line did not add its source line at all"
  failed=1
fi

# Running it again on the same file must not disturb any of the above.
run_ensure_source_line "$file_unrelated" >/dev/null 2>&1 || true

marker_count_unrelated="$(grep -c '# >>> omawsl >>>' "$file_unrelated" 2>/dev/null)" || marker_count_unrelated=0
if [[ "$marker_count_unrelated" -eq 1 ]]; then
  echo "PASS: a third run on the same file stays idempotent (marker still appears exactly once)"
else
  echo "FAIL: expected exactly 1 '# >>> omawsl >>>' marker after a repeat run, found $marker_count_unrelated"
  failed=1
fi

exit "$failed"
