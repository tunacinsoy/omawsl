#!/usr/bin/env bash
set -euo pipefail

# Behavioral check for practice/08-self-update-mechanism/orphan-tools.sh.
#
# Strategy B (per docs/curriculum/08-self-update-mechanism.md's Exercise):
# the real implementation makes network calls (curl to GitHub's API, `mise
# exec node@lts -- npm view` to the npm registry). Neither is confined to
# $HOME, so a HOME-override alone would provide zero containment - every
# such command is stubbed out for the whole run instead (Technique 2).
# Nothing in this check ever makes a real network request.

failed=0
script="$(cd "$(dirname "$0")" && pwd)/orphan-tools.sh"

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; failed=1; }

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

# --- stub the network-facing commands -----------------------------------
# Both curl and mise are redefined as plain shell functions for the
# lifetime of this check. Since orphan-tools.sh is sourced directly into
# this same process (never invoked as a separate `bash script` child), a
# plain function definition already shadows the real command for every
# caller in this process - including background jobs started with `&`,
# which are subshells of this same process and inherit its function
# table automatically. `export -f` is added anyway, matching the
# documented technique, in case any implementation shells out through an
# extra layer.
curl() { :; }
export -f curl
mise() { :; }
export -f mise

source "$script"

# =========================================================================
# Registry
# =========================================================================

result="$(omawsl_orphan_tool_slugs 2>/dev/null || echo '<error>')"
count="$(printf '%s\n' "$result" | grep -c . || true)"
if [[ "$result" == *"zellij"* && "$result" == *"lazydocker"* && "$result" == *"opencode"* \
   && "$result" == *"claude"* && "$result" == *"codex"* && "$result" == *"gemini"* \
   && "$result" == *"gh-copilot"* && "$count" -eq 7 ]]; then
  pass "omawsl_orphan_tool_slugs lists all 7 orphan tools, one per line"
else
  fail "omawsl_orphan_tool_slugs did not print exactly the 7 expected slugs, one per line (got: $result)"
fi

result="$(omawsl_orphan_tool_label zellij 2>/dev/null || echo '<error>')"
if [[ -n "$result" && "$result" != "<error>" ]]; then
  pass "omawsl_orphan_tool_label zellij returned a label ('$result')"
else
  fail "omawsl_orphan_tool_label zellij did not return a label"
fi

if omawsl_orphan_tool_label nonsense-tool &>/dev/null; then
  fail "omawsl_orphan_tool_label nonsense-tool should have failed for an unrecognized slug"
else
  pass "omawsl_orphan_tool_label nonsense-tool correctly fails for an unrecognized slug"
fi

fakebin="$scratch/fakebin"
mkdir -p "$fakebin"
printf '#!/usr/bin/env bash\ntrue\n' > "$fakebin/zellij"
chmod +x "$fakebin/zellij"

if PATH="$fakebin:$PATH" omawsl_orphan_tool_installed zellij; then
  pass "omawsl_orphan_tool_installed zellij succeeds when zellij is on PATH"
else
  fail "omawsl_orphan_tool_installed zellij should succeed when zellij is on PATH"
fi

if PATH="/nonexistent-empty-dir" omawsl_orphan_tool_installed zellij 2>/dev/null; then
  fail "omawsl_orphan_tool_installed zellij should fail when zellij is not on PATH"
else
  pass "omawsl_orphan_tool_installed zellij correctly fails when zellij is not on PATH"
fi

gh() { echo "gh-copilot	1.2.3	github/gh-copilot"; }
export -f gh
if omawsl_orphan_tool_installed gh-copilot; then
  pass "omawsl_orphan_tool_installed gh-copilot succeeds when 'gh extension list' lists it"
else
  fail "omawsl_orphan_tool_installed gh-copilot should succeed when 'gh extension list' lists github/gh-copilot"
fi
gh() { echo "some-other-extension	1.0.0	someone/other"; }
export -f gh
if omawsl_orphan_tool_installed gh-copilot 2>/dev/null; then
  fail "omawsl_orphan_tool_installed gh-copilot should fail when 'gh extension list' does not list it"
else
  pass "omawsl_orphan_tool_installed gh-copilot correctly fails when 'gh extension list' does not list it"
fi
unset -f gh

# =========================================================================
# omawsl_orphan_extract_semver
# =========================================================================

