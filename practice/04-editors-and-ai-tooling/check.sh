#!/usr/bin/env bash
# practice/04-editors-and-ai-tooling/check.sh
#
# Behavioral check for editors.sh (see docs/curriculum/04-editors-and-ai-tooling.md,
# section 3). Never runs the learner's script un-contained: every invocation
# below overrides both HOME and cwd to a scratch directory (nothing here can
# land in the learner's own practice/ directory or their real $HOME), and
# stubs the two external "installer" commands (neovim_installer,
# gh_copilot_installer) via `export -f` before invoking, so nothing real
# ever runs even if the learner's implementation calls something unexpected.

set -euo pipefail

scratch_root="$(mktemp -d)"
trap 'rm -rf "$scratch_root"' EXIT
failed=0

script_dir="$(cd "$(dirname "$0")" && pwd)"
script="$script_dir/editors.sh"
baseline="$script_dir/baseline-settings.json"

if [[ ! -f "$script" ]]; then
  echo "FAIL: $script does not exist - nothing to check"
  exit 1
fi

if [[ ! -f "$baseline" ]]; then
  echo "FAIL: $baseline is missing - the check itself is broken, not your solution"
  exit 1
fi

# ---------------------------------------------------------------------------
# Scenario A: all four tools selected, gh-copilot's installer fails.
# Exercises: shared config (vscode + cursor), and the case-study isolation
# fix - cursor and neovim are scheduled AFTER gh-copilot in the fixed
# dispatch order, so they must still run despite gh-copilot's failure.
# ---------------------------------------------------------------------------
home_a="$scratch_root/home-a"
mkdir -p "$home_a"
log_a="$scratch_root/calls-a.log"
export CALL_LOG="$log_a"

neovim_installer() { echo "neovim_installer" >> "$CALL_LOG"; }
gh_copilot_installer() { echo "gh_copilot_installer" >> "$CALL_LOG"; return 1; }
export -f neovim_installer
export -f gh_copilot_installer

status_a=0
( cd "$home_a" && HOME="$home_a" \
  OMAWSL_EDITORS="VS Code,GitHub Copilot CLI,Cursor,Neovim" \
  bash "$script" > "$scratch_root/out-a.log" 2>&1 ) || status_a=$?

if [[ "$status_a" -eq 0 ]]; then
  echo "PASS: the dispatcher did not abort when gh-copilot's installer failed"
else
  echo "FAIL: running editors.sh exited non-zero ($status_a) after gh-copilot's installer failed - its failure was not isolated (or an unrelated bug crashed the script; check output at $scratch_root/out-a.log)"
  failed=1
fi

calls_a="$(cat "$log_a" 2>/dev/null || true)"

if [[ "$calls_a" == *"gh_copilot_installer"* ]]; then
  echo "PASS: gh_copilot_installer was invoked when GitHub Copilot CLI was selected"
else
  echo "FAIL: gh_copilot_installer was never called - gh-copilot's own selection gate or dispatch is broken"
  failed=1
fi

if [[ "$calls_a" == *"neovim_installer"* ]]; then
  echo "PASS: neovim still ran after gh-copilot's installer failed (isolation held)"
else
  echo "FAIL: neovim_installer was never called - gh-copilot's failure appears to have stopped the dispatch before reaching neovim, the same bug this lesson is about"
  failed=1
fi

vscode_settings_a="$home_a/.vscode-server/data/Machine/settings.json"
if [[ -f "$vscode_settings_a" ]] && diff -q "$vscode_settings_a" "$baseline" >/dev/null 2>&1; then
  echo "PASS: VS Code's settings were deployed and match baseline-settings.json exactly"
else
  echo "FAIL: VS Code's settings at $vscode_settings_a are missing or don't match baseline-settings.json"
  failed=1
fi

cursor_settings_a="$home_a/.cursor-server/data/Machine/settings.json"
if [[ -f "$cursor_settings_a" ]] && diff -q "$cursor_settings_a" "$baseline" >/dev/null 2>&1; then
  echo "PASS: Cursor's settings were deployed after gh-copilot's failure, and match the SAME baseline-settings.json VS Code uses"
else
  echo "FAIL: Cursor's settings at $cursor_settings_a are missing or don't match baseline-settings.json - either the shared-config step is broken, or gh-copilot's failure stopped the dispatch before reaching cursor"
  failed=1
