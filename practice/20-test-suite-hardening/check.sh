#!/usr/bin/env bash
set -euo pipefail

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
failed=0

source "$(dirname "$0")/lib.sh"

# --- omawsl_zoxide_doctor_should_suppress -------------------------------
# Pure decision logic: given "is starship present" as an already-resolved
# fact, decide whether zoxide's own doctor self-check should be suppressed.
# Must exit 0 (true) only when told starship IS present, and exit 1 (false)
# for every other input - the original overly-broad fix suppressed
# unconditionally, which is exactly the bug this checks for.

if omawsl_zoxide_doctor_should_suppress "1"; then
  echo "PASS: omawsl_zoxide_doctor_should_suppress 1 (starship present) suppresses"
else
  echo "FAIL: omawsl_zoxide_doctor_should_suppress 1 (starship present) did not suppress, expected it to"
  failed=1
fi

if omawsl_zoxide_doctor_should_suppress "0"; then
  echo "FAIL: omawsl_zoxide_doctor_should_suppress 0 (starship absent) suppressed - this is the too-broad bug the real fix corrected, a zoxide-only host should keep its real diagnostic"
  failed=1
else
  echo "PASS: omawsl_zoxide_doctor_should_suppress 0 (starship absent) does not suppress"
fi

if omawsl_zoxide_doctor_should_suppress ""; then
  echo "FAIL: omawsl_zoxide_doctor_should_suppress '' (no signal at all) suppressed, expected it not to"
  failed=1
else
  echo "PASS: omawsl_zoxide_doctor_should_suppress '' (no signal at all) does not suppress"
fi

if omawsl_zoxide_doctor_should_suppress "yes"; then
  echo "FAIL: omawsl_zoxide_doctor_should_suppress 'yes' (not the exact '1' sentinel) suppressed, expected only the literal '1' to trigger suppression"
  failed=1
else
  echo "PASS: omawsl_zoxide_doctor_should_suppress 'yes' does not suppress"
fi

# --- omawsl_scoped_mktemp_dir -------------------------------------------
# Must create and print a NEW directory nested under the given base_dir,
# never anywhere else (e.g. never falling back to the system temp dir the
# way the original leaking stub_init/gum_stub_init/stub_hide_command did).

base_dir="$scratch/base"
mkdir -p "$base_dir"

dir1="$(omawsl_scoped_mktemp_dir "$base_dir" "stub_log" || echo '<error>')"

if [[ -n "$dir1" && -d "$dir1" ]]; then
  echo "PASS: omawsl_scoped_mktemp_dir created a directory and printed its path"
else
  echo "FAIL: omawsl_scoped_mktemp_dir '$base_dir' 'stub_log' did not create/print a real directory (got '$dir1')"
  failed=1
fi

if [[ "$dir1" == "$base_dir"/* ]]; then
  echo "PASS: created directory is nested under the given base_dir, not a shared/system tmp"
else
  echo "FAIL: created directory '$dir1' is not nested under base_dir '$base_dir' - this is the exact leak the real fix corrected (bare mktemp landing in system /tmp)"
  failed=1
fi

if [[ "$(basename "$dir1")" == *"stub_log"* ]]; then
  echo "PASS: created directory's name includes the given label"
else
  echo "FAIL: created directory '$dir1' does not include the label 'stub_log' in its name"
  failed=1
fi

dir2="$(omawsl_scoped_mktemp_dir "$base_dir" "stub_log" || echo '<error>')"

if [[ -n "$dir2" && "$dir2" != "$dir1" ]]; then
  echo "PASS: a second call with the same base_dir/label returns a different, unique path"
else
  echo "FAIL: a second call returned '$dir2', expected a different path from the first call's '$dir1' (mktemp -d must always produce a unique name)"
  failed=1
fi

if [[ "$dir2" == "$base_dir"/* ]]; then
  echo "PASS: the second created directory is also nested under base_dir"
else
  echo "FAIL: second created directory '$dir2' is not nested under base_dir '$base_dir'"
  failed=1
fi

exit "$failed"
