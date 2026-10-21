#!/usr/bin/env bash
set -euo pipefail

# HashiCorp signs its apt repo with a new key since 2026-09-09
# (D55C0D1AC78A8D8126CB631CFC9CA96ACA026560), and omawsl_install_terraform
# (install/terminal/cloud-tools.sh) only downloads the key when it first adds
# the repo. Machines set up before then keep the old key, so every
# `apt-get update` warns NO_PUBKEY FC9CA96ACA026560 and skips HashiCorp's
# repo - Terraform stops getting updates (issue #54). This downloads the key
# again into whichever keyring the apt source names (omawsl's own, or the one
# HashiCorp's setup steps use), with the same command the install uses. No-ops
# when the repo isn't set up or names no keyring. A failed download exits
# non-zero, so migrate.sh retries it on the next run.
sources_file="${OMAWSL_TERRAFORM_APT_SOURCES_FILE:-/etc/apt/sources.list.d/hashicorp.list}"
[[ -f "$sources_file" ]] || exit 0

keyring="$(grep -m1 -o 'signed-by=[^] ]*' "$sources_file" | cut -d= -f2 || true)"
[[ -n "$keyring" ]] || exit 0

curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --yes --dearmor -o "$keyring"
