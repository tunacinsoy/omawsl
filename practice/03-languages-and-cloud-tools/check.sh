#!/usr/bin/env bash
# practice/03-languages-and-cloud-tools/check.sh
#
# Behavioral check for dev-environment.sh (see
# docs/curriculum/03-languages-and-cloud-tools.md, section 3). Never runs
# the learner's script un-contained, and never lets curl/gpg/sudo (or a
# real apt repo, or a real network call) actually run for real:
#
#   - Every invocation below runs dev-environment.sh as a genuinely
#     separate process (`bash "$script"`), with HOME, the working
#     directory, AND PATH all redirected into a throwaway scratch
#     directory - never the real ones, and never practice/ itself.
#   - curl, gpg, and sudo are replaced with fake, exported bash functions
#     that just record what they were called with (Technique 2 from
#     check-generation.md) - `export -f` makes them visible inside the
#     separate `bash "$script"` process too, since a function defined only
#     in THIS process would otherwise be invisible there.
#   - `mise` is deliberately NOT one of those always-on function stubs.
#     Some scenarios below need `command -v mise` to genuinely fail (to
#     test the "not installed yet" path); others need it to succeed via a
#     real, tiny fake executable placed under a scratch $HOME/.local/bin
#     (to test the PATH-export-ordering path, and to capture the `mise
#     use`/`mise exec` calls a working mise would receive). Each scenario
#     sets this up for itself.
#   - PATH is fixed to a short, safe list of real system directories for
#     every scenario, deliberately excluding $HOME/.local/bin and any
#     other user-specific directory - this machine may genuinely have a
#     real `mise` (or `terraform`/`az`) installed for unrelated reasons,
#     the same class of false positive this project's own test suite hit
#     once its dev machine got real tools installed for real (see the
#     lesson's Bug 3 section, and tests/helpers/stubs.bash's
#     stub_hide_command).

set -euo pipefail

failed=0
script_dir="$(cd "$(dirname "$0")" && pwd)"
script="$script_dir/dev-environment.sh"
scratch_root="$(mktemp -d)"
trap 'rm -rf "$scratch_root"' EXIT

if [[ ! -f "$script" ]]; then
  echo "FAIL: $script does not exist - nothing to check"
  exit 1
fi

SAFE_PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; failed=1; }

# make_mise_fake <home_dir> <log_file>
# Drops a tiny, genuinely-executable fake `mise` at
# <home_dir>/.local/bin/mise, which just appends its own arguments to
# <log_file> and exits 0. This is a REAL file found via a REAL `PATH`
# lookup (not a bash function) - deliberately, so it exercises the exact
# same "is it on PATH yet" mechanism the learner's script has to get
# right, rather than a shortcut that would work differently.
make_mise_fake() {
  local home_dir="$1" log_file="$2"
  mkdir -p "$home_dir/.local/bin"
  cat > "$home_dir/.local/bin/mise" <<EOF
#!/usr/bin/env bash
echo "mise \$*" >> "$log_file"
exit 0
EOF
  chmod +x "$home_dir/.local/bin/mise"
}

# --- curl / gpg / sudo: always-on stubs, every scenario ---------------------
# None of these ever run for real, in any scenario below. sudo inspects its
# own first argument: a failing "apt-get" is opt-in per scenario via
# SUDO_APT_GET_EXIT (unset/0 by default = success), and "sudo rm" forwards
# to the REAL rm so cleanup-on-failure is verifiable on disk, exactly like
# the real project's own regression test for this (commit 18134f5).
export CALL_LOG=""  # set per scenario below

curl() {
  echo "curl $*" >> "$CALL_LOG"
  return "${CURL_EXIT:-0}"
}
export -f curl

gpg() {
  echo "gpg $*" >> "$CALL_LOG"
  return 0
}
export -f gpg

sudo() {
  echo "sudo $*" >> "$CALL_LOG"
  if [[ "${1:-}" == "apt-get" && "${SUDO_APT_GET_EXIT:-0}" -ne 0 ]]; then
    return "${SUDO_APT_GET_EXIT}"
  fi
  if [[ "${1:-}" == "rm" ]]; then
    shift
    command rm "$@"
    return $?
  fi
  return 0
}
export -f sudo

