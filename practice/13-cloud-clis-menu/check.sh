#!/usr/bin/env bash
set -euo pipefail

# Never lets a real apt-get/curl/unzip/sudo/gpg/dpkg run. Every dangerous
# command below is replaced with a same-named shell function that just
# records what it was asked to do (and, for sudo, simulates the *effect*
# of a real install/uninstall by touching/removing a fake binary on a
# scratch PATH entry) - see docs/curriculum/13-cloud-clis-menu.md,
# section 4, and the teach-from-scratch check-generation reference,
# "Technique 2: stubbing a dangerous command". The real project always
# routes apt-get/gpg/tee/rm through `sudo`, so `sudo` - not `apt-get` - is
# the interception point that actually matters; `apt-get` is stubbed too,
# defensively, in case it's ever called bare.
#
# Everything below is sourced directly into this process (never `bash
# some_script.sh` as a child), and none of the files under test have an
# unconditional dispatcher (each one's `if [[ BASH_SOURCE[0] == $0 ]]`
# guard only fires when the file is *run*, not sourced) - so plain
# sourcing is safe, per Strategy A's own note about when sourcing doesn't
# need a subprocess. `export -f` is used anyway on every stub so the same
# containment also covers the couple of places this check deliberately
# spawns a child `bash -c` (to inspect one file's definitions in
# isolation from the others).

dir="$(cd "$(dirname "$0")" && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
failed=0

required_files="lib.sh items.sh cloud-tools.sh cloud-clis.sh uninstall-language.sh uninstall-cloud-clis.sh doctor-cloud.sh"
for f in $required_files; do
  if [[ ! -f "$dir/$f" ]]; then
    echo "FAIL: practice/13-cloud-clis-menu/$f does not exist yet"
    failed=1
  fi
done
if [[ "$failed" -ne 0 ]]; then
  exit 1
fi

call_log="$scratch/calls.log"
fakebin="$scratch/fakebin"
mkdir -p "$fakebin"
: > "$call_log"
export call_log fakebin
export CURL_EXIT=0

dpkg() { echo "amd64"; }
export -f dpkg

curl() {
  echo "curl $*" >> "$call_log"
  return "${CURL_EXIT}"
}
export -f curl

unzip() {
  echo "unzip $*" >> "$call_log"
  return 0
}
export -f unzip

gpg() {
  echo "gpg $*" >> "$call_log"
  return 0
}
export -f gpg

apt-get() {
  echo "apt-get $*" >> "$call_log"
  return 0
}
export -f apt-get

# sudo simulates the effect of a real install/uninstall (creating or
# removing a fake binary on $fakebin, which is on PATH) so `command -v`
# guards elsewhere behave realistically - without this, every idempotency
# check below would be unable to tell "installed" from "not installed".
sudo() {
  echo "sudo $*" >> "$call_log"
  case "$*" in
    *"apt-get install -y azure-cli"*)        touch "$fakebin/az" ;;
    *"apt-get install -y google-cloud-cli"*) touch "$fakebin/gcloud" ;;
    *"apt-get purge -y azure-cli"*)          rm -f "$fakebin/az" ;;
    *"apt-get purge -y google-cloud-cli"*)   rm -f "$fakebin/gcloud" ;;
    *"/aws/install"*)                        touch "$fakebin/aws" ;;
    *"rm -rf /usr/local/aws-cli"*)           rm -f "$fakebin/aws" ;;
  esac
  return 0
}
export -f sudo

export PATH="$fakebin:$PATH"

reset_state() {
  : > "$call_log"
  rm -f "$fakebin/az" "$fakebin/aws" "$fakebin/gcloud"
}

call_count() {
  grep -c -- "$1" "$call_log" 2>/dev/null || true
}

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; failed=1; }

# shellcheck source=/dev/null
source "$dir/lib.sh"
# shellcheck source=/dev/null
source "$dir/items.sh"
# shellcheck source=/dev/null
source "$dir/cloud-tools.sh"
# shellcheck source=/dev/null
source "$dir/cloud-clis.sh"
# shellcheck source=/dev/null
source "$dir/uninstall-language.sh"
# shellcheck source=/dev/null
source "$dir/uninstall-cloud-clis.sh"
# shellcheck source=/dev/null
source "$dir/doctor-cloud.sh"