result="$(omawsl_orphan_extract_semver "zellij 0.44.3" || echo '<error>')"
if [[ "$result" == "0.44.3" ]]; then
  pass "omawsl_orphan_extract_semver pulls 0.44.3 out of 'zellij 0.44.3'"
else
  fail "omawsl_orphan_extract_semver('zellij 0.44.3') was '$result', expected '0.44.3'"
fi

result="$(omawsl_orphan_extract_semver "2.1.207 (Claude Code)" || echo '<error>')"
if [[ "$result" == "2.1.207" ]]; then
  pass "omawsl_orphan_extract_semver pulls the first version out of trailing text"
else
  fail "omawsl_orphan_extract_semver('2.1.207 (Claude Code)') was '$result', expected '2.1.207'"
fi

result="$(omawsl_orphan_extract_semver "" 2>/dev/null || echo '<error>')"
if [[ "$result" == "" ]]; then
  pass "omawsl_orphan_extract_semver on empty input returns empty, not an error (pipefail-safe)"
else
  fail "omawsl_orphan_extract_semver('') was '$result', expected empty output with exit 0 -- check for a missing '|| true' after the grep|head pipeline"
fi

# =========================================================================
# omawsl_orphan_latest_from_github
# =========================================================================

curl() { echo '{"tag_name":"v0.44.3"}'; }
export -f curl
result="$(omawsl_orphan_latest_from_github zellij-org/zellij 2>/dev/null || echo '<error>')"
if [[ "$result" == "0.44.3" ]]; then
  pass "omawsl_orphan_latest_from_github strips a leading 'v' from the release tag"
else
  fail "omawsl_orphan_latest_from_github with tag_name v0.44.3 was '$result', expected '0.44.3'"
fi

curl() { return 1; }
export -f curl
result="$(omawsl_orphan_latest_from_github zellij-org/zellij 2>/dev/null || echo '<error>')"
if [[ "$result" == "" ]]; then
  pass "omawsl_orphan_latest_from_github returns empty (not an error) when curl fails"
else
  fail "omawsl_orphan_latest_from_github on a curl failure was '$result', expected empty output with exit 0"
fi

curl() { echo 'not valid json'; }
export -f curl
result="$(omawsl_orphan_latest_from_github zellij-org/zellij 2>/dev/null || echo '<error>')"
if [[ "$result" == "" ]]; then
  pass "omawsl_orphan_latest_from_github returns empty (not an error) on malformed JSON"
else
  fail "omawsl_orphan_latest_from_github on malformed JSON was '$result', expected empty output with exit 0"
fi

# =========================================================================
# omawsl_orphan_latest_from_npm
# =========================================================================

mise() { echo "0.41.0"; }
export -f mise
result="$(omawsl_orphan_latest_from_npm "@openai/codex" 2>/dev/null || echo '<error>')"
if [[ "$result" == "0.41.0" ]]; then
  pass "omawsl_orphan_latest_from_npm returns the version 'mise exec node@lts -- npm view' printed"
else
  fail "omawsl_orphan_latest_from_npm('@openai/codex') was '$result', expected '0.41.0'"
fi

mise() { return 1; }
export -f mise
result="$(omawsl_orphan_latest_from_npm "@openai/codex" 2>/dev/null || echo '<error>')"
if [[ "$result" == "" ]]; then
  pass "omawsl_orphan_latest_from_npm returns empty (not an error) when mise fails"
else
  fail "omawsl_orphan_latest_from_npm on a mise failure was '$result', expected empty output with exit 0"
fi

# =========================================================================
# omawsl_orphan_tool_version_installed / omawsl_orphan_tool_version_latest
# =========================================================================

zellij() { echo "zellij 1.2.3"; }
export -f zellij
result="$(omawsl_orphan_tool_version_installed zellij 2>/dev/null || echo '<error>')"
if [[ "$result" == "1.2.3" ]]; then
  pass "omawsl_orphan_tool_version_installed zellij extracts 1.2.3 from a stubbed 'zellij --version'"
else
  fail "omawsl_orphan_tool_version_installed zellij was '$result', expected '1.2.3'"
fi
unset -f zellij

# No zellij on PATH at all here -- this must resolve to empty, not error,
# for the common case of an orphan tool that isn't installed.
result="$(PATH="/nonexistent-empty-dir" omawsl_orphan_tool_version_installed zellij 2>/dev/null || echo '<error>')"
if [[ "$result" == "" ]]; then
  pass "omawsl_orphan_tool_version_installed zellij returns empty (not an error) when zellij isn't installed"