# run_scenario <home_dir> <extra_env_assignments...>
# Invokes dev-environment.sh as a real, separate process, with HOME, cwd,
# and PATH all pinned to the scratch scenario directory - never the real
# ones. <extra_env_assignments...> are NAME=value strings (may contain
# spaces, e.g. "OMAWSL_LANGUAGES=Go,Ruby on Rails") applied via `env`
# rather than bash's own assignment-prefix syntax - bash only recognizes
# `NAME=value cmd` as an environment assignment when NAME=value is a
# literal token in the script text at parse time; a dynamically-built
# string arriving through "$@" is just an ordinary argument by the time
# the shell sees it; without `env`, bash never happens to be so wrong
# quietly and the shell just tries to run it as a command. `env` is a
# separate real program that always treats its own leading NAME=value
# arguments as environment assignments, so it works regardless of how
# those strings were built. Prints the child's combined stdout/stderr;
# caller captures the exit status via $?.
run_scenario() {
  local home_dir="$1"; shift
  ( cd "$home_dir" && HOME="$home_dir" PATH="$SAFE_PATH" env "$@" bash "$script" ) 2>&1
}

# =============================================================================
# Scenario 1: mise not installed anywhere reachable -> installs it via curl.
# =============================================================================
home1="$scratch_root/home1"; mkdir -p "$home1"
log1="$scratch_root/log1"; : > "$log1"
export CALL_LOG="$log1"
export SUDO_APT_GET_EXIT=0
export CURL_EXIT=0

set +e
out1="$(run_scenario "$home1" OMAWSL_LANGUAGES=)"
status1=$?
set -e

if [[ "$status1" -eq 0 ]]; then
  pass "runs without error when mise isn't installed and nothing is selected"
else
  fail "exited non-zero ($status1) when mise isn't installed and nothing is selected - output: $out1"
fi

calls1="$(cat "$log1" 2>/dev/null || true)"
if [[ "$calls1" == *"curl -fsSL https://mise.run"* ]]; then
  pass "installs mise via 'curl -fsSL https://mise.run | sh' when mise isn't already reachable"
else
  fail "did not call 'curl -fsSL https://mise.run' even though mise wasn't reachable (got: $calls1)"
fi

# =============================================================================
# Scenario 2: mise already present, but ONLY under $HOME/.local/bin - not on
# the ambient PATH this process started with. This is the PATH-export-
# ordering check: it only passes if PATH is exported before mise's
# presence is checked.
# =============================================================================
home2="$scratch_root/home2"; mkdir -p "$home2"
log2="$scratch_root/log2"; : > "$log2"
mise_log2="$scratch_root/mise_log2"; : > "$mise_log2"
make_mise_fake "$home2" "$mise_log2"
export CALL_LOG="$log2"

set +e
out2="$(run_scenario "$home2" OMAWSL_LANGUAGES=)"
status2=$?
set -e

if [[ "$status2" -eq 0 ]]; then
  pass "runs without error when mise is already installed under \$HOME/.local/bin"
else
  fail "exited non-zero ($status2) when mise was already installed under \$HOME/.local/bin - output: $out2"
fi

calls2="$(cat "$log2" 2>/dev/null || true)"
if [[ "$calls2" != *"curl"* ]]; then
  pass "does NOT re-download mise when it's already installed under \$HOME/.local/bin (requires exporting PATH before the presence check, not after)"
else
  fail "called curl to install mise even though a real mise executable already existed under \$HOME/.local/bin - likely checking 'command -v mise' BEFORE exporting \$HOME/.local/bin onto PATH (got: $calls2)"
fi

# =============================================================================
# Scenario 3: language dispatch - several languages plus Ruby on Rails,
# verifying the exact mise commands and that nothing extra runs.
# =============================================================================
home3="$scratch_root/home3"; mkdir -p "$home3"
log3="$scratch_root/log3"; : > "$log3"
mise_log3="$scratch_root/mise_log3"; : > "$mise_log3"
make_mise_fake "$home3" "$mise_log3"
export CALL_LOG="$log3"

set +e
out3="$(run_scenario "$home3" 'OMAWSL_LANGUAGES=Go,Rust,Ruby on Rails')"
status3=$?
set -e

mise_calls3="$(cat "$mise_log3" 2>/dev/null || true)"

if [[ "$status3" -eq 0 ]]; then
  pass "language dispatch runs without error for 'Go,Rust,Ruby on Rails'"
else
  fail "exited non-zero ($status3) for OMAWSL_LANGUAGES='Go,Rust,Ruby on Rails' - output: $out3"