# === 1. items.sh: the registry itself ======================================

check_category() {
  local slug="$1" expected="$2" got
  got="$(omawsl_item_category "$slug" 2>/dev/null || echo '<error>')"
  if [[ "$got" == "$expected" ]]; then
    pass "omawsl_item_category $slug == '$expected'"
  else
    fail "omawsl_item_category $slug expected '$expected', got '$got'"
  fi
}
check_category go language
check_category terraform language
check_category azure cloud
check_category aws cloud
check_category gcp cloud

check_label() {
  local slug="$1" expected="$2" got
  got="$(omawsl_item_label "$slug" 2>/dev/null || echo '<error>')"
  if [[ "$got" == "$expected" ]]; then
    pass "omawsl_item_label $slug == '$expected'"
  else
    fail "omawsl_item_label $slug expected '$expected', got '$got'"
  fi
}
check_label azure "Azure CLI"
check_label aws "AWS CLI"
check_label gcp "GCP CLI"

cloud_slugs="$(omawsl_item_slugs cloud 2>/dev/null | sort | paste -sd, - || echo '<error>')"
if [[ "$cloud_slugs" == "aws,azure,gcp" ]]; then
  pass "omawsl_item_slugs cloud returns exactly {azure, aws, gcp}"
else
  fail "omawsl_item_slugs cloud expected the set {azure, aws, gcp}, got '$cloud_slugs'"
fi

language_slugs="$(omawsl_item_slugs language 2>/dev/null | sort | paste -sd, - || echo '<error>')"
if [[ "$language_slugs" == "go,terraform" ]]; then
  pass "omawsl_item_slugs language no longer includes azure"
else
  fail "omawsl_item_slugs language expected the set {go, terraform} (azure moved out), got '$language_slugs'"
fi

# === 2. cloud-tools.sh: Azure CLI moved OUT ================================
# Isolated in a child bash that sources ONLY lib.sh + cloud-tools.sh, so
# this can't accidentally pass just because cloud-clis.sh (sourced above,
# into THIS process) also defines omawsl_install_azure_cli.

cloud_tools_probe="$(bash -c '
  set -euo pipefail
  source "'"$dir"'/lib.sh"
  source "'"$dir"'/cloud-tools.sh"
  if declare -f omawsl_install_azure_cli >/dev/null 2>&1; then
    echo "STILL_DEFINED"
  else
    echo "NOT_DEFINED"
  fi
' 2>&1)" || cloud_tools_probe="<error: $cloud_tools_probe>"

if [[ "$cloud_tools_probe" == "NOT_DEFINED" ]]; then
  pass "cloud-tools.sh no longer defines omawsl_install_azure_cli (moved out)"
else
  fail "cloud-tools.sh should no longer define omawsl_install_azure_cli - got '$cloud_tools_probe'"
fi

reset_state
cloud_tools_run="$(bash -c '
  set -euo pipefail
  source "'"$dir"'/lib.sh"
  source "'"$dir"'/cloud-tools.sh"
  OMAWSL_LANGUAGES="Azure CLI" omawsl_cloud_tools
  echo "RAN_CLEANLY"
' 2>&1)" || cloud_tools_run="<error: $cloud_tools_run>"

if [[ "$cloud_tools_run" == "RAN_CLEANLY" ]]; then
  pass "omawsl_cloud_tools with only 'Azure CLI' selected runs cleanly (no dangling call to a removed function)"
else
  fail "omawsl_cloud_tools with only 'Azure CLI' selected should run cleanly and install nothing - got '$cloud_tools_run'"
fi

if [[ "$(call_count 'apt-get install -y azure-cli')" -eq 0 ]]; then
  pass "omawsl_cloud_tools no longer installs Azure CLI"
else
  fail "omawsl_cloud_tools should not install Azure CLI anymore - it should only handle Terraform now"
fi

# === 3. uninstall-language.sh: Azure CLI moved OUT ==========================

uninstall_lang_probe="$(bash -c '
  set -euo pipefail
  source "'"$dir"'/lib.sh"
  source "'"$dir"'/uninstall-language.sh"
  if omawsl_uninstall_language "Azure CLI" >/dev/null 2>&1; then
    echo "HANDLED"
  else
    echo "REJECTED"
  fi
