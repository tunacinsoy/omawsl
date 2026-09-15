#!/usr/bin/env bash
set -euo pipefail

# Never touches your real $HOME: every invocation of the learner's cli.sh
# below runs with HOME (and cwd) overridden to a scratch directory, so
# choices.env is written and read inside a fake home the check controls
# and deletes when it's done.

root_scratch="$(mktemp -d)"
trap 'rm -rf "$root_scratch"' EXIT
failed=0

script="$(cd "$(dirname "$0")" && pwd)/cli.sh"

if [[ ! -f "$script" ]]; then
  echo "FAIL: practice/07-cli-completion/cli.sh does not exist yet"
  exit 1
fi

new_home() {
  local dir="$root_scratch/$1"
  mkdir -p "$dir"
  echo "$dir"
}

run() {
  # run <home_dir> <cli args...>
  local home="$1"; shift
  ( cd "$home" && HOME="$home" bash "$script" "$@" )
}

# --- Scenario 1: add persists to choices.env, doctor reports it -----------
home1="$(new_home home1)"

if run "$home1" add go > /dev/null 2>&1; then
  echo "PASS: 'cli.sh add go' ran without error"
else
  echo "FAIL: 'cli.sh add go' raised an error — check the implementation for a syntax or runtime error"
  failed=1
fi

choices_file="$home1/.local/state/omawsl-practice/choices.env"
if [[ -f "$choices_file" ]] && grep -q '^OMAWSL_ITEMS="Go"$' "$choices_file"; then
  echo "PASS: choices.env has OMAWSL_ITEMS=\"Go\" after 'add go'"
else
  echo "FAIL: expected $choices_file to contain OMAWSL_ITEMS=\"Go\" after 'add go'"
  failed=1
fi

doctor_out="$(run "$home1" doctor 2>/dev/null || echo '<error>')"
if grep -q '^  \[SELECTED\] Go$' <<< "$doctor_out"; then
  echo "PASS: 'cli.sh doctor' reports Go as selected"
else
  echo "FAIL: 'cli.sh doctor' did not report Go as selected — got:"$'\n'"$doctor_out"
  failed=1
fi

# --- Scenario 2: a second add unions in, doesn't clobber the first --------
run "$home1" add node > /dev/null 2>&1 || true
doctor_out="$(run "$home1" doctor 2>/dev/null || echo '<error>')"
if grep -q '^  \[SELECTED\] Go$' <<< "$doctor_out" && grep -q '^  \[SELECTED\] Node\.js$' <<< "$doctor_out"; then
  echo "PASS: 'add node' after 'add go' reports both Go and Node.js"
else
  echo "FAIL: expected both Go and Node.js reported after 'add go' then 'add node' — got:"$'\n'"$doctor_out"
  failed=1
fi

# --- Scenario 3: re-adding an already-selected item doesn't duplicate it --
run "$home1" add go > /dev/null 2>&1 || true
doctor_out="$(run "$home1" doctor 2>/dev/null || echo '<error>')"
go_lines="$(grep -c '^  \[SELECTED\] Go$' <<< "$doctor_out" || true)"
if [[ "$go_lines" -eq 1 ]]; then
  echo "PASS: re-running 'add go' does not duplicate Go in the report"
else
  echo "FAIL: expected exactly one '[SELECTED] Go' line after re-adding go, found $go_lines — got:"$'\n'"$doctor_out"
  failed=1
fi

# --- Scenario 4: remove takes it out of choices.env AND the report -------
# This is the real bug the original project shipped and then fixed
# (commit 821743c): uninstall removed the software but left the label in
# choices.env, so doctor kept reporting it as selected. Removing here must
# actually update the persisted list, not just "do nothing wrong."
if run "$home1" remove go > /dev/null 2>&1; then
  echo "PASS: 'cli.sh remove go' ran without error"