fi

if [[ "$mise_calls3" == *"use --global go@latest"* ]]; then
  pass "installs Go via 'mise use --global go@latest'"
else
  fail "did not call 'mise use --global go@latest' for a Go selection (mise saw: $mise_calls3)"
fi

if [[ "$mise_calls3" == *"use --global rust@latest"* ]]; then
  pass "installs Rust via 'mise use --global rust@latest'"
else
  fail "did not call 'mise use --global rust@latest' for a Rust selection (mise saw: $mise_calls3)"
fi

if [[ "$mise_calls3" == *"use --global ruby@latest"* ]]; then
  pass "Ruby on Rails installs ruby via 'mise use --global ruby@latest'"
else
  fail "Ruby on Rails selection did not call 'mise use --global ruby@latest' (mise saw: $mise_calls3)"
fi

if [[ "$mise_calls3" == *"exec ruby@latest -- gem install rails"* ]]; then
  pass "Ruby on Rails additionally installs the rails gem via 'mise exec ruby@latest -- gem install rails' (not a bare 'gem install')"
else
  fail "Ruby on Rails selection did not call 'mise exec ruby@latest -- gem install rails' (mise saw: $mise_calls3)"
fi

if [[ "$mise_calls3" != *"php"* && "$mise_calls3" != *"java"* && "$mise_calls3" != *"node"* && "$mise_calls3" != *"python"* && "$mise_calls3" != *"elixir"* ]]; then
  pass "does not install any language that wasn't selected"
else
  fail "installed a language that wasn't selected (mise saw: $mise_calls3)"
fi

# =============================================================================
# Scenario 4: selecting nothing installs no languages, and is not an error.
# =============================================================================
home4="$scratch_root/home4"; mkdir -p "$home4"
log4="$scratch_root/log4"; : > "$log4"
mise_log4="$scratch_root/mise_log4"; : > "$mise_log4"
make_mise_fake "$home4" "$mise_log4"
export CALL_LOG="$log4"

set +e
out4="$(run_scenario "$home4" OMAWSL_LANGUAGES=)"
status4=$?
set -e

mise_calls4="$(cat "$mise_log4" 2>/dev/null || true)"
if [[ "$status4" -eq 0 && "$mise_calls4" != *"use --global"* && "$mise_calls4" != *"exec ruby"* ]]; then
  pass "selecting no languages installs nothing and exits 0"
else
  fail "selecting no languages should exit 0 and call no 'mise use'/'mise exec' - got status $status4, mise saw: $mise_calls4"
fi

# =============================================================================
# Scenario 5: Terraform/Azure CLI are not treated as languages (must not
# reach the mise dispatcher at all), but Terraform IS attempted via the
# cloud-tools path.
# =============================================================================
home5="$scratch_root/home5"; mkdir -p "$home5"
log5="$scratch_root/log5"; : > "$log5"
mise_log5="$scratch_root/mise_log5"; : > "$mise_log5"
make_mise_fake "$home5" "$mise_log5"
export CALL_LOG="$log5"
sources5="$scratch_root/hashicorp5.list"
keyrings5="$scratch_root/keyrings5"
rm -f "$sources5"

set +e
out5="$(run_scenario "$home5" 'OMAWSL_LANGUAGES=Terraform,Azure CLI' \
  "OMAWSL_TERRAFORM_APT_SOURCES_FILE=$sources5" "OMAWSL_TERRAFORM_APT_KEYRINGS_DIR=$keyrings5" \
  "OMAWSL_AZURE_CLI_APT_SOURCES_FILE=$scratch_root/azure5.list" "OMAWSL_AZURE_CLI_APT_KEYRINGS_DIR=$scratch_root/keyrings5")"
status5=$?
set -e

mise_calls5="$(cat "$mise_log5" 2>/dev/null || true)"
calls5="$(cat "$log5" 2>/dev/null || true)"

if [[ "$mise_calls5" != *"use --global"* && "$mise_calls5" != *"exec ruby"* ]]; then
  pass "Terraform/Azure CLI never reach the mise language dispatcher"
else
  fail "Terraform or Azure CLI was mistakenly routed through the mise language dispatcher (mise saw: $mise_calls5)"
fi

if [[ "$calls5" == *"curl -fsSL https://apt.releases.hashicorp.com/gpg"* ]]; then
  pass "Terraform IS attempted via the cloud-tools apt-repo path when selected"