else
  fail "omawsl_orphan_tool_version_installed zellij with no zellij on PATH was '$result', expected empty output with exit 0"
fi

curl() { echo '{"tag_name":"v9.9.9"}'; }
export -f curl
result="$(omawsl_orphan_tool_version_latest zellij 2>/dev/null || echo '<error>')"
if [[ "$result" == "9.9.9" ]]; then
  pass "omawsl_orphan_tool_version_latest zellij dispatches to the GitHub adapter"
else
  fail "omawsl_orphan_tool_version_latest zellij was '$result', expected '9.9.9' (should dispatch to omawsl_orphan_latest_from_github zellij-org/zellij)"
fi

mise() { echo "8.8.8"; }
export -f mise
result="$(omawsl_orphan_tool_version_latest codex 2>/dev/null || echo '<error>')"
if [[ "$result" == "8.8.8" ]]; then
  pass "omawsl_orphan_tool_version_latest codex dispatches to the npm adapter"
else
  fail "omawsl_orphan_tool_version_latest codex was '$result', expected '8.8.8' (should dispatch to omawsl_orphan_latest_from_npm @openai/codex)"
fi

# =========================================================================
# omawsl_orphan_tools_format_line
# =========================================================================

result="$(omawsl_orphan_tools_format_line zellij "1.0.0" "1.0.0" 2>/dev/null || echo '<error>')"
if [[ "$result" == *"up to date"* && "$result" == *"1.0.0"* ]]; then
  pass "omawsl_orphan_tools_format_line reports 'up to date' when installed == latest"
else
  fail "omawsl_orphan_tools_format_line(zellij, 1.0.0, 1.0.0) was '$result', expected it to mention 'up to date' and 1.0.0"
fi

result="$(omawsl_orphan_tools_format_line zellij "1.0.0" "2.0.0" 2>/dev/null || echo '<error>')"
if [[ "$result" == *"update available"* ]]; then
  pass "omawsl_orphan_tools_format_line reports 'update available' when installed != latest"
else
  fail "omawsl_orphan_tools_format_line(zellij, 1.0.0, 2.0.0) was '$result', expected it to mention 'update available'"
fi

result="$(omawsl_orphan_tools_format_line zellij "1.0.0" "" 2>/dev/null || echo '<error>')"
if [[ "$result" == *"unknown"* ]]; then
  pass "omawsl_orphan_tools_format_line reports 'unknown' when latest is empty"
else
  fail "omawsl_orphan_tools_format_line(zellij, 1.0.0, '') was '$result', expected it to mention 'unknown'"
fi

# =========================================================================
# omawsl_orphan_wait_with_timeout
# =========================================================================

sleep 0.2 &
fast_pid=$!
if omawsl_orphan_wait_with_timeout "$fast_pid" 5; then
  pass "omawsl_orphan_wait_with_timeout returns 0 for a process that exits on its own"
else
  fail "omawsl_orphan_wait_with_timeout should have returned 0 for a process that exits well within its timeout"
fi

sleep 30 &
slow_pid=$!
if omawsl_orphan_wait_with_timeout "$slow_pid" 1; then
  fail "omawsl_orphan_wait_with_timeout should have returned 1 for a process that outlives its timeout"
else
  pass "omawsl_orphan_wait_with_timeout returns 1 for a process that outlives its timeout"
fi
if kill -0 "$slow_pid" 2>/dev/null; then
  fail "omawsl_orphan_wait_with_timeout did not actually kill the process after its timeout"
  kill "$slow_pid" 2>/dev/null || true
else
  pass "omawsl_orphan_wait_with_timeout actually killed the process that outlived its timeout"
fi

# =========================================================================
# omawsl_orphan_tools_check_versions
# =========================================================================

zellij() { echo "zellij 1.2.3"; }
export -f zellij
lazydocker() { echo "Version: 4.5.6"; }
export -f lazydocker
curl() { echo '{"tag_name":"v9.9.9"}'; }
export -f curl

results_dir="$scratch/results"
mkdir -p "$results_dir"
omawsl_orphan_tools_check_versions "$results_dir" 5 zellij lazydocker || true