else
  echo "FAIL: 'cli.sh remove go' raised an error — check the implementation for a syntax or runtime error"
  failed=1
fi

doctor_out="$(run "$home1" doctor 2>/dev/null || echo '<error>')"
if ! grep -q '^  \[SELECTED\] Go$' <<< "$doctor_out" && grep -q '^  \[SELECTED\] Node\.js$' <<< "$doctor_out"; then
  echo "PASS: after 'remove go', doctor no longer reports Go but still reports Node.js"
else
  echo "FAIL: after 'remove go', doctor should report Node.js but not Go — got:"$'\n'"$doctor_out"
  failed=1
fi

if grep -q '^OMAWSL_ITEMS="Node\.js"$' "$choices_file"; then
  echo "PASS: choices.env no longer lists Go after 'remove go'"
else
  echo "FAIL: expected $choices_file to contain OMAWSL_ITEMS=\"Node.js\" (Go removed) after 'remove go' — got: $(cat "$choices_file" 2>/dev/null || echo '<missing>')"
  failed=1
fi

# --- Scenario 5: removing an item that was never added is a clean no-op --
if run "$home1" remove vscode > /dev/null 2>&1; then
  echo "PASS: 'cli.sh remove vscode' on a never-added item ran without error"
else
  echo "FAIL: 'cli.sh remove vscode' on a never-added item raised an error — removal of an unselected item should no-op, not fail"
  failed=1
fi

doctor_out="$(run "$home1" doctor 2>/dev/null || echo '<error>')"
if grep -q '^  \[SELECTED\] Node\.js$' <<< "$doctor_out" && ! grep -q 'VS Code' <<< "$doctor_out"; then
  echo "PASS: removing a never-added item left the rest of the selection untouched"
else
  echo "FAIL: removing a never-added item should not change what's reported — got:"$'\n'"$doctor_out"
  failed=1
fi

# --- Scenario 6: nothing selected reports the empty state explicitly -----
home2="$(new_home home2)"
doctor_out="$(run "$home2" doctor 2>/dev/null || echo '<error>')"
if [[ "$doctor_out" == "  (none selected)" ]]; then
  echo "PASS: 'cli.sh doctor' with nothing added reports '(none selected)'"
else
  echo "FAIL: expected 'cli.sh doctor' with nothing added to print exactly '  (none selected)' — got:"$'\n'"$doctor_out"
  failed=1
fi

# --- Scenario 7: removing the only selected item returns to that state --
run "$home2" add go > /dev/null 2>&1 || true
run "$home2" remove go > /dev/null 2>&1 || true
doctor_out="$(run "$home2" doctor 2>/dev/null || echo '<error>')"
if [[ "$doctor_out" == "  (none selected)" ]]; then
  echo "PASS: removing the only selected item returns doctor to '(none selected)'"
else
  echo "FAIL: expected '(none selected)' after adding then removing the only item — got:"$'\n'"$doctor_out"
  failed=1
fi

# --- Scenario 8: doctor reports in registry order, not insertion order ---
home3="$(new_home home3)"
run "$home3" add vscode > /dev/null 2>&1 || true
run "$home3" add go > /dev/null 2>&1 || true
doctor_out="$(run "$home3" doctor 2>/dev/null || echo '<error>')"
go_line="$(grep -n '^  \[SELECTED\] Go$' <<< "$doctor_out" | cut -d: -f1 || true)"
vscode_line="$(grep -n '^  \[SELECTED\] VS Code$' <<< "$doctor_out" | cut -d: -f1 || true)"
if [[ -n "$go_line" && -n "$vscode_line" && "$go_line" -lt "$vscode_line" ]]; then
  echo "PASS: doctor reports Go before VS Code (registry order), even though VS Code was added first"
else
  echo "FAIL: doctor should list items in registry.sh's order (go, node, vscode), not the order they were added — got:"$'\n'"$doctor_out"
  failed=1
fi

exit "$failed"
