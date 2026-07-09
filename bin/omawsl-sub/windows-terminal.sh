#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OMAWSL_ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../../install/lib.sh
source "$OMAWSL_ROOT_DIR/install/lib.sh"

# omawsl_windows_terminal_settings_path
# Locates Windows Terminal's real settings.json under the resolved
# Windows user profile. Checks the Microsoft Store package path first
# (the install method docs/windows-setup.md recommends, design spec
# §13), then the unpackaged/portable install path. Prints nothing and
# returns 1 if neither exists yet, or if the profile itself can't be
# resolved.
omawsl_windows_terminal_settings_path() {
  local profile
  profile="$(omawsl_windows_userprofile)" || return 1

  local store_path="$profile/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json"
  local unpackaged_path="$profile/AppData/Local/Microsoft/Windows Terminal/settings.json"

  if [[ -f "$store_path" ]]; then
    echo "$store_path"
  elif [[ -f "$unpackaged_path" ]]; then
    echo "$unpackaged_path"
  else
    return 1
  fi
}

# omawsl_theme_apply_windows_terminal <scheme_file>
# Merges one windows-terminal-scheme.json fragment into Windows
# Terminal's settings.json `schemes` array (replacing any prior entry
# of the same name) and sets it as the default profile's colorScheme -
# design spec §11's one exception to "no automatic Windows-side edits"
# (§2): a local JSON edit to an already-installed app, no network call,
# no admin rights. Always backs up first (settings.json.bak) since a
# corrupted settings.json breaks the user's whole terminal, not just
# the theme. Prefers jq over sed because `schemes` is a nested array,
# not a single-line key. Skips gracefully (prints a
# docs/windows-setup.md pointer, returns 0) if jq or Windows Terminal's
# settings.json can't be found - never fails the rest of
# `bin/omawsl theme`. Targets `profiles.defaults.colorScheme` (applies
# to every profile unless a specific one overrides it) rather than
# hunting for "the" WSL profile object by name/source/GUID, which is
# more fragile across install configurations.
omawsl_theme_apply_windows_terminal() {
  local scheme_file="$1"

  if ! command -v jq &>/dev/null; then
    echo "omawsl: 'jq' isn't available - skipping the Windows Terminal color sync."
    echo "See docs/windows-setup.md#windows-terminal-theme for the manual steps."
    return 0
  fi

  local settings_file
  if ! settings_file="$(omawsl_windows_terminal_settings_path)"; then
    echo "omawsl: couldn't find Windows Terminal's settings.json - skipping the Windows Terminal color sync."
    echo "See docs/windows-setup.md#windows-terminal-theme for the manual steps."
    return 0
  fi

  cp "$settings_file" "$settings_file.bak"

  local tmp
  tmp="$(mktemp)"
  jq --argjson scheme "$(cat "$scheme_file")" \
    '.schemes = ((.schemes // []) | map(select(.name != $scheme.name))) + [$scheme]
     | .profiles.defaults.colorScheme = $scheme.name' \
    "$settings_file" > "$tmp"

  if ! jq empty "$tmp" 2>/dev/null; then
    echo "omawsl: the Windows Terminal settings edit produced invalid JSON - leaving settings.json untouched (backup at $settings_file.bak)." >&2
    rm -f "$tmp"
    return 1
  fi

  mv "$tmp" "$settings_file"
}
