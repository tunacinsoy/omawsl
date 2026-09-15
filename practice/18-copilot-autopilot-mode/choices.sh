#!/usr/bin/env bash
# Given — you do not need to change this file.
#
# A trimmed copy of install/lib.sh's persisted-choice helpers (built in an
# earlier phase of this curriculum). This lesson is about the opt-in
# prompt/alias/uninstall pattern built on top of these, not about
# re-deriving KEY="value" escaping again, so they're supplied as-is.
#
# omawsl_choices_dir
# Prints the directory choices.env lives in. Honors OMAWSL_STATE_DIR (how
# check.sh keeps this off your real $HOME) and otherwise defaults to
# $HOME/.local/state/omawsl.
omawsl_choices_dir() {
  echo "${OMAWSL_STATE_DIR:-$HOME/.local/state/omawsl}"
}

# omawsl_save_choice <key> <value>
# Persists one KEY="value" line to choices.env, replacing any prior line
# for that key. Idempotent: saving the same key twice overwrites rather
# than duplicating.
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
