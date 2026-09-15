#!/usr/bin/env bash
set -euo pipefail

# Checks practice/01-core-skeleton/lib.sh against the behavior
# install/lib.sh is required to have (docs/curriculum/01-core-skeleton.md,
# section 3). lib.sh is pure/sourceable (no unconditional dispatcher at the
# bottom, unlike e.g. app-gum.sh), so sourcing it directly is safe.
#
# omawsl_save_choice/omawsl_choices_dir touch a real directory - by default,
# $HOME/.local/state/omawsl. To make sure this check never writes into the
# real machine's home directory (even if a learner's implementation
# hardcodes $HOME instead of honoring the OMAWSL_STATE_DIR override), every
# assertion below runs with BOTH HOME and the process's cwd redirected into
# a scratch directory - never the real ones.

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
failed=0

script="$(cd "$(dirname "$0")" && pwd)/lib.sh"

export HOME="$scratch/home"
mkdir -p "$HOME"
cd "$scratch"

# shellcheck disable=SC1090
source "$script"

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; failed=1; }

# --- omawsl_version_ge ---------------------------------------------------

check_version_ge() {
  local version="$1" minimum="$2" expect="$3" desc="$4"
  if omawsl_version_ge "$version" "$minimum" 2>/dev/null; then
    actual=0
  else
    actual=1
  fi
  if [[ "$actual" == "$expect" ]]; then
    pass "omawsl_version_ge $desc"
  else
    fail "omawsl_version_ge $desc: expected exit $expect, got $actual"
  fi
}

check_version_ge "26.04" "24.04" 0 "greater major version"
check_version_ge "24.04" "24.04" 0 "equal version"
check_version_ge "24.10" "24.04" 0 "greater minor, same major"
check_version_ge "22.04" "24.04" 1 "lesser major version"
check_version_ge "24.02" "24.04" 1 "lesser minor, same major"
check_version_ge "24.08" "24.04" 0 "leading-zero minor segment does not misparse as octal"
check_version_ge "24.04" "24.08" 1 "leading-zero minor segment, other direction"

# --- omawsl_list_has ------------------------------------------------------

check_list_has() {
  local list="$1" item="$2" expect="$3" desc="$4"
  if omawsl_list_has "$list" "$item" 2>/dev/null; then
    actual=0
  else
    actual=1
  fi
  if [[ "$actual" == "$expect" ]]; then
    pass "omawsl_list_has $desc"
  else
    fail "omawsl_list_has $desc: expected exit $expect, got $actual"
  fi
}

check_list_has "Go,Python,Rust" "Go" 0 "item present"
check_list_has "Go,Python,Rust" "Java" 1 "item absent"
check_list_has "GoLang,Python" "Go" 1 "does not match as a bare substring"
check_list_has "" "Go" 1 "empty list never matches"

# --- omawsl_is_wsl2_kernel -------------------------------------------------

check_wsl2_kernel() {
  local kernel="$1" expect="$2" desc="$3"
  if omawsl_is_wsl2_kernel "$kernel" 2>/dev/null; then
    actual=0
  else
    actual=1
  fi
  if [[ "$actual" == "$expect" ]]; then
    pass "omawsl_is_wsl2_kernel $desc"
  else
    fail "omawsl_is_wsl2_kernel $desc: expected exit $expect, got $actual"
  fi
}

check_wsl2_kernel "6.18.33.2-microsoft-standard-WSL2" 0 "real WSL2 kernel string matches"
check_wsl2_kernel "4.4.0-19041-Microsoft" 1 "WSL1-style kernel string does not match"
check_wsl2_kernel "5.4.0-91-generic" 1 "bare Linux kernel string does not match"

# --- omawsl_is_wsl2 --------------------------------------------------------
# Not asserted against a hardcoded true/false (this check might not run on
# WSL2 at all) - instead asserts it's wired up to delegate to
# omawsl_is_wsl2_kernel "$(uname -r)" consistently, whatever the real
# kernel here happens to be.

real_kernel="$(uname -r)"
if omawsl_is_wsl2_kernel "$real_kernel" 2>/dev/null; then
  expected_wsl2=0
else
  expected_wsl2=1
fi
if omawsl_is_wsl2 2>/dev/null; then
  actual_wsl2=0
else
  actual_wsl2=1
fi
if [[ "$actual_wsl2" == "$expected_wsl2" ]]; then
  pass "omawsl_is_wsl2 delegates to omawsl_is_wsl2_kernel against the real kernel"
else
  fail "omawsl_is_wsl2 delegates to omawsl_is_wsl2_kernel against the real kernel: expected exit $expected_wsl2, got $actual_wsl2"
fi

# --- omawsl_choices_dir -----------------------------------------------------

unset OMAWSL_STATE_DIR || true
result="$(omawsl_choices_dir 2>/dev/null || echo '<error>')"
if [[ "$result" == "$HOME/.local/state/omawsl" ]]; then
  pass "omawsl_choices_dir defaults to \$HOME/.local/state/omawsl"
