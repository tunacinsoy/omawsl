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
# than duplicating.
omawsl_save_choice() {
  local key="$1" value="$2"
  local dir; dir="$(omawsl_choices_dir)"
  mkdir -p "$dir"
  local file="$dir/choices.env"
  touch "$file"
  local tmp; tmp="$(mktemp)"
  grep -v "^${key}=" "$file" > "$tmp" 2>/dev/null || true
  printf '%s="%s"\n' "$key" "$value" >> "$tmp"
  mv "$tmp" "$file"
}

# omawsl_load_choice <key>
# Prints the persisted value for key, or an empty string if never set.
omawsl_load_choice() {
  local key="$1"
  local file; file="$(omawsl_choices_dir)/choices.env"
  [[ -f "$file" ]] || { echo ""; return 0; }
  (
    # shellcheck disable=SC1090
    source "$file"
    echo "${!key:-}"
  )
}
