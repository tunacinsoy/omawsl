#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

# TODO(Lesson 2): implement both of the following (described in the
# lesson's Exercise section):
#
#   omawsl_ensure_container <name> <docker run args...>
#   omawsl_install_storage

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_install_storage
fi
