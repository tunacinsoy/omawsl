#!/usr/bin/env bash
set -euo pipefail

# omawsl_install_gum [apt_sources_file] [keyrings_dir]
# gum only ships in Ubuntu's own universe repo as of 26.04 (verified via
# `apt-cache policy gum` against a real Ubuntu 26.04 WSL2 instance); on
# 24.04/25.x `apt-get install gum` 404s with "Unable to locate package
# gum". Charm's own apt repo (https://repo.charm.sh/apt/) carries gum for
# every Ubuntu version - including 26.04, where it now shadows the distro
# package - so we add it unconditionally instead of branching on
# VERSION_ID. Idempotent: the repo-add + GPG-key steps only run once
# (guarded by the sources file not existing yet), matching the pattern in
# install/terminal/docker.sh; `apt-get install` itself no-ops if gum is
# already at the candidate version.
omawsl_install_gum() {
  local apt_sources_file="${1:-/etc/apt/sources.list.d/charm.list}"
  local keyrings_dir="${2:-/etc/apt/keyrings}"

  if [[ ! -f "$apt_sources_file" ]]; then
    sudo install -m 0755 -d "$keyrings_dir"
    curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --yes --dearmor -o "$keyrings_dir/charm.gpg"
    echo "deb [signed-by=$keyrings_dir/charm.gpg] https://repo.charm.sh/apt/ * *" \
      | sudo tee "$apt_sources_file" >/dev/null
  fi

  sudo apt-get update -qq
  sudo apt-get install -y gum
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_install_gum
fi
