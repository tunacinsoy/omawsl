#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
source "$SCRIPT_DIR/../lib.sh"

# omawsl_install_azure_cli [apt_sources_file] [keyrings_dir]
# Moved verbatim from install/terminal/cloud-tools.sh - Azure CLI now lives
# in its own OMAWSL_CLOUD_CLIS-driven picker, alongside AWS CLI and GCP CLI
# (design spec §3), not mixed in with the 8 programming languages.
omawsl_install_azure_cli() {
  local apt_sources_file="${1:-${OMAWSL_AZURE_CLI_APT_SOURCES_FILE:-/etc/apt/sources.list.d/azure-cli.list}}"
  local keyrings_dir="${2:-${OMAWSL_AZURE_CLI_APT_KEYRINGS_DIR:-/etc/apt/keyrings}}"

  if command -v az &>/dev/null; then
    return 0
  fi

  local ok=1
  {
    if [[ ! -f "$apt_sources_file" ]]; then
      local codename
      codename="$(. /etc/os-release && echo "$VERSION_CODENAME")"
      # Microsoft's azure-cli apt repo lags behind new Ubuntu releases - fall
      # back to "jammy" (the same default Microsoft's own installer uses)
      # when the detected codename isn't published yet.
      curl -fsSL -o /dev/null "https://packages.microsoft.com/repos/azure-cli/dists/$codename/Release" || codename="jammy"
      sudo install -m 0755 -d "$keyrings_dir" &&
      curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | sudo gpg --yes --dearmor -o "$keyrings_dir/microsoft.gpg" &&
      sudo tee "$apt_sources_file" >/dev/null <<< "deb [arch=$(dpkg --print-architecture) signed-by=$keyrings_dir/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ $codename main" &&
      sudo apt-get update -qq
    fi &&
    sudo apt-get install -y azure-cli
  } || ok=0

  if [[ "$ok" -eq 0 ]]; then
    sudo rm -f "$apt_sources_file"
    echo "omawsl: Azure CLI install failed (repo unreachable?) - skipping, continuing with the rest of the run."
  fi
}

# omawsl_install_gcp_cli [apt_sources_file] [keyrings_dir]
# Same idempotent + failure-isolated shape as omawsl_install_azure_cli, for
# Google's apt repo instead of Microsoft's. Simpler than Azure CLI's: Google's
# repo isn't pinned to a Ubuntu codename (a single "cloud-sdk" suite covers
# every release), so there's no jammy-style fallback needed.
omawsl_install_gcp_cli() {
  local apt_sources_file="${1:-${OMAWSL_GCP_CLI_APT_SOURCES_FILE:-/etc/apt/sources.list.d/google-cloud-sdk.list}}"
  local keyrings_dir="${2:-${OMAWSL_GCP_CLI_APT_KEYRINGS_DIR:-/etc/apt/keyrings}}"

  if command -v gcloud &>/dev/null; then
    return 0
  fi

  local ok=1
  {
    if [[ ! -f "$apt_sources_file" ]]; then
      sudo install -m 0755 -d "$keyrings_dir" &&
      curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --yes --dearmor -o "$keyrings_dir/google.gpg" &&
      sudo tee "$apt_sources_file" >/dev/null <<< "deb [signed-by=$keyrings_dir/google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" &&
      sudo apt-get update -qq
    fi &&
    sudo apt-get install -y google-cloud-cli
  } || ok=0

  if [[ "$ok" -eq 0 ]]; then
    sudo rm -f "$apt_sources_file"
    echo "omawsl: GCP CLI install failed (repo unreachable?) - skipping, continuing with the rest of the run."
  fi
}

# omawsl_aws_cli_arch
# Maps dpkg's architecture name to the naming AWS's own installer zip uses -
# reuses the same `dpkg --print-architecture` check the apt-based installers
# above already rely on, rather than introducing new arch-detection
# machinery.
omawsl_aws_cli_arch() {
  case "$(dpkg --print-architecture)" in
    arm64) echo "aarch64" ;;
    *) echo "x86_64" ;;
  esac
}

# omawsl_aws_cli_install_steps
# The actual install commands, no guard - called both by
# omawsl_install_aws_cli below (guarded) and by bin/omawsl-sub/orphan-tools.sh's
# own update-apply phase (guard bypassed), since AWS CLI has no apt/mise
# native updater of its own (design spec §8). `--update` is always passed:
# it's required to re-run the installer over an already-installed AWS CLI
# (the update path's use case), and is also accepted harmlessly on a fresh
# install (this function's own normal use case via the guarded wrapper).
omawsl_aws_cli_install_steps() {
  local tmp_dir; tmp_dir="$(mktemp -d)"
  local arch; arch="$(omawsl_aws_cli_arch)"
  local ok=1
  {
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-$arch.zip" -o "$tmp_dir/awscliv2.zip" &&
    unzip -q "$tmp_dir/awscliv2.zip" -d "$tmp_dir" &&
    sudo "$tmp_dir/aws/install" --update
  } || ok=0
  rm -rf "$tmp_dir"

  if [[ "$ok" -eq 0 ]]; then
    echo "omawsl: AWS CLI install failed (download unreachable?) - skipping, continuing with the rest of the run."
  fi
}

# omawsl_install_aws_cli
# Guarded entry point - what omawsl_cloud_clis (and bin/omawsl-sub/install.sh)
# call. Idempotent via a command -v guard, since the AWS installer script
# needs an explicit --update flag to touch an already-installed AWS CLI.
omawsl_install_aws_cli() {
  if command -v aws &>/dev/null; then
    return 0
  fi

  omawsl_aws_cli_install_steps
}

# omawsl_cloud_clis
# Reads OMAWSL_CLOUD_CLIS (Azure CLI/AWS CLI/GCP CLI live in their own picker,
# separate from the 8 languages/Terraform - design spec §3/§4) and installs
# each selected tool. Nothing pre-selected by default; selecting none is a
# valid no-op. Each install function already swallows its own failure
# internally and always returns 0, so no extra isolation logic is needed here
# - matches install/terminal/cloud-tools.sh's omawsl_cloud_tools shape.
omawsl_cloud_clis() {
  local cloud_clis="${OMAWSL_CLOUD_CLIS:-}"

  if omawsl_list_has "$cloud_clis" "Azure CLI"; then
    omawsl_install_azure_cli
  fi

  if omawsl_list_has "$cloud_clis" "AWS CLI"; then
    omawsl_install_aws_cli
  fi

  if omawsl_list_has "$cloud_clis" "GCP CLI"; then
    omawsl_install_gcp_cli
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_cloud_clis
fi
