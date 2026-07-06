#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
source "$SCRIPT_DIR/../lib.sh"

omawsl_default_full_name() {
  getent passwd "$(whoami)" 2>/dev/null | cut -d: -f5 | cut -d, -f1
}

# omawsl_identification
# Always prompts for full name and email at first run (not conditional on
# whether git config is already set) - matching Omakub's real
# install/identification.sh behavior, pre-filled from getent passwd and any
# existing git config as defaults.
omawsl_identification() {
  local default_name default_email
  default_name="$(omawsl_default_full_name)"
  default_email="$(git config --global user.email 2>/dev/null || true)"

  OMAWSL_USER_NAME="$(gum input --header "Full name (for git commits)" --value "$default_name")"
  OMAWSL_USER_EMAIL="$(gum input --header "Email (for git commits)" --value "$default_email")"

  export OMAWSL_USER_NAME OMAWSL_USER_EMAIL

  git config --global user.name "$OMAWSL_USER_NAME"
  git config --global user.email "$OMAWSL_USER_EMAIL"

  omawsl_save_choice OMAWSL_USER_NAME "$OMAWSL_USER_NAME"
  omawsl_save_choice OMAWSL_USER_EMAIL "$OMAWSL_USER_EMAIL"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_identification
fi