else
  fail "omawsl_choices_dir defaults to \$HOME/.local/state/omawsl: got '$result'"
fi

export OMAWSL_STATE_DIR="$scratch/custom-state"
result="$(omawsl_choices_dir 2>/dev/null || echo '<error>')"
if [[ "$result" == "$OMAWSL_STATE_DIR" ]]; then
  pass "omawsl_choices_dir honors an OMAWSL_STATE_DIR override"
else
  fail "omawsl_choices_dir honors an OMAWSL_STATE_DIR override: got '$result'"
fi

# --- omawsl_save_choice / omawsl_load_choice --------------------------------
# All of this runs with OMAWSL_STATE_DIR pointed at a scratch directory, set
# above, so even an implementation that ignores the override and hardcodes
# $HOME still only ever touches the scratch $HOME set at the top of this
# script - never a real home directory.

if omawsl_save_choice OMAWSL_LANGUAGES "Go,Python" 2>/dev/null; then
  pass "omawsl_save_choice runs without error"
else
  fail "omawsl_save_choice runs without error"
fi

result="$(omawsl_load_choice OMAWSL_LANGUAGES 2>/dev/null || echo '<error>')"
if [[ "$result" == "Go,Python" ]]; then
  pass "omawsl_save_choice + omawsl_load_choice round-trips a value"
else
  fail "omawsl_save_choice + omawsl_load_choice round-trips a value: got '$result'"
fi

omawsl_save_choice OMAWSL_LANGUAGES "Go" 2>/dev/null || true
omawsl_save_choice OMAWSL_LANGUAGES "Go,Rust" 2>/dev/null || true
result="$(omawsl_load_choice OMAWSL_LANGUAGES 2>/dev/null || echo '<error>')"
if [[ "$result" == "Go,Rust" ]]; then
  pass "omawsl_save_choice overwrites a prior value for the same key"
else
  fail "omawsl_save_choice overwrites a prior value for the same key: got '$result'"
fi

choices_file="$(omawsl_choices_dir 2>/dev/null || echo '<error>')/choices.env"
if [[ -f "$choices_file" ]]; then
  line_count="$(grep -c '^OMAWSL_LANGUAGES=' "$choices_file" 2>/dev/null || echo 0)"
else
  line_count="<no file>"
fi
if [[ "$line_count" == "1" ]]; then
  pass "omawsl_save_choice leaves exactly one line per key, not a duplicate"
else
  fail "omawsl_save_choice leaves exactly one line per key, not a duplicate: found $line_count line(s) in $choices_file"
fi

omawsl_save_choice OMAWSL_STORAGE "MySQL" 2>/dev/null || true
lang_result="$(omawsl_load_choice OMAWSL_LANGUAGES 2>/dev/null || echo '<error>')"
storage_result="$(omawsl_load_choice OMAWSL_STORAGE 2>/dev/null || echo '<error>')"
if [[ "$lang_result" == "Go,Rust" && "$storage_result" == "MySQL" ]]; then
  pass "two different keys are both loadable independently"
else
  fail "two different keys are both loadable independently: OMAWSL_LANGUAGES='$lang_result', OMAWSL_STORAGE='$storage_result'"
fi

result="$(omawsl_load_choice OMAWSL_NEVER_SET 2>/dev/null || echo '<error>')"
if [[ "$result" == "" ]]; then
  pass "omawsl_load_choice on an unset key returns an empty string"
else
  fail "omawsl_load_choice on an unset key returns an empty string: got '$result'"
fi

# The dangerous part: a value containing double quotes, backslashes, a
# $(...) command substitution, and a backtick command substitution, all of
# which must round-trip byte-for-byte AND must never actually execute -
# proof that omawsl_load_choice reads the file as data (grep + string
# editing) rather than as code (source/eval).
danger_value='O"Brien $(touch '"$scratch"'/PWNED_MARKER) `touch '"$scratch"'/PWNED_MARKER2` \done'
omawsl_save_choice OMAWSL_DANGER_TEST "$danger_value" 2>/dev/null || true
loaded="$(omawsl_load_choice OMAWSL_DANGER_TEST 2>/dev/null || echo '<error>')"

if [[ "$loaded" == "$danger_value" ]]; then
  pass "a value with quotes/backslashes/command-substitution syntax round-trips exactly"
else
  fail "a value with quotes/backslashes/command-substitution syntax round-trips exactly: got '$loaded', expected '$danger_value'"
fi

if [[ ! -e "$scratch/PWNED_MARKER" && ! -e "$scratch/PWNED_MARKER2" ]]; then
  pass "the dangerous value was never executed as code"
else
  fail "the dangerous value WAS executed - omawsl_save_choice/omawsl_load_choice must never source or eval a persisted value"
fi

exit "$failed"
