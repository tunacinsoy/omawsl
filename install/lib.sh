#!/usr/bin/env bash
# Shared helpers sourced by install.sh and every install/terminal/*.sh script.
# Kept dependency-free (pure bash) since these run before anything else has
# been installed.

# omawsl_version_ge <version> <minimum>
# Compares two "MAJOR.MINOR" version strings using pure bash arithmetic - no
# `bc` dependency, since bc is not guaranteed present on a fresh image and
# this runs before any apt install has happened (see check-version.sh).
omawsl_version_ge() {
  local version="$1" minimum="$2"
  local v_major="${version%%.*}" m_major="${minimum%%.*}"
  local v_minor="${version#*.}" m_minor="${minimum#*.}"
  v_minor="${v_minor%%.*}" m_minor="${m_minor%%.*}"
  if (( 10#$v_major > 10#$m_major )); then
    return 0
  elif (( 10#$v_major < 10#$m_major )); then
    return 1
  else
    (( 10#$v_minor >= 10#$m_minor ))
  fi
}

# omawsl_list_has <comma_delimited_list> <item>
# Robust membership check on a comma-delimited string. Wraps both sides in
# delimiters and matches the whole token, rather than a bare substring check
# (which would misfire if one option's name is a substring of another).
omawsl_list_has() {
  local list="$1" item="$2"
  [[ ",$list," == *",$item,"* ]]
}

# omawsl_is_wsl2_kernel <kernel_release_string>
# Pure string-matching logic, separated from the real `uname -r` call so it's
# unit-testable with fixture strings. Verified against a real WSL2 Ubuntu
# 26.04 instance: `uname -r` reports "6.18.33.2-microsoft-standard-WSL2".
omawsl_is_wsl2_kernel() {
  local kernel="$1"
  [[ "$kernel" == *microsoft-standard-WSL2* ]]
}

# omawsl_is_wsl2
# Returns 0 if running inside WSL2 specifically (not WSL1, not bare Linux).
omawsl_is_wsl2() {
  omawsl_is_wsl2_kernel "$(uname -r)"
}

# omawsl_choices_dir
# Directory holding persisted first-run choices and version state.
# Overridable via OMAWSL_STATE_DIR for testing.
omawsl_choices_dir() {
  echo "${OMAWSL_STATE_DIR:-$HOME/.local/state/omawsl}"
}

# omawsl_save_choice <key> <value>
# Persists one KEY="value" line to choices.env, replacing any prior line for
# that key. Idempotent: calling it again with the same key overwrites rather
# than duplicating. Escapes backslashes and double-quotes in the value so a
# name/choice containing either round-trips correctly (backslash first, then
# quote, so the escaping is reversible on read).
omawsl_save_choice() {
  local key="$1" value="$2"
  local dir; dir="$(omawsl_choices_dir)"
  mkdir -p "$dir"
  local file="$dir/choices.env"
  touch "$file"
  local tmp; tmp="$(mktemp)"
  grep -v "^${key}=" "$file" > "$tmp" 2>/dev/null || true
  local escaped="${value//\\/\\\\}"
  escaped="${escaped//\"/\\\"}"
  printf '%s="%s"\n' "$key" "$escaped" >> "$tmp"
  mv "$tmp" "$file"
}

# omawsl_load_choice <key>
# Prints the persisted value for key, or an empty string if never set.
# Deliberately does NOT `source` choices.env: that would execute the file's
# content as shell code, so a persisted value containing `$`, backticks, or
# `"` (e.g. from a user's own name/email, via identification.sh) could
# inject arbitrary commands on read. Extracts the value with grep + pure
# string manipulation instead - never eval'd, never sourced - and reverses
# the escaping omawsl_save_choice applied (quote-escape first, then
# backslash, the opposite order from encoding).
omawsl_load_choice() {
  local key="$1"
  local file; file="$(omawsl_choices_dir)/choices.env"
  [[ -f "$file" ]] || { echo ""; return 0; }
  local line
  line="$(grep "^${key}=" "$file" | tail -n1)"
  [[ -z "$line" ]] && { echo ""; return 0; }
  line="${line#*=\"}"
  line="${line%\"}"
  line="${line//\\\"/\"}"
  line="${line//\\\\/\\}"
  echo "$line"
}

# omawsl_docker_reachable
# True if `docker` is on PATH AND actually functional. Shared by
# windows-prereq-checklist.sh (deciding whether Docker Desktop needs
# flagging as a pending Windows-side prerequisite) and docker.sh's own
# Desktop-mode detect-and-defer check (design spec §6, §9).
#
# Deliberately checks more than PATH presence: Docker Desktop drops a
# 'docker' shim onto every WSL distro's PATH, even ones without WSL
# integration enabled for that distro - it just prints a friendly "activate
# WSL integration" nudge and exits non-zero rather than a real command not
# found. A bare `command -v docker` check can't tell that apart from a
# genuinely working docker - confirmed as a real false positive on a real
# machine, which let later steps call `sudo docker ...` directly and hit a
# raw "command not found" instead of omawsl's own graceful deferral message.
omawsl_docker_reachable() {
  command -v docker &>/dev/null && docker info &>/dev/null
}

# omawsl_code_reachable
# True if VS Code's `code` CLI is reachable (via Win32 interop once VS
# Code is installed on Windows). Shared by windows-prereq-checklist.sh
# and app-vscode.sh's own detect-and-defer check (design spec §6, §10).
omawsl_code_reachable() {
  command -v code &>/dev/null
}

# omawsl_cursor_reachable
# Same shape as omawsl_code_reachable, for Cursor's `cursor` CLI.
omawsl_cursor_reachable() {
  command -v cursor &>/dev/null
}

# omawsl_windows_userprofile
# Resolves the Windows user's profile directory as a WSL path
# (e.g. /mnt/c/Users/<name>) via cmd.exe + wslpath, rather than
# assuming the Windows username matches $USER - design spec §11 flags
# this as a real, common mismatch. Prints nothing and returns 1 if
# cmd.exe/wslpath aren't reachable (e.g. outside real WSL2, as in the
# bats suite unless stubbed) or the lookup comes back empty.
omawsl_windows_userprofile() {
  command -v cmd.exe &>/dev/null || return 1
  command -v wslpath &>/dev/null || return 1
  local win_path
  win_path="$(cmd.exe /c "echo %USERPROFILE%" 2>/dev/null | tr -d '\r\n')"
  [[ -n "$win_path" ]] || return 1
  wslpath -u "$win_path"
}

# omawsl_write_version_state <root_dir>
# Copies <root_dir>/version into the persisted state dir (design spec §8:
# a fresh install already reflects current desired state, so the first
# `bin/omawsl migrate` doesn't treat every historical migration as
# pending). Moved here from install.sh (Phase 1) so bin/omawsl-sub/migrate.sh
# (Phase 7) can reuse it without duplicating - takes root_dir as an
# explicit argument rather than reading a global, so both callers stay
# self-contained and testable in isolation.
omawsl_write_version_state() {
  local root_dir="$1"
  local dir; dir="$(omawsl_choices_dir)"
  mkdir -p "$dir"
  cp "$root_dir/version" "$dir/version"
}

# omawsl_merge_csv <a> <b>
# Union of two comma-delimited lists, de-duplicated, order-preserving
# (a's items first, then any of b's items not already in a) - via
# omawsl_list_has, so this respects the same whole-token matching every
# other membership check in this repo uses.
omawsl_merge_csv() {
  local a="$1" b="$2"
  local result="$a"
  local item
  IFS=',' read -ra items <<< "$b"
  for item in "${items[@]}"; do
    [[ -z "$item" ]] && continue
    if ! omawsl_list_has "$result" "$item"; then
      result="${result:+$result,}$item"
    fi
  done
  echo "$result"
}

# omawsl_remove_from_csv <csv> <item>
# Inverse of omawsl_merge_csv: removes one item from a comma-delimited
# list (whole-token match, via omawsl_list_has's own convention - not a
# bare substring), order-preserving for whatever remains. No-ops cleanly
# if the item isn't present.
omawsl_remove_from_csv() {
  local csv="$1" item="$2"
  local result="" tok
  IFS=',' read -ra items <<< "$csv"
  for tok in "${items[@]}"; do
    [[ -z "$tok" ]] && continue
    [[ "$tok" == "$item" ]] && continue
    result="${result:+$result,}$tok"
  done
  echo "$result"
}
