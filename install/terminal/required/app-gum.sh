#!/usr/bin/env bash
set -euo pipefail

# Idempotent: apt install no-ops if gum is already at the candidate version.
# Available directly from Ubuntu's own universe repo as of 26.04 - no
# third-party repo/keyring needed (verified via `apt-cache policy gum`
# against a real Ubuntu 26.04 WSL2 instance: candidate 0.17.0-1 from
# archive.ubuntu.com/ubuntu resolute/universe).
omawsl_install_gum() {
  sudo apt-get update -qq
  sudo apt-get install -y gum
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_install_gum
fi
