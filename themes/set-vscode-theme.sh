#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Kept apart from SCRIPT_DIR, which scripts sourced after this one reset.
OMAWSL_VSCODE_THEMES_DIR="$SCRIPT_DIR"
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

# omawsl_native_vscode_settings_path <profile>
# Path to VS Code's native Windows-side settings.json under a resolved
# Windows user profile (omawsl_windows_userprofile's output) - the one
# place this path is spelled out, shared by the theme sync below and
# app-vscode.sh's update.mode deploy so the two can't drift apart.
omawsl_native_vscode_settings_path() {
  echo "$1/AppData/Roaming/Code/User/settings.json"
}

# omawsl_json_update_value <settings_file> <key> <jq_filter> [<json>]
# Sets one top-level key of a VS Code/Cursor-shaped settings.json to
# <jq_filter> applied to the key's current value (null when missing), with
# <json> available to the filter as $v - so a caller can merge into an
# object the user also writes to (their own colorCustomizations stay) or
# just replace a value. Works on strict JSON (every omawsl-deployed
# Remote-WSL machine-settings file) and on JSONC with comments (typical of
# a hand-edited native settings.json - design spec "Sync theme to native
# Windows-side VS Code/Cursor" §"The JSONC problem"). No-ops if the file
# doesn't exist yet or jq isn't reachable. Backs up to <settings_file>.bak
# first - unless OMAWSL_JSON_NO_BACKUP=1, for a caller making several edits
# that took one backup before the first - and re-validates its own edit
# before committing - a corrupted settings.json breaks the user's whole
# editor.
#
# JSONC is edited line by line so comments survive: a missing key is
# inserted on one line right after the first '{'; an existing one is
# replaced in place when its value is a string, or an object/array written
# on that one line (how omawsl writes them). A value spread over several
# lines is someone's own hand-written setting and is left alone, with a
# message. New text is spliced in with bash string concatenation and
# printed with awk's `print` (never sub()/gsub() or sed s///), so '&', '\'
# or '/' in a value - "Rosé Pine Dawn", "Ocean Green: Dark" - can't break
# the edit.
omawsl_json_update_value() {
  local settings_file="$1" key="$2" filter="$3" value="${4:-null}"
  [[ -f "$settings_file" ]] || return 0
  command -v jq &>/dev/null || return 0

  if [[ "${OMAWSL_JSON_NO_BACKUP:-}" != 1 ]] && ! cp "$settings_file" "$settings_file.bak"; then
    echo "omawsl: couldn't back up $settings_file - skipping the $key sync." >&2
    echo "See docs/windows-setup.md#vscode-theme for the manual steps." >&2
    return 0
  fi

  # Fast path: strict JSON, no comments - jq edits it directly.
  if jq empty "$settings_file" 2>/dev/null; then
    local tmp
    tmp="$(mktemp)"
    if ! jq --arg key "$key" --argjson v "$value" ".[\$key] |= ($filter)" "$settings_file" > "$tmp" ||
      ! cp "$tmp" "$settings_file"; then
      echo "omawsl: couldn't write to $settings_file - skipping the $key sync." >&2
      echo "See docs/windows-setup.md#vscode-theme for the manual steps." >&2
    fi
    rm -f "$tmp"
    return 0
  fi

  # JSONC: a comment-stripped scratch copy only confirms the file is
  # otherwise valid and tells whether the key exists - the edit below goes
  # to the original, comments and all.
  local stripped
  stripped="$(mktemp)"
  omawsl_strip_jsonc_comments "$settings_file" > "$stripped"
  if ! jq empty "$stripped" 2>/dev/null; then
    echo "omawsl: $settings_file isn't valid JSON - skipping the $key sync." >&2
    echo "See docs/windows-setup.md#vscode-theme for the manual steps." >&2
    rm -f "$stripped"
    return 0
  fi

  local tmp_edited key_re line_no old_line new_line new_value
  tmp_edited="$(mktemp)"
  key_re="${key//./\\.}"
  if jq -e --arg key "$key" 'has($key)' "$stripped" >/dev/null; then
    line_no="$(grep -n "\"$key_re\"" "$settings_file" | head -1 | cut -d: -f1)"
    old_line="$(sed -n "${line_no}p" "$settings_file")"
    local prefix old_value rest
    local key_part="^(.*\"$key_re\"[[:space:]]*:[[:space:]]*)"
    local string_value='("([^"\\]|\\.)*")(.*)$'
    local object_value='([[{].*[]}])([[:space:]]*,?[[:space:]]*)$'
    if [[ "$old_line" =~ $key_part$string_value ]]; then
      prefix="${BASH_REMATCH[1]}" old_value="${BASH_REMATCH[2]}" rest="${BASH_REMATCH[4]}"
    elif [[ "$old_line" =~ $key_part$object_value ]] &&
      jq empty <<< "${BASH_REMATCH[2]}" 2>/dev/null; then
      prefix="${BASH_REMATCH[1]}" old_value="${BASH_REMATCH[2]}" rest="${BASH_REMATCH[3]}"
    else
      echo "omawsl: $key in $settings_file spans several lines - leaving your own setting alone, skipping the $key sync." >&2
      rm -f "$stripped" "$tmp_edited"
      return 0
    fi
    new_value="$(jq -c --argjson v "$value" "$filter" <<< "$old_value")"
    new_line="$prefix$new_value$rest"
    awk -v n="$line_no" -v content="$new_line" 'NR==n { print content; next } { print }' "$settings_file" > "$tmp_edited"
  else
    # Inserts right after the file's first '{'. A '{' inside a comment
    # before the real opening brace would be matched too, and a JSONC file
    # that's only comments ends up with a trailing comma - re-validation
    # below catches both and rolls back.
    local before after
    new_value="$(jq -cn --argjson v "$value" "null | $filter")"
    line_no="$(grep -n '{' "$settings_file" | head -1 | cut -d: -f1)"
    old_line="$(sed -n "${line_no}p" "$settings_file")"
    before="${old_line%%\{*}"
    after="${old_line#*\{}"
    printf -v new_line '%s{\n  "%s": %s,\n%s' "$before" "$key" "$new_value" "$after"
    awk -v n="$line_no" -v content="$new_line" 'NR==n { print content; next } { print }' "$settings_file" > "$tmp_edited"
  fi

  # Re-validate before committing; roll back rather than leave a broken
  # settings.json in place.
  local recheck
  recheck="$(mktemp)"
  omawsl_strip_jsonc_comments "$tmp_edited" > "$recheck"
  if jq empty "$recheck" 2>/dev/null; then
    cp "$tmp_edited" "$settings_file" || {
      echo "omawsl: couldn't write to $settings_file - skipping the $key sync." >&2
      echo "See docs/windows-setup.md#vscode-theme for the manual steps." >&2
    }
  else
    echo "omawsl: the $key sync edit to $settings_file produced invalid JSON - leaving it untouched (backup at $settings_file.bak)." >&2
    echo "See docs/windows-setup.md#vscode-theme for the manual steps." >&2
  fi
  rm -f "$stripped" "$tmp_edited" "$recheck"
}

