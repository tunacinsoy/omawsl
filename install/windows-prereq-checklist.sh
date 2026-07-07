#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

# omawsl_windows_checklist_items
# Prints zero or more lines, each describing one pending Windows-side
# prerequisite relevant to what was actually selected. Phase 2 adds the
# first real item: Docker Desktop, shown only if that mode was chosen and
# `docker` isn't already reachable (design spec §6, §9). Later phases
# (VS Code/Cursor in Phase 4) extend this function further rather than
# restructuring it.
omawsl_windows_checklist_items() {
  if [[ "${OMAWSL_DOCKER_MODE:-}" == "Docker Desktop for Windows" ]] && ! omawsl_docker_reachable; then
    echo "  - Docker Desktop - docs/windows-setup.md#docker-desktop (install it, enable WSL integration for this distro, verify 'docker' is reachable)"
  fi
}

omawsl_windows_prereq_checklist() {
  local items
  items="$(omawsl_windows_checklist_items)"

  if [[ -z "$items" ]]; then
    return 0
  fi

  echo "Before continuing, here's what the Windows side needs for what you picked:"
  echo
  echo "$items"
  echo
  echo "We RECOMMEND stopping here: go complete the steps above on the Windows side first,"
  echo "then run this script again. Nothing below strictly requires it - the WSL install will"
  echo "still run fine either way, safely skipping/deferring anything Windows-side that isn't"
  echo "ready yet rather than failing - but doing it in this order avoids extra back-and-forth"
  echo "later, and you won't have to remember to come back to it."
  echo

  local reply=""
  read -r -p "Continue installing the WSL side now anyway? [y/N] " reply || true
  if [[ ! "$reply" =~ ^[Yy]$ ]]; then
    echo "Exiting - nothing has been installed yet. Re-run install.sh whenever you're ready."
    exit 0
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_windows_prereq_checklist
fi
