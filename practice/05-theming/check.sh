#!/usr/bin/env bash
set -euo pipefail

# Checks practice/05-theming/theme.sh's `apply_theme <name>` (wired up as
# `bash theme.sh apply <name>`) against the behavior described in
# docs/curriculum/05-theming.md's Exercise section.
#
# Every invocation of the learner's script runs with both HOME and the
# working directory redirected to a fresh scratch directory (Strategy B,
# Technique 1) - nothing here ever touches the real $HOME, and nothing
# here writes into this practice/ directory itself.

root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT
failed=0

practice_dir="$(cd "$(dirname "$0")" && pwd)"
script="$practice_dir/theme.sh"
themes_dir="$practice_dir/themes"

if [[ ! -f "$script" ]]; then
  echo "FAIL: $script does not exist yet - nothing to check"
  exit 1
fi

have_jq=0
if command -v jq &>/dev/null; then
  have_jq=1
fi

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; failed=1; }

# --- Scenario 1: fresh HOME, no pre-existing zellij/btop/WT config -------

home1="$root/home1"
mkdir -p "$home1"

if ( cd "$home1" && HOME="$home1" bash "$script" apply aurora >"$home1.out" 2>&1 ); then
  pass "'theme.sh apply aurora' succeeds against a fresh \$HOME"
else
  fail "'theme.sh apply aurora' exited non-zero against a fresh \$HOME (output: $(cat "$home1.out" 2>/dev/null || echo '<none>'))"
fi

if [[ -f "$home1/.config/zellij/themes/aurora.kdl" ]] \
  && diff -q "$home1/.config/zellij/themes/aurora.kdl" "$themes_dir/aurora/zellij.kdl" >/dev/null 2>&1; then
  pass "zellij palette file is copied to ~/.config/zellij/themes/aurora.kdl unconditionally"
else
  fail "~/.config/zellij/themes/aurora.kdl is missing or doesn't match themes/aurora/zellij.kdl"
fi

if [[ ! -f "$home1/.config/zellij/config.kdl" ]]; then
  pass "no zellij config.kdl is created when one didn't already exist"
else
  fail "a zellij config.kdl was created out of nothing - the active-config patch should only run when config.kdl already exists"
fi

if [[ ! -d "$home1/.config/btop" ]]; then
  pass "nothing under ~/.config/btop is created when btop.conf didn't already exist"
else
  fail "~/.config/btop was created even though no btop.conf existed - the whole btop block should be skipped, not just the sed patch"
fi

if [[ ! -f "$home1/.config/windows-terminal-settings.json" ]]; then
  pass "no Windows-Terminal-style settings file is created when the target didn't already exist"
else
  fail "~/.config/windows-terminal-settings.json was created even though it didn't exist beforehand - that case should be skipped, not created"
fi

# --- Scenario 2: zellij config.kdl already exists, should be patched -----

home2="$root/home2"
mkdir -p "$home2/.config/zellij"
echo 'theme "old-theme"' > "$home2/.config/zellij/config.kdl"

if ( cd "$home2" && HOME="$home2" bash "$script" apply aurora >"$home2.out" 2>&1 ); then
  pass "'theme.sh apply aurora' succeeds with a pre-existing zellij config.kdl"
else
  fail "'theme.sh apply aurora' exited non-zero with a pre-existing zellij config.kdl (output: $(cat "$home2.out" 2>/dev/null || echo '<none>'))"
fi

content="$(cat "$home2/.config/zellij/config.kdl" 2>/dev/null || echo '<missing>')"
if grep -q 'theme "aurora"' "$home2/.config/zellij/config.kdl" 2>/dev/null; then
  pass "an existing zellij config.kdl's theme line is rewritten to the new theme name"
else
  fail "zellij config.kdl was not patched to reference 'aurora' - contents were: $content"
fi

# --- Scenario 3: btop.conf already exists, should be patched -------------

home3="$root/home3"
mkdir -p "$home3/.config/btop"
echo 'color_theme = "old"' > "$home3/.config/btop/btop.conf"

if ( cd "$home3" && HOME="$home3" bash "$script" apply dusk >"$home3.out" 2>&1 ); then
  pass "'theme.sh apply dusk' succeeds with a pre-existing btop.conf"
else
  fail "'theme.sh apply dusk' exited non-zero with a pre-existing btop.conf (output: $(cat "$home3.out" 2>/dev/null || echo '<none>'))"
fi

if grep -q 'color_theme = "dusk"' "$home3/.config/btop/btop.conf" 2>/dev/null; then
  pass "an existing btop.conf's color_theme line is rewritten to the new theme name"
else
  fail "btop.conf was not patched to reference 'dusk' - contents were: $(cat "$home3/.config/btop/btop.conf" 2>/dev/null || echo '<missing>')"
fi

if [[ -f "$home3/.config/btop/themes/dusk.theme" ]] \
  && diff -q "$home3/.config/btop/themes/dusk.theme" "$themes_dir/dusk/btop.theme" >/dev/null 2>&1; then
  pass "btop palette file is copied to ~/.config/btop/themes/dusk.theme when btop.conf exists"
