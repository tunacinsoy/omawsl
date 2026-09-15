#!/usr/bin/env bash
# practice/03-languages-and-cloud-tools/dev-environment.sh
#
# Rebuild a combined version of mise.sh + select-dev-language.sh +
# cloud-tools.sh, from scratch. See
# docs/curriculum/03-languages-and-cloud-tools.md, section 3 (Exercise).
#
# This file is meant to be *executed* (bash dev-environment.sh), the same
# way every terminal/*.sh script in the real project is - it needs the
# same guard those scripts use at the bottom
# (`if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then ...; fi`) so that running
# it directly performs the steps below, in order, but sourcing it (the
# way a test might, to reach individual pieces) does not auto-run
# anything.
#
# Reads:
#   OMAWSL_LANGUAGES - comma-delimited, may be unset or empty. Whole-token
#     membership only (an item that's a substring of a different, longer
#     item in the list must not count as present) - may contain any subset
#     of exactly these ten labels:
#       "Node.js", "Go", "PHP", "Python", "Elixir", "Rust", "Java",
#       "Ruby on Rails", "Terraform", "Azure CLI"
#
# Step 1 - bootstrap mise:
#   Export $HOME/.local/bin onto PATH for the CURRENT process, BEFORE
#   checking whether `mise` is already reachable - not after. (Get this
#   ordering backwards and a fresh install of mise, done moments earlier
#   in $HOME/.local/bin by a previous step, becomes permanently invisible
#   to every later "is mise already there?" check in this same run - see
#   the lesson's "Bug 1" for the real-world version of this exact mistake,
#   in a different file.)
#   If `mise` is now reachable (it either already was, or just became
#   reachable because of the export above), do nothing further for this
#   step. Otherwise, install it:
#     curl -fsSL https://mise.run | sh
#
# Step 2 - language dispatch (reads OMAWSL_LANGUAGES):
#   For each of these seven labels present, run exactly one command:
#     "Node.js" -> mise use --global node@latest
#     "Go"      -> mise use --global go@latest
#     "PHP"     -> mise use --global php@latest
#     "Python"  -> mise use --global python@latest
#     "Elixir"  -> mise use --global elixir@latest
#     "Rust"    -> mise use --global rust@latest
#     "Java"    -> mise use --global java@latest
#   "Ruby on Rails" is the one exception - it runs TWO commands:
#     mise use --global ruby@latest
#     mise exec ruby@latest -- gem install rails --no-document
#   (Not a bare `gem install rails` - see the lesson's Walkthrough for why
#   that would fail here.)
#   "Terraform" and "Azure CLI" are NOT languages - they belong to step 3
#   below and must NOT trigger any `mise use`/`mise exec` call here.
#   Selecting nothing (OMAWSL_LANGUAGES unset or empty) must run no `mise
#   use`/`mise exec` calls at all, and must not be an error.
#
# Step 3 - cloud tools (also reads OMAWSL_LANGUAGES, same variable):
#   For "Terraform" and/or "Azure CLI", if present, install each selected
#   one from its own third-party apt repository. Both follow the exact
#   same shape:
#
#     - apt_sources_file defaults to:
#         Terraform:  /etc/apt/sources.list.d/hashicorp.list
#         Azure CLI:  /etc/apt/sources.list.d/azure-cli.list
#       but must be overridable via an environment variable:
#         Terraform:  OMAWSL_TERRAFORM_APT_SOURCES_FILE
#         Azure CLI:  OMAWSL_AZURE_CLI_APT_SOURCES_FILE
#     - keyrings_dir defaults to /etc/apt/keyrings for both, overridable
#       via:
#         Terraform:  OMAWSL_TERRAFORM_APT_KEYRINGS_DIR
#         Azure CLI:  OMAWSL_AZURE_CLI_APT_KEYRINGS_DIR
#
#     - If the tool's own command (`terraform` / `az`) is already
#       reachable, skip entirely - do nothing else for that tool.
#
#     - If apt_sources_file does NOT already exist, add the repo:
#         sudo install -m 0755 -d <keyrings_dir>
#         curl -fsSL <key_url> | sudo gpg --yes --dearmor -o <keyrings_dir>/<name>.gpg
#         (write the apt source line into apt_sources_file via `sudo tee`)
#         sudo apt-get update -qq
#       Terraform: key_url = https://apt.releases.hashicorp.com/gpg,
#         keyring file name "hashicorp.gpg", repo url
#         https://apt.releases.hashicorp.com
#       Azure CLI: key_url = https://packages.microsoft.com/keys/microsoft.asc,
#         keyring file name "microsoft.gpg", repo url
#         https://packages.microsoft.com/repos/azure-cli/
#       IMPORTANT: chain these steps with `&&`, not `;` - see the lesson's
#       Walkthrough section on cloud-tools.sh for why a `;`-separated chain
#       silently keeps running later steps after an earlier one in it has
#       already failed.
#       If apt_sources_file DOES already exist, skip this whole repo-add
#       block (idempotent re-run).
#
#     - Either way, then attempt: sudo apt-get install -y <package>
#         Terraform: package = terraform
#         Azure CLI: package = azure-cli
#
#     - If ANY step above (repo-add or the final install) fails: do NOT
#       let that abort the rest of this script (remember
#       `set -euo pipefail` is active). Instead:
#         1. Remove apt_sources_file if it exists (`sudo rm -f
#            <apt_sources_file>`) - a broken/partial repo listing must
#            never be left behind to poison a LATER apt-get update, in
#            this run or a future one.
#         2. Print a message that mentions the tool by name (e.g.
#            "Terraform" or "Azure CLI") and the word "failed".
#         3. Return/continue successfully - a failure installing one
#            cloud tool must never prevent the OTHER selected cloud tool
#            from still being attempted.
#
# TODO: implement steps 1-3 and the guarded entry point described above.

set -euo pipefail
