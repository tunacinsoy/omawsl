#!/usr/bin/env bash
set -euo pipefail

# Checks practice/11-native-vscode-cursor-theme-sync/theme-sync.sh against
# the behavior described in
# docs/curriculum/11-native-vscode-cursor-theme-sync.md, section 3.
#
# theme-sync.sh is pure/sourceable (a helper library of functions, no
# unconditional dispatcher at the bottom - the same shape as the real
# themes/set-vscode-theme.sh), so sourcing it directly is safe.
#
# Every settings-file assertion below runs against a file under a scratch
# directory, with BOTH HOME and the process's cwd redirected there too -
# never the real $HOME and never this practice/ directory itself - even
# though merge_theme_into_settings takes its target path as an explicit
# argument. install_theme_extension shells out to the real `code` command
# by name, so it's checked with a stubbed `code` function (Technique 2:
# export -f) - the real `code --install-extension` is never invoked.

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
failed=0

script="$(cd "$(dirname "$0")" && pwd)/theme-sync.sh"

if [[ ! -f "$script" ]]; then
  echo "FAIL: $script does not exist yet - nothing to check"
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "FAIL: this check requires 'jq' to validate JSON output - install jq and re-run"
  exit 1
fi

# shellcheck disable=SC1090
source "$script"

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; failed=1; }

# --- Scenario 1: strict JSON, key already exists -> replaced, backed up --

home1="$scratch/home1"
mkdir -p "$home1"
settings1="$scratch/settings1.json"
cat > "$settings1" <<'EOF'
{
  "editor.fontSize": 14,
  "workbench.colorTheme": "Default Dark Modern"
}
EOF

if ( cd "$home1" && HOME="$home1" merge_theme_into_settings "$settings1" "workbench.colorTheme" "Tokyo Night" ); then
  pass "merge_theme_into_settings ran without error on a strict JSON file"
else
  fail "merge_theme_into_settings raised an error on a strict JSON file"
fi

if [[ -f "$settings1.bak" ]]; then
  bak_value="$(jq -r '.["workbench.colorTheme"]' "$settings1.bak" 2>/dev/null || echo '<error>')"
  if [[ "$bak_value" == "Default Dark Modern" ]]; then
    pass "the original file was backed up to settings1.json.bak BEFORE the edit"
  else
    fail "settings1.json.bak exists but doesn't hold the pre-edit value (got '$bak_value', expected 'Default Dark Modern')"
  fi
else
  fail "no backup file was created at $settings1.bak before editing"
fi

new_value="$(jq -r '.["workbench.colorTheme"]' "$settings1" 2>/dev/null || echo '<error>')"
if [[ "$new_value" == "Tokyo Night" ]]; then
  pass "workbench.colorTheme was replaced with 'Tokyo Night' in the real file"
else
  fail "workbench.colorTheme in $settings1 was '$new_value', expected 'Tokyo Night'"
fi

fontsize="$(jq -r '.["editor.fontSize"]' "$settings1" 2>/dev/null || echo '<error>')"
if [[ "$fontsize" == "14" ]]; then
  pass "an unrelated key (editor.fontSize) survives the merge untouched"
else
  fail "editor.fontSize in $settings1 was '$fontsize', expected 14 - the merge must only touch the target key"
fi

# --- Scenario 2: JSONC, key absent -> added, comments preserved ----------

home2="$scratch/home2"
mkdir -p "$home2"
settings2="$scratch/settings2.json"
cat > "$settings2" <<'EOF'
{
  // native user settings
  "editor.fontSize": 14,
  "editor.tabSize": 2
}
EOF

if ( cd "$home2" && HOME="$home2" merge_theme_into_settings "$settings2" "workbench.colorTheme" "Tokyo Night" ); then
  pass "merge_theme_into_settings ran without error on a JSONC file with no prior key"
else
  fail "merge_theme_into_settings raised an error on a JSONC file with no prior key"
fi

if grep -qF '// native user settings' "$settings2" 2>/dev/null; then
  pass "the '// native user settings' comment survived adding a brand-new key"
else
  fail "the '// native user settings' comment was lost when adding workbench.colorTheme"
fi

stripped2="$(strip_jsonc_comments "$settings2" 2>/dev/null || echo '{}')"
theme2="$(echo "$stripped2" | jq -r '.["workbench.colorTheme"]' 2>/dev/null || echo '<error>')"
if [[ "$theme2" == "Tokyo Night" ]]; then
  pass "workbench.colorTheme was added to a JSONC file that didn't have it yet"
else
  fail "workbench.colorTheme (via your own strip_jsonc_comments) was '$theme2' after merging into a fresh JSONC file, expected 'Tokyo Night'"
fi

tabsize2="$(echo "$stripped2" | jq -r '.["editor.tabSize"]' 2>/dev/null || echo '<error>')"
if [[ "$tabsize2" == "2" ]]; then
  pass "an unrelated key (editor.tabSize) survives adding a new key to a JSONC file"
else
  fail "editor.tabSize was '$tabsize2' after the merge, expected 2"
fi

# --- Scenario 3: JSONC, key already exists -> replaced, comment preserved

home3="$scratch/home3"
mkdir -p "$home3"
settings3="$scratch/settings3.json"
cat > "$settings3" <<'EOF'
{
  "workbench.colorTheme": "Default Dark Modern", // active theme
  "editor.fontSize": 14
}
EOF