' 2>&1)" || uninstall_lang_probe="<error: $uninstall_lang_probe>"

if [[ "$uninstall_lang_probe" == "REJECTED" ]]; then
  pass "uninstall-language.sh's omawsl_uninstall_language no longer handles 'Azure CLI'"
else
  fail "omawsl_uninstall_language('Azure CLI') should now fall through to the unknown-label case - got '$uninstall_lang_probe'"
fi

uninstall_lang_terraform="$(bash -c '
  set -euo pipefail
  source "'"$dir"'/lib.sh"
  source "'"$dir"'/uninstall-language.sh"
  omawsl_uninstall_language "Terraform" >/dev/null 2>&1 && echo "OK"
' 2>&1)" || uninstall_lang_terraform="<error: $uninstall_lang_terraform>"

if [[ "$uninstall_lang_terraform" == "OK" ]]; then
  pass "omawsl_uninstall_language('Terraform') still works (Terraform never moved)"
else
  fail "omawsl_uninstall_language('Terraform') should still work - got '$uninstall_lang_terraform'"
fi

# === 4. install/uninstall/doctor agree on the cloud registry ===============

for slug_fn in "azure:omawsl_install_azure_cli" "aws:omawsl_install_aws_cli" "gcp:omawsl_install_gcp_cli"; do
  slug="${slug_fn%%:*}"; fn="${slug_fn##*:}"
  if declare -f "$fn" >/dev/null 2>&1; then
    pass "cloud-clis.sh defines $fn for slug '$slug'"
  else
    fail "cloud-clis.sh should define $fn for slug '$slug' (every cloud registry slug needs a matching install function)"
  fi
done

for label in "Azure CLI" "AWS CLI" "GCP CLI"; do
  reset_state
  if omawsl_uninstall_cloud_cli "$label" >/dev/null 2>&1; then
    pass "omawsl_uninstall_cloud_cli accepts label '$label' (agrees with items.sh's registry)"
  else
    fail "omawsl_uninstall_cloud_cli should accept label '$label' as a clean no-op when it's not installed"
  fi
done

if omawsl_uninstall_cloud_cli "Bogus CLI" >/dev/null 2>&1; then
  fail "omawsl_uninstall_cloud_cli('Bogus CLI') should be rejected as unknown, not silently succeed"
else
  pass "omawsl_uninstall_cloud_cli rejects an unregistered label"
fi

for pair in "azure:az" "aws:aws" "gcp:gcloud"; do
  slug="${pair%%:*}"; bin="${pair##*:}"
  rm -f "$fakebin/$bin"
  if omawsl_doctor_cloud_installed "$slug" >/dev/null 2>&1; then
    fail "omawsl_doctor_cloud_installed $slug should report false before $bin is on PATH"
  else
    pass "omawsl_doctor_cloud_installed $slug correctly reports not-installed before $bin exists"
  fi
  touch "$fakebin/$bin"
  if omawsl_doctor_cloud_installed "$slug" >/dev/null 2>&1; then
    pass "omawsl_doctor_cloud_installed $slug correctly reports installed once $bin is on PATH"
  else
    fail "omawsl_doctor_cloud_installed $slug should report true once $bin is on PATH"
  fi
  rm -f "$fakebin/$bin"
done

if omawsl_doctor_cloud_installed "bogus" >/dev/null 2>&1; then
  fail "omawsl_doctor_cloud_installed should reject an unregistered slug, not report it as installed"
else
  pass "omawsl_doctor_cloud_installed rejects an unregistered slug"
fi

# === 5. Install-then-uninstall idempotency (Azure CLI) ======================

reset_state

if command -v az >/dev/null 2>&1; then
  fail "test setup problem: az should not be reachable before the idempotency test starts"
else
  pass "az is not present before the idempotency test (clean starting state)"
fi

if omawsl_install_azure_cli >/dev/null 2>&1; then
  pass "omawsl_install_azure_cli ran without error"
else
  fail "omawsl_install_azure_cli raised an error"
fi

if command -v az >/dev/null 2>&1; then
  pass "az is reachable after omawsl_install_azure_cli"
else
  fail "az is not reachable after omawsl_install_azure_cli - it should end up calling (through sudo) apt-get install -y azure-cli"