# omawsl_json_set_string_value <settings_file> <key> <value>
# Sets a single string-valued key (workbench.colorTheme, update.mode) -
# omawsl_json_update_value with the old value ignored.
omawsl_json_set_string_value() {
  omawsl_json_update_value "$1" "$2" '$v' "$(jq -n --arg v "$3" '$v')"
}

# omawsl_vscode_theme_render <palette_json>
# Prints a full VS Code color theme: Omarchy's MIT-licensed template
# (themes/vscode-theme.json.tpl, see themes/LICENSE.omarchy) with every
# {{ slot }} filled from a theme's vscode-palette.json. Each palette holds
# the value for every slot, already resolved: Omarchy's own colors.toml run
# through its omarchy-theme-color, or for the four themes Omarchy doesn't
# have (catppuccin's Macchiato flavor, dracula, one-dark, solarized) a
# colors.toml written from that theme's official colors - always with the
# same background and text color as its Windows Terminal scheme.
omawsl_vscode_theme_render() {
  local palette="$1" theme slot value
  theme="$(cat "$OMAWSL_VSCODE_THEMES_DIR/vscode-theme.json.tpl")" || return 1
  while IFS=$'\t' read -r slot value; do
    theme="${theme//"{{ $slot }}"/$value}"
  done < <(jq -r 'to_entries[] | "\(.key)\t\(.value)"' "$palette")
  printf '%s\n' "$theme"
}

