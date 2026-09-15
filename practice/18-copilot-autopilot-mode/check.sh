#!/usr/bin/env bash
set -euo pipefail

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
failed=0

script="$(cd "$(dirname "$0")" && pwd)/autopilot.sh"
ALIAS_LINE='alias copilot="copilot --autopilot --allow-all"'

# read_choice <home_dir>
# Reads OMAWSL_COPILOT_AUTOPILOT straight out of that scratch $HOME's
# choices.env, the same raw grep/cut approach configs/bashrc itself uses
# in the real project (never `source`d) - prints "" if never persisted.
read_choice() {
  local home_dir="$1" file="$1/.local/state/omawsl/choices.env"
  grep -m1 '^OMAWSL_COPILOT_AUTOPILOT=' "$file" 2>/dev/null | cut -d'"' -f2 || true
}

# --- Case 1: install yes on a fresh machine -------------------------------
home1="$scratch/home1"
mkdir -p "$home1"

if ( cd "$home1" && HOME="$home1" bash "$script" install yes > /dev/null ); then
  echo "PASS: 'autopilot.sh install yes' ran without error"
else
  echo "FAIL: running 'autopilot.sh install yes' raised an error — check the implementation for a syntax or runtime error"
  failed=1
fi

if [[ -f "$home1/.bashrc" ]] && grep -qF "$ALIAS_LINE" "$home1/.bashrc"; then
  echo "PASS: 'install yes' adds the copilot autopilot alias to ~/.bashrc"
else
  echo "FAIL: 'install yes' did not add '$ALIAS_LINE' to ~/.bashrc"
  failed=1
fi

choice1="$(read_choice "$home1")"
if [[ "$choice1" == "yes" ]]; then
  echo "PASS: 'install yes' persists OMAWSL_COPILOT_AUTOPILOT=\"yes\""
else
  echo "FAIL: expected OMAWSL_COPILOT_AUTOPILOT to be 'yes' after 'install yes', found '$choice1'"
  failed=1
fi

# --- Case 2: install yes twice is idempotent (no duplicate alias line) ---
if ( cd "$home1" && HOME="$home1" bash "$script" install yes > /dev/null ); then
  echo "PASS: running 'install yes' a second time did not error"
else
  echo "FAIL: running 'install yes' a second time raised an error"
  failed=1
fi

alias_count="$(grep -cF "$ALIAS_LINE" "$home1/.bashrc" 2>/dev/null || true)"
alias_count="${alias_count:-0}"
if [[ "$alias_count" -eq 1 ]]; then
  echo "PASS: 'install yes' run twice still leaves exactly one alias line (idempotent)"
else
  echo "FAIL: expected exactly 1 copy of the alias line after running 'install yes' twice, found $alias_count"
  failed=1
fi

# --- Case 3: install no on a fresh machine --------------------------------
home3="$scratch/home3"
mkdir -p "$home3"

if ( cd "$home3" && HOME="$home3" bash "$script" install no > /dev/null ); then
  echo "PASS: 'autopilot.sh install no' ran without error"
else
  echo "FAIL: running 'autopilot.sh install no' raised an error"
  failed=1
fi

if [[ ! -f "$home3/.bashrc" ]] || ! grep -qF "$ALIAS_LINE" "$home3/.bashrc" 2>/dev/null; then
  echo "PASS: 'install no' does not add the copilot autopilot alias"
else
  echo "FAIL: 'install no' added the alias line to ~/.bashrc even though the answer was 'no'"
  failed=1
fi

choice3="$(read_choice "$home3")"
if [[ "$choice3" == "no" ]]; then
  echo "PASS: 'install no' persists OMAWSL_COPILOT_AUTOPILOT=\"no\""
else
  echo "FAIL: expected OMAWSL_COPILOT_AUTOPILOT to be 'no' after 'install no', found '$choice3'"
  failed=1
fi

# --- Case 4: flipping yes -> no removes a previously-added alias ---------
home4="$scratch/home4"
mkdir -p "$home4"

if ( cd "$home4" && HOME="$home4" bash "$script" install yes > /dev/null \
     && HOME="$home4" bash "$script" install no > /dev/null ); then
  echo "PASS: 'install yes' followed by 'install no' ran without error"
else
  echo "FAIL: running 'install yes' then 'install no' raised an error"
  failed=1
fi

if [[ ! -f "$home4/.bashrc" ]] || ! grep -qF "$ALIAS_LINE" "$home4/.bashrc" 2>/dev/null; then
  echo "PASS: flipping the answer from yes to no removes the previously-added alias"
else
  echo "FAIL: the alias line was still present in ~/.bashrc after flipping the answer to 'no'"
  failed=1
fi

# --- Case 5: install never touches other lines already in ~/.bashrc ------
home5="$scratch/home5"
mkdir -p "$home5"
printf 'export SOME_OTHER_VAR=1\nalias ll="ls -la"\n' > "$home5/.bashrc"

if ( cd "$home5" && HOME="$home5" bash "$script" install yes > /dev/null ); then
  echo "PASS: 'install yes' ran without error against a ~/.bashrc that already had content"
else
  echo "FAIL: 'install yes' raised an error against a ~/.bashrc that already had content"
  failed=1
fi

if grep -qF 'export SOME_OTHER_VAR=1' "$home5/.bashrc" 2>/dev/null \
  && grep -qF 'alias ll="ls -la"' "$home5/.bashrc" 2>/dev/null; then
  echo "PASS: pre-existing ~/.bashrc content survives 'install yes' untouched"
else
  echo "FAIL: 'install yes' clobbered pre-existing ~/.bashrc content instead of just adding its one line"
  failed=1
fi

# --- Case 6: uninstall clears the persisted choice and removes the alias -
home6="$scratch/home6"
mkdir -p "$home6"

( cd "$home6" && HOME="$home6" bash "$script" install yes > /dev/null ) || true

if ( cd "$home6" && HOME="$home6" bash "$script" uninstall > /dev/null ); then
  echo "PASS: 'autopilot.sh uninstall' ran without error"
else
  echo "FAIL: running 'autopilot.sh uninstall' raised an error"
  failed=1
fi

if [[ ! -f "$home6/.bashrc" ]] || ! grep -qF "$ALIAS_LINE" "$home6/.bashrc" 2>/dev/null; then
  echo "PASS: 'uninstall' removes the copilot autopilot alias from ~/.bashrc"
else
  echo "FAIL: the alias line was still present in ~/.bashrc after 'uninstall'"
  failed=1
fi

choice6="$(read_choice "$home6")"
if [[ -z "$choice6" ]]; then
  echo "PASS: 'uninstall' clears the persisted OMAWSL_COPILOT_AUTOPILOT choice"
else
  echo "FAIL: expected OMAWSL_COPILOT_AUTOPILOT to be cleared (empty) after 'uninstall', found '$choice6'"
  failed=1
fi

# --- Case 7: uninstall with nothing ever installed is a safe no-op -------
home7="$scratch/home7"
mkdir -p "$home7"

if ( cd "$home7" && HOME="$home7" bash "$script" uninstall > /dev/null ); then
  echo "PASS: 'uninstall' with no prior install does not error"
else
  echo "FAIL: running 'uninstall' with nothing previously installed raised an error"
  failed=1
fi

exit "$failed"