if ( cd "$home3" && HOME="$home3" merge_theme_into_settings "$settings3" "workbench.colorTheme" "Monokai Pro (Filter Ristretto)" ); then
  pass "merge_theme_into_settings ran without error replacing a key in a JSONC file"
else
  fail "merge_theme_into_settings raised an error replacing a key in a JSONC file"
fi

if grep -qF '// active theme' "$settings3" 2>/dev/null; then
  pass "the '// active theme' comment survived replacing the key's value"
else
  fail "the '// active theme' comment was lost when replacing workbench.colorTheme"
fi

stripped3="$(strip_jsonc_comments "$settings3" 2>/dev/null || echo '{}')"
theme3="$(echo "$stripped3" | jq -r '.["workbench.colorTheme"]' 2>/dev/null || echo '<error>')"
if [[ "$theme3" == "Monokai Pro (Filter Ristretto)" ]]; then
  pass "a theme name with parentheses and spaces is written correctly (no sed/awk metacharacter corruption)"
else
  fail "workbench.colorTheme was '$theme3', expected 'Monokai Pro (Filter Ristretto)' - a value with parentheses likely broke a sed/awk substitution"
fi

# --- Scenario 4: a theme name with a colon must also survive ------------

home4="$scratch/home4"
mkdir -p "$home4"
settings4="$scratch/settings4.json"
cat > "$settings4" <<'EOF'
{
  "workbench.colorTheme": "Default Dark Modern",
  "editor.fontSize": 14
}
EOF

( cd "$home4" && HOME="$home4" merge_theme_into_settings "$settings4" "workbench.colorTheme" "Ocean Green: Dark" ) || true

theme4="$(jq -r '.["workbench.colorTheme"]' "$settings4" 2>/dev/null || echo '<error>')"
if [[ "$theme4" == "Ocean Green: Dark" ]]; then
  pass "a theme name with a colon is written correctly"
else
  fail "workbench.colorTheme was '$theme4', expected 'Ocean Green: Dark' - a value with a colon likely broke a sed/awk substitution"
fi

# --- Scenario 5: target file doesn't exist -> no-op, nothing created -----

home5="$scratch/home5"
mkdir -p "$home5"
settings5="$scratch/does-not-exist/settings.json"

if ( cd "$home5" && HOME="$home5" merge_theme_into_settings "$settings5" "workbench.colorTheme" "Tokyo Night" ); then
  pass "merge_theme_into_settings exits 0 when the target file doesn't exist"
else
  fail "merge_theme_into_settings exited non-zero when the target file doesn't exist - it should no-op, not error"
fi

if [[ ! -e "$settings5" ]] && [[ ! -d "$scratch/does-not-exist" ]]; then
  pass "no file or directory was created for a target that didn't already exist"
else
  fail "something was created at or around $settings5 even though the target file never existed - this should be a pure no-op"
fi

# --- Scenario 6: invalid JSON even after stripping comments -> untouched -

home6="$scratch/home6"
mkdir -p "$home6"
settings6="$scratch/settings6.json"
printf 'not valid json {{{\n' > "$settings6"
original6="$(cat "$settings6")"

if ( cd "$home6" && HOME="$home6" merge_theme_into_settings "$settings6" "workbench.colorTheme" "Tokyo Night" ); then
  pass "merge_theme_into_settings exits 0 on a file that isn't valid JSON (skips gracefully, doesn't crash)"
else
  fail "merge_theme_into_settings exited non-zero on invalid JSON - it should skip gracefully instead"
fi

after6="$(cat "$settings6" 2>/dev/null || echo '<missing>')"
if [[ "$after6" == "$original6" ]]; then
  pass "a file that isn't valid JSON is left byte-for-byte untouched"
else
  fail "a file that isn't valid JSON was modified - it should have been left exactly as it was"
fi

# --- Scenario 7: install_theme_extension isolates a SUCCESSFUL call ------

home7="$scratch/home7"
mkdir -p "$home7"

code() { echo "code $*" >> "$scratch/code-calls.log"; return 0; }
export -f code

if ( cd "$home7" && HOME="$home7" install_theme_extension "enkia.tokyo-night" ); then
  pass "install_theme_extension returns success when 'code --install-extension' succeeds"
else
  fail "install_theme_extension exited non-zero even though the stubbed 'code' succeeded"
fi

if grep -q -- "--install-extension enkia.tokyo-night" "$scratch/code-calls.log" 2>/dev/null; then
  pass "install_theme_extension actually invoked 'code --install-extension <extension-id>'"
else
  fail "no call to 'code --install-extension enkia.tokyo-night' was recorded - install_theme_extension may not be calling 'code' at all"
fi

# --- Scenario 8: install_theme_extension isolates a FAILING call ---------

home8="$scratch/home8"
mkdir -p "$home8"

code() { echo "code $*" >> "$scratch/code-calls-8.log"; return 1; }
export -f code

if ( cd "$home8" && HOME="$home8" install_theme_extension "enkia.tokyo-night" ); then
  pass "install_theme_extension does not propagate failure when 'code --install-extension' fails - a broken/missing extension can't abort the rest of a theme apply"
else
  fail "install_theme_extension exited non-zero when the stubbed 'code' failed - this failure must be isolated, not allowed to abort the caller"
fi

exit "$failed"
