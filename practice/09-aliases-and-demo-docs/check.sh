#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/aliases.sh"

scratch="$(mktemp)"
trap 'rm -f "$scratch"' EXIT
failed=0

check_line() {
  local desc="$1" pattern="$2"
  if grep -qF -- "$pattern" "$scratch" 2>/dev/null; then
    echo "PASS: $desc"
  else
    echo "FAIL: $desc — expected to find this line in the target file: $pattern"
    failed=1
  fi
}

# --- first run ---

if append_omakub_aliases "$scratch" >/dev/null 2>&1; then
  echo "PASS: append_omakub_aliases ran without error on an empty file"
else
  echo "FAIL: append_omakub_aliases raised an error on the first run — check for a syntax error, an undefined variable, or a missing 'source' guard"
  failed=1
fi

check_line "ls gets eza's long-format icon flags" "alias ls='eza -lh --group-directories-first --icons=auto'"
check_line "lsa reuses ls (not a second hardcoded eza call)" "alias lsa='ls -a'"
check_line "ll is present" "alias ll='eza -la'"
check_line "lt is present" "alias lt='eza --tree --level=2 --long --icons --git'"
check_line "lta reuses lt (not a second hardcoded eza call)" "alias lta='lt -a'"
check_line "cat is aliased to batcat, not bat (the apt package-naming fix)" "alias cat='batcat --paging=never'"
check_line "fd is aliased to fdfind, not fd (the apt package-naming fix)" "alias fd='fdfind'"
check_line "cd is aliased to zoxide's z" "alias cd='z'"
check_line "the .. directory-nav alias is present" "alias ..='cd ..'"
check_line "the ... directory-nav alias is present" "alias ...='cd ../..'"
check_line "the .... directory-nav alias is present" "alias ....='cd ../../..'"
check_line "the git shortcut alias is present" "alias g='git'"
check_line "the git commit -m alias is present" "alias gcm='git commit -m'"
check_line "the git commit -a -m alias is present" "alias gcam='git commit -a -m'"
check_line "the git commit -a --amend alias is present" "alias gcad='git commit -a --amend'"
check_line "the docker shortcut alias is present" "alias d='docker'"
check_line "the rails shortcut alias is present" "alias r='rails'"
check_line "the lazygit shortcut alias is present" "alias lzg='lazygit'"
check_line "the lazydocker shortcut alias is present" "alias lzd='lazydocker'"
check_line "the n() function opens nvim on the current directory when called with no arguments" "nvim ."

if grep -qF -- '# >>> omawsl aliases >>>' "$scratch" 2>/dev/null; then
  echo "PASS: the appended block is wrapped in the '# >>> omawsl aliases >>>' marker"
else
  echo "FAIL: no '# >>> omawsl aliases >>>' marker line found in the target file"
  failed=1
fi

# --- second run: idempotency ---

if append_omakub_aliases "$scratch" >/dev/null 2>&1; then
  echo "PASS: append_omakub_aliases ran without error on a second run"
else
  echo "FAIL: append_omakub_aliases raised an error on the second run"
  failed=1
fi

marker_count="$(grep -cF -- '# >>> omawsl aliases >>>' "$scratch" 2>/dev/null || true)"
if [[ "$marker_count" == "1" ]]; then
  echo "PASS: a second run did not duplicate the aliases block (marker appears exactly once)"
else
  echo "FAIL: expected exactly one '# >>> omawsl aliases >>>' marker after two runs, found ${marker_count:-0}"
  failed=1
fi

git_alias_count="$(grep -cF -- "alias g='git'" "$scratch" 2>/dev/null || true)"
if [[ "$git_alias_count" == "1" ]]; then
  echo "PASS: a second run did not duplicate individual alias lines (alias g='git' appears exactly once)"
else
  echo "FAIL: expected exactly one \"alias g='git'\" line after two runs, found ${git_alias_count:-0}"
  failed=1
fi

cd_alias_count="$(grep -cF -- "alias cd='z'" "$scratch" 2>/dev/null || true)"
if [[ "$cd_alias_count" == "1" ]]; then
  echo "PASS: a second run did not duplicate individual alias lines (alias cd='z' appears exactly once)"
else
  echo "FAIL: expected exactly one \"alias cd='z'\" line after two runs, found ${cd_alias_count:-0}"
  failed=1
fi

exit "$failed"
