#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../install/lib.sh
source "$SCRIPT_DIR/../install/lib.sh"

# omawsl_strip_jsonc_comments <file>
# Prints a best-effort comment-stripped copy of <file> to stdout, for
# structural validation only - the result is never written back to any
# real file, so hand-written comments in the actual settings.json are
# never touched or lost. Strips '//' line comments (but not when the
# '//' is immediately preceded by ':', so "http://..." inside a string
# value survives) and single-line '/* ... */' block comments. Known
# limitation: doesn't handle multi-line block comments, or a '//'/'/*'
# elsewhere inside a string value - both just make the stripped copy
# fail to parse as JSON, which makes the caller skip gracefully rather
# than risk corrupting anything real.
omawsl_strip_jsonc_comments() {
  sed -E 's#/\*.*\*/##g; s#(^|[^:])//.*$#\1#' "$1"
}

# omawsl_theme_set_vscode_settings <settings_file> <color_theme>
# Merges "workbench.colorTheme" into an existing VS Code/Cursor-shaped
# settings.json, whether it's strict JSON (every omawsl-deployed
# Remote-WSL machine-settings file) or JSONC with comments (typical of
# a hand-edited native settings.json - design spec "Sync theme to
# native Windows-side VS Code/Cursor" §"The JSONC problem"). No-ops if
# the settings file doesn't exist yet or if jq isn't reachable. Always
# backs up to <settings_file>.bak first and re-validates its own edit
# before committing - a corrupted settings.json breaks the user's whole
# editor, not just the theme.
omawsl_theme_set_vscode_settings() {
  local settings_file="$1" color_theme="$2"
  [[ -f "$settings_file" ]] || return 0
  command -v jq &>/dev/null || return 0

  cp "$settings_file" "$settings_file.bak" || {
    echo "omawsl: couldn't back up $settings_file - skipping the color sync." >&2
    echo "See docs/windows-setup.md#vscode-theme for the manual steps." >&2
    return 0
  }

  # Fast path: strict JSON, no comments - merge directly with jq.
  if jq empty "$settings_file" 2>/dev/null; then
    local tmp
    tmp="$(mktemp)"
    jq --arg theme "$color_theme" '.["workbench.colorTheme"] = $theme' "$settings_file" > "$tmp"
    cp "$tmp" "$settings_file" || {
      echo "omawsl: couldn't write to $settings_file - skipping the color sync." >&2
      echo "See docs/windows-setup.md#vscode-theme for the manual steps." >&2
      rm -f "$tmp"
      return 0
    }
    rm -f "$tmp"
    return 0
  fi

  # JSONC fallback: jq couldn't parse it directly (comments, most
  # likely). Strip comments into a throwaway scratch copy purely to (a)
  # confirm the file is otherwise structurally valid and (b) check
  # whether the key already exists - the real edit below never touches
  # the scratch copy, only the original comment-containing file.
  local stripped
  stripped="$(mktemp)"
  omawsl_strip_jsonc_comments "$settings_file" > "$stripped"

  if ! jq empty "$stripped" 2>/dev/null; then
    echo "omawsl: $settings_file isn't valid JSON - skipping the color sync."
    echo "See docs/windows-setup.md#vscode-theme for the manual steps."
    rm -f "$stripped"
    return 0
  fi

  local tmp_edited
  tmp_edited="$(mktemp)"
  if jq -e 'has("workbench.colorTheme")' "$stripped" >/dev/null; then
    sed -E "s/(\"workbench\.colorTheme\"[[:space:]]*:[[:space:]]*)\"[^\"]*\"/\1\"$color_theme\"/" "$settings_file" > "$tmp_edited"
  else
    awk -v val="$color_theme" '
      !done && /\{/ {
        sub(/\{/, "{\n  \"workbench.colorTheme\": \"" val "\",")
        done = 1
      }
      { print }
    ' "$settings_file" > "$tmp_edited"
  fi

  # Re-validate the result before committing - if our own edit produced
  # something that no longer parses (e.g. a literal '{' inside a
  # comment threw off the insert point), roll back rather than leave a
  # broken settings.json in place.
  local recheck
  recheck="$(mktemp)"
  omawsl_strip_jsonc_comments "$tmp_edited" > "$recheck"
  if jq empty "$recheck" 2>/dev/null; then
    cp "$tmp_edited" "$settings_file" || {
      echo "omawsl: couldn't write to $settings_file - skipping the color sync." >&2
      echo "See docs/windows-setup.md#vscode-theme for the manual steps." >&2
      rm -f "$stripped" "$tmp_edited" "$recheck"
      return 0
    }
  else
    echo "omawsl: the color sync edit to $settings_file produced invalid JSON - leaving it untouched (backup at $settings_file.bak)." >&2
    echo "See docs/windows-setup.md#vscode-theme for the manual steps." >&2
  fi

  rm -f "$stripped" "$tmp_edited" "$recheck"
}

# omawsl_theme_apply_vscode <color_theme> <extension_id>
# Applies the theme to VS Code's and Cursor's Remote-WSL settings.json
# (whichever exist) and, if a Windows profile can be resolved via
# omawsl_windows_userprofile, to their native Windows-side
# settings.json too (design spec "Sync theme to native Windows-side VS
# Code/Cursor" - Cursor reads the same workbench.colorTheme key and
# shares this same step). Silently skips the native sync if the
# profile can't be resolved (e.g. not real WSL2) - the Remote-WSL sync
# and extension install below are unaffected either way. Installs the
# VS Code extension via `code --install-extension` only when `code` is
# reachable - matches app-vscode.sh's own detect-and-defer shape
# (Phase 4). Deliberately does NOT attempt `cursor --install-extension`,
# same reasoning as app-cursor.sh (Phase 4): Cursor has its own
# extension distribution and commonly blocks Microsoft-published
# extensions from its marketplace, so this only touches what's clearly
# specified (shared settings keys).
omawsl_theme_apply_vscode() {
  local color_theme="$1" extension_id="$2"

  omawsl_theme_set_vscode_settings "$HOME/.vscode-server/data/Machine/settings.json" "$color_theme"
  omawsl_theme_set_vscode_settings "$HOME/.cursor-server/data/Machine/settings.json" "$color_theme"

  local profile
  if profile="$(omawsl_windows_userprofile)"; then
    omawsl_theme_set_vscode_settings "$profile/AppData/Roaming/Code/User/settings.json" "$color_theme"
    omawsl_theme_set_vscode_settings "$profile/AppData/Roaming/Cursor/User/settings.json" "$color_theme"
  fi

  if omawsl_code_reachable; then
    # NODE_NO_WARNINGS=1: VS Code's `code` CLI is itself a Node.js binary
    # and emits a `[DEP0169] DeprecationWarning: url.parse()...` to
    # stderr on every fresh extension install - confirmed Microsoft's own
    # tooling noise (reproduced in isolation, unrelated to omawsl), but
    # real, alarming-looking, and repeated on every `bin/omawsl theme`
    # call. This is the standard Node.js env var for suppressing runtime
    # deprecation warnings without touching stderr for genuine errors.
    NODE_NO_WARNINGS=1 code --install-extension "$extension_id" >/dev/null
  fi
}