else
  fail "~/.config/btop/themes/dusk.theme is missing or doesn't match themes/dusk/btop.theme"
fi

# --- Scenario 4: unknown theme name is rejected ---------------------------

home4="$root/home4"
mkdir -p "$home4"

if ( cd "$home4" && HOME="$home4" bash "$script" apply not-a-real-theme >"$home4.out" 2>&1 ); then
  fail "'theme.sh apply not-a-real-theme' exited 0 - an unknown theme name should be rejected"
else
  pass "'theme.sh apply not-a-real-theme' exits non-zero for an unknown theme name"
fi

# --- Scenario 5: Windows-Terminal-style merge (requires jq) --------------

if [[ "$have_jq" -eq 1 ]]; then
  # 5a: target exists but is not valid JSON - must be left completely
  # untouched, and no backup should be made.
  home5="$root/home5"
  mkdir -p "$home5/.config"
  printf '{ this is not valid json' > "$home5/.config/windows-terminal-settings.json"
  before="$(cat "$home5/.config/windows-terminal-settings.json")"

  if ( cd "$home5" && HOME="$home5" bash "$script" apply aurora >"$home5.out" 2>&1 ); then
    pass "'theme.sh apply aurora' succeeds even when the WT-style settings file is malformed JSON"
  else
    fail "'theme.sh apply aurora' exited non-zero on malformed JSON - it should skip gracefully, not abort (output: $(cat "$home5.out" 2>/dev/null || echo '<none>'))"
  fi

  after="$(cat "$home5/.config/windows-terminal-settings.json" 2>/dev/null || echo '<missing>')"
  if [[ "$before" == "$after" ]]; then
    pass "a malformed WT-style settings file is left byte-for-byte untouched"
  else
    fail "a malformed WT-style settings file was modified - it should be skipped, not edited"
  fi

  if [[ ! -f "$home5/.config/windows-terminal-settings.json.bak" ]]; then
    pass "no backup is made when the WT-style settings file was malformed to begin with"
  else
    fail "a .bak file was created for a malformed settings file - backups should only happen right before a real edit"
  fi

  # 5b: target exists, valid JSON, already has an entry for a different
  # scheme and an old entry for the same scheme name - should back up,
  # replace (not duplicate) the same-named entry, and set colorScheme.
  home6="$root/home6"
  mkdir -p "$home6/.config"
  seed='{"schemes":[{"name":"Other","background":"#000000"},{"name":"Aurora","background":"#111111"}],"profiles":{"defaults":{"colorScheme":"Other"}}}'
  echo "$seed" > "$home6/.config/windows-terminal-settings.json"

  if ( cd "$home6" && HOME="$home6" bash "$script" apply aurora >"$home6.out" 2>&1 ); then
    pass "'theme.sh apply aurora' succeeds against a valid, pre-populated WT-style settings file"
  else
    fail "'theme.sh apply aurora' exited non-zero against a valid WT-style settings file (output: $(cat "$home6.out" 2>/dev/null || echo '<none>'))"
  fi

  if [[ -f "$home6/.config/windows-terminal-settings.json.bak" ]] \
    && [[ "$(cat "$home6/.config/windows-terminal-settings.json.bak")" == "$seed" ]]; then
    pass "the original WT-style settings file is backed up before being edited"
  else
    fail "no correct .bak backup of the original WT-style settings file was found"
  fi

  names="$(jq -r '.schemes | map(.name) | sort | join(",")' "$home6/.config/windows-terminal-settings.json" 2>/dev/null || echo '<error>')"
  if [[ "$names" == "Aurora,Other" ]]; then
    pass "the schemes array has exactly one entry per name - the old 'Aurora' entry was replaced, not duplicated"
  else
    fail "expected schemes named 'Aurora,Other' (sorted), got: $names"
  fi

  bg="$(jq -r '.schemes[] | select(.name == "Aurora") | .background' "$home6/.config/windows-terminal-settings.json" 2>/dev/null || echo '<error>')"
  if [[ "$bg" == "#101020" ]]; then
    pass "the replaced 'Aurora' scheme entry has the new theme's color values, not the old ones"
  else
    fail "expected the 'Aurora' scheme's background to be '#101020' (from themes/aurora/windows-terminal-scheme.json), got: $bg"
  fi

  active="$(jq -r '.profiles.defaults.colorScheme' "$home6/.config/windows-terminal-settings.json" 2>/dev/null || echo '<error>')"
  if [[ "$active" == "Aurora" ]]; then
    pass "profiles.defaults.colorScheme is set to the applied theme's scheme name"
  else
    fail "expected profiles.defaults.colorScheme to be 'Aurora', got: $active"
  fi
else
  echo "SKIP: jq is not installed on this machine - skipping all Windows-Terminal-style settings assertions"
fi

exit "$failed"