# omawsl_theme_set_vscode_settings <settings_file> <color_theme>
# Thin wrapper around omawsl_json_set_string_value, kept as its own name
# for every existing caller/test - see that function for the actual
# JSONC-safe merge logic.
omawsl_theme_set_vscode_settings() {
  omawsl_json_set_string_value "$1" "workbench.colorTheme" "$2"
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

# omawsl_theme_apply_vscode <theme_dir>
# Gives VS Code and Cursor the theme's colors through their settings alone:
# workbench.colorTheme is set to a theme they ship with (Default Dark
# Modern, or Default Light Modern for a light theme), and the rendered
# theme (omawsl_vscode_theme_render) goes on top as that theme's
# workbench.colorCustomizations, editor.tokenColorCustomizations and
# editor.semanticTokenColorCustomizations. VS Code 1.134 renamed those
# built-in themes' IDs to "Dark Modern" / "Light Modern", and applies a
# scoped block only when it names the active theme's current ID, so the
# block names both: "[Default Dark Modern][Dark Modern]". The old name still
# works for workbench.colorTheme in new versions. Nothing is installed and no
# program runs - omawsl never starts Windows programs (code, cmd.exe) from
# WSL, and themes no longer need a marketplace extension. The colors are
# scoped to that base theme, so the user's own customizations in the same
# settings stay, and switching themes replaces omawsl's block instead of
# piling them up. Written to the Remote-WSL settings files and, when the
# Windows profile resolves, the native ones - creating a native
# settings.json first only for an app that's installed
# (omawsl_theme_ensure_vscode_settings_exists).
omawsl_theme_apply_vscode() {
  local theme_dir="$1" theme base scope
  theme="$(omawsl_vscode_theme_render "$theme_dir/vscode-palette.json")" || return 0
  base="Default Dark Modern" scope="[Default Dark Modern][Dark Modern]"
  if [[ "$(jq -r .type <<< "$theme")" == light ]]; then
    base="Default Light Modern" scope="[Default Light Modern][Light Modern]"
  fi

  local colors token_rules semantic scoped
  colors="$(jq -c .colors <<< "$theme")"
  token_rules="$(jq -c '{textMateRules: .tokenColors}' <<< "$theme")"
  semantic="$(jq -c '{enabled: true, rules: .semanticTokenColors}' <<< "$theme")"
  # Drops every block omawsl may have written before - one-name scopes
  # included - so there's only ever one.
  scoped="(if type == \"object\" then . else {} end)
    | del(.[\"[Default Dark Modern]\"], .[\"[Default Light Modern]\"],
          .[\"[Default Dark Modern][Dark Modern]\"], .[\"[Default Light Modern][Light Modern]\"])
    + {\"$scope\": \$v}"

  local profile
  if profile="$(omawsl_windows_userprofile)"; then
    omawsl_theme_ensure_vscode_settings_exists "$(omawsl_native_vscode_settings_path "$profile")"
    omawsl_theme_ensure_vscode_settings_exists "$profile/AppData/Roaming/Cursor/User/settings.json"
  fi

  # One backup per file, of the settings as they were before this switch -
  # the four edits below don't each overwrite it.
  local file
  while IFS= read -r file; do
    [[ -f "$file" ]] || continue
    if ! cp "$file" "$file.bak"; then
      echo "omawsl: couldn't back up $file - skipping the VS Code theme sync for it." >&2
      echo "See docs/windows-setup.md#vscode-theme for the manual steps." >&2
      continue
    fi
    OMAWSL_JSON_NO_BACKUP=1 omawsl_theme_set_vscode_settings "$file" "$base"
    OMAWSL_JSON_NO_BACKUP=1 omawsl_json_update_value "$file" workbench.colorCustomizations "$scoped" "$colors"
    OMAWSL_JSON_NO_BACKUP=1 omawsl_json_update_value "$file" editor.tokenColorCustomizations "$scoped" "$token_rules"
    OMAWSL_JSON_NO_BACKUP=1 omawsl_json_update_value "$file" editor.semanticTokenColorCustomizations "$scoped" "$semantic"
  done < <(omawsl_theme_vscode_settings_files)
}

# omawsl_theme_vscode_settings_files
# Every VS Code/Cursor settings.json omawsl_theme_apply_vscode writes to -
# the Remote-WSL ones always, the native Windows-side ones only when the
# Windows profile resolves. Quiet about an unresolved profile: callers that
# need the user to know have already looked it up and said so.
omawsl_theme_vscode_settings_files() {
  echo "$HOME/.vscode-server/data/Machine/settings.json"
  echo "$HOME/.cursor-server/data/Machine/settings.json"
  local profile
  if profile="$(omawsl_windows_userprofile 2>/dev/null)"; then
    omawsl_native_vscode_settings_path "$profile"
    echo "$profile/AppData/Roaming/Cursor/User/settings.json"
  fi
}