fi

# ---------------------------------------------------------------------------
# Scenario B: only "VS Code" selected. Exercises: each tool gates on its
# OWN label and no-ops otherwise - selecting VS Code must not also trigger
# Cursor, Neovim, or GitHub Copilot CLI's steps.
# ---------------------------------------------------------------------------
home_b="$scratch_root/home-b"
mkdir -p "$home_b"
log_b="$scratch_root/calls-b.log"
export CALL_LOG="$log_b"

neovim_installer() { echo "neovim_installer" >> "$CALL_LOG"; }
gh_copilot_installer() { echo "gh_copilot_installer" >> "$CALL_LOG"; }
export -f neovim_installer
export -f gh_copilot_installer

status_b=0
( cd "$home_b" && HOME="$home_b" \
  OMAWSL_EDITORS="VS Code" \
  bash "$script" > "$scratch_root/out-b.log" 2>&1 ) || status_b=$?

if [[ "$status_b" -eq 0 ]]; then
  echo "PASS: selecting only VS Code ran without error"
else
  echo "FAIL: selecting only VS Code exited non-zero ($status_b) - check output at $scratch_root/out-b.log"
  failed=1
fi

if [[ -f "$home_b/.vscode-server/data/Machine/settings.json" ]]; then
  echo "PASS: VS Code's settings were deployed when VS Code was selected"
else
  echo "FAIL: VS Code's settings were not deployed even though VS Code was selected"
  failed=1
fi

if [[ -f "$home_b/.cursor-server/data/Machine/settings.json" ]]; then
  echo "FAIL: Cursor's settings were deployed even though only VS Code was selected - Cursor's gate is missing or checking the wrong label"
  failed=1
else
  echo "PASS: Cursor's settings were NOT deployed when only VS Code was selected"
fi

calls_b="$(cat "$log_b" 2>/dev/null || true)"

if [[ "$calls_b" == *"neovim_installer"* ]]; then
  echo "FAIL: neovim_installer was called even though Neovim was not selected"
  failed=1
else
  echo "PASS: neovim_installer was NOT called when Neovim was not selected"
fi

if [[ "$calls_b" == *"gh_copilot_installer"* ]]; then
  echo "FAIL: gh_copilot_installer was called even though GitHub Copilot CLI was not selected"
  failed=1
else
  echo "PASS: gh_copilot_installer was NOT called when GitHub Copilot CLI was not selected"
fi

# ---------------------------------------------------------------------------
# Scenario C: Neovim selected, but ~/.config/nvim already exists. Exercises:
# never overwrite/touch an existing user config.
# ---------------------------------------------------------------------------
home_c="$scratch_root/home-c"
mkdir -p "$home_c/.config/nvim"
echo "existing config - do not touch" > "$home_c/.config/nvim/marker"
log_c="$scratch_root/calls-c.log"
export CALL_LOG="$log_c"

neovim_installer() { echo "neovim_installer" >> "$CALL_LOG"; }
gh_copilot_installer() { echo "gh_copilot_installer" >> "$CALL_LOG"; }
export -f neovim_installer
export -f gh_copilot_installer

status_c=0
( cd "$home_c" && HOME="$home_c" \
  OMAWSL_EDITORS="Neovim" \
  bash "$script" > "$scratch_root/out-c.log" 2>&1 ) || status_c=$?

if [[ "$status_c" -eq 0 ]]; then
  echo "PASS: selecting only Neovim ran without error"
else
  echo "FAIL: selecting only Neovim exited non-zero ($status_c) - check output at $scratch_root/out-c.log"
  failed=1
fi

calls_c="$(cat "$log_c" 2>/dev/null || true)"

if [[ "$calls_c" == *"neovim_installer"* ]]; then
  echo "FAIL: neovim_installer was called even though \$HOME/.config/nvim already existed - an existing config must never be touched"
  failed=1
else
  echo "PASS: neovim_installer was NOT called when \$HOME/.config/nvim already existed"
fi

marker_contents="$(cat "$home_c/.config/nvim/marker" 2>/dev/null || echo '<missing>')"
if [[ "$marker_contents" == "existing config - do not touch" ]]; then
  echo "PASS: the existing nvim config was left untouched"
else
  echo "FAIL: the existing nvim config was modified or removed (marker file now reads: $marker_contents)"
  failed=1
fi

exit "$failed"