fi

first_count="$(call_count 'apt-get install -y azure-cli')"

if omawsl_install_azure_cli >/dev/null 2>&1; then
  pass "calling omawsl_install_azure_cli a second time still runs without error"
else
  fail "a second omawsl_install_azure_cli call raised an error"
fi

second_count="$(call_count 'apt-get install -y azure-cli')"
if [[ "$first_count" -ge 1 && "$second_count" -eq "$first_count" ]]; then
  pass "omawsl_install_azure_cli is idempotent (a second call doesn't re-install)"
else
  fail "expected the install to run exactly once across two calls (idempotency guard) - ran $first_count time(s) then $second_count time(s) total"
fi

if omawsl_uninstall_azure_cli >/dev/null 2>&1; then
  pass "omawsl_uninstall_azure_cli ran without error"
else
  fail "omawsl_uninstall_azure_cli raised an error"
fi

if command -v az >/dev/null 2>&1; then
  fail "az is still reachable after omawsl_uninstall_azure_cli"
else
  pass "az is gone after omawsl_uninstall_azure_cli"
fi

if omawsl_uninstall_azure_cli >/dev/null 2>&1; then
  pass "uninstalling Azure CLI again (already gone) is a clean no-op"
else
  fail "uninstalling an already-uninstalled Azure CLI should not error"
fi

# === 6. omawsl_cloud_clis: the dispatcher reads the picker selection =======

reset_state
OMAWSL_CLOUD_CLIS=""
if omawsl_cloud_clis >/dev/null 2>&1; then
  pass "omawsl_cloud_clis with nothing selected runs without error"
else
  fail "omawsl_cloud_clis with nothing selected raised an error"
fi

if [[ -z "$(cat "$call_log")" ]]; then
  pass "omawsl_cloud_clis with nothing selected installs nothing (valid no-op, matches 'nothing pre-selected by default')"
else
  fail "omawsl_cloud_clis with an empty selection should not call anything - it did:"$'\n'"$(cat "$call_log")"
fi

reset_state
OMAWSL_CLOUD_CLIS="Azure CLI,AWS CLI,GCP CLI"
if omawsl_cloud_clis >/dev/null 2>&1; then
  pass "omawsl_cloud_clis with all three selected runs without error"
else
  fail "omawsl_cloud_clis with all three selected raised an error"
fi

if command -v az >/dev/null 2>&1; then
  pass "omawsl_cloud_clis installed Azure CLI when selected"
else
  fail "omawsl_cloud_clis should have installed Azure CLI ('Azure CLI' was in the selection)"
fi
if command -v gcloud >/dev/null 2>&1; then
  pass "omawsl_cloud_clis installed GCP CLI when selected"
else
  fail "omawsl_cloud_clis should have installed GCP CLI ('GCP CLI' was in the selection)"
fi
if command -v aws >/dev/null 2>&1; then
  pass "omawsl_cloud_clis installed AWS CLI when selected"
else
  fail "omawsl_cloud_clis should have installed AWS CLI ('AWS CLI' was in the selection)"
fi

# === 7. AWS CLI's failure-handling split (the real shipped bug) ============
# omawsl_aws_cli_install_steps must propagate a real failure (it didn't,
# originally - omawsl update reported a failed download as "updated AWS
# CLI"). omawsl_install_aws_cli, the guarded install-time wrapper, must
# swallow that same failure instead, so one bad download can't abort the
# rest of an install.sh run under set -e.

reset_state
CURL_EXIT=1

if omawsl_aws_cli_install_steps >/dev/null 2>&1; then
  fail "omawsl_aws_cli_install_steps returned success even though curl failed - it must propagate a real failure (see this lesson's Walkthrough for the shipped bug this causes)"
else
  pass "omawsl_aws_cli_install_steps returns non-zero when the download fails"
fi

rm -f "$fakebin/aws"
if omawsl_install_aws_cli >/dev/null 2>&1; then
  pass "omawsl_install_aws_cli swallows a failed install_steps call (a failed install can't abort install.sh under set -e)"
else
  fail "omawsl_install_aws_cli should swallow a failed omawsl_aws_cli_install_steps call and still return success"
fi

CURL_EXIT=0

exit "$failed"
