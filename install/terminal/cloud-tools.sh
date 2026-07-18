#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
source "$SCRIPT_DIR/../lib.sh"

# omawsl_install_terraform [apt_sources_file] [keyrings_dir]
# Idempotent (skips the repo-add once the sources file exists; apt-get
# install itself no-ops on an already-installed package) and
# failure-isolated: because this whole flow runs under set -e, a single
# unreachable third-party repo (HashiCorp's, here) must not cascade into
# failing every later step in the run (design spec §12). The `{ ... } ||`
# block catches any failure inside it without killing the script, and
# reports just this tool as failed rather than letting it propagate.
# Kept as its own function rather than sharing a parameterized helper with
# omawsl_install_azure_cli below - the two are similar but not identical,
# and a shared helper would need as many parameters as it'd save lines.
#
# Two implementation notes, found while making this pass its own tests:
# 1. The repo-add steps are chained with explicit `&&`, not bare `;`.
#    Bash disables -e checking for *every* command inside a compound
#    command that sits on the left of `||` (not just the last one), so a
#    `{ cmd1; cmd2; } || ok=0` body would keep running cmd2 even after
#    cmd1 fails - the "isolate the failure" test only passes because we
#    explicitly stop the chain with `&&` instead of relying on -e here.
# 2. The apt-source line is written via `sudo tee ... <<< "..."` (a
#    here-string) rather than `echo "..." | sudo tee ...` (a live pipe).
#    Under bats stubs, `sudo` is a plain function that returns without
#    reading stdin, so a live pipe's writer can get SIGPIPE (exit 141)
#    once the reader has already exited - a here-string avoids the pipe
#    (and the race) entirely while producing the identical `sudo tee ...`
#    invocation the tests assert on.
omawsl_install_terraform() {
  local apt_sources_file="${1:-${OMAWSL_TERRAFORM_APT_SOURCES_FILE:-/etc/apt/sources.list.d/hashicorp.list}}"
  local keyrings_dir="${2:-${OMAWSL_TERRAFORM_APT_KEYRINGS_DIR:-/etc/apt/keyrings}}"

  if command -v terraform &>/dev/null; then
    return 0
  fi

  local ok=1
  {
    if [[ ! -f "$apt_sources_file" ]]; then
      sudo install -m 0755 -d "$keyrings_dir" &&
      curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --yes --dearmor -o "$keyrings_dir/hashicorp.gpg" &&
      sudo tee "$apt_sources_file" >/dev/null <<< "deb [arch=$(dpkg --print-architecture) signed-by=$keyrings_dir/hashicorp.gpg] https://apt.releases.hashicorp.com $(. /etc/os-release && echo "$VERSION_CODENAME") main" &&
      sudo apt-get update -qq
    fi &&
    sudo apt-get install -y terraform
  } || ok=0

  if [[ "$ok" -eq 0 ]]; then
    # A partially-written or now-broken apt source left in place would
    # poison every LATER apt-get call in this run (and any future run) -
    # confirmed on a real WSL2 run where a failed Azure CLI repo-add
    # (Microsoft's repo lacking a Release file for that Ubuntu codename)
    # left /etc/apt/sources.list.d/azure-cli.list behind, which then made
    # libraries.sh's own unrelated `apt-get update` fail and abort the
    # entire install.sh run under set -e. Removing it here means the next
    # apt-get update (this run or a re-run) doesn't see a broken repo at
    # all, and a future call to this function retries the repo-add fresh
    # instead of staying permanently broken.
    sudo rm -f "$apt_sources_file"
    echo "omawsl: Terraform install failed (repo unreachable?) - skipping, continuing with the rest of the run."
  fi
}

# omawsl_cloud_tools
# Reads OMAWSL_LANGUAGES (Terraform lives in the same picker as the 8
# languages - design spec §6) and installs it if selected. Cloud provider
# CLIs (Azure/AWS/GCP) live in their own OMAWSL_CLOUD_CLIS-driven picker -
# see install/terminal/cloud-clis.sh.
omawsl_cloud_tools() {
  local languages="${OMAWSL_LANGUAGES:-}"

  if omawsl_list_has "$languages" "Terraform"; then
    omawsl_install_terraform
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_cloud_tools
fi