else
  fail "Terraform was not attempted at all when selected (got: $calls5)"
fi

# =============================================================================
# Scenario 6: Terraform happy path - sources file doesn't exist yet -> full
# repo-add (with 'gpg --yes --dearmor', the Bug 3 fix) then install.
# =============================================================================
home6="$scratch_root/home6"; mkdir -p "$home6"
log6="$scratch_root/log6"; : > "$log6"
make_mise_fake "$home6" "$scratch_root/mise_log6"
export CALL_LOG="$log6"
export SUDO_APT_GET_EXIT=0
export CURL_EXIT=0
sources6="$scratch_root/hashicorp6.list"
keyrings6="$scratch_root/keyrings6"
rm -f "$sources6"

set +e
out6="$(run_scenario "$home6" OMAWSL_LANGUAGES=Terraform \
  "OMAWSL_TERRAFORM_APT_SOURCES_FILE=$sources6" "OMAWSL_TERRAFORM_APT_KEYRINGS_DIR=$keyrings6")"
status6=$?
set -e

calls6="$(cat "$log6" 2>/dev/null || true)"

if [[ "$status6" -eq 0 ]]; then
  pass "Terraform happy-path install runs without error"
else
  fail "Terraform happy-path install exited non-zero ($status6) - output: $out6"
fi

if [[ "$calls6" == *"curl -fsSL https://apt.releases.hashicorp.com/gpg"* ]]; then
  pass "fetches Terraform's GPG key from https://apt.releases.hashicorp.com/gpg"
else
  fail "did not fetch Terraform's GPG key from the right URL (got: $calls6)"
fi

if [[ "$calls6" == *"sudo gpg --yes --dearmor"* && "$calls6" == *"$keyrings6/hashicorp.gpg"* ]]; then
  pass "dearmors the key with 'gpg --yes --dearmor' into <keyrings_dir>/hashicorp.gpg (the Bug 3 fix - without --yes, a re-run over an existing keyring file would hang)"
else
  fail "did not call 'sudo gpg --yes --dearmor -o $keyrings6/hashicorp.gpg' (got: $calls6)"
fi

if [[ "$calls6" == *"sudo apt-get install -y terraform"* ]]; then
  pass "installs terraform via 'sudo apt-get install -y terraform'"
else
  fail "did not call 'sudo apt-get install -y terraform' (got: $calls6)"
fi

# =============================================================================
# Scenario 7: Terraform - sources file already exists -> skip the repo-add,
# but still attempt the install (idempotent re-run).
# =============================================================================
home7="$scratch_root/home7"; mkdir -p "$home7"
log7="$scratch_root/log7"; : > "$log7"
make_mise_fake "$home7" "$scratch_root/mise_log7"
export CALL_LOG="$log7"
sources7="$scratch_root/hashicorp7.list"
: > "$sources7"

set +e
out7="$(run_scenario "$home7" OMAWSL_LANGUAGES=Terraform \
  "OMAWSL_TERRAFORM_APT_SOURCES_FILE=$sources7" "OMAWSL_TERRAFORM_APT_KEYRINGS_DIR=$scratch_root/keyrings7")"
status7=$?
set -e

calls7="$(cat "$log7" 2>/dev/null || true)"

if [[ "$calls7" != *"curl"* ]]; then
  pass "skips the repo-add (no curl call) when the sources file already exists"
else
  fail "called curl even though the Terraform sources file already existed - the repo-add is supposed to be skipped on a re-run (got: $calls7)"
fi

if [[ "$calls7" == *"sudo apt-get install -y terraform"* ]]; then
  pass "still attempts 'apt-get install -y terraform' even when the repo-add was skipped"
else
  fail "did not attempt 'apt-get install -y terraform' when the sources file already existed (got: $calls7)"
fi

# =============================================================================
# Scenario 8: Terraform - the key fetch itself fails -> isolates the
# failure (exits 0, prints a message), and must NOT proceed to apt-get
# install. This is also the "&&, not ;, inside the isolation block" check:
# a ';'-chained implementation would still reach apt-get install after the
# curl failure.
# =============================================================================
home8="$scratch_root/home8"; mkdir -p "$home8"
log8="$scratch_root/log8"; : > "$log8"
make_mise_fake "$home8" "$scratch_root/mise_log8"
export CALL_LOG="$log8"
export CURL_EXIT=1
export SUDO_APT_GET_EXIT=0
sources8="$scratch_root/hashicorp8.list"
rm -f "$sources8"