zellij_result="$(cat "$results_dir/zellij.result" 2>/dev/null || echo '<error>')"
if [[ "$zellij_result" == "$(printf '1.2.3\t9.9.9')" ]]; then
  pass "omawsl_orphan_tools_check_versions wrote zellij's correct installed/latest result"
else
  fail "omawsl_orphan_tools_check_versions wrote '$zellij_result' for zellij, expected '1.2.3<TAB>9.9.9'"
fi

lazydocker_result="$(cat "$results_dir/lazydocker.result" 2>/dev/null || echo '<error>')"
if [[ "$lazydocker_result" == "$(printf '4.5.6\t9.9.9')" ]]; then
  pass "omawsl_orphan_tools_check_versions wrote lazydocker's correct installed/latest result"
else
  fail "omawsl_orphan_tools_check_versions wrote '$lazydocker_result' for lazydocker, expected '4.5.6<TAB>9.9.9'"
fi
unset -f zellij lazydocker

# A single job that outlives the timeout: must still get a result file,
# with both sides empty ("unknown"), not a missing file or a crash.
omawsl_orphan_tool_version_latest() { sleep 30; echo "9.9.9"; }
export -f omawsl_orphan_tool_version_latest
timeout_results_dir="$scratch/results-timeout"
mkdir -p "$timeout_results_dir"
omawsl_orphan_tools_check_versions "$timeout_results_dir" 1 zellij || true
timeout_result="$(cat "$timeout_results_dir/zellij.result" 2>/dev/null || echo '<error>')"
if [[ "$timeout_result" == "$(printf '\t')" ]]; then
  pass "omawsl_orphan_tools_check_versions backfills an empty installed/latest result for a job that timed out"
else
  fail "omawsl_orphan_tools_check_versions on a timed-out job wrote '$timeout_result', expected an empty (tab-only) result"
fi
unset -f omawsl_orphan_tool_version_latest

# Parallel, not serial: 3 jobs that each take ~0.6s should finish in well
# under 3 x 0.6s = 1.8s if they actually run concurrently.
omawsl_orphan_tool_version_installed() { echo ""; }
export -f omawsl_orphan_tool_version_installed
omawsl_orphan_tool_version_latest() { sleep 0.6; echo "1.0.0"; }
export -f omawsl_orphan_tool_version_latest
parallel_dir="$scratch/results-parallel"
mkdir -p "$parallel_dir"
start_ns="$(date +%s%N)"
omawsl_orphan_tools_check_versions "$parallel_dir" 5 tool-a tool-b tool-c || true
end_ns="$(date +%s%N)"
elapsed_ms=$(( (end_ns - start_ns) / 1000000 ))
if [[ "$elapsed_ms" -lt 1400 ]]; then
  pass "omawsl_orphan_tools_check_versions ran 3 jobs in parallel (took ${elapsed_ms}ms, well under the ~1800ms a serial run would take)"
else
  fail "omawsl_orphan_tools_check_versions took ${elapsed_ms}ms for 3 jobs that each sleep 600ms -- looks serial, not parallel (jobs must run as background jobs, not one after another)"
fi

# Shared deadline, not a fresh timeout per job: 2 jobs that both hang
# forever, with timeout_seconds=1, must finish in ~1s total, not ~2s --
# see commit a50272a in the Walkthrough.
omawsl_orphan_tool_version_latest() { sleep 30; echo "9.9.9"; }
export -f omawsl_orphan_tool_version_latest
deadline_dir="$scratch/results-deadline"
mkdir -p "$deadline_dir"
start_ns="$(date +%s%N)"
omawsl_orphan_tools_check_versions "$deadline_dir" 1 tool-x tool-y || true
end_ns="$(date +%s%N)"
elapsed_ms=$(( (end_ns - start_ns) / 1000000 ))
if [[ "$elapsed_ms" -lt 1600 ]]; then
  pass "omawsl_orphan_tools_check_versions bounds 2 simultaneously-hanging jobs by one shared deadline (took ${elapsed_ms}ms, not ~2000ms+)"
else
  fail "omawsl_orphan_tools_check_versions took ${elapsed_ms}ms to bound 2 hanging jobs with timeout_seconds=1 -- looks like each job gets its own fresh timeout instead of sharing one deadline (~2000ms+ for 2 jobs suggests N x timeout_seconds)"
fi
unset -f omawsl_orphan_tool_version_installed omawsl_orphan_tool_version_latest

exit "$failed"
