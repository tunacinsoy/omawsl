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
#
# <color_theme> is NOT letters-and-spaces-only - real values include
# "Ocean Green: Dark", "Monokai Pro (Filter Ristretto)", "Rosé Pine
# Dawn" (see themes/*/vscode.sh). The JSONC-fallback path below never
# interpolates it into a sed s/// or awk sub() replacement (both treat
# '&' and '\' specially, and a stray '/' would break a sed script that
# uses '/' as its delimiter, which could abort the whole `bin/omawsl
# theme` run under set -e) - it's spliced in via plain bash string
# concatenation instead, then reprinted with awk's `print` (never
# `sub()`/`gsub()`), which has no replacement-text metacharacter
# handling at all.
omawsl_theme_set_vscode_settings() {
  local settings_file="$1" color_theme="$2"
  [[ -f "$settings_file" ]] || return 0
  command -v jq &>/dev/null || return 0

  cp "$settings_file" "$settings_file.bak" || {
    echo "omawsl: couldn't back up $settings_file - skipping the color sync." >&2
    echo "See docs/windows-setup.md#vscode-theme for the manual steps." >&2
    return 0
  }

  # Fast path: strict JSON, no comments - merge directly with jq. jq's
  # --arg safely handles any theme name, no escaping concerns here.
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
    echo "omawsl: $settings_file isn't valid JSON - skipping the color sync." >&2
    echo "See docs/windows-setup.md#vscode-theme for the manual steps." >&2
    rm -f "$stripped"
    return 0
  fi

  local tmp_edited
  tmp_edited="$(mktemp)"
  if jq -e 'has("workbench.colorTheme")' "$stripped" >/dev/null; then
    local line_no old_line new_line
    line_no="$(grep -n '"workbench\.colorTheme"' "$settings_file" | head -1 | cut -d: -f1)"
    old_line="$(sed -n "${line_no}p" "$settings_file")"
    if [[ "$old_line" =~ ^(.*\"workbench\.colorTheme\"[[:space:]]*:[[:space:]]*)\"[^\"]*\"(.*)$ ]]; then
      printf -v new_line '%s"%s"%s' "${BASH_REMATCH[1]}" "$color_theme" "${BASH_REMATCH[2]}"
      awk -v n="$line_no" -v content="$new_line" 'NR==n { print content; next } { print }' "$settings_file" > "$tmp_edited"
    else
      cp "$settings_file" "$tmp_edited"
    fi
  else
    # Inserts right after the file's first '{' (design spec: this is
    # also the documented insert-point risk the rollback test below
    # exercises - a '{' inside a comment before the real opening brace
    # would be matched here too, and re-validation below catches it).
    # If the object has no other members after the inserted key (a
    # JSONC file that's only comments), the trailing comma this leaves
    # makes the result invalid JSON too - also caught by re-validation
    # below, same graceful-skip outcome.
    local line_no old_line before after new_content
    line_no="$(grep -n '{' "$settings_file" | head -1 | cut -d: -f1)"
    old_line="$(sed -n "${line_no}p" "$settings_file")"
    before="${old_line%%\{*}"
    after="${old_line#*\{}"
    printf -v new_content '%s{\n  "workbench.colorTheme": "%s",\n%s' "$before" "$color_theme" "$after"
    awk -v n="$line_no" -v content="$new_content" 'NR==n { print content; next } { print }' "$settings_file" > "$tmp_edited"
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

# omawsl_theme_ensure_vscode_settings_exists <settings_file>
# Creates an empty `{}` settings.json at <settings_file> if it doesn't
# exist yet, but only when the app's own top-level data directory
# (the grandparent of <settings_file> - e.g. .../Code, the parent of
# .../Code/User/settings.json) already exists - that directory is only
# ever created by the app itself, so its presence is a real signal
# VS Code/Cursor is actually installed (and has run at least once),
# without requiring a separate "is this app installed" check. Real-world
# gap this closes: a user can have VS Code installed and used for
# months (real cache/history/logs) while never once opening Settings
# UI/JSON, so no settings.json exists yet for omawsl_theme_set_vscode_settings's
# "only edit an existing file" rule to find - confirmed live, `bin/omawsl
# theme` silently did nothing to the native app on exactly this kind of
# machine. Never creates anything for an app that isn't installed at
# all (data dir absent), matching the "no automatic Windows-side
# installs" spirit - this only ever populates config for software
# that's already there. Same shape as install/terminal/app-vscode.sh's
# omawsl_install_vscode_settings deploying the Remote-WSL machine
# settings file ahead of time ("inert until VS Code exists... applies
# automatically once it does"), mirrored here for the native side.
omawsl_theme_ensure_vscode_settings_exists() {
  local settings_file="$1"
  [[ -f "$settings_file" ]] && return 0
  local app_dir
  app_dir="$(dirname "$(dirname "$settings_file")")"
  [[ -d "$app_dir" ]] || return 0
  mkdir -p "$(dirname "$settings_file")"
  echo '{}' > "$settings_file"
}

# omawsl_theme_apply_vscode <color_theme> <extension_id>
# Applies the theme to VS Code's and Cursor's Remote-WSL settings.json
# (whichever exist) and, if a Windows profile can be resolved via
# omawsl_windows_userprofile, to their native Windows-side
# settings.json too (design spec "Sync theme to native Windows-side VS
# Code/Cursor" - Cursor reads the same workbench.colorTheme key and
# shares this same step) - creating a minimal settings.json first via
# omawsl_theme_ensure_vscode_settings_exists if the app is installed
# but has never had one (see that function's own comment). Silently
# skips the native sync if the profile can't be resolved (e.g. not
# real WSL2) - the Remote-WSL sync and extension install below are
# unaffected either way. Installs the VS Code extension via `code
# --install-extension` only when `code` is reachable - matches
# app-vscode.sh's own detect-and-defer shape (Phase 4). Deliberately
# does NOT attempt `cursor --install-extension`, same reasoning as
# app-cursor.sh (Phase 4): Cursor has its own extension distribution
# and commonly blocks Microsoft-published extensions from its
# marketplace, so this only touches what's clearly specified (shared
# settings keys).
omawsl_theme_apply_vscode() {
  local color_theme="$1" extension_id="$2"

  omawsl_theme_set_vscode_settings "$HOME/.vscode-server/data/Machine/settings.json" "$color_theme"
  omawsl_theme_set_vscode_settings "$HOME/.cursor-server/data/Machine/settings.json" "$color_theme"

  local profile
  if profile="$(omawsl_windows_userprofile)"; then
    local code_settings="$profile/AppData/Roaming/Code/User/settings.json"
    local cursor_settings="$profile/AppData/Roaming/Cursor/User/settings.json"
    omawsl_theme_ensure_vscode_settings_exists "$code_settings"
    omawsl_theme_ensure_vscode_settings_exists "$cursor_settings"
    omawsl_theme_set_vscode_settings "$code_settings" "$color_theme"
    omawsl_theme_set_vscode_settings "$cursor_settings" "$color_theme"
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