set +e
out8="$(run_scenario "$home8" OMAWSL_LANGUAGES=Terraform \
  "OMAWSL_TERRAFORM_APT_SOURCES_FILE=$sources8" "OMAWSL_TERRAFORM_APT_KEYRINGS_DIR=$scratch_root/keyrings8")"
status8=$?
set -e
export CURL_EXIT=0

if [[ "$status8" -eq 0 ]]; then
  pass "a failed key fetch is isolated - the script still exits 0"
else
  fail "the script exited non-zero ($status8) after Terraform's key fetch failed - the failure isn't isolated (missing '{ ... } || ok=0', or the whole script aborted under set -e). Output: $out8"
fi

calls8="$(cat "$log8" 2>/dev/null || true)"
if [[ "$calls8" != *"apt-get install -y terraform"* ]]; then
  pass "does not proceed to 'apt-get install' after the key fetch already failed (repo-add steps are chained with &&, not ;)"
else
  fail "called 'apt-get install -y terraform' even though the key fetch failed first - the repo-add steps must be chained with && so a failure stops the rest of that block (got: $calls8)"
fi

if [[ "$out8" == *"Terraform"* && "$out8" == *"failed"* ]]; then
  pass "prints a message naming Terraform and the word 'failed'"
else
  fail "did not print a message naming Terraform and 'failed' after the key fetch failed (output: $out8)"
fi

# =============================================================================
# Scenario 9: Terraform + Azure CLI both selected. apt-get itself fails
# (repo-add succeeded, install did not) against a PRE-EXISTING (stale)
# Terraform sources file. Verifies: the stale file gets removed (Bug 2's
# fix), a failure message is printed, the script exits 0, AND Azure CLI is
# still attempted (its own key fetch happens) despite Terraform's failure.
# =============================================================================
home9="$scratch_root/home9"; mkdir -p "$home9"
log9="$scratch_root/log9"; : > "$log9"
make_mise_fake "$home9" "$scratch_root/mise_log9"
export CALL_LOG="$log9"
export SUDO_APT_GET_EXIT=1
export CURL_EXIT=0
sources9_tf="$scratch_root/hashicorp9.list"
sources9_az="$scratch_root/azure9.list"
: > "$sources9_tf"   # pre-existing, as if a previous run's repo-add half-succeeded
rm -f "$sources9_az"

set +e
out9="$(run_scenario "$home9" 'OMAWSL_LANGUAGES=Terraform,Azure CLI' \
  "OMAWSL_TERRAFORM_APT_SOURCES_FILE=$sources9_tf" "OMAWSL_TERRAFORM_APT_KEYRINGS_DIR=$scratch_root/keyrings9" \
  "OMAWSL_AZURE_CLI_APT_SOURCES_FILE=$sources9_az" "OMAWSL_AZURE_CLI_APT_KEYRINGS_DIR=$scratch_root/keyrings9")"
status9=$?
set -e
export SUDO_APT_GET_EXIT=0

if [[ "$status9" -eq 0 ]]; then
  pass "an apt-get install failure for Terraform is isolated - the script still exits 0"
else
  fail "the script exited non-zero ($status9) after Terraform's apt-get install failed. Output: $out9"
fi

if [[ ! -f "$sources9_tf" ]]; then
  pass "removes the stale Terraform sources file after apt-get install fails (Bug 2's fix - otherwise it would poison a later, unrelated apt-get update)"
else
  fail "the stale Terraform sources file ($sources9_tf) was NOT removed after apt-get install failed - a later apt-get update would still see this broken repo listing"
fi

if [[ "$out9" == *"Terraform"* && "$out9" == *"failed"* ]]; then
  pass "prints a message naming Terraform and 'failed' when its apt-get install fails"
else
  fail "did not print a message naming Terraform and 'failed' when its apt-get install failed (output: $out9)"
fi

calls9="$(cat "$log9" 2>/dev/null || true)"
if [[ "$calls9" == *"curl -fsSL https://packages.microsoft.com/keys/microsoft.asc"* ]]; then
  pass "Azure CLI is still attempted even though Terraform's install failed first (failure isolation across tools)"
else
  fail "Azure CLI's key was never fetched - Terraform's failure appears to have stopped the run before Azure CLI was attempted (got: $calls9)"
fi

exit "$failed"
